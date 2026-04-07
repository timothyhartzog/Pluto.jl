using Test
import Pluto
import Pluto: Notebook, Cell, generate_markdown, export_notebook
import Pluto: set_provenance!, clear_provenance!, is_ai_generated, get_provenance
import Pluto: is_disabled, set_disabled

# ─────────────────────────────────────────────────────────────────────────────
# Telemetry: redact_sensitive
# ─────────────────────────────────────────────────────────────────────────────
@testset "Telemetry.redact_sensitive" begin

    @testset "sensitive keys are redacted" begin
        for key in ["password", "token", "secret", "api_key", "authorization",
                    "credential", "private_key", "bearer"]
            result = Pluto.Telemetry.redact_sensitive(Dict(key => "super_secret_value"))
            @test result[key] == Pluto.Telemetry.REDACTED_PLACEHOLDER
        end
    end

    @testset "non-sensitive keys are preserved" begin
        data = Dict("user" => "alice", "notebook_id" => "abc-123", "count" => 42)
        result = Pluto.Telemetry.redact_sensitive(data)
        @test result["user"] == "alice"
        @test result["notebook_id"] == "abc-123"
        @test result["count"] == 42
    end

    @testset "nested dicts are redacted recursively" begin
        data = Dict("outer" => Dict("api_key" => "nested_secret", "name" => "bob"))
        result = Pluto.Telemetry.redact_sensitive(data)
        @test result["outer"]["api_key"] == Pluto.Telemetry.REDACTED_PLACEHOLDER
        @test result["outer"]["name"] == "bob"
    end

    @testset "vectors of dicts are redacted" begin
        data = [Dict("password" => "pw1"), Dict("user" => "charlie")]
        result = Pluto.Telemetry.redact_sensitive(data)
        @test result[1]["password"] == Pluto.Telemetry.REDACTED_PLACEHOLDER
        @test result[2]["user"] == "charlie"
    end

    @testset "scalar values pass through" begin
        @test Pluto.Telemetry.redact_sensitive(42) == 42
        @test Pluto.Telemetry.redact_sensitive("hello") == "hello"
        @test Pluto.Telemetry.redact_sensitive(nothing) === nothing
    end

    @testset "case-insensitive key matching" begin
        result = Pluto.Telemetry.redact_sensitive(Dict("PASSWORD" => "s3cr3t", "Token" => "tok"))
        @test result["PASSWORD"] == Pluto.Telemetry.REDACTED_PLACEHOLDER
        @test result["Token"] == Pluto.Telemetry.REDACTED_PLACEHOLDER
    end
end


# ─────────────────────────────────────────────────────────────────────────────
# Telemetry: TelemetryEvent
# ─────────────────────────────────────────────────────────────────────────────
@testset "TelemetryEvent construction" begin

    @testset "payload is redacted on construction" begin
        ev = Pluto.Telemetry.TelemetryEvent("test_event",
            Dict("user" => "alice", "password" => "secret"))
        @test ev.payload["user"] == "alice"
        @test ev.payload["password"] == Pluto.Telemetry.REDACTED_PLACEHOLDER
    end

    @testset "event_name and timestamp are set" begin
        ev = Pluto.Telemetry.TelemetryEvent("my_event")
        @test ev.event_name == "my_event"
        @test ev.timestamp > 0
    end
end


# ─────────────────────────────────────────────────────────────────────────────
# Provenance metadata on Cells
# ─────────────────────────────────────────────────────────────────────────────
@testset "Cell provenance metadata" begin

    cell = Cell("x = 1 + 1")

    @testset "new cell has no provenance" begin
        @test !is_ai_generated(cell)
        @test get_provenance(cell) === nothing
    end

    @testset "set_provenance! marks cell as AI-generated" begin
        prov = Dict{String,Any}("tool" => "Pluto AI", "model" => "gpt-4o")
        set_provenance!(cell, prov)
        @test is_ai_generated(cell)
        @test get_provenance(cell) == prov
        @test get_provenance(cell)["tool"] == "Pluto AI"
    end

    @testset "clear_provenance! removes metadata" begin
        set_provenance!(cell, Dict{String,Any}("tool" => "test"))
        clear_provenance!(cell)
        @test !is_ai_generated(cell)
        @test get_provenance(cell) === nothing
    end

    @testset "set_provenance! replaces previous provenance" begin
        set_provenance!(cell, Dict{String,Any}("tool" => "v1"))
        set_provenance!(cell, Dict{String,Any}("tool" => "v2"))
        @test get_provenance(cell)["tool"] == "v2"
    end
end


# ─────────────────────────────────────────────────────────────────────────────
# Markdown export
# ─────────────────────────────────────────────────────────────────────────────
@testset "generate_markdown" begin

    nb = Notebook([
        Cell("x = 42"),
        Cell("y = x + 1"),
    ])

    md = generate_markdown(nb)

    @testset "code blocks are present" begin
        @test occursin("```julia", md)
        @test occursin("x = 42", md)
        @test occursin("y = x + 1", md)
    end

    @testset "disabled cells are excluded" begin
        disabled_cell = Cell("should_not_appear = true")
        set_disabled(disabled_cell, true)
        nb2 = Notebook([Cell("present = 1"), disabled_cell])
        md2 = generate_markdown(nb2)
        @test occursin("present = 1", md2)
        @test !occursin("should_not_appear", md2)
    end

    @testset "notebook with frontmatter includes title" begin
        nb3 = Notebook([Cell("a = 1")])
        nb3.metadata["frontmatter"] = Dict{String,Any}("title" => "My Test Notebook")
        md3 = generate_markdown(nb3)
        @test occursin("My Test Notebook", md3)
    end
end


# ─────────────────────────────────────────────────────────────────────────────
# export_notebook multi-format
# ─────────────────────────────────────────────────────────────────────────────
@testset "export_notebook formats" begin
    nb = Notebook([Cell("z = 99")])

    @testset ":markdown format" begin
        out = export_notebook(nb; format=:markdown)
        @test occursin("z = 99", out)
        @test occursin("```julia", out)
    end

    @testset ":script format" begin
        out = export_notebook(nb; format=:script)
        @test occursin("z = 99", out)
        # Julia notebook scripts start with the Pluto header
        @test occursin("### A Pluto.jl notebook ###", out)
    end

    @testset "unsupported format throws" begin
        @test_throws ArgumentError export_notebook(nb; format=:pdf)
    end
end
