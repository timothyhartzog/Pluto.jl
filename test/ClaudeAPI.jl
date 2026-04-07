using Test
using HTTP
using Pluto
using Pluto: ServerSession, SessionActions, WorkspaceManager
using Pluto.Configuration
using Pluto.WorkspaceManager: poll

# ─── helpers ──────────────────────────────────────────────────────────────────

function start_server(; port=13450)
    options = Pluto.Configuration.from_flat_kwargs(;
        port,
        launch_browser=false,
        workspace_use_distributed=false,
        require_secret_for_access=false,
        require_secret_for_open_links=false,
    )
    session = Pluto.ServerSession(; options)
    server  = Pluto.run!(session)
    (session, server)
end

function post_claude(port, body::AbstractString; headers=["Content-Type" => "application/json"])
    HTTP.post("http://localhost:$(port)/api/claude", headers, body; status_exception=false)
end

function post_claude(port; prompt="", model="claude-sonnet-4-6", system_prompt="")
    body = """{"prompt":$(repr(prompt)),"model":$(repr(model)),"system_prompt":$(repr(system_prompt))}"""
    post_claude(port, body)
end

# ──────────────────────────────────────────────────────────────────────────────

@testset "Claude API – /api/claude endpoint" begin

    port = 13450
    session, server = start_server(; port)

    # Wait for the server to be ready
    @test poll(10) do
        try
            HTTP.get("http://localhost:$(port)/ping"; status_exception=false).status == 200
        catch
            false
        end
    end

    # ── 1. Empty prompt → 400 ─────────────────────────────────────────────────
    @testset "Empty prompt returns 400" begin
        resp = post_claude(port; prompt="")
        @test resp.status == 400
        body = String(resp.body)
        @test occursin("prompt is empty", body)
        @test occursin("\"success\":false", body)
    end

    # ── 2. Whitespace-only prompt → 400 ───────────────────────────────────────
    @testset "Whitespace-only prompt returns 400" begin
        resp = post_claude(port; prompt="   ")
        @test resp.status == 400
        body = String(resp.body)
        @test occursin("prompt is empty", body)
    end

    # ── 3. Mock response via env var → 200 ────────────────────────────────────
    # This is the mechanism used in CI so that the real `claude` CLI is never
    # invoked.  The PLUTO_CLAUDE_MOCK_RESPONSE env var is set to the text that
    # the endpoint should return verbatim.
    @testset "Mock response (PLUTO_CLAUDE_MOCK_RESPONSE env var)" begin
        mock_text = "Here is your Julia code:\n```julia\nx = 42\n```"
        withenv("PLUTO_CLAUDE_MOCK_RESPONSE" => mock_text) do
            resp = post_claude(port; prompt="Write some Julia code")
            @test resp.status == 200
            body = String(resp.body)
            @test occursin("\"success\":true", body)
            @test occursin("x = 42", body)
        end
    end

    # ── 4. Mock response – full import-clean-analyze workflow ──────────────────
    # Simulates the AI-assisted data workflow:
    #   import dataset → profile → apply cleaning → generate code → preview → export
    @testset "Import-clean-analyze workflow with mocked provider" begin
        workflow_code = """
        Here is the complete data-analysis workflow:

        **Step 1 – Import**
        ```julia
        data = [3.0, 1.0, missing, 4.0, 1.0, 5.0, missing, 9.0]
        ```

        **Step 2 – Profile**
        ```julia
        profile = (n=length(data), n_missing=count(ismissing, data))
        ```

        **Step 3 – Clean**
        ```julia
        cleaned = collect(skipmissing(data))
        ```

        **Step 4 – Analyze**
        ```julia
        result = (mean=sum(cleaned)/length(cleaned), total=sum(cleaned))
        ```
        """

        withenv("PLUTO_CLAUDE_MOCK_RESPONSE" => workflow_code) do
            # Step 1: request import code
            resp = post_claude(port; prompt="Import this CSV dataset and profile it")
            @test resp.status == 200
            body = String(resp.body)
            @test occursin("\"success\":true", body)

            # The response should contain Julia code blocks
            @test occursin("```julia", body)

            # Step 2: request cleaning code
            resp2 = post_claude(port;
                prompt="Apply cleaning suggestions: remove missing values")
            @test resp2.status == 200
            body2 = String(resp2.body)
            @test occursin("\"success\":true", body2)
            @test occursin("skipmissing", body2)

            # Step 3: request analysis / export
            resp3 = post_claude(port;
                prompt="Compute summary statistics and export to CSV")
            @test resp3.status == 200
            body3 = String(resp3.body)
            @test occursin("\"success\":true", body3)
            @test occursin("result", body3)
        end
    end

    # ── 5. Provider unavailable → 500 ─────────────────────────────────────────
    # When `claude` CLI is not present (the normal state in CI without the mock)
    # the endpoint must return 500 with a JSON error, not crash the server.
    #
    # Note on status 502 (Bad Gateway):
    #   A 502 is returned by an *upstream proxy* when the backend server cannot
    #   be reached at all (e.g. the Pluto process has crashed or the port is not
    #   yet listening).  The `serve_claude` handler itself never emits a 502;
    #   instead it emits 500 for internal errors.  If a test sees a 502 it means
    #   the Pluto server was not running at the time of the request – typically
    #   indicating a race condition in test startup or a crashed worker process.
    @testset "Provider unavailable returns 500" begin
        # We use a path that does not exist so the Cmd will fail to spawn.
        # withenv makes sure PLUTO_CLAUDE_MOCK_RESPONSE is NOT set so the
        # real (missing) claude binary path is used.
        withenv("PLUTO_CLAUDE_MOCK_RESPONSE" => nothing) do
            resp = post_claude(port; prompt="Write some Julia code")
            # Either 500 (provider error) or 200 if a real `claude` binary
            # happens to be installed in the test environment.
            @test resp.status in (200, 500)
            body = String(resp.body)
            # Response must always be well-formed JSON
            @test occursin("\"success\":", body)
        end
    end

    # ── 6. Malformed JSON body ─────────────────────────────────────────────────
    @testset "Malformed JSON body is handled gracefully" begin
        resp = post_claude(port, "not json at all")
        # json_get returns "" for a missing key, so the empty-prompt guard fires
        # and returns 400.  We do not accept 200 since that would mean invalid
        # input was processed successfully, masking a potential bug.
        @test resp.status in (400, 500)
        # Server is still alive after bad request
        ping = HTTP.get("http://localhost:$(port)/ping"; status_exception=false)
        @test ping.status == 200
    end

    # ── cleanup ────────────────────────────────────────────────────────────────
    for notebook in values(session.notebooks)
        SessionActions.shutdown(session, notebook; keep_in_session=false, async=false)
    end
    close(server)
end
