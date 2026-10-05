/*
Public synthetic example for Stata-to-R reproduction.
Usage: do original.do "input.csv" "existing-empty-output-directory"

This source was reviewed against Stata documentation, but was not executed
when authored. Only a successful licensed Stata run can create a baseline.
No user data, community ado packages, or network access are required.

Five comparison CSVs and runtime.csv are written. Existing files are refused.
Input month is an integer Stata monthly index (0 = January 1960).
*/

version 17
args input outputdir
if `"`input'"' == "" | `"`outputdir'"' == "" {
    display as error "Usage: do original.do input.csv existing-output-directory"
    exit 198
}

set more off
set type double
set level 95
set dp period

foreach artifact in checkpoint coefficients vcov predictions statistics runtime {
    confirm new file `"`outputdir'/`artifact'.csv"'
}

import delimited using `"`input'"', clear varnames(1) numericcols(all) asdouble
unab inputvars : _all
if "`inputvars'" != "id panel month x z y" {
    display as error "Input columns must be: id,panel,month,x,z,y"
    exit 198
}
confirm numeric variable id panel month x z y
isid id
isid panel month
assert id == floor(id) & panel == floor(panel) & month == floor(month)

format month %tm
xtset panel month, delta(1)
/* Current month plus five calendar lags; available values, partial edges. */
tssmooth ma double ma6 = x, window(5 1 0)

tempname coefs covars stats runtime B V design_rank se statistic p lower upper critical
file open `coefs' using `"`outputdir'/coefficients.csv"', write text
file open `covars' using `"`outputdir'/vcov.csv"', write text
file open `stats' using `"`outputdir'/statistics.csv"', write text
file write `coefs' "model,term,estimate,se,statistic,p,ci_low,ci_high" _n
file write `covars' "model,term_i,term_j,value" _n
file write `stats' "model,name,value" _n

foreach model in ols hc1 cluster {
    if "`model'" == "ols" {
        quietly regress y x z ma6
    }
    if "`model'" == "hc1" {
        quietly regress y x z ma6, vce(robust)
    }
    if "`model'" == "cluster" {
        quietly regress y x z ma6, vce(cluster panel)
    }

    matrix `B' = e(b)
    matrix `V' = e(V)
    local terms : colnames `B'
    local k = colsof(`B')

    if "`model'" == "ols" {
        /* Schema rank is design rank. Cluster e(rank) is rank of e(V). */
        scalar `design_rank' = e(N) - e(df_r)
        if `design_rank' != 4 | `k' != 4 {
            display as error "Demo requires a full-rank four-column design."
            exit 459
        }
        generate byte sample = e(sample)
        predict double fitted if sample == 1, xb
        predict double residual if sample == 1, residuals
    }
    else {
        assert sample == e(sample)
    }

    scalar `critical' = invttail(e(df_r), 0.025)
    forvalues j = 1/`k' {
        local term_i : word `j' of `terms'
        scalar `se' = sqrt(`V'[`j', `j'])
        if missing(`se') | `se' <= 0 {
            display as error "Demo requires positive finite standard errors."
            exit 459
        }
        scalar `statistic' = `B'[1, `j'] / `se'
        scalar `p' = 2 * ttail(e(df_r), abs(`statistic'))
        scalar `lower' = `B'[1, `j'] - `critical' * `se'
        scalar `upper' = `B'[1, `j'] + `critical' * `se'
        file write `coefs' "`model',`term_i'," ///
            %24.17g (`B'[1, `j']) "," %24.17g (`se') "," ///
            %24.17g (`statistic') "," %24.17g (`p') "," ///
            %24.17g (`lower') "," %24.17g (`upper') _n
        forvalues h = 1/`k' {
            local term_j : word `h' of `terms'
            file write `covars' "`model',`term_i',`term_j'," ///
                %24.17g (`V'[`j', `h']) _n
        }
    }

    file write `stats' "`model',N," %24.17g (e(N)) _n
    file write `stats' "`model',rank," %24.17g (`design_rank') _n
    file write `stats' "`model',df_r," %24.17g (e(df_r)) _n
    if "`model'" == "cluster" {
        file write `stats' "`model',N_clust," %24.17g (e(N_clust)) _n
    }
    else {
        file write `stats' "`model',N_clust,0" _n
    }
}
file close `coefs'
file close `covars'
file close `stats'

/* Export numeric month keys, not formatted month labels. */
sort id
format id panel month x z y ma6 sample fitted residual %24.17g
export delimited id panel month x z y ma6 sample ///
    using `"`outputdir'/checkpoint.csv"', datafmt nolabel
export delimited id fitted residual using `"`outputdir'/predictions.csv"' ///
    if sample == 1, datafmt nolabel

/* c(stata_version) is actual runtime; version 17 selects interpreter behavior. */
local edition "BE"
if c(SE) == 1 local edition "SE"
if c(MP) == 1 local edition "MP"
file open `runtime' using `"`outputdir'/runtime.csv"', write text
file write `runtime' "key,value" _n
file write `runtime' "engine,Stata" _n
file write `runtime' "stata_version," %24.17g (c(stata_version)) _n
file write `runtime' "stata_edition,`edition'" _n
file write `runtime' "stata_born_date," (c(born_date)) _n
file write `runtime' "version_control," %24.17g (c(version)) _n
file write `runtime' "user_version," %24.17g (c(userversion)) _n
file write `runtime' "os," (c(os)) _n
file write `runtime' "status,completed" _n
file close `runtime'
display as text "STATA_R_REPRODUCTION_DEMO_COMPLETED"
