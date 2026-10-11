# Contributing

Thanks for your interest in improving this project! Suggestions and fixes are welcome.

## Getting started

1. Fork the repository and clone your fork.
2. Install the packages listed in [`requirements.md`](requirements.md).
3. Run `Rscript run_project.R --run-tests` from the project root to confirm everything works before you change anything.

## Making changes

- Create a branch: `git checkout -b feature/short-description`.
- Follow the existing style: `snake_case` names, `<-` for assignment, comments explaining *why*, project-relative paths via `project_path()` (never absolute paths).
- Keep functions small and reusable; validate inputs and give clear error messages.
- Keep results reproducible: use `CONFIG$seed`, never an unseeded random call.
- Add or update tests in `tests/` for any change to cleaning or clustering logic.
- Never commit secrets, credentials or personal data. Do not commit real customer data.
- Describe the change and why it is useful in your commit messages.

## Before opening a pull request

- [ ] `Rscript run_project.R --run-tests` finishes without errors.
- [ ] Documentation (`README.md`, `docs/`) is updated if behaviour changed.
- [ ] No large or reproducible generated files were added (see `.gitignore`).

## Reporting issues

Please include your R version (`R.version.string`), operating system, the command you ran and the full error message.
