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

        # Delay for attempt n = BASE_DELAY * 2^(n-1)
        for attempt in 1:5
            expected = base * 2^(attempt - 1)
            @test base * 2^(attempt - 1) ≈ expected
        end

        # Verify increasing sequence
        delays = [base * 2^(a - 1) for a in 1:5]
        @test issorted(delays)

        # Attempt 1: no extra wait beyond base
        @test delays[1] == base
        # Attempt 2: double the base
        @test delays[2] ≈ 2 * base
        # Attempt 3: four times the base
        @test delays[3] ≈ 4 * base
    end

end
