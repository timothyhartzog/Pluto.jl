import { html, useContext, useState, useCallback } from "../imports/Preact.js"
import { PlutoActionsContext } from "../common/PlutoContext.js"
import {
    gen_duplicates_code,
    gen_strings_code_clean,
    gen_dates_code,
    gen_workflow_comment,
    TRANSFORM_COLLAPSE_SPACES,
    TRANSFORM_REMOVE_SPECIAL,
} from "./cleaning_codegen.js"

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

function DuplicatesWidget({ on_insert }) {
    const [df, set_df] = useState("df")
    const [cols, set_cols] = useState("")
    const [keep, set_keep] = useState("first")
    const [result, set_result] = useState("df_clean")

    const code = gen_duplicates_code({ df, cols, keep, result })

    return html`
        <div class="cw-widget">
            <div class="cw-widget-title">🔁 Duplicate Handling</div>
            <div class="cw-field-row">
                <label>DataFrame</label>
                <input class="cw-input" value=${df} onInput=${(e) => set_df(e.target.value)} placeholder="df" />
            </div>
            <div class="cw-field-row">
                <label>Columns <span class="cw-hint">(comma-sep, blank = all)</span></label>
                <input class="cw-input" value=${cols} onInput=${(e) => set_cols(e.target.value)} placeholder="col1, col2" />
            </div>
            <div class="cw-field-row">
                <label>Keep</label>
                <select class="cw-select" value=${keep} onChange=${(e) => set_keep(e.target.value)}>
                    <option value="first">first occurrence</option>
                    <option value="last">last occurrence</option>
                    <option value="none">remove all duplicates</option>
                </select>
            </div>
            <div class="cw-field-row">
                <label>Result variable</label>
                <input class="cw-input" value=${result} onInput=${(e) => set_result(e.target.value)} placeholder="df_clean" />
            </div>
            <pre class="cw-preview"><code>${code}</code></pre>
            <button class="cw-insert-btn" onClick=${() => on_insert(code)}>↓ Insert cell</button>
        </div>
    `
}

function StringsWidget({ on_insert }) {
    const [df, set_df] = useState("df")
    const [col, set_col] = useState("text_col")
    const [do_strip, set_strip] = useState(true)
    const [do_lowercase, set_lowercase] = useState(false)
    const [do_uppercase, set_uppercase] = useState(false)
    const [do_titlecase, set_titlecase] = useState(false)
    const [do_collapse_spaces, set_collapse_spaces] = useState(false)
    const [do_remove_special, set_remove_special] = useState(false)
    const [result, set_result] = useState("df_clean")

    // Enforce mutual exclusion among case transforms using a setters map
    const case_setters = { lowercase: set_lowercase, uppercase: set_uppercase, titlecase: set_titlecase }
    const handle_case_change = useCallback(
        (type, checked) => {
            case_setters[type](checked)
            if (checked) {
                Object.entries(case_setters)
                    .filter(([k]) => k !== type)
                    .forEach(([, setter]) => setter(false))
            }
        },
        []
    )

    const transforms = []
    if (do_strip) transforms.push("strip")
    if (do_lowercase) transforms.push("lowercase")
    if (do_uppercase) transforms.push("uppercase")
    if (do_titlecase) transforms.push("titlecase")
    if (do_collapse_spaces) transforms.push(TRANSFORM_COLLAPSE_SPACES)
    if (do_remove_special) transforms.push(TRANSFORM_REMOVE_SPECIAL)

    const df_name = df.trim() || "df"
    const col_name = col.trim() || "text_col"
    const res_name = result.trim() || "df_clean"
    const code = gen_strings_code_clean({ df_name, col_name, res_name, transforms })

    return html`
        <div class="cw-widget">
            <div class="cw-widget-title">🔤 String Cleanup</div>
            <div class="cw-field-row">
                <label>DataFrame</label>
                <input class="cw-input" value=${df} onInput=${(e) => set_df(e.target.value)} placeholder="df" />
            </div>
            <div class="cw-field-row">
                <label>Column</label>
                <input class="cw-input" value=${col} onInput=${(e) => set_col(e.target.value)} placeholder="text_col" />
            </div>
            <div class="cw-checkboxes">
                <label><input type="checkbox" checked=${do_strip} onChange=${(e) => set_strip(e.target.checked)} /> Strip whitespace</label>
                <label><input type="checkbox" checked=${do_lowercase} onChange=${(e) => handle_case_change("lowercase", e.target.checked)} /> lowercase</label>
                <label><input type="checkbox" checked=${do_uppercase} onChange=${(e) => handle_case_change("uppercase", e.target.checked)} /> UPPERCASE</label>
                <label><input type="checkbox" checked=${do_titlecase} onChange=${(e) => handle_case_change("titlecase", e.target.checked)} /> Title Case</label>
                <label><input type="checkbox" checked=${do_collapse_spaces} onChange=${(e) => set_collapse_spaces(e.target.checked)} /> Collapse spaces</label>
                <label><input type="checkbox" checked=${do_remove_special} onChange=${(e) => set_remove_special(e.target.checked)} /> Remove special chars</label>
            </div>
            <div class="cw-field-row">
                <label>Result variable</label>
                <input class="cw-input" value=${result} onInput=${(e) => set_result(e.target.value)} placeholder="df_clean" />
            </div>
            <pre class="cw-preview"><code>${code}</code></pre>
            <button class="cw-insert-btn" onClick=${() => on_insert(code)}>↓ Insert cell</button>
        </div>
    `
}

function DatesWidget({ on_insert }) {
    const [df, set_df] = useState("df")
    const [col, set_col] = useState("date_col")
    const [fmt, set_fmt] = useState("yyyy-mm-dd")
    const [out_fmt, set_out_fmt] = useState("Date")
    const [coerce_missing, set_coerce_missing] = useState(true)
    const [result, set_result] = useState("df_clean")

    const code = gen_dates_code({ df, col, fmt, out_fmt, coerce_missing, result })

    return html`
        <div class="cw-widget">
            <div class="cw-widget-title">📅 Date Parsing</div>
            <div class="cw-field-row">
                <label>DataFrame</label>
                <input class="cw-input" value=${df} onInput=${(e) => set_df(e.target.value)} placeholder="df" />
            </div>
            <div class="cw-field-row">
                <label>Column</label>
                <input class="cw-input" value=${col} onInput=${(e) => set_col(e.target.value)} placeholder="date_col" />
            </div>
            <div class="cw-field-row">
                <label>Input format</label>
                <input class="cw-input" value=${fmt} onInput=${(e) => set_fmt(e.target.value)} placeholder="yyyy-mm-dd" />
            </div>
            <div class="cw-field-row cw-hint-row">
                <span class="cw-hint">Julia dateformat tokens: yyyy, mm, dd, HH, MM, SS — e.g. "dd/mm/yyyy"</span>
            </div>
            <div class="cw-field-row">
                <label>Output type</label>
                <select class="cw-select" value=${out_fmt} onChange=${(e) => set_out_fmt(e.target.value)}>
                    <option value="Date">Date (date only)</option>
                    <option value="DateTime">DateTime (date + time)</option>
                </select>
            </div>
            <div class="cw-checkboxes">
                <label>
                    <input type="checkbox" checked=${coerce_missing} onChange=${(e) => set_coerce_missing(e.target.checked)} />
                    Coerce parse failures to <code>missing</code>
                </label>
            </div>
            <div class="cw-field-row">
                <label>Result variable</label>
                <input class="cw-input" value=${result} onInput=${(e) => set_result(e.target.value)} placeholder="df_clean" />
            </div>
            <pre class="cw-preview"><code>${code}</code></pre>
            <button class="cw-insert-btn" onClick=${() => on_insert(code)}>↓ Insert cell</button>
        </div>
    `
}

// ─── Main panel ──────────────────────────────────────────────────────────────

export function CleaningWidgetsPanel({ open, onClose, notebook_id, notebook_cell_order }) {
    const pluto_actions = useContext(PlutoActionsContext)
    const [active_tab, set_active_tab] = useState("duplicates")
    const [workflow_steps, set_workflow_steps] = useState([])

    const insert_cell = useCallback(
        async (code) => {
            const index = notebook_cell_order ? notebook_cell_order.length : 0
            await pluto_actions.add_remote_cell_at(index, code)
            // Track in workflow chain
            set_workflow_steps((prev) => {
                const label =
                    active_tab === "duplicates"
                        ? "Remove duplicates"
                        : active_tab === "strings"
                          ? "Clean strings"
                          : "Parse dates"
                return [...prev, label]
            })
        },
        [pluto_actions, notebook_cell_order, active_tab]
    )

    const insert_workflow_comment = useCallback(async () => {
        if (workflow_steps.length === 0) return
        const index = notebook_cell_order ? notebook_cell_order.length : 0
        await pluto_actions.add_remote_cell_at(index, gen_workflow_comment(workflow_steps))
    }, [pluto_actions, notebook_cell_order, workflow_steps])

    if (!open) return null

    const tabs = [
        { id: "duplicates", label: "🔁 Duplicates" },
        { id: "strings", label: "🔤 Strings" },
        { id: "dates", label: "📅 Dates" },
    ]

    return html`
        <div id="cw-panel-backdrop" onClick=${(e) => e.target.id === "cw-panel-backdrop" && onClose()}>
            <div id="cw-panel">
                <div id="cw-panel-header">
                    <span id="cw-panel-title">🧹 Data Cleaning Widgets</span>
                    <button id="cw-panel-close" onClick=${onClose} title="Close (Esc)">✕</button>
                </div>

                <div id="cw-tabs">
                    ${tabs.map(
                        ({ id, label }) => html`
                            <button
                                class=${"cw-tab" + (active_tab === id ? " cw-tab-active" : "")}
                                onClick=${() => set_active_tab(id)}
                            >
                                ${label}
                            </button>
                        `
                    )}
                </div>

                <div id="cw-panel-body">
                    ${active_tab === "duplicates" && html`<${DuplicatesWidget} on_insert=${insert_cell} />`}
                    ${active_tab === "strings" && html`<${StringsWidget} on_insert=${insert_cell} />`}
                    ${active_tab === "dates" && html`<${DatesWidget} on_insert=${insert_cell} />`}

                    ${workflow_steps.length > 0 &&
                    html`<div class="cw-workflow-chain">
                        <span class="cw-workflow-label">Workflow so far (${workflow_steps.length} step${workflow_steps.length > 1 ? "s" : ""}):</span>
                        <ol class="cw-workflow-list">
                            ${workflow_steps.map((s) => html`<li>${s}</li>`)}
                        </ol>
                        <div class="cw-workflow-actions">
                            <button class="cw-insert-btn" onClick=${insert_workflow_comment}>↓ Insert workflow comment</button>
                            <button class="cw-clear-btn" onClick=${() => set_workflow_steps([])}>Clear</button>
                        </div>
                    </div>`}
                </div>
            </div>
        </div>
    `
}

// ─── Styles ──────────────────────────────────────────────────────────────────

const CW_STYLES = `
#cw-panel-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.35);
    z-index: 10000;
    display: flex;
    align-items: flex-start;
    justify-content: flex-end;
    padding: 60px 16px 16px;
}

#cw-panel {
    background: var(--background-color, #fff);
    border: 1.5px solid var(--border-color, #e0e0e0);
    border-radius: 10px;
    box-shadow: 0 8px 32px rgba(0,0,0,0.18);
    width: min(500px, 96vw);
    max-height: calc(100vh - 80px);
    display: flex;
    flex-direction: column;
    overflow: hidden;
    font-family: var(--font-family, inherit);
}

#cw-panel-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 16px;
    border-bottom: 1px solid var(--border-color, #e0e0e0);
    background: var(--header-bg, #f8f8f8);
    flex-shrink: 0;
}

#cw-panel-title {
    font-weight: 600;
    font-size: 0.95em;
    color: var(--pluto-output-color, #333);
}

#cw-panel-close {
    background: none;
    border: none;
    cursor: pointer;
    font-size: 1.1em;
    color: #888;
    padding: 2px 6px;
    border-radius: 4px;
    line-height: 1;
}
#cw-panel-close:hover { background: var(--hover-color, #eee); color: #333; }

#cw-tabs {
    display: flex;
    border-bottom: 1px solid var(--border-color, #e0e0e0);
    background: var(--header-bg, #f8f8f8);
    flex-shrink: 0;
}

.cw-tab {
    flex: 1;
    padding: 8px 4px;
    background: none;
    border: none;
    border-bottom: 2.5px solid transparent;
    cursor: pointer;
    font-size: 0.82em;
    font-weight: 500;
    color: var(--pluto-output-color, #555);
    transition: background 0.12s, border-color 0.12s;
}
.cw-tab:hover { background: var(--hover-color, #eee); }
.cw-tab-active {
    border-bottom-color: #4a9eff;
    color: #4a9eff;
    font-weight: 700;
}

#cw-panel-body {
    padding: 14px 16px;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.cw-widget {
    display: flex;
    flex-direction: column;
    gap: 8px;
}

.cw-widget-title {
    font-weight: 700;
    font-size: 0.92em;
    color: var(--pluto-output-color, #333);
    margin-bottom: 2px;
}

.cw-field-row {
    display: flex;
    align-items: center;
    gap: 8px;
}
.cw-field-row label {
    min-width: 110px;
    font-size: 0.83em;
    font-weight: 500;
    color: var(--pluto-output-color, #555);
    white-space: nowrap;
}

.cw-hint-row { margin-top: -4px; }
.cw-hint {
    font-size: 0.75em;
    color: #999;
    font-style: italic;
}

.cw-input {
    flex: 1;
    padding: 4px 8px;
    border: 1.5px solid var(--border-color, #ccc);
    border-radius: 5px;
    font-size: 0.88em;
    background: var(--input-bg, #fff);
    color: var(--pluto-output-color, #333);
}
.cw-input:focus { outline: none; border-color: #4a9eff; }

.cw-select {
    flex: 1;
    padding: 4px 8px;
    border: 1.5px solid var(--border-color, #ccc);
    border-radius: 5px;
    font-size: 0.88em;
    background: var(--input-bg, #fff);
    color: var(--pluto-output-color, #333);
}

.cw-checkboxes {
    display: flex;
    flex-wrap: wrap;
    gap: 6px 12px;
    padding: 4px 0;
}
.cw-checkboxes label {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: 0.83em;
    cursor: pointer;
    user-select: none;
}
.cw-checkboxes input[type=checkbox] { cursor: pointer; }

.cw-preview {
    background: var(--code-bg, #f5f5f5);
    border: 1px solid var(--border-color, #e0e0e0);
    border-radius: 6px;
    padding: 8px 10px;
    margin: 0;
    font-size: 0.78em;
    font-family: "JuliaMono", "Cascadia Code", "Fira Code", monospace;
    white-space: pre;
    overflow-x: auto;
    max-height: 110px;
    overflow-y: auto;
}

.cw-insert-btn {
    align-self: flex-start;
    padding: 5px 14px;
    background: #4a9eff;
    color: #fff;
    border: none;
    border-radius: 5px;
    font-size: 0.85em;
    font-weight: 600;
    cursor: pointer;
    transition: background 0.13s;
}
.cw-insert-btn:hover { background: #2e7de0; }

.cw-clear-btn {
    padding: 5px 12px;
    background: none;
    border: 1px solid var(--border-color, #ccc);
    border-radius: 5px;
    font-size: 0.85em;
    cursor: pointer;
    color: var(--pluto-output-color, #555);
}
.cw-clear-btn:hover { background: var(--hover-color, #eee); }

.cw-workflow-chain {
    margin-top: 8px;
    border-top: 1px solid var(--border-color, #e0e0e0);
    padding-top: 10px;
    display: flex;
    flex-direction: column;
    gap: 6px;
}

.cw-workflow-label {
    font-size: 0.82em;
    font-weight: 600;
    color: #888;
    text-transform: uppercase;
    letter-spacing: 0.04em;
}

.cw-workflow-list {
    margin: 0;
    padding-left: 18px;
    font-size: 0.84em;
    color: var(--pluto-output-color, #444);
}
.cw-workflow-list li { margin: 2px 0; }

.cw-workflow-actions {
    display: flex;
    gap: 8px;
    align-items: center;
}

/* Nav button */
#cw-nav-btn {
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
#cw-nav-btn:hover {
    background: var(--hover-color, rgba(0,0,0,0.05));
    border-color: var(--border-color, #ccc);
}
#cw-nav-btn.active {
    background: #4a9eff22;
    border-color: #4a9eff;
    color: #4a9eff;
}
`

// Inject styles once
if (!document.getElementById("cw-panel-styles")) {
    const style = document.createElement("style")
    style.id = "cw-panel-styles"
    style.textContent = CW_STYLES
    document.head.appendChild(style)
}
