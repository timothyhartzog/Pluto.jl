module SidebarActions

export Action, ActionRegistry, NotebookContext
export register!, available_actions, notebook_context, default_registry

"""
Captures the relevant state of a notebook used to determine which sidebar
actions are available.
"""
struct NotebookContext
    "Number of cells in the notebook."
    cell_count::Int

    "Whether the notebook appears to load external data (e.g. CSV.read, DataFrame)."
    has_data_loading::Bool

    "Whether the notebook defines or references DataFrame-like structures."
    has_dataframe::Bool

    "Whether the notebook contains plotting code."
    has_plots::Bool

    "The set of top-level symbols defined across all notebook cells."
    defined_symbols::Set{Symbol}
end

"""
A sidebar quick action that can be presented to the user.

Fields
======
- `id`          – unique identifier (e.g. `:load_data`)
- `label`       – short human-readable name shown in the sidebar
- `description` – longer tooltip / description
- `is_available` – predicate `(ctx::NotebookContext) -> Bool`; returns `true`
                  when the action should be shown given the notebook context
- `code_template` – Julia code snippet that is inserted when the action is triggered
"""
struct Action
    id::Symbol
    label::String
    description::String
    is_available::Function
    code_template::String
end

"""
A mutable registry of sidebar actions. Supports registration of custom actions,
making it extensible for future use-cases.
"""
mutable struct ActionRegistry
    actions::Vector{Action}
end

ActionRegistry() = ActionRegistry(Action[])

"""
    register!(registry, action) -> registry

Add `action` to `registry`. Returns the registry so calls can be chained.
"""
function register!(registry::ActionRegistry, action::Action)
    push!(registry.actions, action)
    registry
end

"""
    available_actions(registry, context) -> Vector{Action}

Return all actions in `registry` whose `is_available` predicate is satisfied
by `context`.
"""
function available_actions(registry::ActionRegistry, context::NotebookContext)::Vector{Action}
    filter(a -> a.is_available(context), registry.actions)
end

# ---------------------------------------------------------------------------
# Default actions
# ---------------------------------------------------------------------------

const ACTION_LOAD_DATA = Action(
    :load_data,
    "Load Data",
    "Insert code to load data from a file or URL into a DataFrame.",
    ctx -> true,  # always available
    """import CSV, DataFrames
df = CSV.read("path/to/your_file.csv", DataFrames.DataFrame)
""",
)

const ACTION_PROFILE_DATA = Action(
    :profile_data,
    "Profile Data",
    "Generate a summary profile of the loaded DataFrame.",
    ctx -> ctx.has_data_loading || ctx.has_dataframe,
    """# Profile your DataFrame
describe(df)
""",
)

const ACTION_CLEAN_DATA = Action(
    :clean_data,
    "Clean Data",
    "Insert code to handle missing values and fix common data quality issues.",
    ctx -> ctx.has_data_loading || ctx.has_dataframe,
    """import DataFrames: dropmissing, rename!
df_clean = dropmissing(df)
""",
)

const ACTION_PLOT_SUGGESTIONS = Action(
    :plot_suggestions,
    "Plot Suggestions",
    "Generate plot code based on the columns in your DataFrame.",
    ctx -> ctx.has_data_loading || ctx.has_dataframe,
    """import Plots
Plots.plot(df[!, 1], df[!, 2])
""",
)

const ACTION_EXPORT = Action(
    :export,
    "Export",
    "Export the notebook or its data to a file.",
    ctx -> ctx.cell_count > 0,
    """import CSV
CSV.write("output.csv", df)
""",
)

const DEFAULT_ACTIONS = [
    ACTION_LOAD_DATA,
    ACTION_PROFILE_DATA,
    ACTION_CLEAN_DATA,
    ACTION_PLOT_SUGGESTIONS,
    ACTION_EXPORT,
]

# ---------------------------------------------------------------------------
# Default registry factory
# ---------------------------------------------------------------------------

"""
    default_registry() -> ActionRegistry

Return a new `ActionRegistry` pre-populated with the five default actions:
Load Data, Profile Data, Clean Data, Plot Suggestions, and Export.
"""
function default_registry()::ActionRegistry
    registry = ActionRegistry()
    for action in DEFAULT_ACTIONS
        register!(registry, action)
    end
    registry
end

# ---------------------------------------------------------------------------
# Notebook context builder
# ---------------------------------------------------------------------------

# Packages / symbols that indicate data-loading activity
const _DATA_LOADING_PACKAGES = [
    "CSV", "XLSX", "ExcelFiles", "Parquet", "Arrow", "JSON", "JSON3",
    "Downloads", "HTTP",
]

const _DATAFRAME_PACKAGES = [
    "DataFrames", "DataFramesMeta", "Tidier", "TypedTables",
]

const _PLOT_PACKAGES = [
    "Plots", "Makie", "CairoMakie", "GLMakie", "WGLMakie", "AlgebraOfGraphics",
    "VegaLite", "StatsPlots", "UnicodePlots",
]

# Match `import Foo`, `import Foo.Bar`, `using Foo`, `using Foo: bar`, etc.
# The package name must be preceded by whitespace or a comma and followed by
# a non-word character so that e.g. "CSV" does not match "CSVA".
function _uses_package(code::AbstractString, pkg::AbstractString)::Bool
    # Walk each `using`/`import` statement and check if pkg is in it.
    for m in eachmatch(r"(?:using|import)\s+([\w,\s.]+)", code)
        parts = split(m.captures[1], r"[,\s]+"; keepempty=false)
        for part in parts
            # Strip submodule path, e.g. "DataFrames.DataFrame" -> "DataFrames"
            base = first(split(part, '.'))
            base == pkg && return true
        end
    end
    return false
end

"""
    notebook_context(notebook) -> NotebookContext

Inspect all cells in `notebook` and derive a `NotebookContext` describing the
current state of the notebook. This is used to decide which sidebar actions to
show.
"""
function notebook_context(notebook)::NotebookContext
    cells = notebook.cells
    cell_count = length(cells)

    all_code = join((c.code for c in cells), "\n")

    has_data_loading = any(pkg -> _uses_package(all_code, pkg), _DATA_LOADING_PACKAGES)
    has_dataframe    = any(pkg -> _uses_package(all_code, pkg), _DATAFRAME_PACKAGES)
    has_plots        = any(pkg -> _uses_package(all_code, pkg), _PLOT_PACKAGES)

    # Collect the top-level symbols that are defined across all cells via the
    # topology (when available). The topology may not be fully initialised if
    # this is called very early in the notebook lifecycle, so we handle the
    # MethodError / KeyError that can arise from accessing uninitialised nodes.
    defined_symbols = Set{Symbol}()
    try
        topology = notebook.topology
        for (_, node) in topology.nodes
            union!(defined_symbols, node.definitions)
        end
    catch e
        e isa MethodError || e isa KeyError || rethrow()
    end

    NotebookContext(cell_count, has_data_loading, has_dataframe, has_plots, defined_symbols)
end

end # module SidebarActions
