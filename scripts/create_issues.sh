#!/usr/bin/env bash
# Creates all 23 AI-feature GitHub issues and assigns them to GitHub Copilot.
#
# Prerequisites:
#   - GitHub CLI installed: https://cli.github.com/
#   - Authenticated:  gh auth login
#   - (Optional) Copilot coding agent enabled on the repo for --assignee copilot
#
# Usage:
#   bash scripts/create_issues.sh
#   bash scripts/create_issues.sh --no-assign   # skip Copilot assignment

set -euo pipefail

REPO="timothyhartzog/Pluto.jl"
ASSIGN_COPILOT=true

for arg in "$@"; do
  [[ "$arg" == "--no-assign" ]] && ASSIGN_COPILOT=false
done

# ── helpers ──────────────────────────────────────────────────────────────────

ensure_label() {
  local name="$1" color="$2" desc="$3"
  gh label create "$name" --color "$color" --description "$desc" \
     --repo "$REPO" 2>/dev/null \
  || gh label edit "$name" --color "$color" --description "$desc" \
     --repo "$REPO" 2>/dev/null \
  || true
}

CREATED_ISSUES=()

create_issue() {
  local title="$1" labels="$2" body="$3"
  echo "  → $title"
  local url
  url=$(gh issue create \
    --repo   "$REPO" \
    --title  "$title" \
    --label  "$labels" \
    --body   "$body" 2>&1) || { echo "    ⚠ failed: $url"; return; }
  echo "    $url"
  # extract issue number from URL  (e.g. .../issues/42)
  local num
  num=$(echo "$url" | grep -oE '[0-9]+$')
  [[ -n "$num" ]] && CREATED_ISSUES+=("$num")
}

# ── labels ───────────────────────────────────────────────────────────────────

echo "==> Ensuring labels exist..."
ensure_label "epic"          "6f42c1" "Large feature scope spanning multiple issues"
ensure_label "ai"            "0075ca" "AI/LLM-related feature"
ensure_label "backend"       "e4e669" "Backend/server-side work"
ensure_label "frontend"      "d93f0b" "Frontend/UI work"
ensure_label "data"          "bfd4f2" "Data processing or datasets"
ensure_label "security"      "ee0701" "Security-related"
ensure_label "testing"       "0e8a16" "Tests and test infrastructure"
ensure_label "documentation" "cfd3d7" "Documentation"

# ── issues ───────────────────────────────────────────────────────────────────

echo ""
echo "==> Creating issues..."

# 1 ── EPIC: Multi-provider AI integration
create_issue \
  "EPIC: Multi-provider AI integration for notebook assistance" \
  "epic,ai,backend,enhancement" \
"**Problem:**
Need pluggable support for cloud and local LLMs.

**Goal:**
Unified API for provider calls with robust errors and retries.

**Scope:**
- Provider interface for completion and code generation
- Cloud adapter
- Ollama adapter
- Shared error taxonomy
- Integration tests with mocks

**Acceptance Criteria:**
- At least one cloud provider and Ollama are supported
- Provider can be switched without UI changes
- Errors are normalized and surfaced clearly to users

**Copilot Prompt:**
Create a provider abstraction for AI completion and code-generation calls. Add adapters for one cloud provider and Ollama, plus typed error handling and tests."

# 2 ── EPIC: Dataset import, cleaning, and analysis
create_issue \
  "EPIC: Dataset import, cleaning, and analysis assistance" \
  "epic,ai,data,enhancement" \
"**Problem:**
Users need guided analysis from raw data to insight.

**Goal:**
AI assists with import, cleaning, and Julia code generation using safe apply flows.

**Scope:**
- Dataset import assistant
- Data profiling summary
- Cleaning widgets and modules
- Analysis suggestions and code generation

**Acceptance Criteria:**
- User can import datasets via guided workflow
- User can apply common cleaning tasks with widget support
- AI-generated code is previewed before apply

**Copilot Prompt:**
Build structured actions for data import and cleaning, with Julia code generation and apply-preview UX."

# 3 ── EPIC: Sidebar quick actions and guided help modes
create_issue \
  "EPIC: Sidebar quick actions and guided help modes" \
  "epic,ai,frontend,enhancement" \
"**Problem:**
Frequent actions are too manual and slow.

**Goal:**
Provide fast sidebar actions and per-interaction help controls.

**Scope:**
- Sidebar quick actions
- Keyboard shortcuts
- Help mode controls and persistence

**Acceptance Criteria:**
- Sidebar supports common analysis actions
- Help mode can be changed per interaction
- Help mode settings persist as designed

**Copilot Prompt:**
Implement sidebar action registry with help-mode selector and shortcut bindings."

# 4 ── EPIC: Trust, observability, reproducibility, and export
create_issue \
  "EPIC: Trust, observability, reproducibility, and export" \
  "epic,ai,security,enhancement" \
"**Problem:**
AI features need safety, transparency, and reproducibility.

**Goal:**
Add redaction, provenance metadata, usage metrics, and export support.

**Scope:**
- Telemetry with redaction
- Provenance tagging for generated code
- Multi-format export
- Safety and policy checks

**Acceptance Criteria:**
- Sensitive values are redacted from telemetry
- Generated code includes provenance metadata
- Export works for required formats

**Copilot Prompt:**
Add telemetry hooks with redaction, provenance metadata on generated code, and export pipeline for HTML/Markdown/artifacts."

# 5
create_issue \
  "Define AI provider interface and response schema" \
  "ai,backend,enhancement" \
"Implement typed provider interfaces for completion, streaming, and code generation tasks.

**Tasks:**
- Define provider API contracts
- Define structured response schema
- Define shared error taxonomy
- Add schema validation and unit tests

**Acceptance Criteria:**
- Interface supports prompt, streamed prompt, and code-generation intents
- Structured response validation catches malformed provider outputs
- Tests cover valid and invalid payloads"

# 6
create_issue \
  "Implement Ollama adapter with model configuration" \
  "ai,backend,enhancement" \
"Implement local Ollama adapter using the provider interface.

**Tasks:**
- Add configurable host and model
- Add timeout and retry logic
- Map Ollama-specific failures into shared errors
- Add integration tests with mocked responses

**Acceptance Criteria:**
- Local model calls succeed with configurable host/model
- Unavailable model and server failures return clear errors"

# 7
create_issue \
  "Implement cloud provider adapter with secure key handling" \
  "ai,backend,security,enhancement" \
"Implement first cloud provider adapter with secure key handling and robust failure behavior.

**Tasks:**
- Add API key configuration path
- Ensure secrets are never logged
- Add auth, rate-limit, timeout handling
- Add retry policy and tests

**Acceptance Criteria:**
- Auth and quota errors are mapped into shared taxonomy
- Secret values do not appear in logs"

# 8
create_issue \
  "Build notebook context assembler for prompt generation" \
  "ai,backend,enhancement" \
"Create notebook-aware context assembly for AI prompts.

**Tasks:**
- Collect user request, notebook state, recent outputs
- Include dataset profile summaries
- Enforce context limits and truncation policies

**Acceptance Criteria:**
- Context avoids oversized payloads and supports summarization fallback
- Prompt assembly is deterministic and testable"

# 9
create_issue \
  "Add dataset profiling engine for schema and quality summary" \
  "ai,data,backend,enhancement" \
"Implement lightweight profiling summaries for tabular data.

**Tasks:**
- Compute columns, types, missingness, uniqueness
- Add basic numeric stats and categorical cardinality
- Serialize summary for prompt usage

**Acceptance Criteria:**
- Profiling output can be consumed by prompt templates
- Profiling handles common dataset sizes without UI blocking"

# 10
create_issue \
  "Create prompt templates for import, cleaning, and EDA" \
  "ai,backend,enhancement,testing" \
"Create versioned prompt templates for key analysis intents.

**Tasks:**
- Import assistance template
- Data cleaning template
- EDA and visualization suggestion templates
- Unit tests for template assembly

**Acceptance Criteria:**
- Templates produce structured, deterministic sections
- Tests cover representative datasets and edge cases"

# 11
create_issue \
  "Build AI assistant panel with streaming responses" \
  "ai,frontend,enhancement" \
"Build assistant UI panel for natural-language interactions.

**Tasks:**
- Add chat-like interaction panel
- Support streamed responses
- Add loading/error/cancel states

**Acceptance Criteria:**
- User sees streaming partial responses
- Requests can be canceled safely"

# 12
create_issue \
  "Add per-interaction help mode selector" \
  "ai,frontend,enhancement" \
"Implement user-selectable help levels per interaction.

**Modes:**
- Advice only
- Explain first
- Write code
- Guided step-by-step

**Acceptance Criteria:**
- Mode is visible on each interaction
- Default mode can be persisted and overridden per request"

# 13
create_issue \
  "Implement code preview and apply confirmation flow" \
  "ai,frontend,security,enhancement" \
"Add safe apply flow for generated Julia code.

**Tasks:**
- Diff/preview UI before apply
- Explicit user confirmation step
- Provenance metadata tagging on applied code

**Acceptance Criteria:**
- No generated code is applied/executed without confirmation
- Applied suggestions include traceable provenance"

# 14
create_issue \
  "Build dataset import wizard for common formats" \
  "data,frontend,backend,enhancement" \
"Build dataset import flow for common formats.

**Formats:** CSV, TSV, Parquet, Arrow, JSON

**Tasks:**
- Source selection UI
- Delimiter/encoding/type options
- Generate robust Julia import snippets

**Acceptance Criteria:**
- CSV and Parquet workflows are complete in V1
- Import options are correctly reflected in generated code"

# 15
create_issue \
  "Implement cleaning module for missing values and type normalization" \
  "data,backend,enhancement" \
"Create reusable cleaning operations for basic quality improvements.

**Tasks:**
- Missing value strategies
- Type casting and normalization
- Reversible operation metadata for undo

**Acceptance Criteria:**
- Users can preview and apply missing-value and type fixes
- Operation metadata supports rollback behavior"

# 16
create_issue \
  "Implement cleaning widgets for duplicates, strings, and dates" \
  "data,frontend,enhancement" \
"Build UI widgets for common cleaning actions.

**Widgets:**
- Duplicate handling
- String cleanup and normalization
- Date parsing and standardization

**Acceptance Criteria:**
- Each widget can generate Julia transformation code
- Widgets support chaining in workflow order"

# 17
create_issue \
  "Build sidebar quick actions and action registry" \
  "frontend,enhancement" \
"Build context-aware sidebar and pluggable action registry.

**Default actions:**
- Load Data
- Profile Data
- Clean Data
- Plot Suggestions
- Export

**Acceptance Criteria:**
- Action availability reflects notebook context
- Action registry supports future extensibility"

# 18
create_issue \
  "Add keyboard shortcuts for common workflow actions" \
  "frontend,enhancement" \
"Add keyboard shortcuts to speed high-frequency actions.

**Tasks:**
- Define default bindings
- Resolve conflicts
- Show shortcut hints in UI

**Acceptance Criteria:**
- Shortcut map is documented
- Accessibility considerations are addressed"

# 19
create_issue \
  "Add export pipeline for HTML, Markdown, CSV, and report bundle" \
  "backend,data,enhancement" \
"Implement export pipeline for notebook outputs and analysis artifacts.

**Tasks:**
- Export HTML, Markdown, CSV artifacts
- Add reproducible report bundle output
- Attach provenance metadata in exported package

**Acceptance Criteria:**
- User can export from one consistent entry point
- Exports include generated-code provenance where applicable"

# 20
create_issue \
  "Add telemetry with redaction and usage metrics" \
  "backend,security,enhancement" \
"Add observability for AI feature usage and reliability.

**Metrics:**
- Latency
- Error rates
- Token usage
- Provider/model usage mix

**Acceptance Criteria:**
- Sensitive values are redacted prior to logging
- Metrics support dashboarding and regression tracking"

# 21
create_issue \
  "Security pass for prompt injection and unsafe code suggestions" \
  "security,ai,enhancement" \
"Implement baseline defenses for prompt injection and unsafe generated code.

**Tasks:**
- Add suspicious-instruction detection
- Add warning and confirmation gates for risky actions
- Add security-focused test cases

**Acceptance Criteria:**
- Risky generations trigger clear warnings
- Unsafe flows require explicit user approval"

# 22
create_issue \
  "End-to-end tests for import-clean-analyze workflow" \
  "testing,ai,data,frontend,backend" \
"Create deterministic end-to-end coverage for core user workflow.

**Flow:**
1. Import dataset
2. Profile data
3. Apply cleaning suggestions
4. Generate code
5. Preview and apply
6. Export

**Acceptance Criteria:**
- Tests cover success and common failure modes
- Provider behavior is mocked deterministically in CI"

# 23
create_issue \
  "Documentation and onboarding notebooks for AI features" \
  "documentation,ai,enhancement" \
"Create docs and example notebooks for onboarding and troubleshooting.

**Tasks:**
- Quickstart for provider setup
- Guided example: import → clean → analyze → export
- Troubleshooting and known limitations section

**Acceptance Criteria:**
- New users can complete first AI-assisted analysis from docs alone
- Docs include safety and privacy guidance"

# ── assign to Copilot ─────────────────────────────────────────────────────────

if $ASSIGN_COPILOT && [[ ${#CREATED_ISSUES[@]} -gt 0 ]]; then
  echo ""
  echo "==> Assigning ${#CREATED_ISSUES[@]} issues to GitHub Copilot..."
  echo "    (Requires Copilot coding agent enabled on repo Settings → Copilot → Coding agent)"
  for num in "${CREATED_ISSUES[@]}"; do
    echo "  → issue #$num"
    gh issue edit "$num" --repo "$REPO" --add-assignee "copilot" 2>&1 \
      || echo "    ⚠ assignment failed (Copilot agent may not be enabled)"
  done
fi

echo ""
echo "✓ Done. Created ${#CREATED_ISSUES[@]} of 23 issues."
echo "  View at: https://github.com/$REPO/issues"
