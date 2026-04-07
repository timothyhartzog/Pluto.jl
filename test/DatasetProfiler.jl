import Pluto
import Pluto.DatasetProfiler

using Test

@testset "DatasetProfiler" begin

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    # A minimal Tables.jl-compatible NamedTuple of vectors
    simple_table = (
        a = [1, 2, 3, 4, 5],
        b = ["x", "y", "x", "z", "y"],
    )

    # Table with missing values
    missing_table = (
        score = Union{Int, Missing}[10, missing, 30, missing, 50],
        label = Union{String, Missing}["cat", "dog", missing, "cat", "dog"],
    )

    @testset "profile_column – numeric" begin
        col = [1.0, 2.0, 3.0, 4.0, 5.0]
        cp = DatasetProfiler.profile_column(:val, col)

        @test cp.name == "val"
        @test cp.n_rows == 5
        @test cp.n_missing == 0
        @test cp.missingness == 0.0
        @test cp.n_unique == 5
        @test cp.uniqueness == 1.0
        @test cp.min == 1.0
        @test cp.max == 5.0
        @test cp.mean ≈ 3.0
        @test cp.std ≈ sqrt(2.5)
        @test cp.median == 3.0
        @test isempty(cp.top_values)
    end

    @testset "profile_column – categorical" begin
        col = ["a", "b", "a", "c", "b", "a"]
        cp = DatasetProfiler.profile_column(:cat, col)

        @test cp.name == "cat"
        @test cp.n_rows == 6
        @test cp.n_missing == 0
        @test cp.n_unique == 3
        @test cp.min === nothing
        @test cp.max === nothing
        @test cp.mean === nothing
        # Top value should be "a" with count 3
        @test !isempty(cp.top_values)
        @test cp.top_values[1].first == "a"
        @test cp.top_values[1].second == 3
    end

    @testset "profile_column – with missing values" begin
        col = Union{Int, Missing}[1, missing, 3, missing, 5]
        cp = DatasetProfiler.profile_column(:m, col)

        @test cp.n_rows == 5
        @test cp.n_missing == 2
        @test cp.missingness ≈ 0.4
        @test cp.n_unique == 3  # 1, 3, 5
        @test cp.uniqueness ≈ 1.0
        @test cp.min == 1.0
        @test cp.max == 5.0
        @test cp.mean ≈ 3.0
        @test cp.median == 3.0
    end

    @testset "profile_column – empty column" begin
        col = Int[]
        cp = DatasetProfiler.profile_column(:empty, col)

        @test cp.n_rows == 0
        @test cp.n_missing == 0
        @test cp.missingness == 0.0
        @test cp.n_unique == 0
        @test cp.uniqueness == 0.0
        @test cp.min === nothing
        @test cp.max === nothing
    end

    @testset "profile_dataset – simple table" begin
        dp = DatasetProfiler.profile_dataset(simple_table)

        @test dp.n_rows == 5
        @test dp.n_cols == 2
        @test length(dp.columns) == 2
        @test dp.columns[1].name == "a"
        @test dp.columns[2].name == "b"
        # Column a is numeric
        @test dp.columns[1].min !== nothing
        # Column b is categorical
        @test dp.columns[2].min === nothing
        @test !isempty(dp.columns[2].top_values)
    end

    @testset "profile_dataset – table with missing values" begin
        dp = DatasetProfiler.profile_dataset(missing_table)

        @test dp.n_rows == 5
        @test dp.n_cols == 2

        score_col = dp.columns[1]
        @test score_col.name == "score"
        @test score_col.n_missing == 2
        @test score_col.missingness ≈ 0.4
        @test score_col.n_unique == 3
        @test score_col.mean ≈ 30.0
        @test score_col.min == 10.0
        @test score_col.max == 50.0

        label_col = dp.columns[2]
        @test label_col.name == "label"
        @test label_col.n_missing == 1
        @test label_col.n_unique == 2
        @test !isempty(label_col.top_values)
    end

    @testset "profile_dataset – invalid input" begin
        @test_throws ArgumentError DatasetProfiler.profile_dataset(42)
        @test_throws ArgumentError DatasetProfiler.profile_dataset("not a table")
    end

    @testset "serialize_profile" begin
        dp = DatasetProfiler.profile_dataset(simple_table)
        s = DatasetProfiler.serialize_profile(dp)

        @test s isa String
        @test occursin("5 rows", s)
        @test occursin("2 columns", s)
        @test occursin("Column: a", s)
        @test occursin("Column: b", s)
        # Numeric column should show min/max/mean/std/median
        @test occursin("Min", s)
        @test occursin("Max", s)
        @test occursin("Mean", s)
        @test occursin("Std", s)
        @test occursin("Median", s)
        # Categorical column should show top values
        @test occursin("Top values", s)
    end

    @testset "serialize_profile – with missing values" begin
        dp = DatasetProfiler.profile_dataset(missing_table)
        s = DatasetProfiler.serialize_profile(dp)

        @test occursin("Missing", s)
        @test occursin("40.0%", s)  # 2/5 = 40%
    end

    @testset "profile_dataset – boolean column treated as categorical" begin
        tbl = (flag = [true, false, true, true, false],)
        dp = DatasetProfiler.profile_dataset(tbl)
        col = dp.columns[1]
        # Bool is not treated as numeric
        @test col.min === nothing
        @test !isempty(col.top_values)
    end

end
