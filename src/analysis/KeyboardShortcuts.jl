"""
    KeyboardShortcuts

Manages keyboard shortcut definitions for common Pluto workflow actions.

Provides:
- A registry of named shortcuts with key bindings, descriptions, and context
- Conflict detection (same key in the same context)
- UI hint generation for the frontend
- Accessibility metadata for screen readers

## Example

```julia
map = default_shortcuts()
hints = shortcut_hints(map, :cell)
conflicts = resolve_conflicts(map)
```
"""
module KeyboardShortcuts

export KeyboardShortcut, ShortcutMap
export default_shortcuts, register_shortcut!, resolve_conflicts, shortcut_hints, is_accessible

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

"""
    KeyboardShortcut

A single keyboard shortcut binding.

Fields:
- `action`             – unique symbol identifying the action (e.g. `:run_cell`)
- `key`                – OS-agnostic key string, e.g. `"Ctrl+Enter"` / `"Shift+Enter"`
- `description`        – human-readable description of the action
- `context`            – where the shortcut is active: `:global`, `:cell`, or `:editor`
- `accessibility_label`– text announced by screen readers when the shortcut is triggered
"""
struct KeyboardShortcut
    action::Symbol
    key::String
    description::String
    context::Symbol
    accessibility_label::String
end

"""
    ShortcutMap

A dictionary mapping action `Symbol`s to their `KeyboardShortcut` definitions.
"""
const ShortcutMap = Dict{Symbol, KeyboardShortcut}

# ---------------------------------------------------------------------------
# Default bindings
# ---------------------------------------------------------------------------

"""
    default_shortcuts() -> ShortcutMap

Return a `ShortcutMap` containing the built-in keyboard shortcuts for Pluto.

| Action                   | Key              | Context   |
|--------------------------|------------------|-----------|
| `:run_cell`              | Shift+Enter      | cell      |
| `:run_cell_and_next`     | Ctrl+Enter       | cell      |
| `:run_all`               | Ctrl+Shift+Enter | global    |
| `:interrupt`             | Ctrl+C           | global    |
| `:add_cell_below`        | Ctrl+Shift+A     | cell      |
| `:delete_cell`           | Ctrl+Delete      | cell      |
| `:move_cell_up`          | Ctrl+ArrowUp     | cell      |
| `:move_cell_down`        | Ctrl+ArrowDown   | cell      |
| `:fold_cell`             | Ctrl+B           | cell      |
| `:save_notebook`         | Ctrl+S           | global    |
| `:toggle_live_docs`      | F1               | global    |
| `:focus_prev_cell`       | ArrowUp          | editor    |
| `:focus_next_cell`       | ArrowDown        | editor    |
"""
function default_shortcuts()::ShortcutMap
    shortcuts = [
        KeyboardShortcut(:run_cell,          "Shift+Enter",       "Run the focused cell",                    :cell,   "Run cell"),
        KeyboardShortcut(:run_cell_and_next, "Ctrl+Enter",        "Run cell and move focus to next cell",    :cell,   "Run cell and advance"),
        KeyboardShortcut(:run_all,           "Ctrl+Shift+Enter",  "Run all cells in the notebook",           :global, "Run all cells"),
        KeyboardShortcut(:interrupt,         "Ctrl+C",            "Interrupt the running evaluation",        :global, "Interrupt evaluation"),
        KeyboardShortcut(:add_cell_below,    "Ctrl+Shift+A",      "Insert a new cell below the focused cell",:cell,   "Add cell below"),
        KeyboardShortcut(:delete_cell,       "Ctrl+Delete",       "Delete the focused cell",                 :cell,   "Delete cell"),
        KeyboardShortcut(:move_cell_up,      "Ctrl+ArrowUp",      "Move focused cell up",                    :cell,   "Move cell up"),
        KeyboardShortcut(:move_cell_down,    "Ctrl+ArrowDown",    "Move focused cell down",                  :cell,   "Move cell down"),
        KeyboardShortcut(:fold_cell,         "Ctrl+B",            "Toggle code folding for focused cell",    :cell,   "Toggle code fold"),
        KeyboardShortcut(:save_notebook,     "Ctrl+S",            "Save the notebook",                       :global, "Save notebook"),
        KeyboardShortcut(:toggle_live_docs,  "F1",                "Toggle the live documentation panel",     :global, "Toggle live docs"),
        KeyboardShortcut(:focus_prev_cell,   "ArrowUp",           "Move focus to the previous cell",         :editor, "Focus previous cell"),
        KeyboardShortcut(:focus_next_cell,   "ArrowDown",         "Move focus to the next cell",             :editor, "Focus next cell"),
    ]
    return ShortcutMap(s.action => s for s in shortcuts)
end

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

"""
    register_shortcut!(map::ShortcutMap, shortcut::KeyboardShortcut) -> ShortcutMap

Add or replace the shortcut for `shortcut.action` in `map`.

Returns `map` to allow chaining.
"""
function register_shortcut!(map::ShortcutMap, shortcut::KeyboardShortcut)::ShortcutMap
    map[shortcut.action] = shortcut
    return map
end

# ---------------------------------------------------------------------------
# Conflict detection
# ---------------------------------------------------------------------------

"""
    resolve_conflicts(map::ShortcutMap) -> Vector{Tuple{KeyboardShortcut, KeyboardShortcut}}

Return all pairs of shortcuts in `map` that share the same `key` **and** `context`.

An empty vector means there are no conflicts.

## Example
```julia
conflicts = resolve_conflicts(default_shortcuts())
@assert isempty(conflicts)
```
"""
function resolve_conflicts(map::ShortcutMap)::Vector{Tuple{KeyboardShortcut, KeyboardShortcut}}
    conflicts = Tuple{KeyboardShortcut, KeyboardShortcut}[]
    shortcuts = collect(values(map))
    for i in 1:length(shortcuts)
        for j in (i+1):length(shortcuts)
            a, b = shortcuts[i], shortcuts[j]
            if a.key == b.key && a.context == b.context
                push!(conflicts, (a, b))
            end
        end
    end
    return conflicts
end

# ---------------------------------------------------------------------------
# UI hint generation
# ---------------------------------------------------------------------------

"""
    shortcut_hints(map::ShortcutMap, context::Symbol=:global) -> Vector{NamedTuple}

Return a vector of named tuples suitable for rendering shortcut hints in the UI.

Each element has the shape:
```julia
(action=:symbol, key="Key", description="...", accessibility_label="...")
```

Pass `context=:all` to include shortcuts from every context.
"""
function shortcut_hints(
    map::ShortcutMap,
    context::Symbol = :global,
)::Vector{NamedTuple{(:action, :key, :description, :accessibility_label), Tuple{Symbol, String, String, String}}}
    filtered = if context === :all
        collect(values(map))
    else
        filter(s -> s.context === context, collect(values(map)))
    end
    sort!(filtered; by = s -> string(s.action))
    return [
        (action=s.action, key=s.key, description=s.description, accessibility_label=s.accessibility_label)
        for s in filtered
    ]
end

# ---------------------------------------------------------------------------
# Accessibility validation
# ---------------------------------------------------------------------------

"""
    is_accessible(shortcut::KeyboardShortcut) -> Bool

Return `true` when `shortcut` satisfies basic accessibility requirements:

1. `accessibility_label` is non-empty.
2. `description` is non-empty.
3. `key` is non-empty.
"""
function is_accessible(shortcut::KeyboardShortcut)::Bool
    !isempty(shortcut.accessibility_label) &&
    !isempty(shortcut.description) &&
    !isempty(shortcut.key)
end

"""
    is_accessible(map::ShortcutMap) -> Bool

Return `true` when **every** shortcut in `map` passes `is_accessible`.
"""
function is_accessible(map::ShortcutMap)::Bool
    all(is_accessible, values(map))
end

end # module KeyboardShortcuts
