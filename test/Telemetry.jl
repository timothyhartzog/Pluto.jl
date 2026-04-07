using Test
import Pluto.Telemetry:
    AICallRecord, TelemetryStore,
    record!, clear!, get_records,
    redact_sensitive, redact_dict,
    compute_metrics,
    REDACTED_PLACEHOLDER
import Dates

@testset "Telemetry" begin

    # ------------------------------------------------------------------
    @testset "Redaction" begin
        @testset "sensitive keys are redacted" begin
            for key in ["api_key", "API_KEY", "apikey", "APIKEY",
                        "secret", "password", "authorization",
                        "credential", "bearer", "auth_token",
                        "my_api_key", "Authorization", "Bearer-Token"]
                @test redact_sensitive(key, "s3cr3t") == REDACTED_PLACEHOLDER
            end
        end

        @testset "non-sensitive keys are preserved" begin
            for (key, val) in [("model", "gpt-4o"), ("provider", "openai"),
                                ("latency", 42), ("user_id", "u123")]
                @test redact_sensitive(key, val) == val
            end
        end

        @testset "redact_dict replaces sensitive values" begin
            d = Dict{String,Any}(
                "api_key"  => "sk-abc123",
                "model"    => "gpt-4o",
                "password" => "hunter2",
                "count"    => 7,
            )
            rd = redact_dict(d)
            @test rd["api_key"]  == REDACTED_PLACEHOLDER
            @test rd["password"] == REDACTED_PLACEHOLDER
            @test rd["model"]    == "gpt-4o"
            @test rd["count"]    == 7
        end

        @testset "redact_dict preserves non-string values" begin
            d = Dict("latency" => 3.14, "tokens" => 100)
            rd = redact_dict(d)
            @test rd["latency"] == 3.14
            @test rd["tokens"]  == 100
        end
    end

    # ------------------------------------------------------------------
    @testset "TelemetryStore" begin
        store = TelemetryStore()

        @testset "starts empty" begin
            @test isempty(get_records(store))
        end

        r1 = AICallRecord(Dates.now(), "openai", "gpt-4o", 100.0, true, nothing, 50, 20, Dict{String,Any}())
        r2 = AICallRecord(Dates.now(), "anthropic", "claude-3", 200.0, false, "HTTP.ExceptionRequest.StatusError", 80, nothing, Dict{String,Any}())

        @testset "record! appends" begin
            record!(store, r1)
            record!(store, r2)
            recs = get_records(store)
            @test length(recs) == 2
            @test recs[1].provider == "openai"
            @test recs[2].provider == "anthropic"
        end

        @testset "get_records returns a copy" begin
            snap1 = get_records(store)
            record!(store, r1)
            snap2 = get_records(store)
            @test length(snap1) == 2   # original snapshot unaffected
            @test length(snap2) == 3
        end

        @testset "clear! empties the store" begin
            clear!(store)
            @test isempty(get_records(store))
        end

        @testset "max_records evicts oldest" begin
            small_store = TelemetryStore(max_records = 3)
            for i in 1:5
                record!(small_store, AICallRecord(
                    Dates.now(), "p", "m", Float64(i), true, nothing, nothing, nothing, Dict{String,Any}()
                ))
            end
            recs = get_records(small_store)
            @test length(recs) == 3
            # Oldest (latency 1, 2) should be gone; newest 3 remain
            @test recs[1].latency_ms == 3.0
            @test recs[end].latency_ms == 5.0
        end
    end

    # ------------------------------------------------------------------
    @testset "@timed_ai_call macro" begin
        store = TelemetryStore()

        @testset "records successful call" begin
            result = Pluto.Telemetry.@timed_ai_call "openai" "gpt-4o" store begin
                42
            end
            @test result == 42
            recs = get_records(store)
            @test length(recs) == 1
            r = recs[1]
            @test r.success        == true
            @test r.error_type     === nothing
            @test r.provider       == "openai"
            @test r.model          == "gpt-4o"
            @test r.latency_ms     >= 0.0
        end

        @testset "records failed call and re-throws" begin
            store2 = TelemetryStore()
            @test_throws ErrorException begin
                Pluto.Telemetry.@timed_ai_call "anthropic" "claude-3" store2 begin
                    error("upstream error")
                end
            end
            recs = get_records(store2)
            @test length(recs) == 1
            r = recs[1]
            @test r.success    == false
            @test r.error_type == "ErrorException"
            @test r.provider   == "anthropic"
        end
    end

    # ------------------------------------------------------------------
    @testset "compute_metrics" begin
        @testset "empty records" begin
            m = compute_metrics(AICallRecord[])
            @test m.count == 0
            @test isnan(m.error_rate)
            @test isnan(m.mean_latency_ms)
        end

        # Build a fixture with known values
        make_rec(provider, model, latency, success; prompt=nothing, completion=nothing) =
            AICallRecord(
                Dates.now(), provider, model, latency, success,
                success ? nothing : "SomeError",
                prompt, completion,
                Dict{String,Any}()
            )

        records = [
            make_rec("openai",    "gpt-4o",    100.0, true;  prompt=200, completion=100),
            make_rec("openai",    "gpt-4o",    200.0, true;  prompt=300, completion=150),
            make_rec("openai",    "gpt-4o",    300.0, false; prompt=250, completion=0),
            make_rec("anthropic", "claude-3",  150.0, true;  prompt=180, completion=90),
            make_rec("anthropic", "claude-3",  250.0, false),
        ]

        m = compute_metrics(records)

        @testset "count" begin
            @test m.count == 5
        end

        @testset "error_rate" begin
            @test m.error_rate ≈ 2 / 5
        end

        @testset "mean_latency_ms" begin
            expected = (100 + 200 + 300 + 150 + 250) / 5
            @test m.mean_latency_ms ≈ expected
        end

        @testset "latency percentiles" begin
            # sorted latencies: [100, 150, 200, 250, 300]
            @test m.p50_latency_ms == 200.0   # 50th pct → index 3
            @test m.p95_latency_ms == 300.0   # 95th pct → index 5
            @test m.p99_latency_ms == 300.0
        end

        @testset "token totals" begin
            @test m.total_prompt_tokens     == 200 + 300 + 250 + 180   # 930; missing treated as 0
            @test m.total_completion_tokens == 100 + 150 + 0 + 90      # 340; missing treated as 0
        end

        @testset "by_provider" begin
            @test haskey(m.by_provider, "openai")
            @test haskey(m.by_provider, "anthropic")
            @test m.by_provider["openai"].count == 3
            @test m.by_provider["anthropic"].count == 2
            @test m.by_provider["openai"].error_rate ≈ 1 / 3
            @test m.by_provider["anthropic"].error_rate ≈ 1 / 2
        end

        @testset "by_model" begin
            @test haskey(m.by_model, "gpt-4o")
            @test haskey(m.by_model, "claude-3")
            @test m.by_model["gpt-4o"].count    == 3
            @test m.by_model["claude-3"].count  == 2
        end

        @testset "compute_metrics from store" begin
            store = TelemetryStore()
            foreach(r -> record!(store, r), records)
            m2 = compute_metrics(store)
            @test m2.count == 5
            @test m2.error_rate ≈ m.error_rate
        end
    end

end
