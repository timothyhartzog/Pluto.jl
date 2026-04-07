"""
Cloud AI provider adapter.

Implements [`AbstractAIProvider`](@ref) for any OpenAI-compatible REST API,
including OpenAI itself, Anthropic (via their OpenAI-compatible endpoint),
and other cloud LLM services.

HTTP requests are made using the `HTTP.jl` package that is already a
dependency of Pluto.
"""

import HTTP

# ── Struct ────────────────────────────────────────────────────────────────────

"""
    CloudProvider(; base_url, api_key, model, max_retries, timeout)

Provider adapter for OpenAI-compatible cloud APIs.

# Fields
- `base_url::String`   – base URL, e.g. `"https://api.openai.com/v1"`
- `api_key::String`    – bearer-token API key
- `model::String`      – model identifier, e.g. `"gpt-4o"`
- `max_retries::Int`   – how many times to retry transient errors (default 3)
- `timeout::Float64`   – per-request timeout in seconds (default 30)
"""
struct CloudProvider <: AbstractAIProvider
    base_url::String
    api_key::String
    model::String
    max_retries::Int
    timeout::Float64
end

function CloudProvider(;
    base_url::AbstractString="https://api.openai.com/v1",
    api_key::AbstractString="",
    model::AbstractString="gpt-4o",
    max_retries::Int=3,
    timeout::Real=30.0,
)
    CloudProvider(String(base_url), String(api_key), String(model), max_retries, Float64(timeout))
end

# ── complete ──────────────────────────────────────────────────────────────────

function complete(provider::CloudProvider, prompt::AbstractString;
                  system_prompt::AbstractString="",
                  max_tokens::Int=1024,
                  temperature::Real=0.7,
                  kwargs...)

    isempty(strip(prompt)) && throw(AIProviderError(AI_EMPTY_PROMPT,
        "Prompt must not be empty"; provider=:cloud))

    messages = Any[]
    if !isempty(strip(system_prompt))
        push!(messages, Dict("role" => "system", "content" => system_prompt))
    end
    push!(messages, Dict("role" => "user", "content" => prompt))

    body = _json_encode(Dict(
        "model"       => provider.model,
        "messages"    => messages,
        "max_tokens"  => max_tokens,
        "temperature" => Float64(temperature),
    ))

    with_retries(; max_retries=provider.max_retries) do
        _cloud_request(provider, body)
    end
end

# ── HTTP helpers ──────────────────────────────────────────────────────────────

function _cloud_request(provider::CloudProvider, body::String)
    url = rstrip(provider.base_url, '/') * "/chat/completions"

    headers = [
        "Content-Type"  => "application/json",
        "Authorization" => "Bearer $(provider.api_key)",
    ]

    local resp
    try
        resp = HTTP.post(url, headers, body;
                         readtimeout=provider.timeout,
                         connect_timeout=10)
    catch e
        if e isa HTTP.TimeoutError
            throw(AIProviderError(AI_TIMEOUT,
                "Request to cloud provider timed out after $(provider.timeout)s";
                provider=:cloud))
        end
        throw(AIProviderError(AI_UNAVAILABLE,
            "Could not reach cloud provider at $(provider.base_url): $(sprint(showerror, e))";
            provider=:cloud))
    end

    status = resp.status
    resp_body = String(resp.body)

    if status == 429
        throw(AIProviderError(AI_RATE_LIMIT,
            "Cloud provider rate limit exceeded"; provider=:cloud, http_status=status))
    elseif status >= 400
        throw(AIProviderError(AI_API_ERROR,
            "Cloud provider returned error: $(resp_body)";
            provider=:cloud, http_status=status))
    end

    _cloud_extract_text(resp_body)
end

function _cloud_extract_text(resp_body::String)
    # Parse: {"choices":[{"message":{"content":"<text>"}}]}
    m = match(r"\"content\"\s*:\s*\"((?:[^\"\\]|\\.)*)\"", resp_body)
    if m === nothing
        throw(AIProviderError(AI_PARSE_ERROR,
            "Could not parse cloud provider response: $(resp_body)";
            provider=:cloud))
    end
    _unescape_json_string(m.captures[1])
end

# ── Minimal JSON helpers (no extra dependency) ─────────────────────────────────

function _json_encode(d::Dict)
    pairs_str = join(
        (string("\"", k, "\":", _json_val(v)) for (k, v) in d),
        ","
    )
    "{" * pairs_str * "}"
end

function _json_val(v)
    if v isa AbstractString
        "\"" * _escape_json_string(v) * "\""
    elseif v isa Bool
        v ? "true" : "false"
    elseif v isa Real
        string(v)
    elseif v isa AbstractDict
        _json_encode(Dict(string(k) => val for (k, val) in v))
    elseif v isa AbstractVector
        "[" * join((_json_val(item) for item in v), ",") * "]"
    else
        "\"" * _escape_json_string(string(v)) * "\""
    end
end

function _escape_json_string(s::AbstractString)
    replace(s,
        "\\" => "\\\\",
        "\"" => "\\\"",
        "\n" => "\\n",
        "\r" => "\\r",
        "\t" => "\\t",
    )
end

function _unescape_json_string(s::AbstractString)
    replace(s,
        "\\n"  => "\n",
        "\\r"  => "\r",
        "\\t"  => "\t",
        "\\\"" => "\"",
        "\\\\" => "\\",
    )
end
