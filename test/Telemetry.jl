using Test
import Pluto
import Pluto.Telemetry:
    TelemetryStore,
    MetricEvent,
    AggregatedMetrics,
    record_request!,
    record_error!,
    get_metrics,
    reset!,
    redact

@testset "Telemetry" begin

    # ------------------------------------------------------------------
    @testset "redact – sensitive keys are replaced" begin
        d = Dict(
            "api_key"   => "sk-secret",
            "api-key"   => "another-secret",
            "secret"    => "mysecret",
            "token"     => "tok-abc",
            "password"  => "hunter2",
            "auth"      => "Bearer xyz",
            "prompt"    => "Write code for me",
            "content"   => "cell code here",
            "safe_key"  => "visible",
            "latency"   => 42,
        )
        safe = redact(d)

        @test safe["api_key"]  == "[REDACTED]"
        @test safe["api-key"]  == "[REDACTED]"
        @test safe["secret"]   == "[REDACTED]"
        @test safe["token"]    == "[REDACTED]"
        @test safe["password"] == "[REDACTED]"
        @test safe["auth"]     == "[REDACTED]"
        @test safe["prompt"]   == "[REDACTED]"
        @test safe["content"]  == "[REDACTED]"
        @test safe["safe_key"] == "visible"
        @test safe["latency"]  == 42
    end

    @testset "redact – nested structures" begin
        d = Dict(
            "outer" => Dict("api_key" => "s", "safe" => 1),
            "list"  => [Dict("token" => "t"), Dict("ok" => "yes")],
        )
        safe = redact(d)

        @test safe["outer"]["api_key"] == "[REDACTED]"
        @test safe["outer"]["safe"]    == 1
        @test safe["list"][1]["token"] == "[REDACTED]"
        @test safe["list"][2]["ok"]    == "yes"
    end

    @testset "redact – non-dict values passed through" begin
        @test redact("hello") == "hello"
        @test redact(42)      == 42
        @test redact(3.14)    == 3.14
        @test redact(nothing) === nothing
    end

    # ------------------------------------------------------------------
    @testset "record_request! adds a successful event" begin
        store = TelemetryStore()
        ev = record_request!(store;
            provider = "openai",
            model    = "gpt-4o",
            latency_ms    = 250.0,
            input_tokens  = 100,
            output_tokens = 50,
        )

        @test ev isa MetricEvent
        @test ev.provider      == "openai"
        @test ev.model         == "gpt-4o"
        @test ev.latency_ms    ≈ 250.0
        @test ev.input_tokens  == 100
        @test ev.output_tokens == 50
        @test ev.is_error      == false
        @test ev.error_type    == ""

        m = get_metrics(store)
        @test m.total_requests == 1
        @test m.total_errors   == 0
    end

    @testset "record_error! adds an error event" begin
        store = TelemetryStore()
        ev = record_error!(store;
            provider   = "ollama",
            model      = "llama3",
            error_type = "timeout",
        )

        @test ev.is_error   == true
        @test ev.error_type == "timeout"
        @test ev.provider   == "ollama"
        @test ev.model      == "llama3"

        m = get_metrics(store)
        @test m.total_requests == 1
        @test m.total_errors   == 1
        @test m.error_rate     ≈ 1.0
    end

    # ------------------------------------------------------------------
    @testset "get_metrics – latency statistics" begin
        store = TelemetryStore()
        for ms in [100.0, 200.0, 300.0, 400.0, 500.0]
            record_request!(store; provider="p", model="m", latency_ms=ms)
        end

        m = get_metrics(store)
        @test m.total_requests == 5
        @test m.total_errors   == 0
        @test m.error_rate     ≈ 0.0
        @test m.mean_latency_ms ≈ 300.0
        @test m.p50_latency_ms  ≈ 300.0
        # p95 of [100,200,300,400,500]: idx = 1 + 0.95*4 = 4.8 → 400 + 0.8*(500-400) = 480
        @test m.p95_latency_ms  ≈ 480.0
    end

    @testset "get_metrics – token usage" begin
        store = TelemetryStore()
        record_request!(store; provider="p", model="m", latency_ms=10.0,
                        input_tokens=100, output_tokens=40)
        record_request!(store; provider="p", model="m", latency_ms=20.0,
                        input_tokens=200, output_tokens=80)

        m = get_metrics(store)
        @test m.total_input_tokens  == 300
        @test m.total_output_tokens == 120
    end

    @testset "get_metrics – provider/model usage mix" begin
        store = TelemetryStore()
        record_request!(store; provider="openai", model="gpt-4o",   latency_ms=10.0)
        record_request!(store; provider="openai", model="gpt-4o",   latency_ms=20.0)
        record_request!(store; provider="openai", model="gpt-3.5",  latency_ms=5.0)
        record_request!(store; provider="ollama", model="llama3",   latency_ms=30.0)
        record_error!(  store; provider="openai", model="gpt-4o",   error_type="rate_limit")

        m = get_metrics(store)
        @test m.by_provider["openai"] == 4
        @test m.by_provider["ollama"] == 1
        @test m.by_model["gpt-4o"]   == 3   # 2 successes + 1 error
        @test m.by_model["gpt-3.5"]  == 1
        @test m.by_model["llama3"]   == 1
        @test m.error_types["rate_limit"] == 1
    end

    @testset "get_metrics – error rate calculation" begin
        store = TelemetryStore()
        for _ in 1:8
            record_request!(store; provider="p", model="m", latency_ms=1.0)
        end
        for _ in 1:2
            record_error!(store; provider="p", model="m", error_type="err")
        end

        m = get_metrics(store)
        @test m.total_requests == 10
        @test m.total_errors   == 2
        @test m.error_rate     ≈ 0.2
    end

    @testset "get_metrics – empty store" begin
        store = TelemetryStore()
        m = get_metrics(store)
        @test m.total_requests      == 0
        @test m.total_errors        == 0
        @test m.error_rate          ≈ 0.0
        @test isnan(m.mean_latency_ms)
        @test isnan(m.p50_latency_ms)
        @test isnan(m.p95_latency_ms)
        @test m.total_input_tokens  == 0
        @test m.total_output_tokens == 0
        @test isempty(m.by_provider)
        @test isempty(m.by_model)
        @test isempty(m.error_types)
    end

    # ------------------------------------------------------------------
    @testset "reset! clears all events" begin
        store = TelemetryStore()
        record_request!(store; provider="p", model="m", latency_ms=1.0)
        record_error!(  store; provider="p", model="m")

        @test get_metrics(store).total_requests == 2
        reset!(store)
        @test get_metrics(store).total_requests == 0
    end

    @testset "TelemetryStore – max_events cap" begin
        store = TelemetryStore(; max_events = 5)
        for i in 1:10
            record_request!(store; provider="p", model="m", latency_ms=Float64(i))
        end
        # Only the 5 most recent events should be kept
        @test get_metrics(store).total_requests == 5
        # The oldest were dropped; the newest should have latency 10.0
        m = get_metrics(store)
        # mean of [6,7,8,9,10] = 8.0
        @test m.mean_latency_ms ≈ 8.0
    end

    # ------------------------------------------------------------------
    @testset "default_registry – missing keyword args use defaults" begin
        store = TelemetryStore()
        # input_tokens and output_tokens default to 0
        ev = record_request!(store; provider="p", model="m", latency_ms=5.0)
        @test ev.input_tokens  == 0
        @test ev.output_tokens == 0

        # error_type and latency_ms have defaults for record_error!
        ev2 = record_error!(store; provider="p", model="m")
        @test ev2.error_type == "unknown"
        @test isnan(ev2.latency_ms)
    end

end # @testset "Telemetry"
