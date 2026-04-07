module DatasetProfiler

import Tables

"""
    ColumnProfile

Statistics and metadata for a single column of a dataset.

Fields:
- `name`: column name
- `eltype`: element type (as a String)
- `n_rows`: total number of rows
- `n_missing`: number of missing values
- `missingness`: fraction of missing values in [0, 1]
- `n_unique`: number of distinct non-missing values
- `uniqueness`: fraction of distinct non-missing values (relative to non-missing rows)
- `min`: minimum value (numeric columns only, otherwise `nothing`)
- `max`: maximum value (numeric columns only, otherwise `nothing`)
- `mean`: arithmetic mean (numeric columns only, otherwise `nothing`)
- `std`: standard deviation (numeric columns only, otherwise `nothing`)
- `median`: median value (numeric columns only, otherwise `nothing`)
- `top_values`: up to 5 most-frequent values and their counts (categorical/non-numeric columns)
"""
struct ColumnProfile
    name::String
    eltype::String
    n_rows::Int
    n_missing::Int
    missingness::Float64
    n_unique::Int
    uniqueness::Float64
    min::Union{Nothing, Float64}
    max::Union{Nothing, Float64}
    mean::Union{Nothing, Float64}
    std::Union{Nothing, Float64}
    median::Union{Nothing, Float64}
    top_values::Vector{Pair{String, Int}}
end

"""
    DatasetProfile

Profiling summary for an entire tabular dataset.

Fields:
- `n_rows`: number of rows
- `n_cols`: number of columns
- `columns`: vector of `ColumnProfile` for each column
"""
struct DatasetProfile
    n_rows::Int
    n_cols::Int
    columns::Vector{ColumnProfile}
end

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_is_missing(x) = ismissing(x)

function _count_missing(col)
    count(_is_missing, col)
end

function _nonmissing(col)
    filter(!_is_missing, col)
end

function _is_numeric(T::Type)
    T <: Real && !(T <: Bool)
end

function _is_numeric_col(col)
    T = eltype(col)
    # Strip Missing from the union type if present
    if T isa Union
        types = Base.uniontypes(T)
        non_missing_types = filter(t -> t !== Missing, types)
        return length(non_missing_types) == 1 && _is_numeric(non_missing_types[1])
    end
    _is_numeric(T)
end

function _numeric_stats(vals::AbstractVector)
    if isempty(vals)
        return (min=nothing, max=nothing, mean=nothing, std=nothing, median=nothing)
    end
    fvals = Float64.(vals)
    n = length(fvals)
    mu = sum(fvals) / n
    sigma = n > 1 ? sqrt(sum((x - mu)^2 for x in fvals) / (n - 1)) : 0.0
    sorted = sort(fvals)
    med = if isodd(n)
        sorted[(n + 1) ÷ 2]
    else
        (sorted[n ÷ 2] + sorted[n ÷ 2 + 1]) / 2.0
    end
    return (
        min=Float64(minimum(fvals)),
        max=Float64(maximum(fvals)),
        mean=mu,
        std=sigma,
        median=med,
    )
end

function _top_values(col, n::Int=5)
    counts = Dict{String, Int}()
    for val in col
        _is_missing(val) && continue
        k = string(val)
        counts[k] = get(counts, k, 0) + 1
    end
    sorted = sort(collect(counts), by=p -> -p.second)
    Pair{String, Int}[k => v for (k, v) in sorted[1:min(n, length(sorted))]]
end

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

"""
    profile_column(name, col) -> ColumnProfile

Compute statistics for a single column vector `col` with the given `name`.
The column may contain `missing` values.
"""
function profile_column(name, col)::ColumnProfile
    n_rows = length(col)
    n_missing = _count_missing(col)
    missingness = n_rows > 0 ? n_missing / n_rows : 0.0

    nonmissing = _nonmissing(col)
    n_nonmissing = length(nonmissing)
    n_unique = length(Set(nonmissing))
    uniqueness = n_nonmissing > 0 ? n_unique / n_nonmissing : 0.0

    T = eltype(col)

    if _is_numeric_col(col)
        stats = _numeric_stats(nonmissing)
        return ColumnProfile(
            string(name),
            string(T),
            n_rows,
            n_missing,
            missingness,
            n_unique,
            uniqueness,
            stats.min,
            stats.max,
            stats.mean,
            stats.std,
            stats.median,
            Pair{String, Int}[],
        )
    else
        top = _top_values(col)
        return ColumnProfile(
            string(name),
            string(T),
            n_rows,
            n_missing,
            missingness,
            n_unique,
            uniqueness,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            top,
        )
    end
end

"""
    profile_dataset(table) -> DatasetProfile

Profile a tabular dataset. Accepts any object that implements the
[Tables.jl](https://tables.juliadata.org/) interface (e.g. a `DataFrame`,
a `NamedTuple` of vectors, or a `Vector` of `NamedTuple`s).

Returns a `DatasetProfile` with per-column statistics suitable for
consumption by prompt templates via `serialize_profile`.
"""
function profile_dataset(table)::DatasetProfile
    if !Tables.istable(table)
        throw(ArgumentError("profile_dataset: argument does not implement the Tables.jl interface"))
    end
    cols = Tables.columns(table)
    names = Tables.columnnames(cols)
    col_profiles = ColumnProfile[
        profile_column(n, Tables.getcolumn(cols, n))
        for n in names
    ]
    n_rows = isempty(col_profiles) ? 0 : col_profiles[1].n_rows
    return DatasetProfile(n_rows, length(col_profiles), col_profiles)
end

"""
    serialize_profile(profile::DatasetProfile) -> String

Serialize a `DatasetProfile` to a human-readable text summary suitable for
inclusion in a prompt template or LLM context.
"""
function serialize_profile(profile::DatasetProfile)::String
    io = IOBuffer()
    println(io, "Dataset: $(profile.n_rows) rows × $(profile.n_cols) columns")
    println(io)
    for col in profile.columns
        println(io, "Column: $(col.name)")
        println(io, "  Type       : $(col.eltype)")
        println(io, "  Missing    : $(col.n_missing)/$(col.n_rows) ($(round(col.missingness * 100; digits=1))%)")
        println(io, "  Unique     : $(col.n_unique) ($(round(col.uniqueness * 100; digits=1))% of non-missing)")
        if col.min !== nothing
            println(io, "  Min        : $(col.min)")
            println(io, "  Max        : $(col.max)")
            println(io, "  Mean       : $(round(col.mean; digits=4))")
            println(io, "  Std        : $(round(col.std; digits=4))")
            println(io, "  Median     : $(col.median)")
        elseif !isempty(col.top_values)
            top_str = join(["$(k) ($(v))" for (k, v) in col.top_values], ", ")
            println(io, "  Top values : $(top_str)")
        end
        println(io)
    end
    String(take!(io))
end

end # module DatasetProfiler
