import Pluto
using Pluto.PromptTemplates
using Test

@testset "PromptTemplates" begin

    # ── TemplateSection struct ────────────────────────────────────────────────

    @testset "TemplateSection" begin
        sec = TemplateSection("My Title", "My content", v"1.2.3")
        @test sec.title   == "My Title"
        @test sec.content == "My content"
        @test sec.version == v"1.2.3"
    end

    # ── Version constants ─────────────────────────────────────────────────────

    @testset "Version constants" begin
        @test PromptTemplates.IMPORT_TEMPLATE_VERSION  isa VersionNumber
        @test PromptTemplates.CLEANING_TEMPLATE_VERSION isa VersionNumber
        @test PromptTemplates.EDA_TEMPLATE_VERSION     isa VersionNumber
    end

    # ── import_template ───────────────────────────────────────────────────────

    @testset "import_template" begin

        @testset "returns Vector{TemplateSection}" begin
            secs = import_template()
            @test secs isa Vector{TemplateSection}
            @test length(secs) == 3
        end

        @testset "section titles" begin
            secs = import_template()
            titles = getproperty.(secs, :title)
            @test "Overview" in titles
            @test "Suggested Code" in titles
            @test "Notes" in titles
        end

        @testset "all sections carry the correct version" begin
            secs = import_template()
            for sec in secs
                @test sec.version == PromptTemplates.IMPORT_TEMPLATE_VERSION
            end
        end

        @testset "CSV file" begin
            secs = import_template(file_path="data/sales.csv", separator=",")
            overview = findfirst(s -> s.title == "Overview", secs)
            @test !isnothing(overview)
            @test occursin("csv", secs[overview].content)
            @test occursin("data/sales.csv", secs[overview].content)

            code_sec = findfirst(s -> s.title == "Suggested Code", secs)
            @test !isnothing(code_sec)
            @test occursin("CSV", secs[code_sec].content)
            @test occursin("DataFrame", secs[code_sec].content)
        end

        @testset "TSV file inferred from extension" begin
            secs = import_template(file_path="data/output.tsv")
            code_idx = findfirst(s -> s.title == "Suggested Code", secs)
            @test !isnothing(code_idx)
            @test occursin("CSV", secs[code_idx].content)
        end

        @testset "Excel file" begin
            secs = import_template(file_path="report.xlsx")
            code_idx = findfirst(s -> s.title == "Suggested Code", secs)
            @test !isnothing(code_idx)
            @test occursin("XLSX", secs[code_idx].content)
        end

        @testset "JSON file" begin
            secs = import_template(file_path="records.json")
            code_idx = findfirst(s -> s.title == "Suggested Code", secs)
            @test !isnothing(code_idx)
            @test occursin("JSON3", secs[code_idx].content)
        end

        @testset "Parquet file" begin
            secs = import_template(file_path="data.parquet")
            code_idx = findfirst(s -> s.title == "Suggested Code", secs)
            @test !isnothing(code_idx)
            @test occursin("Parquet2", secs[code_idx].content)
        end

        @testset "Arrow / Feather file" begin
            secs = import_template(file_path="data.arrow")
            code_idx = findfirst(s -> s.title == "Suggested Code", secs)
            @test !isnothing(code_idx)
            @test occursin("Arrow", secs[code_idx].content)
        end

        @testset "file_type overrides extension" begin
            secs = import_template(file_path="data.bin", file_type="csv")
            code_idx = findfirst(s -> s.title == "Suggested Code", secs)
            @test occursin("CSV", secs[code_idx].content)
        end

        @testset "unknown extension falls back gracefully" begin
            secs = import_template(file_path="data.abc123")
            code_idx = findfirst(s -> s.title == "Suggested Code", secs)
            @test secs[code_idx].content isa String
            @test !isempty(secs[code_idx].content)
        end

        @testset "no arguments – minimal call" begin
            secs = import_template()
            for sec in secs
                @test sec isa TemplateSection
                @test !isempty(sec.title)
                @test !isempty(sec.content)
            end
        end

        @testset "no_header flag is reflected" begin
            secs_with    = import_template(has_header=true)
            secs_without = import_template(has_header=false)
            ov_with    = secs_with[findfirst(s -> s.title == "Overview", secs_with)].content
            ov_without = secs_without[findfirst(s -> s.title == "Overview", secs_without)].content
            @test occursin("yes", ov_with)
            @test occursin("no",  ov_without)
        end

        @testset "non-UTF-8 encoding appears in overview" begin
            secs = import_template(encoding="latin-1")
            ov = secs[findfirst(s -> s.title == "Overview", secs)].content
            @test occursin("latin-1", ov)
        end

        @testset "deterministic – same args produce identical output" begin
            a = import_template(file_path="x.csv", separator=",", encoding="UTF-8")
            b = import_template(file_path="x.csv", separator=",", encoding="UTF-8")
            for (sa, sb) in zip(a, b)
                @test sa.title   == sb.title
                @test sa.content == sb.content
                @test sa.version == sb.version
            end
        end
    end

    # ── cleaning_template ─────────────────────────────────────────────────────

    @testset "cleaning_template" begin

        @testset "returns Vector{TemplateSection}" begin
            secs = cleaning_template()
            @test secs isa Vector{TemplateSection}
            @test length(secs) == 5
        end

        @testset "section titles" begin
            secs = cleaning_template()
            titles = getproperty.(secs, :title)
            @test "Overview"         in titles
            @test "Missing Values"   in titles
            @test "Type Corrections" in titles
            @test "Deduplication"    in titles
            @test "Suggested Code"   in titles
        end

        @testset "all sections carry the correct version" begin
            secs = cleaning_template()
            for sec in secs
                @test sec.version == PromptTemplates.CLEANING_TEMPLATE_VERSION
            end
        end

        @testset "overview counts reflect inputs" begin
            secs = cleaning_template(
                column_names   = ["age", "name", "score"],
                column_types   = ["Int64", "String", "Float64"],
                missing_counts = [0, 3, 1],
                duplicate_rows = 5,
            )
            ov = secs[findfirst(s -> s.title == "Overview", secs)].content
            @test occursin("3",  ov)   # column count
            @test occursin("4",  ov)   # total missing (3+1)
            @test occursin("5",  ov)   # duplicate rows
        end

        @testset "no missing values – positive message" begin
            secs = cleaning_template(
                column_names   = ["a", "b"],
                column_types   = ["Int64", "Float64"],
                missing_counts = [0, 0],
            )
            mv_sec = secs[findfirst(s -> s.title == "Missing Values", secs)]
            @test occursin("No missing values", mv_sec.content)
        end

        @testset "missing values listed per column" begin
            secs = cleaning_template(
                column_names   = ["city", "price", "qty"],
                column_types   = ["String", "Float64", "Int64"],
                missing_counts = [2, 0, 7],
            )
            mv_sec = secs[findfirst(s -> s.title == "Missing Values", secs)]
            @test occursin("city", mv_sec.content)
            @test occursin("qty",  mv_sec.content)
            @test !occursin("`price`", mv_sec.content)  # 0 missing – should not appear
        end

        @testset "no duplicates – positive message" begin
            secs = cleaning_template(duplicate_rows=0)
            dd = secs[findfirst(s -> s.title == "Deduplication", secs)]
            @test occursin("No duplicate", dd.content)
        end

        @testset "duplicates present – code snippet shown" begin
            secs = cleaning_template(duplicate_rows=12)
            dd = secs[findfirst(s -> s.title == "Deduplication", secs)]
            @test occursin("12", dd.content)
            @test occursin("unique", dd.content)
        end

        @testset "string columns flagged in type corrections" begin
            secs = cleaning_template(
                column_names = ["id", "revenue"],
                column_types = ["String", "String"],
            )
            tc = secs[findfirst(s -> s.title == "Type Corrections", secs)]
            @test occursin("id",      tc.content)
            @test occursin("revenue", tc.content)
        end

        @testset "no string columns – positive message" begin
            secs = cleaning_template(
                column_names = ["x", "y"],
                column_types = ["Float64", "Int64"],
            )
            tc = secs[findfirst(s -> s.title == "Type Corrections", secs)]
            @test occursin("appropriate types", tc.content)
        end

        @testset "suggested code contains DataFrames import" begin
            secs = cleaning_template(
                column_names   = ["a"],
                column_types   = ["Int64"],
                missing_counts = [3],
                duplicate_rows = 1,
            )
            sc = secs[findfirst(s -> s.title == "Suggested Code", secs)]
            @test occursin("DataFrames", sc.content)
            @test occursin("dropmissing", sc.content)
            @test occursin("unique", sc.content)
        end

        @testset "deterministic – same args produce identical output" begin
            args = (
                column_names   = ["x", "y"],
                column_types   = ["Float64", "String"],
                missing_counts = [1, 4],
                duplicate_rows = 2,
            )
            a = cleaning_template(; args...)
            b = cleaning_template(; args...)
            for (sa, sb) in zip(a, b)
                @test sa.content == sb.content
            end
        end

        @testset "edge case: empty inputs" begin
            secs = cleaning_template()
            for sec in secs
                @test sec isa TemplateSection
                @test !isempty(sec.title)
                @test !isempty(sec.content)
            end
        end
    end

    # ── eda_template ─────────────────────────────────────────────────────────

    @testset "eda_template" begin

        @testset "returns Vector{TemplateSection}" begin
            secs = eda_template()
            @test secs isa Vector{TemplateSection}
            @test length(secs) == 5
        end

        @testset "section titles" begin
            secs = eda_template()
            titles = getproperty.(secs, :title)
            @test "Overview"               in titles
            @test "Descriptive Statistics" in titles
            @test "Univariate Analysis"    in titles
            @test "Bivariate Analysis"     in titles
            @test "Suggested Code"         in titles
        end

        @testset "all sections carry the correct version" begin
            secs = eda_template()
            for sec in secs
                @test sec.version == PromptTemplates.EDA_TEMPLATE_VERSION
            end
        end

        @testset "overview reflects row/col counts" begin
            secs = eda_template(
                column_names = ["a", "b", "c"],
                column_types = ["Float64", "Int64", "String"],
                n_rows = 500,
            )
            ov = secs[findfirst(s -> s.title == "Overview", secs)].content
            @test occursin("500",  ov)
            @test occursin("3",    ov)
        end

        @testset "column names listed in overview" begin
            secs = eda_template(column_names=["alpha", "beta"], column_types=["Float64", "Float64"])
            ov = secs[findfirst(s -> s.title == "Overview", secs)].content
            @test occursin("alpha", ov)
            @test occursin("beta",  ov)
        end

        @testset "descriptive statistics section has describe()" begin
            secs = eda_template()
            ds = secs[findfirst(s -> s.title == "Descriptive Statistics", secs)]
            @test occursin("describe", ds.content)
        end

        @testset "univariate analysis – numeric columns get histogram" begin
            secs = eda_template(
                column_names = ["age", "income"],
                column_types = ["Int64", "Float64"],
            )
            ua = secs[findfirst(s -> s.title == "Univariate Analysis", secs)]
            @test occursin("histogram", ua.content)
            @test occursin("age",       ua.content)
            @test occursin("income",    ua.content)
        end

        @testset "univariate analysis – categorical columns get bar chart" begin
            secs = eda_template(
                column_names = ["gender", "region"],
                column_types = ["String", "String"],
            )
            ua = secs[findfirst(s -> s.title == "Univariate Analysis", secs)]
            @test occursin("bar", ua.content)
            @test occursin("gender", ua.content)
        end

        @testset "bivariate analysis – two numeric columns" begin
            secs = eda_template(
                column_names = ["x", "y"],
                column_types = ["Float64", "Float64"],
            )
            ba = secs[findfirst(s -> s.title == "Bivariate Analysis", secs)]
            @test occursin("scatter",   ba.content)
            @test occursin("x",         ba.content)
            @test occursin("y",         ba.content)
        end

        @testset "bivariate analysis – one numeric, one categorical" begin
            secs = eda_template(
                column_names = ["score", "category"],
                column_types = ["Float64", "String"],
            )
            ba = secs[findfirst(s -> s.title == "Bivariate Analysis", secs)]
            @test !isempty(ba.content)
        end

        @testset "bivariate analysis – no numeric columns" begin
            secs = eda_template(
                column_names = ["country", "city"],
                column_types = ["String", "String"],
            )
            ba = secs[findfirst(s -> s.title == "Bivariate Analysis", secs)]
            @test !isempty(ba.content)
        end

        @testset "suggested code references numeric columns" begin
            secs = eda_template(
                column_names = ["price", "qty"],
                column_types = ["Float64", "Int64"],
                n_rows = 100,
            )
            sc = secs[findfirst(s -> s.title == "Suggested Code", secs)]
            @test occursin("price", sc.content)
            @test occursin("qty",   sc.content)
            @test occursin("histogram", sc.content)
        end

        @testset "deterministic – same args produce identical output" begin
            args = (
                column_names = ["v1", "v2", "label"],
                column_types = ["Float64", "Int64", "String"],
                n_rows = 200,
            )
            a = eda_template(; args...)
            b = eda_template(; args...)
            for (sa, sb) in zip(a, b)
                @test sa.content == sb.content
            end
        end

        @testset "edge case: empty inputs" begin
            secs = eda_template()
            for sec in secs
                @test sec isa TemplateSection
                @test !isempty(sec.title)
                @test !isempty(sec.content)
            end
        end

        @testset "edge case: single column" begin
            secs = eda_template(
                column_names = ["value"],
                column_types = ["Float64"],
                n_rows = 50,
            )
            for sec in secs
                @test sec isa TemplateSection
            end
        end

        @testset "edge case: many columns" begin
            names = ["col$(i)" for i in 1:20]
            types = [isodd(i) ? "Float64" : "String" for i in 1:20]
            secs  = eda_template(column_names=names, column_types=types, n_rows=1000)
            for sec in secs
                @test sec isa TemplateSection
                @test !isempty(sec.content)
            end
        end
    end

end # @testset "PromptTemplates"
