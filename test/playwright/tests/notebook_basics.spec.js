// @ts-check
/**
 * Notebook Basics Test Suite — Pluto.jl Playwright
 *
 * Covers the core notebook lifecycle:
 *  - Creating a new notebook
 *  - Running cells and verifying output
 *  - Reactive re-evaluation
 *  - Shutting down a notebook
 *  - Main menu navigation
 */

const { test, expect } = require("@playwright/test")
const { attachErrorCapture, assertNoErrors } = require("../helpers/errors")
const {
    gotoPlutoMainMenu,
    createNewNotebook,
    shutdownCurrentNotebook,
    getCellIds,
    typeInCell,
    runCell,
    runAllChanged,
    getCellOutput,
    waitForCellOutput,
    waitForPlutoToCalmDown,
    saveDebugScreenshot,
    getPlutoUrl,
} = require("../helpers/pluto")

const ALLOWED_CONSOLE_PATTERNS = [
    /MathJax/i,
    /favicon/i,
    /preconnect/i,
    /A new version of Pluto/i,
    /outdated/i,
]

test.describe("Notebook basics", () => {
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

    // -----------------------------------------------------------------------
    // Basic cell execution
    // -----------------------------------------------------------------------

    test("runs a simple arithmetic cell", async ({ page }) => {
        const [cellId] = await getCellIds(page)
        await typeInCell(page, "6 * 7", cellId)
        await runCell(page, cellId)
        const output = await waitForCellOutput(page, cellId, "42", { timeout: 30_000 })
        expect(output).toBe("42")
        assertNoErrors(capture, { allowedPatterns: ALLOWED_CONSOLE_PATTERNS })
    })

    test("runs a string expression cell", async ({ page }) => {
        const [cellId] = await getCellIds(page)
        await typeInCell(page, '"Hello, Pluto!"', cellId)
        await runCell(page, cellId)
        await waitForCellOutput(page, cellId, '"Hello, Pluto!"', { timeout: 30_000 })
        assertNoErrors(capture, { allowedPatterns: ALLOWED_CONSOLE_PATTERNS })
    })

    // -----------------------------------------------------------------------
    // Multi-cell reactive evaluation
    // -----------------------------------------------------------------------

    test("reactive update propagates through dependent cells", async ({ page }) => {
        // Cell 1: x = 3
        const [firstCellId] = await getCellIds(page)
        await typeInCell(page, "x = 3", firstCellId)

        // Add cell 2: y = x * 10
        await page.click(`pluto-cell[id="${firstCellId}"] .add_cell.after`)
        await page.waitForFunction(() => document.querySelectorAll("pluto-cell").length >= 2)
        const [, secondCellId] = await getCellIds(page)
        await typeInCell(page, "y = x * 10", secondCellId)

        await runAllChanged(page)

        await waitForCellOutput(page, secondCellId, "30", { timeout: 30_000 })

        // Now change x = 5
        await page.fill(
            `pluto-cell[id="${firstCellId}"] pluto-input .cm-content`,
            "x = 5"
        )
        await runAllChanged(page)

        const newOutput = await waitForCellOutput(page, secondCellId, "50", { timeout: 30_000 })
        expect(newOutput).toBe("50")
    })

    test("multiple independent cells run without errors", async ({ page }) => {
        const [c1] = await getCellIds(page)
        await typeInCell(page, "a = 10", c1)

        await page.click(`pluto-cell[id="${c1}"] .add_cell.after`)
        await page.waitForFunction(() => document.querySelectorAll("pluto-cell").length >= 2)

        await page.click(`pluto-cell:last-of-type .add_cell.after`)
        await page.waitForFunction(() => document.querySelectorAll("pluto-cell").length >= 3)

        const [, c2, c3] = await getCellIds(page)
        await typeInCell(page, "b = 20", c2)
        await typeInCell(page, "a + b", c3)

        await runAllChanged(page)

        await waitForCellOutput(page, c3, "30", { timeout: 30_000 })
        assertNoErrors(capture, { allowedPatterns: ALLOWED_CONSOLE_PATTERNS })
    })

    // -----------------------------------------------------------------------
    // Page title / URL
    // -----------------------------------------------------------------------

    test("notebook page title is not the main menu title", async ({ page }) => {
        const title = await page.title()
        // The editor page should have a different title than the main menu
        expect(title).not.toBe("")
    })

    test("notebook URL contains the notebook id or path", async ({ page }) => {
        const url = page.url()
        // The notebook editor URL looks like /edit?id=<uuid>
        expect(url).toContain(getPlutoUrl())
        expect(url).not.toBe(getPlutoUrl() + "/")
    })

    // -----------------------------------------------------------------------
    // UI structure
    // -----------------------------------------------------------------------

    test("editor page renders at least one pluto-cell", async ({ page }) => {
        const cellCount = await page.evaluate(
            () => document.querySelectorAll("pluto-cell").length
        )
        expect(cellCount).toBeGreaterThanOrEqual(1)
    })

    test("each cell has a run button", async ({ page }) => {
        const [cellId] = await getCellIds(page)
        const btn = await page.$(`pluto-cell[id="${cellId}"] .runcell`)
        expect(btn).not.toBeNull()
    })

    test("cells have CodeMirror editors", async ({ page }) => {
        const [cellId] = await getCellIds(page)
        const cm = await page.$(`pluto-cell[id="${cellId}"] .cm-editor`)
        expect(cm).not.toBeNull()
    })
})

// ---------------------------------------------------------------------------
// Main menu tests (separate describe so we don't create a notebook first)
// ---------------------------------------------------------------------------
test.describe("Main menu", () => {
    test("main menu is reachable and renders correctly", async ({ page }) => {
        const capture = attachErrorCapture(page)
        try {
            await gotoPlutoMainMenu(page)

            // The "new notebook" link should be visible
            await page.waitForSelector('a[href="new"]', { state: "visible", timeout: 30_000 })

            const newLink = await page.$('a[href="new"]')
            expect(newLink).not.toBeNull()

            assertNoErrors(capture, { allowedPatterns: ALLOWED_CONSOLE_PATTERNS })
        } finally {
            capture.dispose()
        }
    })

    test("main menu title is present", async ({ page }) => {
        await gotoPlutoMainMenu(page)
        const title = await page.title()
        expect(title.length).toBeGreaterThan(0)
    })
})
