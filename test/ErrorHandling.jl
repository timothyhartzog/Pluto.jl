using Pluto.ErrorHandling

@testset "ErrorHandling" begin
    # ------------------------------------------------------------------
    # ErrorCategory
    # ------------------------------------------------------------------
    @testset "categorize_error – syntax" begin
        e = Base.Meta.ParseError("unexpected token")
        @test categorize_error(e) === SYNTAX_ERROR
    end

    @testset "categorize_error – runtime (MethodError)" begin
        e = MethodError(+, (1, "a"))
        @test categorize_error(e) === RUNTIME_ERROR
    end

    @testset "categorize_error – runtime (UndefVarError)" begin
        e = UndefVarError(:foo)
        @test categorize_error(e) === RUNTIME_ERROR
    end

    @testset "categorize_error – runtime (TypeError)" begin
        e = TypeError(:convert, "", Int, "hello")
        @test categorize_error(e) === RUNTIME_ERROR
    end

    @testset "categorize_error – runtime (BoundsError)" begin
        e = BoundsError([1, 2, 3], 10)
        @test categorize_error(e) === RUNTIME_ERROR
    end

    @testset "categorize_error – runtime (DivideError)" begin
        e = DivideError()
        @test categorize_error(e) === RUNTIME_ERROR
    end

    @testset "categorize_error – runtime (DomainError)" begin
        e = DomainError(-1, "sqrt of negative")
        @test categorize_error(e) === RUNTIME_ERROR
    end

    @testset "categorize_error – runtime (OverflowError)" begin
        e = OverflowError("integer overflow")
        @test categorize_error(e) === RUNTIME_ERROR
    end

    @testset "categorize_error – runtime (AssertionError)" begin
        e = AssertionError("x > 0")
        @test categorize_error(e) === RUNTIME_ERROR
    end

    @testset "categorize_error – runtime (ErrorException)" begin
        e = ErrorException("something went wrong")
        @test categorize_error(e) === RUNTIME_ERROR
    end

    @testset "categorize_error – network (IOError)" begin
        e = Base.IOError("connection refused", -1)
        @test categorize_error(e) === NETWORK_ERROR
    end

    @testset "categorize_error – network (EOFError)" begin
        e = EOFError()
        @test categorize_error(e) === NETWORK_ERROR
    end

    @testset "categorize_error – network (message heuristic)" begin
        e = ErrorException("lost network connection")
        @test categorize_error(e) === NETWORK_ERROR
    end

    @testset "categorize_error – timeout heuristic" begin
        e = ErrorException("request timeout exceeded")
        @test categorize_error(e) === TIMEOUT_ERROR
    end

    @testset "categorize_error – package heuristic" begin
        e = ArgumentError("package not found in registry")
        @test categorize_error(e) === PACKAGE_ERROR
    end

    @testset "categorize_error – workspace (ProcessFailedException)" begin
        e = ProcessFailedException(Base.Process[])
        @test categorize_error(e) === WORKSPACE_ERROR
    end

    @testset "categorize_error – unknown" begin
        # A raw non-Exception value falls through
        @test categorize_error(42) === UNKNOWN_ERROR
    end

    # ------------------------------------------------------------------
    # ErrorSeverity
    # ------------------------------------------------------------------
    @testset "assess_severity – syntax is low" begin
        e = Base.Meta.ParseError("bad")
        @test assess_severity(e, SYNTAX_ERROR) === SEVERITY_LOW
    end

    @testset "assess_severity – package is medium" begin
        e = ArgumentError("package missing")
        @test assess_severity(e, PACKAGE_ERROR) === SEVERITY_MEDIUM
    end

    @testset "assess_severity – network is high" begin
        e = Base.IOError("conn refused", -1)
        @test assess_severity(e, NETWORK_ERROR) === SEVERITY_HIGH
    end

    @testset "assess_severity – timeout is high" begin
        e = ErrorException("timeout")
        @test assess_severity(e, TIMEOUT_ERROR) === SEVERITY_HIGH
    end

    @testset "assess_severity – workspace is critical" begin
        e = ProcessFailedException(Base.Process[])
        @test assess_severity(e, WORKSPACE_ERROR) === SEVERITY_CRITICAL
    end

    @testset "assess_severity – stack overflow is high" begin
        e = StackOverflowError()
        @test assess_severity(e, RUNTIME_ERROR) === SEVERITY_HIGH
    end

    @testset "assess_severity – OOM is critical" begin
        e = OutOfMemoryError()
        @test assess_severity(e, RUNTIME_ERROR) === SEVERITY_CRITICAL
    end

    # ------------------------------------------------------------------
    # wrap_error
    # ------------------------------------------------------------------
    @testset "wrap_error – basic fields" begin
        e = ErrorException("test error")
        pe = wrap_error(e)
        @test pe isa PlutoError
        @test pe.exception === e
        @test occursin("test error", pe.message)
        @test pe.cell_id === nothing
        @test pe.category === RUNTIME_ERROR
        @test pe.severity === SEVERITY_LOW
        @test pe.timestamp > 0
    end

    @testset "wrap_error – with cell_id" begin
        e = BoundsError([1], 5)
        pe = wrap_error(e; cell_id = "abc-123")
        @test pe.cell_id == "abc-123"
    end

    @testset "wrap_error – with context" begin
        e = MethodError(+, (1, 2))
        ctx = Dict{String, Any}("notebook" => "test.jl")
        pe = wrap_error(e; context = ctx)
        @test pe.context["notebook"] == "test.jl"
    end

    @testset "wrap_error – non-Exception value" begin
        pe = wrap_error("raw string error")
        @test pe.exception isa ErrorException
        @test pe.category === RUNTIME_ERROR
    end

    # ------------------------------------------------------------------
    # ErrorLog
    # ------------------------------------------------------------------
    @testset "ErrorLog construction" begin
        log = ErrorLog()
        @test isempty(log.errors)
        @test log.max_size == 100
        log2 = ErrorLog(; max_size = 5)
        @test log2.max_size == 5
    end

    @testset "log_error! appends" begin
        log = ErrorLog()
        e = ErrorException("first")
        pe = log_error!(log, e)
        @test length(log.errors) == 1
        @test pe === log.errors[1]
    end

    @testset "log_error! with cell_id" begin
        log = ErrorLog()
        log_error!(log, ErrorException("x"); cell_id = "cell-1")
        @test log.errors[1].cell_id == "cell-1"
    end

    @testset "log_error! enforces max_size" begin
        log = ErrorLog(; max_size = 3)
        for i in 1:5
            log_error!(log, ErrorException("e$i"))
        end
        @test length(log.errors) == 3
        @test log.errors[1].message == "e3"
        @test log.errors[end].message == "e5"
    end

    @testset "clear_errors!" begin
        log = ErrorLog()
        log_error!(log, ErrorException("a"))
        log_error!(log, ErrorException("b"))
        clear_errors!(log)
        @test isempty(log.errors)
    end

    @testset "recent_errors returns last n" begin
        log = ErrorLog()
        for i in 1:20
            log_error!(log, ErrorException("e$i"))
        end
        r = recent_errors(log; n = 5)
        @test length(r) == 5
        @test r[end].message == "e20"
        @test r[1].message == "e16"
    end

    @testset "recent_errors when fewer than n errors" begin
        log = ErrorLog()
        log_error!(log, ErrorException("only"))
        r = recent_errors(log; n = 10)
        @test length(r) == 1
    end

    @testset "summarize_errors – counts" begin
        log = ErrorLog()
        log_error!(log, ErrorException("runtime1"))
        log_error!(log, ErrorException("runtime2"))
        log_error!(log, Base.IOError("net", -1))
        s = summarize_errors(log)
        @test s["total"] == 3
        @test s["by_category"]["RUNTIME_ERROR"] == 2
        @test s["by_category"]["NETWORK_ERROR"] == 1
        @test haskey(s, "by_severity")
        @test s["max_size"] == 100
    end

    @testset "summarize_errors – empty log" begin
        log = ErrorLog()
        s = summarize_errors(log)
        @test s["total"] == 0
        @test isempty(s["by_category"])
        @test isempty(s["by_severity"])
    end

    # ------------------------------------------------------------------
    # is_recoverable
    # ------------------------------------------------------------------
    @testset "is_recoverable – network error" begin
        @test is_recoverable(Base.IOError("conn", -1)) === true
    end

    @testset "is_recoverable – timeout" begin
        @test is_recoverable(ErrorException("request timeout")) === true
    end

    @testset "is_recoverable – runtime error" begin
        @test is_recoverable(MethodError(+, (1, 2))) === false
    end

    @testset "is_recoverable – non-Exception" begin
        @test is_recoverable(42) === false
    end

    # ------------------------------------------------------------------
    # retry_with_backoff
    # ------------------------------------------------------------------
    @testset "retry_with_backoff – succeeds first try" begin
        count = Ref(0)
        result = retry_with_backoff(; base_delay = 0.0) do
            count[] += 1
            42
        end
        @test result == 42
        @test count[] == 1
    end

    @testset "retry_with_backoff – retries on recoverable error" begin
        count = Ref(0)
        result = retry_with_backoff(; max_retries = 3, base_delay = 0.0) do
            count[] += 1
            count[] < 3 && throw(Base.IOError("transient", -1))
            "ok"
        end
        @test result == "ok"
        @test count[] == 3
    end

    @testset "retry_with_backoff – gives up after max_retries" begin
        count = Ref(0)
        @test_throws Base.IOError retry_with_backoff(; max_retries = 2, base_delay = 0.0) do
            count[] += 1
            throw(Base.IOError("always fails", -1))
        end
        @test count[] == 3  # initial + 2 retries
    end

    @testset "retry_with_backoff – does not retry non-recoverable" begin
        count = Ref(0)
        @test_throws MethodError retry_with_backoff(; max_retries = 5, base_delay = 0.0) do
            count[] += 1
            throw(MethodError(+, (1, 2)))
        end
        @test count[] == 1  # no retry
    end

    # ------------------------------------------------------------------
    # Integration: full round-trip through the framework
    # ------------------------------------------------------------------
    @testset "integration – catch, log, and summarise" begin
        log = ErrorLog(; max_size = 50)
        scenarios = [
            (ErrorException("something failed"),         "cell-1"),
            (Base.Meta.ParseError("bad syntax"),         "cell-2"),
            (Base.IOError("lost connection", -1),        "cell-3"),
            (ErrorException("network timeout exceeded"), "cell-4"),
            (MethodError(+, (1, "x")),                  "cell-5"),
        ]

        for (exc, cid) in scenarios
            log_error!(log, exc; cell_id = cid)
        end

        s = summarize_errors(log)
        @test s["total"] == 5

        # Each cell_id should be present
        logged_ids = [e.cell_id for e in log.errors]
        for (_, cid) in scenarios
            @test cid in logged_ids
        end

        # We should have at least two different categories
        @test length(s["by_category"]) >= 2

        # Recent errors — ask for last 2
        r = recent_errors(log; n = 2)
        @test length(r) == 2
        @test r[end].cell_id == "cell-5"

        # Clear and confirm
        clear_errors!(log)
        @test isempty(log.errors)
    end
end
