"""
Extensive error handling framework for Pluto.jl.

Provides structured error categorisation, severity assessment, retry logic,
and aggregated error reporting.
"""
module ErrorHandling

export ErrorCategory, ErrorSeverity, PlutoError, ErrorLog
# ErrorCategory values
export SYNTAX_ERROR, RUNTIME_ERROR, PACKAGE_ERROR, NETWORK_ERROR
export TIMEOUT_ERROR, WORKSPACE_ERROR, CELL_ERROR, UNKNOWN_ERROR
# ErrorSeverity values
export SEVERITY_LOW, SEVERITY_MEDIUM, SEVERITY_HIGH, SEVERITY_CRITICAL
export categorize_error, assess_severity, wrap_error
export log_error!, clear_errors!, recent_errors, summarize_errors
export retry_with_backoff, is_recoverable

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

"""
High-level category for a Pluto error.
"""
@enum ErrorCategory begin
    SYNTAX_ERROR       # Julia parse / compile errors
    RUNTIME_ERROR      # General evaluation errors
    PACKAGE_ERROR      # Pkg / import related errors
    NETWORK_ERROR      # HTTP / WebSocket errors
    TIMEOUT_ERROR      # Evaluation or connection timeouts
    WORKSPACE_ERROR    # WorkspaceManager / process errors
    CELL_ERROR         # Cell-specific execution errors
    UNKNOWN_ERROR      # Anything that doesn't match above
end

"""
Severity level for a Pluto error.  Higher ordinal = more severe.
"""
@enum ErrorSeverity begin
    SEVERITY_LOW       # Informational; user can continue normally
    SEVERITY_MEDIUM    # Degraded functionality; user should act
    SEVERITY_HIGH      # Major feature broken; restart may be required
    SEVERITY_CRITICAL  # Notebook or server unusable
end

# ---------------------------------------------------------------------------
# Structs
# ---------------------------------------------------------------------------

"""
Structured representation of an error captured inside Pluto.

Fields
------
- `category`   : `ErrorCategory` classification
- `severity`   : `ErrorSeverity` level
- `message`    : Human-readable description
- `exception`  : The original `Exception` (or `nothing`)
- `stacktrace` : Captured `StackTrace` (may be empty)
- `cell_id`    : UUID string of the offending cell, or `nothing`
- `timestamp`  : `time()` at capture point
- `context`    : Arbitrary key→value metadata
"""
struct PlutoError
    category    :: ErrorCategory
    severity    :: ErrorSeverity
    message     :: String
    exception   :: Union{Exception, Nothing}
    stacktrace  :: Vector{Base.StackFrame}
    cell_id     :: Union{String, Nothing}
    timestamp   :: Float64
    context     :: Dict{String, Any}
end

"""
Ring-buffer style log of `PlutoError` values.

Fields
------
- `errors`   : Collected errors (most-recent last)
- `max_size` : Maximum number of errors to retain (oldest dropped)
"""
mutable struct ErrorLog
    errors   :: Vector{PlutoError}
    max_size :: Int
end

"""
    ErrorLog(; max_size = 100)

Create an empty `ErrorLog`.
"""
ErrorLog(; max_size::Int = 100) = ErrorLog(PlutoError[], max_size)

# ---------------------------------------------------------------------------
# Categorisation & severity
# ---------------------------------------------------------------------------

"""
    categorize_error(e) -> ErrorCategory

Inspect exception `e` and return the most appropriate `ErrorCategory`.
"""
function categorize_error(e::Exception)::ErrorCategory
    T = typeof(e)
    name = string(T)

    # Syntax / compile
    if e isa Base.Meta.ParseError || e isa LoadError || name == "UndefVarError" && contains(string(e), "syntax")
        return SYNTAX_ERROR
    end

    # Package / import
    if name in ("PkgError", "PackageError") ||
       e isa ArgumentError && (contains(e.msg, "package") || contains(e.msg, "import")) ||
       occursin("Pkg", name) ||
       e isa ErrorException && contains(e.msg, "package") ||
       (e isa LoadError && contains(string(e), "package"))
        return PACKAGE_ERROR
    end

    # Network
    if occursin("HTTP", name) || occursin("Socket", name) || occursin("Network", name) ||
       e isa Base.IOError || e isa EOFError ||
       (e isa ErrorException && (contains(e.msg, "connection") || contains(e.msg, "network")))
        return NETWORK_ERROR
    end

    # Timeout
    if occursin("Timeout", name) || occursin("timeout", name) ||
       (e isa ErrorException && contains(lowercase(e.msg), "timeout"))
        return TIMEOUT_ERROR
    end

    # Workspace
    if occursin("Workspace", name) || occursin("Process", name) ||
       (e isa ProcessFailedException)
        return WORKSPACE_ERROR
    end

    # Runtime — all other concrete evaluation errors
    if e isa MethodError || e isa UndefVarError || e isa TypeError ||
       e isa BoundsError || e isa DivideError || e isa DomainError ||
       e isa OverflowError || e isa StackOverflowError || e isa OutOfMemoryError ||
       e isa AssertionError || e isa ErrorException
        return RUNTIME_ERROR
    end

    return UNKNOWN_ERROR
end

categorize_error(::Any) = UNKNOWN_ERROR

"""
    assess_severity(e, category) -> ErrorSeverity

Return the `ErrorSeverity` for a given exception and its category.
"""
function assess_severity(e::Exception, category::ErrorCategory)::ErrorSeverity
    category == TIMEOUT_ERROR      && return SEVERITY_HIGH
    category == WORKSPACE_ERROR    && return SEVERITY_CRITICAL
    category == NETWORK_ERROR      && return SEVERITY_HIGH
    category == PACKAGE_ERROR      && return SEVERITY_MEDIUM
    category == SYNTAX_ERROR       && return SEVERITY_LOW

    # Runtime heuristics
    if category == RUNTIME_ERROR
        e isa StackOverflowError   && return SEVERITY_HIGH
        e isa OutOfMemoryError     && return SEVERITY_CRITICAL
    end

    return SEVERITY_LOW
end

assess_severity(::Any, ::ErrorCategory) = SEVERITY_LOW

# ---------------------------------------------------------------------------
# Wrapping helpers
# ---------------------------------------------------------------------------

"""
    wrap_error(e; cell_id=nothing, context=Dict{String,Any}()) -> PlutoError

Convert any throwable `e` into a `PlutoError`.  Captures the current
stacktrace automatically.
"""
function wrap_error(
    e;
    cell_id::Union{String, Nothing} = nothing,
    context::Dict{String, Any} = Dict{String, Any}()
)::PlutoError
    exc = e isa Exception ? e : ErrorException(string(e))
    category = categorize_error(exc)
    severity = assess_severity(exc, category)
    msg = sprint(showerror, exc)
    # capture_stacktrace is only meaningful inside a catch block
    st = Base.catch_stack()
    frames = isempty(st) ? Base.StackFrame[] : Base.stacktrace(st[end][2])
    PlutoError(category, severity, msg, exc, frames, cell_id, time(), context)
end

# ---------------------------------------------------------------------------
# ErrorLog operations
# ---------------------------------------------------------------------------

"""
    log_error!(log, e; cell_id=nothing, context=Dict{String,Any}()) -> PlutoError

Wrap `e` and append the result to `log`.  The oldest entry is dropped when
`log.max_size` is exceeded.  Returns the created `PlutoError`.
"""
function log_error!(
    log::ErrorLog,
    e;
    cell_id::Union{String, Nothing} = nothing,
    context::Dict{String, Any} = Dict{String, Any}()
)::PlutoError
    pe = wrap_error(e; cell_id, context)
    push!(log.errors, pe)
    if length(log.errors) > log.max_size
        deleteat!(log.errors, 1)
    end
    pe
end

"""
    clear_errors!(log)

Remove all errors from `log`.
"""
function clear_errors!(log::ErrorLog)
    empty!(log.errors)
    nothing
end

"""
    recent_errors(log; n=10) -> Vector{PlutoError}

Return up to the `n` most recent errors in `log`.
"""
function recent_errors(log::ErrorLog; n::Int = 10)::Vector{PlutoError}
    tail_start = max(1, length(log.errors) - n + 1)
    log.errors[tail_start:end]
end

"""
    summarize_errors(log) -> Dict{String,Any}

Return a summary dict with counts broken down by category and severity.
"""
function summarize_errors(log::ErrorLog)::Dict{String, Any}
    by_cat = Dict{String, Int}()
    by_sev = Dict{String, Int}()
    for e in log.errors
        cat_key = string(e.category)
        sev_key = string(e.severity)
        by_cat[cat_key] = get(by_cat, cat_key, 0) + 1
        by_sev[sev_key] = get(by_sev, sev_key, 0) + 1
    end
    Dict{String, Any}(
        "total"       => length(log.errors),
        "by_category" => by_cat,
        "by_severity" => by_sev,
        "max_size"    => log.max_size,
    )
end

# ---------------------------------------------------------------------------
# Retry helper
# ---------------------------------------------------------------------------

"""
    is_recoverable(e) -> Bool

Return `true` if the error is considered transient (worth retrying).
"""
function is_recoverable(e::Exception)::Bool
    cat = categorize_error(e)
    cat in (NETWORK_ERROR, TIMEOUT_ERROR)
end

is_recoverable(::Any) = false

"""
    retry_with_backoff(f; max_retries=3, base_delay=1.0, factor=2.0, jitter=0.1)

Call `f()` up to `max_retries` additional times if it throws a recoverable
error, using exponential back-off with optional jitter.  Re-throws the last
exception if all attempts fail.
"""
function retry_with_backoff(
    f;
    max_retries::Int    = 3,
    base_delay::Float64 = 1.0,
    factor::Float64     = 2.0,
    jitter::Float64     = 0.1,
)
    delay = base_delay
    last_exc = nothing
    for attempt in 0:max_retries
        try
            return f()
        catch e
            last_exc = e
            if !is_recoverable(e) || attempt == max_retries
                rethrow(e)
            end
            sleep(delay + jitter * rand())
            delay *= factor
        end
    end
    throw(last_exc)
end

end # module ErrorHandling
