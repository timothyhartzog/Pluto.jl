# Pluto AI issue import pack

This folder contains:

- pluto_ai_issue_backlog.csv
- upload_issues.sh
- github_issues_copy_paste.md

## Quick start

1. Authenticate GitHub CLI:

gh auth login

2. Make script executable:

chmod +x tools/github_issue_import/upload_issues.sh

3. Run the upload:

REPO=JuliaPluto/Pluto.jl tools/github_issue_import/upload_issues.sh JuliaPluto/Pluto.jl tools/github_issue_import/pluto_ai_issue_backlog.csv

## Notes

- Labels in the CSV should exist in the repository. If a label does not exist, issue creation can fail.
- You can edit titles, labels, and bodies in pluto_ai_issue_backlog.csv before upload.
- Re-running the script creates duplicate issues. Run once unless duplicates are intended.

## Optional: create labels first

You can create missing labels from the web UI:

- Repository -> Issues -> Labels -> New label

Or with GitHub CLI:

gh label create ai --repo JuliaPluto/Pluto.jl --color 1f6feb --description "AI related work"
