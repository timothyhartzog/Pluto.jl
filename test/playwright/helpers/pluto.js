// @ts-check
/**
 * Pluto-specific Playwright helpers.
 *
 * Provides high-level actions for navigating to Pluto, creating/opening
 * notebooks, running cells, and waiting for the UI to settle.
 */

const path = require("path")
const fs = require("fs")

const PLUTO_PORT = process.env.PLUTO_PORT || "1234"

/** @returns {string} */
const getPlutoUrl = () => `http://localhost:${PLUTO_PORT}`

const FIXTURES_DIR = path.join(__dirname, "..", "fixtures")
const ARTIFACTS_DIR = path.join(__dirname, "..", "artifacts")

/** @param {string} name */
const getFixturePath = (name) => path.join(FIXTURES_DIR, name)

/** @param {string} suffix */
const getTempNotebookPath = (suffix = "") =>
    path.join(ARTIFACTS_DIR, `temp_notebook_${suffix}_${Date.now()}.jl`)

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

/**
 * Navigate to the Pluto main menu and wait for it to be ready.
 *
 * @param {import("@playwright/test").Page} page
 */
async function gotoPlutoMainMenu(page) {
    await page.goto(getPlutoUrl(), { waitUntil: "domcontentloaded" })
    // Wait until the "not yet ready" class is removed from the body
    await page.waitForFunction(() => document.querySelector(".not_yet_ready") == null, {
        timeout: 60_000,
    })
}

/**
 * Create a new notebook from the Pluto main menu.
 *
 * @param {import("@playwright/test").Page} page
 */
async function createNewNotebook(page) {
    await page.waitForSelector('a[href="new"]')
    await Promise.all([page.waitForNavigation({ waitUntil: "domcontentloaded" }), page.click('a[href="new"]')])
    await page.waitForSelector("pluto-input", { state: "visible", timeout: 60_000 })
    await waitForPlutoToCalmDown(page)
}

/**
 * Open a notebook by its absolute file-system path.
 *
 * @param {import("@playwright/test").Page} page
 * @param {string} notebookPath
 */
async function openNotebook(page, notebookPath) {
    const url = `${getPlutoUrl()}/?path=${encodeURIComponent(notebookPath)}`
    await page.goto(url, { waitUntil: "domcontentloaded" })
    await page.waitForSelector("pluto-input", { state: "visible", timeout: 60_000 })
    await waitForPlutoToCalmDown(page)
}

/**
 * Shut down the current notebook via the JS API exposed by Pluto.
 *
 * @param {import("@playwright/test").Page} page
 */
async function shutdownCurrentNotebook(page) {
    await page.evaluate(() => {
        // @ts-ignore
        window.shutdownNotebook?.()
    })
}

// ---------------------------------------------------------------------------
// Cell helpers
// ---------------------------------------------------------------------------

/**
 * Get all cell IDs present on the current page.
 *
 * @param {import("@playwright/test").Page} page
 * @returns {Promise<string[]>}
 */
async function getCellIds(page) {
    return page.evaluate(() =>
        Array.from(document.querySelectorAll("pluto-cell")).map((el) => el.getAttribute("id") ?? "")
    )
}

/**
 * Type code into the last (or a specific) cell's CodeMirror editor.
 *
 * @param {import("@playwright/test").Page} page
 * @param {string} code
 * @param {string|null} [cellId] — if omitted, the last cell is used
 */
async function typeInCell(page, code, cellId = null) {
    const selector = cellId
        ? `pluto-cell[id="${cellId}"] pluto-input .cm-content`
        : "pluto-cell:last-of-type pluto-input .cm-content"
    await page.waitForSelector(selector, { state: "visible" })
    await page.fill(selector, code)
}

/**
 * Click the run button for a specific cell.
 *
 * @param {import("@playwright/test").Page} page
 * @param {string} cellId
 */
async function runCell(page, cellId) {
    const btn = `pluto-cell[id="${cellId}"] .runcell`
    await page.waitForSelector(btn, { state: "visible" })
    await page.click(btn)
    await waitForPlutoToCalmDown(page)
}

/**
 * Click "Run all changed cells".
 *
 * @param {import("@playwright/test").Page} page
 */
async function runAllChanged(page) {
    await page.waitForSelector(".runallchanged", { state: "visible" })
    await page.click(".runallchanged")
    // Wait for Pluto to start running, then wait for it to finish
    await waitForPlutoBusy(page, true)
    await waitForPlutoBusy(page, false)
}

/**
 * Get the text content of a cell's output.
 *
 * @param {import("@playwright/test").Page} page
 * @param {string} cellId
 * @returns {Promise<string|null>}
 */
async function getCellOutput(page, cellId) {
    return page.evaluate(
        (id) => document.querySelector(`pluto-cell[id="${id}"] pluto-output`)?.textContent ?? null,
        cellId
    )
}

/**
 * Wait until the output of a cell matches `expectedText`.
 *
 * @param {import("@playwright/test").Page} page
 * @param {string} cellId
 * @param {string} expectedText
 * @param {{ timeout?: number }} [options]
 */
async function waitForCellOutput(page, cellId, expectedText, { timeout = 30_000 } = {}) {
    const selector = `pluto-cell[id="${cellId}"] pluto-output`
    await page.waitForSelector(selector, { state: "visible", timeout })
    await page.waitForFunction(
        ([sel, target]) => document.querySelector(sel)?.textContent?.trim() === target,
        [selector, expectedText],
        { timeout }
    )
    return getCellOutput(page, cellId)
}

/**
 * Wait until a cell shows an error badge.
 *
 * @param {import("@playwright/test").Page} page
 * @param {string} cellId
 * @param {{ timeout?: number }} [options]
 */
async function waitForCellError(page, cellId, { timeout = 30_000 } = {}) {
    const selector = `pluto-cell[id="${cellId}"].errored`
    await page.waitForSelector(selector, { timeout })
}

// ---------------------------------------------------------------------------
// Waiting helpers
// ---------------------------------------------------------------------------

/**
 * Wait until Pluto reaches the desired busy / quiet state.
 *
 * @param {import("@playwright/test").Page} page
 * @param {boolean} iWantBusiness
 * @param {{ timeout?: number }} [options]
 */
async function waitForPlutoBusy(page, iWantBusiness, { timeout = 60_000 } = {}) {
    await page.waitForFunction(
        (iWantBusiness) => {
            const body = document.body
            // @ts-ignore
            const updateOngoing = body?._update_is_ongoing ?? false
            // @ts-ignore
            const jsInitSize = body?._js_init_set?.size ?? 0
            const isLoading = body?.classList?.contains("loading") ?? false
            const hasProcessStatus =
                document.querySelector("#process-status-tab-button.something_is_happening") != null
            const hasRunningCell =
                document.querySelector(
                    "pluto-cell.running, pluto-cell.queued, pluto-cell.internal_test_queued"
                ) != null

            const quiet =
                !updateOngoing && jsInitSize === 0 && !isLoading && !hasProcessStatus && !hasRunningCell

            return iWantBusiness ? !quiet : quiet
        },
        iWantBusiness,
        { timeout }
    )
}

/**
 * Wait for Pluto to stop all activity.
 *
 * @param {import("@playwright/test").Page} page
 * @param {{ timeout?: number }} [options]
 */
async function waitForPlutoToCalmDown(page, options = {}) {
    await waitForPlutoBusy(page, false, options)
}

// ---------------------------------------------------------------------------
// Screenshot
// ---------------------------------------------------------------------------

/**
 * Save a screenshot into the artifacts directory.
 *
 * @param {import("@playwright/test").Page} page
 * @param {string} [name]
 */
async function saveDebugScreenshot(page, name = `screenshot_${Date.now()}`) {
    fs.mkdirSync(ARTIFACTS_DIR, { recursive: true })
    const dest = path.join(ARTIFACTS_DIR, `${name}.png`)
    await page.screenshot({ path: dest, fullPage: true })
    console.log(`📸 Screenshot saved: ${dest}`)
    return dest
}

module.exports = {
    getPlutoUrl,
    getFixturePath,
    getTempNotebookPath,
    gotoPlutoMainMenu,
    createNewNotebook,
    openNotebook,
    shutdownCurrentNotebook,
    getCellIds,
    typeInCell,
    runCell,
    runAllChanged,
    getCellOutput,
    waitForCellOutput,
    waitForCellError,
    waitForPlutoBusy,
    waitForPlutoToCalmDown,
    saveDebugScreenshot,
}
