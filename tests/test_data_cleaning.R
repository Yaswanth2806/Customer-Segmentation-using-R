# ==============================================================================
# tests/test_data_cleaning.R - automated checks for R/02_data_cleaning.R
# Run from the project root:  Rscript tests/test_data_cleaning.R
# (base R only - no testing framework required)
# ==============================================================================

options(customerseg.autorun = FALSE)
if (!exists("find_project_root", mode = "function")) {
  .root <- c(".", "..")[file.exists(file.path(c(".", ".."), "run_project.R"))][1]
  if (is.na(.root)) stop("Run tests from the project root (folder containing run_project.R).", call. = FALSE)
  source(file.path(.root, "R", "01_data_loading.R"))
}
if (!exists("clean_customer_data", mode = "function")) source_project_script("02_data_cleaning.R")

# ---- tiny test helpers ----------------------------------------------------------
.results <- new.env()
run_test <- function(name, code) {
  ok <- tryCatch({ force(code); TRUE }, error = function(e) {
    message("  FAIL: ", name, "\n        ", conditionMessage(e)); FALSE })
  if (ok) message("  PASS: ", name)
  assign(name, ok, envir = .results)
}
expect <- function(cond, msg = "expectation failed") if (!isTRUE(cond)) stop(msg, call. = FALSE)
expect_error <- function(expr, pattern = NULL) {
  err <- tryCatch({ expr; NULL }, error = function(e) e)
  if (is.null(err)) stop("expected an error but none was raised", call. = FALSE)
  if (!is.null(pattern) && !grepl(pattern, conditionMessage(err))) {
    stop(sprintf("error message '%s' does not match '%s'", conditionMessage(err), pattern), call. = FALSE)
  }
}

# ---- fixtures ---------------------------------------------------------------------
make_df <- function() {
  data.frame(CustomerID = 1:6,
             Gender = c("Male", "Female", "Female", "Male", "Female", "Male"),
             Age = c(25, 32, 41, 28, 55, 38),
             Annual_Income = c(30, 45, 60, 38, 80, 52),
             Spending_Score = c(40, 60, 55, 35, 20, 70),
             stringsAsFactors = FALSE)
}

message("Running tests: data cleaning")

run_test("column names are standardised (Mall Customers variants)", {
  raw <- data.frame(CustomerID = 1:2, Genre = c("Male", "Female"), Age = c(20, 30),
                    `Annual Income (k$)` = c(15, 20), `Spending Score (1-100)` = c(50, 60),
                    check.names = FALSE)
  out <- standardize_column_names(raw)
  expect(identical(names(out), CONFIG$required_columns), "names were not mapped to the standard set")
})

run_test("validate_schema stops on a missing required column", {
  df <- make_df(); df$Age <- NULL
  expect_error(validate_schema(df), "Missing required column")
})

run_test("validate_schema stops when a feature is not numeric", {
  df <- make_df(); df$Age <- as.character(df$Age)
  expect_error(validate_schema(df), "must be numeric")
})

run_test("missing numeric values are median-imputed and logged", {
  df <- make_df(); df$Age[2] <- NA
  res <- handle_missing(df, threshold = 0.5)
  expect(!anyNA(res$data$Age), "NA remained after imputation")
  expect(res$data$Age[2] == stats::median(c(25, 41, 28, 55, 38)), "wrong fill value")
  expect(nrow(res$log) == 1 && res$log$Rows_Affected == 1, "imputation not logged")
})

run_test("too many missing values stop the pipeline instead of imputing", {
  df <- make_df(); df$Annual_Income[1:3] <- NA
  expect_error(handle_missing(df, threshold = 0.05), "missing values")
})

run_test("missing Gender becomes 'Unknown'", {
  df <- make_df(); df$Gender[1] <- NA
  res <- handle_missing(df)
  expect(res$data$Gender[1] == "Unknown", "Gender not set to Unknown")
})

run_test("exact duplicate rows are removed and reported", {
  df <- rbind(make_df(), make_df()[2, ])
  res <- handle_duplicates(df)
  expect(res$n_exact == 1, "duplicate not detected")
  expect(nrow(res$data) == 6 && nrow(res$removed) == 1, "wrong rows kept/removed")
})

run_test("conflicting CustomerIDs stop the pipeline (no silent deletion)", {
  df <- make_df(); df$CustomerID[2] <- 1   # same ID, different data
  expect_error(handle_duplicates(df), "DIFFERENT data")
})

run_test("IQR outliers are flagged but never deleted", {
  df <- make_df(); df$Annual_Income[6] <- 500
  out <- detect_outliers_iqr(df)
  expect(out$summary$N_Outliers[out$summary$Variable == "Annual_Income"] >= 1, "outlier not flagged")
  expect(nrow(out$flagged_rows) >= 1, "flagged_rows empty")
  expect(nrow(df) == 6, "rows were deleted")
})

run_test("clean_customer_data keeps every valid observation", {
  raw <- make_df(); raw$Annual_Income[6] <- 500
  res <- clean_customer_data(raw)
  expect(nrow(res$data) == nrow(raw), "valid rows were dropped")
  expect(identical(names(res$data), CONFIG$required_columns), "unexpected columns in cleaned data")
})

run_test("loading and cleaning never modify the raw file", {
  ds <- find_raw_dataset()
  before <- unname(tools::md5sum(ds$path))
  invisible(clean_customer_data(load_customer_data(ds$path)))
  after <- unname(tools::md5sum(ds$path))
  expect(identical(before, after), "raw file changed")
})

run_test("load_customer_data gives clear errors", {
  expect_error(load_customer_data("does_not_exist.csv"), "not found")
  expect_error(load_customer_data(c("a.csv", "b.csv")), "single file path")
})

run_test("synthetic data passes the full cleaning workflow", {
  res <- clean_customer_data(simulate_customers(n = 120, seed = 1))
  expect(nrow(res$data) == 120, "unexpected row count")
  expect(!anyNA(res$data), "NA in cleaned data")
})

failed <- names(Filter(isFALSE, as.list(.results)))
message(sprintf("\n%d passed, %d failed", length(as.list(.results)) - length(failed), length(failed)))
if (length(failed) > 0) {
  if (sys.nframe() == 0) quit(status = 1) else stop("Data-cleaning tests failed: ", paste(failed, collapse = "; "), call. = FALSE)
}
