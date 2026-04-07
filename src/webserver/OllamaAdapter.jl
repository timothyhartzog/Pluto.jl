
# ── Ollama local model adapter ────────────────────────────────────────────────
#
# Provides `ollama_generate`, a module-level function that calls the Ollama
# REST API (`/api/generate`) with configurable host, model, timeout, and retry
# logic, and maps Ollama-specific failures into user-friendly error strings.
#
# Usage (from Router.jl):
#   text, err = ollama_generate(host, model, prompt, system_prompt;
#                               timeout_seconds=120, max_retries=2)
#   err === nothing  →  `text` contains the model response
#   err !== nothing  →  `text` is nothing, `err` is a human-readable message

# ---------------------------------------------------------------------------
# Internal JSON string encoder (no extra dep — mirrors the one in Router.jl)
# ---------------------------------------------------------------------------
_ollama_json_str(s::AbstractString) =
    "\"" * replace(s, "\\" => "\\\\", "\"" => "\\\"",
                      "\n" => "\\n",  "\r" => "\\r",
                      "\t" => "\\t") * "\""

# ---------------------------------------------------------------------------
# Shared Ollama error types
# ---------------------------------------------------------------------------

"""
    OllamaModelNotFoundError(model, host)

Thrown (as an error string) when the requested model is not available on the
Ollama server.
"""
struct OllamaModelNotFoundError
    model::String
    host::String
end

"""
    OllamaServerUnavailableError(host)

Thrown (as an error string) when the Ollama server cannot be reached.
"""
struct OllamaServerUnavailableError
    host::String
end

# ---------------------------------------------------------------------------
# Core adapter function
# ---------------------------------------------------------------------------

"""
    ollama_generate(host, model, prompt[, system_prompt];
                    timeout_seconds=120, max_retries=2) -> (text, error)

Call the Ollama `/api/generate` endpoint at `host` and return a 2-tuple:

- `(text::String, nothing)` on success
- `(nothing, error_message::String)` on failure

`max_retries` controls how many *additional* attempts are made on transient
5xx / IO errors (exponential back-off, capped at 8 s).  4xx errors (e.g.
model not found) are **not** retried.
"""
function ollama_generate(
    host::AbstractString,
    model::AbstractString,
    prompt::AbstractString,
    system_prompt::AbstractString = "";
    timeout_seconds::Int = 120,
    max_retries::Int = 2,
)
    url = string(rstrip(host, '/'), "/api/generate")

    # Build request payload (manual JSON — no extra dependency)
    payload =
        "{\"model\":$(_ollama_json_str(model))," *
        "\"prompt\":$(_ollama_json_str(prompt))," *
        "\"stream\":false" *
        (isempty(strip(system_prompt)) ? "" :
             ",\"system\":$(_ollama_json_str(system_prompt))") *
        "}"

    last_error = nothing
    for attempt in 1:(max_retries + 1)
        try
            resp = HTTP.post(
                url,
                ["Content-Type" => "application/json"],
                payload;
                connect_timeout = 10,
                readtimeout     = timeout_seconds,
                status_exception = true,
            )
            rbody = String(resp.body)
            # Extract the "response" string value from the JSON object
            m = match(r"\"response\"\s*:\s*\"((?:[^\"\\]|\\.)*)\"", rbody)
            m === nothing && return (nothing, "Unexpected response format from Ollama")
            text = replace(
                m.captures[1],
                "\\n" => "\n", "\\t" => "\t",
                "\\\"" => "\"", "\\\\" => "\\",
            )
            return (text, nothing)

        catch e
            last_error = e

            # ── Immediate, non-retryable failures ───────────────────────────
            if e isa HTTP.StatusError
                if e.status == 404
                    return (
                        nothing,
                        "Model '$(model)' not found on Ollama server at $(host). " *
                        "Run: ollama pull $(model)",
                    )
                elseif e.status < 500
                    return (
                        nothing,
                        "Ollama error (HTTP $(e.status)): $(sprint(showerror, e))",
                    )
                end
                # 5xx → retryable, fall through
            end

            # ── Exponential back-off before next attempt ─────────────────────
            if attempt <= max_retries
                sleep(min(2^(attempt - 1), 8))
            end
        end
    end

    # ── Map last error to a user-friendly message ────────────────────────────
    err_msg = sprint(showerror, last_error)

    if last_error isa Base.IOError ||
       occursin("ECONNREFUSED", err_msg) ||
       occursin("connection refused", lowercase(err_msg))
        return (
            nothing,
            "Cannot connect to Ollama server at $(host). " *
            "Is Ollama running? (ollama serve)",
        )
    end

    if occursin("timeout", lowercase(err_msg)) ||
       occursin("timed out", lowercase(err_msg))
        return (
            nothing,
            "Ollama request timed out after $(timeout_seconds)s. " *
            "Try a shorter prompt or a faster model.",
        )
    end

    return (nothing, "Ollama request failed: $(err_msg)")
end
