# AI Provider Interface
#
# Defines typed interfaces, structured response schemas, and a shared error
# taxonomy for the AI provider integrations used by Pluto notebooks.
#
# Intent categories
# -----------------
#   :completion   – single-turn text completion
#   :streamed     – streaming text completion (token-by-token)
#   :code_gen     – code-generation task returning Julia source
#
# Provider implementations should subtype `AbstractAIProvider` and implement
# the `complete`, `stream_complete`, and `generate_code` methods.

module AIProvider

export AbstractAIProvider
export AIRequest, AIResponse, AIStreamChunk
export AIProviderError, AIValidationError, AIRateLimitError,
       AIAuthError, AITimeoutError, AIUnavailableError
export validate_response, validate_request

# ────────────────────────────────────────────────────────────────────────────
# Error taxonomy
# ────────────────────────────────────────────────────────────────────────────

"""
    AIProviderError(message)

Base error type for all AI provider failures.  Concrete sub-types carry
additional structured context.
"""
struct AIProviderError <: Exception
    message::String
end

"""
    AIValidationError(message, field)

Raised when a request or response fails schema validation.
`field` identifies which field triggered the error (empty string if unknown).
"""
struct AIValidationError <: Exception
    message::String
    field::String
end
AIValidationError(message::String) = AIValidationError(message, "")

"""
    AIRateLimitError(message; retry_after)

Raised when the upstream provider signals that the rate limit has been
exceeded.  `retry_after` is the suggested wait in seconds (or `nothing`).
"""
struct AIRateLimitError <: Exception
    message::String
    retry_after::Union{Int,Nothing}
end
AIRateLimitError(message::String) = AIRateLimitError(message, nothing)

"""
    AIAuthError(message)

Raised when authentication with the upstream provider fails (bad key, expired
token, etc.).
"""
struct AIAuthError <: Exception
    message::String
end

"""
    AITimeoutError(message; timeout_secs)

Raised when the upstream provider does not respond within the configured
timeout.
"""
struct AITimeoutError <: Exception
    message::String
    timeout_secs::Union{Float64,Nothing}
end
AITimeoutError(message::String) = AITimeoutError(message, nothing)

"""
    AIUnavailableError(message)

Raised when the upstream provider is temporarily unavailable (e.g. 503).
"""
struct AIUnavailableError <: Exception
    message::String
end

# ────────────────────────────────────────────────────────────────────────────
# Request schema
# ────────────────────────────────────────────────────────────────────────────

"""
    AIRequest

Structured container for an AI provider request.

# Fields
- `intent`        – one of `:completion`, `:streamed`, `:code_gen`
- `prompt`        – the user / instruction prompt (non-empty)
- `system_prompt` – optional system / context prompt
- `model`         – provider-specific model identifier (non-empty)
- `max_tokens`    – upper bound on response tokens (positive integer or `nothing`)
- `temperature`   – sampling temperature in [0, 2] (or `nothing` for default)
- `metadata`      – arbitrary key-value pairs for provider-specific options
"""
struct AIRequest
    intent::Symbol
    prompt::String
    system_prompt::String
    model::String
    max_tokens::Union{Int,Nothing}
    temperature::Union{Float64,Nothing}
    metadata::Dict{String,Any}
end

function AIRequest(;
    intent::Symbol,
    prompt::String,
    system_prompt::String = "",
    model::String,
    max_tokens::Union{Int,Nothing} = nothing,
    temperature::Union{Float64,Nothing} = nothing,
    metadata::Dict{String,Any} = Dict{String,Any}(),
)
    AIRequest(intent, prompt, system_prompt, model, max_tokens, temperature, metadata)
end

const VALID_INTENTS = (:completion, :streamed, :code_gen)

# ────────────────────────────────────────────────────────────────────────────
# Response schema
# ────────────────────────────────────────────────────────────────────────────

"""
    AIResponse

Structured container for a completed AI provider response.

# Fields
- `success`        – `true` when the provider returned a usable result
- `text`           – the response text (may be empty on failure)
- `model`          – the model that produced the response
- `intent`         – echoes the original request intent
- `finish_reason`  – provider finish signal, e.g. `"stop"`, `"length"`, `"error"`
- `input_tokens`   – tokens consumed by the prompt (or `nothing`)
- `output_tokens`  – tokens produced in the response (or `nothing`)
- `error`          – error message when `success == false`
- `metadata`       – arbitrary key-value pairs returned by the provider
"""
struct AIResponse
    success::Bool
    text::String
    model::String
    intent::Symbol
    finish_reason::String
    input_tokens::Union{Int,Nothing}
    output_tokens::Union{Int,Nothing}
    error::String
    metadata::Dict{String,Any}
end

function AIResponse(;
    success::Bool,
    text::String = "",
    model::String,
    intent::Symbol,
    finish_reason::String = success ? "stop" : "error",
    input_tokens::Union{Int,Nothing} = nothing,
    output_tokens::Union{Int,Nothing} = nothing,
    error::String = "",
    metadata::Dict{String,Any} = Dict{String,Any}(),
)
    AIResponse(success, text, model, intent, finish_reason, input_tokens, output_tokens, error, metadata)
end

"""
    AIStreamChunk

A single chunk delivered during a streaming completion.

# Fields
- `delta`   – incremental text fragment
- `done`    – `true` on the final chunk
- `metadata`– optional per-chunk metadata
"""
struct AIStreamChunk
    delta::String
    done::Bool
    metadata::Dict{String,Any}
end

AIStreamChunk(delta::String, done::Bool) =
    AIStreamChunk(delta, done, Dict{String,Any}())

# ────────────────────────────────────────────────────────────────────────────
# Abstract provider interface
# ────────────────────────────────────────────────────────────────────────────

"""
    AbstractAIProvider

Supertype for all AI provider implementations.  Concrete subtypes must
implement:

- `complete(provider, request)  → AIResponse`
- `stream_complete(provider, request, on_chunk) → AIResponse`
- `generate_code(provider, request) → AIResponse`

and may optionally implement:

- `provider_name(provider) → String`
- `supported_models(provider) → Vector{String}`
"""
abstract type AbstractAIProvider end

"""
    provider_name(provider) → String

Return a human-readable name for the provider (e.g. `"Claude"`, `"OpenAI"`).
Default implementation uses the type name.
"""
provider_name(p::AbstractAIProvider) = string(nameof(typeof(p)))

"""
    supported_models(provider) → Vector{String}

Return a list of model identifiers supported by this provider.
Default returns an empty vector (no restriction).
"""
supported_models(::AbstractAIProvider) = String[]

"""
    complete(provider, request) → AIResponse

Execute a single-turn text completion. The `request` intent must be
`:completion`.  Throws `AIValidationError` for malformed requests.
"""
function complete end

"""
    stream_complete(provider, request, on_chunk) → AIResponse

Execute a streaming text completion.  `on_chunk(::AIStreamChunk)` is called
for each chunk as it arrives.  The `request` intent must be `:streamed`.
Returns the aggregated `AIResponse` once the stream is finished.
Throws `AIValidationError` for malformed requests.
"""
function stream_complete end

"""
    generate_code(provider, request) → AIResponse

Execute a code-generation task.  The `request` intent must be `:code_gen`.
The returned `AIResponse.text` contains the generated Julia source code.
Throws `AIValidationError` for malformed requests.
"""
function generate_code end

# ────────────────────────────────────────────────────────────────────────────
# Validation helpers
# ────────────────────────────────────────────────────────────────────────────

"""
    validate_request(request) → nothing

Validate an `AIRequest` against the schema.  Throws `AIValidationError` if
the request is malformed.
"""
function validate_request(req::AIRequest)
    if req.intent ∉ VALID_INTENTS
        throw(AIValidationError(
            "intent must be one of $(VALID_INTENTS), got :$(req.intent)",
            "intent",
        ))
    end
    if isempty(strip(req.prompt))
        throw(AIValidationError("prompt must not be empty", "prompt"))
    end
    if isempty(strip(req.model))
        throw(AIValidationError("model must not be empty", "model"))
    end
    if req.max_tokens !== nothing && req.max_tokens <= 0
        throw(AIValidationError("max_tokens must be a positive integer, got $(req.max_tokens)", "max_tokens"))
    end
    if req.temperature !== nothing && !(0.0 <= req.temperature <= 2.0)
        throw(AIValidationError(
            "temperature must be in [0, 2], got $(req.temperature)",
            "temperature",
        ))
    end
    nothing
end

"""
    validate_response(response) → nothing

Validate an `AIResponse` against the schema.  Throws `AIValidationError` if
the response is malformed.
"""
function validate_response(resp::AIResponse)
    if resp.intent ∉ VALID_INTENTS
        throw(AIValidationError(
            "response intent must be one of $(VALID_INTENTS), got :$(resp.intent)",
            "intent",
        ))
    end
    if isempty(strip(resp.model))
        throw(AIValidationError("response model must not be empty", "model"))
    end
    if resp.finish_reason ∉ ("stop", "length", "error", "content_filter", "tool_use")
        throw(AIValidationError(
            "unrecognized finish_reason: \"$(resp.finish_reason)\"",
            "finish_reason",
        ))
    end
    if resp.input_tokens !== nothing && resp.input_tokens < 0
        throw(AIValidationError("input_tokens must be non-negative, got $(resp.input_tokens)", "input_tokens"))
    end
    if resp.output_tokens !== nothing && resp.output_tokens < 0
        throw(AIValidationError("output_tokens must be non-negative, got $(resp.output_tokens)", "output_tokens"))
    end
    if !resp.success && isempty(resp.error)
        throw(AIValidationError("error must not be empty when success is false", "error"))
    end
    nothing
end

end # module AIProvider
