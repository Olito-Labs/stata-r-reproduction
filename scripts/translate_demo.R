#!/usr/bin/env Rscript
# Usage: Rscript --vanilla scripts/translate_demo.R INPUT.csv OUTPUT_DIRECTORY
# Required package: sandwich. A local .r-library is supported without changing
# the user's global R library. No package is installed by this script.
#
# Public synthetic fixture: p = 1..4 and t = 1..18, month = 719+t,
# id = 100*p+t. Drop (p,t) = (1,4),(2,8),(3,3),(3,14),(4,11).
# x_star = .35*p + .12*t + (((7*p+3*t) %% 9)-4)*.08
# z = (((5*p+2*t) %% 11)-5)/3 + .04*t
# y = 1.7 + .65*x_star - .3*z + .07*p + (((11*p+5*t) %% 13)-6)*.09
# Observe x=x_star except p=2,t<=6 and (1,6),(3,10),(4,17), which are NA.
# y is NA at (1,12),(3,6). Rows sort on (17*id) %% 71, then id.
# No random-number generator is used. All values are synthetic.

demo_script_root <- local({
  frames <- sys.frames()
  source_files <- vapply(frames, function(frame) {
    if (is.null(frame$ofile)) "" else frame$ofile
  }, character(1))
  source_files <- source_files[nzchar(source_files)]
  if (length(source_files)) {
    path <- source_files[[length(source_files)]]
  } else {
    flag <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
    path <- if (length(flag)) sub("^--file=", "", flag[[1]]) else "scripts/translate_demo.R"
  }
  normalizePath(file.path(dirname(path), ".."), mustWork = TRUE)
})
local_library <- file.path(demo_script_root, ".r-library")
if (dir.exists(local_library)) .libPaths(c(local_library, .libPaths()))
# Load the bundled semantics into their own environment. An interactive session
# can contain unrelated calendar_mean/validate_panel_month functions; neither
# those functions nor later changes to them may alter this translation.
.demo_semantics <- new.env(parent = baseenv())
sys.source(file.path(demo_script_root, "scripts", "stata_semantics.R"), envir = .demo_semantics)
lockEnvironment(.demo_semantics, bindings = TRUE)

validate_demo_input <- function(data) {
  required <- c("id", "panel", "month", "x", "z", "y")
  if (!is.data.frame(data) || !identical(names(data), required)) {
    stop("Input columns must be exactly: id,panel,month,x,z,y (in that order).", call. = FALSE)
  }
  if (!all(vapply(data, is.numeric, logical(1)))) stop("Every input column must be numeric.", call. = FALSE)
  if (!nrow(data)) stop("Input must contain observations.", call. = FALSE)
  # CSV has one supported missing representation: blank or NA. NaN carries
  # different semantics in R, so fail instead of silently serializing it as NA.
  if (any(vapply(data, function(column) any(is.nan(column)), logical(1)))) {
    stop("NaN is unsupported in demo input; use NA only for genuinely missing observations.", call. = FALSE)
  }
  if (anyNA(data$id) || any(!is.finite(data$id)) || any(data$id != trunc(data$id)) || anyDuplicated(data$id)) {
    stop("id must contain unique finite nonmissing integer values.", call. = FALSE)
  }
  .demo_semantics$validate_panel_month(data$panel, data$month)
  if (any(vapply(data[c("x", "z", "y")], function(x) any(!is.finite(x) & !is.na(x)), logical(1)))) {
    stop("Measurements may be finite or missing; infinite values are unsupported.", call. = FALSE)
  }
  invisible(TRUE)
}

read_demo_input <- function(path) {
  data <- read.csv(path, colClasses = "numeric", na.strings = c("", "NA"), check.names = FALSE)
  validate_demo_input(data)
  data
}

fit_demo <- function(data) {
  validate_demo_input(data)
  if (!requireNamespace("sandwich", quietly = TRUE)) {
    stop("Package 'sandwich' is required. Install it in the project .r-library.", call. = FALSE)
  }
  checkpoint <- data
  checkpoint$ma6 <- .demo_semantics$calendar_mean(data$x, data$panel, data$month, lookback = 5L)
  in_sample <- complete.cases(checkpoint[c("y", "x", "z", "ma6")])
  checkpoint$sample <- as.integer(in_sample)
  sample <- checkpoint[in_sample, , drop = FALSE]
  # Build the model only after fixing the exact row sample; unexpected missing
  # values must fail instead of triggering a second, hidden deletion policy.
  model <- lm(y ~ x + z + ma6, data = sample, na.action = na.fail,
              model = TRUE, x = TRUE, y = TRUE, singular.ok = FALSE)
  N <- nobs(model)
  K <- model$rank
  G <- length(unique(sample$panel))
  if (N <= K || G < 2L) stop("Positive residual degrees of freedom and at least two clusters are required.", call. = FALSE)
  matrices <- list(
    ols = vcov(model),
    hc1 = sandwich::vcovHC(model, type = "HC1"),
    cluster = sandwich::vcovCL(model, cluster = sample$panel, type = "HC1", cadjust = TRUE, fix = FALSE)
  )
  b <- coef(model)
  terms <- names(b)
  terms[terms == "(Intercept)"] <- "_cons"
  matrices <- lapply(matrices, function(V) {
    dimnames(V) <- list(terms, terms)
    if (any(!is.finite(V)) || any(diag(V) <= 0)) {
      stop("Covariance must be finite and standard errors must be strictly positive.", call. = FALSE)
    }
    V
  })
  coefficients <- do.call(rbind, lapply(names(matrices), function(name) {
    se <- sqrt(diag(matrices[[name]]))
    df <- if (name == "cluster") G - 1L else N - K
    statistic <- unname(b) / se
    critical <- qt(0.975, df = df)
    data.frame(model = name, term = terms, estimate = unname(b), se = unname(se),
               statistic = unname(statistic), p = unname(2 * pt(-abs(statistic), df = df)),
               ci_low = unname(b - critical * se), ci_high = unname(b + critical * se),
               stringsAsFactors = FALSE, row.names = NULL)
  }))
  covariance <- do.call(rbind, lapply(names(matrices), function(name) {
    V <- matrices[[name]]
    keys <- expand.grid(term_i = terms, term_j = terms, KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
    data.frame(model = name, keys, value = as.vector(V), stringsAsFactors = FALSE)
  }))
  predictions <- data.frame(id = sample$id, fitted = unname(fitted(model)), residual = unname(residuals(model)))
  statistics <- do.call(rbind, lapply(names(matrices), function(name) {
    data.frame(model = name, name = c("N", "rank", "df_r", "N_clust"),
               value = c(N, K, if (name == "cluster") G - 1L else N - K, if (name == "cluster") G else 0L),
               stringsAsFactors = FALSE)
  }))
  list(checkpoint = checkpoint, coefficients = coefficients, vcov = covariance,
       predictions = predictions, statistics = statistics, matrices = matrices)
}

write_csv_17 <- function(data, path) {
  # 17 significant digits recover each finite binary64 value on round-trip.
  encoded <- lapply(data, function(column) {
    if (is.numeric(column)) {
      result <- sprintf("%.17g", column)
      result[is.na(column)] <- ""
      result
    } else as.character(column)
  })
  encoded <- as.data.frame(encoded, stringsAsFactors = FALSE, check.names = FALSE)
  write.table(encoded, file = path, sep = ",", row.names = FALSE, col.names = TRUE,
              quote = TRUE, na = "", qmethod = "double", fileEncoding = "UTF-8")
  invisible(path)
}

run_translation <- function(input_path, output_dir) {
  output_names <- c("checkpoint", "coefficients", "vcov", "predictions", "statistics", "runtime")
  output_paths <- file.path(output_dir, paste0(output_names, ".csv"))
  if (any(file.exists(output_paths))) {
    stop("Refusing to overwrite existing output CSVs. Choose a new output directory.", call. = FALSE)
  }
  result <- fit_demo(read_demo_input(input_path))
  if (!dir.exists(output_dir) && !dir.create(output_dir, recursive = TRUE)) {
    stop("Cannot create output directory.", call. = FALSE)
  }
  for (name in c("checkpoint", "coefficients", "vcov", "predictions", "statistics")) {
    write_csv_17(result[[name]], file.path(output_dir, paste0(name, ".csv")))
  }
  runtime <- data.frame(key = c("R_version", "sandwich_version"),
                        value = c(R.version.string, as.character(packageVersion("sandwich"))),
                        stringsAsFactors = FALSE)
  write_csv_17(runtime, file.path(output_dir, "runtime.csv"))
  cat("Wrote R outputs to:", normalizePath(output_dir), "\n")
  cat("These outputs alone do not verify Stata equivalence.\n")
  invisible(result)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != 2L) {
    stop("Usage: Rscript --vanilla scripts/translate_demo.R INPUT.csv OUTPUT_DIRECTORY", call. = FALSE)
  }
  run_translation(args[[1]], args[[2]])
}
