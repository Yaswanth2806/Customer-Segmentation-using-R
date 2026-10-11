# ==============================================================================
# run_project.R - run the complete customer segmentation pipeline
# ------------------------------------------------------------------------------
# Usage (from the project root):
#   Rscript run_project.R                   # pipeline + try to render the report
#   Rscript run_project.R --no-report       # pipeline only
#   Rscript run_project.R --run-tests       # also run the automated tests first
#
# In RStudio: open the project folder (or setwd() to it) and source this file.
#
# Steps: 1 loading -> 2 cleaning -> 3 EDA -> 4 feature engineering ->
#        5 cluster evaluation -> 6 final clustering -> 7 profiling ->
#        8 business insights -> (optional) report rendering
# ==============================================================================

args <- if (interactive()) character() else commandArgs(trailingOnly = TRUE)
render_report <- !("--no-report" %in% args)
run_tests     <- "--run-tests" %in% args

# --- 0. Environment checks ----------------------------------------------------
if (!file.exists("run_project.R") || !file.exists("R/01_data_loading.R")) {
  stop("Please run this script from the project root folder (the one containing run_project.R). ",
       "In RStudio use setwd('path/to/customer-segmentation-r').", call. = FALSE)
}
if (getRversion() < "4.1.0") {
  stop("R >= 4.1.0 is required (found ", as.character(getRversion()), "). See requirements.md.", call. = FALSE)
}

options(customerseg.autorun = FALSE)   # load functions only; this script controls execution
source("R/01_data_loading.R")
check_dependencies()                   # stops with an install.packages() hint if needed

for (script in c("02_data_cleaning.R", "03_exploratory_data_analysis.R", "04_feature_engineering.R",
                 "05_optimal_clusters.R", "06_customer_clustering.R", "07_segment_profiling.R",
                 "08_business_insights.R")) {
  source(file.path("R", script))
}
ensure_project_dirs()                  # outputs/ and data/processed/ are created automatically

# --- Optional: automated tests --------------------------------------------------
if (run_tests) {
  message("== Running automated tests ==")
  for (t in c("tests/test_data_cleaning.R", "tests/test_clustering.R")) source(t)
  options(customerseg.autorun = FALSE)
}

# --- Pipeline ------------------------------------------------------------------
run_step <- function(label, expr) {
  t0 <- Sys.time()
  result <- tryCatch(expr, error = function(e) {
    stop(sprintf("Pipeline stopped at '%s': %s", label, conditionMessage(e)), call. = FALSE)
  })
  message(sprintf("   done in %.1f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  invisible(result)
}

message("Customer Segmentation Pipeline (seed = ", CONFIG$seed, ")\n")
loaded <- run_step("data loading",            run_data_loading())
cleaned <- run_step("data cleaning",          run_data_cleaning(loaded$data))
run_step("exploratory data analysis",         run_eda(cleaned$data))
run_step("feature engineering",               run_feature_engineering(cleaned$data))
run_step("optimal cluster evaluation",        run_optimal_clusters())
run_step("final clustering",                  run_customer_clustering())
run_step("segment profiling",                 run_segment_profiling())
run_step("business insights",                 run_business_insights())

# --- Optional: render the R Markdown report ---------------------------------------
if (render_report) {
  message("== Rendering report ==")
  if (all(vapply(REPORT_PACKAGES, requireNamespace, logical(1), quietly = TRUE)) &&
      rmarkdown::pandoc_available()) {
    out <- tryCatch(
      rmarkdown::render(project_path("reports", "customer_segmentation_report.Rmd"),
                        output_dir = project_path("outputs", "reports"),
                        quiet = TRUE, envir = new.env()),
      error = function(e) { warning("Report rendering failed: ", conditionMessage(e), call. = FALSE); NULL })
    if (!is.null(out)) message("  saved report: outputs/reports/", basename(out))
  } else {
    warning("Skipping report: install 'rmarkdown'/'knitr' and Pandoc (bundled with RStudio) to render it.",
            call. = FALSE)
  }
}

message("\nPipeline finished. Results are in data/processed/ and outputs/.")
