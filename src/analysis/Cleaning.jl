module Cleaning

export MissingStrategy, DropMissing, FillConstant, FillMean, FillMedian, FillMode
export TypeOperation, CastType, NormalizeColumnNames
export CleaningOperation, CleaningPlan
export preview_operation, apply_operation, add_operation!, apply_plan, undo_last!

# ---------------------------------------------------------------------------
# Data representation
# A "cleaning table" is an OrderedDict-like structure: Symbol → Vector.
# We use a plain Dict here and preserve insertion order via a keys vector.

"""
Internal column-oriented table representation used by the Cleaning module.
Maps column names (`Symbol`) to their value vectors.
"""
struct CleaningTable
    columns::Dict{Symbol,Vector}
    column_order::Vector{Symbol}
end

CleaningTable(pairs::Pair{Symbol}...) = CleaningTable(
    Dict{Symbol,Vector}(pairs),
    [first(p) for p in pairs],
)

function CleaningTable(nt::NamedTuple)
    cols = Dict{Symbol,Vector}(k => collect(v) for (k, v) in pairs(nt))
    CleaningTable(cols, collect(keys(nt)))
end

Base.length(t::CleaningTable) = isempty(t.columns) ? 0 : length(first(values(t.columns)))
Base.getindex(t::CleaningTable, col::Symbol) = t.columns[col]
Base.haskey(t::CleaningTable, col::Symbol) = haskey(t.columns, col)
Base.keys(t::CleaningTable) = t.column_order

"""
Return a deep copy of a `CleaningTable`.
"""
function Base.copy(t::CleaningTable)
    new_cols = Dict{Symbol,Vector}(k => copy(v) for (k, v) in t.columns)
    CleaningTable(new_cols, copy(t.column_order))
end

"""
Convert a `CleaningTable` back to a `NamedTuple` of vectors.
"""
function to_namedtuple(t::CleaningTable)
    NamedTuple{Tuple(t.column_order)}(Tuple(t.columns[c] for c in t.column_order))
end

# ---------------------------------------------------------------------------
# Missing-value strategies

"""
Abstract base type for all missing-value handling strategies.
"""
abstract type MissingStrategy end

"""
    DropMissing(; columns=Symbol[])

Drop every row that contains a missing value in any of `columns`.
If `columns` is empty, checks all columns.
"""
struct DropMissing <: MissingStrategy
    "Columns to inspect; empty means all columns."
    columns::Vector{Symbol}
end
DropMissing(; columns::Vector{Symbol}=Symbol[]) = DropMissing(columns)

"""
    FillConstant(value; columns=Symbol[])

Replace `missing` entries with `value`.
If `columns` is empty, applies to all columns.
"""
struct FillConstant{T} <: MissingStrategy
    columns::Vector{Symbol}
    value::T
end
FillConstant(value; columns::Vector{Symbol}=Symbol[]) = FillConstant{typeof(value)}(columns, value)

"""
    FillMean(; columns=Symbol[])

Replace `missing` entries with the column mean (numeric columns only).
Non-numeric columns are left unchanged.
If `columns` is empty, applies to all columns.
"""
struct FillMean <: MissingStrategy
    columns::Vector{Symbol}
end
FillMean(; columns::Vector{Symbol}=Symbol[]) = FillMean(columns)

"""
    FillMedian(; columns=Symbol[])

Replace `missing` entries with the column median (numeric columns only).
If `columns` is empty, applies to all columns.
"""
struct FillMedian <: MissingStrategy
    columns::Vector{Symbol}
end
FillMedian(; columns::Vector{Symbol}=Symbol[]) = FillMedian(columns)

"""
    FillMode(; columns=Symbol[])

Replace `missing` entries with the most-frequently-occurring non-missing value.
If `columns` is empty, applies to all columns.
"""
struct FillMode <: MissingStrategy
    columns::Vector{Symbol}
end
FillMode(; columns::Vector{Symbol}=Symbol[]) = FillMode(columns)

# ---------------------------------------------------------------------------
# Type-normalization operations

"""
Abstract base type for type-casting / column-name normalization operations.
"""
abstract type TypeOperation end

"""
    CastType(target_type; columns=Symbol[])

Cast the specified columns to `target_type` using `convert`.
Missing values are preserved as `missing`.
If `columns` is empty, attempts to cast all columns.
"""
struct CastType <: TypeOperation
    columns::Vector{Symbol}
    target_type::Type
end
CastType(T::Type; columns::Vector{Symbol}=Symbol[]) = CastType(columns, T)

"""
    NormalizeColumnNames()

Rename every column: lowercase its name and replace spaces / hyphens with underscores.
"""
struct NormalizeColumnNames <: TypeOperation end

# ---------------------------------------------------------------------------
# Operation = MissingStrategy | TypeOperation

const AnyOperation = Union{MissingStrategy,TypeOperation}

# ---------------------------------------------------------------------------
# CleaningOperation – reversible metadata

"""
    CleaningOperation

Metadata record for a single cleaning step.

Fields
------
- `id`          – unique identifier (UUID-style string).
- `description` – human-readable summary of what was done.
- `operation`   – the `MissingStrategy` or `TypeOperation` that was applied.
- `timestamp`   – `time()` value when the operation was created.
- `snapshot`    – a deep copy of the `CleaningTable` *before* the operation was
                  applied, enabling full rollback.
"""
struct CleaningOperation
    id::String
    description::String
    operation::AnyOperation
    timestamp::Float64
    snapshot::CleaningTable
end

function _new_id()
    # Construct a simple unique id without external packages.
    string(round(Int, time() * 1e6); base=36) * "-" * string(rand(UInt32); base=36)
end

# ---------------------------------------------------------------------------
# CleaningPlan

"""
    CleaningPlan

An ordered sequence of `CleaningOperation` records.
Use `add_operation!` to append operations and `undo_last!` to remove the most
recent one and retrieve the pre-operation snapshot.
"""
mutable struct CleaningPlan
    operations::Vector{CleaningOperation}
end
CleaningPlan() = CleaningPlan(CleaningOperation[])

# ---------------------------------------------------------------------------
# Helpers

function _target_columns(t::CleaningTable, cols::Vector{Symbol})
    isempty(cols) ? copy(t.column_order) : cols
end

function _column_mean(v::Vector)
    vals = collect(skipmissing(v))
    isempty(vals) && return missing
    try
        sum(float.(vals)) / length(vals)
    catch
        missing
    end
end

function _column_median(v::Vector)
    vals = sort(collect(skipmissing(v)))
    isempty(vals) && return missing
    try
        n = length(vals)
        fv = float.(vals)
        isodd(n) ? fv[div(n, 2) + 1] : (fv[div(n, 2)] + fv[div(n, 2) + 1]) / 2
    catch
        missing
    end
end

function _column_mode(v::Vector)
    vals = collect(skipmissing(v))
    isempty(vals) && return missing
    freq = Dict{Any,Int}()
    for val in vals
        freq[val] = get(freq, val, 0) + 1
    end
    argmax(freq)
end

function _fill_column(col::Vector, fill_val)
    [ismissing(x) ? fill_val : x for x in col]
end

function _normalize_name(name::Symbol)::Symbol
    s = lowercase(String(name))
    s = replace(s, r"[ \-]+" => "_")
    Symbol(s)
end

# ---------------------------------------------------------------------------
# apply_operation – mutates a copy of the table

"""
    apply_operation(data::CleaningTable, op::DropMissing) -> CleaningTable

Return a new `CleaningTable` with rows removed wherever a targeted column has a
missing value.
"""
function apply_operation(data::CleaningTable, op::DropMissing)::CleaningTable
    result = copy(data)
    cols = _target_columns(data, op.columns)
    nrows = length(data)
    # build keep-mask
    keep = trues(nrows)
    for col in cols
        haskey(data, col) || continue
        v = data[col]
        for i in 1:nrows
            if ismissing(v[i])
                keep[i] = false
            end
        end
    end
    for col in result.column_order
        result.columns[col] = result.columns[col][keep]
    end
    result
end

"""
    apply_operation(data::CleaningTable, op::FillConstant) -> CleaningTable

Return a new `CleaningTable` with missing values replaced by `op.value`.
"""
function apply_operation(data::CleaningTable, op::FillConstant)::CleaningTable
    result = copy(data)
    cols = _target_columns(data, op.columns)
    for col in cols
        haskey(result, col) || continue
        result.columns[col] = _fill_column(result.columns[col], op.value)
    end
    result
end

"""
    apply_operation(data::CleaningTable, op::FillMean) -> CleaningTable

Return a new `CleaningTable` with missing values replaced by each column's mean.
"""
function apply_operation(data::CleaningTable, op::FillMean)::CleaningTable
    result = copy(data)
    cols = _target_columns(data, op.columns)
    for col in cols
        haskey(result, col) || continue
        fill_val = _column_mean(result.columns[col])
        ismissing(fill_val) && continue
        result.columns[col] = _fill_column(result.columns[col], fill_val)
    end
    result
end

"""
    apply_operation(data::CleaningTable, op::FillMedian) -> CleaningTable

Return a new `CleaningTable` with missing values replaced by each column's median.
"""
function apply_operation(data::CleaningTable, op::FillMedian)::CleaningTable
    result = copy(data)
    cols = _target_columns(data, op.columns)
    for col in cols
        haskey(result, col) || continue
        fill_val = _column_median(result.columns[col])
        ismissing(fill_val) && continue
        result.columns[col] = _fill_column(result.columns[col], fill_val)
    end
    result
end

"""
    apply_operation(data::CleaningTable, op::FillMode) -> CleaningTable

Return a new `CleaningTable` with missing values replaced by each column's mode.
"""
function apply_operation(data::CleaningTable, op::FillMode)::CleaningTable
    result = copy(data)
    cols = _target_columns(data, op.columns)
    for col in cols
        haskey(result, col) || continue
        fill_val = _column_mode(result.columns[col])
        ismissing(fill_val) && continue
        result.columns[col] = _fill_column(result.columns[col], fill_val)
    end
    result
end

function _cast_value(::Type{T}, x) where {T}
    ismissing(x) && return missing
    x isa T && return x
    if T <: Number && x isa AbstractString
        return parse(T, x)
    end
    return convert(T, x)
end

"""
    apply_operation(data::CleaningTable, op::CastType) -> CleaningTable

Return a new `CleaningTable` with the targeted columns cast to `op.target_type`.
Missing values are preserved; string values are parsed when the target is a numeric type.
"""
function apply_operation(data::CleaningTable, op::CastType)::CleaningTable
    result = copy(data)
    cols = _target_columns(data, op.columns)
    T = op.target_type
    for col in cols
        haskey(result, col) || continue
        result.columns[col] = [_cast_value(T, x) for x in result.columns[col]]
    end
    result
end

"""
    apply_operation(data::CleaningTable, op::NormalizeColumnNames) -> CleaningTable

Return a new `CleaningTable` with column names lowercased and whitespace/hyphens
replaced by underscores.
"""
function apply_operation(data::CleaningTable, op::NormalizeColumnNames)::CleaningTable
    new_cols = Dict{Symbol,Vector}()
    new_order = Symbol[]
    for col in data.column_order
        new_name = _normalize_name(col)
        new_cols[new_name] = copy(data.columns[col])
        push!(new_order, new_name)
    end
    CleaningTable(new_cols, new_order)
end

# ---------------------------------------------------------------------------
# preview_operation

"""
    PreviewResult

Summary returned by `preview_operation`.

Fields
------
- `affected_rows`     – number of rows modified (or -1 when not row-based, e.g. column rename).
- `affected_columns`  – column names that would be changed.
- `description`       – human-readable explanation.
- `sample_before`     – up to 5 representative original values (per affected column).
- `sample_after`      – corresponding values after the operation.
"""
struct PreviewResult
    affected_rows::Int
    affected_columns::Vector{Symbol}
    description::String
    sample_before::Dict{Symbol,Vector}
    sample_after::Dict{Symbol,Vector}
end

"""
    preview_operation(data::CleaningTable, op) -> PreviewResult

Return a `PreviewResult` describing what `apply_operation(data, op)` would change
without modifying `data`.
"""
function preview_operation(data::CleaningTable, op::DropMissing)::PreviewResult
    cols = _target_columns(data, op.columns)
    nrows = length(data)
    keep = trues(nrows)
    for col in cols
        haskey(data, col) || continue
        v = data[col]
        for i in 1:nrows
            ismissing(v[i]) && (keep[i] = false)
        end
    end
    dropped = sum(.!keep)
    affected_cols = filter(c -> haskey(data, c), cols)
    # sample: up to 5 rows that would be dropped
    drop_indices = dropped > 0 ? findall(.!keep)[1:min(5, dropped)] : Int[]
    sb = Dict{Symbol,Vector}(c => data[c][drop_indices] for c in affected_cols)
    PreviewResult(
        dropped,
        affected_cols,
        "DropMissing: would remove $dropped row(s) out of $nrows.",
        sb,
        Dict{Symbol,Vector}(),  # after = nothing (rows are removed)
    )
end

function preview_operation(data::CleaningTable, op::Union{FillConstant,FillMean,FillMedian,FillMode})::PreviewResult
    result = apply_operation(data, op)
    cols = _target_columns(data, op.columns)
    candidate_cols = filter(c -> haskey(data, c), cols)

    total_filled = 0
    affected_cols = Symbol[]
    sb = Dict{Symbol,Vector}()
    sa = Dict{Symbol,Vector}()
    for col in candidate_cols
        before_v = data[col]
        after_v  = result[col]
        missing_indices = findall(ismissing, before_v)
        isempty(missing_indices) && continue
        push!(affected_cols, col)
        total_filled += length(missing_indices)
        idx = missing_indices[1:min(5, length(missing_indices))]
        sb[col] = before_v[idx]
        sa[col] = after_v[idx]
    end

    desc = "$(typeof(op).name.name): would fill $total_filled missing value(s) across $(length(affected_cols)) column(s)."
    PreviewResult(total_filled, affected_cols, desc, sb, sa)
end

function preview_operation(data::CleaningTable, op::CastType)::PreviewResult
    cols = _target_columns(data, op.columns)
    affected_cols = filter(c -> haskey(data, c), cols)
    result = apply_operation(data, op)
    n = min(5, length(data))
    sb = Dict{Symbol,Vector}(c => data[c][1:n] for c in affected_cols)
    sa = Dict{Symbol,Vector}(c => result[c][1:n] for c in affected_cols)
    desc = "CastType: would cast $(length(affected_cols)) column(s) to $(op.target_type)."
    PreviewResult(-1, affected_cols, desc, sb, sa)
end

function preview_operation(data::CleaningTable, op::NormalizeColumnNames)::PreviewResult
    old_names = data.column_order
    new_names = [_normalize_name(n) for n in old_names]
    changed = [(o, n) for (o, n) in zip(old_names, new_names) if o != n]
    desc = "NormalizeColumnNames: would rename $(length(changed)) column(s)."
    PreviewResult(
        -1,
        first.(changed),
        desc,
        Dict{Symbol,Vector}(o => [String(o)] for (o, _) in changed),
        Dict{Symbol,Vector}(o => [String(n)] for (o, n) in changed),
    )
end

# ---------------------------------------------------------------------------
# CleaningPlan helpers

function _describe(op::DropMissing)
    cols = isempty(op.columns) ? "all columns" : join(op.columns, ", ")
    "Drop rows with missing values in: $cols"
end
function _describe(op::FillConstant)
    cols = isempty(op.columns) ? "all columns" : join(op.columns, ", ")
    "Fill missing values with $(repr(op.value)) in: $cols"
end
function _describe(op::FillMean)
    cols = isempty(op.columns) ? "all columns" : join(op.columns, ", ")
    "Fill missing values with column mean in: $cols"
end
function _describe(op::FillMedian)
    cols = isempty(op.columns) ? "all columns" : join(op.columns, ", ")
    "Fill missing values with column median in: $cols"
end
function _describe(op::FillMode)
    cols = isempty(op.columns) ? "all columns" : join(op.columns, ", ")
    "Fill missing values with column mode in: $cols"
end
function _describe(op::CastType)
    cols = isempty(op.columns) ? "all columns" : join(op.columns, ", ")
    "Cast to $(op.target_type) in: $cols"
end
_describe(::NormalizeColumnNames) = "Normalize column names"

"""
    add_operation!(plan::CleaningPlan, data::CleaningTable, op) -> CleaningTable

Apply `op` to `data`, record a `CleaningOperation` (with a snapshot for undo)
in `plan`, and return the new `CleaningTable`.
"""
function add_operation!(plan::CleaningPlan, data::CleaningTable, op::AnyOperation)::CleaningTable
    snapshot = copy(data)
    result = apply_operation(data, op)
    record = CleaningOperation(
        _new_id(),
        _describe(op),
        op,
        time(),
        snapshot,
    )
    push!(plan.operations, record)
    result
end

"""
    apply_plan(data::CleaningTable, plan::CleaningPlan) -> CleaningTable

Re-apply all operations in `plan` to `data` in order and return the final table.
`plan` is not modified.
"""
function apply_plan(data::CleaningTable, plan::CleaningPlan)::CleaningTable
    result = data
    for rec in plan.operations
        result = apply_operation(result, rec.operation)
    end
    result
end

"""
    undo_last!(plan::CleaningPlan) -> Union{CleaningTable, Nothing}

Remove the most-recent operation from `plan` and return the snapshot taken
just before that operation was applied (i.e. the table state before it).
Returns `nothing` if `plan` is empty.
"""
function undo_last!(plan::CleaningPlan)::Union{CleaningTable,Nothing}
    isempty(plan.operations) && return nothing
    last_op = pop!(plan.operations)
    last_op.snapshot
end

end # module Cleaning
