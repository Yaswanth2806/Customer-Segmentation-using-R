# Dataset Documentation

## Which data does the project use?

| Priority | File (in `data/raw/`) | Type | When it is used |
|---|---|---|---|
| 1 | `Mall_Customers.csv` | Real public teaching dataset | Used automatically if you download it (instructions below) |
| 2 | `synthetic_customers.csv` | **Synthetic demonstration data** | Used when the file above is absent |

> **The synthetic file is not real customer data.** It was generated from five invented customer archetypes
> (fixed seed 42, 200 rows) purely so the pipeline runs out of the box. Every chart caption and the report state
> when synthetic data was used. Do not draw business conclusions from it.

## Mall Customers dataset (recommended)

- **Name:** Mall Customer Segmentation Data
- **Source:** Kaggle - <https://www.kaggle.com/datasets/vjchoudhary7/customer-segmentation-tutorial-in-python>
- **Author:** Vijay Choudhary (Kaggle user `vjchoudhary7`)
- **License:** CC0 1.0 (public domain) as shown on the Kaggle page - please re-check the license shown there before redistributing.
- **How to use:** download `Mall_Customers.csv` from Kaggle, place it in `data/raw/`, and run `Rscript run_project.R`.
  The file is listed in `.gitignore` so you do not re-publish it by accident.

## Data dictionary

| Raw column (Mall Customers) | Standard name in the pipeline | Type | Description |
|---|---|---|---|
| `CustomerID` | `CustomerID` | integer | Unique customer identifier. **Never used for clustering.** |
| `Gender` (or `Genre` in older copies) | `Gender` | text | `Female` / `Male`. Used for description only, not clustering. |
| `Age` | `Age` | integer | Age in years. |
| `Annual Income (k$)` | `Annual_Income` | integer | Annual income in thousand dollars. |
| `Spending Score (1-100)` | `Spending_Score` | integer | Score from 1 to 100 assigned by the mall based on customer behaviour and spending nature. It is an index, **not** revenue. |

The synthetic file uses exactly the same column names and format.

## Limitations

- Only 200 customers and 3 behavioural variables; real segmentation uses far richer data.
- The Mall Customers dataset is a widely used teaching dataset; how it was collected is not documented and it may itself be simulated.
- Spending Score is defined by the data provider; its exact calculation is unknown.
- No transaction history, time dimension, product information or churn outcome, so churn cannot be predicted.
- The synthetic data has simpler, cleaner structure than real customers and contains no missing values or duplicates
  (the automated tests inject these problems to verify the cleaning code).
