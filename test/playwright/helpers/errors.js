// @ts-check
/**
 * Browser-error capture utilities for Pluto Playwright tests.
 *
 * Provides structured recording of console messages, page errors, and
 * failed network requests so tests can assert on error state rather than
 * relying on brittle timing waits.
 */

/**
 * @typedef {Object} ConsoleEntry
 * @property {"log"|"info"|"warn"|"error"|"debug"} level
 * @property {string} text
 * @property {number} timestamp
 */

/**
 * @typedef {Object} NetworkEntry
 * @property {string} url
 * @property {"failed"|"aborted"} reason
 * @property {number} timestamp
 */

/**
 * @typedef {Object} PageErrorEntry
 * @property {string} message
 * @property {string} stack
 * @property {number} timestamp
 */

/**
 * @typedef {Object} ErrorCapture
 * @property {ConsoleEntry[]} console
 * @property {NetworkEntry[]} network
 * @property {PageErrorEntry[]} pageErrors
 * @property {() => void} dispose
 * @property {() => ConsoleEntry[]} errors
 * @property {() => ConsoleEntry[]} warnings
 * @property {() => boolean} hasErrors
 * @property {() => boolean} hasWarnings
 * @property {() => void} clear
 * @property {() => ErrorSummary} summary
 */

/**
 * @typedef {Object} ErrorSummary
 * @property {number} totalConsole
 * @property {number} errorCount
 * @property {number} warningCount
 * @property {number} networkFailures
 * @property {number} pageErrors
 * @property {boolean} hasAnyErrors
 * @property {string[]} errorMessages
 */

/**
 * Attach error capture listeners to a Playwright page.
 *
 * @param {import("@playwright/test").Page} page
 * @returns {ErrorCapture}
 */
function attachErrorCapture(page) {
    /** @type {ConsoleEntry[]} */
    const consoleLog = []
    /** @type {NetworkEntry[]} */
    const networkLog = []
    /** @type {PageErrorEntry[]} */
    const pageErrorLog = []

    /** @param {import("@playwright/test").ConsoleMessage} msg */
    const onConsole = (msg) => {
        consoleLog.push({
            level: /** @type {any} */ (msg.type()),
            text: msg.text(),
            timestamp: Date.now(),
        })
    }

    /** @param {Error} err */
    const onPageError = (err) => {
        pageErrorLog.push({
            message: err.message,
            stack: err.stack || "",
            timestamp: Date.now(),
        })
    }

    /** @param {import("@playwright/test").Request} req */
    const onRequestFailed = (req) => {
        networkLog.push({
            url: req.url(),
            reason: req.failure()?.errorText === "net::ERR_ABORTED" ? "aborted" : "failed",
            timestamp: Date.now(),
        })
    }

    page.on("console", onConsole)
    page.on("pageerror", onPageError)
    page.on("requestfailed", onRequestFailed)

    return {
        console: consoleLog,
        network: networkLog,
        pageErrors: pageErrorLog,

        dispose() {
            page.off("console", onConsole)
            page.off("pageerror", onPageError)
            page.off("requestfailed", onRequestFailed)
        },

        errors() {
            return consoleLog.filter((e) => e.level === "error")
        },

        warnings() {
            return consoleLog.filter((e) => e.level === "warn")
        },

        hasErrors() {
            return this.errors().length > 0 || pageErrorLog.length > 0
        },

        hasWarnings() {
            return this.warnings().length > 0
        },

        clear() {
            consoleLog.length = 0
            networkLog.length = 0
            pageErrorLog.length = 0
        },

        summary() {
            const errs = this.errors()
            return {
                totalConsole: consoleLog.length,
                errorCount: errs.length,
                warningCount: this.warnings().length,
                networkFailures: networkLog.length,
                pageErrors: pageErrorLog.length,
                hasAnyErrors: this.hasErrors(),
                errorMessages: [
                    ...errs.map((e) => `[console.error] ${e.text}`),
                    ...pageErrorLog.map((e) => `[pageerror] ${e.message}`),
                ],
            }
        },
    }
}

/**
 * Wait until the error capture has at least `count` console-error entries
 * or the timeout elapses.
 *
 * @param {import("@playwright/test").Page} page
 * @param {ErrorCapture} capture
 * @param {number} count
 * @param {number} [timeoutMs=10000]
 */
async function waitForErrors(page, capture, count = 1, timeoutMs = 10_000) {
    const deadline = Date.now() + timeoutMs
    while (Date.now() < deadline) {
        if (capture.errors().length >= count) return
        await page.waitForTimeout(100)
    }
    throw new Error(
        `Expected ${count} console error(s) within ${timeoutMs}ms, but only got ${capture.errors().length}.\n` +
            `Captured errors: ${JSON.stringify(capture.errors(), null, 2)}`
    )
}

/**
 * Assert that no unexpected errors were captured.  Throws if any are found.
 *
 * @param {ErrorCapture} capture
 * @param {{ allowedPatterns?: RegExp[] }} [options]
 */
function assertNoErrors(capture, { allowedPatterns = [] } = {}) {
    const unexpectedErrors = [
        ...capture.errors().map((e) => e.text),
        ...capture.pageErrors.map((e) => e.message),
    ].filter((msg) => !allowedPatterns.some((p) => p.test(msg)))

    if (unexpectedErrors.length > 0) {
        throw new Error(
            `Unexpected browser errors detected (${unexpectedErrors.length}):\n` +
                unexpectedErrors.map((m) => `  • ${m}`).join("\n")
        )
    }
}

module.exports = { attachErrorCapture, waitForErrors, assertNoErrors }
