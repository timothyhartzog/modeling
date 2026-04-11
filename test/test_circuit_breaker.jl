"""
    test_circuit_breaker.jl — Unit tests for src/circuit_breaker.jl
"""

using Test

if !isdefined(Main, :CircuitBreaker)
    include(joinpath(@__DIR__, "..", "src", "circuit_breaker.jl"))
end
using .CircuitBreaker: CircuitBreakerState, check_and_update!, should_allow!

@testset "CircuitBreaker" begin

    # Helper: fresh circuit breaker with threshold=3, timeout=60s
    function make_cb(; threshold=3, timeout=60.0)
        CircuitBreakerState(:closed, 0, threshold, timeout, nothing)
    end

    @testset "initial state is :closed and allows requests" begin
        cb = make_cb()
        @test cb.state == :closed
        @test check_and_update!(cb, 200) == true
        @test cb.state == :closed
    end

    @testset "non-429 success resets failure count" begin
        cb = make_cb()
        cb.failure_count = 2
        check_and_update!(cb, 200)
        @test cb.failure_count == 0
    end

    @testset "429 increments failure count" begin
        cb = make_cb()
        check_and_update!(cb, 429)
        @test cb.failure_count == 1
        @test cb.state == :closed
    end

    @testset "circuit opens after reaching failure threshold" begin
        cb = make_cb(threshold=3)
        check_and_update!(cb, 429)
        check_and_update!(cb, 429)
        result = check_and_update!(cb, 429)
        @test result == false
        @test cb.state == :open
        @test cb.last_trip_time !== nothing
    end

    @testset "open circuit rejects requests" begin
        cb = make_cb(threshold=1)
        check_and_update!(cb, 429)  # opens circuit
        @test cb.state == :open
        # Subsequent calls with any status return false while still open
        @test check_and_update!(cb, 429) == false
    end

    @testset "circuit transitions to :half_open after reset timeout" begin
        cb = make_cb(threshold=1, timeout=0.05)
        check_and_update!(cb, 429)         # opens circuit
        @test cb.state == :open
        sleep(0.1)                         # wait for timeout to expire
        # Passing a non-429 status triggers the timeout check (429 would return early)
        result = check_and_update!(cb, 200)
        @test cb.state == :half_open
        @test cb.failure_count == 0
        @test result == true               # :half_open allows requests through
    end

    @testset "circuit closes after successful probe in :half_open" begin
        cb = make_cb(threshold=1, timeout=0.05)
        check_and_update!(cb, 429)   # open
        sleep(0.1)
        check_and_update!(cb, 200)   # → :half_open (timeout elapsed, non-429 triggers check)
        result = check_and_update!(cb, 200)  # success in :half_open → :closed
        @test cb.state == :closed
        @test result == true
    end

    @testset "circuit re-opens on 429 in :half_open" begin
        cb = make_cb(threshold=1, timeout=0.05)
        check_and_update!(cb, 429)   # open (threshold=1)
        sleep(0.1)
        check_and_update!(cb, 200)   # → :half_open (timeout elapsed, non-429)
        @test cb.state == :half_open
        result = check_and_update!(cb, 429)  # 429 in :half_open → increments, re-opens
        @test cb.state == :open
        @test result == false
    end

    @testset "failure_count resets to zero when circuit closes" begin
        cb = make_cb(threshold=1, timeout=0.05)
        check_and_update!(cb, 429)   # open
        sleep(0.1)
        check_and_update!(cb, 200)   # → :half_open
        check_and_update!(cb, 200)   # → :closed
        @test cb.failure_count == 0
    end

    @testset "open circuit resets last_trip_time on 429 above threshold" begin
        cb = make_cb(threshold=1)
        check_and_update!(cb, 429)
        trip_time = cb.last_trip_time
        sleep(0.01)
        # A new 429 on an open circuit re-triggers the threshold branch, resetting trip time
        check_and_update!(cb, 429)
        @test cb.last_trip_time !== trip_time
        @test cb.last_trip_time > trip_time
    end

    @testset "open circuit does not change last_trip_time on non-429 calls" begin
        cb = make_cb(threshold=1, timeout=60.0)  # large timeout so it doesn't expire
        check_and_update!(cb, 429)
        trip_time = cb.last_trip_time
        check_and_update!(cb, 200)   # non-429, timeout hasn't elapsed
        @test cb.last_trip_time == trip_time
    end

    @testset "allows requests below failure threshold" begin
        cb = make_cb(threshold=5)
        for _ in 1:4
            @test check_and_update!(cb, 429) == true
        end
        @test cb.failure_count == 4
        @test cb.state == :closed
    end

    @testset "return type is Bool" begin
        cb = make_cb()
        @test check_and_update!(cb, 200) isa Bool
        @test check_and_update!(cb, 429) isa Bool
    end

    @testset "should_allow! — closed circuit permits requests" begin
        cb = make_cb()
        @test should_allow!(cb) == true
    end

    @testset "should_allow! — open circuit blocks requests" begin
        cb = make_cb(threshold=1)
        check_and_update!(cb, 429)
        @test cb.state == :open
        @test should_allow!(cb) == false
    end

    @testset "should_allow! — transitions :open → :half_open after timeout" begin
        cb = make_cb(threshold=1, timeout=0.05)
        check_and_update!(cb, 429)
        @test cb.state == :open
        sleep(0.1)
        result = should_allow!(cb)
        @test cb.state == :half_open
        @test result == true
    end

    @testset "should_allow! — :half_open permits requests" begin
        cb = make_cb(threshold=1, timeout=0.05)
        check_and_update!(cb, 429)
        sleep(0.1)
        should_allow!(cb)  # → :half_open
        @test should_allow!(cb) == true
    end

end
