# Pluto Notebook Editor Tools

Two tools that let Claude Code read and write cells in Pluto.jl (`.jl`) notebooks:

| File | What it is |
|---|---|
| `pluto_notebook_editor.jl` | Julia CLI / library — all notebook I/O logic |
| `pluto_mcp_server.py` | Python MCP server — wraps the Julia CLI so Claude Code can call it as a tool |

---

## A — Julia CLI

No extra packages required (uses only stdlib `UUIDs`).

```bash
# List all cells (JSON output)
julia tools/pluto_notebook_editor.jl my_notebook.jl list

# Read one cell's full code
julia tools/pluto_notebook_editor.jl my_notebook.jl read <cell-uuid>

# Add a cell at the end
echo 'x = 42' | julia tools/pluto_notebook_editor.jl my_notebook.jl add

# Add a cell at 0-based position 2
echo 'x = 42' | julia tools/pluto_notebook_editor.jl my_notebook.jl add 2

# Edit an existing cell
echo 'x = 100' | julia tools/pluto_notebook_editor.jl my_notebook.jl edit <cell-uuid>

# Delete a cell
julia tools/pluto_notebook_editor.jl my_notebook.jl delete <cell-uuid>
```

All commands print JSON to stdout and exit 0 on success, or print an error to
stderr and exit 1 on failure.

---

## C — MCP Server

The Python server (`pluto_mcp_server.py`) speaks the
[Model Context Protocol](https://spec.modelcontextprotocol.io/) over stdio so
Claude Code can call it as a set of named tools.

**Requires:** Python 3.10+ and `julia` on `PATH`.

### Register with Claude Code

Add the following to `~/.claude/settings.json` (global) or
`.claude/settings.json` (project-level):

```json
{
  "mcpServers": {
    "pluto-notebook": {
      "command": "python3",
      "args": ["/workspaces/Pluto.jl/tools/pluto_mcp_server.py"]
    }
  }
}
```

Optional environment variables:

| Variable | Default | Description |
|---|---|---|
| `JULIA_BIN` | `julia` | Path to the Julia binary |
| `JULIA_EDITOR_SCRIPT` | same dir as the `.py` file | Path to `pluto_notebook_editor.jl` |

### Available tools

| Tool | Description |
|---|---|
| `list_cells(notebook_path)` | List all cells with IDs, indices, code previews |
| `read_cell(notebook_path, cell_id)` | Read a cell's full source code |
| `add_cell(notebook_path, code[, position])` | Insert a new cell (append or at 0-based index) |
| `edit_cell(notebook_path, cell_id, new_code)` | Replace a cell's source code |
| `delete_cell(notebook_path, cell_id)` | Remove a cell |

### Example session

After registering the MCP server, Claude Code can do things like:

```
list_cells("/my/project/analysis.jl")
→ { "count": 5, "cells": [ { "id": "b2d79330-...", "index": 0, "code_preview": "n = 1:100000" }, … ] }

add_cell("/my/project/analysis.jl", "using Statistics\nmean(seq)")
→ { "id": "a1b2c3d4-...", "index": 5 }

edit_cell("/my/project/analysis.jl", "b2d79330-...", "n = 1:1_000_000")
→ { "success": true, "id": "b2d79330-..." }
```

---

## How it works

Pluto notebooks are plain `.jl` files with a specific text format:

```
### A Pluto.jl notebook ###
# v0.x.y
…preamble (using Markdown, using InteractiveUtils, …)…

# ╔═╡ <uuid>
<cell code>

# ╔═╡ Cell order:
# ╠═<uuid>          ← unfolded cell
# ╟─<uuid>          ← folded cell
```

The Julia CLI parses this format, performs the requested edit, and writes the
file back — preserving the preamble verbatim so Pluto's version string and
package metadata are never touched.
