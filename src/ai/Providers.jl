"""
AI provider abstraction for Pluto notebook assistance.

Defines the abstract interface that all AI provider adapters must implement,
plus a shared error taxonomy used across all providers.
"""

# ── Error taxonomy ────────────────────────────────────────────────────────────

"""
    AIErrorCode

Normalised error codes surfaced to callers regardless of which provider is
in use.

| Code | Meaning |
|------|---------|
| `:empty_prompt` | The caller passed an empty or whitespace-only prompt. |
| `:api_error` | The provider returned a non-success status. |
| `:rate_limit` | The provider is throttling requests. |
| `:timeout` | The request did not complete within the allowed window. |
| `:unavailable` | The provider endpoint could not be reached. |
| `:parse_error` | The provider's response could not be decoded. |
| `:not_configured` | No provider has been configured. |
"""
@enum AIErrorCode begin
    AI_EMPTY_PROMPT
    AI_API_ERROR
    AI_RATE_LIMIT
    AI_TIMEOUT
    AI_UNAVAILABLE
    AI_PARSE_ERROR
    AI_NOT_CONFIGURED
end

"""
    AIProviderError(code, message; provider=:unknown, http_status=nothing)

Normalised exception thrown by every AI provider adapter.

Fields:
- `code::AIErrorCode`      – machine-readable error category
- `message::String`        – human-readable explanation
- `provider::Symbol`       – which provider raised the error (e.g. `:ollama`)
- `http_status::Union{Nothing,Int}` – HTTP status code, when available
"""
struct AIProviderError <: Exception
    code::AIErrorCode
    message::String
    provider::Symbol
    http_status::Union{Nothing,Int}
end

function AIProviderError(code::AIErrorCode, message::AbstractString;
                         provider::Symbol=:unknown,
                         http_status::Union{Nothing,Int}=nothing)
    AIProviderError(code, String(message), provider, http_status)
end

function Base.showerror(io::IO, e::AIProviderError)
    print(io, "AIProviderError($(e.code), provider=$(e.provider)): $(e.message)")
    if e.http_status !== nothing
        print(io, " [HTTP $(e.http_status)]")
    end
end

# ── Abstract interface ────────────────────────────────────────────────────────

"""
    AbstractAIProvider

Supertype for all AI provider adapters.  Every concrete subtype must implement:

```julia
complete(provider::MyProvider, prompt::AbstractString; kwargs...) -> String
```

and may optionally specialise:

```julia
complete_code(provider::MyProvider, prompt::AbstractString; kwargs...) -> String
```

which by default delegates to `complete` with a Julia-focused system prompt.
"""
abstract type AbstractAIProvider end

"""
    complete(provider, prompt; system_prompt="", max_tokens=1024, temperature=0.7) -> String

Send `prompt` to `provider` and return the response text.

# Arguments
- `provider::AbstractAIProvider` – the configured provider instance
- `prompt::AbstractString`       – the user prompt
- `system_prompt::AbstractString` – optional system / instruction context
- `max_tokens::Int`              – upper bound on response length
- `temperature::Real`            – sampling temperature (0 = deterministic)

Throws [`AIProviderError`](@ref) on any failure.
"""
function complete end

"""
    complete_code(provider, prompt; kwargs...) -> String

Like [`complete`](@ref) but tailored for Julia code generation.
The default implementation adds a Julia-focused system prompt and delegates
to `complete`.
"""
function complete_code(provider::AbstractAIProvider, prompt::AbstractString; kwargs...)
    system_prompt = get(kwargs, :system_prompt,
        "You are an expert Julia programmer. " *
        "Respond with valid Julia code only, without explanation or markdown fences.")
    complete(provider, prompt; kwargs..., system_prompt)
end

# ── Retry helper ─────────────────────────────────────────────────────────────

const RETRYABLE_CODES = (AI_RATE_LIMIT, AI_TIMEOUT, AI_UNAVAILABLE)

"""
    with_retries(f; max_retries=3, base_delay=1.0) -> Any

Call `f()` and retry up to `max_retries` times when a retryable
[`AIProviderError`](@ref) is thrown (rate limit / timeout / unavailable).
Uses exponential back-off with jitter.
"""
function with_retries(f; max_retries::Int=3, base_delay::Real=1.0)
    last_err = nothing
    for attempt in 1:max_retries
        try
            return f()
        catch e
            if e isa AIProviderError && e.code in RETRYABLE_CODES
                last_err = e
                if attempt < max_retries
                    delay = base_delay * (2^(attempt - 1)) * (0.5 + 0.5 * rand())
                    sleep(delay)
                end
            else
                rethrow()
            end
        end
    end
    throw(last_err)
end

# ── Provider registry ─────────────────────────────────────────────────────────

"""
    build_provider(options::AIOptions) -> AbstractAIProvider

Construct the appropriate [`AbstractAIProvider`](@ref) from the given
[`AIOptions`](@ref).  Returns `nothing` when `options.provider == "none"`.
"""
function build_provider end   # implemented in Pluto.jl after all files are loaded
