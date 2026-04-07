#!/usr/bin/env julia
# tools/pluto_notebook_editor.jl
#
# Programmatically read and edit Pluto.jl notebook files (.jl format).
# Can be used as a standalone CLI or included as a library.
#
# CLI Usage:
#   julia pluto_notebook_editor.jl <notebook.jl> list
#   julia pluto_notebook_editor.jl <notebook.jl> read   <cell_id>
#   julia pluto_notebook_editor.jl <notebook.jl> delete <cell_id>
#   echo '<code>' | julia pluto_notebook_editor.jl <notebook.jl> add    [<position>]
#   echo '<code>' | julia pluto_notebook_editor.jl <notebook.jl> edit   <cell_id>
#
# All output is JSON on stdout.  Errors are written to stderr and exit 1.

using UUIDs: UUID, uuid1

# ── Constants (must match Pluto's save format exactly) ────────────────────────
const CELL_DELIMITER         = "# ╔═╡ "
const CELL_METADATA_PREFIX   = "# ╠═╡ "
const ORDER_DELIMITER        = "# ╠═"
const ORDER_DELIMITER_FOLDED = "# ╟─"
const DISABLED_PREFIX        = "#=╠═╡\n"
const DISABLED_SUFFIX        = "\n  ╠═╡ =#"
const CELL_SUFFIX            = "\n\n"

# ── Data model ────────────────────────────────────────────────────────────────
struct PlutoCell
    id::UUID
    code::String
    folded::Bool
    disabled::Bool
end

struct PlutoNotebook
    # Everything before the first "# ╔═╡ " line (header, version, preamble).
    # Written back verbatim so we never corrupt Pluto's metadata.
    preamble::String
    cells::Vector{PlutoCell}   # display order
end

# ── Minimal JSON emitter (no external deps) ───────────────────────────────────
_jesc(s::AbstractString) = replace(replace(replace(replace(replace(
    s,
    "\\" => "\\\\"),
    "\"" => "\\\""),
    "\n" => "\\n"),
    "\r" => "\\r"),
    "\t" => "\\t")

_json(x::Bool)            = x ? "true" : "false"
_json(::Nothing)          = "null"
_json(x::Integer)         = string(x)
_json(x::AbstractString)  = "\"$(_jesc(x))\""
_json(x::UUID)            = _json(string(x))
_json(v::AbstractVector)  = "[" * join(_json.(v), ",") * "]"
_json(d::AbstractDict)    = "{" * join(["$(_json(string(k))):$(_json(v))" for (k,v) in d], ",") * "}"

# ── Parser ────────────────────────────────────────────────────────────────────
"""
    parse_notebook(path) -> PlutoNotebook

Read a `.jl` Pluto notebook from `path` and return a `PlutoNotebook` with
cells in display order.
"""
function parse_notebook(path::String)::PlutoNotebook
    content = read(path, String)

    m = findfirst(CELL_DELIMITER, content)
    isnothing(m) && return PlutoNotebook(content, PlutoCell[])

    preamble = content[1 : m.start - 1]
    rest     = content[m.start : end]

    # Split on the cell delimiter → ["", chunk1, chunk2, …, "Cell order:\n…"]
    chunks = split(rest, CELL_DELIMITER)

    order_idx   = findfirst(c -> startswith(strip(c), "Cell order:"), chunks)
    order_chunk = isnothing(order_idx) ? "" : chunks[order_idx]
    cell_chunks = chunks[2 : (isnothing(order_idx) ? length(chunks) : order_idx - 1)]

    # --- parse each cell body ---
    cells_dict = Dict{UUID, PlutoCell}()
    for chunk in cell_chunks
        nl = findfirst('\n', chunk)
        isnothing(nl) && continue
        id = tryparse(UUID, strip(chunk[1 : nl - 1]))
        isnothing(id) && continue

        body_lines = split(chunk[nl + 1 : end], '\n')

        # skip cell-level TOML metadata lines ("# ╠═╡ …")
        i = 1
        while i <= length(body_lines) && startswith(body_lines[i], CELL_METADATA_PREFIX)
            i += 1
        end
        code_raw = join(body_lines[i:end], '\n')

        # unwrap disabled-on-startup wrapper
        disabled = startswith(code_raw, DISABLED_PREFIX)
        if disabled
            code_raw = replace(replace(code_raw, DISABLED_PREFIX => ""), DISABLED_SUFFIX => "")
        end

        # strip trailing \n\n suffix Pluto appends
        code = rstrip(code_raw, '\n')

        cells_dict[id] = PlutoCell(id, code, false, disabled)
    end

    # --- parse cell order ---
    cell_order = UUID[]
    folded_ids = Set{UUID}()
    for line in split(order_chunk, '\n')
        line = strip(line)
        if startswith(line, ORDER_DELIMITER_FOLDED)
            id = tryparse(UUID, strip(line[ncodeunits(ORDER_DELIMITER_FOLDED) + 1 : end]))
            isnothing(id) && continue
            push!(cell_order, id); push!(folded_ids, id)
        elseif startswith(line, ORDER_DELIMITER)
            id = tryparse(UUID, strip(line[ncodeunits(ORDER_DELIMITER) + 1 : end]))
            isnothing(id) && continue
            push!(cell_order, id)
        end
    end

    # build display-ordered list; orphan cells (no order entry) go at the end
    seen = Set{UUID}()
    ordered = PlutoCell[]
    for id in cell_order
        haskey(cells_dict, id) || continue
        c = cells_dict[id]
        push!(ordered, PlutoCell(c.id, c.code, id ∈ folded_ids, c.disabled))
        push!(seen, id)
    end
    for (id, c) in cells_dict
        id ∈ seen && continue
        push!(ordered, c)
    end

    PlutoNotebook(preamble, ordered)
end

# ── Serialiser ────────────────────────────────────────────────────────────────
"""
    save_notebook(path, nb)

Write `nb` back to `path` in Pluto's plain-text format.
Cells are saved in display order (Pluto's reactive engine handles
execution order, so topological sorting is not required here).
"""
function save_notebook(path::String, nb::PlutoNotebook)
    io = IOBuffer()

    # verbatim preamble (header + version + using … + optional fake_bind)
    print(io, nb.preamble)

    for cell in nb.cells
        println(io, CELL_DELIMITER, string(cell.id))
        if cell.disabled
            print(io, DISABLED_PREFIX, cell.code, DISABLED_SUFFIX, CELL_SUFFIX)
        else
            print(io, cell.code, CELL_SUFFIX)
        end
    end

    println(io, CELL_DELIMITER, "Cell order:")
    for cell in nb.cells
        delim = cell.folded ? ORDER_DELIMITER_FOLDED : ORDER_DELIMITER
        println(io, delim, string(cell.id))
    end

    write(path, String(take!(io)))
end

# ── Operations (return nothing; print JSON to stdout) ─────────────────────────
function op_list(nb::PlutoNotebook)
    cells = [Dict{String,Any}(
        "id"           => string(c.id),
        "index"        => i - 1,
        "code_preview" => first(c.code, 120),
        "folded"       => c.folded,
        "disabled"     => c.disabled,
    ) for (i, c) in enumerate(nb.cells)]
    println(_json(Dict("cells" => cells, "count" => length(cells))))
end

function op_read(nb::PlutoNotebook, cell_id_str::String)
    id  = tryparse(UUID, cell_id_str); isnothing(id) && error("Invalid UUID: $cell_id_str")
    idx = findfirst(c -> c.id == id, nb.cells); isnothing(idx) && error("Cell not found: $cell_id_str")
    c   = nb.cells[idx]
    println(_json(Dict("id" => string(c.id), "index" => idx - 1,
                        "code" => c.code, "folded" => c.folded, "disabled" => c.disabled)))
end

function op_add(path::String, nb::PlutoNotebook, position, code::String)
    new_cell = PlutoCell(uuid1(), code, false, false)
    pos = if position == "end" || position == ""
        length(nb.cells) + 1
    else
        clamp(parse(Int, position) + 1, 1, length(nb.cells) + 1)
    end
    insert!(nb.cells, pos, new_cell)
    save_notebook(path, nb)
    println(_json(Dict("id" => string(new_cell.id), "index" => pos - 1)))
end

function op_edit(path::String, nb::PlutoNotebook, cell_id_str::String, new_code::String)
    id  = tryparse(UUID, cell_id_str); isnothing(id) && error("Invalid UUID: $cell_id_str")
    idx = findfirst(c -> c.id == id, nb.cells); isnothing(idx) && error("Cell not found: $cell_id_str")
    c   = nb.cells[idx]
    nb.cells[idx] = PlutoCell(c.id, new_code, c.folded, c.disabled)
    save_notebook(path, nb)
    println(_json(Dict("success" => true, "id" => cell_id_str)))
end

function op_delete(path::String, nb::PlutoNotebook, cell_id_str::String)
    id  = tryparse(UUID, cell_id_str); isnothing(id) && error("Invalid UUID: $cell_id_str")
    idx = findfirst(c -> c.id == id, nb.cells); isnothing(idx) && error("Cell not found: $cell_id_str")
    deleteat!(nb.cells, idx)
    save_notebook(path, nb)
    println(_json(Dict("success" => true, "id" => cell_id_str)))
end

# ── CLI entry point ───────────────────────────────────────────────────────────
if abspath(PROGRAM_FILE) == @__FILE__
    function cli_error(msg)
        println(stderr, "ERROR: ", msg)
        exit(1)
    end

    length(ARGS) < 2 && cli_error("""
Usage:
  julia pluto_notebook_editor.jl <notebook.jl> list
  julia pluto_notebook_editor.jl <notebook.jl> read   <cell_id>
  julia pluto_notebook_editor.jl <notebook.jl> delete <cell_id>
  echo '<code>' | julia pluto_notebook_editor.jl <notebook.jl> add    [<position>]
  echo '<code>' | julia pluto_notebook_editor.jl <notebook.jl> edit   <cell_id>
""")

    notebook_path = ARGS[1]
    cmd           = ARGS[2]

    isfile(notebook_path) || cli_error("File not found: $notebook_path")

    nb = try
        parse_notebook(notebook_path)
    catch e
        cli_error("Failed to parse notebook: $e")
    end

    try
        if cmd == "list"
            op_list(nb)
        elseif cmd == "read"
            length(ARGS) >= 3 || cli_error("read requires <cell_id>")
            op_read(nb, ARGS[3])
        elseif cmd == "add"
            position = length(ARGS) >= 3 ? ARGS[3] : "end"
            op_add(notebook_path, nb, position, read(stdin, String))
        elseif cmd == "edit"
            length(ARGS) >= 3 || cli_error("edit requires <cell_id>")
            op_edit(notebook_path, nb, ARGS[3], read(stdin, String))
        elseif cmd == "delete"
            length(ARGS) >= 3 || cli_error("delete requires <cell_id>")
            op_delete(notebook_path, nb, ARGS[3])
        else
            cli_error("Unknown command '$cmd'. Valid commands: list, read, add, edit, delete")
        end
    catch e
        cli_error(sprint(showerror, e))
    end
end
