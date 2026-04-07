import { html, useContext, useState, useRef, useCallback } from "../imports/Preact.js"
import { PlutoActionsContext } from "../common/PlutoContext.js"

// ─── CSV helpers ─────────────────────────────────────────────────────────────

/** Parse a single CSV line, respecting double-quoted fields. */
function parse_csv_row(line) {
    const result = []
    let field = ""
    let in_quotes = false
    for (let i = 0; i < line.length; i++) {
        const c = line[i]
        if (c === '"') {
            if (in_quotes && line[i + 1] === '"') {
                field += '"'
                i++
            } else {
                in_quotes = !in_quotes
            }
        } else if (c === "," && !in_quotes) {
            result.push(field.trim())
            field = ""
        } else {
            field += c
        }
    }
    result.push(field.trim())
    return result
}

/** Return { columns, rows (up to max_rows), total_rows } from raw CSV text. */
function parse_csv_preview(text, max_rows = 5) {
    const lines = text
        .trim()
        .split(/\r?\n/)
        .filter((l) => l.trim())
    if (lines.length === 0) return { columns: [], rows: [], total_rows: 0 }
    const columns = parse_csv_row(lines[0])
    const data_lines = lines.slice(1)
    const rows = data_lines.slice(0, max_rows).map(parse_csv_row)
    return { columns, rows, total_rows: data_lines.length }
}

/** Infer a simple Julia-style type for each column from sample values. */
function infer_types(columns, rows) {
    return columns.map((_col, i) => {
        const values = rows.map((r) => r[i]).filter((v) => v != null && v !== "")
        if (values.length === 0) return "Any"
        if (values.every((v) => /^-?\d+$/.test(v))) return "Int"
        if (values.every((v) => /^-?\d*\.?\d+([eE][+-]?\d+)?$/.test(v))) return "Float64"
        if (values.every((v) => /^\d{4}-\d{2}-\d{2}/.test(v))) return "Date"
        return "String"
    })
}

// ─── Cleaning task catalogue ──────────────────────────────────────────────────

const CLEANING_TASKS = [
    { id: "drop_missing", label: "Drop rows with missing values" },
    { id: "fill_missing", label: "Fill missing values with column mean/mode" },
    { id: "normalize", label: "Normalize numeric columns to 0–1 range" },
    { id: "deduplicate", label: "Remove duplicate rows" },
    { id: "strip_whitespace", label: "Strip leading/trailing whitespace from strings" },
    { id: "rename_lower", label: "Rename all columns to lowercase_snake_case" },
]

// ─── Claude helper ────────────────────────────────────────────────────────────

function extract_code_blocks(text) {
    const blocks = []
    const re = /```(?:julia|jl)?\n([\s\S]*?)```/g
    let m
    while ((m = re.exec(text)) !== null) {
        blocks.push({ code: m[1].trim() })
    }
    return blocks
}

async function generate_import_code({ filename, columns, types, total_rows, sample_rows, cleaning_tasks, from_url, notebook_id }) {
    const col_info = columns.length > 0 ? columns.map((c, i) => `${c} (${types[i]})`).join(", ") : "(unknown — remote URL)"
    const sample =
        sample_rows.length > 0
            ? sample_rows
                  .slice(0, 3)
                  .map((r) => r.join(", "))
                  .join("\n")
            : "(not available)"
    const tasks_list = cleaning_tasks.length > 0 ? cleaning_tasks.map((t) => `- ${t}`).join("\n") : "- None"

    const source_hint = from_url
        ? `The dataset is at URL: ${from_url}\nGenerate code that downloads it with Downloads.jl or HTTP.jl and then reads it.`
        : `The dataset file is named: ${filename}\nGenerate code that reads it with CSV.read("${filename}", DataFrame).`

    const prompt = `You are an expert Julia data scientist. Generate Julia code to import, profile, and clean a tabular dataset.

${source_hint}

Dataset summary:
- Columns (${columns.length > 0 ? columns.length : "unknown"}): ${col_info}
- Total data rows: ${total_rows > 0 ? total_rows : "unknown"}
- Sample data (first rows):
${sample}

Cleaning tasks requested:
${tasks_list}

Instructions:
- Split the code into separate fenced \`\`\`julia code blocks, one per logical step.
- Step 1: Package imports (CSV, DataFrames, and any others needed).
- Step 2: Load the dataset into a DataFrame named \`df\`.
- Step 3: Profile — show \`describe(df)\`, \`first(df, 5)\`, and \`size(df)\`.
- Step 4 (if cleaning tasks listed): Apply each cleaning step in order with brief comments.
- Step 5: Print a short summary after cleaning (nrow, ncol, missing count).
- Do NOT wrap multiple steps in a single block.
- Use DataFrames.jl idioms throughout.`

    const resp = await fetch("/api/claude", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
            prompt,
            model: "claude-sonnet-4-6",
            system_prompt: "You are an expert Julia data scientist. Always generate clean, runnable Julia code using DataFrames.jl conventions.",
            notebook_id,
        }),
    })
    const data = await resp.json()
    if (!resp.ok || !data.success) throw new Error(data.error ?? `HTTP ${resp.status}`)
    return data.response
}

// ─── Component ────────────────────────────────────────────────────────────────

export function DataImportPanel({ open, onClose, notebook_id, notebook_cell_order }) {
    const pluto_actions = useContext(PlutoActionsContext)

    const [step, set_step] = useState(1) // 1=import, 2=profile, 3=clean, 4=code
    const [input_mode, set_input_mode] = useState("paste") // paste | upload | url
    const [csv_text, set_csv_text] = useState("")
    const [data_url, set_data_url] = useState("")
    const [filename, set_filename] = useState("data.csv")
    const [profile, set_profile] = useState(null)
    const [selected_tasks, set_selected_tasks] = useState([])
    const [loading, set_loading] = useState(false)
    const [error, set_error] = useState(null)
    const [response_text, set_response_text] = useState(null)
    const [code_blocks, set_code_blocks] = useState([])

    const file_input_ref = useRef(null)

    const reset = useCallback(() => {
        set_step(1)
        set_csv_text("")
        set_data_url("")
        set_filename("data.csv")
        set_profile(null)
        set_selected_tasks([])
        set_error(null)
        set_response_text(null)
        set_code_blocks([])
        set_input_mode("paste")
    }, [])

    const handle_close = useCallback(() => {
        reset()
        onClose()
    }, [reset, onClose])

    const handle_file_upload = useCallback((e) => {
        const file = e.target.files?.[0]
        if (!file) return
        set_filename(file.name)
        const reader = new FileReader()
        reader.onload = (ev) => {
            set_csv_text(ev.target.result)
            set_input_mode("paste")
        }
        reader.readAsText(file)
    }, [])

    const handle_profile = useCallback(() => {
        set_error(null)
        const text = csv_text.trim()
        if (!text) {
            set_error("Please provide CSV data first (paste or upload a file).")
            return
        }
        try {
            const { columns, rows, total_rows } = parse_csv_preview(text)
            if (columns.length === 0) {
                set_error("Could not detect columns. Make sure the first row contains comma-separated headers.")
                return
            }
            const types = infer_types(columns, rows)
            set_profile({ columns, rows, types, total_rows, from_url: null })
            set_step(2)
        } catch (e) {
            set_error("CSV parse error: " + e.message)
        }
    }, [csv_text])

    const handle_url_next = useCallback(() => {
        set_error(null)
        if (!data_url.trim()) {
            set_error("Please enter a dataset URL.")
            return
        }
        const url_filename = data_url.split("/").pop().split("?")[0] || "data.csv"
        set_filename(url_filename)
        set_profile({ columns: [], rows: [], types: [], total_rows: 0, from_url: data_url.trim() })
        set_step(2)
    }, [data_url])

    const handle_generate = useCallback(async () => {
        if (!profile) return
        set_loading(true)
        set_error(null)
        try {
            const task_labels = selected_tasks.map((id) => CLEANING_TASKS.find((t) => t.id === id)?.label ?? id)
            const text = await generate_import_code({
                filename,
                columns: profile.columns,
                types: profile.types,
                total_rows: profile.total_rows,
                sample_rows: profile.rows,
                cleaning_tasks: task_labels,
                from_url: profile.from_url,
                notebook_id,
            })
            set_response_text(text)
            set_code_blocks(extract_code_blocks(text))
            set_step(4)
        } catch (e) {
            set_error(e.message)
        } finally {
            set_loading(false)
        }
    }, [profile, selected_tasks, filename, notebook_id])

    const insert_all = useCallback(async () => {
        const start = notebook_cell_order ? notebook_cell_order.length : 0
        for (let i = 0; i < code_blocks.length; i++) {
            await pluto_actions.add_remote_cell_at(start + i, code_blocks[i].code)
        }
        handle_close()
    }, [code_blocks, notebook_cell_order, pluto_actions, handle_close])

    const insert_one = useCallback(
        async (code) => {
            const index = notebook_cell_order ? notebook_cell_order.length : 0
            await pluto_actions.add_remote_cell_at(index, code)
        },
        [notebook_cell_order, pluto_actions]
    )

    const toggle_task = useCallback((id) => {
        set_selected_tasks((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]))
    }, [])

    if (!open) return null

    const step_labels = ["Import", "Profile", "Clean", "Code"]

    return html`
        <div
            id="data-import-backdrop"
            onClick=${(e) => e.target.id === "data-import-backdrop" && handle_close()}
        >
            <div id="data-import-panel">
                <!-- Header -->
                <div id="data-import-header">
                    <span id="data-import-title">📊 Dataset Import Assistant</span>
                    <button class="di-close-btn" onClick=${handle_close} title="Close (Esc)">✕</button>
                </div>

                <!-- Step indicator -->
                <div id="data-import-steps">
                    ${step_labels.map(
                        (label, idx) => html`
                            <div
                                class=${"di-step" +
                                (step === idx + 1 ? " di-step-active" : "") +
                                (step > idx + 1 ? " di-step-done" : "")}
                            >
                                <span class="di-step-circle">${step > idx + 1 ? "✓" : idx + 1}</span>
                                <span class="di-step-label">${label}</span>
                            </div>
                            ${idx < step_labels.length - 1 ? html`<div class="di-step-connector"></div>` : null}
                        `
                    )}
                </div>

                <!-- Body -->
                <div id="data-import-body">
                    ${error ? html`<div class="di-error"><strong>Error:</strong> ${error}</div>` : null}

                    <!-- ── Step 1: Import ── -->
                    ${step === 1
                        ? html`
                              <div class="di-section">
                                  <p class="di-desc">
                                      Paste CSV/TSV data, upload a file, or provide a remote URL to get started.
                                  </p>

                                  <div class="di-tab-bar">
                                      <button
                                          class=${"di-tab" + (input_mode === "paste" ? " di-tab-active" : "")}
                                          onClick=${() => set_input_mode("paste")}
                                      >
                                          Paste CSV
                                      </button>
                                      <button
                                          class=${"di-tab" + (input_mode === "upload" ? " di-tab-active" : "")}
                                          onClick=${() => {
                                              set_input_mode("upload")
                                              file_input_ref.current?.click()
                                          }}
                                      >
                                          Upload File
                                      </button>
                                      <button
                                          class=${"di-tab" + (input_mode === "url" ? " di-tab-active" : "")}
                                          onClick=${() => set_input_mode("url")}
                                      >
                                          From URL
                                      </button>
                                  </div>

                                  <input
                                      ref=${file_input_ref}
                                      type="file"
                                      accept=".csv,.tsv,.txt"
                                      style="display:none"
                                      onChange=${handle_file_upload}
                                  />

                                  ${input_mode !== "url"
                                      ? html`
                                            <div class="di-field">
                                                <label class="di-label">Dataset filename</label>
                                                <input
                                                    type="text"
                                                    class="di-input"
                                                    value=${filename}
                                                    onInput=${(e) => set_filename(e.target.value)}
                                                    placeholder="data.csv"
                                                />
                                            </div>
                                            <div class="di-field">
                                                <label class="di-label">CSV data</label>
                                                <textarea
                                                    class="di-textarea"
                                                    rows="8"
                                                    placeholder="Paste CSV here — first row should be column headers…"
                                                    value=${csv_text}
                                                    onInput=${(e) => set_csv_text(e.target.value)}
                                                ></textarea>
                                            </div>
                                        `
                                      : html`
                                            <div class="di-field">
                                                <label class="di-label">Dataset URL</label>
                                                <input
                                                    type="text"
                                                    class="di-input"
                                                    value=${data_url}
                                                    onInput=${(e) => set_data_url(e.target.value)}
                                                    placeholder="https://example.com/data.csv"
                                                />
                                            </div>
                                            <p class="di-note">
                                                ℹ️ Julia code to download from this URL will be generated automatically.
                                            </p>
                                        `}

                                  <div class="di-actions">
                                      <button
                                          class="di-btn-primary"
                                          onClick=${input_mode === "url" ? handle_url_next : handle_profile}
                                      >
                                          Next: Profile →
                                      </button>
                                  </div>
                              </div>
                          `
                        : null}

                    <!-- ── Step 2: Profile ── -->
                    ${step === 2 && profile
                        ? html`
                              <div class="di-section">
                                  <h3 class="di-step-title">Data Profile</h3>
                                  ${profile.from_url
                                      ? html`
                                            <p class="di-desc">
                                                Remote dataset: <code>${profile.from_url}</code>
                                            </p>
                                            <div class="di-info-box">
                                                📡 Column profile will be available after the data is loaded in Julia.
                                            </div>
                                        `
                                      : html`
                                            <p class="di-desc">
                                                Detected <strong>${profile.columns.length}</strong> columns and
                                                <strong>${profile.total_rows.toLocaleString()}</strong> data rows.
                                            </p>
                                            <div class="di-table-wrap">
                                                <table class="di-table">
                                                    <thead>
                                                        <tr>
                                                            <th>#</th>
                                                            <th>Column</th>
                                                            <th>Inferred&nbsp;Type</th>
                                                            ${profile.rows
                                                                .slice(0, 3)
                                                                .map(
                                                                    (_, i) =>
                                                                        html`<th>Row&nbsp;${i + 1}</th>`
                                                                )}
                                                        </tr>
                                                    </thead>
                                                    <tbody>
                                                        ${profile.columns.map(
                                                            (col, i) => html`
                                                                <tr>
                                                                    <td class="di-td-num">${i + 1}</td>
                                                                    <td class="di-td-col">${col}</td>
                                                                    <td
                                                                        class=${"di-td-type di-type-" +
                                                                        profile.types[i].toLowerCase()}
                                                                    >
                                                                        ${profile.types[i]}
                                                                    </td>
                                                                    ${profile.rows
                                                                        .slice(0, 3)
                                                                        .map(
                                                                            (row) =>
                                                                                html`<td class="di-td-val">
                                                                                    ${row[i] ?? ""}
                                                                                </td>`
                                                                        )}
                                                                </tr>
                                                            `
                                                        )}
                                                    </tbody>
                                                </table>
                                            </div>
                                        `}
                                  <div class="di-actions">
                                      <button class="di-btn-secondary" onClick=${() => set_step(1)}>← Back</button>
                                      <button class="di-btn-primary" onClick=${() => set_step(3)}>
                                          Next: Clean →
                                      </button>
                                  </div>
                              </div>
                          `
                        : null}

                    <!-- ── Step 3: Clean ── -->
                    ${step === 3
                        ? html`
                              <div class="di-section">
                                  <h3 class="di-step-title">Cleaning Options</h3>
                                  <p class="di-desc">
                                      Select any data cleaning tasks to include. The AI will generate the
                                      corresponding Julia code for each.
                                  </p>
                                  <div class="di-task-list">
                                      ${CLEANING_TASKS.map(
                                          (task) => html`
                                              <label class="di-task">
                                                  <input
                                                      type="checkbox"
                                                      checked=${selected_tasks.includes(task.id)}
                                                      onChange=${() => toggle_task(task.id)}
                                                  />
                                                  <span class="di-task-label">${task.label}</span>
                                              </label>
                                          `
                                      )}
                                  </div>
                                  <div class="di-actions">
                                      <button class="di-btn-secondary" onClick=${() => set_step(2)}>← Back</button>
                                      <button
                                          class="di-btn-primary"
                                          onClick=${handle_generate}
                                          disabled=${loading}
                                      >
                                          ${loading
                                              ? html`<span class="di-spinner"></span> Generating…`
                                              : "✦ Generate Code →"}
                                      </button>
                                  </div>
                              </div>
                          `
                        : null}

                    <!-- ── Step 4: Code preview ── -->
                    ${step === 4
                        ? html`
                              <div class="di-section">
                                  <h3 class="di-step-title">Generated Julia Code</h3>
                                  <p class="di-desc">
                                      Review the ${code_blocks.length} generated cell${code_blocks.length !== 1 ? "s" : ""} below.
                                      Insert individual cells or apply all at once.
                                  </p>
                                  ${code_blocks.length > 0
                                      ? html`
                                            <div class="di-code-blocks">
                                                ${code_blocks.map(
                                                    ({ code }, i) => html`
                                                        <div class="di-code-block">
                                                            <div class="di-code-toolbar">
                                                                <span class="di-code-label">Cell ${i + 1}</span>
                                                                <button
                                                                    class="di-insert-btn"
                                                                    onClick=${() => insert_one(code)}
                                                                >
                                                                    ↓ Insert
                                                                </button>
                                                            </div>
                                                            <pre class="di-code"><code>${code}</code></pre>
                                                        </div>
                                                    `
                                                )}
                                            </div>
                                        `
                                      : html`
                                            <div class="di-info-box">
                                                <pre class="di-raw">${response_text}</pre>
                                            </div>
                                        `}
                                  <div class="di-actions">
                                      <button class="di-btn-secondary" onClick=${() => set_step(3)}>← Back</button>
                                      ${code_blocks.length > 0
                                          ? html`
                                                <button class="di-btn-primary" onClick=${insert_all}>
                                                    ↓ Insert All ${code_blocks.length} Cells
                                                </button>
                                            `
                                          : null}
                                  </div>
                              </div>
                          `
                        : null}
                </div>
            </div>
        </div>
    `
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const DATA_IMPORT_STYLES = `
#data-import-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.35);
    z-index: 10000;
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding: 60px 16px 16px;
    overflow-y: auto;
}

#data-import-panel {
    background: var(--background-color, #fff);
    border: 1.5px solid var(--border-color, #e0e0e0);
    border-radius: 10px;
    box-shadow: 0 8px 32px rgba(0,0,0,0.18);
    width: min(620px, 96vw);
    max-height: calc(100vh - 80px);
    display: flex;
    flex-direction: column;
    overflow: hidden;
    font-family: var(--font-family, inherit);
}

#data-import-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 16px;
    border-bottom: 1px solid var(--border-color, #e0e0e0);
    background: var(--header-bg, #f8f8f8);
    flex-shrink: 0;
}

#data-import-title {
    font-weight: 600;
    font-size: 0.95em;
    color: var(--pluto-output-color, #333);
}

.di-close-btn {
    background: none;
    border: none;
    cursor: pointer;
    font-size: 1.1em;
    color: #888;
    padding: 2px 6px;
    border-radius: 4px;
    line-height: 1;
}
.di-close-btn:hover { background: var(--hover-color, #eee); color: #333; }

#data-import-steps {
    display: flex;
    align-items: center;
    padding: 10px 16px;
    border-bottom: 1px solid var(--border-color, #e0e0e0);
    background: var(--header-bg, #f8f8f8);
    flex-shrink: 0;
    gap: 0;
}

.di-step {
    display: flex;
    align-items: center;
    gap: 5px;
    opacity: 0.45;
}
.di-step-active, .di-step-done { opacity: 1; }

.di-step-circle {
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: var(--border-color, #ddd);
    color: #555;
    font-size: 0.75em;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
}
.di-step-active .di-step-circle { background: #cf8b4e; color: #fff; }
.di-step-done .di-step-circle { background: #4caf50; color: #fff; }

.di-step-label { font-size: 0.8em; font-weight: 500; white-space: nowrap; }

.di-step-connector {
    flex: 1;
    height: 2px;
    background: var(--border-color, #ddd);
    min-width: 16px;
    margin: 0 4px;
}

#data-import-body {
    padding: 16px;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.di-section { display: flex; flex-direction: column; gap: 10px; }
.di-step-title { font-size: 0.95em; font-weight: 600; margin: 0; }
.di-desc { font-size: 0.88em; color: var(--pluto-output-color, #555); margin: 0; }
.di-note { font-size: 0.82em; color: #888; font-style: italic; margin: 0; }

.di-error {
    padding: 10px 12px;
    background: #fff0f0;
    border: 1px solid #ffaaaa;
    border-radius: 6px;
    color: #c0392b;
    font-size: 0.88em;
}

.di-info-box {
    padding: 10px 12px;
    background: var(--secondary-bg, #f5f5f5);
    border: 1px solid var(--border-color, #ddd);
    border-radius: 6px;
    font-size: 0.88em;
    color: var(--pluto-output-color, #555);
}

/* Tabs */
.di-tab-bar { display: flex; gap: 4px; }
.di-tab {
    padding: 5px 12px;
    border: 1.5px solid var(--border-color, #ccc);
    border-radius: 6px;
    background: none;
    cursor: pointer;
    font-size: 0.85em;
    color: var(--pluto-output-color, #555);
    transition: background 0.12s, border-color 0.12s;
}
.di-tab:hover { background: var(--hover-color, #eee); }
.di-tab-active { background: #cf8b4e22; border-color: #cf8b4e; color: #cf8b4e; font-weight: 600; }

/* Form fields */
.di-field { display: flex; flex-direction: column; gap: 4px; }
.di-label { font-size: 0.82em; font-weight: 500; }
.di-input {
    padding: 6px 10px;
    border: 1.5px solid var(--border-color, #ccc);
    border-radius: 6px;
    font-size: 0.9em;
    background: var(--input-bg, #fff);
    color: var(--pluto-output-color, #333);
}
.di-input:focus { outline: none; border-color: #cf8b4e; }
.di-textarea {
    width: 100%;
    box-sizing: border-box;
    resize: vertical;
    border: 1.5px solid var(--border-color, #ccc);
    border-radius: 6px;
    padding: 8px 10px;
    font-size: 0.85em;
    font-family: "JuliaMono", "Cascadia Code", monospace;
    background: var(--input-bg, #fff);
    color: var(--pluto-output-color, #333);
    min-height: 140px;
}
.di-textarea:focus { outline: none; border-color: #cf8b4e; }

/* Profile table */
.di-table-wrap { overflow-x: auto; border-radius: 6px; border: 1px solid var(--border-color, #ddd); }
.di-table { border-collapse: collapse; width: 100%; font-size: 0.82em; }
.di-table th {
    background: var(--secondary-bg, #f5f5f5);
    padding: 6px 10px;
    text-align: left;
    font-weight: 600;
    border-bottom: 1px solid var(--border-color, #ddd);
    white-space: nowrap;
}
.di-table td { padding: 5px 10px; border-bottom: 1px solid var(--border-color, #f0f0f0); }
.di-table tr:last-child td { border-bottom: none; }
.di-td-num { color: #aaa; text-align: right; width: 2em; }
.di-td-col { font-weight: 600; }
.di-td-type { font-family: monospace; font-size: 0.9em; }
.di-td-val { color: #777; max-width: 120px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

/* Type badges */
.di-type-int { color: #2196f3; }
.di-type-float64 { color: #9c27b0; }
.di-type-date { color: #009688; }
.di-type-string { color: #795548; }
.di-type-any { color: #aaa; }

/* Cleaning tasks */
.di-task-list { display: flex; flex-direction: column; gap: 6px; }
.di-task {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 7px 10px;
    border: 1px solid var(--border-color, #ddd);
    border-radius: 6px;
    cursor: pointer;
    transition: background 0.1s;
}
.di-task:hover { background: var(--hover-color, #f8f8f8); }
.di-task input[type=checkbox] { accent-color: #cf8b4e; width: 15px; height: 15px; }
.di-task-label { font-size: 0.88em; }

/* Code blocks */
.di-code-blocks { display: flex; flex-direction: column; gap: 8px; }
.di-code-block {
    border: 1.5px solid var(--border-color, #ddd);
    border-radius: 7px;
    overflow: hidden;
}
.di-code-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 5px 10px;
    background: var(--secondary-bg, #f5f5f5);
    border-bottom: 1px solid var(--border-color, #ddd);
}
.di-code-label { font-size: 0.8em; color: #888; font-weight: 600; }
.di-insert-btn {
    padding: 3px 10px;
    background: #cf8b4e;
    color: #fff;
    border: none;
    border-radius: 4px;
    font-size: 0.82em;
    font-weight: 600;
    cursor: pointer;
}
.di-insert-btn:hover { background: #b87740; }
.di-code {
    margin: 0;
    padding: 10px 12px;
    font-size: 0.82em;
    background: var(--code-bg, #fafafa);
    overflow-x: auto;
    white-space: pre;
    font-family: "JuliaMono", "Cascadia Code", "Fira Code", monospace;
    max-height: 200px;
    overflow-y: auto;
}
.di-raw {
    margin: 0;
    font-size: 0.82em;
    white-space: pre-wrap;
    font-family: inherit;
}

/* Action row */
.di-actions { display: flex; gap: 8px; align-items: center; margin-top: 4px; }
.di-btn-primary {
    padding: 7px 18px;
    background: #cf8b4e;
    color: #fff;
    border: none;
    border-radius: 6px;
    font-size: 0.9em;
    font-weight: 600;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 6px;
    transition: background 0.15s;
}
.di-btn-primary:hover:not(:disabled) { background: #b87740; }
.di-btn-primary:disabled { opacity: 0.55; cursor: default; }
.di-btn-secondary {
    padding: 7px 14px;
    background: none;
    border: 1px solid var(--border-color, #ccc);
    border-radius: 6px;
    font-size: 0.9em;
    cursor: pointer;
    color: var(--pluto-output-color, #555);
}
.di-btn-secondary:hover { background: var(--hover-color, #eee); }

/* Spinner */
.di-spinner {
    display: inline-block;
    width: 12px;
    height: 12px;
    border: 2px solid rgba(255,255,255,0.4);
    border-top-color: #fff;
    border-radius: 50%;
    animation: di-spin 0.7s linear infinite;
}
@keyframes di-spin { to { transform: rotate(360deg); } }

/* Nav button */
#data-import-nav-btn {
    background: none;
    border: 1.5px solid transparent;
    border-radius: 6px;
    padding: 4px 10px;
    cursor: pointer;
    font-size: 0.85em;
    font-weight: 600;
    color: var(--pluto-output-color, #555);
    display: flex;
    align-items: center;
    gap: 5px;
    transition: background 0.15s, border-color 0.15s;
    white-space: nowrap;
}
#data-import-nav-btn:hover {
    background: var(--hover-color, rgba(0,0,0,0.05));
    border-color: var(--border-color, #ccc);
}
#data-import-nav-btn.active {
    background: #cf8b4e22;
    border-color: #cf8b4e;
    color: #cf8b4e;
}
`

// Inject styles once
if (!document.getElementById("data-import-panel-styles")) {
    const style = document.createElement("style")
    style.id = "data-import-panel-styles"
    style.textContent = DATA_IMPORT_STYLES
    document.head.appendChild(style)
}
