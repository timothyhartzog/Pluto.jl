"""
Notebook-aware context assembly for AI prompt generation.

Collects the user request, notebook state, recent cell outputs, and dataset
profile summaries into a single `NotebookContext` value.  Context size is
bounded by configurable token/character limits and a summarisation fallback
ensures that oversized payloads are never produced.
"""
module NotebookContextAssembler

export NotebookContext, CellContext, DatasetProfile
export assemble_context, render_prompt, profile_dataset

import UUIDs: UUID
import ..Pluto: Cell, Notebook

# ---------------------------------------------------------------------------
# Constants / defaults
# ---------------------------------------------------------------------------

"Maximum number of characters used to represent a single cell output."
const DEFAULT_MAX_CELL_OUTPUT_CHARS = 500

"Maximum total characters for the rendered prompt string."
const DEFAULT_MAX_PROMPT_CHARS = 8_000

"Maximum number of cells included in the context."
const DEFAULT_MAX_CELLS = 30

"Placeholder inserted when a value has been truncated."
const TRUNCATION_MARKER = "[…truncated…]"

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

"""
A lightweight summary of a named dataset found inside a notebook cell.

Fields:
- `name`         – variable name as it appears in the code.
- `type_summary` – human-readable type description (e.g. `"Matrix{Float64}"`).
- `size_info`    – shape / length description (e.g. `"100×3"`).
- `sample_values`– a short string preview of the first few values.
"""
struct DatasetProfile
    name::String
    type_summary::String
    size_info::String
    sample_values::String
end

"""
Context extracted from a single notebook cell.

Fields:
- `cell_id`        – the cell's UUID.
- `code`           – source code of the cell.
- `output_summary` – truncated plain-text representation of the cell output.
- `errored`        – whether the cell produced an error on the last run.
"""
struct CellContext
    cell_id::UUID
    code::String
    output_summary::String
    errored::Bool
end

"""
The assembled context that will be rendered into an AI prompt.

Fields:
- `user_request`     – the natural-language question / instruction from the user.
- `cells`            – ordered list of `CellContext` values.
- `dataset_profiles` – dataset summaries extracted from cell outputs/code.
- `notebook_metadata`– arbitrary key-value pairs from `notebook.metadata`.
"""
struct NotebookContext
    user_request::String
    cells::Vector{CellContext}
    dataset_profiles::Vector{DatasetProfile}
    notebook_metadata::Dict{String,Any}
end

# ---------------------------------------------------------------------------
# Output summarisation helpers
# ---------------------------------------------------------------------------

"""
    summarise_output(output::CellOutput; max_chars::Int) -> String

Convert a `CellOutput` to a short plain-text string, truncating to
`max_chars` characters when necessary.
"""
function summarise_output(output, max_chars::Int)
    body = output.body
    if isnothing(body)
        return ""
    end

    raw = if body isa String
        body
    elseif body isa Vector{UInt8}
        # Binary data – just report the size.
        "<$(length(body)) bytes of binary data>"
    elseif body isa AbstractDict
        # Structured output – stringify the relevant fields.
        get(body, "text", repr(body))
    else
        repr(body)
    end

    truncate_string(raw, max_chars)
end

"""
    truncate_string(s::AbstractString, max_chars::Int) -> String

Return `s` if it fits within `max_chars`, otherwise a truncated version with
`TRUNCATION_MARKER` appended.
"""
function truncate_string(s::AbstractString, max_chars::Int)
    if length(s) <= max_chars
        return String(s)
    end
    String(s[1:max_chars]) * TRUNCATION_MARKER
end

# ---------------------------------------------------------------------------
# Dataset profiling
# ---------------------------------------------------------------------------

"""
    profile_dataset(name::AbstractString, value) -> DatasetProfile

Build a `DatasetProfile` for `value` bound to `name`.  Works for any Julia
value; specialised information is extracted for arrays and tables.
"""
function profile_dataset(name::AbstractString, value)
    type_summary = string(typeof(value))
    size_info = _size_info(value)
    sample_values = truncate_string(_sample_values(value), 200)
    DatasetProfile(string(name), type_summary, size_info, sample_values)
end

function _size_info(v::AbstractArray)
    join(size(v), "×")
end
function _size_info(v::AbstractVector)
    string(length(v))
end
function _size_info(v)
    # Attempt length() for generic collections; fall back gracefully.
    try
        return string(length(v))
    catch
        return "unknown"
    end
end

function _sample_values(v::AbstractArray)
    flat = collect(Iterators.take(v, 5))
    repr(flat)
end
function _sample_values(v::AbstractVector)
    repr(collect(Iterators.take(v, 5)))
end
function _sample_values(v)
    repr(v)
end

# ---------------------------------------------------------------------------
# Context assembly
# ---------------------------------------------------------------------------

"""
    assemble_context(
        notebook::Notebook,
        user_request::AbstractString;
        max_cells::Int            = DEFAULT_MAX_CELLS,
        max_cell_output_chars::Int = DEFAULT_MAX_CELL_OUTPUT_CHARS,
        dataset_profiles::Vector{DatasetProfile} = DatasetProfile[],
    ) -> NotebookContext

Collect the notebook state into a `NotebookContext` ready for prompt rendering.

Cells are taken in notebook order (i.e., top-to-bottom as the user sees them)
and capped at `max_cells`.  Each cell output is truncated to
`max_cell_output_chars` characters.  Disabled cells are excluded.
"""
function assemble_context(
    notebook::Notebook,
    user_request::AbstractString;
    max_cells::Int             = DEFAULT_MAX_CELLS,
    max_cell_output_chars::Int = DEFAULT_MAX_CELL_OUTPUT_CHARS,
    dataset_profiles::Vector{DatasetProfile} = DatasetProfile[],
)
    active_cells = filter(!_is_disabled, notebook.cells)
    selected = first(active_cells, max_cells)

    cell_contexts = map(selected) do cell
        output_summary = summarise_output(cell.output, max_cell_output_chars)
        CellContext(cell.cell_id, cell.code, output_summary, cell.errored)
    end

    NotebookContext(
        String(user_request),
        cell_contexts,
        dataset_profiles,
        copy(notebook.metadata),
    )
end

_is_disabled(cell::Cell) = get(cell.metadata, "disabled", false)

# ---------------------------------------------------------------------------
# Prompt rendering
# ---------------------------------------------------------------------------

"""
    render_prompt(ctx::NotebookContext; max_chars::Int = DEFAULT_MAX_PROMPT_CHARS) -> String

Convert a `NotebookContext` into a plain-text prompt string suitable for
passing to an LLM.  The result is guaranteed to be at most `max_chars`
characters long; if the full serialisation would exceed that limit a
summarisation fallback (truncation) is applied.

The rendering is deterministic: given the same `NotebookContext` and
keyword arguments it always returns the same string.
"""
function render_prompt(ctx::NotebookContext; max_chars::Int = DEFAULT_MAX_PROMPT_CHARS)
    buf = IOBuffer()
    _write_prompt(buf, ctx)
    full = String(take!(buf))
    truncate_string(full, max_chars)
end

function _write_prompt(io::IO, ctx::NotebookContext)
    println(io, "## User Request")
    println(io, ctx.user_request)
    println(io)

    if !isempty(ctx.notebook_metadata)
        println(io, "## Notebook Metadata")
        for (k, v) in sort(collect(ctx.notebook_metadata); by=first)
            println(io, "- $(k): $(v)")
        end
        println(io)
    end

    if !isempty(ctx.dataset_profiles)
        println(io, "## Dataset Profiles")
        for dp in ctx.dataset_profiles
            println(io, "### $(dp.name)")
            println(io, "- Type: $(dp.type_summary)")
            println(io, "- Size: $(dp.size_info)")
            println(io, "- Sample: $(dp.sample_values)")
        end
        println(io)
    end

    if !isempty(ctx.cells)
        println(io, "## Notebook Cells")
        for (i, cc) in enumerate(ctx.cells)
            println(io, "### Cell $i ($(cc.cell_id))")
            println(io, "```julia")
            print(io, cc.code)
            println(io)
            println(io, "```")
            if cc.errored
                println(io, "**Status:** error")
            end
            if !isempty(cc.output_summary)
                println(io, "**Output:**")
                println(io, cc.output_summary)
            end
            println(io)
        end
    end
end

end # module NotebookContextAssembler
