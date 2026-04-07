using Test
import Pluto

const AI = Pluto.AIProvider

@testset "AIProvider" begin

    # ── Error taxonomy ────────────────────────────────────────────────────
    @testset "Error types" begin
        e1 = AI.AIProviderError("something went wrong")
        @test e1 isa Exception
        @test e1.message == "something went wrong"

        e2 = AI.AIValidationError("bad field", "model")
        @test e2 isa Exception
        @test e2.field == "model"

        e3 = AI.AIValidationError("no field")
        @test e3.field == ""

        e4 = AI.AIRateLimitError("too many requests", 60)
        @test e4.retry_after == 60

        e5 = AI.AIRateLimitError("rate limit")
        @test e5.retry_after === nothing

        e6 = AI.AIAuthError("invalid key")
        @test e6 isa Exception

        e7 = AI.AITimeoutError("timed out", 30.0)
        @test e7.timeout_secs == 30.0

        e8 = AI.AITimeoutError("timed out")
        @test e8.timeout_secs === nothing

        e9 = AI.AIUnavailableError("service unavailable")
        @test e9 isa Exception
    end

    # ── AIRequest construction ────────────────────────────────────────────
    @testset "AIRequest construction" begin
        req = AI.AIRequest(
            intent = :completion,
            prompt = "Hello world",
            model  = "test-model",
        )
        @test req.intent == :completion
        @test req.prompt == "Hello world"
        @test req.system_prompt == ""
        @test req.model == "test-model"
        @test req.max_tokens === nothing
        @test req.temperature === nothing
        @test isempty(req.metadata)

        req2 = AI.AIRequest(
            intent      = :code_gen,
            prompt      = "Write a sort function",
            model       = "claude-3",
            max_tokens  = 512,
            temperature = 0.7,
            metadata    = Dict{String,Any}("stream" => false),
        )
        @test req2.intent == :code_gen
        @test req2.max_tokens == 512
        @test req2.temperature ≈ 0.7
        @test req2.metadata["stream"] == false
    end

    # ── AIResponse construction ───────────────────────────────────────────
    @testset "AIResponse construction" begin
        resp = AI.AIResponse(
            success = true,
            text    = "Hello from AI",
            model   = "test-model",
            intent  = :completion,
        )
        @test resp.success == true
        @test resp.text == "Hello from AI"
        @test resp.finish_reason == "stop"
        @test resp.error == ""

        bad = AI.AIResponse(
            success       = false,
            model         = "test-model",
            intent        = :completion,
            finish_reason = "error",
            error         = "upstream failure",
        )
        @test bad.success == false
        @test bad.error == "upstream failure"
    end

    # ── AIStreamChunk construction ────────────────────────────────────────
    @testset "AIStreamChunk construction" begin
        c1 = AI.AIStreamChunk("partial text", false)
        @test c1.delta == "partial text"
        @test c1.done == false
        @test isempty(c1.metadata)

        c2 = AI.AIStreamChunk("", true, Dict{String,Any}("id" => "abc"))
        @test c2.done == true
        @test c2.metadata["id"] == "abc"
    end

    # ── validate_request – valid payloads ─────────────────────────────────
    @testset "validate_request – valid" begin
        for intent in (:completion, :streamed, :code_gen)
            req = AI.AIRequest(intent=intent, prompt="do something", model="m1")
            @test AI.validate_request(req) === nothing
        end

        req_full = AI.AIRequest(
            intent      = :completion,
            prompt      = "test",
            model       = "gpt-4",
            max_tokens  = 100,
            temperature = 1.0,
        )
        @test AI.validate_request(req_full) === nothing
    end

    # ── validate_request – invalid payloads ──────────────────────────────
    @testset "validate_request – invalid" begin
        # bad intent
        req_bad_intent = AI.AIRequest(intent=:unknown, prompt="hi", model="m1")
        @test_throws AI.AIValidationError AI.validate_request(req_bad_intent)
        try
            AI.validate_request(req_bad_intent)
        catch e
            @test e.field == "intent"
        end

        # empty prompt
        req_empty_prompt = AI.AIRequest(intent=:completion, prompt="   ", model="m1")
        @test_throws AI.AIValidationError AI.validate_request(req_empty_prompt)
        try
            AI.validate_request(req_empty_prompt)
        catch e
            @test e.field == "prompt"
        end

        # empty model
        req_empty_model = AI.AIRequest(intent=:completion, prompt="hi", model="")
        @test_throws AI.AIValidationError AI.validate_request(req_empty_model)
        try
            AI.validate_request(req_empty_model)
        catch e
            @test e.field == "model"
        end

        # zero max_tokens
        req_zero_tokens = AI.AIRequest(intent=:completion, prompt="hi", model="m1", max_tokens=0)
        @test_throws AI.AIValidationError AI.validate_request(req_zero_tokens)
        try
            AI.validate_request(req_zero_tokens)
        catch e
            @test e.field == "max_tokens"
        end

        # negative max_tokens
        req_neg_tokens = AI.AIRequest(intent=:completion, prompt="hi", model="m1", max_tokens=-5)
        @test_throws AI.AIValidationError AI.validate_request(req_neg_tokens)

        # temperature out of range (too high)
        req_hot = AI.AIRequest(intent=:completion, prompt="hi", model="m1", temperature=2.1)
        @test_throws AI.AIValidationError AI.validate_request(req_hot)
        try
            AI.validate_request(req_hot)
        catch e
            @test e.field == "temperature"
        end

        # temperature out of range (negative)
        req_cold = AI.AIRequest(intent=:completion, prompt="hi", model="m1", temperature=-0.1)
        @test_throws AI.AIValidationError AI.validate_request(req_cold)
    end

    # ── validate_response – valid payloads ────────────────────────────────
    @testset "validate_response – valid" begin
        for intent in (:completion, :streamed, :code_gen)
            resp = AI.AIResponse(success=true, text="ok", model="m1", intent=intent)
            @test AI.validate_response(resp) === nothing
        end

        for reason in ("stop", "length", "error", "content_filter", "tool_use")
            resp = AI.AIResponse(
                success       = reason != "error",
                text          = reason == "error" ? "" : "ok",
                model         = "m1",
                intent        = :completion,
                finish_reason = reason,
                error         = reason == "error" ? "provider error" : "",
            )
            @test AI.validate_response(resp) === nothing
        end

        resp_tokens = AI.AIResponse(
            success      = true,
            text         = "hello",
            model        = "m1",
            intent       = :completion,
            input_tokens = 10,
            output_tokens = 5,
        )
        @test AI.validate_response(resp_tokens) === nothing
    end

    # ── validate_response – invalid payloads ─────────────────────────────
    @testset "validate_response – invalid" begin
        # bad intent
        resp_bad_intent = AI.AIResponse(
            success=true, text="ok", model="m1", intent=:unknown,
        )
        @test_throws AI.AIValidationError AI.validate_response(resp_bad_intent)
        try
            AI.validate_response(resp_bad_intent)
        catch e
            @test e.field == "intent"
        end

        # empty model
        resp_no_model = AI.AIResponse(
            success=true, text="ok", model="", intent=:completion,
        )
        @test_throws AI.AIValidationError AI.validate_response(resp_no_model)
        try
            AI.validate_response(resp_no_model)
        catch e
            @test e.field == "model"
        end

        # unrecognized finish_reason
        resp_bad_finish = AI.AIResponse(
            success=true, text="ok", model="m1", intent=:completion,
            finish_reason="unknown_reason",
        )
        @test_throws AI.AIValidationError AI.validate_response(resp_bad_finish)
        try
            AI.validate_response(resp_bad_finish)
        catch e
            @test e.field == "finish_reason"
        end

        # failure with no error message
        resp_silent_fail = AI.AIResponse(
            success=false, text="", model="m1", intent=:completion,
            finish_reason="error", error="",
        )
        @test_throws AI.AIValidationError AI.validate_response(resp_silent_fail)
        try
            AI.validate_response(resp_silent_fail)
        catch e
            @test e.field == "error"
        end

        # negative input_tokens
        resp_neg_in = AI.AIResponse(
            success=true, text="ok", model="m1", intent=:completion,
            input_tokens=-1,
        )
        @test_throws AI.AIValidationError AI.validate_response(resp_neg_in)
        try
            AI.validate_response(resp_neg_in)
        catch e
            @test e.field == "input_tokens"
        end

        # negative output_tokens
        resp_neg_out = AI.AIResponse(
            success=true, text="ok", model="m1", intent=:completion,
            output_tokens=-3,
        )
        @test_throws AI.AIValidationError AI.validate_response(resp_neg_out)
        try
            AI.validate_response(resp_neg_out)
        catch e
            @test e.field == "output_tokens"
        end
    end

    # ── AbstractAIProvider interface ──────────────────────────────────────
    @testset "AbstractAIProvider interface" begin
        # Concrete stub provider for testing
        struct EchoProvider <: AI.AbstractAIProvider end

        function AI.complete(p::EchoProvider, req::AI.AIRequest)
            AI.validate_request(req)
            AI.AIResponse(success=true, text="echo: $(req.prompt)", model="echo", intent=req.intent)
        end

        function AI.stream_complete(p::EchoProvider, req::AI.AIRequest, on_chunk::Function)
            AI.validate_request(req)
            words = split(req.prompt)
            for (i, w) in enumerate(words)
                on_chunk(AI.AIStreamChunk(string(w, " "), i == length(words)))
            end
            AI.AIResponse(success=true, text=req.prompt, model="echo", intent=req.intent)
        end

        function AI.generate_code(p::EchoProvider, req::AI.AIRequest)
            AI.validate_request(req)
            AI.AIResponse(success=true, text="# $(req.prompt)\nmissing", model="echo", intent=req.intent)
        end

        provider = EchoProvider()

        @test AI.provider_name(provider) == "EchoProvider"
        @test AI.supported_models(provider) == String[]

        # completion intent
        req_c = AI.AIRequest(intent=:completion, prompt="hello world", model="echo")
        resp_c = AI.complete(provider, req_c)
        @test resp_c.success
        @test occursin("hello world", resp_c.text)
        @test AI.validate_response(resp_c) === nothing

        # streamed intent
        req_s = AI.AIRequest(intent=:streamed, prompt="one two three", model="echo")
        chunks = AI.AIStreamChunk[]
        resp_s = AI.stream_complete(provider, req_s, c -> push!(chunks, c))
        @test !isempty(chunks)
        @test chunks[end].done == true
        @test resp_s.success

        # code_gen intent
        req_g = AI.AIRequest(intent=:code_gen, prompt="sort a vector", model="echo")
        resp_g = AI.generate_code(provider, req_g)
        @test resp_g.success
        @test AI.validate_response(resp_g) === nothing

        # validate_request called inside complete – bad request propagates
        req_bad = AI.AIRequest(intent=:completion, prompt="   ", model="echo")
        @test_throws AI.AIValidationError AI.complete(provider, req_bad)
    end

end
