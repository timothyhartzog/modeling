"""
    circuit_breaker.jl — Circuit breaker for rate-limit and server-error protection.

States:
  :closed   — Normal operation. Requests pass through.
  :open     — Too many failures. Requests are rejected immediately.
  :half_open — Timeout elapsed; one probe request is allowed to test recovery.
"""
module CircuitBreaker

export CircuitBreakerState, check_and_update!, should_allow!

mutable struct CircuitBreakerState
    state::Symbol  # :closed, :open, :half_open
    failure_count::Int
    failure_threshold::Int
    reset_timeout::Float64  # seconds
    last_trip_time::Union{Float64, Nothing}
end

"""
    check_and_update!(cb::CircuitBreakerState, status::Int) → Bool

Inspect the last HTTP `status` code and advance the circuit-breaker state machine.
Returns `true` if the next request should proceed, `false` if the circuit is open.

Transitions:
- 429 status increments `failure_count`; once it reaches `failure_threshold` the
  circuit moves to `:open` and subsequent calls return `false`.
- Any non-429 status resets `failure_count` to zero and closes the circuit when
  it was `:half_open`.
- After `reset_timeout` seconds in the `:open` state, the circuit moves to
  `:half_open` and allows one probe request through.
"""
function check_and_update!(cb::CircuitBreakerState, status::Int)::Bool
    if status == 429
        cb.failure_count += 1
        if cb.failure_count >= cb.failure_threshold
            cb.state = :open
            cb.last_trip_time = time()
            @error "Circuit breaker OPEN: Rate limit threshold exceeded"
            return false
        end
    else
        cb.failure_count = 0
        if cb.state == :half_open
            cb.state = :closed
            @info "Circuit breaker CLOSED: Recovered"
        end
    end

    if cb.state == :open && cb.last_trip_time !== nothing &&
            time() - cb.last_trip_time > cb.reset_timeout
        cb.state = :half_open
        cb.failure_count = 0
        @info "Circuit breaker HALF_OPEN: Testing recovery..."
    end

    return cb.state != :open
end

"""
    should_allow!(cb::CircuitBreakerState) → Bool

Pre-flight check: applies the `:open` → `:half_open` timeout transition if
`reset_timeout` has elapsed, then returns `true` if the request should proceed
or `false` if the circuit is still open.

Call this *before* issuing a request; call `check_and_update!` *after* receiving
the response status.
"""
function should_allow!(cb::CircuitBreakerState)::Bool
    if cb.state == :open && cb.last_trip_time !== nothing &&
            time() - cb.last_trip_time > cb.reset_timeout
        cb.state = :half_open
        cb.failure_count = 0
        @info "Circuit breaker HALF_OPEN: Testing recovery..."
    end
    return cb.state != :open
end

end  # module
