# Publishing Guide and Final Checklist

## Part 1 - Run the project locally (required before publishing)

The code in this repository has been written and statically reviewed, but the generated results (plots, tables,
processed data, rendered report) are produced when **you** run the pipeline in R. Do this first:

```bash
cd customer-segmentation-r
Rscript run_project.R --run-tests
```

Or in RStudio: `setwd("path/to/customer-segmentation-r")`, then `source("run_project.R")`.

If a step fails, the error names the step (for example *"Pipeline stopped at 'final clustering': ..."*). The most common causes are a missing package (run the `install.packages(...)` line from `requirements.md`) or running from the wrong folder (the working directory must contain `run_project.R`).

Optional but recommended - pin package versions:

```r
install.packages("renv")
renv::init()
renv::snapshot()      # creates renv.lock - commit it
```

## Part 2 - Publish on GitHub

1. **Install Git** (<https://git-scm.com/downloads>) and create a free GitHub account.
2. **Configure Git once:**
   ```bash
   git config --global user.name  "Your Name"
   git config --global user.email "your.email@example.com"
   ```
3. **Create an empty repository** on GitHub: *New repository* → name `customer-segmentation-r` → leave "Add a README / .gitignore / license" **unticked** (they already exist) → *Create repository*.
4. **Personalise placeholders:** replace `[Your Name]` in `LICENSE`, `DESCRIPTION`, `README.md`, and the report's `author:` line; replace the GitHub/LinkedIn/email links in `README.md`.
5. **Initialise and push:**
   ```bash
   cd customer-segmentation-r
   git init
   git add .
   git status                      # review what will be committed
   git commit -m "Add customer segmentation project in R"
   git branch -M main
   git remote add origin https://github.com/<your-username>/customer-segmentation-r.git
   git push -u origin main
   ```
   If GitHub asks for a password, use a **personal access token** (Settings → Developer settings → Personal access tokens) or sign in with GitHub Desktop / the GitHub CLI (`gh auth login`).
6. **Polish the repository page:** add a short description, topics (`r`, `data-analysis`, `customer-segmentation`, `k-means`, `ggplot2`), and pin the repository on your profile.
7. **Verify on GitHub:** README renders, example images appear, and the folder structure matches.

## Part 3 - Submitting to the course LMS (if applicable)

The LMS project page asks for:

- the **GitHub repository URL** (required), optionally a live demo URL, a **demo video URL** and notes;
- per the submission instructions on the page: the R script(s), the cleaned/processed dataset, a well-structured **PDF report**, and screenshots/exported images of your visualisations, organised in one folder or ZIP;
- a **5-10 minute screen-recorded demo video** (shareable Google Drive or unlisted YouTube link): introduce the problem, explain the dataset, walk through the R code, and highlight the key insights and plots.

**Creating the PDF report:**

- Easiest: open `outputs/reports/customer_segmentation_report.html` in Chrome → *Print* → *Save as PDF*.
- Or: `tinytex::install_tinytex()` once, then
  `rmarkdown::render("reports/customer_segmentation_report.Rmd", output_format = "pdf_document", output_dir = "outputs/reports")`.

**Check the deadline shown on the LMS project page.** Late submissions may not be evaluated unless prior approval is taken, so contact your mentor early if you are past the due date.

## Final checklist before publishing

### Code and execution
- [ ] `Rscript run_project.R --run-tests` completes with no errors and all tests pass
- [ ] `data/processed/customers_clean.csv` and `data/processed/segmented_customers.csv` exist
- [ ] `outputs/plots/` contains the PNG charts and `outputs/tables/` the CSV tables
- [ ] `outputs/reports/customer_segmentation_report.html` renders and shows real results
- [ ] Re-running the pipeline gives identical cluster results (fixed seed)

### Data and ethics
- [ ] Report and README clearly say whether synthetic or real data was used
- [ ] Real dataset license and source are cited (`data/README.md`)
- [ ] No personal data, credentials or API keys are in the repository
- [ ] `data/raw/` is unmodified

### Documentation
- [ ] Placeholders `[Your Name]`, GitHub/LinkedIn/email links replaced
- [ ] The segment summary table from `outputs/reports/segment_summary.md` is pasted into `README.md`
- [ ] README images display (commit the PNG files from `outputs/plots/`)
- [ ] Business recommendations are described as hypotheses; no churn prediction is claimed

### Repository hygiene
- [ ] `renv.lock` is committed (after `renv::snapshot()`)
- [ ] `.gitignore` is respected (`git status` shows no `.Rhistory`, `.RData`, `.Rproj.user`, HTML files)
- [ ] Repository has a description, topics and the MIT license
