using Test
using HTTP
using Sockets
using Pluto
using Pluto.Configuration: from_flat_kwargs

# ---------------------------------------------------------------------------
# Helper: find a free port on localhost
# ---------------------------------------------------------------------------
function free_port()
    server = listen(IPv4(0), 0)
    port   = getsockname(server)[2]
    close(server)
    Int(port)
end

# ---------------------------------------------------------------------------
# Helper: start a minimal mock Ollama server
#
# The handler returns a 200 with a fake generate response for any request
# that does NOT contain the sentinel model name "no-such-model", and a 404
# for requests that do.
# ---------------------------------------------------------------------------
function start_mock_ollama(port)
    HTTP.serve!("127.0.0.1", port) do req::HTTP.Request
        body_str = String(req.body)
        if occursin("\"no-such-model\"", body_str)
            r = HTTP.Response(
                404,
                "{\"error\":\"model 'no-such-model' not found, try pulling it first\"}",
            )
            HTTP.setheader(r, "Content-Type" => "application/json")
            return r
        end
        r = HTTP.Response(
            200,
            "{\"model\":\"test-model\",\"response\":\"Hello from mock Ollama!\",\"done\":true}",
        )
        HTTP.setheader(r, "Content-Type" => "application/json")
        return r
    end
end

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
@testset "Ollama adapter" begin

    mock_port = free_port()
    mock_host = "http://127.0.0.1:$(mock_port)"
    mock_server = start_mock_ollama(mock_port)

    try
        # ── Unit tests: ollama_generate ─────────────────────────────────────

        @testset "ollama_generate – successful call" begin
            text, err = Pluto.ollama_generate(
                mock_host, "test-model", "Hello!";
                timeout_seconds = 30, max_retries = 0,
            )
            @test err  === nothing
            @test text == "Hello from mock Ollama!"
        end

        @testset "ollama_generate – with system prompt" begin
            text, err = Pluto.ollama_generate(
                mock_host, "test-model", "Hi!", "You are helpful.";
                timeout_seconds = 30, max_retries = 0,
            )
            @test err  === nothing
            @test text == "Hello from mock Ollama!"
        end

        @testset "ollama_generate – model not found (404)" begin
            text, err = Pluto.ollama_generate(
                mock_host, "no-such-model", "Hello!";
                timeout_seconds = 30, max_retries = 0,
            )
            @test text === nothing
            @test err  !== nothing
            @test occursin("no-such-model", err)
            # Should mention how to fix it
            @test occursin("pull", lowercase(err))
        end

        @testset "ollama_generate – server unavailable" begin
            # Port 1 is privileged / always refused
            text, err = Pluto.ollama_generate(
                "http://127.0.0.1:1", "test-model", "Hello!";
                timeout_seconds = 5, max_retries = 0,
            )
            @test text === nothing
            @test err  !== nothing
            # Must mention connection or that the server is unavailable
            lower_err = lowercase(err)
            @test (
                occursin("connect", lower_err) ||
                occursin("unavailable", lower_err) ||
                occursin("failed", lower_err)
            )
        end

        # ── Integration tests: /api/ollama endpoint through Pluto ────────────

        pluto_port = free_port()
        options = from_flat_kwargs(;
            port                        = pluto_port,
            launch_browser              = false,
            workspace_use_distributed   = false,
            require_secret_for_access   = false,
            require_secret_for_open_links = false,
            ollama_host                 = mock_host,
            ollama_model                = "test-model",
            ollama_timeout_seconds      = 30,
            ollama_max_retries          = 0,
        )
        🍭 = Pluto.ServerSession(; options)
        pluto_server = Pluto.run!(🍭)
        pluto_url    = "http://127.0.0.1:$(pluto_port)"

        # Wait for the server to be ready
        @test Pluto.WorkspaceManager.poll(10) do
            try
                HTTP.get("$(pluto_url)/ping"; retry=false).status == 200
            catch
                false
            end
        end

        try
            @testset "/api/ollama – successful generation" begin
                resp = HTTP.post(
                    "$(pluto_url)/api/ollama",
                    ["Content-Type" => "application/json"],
                    "{\"prompt\":\"Hello!\"}";
                    status_exception = false,
                )
                @test resp.status == 200
                body = String(resp.body)
                @test occursin("\"success\":true",  body)
                @test occursin("Hello from mock Ollama!", body)
            end

            @testset "/api/ollama – empty prompt returns 400" begin
                resp = HTTP.post(
                    "$(pluto_url)/api/ollama",
                    ["Content-Type" => "application/json"],
                    "{\"prompt\":\"\"}";
                    status_exception = false,
                )
                @test resp.status == 400
                @test occursin("\"success\":false", String(resp.body))
            end

            @testset "/api/ollama – unknown model returns 502" begin
                resp = HTTP.post(
                    "$(pluto_url)/api/ollama",
                    ["Content-Type" => "application/json"],
                    "{\"prompt\":\"Hello!\",\"model\":\"no-such-model\"}";
                    status_exception = false,
                )
                @test resp.status == 502
                body = String(resp.body)
                @test occursin("\"success\":false", body)
                @test occursin("no-such-model",    body)
            end

            @testset "/api/ollama – per-request model override" begin
                # Use the default (test-model) by not specifying model
                resp = HTTP.post(
                    "$(pluto_url)/api/ollama",
                    ["Content-Type" => "application/json"],
                    "{\"prompt\":\"Hi there!\"}";
                    status_exception = false,
                )
                @test resp.status == 200
                @test occursin("\"success\":true", String(resp.body))
            end

        finally
            close(pluto_server)
        end

    finally
        close(mock_server)
    end

end
