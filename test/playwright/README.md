# Pluto.jl — Playwright End-to-End Tests

This directory contains a complete Playwright-based end-to-end testing framework
for Pluto.jl, including an extensive browser error handling toolkit.

## Directory structure

```
test/playwright/
├── playwright.config.js        # Playwright configuration
├── package.json                # Node dependencies
├── helpers/
│   ├── errors.js               # Browser error-capture utilities
│   ├── pluto.js                # Pluto-specific page helpers
│   ├── global-setup.js         # Pre-test server health check
│   └── global-teardown.js      # Post-test summary
├── tests/
│   ├── error_handling.spec.js  # Error capture helper tests + cell error tests
│   └── notebook_basics.spec.js # Core notebook lifecycle tests
├── fixtures/
│   ├── error_notebook.jl       # Notebook with intentional errors
│   └── simple_notebook.jl      # Simple arithmetic notebook
└── artifacts/                  # Screenshots, reports, traces (git-ignored)
```

## Running the tests

### Prerequisites

1. Start a Pluto server and note the port:
   ```julia
   using Pluto
   Pluto.run(port=1234)
   ```
2. Install dependencies:
   ```sh
   cd test/playwright
   npm install
   npx playwright install chromium
   ```

### Run all tests

```sh
PLUTO_PORT=1234 npm test
```

### Run with headed browser (visible window)

```sh
PLUTO_PORT=1234 npm run test:headed
```

### Run in debug mode (step-through)

```sh
PLUTO_PORT=1234 npm run test:debug
```

### View HTML report

```sh
npm run report
```

---

## Error handling framework (`helpers/errors.js`)

The `attachErrorCapture(page)` function returns an `ErrorCapture` object that
automatically collects:

| Event type        | Captured in        |
|-------------------|--------------------|
| `console.error`   | `capture.console`  |
| `console.warn`    | `capture.console`  |
| Uncaught JS error | `capture.pageErrors` |
| Request failure   | `capture.network`  |

Key utilities:

```js
const capture = attachErrorCapture(page)

// Check for errors
capture.hasErrors()               // → boolean
capture.errors()                  // → ConsoleEntry[]
capture.warnings()                // → ConsoleEntry[]
capture.summary()                 // → ErrorSummary

// Wait for N console errors (or timeout)
await waitForErrors(page, capture, 2)

// Assert clean – throws if unexpected errors are found
assertNoErrors(capture, { allowedPatterns: [/MathJax/i] })

// Reset for the next assertion block
capture.clear()

// Remove listeners when done
capture.dispose()
```

## Julia ErrorHandling module (`src/analysis/ErrorHandling.jl`)

A companion Julia module exposed as `Pluto.ErrorHandling` that provides:

- `ErrorCategory` enum — SYNTAX_ERROR, RUNTIME_ERROR, PACKAGE_ERROR,
  NETWORK_ERROR, TIMEOUT_ERROR, WORKSPACE_ERROR, CELL_ERROR, UNKNOWN_ERROR
- `ErrorSeverity` enum — SEVERITY_LOW … SEVERITY_CRITICAL
- `PlutoError` struct — structured error with category, severity, message,
  exception, stacktrace, cell_id, timestamp, context
- `ErrorLog` — ring-buffer log with configurable `max_size`
- `wrap_error(e)` — convert any throwable to a `PlutoError`
- `log_error!(log, e)` — capture and store an error
- `summarize_errors(log)` — aggregated counts by category / severity
- `retry_with_backoff(f)` — exponential back-off retry for recoverable errors
