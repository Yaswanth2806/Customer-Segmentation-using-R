# ==============================================================================
# 04_feature_engineering.R
# ------------------------------------------------------------------------------
# Purpose : Select the numeric clustering features and standardise them with
#           scale() so no variable dominates the distance calculation.
#
# Rules enforced here:
#   * identifiers (CustomerID) and categorical columns (Gender) are NEVER passed
#     to k-means;
#   * the same feature columns (CONFIG$features) are used for scaling,
#     evaluation and the final model;
#   * the original customer data stays in customers_clean.csv for interpretation.
#
# Inputs  : data/processed/customers_clean.csv
# Outputs : data/processed/features_scaled.csv   (CustomerID + *_z columns)
#           outputs/tables/scaling_parameters.csv (mean and SD used by scale())
# Usage   : Rscript R/04_feature_engineering.R   (from the project root)
# ==============================================================================

if (!exists("find_project_root", mode = "function")) {
  .f <- c("R/01_data_loading.R", "01_data_loading.R")
  .f <- .f[file.exists(.f)][1]
  if (is.na(.f)) stop("Run this script from the project root (the folder containing run_project.R).", call. = FALSE)
  local({ op <- options(customerseg.autorun = FALSE); on.exit(options(op)); source(.f) })
}

#' Extract the clustering features as a numeric data frame, with validation.
select_features <- function(df, features = CONFIG$features) {
  if (!is.data.frame(df)) stop("`df` must be a data frame.", call. = FALSE)
  forbidden <- intersect(features, c("CustomerID", "Gender", "Cluster", "Segment"))
  if (length(forbidden) > 0) {
    stop("Identifiers / categorical / label columns cannot be clustering features: ",
         paste(forbidden, collapse = ", "), call. = FALSE)
  }
  missing_cols <- setdiff(features, names(df))
  if (length(missing_cols) > 0) {
    stop("Feature column(s) not found: ", paste(missing_cols, collapse = ", "), call. = FALSE)
  }
  feat <- as.data.frame(df)[, features, drop = FALSE]
  if (!all(vapply(feat, is.numeric, logical(1)))) {
    stop("All clustering features must be numeric.", call. = FALSE)
  }
  if (anyNA(feat)) {
    stop("Clustering features contain missing values; run the cleaning step first.", call. = FALSE)
  }
  feat
}

#' Standardise features to mean 0 and SD 1 (z-scores) using base scale().
scale_features <- function(feature_df) {
  sds <- vapply(feature_df, stats::sd, numeric(1))
  if (any(is.na(sds)) || any(sds == 0)) {
    stop("Cannot scale: feature(s) with zero variance or too few rows: ",
         paste(names(sds)[is.na(sds) | sds == 0], collapse = ", "), call. = FALSE)
  }
  scaled <- scale(as.matrix(feature_df))
  list(
    scaled = matrix(scaled, nrow = nrow(scaled), dimnames = list(NULL, colnames(feature_df))),
    center = attr(scaled, "scaled:center"),
    scale  = attr(scaled, "scaled:scale")
  )
}

run_feature_engineering <- function(df = NULL) {
  message("== Step 4: Feature engineering ==")
  ensure_project_dirs()
  if (is.null(df)) df <- load_clean_data()

  feat   <- select_features(df)
  scaled <- scale_features(feat)
  message("  Clustering features : ", paste(CONFIG$features, collapse = ", "))
  message("  Excluded from model : CustomerID (identifier), Gender (categorical)")

  out <- data.frame(CustomerID = df$CustomerID, scaled$scaled, check.names = FALSE)
  names(out) <- c("CustomerID", paste0(CONFIG$features, "_z"))
  readr::write_csv(out, project_path("data", "processed", "features_scaled.csv"))
  message("  saved data  : data/processed/features_scaled.csv")

  params <- data.frame(Feature = CONFIG$features, Mean = round(unname(scaled$center), 4),
                       SD = round(unname(scaled$scale), 4), stringsAsFactors = FALSE)
  save_table(params, "scaling_parameters.csv")
  invisible(list(features = feat, scaled = scaled))
}

if (isTRUE(getOption("customerseg.autorun", TRUE))) run_feature_engineering()
