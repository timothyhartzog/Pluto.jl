// @ts-check
const { defineConfig, devices } = require("@playwright/test")
const path = require("path")

const PLUTO_PORT = process.env.PLUTO_PORT || "1234"
const BASE_URL = `http://localhost:${PLUTO_PORT}`

/**
 * Playwright configuration for Pluto.jl end-to-end tests.
 * @see https://playwright.dev/docs/test-configuration
 */
module.exports = defineConfig({
    testDir: "./tests",
    outputDir: "./artifacts/test-results",

    /* Maximum time one test can run (ms). */
    timeout: 120_000,

    /* Expect assertion timeout. */
    expect: {
        timeout: 30_000,
    },

    /* Run tests in files in parallel. */
    fullyParallel: false,

    /* Fail the build on CI if you accidentally left test.only in the source. */
    forbidOnly: !!process.env.CI,

    /* Retry on CI only. */
    retries: process.env.CI ? 2 : 0,

    /* Reporter to use. */
    reporter: [
        ["list"],
        ["html", { outputFolder: "./artifacts/playwright-report", open: "never" }],
        ["json", { outputFile: "./artifacts/results.json" }],
    ],

    use: {
        baseURL: BASE_URL,

        /* Collect trace on first retry. */
        trace: "on-first-retry",

        /* Capture screenshot on failure. */
        screenshot: "only-on-failure",

        /* Record video on first retry. */
        video: "on-first-retry",

        /* Viewport. */
        viewport: { width: 1280, height: 800 },

        /* Ignore HTTPS errors (Pluto dev runs over HTTP). */
        ignoreHTTPSErrors: true,
    },

    projects: [
        {
            name: "chromium",
            use: {
                ...devices["Desktop Chrome"],
                launchOptions: {
                    args: [
                        "--no-sandbox",
                        "--disable-setuid-sandbox",
                        "--disable-dev-shm-usage",
                    ],
                },
            },
        },
    ],

    /* Global setup/teardown. */
    globalSetup: require.resolve("./helpers/global-setup.js"),
    globalTeardown: require.resolve("./helpers/global-teardown.js"),
})
