# Verification contract

## What this example checks

`demo-v1` is deliberately small: ordinary numeric missing values, integer monthly
panel keys, a current-plus-five-month mean, and `y ~ x + z + ma6` with an intercept.
`rank` means design rank, not rank of a clustered covariance matrix. Models are
named `ols`, `hc1`, `cluster`; terms are `_cons`, `x`, `z`, `ma6`.

| File | Identity | Values |
| --- | --- | --- |
| `checkpoint.csv` | id | panel, month, x, z, y, ma6, sample |
| `coefficients.csv` | model, term | estimate, se, statistic, p, ci_low, ci_high |
| `vcov.csv` | model, term_i, term_j | value |
| `predictions.csv` | id | fitted, residual, estimation rows only |
| `statistics.csv` | model, name | value; N, rank, df_r, N_clust |
| `runtime.csv` | key | value; actual runtime/package versions |

Tables must be nonempty and have the exact column set, unique keys and complete
model/term combinations. Prediction IDs must equal checkpoint sample IDs.
Each model's N must equal that sample size. Row order is irrelevant for keyed
comparison; sequence-sensitive computations still require explicit order checks
when adapting this approach to other analyses.
Model outputs must be finite; standard errors must be positive. Design rank,
degrees of freedom and cluster counts must satisfy the demo model contract.
The checker also requires actual engine-specific version fields, not merely a
Stata `version` compatibility setting.

Identifiers and integer fields are exact. Numeric cells use
`abs(R - Stata) <= atol + rtol * abs(Stata)` element by element. Defaults are
`atol=1e-10`, `rtol=1e-8`, chosen for this double-precision synthetic example.
They are not a universal econometric acceptance criterion. State domain-specific
tolerances before inspecting discrepancies. Do not use a global average error
that can hide one bad observation.

Ordinary missing numeric spellings `NA`, `.`, and an empty field normalize to one
missing category. Tagged `.a` through `.z`, NaN and signed infinity remain
different categories in the numeric comparator. This is not a `.dta` importer:
the shipped demo excludes extended missing tags and nonfinite measurements.
Metadata and category labels in a real `.dta` need their own exact checkpoints.

## Evidence and its limits

`run_demo.py` writes a `manifest.json` only after the relevant command succeeds.
It records engine, input hash, source hashes, command, platform, time and hashes
of all six CSVs. Stata additionally must write a zero do-file exit marker.
The comparator requires an engine=`stata` reference and an engine=`r` candidate,
successful manifests, matching input hashes and unchanged output hashes.

Hashes detect accidental changes after a run. They do not authenticate a person,
prove that a manifest is truthful, or certify untrusted results. Source hashes
are retained for audit, not compared across two languages. Use the runner in a
trusted environment, retain its logs and archived source revision, and investigate
any hand-edited manifest. A hand-labelled R output is not a Stata baseline.

Python tests contain invented fixture bundles to test comparison mechanics.
They are explicitly test data, not observed Stata results. No Stata golden outputs
are shipped in this preview.

## Adapting to a real analysis

1. Inventory source blocks, datasets, IDs, versions, command options and dependencies.
2. Preserve originals. Create an instrumented copy if exports are needed. Record
   its diff and establish that added exports do not change analysis state.
3. Export checkpoints after imports, filters, joins, derived variables and sample
   construction. Include missing reasons and labels where material.
4. Capture full `e(b)`, `e(V)` and `e(sample)` before a later command replaces them.
5. Extend the schema and tests for the actual model. Do not rename a different
   estimator to one of the demo's models to bypass validation.
6. Run source and translation on the same permitted inputs. Diagnose the first
   divergent checkpoint before interpreting final tables.
7. Preserve code, allowed inputs or hashes, logs, dependency lock, discrepancies,
   prompts when policy permits, and the evidence summary in approved storage.

Different source bugs can reproduce perfectly. Reproduction and substantive
critique are separate deliverables. Neither output matching nor a recorded prompt
history establishes scientific, causal, legal or discovery-related guarantees.

## Authoritative execution references

- [Stata Unix batch mode](https://www.stata.com/support/faqs/unix/batch-mode/)
- [Stata macOS batch mode](https://www.stata.com/support/faqs/mac/advanced-topics/)
- [Stata Windows batch mode](https://www.stata.com/support/faqs/windows/batch-mode/)
- [Stata stored results](https://www.stata.com/manuals/rstoredresults.pdf)
- [Stata version control](https://www.stata.com/manuals/pversion.pdf)
- [PyStata installation](https://www.stata.com/python/pystata19/install.html),
  an optional bridge requiring an installed Stata; not a dependency of this skill.
