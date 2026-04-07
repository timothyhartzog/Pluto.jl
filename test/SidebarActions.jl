import Pluto
import Pluto.SidebarActions:
    Action, ActionRegistry, NotebookContext,
    register!, available_actions, notebook_context, default_registry,
    load_data, profile_data, clean_data, plot_suggestions, export_action

using Test

@testset "SidebarActions" begin

    @testset "NotebookContext construction" begin
        ctx = NotebookContext()
        @test ctx.has_data_cells  == false
        @test ctx.has_dataframes  == false
        @test ctx.has_plots       == false
        @test ctx.cell_count      == 0
        @test ctx.defined_symbols == Symbol[]

        ctx2 = NotebookContext(
            has_data_cells  = true,
            has_dataframes  = true,
            has_plots       = true,
            cell_count      = 5,
            defined_symbols = [:df, :x],
        )
        @test ctx2.has_data_cells  == true
        @test ctx2.has_dataframes  == true
        @test ctx2.has_plots       == true
        @test ctx2.cell_count      == 5
        @test ctx2.defined_symbols == [:df, :x]
    end

    @testset "Action construction" begin
        a = Action(:foo, "Foo", "Do foo")
        @test a.id          === :foo
        @test a.name        == "Foo"
        @test a.description == "Do foo"
        # Default availability: always true
        @test a.available(NotebookContext()) == true

        b = Action(:bar, "Bar", "Do bar", ctx -> ctx.has_plots)
        @test b.available(NotebookContext(has_plots = true))  == true
        @test b.available(NotebookContext(has_plots = false)) == false
    end

    @testset "ActionRegistry register! and deduplication" begin
        reg = ActionRegistry()
        @test isempty(reg.actions)

        a1 = Action(:a, "A", "First A")
        register!(reg, a1)
        @test length(reg.actions) == 1

        # Registering a second action with the same id replaces the first
        a2 = Action(:a, "A v2", "Second A")
        register!(reg, a2)
        @test length(reg.actions) == 1
        @test reg.actions[1].name == "A v2"

        register!(reg, Action(:b, "B", "B"))
        @test length(reg.actions) == 2
    end

    @testset "available_actions filters by context" begin
        reg = ActionRegistry()
        register!(reg, Action(:always,    "Always",    "Always available"))
        register!(reg, Action(:needs_df,  "Needs DF",  "Needs DataFrame",  ctx -> ctx.has_dataframes))
        register!(reg, Action(:needs_plt, "Needs Plot","Needs plots",      ctx -> ctx.has_plots))

        empty_ctx = NotebookContext()
        @test length(available_actions(reg, empty_ctx)) == 1
        @test available_actions(reg, empty_ctx)[1].id === :always

        df_ctx = NotebookContext(has_dataframes = true)
        avail  = available_actions(reg, df_ctx)
        ids    = [a.id for a in avail]
        @test :always   ∈ ids
        @test :needs_df ∈ ids
        @test :needs_plt ∉ ids

        full_ctx = NotebookContext(has_dataframes = true, has_plots = true)
        @test length(available_actions(reg, full_ctx)) == 3
    end

    @testset "default_registry" begin
        reg = default_registry()

        # All five default actions are present
        ids = [a.id for a in reg.actions]
        @test :load_data        ∈ ids
        @test :profile_data     ∈ ids
        @test :clean_data       ∈ ids
        @test :plot_suggestions ∈ ids
        @test :export           ∈ ids
        @test length(ids) == 5

        # load_data is always available
        @test load_data.available(NotebookContext()) == true

        # profile_data, clean_data, plot_suggestions require data or dataframes
        for action in (profile_data, clean_data, plot_suggestions)
            @test action.available(NotebookContext())                           == false
            @test action.available(NotebookContext(has_data_cells  = true))    == true
            @test action.available(NotebookContext(has_dataframes  = true))    == true
        end

        # export requires at least one cell
        @test export_action.available(NotebookContext(cell_count = 0)) == false
        @test export_action.available(NotebookContext(cell_count = 1)) == true
    end

    @testset "default_registry available_actions with empty notebook" begin
        reg = default_registry()
        ctx = NotebookContext()
        avail = available_actions(reg, ctx)
        ids   = [a.id for a in avail]
        # Only load_data is available when the notebook is empty
        @test ids == [:load_data]
    end

    @testset "default_registry available_actions with data notebook" begin
        reg = default_registry()
        ctx = NotebookContext(has_data_cells = true, has_dataframes = true, cell_count = 3)
        avail = available_actions(reg, ctx)
        ids   = [a.id for a in avail]
        @test :load_data        ∈ ids
        @test :profile_data     ∈ ids
        @test :clean_data       ∈ ids
        @test :plot_suggestions ∈ ids
        @test :export           ∈ ids
    end

    @testset "notebook_context from Notebook object" begin
        # Build a minimal notebook-like struct using actual Pluto cells
        nb = Pluto.Notebook([
            Pluto.Cell("using CSV; df = CSV.read(\"data.csv\", DataFrame)"),
            Pluto.Cell("plot(df.x, df.y)"),
        ])

        ctx = notebook_context(nb)
        @test ctx.has_data_cells == true
        @test ctx.has_dataframes == true
        @test ctx.has_plots      == true
        @test ctx.cell_count     == 2
    end

    @testset "notebook_context from empty Notebook" begin
        nb  = Pluto.Notebook(Pluto.Cell[])
        ctx = notebook_context(nb)
        @test ctx.has_data_cells == false
        @test ctx.has_dataframes == false
        @test ctx.has_plots      == false
        @test ctx.cell_count     == 0
    end

    @testset "registry is extensible" begin
        reg = default_registry()
        custom = Action(:my_action, "My Action", "Custom plugin action",
                        ctx -> ctx.cell_count >= 10)
        register!(reg, custom)

        @test length(reg.actions) == 6
        @test any(a -> a.id === :my_action, reg.actions)

        @test custom.available(NotebookContext(cell_count = 9))  == false
        @test custom.available(NotebookContext(cell_count = 10)) == true
    end
end
