# ==============================================================================
# 05_optimal_clusters.R
# ------------------------------------------------------------------------------
# Purpose : Investigate how many customer segments (K) the data supports using
#           the Elbow Method (within-cluster sum of squares) and Silhouette
#           analysis (cluster separation).
#
# IMPORTANT - choosing K is a judgement call, not a single-metric decision.
#   * The elbow is often ambiguous; the silhouette often keeps creeping upward
#     for larger K even when extra clusters add little business value.
#   * We therefore report BOTH metrics plus a transparent starting rule:
#       recommended K = the smallest K >= CONFIG$k_min_recommended whose average
#       silhouette is within CONFIG$silhouette_tol of the best silhouette.
#   * Always sanity-check the recommendation against the segment profiles
#     (step 07) and override it with CONFIG$k_final if another K is more useful.
#
# Inputs  : data/processed/features_scaled.csv
# Outputs : outputs/tables/cluster_evaluation.csv
#           outputs/plots/{elbow_plot, silhouette_analysis}.png
# Usage   : Rscript R/05_optimal_clusters.R   (from the project root)
# ==============================================================================

if (!exists("find_project_root", mode = "function")) {
  .f <- c("R/01_data_loading.R", "01_data_loading.R")
  .f <- .f[file.exists(.f)][1]
  if (is.na(.f)) stop("Run this script from the project root (the folder containing run_project.R).", call. = FALSE)
  local({ op <- options(customerseg.autorun = FALSE); on.exit(options(op)); source(.f) })
}

#' Fit k-means reproducibly. The seed is set immediately before every fit so the
#' evaluation here and the final model in step 06 give identical results for the
#' same K.
fit_kmeans <- function(scaled, k, seed = CONFIG$seed, nstart = CONFIG$nstart) {
  if (!is.matrix(scaled) || !is.numeric(scaled)) stop("`scaled` must be a numeric matrix.", call. = FALSE)
  if (anyNA(scaled)) stop("`scaled` contains missing values.", call. = FALSE)
  if (!is.numeric(k) || length(k) != 1L || k < 2 || k >= nrow(scaled)) {
    stop("`k` must be a single integer with 2 <= k < number of rows (", nrow(scaled), ").", call. = FALSE)
  }
  set.seed(seed)
  stats::kmeans(scaled, centers = k, nstart = nstart, iter.max = 100)
}

#' Evaluate each K: total within-cluster sum of squares and mean silhouette width.
evaluate_k <- function(scaled, k_range = CONFIG$k_range, seed = CONFIG$seed, nstart = CONFIG$nstart) {
  k_range <- as.integer(k_range)
  if (length(k_range) < 3 || any(k_range < 2)) {
    stop("`k_range` needs at least three values, all >= 2.", call. = FALSE)
  }
  k_range <- k_range[k_range < nrow(scaled)]
  d <- stats::dist(scaled)
  res <- lapply(k_range, function(k) {
    km  <- fit_kmeans(scaled, k, seed, nstart)
    sil <- cluster::silhouette(km$cluster, d)
    data.frame(K = k, WSS = km$tot.withinss, Avg_Silhouette = mean(sil[, "sil_width"]))
  })
  do.call(rbind, res)
}

#' Elbow candidate: the K farthest from the straight line joining the first and
#' last points of the (normalised) WSS curve - a simple, reproducible heuristic.
elbow_k <- function(k, wss) {
  x <- (k - min(k)) / (max(k) - min(k))
  y <- (wss - min(wss)) / (max(wss) - min(wss))
  n <- length(k)
  x1 <- x[1]; y1 <- y[1]; x2 <- x[n]; y2 <- y[n]
  dist_to_line <- abs((x2 - x1) * (y1 - y) - (x1 - x) * (y2 - y1)) / sqrt((x2 - x1)^2 + (y2 - y1)^2)
  k[which.max(dist_to_line)]
}

#' Recommended K using the parsimony rule described at the top of this file.
recommend_k <- function(eval_df, k_min = CONFIG$k_min_recommended, tol = CONFIG$silhouette_tol) {
  cand <- eval_df[eval_df$K >= k_min, , drop = FALSE]
  if (nrow(cand) == 0) stop("No candidate K >= ", k_min, " in the evaluation table.", call. = FALSE)
  best <- max(cand$Avg_Silhouette)
  min(cand$K[cand$Avg_Silhouette >= best - tol])
}

plot_elbow <- function(eval_df, elbow, recommended) {
  ggplot2::ggplot(eval_df, ggplot2::aes(x = K, y = WSS)) +
    ggplot2::geom_line(colour = "#2C7FB8", linewidth = 1) +
    ggplot2::geom_point(colour = "#2C7FB8", size = 2.5) +
    ggplot2::geom_vline(xintercept = recommended, linetype = "dashed", colour = "firebrick") +
    ggplot2::scale_x_continuous(breaks = eval_df$K) +
    ggplot2::scale_y_continuous(labels = scales::comma) +
    ggplot2::labs(title = "Elbow Method: Total Within-Cluster Sum of Squares",
                  subtitle = sprintf("Elbow heuristic suggests K = %d; dashed line marks the recommended K = %d", elbow, recommended),
                  x = "Number of clusters (K)", y = "Total within-cluster sum of squares",
                  caption = dataset_caption()) +
    theme_seg()
}

plot_silhouette <- function(eval_df, recommended) {
  best_k <- eval_df$K[which.max(eval_df$Avg_Silhouette)]
  ggplot2::ggplot(eval_df, ggplot2::aes(x = K, y = Avg_Silhouette)) +
    ggplot2::geom_line(colour = "#41AB5D", linewidth = 1) +
    ggplot2::geom_point(colour = "#41AB5D", size = 2.5) +
    ggplot2::geom_vline(xintercept = recommended, linetype = "dashed", colour = "firebrick") +
    ggplot2::scale_x_continuous(breaks = eval_df$K) +
    ggplot2::labs(title = "Silhouette Analysis: Average Silhouette Width by K",
                  subtitle = sprintf("Highest silhouette at K = %d; dashed line marks the recommended K = %d (parsimony rule)", best_k, recommended),
                  x = "Number of clusters (K)", y = "Average silhouette width",
                  caption = dataset_caption()) +
    theme_seg()
}

#' Resolve the K used downstream: manual override first, otherwise recommended.
resolve_final_k <- function(eval_df) {
  if (!is.na(CONFIG$k_final)) {
    if (!CONFIG$k_final %in% eval_df$K) {
      stop("CONFIG$k_final = ", CONFIG$k_final, " is outside the evaluated range (",
           min(eval_df$K), "-", max(eval_df$K), ").", call. = FALSE)
    }
    return(as.integer(CONFIG$k_final))
  }
  as.integer(recommend_k(eval_df))
}

run_optimal_clusters <- function(scaled = NULL) {
  message("== Step 5: Optimal number of clusters ==")
  ensure_project_dirs()
  if (is.null(scaled)) scaled <- load_scaled_features()

  eval_df     <- evaluate_k(scaled)
  elbow       <- elbow_k(eval_df$K, eval_df$WSS)
  recommended <- recommend_k(eval_df)
  final_k     <- resolve_final_k(eval_df)

  eval_df$Elbow_Candidate <- eval_df$K == elbow
  eval_df$Recommended     <- eval_df$K == recommended
  eval_df$Selected        <- eval_df$K == final_k
  eval_df$WSS <- round(eval_df$WSS, 2)
  eval_df$Avg_Silhouette <- round(eval_df$Avg_Silhouette, 4)
  save_table(eval_df, "cluster_evaluation.csv")

  save_plot(plot_elbow(eval_df, elbow, recommended), "elbow_plot.png")
  save_plot(plot_silhouette(eval_df, recommended), "silhouette_analysis.png")

  message(sprintf("  Elbow heuristic: K = %d | Best silhouette: K = %d | Recommended: K = %d | Selected: K = %d",
                  elbow, eval_df$K[which.max(eval_df$Avg_Silhouette)], recommended, final_k))
  message("  Note: K is a judgement call - check the segment profiles before accepting it.")
  invisible(list(evaluation = eval_df, elbow = elbow, recommended = recommended, selected = final_k))
}

if (isTRUE(getOption("customerseg.autorun", TRUE))) run_optimal_clusters()
