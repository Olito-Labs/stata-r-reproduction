#!/usr/bin/env python3
"""Run the shipped synthetic example; never arbitrary customer do-files."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import shutil
import subprocess

from compare_outputs import FILES, compare, read_bundle, sha256

ROOT = Path(__file__).resolve().parents[1]


def executable(name):
    found = shutil.which(str(name))
    if not found:
        raise ValueError(f"Executable unavailable: {name}")
    return str(Path(found).resolve())


def stata_command(binary, system):
    flags = {"Darwin": "-e", "Linux": "-b", "Windows": "/e"}
    if system not in flags:
        raise ValueError("Unsupported Stata batch platform")
    return [binary, flags[system], "do", "wrapper.do"]


def wrapper_source():
    # Fixed relative paths avoid quoting/macro expansion of user-supplied paths.
    return '''version 17
set more off
capture noisily do "original.do" "input.csv" "../stata"
local run_rc = _rc
tempname stamp
file open `stamp' using "exit-status.txt", write text
file write `stamp' "`run_rc'" _n
file close `stamp'
exit `run_rc', clear
'''


def check_stata_completion(work):
    marker = work / "exit-status.txt"
    if not marker.is_file() or marker.read_text().strip() != "0":
        raise ValueError("Stata did not confirm successful do-file completion; inspect its log")


def execute(command, cwd, logfile, timeout):
    with logfile.open("x", encoding="utf-8") as log:
        subprocess.run(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=timeout, shell=False)


def seal(directory, engine, input_hash, sources, command):
    manifest = {
        "schema_version": 1, "engine": engine, "status": "success",
        "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
        "input_sha256": input_hash, "source_sha256": sources,
        "outputs_sha256": {name: sha256(directory / name) for name in FILES},
        "command": command, "platform": platform.platform(),
    }
    with (directory / "manifest.json").open("x") as f:
        json.dump(manifest, f, indent=2)
    read_bundle(directory, engine)


def run(out, r_only=False, stata=None, rscript="Rscript", timeout=120, atol="1e-10", rtol="1e-8"):
    out = Path(out).resolve()
    # Never reuse a directory, even for a previous failed/partial run.
    if out.exists():
        raise FileExistsError("Output directory already exists; choose a new run directory")
    if r_only == bool(stata):
        raise ValueError("Choose exactly one of --r-only or --stata PATH")
    r_binary = executable(rscript)
    stata_binary = executable(stata) if stata else None
    input_path = ROOT / "assets/demo/input.csv"
    input_hash = sha256(input_path)
    source_paths = [ROOT / "scripts/translate_demo.R", ROOT / "scripts/stata_semantics.R", ROOT / "assets/demo/original.do"]
    source_hashes = {p.relative_to(ROOT).as_posix(): sha256(p) for p in source_paths}
    out.mkdir(parents=True)
    command = [r_binary, "--vanilla", str(source_paths[0]), str(input_path), str(out / "r")]
    execute(command, ROOT, out / "r.log", timeout)
    seal(out / "r", "r", input_hash, {k: v for k, v in source_hashes.items() if k.endswith(".R")}, command)
    if stata_binary:
        work = out / "stata-work"
        work.mkdir()
        (out / "stata").mkdir()
        shutil.copyfile(input_path, work / "input.csv")
        shutil.copyfile(source_paths[2], work / "original.do")
        (work / "wrapper.do").write_text(wrapper_source())
        command = stata_command(stata_binary, platform.system())
        execute(command, work, out / "stata-process.log", timeout)
        check_stata_completion(work)
        if sha256(work / "input.csv") != input_hash or sha256(work / "original.do") != source_hashes["assets/demo/original.do"]:
            raise ValueError("Stata run changed its input or source")
        seal(out / "stata", "stata", input_hash,
             {"assets/demo/original.do": source_hashes["assets/demo/original.do"], "wrapper.do": sha256(work / "wrapper.do")}, command)
    if sha256(input_path) != input_hash or any(sha256(p) != source_hashes[p.relative_to(ROOT).as_posix()] for p in source_paths):
        raise ValueError("Source or input changed during execution")
    report = compare(out / "stata", out / "r", atol=atol, rtol=rtol)
    with (out / "comparison.json").open("x") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report, indent=2))
    if r_only:
        print("R ran successfully. No Stata/R equivalence claim is available.")
        return 0
    return {"MATCHED_OUTPUTS": 0, "MISMATCH": 1}.get(report["status"], 2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--r-only", action="store_true")
    mode.add_argument("--stata", help="Path to an installed, licensed Stata executable")
    parser.add_argument("--rscript", default="Rscript")
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--atol", default="1e-10")
    parser.add_argument("--rtol", default="1e-8")
    args = parser.parse_args()
    try:
        return run(**vars(args))
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(json.dumps({"status": "RUN_FAILED", "reason": str(exc)}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
