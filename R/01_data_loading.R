# ==============================================================================
# 01_data_loading.R
# ------------------------------------------------------------------------------
# Purpose : Project configuration, path helpers, shared utilities, and safe
#           loading of the raw customer CSV.
# Inputs  : data/raw/Mall_Customers.csv       (preferred - download it, see data/README.md)
#           data/raw/synthetic_customers.csv  (fallback - clearly SYNTHETIC)
# Outputs : outputs/tables/dataset_info.csv
# Usage   : Rscript R/01_data_loading.R        (run from the project root)
#           or source("R/01_data_loading.R") and call run_data_loading()
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Configuration (single source of truth for the whole pipeline)
# ------------------------------------------------------------------------------
CONFIG <- list(
  seed              = 42L,                       # fixed seed -> reproducible results
  required_columns  = c("CustomerID", "Gender", "Age", "Annual_Income", "Spending_Score"),
  features          = c("Age", "Annual_Income", "Spending_Score"),  # used for clustering
  k_range           = 2:10,                      # candidate numbers of clusters
  k_min_recommended = 3L,                        # K = 2 is rarely actionable for marketing
  silhouette_tol    = 0.03,                      # parsimony tolerance (see 05_optimal_clusters.R)
  k_final           = NA_integer_,               # set e.g. 5L to override the recommended K
  nstart            = 50L,                       # random restarts for k-means
  missing_threshold = 0.05,                      # max share of missing values we will impute
  iqr_multiplier    = 1.5,                       # IQR rule for outlier flagging
  valid_ranges      = list(                      # plausibility ranges (flag, never delete)
    Age            = c(10, 100),
    Annual_Income  = c(0, 1000),                 # thousands of dollars
    Spending_Score = c(1, 100)
  )
)

# Packages needed to run the analysis pipeline (R Markdown packages are optional
# and only checked when the report is rendered).
REQUIRED_PACKAGES <- c("dplyr", "tidyr", "readr", "tibble", "ggplot2", "rlang",
                       "scales", "corrplot", "cluster", "factoextra")
REPORT_PACKAGES   <- c("rmarkdown", "knitr")

# ------------------------------------------------------------------------------
# 2. Dependency checking
# ------------------------------------------------------------------------------
#' Stop with an actionable message if required packages are not installed.
check_dependencies <- function(pkgs = REQUIRED_PACKAGES) {
  installed <- vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)
  if (!all(installed)) {
    missing <- pkgs[!installed]
    stop(
      "Missing R package(s): ", paste(missing, collapse = ", "), ".\n",
      "Install them with:\n  install.packages(c(",
      paste0('"', missing, '"', collapse = ", "), "))\n",
      "or restore the pinned environment with renv::restore() (see README).",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# 3. Project-relative paths (no hard-coded absolute paths anywhere)
# ------------------------------------------------------------------------------
#' Walk up from `start` until the folder containing run_project.R is found.
find_project_root <- function(start = getwd()) {
  dir <- normalizePath(start, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(dir, "run_project.R")) &&
        file.exists(file.path(dir, "DESCRIPTION"))) {
      return(dir)
    }
    parent <- dirname(dir)
    if (identical(parent, dir)) {
      stop("Could not locate the project root (a folder containing run_project.R). ",
           "Set your working directory to the project folder, e.g. setwd('customer-segmentation-r').",
           call. = FALSE)
    }
    dir <- parent
  }
}

#' Build a path relative to the project root.
project_path <- function(...) file.path(find_project_root(), ...)

#' Create all data/output directories (safe to call repeatedly).
ensure_project_dirs <- function() {
  dirs <- c("data/raw", "data/processed", "outputs/plots", "outputs/tables", "outputs/reports")
  for (d in dirs) dir.create(project_path(d), recursive = TRUE, showWarnings = FALSE)
  invisible(vapply(dirs, project_path, character(1)))
}

#' Source another pipeline script without triggering its auto-run block.
source_project_script <- function(file) {
  op <- options(customerseg.autorun = FALSE)
  on.exit(options(op), add = TRUE)
  source(project_path("R", file), local = FALSE)
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# 4. Shared output helpers (plots, tables, themes)
# ------------------------------------------------------------------------------
#' Consistent, professional ggplot2 theme used by every chart.
theme_seg <- function(base_size = 12) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.title       = ggplot2::element_text(face = "bold", size = base_size + 3),
      plot.subtitle    = ggplot2::element_text(colour = "grey35"),
      plot.caption     = ggplot2::element_text(colour = "grey45", hjust = 0),
      panel.grid.minor = ggplot2::element_blank(),
      legend.position  = "bottom",
      strip.text       = ggplot2::element_text(face = "bold")
    )
}

#' Caption stating which dataset the chart is based on (so synthetic data is
#' never mistaken for real customers). Returns NULL if info is not yet saved.
dataset_caption <- function() {
  p <- project_path("outputs", "tables", "dataset_info.csv")
  if (!file.exists(p)) return(NULL)
  info <- utils::read.csv(p, stringsAsFactors = FALSE)
  if (identical(info$Dataset_Type[1], "synthetic")) {
    "Data: SYNTHETIC demonstration dataset - not real customer data"
  } else {
    "Data: Mall Customers dataset (Kaggle, CC0)"
  }
}

#' Save a ggplot to outputs/plots/<filename>.
save_plot <- function(plot, filename, width = 8, height = 5, dpi = 150) {
  path <- project_path("outputs", "plots", filename)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(path, plot = plot, width = width, height = height, dpi = dpi, bg = "white")
  message("  saved plot  : outputs/plots/", filename)
  invisible(path)
}

#' Save a data frame to outputs/tables/<filename>.
save_table <- function(df, filename) {
  path <- project_path("outputs", "tables", filename)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(df, path)
  message("  saved table : outputs/tables/", filename)
  invisible(path)
}

#' Convert a data frame to a markdown table (character vector of lines).
df_to_markdown <- function(df) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  header <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep    <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  rows   <- vapply(seq_len(nrow(df)), function(i) {
    paste0("| ", paste(trimws(as.character(unlist(df[i, ]))), collapse = " | "), " |")
  }, character(1))
  c(header, sep, rows)
}

# ------------------------------------------------------------------------------
# 5. Readers for intermediate pipeline files
# ------------------------------------------------------------------------------
#' Read the cleaned dataset produced by 02_data_cleaning.R.
load_clean_data <- function() {
  path <- project_path("data", "processed", "customers_clean.csv")
  if (!file.exists(path)) {
    stop("Cleaned data not found at data/processed/customers_clean.csv. ",
         "Run R/02_data_cleaning.R (or run_project.R) first.", call. = FALSE)
  }
  readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
}

#' Read the standardised feature matrix produced by 04_feature_engineering.R.
#' Returns a numeric matrix with columns named exactly CONFIG$features.
load_scaled_features <- function() {
  path <- project_path("data", "processed", "features_scaled.csv")
  if (!file.exists(path)) {
    stop("Scaled features not found at data/processed/features_scaled.csv. ",
         "Run R/04_feature_engineering.R (or run_project.R) first.", call. = FALSE)
  }
  df <- readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
  z_cols <- paste0(CONFIG$features, "_z")
  if (!all(z_cols %in% names(df))) {
    stop("features_scaled.csv must contain columns: ", paste(z_cols, collapse = ", "),
         ". Re-run R/04_feature_engineering.R.", call. = FALSE)
  }
  mat <- as.matrix(as.data.frame(df)[, z_cols, drop = FALSE])
  colnames(mat) <- CONFIG$features
  rownames(mat) <- df$CustomerID
  mat
}

# ------------------------------------------------------------------------------
# 6. Synthetic fallback dataset (clearly labelled - never presented as real data)
# ------------------------------------------------------------------------------
#' Simulate Mall-Customers-style data from five customer archetypes.
#' Returns raw-format column names so it flows through the same cleaning code.
simulate_customers <- function(n = 200L, seed = CONFIG$seed) {
  set.seed(seed)
  arche <- data.frame(
    share      = c(0.40, 0.19, 0.18, 0.115, 0.115),
    inc_mean   = c(55, 86, 88, 26, 26),  inc_sd   = c(8, 12, 12, 7, 7),
    spend_mean = c(50, 82, 17, 79, 20),  spend_sd = c(8, 8, 8, 9, 8),
    age_mean   = c(43, 33, 41, 25, 45),  age_sd   = c(12, 4, 10, 5, 12)
  )
  counts <- round(arche$share * n)
  counts[1] <- counts[1] + (n - sum(counts))
  grp <- rep(seq_len(nrow(arche)), times = counts)

  income <- round(stats::rnorm(n, arche$inc_mean[grp],   arche$inc_sd[grp]))
  spend  <- round(stats::rnorm(n, arche$spend_mean[grp], arche$spend_sd[grp]))
  age    <- round(stats::rnorm(n, arche$age_mean[grp],   arche$age_sd[grp]))
  income <- pmin(pmax(income, 15), 137)
  spend  <- pmin(pmax(spend, 1), 99)
  age    <- pmin(pmax(age, 18), 70)

  idx <- sample.int(n)  # shuffle so rows are not ordered by archetype
  df <- data.frame(
    CustomerID = seq_len(n),
    Gender     = sample(c("Female", "Male"), n, replace = TRUE, prob = c(0.56, 0.44)),
    Age        = as.integer(age[idx]),
    stringsAsFactors = FALSE
  )
  df[["Annual Income (k$)"]]     <- as.integer(income[idx])
  df[["Spending Score (1-100)"]] <- as.integer(spend[idx])
  df
}

#' Write the synthetic dataset to data/raw/synthetic_customers.csv.
generate_synthetic_customers <- function(path = project_path("data", "raw", "synthetic_customers.csv"),
                                         n = 200L, seed = CONFIG$seed) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(simulate_customers(n, seed), path, row.names = FALSE)
  invisible(path)
}

# ------------------------------------------------------------------------------
# 7. Locating and loading the raw data
# ------------------------------------------------------------------------------
#' Choose the raw dataset: the real Mall Customers file if present, otherwise
#' the synthetic demonstration file (generated if it does not exist).
find_raw_dataset <- function() {
  real <- project_path("data", "raw", "Mall_Customers.csv")
  syn  <- project_path("data", "raw", "synthetic_customers.csv")
  if (file.exists(real)) {
    return(list(path = real, type = "mall_customers",
                note = "Mall Customer Segmentation Data (Kaggle, CC0 public domain)."))
  }
  if (!file.exists(syn)) {
    message("No raw dataset found - generating the SYNTHETIC demonstration dataset.")
    generate_synthetic_customers(syn)
  } else {
    message("Mall_Customers.csv not found in data/raw/ - using the SYNTHETIC demonstration dataset.")
  }
  list(path = syn, type = "synthetic",
       note = "Synthetic demonstration data generated with a fixed seed. Not real customer data.")
}

#' Read a CSV safely with clear error messages. The file is never modified.
load_customer_data <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    stop("`path` must be a single file path string.", call. = FALSE)
  }
  if (!file.exists(path)) {
    stop("Data file not found: ", path, "\n",
         "Place Mall_Customers.csv in data/raw/ (see data/README.md) or remove it ",
         "to use the synthetic demonstration dataset.", call. = FALSE)
  }
  if (!grepl("\\.csv$", path, ignore.case = TRUE)) {
    stop("Expected a .csv file but got: ", basename(path), call. = FALSE)
  }
  df <- tryCatch(
    readr::read_csv(path, show_col_types = FALSE, progress = FALSE),
    error = function(e) stop("Could not read '", basename(path), "': ", conditionMessage(e), call. = FALSE)
  )
  if (nrow(df) == 0L) stop("The file '", basename(path), "' contains no rows.", call. = FALSE)
  df
}

# ------------------------------------------------------------------------------
# 8. Step runner
# ------------------------------------------------------------------------------
run_data_loading <- function() {
  message("== Step 1: Data loading ==")
  ensure_project_dirs()
  ds  <- find_raw_dataset()
  raw <- load_customer_data(ds$path)
  message(sprintf("  Loaded %d rows x %d columns from data/raw/%s", nrow(raw), ncol(raw), basename(ds$path)))
  message("  Columns: ", paste(names(raw), collapse = ", "))
  info <- data.frame(
    Dataset_Type = ds$type,
    Source_File  = basename(ds$path),
    Rows         = nrow(raw),
    Columns      = ncol(raw),
    Note         = ds$note,
    stringsAsFactors = FALSE
  )
  save_table(info, "dataset_info.csv")
  invisible(list(data = raw, info = info))
}

if (isTRUE(getOption("customerseg.autorun", TRUE))) run_data_loading()
