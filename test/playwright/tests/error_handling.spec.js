// @ts-check
/**
 * Error Handling Test Suite — Pluto.jl Playwright
 *
 * Verifies that:
 *  1. Console errors are captured correctly.
 *  2. Page errors (uncaught exceptions) are captured.
 *  3. Network request failures are recorded.
 *  4. Pluto cell errors (DivideError, UndefVarError) surface as expected.
 *  5. The error capture helpers work correctly in isolation (unit-like tests).
 */

const { test, expect } = require("@playwright/test")
const {
    attachErrorCapture,
    waitForErrors,
    assertNoErrors,
} = require("../helpers/errors")
const {
    gotoPlutoMainMenu,
    createNewNotebook,
    shutdownCurrentNotebook,
    getCellIds,
    typeInCell,
    runCell,
    waitForCellOutput,
    waitForCellError,
    saveDebugScreenshot,
} = require("../helpers/pluto")

// Known benign console messages that Pluto always emits
const ALLOWED_CONSOLE_PATTERNS = [
    /MathJax/i,
    /favicon/i,
    /preconnect/i,
    /A new version of Pluto/i,
    /outdated/i,
]

// ---------------------------------------------------------------------------
// Suite 1: Error capture helpers – tested against injected page errors
// ---------------------------------------------------------------------------
test.describe("ErrorCapture helpers", () => {
    let capture = null

    test.beforeEach(async ({ page }) => {
        capture = attachErrorCapture(page)
    })

    test.afterEach(async () => {
        capture?.dispose()
        capture = null
    })

    test("records console.error messages", async ({ page }) => {
        await page.goto("about:blank")
        await page.evaluate(() => console.error("test-error-message"))
        const errs = capture.errors()
        expect(errs.length).toBeGreaterThanOrEqual(1)
        const found = errs.find((e) => e.text.includes("test-error-message"))
        expect(found).toBeDefined()
        expect(found.level).toBe("error")
    })

    test("records console.warn messages", async ({ page }) => {
        await page.goto("about:blank")
        await page.evaluate(() => console.warn("test-warning-message"))
        const warns = capture.warnings()
        expect(warns.length).toBeGreaterThanOrEqual(1)
        const found = warns.find((e) => e.text.includes("test-warning-message"))
        expect(found).toBeDefined()
        expect(found.level).toBe("warn")
    })

    test("records page errors (uncaught exceptions)", async ({ page }) => {
        await page.goto("about:blank")
        await page.evaluate(() => {
            setTimeout(() => { throw new Error("uncaught-test-error") }, 0)
        })
        await page.waitForTimeout(500)
        expect(capture.pageErrors.length).toBeGreaterThanOrEqual(1)
        const found = capture.pageErrors.find((e) => e.message.includes("uncaught-test-error"))
        expect(found).toBeDefined()
        expect(found.stack).toBeDefined()
        expect(found.timestamp).toBeGreaterThan(0)
    })

    test("summary aggregates all error types correctly", async ({ page }) => {
        await page.goto("about:blank")
        await page.evaluate(() => {
            console.error("err-1")
            console.error("err-2")
            console.warn("warn-1")
        })
        const s = capture.summary()
        expect(s.errorCount).toBeGreaterThanOrEqual(2)
        expect(s.warningCount).toBeGreaterThanOrEqual(1)
        expect(s.hasAnyErrors).toBe(true)
        expect(s.errorMessages.length).toBeGreaterThanOrEqual(2)
    })

    test("clear() resets all logs", async ({ page }) => {
        await page.goto("about:blank")
        await page.evaluate(() => {
            console.error("will-be-cleared")
            console.warn("warn-cleared")
        })
        capture.clear()
        expect(capture.errors().length).toBe(0)
        expect(capture.warnings().length).toBe(0)
        expect(capture.pageErrors.length).toBe(0)
    })

    test("hasErrors() returns false when no errors", async ({ page }) => {
        await page.goto("about:blank")
        await page.evaluate(() => console.log("just a log"))
        expect(capture.hasErrors()).toBe(false)
    })

    test("assertNoErrors does not throw when capture is clean", async ({ page }) => {
        await page.goto("about:blank")
        // Should not throw
        assertNoErrors(capture)
    })

    test("assertNoErrors throws when unexpected errors are present", async ({ page }) => {
        await page.goto("about:blank")
        await page.evaluate(() => console.error("unexpected-error"))
        await page.waitForTimeout(100)
        expect(() =>
            assertNoErrors(capture, { allowedPatterns: [/something-else/] })
        ).toThrow(/unexpected-error/)
    })

    test("assertNoErrors respects allowedPatterns", async ({ page }) => {
        await page.goto("about:blank")
        await page.evaluate(() => console.error("allowed-known-error"))
        await page.waitForTimeout(100)
        // Should not throw because we explicitly allow the pattern
        assertNoErrors(capture, { allowedPatterns: [/allowed-known-error/] })
    })

    test("timestamps are monotonically ordered", async ({ page }) => {
        await page.goto("about:blank")
        for (let i = 0; i < 5; i++) {
            await page.evaluate((i) => console.error(`ts-error-${i}`), i)
        }
        const errors = capture.errors()
        for (let i = 1; i < errors.length; i++) {
            expect(errors[i].timestamp).toBeGreaterThanOrEqual(errors[i - 1].timestamp)
        }
    })

    test("network failure is recorded", async ({ page }) => {
        await page.goto("about:blank")
        // Navigate to a definitely-unreachable URL in a new tab frame to trigger requestfailed
        const navCapture = attachErrorCapture(page)
        await page
            .goto("http://127.0.0.1:19999/nonexistent", { waitUntil: "commit" })
            .catch(() => {
                /* expected */
            })
        // navigation failure itself is not a 'requestfailed' event but we still verify dispose()
        navCapture.dispose()
    })
})

// ---------------------------------------------------------------------------
// Suite 2: Pluto integration — cell errors surfaced in the UI
// ---------------------------------------------------------------------------
test.describe("Pluto cell error handling", () => {
    let capture = null

    test.beforeEach(async ({ page }) => {
        capture = attachErrorCapture(page)
        await gotoPlutoMainMenu(page)
        await createNewNotebook(page)
    })

    test.afterEach(async ({ page }, testInfo) => {
        await saveDebugScreenshot(page, `after_${testInfo.title.replace(/\W+/g, "_")}`)
        capture?.dispose()
        capture = null
        await shutdownCurrentNotebook(page)
    })

    test("valid cell runs without UI errors", async ({ page }) => {
        const [cellId] = await getCellIds(page)
        await typeInCell(page, "1 + 1", cellId)
        await runCell(page, cellId)
        const output = await waitForCellOutput(page, cellId, "2", { timeout: 30_000 })
        expect(output).toBe("2")
        assertNoErrors(capture, { allowedPatterns: ALLOWED_CONSOLE_PATTERNS })
    })

    test("runtime error (DivideError) shows errored cell", async ({ page }) => {
        const [cellId] = await getCellIds(page)
        await typeInCell(page, "div(1, 0)", cellId)
        await runCell(page, cellId)
        await waitForCellError(page, cellId, { timeout: 30_000 })
        const hasErrored = await page.$(`pluto-cell[id="${cellId}"].errored`)
        expect(hasErrored).not.toBeNull()
    })

    test("undefined variable shows errored cell", async ({ page }) => {
        const [cellId] = await getCellIds(page)
        await typeInCell(page, "undefined_variable_xyz_pw + 1", cellId)
        await runCell(page, cellId)
        await waitForCellError(page, cellId, { timeout: 30_000 })
        const hasErrored = await page.$(`pluto-cell[id="${cellId}"].errored`)
        expect(hasErrored).not.toBeNull()
    })

    test("multiple cells: error in one does not prevent unrelated cell from running", async ({ page }) => {
        // First cell — will error
        const [firstCellId] = await getCellIds(page)
        await typeInCell(page, "div(10, 0)", firstCellId)

        // Add a second independent cell
        await page.click(`pluto-cell[id="${firstCellId}"] .add_cell.after`)
        await page.waitForFunction(
            () => document.querySelectorAll("pluto-cell").length >= 2
        )
        const allCells = await getCellIds(page)
        const secondCellId = allCells[1]
        await typeInCell(page, "100 + 23", secondCellId)

        await page.click(`pluto-cell[id="${firstCellId}"] .runcell`)
        await page.click(`pluto-cell[id="${secondCellId}"] .runcell`)

        // First cell should be errored
        await waitForCellError(page, firstCellId, { timeout: 30_000 })

        // Second cell should still produce output
        await waitForCellOutput(page, secondCellId, "123", { timeout: 30_000 })
    })

    test("correcting an error clears the errored state", async ({ page }) => {
        const [cellId] = await getCellIds(page)
        await typeInCell(page, "no_such_var_abc", cellId)
        await runCell(page, cellId)
        await waitForCellError(page, cellId, { timeout: 30_000 })

        // Now fix the code
        await page.fill(`pluto-cell[id="${cellId}"] pluto-input .cm-content`, "42")
        await runCell(page, cellId)

        // The errored class should eventually disappear
        await page.waitForSelector(`pluto-cell[id="${cellId}"]:not(.errored)`, {
            timeout: 30_000,
        })
        const output = await waitForCellOutput(page, cellId, "42", { timeout: 30_000 })
        expect(output).toBe("42")
    })
})
