"""
Telemetry module for AI feature observability.

Tracks latency, error rates, token usage, and provider/model metrics.
Sensitive values (API keys, credentials, etc.) are redacted before logging.

# Usage

```julia
# Record an AI call manually:
record!(AICallRecord(
    Dates.now(), "openai", "gpt-4o", 120.5, true, nothing, 500, 200, Dict{String,Any}()
))

# Wrap a call with automatic latency + error tracking:
result = @timed_ai_call("openai", "gpt-4o") begin
    call_some_llm_api(prompt)
end

# Retrieve aggregated metrics:
m = compute_metrics()
@info "AI metrics" m.count m.error_rate m.mean_latency_ms m.total_prompt_tokens
```
"""
module Telemetry

export AICallRecord, TelemetryStore,
    record!, clear!, get_records,
    redact_sensitive, redact_dict,
    compute_metrics,
    @timed_ai_call

import Dates

# ---------------------------------------------------------------------------
# Redaction
# ---------------------------------------------------------------------------

"""
Keys (lowercased, substring-matched) whose values should be redacted.
"""
const SENSITIVE_KEY_FRAGMENTS = (
    "api_key", "apikey", "secret", "password",
    "authorization", "credential", "bearer", "auth_token",
)

const REDACTED_PLACEHOLDER = "[REDACTED]"

"""
    redact_sensitive(key::AbstractString, value) -> Any

Return `REDACTED_PLACEHOLDER` when `key` (case-insensitive) matches a known
sensitive field name; otherwise return `value` unchanged.
"""
function redact_sensitive(key::AbstractString, value)
    k = lowercase(key)
    for frag in SENSITIVE_KEY_FRAGMENTS
        occursin(frag, k) && return REDACTED_PLACEHOLDER
    end
    return value
end

"""
    redact_dict(d::AbstractDict) -> Dict{String,Any}

Return a new `Dict` with every value whose key matches a sensitive fragment
replaced by `REDACTED_PLACEHOLDER`.
"""
function redact_dict(d::AbstractDict)
    Dict{String,Any}(string(k) => redact_sensitive(string(k), v) for (k, v) in d)
end

# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

"""
Immutable record of a single AI API call.

Fields
- `timestamp`          – when the call was initiated
- `provider`           – e.g. `"openai"`, `"anthropic"`
- `model`              – e.g. `"gpt-4o"`, `"claude-3-opus"`
- `latency_ms`         – wall-clock duration in milliseconds
- `success`            – `true` if the call returned without throwing
- `error_type`         – `string(typeof(exception))` on failure, otherwise `nothing`
- `tokens_prompt`      – prompt tokens consumed (if reported)
- `tokens_completion`  – completion tokens consumed (if reported)
- `metadata`           – additional **already-redacted** key/value pairs
"""
struct AICallRecord
    timestamp::Dates.DateTime
    provider::String
    model::String
    latency_ms::Float64
    success::Bool
    error_type::Union{String,Nothing}
    tokens_prompt::Union{Int,Nothing}
    tokens_completion::Union{Int,Nothing}
    metadata::Dict{String,Any}
end

# ---------------------------------------------------------------------------
# Thread-safe store
# ---------------------------------------------------------------------------

"""
Thread-safe, bounded circular store for `AICallRecord`s.

When `max_records` is exceeded the oldest record is dropped to make room.
"""
mutable struct TelemetryStore
    records::Vector{AICallRecord}
    lock::ReentrantLock
    max_records::Int

    TelemetryStore(; max_records::Int = 10_000) =
        new(AICallRecord[], ReentrantLock(), max_records)
end

# Package-level default store (one per Julia session).
const _global_store = TelemetryStore()

"""
    record!(store::TelemetryStore, r::AICallRecord)

Append `r` to `store`, dropping the oldest entry if capacity is exceeded.
"""
function record!(store::TelemetryStore, r::AICallRecord)
    lock(store.lock) do
        push!(store.records, r)
        if length(store.records) > store.max_records
            popfirst!(store.records)
        end
    end
    nothing
end

"""
    record!(r::AICallRecord)

Append `r` to the global telemetry store.
"""
record!(r::AICallRecord) = record!(_global_store, r)

"""
    get_records([store]) -> Vector{AICallRecord}

Return a snapshot (shallow copy) of all records held by `store`
(default: the global store).
"""
function get_records(store::TelemetryStore = _global_store)
    lock(store.lock) do
        copy(store.records)
    end
end

"""
    clear!([store])

Remove all records from `store` (default: the global store).
"""
function clear!(store::TelemetryStore = _global_store)
    lock(store.lock) do
        empty!(store.records)
    end
    nothing
end

# ---------------------------------------------------------------------------
# Instrumentation macro
# ---------------------------------------------------------------------------

"""
    @timed_ai_call(provider, model[, store], expr)

Wrap `expr` to automatically measure wall-clock latency and capture
success/failure, then append an `AICallRecord` to `store` (default:
the global store).

The result of `expr` is returned; any exception is re-thrown after the
record is written.

# Example
```julia
response = @timed_ai_call("openai", "gpt-4o") call_llm(prompt)
```
"""
macro timed_ai_call(provider, model, expr)
    quote
        local _t0        = time_ns()
        local _success   = true
        local _err_type  = nothing
        local _result    = nothing
        try
            _result = $(esc(expr))
        catch _e
            _success  = false
            _err_type = string(typeof(_e))
            rethrow(_e)
        finally
            local _latency_ms = (time_ns() - _t0) / 1_000_000.0
            record!(_global_store, AICallRecord(
                Dates.now(),
                string($(esc(provider))),
                string($(esc(model))),
                _latency_ms,
                _success,
                _err_type,
                nothing,
                nothing,
                Dict{String,Any}(),
            ))
        end
        _result
    end
end

macro timed_ai_call(provider, model, store, expr)
    quote
        local _t0        = time_ns()
        local _success   = true
        local _err_type  = nothing
        local _result    = nothing
        try
            _result = $(esc(expr))
        catch _e
            _success  = false
            _err_type = string(typeof(_e))
            rethrow(_e)
        finally
            local _latency_ms = (time_ns() - _t0) / 1_000_000.0
            record!($(esc(store)), AICallRecord(
                Dates.now(),
                string($(esc(provider))),
                string($(esc(model))),
                _latency_ms,
                _success,
                _err_type,
                nothing,
                nothing,
                Dict{String,Any}(),
            ))
        end
        _result
    end
end

# ---------------------------------------------------------------------------
# Metrics aggregation
# ---------------------------------------------------------------------------

"""
    compute_metrics(records::AbstractVector{AICallRecord}) -> NamedTuple

Aggregate the given records into a summary `NamedTuple` with fields:

| Field                   | Description                                      |
|:------------------------|:-------------------------------------------------|
| `count`                 | total number of records                          |
| `error_rate`            | fraction of failed calls (NaN when `count == 0`) |
| `mean_latency_ms`       | arithmetic mean latency                          |
| `p50_latency_ms`        | 50th-percentile (median) latency                 |
| `p95_latency_ms`        | 95th-percentile latency                          |
| `p99_latency_ms`        | 99th-percentile latency                          |
| `total_prompt_tokens`   | sum of all `tokens_prompt` values                |
| `total_completion_tokens` | sum of all `tokens_completion` values          |
| `by_provider`           | `Dict{String,NamedTuple}` — same metrics grouped by provider |
| `by_model`              | `Dict{String,NamedTuple}` — same metrics grouped by model    |

Note: `by_provider` and `by_model` entries do **not** recurse further (their
own `by_provider`/`by_model` fields are empty dicts).
"""
function compute_metrics(records::AbstractVector{AICallRecord})
    n = length(records)

    empty_result() = (
        count                 = 0,
        error_rate            = NaN,
        mean_latency_ms       = NaN,
        p50_latency_ms        = NaN,
        p95_latency_ms        = NaN,
        p99_latency_ms        = NaN,
        total_prompt_tokens   = 0,
        total_completion_tokens = 0,
        by_provider           = Dict{String,Any}(),
        by_model              = Dict{String,Any}(),
    )

    n == 0 && return empty_result()

    errors   = count(r -> !r.success, records)
    latencies = sort!([r.latency_ms for r in records])

    function percentile(v, p)
        idx = clamp(ceil(Int, p / 100 * length(v)), 1, length(v))
        v[idx]
    end

    total_prompt     = sum(r -> something(r.tokens_prompt, 0), records)
    total_completion = sum(r -> something(r.tokens_completion, 0), records)

    # Leaf-level helper (no recursive grouping to keep allocations bounded)
    function leaf_metrics(recs)
        m = length(recs)
        m == 0 && return empty_result()
        lats = sort!([r.latency_ms for r in recs])
        (
            count                 = m,
            error_rate            = count(r -> !r.success, recs) / m,
            mean_latency_ms       = sum(lats) / m,
            p50_latency_ms        = percentile(lats, 50),
            p95_latency_ms        = percentile(lats, 95),
            p99_latency_ms        = percentile(lats, 99),
            total_prompt_tokens   = sum(r -> something(r.tokens_prompt, 0), recs),
            total_completion_tokens = sum(r -> something(r.tokens_completion, 0), recs),
            by_provider           = Dict{String,Any}(),
            by_model              = Dict{String,Any}(),
        )
    end

    # Group by provider
    providers  = unique(r.provider for r in records)
    by_provider = Dict{String,Any}(
        p => leaf_metrics(filter(r -> r.provider == p, records)) for p in providers
    )

    # Group by model
    models   = unique(r.model for r in records)
    by_model = Dict{String,Any}(
        m => leaf_metrics(filter(r -> r.model == m, records)) for m in models
    )

    (
        count                   = n,
        error_rate              = errors / n,
        mean_latency_ms         = sum(latencies) / n,
        p50_latency_ms          = percentile(latencies, 50),
        p95_latency_ms          = percentile(latencies, 95),
        p99_latency_ms          = percentile(latencies, 99),
        total_prompt_tokens     = total_prompt,
        total_completion_tokens = total_completion,
        by_provider             = by_provider,
        by_model                = by_model,
    )
end

"""
    compute_metrics([store]) -> NamedTuple

Aggregate metrics from all records in `store` (default: the global store).
"""
compute_metrics(store::TelemetryStore = _global_store) =
    compute_metrics(get_records(store))

end  # module Telemetry
