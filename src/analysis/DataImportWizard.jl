module DataImportWizard

export ImportFormat, CSV_FORMAT, TSV_FORMAT, PARQUET_FORMAT, ARROW_FORMAT, JSON_FORMAT
export ImportOptions, generate_import_code, detect_format, default_options

"""
Supported dataset import formats.
"""
@enum ImportFormat begin
    CSV_FORMAT
    TSV_FORMAT
    PARQUET_FORMAT
    ARROW_FORMAT
    JSON_FORMAT
end

"""
Options controlling how a dataset is read and how the import snippet is generated.

Fields common to all formats:
- `encoding`:        File encoding, e.g. `"UTF-8"` (default) or `"Latin-1"`.

CSV / TSV options:
- `delimiter`:       Column separator character. Defaults to `','` for CSV and `'\\t'` for TSV.
- `has_header`:      Whether the first row contains column names (default `true`).
- `comment`:         Character that marks a comment line (`nothing` = disabled).
- `missingstring`:   String that should be read as `missing` (`nothing` = use CSV.jl default).
- `dateformat`:      `DateFormat`-compatible string, e.g. `"yyyy-mm-dd"` (`nothing` = auto).
- `types`:           Mapping from column name to Julia type string, e.g.
                     `Dict("age" => "Int64", "name" => "String")`.
- `limit`:           Maximum number of rows to read (`nothing` = all rows).
- `skipto`:          First data row index (1-based, `nothing` = auto).

Parquet options:
- `columns`:         Subset of column names to read (`nothing` = all columns).

Arrow options:
- `ntasks`:          Number of parallel tasks for reading (`nothing` = Julia default).

JSON options:
- `json_type`:       Expected top-level JSON structure: `"object"`, `"array"`, or `"auto"`.
- `struct_type`:     Julia type to materialise each record into: `"NamedTuple"` or `"Dict"`.
"""
Base.@kwdef struct ImportOptions
    encoding::String           = "UTF-8"
    delimiter::Char            = ','
    has_header::Bool           = true
    comment::Union{Char,Nothing}   = nothing
    missingstring::Union{String,Nothing} = nothing
    dateformat::Union{String,Nothing}    = nothing
    types::Union{Dict{String,String},Nothing} = nothing
    limit::Union{Int,Nothing}  = nothing
    skipto::Union{Int,Nothing} = nothing
    columns::Union{Vector{String},Nothing} = nothing
    ntasks::Union{Int,Nothing} = nothing
    json_type::String          = "auto"
    struct_type::String        = "NamedTuple"
end

# ---------------------------------------------------------------------------
# detect_format
# ---------------------------------------------------------------------------

"""
    detect_format(filepath::AbstractString) -> ImportFormat

Infer the `ImportFormat` from the file extension of *filepath*.
Raises an `ArgumentError` if the extension is not recognised.
"""
function detect_format(filepath::AbstractString)::ImportFormat
    ext = lowercase(last(splitext(filepath)))
    if ext == ".csv"
        return CSV_FORMAT
    elseif ext == ".tsv"
        return TSV_FORMAT
    elseif ext == ".parquet"
        return PARQUET_FORMAT
    elseif ext == ".arrow" || ext == ".feather"
        return ARROW_FORMAT
    elseif ext == ".json" || ext == ".jsonl" || ext == ".ndjson"
        return JSON_FORMAT
    else
        throw(ArgumentError("Unsupported file extension: $(repr(ext))"))
    end
end

# ---------------------------------------------------------------------------
# default_options
# ---------------------------------------------------------------------------

"""
    default_options(format::ImportFormat) -> ImportOptions

Return sensible default `ImportOptions` for *format*.
"""
function default_options(format::ImportFormat)::ImportOptions
    if format == CSV_FORMAT
        return ImportOptions(delimiter=',')
    elseif format == TSV_FORMAT
        return ImportOptions(delimiter='\t')
    elseif format == PARQUET_FORMAT
        return ImportOptions()
    elseif format == ARROW_FORMAT
        return ImportOptions()
    elseif format == JSON_FORMAT
        return ImportOptions(json_type="array", struct_type="NamedTuple")
    else
        return ImportOptions()
    end
end

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_repr_string(s::AbstractString) = repr(s)
_repr_char(c::Char) = repr(c)

function _csv_kwargs(opts::ImportOptions, fmt::ImportFormat)::String
    pairs = Pair[]

    # delimiter – only emit when not the default for the format
    default_delim = fmt == TSV_FORMAT ? '\t' : ','
    if opts.delimiter != default_delim
        push!(pairs, "delim" => _repr_char(opts.delimiter))
    elseif fmt == TSV_FORMAT
        push!(pairs, "delim" => _repr_char('\t'))
    end

    opts.has_header || push!(pairs, "header" => "false")

    opts.comment !== nothing &&
        push!(pairs, "comment" => _repr_char(opts.comment))

    if opts.missingstring !== nothing
        push!(pairs, "missingstring" => _repr_string(opts.missingstring))
    end

    opts.dateformat !== nothing &&
        push!(pairs, "dateformat" => _repr_string(opts.dateformat))

    if opts.types !== nothing && !isempty(opts.types)
        type_dict = join(
            ["$(repr(k)) => $(v)" for (k, v) in sort(collect(opts.types), by=first)],
            ", "
        )
        push!(pairs, "types" => "Dict($(type_dict))")
    end

    opts.limit !== nothing  && push!(pairs, "limit"  => string(opts.limit))
    opts.skipto !== nothing && push!(pairs, "skipto" => string(opts.skipto))

    join(["$(k)=$(v)" for (k, v) in pairs], ", ")
end

# ---------------------------------------------------------------------------
# generate_import_code
# ---------------------------------------------------------------------------

"""
    generate_import_code(source::AbstractString,
                         format::ImportFormat,
                         options::ImportOptions = default_options(format)) -> String

Return a Julia code snippet (as a `String`) that reads the dataset at *source*
using the given *format* and *options*.

The generated code:
- `using`-imports the required package(s).
- Reads the data into a variable named `df` (DataFrames-based formats) or `data` (JSON).
- Uses only options that differ from their defaults so that the snippet stays concise.
"""
function generate_import_code(
    source::AbstractString,
    format::ImportFormat,
    options::ImportOptions = default_options(format),
)::String
    if format == CSV_FORMAT
        return _gen_csv(source, options, CSV_FORMAT)
    elseif format == TSV_FORMAT
        return _gen_csv(source, options, TSV_FORMAT)
    elseif format == PARQUET_FORMAT
        return _gen_parquet(source, options)
    elseif format == ARROW_FORMAT
        return _gen_arrow(source, options)
    elseif format == JSON_FORMAT
        return _gen_json(source, options)
    else
        throw(ArgumentError("Unknown format: $(format)"))
    end
end

# -- CSV / TSV ---------------------------------------------------------------

function _gen_csv(source::AbstractString, opts::ImportOptions, fmt::ImportFormat)::String
    src = _repr_string(source)
    kwargs_str = _csv_kwargs(opts, fmt)
    call = isempty(kwargs_str) ? "CSV.read($(src), DataFrame)" :
                                 "CSV.read($(src), DataFrame; $(kwargs_str))"
    """using CSV, DataFrames

df = $(call)"""
end

# -- Parquet -----------------------------------------------------------------

function _gen_parquet(source::AbstractString, opts::ImportOptions)::String
    src = _repr_string(source)
    col_arg = ""
    if opts.columns !== nothing && !isempty(opts.columns)
        cols = join(["\"$(c)\"" for c in opts.columns], ", ")
        col_arg = "; columns=[$(cols)]"
    end
    """using Parquet2, DataFrames

df = DataFrame(Parquet2.Dataset($(src))$(col_arg))"""
end

# -- Arrow -------------------------------------------------------------------

function _gen_arrow(source::AbstractString, opts::ImportOptions)::String
    src = _repr_string(source)
    task_arg = opts.ntasks !== nothing ? "; ntasks=$(opts.ntasks)" : ""
    """using Arrow, DataFrames

df = Arrow.Table($(src)$(task_arg)) |> DataFrame"""
end

# -- JSON --------------------------------------------------------------------

function _gen_json(source::AbstractString, opts::ImportOptions)::String
    src = _repr_string(source)
    type_hint = if opts.struct_type == "Dict"
        "Dict{String, Any}"
    else
        "NamedTuple"
    end

    if opts.json_type == "object"
        """using JSON3

data = open($(src), "r") do io
    JSON3.read(io, $(type_hint))
end"""
    elseif opts.json_type == "array"
        """using JSON3

data = open($(src), "r") do io
    JSON3.read(io, Vector{$(type_hint)})
end"""
    else  # "auto"
        """using JSON3

data = open($(src), "r") do io
    JSON3.read(io)
end"""
    end
end

end # module DataImportWizard
