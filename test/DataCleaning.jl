import Pluto
import Pluto.DataCleaning

using Test

# ---------------------------------------------------------------------------
# Shared test fixture
# ---------------------------------------------------------------------------

# A simple Tables.jl-compatible row-table
function make_table()
    [
        (name="Alice", age=30,     score=1.0),
        (name="Bob",   age=missing, score=4.0),
        (name="Carol", age=25,     score=missing),
        (name="Dave",  age=35,     score=9.0),
        (name="Eve",   age=missing, score=16.0),
    ]
end

function make_numeric_table()
    [(x=1.0,), (x=2.0,), (x=3.0,), (x=4.0,), (x=5.0,)]
end

# ---------------------------------------------------------------------------

@testset "DataCleaning" begin

    # -----------------------------------------------------------------------
    @testset "HandleMissingOperation – DropRows" begin
        tbl = make_table()
        op  = DataCleaning.HandleMissingOperation(:age, DataCleaning.DropRows)

        # preview – non-mutating
        prev = DataCleaning.preview_operation(tbl, op)
        @test prev.column         == :age
        @test prev.operation_type == :handle_missing
        @test prev.affected_rows  == 2    # Bob and Eve
        @test prev.rows_kept      == 3

        # apply
        new_tbl, meta = DataCleaning.apply_operation(tbl, op)
        @test length(new_tbl) == 3
        @test all(!ismissing(r.age) for r in new_tbl)

        # metadata
        @test meta.operation_type == :handle_missing
        @test meta.column         == :age
        @test length(meta.original_values) == 5
        @test meta.parameters[:strategy]   == DataCleaning.DropRows

        # undo not supported for DropRows
        @test_throws DomainError DataCleaning.undo_operation(new_tbl, meta)
    end

    # -----------------------------------------------------------------------
    @testset "HandleMissingOperation – FillConstant" begin
        tbl = make_table()
        op  = DataCleaning.HandleMissingOperation(:age, DataCleaning.FillConstant, 0)

        prev = DataCleaning.preview_operation(tbl, op)
        @test prev.affected_rows == 2
        @test all(!ismissing, prev.sample_after)

        new_tbl, meta = DataCleaning.apply_operation(tbl, op)
        @test length(new_tbl) == 5
        ages = [r.age for r in new_tbl]
        @test !any(ismissing, ages)
        @test ages[2] == 0  # Bob was filled
        @test ages[5] == 0  # Eve was filled

        # undo
        restored = DataCleaning.undo_operation(new_tbl, meta)
        @test ismissing(restored[2].age)
        @test ismissing(restored[5].age)
    end

    # -----------------------------------------------------------------------
    @testset "HandleMissingOperation – FillMean" begin
        tbl = make_table()
        op  = DataCleaning.HandleMissingOperation(:age, DataCleaning.FillMean)

        new_tbl, _ = DataCleaning.apply_operation(tbl, op)
        ages = [r.age for r in new_tbl]
        @test !any(ismissing, ages)
        expected_mean = (30 + 25 + 35) / 3
        @test ages[2] ≈ expected_mean atol=1e-9
    end

    # -----------------------------------------------------------------------
    @testset "HandleMissingOperation – FillMedian" begin
        tbl = make_table()
        op  = DataCleaning.HandleMissingOperation(:age, DataCleaning.FillMedian)

        new_tbl, _ = DataCleaning.apply_operation(tbl, op)
        ages = [r.age for r in new_tbl]
        @test !any(ismissing, ages)
        @test ages[2] == 30.0  # median of [30,25,35]
    end

    # -----------------------------------------------------------------------
    @testset "HandleMissingOperation – FillMode" begin
        tbl = [(x = 1,), (x = 2,), (x = 1,), (x = missing,)]
        op  = DataCleaning.HandleMissingOperation(:x, DataCleaning.FillMode)

        new_tbl, _ = DataCleaning.apply_operation(tbl, op)
        xs = [r.x for r in new_tbl]
        @test xs[4] == 1   # mode is 1
    end

    # -----------------------------------------------------------------------
    @testset "HandleMissingOperation – FillForward" begin
        tbl = [(x=1,), (x=missing,), (x=missing,), (x=4,)]
        op  = DataCleaning.HandleMissingOperation(:x, DataCleaning.FillForward)

        new_tbl, _ = DataCleaning.apply_operation(tbl, op)
        xs = [r.x for r in new_tbl]
        @test xs == [1, 1, 1, 4]
    end

    # -----------------------------------------------------------------------
    @testset "HandleMissingOperation – FillBackward" begin
        tbl = [(x=missing,), (x=missing,), (x=3,), (x=4,)]
        op  = DataCleaning.HandleMissingOperation(:x, DataCleaning.FillBackward)

        new_tbl, _ = DataCleaning.apply_operation(tbl, op)
        xs = [r.x for r in new_tbl]
        @test xs == [3, 3, 3, 4]
    end

    # -----------------------------------------------------------------------
    @testset "CastTypeOperation" begin
        tbl = [(v="1",), (v="2",), (v="abc",), (v="4",)]
        op  = DataCleaning.CastTypeOperation(:v, Int)

        prev = DataCleaning.preview_operation(tbl, op)
        @test prev.column              == :v
        @test prev.operation_type      == :cast_type
        @test prev.conversion_failures == 1   # "abc" can't be Int

        new_tbl, meta = DataCleaning.apply_operation(tbl, op)
        vs = [r.v for r in new_tbl]
        @test vs[1] == 1
        @test vs[2] == 2
        @test ismissing(vs[3])
        @test vs[4] == 4

        @test meta.operation_type == :cast_type
        @test meta.parameters[:target_type] == Int

        # undo
        restored = DataCleaning.undo_operation(new_tbl, meta)
        rvs = [r.v for r in restored]
        @test rvs[1] == "1"
        @test rvs[3] == "abc"
    end

    # -----------------------------------------------------------------------
    @testset "NormalizeOperation – MinMax" begin
        tbl = make_numeric_table()
        op  = DataCleaning.NormalizeOperation(:x, DataCleaning.MinMaxNormalization)

        prev = DataCleaning.preview_operation(tbl, op)
        @test prev.column         == :x
        @test prev.operation_type == :normalize
        @test prev.method         == DataCleaning.MinMaxNormalization

        new_tbl, meta = DataCleaning.apply_operation(tbl, op)
        xs = [r.x for r in new_tbl]
        @test xs[1] ≈ 0.0
        @test xs[end] ≈ 1.0
        @test all(0.0 .<= xs .<= 1.0)

        @test meta.operation_type == :normalize
        @test meta.parameters[:method] == DataCleaning.MinMaxNormalization

        # undo
        restored = DataCleaning.undo_operation(new_tbl, meta)
        rxs = [r.x for r in restored]
        @test rxs ≈ [1.0, 2.0, 3.0, 4.0, 5.0]
    end

    # -----------------------------------------------------------------------
    @testset "NormalizeOperation – ZScore" begin
        tbl = make_numeric_table()
        op  = DataCleaning.NormalizeOperation(:x, DataCleaning.ZScoreNormalization)

        new_tbl, _ = DataCleaning.apply_operation(tbl, op)
        xs = [r.x for r in new_tbl]
        μ = sum(xs) / length(xs)
        σ = sqrt(sum((x - μ)^2 for x in xs) / (length(xs) - 1))
        @test abs(μ) < 1e-9         # mean ≈ 0
        @test abs(σ - 1.0) < 1e-9  # sample std ≈ 1
    end

    # -----------------------------------------------------------------------
    @testset "NormalizeOperation – Robust" begin
        tbl = make_numeric_table()
        op  = DataCleaning.NormalizeOperation(:x, DataCleaning.RobustNormalization)

        new_tbl, _ = DataCleaning.apply_operation(tbl, op)
        xs = [r.x for r in new_tbl]
        @test any(x -> abs(x) < 1e-9, xs)   # median maps to 0
    end

    # -----------------------------------------------------------------------
    @testset "NormalizeOperation – with missing values" begin
        tbl = [(x=1.0,), (x=missing,), (x=3.0,), (x=4.0,), (x=5.0,)]
        op  = DataCleaning.NormalizeOperation(:x, DataCleaning.MinMaxNormalization)

        new_tbl, _ = DataCleaning.apply_operation(tbl, op)
        xs = [r.x for r in new_tbl]
        @test ismissing(xs[2])
        @test xs[1] ≈ 0.0
        @test xs[end] ≈ 1.0
    end

    # -----------------------------------------------------------------------
    @testset "OperationMetadata fields" begin
        tbl = make_numeric_table()
        op  = DataCleaning.NormalizeOperation(:x, DataCleaning.MinMaxNormalization)
        _, meta = DataCleaning.apply_operation(tbl, op)

        @test meta isa DataCleaning.OperationMetadata
        @test meta.column == :x
        @test length(meta.original_values) == 5
        @test meta.timestamp > 0.0
    end

    # -----------------------------------------------------------------------
    @testset "undo_operation – row count mismatch" begin
        tbl = make_numeric_table()
        op  = DataCleaning.NormalizeOperation(:x, DataCleaning.MinMaxNormalization)
        new_tbl, meta = DataCleaning.apply_operation(tbl, op)

        shorter_tbl = new_tbl[1:3]
        @test_throws DomainError DataCleaning.undo_operation(shorter_tbl, meta)
    end

end
