import Pluto
import Pluto.Cleaning

using Test

@testset "Cleaning" begin

    # -----------------------------------------------------------------------
    # Helpers: build sample CleaningTable instances

    function make_table()
        Cleaning.CleaningTable(
            :age    => Union{Int,Missing}[25, missing, 30, missing, 45],
            :salary => Union{Float64,Missing}[50000.0, 60000.0, missing, 80000.0, missing],
            :name   => Union{String,Missing}["Alice", "Bob", missing, "Dave", "Eve"],
        )
    end

    function make_simple()
        Cleaning.CleaningTable(
            :x => [1, 2, 3, 4, 5],
            :y => [10.0, 20.0, 30.0, 40.0, 50.0],
        )
    end

    # -----------------------------------------------------------------------
    @testset "CleaningTable basics" begin
        t = make_table()
        @test length(t) == 5
        @test haskey(t, :age)
        @test !haskey(t, :unknown)
        @test t[:age][1] == 25
        @test ismissing(t[:age][2])
        @test keys(t) == [:age, :salary, :name]
    end

    @testset "copy" begin
        t = make_table()
        c = copy(t)
        @test isequal(c[:age], t[:age])
        # modifying copy does not affect original
        c.columns[:age][1] = 99
        @test t[:age][1] == 25
    end

    @testset "to_namedtuple" begin
        t = make_simple()
        nt = Cleaning.to_namedtuple(t)
        @test nt isa NamedTuple
        @test nt.x == [1, 2, 3, 4, 5]
        @test nt.y == [10.0, 20.0, 30.0, 40.0, 50.0]
    end

    # -----------------------------------------------------------------------
    @testset "DropMissing" begin
        t = make_table()

        @testset "all columns" begin
            result = Cleaning.apply_operation(t, Cleaning.DropMissing())
            # rows with any missing: rows 2, 3, 4, 5 (indices) — let's check
            # row2: age missing; row3: salary missing; row4: age missing; row5: salary missing
            # row1 is complete
            @test length(result) == 1
            @test result[:name][1] == "Alice"
        end

        @testset "specific column" begin
            result = Cleaning.apply_operation(t, Cleaning.DropMissing(columns=[:age]))
            # drops rows 2 and 4 (age is missing)
            @test length(result) == 3
            @test all(!ismissing, result[:age])
        end

        @testset "no missing rows unchanged" begin
            t2 = make_simple()
            result = Cleaning.apply_operation(t2, Cleaning.DropMissing())
            @test length(result) == 5
        end
    end

    # -----------------------------------------------------------------------
    @testset "FillConstant" begin
        t = make_table()

        @testset "fill age with 0" begin
            op = Cleaning.FillConstant(0, columns=[:age])
            result = Cleaning.apply_operation(t, op)
            @test result[:age][2] == 0
            @test result[:age][4] == 0
            @test result[:age][1] == 25
        end

        @testset "fill all with missing stays missing where not applicable" begin
            op = Cleaning.FillConstant("N/A")
            result = Cleaning.apply_operation(t, op)
            # name row3 was missing → filled
            @test result[:name][3] == "N/A"
            # non-missing values preserved
            @test result[:name][1] == "Alice"
        end
    end

    # -----------------------------------------------------------------------
    @testset "FillMean" begin
        t = make_table()
        op = Cleaning.FillMean(columns=[:age, :salary])
        result = Cleaning.apply_operation(t, op)

        # age non-missing: 25, 30, 45 → mean = 100/3 ≈ 33.33
        expected_age_mean = (25 + 30 + 45) / 3
        @test result[:age][2] ≈ expected_age_mean
        @test result[:age][4] ≈ expected_age_mean

        # salary non-missing: 50000, 60000, 80000 → mean = 190000/3
        expected_salary_mean = (50000.0 + 60000.0 + 80000.0) / 3
        @test result[:salary][3] ≈ expected_salary_mean
        @test result[:salary][5] ≈ expected_salary_mean

        # non-numeric column unaffected
        @test ismissing(result[:name][3])
    end

    # -----------------------------------------------------------------------
    @testset "FillMedian" begin
        t = make_table()
        op = Cleaning.FillMedian(columns=[:age])
        result = Cleaning.apply_operation(t, op)
        # age non-missing: 25, 30, 45 → median = 30.0
        @test result[:age][2] == 30.0
        @test result[:age][4] == 30.0
    end

    # -----------------------------------------------------------------------
    @testset "FillMode" begin
        t = Cleaning.CleaningTable(
            :category => Union{String,Missing}["A", "B", missing, "A", "B", "A"],
        )
        op = Cleaning.FillMode()
        result = Cleaning.apply_operation(t, op)
        # mode of ["A","B","A","B","A"] is "A"
        @test result[:category][3] == "A"
    end

    # -----------------------------------------------------------------------
    @testset "CastType" begin
        t = Cleaning.CleaningTable(
            :x => Any["1", "2", "3"],
        )
        op = Cleaning.CastType(Int, columns=[:x])
        result = Cleaning.apply_operation(t, op)
        @test result[:x] == [1, 2, 3]
        @test eltype(result[:x]) == Int
    end

    @testset "CastType preserves missing" begin
        t = Cleaning.CleaningTable(
            :x => Union{Float64,Missing}[1.0, missing, 3.0],
        )
        op = Cleaning.CastType(Int, columns=[:x])
        result = Cleaning.apply_operation(t, op)
        @test result[:x][1] == 1
        @test ismissing(result[:x][2])
        @test result[:x][3] == 3
    end

    # -----------------------------------------------------------------------
    @testset "NormalizeColumnNames" begin
        t = Cleaning.CleaningTable(
            Symbol("First Name") => ["Alice", "Bob"],
            :Age => [25, 30],
            Symbol("salary-USD") => [50000.0, 60000.0],
        )
        op = Cleaning.NormalizeColumnNames()
        result = Cleaning.apply_operation(t, op)
        @test :first_name ∈ keys(result)
        @test :age ∈ keys(result)
        @test :salary_usd ∈ keys(result)
        @test result[:first_name] == ["Alice", "Bob"]
    end

    # -----------------------------------------------------------------------
    @testset "preview_operation" begin

        @testset "DropMissing preview" begin
            t = make_table()
            pr = Cleaning.preview_operation(t, Cleaning.DropMissing())
            @test pr isa Cleaning.PreviewResult
            @test pr.affected_rows == 4  # rows 2,3,4,5 dropped
            @test occursin("DropMissing", pr.description)
        end

        @testset "FillConstant preview" begin
            t = make_table()
            pr = Cleaning.preview_operation(t, Cleaning.FillConstant(0, columns=[:age]))
            @test pr.affected_rows == 2
            @test :age ∈ pr.affected_columns
            @test all(ismissing, pr.sample_before[:age])
            @test all(==(0), pr.sample_after[:age])
        end

        @testset "FillMean preview" begin
            t = make_table()
            pr = Cleaning.preview_operation(t, Cleaning.FillMean(columns=[:age]))
            @test pr.affected_rows == 2
        end

        @testset "CastType preview" begin
            t = Cleaning.CleaningTable(:x => Any["1", "2"])
            pr = Cleaning.preview_operation(t, Cleaning.CastType(Int, columns=[:x]))
            @test pr isa Cleaning.PreviewResult
            @test :x ∈ pr.affected_columns
        end

        @testset "NormalizeColumnNames preview" begin
            t = Cleaning.CleaningTable(
                Symbol("First Name") => ["A"],
                :age => [1],
            )
            pr = Cleaning.preview_operation(t, Cleaning.NormalizeColumnNames())
            @test pr isa Cleaning.PreviewResult
            # Only "First Name" would be renamed; :age is already normalized
            @test length(pr.affected_columns) == 1
        end
    end

    # -----------------------------------------------------------------------
    @testset "CleaningPlan and undo" begin

        @testset "add_operation! updates table and records metadata" begin
            t = make_table()
            plan = Cleaning.CleaningPlan()
            @test isempty(plan.operations)

            t2 = Cleaning.add_operation!(plan, t, Cleaning.DropMissing(columns=[:age]))
            @test length(plan.operations) == 1
            @test length(t2) == 3  # dropped 2 rows
            @test plan.operations[1].description isa String
            @test !isempty(plan.operations[1].id)
            @test plan.operations[1].timestamp > 0.0
        end

        @testset "undo_last! restores previous state" begin
            t = make_table()
            plan = Cleaning.CleaningPlan()
            t2 = Cleaning.add_operation!(plan, t, Cleaning.DropMissing(columns=[:age]))
            @test length(t2) == 3

            restored = Cleaning.undo_last!(plan)
            @test restored isa Cleaning.CleaningTable
            @test length(restored) == 5  # back to original
            @test isempty(plan.operations)
        end

        @testset "undo_last! on empty plan returns nothing" begin
            plan = Cleaning.CleaningPlan()
            @test Cleaning.undo_last!(plan) === nothing
        end

        @testset "apply_plan chains operations" begin
            t = make_table()
            plan = Cleaning.CleaningPlan()
            # Step 1: fill age
            Cleaning.add_operation!(plan, t, Cleaning.FillConstant(0, columns=[:age]))
            # Step 2: fill salary
            Cleaning.add_operation!(plan, t, Cleaning.FillConstant(0.0, columns=[:salary]))

            result = Cleaning.apply_plan(t, plan)
            @test all(!ismissing, result[:age])
            @test all(!ismissing, result[:salary])
            @test length(result) == 5
        end

        @testset "multiple undo" begin
            t = make_table()
            plan = Cleaning.CleaningPlan()
            t2 = Cleaning.add_operation!(plan, t, Cleaning.FillConstant(0, columns=[:age]))
            t3 = Cleaning.add_operation!(plan, t2, Cleaning.FillConstant(0.0, columns=[:salary]))
            @test length(plan.operations) == 2

            Cleaning.undo_last!(plan)
            @test length(plan.operations) == 1

            Cleaning.undo_last!(plan)
            @test length(plan.operations) == 0
        end
    end

    # -----------------------------------------------------------------------
    @testset "round-trip: apply then undo restores original" begin
        t = make_table()
        plan = Cleaning.CleaningPlan()

        # Apply a fill operation
        _ = Cleaning.add_operation!(plan, t, Cleaning.FillMean(columns=[:age]))

        # Undo → should be same as original t
        restored = Cleaning.undo_last!(plan)
        @test length(restored) == length(t)
        for col in keys(t)
            orig_v = t[col]
            rest_v = restored[col]
            for i in 1:length(orig_v)
                if ismissing(orig_v[i])
                    @test ismissing(rest_v[i])
                else
                    @test rest_v[i] == orig_v[i]
                end
            end
        end
    end

end # @testset "Cleaning"
