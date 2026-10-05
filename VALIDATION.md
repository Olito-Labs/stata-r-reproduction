# Validation status

As of 2026-10-05. Preview release; **no licensed Stata execution yet**.

## Executed locally

Environment: macOS arm64, Python 3.14.7, R 4.6.1, `sandwich` 3.1.3.

| Check | Result |
| --- | --- |
| Python unit tests | 34 passed |
| R semantic and numerical checks | 65 passed |
| R interactive `source()` workflow | 65 checks passed; actual output generated |
| End-to-end R-only runner | Successful execution; `REFERENCE_UNAVAILABLE` |
| Skill structure validator | Passed |
| Independent forward test | Completed; demonstrated defects fixed and retested |
| Stata source and batch adapter | Static documentation review only |
| Executed Stata/R comparison | **Not performed** |

The synthetic fixture has 67 rows, 56 estimation observations, design rank four
and four clusters. OLS and HC1 use 52 residual degrees of freedom. Clustered
inference uses three. These facts describe the R run, not a Stata baseline.

## Tests exercise behavior, not just successful execution

- Calendar boundaries, gaps, panel separation, all-missing windows, unsorted rows
  and a negative control using an incorrect row-based moving average.
- Duplicate and fractional keys; NaN, infinity, singular designs, zero standard
  errors and output collisions. Existing output bytes stay unchanged.
- Coefficients and every OLS, HC1 and clustered covariance entry against
  independently calculated matrix formulas. Tests also check p-values, confidence
  intervals, sample IDs, predictions and 17-digit serialization.
- RStudio helper collisions: an existing function cannot replace the shipped
  calendar semantics, and user functions remain unchanged.
- Comparator mutations: changed IDs with equal row counts, isolated numeric
  errors, off-diagonal covariance changes, invalid degrees of freedom, missing
  files, duplicate keys, incomplete matrices, stale hashes and false runtime fields.
- Invalid model outputs fail even when both bundles contain the same NA or Inf.

Python test fixtures deliberately invent small evidence bundles. They test the
comparator and are **not** golden outputs from Stata. A green CI result runs only
R/Python checks and does not change the Stata status.

## Remaining acceptance work

Run the shipped example in an approved licensed Stata 17+ environment. Retain its
actual version/edition, source and input hashes, complete exports and logs.
Investigate any first divergent checkpoint. Publish the observed comparison
result without replacing the Stata baseline with R-generated values.

Until that run succeeds, use this package for instruction, synthetic practice
and R-side verification. Broader estimators and real datasets need their own
scoped fixtures and reference evidence, even after this example matches.
