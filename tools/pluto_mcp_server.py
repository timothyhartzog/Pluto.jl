#!/usr/bin/env python3
"""
Pluto.jl Notebook MCP Server
=============================
Exposes Pluto notebook editing as MCP (Model Context Protocol) tools so that
Claude Code can read and write cells in .jl Pluto notebooks.

The server speaks JSON-RPC 2.0 over stdio with Content-Length framing
(identical to the Language Server Protocol transport).

It delegates all notebook I/O to pluto_notebook_editor.jl via subprocess.

Setup — add to ~/.claude/settings.json:
{
  "mcpServers": {
    "pluto-notebook": {
      "command": "python3",
      "args": ["/workspaces/Pluto.jl/tools/pluto_mcp_server.py"]
    }
  }
}

Environment variables (optional):
  JULIA_BIN              Path to the julia binary (default: "julia")
  JULIA_EDITOR_SCRIPT    Path to pluto_notebook_editor.jl
                         (default: same directory as this file)
"""

import json
import os
import subprocess
import sys
from typing import Any

# ── Configuration ─────────────────────────────────────────────────────────────
JULIA_BIN = os.environ.get("JULIA_BIN", "julia")
EDITOR_SCRIPT = os.environ.get(
    "JULIA_EDITOR_SCRIPT",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "pluto_notebook_editor.jl"),
)

# ── Julia subprocess helper ───────────────────────────────────────────────────
def _julia(notebook_path: str, cmd: str, *args: str, stdin_text: str | None = None) -> Any:
    """
    Run pluto_notebook_editor.jl and return the parsed JSON result.
    Raises RuntimeError on non-zero exit or JSON parse failure.
    """
    result = subprocess.run(
        [JULIA_BIN, EDITOR_SCRIPT, notebook_path, cmd, *args],
        capture_output=True,
        text=True,
        input=stdin_text,
        timeout=60,
    )
    if result.returncode != 0:
        msg = result.stderr.strip() or f"julia exited with code {result.returncode}"
        raise RuntimeError(msg)
    return json.loads(result.stdout.strip())

# ── MCP transport (Content-Length framed JSON-RPC 2.0 over stdio) ─────────────
_stdin  = open(sys.stdin.fileno(),  "rb", closefd=False)
_stdout = open(sys.stdout.fileno(), "wb", closefd=False)


def _read_message() -> dict | None:
    """Read one JSON-RPC message from stdin; return None on EOF."""
    headers: dict[str, str] = {}
    while True:
        raw = _stdin.readline()
        if not raw:
            return None
        line = raw.decode("utf-8").rstrip("\r\n")
        if line == "":
            break
        if ":" in line:
            k, _, v = line.partition(":")
            headers[k.strip().lower()] = v.strip()

    length = int(headers.get("content-length", 0))
    if length == 0:
        return None
    body = _stdin.read(length)
    return json.loads(body.decode("utf-8"))


def _write_message(obj: dict) -> None:
    body = json.dumps(obj).encode("utf-8")
    header = f"Content-Length: {len(body)}\r\n\r\n".encode("utf-8")
    _stdout.write(header + body)
    _stdout.flush()


def _ok(msg_id: Any, result: Any) -> None:
    _write_message({"jsonrpc": "2.0", "id": msg_id, "result": result})


def _err(msg_id: Any, code: int, message: str) -> None:
    _write_message({"jsonrpc": "2.0", "id": msg_id,
                    "error": {"code": code, "message": message}})

# ── Tool definitions ──────────────────────────────────────────────────────────
TOOLS = [
    {
        "name": "list_cells",
        "description": (
            "List all cells in a Pluto.jl notebook. "
            "Returns cell IDs, 0-based indices, a code preview, and fold/disabled flags."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "notebook_path": {
                    "type": "string",
                    "description": "Absolute path to the .jl Pluto notebook file.",
                }
            },
            "required": ["notebook_path"],
        },
    },
    {
        "name": "read_cell",
        "description": "Read the full source code of a specific cell in a Pluto.jl notebook.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "notebook_path": {
                    "type": "string",
                    "description": "Absolute path to the .jl Pluto notebook file.",
                },
                "cell_id": {
                    "type": "string",
                    "description": "UUID of the cell to read.",
                },
            },
            "required": ["notebook_path", "cell_id"],
        },
    },
    {
        "name": "add_cell",
        "description": (
            "Insert a new code cell into a Pluto.jl notebook. "
            "Returns the new cell's UUID and 0-based index."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "notebook_path": {
                    "type": "string",
                    "description": "Absolute path to the .jl Pluto notebook file.",
                },
                "code": {
                    "type": "string",
                    "description": "Julia source code for the new cell.",
                },
                "position": {
                    "type": "integer",
                    "description": (
                        "0-based index at which to insert the cell. "
                        "Omit to append at the end."
                    ),
                },
            },
            "required": ["notebook_path", "code"],
        },
    },
    {
        "name": "edit_cell",
        "description": "Replace the source code of an existing cell in a Pluto.jl notebook.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "notebook_path": {
                    "type": "string",
                    "description": "Absolute path to the .jl Pluto notebook file.",
                },
                "cell_id": {
                    "type": "string",
                    "description": "UUID of the cell to replace.",
                },
                "new_code": {
                    "type": "string",
                    "description": "New Julia source code for the cell.",
                },
            },
            "required": ["notebook_path", "cell_id", "new_code"],
        },
    },
    {
        "name": "delete_cell",
        "description": "Remove a cell from a Pluto.jl notebook.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "notebook_path": {
                    "type": "string",
                    "description": "Absolute path to the .jl Pluto notebook file.",
                },
                "cell_id": {
                    "type": "string",
                    "description": "UUID of the cell to delete.",
                },
            },
            "required": ["notebook_path", "cell_id"],
        },
    },
]

# ── Tool dispatch ─────────────────────────────────────────────────────────────
def _call_tool(name: str, args: dict) -> Any:
    nb = args["notebook_path"]
    if name == "list_cells":
        return _julia(nb, "list")
    elif name == "read_cell":
        return _julia(nb, "read", args["cell_id"])
    elif name == "add_cell":
        pos = str(args["position"]) if "position" in args else "end"
        return _julia(nb, "add", pos, stdin_text=args["code"])
    elif name == "edit_cell":
        return _julia(nb, "edit", args["cell_id"], stdin_text=args["new_code"])
    elif name == "delete_cell":
        return _julia(nb, "delete", args["cell_id"])
    else:
        raise ValueError(f"Unknown tool: {name}")

# ── Main loop ─────────────────────────────────────────────────────────────────
def main() -> None:
    while True:
        try:
            msg = _read_message()
        except Exception as e:
            _write_message({"jsonrpc": "2.0", "id": None,
                            "error": {"code": -32700, "message": f"Parse error: {e}"}})
            continue

        if msg is None:
            break

        msg_id = msg.get("id")          # None for notifications
        method = msg.get("method", "")
        params = msg.get("params") or {}

        # Notifications have no id — send no response
        is_notification = "id" not in msg

        try:
            if method == "initialize":
                _ok(msg_id, {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "pluto-notebook-editor", "version": "1.0.0"},
                })
            elif method == "tools/list":
                _ok(msg_id, {"tools": TOOLS})
            elif method == "tools/call":
                result = _call_tool(params["name"], params.get("arguments") or {})
                _ok(msg_id, {
                    "content": [{"type": "text", "text": json.dumps(result, indent=2)}]
                })
            elif is_notification:
                pass  # e.g. notifications/initialized — no response required
            else:
                _err(msg_id, -32601, f"Method not found: {method}")
        except Exception as e:
            if not is_notification:
                _err(msg_id, -32603, str(e))


if __name__ == "__main__":
    main()
