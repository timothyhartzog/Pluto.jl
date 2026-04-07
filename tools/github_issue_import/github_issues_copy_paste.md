# Pluto AI GitHub Issues (Copy/Paste Ready)

Use this file to create issues manually in GitHub:

1. Open: Repository -> Issues -> New issue
2. Copy the Title into the issue title field
3. Copy the Labels list and add those labels in GitHub
4. Copy the Body into the issue description

---

## 1) EPIC: Multi-provider AI integration for notebook assistance

Title:
EPIC: Multi-provider AI integration for notebook assistance

Labels:
epic, ai, backend, enhancement

Body:
Problem:
Need pluggable support for cloud and local LLMs.

Goal:
Unified API for provider calls with robust errors and retries.

Scope:
- Provider interface for completion and code generation
- Cloud adapter
- Ollama adapter
- Shared error taxonomy
- Integration tests with mocks

Acceptance Criteria:
- At least one cloud provider and Ollama are supported
- Provider can be switched without UI changes
- Errors are normalized and surfaced clearly to users

Copilot Prompt:
Create a provider abstraction for AI completion and code-generation calls. Add adapters for one cloud provider and Ollama, plus typed error handling and tests.

---

## 2) EPIC: Dataset import, cleaning, and analysis assistance

Title:
EPIC: Dataset import, cleaning, and analysis assistance

Labels:
epic, ai, data, enhancement

Body:
Problem:
Users need guided analysis from raw data to insight.

Goal:
AI assists with import, cleaning, and Julia code generation using safe apply flows.

Scope:
- Dataset import assistant
- Data profiling summary
- Cleaning widgets and modules
- Analysis suggestions and code generation

Acceptance Criteria:
- User can import datasets via guided workflow
- User can apply common cleaning tasks with widget support
- AI-generated code is previewed before apply

Copilot Prompt:
Build structured actions for data import and cleaning, with Julia code generation and apply-preview UX.

---

## 3) EPIC: Sidebar quick actions and guided help modes

Title:
EPIC: Sidebar quick actions and guided help modes

Labels:
epic, ai, frontend, enhancement

Body:
Problem:
Frequent actions are too manual and slow.

Goal:
Provide fast sidebar actions and per-interaction help controls.

Scope:
- Sidebar quick actions
- Keyboard shortcuts
- Help mode controls and persistence

Acceptance Criteria:
- Sidebar supports common analysis actions
- Help mode can be changed per interaction
- Help mode settings persist as designed

Copilot Prompt:
Implement sidebar action registry with help-mode selector and shortcut bindings.

---

## 4) EPIC: Trust, observability, reproducibility, and export

Title:
EPIC: Trust, observability, reproducibility, and export

Labels:
epic, ai, security, enhancement

Body:
Problem:
AI features need safety, transparency, and reproducibility.

Goal:
Add redaction, provenance metadata, usage metrics, and export support.

Scope:
- Telemetry with redaction
- Provenance tagging for generated code
- Multi-format export
- Safety and policy checks

Acceptance Criteria:
- Sensitive values are redacted from telemetry
- Generated code includes provenance metadata
- Export works for required formats

Copilot Prompt:
Add telemetry hooks with redaction, provenance metadata on generated code, and export pipeline for HTML/Markdown/artifacts.

---

## 5) Define AI provider interface and response schema

Title:
Define AI provider interface and response schema

Labels:
ai, backend, enhancement

Body:
Implement typed provider interfaces for completion, streaming, and code generation tasks.

Tasks:
- Define provider API contracts
- Define structured response schema
- Define shared error taxonomy
- Add schema validation and unit tests

Acceptance Criteria:
- Interface supports prompt, streamed prompt, and code-generation intents
- Structured response validation catches malformed provider outputs
- Tests cover valid and invalid payloads

---

## 6) Implement Ollama adapter with model configuration

Title:
Implement Ollama adapter with model configuration

Labels:
ai, backend, enhancement

Body:
Implement local Ollama adapter using the provider interface.

Tasks:
- Add configurable host and model
- Add timeout and retry logic
- Map Ollama-specific failures into shared errors
- Add integration tests with mocked responses

Acceptance Criteria:
- Local model calls succeed with configurable host/model
- Unavailable model and server failures return clear errors

---

## 7) Implement cloud provider adapter with secure key handling

Title:
Implement cloud provider adapter with secure key handling

Labels:
ai, backend, security, enhancement

Body:
Implement first cloud provider adapter with secure key handling and robust failure behavior.

Tasks:
- Add API key configuration path
- Ensure secrets are never logged
- Add auth, rate-limit, timeout handling
- Add retry policy and tests

Acceptance Criteria:
- Auth and quota errors are mapped into shared taxonomy
- Secret values do not appear in logs

---

## 8) Build notebook context assembler for prompt generation

Title:
Build notebook context assembler for prompt generation

Labels:
ai, backend, enhancement

Body:
Create notebook-aware context assembly for AI prompts.

Tasks:
- Collect user request, notebook state, recent outputs
- Include dataset profile summaries
- Enforce context limits and truncation policies

Acceptance Criteria:
- Context avoids oversized payloads and supports summarization fallback
- Prompt assembly is deterministic and testable

---

## 9) Add dataset profiling engine for schema and quality summary

Title:
Add dataset profiling engine for schema and quality summary

Labels:
ai, data, backend, enhancement

Body:
Implement lightweight profiling summaries for tabular data.

Tasks:
- Compute columns, types, missingness, uniqueness
- Add basic numeric stats and categorical cardinality
- Serialize summary for prompt usage

Acceptance Criteria:
- Profiling output can be consumed by prompt templates
- Profiling handles common dataset sizes without UI blocking

---

## 10) Create prompt templates for import, cleaning, and EDA

Title:
Create prompt templates for import, cleaning, and EDA

Labels:
ai, backend, enhancement, testing

Body:
Create versioned prompt templates for key analysis intents.

Tasks:
- Import assistance template
- Data cleaning template
- EDA and visualization suggestion templates
- Unit tests for template assembly

Acceptance Criteria:
- Templates produce structured, deterministic sections
- Tests cover representative datasets and edge cases

---

## 11) Build AI assistant panel with streaming responses

Title:
Build AI assistant panel with streaming responses

Labels:
ai, frontend, enhancement

Body:
Build assistant UI panel for natural-language interactions.

Tasks:
- Add chat-like interaction panel
- Support streamed responses
- Add loading/error/cancel states

Acceptance Criteria:
- User sees streaming partial responses
- Requests can be canceled safely

---

## 12) Add per-interaction help mode selector

Title:
Add per-interaction help mode selector

Labels:
ai, frontend, enhancement

Body:
Implement user-selectable help levels per interaction.

Modes:
- Advice only
- Explain first
- Write code
- Guided step-by-step

Acceptance Criteria:
- Mode is visible on each interaction
- Default mode can be persisted and overridden per request

---

## 13) Implement code preview and apply confirmation flow

Title:
Implement code preview and apply confirmation flow

Labels:
ai, frontend, security, enhancement

Body:
Add safe apply flow for generated Julia code.

Tasks:
- Diff/preview UI before apply
- Explicit user confirmation step
- Provenance metadata tagging on applied code

Acceptance Criteria:
- No generated code is applied/executed without confirmation
- Applied suggestions include traceable provenance

---

## 14) Build dataset import wizard for common formats

Title:
Build dataset import wizard for common formats

Labels:
data, frontend, backend, enhancement

Body:
Build dataset import flow for common formats.

Formats:
- CSV, TSV, Parquet, Arrow, JSON

Tasks:
- Source selection UI
- Delimiter/encoding/type options
- Generate robust Julia import snippets

Acceptance Criteria:
- CSV and Parquet workflows are complete in V1
- Import options are correctly reflected in generated code

---

## 15) Implement cleaning module for missing values and type normalization

Title:
Implement cleaning module for missing values and type normalization

Labels:
data, backend, enhancement

Body:
Create reusable cleaning operations for basic quality improvements.

Tasks:
- Missing value strategies
- Type casting and normalization
- Reversible operation metadata for undo

Acceptance Criteria:
- Users can preview and apply missing-value and type fixes
- Operation metadata supports rollback behavior

---

## 16) Implement cleaning widgets for duplicates, strings, and dates

Title:
Implement cleaning widgets for duplicates, strings, and dates

Labels:
data, frontend, enhancement

Body:
Build UI widgets for common cleaning actions.

Widgets:
- Duplicate handling
- String cleanup and normalization
- Date parsing and standardization

Acceptance Criteria:
- Each widget can generate Julia transformation code
- Widgets support chaining in workflow order

---

## 17) Build sidebar quick actions and action registry

Title:
Build sidebar quick actions and action registry

Labels:
frontend, enhancement

Body:
Build context-aware sidebar and pluggable action registry.

Default actions:
- Load Data
- Profile Data
- Clean Data
- Plot Suggestions
- Export

Acceptance Criteria:
- Action availability reflects notebook context
- Action registry supports future extensibility

---

## 18) Add keyboard shortcuts for common workflow actions

Title:
Add keyboard shortcuts for common workflow actions

Labels:
frontend, enhancement

Body:
Add keyboard shortcuts to speed high-frequency actions.

Tasks:
- Define default bindings
- Resolve conflicts
- Show shortcut hints in UI

Acceptance Criteria:
- Shortcut map is documented
- Accessibility considerations are addressed

---

## 19) Add export pipeline for HTML, Markdown, CSV, and report bundle

Title:
Add export pipeline for HTML, Markdown, CSV, and report bundle

Labels:
backend, data, enhancement

Body:
Implement export pipeline for notebook outputs and analysis artifacts.

Tasks:
- Export HTML, Markdown, CSV artifacts
- Add reproducible report bundle output
- Attach provenance metadata in exported package

Acceptance Criteria:
- User can export from one consistent entry point
- Exports include generated-code provenance where applicable

---

## 20) Add telemetry with redaction and usage metrics

Title:
Add telemetry with redaction and usage metrics

Labels:
backend, security, enhancement

Body:
Add observability for AI feature usage and reliability.

Metrics:
- Latency
- Error rates
- Token usage
- Provider/model usage mix

Acceptance Criteria:
- Sensitive values are redacted prior to logging
- Metrics support dashboarding and regression tracking

---

## 21) Security pass for prompt injection and unsafe code suggestions

Title:
Security pass for prompt injection and unsafe code suggestions

Labels:
security, ai, enhancement

Body:
Implement baseline defenses for prompt injection and unsafe generated code.

Tasks:
- Add suspicious-instruction detection
- Add warning and confirmation gates for risky actions
- Add security-focused test cases

Acceptance Criteria:
- Risky generations trigger clear warnings
- Unsafe flows require explicit user approval

---

## 22) End-to-end tests for import-clean-analyze workflow

Title:
End-to-end tests for import-clean-analyze workflow

Labels:
testing, ai, data, frontend, backend

Body:
Create deterministic end-to-end coverage for core user workflow.

Flow:
- Import dataset
- Profile data
- Apply cleaning suggestions
- Generate code
- Preview and apply
- Export

Acceptance Criteria:
- Tests cover success and common failure modes
- Provider behavior is mocked deterministically in CI

---

## 23) Documentation and onboarding notebooks for AI features

Title:
Documentation and onboarding notebooks for AI features

Labels:
documentation, ai, enhancement

Body:
Create docs and example notebooks for onboarding and troubleshooting.

Tasks:
- Quickstart for provider setup
- Guided example: import -> clean -> analyze -> export
- Troubleshooting and known limitations section

Acceptance Criteria:
- New users can complete first AI-assisted analysis from docs alone
- Docs include safety and privacy guidance
