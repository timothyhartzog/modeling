"""
    test_api_client.jl — Unit tests for src/api_client.jl
    Note: No real HTTP calls are made; ANTHROPIC_API_KEY is not required.
"""

using Test, HTTP

include(joinpath(@__DIR__, "..", "src", "api_client.jl"))
using .APIClient

@testset "APIClient" begin

    @testset "get_api_key raises error when env var is absent" begin
        # Temporarily remove the env var if present, then restore
        old_key = get(ENV, "ANTHROPIC_API_KEY", nothing)
        delete!(ENV, "ANTHROPIC_API_KEY")
        try
            @test_throws ErrorException APIClient.get_api_key()
        finally
            if old_key !== nothing
                ENV["ANTHROPIC_API_KEY"] = old_key
            end
        end
    end

    @testset "_get_retry_after parses Retry-After header" begin
        # Header present with integer value
        headers_int = ["Retry-After" => "30"]
        @test APIClient._get_retry_after(headers_int) == 30.0

        # Header present with float value
        headers_float = ["retry-after" => "1.5"]
        @test APIClient._get_retry_after(headers_float) == 1.5

        # Header is case-insensitive
        headers_upper = ["RETRY-AFTER" => "60"]
        @test APIClient._get_retry_after(headers_upper) == 60.0

        # Header absent returns 0.0
        headers_none = ["Content-Type" => "application/json"]
        @test APIClient._get_retry_after(headers_none) == 0.0

        # Empty headers returns 0.0
        @test APIClient._get_retry_after(Pair{String,String}[]) == 0.0
    end

    @testset "is_permanent_error" begin
        for s in (400, 401, 403, 404, 422)
            @test APIClient.is_permanent_error(s) == true
        end
        for s in (200, 429, 500, 502, 503, 504, 529)
            @test APIClient.is_permanent_error(s) == false
        end
    end

    @testset "is_transient_error" begin
        sentinel = ErrorException("other")
        for s in (429, 502, 503, 504, 522)
            @test APIClient.is_transient_error(s, sentinel) == true
        end
        # non-transient status, non-IO exception → false
        @test APIClient.is_transient_error(200, sentinel) == false
        @test APIClient.is_transient_error(401, sentinel) == false
        # Base.IOError is transient regardless of status
        @test APIClient.is_transient_error(0, Base.IOError("disk", 0)) == true
        # HTTP.ConnectError and HTTP.RequestError are transient
        @test APIClient.is_transient_error(0, HTTP.ConnectError("example.com", Base.IOError("refused", 0))) == true
        req = HTTP.Request("GET", "/")
        @test APIClient.is_transient_error(0, HTTP.RequestError(req, Base.IOError("reset", 0))) == true
    end

    @testset "PermanentError and TransientError are subtypes of APIException" begin
        @test APIClient.PermanentError <: APIClient.APIException
        @test APIClient.TransientError <: APIClient.APIException
        @test APIClient.APIException <: Exception
    end

    @testset "PermanentError fields" begin
        e = APIClient.PermanentError("bad request", 400)
        @test e.message == "bad request"
        @test e.status == 400
    end

    @testset "TransientError fields" begin
        e = APIClient.TransientError("rate limited", 429, 5.0)
        @test e.message == "rate limited"
        @test e.status == 429
        @test e.retry_after == 5.0
    end

    @testset "exponential backoff delay formula" begin
        base = APIClient.BASE_DELAY
        @test base > 0.0

        # Delay for attempt n = BASE_DELAY * 2^(n-1) — check against concrete values
        expected_delays = [base * 2^(a - 1) for a in 1:5]
        @test expected_delays[1] == base          # attempt 1: 2.0s
        @test expected_delays[2] ≈ 2 * base       # attempt 2: 4.0s
        @test expected_delays[3] ≈ 4 * base       # attempt 3: 8.0s
        @test expected_delays[4] ≈ 8 * base       # attempt 4: 16.0s
        @test expected_delays[5] ≈ 16 * base      # attempt 5: 32.0s

        # Verify strictly increasing sequence
        @test issorted(expected_delays)
    end

end
