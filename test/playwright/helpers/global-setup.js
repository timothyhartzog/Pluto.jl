// @ts-check
/**
 * Global setup for Playwright tests.
 * Validates that the Pluto server is reachable before tests run.
 */

const { chromium } = require("@playwright/test")
const path = require("path")
const fs = require("fs")

const PLUTO_PORT = process.env.PLUTO_PORT || "1234"
const BASE_URL = `http://localhost:${PLUTO_PORT}`
const ARTIFACTS_DIR = path.join(__dirname, "..", "artifacts")

module.exports = async function globalSetup() {
    // Ensure artifacts directory exists
    fs.mkdirSync(ARTIFACTS_DIR, { recursive: true })

    console.log(`\n🔌 Checking Pluto server at ${BASE_URL} ...`)

    const browser = await chromium.launch({
        args: ["--no-sandbox", "--disable-setuid-sandbox"],
    })

    let page
    try {
        page = await browser.newPage()

        // Poll until Pluto responds or we give up
        const MAX_WAIT_MS = 60_000
        const POLL_MS = 1_000
        const deadline = Date.now() + MAX_WAIT_MS
        let lastErr

        while (Date.now() < deadline) {
            try {
                const response = await page.goto(BASE_URL, {
                    timeout: 5_000,
                    waitUntil: "domcontentloaded",
                })
                if (response && response.status() < 500) {
                    console.log(`✅ Pluto server is ready (HTTP ${response.status()})`)
                    return
                }
            } catch (err) {
                lastErr = err
            }
            await new Promise((r) => setTimeout(r, POLL_MS))
        }

        throw new Error(
            `Pluto server at ${BASE_URL} did not become ready within ${MAX_WAIT_MS}ms. Last error: ${lastErr}`
        )
    } finally {
        await page?.close()
        await browser.close()
    }
}
