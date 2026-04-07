
# Tests for the multi-provider AI integration.
# These tests use mock providers so no real network calls are made.

@testset "AI Provider Abstraction" begin

    # ── Error taxonomy ────────────────────────────────────────────────────────
    @testset "AIProviderError" begin
        e = Pluto.AIProviderError(Pluto.AI_API_ERROR, "something went wrong";
                                   provider=:cloud, http_status=503)
        @test e.code    == Pluto.AI_API_ERROR
        @test e.message == "something went wrong"
        @test e.provider == :cloud
        @test e.http_status == 503

        # showerror should include relevant info
        msg = sprint(showerror, e)
        @test occursin("AI_API_ERROR", msg)
        @test occursin("cloud", msg)
        @test occursin("503", msg)

        # Constructor with keyword-only (no http_status)
        e2 = Pluto.AIProviderError(Pluto.AI_EMPTY_PROMPT, "no prompt"; provider=:ollama)
        @test e2.http_status === nothing
    end

    # ── Mock provider ─────────────────────────────────────────────────────────
    # Define a minimal mock inside the test scope
    struct MockProvider <: Pluto.AbstractAIProvider
        response::String
        should_fail::Bool
        fail_code::Pluto.AIErrorCode
    end
    MockProvider(response) = MockProvider(response, false, Pluto.AI_API_ERROR)

    function Pluto.complete(p::MockProvider, prompt::AbstractString; kwargs...)
        isempty(strip(prompt)) && throw(Pluto.AIProviderError(Pluto.AI_EMPTY_PROMPT,
            "empty prompt"; provider=:mock))
        p.should_fail && throw(Pluto.AIProviderError(p.fail_code,
            "mock error"; provider=:mock))
        return p.response
    end

    @testset "MockProvider complete" begin
        p = MockProvider("Hello from mock")
        @test Pluto.complete(p, "say hello") == "Hello from mock"
    end

    @testset "MockProvider empty prompt" begin
        p = MockProvider("x")
        @test_throws Pluto.AIProviderError Pluto.complete(p, "")
        @test_throws Pluto.AIProviderError Pluto.complete(p, "   ")
    end

    @testset "complete_code default system prompt" begin
        # complete_code should delegate to complete and accept kwargs
        p = MockProvider("x = 1")
        result = Pluto.complete_code(p, "assign x to 1")
        @test result == "x = 1"
    end

    # ── Retry helper ─────────────────────────────────────────────────────────
    @testset "with_retries – success on first try" begin
        calls = Ref(0)
        result = Pluto.with_retries(; max_retries=3) do
            calls[] += 1
            "ok"
        end
        @test result == "ok"
        @test calls[] == 1
    end

    @testset "with_retries – retries on AI_RATE_LIMIT" begin
        calls = Ref(0)
        result = Pluto.with_retries(; max_retries=3, base_delay=0.0) do
            calls[] += 1
            if calls[] < 3
                throw(Pluto.AIProviderError(Pluto.AI_RATE_LIMIT, "slow down"; provider=:mock))
            end
            "eventually ok"
        end
        @test result == "eventually ok"
        @test calls[] == 3
    end

    @testset "with_retries – gives up after max_retries" begin
        calls = Ref(0)
        @test_throws Pluto.AIProviderError begin
            Pluto.with_retries(; max_retries=2, base_delay=0.0) do
                calls[] += 1
                throw(Pluto.AIProviderError(Pluto.AI_TIMEOUT, "timeout"; provider=:mock))
            end
        end
        @test calls[] == 2
    end

    @testset "with_retries – does not retry non-retryable errors" begin
        calls = Ref(0)
        @test_throws Pluto.AIProviderError begin
            Pluto.with_retries(; max_retries=3, base_delay=0.0) do
                calls[] += 1
                throw(Pluto.AIProviderError(Pluto.AI_API_ERROR, "bad request"; provider=:mock))
            end
        end
        @test calls[] == 1  # no retry for AI_API_ERROR
    end

    # ── build_provider ────────────────────────────────────────────────────────
    @testset "build_provider – none" begin
        opts = Pluto.Configuration.AIOptions(provider="none")
        @test Pluto.build_provider(opts) === nothing
    end

    @testset "build_provider – cloud defaults" begin
        opts = Pluto.Configuration.AIOptions(provider="cloud")
        p = Pluto.build_provider(opts)
        @test p isa Pluto.CloudProvider
        @test p.base_url == "https://api.openai.com/v1"
        @test p.model    == "gpt-4o"
    end

    @testset "build_provider – cloud custom" begin
        opts = Pluto.Configuration.AIOptions(
            provider="cloud",
            base_url="https://my-proxy.example.com/v1",
            model="my-model",
            max_retries=5,
            timeout=45.0,
        )
        p = Pluto.build_provider(opts)
        @test p isa Pluto.CloudProvider
        @test p.base_url    == "https://my-proxy.example.com/v1"
        @test p.model       == "my-model"
        @test p.max_retries == 5
        @test p.timeout     == 45.0
    end

    @testset "build_provider – ollama defaults" begin
        opts = Pluto.Configuration.AIOptions(provider="ollama")
        p = Pluto.build_provider(opts)
        @test p isa Pluto.OllamaProvider
        @test p.base_url == "http://localhost:11434"
        @test p.model    == "llama3.2"
    end

    @testset "build_provider – ollama custom" begin
        opts = Pluto.Configuration.AIOptions(
            provider="ollama",
            base_url="http://gpu-server:11434",
            model="codellama",
        )
        p = Pluto.build_provider(opts)
        @test p isa Pluto.OllamaProvider
        @test p.base_url == "http://gpu-server:11434"
        @test p.model    == "codellama"
    end

    @testset "build_provider – unknown provider" begin
        opts = Pluto.Configuration.AIOptions(provider="unknown_xyz")
        @test_throws ErrorException Pluto.build_provider(opts)
    end

    # ── AIOptions in Configuration ─────────────────────────────────────────
    @testset "AIOptions defaults" begin
        opts = Pluto.Configuration.AIOptions()
        @test opts.provider    == "none"
        @test opts.max_retries == 3
        @test opts.timeout     == 60.0
        @test opts.api_key_env == "PLUTO_AI_API_KEY"
    end

    @testset "from_flat_kwargs includes ai options" begin
        cfg = Pluto.Configuration.from_flat_kwargs(;
            ai_provider    = "ollama",
            ai_model       = "mistral",
            ai_max_retries = 5,
        )
        @test cfg.ai.provider    == "ollama"
        @test cfg.ai.model       == "mistral"
        @test cfg.ai.max_retries == 5
    end

    # ── CloudProvider JSON helpers ────────────────────────────────────────────
    @testset "CloudProvider _escape_json_string" begin
        @test Pluto._escape_json_string("hello\nworld") == "hello\\nworld"
        @test Pluto._escape_json_string("say \"hi\"")  == "say \\\"hi\\\""
        @test Pluto._escape_json_string("a\\b")        == "a\\\\b"
    end

    @testset "CloudProvider _unescape_json_string" begin
        @test Pluto._unescape_json_string("hello\\nworld")   == "hello\nworld"
        @test Pluto._unescape_json_string("say \\\"hi\\\"") == "say \"hi\""
        @test Pluto._unescape_json_string("a\\\\b")          == "a\\b"
    end

    @testset "CloudProvider _cloud_extract_text" begin
        resp = """{"id":"x","choices":[{"message":{"role":"assistant","content":"Hello world"}}]}"""
        @test Pluto._cloud_extract_text(resp) == "Hello world"
    end

    @testset "CloudProvider _cloud_extract_text parse error" begin
        @test_throws Pluto.AIProviderError Pluto._cloud_extract_text("{}")
    end

    # ── OllamaProvider JSON helpers ───────────────────────────────────────────
    @testset "OllamaProvider _ollama_extract_text" begin
        resp = """{"model":"llama3.2","response":"42 is the answer","done":true}"""
        @test Pluto._ollama_extract_text(resp) == "42 is the answer"
    end

    @testset "OllamaProvider _ollama_extract_text parse error" begin
        @test_throws Pluto.AIProviderError Pluto._ollama_extract_text("{}")
    end

end
