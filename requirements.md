# Requirements

## R version

- **R >= 4.1.0** (the code uses the native pipe `|>`).
- RStudio (optional but recommended) or Visual Studio Code with the R extension.
- Pandoc is needed only to render the R Markdown report (it is bundled with RStudio).
- A LaTeX distribution (for example `tinytex::install_tinytex()`) is needed only if you want to render the report directly to PDF.

## R packages

| Package | Minimum version | Purpose |
|---|---|---|
| dplyr | - | data manipulation |
| tidyr | - | reshaping data |
| readr | - | reading and writing CSV files |
| tibble | - | tidy data frames |
| ggplot2 | 3.4.0 | all charts |
| rlang | - | tidy evaluation helpers |
| scales | - | axis formatting |
| corrplot | - | correlation heat-map |
| cluster | - | silhouette analysis |
| factoextra | - | silhouette visualisation |
| rmarkdown, knitr | - | rendering `reports/customer_segmentation_report.Rmd` |
| renv | - | optional: lock exact package versions |

`stats` (k-means, PCA) ships with R.

## Install

```r
install.packages(c("dplyr", "tidyr", "readr", "tibble", "ggplot2", "rlang", "scales",
                   "corrplot", "cluster", "factoextra", "rmarkdown", "knitr", "renv"))
```

(Installing the `tidyverse` meta-package also provides dplyr, tidyr, readr, tibble and ggplot2.)

## Reproducible environment with renv (recommended before publishing)

```r
install.packages("renv")
renv::init()       # creates renv/ and renv.lock for this project
# ... run the pipeline once to confirm everything works ...
renv::snapshot()   # records the exact package versions in renv.lock
```

Anyone cloning the repository can then run `renv::restore()` to install the same versions.
