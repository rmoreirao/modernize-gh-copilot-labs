# Application repository

This is the proposed layout after one run. The application keeps its own assessment, plan, and tasks for review and approval, alongside the baseline report. The baseline tests should stay unchanged during the migration so they can catch unintended behavior changes.

```text
your-app/
|-- .github/upgrades/<scenario>/
|   |-- assessment.md
|   |-- plan.md
|   |-- tasks.md
|   `-- baseline-report.md
|-- tests/baseline/
`-- src/
```
