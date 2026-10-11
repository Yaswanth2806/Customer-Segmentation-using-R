# ==============================================================================
# 06_customer_clustering.R
# ------------------------------------------------------------------------------
# Purpose : Fit the final k-means model on the standardised features, assign a
#           cluster to every customer, evaluate it, and visualise it with PCA.
#
# Notes   : * K comes from step 05 (or CONFIG$k_final if you override it).
#           * Cluster IDs are re-numbered so Cluster 1 has the highest average
#             spending score (k-means numbering is otherwise arbitrary).
#           * Customers are matched to cluster labels by row position AND the
#             CustomerID order is verified, so labels cannot be mixed up.
#
# Inputs  : data/processed/customers_clean.csv, features_scaled.csv,
#           outputs/tables/cluster_evaluation.csv
# Outputs : data/processed/segmented_customers.csv  (customer data + Cluster)
#           data/processed/kmeans_model.rds
#           outputs/tables/model_evaluation.csv, cluster_silhouette_widths.csv
#           outputs/plots/{cluster_pca, cluster_income_vs_spending,
#                          final_silhouette}.png
# Usage   : Rscript R/06_customer_clustering.R   (from the project root)
# ==============================================================================

if (!exists("find_project_root", mode = "function")) {
  .f <- c("R/01_data_loading.R", "01_data_loading.R")
  .f <- .f[file.exists(.f)][1]
  if (is.na(.f)) stop("Run this script from the project root (the folder containing run_project.R).", call. = FALSE)
  local({ op <- options(customerseg.autorun = FALSE); on.exit(options(op)); source(.f) })
}
if (!exists("fit_kmeans", mode = "function")) source_project_script("05_optimal_clusters.R")

#' Re-number k-means clusters so Cluster 1 = highest mean spending score.
relabel_clusters <- function(cluster, spending_score) {
  if (length(cluster) != length(spending_score)) {
    stop("`cluster` and `spending_score` must have the same length.", call. = FALSE)
  }
  means <- tapply(spending_score, cluster, mean)
  ord   <- as.integer(names(means)[order(-means)])
  match(cluster, ord)
}

#' Determine K: explicit argument > CONFIG$k_final > evaluation table from step 05.
determine_k <- function(k = NULL) {
  if (!is.null(k)) return(as.integer(k))
  path <- project_path("outputs", "tables", "cluster_evaluation.csv")
  if (!file.exists(path)) {
    stop("outputs/tables/cluster_evaluation.csv not found. Run R/05_optimal_clusters.R first, ",
         "or pass k explicitly to run_customer_clustering(k = ...).", call. = FALSE)
  }
  ev <- utils::read.csv(path, stringsAsFactors = FALSE)
  as.integer(ev$K[as.logical(ev$Selected)][1])
}

plot_clusters_pca <- function(scaled, cluster) {
  pca <- stats::prcomp(scaled)
  var_exp <- summary(pca)$importance[2, 1:2] * 100
  scores <- data.frame(PC1 = pca$x[, 1], PC2 = pca$x[, 2], Cluster = factor(cluster))
  ggplot2::ggplot(scores, ggplot2::aes(x = PC1, y = PC2, colour = Cluster)) +
    ggplot2::geom_point(size = 2.4, alpha = 0.85) +
    ggplot2::scale_colour_viridis_d(end = 0.9) +
    ggplot2::labs(title = "Customer Segments in Principal Component Space",
                  subtitle = sprintf("PC1 explains %.1f%% and PC2 %.1f%% of the variance in the standardised features",
                                     var_exp[1], var_exp[2]),
                  x = "Principal component 1", y = "Principal component 2",
                  caption = dataset_caption()) +
    theme_seg()
}

plot_clusters_income_spending <- function(seg) {
  ggplot2::ggplot(seg, ggplot2::aes(x = Annual_Income, y = Spending_Score, colour = factor(Cluster))) +
    ggplot2::geom_point(size = 2.4, alpha = 0.85) +
    ggplot2::scale_colour_viridis_d(end = 0.9, name = "Cluster") +
    ggplot2::labs(title = "Customer Segments: Annual Income vs. Spending Score",
                  x = "Annual income (thousand $)", y = "Spending score (1-100)",
                  caption = dataset_caption()) +
    theme_seg()
}

run_customer_clustering <- function(k = NULL) {
  message("== Step 6: Customer clustering ==")
  ensure_project_dirs()
  df     <- load_clean_data()
  scaled <- load_scaled_features()

  if (nrow(df) != nrow(scaled) || !identical(as.character(df$CustomerID), rownames(scaled))) {
    stop("Customer order in customers_clean.csv and features_scaled.csv does not match. ",
         "Re-run R/04_feature_engineering.R.", call. = FALSE)
  }
  k <- determine_k(k)
  message("  Fitting k-means with K = ", k, " (seed = ", CONFIG$seed, ", nstart = ", CONFIG$nstart, ")")

  km      <- fit_kmeans(scaled, k)
  cluster <- relabel_clusters(km$cluster, df$Spending_Score)

  seg <- as.data.frame(df)
  seg$Cluster <- cluster
  readr::write_csv(seg, project_path("data", "processed", "segmented_customers.csv"))
  message("  saved data  : data/processed/segmented_customers.csv")

  sil <- cluster::silhouette(cluster, stats::dist(scaled))
  sil_by_cluster <- stats::aggregate(sil_width ~ cluster,
                                     data = data.frame(cluster = sil[, "cluster"], sil_width = sil[, "sil_width"]),
                                     FUN = mean)
  model_eval <- data.frame(
    Metric = c("K (clusters)", "Customers", "Random seed", "nstart",
               "Average silhouette width", "Between-SS / Total-SS (%)"),
    Value  = c(k, nrow(seg), CONFIG$seed, CONFIG$nstart,
               round(mean(sil[, "sil_width"]), 4), round(100 * km$betweenss / km$totss, 2)),
    stringsAsFactors = FALSE
  )
  save_table(model_eval, "model_evaluation.csv")
  save_table(data.frame(Cluster = as.integer(sil_by_cluster$cluster),
                        Customers = as.integer(table(cluster)[as.character(sil_by_cluster$cluster)]),
                        Avg_Silhouette = round(sil_by_cluster$sil_width, 4)),
             "cluster_silhouette_widths.csv")

  saveRDS(list(kmeans = km, k = k, seed = CONFIG$seed, features = CONFIG$features),
          project_path("data", "processed", "kmeans_model.rds"))

  save_plot(plot_clusters_pca(scaled, cluster), "cluster_pca.png")
  save_plot(plot_clusters_income_spending(seg), "cluster_income_vs_spending.png")

  # factoextra silhouette plot (wrapped so a plotting hiccup never stops the pipeline)
  tryCatch({
    p <- factoextra::fviz_silhouette(sil, print.summary = FALSE, ggtheme = theme_seg())
    save_plot(p + ggplot2::labs(title = "Final Model: Silhouette Width per Customer",
                                caption = dataset_caption()),
              "final_silhouette.png")
  }, error = function(e) warning("Could not create the factoextra silhouette plot: ", conditionMessage(e), call. = FALSE))

  message(sprintf("  Average silhouette width: %.3f", mean(sil[, "sil_width"])))
  invisible(list(segmented = seg, model = km, silhouette = sil, k = k))
}

if (isTRUE(getOption("customerseg.autorun", TRUE))) run_customer_clustering()
