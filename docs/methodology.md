# Methodology

This document explains every analytical decision in the pipeline so results can be reviewed and reproduced.

## 1. Data preparation (`R/02_data_cleaning.R`)

| Issue | Strategy | Why |
|---|---|---|
| Column-name variants (`Genre`, `Annual Income (k$)`, ...) | Mapped to `CustomerID, Gender, Age, Annual_Income, Spending_Score` | One code path for every copy of the dataset |
| Missing numeric values | Median imputation, only if <= 5% of rows are affected, otherwise the pipeline stops; every change is logged in `outputs/tables/imputation_log.csv` | Median is robust to outliers; a hard limit prevents hiding a data-quality problem |
| Missing `Gender` | Set to `"Unknown"` | Gender is descriptive only |
| Exact duplicate rows | Removed (first copy kept) and listed in `removed_duplicate_records.csv` | Double-counting a customer would distort clusters |
| Same `CustomerID`, different data | **Pipeline stops** with the IDs listed | A person must decide which record is correct |
| Same attributes, different `CustomerID` | Flagged only | Different customers can genuinely look alike |
| Out-of-range values | Flagged in `range_validation.csv`, kept | Possible data-entry problems need investigation, not silent deletion |
| Outliers (1.5 x IQR) | Flagged in `outlier_summary.csv` / `outlier_records.csv`, **kept** | High earners or big spenders are valid customers and often the most interesting segment |

The raw file in `data/raw/` is never modified. The cleaned data is written to `data/processed/customers_clean.csv`.

## 2. Feature engineering (`R/04_feature_engineering.R`)

- **Features:** `Age`, `Annual_Income`, `Spending_Score`.
- **Excluded:** `CustomerID` (an identifier carries no behavioural meaning) and `Gender` (categorical; Euclidean distance on a 0/1 code would be misleading). Gender is used only to describe segments afterwards.
- **Standardisation:** `scale()` converts each feature to a z-score. Without it the variable with the largest numeric range (income) would dominate the distance calculation.
- The mean and SD used are stored in `outputs/tables/scaling_parameters.csv`, and the original customer data stays available for interpretation.

## 3. Choosing the number of clusters (`R/05_optimal_clusters.R`)

- **Elbow method:** total within-cluster sum of squares (WSS) for K = 2..10. We also report an elbow candidate computed as the K farthest from the straight line joining the first and last points of the normalised curve.
- **Silhouette analysis:** average silhouette width per K (range -1 to 1; higher means better separated clusters).
- **No single metric decides.** The elbow is frequently ambiguous and the silhouette often keeps rising slowly with K while the extra clusters add little business value.
- **Starting rule:** choose the smallest K >= 3 whose silhouette is within 0.03 of the best silhouette. K = 2 is excluded as a recommendation because two segments are rarely actionable. The rule is a documented starting point, not a proof.
- **Human check:** review the segment profiles (step 07). If another K gives clearer, more useful segments, set `CONFIG$k_final` in `R/01_data_loading.R` and re-run.

## 4. Final model (`R/06_customer_clustering.R`)

- `stats::kmeans()` (Hartigan-Wong) with `nstart = 50` restarts and `iter.max = 100`.
- `set.seed(CONFIG$seed)` immediately before each fit, so the evaluation in step 05 and the final fit in step 06 give identical results for the same K.
- Cluster numbers are re-ordered so that **Cluster 1 has the highest average spending score**. Raw k-means numbering is arbitrary.
- Rows are matched to labels by position and the `CustomerID` order is verified, so labels cannot be attached to the wrong customer.
- **No data leakage:** clustering is unsupervised - there is no target variable and no train/test split. Scaling and clustering use the same feature columns.
- **Evaluation:** average silhouette width, silhouette per cluster, and the share of variance between clusters (between-SS / total-SS).
- **Visualisation:** PCA (`stats::prcomp`) projects the three standardised features to two dimensions; the percentage of variance explained is shown in the subtitle.

## 5. Segment profiling and labels (`R/07_segment_profiling.R`)

For each cluster we report size, percentage, average age, average income and average spending score. Business labels are **derived from the data**: a cluster's average income and spending score are compared with the overall averages via z-scores (High >= +0.5, Low <= -0.5, otherwise Medium) and mapped like this:

| Spending | Income | Label |
|---|---|---|
| High | High | High-Value Customers |
| High | Medium / Low | Potential Loyal Customers |
| Medium | any | Average Customers |
| Low | High | Customers Requiring Further Engagement |
| Low | Medium / Low | Low-Spending Customers |

If two clusters receive the same label, the cluster number is appended so names stay unique. The `Rationale` column in `segment_profiles.csv` shows the z-scores behind every label.

## 6. Business insights (`R/08_business_insights.R`)

Recommendations come from a rule-based playbook keyed by segment type and are combined with the segment's own statistics as evidence. They are **hypotheses to test with controlled experiments**, not causal claims. The project does **not** predict churn: the dataset contains no churn outcome and no predictive model is trained.

## 7. Reproducibility

- Fixed seed (`CONFIG$seed = 42`).
- All parameters live in one `CONFIG` list.
- Project-relative paths only (`project_path()`).
- Package versions can be pinned with `renv` (see `requirements.md`).
- Automated tests: `tests/test_data_cleaning.R` and `tests/test_clustering.R`.

## 8. Known limitations

- K-means assumes compact, roughly spherical clusters of similar size and is sensitive to outliers.
- Results depend on feature choice and scaling.
- A small dataset (200 customers) limits how stable the segments are.
- Segments are a snapshot in time; customer behaviour changes.
