# ==============================================================================
# 08_business_insights.R
# ------------------------------------------------------------------------------
# Purpose : Turn the segment profiles into evidence-based marketing hypotheses.
#
# IMPORTANT - how to read the output:
#   * Every recommendation is a HYPOTHESIS to test (e.g. with an A/B test), not a
#     proven causal effect. Segments describe customers; they do not prove that
#     any campaign will work.
#   * This project does NOT predict churn: the dataset has no churn outcome and
#     no predictive model is trained. "Needs engagement" means low spending
#     relative to income or peers, nothing more.
#   * Spending Score is an index (1-100), not revenue.
#
# Inputs  : outputs/tables/segment_profiles.csv
# Outputs : outputs/tables/business_recommendations.csv
#           outputs/reports/segment_recommendations.md
# Usage   : Rscript R/08_business_insights.R   (from the project root)
# ==============================================================================

if (!exists("find_project_root", mode = "function")) {
  .f <- c("R/01_data_loading.R", "01_data_loading.R")
  .f <- .f[file.exists(.f)][1]
  if (is.na(.f)) stop("Run this script from the project root (the folder containing run_project.R).", call. = FALSE)
  local({ op <- options(customerseg.autorun = FALSE); on.exit(options(op)); source(.f) })
}

# Playbook keyed by Segment_Type (assigned in 07_segment_profiling.R).
RECOMMENDATION_PLAYBOOK <- list(
  "High-Value Customers" = list(
    priority   = 1L,
    action     = "Introduce loyalty benefits, early access and premium offers to protect and grow this group.",
    hypothesis = "A loyalty tier with premium perks increases repeat visits and basket size for these customers.",
    kpi        = "Repeat purchase rate, average basket value, loyalty-tier enrolment"
  ),
  "Potential Loyal Customers" = list(
    priority   = 2L,
    action     = "Offer personalised recommendations and reward programmes sized for their budget.",
    hypothesis = "Personalised, budget-appropriate offers convert high engagement into long-term loyalty.",
    kpi        = "Repeat purchase rate, offer redemption rate, share of wallet"
  ),
  "Customers Requiring Further Engagement" = list(
    priority   = 3L,
    action     = "Run targeted engagement campaigns (premium product discovery, personalised outreach) and ask for feedback.",
    hypothesis = "These customers have spending capacity but spend little; relevant offers or better product fit raise their spending.",
    kpi        = "Spending-score uplift vs. a control group, campaign response rate, survey feedback"
  ),
  "Average Customers" = list(
    priority   = 4L,
    action     = "Maintain core service quality and test cross-sell bundles and seasonal promotions.",
    hypothesis = "Bundles and timely promotions move part of this large middle group toward higher spending.",
    kpi        = "Conversion rate on bundles, average basket value, promotion ROI"
  ),
  "Low-Spending Customers" = list(
    priority   = 5L,
    action     = "Test low-cost relevant offers (entry-level products, discounts) and improve engagement without heavy spend.",
    hypothesis = "Light-touch, price-appropriate offers lift engagement at acceptable acquisition cost.",
    kpi        = "Offer response rate, cost per engaged customer, spending-score change"
  )
)

CAVEAT_TEXT <- paste("Hypothesis for controlled testing, not a proven causal effect.",
                     "Segments are descriptive; no churn model is implemented.")

#' Create one evidence-based recommendation row per segment.
build_recommendations <- function(profile) {
  needed <- c("Cluster", "Segment", "Segment_Type", "Customers", "Percent",
              "Avg_Age", "Avg_Annual_Income", "Avg_Spending_Score")
  if (!all(needed %in% names(profile))) {
    stop("`profile` must contain columns: ", paste(needed, collapse = ", "), call. = FALSE)
  }
  overall_spend <- stats::weighted.mean(profile$Avg_Spending_Score, profile$Customers)

  rows <- lapply(seq_len(nrow(profile)), function(i) {
    p <- profile[i, ]
    play <- RECOMMENDATION_PLAYBOOK[[p$Segment_Type]]
    if (is.null(play)) stop("No playbook entry for segment type: ", p$Segment_Type, call. = FALSE)
    data.frame(
      Priority = play$priority,
      Cluster = p$Cluster,
      Segment = p$Segment,
      Evidence = sprintf("%d customers (%.1f%% of base); average age %.1f; average income %.1fk$; average spending score %.1f (overall %.1f).",
                         p$Customers, p$Percent, p$Avg_Age, p$Avg_Annual_Income,
                         p$Avg_Spending_Score, overall_spend),
      Recommended_Action = play$action,
      Hypothesis_To_Test = play$hypothesis,
      Suggested_KPIs = play$kpi,
      Caveat = CAVEAT_TEXT,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out <- out[order(out$Priority, out$Cluster), ]
  rownames(out) <- NULL
  out
}

#' Render the recommendations as a markdown report.
recommendations_to_markdown <- function(recs) {
  lines <- c(
    "# Segment Recommendations", "",
    paste0("_Generated by R/08_business_insights.R on ", format(Sys.Date()), "._"), "",
    "> **Read this first:** every item below is a *hypothesis to test*, not a proven causal effect.",
    "> Segments describe customers' observed spending behaviour; this project does not predict churn.", ""
  )
  for (i in seq_len(nrow(recs))) {
    r <- recs[i, ]
    lines <- c(lines,
      sprintf("## %d. %s", i, r$Segment), "",
      paste0("**Evidence:** ", r$Evidence), "",
      paste0("**Recommended action:** ", r$Recommended_Action), "",
      paste0("**Hypothesis to test:** ", r$Hypothesis_To_Test), "",
      paste0("**Suggested KPIs:** ", r$Suggested_KPIs), "")
  }
  lines
}

run_business_insights <- function() {
  message("== Step 8: Business insights ==")
  ensure_project_dirs()
  path <- project_path("outputs", "tables", "segment_profiles.csv")
  if (!file.exists(path)) {
    stop("segment_profiles.csv not found. Run R/07_segment_profiling.R first.", call. = FALSE)
  }
  profile <- utils::read.csv(path, stringsAsFactors = FALSE)
  recs <- build_recommendations(profile)
  save_table(recs, "business_recommendations.csv")
  writeLines(recommendations_to_markdown(recs), project_path("outputs", "reports", "segment_recommendations.md"))
  message("  saved report: outputs/reports/segment_recommendations.md")
  invisible(recs)
}

if (isTRUE(getOption("customerseg.autorun", TRUE))) run_business_insights()
