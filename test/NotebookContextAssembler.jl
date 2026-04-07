import Pluto: Pluto, Cell, Notebook
import Pluto.NotebookContextAssembler:
    NotebookContext, CellContext, DatasetProfile,
    assemble_context, render_prompt, profile_dataset,
    summarise_output, truncate_string,
    DEFAULT_MAX_CELLS, DEFAULT_MAX_CELL_OUTPUT_CHARS, DEFAULT_MAX_PROMPT_CHARS,
    TRUNCATION_MARKER

using Test
using UUIDs: uuid4

# ─── helpers ──────────────────────────────────────────────────────────────────

"Build a minimal notebook with the given cell codes."
function make_notebook(codes::Vector{String})
    cells = [Cell(c) for c in codes]
    Notebook(cells, tempname())
end

"Return a fresh `CellOutput` with a plain-text body."
function text_output(s::String)
    Pluto.CellOutput(body=s, mime=MIME("text/plain"))
end

# ─── truncate_string ──────────────────────────────────────────────────────────

@testset "truncate_string" begin
    @test truncate_string("hello", 10) == "hello"
    @test truncate_string("hello", 5)  == "hello"
    @test truncate_string("hello world", 5) == "hello" * TRUNCATION_MARKER
    @test endswith(truncate_string("a"^1000, 100), TRUNCATION_MARKER)
    @test length(truncate_string("a"^1000, 100)) == 100 + length(TRUNCATION_MARKER)
end

# ─── summarise_output ─────────────────────────────────────────────────────────

@testset "summarise_output" begin
    nothing_out = Pluto.CellOutput()
    @test summarise_output(nothing_out, 200) == ""

    str_out = text_output("hello")
    @test summarise_output(str_out, 200) == "hello"

    # truncation
    long = "x"^1000
    result = summarise_output(text_output(long), 100)
    @test startswith(result, "x"^100)
    @test endswith(result, TRUNCATION_MARKER)

    # binary output
    bin_out = Pluto.CellOutput(body=UInt8[0x01, 0x02, 0x03])
    s = summarise_output(bin_out, 200)
    @test occursin("3", s)
    @test occursin("bytes", s)

    # dict output
    dict_out = Pluto.CellOutput(body=Dict("text" => "result"))
    @test summarise_output(dict_out, 200) == "result"

    # dict without "text" key falls back to repr
    dict_out2 = Pluto.CellOutput(body=Dict("value" => 42))
    s2 = summarise_output(dict_out2, 200)
    @test !isempty(s2)
end

# ─── profile_dataset ──────────────────────────────────────────────────────────

@testset "profile_dataset" begin
    dp = profile_dataset("mymatrix", ones(4, 3))
    @test dp.name == "mymatrix"
    @test occursin("Float64", dp.type_summary)
    @test occursin("4", dp.size_info)
    @test occursin("3", dp.size_info)
    @test !isempty(dp.sample_values)

    dp_vec = profile_dataset("v", [10, 20, 30])
    @test dp_vec.name == "v"
    @test occursin("3", dp_vec.size_info)
    @test occursin("10", dp_vec.sample_values)

    dp_scalar = profile_dataset("x", 42)
    @test dp_scalar.name == "x"
    @test !isempty(dp_scalar.size_info)
end

# ─── assemble_context ─────────────────────────────────────────────────────────

@testset "assemble_context" begin
    nb = make_notebook(["x = 1", "y = x + 1", "z = y * 2"])

    ctx = assemble_context(nb, "What is z?")

    @test ctx.user_request == "What is z?"
    @test length(ctx.cells) == 3
    @test ctx.cells[1].code == "x = 1"
    @test ctx.cells[2].code == "y = x + 1"
    @test ctx.cells[3].code == "z = y * 2"
    @test isempty(ctx.dataset_profiles)
    @test ctx.notebook_metadata isa Dict

    @testset "max_cells limit" begin
        ctx2 = assemble_context(nb, "hi"; max_cells=2)
        @test length(ctx2.cells) == 2
    end

    @testset "disabled cells are excluded" begin
        nb2 = make_notebook(["a = 1", "b = 2", "c = 3"])
        nb2.cells[2].metadata["disabled"] = true
        ctx3 = assemble_context(nb2, "test")
        @test length(ctx3.cells) == 2
        @test all(cc -> cc.code != "b = 2", ctx3.cells)
    end

    @testset "cell outputs are captured and truncated" begin
        nb3 = make_notebook(["result = 99"])
        nb3.cells[1].output = text_output("99")
        ctx4 = assemble_context(nb3, "what?"; max_cell_output_chars=3)
        @test startswith(ctx4.cells[1].output_summary, "99")
        # output is short enough – no truncation
        ctx5 = assemble_context(nb3, "what?"; max_cell_output_chars=200)
        @test ctx5.cells[1].output_summary == "99"
    end

    @testset "errored cells are flagged" begin
        nb4 = make_notebook(["sqrt(-1)"])
        nb4.cells[1].errored = true
        ctx6 = assemble_context(nb4, "why error?")
        @test ctx6.cells[1].errored == true
    end

    @testset "dataset profiles are passed through" begin
        dp = profile_dataset("ds", [1, 2, 3])
        ctx7 = assemble_context(nb, "analyze"; dataset_profiles=[dp])
        @test length(ctx7.dataset_profiles) == 1
        @test ctx7.dataset_profiles[1].name == "ds"
    end
end

# ─── render_prompt ────────────────────────────────────────────────────────────

@testset "render_prompt" begin
    nb = make_notebook(["x = 1", "y = x + 1"])
    nb.cells[1].output = text_output("1")
    ctx = assemble_context(nb, "Explain the code.")

    prompt = render_prompt(ctx)
    @test prompt isa String
    @test occursin("Explain the code.", prompt)
    @test occursin("x = 1", prompt)
    @test occursin("y = x + 1", prompt)
    @test occursin("1", prompt)   # cell 1 output

    @testset "deterministic output" begin
        p1 = render_prompt(ctx)
        p2 = render_prompt(ctx)
        @test p1 == p2
    end

    @testset "max_chars limit" begin
        long_code = "x = " * "1"^500
        nb2 = make_notebook([long_code])
        ctx2 = assemble_context(nb2, "test")
        prompt2 = render_prompt(ctx2; max_chars=100)
        @test length(prompt2) == 100 + length(TRUNCATION_MARKER)
        @test endswith(prompt2, TRUNCATION_MARKER)
    end

    @testset "dataset profiles appear in prompt" begin
        dp = profile_dataset("mat", ones(2, 2))
        ctx3 = assemble_context(nb, "profile it"; dataset_profiles=[dp])
        p3 = render_prompt(ctx3)
        @test occursin("mat", p3)
        @test occursin("Float64", p3)
    end

    @testset "errored cell flagged in prompt" begin
        nb3 = make_notebook(["bad_code()"])
        nb3.cells[1].errored = true
        ctx4 = assemble_context(nb3, "fix it")
        p4 = render_prompt(ctx4)
        @test occursin("error", p4)
    end

    @testset "notebook metadata appears in prompt" begin
        nb4 = make_notebook(["1 + 1"])
        nb4.metadata["title"] = "My Notebook"
        ctx5 = assemble_context(nb4, "describe")
        p5 = render_prompt(ctx5)
        @test occursin("My Notebook", p5)
    end
end
