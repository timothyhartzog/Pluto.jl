@testset "SidebarActions" begin
    using Test
    import Pluto.SidebarActions:
        Action, ActionRegistry, NotebookContext,
        register!, available_actions, default_registry,
        ACTION_LOAD_DATA, ACTION_PROFILE_DATA, ACTION_CLEAN_DATA,
        ACTION_PLOT_SUGGESTIONS, ACTION_EXPORT

    # -----------------------------------------------------------------------
    # NotebookContext construction
    # -----------------------------------------------------------------------
    @testset "NotebookContext" begin
        ctx = NotebookContext(0, false, false, false, Set{Symbol}())
        @test ctx.cell_count == 0
        @test !ctx.has_data_loading
        @test !ctx.has_dataframe
        @test !ctx.has_plots
        @test isempty(ctx.defined_symbols)

        ctx2 = NotebookContext(5, true, true, false, Set([:df, :x]))
        @test ctx2.cell_count == 5
        @test ctx2.has_data_loading
        @test ctx2.has_dataframe
        @test !ctx2.has_plots
        @test :df ∈ ctx2.defined_symbols
    end

    # -----------------------------------------------------------------------
    # Action struct
    # -----------------------------------------------------------------------
    @testset "Action struct" begin
        always_on = Action(:test, "Test", "A test action", _ -> true, "# code")
        @test always_on.id == :test
        @test always_on.label == "Test"
        @test always_on.description == "A test action"
        @test always_on.code_template == "# code"
        ctx = NotebookContext(0, false, false, false, Set{Symbol}())
        @test always_on.is_available(ctx) === true
    end

    # -----------------------------------------------------------------------
    # ActionRegistry: register! and available_actions
    # -----------------------------------------------------------------------
    @testset "ActionRegistry" begin
        registry = ActionRegistry()
        @test isempty(registry.actions)

        a1 = Action(:a1, "A1", "", _ -> true,  "")
        a2 = Action(:a2, "A2", "", _ -> false, "")
        a3 = Action(:a3, "A3", "", ctx -> ctx.has_data_loading, "")

        register!(registry, a1)
        register!(registry, a2)
        register!(registry, a3)

        @test length(registry.actions) == 3

        empty_ctx  = NotebookContext(0, false, false, false, Set{Symbol}())
        data_ctx   = NotebookContext(3, true,  false, false, Set{Symbol}())

        avail_empty = available_actions(registry, empty_ctx)
        @test length(avail_empty) == 1
        @test avail_empty[1].id == :a1

        avail_data = available_actions(registry, data_ctx)
        @test length(avail_data) == 2
        @test Set(a.id for a in avail_data) == Set([:a1, :a3])
    end

    # -----------------------------------------------------------------------
    # register! returns the registry (chainable)
    # -----------------------------------------------------------------------
    @testset "register! is chainable" begin
        reg = ActionRegistry()
        a = Action(:x, "X", "", _ -> true, "")
        result = register!(reg, a)
        @test result === reg
    end

    # -----------------------------------------------------------------------
    # Default registry
    # -----------------------------------------------------------------------
    @testset "default_registry" begin
        reg = default_registry()
        @test length(reg.actions) == 5

        ids = Set(a.id for a in reg.actions)
        @test :load_data        ∈ ids
        @test :profile_data     ∈ ids
        @test :clean_data       ∈ ids
        @test :plot_suggestions ∈ ids
        @test :export           ∈ ids
    end

    # -----------------------------------------------------------------------
    # Default action availability
    # -----------------------------------------------------------------------
    @testset "default action availability" begin
        empty_ctx  = NotebookContext(0, false, false, false, Set{Symbol}())
        data_ctx   = NotebookContext(3, true,  false, false, Set{Symbol}())
        df_ctx     = NotebookContext(3, false, true,  false, Set{Symbol}())
        full_ctx   = NotebookContext(5, true,  true,  true,  Set([:df]))

        # Load Data: always available
        @test ACTION_LOAD_DATA.is_available(empty_ctx)
        @test ACTION_LOAD_DATA.is_available(data_ctx)

        # Profile Data: requires data_loading or dataframe
        @test !ACTION_PROFILE_DATA.is_available(empty_ctx)
        @test  ACTION_PROFILE_DATA.is_available(data_ctx)
        @test  ACTION_PROFILE_DATA.is_available(df_ctx)
        @test  ACTION_PROFILE_DATA.is_available(full_ctx)

        # Clean Data: requires data_loading or dataframe
        @test !ACTION_CLEAN_DATA.is_available(empty_ctx)
        @test  ACTION_CLEAN_DATA.is_available(data_ctx)
        @test  ACTION_CLEAN_DATA.is_available(df_ctx)

        # Plot Suggestions: requires data_loading or dataframe
        @test !ACTION_PLOT_SUGGESTIONS.is_available(empty_ctx)
        @test  ACTION_PLOT_SUGGESTIONS.is_available(data_ctx)
        @test  ACTION_PLOT_SUGGESTIONS.is_available(df_ctx)

        # Export: requires at least one cell
        @test !ACTION_EXPORT.is_available(empty_ctx)
        @test  ACTION_EXPORT.is_available(data_ctx)
        @test  ACTION_EXPORT.is_available(full_ctx)
    end

    # -----------------------------------------------------------------------
    # Extensibility: custom actions can be added to a registry
    # -----------------------------------------------------------------------
    @testset "extensibility" begin
        reg = default_registry()
        custom = Action(
            :my_custom,
            "My Custom Action",
            "Does something special",
            ctx -> ctx.has_plots,
            "# custom code",
        )
        register!(reg, custom)
        @test length(reg.actions) == 6

        no_plot_ctx = NotebookContext(2, false, false, false, Set{Symbol}())
        plot_ctx    = NotebookContext(2, false, false, true,  Set{Symbol}())

        avail_no_plot = available_actions(reg, no_plot_ctx)
        @test !any(a.id == :my_custom for a in avail_no_plot)

        avail_plot = available_actions(reg, plot_ctx)
        @test  any(a.id == :my_custom for a in avail_plot)
    end

    # -----------------------------------------------------------------------
    # notebook_context helper
    # -----------------------------------------------------------------------
    @testset "notebook_context" begin
        import Pluto.SidebarActions: notebook_context

        # Empty notebook
        nb_empty = Pluto.Notebook(Pluto.Cell[], tempname() * ".jl")
        ctx = notebook_context(nb_empty)
        @test ctx.cell_count == 0
        @test !ctx.has_data_loading
        @test !ctx.has_dataframe
        @test !ctx.has_plots

        # Notebook with a CSV data-loading cell
        csv_cell = Pluto.Cell("import CSV, DataFrames\ndf = CSV.read(\"path/to/your_file.csv\", DataFrames.DataFrame)")
        nb_data = Pluto.Notebook([csv_cell], tempname() * ".jl")
        ctx2 = notebook_context(nb_data)
        @test ctx2.cell_count == 1
        @test ctx2.has_data_loading

        # Notebook with a DataFrames cell
        df_cell = Pluto.Cell("using DataFrames\ndf = DataFrame(a=[1,2,3])")
        nb_df = Pluto.Notebook([df_cell], tempname() * ".jl")
        ctx3 = notebook_context(nb_df)
        @test ctx3.has_dataframe

        # Notebook with a Plots cell
        plot_cell = Pluto.Cell("using Plots\nplot([1,2,3])")
        nb_plot = Pluto.Notebook([plot_cell], tempname() * ".jl")
        ctx4 = notebook_context(nb_plot)
        @test ctx4.has_plots
    end
end
