#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./tools/github_issue_import/upload_issues.sh JuliaPluto/Pluto.jl ./tools/github_issue_import/pluto_ai_issue_backlog.csv

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <owner/repo> <csv_path>"
  exit 1
fi

REPO="$1"
CSV_PATH="$2"

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: GitHub CLI (gh) is required."
  exit 1
fi

# Skip header and parse CSV with Python for robust quoted field handling.
tail -n +2 "$CSV_PATH" | python3 - <<'PY'
import csv
import json
import os
import sys
import subprocess

repo = os.environ.get("REPO")
if not repo:
    print("Missing REPO environment variable", file=sys.stderr)
    sys.exit(1)

reader = csv.reader(sys.stdin)
for row in reader:
    if len(row) < 3:
        continue
    title = row[0].strip()
    labels_raw = row[1].strip()
    body = row[2].strip()
    cmd = ["gh", "issue", "create", "--repo", repo, "--title", title, "--body", body]
    if labels_raw:
        cmd.extend(["--label", labels_raw])
    print(f"Creating issue: {title}")
    subprocess.run(cmd, check=True)
PY
