# Stata-to-R reproduction

A reusable AI skill and runnable example for translating Stata analyses into R
without silently changing their meaning. Built by [Olito Labs](https://olitolabs.com).

**Preview release:** R and Python tests run automatically. The Stata exporter and
batch integration have been reviewed against official documentation but have not
yet been executed in a licensed Stata runtime. This is not a validated universal
converter. No cross-language equivalence claim is made by this release.

## Start here

- **Use an AI assistant:** give it [SKILL.md](SKILL.md) and the referenced files,
  or copy this folder into your agent's documented skill directory. Ask it to
  reproduce a small permitted analysis and report what it actually verified.
- **Use R/RStudio without an agent:** run the synthetic example below.
- **Use an approved browser-only assistant:** attach the instruction files and
  synthetic example, or paste their text. Runtime access still requires local R
  and licensed Stata. An AI subscription does not supply a Stata license.
- **Download:** [GitHub releases](https://github.com/Olito-Labs/stata-r-reproduction/releases)
  contain a source ZIP. No account, hosted service, API key or MCP server is
  required to read the skill or run its scripts.

Example request:

> Use stata-r-reproduction. Explain this synthetic do-file, reproduce its
> six-month moving average in R, and verify each checkpoint. Keep the original
> unchanged. If Stata is unavailable, tell me exactly what remains unverified.

## What is included

| Component | Purpose |
| --- | --- |
| `SKILL.md` | Instructions for an assistant, including stopping and evidence rules |
| `references/` | Stata semantics, R package choices, verification contract and sources |
| `assets/demo/input.csv` | Fully synthetic monthly panel with gaps and missing values |
| `assets/demo/original.do` | Stata reference exporter, using built-in commands only |
| `scripts/translate_demo.R` | R reproduction using base R and `sandwich` |
| `scripts/compare_outputs.py` | Exact-identity and full-precision numeric comparisons |
| `scripts/run_demo.py` | Isolated runs, hashes, logs and an explicit evidence result |
| `tests/` | Independent matrix oracles, semantic edge cases and comparator mutations |

No customer data, correspondence, transcripts or actual case work is included.

## Run the R-only example

Install Python 3.10+ and R 4.3+ using your approved process. From this folder,
install the small R dependency set once. This command downloads packages from
CRAN into a project-local library; scripts do not install packages automatically.

```sh
Rscript --vanilla -e 'dir.create(".r-library", showWarnings=FALSE); install.packages("sandwich", lib=".r-library", repos="https://cloud.r-project.org")'
python3 -m unittest discover -s tests -p 'test_*.py'
Rscript --vanilla tests/test_r.R
python3 scripts/run_demo.py --r-only --out runs/first-r-check
```

On Windows, use `python` if that is your Python command. In RStudio, you can
run the R tests with `source("tests/test_r.R")` from the repository root.
The R script also supports:

```r
source("scripts/translate_demo.R")
run_translation("assets/demo/input.csv", "runs/rstudio-check")
```

Choose a new output directory for every run. The runner refuses reuse. The direct
R script also refuses to replace existing output CSVs.

Expected R-only result: `REFERENCE_UNAVAILABLE`. Exit 0 in explicit `--r-only`
mode means only that R ran successfully. It does **not** mean Stata matched.

## Run both languages

Use an installed, licensed Stata 17+ executable. Stata is commercial software and
is not included. The batch adapter is provisional until a real Stata run is
recorded. Review the generated wrapper and `runs/.../stata-work/wrapper.log`.
Captured process stdout can be empty even when Stata writes a diagnostic log.

```sh
python3 scripts/run_demo.py --stata /path/to/stata-executable --out runs/first-comparison
```

For macOS GUI Stata, pass the actual executable inside the application bundle,
not the `.app` directory or a symlink. For example, an installed MP edition may
use `/Applications/Stata/StataMP.app/Contents/MacOS/StataMP`. A graphical login
may be necessary. Console Stata on macOS is not tested by this adapter.
Linux uses `-b`; macOS GUI uses `-e`; Windows uses `/e`.

The runner executes the shipped synthetic fixture only. It creates fresh output
directories, captures logs, checks Stata's do-file exit marker, records source and
input hashes, verifies output hashes, and compares results. It never contacts an
external model or uploads data. Local Stata/R startup configuration is not a
security sandbox; run in an environment you trust.

Recheck an existing pair:

```sh
python3 scripts/compare_outputs.py runs/first-comparison/stata runs/first-comparison/r
```

Comparator exit codes: **0** matched these outputs, **1** mismatch, **2** missing
reference or invalid evidence. See [verification](references/verification.md)
for the schema and limits of this evidence.

## Why these checks matter

Stata `x > 0` can include numeric missing values. R's `NA > 0` is unknown.
A six-row mean is not a six-month mean when months are absent. Matching regression
coefficients does not establish matching samples, covariance, tests or confidence
intervals. See [Stata semantics](references/stata-semantics.md) for official sources.

This example handles ordinary missing values, an unweighted full-rank linear
model and one cluster variable. It does not certify weighted models, fixed-effects
estimators, custom ado commands, IV, survey designs or nonlinear models. The small
four-cluster example is a software test, not recommended inferential practice.

## Reproducibility and contribution

[Validation status](VALIDATION.md) separates executed tests from pending checks.
Runtime CSVs and manifests record the versions actually used. A fresh CRAN install
can change versions; archive an approved project environment or use `renv` for a
real engagement. This preview does not include a complete environment lock.

Contributions should include a minimal **synthetic** counterexample and an
independent expected result. New claims of Stata equivalence need actual Stata
version/source/input evidence. Do not submit confidential logs, datasets or
research. Do not increase a tolerance merely to make a failing test pass.

MIT license for this project's original code and documentation. Stata and R names
identify their respective products. No affiliation or endorsement is implied.
