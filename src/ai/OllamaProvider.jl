"""
Ollama provider adapter.

Implements [`AbstractAIProvider`](@ref) for a locally-running
[Ollama](https://ollama.com) server via its REST API.

HTTP requests are made using the `HTTP.jl` package that is already a
dependency of Pluto.
"""

import HTTP

# ── Struct ────────────────────────────────────────────────────────────────────

"""
    OllamaProvider(; base_url, model, max_retries, timeout)

Provider adapter for a local Ollama server.

# Fields
- `base_url::String`   – Ollama server URL, default `"http://localhost:11434"`
- `model::String`      – model tag, e.g. `"llama3.2"` or `"codellama"`
- `max_retries::Int`   – how many times to retry transient errors (default 3)
- `timeout::Float64`   – per-request timeout in seconds (default 120)
"""
struct OllamaProvider <: AbstractAIProvider
    base_url::String
    model::String
    max_retries::Int
    timeout::Float64
end

function OllamaProvider(;
    base_url::AbstractString="http://localhost:11434",
    model::AbstractString="llama3.2",
    max_retries::Int=3,
    timeout::Real=120.0,
)
    OllamaProvider(String(base_url), String(model), max_retries, Float64(timeout))
end

# ── complete ──────────────────────────────────────────────────────────────────

function complete(provider::OllamaProvider, prompt::AbstractString;
                  system_prompt::AbstractString="",
                  max_tokens::Int=1024,
                  temperature::Real=0.7,
                  kwargs...)

    isempty(strip(prompt)) && throw(AIProviderError(AI_EMPTY_PROMPT,
        "Prompt must not be empty"; provider=:ollama))

    body = _ollama_build_body(provider.model, prompt, system_prompt,
                              max_tokens, Float64(temperature))

    with_retries(; max_retries=provider.max_retries) do
        _ollama_request(provider, body)
    end
end

# ── HTTP helpers ──────────────────────────────────────────────────────────────

function _ollama_build_body(model, prompt, system_prompt, max_tokens, temperature)
    options = Dict{String,Any}(
        "temperature" => temperature,
        "num_predict" => max_tokens,
    )
    d = Dict{String,Any}(
        "model"  => model,
        "prompt" => prompt,
        "stream" => false,
        "options" => options,
    )
    if !isempty(strip(system_prompt))
        d["system"] = system_prompt
    end
    _json_encode(d)
end

function _ollama_request(provider::OllamaProvider, body::String)
    url = rstrip(provider.base_url, '/') * "/api/generate"

    headers = ["Content-Type" => "application/json"]

    local resp
    try
        resp = HTTP.post(url, headers, body;
                         readtimeout=provider.timeout,
                         connect_timeout=10)
    catch e
        if e isa HTTP.TimeoutError
            throw(AIProviderError(AI_TIMEOUT,
                "Ollama request timed out after $(provider.timeout)s";
                provider=:ollama))
        end
        throw(AIProviderError(AI_UNAVAILABLE,
            "Could not reach Ollama at $(provider.base_url): $(sprint(showerror, e))";
            provider=:ollama))
    end

    status = resp.status
    resp_body = String(resp.body)

    if status >= 400
        throw(AIProviderError(AI_API_ERROR,
            "Ollama returned error: $(resp_body)";
            provider=:ollama, http_status=status))
    end

    _ollama_extract_text(resp_body)
end

function _ollama_extract_text(resp_body::String)
    # Ollama generate response: {"response":"<text>","done":true,...}
    m = match(r"\"response\"\s*:\s*\"((?:[^\"\\]|\\.)*)\"", resp_body)
    if m === nothing
        throw(AIProviderError(AI_PARSE_ERROR,
            "Could not parse Ollama response: $(resp_body)";
            provider=:ollama))
    end
    _unescape_json_string(m.captures[1])
end
