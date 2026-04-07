using Test
import Pluto: DataImportWizard
using Pluto.DataImportWizard: ImportFormat, CSV_FORMAT, TSV_FORMAT, PARQUET_FORMAT, ARROW_FORMAT, JSON_FORMAT,
                               ImportOptions, generate_import_code, detect_format, default_options

@testset "DataImportWizard" begin

    # ------------------------------------------------------------------
    # detect_format
    # ------------------------------------------------------------------
    @testset "detect_format" begin
        @test detect_format("data.csv")     == CSV_FORMAT
        @test detect_format("data.CSV")     == CSV_FORMAT
        @test detect_format("/tmp/path/to/data.csv") == CSV_FORMAT
        @test detect_format("data.tsv")     == TSV_FORMAT
        @test detect_format("data.parquet") == PARQUET_FORMAT
        @test detect_format("data.arrow")   == ARROW_FORMAT
        @test detect_format("data.feather") == ARROW_FORMAT
        @test detect_format("data.json")    == JSON_FORMAT
        @test detect_format("data.jsonl")   == JSON_FORMAT
        @test detect_format("data.ndjson")  == JSON_FORMAT

        @test_throws ArgumentError detect_format("data.xlsx")
        @test_throws ArgumentError detect_format("data.txt")
        @test_throws ArgumentError detect_format("noextension")
    end

    # ------------------------------------------------------------------
    # default_options
    # ------------------------------------------------------------------
    @testset "default_options" begin
        csv_opts = default_options(CSV_FORMAT)
        @test csv_opts.delimiter == ','
        @test csv_opts.has_header == true
        @test csv_opts.encoding == "UTF-8"

        tsv_opts = default_options(TSV_FORMAT)
        @test tsv_opts.delimiter == '\t'

        parquet_opts = default_options(PARQUET_FORMAT)
        @test parquet_opts.columns === nothing

        arrow_opts = default_options(ARROW_FORMAT)
        @test arrow_opts.ntasks === nothing

        json_opts = default_options(JSON_FORMAT)
        @test json_opts.json_type == "array"
        @test json_opts.struct_type == "NamedTuple"
    end

    # ------------------------------------------------------------------
    # generate_import_code – CSV
    # ------------------------------------------------------------------
    @testset "generate_import_code CSV" begin
        code = generate_import_code("mydata.csv", CSV_FORMAT)
        @test occursin("using CSV, DataFrames", code)
        @test occursin("CSV.read(\"mydata.csv\", DataFrame)", code)

        # custom delimiter
        opts = ImportOptions(delimiter='|')
        code = generate_import_code("pipe.csv", CSV_FORMAT, opts)
        @test occursin("delim='|'", code)

        # no header
        opts_noheader = ImportOptions(has_header=false)
        code = generate_import_code("noheader.csv", CSV_FORMAT, opts_noheader)
        @test occursin("header=false", code)

        # missing string
        opts_miss = ImportOptions(missingstring="NA")
        code = generate_import_code("na.csv", CSV_FORMAT, opts_miss)
        @test occursin("missingstring=\"NA\"", code)

        # dateformat
        opts_date = ImportOptions(dateformat="yyyy-mm-dd")
        code = generate_import_code("dated.csv", CSV_FORMAT, opts_date)
        @test occursin("dateformat=\"yyyy-mm-dd\"", code)

        # column types
        opts_types = ImportOptions(types=Dict("age" => "Int64", "name" => "String"))
        code = generate_import_code("typed.csv", CSV_FORMAT, opts_types)
        @test occursin("types=Dict(", code)
        @test occursin("\"age\" => Int64", code)
        @test occursin("\"name\" => String", code)

        # limit and skipto
        opts_limit = ImportOptions(limit=1000, skipto=2)
        code = generate_import_code("big.csv", CSV_FORMAT, opts_limit)
        @test occursin("limit=1000", code)
        @test occursin("skipto=2", code)

        # comment character
        opts_comment = ImportOptions(comment='#')
        code = generate_import_code("comments.csv", CSV_FORMAT, opts_comment)
        @test occursin("comment='#'", code)

        # source path with spaces / special chars
        code = generate_import_code("my data/file.csv", CSV_FORMAT)
        @test occursin("\"my data/file.csv\"", code)
    end

    # ------------------------------------------------------------------
    # generate_import_code – TSV
    # ------------------------------------------------------------------
    @testset "generate_import_code TSV" begin
        code = generate_import_code("data.tsv", TSV_FORMAT)
        @test occursin("using CSV, DataFrames", code)
        @test occursin("delim='\\t'", code)

        # TSV with explicit non-tab delimiter overrides default
        opts = ImportOptions(delimiter=',')
        code = generate_import_code("weird.tsv", TSV_FORMAT, opts)
        @test occursin("delim=','", code)
    end

    # ------------------------------------------------------------------
    # generate_import_code – Parquet
    # ------------------------------------------------------------------
    @testset "generate_import_code Parquet" begin
        code = generate_import_code("data.parquet", PARQUET_FORMAT)
        @test occursin("using Parquet2, DataFrames", code)
        @test occursin("Parquet2.Dataset(\"data.parquet\")", code)
        @test occursin("DataFrame(", code)

        # column subset
        opts = ImportOptions(columns=["id", "name", "value"])
        code = generate_import_code("data.parquet", PARQUET_FORMAT, opts)
        @test occursin("columns=[\"id\", \"name\", \"value\"]", code)
    end

    # ------------------------------------------------------------------
    # generate_import_code – Arrow
    # ------------------------------------------------------------------
    @testset "generate_import_code Arrow" begin
        code = generate_import_code("data.arrow", ARROW_FORMAT)
        @test occursin("using Arrow, DataFrames", code)
        @test occursin("Arrow.Table(\"data.arrow\")", code)
        @test occursin("|> DataFrame", code)

        # ntasks
        opts = ImportOptions(ntasks=4)
        code = generate_import_code("parallel.arrow", ARROW_FORMAT, opts)
        @test occursin("ntasks=4", code)
    end

    # ------------------------------------------------------------------
    # generate_import_code – JSON
    # ------------------------------------------------------------------
    @testset "generate_import_code JSON" begin
        # auto mode
        opts_auto = ImportOptions(json_type="auto")
        code = generate_import_code("data.json", JSON_FORMAT, opts_auto)
        @test occursin("using JSON3", code)
        @test occursin("JSON3.read(io)", code)

        # array mode
        opts_arr = ImportOptions(json_type="array", struct_type="NamedTuple")
        code = generate_import_code("records.json", JSON_FORMAT, opts_arr)
        @test occursin("Vector{NamedTuple}", code)

        # object mode
        opts_obj = ImportOptions(json_type="object", struct_type="NamedTuple")
        code = generate_import_code("record.json", JSON_FORMAT, opts_obj)
        @test occursin("JSON3.read(io, NamedTuple)", code)

        # Dict struct type
        opts_dict = ImportOptions(json_type="object", struct_type="Dict")
        code = generate_import_code("record.json", JSON_FORMAT, opts_dict)
        @test occursin("Dict{String, Any}", code)
    end

    # ------------------------------------------------------------------
    # Convenience: detect_format + generate_import_code roundtrip
    # ------------------------------------------------------------------
    @testset "roundtrip detect + generate" begin
        for (path, expected_pkg) in [
            ("dataset.csv",     "CSV"),
            ("dataset.tsv",     "CSV"),
            ("dataset.parquet", "Parquet2"),
            ("dataset.arrow",   "Arrow"),
            ("dataset.json",    "JSON3"),
        ]
            fmt  = detect_format(path)
            opts = default_options(fmt)
            code = generate_import_code(path, fmt, opts)
            @test occursin(expected_pkg, code)
        end
    end

    # ------------------------------------------------------------------
    # ImportOptions keyword constructor
    # ------------------------------------------------------------------
    @testset "ImportOptions defaults" begin
        opts = ImportOptions()
        @test opts.encoding      == "UTF-8"
        @test opts.delimiter     == ','
        @test opts.has_header    == true
        @test opts.comment       === nothing
        @test opts.missingstring === nothing
        @test opts.dateformat    === nothing
        @test opts.types         === nothing
        @test opts.limit         === nothing
        @test opts.skipto        === nothing
        @test opts.columns       === nothing
        @test opts.ntasks        === nothing
        @test opts.json_type     == "auto"
        @test opts.struct_type   == "NamedTuple"
    end

end
