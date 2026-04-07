module SidebarActions

export Action, ActionRegistry, NotebookContext
export register!, available_actions, notebook_context, default_registry

"""
    NotebookContext

Represents the current state of a notebook, used to determine which sidebar
actions are available.

# Fields
- `has_data_cells::Bool`: whether the notebook contains cells that load data
- `has_dataframes::Bool`: whether the notebook has DataFrame-like variables defined
- `has_plots::Bool`: whether the notebook contains plot-producing cells
- `cell_count::Int`: total number of cells in the notebook
- `defined_symbols::Vector{Symbol}`: symbols defined in the notebook workspace
"""
struct NotebookContext
    has_data_cells::Bool
    has_dataframes::Bool
    has_plots::Bool
    cell_count::Int
    defined_symbols::Vector{Symbol}
end

"""
    NotebookContext(; kwargs...)

Construct a `NotebookContext` with keyword arguments, defaulting all fields to
empty/false.
"""
function NotebookContext(;
    has_data_cells::Bool = false,
    has_dataframes::Bool = false,
    has_plots::Bool = false,
    cell_count::Int = 0,
    defined_symbols::Vector{Symbol} = Symbol[],
)
    NotebookContext(has_data_cells, has_dataframes, has_plots, cell_count, defined_symbols)
end

"""
    Action

Represents a single sidebar quick action.

# Fields
- `id::Symbol`: unique identifier for the action
- `name::String`: human-readable display name
- `description::String`: short description shown in the UI
- `available::Function`: `(ctx::NotebookContext) -> Bool` predicate controlling
  whether this action should be shown given the current notebook context
"""
struct Action
    id::Symbol
    name::String
    description::String
    available::Function
end

"""
    Action(id, name, description)

Construct an `Action` that is always available (ignores notebook context).
"""
function Action(id::Symbol, name::String, description::String)
    Action(id, name, description, _ -> true)
end

"""
    ActionRegistry

A pluggable registry of sidebar `Action`s. New actions can be added at any time
via [`register!`](@ref), enabling future extensibility without modifying core code.
"""
mutable struct ActionRegistry
    actions::Vector{Action}
end

ActionRegistry() = ActionRegistry(Action[])

"""
    register!(registry::ActionRegistry, action::Action)

Add `action` to `registry`. If an action with the same `id` already exists it is
replaced, so calling `register!` is idempotent for a given id.
"""
function register!(registry::ActionRegistry, action::Action)
    idx = findfirst(a -> a.id === action.id, registry.actions)
    if idx === nothing
        push!(registry.actions, action)
    else
        registry.actions[idx] = action
    end
    registry
end

"""
    available_actions(registry::ActionRegistry, ctx::NotebookContext) -> Vector{Action}

Return the subset of actions in `registry` whose `available` predicate returns
`true` for the given `ctx`.
"""
function available_actions(registry::ActionRegistry, ctx::NotebookContext)::Vector{Action}
    filter(a -> a.available(ctx), registry.actions)
end

"""
    notebook_context(notebook) -> NotebookContext

Derive a [`NotebookContext`](@ref) from a Pluto `Notebook` by inspecting cell
source code for common data-loading and plotting patterns.
"""
function notebook_context(notebook)::NotebookContext
    sources = [cell.code for cell in notebook.cells]

    data_patterns = [
        r"\bCSV\b", r"\breadcsv\b", r"\bDataFrame\b", r"\bArrow\b",
        r"\bExcel\b", r"\bJLD2\b", r"\bNPZ\b", r"\bJSON\b", r"\bHTTP\b",
    ]
    plot_patterns = [
        r"\bplot\b", r"\bPlots\b", r"\bMakie\b", r"\bGadfly\b",
        r"\bVegaLite\b", r"\bscatter\b", r"\bheatmap\b", r"\bbar\(",
    ]
    df_patterns = [r"\bDataFrame\b"]

    has_data_cells  = any(s -> any(p -> occursin(p, s), data_patterns),  sources)
    has_dataframes  = any(s -> any(p -> occursin(p, s), df_patterns),     sources)
    has_plots       = any(s -> any(p -> occursin(p, s), plot_patterns),   sources)

    NotebookContext(
        has_data_cells  = has_data_cells,
        has_dataframes  = has_dataframes,
        has_plots       = has_plots,
        cell_count      = length(notebook.cells),
        defined_symbols = Symbol[],
    )
end

# ---------------------------------------------------------------------------
# Default actions
# ---------------------------------------------------------------------------

const load_data = Action(
    :load_data,
    "Load Data",
    "Insert a cell to load data from a file or URL.",
)

const profile_data = Action(
    :profile_data,
    "Profile Data",
    "Generate a statistical profile of the loaded DataFrames.",
    ctx -> ctx.has_dataframes || ctx.has_data_cells,
)

const clean_data = Action(
    :clean_data,
    "Clean Data",
    "Insert cells with common data-cleaning transformations.",
    ctx -> ctx.has_dataframes || ctx.has_data_cells,
)

const plot_suggestions = Action(
    :plot_suggestions,
    "Plot Suggestions",
    "Suggest visualisations based on the current data.",
    ctx -> ctx.has_dataframes || ctx.has_data_cells,
)

const export_action = Action(
    :export,
    "Export",
    "Export the notebook or its outputs.",
    ctx -> ctx.cell_count > 0,
)

"""
    default_registry() -> ActionRegistry

Return a new [`ActionRegistry`](@ref) pre-populated with the five built-in
sidebar actions: Load Data, Profile Data, Clean Data, Plot Suggestions, Export.
"""
function default_registry()::ActionRegistry
    reg = ActionRegistry()
    for action in (load_data, profile_data, clean_data, plot_suggestions, export_action)
        register!(reg, action)
    end
    reg
end

end  # module SidebarActions
