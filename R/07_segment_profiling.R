# ==============================================================================
# 07_segment_profiling.R
# ------------------------------------------------------------------------------
# Purpose : Profile each cluster and give it a business-friendly label.
#
# Labelling is DATA-DRIVEN. For every cluster we compare its average income and
# spending score with the overall customer base using z-scores
# (cluster mean - overall mean) / overall SD, then classify each as
# High (z >= +0.5), Low (z <= -0.5) or Medium:
#
#   spending High  + income High          -> High-Value Customers
#   spending High  + income Medium/Low    -> Potential Loyal Customers
#   spending Medium (any income)          -> Average Customers
#   spending Low   + income High          -> Customers Requiring Further Engagement
#   spending Low   + income Medium/Low    -> Low-Spending Customers
#
# If two clusters receive the same label, "(Cluster N)" is appended so every
# segment name stays unique. Labels are descriptions of the observed averages,
# not assumptions - always review them against the profile table.
#
# Inputs  : data/processed/segmented_customers.csv
# Outputs : data/processed/segmented_customers.csv (adds a Segment column)
#           outputs/tables/{segment_profiles, gender_by_segment}.csv
#           outputs/reports/segment_summary.md
#           outputs/plots/{segment_sizes, segment_average_metrics,
#                          segment_income_vs_spending}.png
# Usage   : Rscript R/07_segment_profiling.R   (from the project root)
# ==============================================================================

if (!exists("find_project_root", mode = "function")) {
  .f <- c("R/01_data_loading.R", "01_data_loading.R")
  .f <- .f[file.exists(.f)][1]
  if (is.na(.f)) stop("Run this script from the project root (the folder containing run_project.R).", call. = FALSE)
  local({ op <- options(customerseg.autorun = FALSE); on.exit(options(op)); source(.f) })
}

Z_THRESHOLD <- 0.5

level_from_z <- function(z, threshold = Z_THRESHOLD) {
  ifelse(z >= threshold, "High", ifelse(z <= -threshold, "Low", "Medium"))
}

classify_segment <- function(income_level, spending_level) {
  if (spending_level == "High") {
    if (income_level == "High") "High-Value Customers" else "Potential Loyal Customers"
  } else if (spending_level == "Low") {
    if (income_level == "High") "Customers Requiring Further Engagement" else "Low-Spending Customers"
  } else {
    "Average Customers"
  }
}

#' Build the segment profile table (counts, shares, averages, labels, evidence).
profile_segments <- function(seg) {
  needed <- c("Cluster", "Age", "Annual_Income", "Spending_Score")
  if (!all(needed %in% names(seg))) {
    stop("`seg` must contain columns: ", paste(needed, collapse = ", "), call. = FALSE)
  }
  n_total <- nrow(seg)
  prof <- seg |>
    dplyr::group_by(Cluster) |>
    dplyr::summarise(Customers = dplyr::n(),
                     Avg_Age = mean(Age),
                     Avg_Annual_Income = mean(Annual_Income),
                     Avg_Spending_Score = mean(Spending_Score),
                     .groups = "drop") |>
    dplyr::arrange(Cluster) |>
    as.data.frame()

  prof$Percent <- 100 * prof$Customers / n_total
  prof$Income_z   <- (prof$Avg_Annual_Income  - mean(seg$Annual_Income))  / stats::sd(seg$Annual_Income)
  prof$Spending_z <- (prof$Avg_Spending_Score - mean(seg$Spending_Score)) / stats::sd(seg$Spending_Score)
  prof$Income_Level   <- level_from_z(prof$Income_z)
  prof$Spending_Level <- level_from_z(prof$Spending_z)

  prof$Segment_Type <- mapply(classify_segment, prof$Income_Level, prof$Spending_Level, USE.NAMES = FALSE)
  dup <- duplicated(prof$Segment_Type) | duplicated(prof$Segment_Type, fromLast = TRUE)
  prof$Segment <- ifelse(dup, paste0(prof$Segment_Type, " (Cluster ", prof$Cluster, ")"), prof$Segment_Type)
  prof$Rationale <- sprintf("Income %s (z = %+.2f) and spending %s (z = %+.2f) relative to all customers",
                            prof$Income_Level, prof$Income_z, prof$Spending_Level, prof$Spending_z)

  prof <- prof[, c("Cluster", "Segment", "Segment_Type", "Customers", "Percent", "Avg_Age",
                   "Avg_Annual_Income", "Avg_Spending_Score", "Income_Level", "Spending_Level",
                   "Income_z", "Spending_z", "Rationale")]
  num_cols <- c("Percent", "Avg_Age", "Avg_Annual_Income", "Avg_Spending_Score")
  prof[num_cols] <- lapply(prof[num_cols], round, 1)
  prof[c("Income_z", "Spending_z")] <- lapply(prof[c("Income_z", "Spending_z")], round, 2)
  prof
}

plot_segment_sizes <- function(prof) {
  prof$Label <- paste0(prof$Customers, " (", prof$Percent, "%)")
  ggplot2::ggplot(prof, ggplot2::aes(x = stats::reorder(Segment, Customers), y = Customers, fill = Segment)) +
    ggplot2::geom_col(show.legend = FALSE, width = 0.7) +
    ggplot2::geom_text(ggplot2::aes(label = Label), hjust = -0.1) +
    ggplot2::coord_flip() +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.25))) +
    ggplot2::scale_fill_viridis_d(end = 0.9) +
    ggplot2::labs(title = "Number of Customers per Segment", x = NULL,
                  y = "Customers (share of customer base)", caption = dataset_caption()) +
    theme_seg()
}

plot_segment_metrics <- function(prof) {
  long <- tidyr::pivot_longer(prof[, c("Segment", "Avg_Age", "Avg_Annual_Income", "Avg_Spending_Score")],
                              cols = -Segment, names_to = "Metric", values_to = "Value")
  long$Metric <- factor(long$Metric,
                        levels = c("Avg_Age", "Avg_Annual_Income", "Avg_Spending_Score"),
                        labels = c("Average age (years)", "Average annual income (k$)", "Average spending score"))
  long$Segment <- factor(long$Segment, levels = rev(prof$Segment))  # keep cluster order in every panel
  ggplot2::ggplot(long, ggplot2::aes(x = Segment, y = Value, fill = Segment)) +
    ggplot2::geom_col(show.legend = FALSE, width = 0.7) +
    ggplot2::geom_text(ggplot2::aes(label = Value), hjust = -0.1, size = 3.2) +
    ggplot2::coord_flip() +
    ggplot2::facet_wrap(~Metric, scales = "free") +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.25))) +
    ggplot2::scale_fill_viridis_d(end = 0.9) +
    ggplot2::labs(title = "Segment Profiles: Average Age, Income and Spending Score",
                  x = NULL, y = NULL, caption = dataset_caption()) +
    theme_seg()
}

plot_segments_scatter <- function(seg, prof) {
  ggplot2::ggplot(seg, ggplot2::aes(x = Annual_Income, y = Spending_Score, colour = Segment)) +
    ggplot2::geom_point(size = 2.3, alpha = 0.8) +
    ggplot2::geom_point(data = prof, ggplot2::aes(x = Avg_Annual_Income, y = Avg_Spending_Score),
                        colour = "black", shape = 4, size = 4, stroke = 1.3, inherit.aes = FALSE) +
    ggplot2::scale_colour_viridis_d(end = 0.9) +
    ggplot2::guides(colour = ggplot2::guide_legend(ncol = 2)) +
    ggplot2::labs(title = "Customer Segments by Income and Spending",
                  subtitle = "Black crosses mark segment averages",
                  x = "Annual income (thousand $)", y = "Spending score (1-100)",
                  colour = NULL, caption = dataset_caption()) +
    theme_seg()
}

run_segment_profiling <- function() {
  message("== Step 7: Segment profiling ==")
  ensure_project_dirs()
  path <- project_path("data", "processed", "segmented_customers.csv")
  if (!file.exists(path)) {
    stop("segmented_customers.csv not found. Run R/06_customer_clustering.R first.", call. = FALSE)
  }
  seg <- as.data.frame(readr::read_csv(path, show_col_types = FALSE, progress = FALSE))
  seg$Segment <- NULL  # allow safe re-runs

  prof <- profile_segments(seg)
  seg  <- merge(seg, prof[, c("Cluster", "Segment")], by = "Cluster", sort = FALSE)
  seg  <- seg[order(seg$CustomerID), c("CustomerID", "Gender", "Age", "Annual_Income",
                                       "Spending_Score", "Cluster", "Segment")]
  readr::write_csv(seg, path)
  message("  updated data: data/processed/segmented_customers.csv (added Segment column)")

  save_table(prof, "segment_profiles.csv")
  gender <- as.data.frame(dplyr::count(seg, Segment, Gender, name = "Customers"))
  gender$Percent_Within_Segment <- round(100 * gender$Customers / ave(gender$Customers, gender$Segment, FUN = sum), 1)
  save_table(gender, "gender_by_segment.csv")

  md_cols <- c("Cluster", "Segment", "Customers", "Percent", "Avg_Age", "Avg_Annual_Income", "Avg_Spending_Score")
  writeLines(c("# Segment Summary", "",
               paste0("_Generated by R/07_segment_profiling.R on ", format(Sys.Date()), "._"), "",
               df_to_markdown(prof[, md_cols]), "",
               "Avg_Annual_Income is in thousand dollars; Avg_Spending_Score is on a 1-100 scale."),
             project_path("outputs", "reports", "segment_summary.md"))
  message("  saved report: outputs/reports/segment_summary.md")

  save_plot(plot_segment_sizes(prof), "segment_sizes.png")
  save_plot(plot_segment_metrics(prof), "segment_average_metrics.png", width = 11, height = 5)
  save_plot(plot_segments_scatter(seg, prof), "segment_income_vs_spending.png")

  print(prof[, md_cols], row.names = FALSE)
  invisible(list(profile = prof, segmented = seg))
}

if (isTRUE(getOption("customerseg.autorun", TRUE))) run_segment_profiling()
