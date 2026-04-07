using Test
using Pluto
using Pluto.Configuration: CloudProviderOptions
using Pluto.CloudProvider:
    RedactedSecret, secret_value,
    CloudAuthError, CloudRateLimitError, CloudTimeoutError, CloudServerError,
    load_api_key, cloud_request

@testset "CloudProvider" begin

    # ─────────────────────────────────────────────────────────────────────────
    @testset "RedactedSecret never leaks the value" begin
        r = RedactedSecret("super-secret-key-123")

        # show / print must NOT contain the real value
        shown = sprint(show, r)
        @test !occursin("super-secret-key-123", shown)
        @test occursin("REDACTED", shown)

        printed = sprint(print, r)
        @test !occursin("super-secret-key-123", printed)
        @test occursin("REDACTED", printed)

        # string(...) must NOT contain the real value
        @test !occursin("super-secret-key-123", string(r))
        @test occursin("REDACTED", string(r))

        # MIME text/plain
        shown_plain = sprint(show, MIME"text/plain"(), r)
        @test !occursin("super-secret-key-123", shown_plain)

        # The raw value is only accessible via secret_value()
        @test secret_value(r) == "super-secret-key-123"
    end

    # ─────────────────────────────────────────────────────────────────────────
    @testset "CloudProviderOptions defaults" begin
        opts = CloudProviderOptions()
        @test opts.api_key_path === nothing
        @test opts.api_key_env == "PLUTO_CLOUD_API_KEY"
        @test opts.base_url == "https://api.openai.com/v1"
        @test opts.timeout == 30.0
        @test opts.max_retries == 3
    end

    # ─────────────────────────────────────────────────────────────────────────
    @testset "load_api_key from environment variable" begin
        env_name = "TEST_PLUTO_CLOUD_KEY_$(rand(UInt32))"
        opts = CloudProviderOptions(; api_key_env=env_name)

        # Key absent → nothing
        @test load_api_key(opts) === nothing

        # Key present → RedactedSecret wrapping the value
        withenv(env_name => "env-key-value") do
            result = load_api_key(opts)
            @test result isa RedactedSecret
            @test secret_value(result) == "env-key-value"
            # The secret must never appear via show
            @test !occursin("env-key-value", string(result))
        end
    end

    # ─────────────────────────────────────────────────────────────────────────
    @testset "load_api_key from file" begin
        key_file = tempname()
        try
            write(key_file, "  file-key-value\n")  # includes surrounding whitespace
            opts = CloudProviderOptions(; api_key_path=key_file)
            result = load_api_key(opts)
            @test result isa RedactedSecret
            @test secret_value(result) == "file-key-value"   # whitespace stripped
        finally
            isfile(key_file) && rm(key_file)
        end
    end

    # ─────────────────────────────────────────────────────────────────────────
    @testset "load_api_key: file takes priority over env var" begin
        env_name = "TEST_PLUTO_KEY_PRIORITY_$(rand(UInt32))"
        key_file = tempname()
        try
            write(key_file, "file-key")
            opts = CloudProviderOptions(; api_key_path=key_file, api_key_env=env_name)
            withenv(env_name => "env-key") do
                result = load_api_key(opts)
                @test secret_value(result) == "file-key"
            end
        finally
            isfile(key_file) && rm(key_file)
        end
    end

    # ─────────────────────────────────────────────────────────────────────────
    @testset "Error taxonomy – showerror messages" begin
        auth_err    = CloudAuthError("Bad credentials", 401)
        ratelim_err = CloudRateLimitError("Too many requests", 60.0)
        ratelim_nil = CloudRateLimitError("Too many requests", nothing)
        timeout_err = CloudTimeoutError("Timed out after 30s")
        server_err  = CloudServerError("Internal server error", 503)

        @test occursin("401", sprint(showerror, auth_err))
        @test occursin("60.0", sprint(showerror, ratelim_err))
        @test occursin("unknown", sprint(showerror, ratelim_nil))
        @test occursin("30s", sprint(showerror, timeout_err))
        @test occursin("503", sprint(showerror, server_err))

        # All are subtypes of CloudProviderError
        for e in [auth_err, ratelim_err, timeout_err, server_err]
            @test e isa Pluto.CloudProvider.CloudProviderError
        end
    end

    # ─────────────────────────────────────────────────────────────────────────
    @testset "cloud_request throws CloudAuthError when no key is configured" begin
        env_name = "TEST_PLUTO_ABSENT_KEY_$(rand(UInt32))"
        opts = CloudProviderOptions(;
            api_key_env = env_name,
            max_retries = 0,
        )
        # Make sure the env var is absent
        @test get(ENV, env_name, "") == ""
        @test_throws CloudAuthError cloud_request(opts, "/some/endpoint", "{}") 
    end

    # ─────────────────────────────────────────────────────────────────────────
    @testset "Options struct contains cloud field" begin
        # Verify the cloud config is accessible through the main Options struct
        opts = Pluto.Configuration.Options()
        @test opts.cloud isa CloudProviderOptions

        custom_cloud = CloudProviderOptions(; max_retries=1, timeout=5.0)
        opts2 = Pluto.Configuration.Options(; cloud=custom_cloud)
        @test opts2.cloud.max_retries == 1
        @test opts2.cloud.timeout == 5.0
    end

    # ─────────────────────────────────────────────────────────────────────────
    @testset "ServerSession carries cloud options" begin
        session = Pluto.ServerSession()
        @test session.options.cloud isa CloudProviderOptions
    end

end
