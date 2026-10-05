# Stata semantics that reproduction must preserve

Read this reference when defining a translation's supported scope or diagnosing a mismatch.
Sources document semantics; they do not prove that an implementation matches Stata.
Use documentation for the original runtime when release differences matter.

## Demo scope and evidence

`assets/demo/original.do` uses synthetic numeric CSV data and official Stata commands.
It declares Stata 17 behavior and imports floating-point values as doubles.
It fits `regress y x z ma6` with ordinary, HC1, and one-way clustered variance.
It requires a full-rank four-column design, including the intercept.
It does not establish support for arbitrary do-files or estimators.

Five comparison files carry checkpoints, coefficients, covariance, predictions, and statistics.
`runtime.csv` additionally records the actual executable version, edition, build date, and interpreter version.
`rank` means design-matrix rank, captured from the OLS sample size minus residual degrees of freedom.
Stata's `e(rank)` instead reports covariance-matrix rank; clustering can reduce that rank.
Predictions contain OLS fitted values and residuals only for the common estimation sample.
Ordinary, HC1, and clustered fits use the same regressors and sample in this demo.

Source review is not execution verification.
Require a successful licensed Stata run and fresh output files before declaring a match.
Never substitute R-generated values for missing Stata reference results.
Keep source/input hashes and execution logs with each comparison.

## Missing values and filters

Stata orders numeric values as `nonmissing < . < .a < ... < .z`.
Thus, `x > 1000` includes numeric missings; `x == .` excludes extended missings.
Use the source predicate's actual semantics, including `missing()` and `x < .`.
String missing is `""`; labelled numeric codes remain numeric values.
An import that collapses missing tags or silently converts labels to factors can change later operations.
Require explicit handling for extended missings, value labels, and command-specific missing-value reductions.
The numeric demo covers ordinary missing values only.

Sources: [Missing values](https://www.stata.com/manuals/dmissingvalues.pdf),
[Logical expressions](https://www.stata.com/support/faqs/data-management/logical-expressions-and-missing-values/).

## Float storage and assignment

Stata evaluates expressions in double precision but normally stores new numeric variables as floats.
`set type double` changes the default; explicit types override it.
Float-stored `0.1` can fail equality with the double literal `.1`.
Importing a rounded float into a double does not restore its lost precision.
Recomputing each source assignment in double precision can therefore change a filter or merge key.
Record storage types, assignment points, and `set type`; do not silently modernize them.
The demo explicitly uses double storage and does not test float-assignment emulation.

Sources: [Data types](https://www.stata.com/manuals/ddatatypes.pdf),
[Generate and set type](https://www.stata.com/manuals/dgenerate.pdf).

## Date units, gaps, and moving averages

Stata monthly dates count months from January 1960; daily dates count days from January 1, 1960.
`format month %tm` changes display, not the stored unit.
`mofd()` converts daily dates to month indices; `month()` only extracts month of year.
Keep an integer calendar key and distinguish units from `delta()`.
`xtset panel month, delta(1)` makes `L.x` the preceding month within the same panel.
An absent month yields a missing lag; a previous available row cannot replace it.
Require unique panel/time keys. Gaps are allowed; duplicate keys are not.

For monthly unit delta, `window(5 1 0)` includes the current and five preceding months.
`window(6)` excludes the current value by default.
`tssmooth ma` removes missing values and absent periods from the denominator.
Edges use the available window; an entirely missing window produces missing.
`if` and `in` restrictions make excluded inputs missing before smoothing.
A six-row mean and a six-complete-month mean can both differ from this rule.
The demo does not fill absent rows and does not require six nonmissing inputs.
Daily, quarterly, business-calendar, timestamp, and nonunit-delta workflows need separate adapters.

Sources: [Datetime](https://www.stata.com/manuals/ddatetime.pdf),
[tsset](https://www.stata.com/manuals/tstsset.pdf),
[tssmooth ma](https://www.stata.com/manuals/tstssmoothma.pdf),
[Panel key uniqueness](https://www.stata.com/support/faqs/data-management/repeated-time-values/).

## Joins, ordering, and duplicates

Preserve `1:1`, `1:m`, and `m:1` cardinality checks and `_merge` outcomes.
Matched overlapping columns normally keep master values, even when those values are missing.
`update` and `update replace` change that rule and introduce additional merge statuses.
Stata `m:m` pairs records by position within keys and repeats the shorter group's last record.
It is not a Cartesian join. Sequential `_n` merges also depend on order.
Reject these cases unless a separately tested adapter states their exact semantics.

An ordinary Stata sort randomizes ties; `stable` preserves the incoming order.
`duplicates drop` keeps the first occurrence, making prior order significant.
Track row IDs before sorting, and inspect `_n`, `_N`, subscripts, and first/last operations.
Missing merge keys, nonunique sort keys, and overlapping columns require explicit tests.
The demo validates unique keys but does not translate merges or duplicate removal.

Sources: [Merge](https://www.stata.com/manuals/dmerge.pdf),
[Sort](https://www.stata.com/manuals/dsort.pdf),
[Duplicates](https://www.stata.com/manuals/dduplicates.pdf).

## Factors and regression inference

Stata's `i.` factors require nonnegative integers; `c.` means continuous.
`#` requests interactions; `##` also includes constituent terms.
Numeric levels determine the default base; `ib...` and persisted `fvset` metadata can override it.
Compare expanded columns, bases, omitted columns, and coefficient names before comparing estimates.
Factors, empty cells, rank deficiency, and absorbed effects are outside the numeric demo.

For unweighted `regress`, HC1 uses `N/(N-k)` and `t(N-k)` inference.
One-way clustering uses `G/(G-1) * (N-1)/(N-k)` and `t(G-1)` inference.
Here, `k` is design rank including the intercept, and `G` is cluster count.
Compare the exact estimation sample before coefficients, covariance, and interval limits.
Missing cluster IDs can remove observations. Matching coefficients alone proves little about inference.
Do not assume that another command's `robust` option has identical semantics.
Four synthetic clusters illustrate mechanics; they are not an endorsement of small-cluster inference.

`aweights` and `pweights` are normalized; `pweights` imply robust variance by default.
`fweights` use their sum as sample size; `iweights` change treatment with the variance option.
Weighted estimation, multiway clustering, HC2/HC3, survey designs, and other estimators need separate validation.

Sources: [Factor syntax](https://www.stata.com/manuals/u11.pdf),
[Regress methods and stored results](https://www.stata.com/manuals/rregress.pdf).

## Runtime and ado provenance

`version 17` selects compatibility behavior; it does not identify the actual executable or ado revision.
Record `c(stata_version)`, `c(born_date)`, `c(version)`, and `c(userversion)`.
Identify the edition through `c(MP)` and `c(SE)` or the runtime's documented real-edition value.
Legacy `c(flavor)` and `c(edition)` can describe a minimum edition rather than the actual edition.
For community commands, record `which command, all`, search paths, versions, and file hashes.
Installing a current SSC package does not recreate an earlier package revision.
Never update dependencies merely to make an original analysis run without recording the change.

PyStata invokes an installed Stata 17+ runtime; `stata_setup` only locates that installation.
Batch execution also requires working licensed Stata. Use platform-specific documented flags.
Inspect the do-file before execution; a do-file can modify files or invoke other programs.
When Stata is unavailable, deliver the translation and R checks with explicit unverified status.

Sources: [Version](https://www.stata.com/manuals/pversion.pdf),
[Runtime values](https://www.stata.com/manuals/pcreturn.pdf),
[Which](https://www.stata.com/manuals/rwhich.pdf),
[Ado paths](https://www.stata.com/manuals/psysdir.pdf),
[PyStata](https://www.stata.com/python/pystata19/install.html),
[License initialization](https://www.stata.com/manuals/ig.pdf),
[Unix batch](https://www.stata.com/support/faqs/unix/batch-mode/),
[macOS batch](https://www.stata.com/support/faqs/mac/advanced-topics/).
