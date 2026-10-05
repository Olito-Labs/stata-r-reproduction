#!/usr/bin/env Rscript
# Base-R tests. No Stata outputs or cross-language claims are made here.
args_all <- commandArgs(trailingOnly = FALSE)
script_arg <- grep("^--file=", args_all, value = TRUE)
test_file <- if (length(script_arg)) sub("^--file=", "", script_arg[[1]]) else "tests/test_r.R"
repo_root <- normalizePath(file.path(dirname(test_file), ".."), mustWork = TRUE)
source(file.path(repo_root, "scripts", "stata_semantics.R"))
source(file.path(repo_root, "scripts", "translate_demo.R"))

checks <- 0L
check <- function(ok, description) {
  if (!isTRUE(ok)) stop(description, call. = FALSE)
  checks <<- checks + 1L
  cat("PASS:", description, "\n")
}
close_each <- function(actual, expected, atol = 1e-10, rtol = 1e-9) {
  if (!identical(dim(actual), dim(expected)) || length(actual) != length(expected)) return(FALSE)
  if (!identical(unname(is.na(actual)), unname(is.na(expected)))) return(FALSE)
  keep <- !is.na(expected)
  all(abs(actual[keep] - expected[keep]) <= atol + rtol * abs(expected[keep]))
}
expect_error <- function(expr) inherits(tryCatch(force(expr), error = identity), "error")

check(identical(stata_gt(c(-1, 0, 1, NA_real_, NaN), 0), c(FALSE, FALSE, TRUE, TRUE, TRUE)),
      "Stata-style greater-than includes numeric missing values")
check(expect_error(stata_gt(1:3, NA_real_)), "missing threshold is rejected")
check(close_each(calendar_mean(c(2, 4, 8), c(1, 1, 1), c(0, 5, 6)), c(2, 3, 6)),
      "calendar window includes its left boundary and excludes older values")
check(close_each(calendar_mean(c(2, 10, 20), c(1, 1, 1), c(0, 8, 9)), c(2, 10, 15)),
      "missing calendar months do not become adjacent months")
check(close_each(calendar_mean(c(2, 100, 4, 200), c(1, 2, 1, 2), c(0, 0, 1, 1)),
                 c(2, 100, 3, 150)), "panels remain separate")
check(close_each(calendar_mean(c(NA, NA, 6, NA), c(1, 1, 1, 1), c(0, 1, 2, 9)),
                 c(NA_real_, NA_real_, 6, NA_real_)), "all-missing windows return NA and partial edges work")
check(expect_error(calendar_mean(c(1, 2), c(1, 1), c(0, 0))), "duplicate panel-month keys fail")
check(expect_error(calendar_mean(c(1, 2), c(1, 1), c(0, 0.5))), "fractional months fail")
check(expect_error(calendar_mean(c(1, 2), c(1, NA), c(0, 1))), "missing panel keys fail")
check(expect_error(calendar_mean(c(1, 2), c(1, 1), c(0, Inf))), "nonfinite month keys fail")
check(expect_error(calendar_mean(c(1, Inf), c(1, 1), c(0, 1))), "infinite measurements fail")
check(expect_error(calendar_mean(1, c(1, 2), c(0, 1))), "incompatible vector lengths fail")
check(expect_error(calendar_mean(1, 1, 0, lookback = -1)), "negative lookback fails")
check(identical(calendar_mean(numeric(), numeric(), numeric()), numeric()), "empty input is supported")

ordered <- data.frame(id = c(100, 101, 102, 200), panel = c(1, 1, 1, 2),
                      month = c(0, 5, 6, 0), x = c(2, 4, 8, 100))
permutation <- c(3L, 4L, 1L, 2L)
shuffled <- ordered[permutation, ]
check(close_each(calendar_mean(shuffled$x, shuffled$panel, shuffled$month),
                 calendar_mean(ordered$x, ordered$panel, ordered$month)[permutation]),
      "unsorted input retains its row association")
row_mean <- vapply(seq_len(3), function(i) mean(c(2, 10, 20)[seq_len(i)]), numeric(1))
check(!close_each(calendar_mean(c(2, 10, 20), c(1, 1, 1), c(0, 8, 9)), row_mean),
      "negative control detects a row-based window substituted for a calendar window")
check(!close_each(c(0, 0, 1e-4), c(0, 0, 0), atol = 1e-8, rtol = 0),
      "elementwise tolerance detects a localized numerical discrepancy")

if (!requireNamespace("sandwich", quietly = TRUE)) stop("Install sandwich in the project library before running estimator tests.")
input <- read_demo_input(file.path(repo_root, "assets", "demo", "input.csv"))
fit <- fit_demo(input)
check(identical(fit$checkpoint$id, input$id), "checkpoint retains exact input row IDs and order")
expected_sample <- complete.cases(fit$checkpoint[c("y", "x", "z", "ma6")])
check(identical(fit$checkpoint$sample, as.integer(expected_sample)), "sample indicator equals the complete model sample")
check(identical(fit$predictions$id, input$id[expected_sample]), "predictions contain exact sample IDs in input order")
check(nrow(input) == 67L, "synthetic fixture contains 67 observations")

# RStudio users may already have functions with the same names. Sourcing the
# translation must use its bundled semantics and preserve the user's helpers.
interactive_env <- new.env(parent = globalenv())
ambient_mean <- function(x, ...) seq_along(x)
ambient_validator <- function(...) invisible(TRUE)
interactive_env$calendar_mean <- ambient_mean
interactive_env$validate_panel_month <- ambient_validator
source(file.path(repo_root, "scripts", "translate_demo.R"), local = interactive_env)
interactive_fit <- interactive_env$fit_demo(input)
check(close_each(interactive_fit$checkpoint$ma6, fit$checkpoint$ma6),
      "source workflow ignores a pre-existing calendar_mean function")
check(close_each(interactive_fit$coefficients$estimate, fit$coefficients$estimate),
      "interactive helper collisions cannot change regression estimates")
check(identical(interactive_env$calendar_mean, ambient_mean) &&
        identical(interactive_env$validate_panel_month, ambient_validator),
      "sourcing the translation preserves the user's existing helper functions")
interactive_bad <- input
interactive_bad$panel[2] <- interactive_bad$panel[1]
interactive_bad$month[2] <- interactive_bad$month[1]
check(expect_error(interactive_env$fit_demo(interactive_bad)),
      "a permissive ambient validator cannot bypass panel-month validation")
interactive_env$calendar_mean <- function(...) stop("ambient calendar helper must not run")
interactive_env$validate_panel_month <- function(...) stop("ambient validator must not run")
check(!expect_error(interactive_env$fit_demo(input)),
      "changing interactive helpers after sourcing cannot affect translation")

# This environment sees ordinary attached R packages, but not the helpers that
# this test file loaded into the global environment.
partial_env <- new.env(parent = as.environment("package:stats"))
partial_env$calendar_mean <- ambient_mean
source(file.path(repo_root, "scripts", "translate_demo.R"), local = partial_env)
check(!expect_error(partial_env$fit_demo(input)),
      "source workflow works when only calendar_mean already exists")
interactive_output <- tempfile("stata-r-interactive-")
partial_env$run_translation(file.path(repo_root, "assets", "demo", "input.csv"), interactive_output)
interactive_checkpoint <- read.csv(file.path(interactive_output, "checkpoint.csv"))
check(close_each(interactive_checkpoint$ma6, fit$checkpoint$ma6),
      "interactive run_translation writes the bundled calendar-window results")

bad_id <- input; bad_id$id[2] <- bad_id$id[1]
check(expect_error(fit_demo(bad_id)), "duplicate observation IDs fail")
fractional_id <- input; fractional_id$id[1] <- fractional_id$id[1] + 0.5
check(expect_error(fit_demo(fractional_id)), "fractional observation IDs fail")
infinite_id <- input; infinite_id$id[1] <- Inf
check(expect_error(fit_demo(infinite_id)), "infinite observation IDs fail")
missing_id <- input; missing_id$id[1] <- NA_real_
check(expect_error(fit_demo(missing_id)), "missing observation IDs fail")
for (column in c("x", "z", "y")) {
  nan_input <- input; nan_input[[column]][1] <- NaN
  check(expect_error(fit_demo(nan_input)), paste("NaN in", column, "fails instead of becoming NA"))
}
nan_csv <- tempfile(fileext = ".csv")
writeLines(c("id,panel,month,x,z,y", "1,1,720,NaN,2,3"), nan_csv)
check(expect_error(read_demo_input(nan_csv)), "CSV NaN fails at the import boundary")
zero_outcome <- input; zero_outcome$y <- 0
check(expect_error(suppressWarnings(fit_demo(zero_outcome))), "zero standard errors fail before inference is exported")

# Independent matrix calculation: no covariance package or fitted-model residuals.
sample <- fit$checkpoint[expected_sample, ]
X <- cbind(`_cons` = 1, x = sample$x, z = sample$z, ma6 = sample$ma6)
y <- sample$y
N <- nrow(X); K <- ncol(X)
XX_inv <- solve(crossprod(X))
b <- drop(XX_inv %*% crossprod(X, y))
u <- drop(y - X %*% b)
score <- X * u
groups <- sort(unique(sample$panel)); G <- length(groups)
cluster_score <- t(vapply(groups, function(g) colSums(score[sample$panel == g, , drop = FALSE]), numeric(K)))
manual <- list(
  ols = XX_inv * sum(u^2) / (N - K),
  hc1 = XX_inv %*% crossprod(score) %*% XX_inv * N / (N - K),
  cluster = XX_inv %*% crossprod(cluster_score) %*% XX_inv * G / (G - 1) * (N - 1) / (N - K)
)
for (model_name in names(manual)) {
  check(close_each(unname(fit$matrices[[model_name]]), unname(manual[[model_name]])),
        paste(model_name, "full covariance matches independent matrix algebra"))
  rows <- fit$coefficients[fit$coefficients$model == model_name, ]
  check(identical(rows$term, colnames(X)), paste(model_name, "coefficient names match the design matrix"))
  check(close_each(rows$estimate, unname(b)), paste(model_name, "coefficients match independent matrix algebra"))
  df <- if (model_name == "cluster") G - 1 else N - K
  check(close_each(rows$p, 2 * pt(-abs(b / sqrt(diag(manual[[model_name]]))), df = df)),
        paste(model_name, "p-values use the intended degrees of freedom"))
  check(close_each(rows$ci_low, b - qt(0.975, df) * sqrt(diag(manual[[model_name]]))),
        paste(model_name, "confidence intervals use the intended degrees of freedom"))
}
check(close_each(fit$predictions$fitted, drop(X %*% b)), "fitted values match independent matrix algebra")
check(close_each(fit$predictions$residual, u), "residuals match independent matrix algebra")
check(all(fit$statistics$value[fit$statistics$name == "N"] == N), "all estimators report the same sample count")
check(all(fit$statistics$value[fit$statistics$name == "rank"] == K), "all estimators report design rank")
check(fit$statistics$value[fit$statistics$model == "cluster" & fit$statistics$name == "df_r"] == G - 1,
      "cluster inference records G minus one degrees of freedom")

output_dir <- tempfile("stata-r-demo-")
dir.create(output_dir)
run_translation(file.path(repo_root, "assets", "demo", "input.csv"), output_dir)
expected_files <- c("checkpoint.csv", "coefficients.csv", "vcov.csv", "predictions.csv", "statistics.csv", "runtime.csv")
check(all(file.exists(file.path(output_dir, expected_files))), "translation workflow writes all six expected CSV files")
roundtrip <- read.csv(file.path(output_dir, "coefficients.csv"), stringsAsFactors = FALSE)
check(close_each(roundtrip$estimate, fit$coefficients$estimate, atol = 0, rtol = 0),
      "17-digit coefficient serialization round-trips exactly")
V_roundtrip <- read.csv(file.path(output_dir, "vcov.csv"), stringsAsFactors = FALSE)
check(nrow(V_roundtrip) == 3L * K * K && !anyDuplicated(V_roundtrip[c("model", "term_i", "term_j")]),
      "covariance export includes every uniquely keyed matrix entry")
runtime <- read.csv(file.path(output_dir, "runtime.csv"), stringsAsFactors = FALSE)
check(all(c("R_version", "sandwich_version") %in% runtime$key), "runtime records R and sandwich versions")
before <- tools::md5sum(file.path(output_dir, expected_files))
check(expect_error(run_translation(file.path(repo_root, "assets", "demo", "input.csv"), output_dir)),
      "translation refuses an output directory containing its existing CSVs")
check(identical(before, tools::md5sum(file.path(output_dir, expected_files))),
      "refused rerun leaves every existing output byte unchanged")
collision_dir <- tempfile("stata-r-collision-")
dir.create(collision_dir)
writeLines("existing runtime sentinel", file.path(collision_dir, "runtime.csv"))
check(expect_error(run_translation(file.path(repo_root, "assets", "demo", "input.csv"), collision_dir)),
      "a collision with runtime.csv alone fails before any result is written")
check(identical(list.files(collision_dir), "runtime.csv") &&
        identical(readLines(file.path(collision_dir, "runtime.csv")), "existing runtime sentinel"),
      "collision preflight prevents partial output and preserves existing content")
cat(sprintf("\n%d checks passed. R-only validation; Stata equivalence is unverified.\n", checks))
cat("Test outputs used the temporary directory:", output_dir, "\n")
