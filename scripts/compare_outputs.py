#!/usr/bin/env python3
"""Compare demo-v1 evidence bundles. No third-party Python dependencies."""
import argparse
import csv
from decimal import Decimal, InvalidOperation, localcontext
import hashlib
import json
from pathlib import Path
import re

SCHEMAS = {
    "checkpoint.csv": (("id",), ("panel", "month", "x", "z", "y", "ma6", "sample")),
    "coefficients.csv": (("model", "term"), ("estimate", "se", "statistic", "p", "ci_low", "ci_high")),
    "vcov.csv": (("model", "term_i", "term_j"), ("value",)),
    "predictions.csv": (("id",), ("fitted", "residual")),
    "statistics.csv": (("model", "name"), ("value",)),
}
FILES = tuple(SCHEMAS) + ("runtime.csv",)
MODELS = {"ols", "hc1", "cluster"}
TERMS = {"_cons", "x", "z", "ma6"}
STATISTICS = {"N", "rank", "df_r", "N_clust"}
HEX = re.compile(r"[a-f0-9]{64}\Z")


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def number(value):
    value = value.strip()
    if value in {"", ".", "NA"}:
        return "NA"
    if re.fullmatch(r"\.[a-z]", value):
        return value
    try:
        value = Decimal(value)
    except InvalidOperation as exc:
        raise ValueError("invalid numeric cell") from exc
    if value.is_nan():
        return "NaN"
    if value.is_infinite():
        return "-Inf" if value.is_signed() else "Inf"
    return value


def numeric_equal(left, right, atol, rtol):
    left, right = number(left), number(right)
    if not isinstance(left, Decimal) or not isinstance(right, Decimal):
        return left == right
    with localcontext() as context:
        context.prec = 80
        return abs(left - right) <= atol + rtol * abs(left)


def tolerance(value):
    result = Decimal(str(value))
    if not result.is_finite() or result < 0:
        raise ValueError("tolerances must be nonnegative finite numbers")
    return result


def table(path, keys, values):
    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames or []
        if len(headers) != len(set(headers)) or set(headers) != set(keys + values):
            raise ValueError(f"{path.name}: unexpected or duplicate columns")
        rows = {}
        for row in reader:
            if None in row or any(v is None for v in row.values()):
                raise ValueError(f"{path.name}: malformed row")
            row = {k: v.strip() for k, v in row.items()}
            key = tuple(row[k] for k in keys)
            if any(not k for k in key) or key in rows:
                raise ValueError(f"{path.name}: empty or duplicate key")
            rows[key] = row
        if not rows:
            raise ValueError(f"{path.name}: empty table")
        return rows


def read_bundle(path, engine):
    manifest = json.loads((path / "manifest.json").read_text())
    if not isinstance(manifest, dict) or manifest.get("schema_version") != 1:
        raise ValueError("unsupported manifest")
    if manifest.get("engine") != engine or manifest.get("status") != "success":
        raise ValueError("incorrect engine or unsuccessful run")
    if not HEX.fullmatch(str(manifest.get("input_sha256", ""))):
        raise ValueError("missing input hash")
    sources = manifest.get("source_sha256")
    if not isinstance(sources, dict) or not sources or any(not HEX.fullmatch(str(v)) for v in sources.values()):
        raise ValueError("missing source hashes")
    if not isinstance(manifest.get("outputs_sha256"), dict):
        raise ValueError("missing output hashes")
    for name in FILES:
        if manifest["outputs_sha256"].get(name) != sha256(path / name):
            raise ValueError(f"{name}: absent or stale output hash")
    runtime = table(path / "runtime.csv", ("key",), ("value",))
    required_runtime = ("R_version", "sandwich_version") if engine == "r" else (
        "engine", "stata_version", "stata_edition", "stata_born_date", "status")
    if any(not runtime.get((key,), {}).get("value") for key in required_runtime):
        raise ValueError("actual runtime provenance missing")
    if engine == "stata" and (runtime[("engine",)]["value"] != "Stata" or runtime[("status",)]["value"] != "completed"):
        raise ValueError("Stata runtime contradicts successful reference manifest")
    tables = {name: table(path / name, *schema) for name, schema in SCHEMAS.items()}
    validate_shape(tables)
    return manifest, tables


def validate_shape(tables):
    expected = {
        "coefficients.csv": {(m, t) for m in MODELS for t in TERMS},
        "vcov.csv": {(m, t, u) for m in MODELS for t in TERMS for u in TERMS},
        "statistics.csv": {(m, s) for m in MODELS for s in STATISTICS},
    }
    for name, keys in expected.items():
        if set(tables[name]) != keys:
            raise ValueError(f"{name}: incomplete or unexpected demo-v1 keys")
    sample = set()
    ids = set()
    panel_months = set()
    clusters = set()
    for key, row in tables["checkpoint.csv"].items():
        for name in ("id", "panel", "month", "sample"):
            value = number(row[name])
            if not isinstance(value, Decimal) or value != value.to_integral_value():
                raise ValueError(f"checkpoint.csv: {name} must be a finite integer")
        numeric_id = number(row["id"])
        panel_month = (number(row["panel"]), number(row["month"]))
        if numeric_id in ids or panel_month in panel_months:
            raise ValueError("duplicate numeric ID or panel-month key")
        ids.add(numeric_id)
        panel_months.add(panel_month)
        values = [number(row[name]) for name in ("x", "z", "y", "ma6")]
        if any(not isinstance(v, Decimal) and v != "NA" for v in values):
            raise ValueError("demo measurements must be finite or ordinary missing")
        if row["sample"] not in {"0", "1"}:
            raise ValueError("sample must be 0 or 1")
        if (row["sample"] == "1") != all(isinstance(v, Decimal) for v in values):
            raise ValueError("sample disagrees with complete model measurements")
        if row["sample"] == "1":
            sample.add(key)
            clusters.add(number(row["panel"]))
    if set(tables["predictions.csv"]) != sample:
        raise ValueError("prediction IDs do not equal estimation-sample IDs")
    for (model, name), row in tables["statistics.csv"].items():
        value = number(row["value"])
        if not isinstance(value, Decimal) or value != value.to_integral_value():
            raise ValueError("statistics must be finite integers")
        if name == "N" and value != len(sample):
            raise ValueError("N disagrees with estimation sample")
    if len(sample) <= len(TERMS) or len(clusters) < 2:
        raise ValueError("insufficient observations or clusters")
    for model in MODELS:
        expected_stats = {"rank": len(TERMS), "df_r": len(clusters) - 1 if model == "cluster" else len(sample) - len(TERMS),
                          "N_clust": len(clusters) if model == "cluster" else 0}
        for name, expected_value in expected_stats.items():
            if number(tables["statistics.csv"][(model, name)]["value"]) != expected_value:
                raise ValueError("rank, degrees of freedom or cluster count violates demo contract")
    for filename in ("coefficients.csv", "vcov.csv", "predictions.csv"):
        for row in tables[filename].values():
            for column in SCHEMAS[filename][1]:
                if not isinstance(number(row[column]), Decimal):
                    raise ValueError(f"{filename}: model outputs must be finite")
            if filename == "coefficients.csv":
                if number(row["se"]) <= 0 or not 0 <= number(row["p"]) <= 1 or number(row["ci_low"]) > number(row["ci_high"]):
                    raise ValueError("invalid standard error, probability or confidence interval")


def compare(reference, actual, atol="1e-10", rtol="1e-8"):
    reference, actual = Path(reference), Path(actual)
    if not reference.is_dir():
        return {"status": "REFERENCE_UNAVAILABLE", "reason": "Stata reference directory is absent"}
    try:
        atol, rtol = tolerance(atol), tolerance(rtol)
        ref_manifest, ref = read_bundle(reference, "stata")
        r_manifest, result = read_bundle(actual, "r")
        if ref_manifest["input_sha256"] != r_manifest["input_sha256"]:
            raise ValueError("input hashes differ")
        count = 0
        examples = []
        maximum = Decimal(0)
        for name, (keys, values) in SCHEMAS.items():
            if set(ref[name]) != set(result[name]):
                count += len(set(ref[name]) ^ set(result[name]))
                if len(examples) < 20:
                    examples.append({"file": name, "reason": "row keys differ"})
            for key in ref[name].keys() & result[name].keys():
                for column in values:
                    left, right = ref[name][key][column], result[name][key][column]
                    exact = name == "statistics.csv" or (name == "checkpoint.csv" and column in {"panel", "month", "sample"})
                    equal = numeric_equal(left, right, Decimal(0) if exact else atol, Decimal(0) if exact else rtol)
                    a, b = number(left), number(right)
                    if isinstance(a, Decimal) and isinstance(b, Decimal):
                        maximum = max(maximum, abs(a - b))
                    if not equal:
                        count += 1
                        if len(examples) < 20:
                            examples.append({"file": name, "key": list(key), "column": column})
        return {"status": "MISMATCH" if count else "MATCHED_OUTPUTS", "mismatches": count,
                "atol": str(atol), "rtol": str(rtol), "max_absolute_difference": str(maximum),
                "examples": examples,
                "scope": "demo-v1 outputs only; not proof of model validity or provenance authenticity"}
    except (OSError, ValueError, TypeError, InvalidOperation, KeyError) as exc:
        return {"status": "INVALID_EVIDENCE", "reason": str(exc)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("actual", type=Path)
    parser.add_argument("--atol", default="1e-10")
    parser.add_argument("--rtol", default="1e-8")
    args = parser.parse_args()
    report = compare(args.reference, args.actual, args.atol, args.rtol)
    print(json.dumps(report, indent=2))
    return {"MATCHED_OUTPUTS": 0, "MISMATCH": 1}.get(report["status"], 2)


if __name__ == "__main__":
    raise SystemExit(main())
