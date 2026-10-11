# Customer Segmentation Using R Programming

An end-to-end, reproducible data analytics project that segments customers by **age, annual income and spending score** with unsupervised machine learning (k-means) in **R**, then turns the segments into evidence-based marketing hypotheses.

> **Dataset note:** the project runs out of the box on a clearly labelled **synthetic demonstration dataset**.
> For the real public Mall Customers dataset, follow [`data/README.md`](data/README.md). Synthetic data is never
> presented as real customer data, and every chart caption says which dataset was used.

## Business Problem

A retailer cannot market effectively to "everyone". Which customers are the most valuable? Which have the income to spend more but do not? Which spend little and need a different approach? Segmentation groups customers by similar behaviour so marketing can be targeted instead of generic.

## Project Objectives

- Identify high-value customers and understand purchasing behaviour.
- Segment customers based on spending patterns.
- Identify customers who may need engagement or retention-style campaigns.
- Support targeted marketing strategies and business decisions.

## Features

- Safe CSV loading, data validation, duplicate and missing-value handling, IQR outlier flagging (nothing is silently deleted; raw data is never modified)
- Exploratory analysis: distributions, gender split, income/age vs. spending, correlations, boxplots
- Feature standardisation with `scale()`; identifiers and categorical columns excluded from the model
- K-means clustering with the **elbow method** and **silhouette analysis**, a fixed random seed and PCA visualisation
- Data-driven segment labels and a profile table (size, share, average age, income and spending)
- Rule-based business recommendations clearly framed as **hypotheses, not causal effects** (no churn prediction is claimed)
- Reusable functions, input validation, project-relative paths, automated tests
- One-command pipeline (`run_project.R`) and an R Markdown report that renders to HTML

## Technology Stack

| Area | Tools |
|---|---|
| Language | R (>= 4.1) |
| IDE | RStudio / Visual Studio Code |
| Data manipulation & cleaning | tidyverse components: dplyr, tidyr, readr, tibble |
| Visualisation | ggplot2, corrplot, scales |
| Machine learning | stats (`kmeans`, `prcomp`), cluster, factoextra |
| Reporting | R Markdown (knitr) |
| Version control | Git and GitHub |

## Dataset Source and Attribution

- **Recommended:** *Mall Customer Segmentation Data* by Vijay Choudhary on Kaggle (CC0 / public domain according to the Kaggle page; please verify) - <https://www.kaggle.com/datasets/vjchoudhary7/customer-segmentation-tutorial-in-python>. Columns: CustomerID, Gender, Age, Annual Income (k$), Spending Score (1-100).
- **Included fallback:** `data/raw/synthetic_customers.csv` - 200 **synthetic** customers generated from five invented archetypes (seed 42) for demonstration only.

The data dictionary, license notes and limitations are in [`data/README.md`](data/README.md).

## Folder Structure

```
customer-segmentation-r/
├── data/
│   ├── raw/                      # original data (never modified)
│   │   └── synthetic_customers.csv
│   ├── processed/                # cleaned + segmented data (generated)
│   └── README.md                 # dataset source, license, data dictionary, limitations
├── R/
│   ├── 01_data_loading.R         # config, helpers, safe loading
│   ├── 02_data_cleaning.R
│   ├── 03_exploratory_data_analysis.R
│   ├── 04_feature_engineering.R
│   ├── 05_optimal_clusters.R     # elbow + silhouette
│   ├── 06_customer_clustering.R  # final k-means + PCA plot
│   ├── 07_segment_profiling.R
│   └── 08_business_insights.R
├── outputs/
│   ├── plots/                    # PNG charts (generated)
│   ├── tables/                   # CSV summaries (generated)
│   └── reports/                  # rendered report + markdown summaries (generated)
├── reports/
│   └── customer_segmentation_report.Rmd
├── tests/
│   ├── test_data_cleaning.R
│   └── test_clustering.R
├── docs/
│   ├── methodology.md
│   ├── business_recommendations.md
│   └── publishing_checklist.md   # GitHub publishing guide + final checklist
├── .gitignore
├── .Rprofile
├── CONTRIBUTING.md
├── DESCRIPTION
├── LICENSE
├── README.md
├── requirements.md
└── run_project.R
```

`renv.lock` is created when you run `renv::init()` / `renv::snapshot()` (see below) and should then be committed.

## Installation

```bash
git clone https://github.com/<your-username>/customer-segmentation-r.git
cd customer-segmentation-r
```

Install **R >= 4.1** from <https://cran.r-project.org/> and (optionally) RStudio from <https://posit.co/download/rstudio-desktop/>.

### Package setup

```r
install.packages(c("dplyr", "tidyr", "readr", "tibble", "ggplot2", "rlang", "scales",
                   "corrplot", "cluster", "factoextra", "rmarkdown", "knitr"))
```

To pin exact versions for reproducibility: `install.packages("renv"); renv::init(); renv::snapshot()`. Later, `renv::restore()` reinstalls the same versions. Details are in [`requirements.md`](requirements.md).

## How to Run the Complete Project

From the project root folder:

```bash
Rscript run_project.R                  # full pipeline + HTML report
Rscript run_project.R --no-report      # pipeline only
Rscript run_project.R --run-tests      # run automated tests first
```

In RStudio: open the folder, then `source("run_project.R")` (the working directory must be the project root).

The pipeline runs these steps in order and creates all output folders automatically:

1. Data loading → 2. Data cleaning → 3. Exploratory analysis → 4. Feature engineering → 5. Cluster evaluation (elbow + silhouette) → 6. Final clustering → 7. Segment profiling → 8. Business insights → (optional) report.

Each script can also be run on its own after the previous steps, for example `Rscript R/05_optimal_clusters.R`. To run only the tests: `Rscript tests/test_data_cleaning.R` and `Rscript tests/test_clustering.R`.

To use the real dataset, put `Mall_Customers.csv` in `data/raw/` and run again. To override the chosen number of clusters, set `k_final` in `CONFIG` inside `R/01_data_loading.R`.

### Where the results appear

| What | Location |
|---|---|
| Cleaned data | `data/processed/customers_clean.csv` |
| Customers with cluster and segment label | `data/processed/segmented_customers.csv` |
| Segment profile table | `outputs/tables/segment_profiles.csv` |
| Cluster evaluation (WSS, silhouette per K) | `outputs/tables/cluster_evaluation.csv` |
| Recommendations | `outputs/tables/business_recommendations.csv`, `outputs/reports/segment_recommendations.md` |
| Charts | `outputs/plots/*.png` |
| Report | `outputs/reports/customer_segmentation_report.html` |

## Example Visualizations

These images are created when you run the pipeline. Commit the PNGs from `outputs/plots/` after your first run so they display here on GitHub.

| | |
|---|---|
| ![Income vs spending](outputs/plots/income_vs_spending.png) | ![Elbow plot](outputs/plots/elbow_plot.png) |
| ![Silhouette analysis](outputs/plots/silhouette_analysis.png) | ![Cluster PCA](outputs/plots/cluster_pca.png) |
| ![Segment sizes](outputs/plots/segment_sizes.png) | ![Segment metrics](outputs/plots/segment_average_metrics.png) |

## Sample Segment Summary

The pipeline writes a ready-made markdown table of your segments to `outputs/reports/segment_summary.md`. After your first run, paste it here. It has this format:

| Cluster | Segment | Customers | Percent | Avg_Age | Avg_Annual_Income | Avg_Spending_Score |
|---|---|---|---|---|---|---|
| *1..K* | *label derived from the data* | *count* | *share of customers* | *years* | *thousand $* | *1-100 index* |

Segment names such as "High-Value Customers" are assigned from the observed statistics, never fixed in advance.

## Business Use Cases

- **Loyalty programmes:** reward the most valuable segment and design tiers.
- **Targeted campaigns:** engage customers with high income but low spending.
- **Budget-aware offers:** personalised recommendations for enthusiastic spenders with lower income.
- **Campaign planning:** size each segment before allocating budget.
- **Experiment design:** use segments as the unit for A/B tests of marketing actions.

## Limitations

- Small dataset and only three behavioural variables; no transaction history or time dimension.
- The Mall Customers dataset is a teaching dataset with an undocumented collection method; the bundled fallback is synthetic.
- K-means assumes compact, roughly spherical clusters and is sensitive to outliers; the best K is a judgement call.
- Recommendations are untested hypotheses. **No churn prediction is implemented** because there is no churn outcome in the data.

## Future Improvements

- RFM features from transaction data; hierarchical clustering, k-medoids and Gaussian mixture comparison; segment stability checks.
- Interactive Shiny dashboard.
- Controlled A/B tests of the recommended actions.
- A supervised churn model if real churn data becomes available.

## Author

- **Name:** [Your Name]
- **GitHub:** [github.com/your-username](https://github.com/your-username)
- **LinkedIn:** [linkedin.com/in/your-profile](https://linkedin.com/in/your-profile)
- **Email:** your.email@example.com

## License

Released under the [MIT License](LICENSE). Dataset licenses are described in [`data/README.md`](data/README.md).
