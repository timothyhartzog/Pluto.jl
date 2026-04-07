module ExportPipeline

export ProvenanceMetadata, ExportResult
export export_html, export_markdown, export_csv, export_bundle, export_notebook

import ..Pluto
import ..Pluto: Notebook, Cell, PLUTO_VERSION, generate_html, frontmatter

import Dates
import Markdown
import Tables
import UUIDs: UUID

# ───────────────────────────────────────────────────────────────────────────────
# Provenance
# ───────────────────────────────────────────────────────────────────────────────

"""
    ProvenanceMetadata

Metadata that records the origin of an exported artifact, including the source
notebook path, Pluto/Julia versions, and the timestamp of the export.
"""
struct ProvenanceMetadata
    notebook_path::String
    pluto_version::VersionNumber
    julia_version::VersionNumber
    exported_at::Dates.DateTime
    export_format::Symbol
end

function ProvenanceMetadata(notebook::Notebook, format::Symbol)
    ProvenanceMetadata(
        notebook.path,
        PLUTO_VERSION,
        VERSION,
        Dates.now(Dates.UTC),
        format,
    )
end

"""Return a `Dict` representation suitable for serialisation (TOML / JSON)."""
function provenance_dict(p::ProvenanceMetadata)
    Dict{String,String}(
        "notebook_path"  => p.notebook_path,
        "pluto_version"  => string(p.pluto_version),
        "julia_version"  => string(p.julia_version),
        "exported_at"    => string(p.exported_at) * " UTC",
        "export_format"  => string(p.export_format),
    )
end

# ───────────────────────────────────────────────────────────────────────────────
# ExportResult
# ───────────────────────────────────────────────────────────────────────────────

"""
    ExportResult{T}

Wraps exported content together with its [`ProvenanceMetadata`](@ref).

`content` type depends on the format:
- `:html`     → `String`
- `:markdown` → `String`
- `:csv`      → `String`
- `:bundle`   → `String` (directory path of the written bundle)
"""
struct ExportResult{T}
    content::T
    provenance::ProvenanceMetadata
end

# ───────────────────────────────────────────────────────────────────────────────
# HTML export
# ───────────────────────────────────────────────────────────────────────────────

"""
    export_html(notebook::Notebook; kwargs...) -> ExportResult{String}

Generate a static HTML representation of *notebook*.  Any keyword arguments are
forwarded to `Pluto.generate_html`.  Returns an [`ExportResult`](@ref) whose
`content` field is the complete HTML string.

If `path` is provided the HTML is also written to that file.
"""
function export_html(notebook::Notebook; path::Union{Nothing,AbstractString}=nothing, kwargs...)::ExportResult{String}
    html = generate_html(notebook; kwargs...)
    prov = ProvenanceMetadata(notebook, :html)

    # Inject provenance comment just before </head> (best-effort)
    comment = _provenance_html_comment(prov)
    html = replace(html, r"</head>"i => comment * "</head>"; count=1)

    result = ExportResult{String}(html, prov)
    if path !== nothing
        write(path, html)
    end
    result
end

function _provenance_html_comment(p::ProvenanceMetadata)
    d = provenance_dict(p)
    lines = join(("  $(k): $(v)" for (k, v) in sort(collect(d))), "\n")
    "<!--\n  Pluto Export Provenance\n$(lines)\n-->\n"
end

# ───────────────────────────────────────────────────────────────────────────────
# Markdown export
# ───────────────────────────────────────────────────────────────────────────────

"""
    export_markdown(notebook::Notebook; path=nothing) -> ExportResult{String}

Convert *notebook* cells to a Markdown document.  Each cell's source code is
rendered as a fenced Julia code block.  Plain-text cell outputs (if available)
are included as block-quotes beneath the code.

A provenance header is prepended to the document.
"""
function export_markdown(notebook::Notebook; path::Union{Nothing,AbstractString}=nothing)::ExportResult{String}
    prov = ProvenanceMetadata(notebook, :markdown)
    buf  = IOBuffer()

    # Frontmatter as YAML-ish comment block
    fm = frontmatter(notebook)
    title = get(fm, "title", basename(notebook.path))
    println(buf, "# $(title)\n")
    println(buf, _provenance_md_comment(prov), "\n")

    for cell in notebook.cells
        Pluto.is_disabled(cell) && continue

        println(buf, "```julia")
        println(buf, cell.code)
        println(buf, "```\n")

        # Include plain-text output when available; output.body defaults to
        # `nothing` for cells that have not run yet, so we guard with `isa String`.
        output = cell.output
        if output.body isa String && !isempty(output.body) && output.mime == MIME("text/plain")
            for line in split(output.body, '\n')
                println(buf, "> ", line)
            end
            println(buf)
        end
    end

    md = String(take!(buf))
    result = ExportResult{String}(md, prov)
    if path !== nothing
        write(path, md)
    end
    result
end

function _provenance_md_comment(p::ProvenanceMetadata)
    d = provenance_dict(p)
    lines = join(("<!-- $(k): $(v) -->" for (k, v) in sort(collect(d))), "\n")
    lines
end

# ───────────────────────────────────────────────────────────────────────────────
# CSV export
# ───────────────────────────────────────────────────────────────────────────────

"""
    export_csv(data; path=nothing) -> ExportResult{String}

Serialise any `Tables.jl`-compatible *data* to a CSV string.

If `path` is provided the CSV is also written to that file.

!!! note
    This function does not require a `Notebook`; provenance metadata is generated
    with placeholder values in that case.  Pass a `notebook` keyword argument to
    attach full provenance.
"""
function export_csv(data;
    path::Union{Nothing,AbstractString}=nothing,
    notebook::Union{Nothing,Notebook}=nothing,
)::ExportResult{String}

    prov = if notebook !== nothing
        ProvenanceMetadata(notebook, :csv)
    else
        ProvenanceMetadata("", PLUTO_VERSION, VERSION, Dates.now(Dates.UTC), :csv)
    end

    csv = _table_to_csv(data)
    result = ExportResult{String}(csv, prov)
    if path !== nothing
        write(path, csv)
    end
    result
end

"""Export a `Tables.jl`-compatible table to a CSV string (no external deps)."""
function _table_to_csv(data)::String
    rows = Tables.rows(data)
    schema = Tables.schema(rows)

    buf = IOBuffer()

    if schema !== nothing
        cols = string.(schema.names)
        println(buf, join(_csv_escape.(cols), ","))
    end

    for row in rows
        vals = [Tables.getcolumn(row, col) for col in Tables.columnnames(row)]
        println(buf, join(_csv_escape.(string.(vals)), ","))
    end

    String(take!(buf))
end

function _csv_escape(s::AbstractString)
    if occursin(',', s) || occursin('"', s) || occursin('\n', s)
        '"' * replace(s, '"' => "\"\"") * '"'
    else
        s
    end
end

# ───────────────────────────────────────────────────────────────────────────────
# Notebook summary CSV (convenience)
# ───────────────────────────────────────────────────────────────────────────────

"""
    export_notebook_summary_csv(notebook::Notebook; path=nothing) -> ExportResult{String}

Export a CSV summary of all cells in *notebook* (cell id, first 80 chars of
code, runtime in nanoseconds, and whether the cell errored).
"""
function export_notebook_summary_csv(notebook::Notebook; path::Union{Nothing,AbstractString}=nothing)::ExportResult{String}
    rows = [
        (
            cell_id  = string(cell.cell_id),
            code     = first(cell.code, 80),
            runtime_ns = something(cell.runtime, UInt64(0)),  # 0 when cell has not run
            errored  = cell.errored,
        )
        for cell in notebook.cells
    ]
    export_csv(rows; path, notebook)
end

# ───────────────────────────────────────────────────────────────────────────────
# Bundle export
# ───────────────────────────────────────────────────────────────────────────────

"""
    export_bundle(notebook::Notebook; dir=nothing) -> ExportResult{String}

Write a *report bundle* for *notebook* to the directory *dir* (created if it
does not exist; defaults to a temporary directory).  The bundle contains:

- `report.html`        – static HTML export
- `report.md`          – Markdown export
- `cell_summary.csv`   – per-cell summary CSV
- `provenance.toml`    – TOML file with provenance metadata

Returns an [`ExportResult`](@ref) whose `content` is the absolute path to the
bundle directory.
"""
function export_bundle(notebook::Notebook; dir::Union{Nothing,AbstractString}=nothing)::ExportResult{String}
    bundle_dir = something(dir, mktempdir())
    mkpath(bundle_dir)

    prov = ProvenanceMetadata(notebook, :bundle)

    export_html(notebook; path=joinpath(bundle_dir, "report.html"))
    export_markdown(notebook; path=joinpath(bundle_dir, "report.md"))
    export_notebook_summary_csv(notebook; path=joinpath(bundle_dir, "cell_summary.csv"))

    # Write TOML provenance file
    toml_path = joinpath(bundle_dir, "provenance.toml")
    _write_provenance_toml(toml_path, prov)

    ExportResult{String}(bundle_dir, prov)
end

function _write_provenance_toml(path::AbstractString, p::ProvenanceMetadata)
    d = provenance_dict(p)
    open(path, "w") do io
        println(io, "# Pluto Export Provenance")
        for (k, v) in sort(collect(d))
            println(io, "$(k) = $(repr(v))")
        end
    end
end

# ───────────────────────────────────────────────────────────────────────────────
# Unified entry point
# ───────────────────────────────────────────────────────────────────────────────

"""
    export_notebook(notebook::Notebook, format::Symbol; path=nothing, kwargs...)

Single entry point for all export formats.  *format* must be one of:

| format      | description                                    |
|:----------- |:---------------------------------------------- |
| `:html`     | Static HTML file (default Pluto export)        |
| `:markdown` | Markdown document with fenced code blocks      |
| `:csv`      | Per-cell summary CSV                           |
| `:bundle`   | Directory bundle with all of the above         |

All keyword arguments are forwarded to the format-specific function.
"""
function export_notebook(notebook::Notebook, format::Symbol; kwargs...)
    if format === :html
        export_html(notebook; kwargs...)
    elseif format === :markdown
        export_markdown(notebook; kwargs...)
    elseif format === :csv
        export_notebook_summary_csv(notebook; kwargs...)
    elseif format === :bundle
        export_bundle(notebook; kwargs...)
    else
        throw(ArgumentError("Unknown export format: $(format). Must be :html, :markdown, :csv, or :bundle."))
    end
end

end # module ExportPipeline
