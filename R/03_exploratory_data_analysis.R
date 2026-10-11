# ==============================================================================
# 03_exploratory_data_analysis.R
# ------------------------------------------------------------------------------
# Purpose : Explore the cleaned customer data with ggplot2 / corrplot.
# Inputs  : data/processed/customers_clean.csv
# Outputs : outputs/plots/{age_distribution, income_distribution,
#             spending_distribution, gender_distribution, income_vs_spending,
#             age_vs_spending, correlation_matrix, boxplots_outliers}.png
#           outputs/tables/{summary_statistics, gender_summary,
#             correlation_matrix, customer_profile_summary}.csv
# Usage   : Rscript R/03_exploratory_data_analysis.R   (from the project root)
# ==============================================================================

if (!exists("find_project_root", mode = "function")) {
  .f <- c("R/01_data_loading.R", "01_data_loading.R")
  .f <- .f[file.exists(.f)][1]
  if (is.na(.f)) stop("Run this script from the project root (the folder containing run_project.R).", call. = FALSE)
  local({ op <- options(customerseg.autorun = FALSE); on.exit(options(op)); source(.f) })
}

PLOT_FILL <- "#2C7FB8"

# ------------------------------------------------------------------------------
# Plot builders (each returns a ggplot object)
# ------------------------------------------------------------------------------
plot_distribution <- function(df, var, title, xlab, binwidth) {
  ggplot2::ggplot(df, ggplot2::aes(x = !!rlang::sym(var))) +
    ggplot2::geom_histogram(binwidth = binwidth, fill = PLOT_FILL, colour = "white") +
    ggplot2::geom_vline(xintercept = mean(df[[var]]), linetype = "dashed", colour = "firebrick") +
    ggplot2::labs(title = title,
                  subtitle = sprintf("Dashed line = mean (%.1f); n = %d customers", mean(df[[var]]), nrow(df)),
                  x = xlab, y = "Number of customers", caption = dataset_caption()) +
    theme_seg()
}

plot_gender <- function(df) {
  counts <- dplyr::count(df, Gender, name = "n")
  counts$pct <- round(100 * counts$n / sum(counts$n), 1)
  ggplot2::ggplot(counts, ggplot2::aes(x = Gender, y = n, fill = Gender)) +
    ggplot2::geom_col(width = 0.6, show.legend = FALSE) +
    ggplot2::geom_text(ggplot2::aes(label = paste0(n, " (", pct, "%)")), vjust = -0.4) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.12))) +
    ggplot2::scale_fill_viridis_d(end = 0.8) +
    ggplot2::labs(title = "Gender Distribution of Customers",
                  x = "Gender", y = "Number of customers", caption = dataset_caption()) +
    theme_seg()
}

plot_income_vs_spending <- function(df) {
  ggplot2::ggplot(df, ggplot2::aes(x = Annual_Income, y = Spending_Score, colour = Gender)) +
    ggplot2::geom_point(alpha = 0.75, size = 2.2) +
    ggplot2::scale_colour_viridis_d(end = 0.8) +
    ggplot2::labs(title = "Annual Income vs. Spending Score",
                  subtitle = "Visible groupings motivate the clustering step",
                  x = "Annual income (thousand $)", y = "Spending score (1-100)",
                  caption = dataset_caption()) +
    theme_seg()
}

plot_age_vs_spending <- function(df) {
  ggplot2::ggplot(df, ggplot2::aes(x = Age, y = Spending_Score)) +
    ggplot2::geom_point(alpha = 0.7, size = 2.2, colour = PLOT_FILL) +
    ggplot2::geom_smooth(method = "lm", formula = y ~ x, se = TRUE, colour = "firebrick", linewidth = 0.8) +
    ggplot2::labs(title = "Age vs. Spending Score",
                  subtitle = "Red line = linear trend with 95% confidence band",
                  x = "Age (years)", y = "Spending score (1-100)", caption = dataset_caption()) +
    theme_seg()
}

plot_boxplots <- function(df) {
  long <- tidyr::pivot_longer(df, cols = dplyr::all_of(CONFIG$features),
                              names_to = "Variable", values_to = "Value")
  ggplot2::ggplot(long, ggplot2::aes(x = Variable, y = Value)) +
    ggplot2::geom_boxplot(fill = PLOT_FILL, alpha = 0.6, outlier.colour = "firebrick", outlier.size = 2) +
    ggplot2::facet_wrap(~Variable, scales = "free", nrow = 1) +
    ggplot2::labs(title = "Boxplots of Clustering Features",
                  subtitle = "Red points are outliers by the 1.5 x IQR rule (kept in the analysis)",
                  x = NULL, y = "Value", caption = dataset_caption()) +
    theme_seg() +
    ggplot2::theme(axis.text.x = ggplot2::element_blank(), axis.ticks.x = ggplot2::element_blank())
}

#' Save a correlation heat-map using corrplot (base graphics device).
save_correlation_plot <- function(cor_matrix, filename = "correlation_matrix.png") {
  path <- project_path("outputs", "plots", filename)
  grDevices::png(path, width = 1600, height = 1400, res = 220, bg = "white")
  on.exit(grDevices::dev.off(), add = TRUE)
  corrplot::corrplot(cor_matrix, method = "color", type = "upper", addCoef.col = "black",
                     tl.col = "black", tl.srt = 35, number.cex = 1,
                     title = "Correlation of Numerical Variables", mar = c(0, 0, 2, 0))
  message("  saved plot  : outputs/plots/", filename)
  invisible(path)
}

# ------------------------------------------------------------------------------
# Summary tables
# ------------------------------------------------------------------------------
summarise_numeric <- function(df, cols = CONFIG$features) {
  res <- lapply(cols, function(col) {
    x <- df[[col]]
    data.frame(Variable = col, Mean = round(mean(x), 2), Median = stats::median(x),
               SD = round(stats::sd(x), 2), Min = min(x),
               Q1 = unname(stats::quantile(x, 0.25)), Q3 = unname(stats::quantile(x, 0.75)),
               Max = max(x), stringsAsFactors = FALSE)
  })
  do.call(rbind, res)
}

build_customer_profile <- function(df) {
  by_gender <- df |>
    dplyr::group_by(Gender) |>
    dplyr::summarise(Customers = dplyr::n(),
                     Avg_Age = round(mean(Age), 1),
                     Avg_Annual_Income = round(mean(Annual_Income), 1),
                     Avg_Spending_Score = round(mean(Spending_Score), 1),
                     .groups = "drop")
  overall <- data.frame(Gender = "All customers", Customers = nrow(df),
                        Avg_Age = round(mean(df$Age), 1),
                        Avg_Annual_Income = round(mean(df$Annual_Income), 1),
                        Avg_Spending_Score = round(mean(df$Spending_Score), 1),
                        stringsAsFactors = FALSE)
  rbind(overall, as.data.frame(by_gender))
}

# ------------------------------------------------------------------------------
# Step runner
# ------------------------------------------------------------------------------
run_eda <- function(df = NULL) {
  message("== Step 3: Exploratory data analysis ==")
  ensure_project_dirs()
  if (is.null(df)) df <- load_clean_data()

  save_plot(plot_distribution(df, "Age", "Customer Age Distribution", "Age (years)", 5),
            "age_distribution.png")
  save_plot(plot_distribution(df, "Annual_Income", "Annual Income Distribution",
                              "Annual income (thousand $)", 10),
            "income_distribution.png")
  save_plot(plot_distribution(df, "Spending_Score", "Spending Score Distribution",
                              "Spending score (1-100)", 10),
            "spending_distribution.png")
  save_plot(plot_gender(df), "gender_distribution.png", width = 6)
  save_plot(plot_income_vs_spending(df), "income_vs_spending.png")
  save_plot(plot_age_vs_spending(df), "age_vs_spending.png")
  save_plot(plot_boxplots(df), "boxplots_outliers.png", width = 10, height = 5)

  cor_matrix <- stats::cor(as.data.frame(df)[, CONFIG$features], use = "pairwise.complete.obs")
  save_correlation_plot(cor_matrix)

  save_table(summarise_numeric(df), "summary_statistics.csv")
  save_table(as.data.frame(dplyr::count(df, Gender, name = "Customers")) |>
               transform(Percent = round(100 * Customers / sum(Customers), 1)),
             "gender_summary.csv")
  save_table(data.frame(Variable = rownames(cor_matrix), round(cor_matrix, 3), row.names = NULL),
             "correlation_matrix.csv")
  save_table(build_customer_profile(df), "customer_profile_summary.csv")

  invisible(list(summary = summarise_numeric(df), correlation = cor_matrix))
}

if (isTRUE(getOption("customerseg.autorun", TRUE))) run_eda()
