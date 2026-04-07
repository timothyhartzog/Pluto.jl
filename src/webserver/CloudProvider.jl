"""
Cloud provider adapter with secure API-key handling, structured error taxonomy,
and an automatic retry policy.

Typical usage:

```julia
using Pluto
opts = Pluto.Configuration.CloudProviderOptions(
    api_key_env = "OPENAI_API_KEY",
    base_url    = "https://api.openai.com/v1",
    timeout     = 30.0,
    max_retries = 3,
)
response = Pluto.CloudProvider.cloud_request(opts, "/chat/completions",
    "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
```
"""
module CloudProvider

import HTTP
import ..Configuration: CloudProviderOptions


# ── Secure secret type ────────────────────────────────────────────────────────

"""
    RedactedSecret(value::String)

A thin wrapper around a secret string value that prevents the secret from
appearing in logs, `@show` output, or any other `show`-based serialisation.
Access the raw value only via `secret_value(r)`.
"""
struct RedactedSecret
    _value::String
end

"""Return the raw secret string.  Call only where the value is actually needed."""
secret_value(r::RedactedSecret)::String = r._value

Base.show(io::IO, ::RedactedSecret)                        = print(io, "[REDACTED]")
Base.show(io::IO, ::MIME"text/plain", r::RedactedSecret)   = show(io, r)
Base.show(io::IO, ::MIME"text/html",  r::RedactedSecret)   = show(io, r)
# Prevent accidental interpolation into strings:
Base.string(r::RedactedSecret) = "[REDACTED]"
Base.print(io::IO, r::RedactedSecret) = print(io, "[REDACTED]")


# ── Error taxonomy ────────────────────────────────────────────────────────────

"""Supertype for all errors raised by the cloud provider adapter."""
abstract type CloudProviderError <: Exception end

"""
    CloudAuthError(message, status_code)

Raised when the cloud provider returns HTTP 401 or 403 (authentication /
authorisation failure) or when no API key can be found.
"""
struct CloudAuthError <: CloudProviderError
    message::String
    status_code::Int
end

"""
    CloudRateLimitError(message, retry_after)

Raised when the cloud provider returns HTTP 429 (quota / rate-limit exceeded).
`retry_after` is the number of seconds suggested by the provider, or `nothing`
if the header was absent.
"""
struct CloudRateLimitError <: CloudProviderError
    message::String
    retry_after::Union{Float64,Nothing}
end

"""
    CloudTimeoutError(message)

Raised when the request to the cloud provider times out or a network-level I/O
error occurs and all retry attempts have been exhausted.
"""
struct CloudTimeoutError <: CloudProviderError
    message::String
end

"""
    CloudServerError(message, status_code)

Raised when the cloud provider returns a 5xx server error and all retry
attempts have been exhausted.
"""
struct CloudServerError <: CloudProviderError
    message::String
    status_code::Int
end

function Base.showerror(io::IO, e::CloudAuthError)
    print(io, "CloudAuthError (HTTP $(e.status_code)): $(e.message)")
end
function Base.showerror(io::IO, e::CloudRateLimitError)
    ra = e.retry_after === nothing ? "unknown" : "$(round(e.retry_after, digits=1))s"
    print(io, "CloudRateLimitError (retry-after: $(ra)): $(e.message)")
end
function Base.showerror(io::IO, e::CloudTimeoutError)
    print(io, "CloudTimeoutError: $(e.message)")
end
function Base.showerror(io::IO, e::CloudServerError)
    print(io, "CloudServerError (HTTP $(e.status_code)): $(e.message)")
end


# ── Key loading ───────────────────────────────────────────────────────────────

"""
    load_api_key(options::CloudProviderOptions) -> Union{RedactedSecret, Nothing}

Load the API key according to `options`.

1. If `options.api_key_path` is set and the file exists its contents are used.
2. Otherwise the environment variable named by `options.api_key_env` is tried.
3. Returns `nothing` if neither source yields a non-empty value.

The return type is `RedactedSecret` so that the key is never accidentally
logged or interpolated into strings.
"""
function load_api_key(options::CloudProviderOptions)::Union{RedactedSecret,Nothing}
    if options.api_key_path !== nothing
        path = options.api_key_path::String
        if isfile(path)
            raw = strip(read(path, String))
            if !isempty(raw)
                return RedactedSecret(raw)
            end
        else
            @warn "CloudProvider: api_key_path does not exist" path
        end
    end

    env_val = get(ENV, options.api_key_env, "")
    isempty(env_val) ? nothing : RedactedSecret(env_val)
end


# ── HTTP request with retry ───────────────────────────────────────────────────

# Backoff schedule: attempt 1 → 1s, attempt 2 → 2s, attempt 3 → 4s, …
_backoff(attempt::Int) = min(2.0^(attempt - 1), 30.0)

"""
    cloud_request(options, endpoint, body_str; method="POST", api_key=nothing)
    -> HTTP.Response

Make an authenticated HTTP request to a cloud provider endpoint.

# Arguments
- `options::CloudProviderOptions` – configuration (key source, base URL, timeouts, retries).
- `endpoint::String` – path to append to `options.base_url`, e.g. `"/chat/completions"`.
- `body_str::Union{String,Vector{UInt8}}` – raw request body (typically a JSON string).
- `method::String` – HTTP verb, default `"POST"`.
- `api_key::Union{RedactedSecret,Nothing}` – optional pre-loaded key; if `nothing`,
  `load_api_key(options)` is called automatically.

# Error mapping
| HTTP status | Error thrown              |
|-------------|--------------------------|
| 401, 403    | `CloudAuthError`          |
| 429         | `CloudRateLimitError`     |
| 5xx         | `CloudServerError` (after retries) |
| timeout / network error | `CloudTimeoutError` (after retries) |

Successful responses (any 2xx or 3xx) are returned as-is.
"""
function cloud_request(
    options   ::CloudProviderOptions,
    endpoint  ::String,
    body_str  ::Union{String,Vector{UInt8}};
    method    ::String = "POST",
    api_key   ::Union{RedactedSecret,Nothing} = nothing,
)::HTTP.Response

    key = api_key !== nothing ? api_key : load_api_key(options)
    if key === nothing
        throw(CloudAuthError(
            "No API key available. Set options.api_key_path or the " *
            "$(options.api_key_env) environment variable.",
            401,
        ))
    end

    url     = rstrip(options.base_url, '/') * "/" * lstrip(endpoint, '/')
    headers = [
        "Content-Type"  => "application/json",
        "Authorization" => "Bearer $(secret_value(key))",
    ]

    last_exc = nothing

    for attempt in 1:(options.max_retries + 1)
        try
            response = HTTP.request(
                method, url, headers, body_str;
                readtimeout  = options.timeout,
                status_exception = false,
            )

            status = response.status

            # ── authentication / authorisation errors ─────────────────────
            if status == 401 || status == 403
                throw(CloudAuthError("Authentication failed", status))
            end

            # ── quota / rate-limit errors ─────────────────────────────────
            if status == 429
                retry_after = _parse_retry_after(response)
                if attempt <= options.max_retries
                    sleep_s = retry_after !== nothing ? retry_after : _backoff(attempt)
                    @info "CloudProvider: rate-limited; waiting $(sleep_s)s before retry $(attempt)/$(options.max_retries)"
                    sleep(sleep_s)
                    continue
                end
                throw(CloudRateLimitError("Rate limit exceeded", retry_after))
            end

            # ── server errors (retryable) ─────────────────────────────────
            if status >= 500
                last_exc = CloudServerError("Server error", status)
                if attempt <= options.max_retries
                    @info "CloudProvider: server error $(status); retry $(attempt)/$(options.max_retries)"
                    sleep(_backoff(attempt))
                    continue
                end
                throw(last_exc)
            end

            return response

        catch e
            # Do not retry on auth or rate-limit errors; re-throw immediately.
            if e isa CloudAuthError || e isa CloudRateLimitError
                rethrow()
            end

            # Timeout / network errors are retryable.
            if _is_transient_error(e)
                last_exc = CloudTimeoutError("Transient error: $(e)")
                if attempt <= options.max_retries
                    @info "CloudProvider: transient error; retry $(attempt)/$(options.max_retries)" exception=(e, catch_backtrace())
                    sleep(_backoff(attempt))
                    continue
                end
                throw(CloudTimeoutError("Request failed after $(options.max_retries) retries: $(e)"))
            end

            rethrow()
        end
    end

    # Should be unreachable, but satisfy the type checker.
    throw(last_exc)
end


# ── Internal helpers ──────────────────────────────────────────────────────────

function _parse_retry_after(response::HTTP.Response)::Union{Float64,Nothing}
    for (k, v) in response.headers
        if lowercase(k) == "retry-after"
            parsed = tryparse(Float64, strip(v))
            return parsed
        end
    end
    nothing
end

function _is_transient_error(e)::Bool
    e isa HTTP.TimeoutError    ||
    e isa HTTP.IOError         ||
    e isa Base.IOError         ||
    (e isa HTTP.StatusError && e.status >= 500)
end


end  # module CloudProvider
