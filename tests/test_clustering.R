# ==============================================================================
# tests/test_clustering.R - automated checks for feature engineering,
# cluster evaluation, k-means fitting and segment profiling.
# Run from the project root:  Rscript tests/test_clustering.R
# (base R only - no testing framework required)
# ==============================================================================

options(customerseg.autorun = FALSE)
if (!exists("find_project_root", mode = "function")) {
  .root <- c(".", "..")[file.exists(file.path(c(".", ".."), "run_project.R"))][1]
  if (is.na(.root)) stop("Run tests from the project root (folder containing run_project.R).", call. = FALSE)
  source(file.path(.root, "R", "01_data_loading.R"))
}
for (.s in c("02_data_cleaning.R", "04_feature_engineering.R", "05_optimal_clusters.R",
             "06_customer_clustering.R", "07_segment_profiling.R", "08_business_insights.R")) {
  source_project_script(.s)
}

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

# ---- fixtures: clean synthetic customers (never real data) ------------------------
clean <- clean_customer_data(simulate_customers(n = 150, seed = 7))$data
feat  <- select_features(clean)
scaled <- scale_features(feat)$scaled

message("Running tests: feature engineering and clustering")

run_test("identifiers and categorical columns cannot be clustering features", {
  expect_error(select_features(clean, c("CustomerID", "Age")), "cannot be clustering features")
  expect_error(select_features(clean, c("Gender", "Age")), "cannot be clustering features")
})

run_test("selected features contain only the configured numeric columns", {
  expect(identical(names(feat), CONFIG$features), "unexpected feature columns")
  expect(all(vapply(feat, is.numeric, logical(1))), "non-numeric feature")
})

run_test("scale_features standardises to mean 0 and SD 1", {
  expect(all(abs(colMeans(scaled)) < 1e-8), "means are not ~0")
  expect(all(abs(apply(scaled, 2, stats::sd) - 1) < 1e-8), "SDs are not ~1")
  expect(identical(colnames(scaled), CONFIG$features), "scaled columns differ from selected features")
})

run_test("scale_features rejects zero-variance features", {
  bad <- feat; bad$Age <- 30
  expect_error(scale_features(bad), "zero variance")
})

run_test("k-means is reproducible with a fixed seed", {
  a <- fit_kmeans(scaled, 4, seed = 123, nstart = 10)
  b <- fit_kmeans(scaled, 4, seed = 123, nstart = 10)
  expect(identical(a$cluster, b$cluster), "same seed gave different clusters")
})

run_test("every customer receives exactly one of K clusters", {
  km <- fit_kmeans(scaled, 5, nstart = 10)
  expect(length(km$cluster) == nrow(scaled), "wrong number of assignments")
  expect(!anyNA(km$cluster), "NA cluster labels")
  expect(length(unique(km$cluster)) == 5, "expected 5 non-empty clusters")
})

run_test("fit_kmeans validates K", {
  expect_error(fit_kmeans(scaled, 1), "must be a single integer")
  expect_error(fit_kmeans(scaled, nrow(scaled)), "must be a single integer")
})

run_test("evaluate_k returns WSS and silhouette for every K", {
  ev <- evaluate_k(scaled, 2:6, nstart = 25)
  expect(identical(ev$K, 2:6), "missing K values")
  expect(all(diff(ev$WSS) < 0), "WSS should decrease as K grows")
  expect(all(ev$Avg_Silhouette >= -1 & ev$Avg_Silhouette <= 1), "silhouette outside [-1, 1]")
})

run_test("recommend_k respects the minimum K and the parsimony rule", {
  ev <- data.frame(K = 2:6, WSS = c(100, 70, 50, 40, 35),
                   Avg_Silhouette = c(0.60, 0.40, 0.44, 0.45, 0.30))
  expect(recommend_k(ev, k_min = 3, tol = 0.03) == 4, "expected smallest K within tolerance of best (K = 4)")
  expect(recommend_k(ev, k_min = 2, tol = 0.0) == 2, "expected K = 2 when it is allowed and best")
})

run_test("elbow_k finds the bend of a clear elbow curve", {
  expect(elbow_k(2:8, c(100, 60, 30, 25, 22, 20, 19)) == 4, "elbow not at K = 4")
})

run_test("relabel_clusters numbers clusters by descending spending score", {
  cl <- c(1, 1, 2, 2, 3, 3); sp <- c(10, 20, 80, 90, 50, 55)
  expect(identical(relabel_clusters(cl, sp), c(3L, 3L, 1L, 1L, 2L, 2L)), "wrong ordering")
})

run_test("segment profiling covers all customers and labels are unique", {
  km <- fit_kmeans(scaled, 5, nstart = 10)
  seg <- as.data.frame(clean)
  seg$Cluster <- relabel_clusters(km$cluster, seg$Spending_Score)
  prof <- profile_segments(seg)
  expect(sum(prof$Customers) == nrow(seg), "customer counts do not add up")
  expect(abs(sum(prof$Percent) - 100) < 1, "percentages do not add up to ~100")
  expect(!anyDuplicated(prof$Segment), "segment labels are not unique")
  expect(all(c("Cluster", "Customers", "Percent", "Avg_Age", "Avg_Annual_Income", "Avg_Spending_Score") %in% names(prof)),
         "profile table is missing required columns")
})

run_test("segment labels follow the observed statistics", {
  expect(classify_segment("High", "High") == "High-Value Customers", "High/High")
  expect(classify_segment("High", "Low") == "Customers Requiring Further Engagement", "High/Low")
  expect(classify_segment("Low", "High") == "Potential Loyal Customers", "Low/High")
  expect(classify_segment("Low", "Low") == "Low-Spending Customers", "Low/Low")
  expect(classify_segment("Medium", "Medium") == "Average Customers", "Medium/Medium")
})

run_test("recommendations exist for every segment and state they are hypotheses", {
  km <- fit_kmeans(scaled, 5, nstart = 10)
  seg <- as.data.frame(clean)
  seg$Cluster <- relabel_clusters(km$cluster, seg$Spending_Score)
  recs <- build_recommendations(profile_segments(seg))
  expect(nrow(recs) == 5, "expected one recommendation per segment")
  expect(all(grepl("Hypothesis", recs$Caveat)), "caveat missing")
  expect(!any(grepl("predict", recs$Recommended_Action, ignore.case = TRUE)), "recommendations must not claim prediction")
})

failed <- names(Filter(isFALSE, as.list(.results)))
message(sprintf("\n%d passed, %d failed", length(as.list(.results)) - length(failed), length(failed)))
if (length(failed) > 0) {
  if (sys.nframe() == 0) quit(status = 1) else stop("Clustering tests failed: ", paste(failed, collapse = "; "), call. = FALSE)
}
