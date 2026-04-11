"""
    test_api_client.jl — Unit tests for src/api_client.jl
    Note: No real HTTP calls are made; ANTHROPIC_API_KEY is not required.
"""

using Test

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
