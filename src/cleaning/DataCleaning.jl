"""
Reusable cleaning operations for basic data quality improvements in Pluto notebooks.

Provides:
- Missing value strategies (drop, fill with mean/median/mode/constant/forward/backward)
- Type casting and column normalization (min-max, z-score, robust)
- Reversible `OperationMetadata` so every change can be undone
- `preview_operation` – inspect what *would* change without modifying data
- `apply_operation`  – apply a cleaning step and return updated data + metadata
- `undo_operation`   – restore a column to its pre-operation state
"""
module DataCleaning

import Tables
import Statistics: mean, median

export MissingStrategy, NormalizationMethod
export HandleMissingOperation, CastTypeOperation, NormalizeOperation
export OperationMetadata
export preview_operation, apply_operation, undo_operation


# ---------------------------------------------------------------------------
# Enums / strategy tokens
# ---------------------------------------------------------------------------

"""
Strategy for handling missing values in a column.

| Value            | Behaviour                                          |
|------------------|----------------------------------------------------|
| `DropRows`       | Remove rows that have a missing value              |
| `FillMean`       | Replace missing with the column mean               |
| `FillMedian`     | Replace missing with the column median             |
| `FillMode`       | Replace missing with the most frequent value       |
| `FillConstant`   | Replace missing with a user-supplied constant      |
| `FillForward`    | Propagate the last non-missing value forward       |
| `FillBackward`   | Propagate the next non-missing value backward      |
"""
@enum MissingStrategy begin
    DropRows
    FillMean
    FillMedian
    FillMode
    FillConstant
    FillForward
    FillBackward
end

"""
Method used when normalizing a numeric column.

| Value                  | Formula                                          |
|------------------------|--------------------------------------------------|
| `MinMaxNormalization`  | `(x - min) / (max - min)`                       |
| `ZScoreNormalization`  | `(x - mean) / std`                              |
| `RobustNormalization`  | `(x - median) / IQR`                            |
"""
@enum NormalizationMethod begin
    MinMaxNormalization
    ZScoreNormalization
    RobustNormalization
end


# ---------------------------------------------------------------------------
# Operation descriptors
# ---------------------------------------------------------------------------

"""
    HandleMissingOperation(column, strategy[, fill_value])

Describes how to handle missing values in `column`.
`fill_value` is only used when `strategy == FillConstant`.
"""
struct HandleMissingOperation
    column::Symbol
    strategy::MissingStrategy
    fill_value::Any

    HandleMissingOperation(column::Symbol, strategy::MissingStrategy, fill_value=nothing) =
        new(column, strategy, fill_value)
end

"""
    CastTypeOperation(column, target_type)

Describes a type-conversion of every element in `column` to `target_type`.
Elements that cannot be converted are replaced with `missing`.
"""
struct CastTypeOperation
    column::Symbol
    target_type::Type
end

"""
    NormalizeOperation(column, method)

Describes a normalization of the numeric values in `column` using `method`.
"""
struct NormalizeOperation
    column::Symbol
    method::NormalizationMethod
end

const CleaningOperation = Union{HandleMissingOperation,CastTypeOperation,NormalizeOperation}


# ---------------------------------------------------------------------------
# Operation metadata – supports rollback
# ---------------------------------------------------------------------------

"""
    OperationMetadata

Records everything needed to undo a single cleaning step.

Fields
------
- `operation_type :: Symbol`   – `:handle_missing`, `:cast_type`, or `:normalize`
- `column         :: Symbol`   – the column that was modified
- `original_values`            – the column values *before* the operation
- `parameters     :: Dict{Symbol,Any}` – operation-specific parameters (e.g. strategy, method)
- `timestamp      :: Float64`  – `time()` at the moment `apply_operation` was called
"""
struct OperationMetadata
    operation_type::Symbol
    column::Symbol
    original_values::Vector{Any}
    parameters::Dict{Symbol,Any}
    timestamp::Float64
end


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

"""Extract a column from a Tables.jl-compatible object as a plain `Vector{Any}`."""
function _get_column(tbl, col::Symbol)::Vector{Any}
    cols = Tables.columns(tbl)
    Vector{Any}(Tables.getcolumn(cols, col))
end

"""Return a copy of the row-table `rows` with column `col` replaced by `new_values`."""
function _replace_column(tbl, col::Symbol, new_values::AbstractVector)
    rows = Tables.rowtable(tbl)
    map(enumerate(rows)) do (i, row)
        pairs = [c => (c === col ? new_values[i] : Tables.getcolumn(row, c))
                 for c in Tables.columnnames(row)]
        NamedTuple(pairs)
    end
end

"""Compute the statistical mode of a vector (most frequent non-missing element)."""
function _mode(v::AbstractVector)
    counts = Dict{Any,Int}()
    for x in v
        ismissing(x) && continue
        counts[x] = get(counts, x, 0) + 1
    end
    isempty(counts) && return missing
    argmax(counts)
end

"""Forward-fill: replace each `missing` with the most recent non-missing value."""
function _fill_forward(v::AbstractVector)
    out = Vector{Any}(v)
    last_valid = missing
    for i in eachindex(out)
        if !ismissing(out[i])
            last_valid = out[i]
        else
            out[i] = last_valid
        end
    end
    out
end

"""Backward-fill: replace each `missing` with the next non-missing value."""
function _fill_backward(v::AbstractVector)
    out = Vector{Any}(v)
    next_valid = missing
    for i in reverse(eachindex(out))
        if !ismissing(out[i])
            next_valid = out[i]
        else
            out[i] = next_valid
        end
    end
    out
end

"""IQR (inter-quartile range) for robust normalization."""
function _iqr(v::AbstractVector)
    nonmissing = filter(!ismissing, v)
    isempty(nonmissing) && return 0.0
    sorted = sort(nonmissing)
    n = length(sorted)
    q1_idx = max(1, round(Int, 0.25 * n + 0.5))
    q3_idx = min(n, round(Int, 0.75 * n + 0.5))
    Float64(sorted[q3_idx]) - Float64(sorted[q1_idx])
end


# ---------------------------------------------------------------------------
# Missing-value handling
# ---------------------------------------------------------------------------

function _apply_missing(col_vals::Vector{Any}, op::HandleMissingOperation)
    strategy = op.strategy

    if strategy == DropRows
        # Signal which rows to keep (non-missing)
        keep = .!ismissing.(col_vals)
        return col_vals[keep], keep
    end

    filled = Vector{Any}(col_vals)

    if strategy == FillForward
        filled = _fill_forward(filled)
    elseif strategy == FillBackward
        filled = _fill_backward(filled)
    else
        # Compute fill value
        fv = if strategy == FillConstant
            op.fill_value
        elseif strategy == FillMean
            nm = filter(!ismissing, col_vals)
            isempty(nm) ? missing : mean(Float64.(nm))
        elseif strategy == FillMedian
            nm = filter(!ismissing, col_vals)
            isempty(nm) ? missing : median(Float64.(nm))
        elseif strategy == FillMode
            _mode(col_vals)
        end

        for i in eachindex(filled)
            ismissing(filled[i]) && (filled[i] = fv)
        end
    end

    filled, trues(length(filled))   # keep all rows
end


# ---------------------------------------------------------------------------
# Type casting
# ---------------------------------------------------------------------------

function _apply_cast(col_vals::Vector{Any}, op::CastTypeOperation)
    T = op.target_type
    map(col_vals) do v
        ismissing(v) && return missing
        v isa T && return v
        try
            # For string sources, prefer `parse` when the target is a number type
            if v isa AbstractString && T <: Number
                parse(T, v)
            else
                T(v)
            end
        catch
            missing
        end
    end
end


# ---------------------------------------------------------------------------
# Normalization
# ---------------------------------------------------------------------------

function _apply_normalize(col_vals::Vector{Any}, op::NormalizeOperation)
    nm = filter(x -> !ismissing(x), col_vals)
    isempty(nm) && return col_vals

    method = op.method

    if method == MinMaxNormalization
        lo = Float64(minimum(nm))
        hi = Float64(maximum(nm))
        denom = hi - lo
        return map(col_vals) do v
            ismissing(v) ? missing : (denom ≈ 0.0 ? 0.0 : (Float64(v) - lo) / denom)
        end

    elseif method == ZScoreNormalization
        μ = mean(Float64.(nm))
        σ = length(nm) <= 1 ? 0.0 : sqrt(sum((Float64(x) - μ)^2 for x in nm) / (length(nm) - 1))
        return map(col_vals) do v
            ismissing(v) ? missing : (σ ≈ 0.0 ? 0.0 : (Float64(v) - μ) / σ)
        end

    elseif method == RobustNormalization
        med = median(Float64.(nm))
        iqr = _iqr(col_vals)
        return map(col_vals) do v
            ismissing(v) ? missing : (iqr ≈ 0.0 ? 0.0 : (Float64(v) - med) / iqr)
        end
    end
end


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

"""
    preview_operation(tbl, op) -> NamedTuple

Return a named-tuple summarising what the operation *would* do, without
modifying `tbl`.  Always returns:
```
(column, operation_type, affected_rows, sample_before, sample_after)
```
where `sample_before` / `sample_after` show the first few values.
"""
function preview_operation(tbl, op::HandleMissingOperation)
    col_vals = _get_column(tbl, op.column)
    new_vals, keep = _apply_missing(col_vals, op)

    affected = count(ismissing, col_vals)
    n = min(5, length(col_vals))
    (
        column          = op.column,
        operation_type  = :handle_missing,
        strategy        = op.strategy,
        affected_rows   = affected,
        rows_kept       = count(keep),
        sample_before   = col_vals[1:n],
        sample_after    = new_vals[1:min(n, length(new_vals))],
    )
end

function preview_operation(tbl, op::CastTypeOperation)
    col_vals = _get_column(tbl, op.column)
    new_vals = _apply_cast(col_vals, op)

    failures = count(i -> !ismissing(col_vals[i]) && ismissing(new_vals[i]), eachindex(col_vals))
    n = min(5, length(col_vals))
    (
        column          = op.column,
        operation_type  = :cast_type,
        target_type     = op.target_type,
        conversion_failures = failures,
        sample_before   = col_vals[1:n],
        sample_after    = new_vals[1:n],
    )
end

function preview_operation(tbl, op::NormalizeOperation)
    col_vals = _get_column(tbl, op.column)
    new_vals = _apply_normalize(col_vals, op)

    n = min(5, length(col_vals))
    (
        column         = op.column,
        operation_type = :normalize,
        method         = op.method,
        sample_before  = col_vals[1:n],
        sample_after   = new_vals[1:n],
    )
end


"""
    apply_operation(tbl, op) -> (new_tbl, metadata::OperationMetadata)

Apply `op` to `tbl` and return:
- the cleaned table (a `Vector` of `NamedTuple` rows – Tables.jl compatible)
- an `OperationMetadata` value that can be passed to `undo_operation` to revert
"""
function apply_operation(tbl, op::HandleMissingOperation)
    col_vals  = _get_column(tbl, op.column)
    new_vals, keep = _apply_missing(col_vals, op)

    meta = OperationMetadata(
        :handle_missing,
        op.column,
        col_vals,
        Dict{Symbol,Any}(:strategy => op.strategy, :fill_value => op.fill_value),
        time(),
    )

    rows = Tables.rowtable(tbl)
    if op.strategy == DropRows
        # Remove rows where the original column was missing
        rows = rows[keep]
        new_tbl = rows
    else
        new_tbl = _replace_column(tbl, op.column, new_vals)
    end

    new_tbl, meta
end

function apply_operation(tbl, op::CastTypeOperation)
    col_vals = _get_column(tbl, op.column)
    new_vals = _apply_cast(col_vals, op)

    meta = OperationMetadata(
        :cast_type,
        op.column,
        col_vals,
        Dict{Symbol,Any}(:target_type => op.target_type),
        time(),
    )

    _replace_column(tbl, op.column, new_vals), meta
end

function apply_operation(tbl, op::NormalizeOperation)
    col_vals = _get_column(tbl, op.column)
    new_vals = _apply_normalize(col_vals, op)

    meta = OperationMetadata(
        :normalize,
        op.column,
        col_vals,
        Dict{Symbol,Any}(:method => op.method),
        time(),
    )

    _replace_column(tbl, op.column, new_vals), meta
end


"""
    undo_operation(tbl, metadata::OperationMetadata) -> new_tbl

Restore the column recorded in `metadata` to its pre-operation values.

!!! note
    For `DropRows` operations the table may have fewer rows than the original.
    `undo_operation` cannot recover the dropped rows because `tbl` no longer
    contains them – the `original_values` stored in the metadata represent all
    rows *before* the drop, but there is no positional alignment once rows have
    been removed.  In that case a `DomainError` is thrown with an explanation.
"""
function undo_operation(tbl, meta::OperationMetadata)
    if meta.operation_type == :handle_missing &&
       get(meta.parameters, :strategy, nothing) == DropRows

        throw(DomainError(
            :DropRows,
            "Cannot undo a DropRows operation because deleted rows are no longer " *
            "present in the table.  Use the original table instead.",
        ))
    end

    n_tbl = length(Tables.rowtable(tbl))
    n_orig = length(meta.original_values)

    if n_tbl != n_orig
        throw(DomainError(
            n_tbl,
            "Table has $n_tbl rows but the stored original has $n_orig rows. " *
            "Make sure you are undoing on the correct table.",
        ))
    end

    _replace_column(tbl, meta.column, meta.original_values)
end

end # module DataCleaning
