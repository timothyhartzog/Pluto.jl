// @ts-check
/**
 * Global teardown for Playwright tests.
 * Prints a brief summary of the artifacts produced.
 */

const fs = require("fs")
const path = require("path")

const ARTIFACTS_DIR = path.join(__dirname, "..", "artifacts")

module.exports = async function globalTeardown() {
    const resultsPath = path.join(ARTIFACTS_DIR, "results.json")
    if (!fs.existsSync(resultsPath)) {
        console.log("⚠️  No results.json found – skipping teardown summary.")
        return
    }

    try {
        const results = JSON.parse(fs.readFileSync(resultsPath, "utf8"))
        const { stats } = results
        if (stats) {
            console.log(`\n📊 Test run summary`)
            console.log(`   Passed  : ${stats.expected ?? 0}`)
            console.log(`   Failed  : ${stats.unexpected ?? 0}`)
            console.log(`   Skipped : ${stats.skipped ?? 0}`)
            console.log(`   Duration: ${((stats.duration ?? 0) / 1000).toFixed(1)}s\n`)
        }
    } catch {
        // Non-fatal – just skip the summary
    }
}
