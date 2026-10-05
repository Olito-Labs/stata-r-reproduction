# Narrow, explicit Stata-compatible semantics for this demonstration.
# This is not a general Stata interpreter. Tagged missing values require a
# separate import policy; this helper treats every R numeric NA/NaN as missing.

stata_gt <- function(x, threshold) {
  if (!is.numeric(x) || !is.numeric(threshold) || length(threshold) != 1L ||
      is.na(threshold) || !is.finite(threshold)) {
    stop("x must be numeric and threshold must be one finite number.", call. = FALSE)
  }
  is.na(x) | x > threshold
}

validate_panel_month <- function(panel, month) {
  valid_integer <- function(x) {
    is.numeric(x) && !anyNA(x) && all(is.finite(x)) && all(x == trunc(x))
  }
  if (length(panel) != length(month) || !valid_integer(panel) || !valid_integer(month)) {
    stop("panel and month must be equal-length finite, nonmissing integer vectors.", call. = FALSE)
  }
  if (anyDuplicated(data.frame(panel = panel, month = month))) {
    stop("Each panel-month pair must be unique.", call. = FALSE)
  }
  invisible(TRUE)
}

calendar_mean <- function(x, panel, month, lookback = 5L) {
  validate_panel_month(panel, month)
  if (!is.numeric(x) || length(x) != length(panel) || any(!is.finite(x) & !is.na(x))) {
    stop("x must contain numeric finite values or missing values, one per panel-month.", call. = FALSE)
  }
  if (!is.numeric(lookback) || length(lookback) != 1L || is.na(lookback) ||
      !is.finite(lookback) || lookback < 0 || lookback != trunc(lookback)) {
    stop("lookback must be one nonnegative finite integer.", call. = FALSE)
  }
  result <- rep(NA_real_, length(x))
  # Deliberately direct interval implementation: transparent reference semantics
  # for a small fixture, not a performance claim. Order never defines a window.
  for (g in unique(panel)) {
    positions <- which(panel == g)
    for (i in positions) {
      window <- positions[month[positions] >= month[i] - lookback & month[positions] <= month[i]]
      observed <- x[window][!is.na(x[window])]
      if (length(observed)) result[i] <- mean(observed)
    }
  }
  result
}
