"""
Versioned prompt templates for key analysis intents in Pluto notebooks.

Templates cover:
- Import assistance
- Data cleaning
- Exploratory Data Analysis (EDA) and visualization suggestions
"""
module PromptTemplates

export TemplateSection
export import_template, cleaning_template, eda_template

# ── Template version constants ──────────────────────────────────────────────

const IMPORT_TEMPLATE_VERSION  = v"1.0.0"
const CLEANING_TEMPLATE_VERSION = v"1.0.0"
const EDA_TEMPLATE_VERSION     = v"1.0.0"

# ── Core data structure ───────────────────────────────────────────────────────

"""
    TemplateSection(title, content, version)

A single structured section produced by a prompt template.

- `title`   – short human-readable heading
- `content` – the body text / code snippet for this section
- `version` – the template version that produced this section
"""
struct TemplateSection
    title::String
    content::String
    version::VersionNumber
end

# ── Helpers ───────────────────────────────────────────────────────────────────

# ── Import Assistance Template ────────────────────────────────────────────────

"""
    import_template(; file_path, file_type, separator, encoding, has_header) -> Vector{TemplateSection}

Return a structured set of prompt sections that guide a user through loading
a data file in Julia / Pluto.

# Keyword arguments
- `file_path`  – path to the data file (optional)
- `file_type`  – format hint, e.g. `"csv"`, `"xlsx"`, `"json"`, `"parquet"` (optional)
- `separator`  – column separator for delimited files, e.g. `","`, `";"`, `"\\t"` (optional)
- `encoding`   – file encoding hint, defaults to `"UTF-8"`
- `has_header` – whether the first row is a header (`true` / `false`)

# Returns
A `Vector{TemplateSection}` with sections:
1. **Overview** – summary of what will be imported and inferred format
2. **Suggested Code** – ready-to-run Julia snippet
3. **Notes** – caveats and next steps
"""
function import_template(;
    file_path::Union{String,Nothing}  = nothing,
    file_type::Union{String,Nothing}  = nothing,
    separator::Union{String,Nothing}  = nothing,
    encoding::String                  = "UTF-8",
    has_header::Bool                  = true,
)::Vector{TemplateSection}
    v = IMPORT_TEMPLATE_VERSION

    # ── infer file type from extension when not provided ──────────────────────
    inferred_type = if file_type !== nothing
        lowercase(file_type)
    elseif file_path !== nothing
        ext = lowercase(last(splitext(file_path)))
        ext in (".csv", ".tsv", ".txt", ".xlsx", ".xls",
                ".json", ".parquet", ".arrow", ".feather") ? String(lstrip(ext, '.')) : "unknown"
    else
        "unknown"
    end

    # ── section 1: overview ───────────────────────────────────────────────────
    overview_lines = String[]
    push!(overview_lines, "Detected format: **$(inferred_type)**")
    push!(overview_lines, "Encoding: $(encoding)")
    if file_path !== nothing
        push!(overview_lines, "File: `$(file_path)`")
    end
    if separator !== nothing
        push!(overview_lines, "Separator: `$(repr(separator))`")
    end
    push!(overview_lines, "Header row: $(has_header ? "yes" : "no")")
    overview = TemplateSection("Overview", join(overview_lines, "\n"), v)

    # ── section 2: suggested code ─────────────────────────────────────────────
    code = _import_code(inferred_type, file_path, separator, encoding, has_header)
    suggested = TemplateSection("Suggested Code", code, v)

    # ── section 3: notes ──────────────────────────────────────────────────────
    notes = _import_notes(inferred_type)
    note_section = TemplateSection("Notes", notes, v)

    return [overview, suggested, note_section]
end

function _import_code(
    file_type::String,
    file_path::Union{String,Nothing},
    separator::Union{String,Nothing},
    encoding::String,
    has_header::Bool,
)::String
    fp = file_path !== nothing ? "\"$(file_path)\"" : "\"path/to/your/file\""
    header_arg = has_header ? "" : ", header=false"
    enc_arg = encoding == "UTF-8" ? "" : ", encoding=\"$(encoding)\""

    if file_type in ("csv", "tsv", "txt")
        sep_arg = if separator !== nothing
            ", delim='$(separator)'"
        elseif file_type == "tsv"
            ", delim='\\t'"
        else
            ""
        end
        return """using CSV, DataFrames
df = CSV.read($(fp), DataFrame$(sep_arg)$(header_arg)$(enc_arg))"""

    elseif file_type in ("xlsx", "xls")
        return """using XLSX, DataFrames
xf = XLSX.readxlsx($(fp))
df = DataFrame(XLSX.eachtablerow(xf[XLSX.sheetnames(xf)[1]]))"""

    elseif file_type == "json"
        return """using JSON3, DataFrames
raw = open($(fp)) do io JSON3.read(io) end
df = DataFrame(raw)"""

    elseif file_type in ("parquet",)
        return """using Parquet2, DataFrames
ds = Parquet2.Dataset($(fp))
df = DataFrame(ds; copycols=true)"""

    elseif file_type in ("arrow", "feather")
        return """using Arrow, DataFrames
df = DataFrame(Arrow.Table($(fp)))"""

    else
        return """# Could not detect file format automatically.
# For CSV-like files:
using CSV, DataFrames
df = CSV.read($(fp), DataFrame)"""
    end
end

function _import_notes(file_type::String)::String
    common = """- Preview the first rows with `first(df, 5)`.
- Check column types with `describe(df)`.
- Use `nrow(df)` / `ncol(df)` to inspect dimensions."""

    specific = if file_type in ("csv", "tsv", "txt")
        "- If parsing fails, try passing `missingstring=\"NA\"` or adjusting `delim`."
    elseif file_type in ("xlsx", "xls")
        "- Specify a sheet name with `xf[\"Sheet1\"]` if the default sheet is wrong."
    elseif file_type == "json"
        "- For JSON arrays of objects, `DataFrame(raw)` works; for nested structures consider `JSON3.read` + manual flattening."
    elseif file_type in ("parquet", "arrow", "feather")
        "- Column names and types are embedded in the file metadata and are read automatically."
    else
        "- Inspect the raw file content to determine the correct parsing approach."
    end

    return "$(common)\n$(specific)"
end

# ── Data Cleaning Template ─────────────────────────────────────────────────────

"""
    cleaning_template(; column_names, column_types, missing_counts, duplicate_rows) -> Vector{TemplateSection}

Return a structured set of prompt sections that guide a user through cleaning
a dataset loaded into a `DataFrame`.

# Keyword arguments
- `column_names`   – vector of column names (`String`)
- `column_types`   – vector of inferred element types (as `String`, e.g. `"Int64"`, `"String"`)
- `missing_counts` – number of missing values per column (same order as `column_names`)
- `duplicate_rows` – total number of duplicate rows detected

# Returns
A `Vector{TemplateSection}` with sections:
1. **Overview** – dataset summary and detected issues
2. **Missing Values** – suggestions for handling `missing`
3. **Type Corrections** – columns that may need re-typing
4. **Deduplication** – code snippet to remove duplicate rows
5. **Suggested Code** – consolidated cleaning script
"""
function cleaning_template(;
    column_names::AbstractVector{<:AbstractString}   = String[],
    column_types::AbstractVector{<:AbstractString}   = String[],
    missing_counts::AbstractVector{<:Integer}        = Int[],
    duplicate_rows::Integer                          = 0,
)::Vector{TemplateSection}
    v = CLEANING_TEMPLATE_VERSION
    n_cols = length(column_names)

    # ── section 1: overview ───────────────────────────────────────────────────
    total_missing = isempty(missing_counts) ? 0 : sum(missing_counts)
    overview_parts = [
        "Columns: $(n_cols)",
        "Total missing values: $(total_missing)",
        "Duplicate rows detected: $(duplicate_rows)",
    ]
    overview = TemplateSection("Overview", join(overview_parts, "\n"), v)

    # ── section 2: missing values ─────────────────────────────────────────────
    missing_content = _missing_section(column_names, missing_counts)
    missing_sec = TemplateSection("Missing Values", missing_content, v)

    # ── section 3: type corrections ───────────────────────────────────────────
    type_content = _type_section(column_names, column_types)
    type_sec = TemplateSection("Type Corrections", type_content, v)

    # ── section 4: deduplication ──────────────────────────────────────────────
    dedup_content = _dedup_section(duplicate_rows)
    dedup_sec = TemplateSection("Deduplication", dedup_content, v)

    # ── section 5: consolidated cleaning script ───────────────────────────────
    script = _cleaning_script(column_names, column_types, missing_counts, duplicate_rows)
    script_sec = TemplateSection("Suggested Code", script, v)

    return [overview, missing_sec, type_sec, dedup_sec, script_sec]
end

function _missing_section(
    names::AbstractVector{<:AbstractString},
    counts::AbstractVector{<:Integer},
)::String
    if isempty(counts) || all(==(0), counts)
        return "No missing values detected. ✓"
    end
    lines = ["Columns with missing values:"]
    for (name, cnt) in zip(names, counts)
        cnt > 0 && push!(lines, "  - `$(name)`: $(cnt) missing")
    end
    push!(lines, "")
    push!(lines, "Strategies:")
    push!(lines, "  - Drop rows:   `dropmissing(df, :column_name)`")
    push!(lines, "  - Fill with value: `coalesce.(df.column_name, replacement)`")
    push!(lines, "  - Fill with mean:  `df.column_name .= coalesce.(df.column_name, mean(skipmissing(df.column_name)))`")
    return join(lines, "\n")
end

function _type_section(
    names::AbstractVector{<:AbstractString},
    types::AbstractVector{<:AbstractString},
)::String
    if isempty(names) || isempty(types)
        return "No column type information provided."
    end
    string_cols = [n for (n, t) in zip(names, types)
                   if lowercase(t) in ("string", "abstractstring", "inlinestrings.string15",
                                       "inlinestrings.string31", "inlinestrings.string63",
                                       "inlinestrings.string127", "inlinestrings.string255")]
    if isempty(string_cols)
        return "All columns appear to have appropriate types. ✓"
    end
    lines = [
        "The following columns are stored as `String` and may benefit from conversion:",
    ]
    for col in string_cols
        push!(lines, "  - `$(col)` → consider `parse.(Int, df.$(col))` or `parse.(Float64, df.$(col))`")
    end
    push!(lines, "")
    push!(lines, "Use `eltype(df.column_name)` to verify the actual element type.")
    return join(lines, "\n")
end

function _dedup_section(duplicate_rows::Integer)::String
    if duplicate_rows == 0
        return "No duplicate rows detected. ✓"
    end
    return """$(duplicate_rows) duplicate row(s) detected.

Remove duplicates with:
  unique!(df)          # in-place
  df_clean = unique(df)  # copy"""
end

function _cleaning_script(
    names::AbstractVector{<:AbstractString},
    types::AbstractVector{<:AbstractString},
    missing_counts::AbstractVector{<:Integer},
    duplicate_rows::Integer,
)::String
    lines = ["# ── Data Cleaning Script ────────────────────────────────────────────────"]
    push!(lines, "using DataFrames, Statistics")
    push!(lines, "")

    # Drop duplicates
    if duplicate_rows > 0
        push!(lines, "# Remove duplicate rows")
        push!(lines, "unique!(df)")
        push!(lines, "")
    end

    # Handle missing values
    if !isempty(missing_counts) && any(>(0), missing_counts)
        push!(lines, "# Handle missing values")
        for (name, cnt) in zip(names, missing_counts)
            if cnt > 0
                push!(lines, "dropmissing!(df, :$(name))  # or use coalesce/fill strategy")
            end
        end
        push!(lines, "")
    end

    # Type coercions for string columns
    str_cols = isempty(types) ? String[] :
               [n for (n, t) in zip(names, types)
                if lowercase(t) in ("string", "abstractstring")]
    if !isempty(str_cols)
        push!(lines, "# Coerce string columns to numeric where appropriate")
        for col in str_cols
            push!(lines, "# df.$(col) = parse.(Float64, df.$(col))")
        end
        push!(lines, "")
    end

    push!(lines, "# Preview cleaned dataset")
    push!(lines, "describe(df)")

    return join(lines, "\n")
end

# ── EDA & Visualization Template ──────────────────────────────────────────────

"""
    eda_template(; column_names, column_types, n_rows, n_cols) -> Vector{TemplateSection}

Return a structured set of prompt sections with EDA and visualization
suggestions for a dataset.

# Keyword arguments
- `column_names` – vector of column names (`String`)
- `column_types` – vector of column type strings (e.g. `"Float64"`, `"String"`)
- `n_rows`       – number of rows in the dataset
- `n_cols`       – number of columns (inferred from `column_names` when provided)

# Returns
A `Vector{TemplateSection}` with sections:
1. **Overview** – dataset dimensions and column summary
2. **Descriptive Statistics** – code to compute summary stats
3. **Univariate Analysis** – per-column distribution plots
4. **Bivariate Analysis** – pairwise relationships
5. **Suggested Code** – consolidated EDA starter script
"""
function eda_template(;
    column_names::AbstractVector{<:AbstractString} = String[],
    column_types::AbstractVector{<:AbstractString} = String[],
    n_rows::Integer                                = 0,
    n_cols::Integer                                = length(column_names),
)::Vector{TemplateSection}
    v = EDA_TEMPLATE_VERSION

    effective_n_cols = max(n_cols, length(column_names))

    # ── section 1: overview ───────────────────────────────────────────────────
    overview_parts = [
        "Rows: $(n_rows > 0 ? n_rows : "unknown")",
        "Columns: $(effective_n_cols > 0 ? effective_n_cols : "unknown")",
    ]
    if !isempty(column_names)
        push!(overview_parts, "Column list: " * join("`" .* column_names .* "`", ", "))
    end
    overview = TemplateSection("Overview", join(overview_parts, "\n"), v)

    # ── section 2: descriptive statistics ────────────────────────────────────
    stats_content = """Compute summary statistics:

```julia
describe(df)           # mean, std, min/max, missing counts
```"""
    stats_sec = TemplateSection("Descriptive Statistics", stats_content, v)

    # ── section 3: univariate analysis ───────────────────────────────────────
    univariate_content = _univariate_section(column_names, column_types)
    univariate_sec = TemplateSection("Univariate Analysis", univariate_content, v)

    # ── section 4: bivariate analysis ────────────────────────────────────────
    bivariate_content = _bivariate_section(column_names, column_types)
    bivariate_sec = TemplateSection("Bivariate Analysis", bivariate_content, v)

    # ── section 5: consolidated EDA script ───────────────────────────────────
    script = _eda_script(column_names, column_types, n_rows)
    script_sec = TemplateSection("Suggested Code", script, v)

    return [overview, stats_sec, univariate_sec, bivariate_sec, script_sec]
end

function _is_numeric_type(t::AbstractString)::Bool
    lowercase(t) in ("float64", "float32", "int64", "int32", "int16", "int8",
                     "uint64", "uint32", "uint16", "uint8", "float16",
                     "int", "float", "integer", "abstractfloat")
end

function _is_categorical_type(t::AbstractString)::Bool
    lowercase(t) in ("string", "abstractstring", "bool", "boolean",
                     "categoricalvalue", "union{missing, string}")
end

function _univariate_section(
    names::AbstractVector{<:AbstractString},
    types::AbstractVector{<:AbstractString},
)::String
    if isempty(names)
        return """For each column, create a histogram (numeric) or bar chart (categorical):

```julia
using Plots
histogram(df.numeric_column; title="Distribution")
bar(sort(countmap(df.categorical_column)); title="Frequency")
```"""
    end

    lines = ["Suggested plots per column:", ""]
    for (name, typ) in zip(names, types)
        if _is_numeric_type(typ)
            push!(lines, "  - `$(name)` ($(typ)): `histogram(df.$(name))`")
        elseif _is_categorical_type(typ)
            push!(lines, "  - `$(name)` ($(typ)): `bar(sort(countmap(df.$(name))))`")
        else
            push!(lines, "  - `$(name)` ($(typ)): inspect with `describe(df[!, :$(name)])`")
        end
    end
    push!(lines, "")
    push!(lines, "```julia\nusing Plots, StatsBase\n```")
    return join(lines, "\n")
end

function _bivariate_section(
    names::AbstractVector{<:AbstractString},
    types::AbstractVector{<:AbstractString},
)::String
    if isempty(names)
        return """Explore relationships between columns:

```julia
using Plots
scatter(df.col_x, df.col_y; xlabel="col_x", ylabel="col_y")
```"""
    end

    numeric_cols = [n for (n, t) in zip(names, types) if _is_numeric_type(t)]

    if length(numeric_cols) >= 2
        lines = [
            "Numeric columns available for pairwise analysis:",
            "  " * join("`" .* numeric_cols .* "`", ", "),
            "",
            "Suggestions:",
            "  - Correlation matrix: `cor(Matrix(df[!, $(repr(Symbol.(numeric_cols)))]))`",
            "  - Scatter plot: `scatter(df.$(numeric_cols[1]), df.$(numeric_cols[2]))`",
            "  - Pair plot (requires StatsPlots): `@df df cornerplot(cols($(repr(numeric_cols))))`",
        ]
        return join(lines, "\n")
    elseif length(numeric_cols) == 1
        return """Only one numeric column (`$(numeric_cols[1])`) found.
Consider grouping by a categorical column:

```julia
using StatsPlots
@df df boxplot(:categorical_col, :$(numeric_cols[1]))
```"""
    else
        return "No numeric columns detected. Explore frequency tables with `combine(groupby(df, :col), nrow)`."
    end
end

function _eda_script(
    names::AbstractVector{<:AbstractString},
    types::AbstractVector{<:AbstractString},
    n_rows::Integer,
)::String
    numeric_cols = [n for (n, t) in zip(names, types) if _is_numeric_type(t)]
    cat_cols     = [n for (n, t) in zip(names, types) if _is_categorical_type(t)]

    lines = ["# ── EDA Starter Script ──────────────────────────────────────────────────"]
    push!(lines, "using DataFrames, Statistics, Plots, StatsBase")
    push!(lines, "")
    push!(lines, "# 1. Dimensions and types")
    push!(lines, "println(\"Rows: \$(nrow(df)), Cols: \$(ncol(df))\")")
    push!(lines, "describe(df)")
    push!(lines, "")

    if !isempty(numeric_cols)
        push!(lines, "# 2. Numeric distributions")
        for col in numeric_cols
            push!(lines, "histogram(df.$(col); title=\"$(col)\", xlabel=\"$(col)\", ylabel=\"count\")")
        end
        push!(lines, "")
    end

    if !isempty(cat_cols)
        push!(lines, "# 3. Categorical frequencies")
        for col in cat_cols
            push!(lines, "bar(sort(countmap(df.$(col))); title=\"$(col) frequency\")")
        end
        push!(lines, "")
    end

    if length(numeric_cols) >= 2
        push!(lines, "# 4. Pairwise scatter")
        push!(lines, "scatter(df.$(numeric_cols[1]), df.$(numeric_cols[2]);")
        push!(lines, "        xlabel=\"$(numeric_cols[1])\", ylabel=\"$(numeric_cols[2])\")")
        push!(lines, "")
        push!(lines, "# 5. Correlation matrix")
        cols_expr = "[" * join(("df." .* numeric_cols), ", ") * "]"
        push!(lines, "cor(hcat($(cols_expr)...))")
    end

    return join(lines, "\n")
end

end # module PromptTemplates
