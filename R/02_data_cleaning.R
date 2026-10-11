# ==============================================================================
# 02_data_cleaning.R
# ------------------------------------------------------------------------------
# Purpose : Inspect, validate and clean the raw customer data. The raw file is
#           NEVER modified, and no valid observation is silently deleted.
#
# Cleaning strategy (documented in docs/methodology.md):
#   * Column names are standardised to CustomerID, Gender, Age, Annual_Income,
#     Spending_Score (handles the "Genre" / "Annual Income (k$)" variants).
#   * Exact duplicate rows are removed (first copy kept) and logged. Rows that
#     share a CustomerID but differ elsewhere STOP the pipeline for manual review.
#   * Rows with identical attributes but different CustomerIDs are only flagged:
#     different customers can legitimately look alike.
#   * Missing numeric values are median-imputed only if <= 5% of rows are
#     affected (otherwise the pipeline stops); missing Gender becomes "Unknown".
#   * Out-of-range values and IQR outliers are FLAGGED and KEPT - in customer
#     data they are usually genuine (e.g. very high earners).
#
# Inputs  : data/raw/*.csv (via 01_data_loading.R)
# Outputs : data/processed/customers_clean.csv
#           outputs/tables/{data_quality_summary,missing_values_summary,
#                           range_validation,outlier_summary,outlier_records}.csv
# Usage   : Rscript R/02_data_cleaning.R   (from the project root)
# ==============================================================================

if (!exists("find_project_root", mode = "function")) {
  .f <- c("R/01_data_loading.R", "01_data_loading.R")
  .f <- .f[file.exists(.f)][1]
  if (is.na(.f)) stop("Run this script from the project root (the folder containing run_project.R).", call. = FALSE)
  local({ op <- options(customerseg.autorun = FALSE); on.exit(options(op)); source(.f) })
}

# ------------------------------------------------------------------------------
# Column handling and validation
# ------------------------------------------------------------------------------
#' Map common column-name variants onto the standard names used by the pipeline.
standardize_column_names <- function(df) {
  lookup <- c(
    "customerid" = "CustomerID", "customer_id" = "CustomerID",
    "customer id" = "CustomerID", "id" = "CustomerID",
    "gender" = "Gender", "genre" = "Gender", "sex" = "Gender",
    "age" = "Age",
    "annual income (k$)" = "Annual_Income", "annual income" = "Annual_Income",
    "annual_income" = "Annual_Income", "annual_income_k" = "Annual_Income",
    "spending score (1-100)" = "Spending_Score", "spending score" = "Spending_Score",
    "spending_score" = "Spending_Score"
  )
  key <- tolower(trimws(names(df)))
  hit <- key %in% names(lookup)
  names(df)[hit] <- unname(lookup[key[hit]])
  df
}

#' Check that all required columns exist, numeric features are numeric and the
#' identifier has no missing values. Stops with a clear message otherwise.
validate_schema <- function(df, required = CONFIG$required_columns) {
  if (!is.data.frame(df)) stop("`df` must be a data frame.", call. = FALSE)
  missing_cols <- setdiff(required, names(df))
  if (length(missing_cols) > 0) {
    stop("Missing required column(s): ", paste(missing_cols, collapse = ", "),
         ".\nColumns found: ", paste(names(df), collapse = ", "), call. = FALSE)
  }
  not_numeric <- CONFIG$features[!vapply(CONFIG$features, function(f) is.numeric(df[[f]]), logical(1))]
  if (length(not_numeric) > 0) {
    stop("Column(s) must be numeric: ", paste(not_numeric, collapse = ", "),
         ". Check the raw file for text values in these columns.", call. = FALSE)
  }
  if (anyNA(df$CustomerID)) {
    stop("CustomerID contains missing values; every customer needs an identifier.", call. = FALSE)
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# Inspection
# ------------------------------------------------------------------------------
#' Print dimensions, column names, data types and summary statistics.
inspect_data <- function(df, verbose = TRUE) {
  types <- data.frame(Column = names(df),
                      Type = vapply(df, function(x) class(x)[1], character(1)),
                      stringsAsFactors = FALSE)
  if (verbose) {
    cat(sprintf("Dimensions: %d rows x %d columns\n", nrow(df), ncol(df)))
    cat("Columns and types:\n")
    print(types, row.names = FALSE)
    cat("\nSummary statistics:\n")
    print(summary(as.data.frame(df)))
  }
  invisible(list(dimensions = dim(df), types = types, summary = summary(as.data.frame(df))))
}

#' Count missing values per column.
summarise_missing <- function(df) {
  n_na <- vapply(df, function(x) sum(is.na(x)), numeric(1))
  data.frame(Column = names(df), Missing_Count = as.integer(n_na),
             Missing_Percent = round(100 * n_na / nrow(df), 2),
             row.names = NULL, stringsAsFactors = FALSE)
}

#' Compare each numeric feature with its plausible range (flag only, never delete).
check_ranges <- function(df, ranges = CONFIG$valid_ranges) {
  res <- lapply(names(ranges), function(col) {
    x  <- df[[col]]
    lo <- ranges[[col]][1]; hi <- ranges[[col]][2]
    data.frame(Variable = col, Allowed_Min = lo, Allowed_Max = hi,
               Observed_Min = suppressWarnings(min(x, na.rm = TRUE)),
               Observed_Max = suppressWarnings(max(x, na.rm = TRUE)),
               N_Out_Of_Range = sum(!is.na(x) & (x < lo | x > hi)),
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, res)
  if (any(out$N_Out_Of_Range > 0)) {
    warning("Some values fall outside their plausible range; they were flagged, not removed. ",
            "See outputs/tables/range_validation.csv.", call. = FALSE)
  }
  out
}

# ------------------------------------------------------------------------------
# Duplicates, missing values, categorical clean-up
# ------------------------------------------------------------------------------
#' Remove exact duplicate rows (keeping the first) and flag suspicious look-alikes.
handle_duplicates <- function(df) {
  exact   <- duplicated(df)
  removed <- df[exact, , drop = FALSE]
  kept    <- df[!exact, , drop = FALSE]

  conflicting <- unique(kept$CustomerID[duplicated(kept$CustomerID)])
  if (length(conflicting) > 0) {
    stop("CustomerID values are shared by rows with DIFFERENT data: ",
         paste(utils::head(conflicting, 10), collapse = ", "),
         if (length(conflicting) > 10) ", ..." else "",
         ".\nInvestigate these records manually; the pipeline will not guess which row is correct.",
         call. = FALSE)
  }
  attr_cols <- setdiff(names(kept), "CustomerID")
  n_attr_dupes <- sum(duplicated(kept[attr_cols]))
  list(data = kept, removed = removed, n_exact = sum(exact), n_attribute_dupes = n_attr_dupes)
}

#' Impute missing values using the documented strategy and log every change.
handle_missing <- function(df, threshold = CONFIG$missing_threshold) {
  log <- list()
  for (col in CONFIG$features) {
    n_na <- sum(is.na(df[[col]]))
    if (n_na == 0) next
    share <- n_na / nrow(df)
    if (share > threshold) {
      stop(sprintf("Column '%s' has %.1f%% missing values (limit %.0f%%). Investigate before imputing.",
                   col, 100 * share, 100 * threshold), call. = FALSE)
    }
    fill <- stats::median(df[[col]], na.rm = TRUE)
    df[[col]][is.na(df[[col]])] <- fill
    log[[col]] <- data.frame(Column = col, Strategy = "median imputation",
                             Rows_Affected = n_na, Fill_Value = fill, stringsAsFactors = FALSE)
  }
  g <- as.character(df$Gender)
  g_missing <- is.na(g) | trimws(g) == ""
  if (any(g_missing)) {
    g[g_missing] <- "Unknown"
    log[["Gender"]] <- data.frame(Column = "Gender", Strategy = "set to 'Unknown'",
                                  Rows_Affected = sum(g_missing), Fill_Value = NA_real_,
                                  stringsAsFactors = FALSE)
  }
  df$Gender <- g
  log_df <- if (length(log) > 0) do.call(rbind, log) else
    data.frame(Column = character(), Strategy = character(),
               Rows_Affected = integer(), Fill_Value = numeric(), stringsAsFactors = FALSE)
  rownames(log_df) <- NULL
  list(data = df, log = log_df)
}

#' Standardise Gender labels ("male", " MALE " -> "Male").
clean_gender <- function(df) {
  g <- trimws(as.character(df$Gender))
  g <- paste0(toupper(substr(g, 1, 1)), tolower(substring(g, 2)))
  unexpected <- setdiff(unique(g), c("Female", "Male", "Unknown"))
  if (length(unexpected) > 0) {
    warning("Unexpected Gender value(s) kept as-is: ", paste(unexpected, collapse = ", "), call. = FALSE)
  }
  df$Gender <- g
  df
}

# ------------------------------------------------------------------------------
# Outliers (IQR rule) - flagged, never deleted
# ------------------------------------------------------------------------------
detect_outliers_iqr <- function(df, cols = CONFIG$features, k = CONFIG$iqr_multiplier) {
  per_col <- lapply(cols, function(col) {
    x <- df[[col]]
    q <- stats::quantile(x, c(0.25, 0.75), na.rm = TRUE, names = FALSE)
    iqr <- q[2] - q[1]
    lo <- q[1] - k * iqr
    hi <- q[2] + k * iqr
    list(flag = !is.na(x) & (x < lo | x > hi),
         row = data.frame(Variable = col, Q1 = q[1], Q3 = q[2], IQR = iqr,
                          Lower_Bound = lo, Upper_Bound = hi,
                          N_Outliers = sum(!is.na(x) & (x < lo | x > hi)),
                          Percent_Outliers = round(100 * sum(!is.na(x) & (x < lo | x > hi)) / length(x), 2),
                          stringsAsFactors = FALSE))
  })
  flags <- do.call(cbind, lapply(per_col, `[[`, "flag"))
  colnames(flags) <- cols
  any_flag <- rowSums(flags) > 0
  flagged <- df[any_flag, , drop = FALSE]
  if (nrow(flagged) > 0) {
    flagged$Outlier_Variables <- apply(flags[any_flag, , drop = FALSE], 1,
                                       function(r) paste(cols[r], collapse = "; "))
  }
  list(summary = do.call(rbind, lapply(per_col, `[[`, "row")), flagged_rows = flagged)
}

# ------------------------------------------------------------------------------
# Orchestration
# ------------------------------------------------------------------------------
#' Run the full cleaning workflow on a raw data frame.
clean_customer_data <- function(raw) {
  df <- standardize_column_names(raw)
  validate_schema(df)
  extra <- setdiff(names(df), CONFIG$required_columns)
  if (length(extra) > 0) message("  Ignoring extra column(s): ", paste(extra, collapse = ", "))
  df <- tibble::as_tibble(df[CONFIG$required_columns])

  missing_before <- summarise_missing(df)
  ranges         <- check_ranges(df)
  dup            <- handle_duplicates(df)
  miss           <- handle_missing(dup$data)
  df_clean       <- clean_gender(miss$data)
  outliers       <- detect_outliers_iqr(df_clean)

  quality <- data.frame(
    Check = c("Rows in raw file", "Columns in raw file",
              "Missing values (required columns)", "Values imputed",
              "Exact duplicate rows removed", "Attribute look-alike rows flagged (kept)",
              "Out-of-range values flagged (kept)", "Records with IQR outliers flagged (kept)",
              "Rows in cleaned data"),
    Value = c(nrow(raw), ncol(raw),
              sum(missing_before$Missing_Count), sum(miss$log$Rows_Affected),
              dup$n_exact, dup$n_attribute_dupes,
              sum(ranges$N_Out_Of_Range), nrow(outliers$flagged_rows),
              nrow(df_clean)),
    stringsAsFactors = FALSE
  )
  list(data = df_clean, quality = quality, missing_summary = missing_before,
       ranges = ranges, duplicates = dup, imputation_log = miss$log, outliers = outliers)
}

run_data_cleaning <- function(raw = NULL) {
  message("== Step 2: Data cleaning ==")
  ensure_project_dirs()
  if (is.null(raw)) {
    ds  <- find_raw_dataset()
    raw <- load_customer_data(ds$path)
  }
  inspect_data(raw)
  res <- clean_customer_data(raw)

  out_path <- project_path("data", "processed", "customers_clean.csv")
  readr::write_csv(res$data, out_path)
  message("  saved data  : data/processed/customers_clean.csv (", nrow(res$data), " rows)")

  save_table(res$quality,         "data_quality_summary.csv")
  save_table(res$missing_summary, "missing_values_summary.csv")
  save_table(res$ranges,          "range_validation.csv")
  save_table(res$outliers$summary, "outlier_summary.csv")
  if (nrow(res$outliers$flagged_rows) > 0) save_table(res$outliers$flagged_rows, "outlier_records.csv")
  if (nrow(res$duplicates$removed) > 0)    save_table(res$duplicates$removed, "removed_duplicate_records.csv")
  if (nrow(res$imputation_log) > 0)        save_table(res$imputation_log, "imputation_log.csv")

  invisible(res)
}

if (isTRUE(getOption("customerseg.autorun", TRUE))) run_data_cleaning()
