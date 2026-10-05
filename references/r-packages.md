# R packages for verified Stata reproduction

Primary documentation reviewed on 2026-10-05.
Package documentation supports implementation choices; it does not prove output equivalence.
Record the actual installed versions and compare against the exact Stata command and version.

## Minimal executable demo

The included demo depends directly on **base R and sandwich only**.
Its tests use base R assertions and independent matrix algebra.
The synthetic CSV requires no import package and uses no random-number generator.
Do not install the optional packages below merely to run the demo.
The project-local `.r-library` is supported by the R scripts.
The demo accepts integer observation IDs, integer panel/month keys, finite measurements, and ordinary NA.
It rejects NaN, duplicate panel-month keys, nonpositive standard errors, and output-file collisions.

## Add packages when the source analysis needs them

| Requirement | Candidate | Selection rule |
| --- | --- | --- |
| Stata DTA import | haven | Preserve codes, labels, formats, and missing tags before conversion. |
| Large in-memory transformations | data.table | Choose one primary data engine; audit ordering and key cardinality. |
| Index-based rolling windows | slider | Use when a calendar interval, rather than a row count, defines a window. |
| Absorbed fixed effects | fixest | Specify covariance, corrections, removal policy, and numerical tolerances. |
| Package-version restoration | renv | Add early for a substantive project; record R and system details separately. |
| Richer test diagnostics | testthat / waldo | Optional; exact checks and explicit numeric tolerances remain necessary. |
| Beyond-memory preprocessing | Arrow / DuckDB | Defer until memory measurements justify a second execution backend. |

Base `stats::lm` remains a useful small-data reference estimator.
Do not translate an unsupported estimator by selecting the nearest package name.
Weights, survey designs, IV estimators, nonlinear models, and post-estimation need separate contracts.

## haven: import is not semantic conversion

Labelled numeric values are not automatically categorical variables.
Labels may cover only part of a variable's values.
Choose factor conversion or label removal per variable; keep the source metadata.
Tagged missing values behave like R NA in ordinary operations.
Inspect tags explicitly with `na_tag()`; do not assume joins or comparisons preserve Stata semantics.
See [conversion semantics](https://haven.tidyverse.org/articles/semantics.html)
and [tagged missing values](https://haven.tidyverse.org/reference/tagged_na.html).

Audit date formats, units, and origins separately from displayed values.
Stata daily dates use a 1960 origin; weekly, monthly, quarterly, and business dates need their own rules.
Writing datetimes with `adjust_tz = TRUE` can change underlying numeric times.
See [haven dates](https://haven.tidyverse.org/articles/datetimes.html),
[Stata I/O](https://haven.tidyverse.org/reference/read_dta.html),
and [Stata business calendars](https://www.stata.com/features/overview/business-calendars/).

## data.table and dplyr: order and matches are part of the result

`data.table::merge()` matches NA to NA and sorts keys by default.
`sort = FALSE` has a documented order; preserve observation IDs regardless.
`by` retains group encounter order; `keyby` sorts group keys.
`setorder()` mutates by reference, uses C-locale order, and defaults to missing values first.
See [merge](https://rdatatable.gitlab.io/data.table/reference/merge.html),
[grouping and joins](https://rdatatable.gitlab.io/data.table/reference/data.table.html),
and [ordering](https://rdatatable.gitlab.io/data.table/reference/setorder.html).

`allow.cartesian = FALSE` is an output-size guard, not an assertion of unique keys.
Validate intended one-to-one or many-to-one relationships directly.
Rolling joins need an explicit direction, maximum distance, endpoint rule, and duplicate policy.
If using dplyr instead, set `relationship`, `na_matches`, and unmatched-row policy.
Its `group_by()` sorts group keys, while `.by` preserves encounter order.
See [dplyr joins](https://dplyr.tidyverse.org/reference/mutate-joins.html)
and [per-operation grouping](https://dplyr.tidyverse.org/reference/dplyr_by.html).

## slider: calendar windows are not row windows

`slide()` uses positions; `slide_index()` uses index boundaries.
Index values must increase and cannot be missing; repeated indexes are grouped together.
`.complete = TRUE` does not assert a minimum number of usable regression observations.
Specify interval endpoints, panel separation, partial-edge behavior, and all-missing behavior.
A six-month window is not necessarily six rows or 180 days.
See [slide_index](https://slider.r-lib.org/reference/slide_index.html).
Ordinary `data.table::froll*()` follows physical order; gaps require an adaptive window.
See [data.table rolling functions](https://rdatatable.gitlab.io/data.table/reference/froll.html).

## lm, sandwich, and inference

Match the model sample, factor bases, interactions, intercept, and design rank before comparing estimates.
Inspect [lm](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/lm.html)
and [model.matrix](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/model.matrix.html).
For ordinary unweighted robust OLS, explicitly request `vcovHC(type = "HC1")`; the default is HC3.
For one-way clustered OLS, explicitly request `vcovCL(type = "HC1", cadjust = TRUE)`.
The cluster correction is `G/(G-1) * (N-1)/(N-K)`.
See [vcovHC](https://sandwich.r-forge.r-project.org/reference/vcovHC.html)
and [vcovCL](https://sandwich.r-forge.r-project.org/reference/vcovCL.html).

Covariance corrections and inference degrees of freedom are separate.
Ordinary Stata robust inference uses N-K; conventional one-way clustered inference uses G-1.
If using `lmtest::coeftest()`, supply cluster degrees of freedom explicitly.
See [Stata regress](https://www.stata.com/manuals/rregress.pdf)
and [lmtest](https://cran.r-project.org/web/packages/lmtest/lmtest.pdf).
Compare the complete named covariance matrix, including off-diagonal entries.
Do not treat matching standard errors as proof that joint tests will match.

## fixest: specify defaults and pin versions

Use explicit `vcov`, `ssc`, `fixef.rm`, and collinearity settings.
`K.fixef` controls absorbed-parameter counting; `K.exact` addresses redundant fixed effects.
`G.df` controls multiway covariance corrections; `t.df` controls inference.
See [ssc](https://lrberge.github.io/fixest/reference/ssc.html).
The [comparison vignette](https://lrberge.github.io/fixest/articles/standard_errors.html)
shows why dummy-variable lm, xtreg, and other panel estimators can differ.
It is not a blanket equivalence guarantee for every reghdfe model.
Version 0.13.0 changed covariance and fixed-effect removal defaults.
Version 0.14.0 fixed a multiple-fixed-effect degrees-of-freedom bug.
See the [changelog](https://lrberge.github.io/fixest/news/index.html).
Extract sample membership with [obs](https://lrberge.github.io/fixest/reference/obs.html).

## Reproducibility and test traps

[renv](https://rstudio.github.io/renv/articles/renv.html) restores packages but does not install the recorded R version.
Record OS, compiler, system libraries, locale, RNG settings, and input hashes where relevant.
Audit [dependency discovery](https://rstudio.github.io/renv/articles/faq.html) for dynamic package loading.
Use exact checks for sample IDs, keys, types, dimensions, names, and missing-value categories.
Use a stated elementwise absolute-plus-relative tolerance for numerical results.
[testthat equality](https://testthat.r-lib.org/reference/equality-expectations.html) can relax numeric types.
[waldo tolerance](https://waldo.r-lib.org/reference/compare.html) uses averaged differences and can equate NaN with NA.
Use waldo for diagnosis; do not let a permissive aggregate tolerance define the entire acceptance contract.
Matching numeric seeds across languages does not establish matching random draws.
Generator, initialization, transformation, version, and draw order also matter.
Prefer shared saved draws or deterministic fixtures for an exact comparison.
See [R RNG](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Random.html)
and [Stata seeds](https://www.stata.com/manuals/rsetseed.pdf).

[Arrow](https://arrow.apache.org/docs/r/articles/dataset.html) can preprocess lazily, but collection needs memory.
[DuckDB](https://r.duckdb.org/reference/duckdb_memory.html) has a memory budget distinct from R's.
[DuckDB joins and grouping](https://duckdb.org/docs/lts/sql/dialect/order_preservation) do not preserve row order.
Any backend change requires new checks for types, missing values, ordering, and materialization.
