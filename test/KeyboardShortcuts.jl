using Test
import Pluto
import Pluto.KeyboardShortcuts:
    KeyboardShortcut, ShortcutMap,
    default_shortcuts, register_shortcut!,
    resolve_conflicts, shortcut_hints, is_accessible

@testset "KeyboardShortcuts" begin

    # ------------------------------------------------------------------
    @testset "KeyboardShortcut struct" begin
        s = KeyboardShortcut(:run_cell, "Shift+Enter", "Run the cell", :cell, "Run cell")
        @test s.action === :run_cell
        @test s.key == "Shift+Enter"
        @test s.description == "Run the cell"
        @test s.context === :cell
        @test s.accessibility_label == "Run cell"
    end

    # ------------------------------------------------------------------
    @testset "default_shortcuts" begin
        map = default_shortcuts()

        # Returns the correct type
        @test map isa ShortcutMap

        # All expected actions are present
        expected_actions = [
            :run_cell, :run_cell_and_next, :run_all, :interrupt,
            :add_cell_below, :delete_cell, :move_cell_up, :move_cell_down,
            :fold_cell, :save_notebook, :toggle_live_docs,
            :focus_prev_cell, :focus_next_cell,
        ]
        for action in expected_actions
            @test haskey(map, action)
        end

        # All shortcuts have non-empty keys
        for (action, s) in map
            @test !isempty(s.key)
        end

        # Context values are valid symbols
        valid_contexts = Set([:global, :cell, :editor])
        for (action, s) in map
            @test s.context ∈ valid_contexts
        end
    end

    # ------------------------------------------------------------------
    @testset "register_shortcut!" begin
        map = default_shortcuts()
        original_len = length(map)

        # Add a brand-new shortcut
        custom = KeyboardShortcut(:my_action, "Ctrl+M", "My custom action", :global, "My action")
        result = register_shortcut!(map, custom)

        @test result === map                          # returns the same dict
        @test length(map) == original_len + 1
        @test map[:my_action] === custom

        # Overwrite an existing shortcut
        replacement = KeyboardShortcut(:run_cell, "Ctrl+R", "Run cell (custom)", :cell, "Run cell custom")
        register_shortcut!(map, replacement)

        @test map[:run_cell] === replacement
        @test length(map) == original_len + 1        # count unchanged
    end

    # ------------------------------------------------------------------
    @testset "resolve_conflicts" begin
        map = default_shortcuts()

        # Default map should have NO conflicts
        conflicts = resolve_conflicts(map)
        @test isempty(conflicts)

        # Inject a conflict manually
        duplicate = KeyboardShortcut(:another_action, "Shift+Enter", "Duplicate key", :cell, "Duplicate")
        register_shortcut!(map, duplicate)

        conflicts = resolve_conflicts(map)
        @test length(conflicts) == 1
        actions_in_conflict = Set([conflicts[1][1].action, conflicts[1][2].action])
        @test :run_cell ∈ actions_in_conflict
        @test :another_action ∈ actions_in_conflict

        # Same key in a DIFFERENT context should NOT be a conflict
        no_conflict = KeyboardShortcut(:same_key_global, "Shift+Enter", "Global action", :global, "Global")
        register_shortcut!(map, no_conflict)
        conflicts2 = resolve_conflicts(map)
        # still only 1 conflict (cell context), not 3
        @test length(conflicts2) == 1
    end

    # ------------------------------------------------------------------
    @testset "shortcut_hints" begin
        map = default_shortcuts()

        # Global context
        global_hints = shortcut_hints(map, :global)
        @test global_hints isa Vector
        for h in global_hints
            @test h.action isa Symbol
            @test h.key isa String
            @test h.description isa String
            @test h.accessibility_label isa String
            @test h isa NamedTuple
        end

        # Every hint returned for :global must actually be global
        global_actions = Set(s.action for s in values(map) if s.context === :global)
        @test Set(h.action for h in global_hints) == global_actions

        # context=:all returns all shortcuts
        all_hints = shortcut_hints(map, :all)
        @test length(all_hints) == length(map)

        # Results are sorted by action name
        names = [string(h.action) for h in all_hints]
        @test names == sort(names)

        # Default (no second argument) returns global shortcuts
        default_hints = shortcut_hints(map)
        @test Set(h.action for h in default_hints) == global_actions
    end

    # ------------------------------------------------------------------
    @testset "is_accessible – single shortcut" begin
        good = KeyboardShortcut(:x, "Ctrl+X", "Cut", :global, "Cut")
        @test is_accessible(good) == true

        no_label = KeyboardShortcut(:x, "Ctrl+X", "Cut", :global, "")
        @test is_accessible(no_label) == false

        no_desc = KeyboardShortcut(:x, "Ctrl+X", "", :global, "Cut")
        @test is_accessible(no_desc) == false

        no_key = KeyboardShortcut(:x, "", "Cut", :global, "Cut")
        @test is_accessible(no_key) == false
    end

    # ------------------------------------------------------------------
    @testset "is_accessible – ShortcutMap" begin
        # Default map should be fully accessible
        @test is_accessible(default_shortcuts()) == true

        # Inserting an inaccessible shortcut makes the map fail
        bad_map = default_shortcuts()
        register_shortcut!(bad_map, KeyboardShortcut(:bad, "Ctrl+Z", "Undo", :global, ""))
        @test is_accessible(bad_map) == false
    end

    # ------------------------------------------------------------------
    @testset "ShortcutMap is a Dict" begin
        map = default_shortcuts()
        @test map isa Dict{Symbol, KeyboardShortcut}
        @test haskey(map, :run_cell)
        @test !haskey(map, :nonexistent_action)
    end

end
