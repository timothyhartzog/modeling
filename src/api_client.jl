"""
    api_client.jl — Anthropic API wrapper with exponential backoff and retry logic.
"""
module APIClient

using HTTP, JSON3, Dates, Logging

export generate_chapter, GenerationResult, TransientError, PermanentError

abstract type APIException <: Exception end

"""Transient API error that should be retried with exponential backoff."""
struct TransientError <: APIException
    message::String
    status::Int
    retry_after::Float64
end

"""Permanent API error that should not be retried (e.g. auth failure, bad request)."""
struct PermanentError <: APIException
    message::String
    status::Int
end

Base.showerror(io::IO, e::TransientError) =
    print(io, "TransientError ($(e.status)): $(e.message)")
Base.showerror(io::IO, e::PermanentError) =
    print(io, "PermanentError ($(e.status)): $(e.message)")

"""
    is_transient_error(status, error) → Bool

Return `true` for HTTP status codes and exception types that are safe to retry.
"""
function is_transient_error(status::Int, error::Exception)::Bool
    status in (429, 502, 503, 504, 522) && return true  # Service issues
    error isa HTTP.ConnectError && return true           # Network connection
    error isa HTTP.RequestError && return true           # Request-level network error
    error isa Base.IOError && return true               # I/O
    return false
end

"""
    is_permanent_error(status) → Bool

Return `true` for HTTP status codes that indicate a non-retryable failure.
"""
function is_permanent_error(status::Int)::Bool
    status in (400, 401, 403, 404, 422) && return true
    return false
end

const API_URL = "https://api.anthropic.com/v1/messages"
const MODEL = "claude-sonnet-4-20250514"
const MAX_TOKENS = 8192
const MAX_RETRIES = 5
const BASE_DELAY = 2.0  # seconds

"""
    GenerationResult

Holds the generated content along with token usage metadata from the API response.

Fields:
- `content`              — Generated markdown text.
- `input_tokens`         — Uncached input tokens billed.
- `output_tokens`        — Output tokens generated.
- `cache_read_tokens`    — Input tokens served from the prompt cache.
- `cache_creation_tokens`— Input tokens written into the prompt cache.
- `stop_reason`          — Why generation stopped (`"end_turn"` or `"max_tokens"`).
"""
struct GenerationResult
    content::String
    input_tokens::Int
    output_tokens::Int
    cache_read_tokens::Int
    cache_creation_tokens::Int
    stop_reason::String
end

"""
    get_api_key() → String

Read API key from environment variable ANTHROPIC_API_KEY.
"""
function get_api_key()
    key = get(ENV, "ANTHROPIC_API_KEY", "")
    isempty(key) && error("ANTHROPIC_API_KEY environment variable not set")
    return key
end

"""
    generate_chapter(system_prompt::String, chapter_prompt::String; 
                     api_key::String=get_api_key()) → GenerationResult

Call the Anthropic API to generate a single chapter. Returns a `GenerationResult`
containing the generated markdown text and token usage metadata.
Retries with exponential backoff on rate limits and transient errors.
"""
function generate_chapter(system_prompt::String, chapter_prompt::String;
                          api_key::String=get_api_key())
    headers = [
        "x-api-key" => api_key,
        "anthropic-version" => "2023-06-01",
        "anthropic-beta" => "prompt-caching-2024-07-31",
        "content-type" => "application/json"
    ]

    body = JSON3.write(Dict(
        "model" => MODEL,
        "max_tokens" => MAX_TOKENS,
        "system" => [
            Dict(
                "type" => "text",
                "text" => system_prompt,
                "cache_control" => Dict("type" => "ephemeral")
            )
        ],
        "messages" => [
            Dict("role" => "user", "content" => chapter_prompt)
        ]
    ))

    for attempt in 1:MAX_RETRIES
        try
            response = HTTP.post(API_URL, headers, body;
                                 connect_timeout=30, readtimeout=300,
                                 retry=false, status_exception=false)

            status = response.status

            if status == 200
                result = JSON3.read(String(response.body))
                # Log token usage including cache hits/misses
                if haskey(result, :usage)
                    u = result.usage
                    input_tokens                 = get(u, :input_tokens, 0)
                    output_tokens                = get(u, :output_tokens, 0)
                    cache_creation_input_tokens  = get(u, :cache_creation_input_tokens, 0)
                    cache_read_input_tokens      = get(u, :cache_read_input_tokens, 0)
                    @debug "Token usage" input_tokens output_tokens cache_creation_input_tokens cache_read_input_tokens
                end
                # Extract text from content blocks
                text_parts = String[]
                for block in result.content
                    if block.type == "text"
                        push!(text_parts, block.text)
                    end
                end
                content = join(text_parts, "\n")

                # Extract token usage
                usage = get(result, :usage, nothing)
                input_tokens          = usage !== nothing ? Int(get(usage, :input_tokens, 0)) : 0
                output_tokens         = usage !== nothing ? Int(get(usage, :output_tokens, 0)) : 0
                cache_read_tokens     = usage !== nothing ? Int(get(usage, :cache_read_input_tokens, 0)) : 0
                cache_creation_tokens = usage !== nothing ? Int(get(usage, :cache_creation_input_tokens, 0)) : 0

                stop_reason = String(get(result, :stop_reason, "unknown"))
                if stop_reason == "max_tokens"
                    @warn "Chapter truncated at max_tokens ($MAX_TOKENS). Content may be incomplete."
                end

                return GenerationResult(content, input_tokens, output_tokens,
                                        cache_read_tokens, cache_creation_tokens, stop_reason)

            elseif is_permanent_error(status)
                body_str = String(response.body)
                @error "Permanent API error ($status): $body_str"
                throw(PermanentError(body_str, status))

            elseif status == 429
                # Rate limited — extract retry-after if available
                retry_after = _get_retry_after(HTTP.headers(response))
                delay = max(retry_after, BASE_DELAY * 2^(attempt - 1))
                @warn "Rate limited (429). Retry $attempt/$MAX_RETRIES in $(round(delay, digits=1))s"
                sleep(delay)

            elseif status == 529 || status >= 500
                # Overloaded or server error — transient, apply backoff
                delay = BASE_DELAY * 2^(attempt - 1)
                @warn "Server error ($status). Retry $attempt/$MAX_RETRIES in $(round(delay, digits=1))s"
                sleep(delay)

            else
                body_str = String(response.body)
                error("API returned unexpected status $status: $body_str")
            end
        catch e
            # PermanentError must propagate immediately — never retry auth/validation failures.
            e isa PermanentError && rethrow(e)
            if is_transient_error(0, e)
                delay = BASE_DELAY * 2^(attempt - 1)
                @warn "Network error: $e. Retry $attempt/$MAX_RETRIES in $(round(delay, digits=1))s"
                sleep(delay)
            else
                rethrow(e)
            end
        end
    end

    error("Failed after $MAX_RETRIES retries")
end

function _get_retry_after(headers)
    for (k, v) in headers
        if lowercase(k) == "retry-after"
            return parse(Float64, v)
        end
    end
    return 0.0
end

end # module
