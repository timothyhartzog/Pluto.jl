import { html, useState, useContext, useCallback } from "../imports/Preact.js"
import { PlutoActionsContext } from "../common/PlutoContext.js"
import { ctrl_or_cmd_name, has_ctrl_or_cmd_pressed } from "../common/KeyboardShortcuts.js"
import { open_bottom_right_panel } from "./BottomRightPanel.js"
import { useEventListener } from "../common/useEventListener.js"

// ─── Help mode persistence ───────────────────────────────────────────────────

const HELP_MODE_KEY = "pluto-help-mode"

/** @typedef {"minimal" | "guided" | "verbose"} HelpMode */

/**
 * Read the persisted help mode from localStorage.
 * @returns {HelpMode}
 */
const load_help_mode = () => {
    try {
        const stored = localStorage.getItem(HELP_MODE_KEY)
        if (stored === "minimal" || stored === "guided" || stored === "verbose") return stored
    } catch (_) {}
    return "guided"
}

/**
 * Persist the help mode to localStorage.
 * @param {HelpMode} mode
 */
const save_help_mode = (mode) => {
    try {
        localStorage.setItem(HELP_MODE_KEY, mode)
    } catch (_) {}
}

// ─── Action registry ─────────────────────────────────────────────────────────

/**
 * @typedef SidebarAction
 * @property {string} id Unique identifier used for keyboard shortcut dispatch
 * @property {string} label Short button label
 * @property {string} icon Emoji / symbol shown on the button
 * @property {string} description Longer description shown in guided/verbose modes
 * @property {string} shortcut Human-readable shortcut hint
 * @property {(actions: any, notebook: any) => void} run Function executed on click/shortcut
 */

/** @returns {SidebarAction[]} */
const build_action_registry = (
    /** @type {any} */ actions,
    /** @type {import("./Editor.js").NotebookData} */ notebook
) => [
    {
        id: "run_all",
        label: "Run all",
        icon: "▶▶",
        description: "Run every cell in the notebook",
        shortcut: `${ctrl_or_cmd_name}+Shift+↵`,
        run: () => {
            const all_ids = notebook?.cell_order ?? []
            if (all_ids.length > 0) {
                actions.set_and_run_multiple(all_ids)
            }
        },
    },
    {
        id: "interrupt",
        label: "Interrupt",
        icon: "⏹",
        description: "Interrupt the currently running computation",
        shortcut: `${ctrl_or_cmd_name}+Q`,
        run: () => actions.interrupt_remote?.(),
    },
    {
        id: "add_cell",
        label: "Add cell",
        icon: "＋",
        description: "Add a new code cell at the end of the notebook",
        shortcut: `${ctrl_or_cmd_name}+Shift+A`,
        run: () => {
            const index = notebook?.cell_order?.length ?? 0
            actions.add_remote_cell_at(index, "")
        },
    },
    {
        id: "run_selected",
        label: "Run selected",
        icon: "▶",
        description: "Run the currently selected cells (Shift+Enter also works)",
        shortcut: "Shift+↵",
        run: () => {
            const selected = actions.get_selected_cells?.(null, true) ?? []
            if (selected.length > 0) actions.set_and_run_multiple(selected)
        },
    },
    {
        id: "open_docs",
        label: "Docs",
        icon: "?",
        description: "Open the live documentation panel",
        shortcut: `${ctrl_or_cmd_name}+Shift+D`,
        run: () => open_bottom_right_panel("docs"),
    },
]

// ─── Component ────────────────────────────────────────────────────────────────

/**
 * @param {{
 *   notebook: import("./Editor.js").NotebookData,
 *   disable_input: boolean,
 * }} props
 */
export const SidebarActions = ({ notebook, disable_input }) => {
    const actions = useContext(PlutoActionsContext)
    const [help_mode, set_help_mode_state] = useState(/** @type {HelpMode} */ (load_help_mode()))

    const set_help_mode = useCallback((/** @type {HelpMode} */ mode) => {
        set_help_mode_state(mode)
        save_help_mode(mode)
    }, [])

    const action_registry = build_action_registry(actions, notebook)

    // Global keyboard shortcuts for sidebar actions
    useEventListener(
        window,
        "keydown",
        (/** @type {KeyboardEvent} */ e) => {
            if (disable_input) return

            const tag = /** @type {HTMLElement} */ (document.activeElement)?.tagName
            // Avoid interfering with text input areas, except for our explicit shortcuts
            const in_input = tag === "INPUT" || tag === "TEXTAREA"

            if (has_ctrl_or_cmd_pressed(e) && e.shiftKey && e.key === "Enter") {
                // Ctrl/Cmd + Shift + Enter → Run all cells
                e.preventDefault()
                const all_ids = notebook?.cell_order ?? []
                if (all_ids.length > 0) actions.set_and_run_multiple(all_ids)
            } else if (has_ctrl_or_cmd_pressed(e) && e.shiftKey && (e.key === "a" || e.key === "A")) {
                if (!in_input) {
                    // Ctrl/Cmd + Shift + A → Add cell
                    e.preventDefault()
                    const index = notebook?.cell_order?.length ?? 0
                    actions.add_remote_cell_at(index, "")
                }
            } else if (has_ctrl_or_cmd_pressed(e) && e.shiftKey && (e.key === "d" || e.key === "D")) {
                // Ctrl/Cmd + Shift + D → Open docs
                e.preventDefault()
                open_bottom_right_panel("docs")
            }
        },
        [disable_input, actions, notebook]
    )

    const show_descriptions = help_mode === "guided" || help_mode === "verbose"
    const show_shortcut_hints = help_mode === "verbose"

    return html`
        <aside id="sidebar-actions" aria-label="Sidebar quick actions">
            <div id="sidebar-actions-inner">
                <!-- Help mode selector -->
                <div id="sidebar-help-mode" title="Help mode: controls how much guidance is shown">
                    <span id="sidebar-help-mode-label">Help</span>
                    <div id="sidebar-help-mode-buttons">
                        ${(["minimal", "guided", "verbose"]).map(
                            (mode) => html`
                                <button
                                    key=${mode}
                                    class=${`sidebar-help-mode-btn${help_mode === mode ? " active" : ""}`}
                                    title=${mode === "minimal"
                                        ? "Minimal – icons only"
                                        : mode === "guided"
                                          ? "Guided – show descriptions"
                                          : "Verbose – show descriptions + shortcuts"}
                                    onClick=${() => set_help_mode(/** @type {HelpMode} */ (mode))}
                                >
                                    ${mode === "minimal" ? "·" : mode === "guided" ? "○" : "●"}
                                </button>
                            `
                        )}
                    </div>
                </div>

                <!-- Action buttons -->
                <div id="sidebar-action-buttons">
                    ${action_registry.map(
                        (action) => html`
                            <button
                                key=${action.id}
                                class="sidebar-action-btn"
                                id=${`sidebar-action-${action.id}`}
                                title=${action.description}
                                disabled=${disable_input}
                                onClick=${(e) => {
                                    e.preventDefault()
                                    action.run()
                                }}
                            >
                                <span class="sidebar-action-icon">${action.icon}</span>
                                ${show_descriptions
                                    ? html`<span class="sidebar-action-label">${action.label}</span>`
                                    : null}
                                ${show_shortcut_hints
                                    ? html`<span class="sidebar-action-shortcut">${action.shortcut}</span>`
                                    : null}
                            </button>
                        `
                    )}
                </div>
            </div>
        </aside>
    `
}

// ─── Styles ──────────────────────────────────────────────────────────────────

const SIDEBAR_STYLES = `
#sidebar-actions {
    position: fixed;
    left: 0;
    top: 50%;
    transform: translateY(-50%);
    z-index: 40;
    /* Hide on very narrow screens */
    display: none;
}

@media (min-width: 900px) {
    #sidebar-actions {
        display: block;
    }
}

#sidebar-actions-inner {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    background: var(--sidebar-bg, var(--helpbox-bg-color, #f8f8f8));
    border: 1.5px solid var(--sidebar-border, var(--helpbox-box-shadow-color, #e0e0e0));
    border-left: none;
    border-radius: 0 10px 10px 0;
    box-shadow: 2px 2px 10px rgba(0,0,0,0.10);
    padding: 6px 4px;
    gap: 4px;
    min-width: 42px;
}

/* ─── help mode selector ─── */

#sidebar-help-mode {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding-bottom: 6px;
    border-bottom: 1px solid var(--sidebar-border, #e0e0e0);
    margin-bottom: 4px;
    gap: 3px;
}

#sidebar-help-mode-label {
    font-size: 0.65em;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--pluto-output-color, #888);
    opacity: 0.6;
    user-select: none;
}

#sidebar-help-mode-buttons {
    display: flex;
    flex-direction: row;
    gap: 2px;
}

.sidebar-help-mode-btn {
    background: none;
    border: 1.5px solid transparent;
    border-radius: 4px;
    cursor: pointer;
    font-size: 0.85em;
    line-height: 1;
    padding: 2px 4px;
    color: var(--pluto-output-color, #888);
    transition: background 0.12s, border-color 0.12s;
}

.sidebar-help-mode-btn:hover {
    background: var(--hover-color, rgba(0,0,0,0.06));
    border-color: var(--sidebar-border, #ccc);
}

.sidebar-help-mode-btn.active {
    background: var(--sidebar-active-bg, rgba(207,139,78,0.15));
    border-color: #cf8b4e;
    color: #cf8b4e;
    font-weight: 700;
}

/* ─── action buttons ─── */

#sidebar-action-buttons {
    display: flex;
    flex-direction: column;
    gap: 3px;
    align-items: stretch;
}

.sidebar-action-btn {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background: none;
    border: 1.5px solid transparent;
    border-radius: 7px;
    cursor: pointer;
    padding: 5px 6px;
    color: var(--pluto-output-color, #444);
    transition: background 0.12s, border-color 0.12s;
    gap: 2px;
    min-width: 34px;
}

.sidebar-action-btn:hover:not(:disabled) {
    background: var(--hover-color, rgba(0,0,0,0.06));
    border-color: var(--sidebar-border, #ccc);
}

.sidebar-action-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
}

.sidebar-action-btn:active:not(:disabled) {
    background: var(--sidebar-active-bg, rgba(207,139,78,0.15));
    border-color: #cf8b4e;
}

.sidebar-action-icon {
    font-size: 1.1em;
    line-height: 1;
    user-select: none;
}

.sidebar-action-label {
    font-size: 0.65em;
    font-weight: 600;
    text-align: center;
    white-space: nowrap;
    user-select: none;
    color: var(--pluto-output-color, #555);
    max-width: 80px;
}

.sidebar-action-shortcut {
    font-size: 0.58em;
    color: #aaa;
    font-family: var(--julia-mono-font-stack, monospace);
    white-space: nowrap;
    user-select: none;
    text-align: center;
}
`

// Inject styles once
if (typeof document !== "undefined" && !document.getElementById("sidebar-actions-styles")) {
    const style = document.createElement("style")
    style.id = "sidebar-actions-styles"
    style.textContent = SIDEBAR_STYLES
    document.head.appendChild(style)
}
