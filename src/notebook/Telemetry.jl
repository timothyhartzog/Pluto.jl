"""
Telemetry module for Pluto.jl

Provides hooks for tracking notebook usage events with automatic redaction of
sensitive values from telemetry payloads.

# Usage

```julia
Pluto.Telemetry.record_event("notebook_run", Dict("notebook_id" => id, "token" => secret))
# => {"notebook_id" => id, "token" => "[REDACTED]"}
```

Register a custom sink via `on_telemetry_event`:

```julia
Pluto.run(; on_event = function(e)
    if e isa Pluto.Telemetry.TelemetryEvent
        # handle telemetry
    end
end)
```
"""
module Telemetry

export TelemetryEvent, redact_sensitive, record_event

"""
A set of field-name patterns (lowercase) that are considered sensitive and should be
redacted from telemetry payloads.
"""
const SENSITIVE_KEYS = Set{String}([
    "password", "passwd", "pwd",
    "token", "access_token", "refresh_token", "id_token",
    "secret", "client_secret",
    "key", "api_key", "private_key", "secret_key",
    "auth", "authorization", "bearer",
    "credential", "credentials",
    "ssn", "social_security",
    "credit_card", "card_number",
])

const REDACTED_PLACEHOLDER = "[REDACTED]"

"""
    redact_sensitive(data)

Recursively walk `data` (a `Dict`, `Vector`, or scalar) and replace values whose
keys match a known sensitive pattern with `"[REDACTED]"`.

# Examples

```julia
julia> Pluto.Telemetry.redact_sensitive(Dict("user" => "alice", "password" => "s3cr3t"))
Dict("user" => "alice", "password" => "[REDACTED]")

julia> Pluto.Telemetry.redact_sensitive(Dict("nested" => Dict("api_key" => "abc123")))
Dict("nested" => Dict("api_key" => "[REDACTED]"))
```
"""
function redact_sensitive(data::AbstractDict)
    result = Dict{keytype(data), Any}()
    for (k, v) in data
        if _is_sensitive_key(k)
            result[k] = REDACTED_PLACEHOLDER
        else
            result[k] = redact_sensitive(v)
        end
    end
    result
end

function redact_sensitive(data::AbstractVector)
    map(redact_sensitive, data)
end

# Scalars and other types pass through unchanged
redact_sensitive(data) = data

_is_sensitive_key(key::AbstractString) = lowercase(strip(key)) in SENSITIVE_KEYS
_is_sensitive_key(key::Symbol) = _is_sensitive_key(String(key))
_is_sensitive_key(::Any) = false


"""
    TelemetryEvent

Represents a telemetry event that can be consumed by a registered event handler.
The `payload` dict has already had sensitive values redacted.

Fields:
- `event_name::String` – a short identifier for the event kind, e.g. `"notebook_run"`.
- `payload::Dict{String,Any}` – additional metadata (already redacted).
- `timestamp::Float64` – `time()` at the moment of recording.
"""
struct TelemetryEvent
    event_name::String
    payload::Dict{String,Any}
    timestamp::Float64
end

TelemetryEvent(event_name::AbstractString, payload::AbstractDict=Dict{String,Any}()) =
    TelemetryEvent(
        String(event_name),
        Dict{String,Any}(redact_sensitive(payload)),
        time(),
    )


"""
    record_event(session, event_name, payload=Dict())

Build a [`TelemetryEvent`](@ref) (with sensitive values redacted) and forward it to
the session's `on_event` callback if one is registered.

This function never throws: any error in the consumer is caught and logged.
"""
function record_event(session, event_name::AbstractString, payload::AbstractDict=Dict{String,Any}())
    event = TelemetryEvent(event_name, payload)
    try
        session.options.server.on_event(event)
    catch e
        @warn "Couldn't deliver telemetry event" event_name exception=(e, catch_backtrace())
    end
    event
end

end  # module Telemetry
