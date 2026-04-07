using Test
using Pluto
using Pluto: Cell, Notebook, ExportPipeline

@testset "ExportPipeline" begin

    # Build a minimal notebook (no server session needed)
    nb = Notebook([
        Cell("x = 1"),
        Cell("y = x + 2"),
        Cell("z = x * y"),
    ])
    # Give each cell a small output so Markdown/CSV tests are meaningful
    nb.cells[1].output = Pluto.CellOutput(body="1", mime=MIME("text/plain"))
    nb.cells[2].output = Pluto.CellOutput(body="3", mime=MIME("text/plain"))
    nb.cells[3].output = Pluto.CellOutput(body="3", mime=MIME("text/plain"))

    # A notebook with cells that have no output (body=nothing, never run)
    nb_no_output = Notebook([Cell("a = 42"), Cell("b = a + 1")])

    # ──────────────────────────────────────────────────────────────────────────
    # ProvenanceMetadata
    # ──────────────────────────────────────────────────────────────────────────
    @testset "ProvenanceMetadata" begin
        p = ExportPipeline.ProvenanceMetadata(nb, :test_format)
        @test p.notebook_path == nb.path
        @test p.pluto_version == Pluto.PLUTO_VERSION
        @test p.julia_version == VERSION
        @test p.export_format == :test_format

        d = ExportPipeline.provenance_dict(p)
        @test haskey(d, "notebook_path")
        @test haskey(d, "pluto_version")
        @test haskey(d, "julia_version")
        @test haskey(d, "exported_at")
        @test haskey(d, "export_format")
        @test d["export_format"] == "test_format"
    end

    # ──────────────────────────────────────────────────────────────────────────
    # HTML export
    # ──────────────────────────────────────────────────────────────────────────
    @testset "export_html" begin
        result = ExportPipeline.export_html(nb)
        @test result isa ExportPipeline.ExportResult{String}
        @test result.provenance.export_format == :html
        @test occursin("<!DOCTYPE html>", result.content) || occursin("<html", result.content)
        @test occursin("Pluto Export Provenance", result.content)

        # Write to file
        tmp = tempname() * ".html"
        result2 = ExportPipeline.export_html(nb; path=tmp)
        @test isfile(tmp)
        @test read(tmp, String) == result2.content
        rm(tmp)
    end

    # ──────────────────────────────────────────────────────────────────────────
    # Markdown export
    # ──────────────────────────────────────────────────────────────────────────
    @testset "export_markdown" begin
        result = ExportPipeline.export_markdown(nb)
        @test result isa ExportPipeline.ExportResult{String}
        @test result.provenance.export_format == :markdown
        md = result.content
        # Code blocks present
        @test occursin("```julia", md)
        @test occursin("x = 1", md)
        @test occursin("y = x + 2", md)
        # Provenance comment present
        @test occursin("pluto_version", md)

        # Write to file
        tmp = tempname() * ".md"
        result2 = ExportPipeline.export_markdown(nb; path=tmp)
        @test isfile(tmp)
        @test read(tmp, String) == result2.content
        rm(tmp)
    end

    # ──────────────────────────────────────────────────────────────────────────
    # Markdown export – cells with no output (body=nothing)
    # ──────────────────────────────────────────────────────────────────────────
    @testset "export_markdown (no-output cells)" begin
        result = ExportPipeline.export_markdown(nb_no_output)
        @test result isa ExportPipeline.ExportResult{String}
        md = result.content
        @test occursin("```julia", md)
        @test occursin("a = 42", md)
        # No block-quote lines expected since cells have no text output
        @test !occursin("> ", md)
    end

    # ──────────────────────────────────────────────────────────────────────────
    # CSV export – non-Tables data should error
    # ──────────────────────────────────────────────────────────────────────────
    @testset "export_csv (error conditions)" begin
        @test_throws Exception ExportPipeline.export_csv(42)  # plain Int is not a table
    end

    # ──────────────────────────────────────────────────────────────────────────
    # Bundle export – default temp dir
    # ──────────────────────────────────────────────────────────────────────────
    @testset "export_bundle (default temp dir)" begin
        result = ExportPipeline.export_bundle(nb_no_output)
        @test isdir(result.content)
        @test isfile(joinpath(result.content, "provenance.toml"))
    end

    # ──────────────────────────────────────────────────────────────────────────
    # Notebook summary CSV – cells without runtime
    # ──────────────────────────────────────────────────────────────────────────
    @testset "export_notebook_summary_csv (no runtime)" begin
        result = ExportPipeline.export_notebook_summary_csv(nb_no_output)
        @test occursin("0", result.content)  # default 0 for unrun cells
    end


    @testset "export_csv (generic data)" begin
        data = [(a=1, b="hello"), (a=2, b="world,\"quoted\"")]
        result = ExportPipeline.export_csv(data)
        @test result isa ExportPipeline.ExportResult{String}
        @test result.provenance.export_format == :csv
        csv = result.content
        @test occursin("a,b", csv)
        @test occursin("hello", csv)
        # quoted field with comma must be escaped
        @test occursin('"', csv)

        # Write to file
        tmp = tempname() * ".csv"
        result2 = ExportPipeline.export_csv(data; path=tmp)
        @test isfile(tmp)
        @test read(tmp, String) == result2.content
        rm(tmp)
    end

    # ──────────────────────────────────────────────────────────────────────────
    # Notebook summary CSV
    # ──────────────────────────────────────────────────────────────────────────
    @testset "export_notebook_summary_csv" begin
        result = ExportPipeline.export_notebook_summary_csv(nb)
        @test result isa ExportPipeline.ExportResult{String}
        csv = result.content
        @test occursin("cell_id", csv)
        @test occursin("errored", csv)
        @test occursin("runtime_ns", csv)
        # Three cells → three data rows plus header
        lines = filter(!isempty, split(csv, '\n'))
        @test length(lines) == length(nb.cells) + 1
    end

    # ──────────────────────────────────────────────────────────────────────────
    # Bundle export
    # ──────────────────────────────────────────────────────────────────────────
    @testset "export_bundle" begin
        bundle_dir = mktempdir()
        result = ExportPipeline.export_bundle(nb; dir=bundle_dir)
        @test result isa ExportPipeline.ExportResult{String}
        @test result.content == bundle_dir
        @test result.provenance.export_format == :bundle

        @test isfile(joinpath(bundle_dir, "report.html"))
        @test isfile(joinpath(bundle_dir, "report.md"))
        @test isfile(joinpath(bundle_dir, "cell_summary.csv"))
        @test isfile(joinpath(bundle_dir, "provenance.toml"))

        toml_content = read(joinpath(bundle_dir, "provenance.toml"), String)
        @test occursin("pluto_version", toml_content)
        @test occursin("notebook_path", toml_content)
    end

    # ──────────────────────────────────────────────────────────────────────────
    # Unified entry point: export_notebook
    # ──────────────────────────────────────────────────────────────────────────
    @testset "export_notebook unified entry point" begin
        html_result = ExportPipeline.export_notebook(nb, :html)
        @test html_result.provenance.export_format == :html

        md_result = ExportPipeline.export_notebook(nb, :markdown)
        @test md_result.provenance.export_format == :markdown

        csv_result = ExportPipeline.export_notebook(nb, :csv)
        @test csv_result.provenance.export_format == :csv

        bundle_result = ExportPipeline.export_notebook(nb, :bundle)
        @test bundle_result.provenance.export_format == :bundle

        @test_throws ArgumentError ExportPipeline.export_notebook(nb, :unknown_format)
    end

end
