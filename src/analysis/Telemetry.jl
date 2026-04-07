"""
Telemetry module for AI feature observability.

Tracks latency, error rates, token usage, and provider/model usage mix
for AI-powered features in Pluto. Sensitive values are redacted before logging.

## Usage

```julia
store = TelemetryStore()

# Record a successful AI request
record_request!(store;
    provider = "openai",
    model    = "gpt-4o",
    latency_ms = 320.0,
    input_tokens  = 512,
    output_tokens = 128,
)

# Record an error
record_error!(store; provider = "openai", model = "gpt-4o", error_type = "timeout")

# Query aggregated metrics
m = get_metrics(store)
m.total_requests   # => 1
m.total_errors     # => 0
m.mean_latency_ms  # => 320.0

# Redact sensitive data before logging
safe = redact(Dict("api_key" => "sk-secret", "prompt" => "hello"))
# => Dict("api_key" => "[REDACTED]", "prompt" => "[REDACTED]")
```
"""
module Telemetry

export TelemetryStore,
       MetricEvent,
       AggregatedMetrics,
       record_request!,
       record_error!,
       get_metrics,
       reset!,
       redact

import Dates: now, DateTime

# ---------------------------------------------------------------------------
# Sensitive key patterns – values whose keys match these patterns are
# replaced with "[REDACTED]" by `redact`.
# ---------------------------------------------------------------------------
const SENSITIVE_KEY_PATTERNS = [
    r"api[_\-]?key"i,
    r"secret"i,
    r"token"i,
    r"password"i,
    r"passwd"i,
    r"auth"i,
    r"credential"i,
    r"prompt"i,          # raw user prompts may contain PII
    r"content"i,         # message/cell content
    r"notebook[_\-]?content"i,
    r"cell[_\-]?code"i,
    r"user[_\-]?data"i,
]

"""
    redact(value) -> value
    redact(d::AbstractDict) -> Dict
    redact(v::AbstractVector) -> Vector

Recursively redacts sensitive fields from a dictionary or collection.
String keys whose names match known sensitive patterns (API keys, secrets,
prompts, user content, …) are replaced with `"[REDACTED]"`.
"""
function redact(d::AbstractDict)
    out = Dict{Any,Any}()
    for (k, v) in d
        key_str = string(k)
        if any(occursin(pat, key_str) for pat in SENSITIVE_KEY_PATTERNS)
            out[k] = "[REDACTED]"
        else
            out[k] = redact(v)
        end
    end
    return out
end

redact(v::AbstractVector) = [redact(x) for x in v]
redact(v::AbstractString) = v          # only redact by key, not by value
redact(v) = v                          # pass non-string scalars unchanged

# ---------------------------------------------------------------------------
# MetricEvent – a single recorded AI request or error event
# ---------------------------------------------------------------------------

"""
    MetricEvent

A single telemetry event representing one AI request or error.

Fields
------
- `timestamp`     – `DateTime` when the event was recorded.
- `provider`      – Provider name (e.g. `"openai"`, `"ollama"`).
- `model`         – Model name (e.g. `"gpt-4o"`).
- `latency_ms`    – Round-trip latency in milliseconds (≥ 0, `NaN` if unknown).
- `input_tokens`  – Number of prompt tokens consumed (0 if not applicable).
- `output_tokens` – Number of completion tokens generated (0 if not applicable).
- `is_error`      – `true` when the request resulted in an error.
- `error_type`    – Short tag describing the error kind (empty string if none).
"""
struct MetricEvent
    timestamp::DateTime
    provider::String
    model::String
    latency_ms::Float64
    input_tokens::Int
    output_tokens::Int
    is_error::Bool
    error_type::String
end

# ---------------------------------------------------------------------------
# TelemetryStore – mutable container that accumulates MetricEvents
# ---------------------------------------------------------------------------

"""
    TelemetryStore(; max_events = 10_000)

Thread-safe store that accumulates `MetricEvent`s.
Old events are dropped (FIFO) once the store reaches `max_events`.
"""
mutable struct TelemetryStore
    events::Vector{MetricEvent}
    max_events::Int
    lock::ReentrantLock

    TelemetryStore(; max_events::Int = 10_000) =
        new(MetricEvent[], max_events, ReentrantLock())
end

# ---------------------------------------------------------------------------
# Recording helpers
# ---------------------------------------------------------------------------

"""
    record_request!(store; provider, model, latency_ms,
                    input_tokens=0, output_tokens=0) -> MetricEvent

Record a *successful* AI-request event in `store`.
"""
function record_request!(
    store::TelemetryStore;
    provider::AbstractString,
    model::AbstractString,
    latency_ms::Real,
    input_tokens::Integer = 0,
    output_tokens::Integer = 0,
)
    ev = MetricEvent(
        now(),
        string(provider),
        string(model),
        Float64(latency_ms),
        Int(input_tokens),
        Int(output_tokens),
        false,
        "",
    )
    _push!(store, ev)
    return ev
end

"""
    record_error!(store; provider, model, error_type="unknown",
                  latency_ms=NaN) -> MetricEvent

Record an *error* event in `store`.
"""
function record_error!(
    store::TelemetryStore;
    provider::AbstractString,
    model::AbstractString,
    error_type::AbstractString = "unknown",
    latency_ms::Real = NaN,
)
    ev = MetricEvent(
        now(),
        string(provider),
        string(model),
        Float64(latency_ms),
        0,
        0,
        true,
        string(error_type),
    )
    _push!(store, ev)
    return ev
end

function _push!(store::TelemetryStore, ev::MetricEvent)
    lock(store.lock) do
        push!(store.events, ev)
        # Drop oldest events when the store is full
        if length(store.events) > store.max_events
            deleteat!(store.events, 1:(length(store.events) - store.max_events))
        end
    end
end

# ---------------------------------------------------------------------------
# reset!
# ---------------------------------------------------------------------------

"""
    reset!(store) -> store

Remove all recorded events from `store`.
"""
function reset!(store::TelemetryStore)
    lock(store.lock) do
        empty!(store.events)
    end
    return store
end

# ---------------------------------------------------------------------------
# AggregatedMetrics – summary returned by get_metrics
# ---------------------------------------------------------------------------

"""
    AggregatedMetrics

Summary statistics computed from all events in a `TelemetryStore`.

Fields
------
- `total_requests`      – Total number of request events (including errors).
- `total_errors`        – Total number of error events.
- `error_rate`          – `total_errors / total_requests` (0.0 if no requests).
- `mean_latency_ms`     – Mean latency over successful requests (`NaN` if none).
- `p50_latency_ms`      – Median latency over successful requests (`NaN` if none).
- `p95_latency_ms`      – 95th-percentile latency over successful requests (`NaN` if none).
- `total_input_tokens`  – Sum of input tokens across all events.
- `total_output_tokens` – Sum of output tokens across all events.
- `by_provider`         – `Dict{String, Int}` request count per provider.
- `by_model`            – `Dict{String, Int}` request count per model.
- `error_types`         – `Dict{String, Int}` error count per error type.
"""
struct AggregatedMetrics
    total_requests::Int
    total_errors::Int
    error_rate::Float64
    mean_latency_ms::Float64
    p50_latency_ms::Float64
    p95_latency_ms::Float64
    total_input_tokens::Int
    total_output_tokens::Int
    by_provider::Dict{String,Int}
    by_model::Dict{String,Int}
    error_types::Dict{String,Int}
end

# ---------------------------------------------------------------------------
# get_metrics
# ---------------------------------------------------------------------------

"""
    get_metrics(store) -> AggregatedMetrics

Compute and return aggregated telemetry metrics from `store`.
The result can be used for dashboarding and regression tracking.
"""
function get_metrics(store::TelemetryStore)::AggregatedMetrics
    events = lock(store.lock) do
        copy(store.events)
    end

    total_requests = length(events)
    total_errors   = count(e -> e.is_error, events)
    error_rate     = total_requests == 0 ? 0.0 : total_errors / total_requests

    # Latency statistics (only over non-NaN values from successful requests)
    latencies = filter(x -> !isnan(x), [e.latency_ms for e in events if !e.is_error])
    mean_lat = isempty(latencies) ? NaN : sum(latencies) / length(latencies)
    p50_lat  = isempty(latencies) ? NaN : _percentile(latencies, 50)
    p95_lat  = isempty(latencies) ? NaN : _percentile(latencies, 95)

    total_input  = sum(e.input_tokens  for e in events; init = 0)
    total_output = sum(e.output_tokens for e in events; init = 0)

    by_provider = Dict{String,Int}()
    by_model    = Dict{String,Int}()
    error_types = Dict{String,Int}()

    for e in events
        by_provider[e.provider] = get(by_provider, e.provider, 0) + 1
        by_model[e.model]       = get(by_model, e.model, 0) + 1
        if e.is_error && !isempty(e.error_type)
            error_types[e.error_type] = get(error_types, e.error_type, 0) + 1
        end
    end

    return AggregatedMetrics(
        total_requests,
        total_errors,
        error_rate,
        mean_lat,
        p50_lat,
        p95_lat,
        total_input,
        total_output,
        by_provider,
        by_model,
        error_types,
    )
end

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

"Compute the p-th percentile (0–100) of a non-empty sorted vector."
function _percentile(values::AbstractVector{<:Real}, p::Real)
    sorted = sort(values)
    n = length(sorted)
    # Linear interpolation: index ranges from 1 to n
    idx = 1.0 + (p / 100.0) * (n - 1)
    lo = floor(Int, idx)
    hi = ceil(Int, idx)
    lo == hi ? sorted[lo] : sorted[lo] + (idx - lo) * (sorted[hi] - sorted[lo])
end

end # module Telemetry
