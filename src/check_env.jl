#!/usr/bin/env julia
"""
    check_env.jl — Pre-flight environment validator for the textbook generation pipeline.

    Usage:
        julia --project=. src/check_env.jl                # Full check (default)
        julia --project=. src/check_env.jl --no-api-ping  # Skip live API test
        julia --project=. src/check_env.jl --json         # JSON output for programmatic use
"""

using Pkg

# ─────────────────────────────────────────────
# CLI argument parsing
# ─────────────────────────────────────────────
const NO_API_PING = "--no-api-ping" in ARGS
const JSON_OUTPUT = "--json"        in ARGS

# ─────────────────────────────────────────────
# Attempt to load optional packages at top level
# ─────────────────────────────────────────────
const _HTTP_OK  = try; using HTTP;  true; catch; false; end
const _JSON3_OK = try; using JSON3; true; catch; false; end

# ─────────────────────────────────────────────
# Paths (mirrors generate.jl conventions)
# ─────────────────────────────────────────────
const PROJECT_ROOT       = dirname(@__DIR__)
const SYSTEM_PROMPT_PATH = joinpath(PROJECT_ROOT, "system_prompt.md")
const STATE_PATH         = joinpath(PROJECT_ROOT, "state.json")
const OUTPUT_DIR         = joinpath(PROJECT_ROOT, "output")
const MANIFEST_PATHS     = [
    joinpath(PROJECT_ROOT, "manifests", "part1.json"),
    joinpath(PROJECT_ROOT, "manifests", "part2.json"),
]

# ─────────────────────────────────────────────
# Result accumulation
# ─────────────────────────────────────────────
struct CheckResult
    label  :: String
    passed :: Bool
    detail :: String   # shown on the same line after the tick/cross
    hint   :: String   # shown as an indented fix hint on failure (may be "")
end

const RESULTS = CheckResult[]

function record!(label::String, passed::Bool, detail::String, hint::String="")
    push!(RESULTS, CheckResult(label, passed, detail, hint))
end

# ─────────────────────────────────────────────
# Helper: thousands separator
# ─────────────────────────────────────────────
function _fmt(n::Int)
    s = string(n)
    buf = IOBuffer()
    for (i, c) in enumerate(reverse(s))
        i > 1 && (i - 1) % 3 == 0 && write(buf, ',')
        write(buf, c)
    end
    return String(reverse(take!(buf)))
end

# ─────────────────────────────────────────────
# Individual checks
# ─────────────────────────────────────────────

function check_julia_version()
    v  = VERSION
    ok = v >= v"1.10"
    record!(
        "Julia version",
        ok,
        "$(v.major).$(v.minor).$(v.patch) ($(ok ? "≥" : "<") 1.10 required)",
        ok ? "" : "Upgrade to Julia 1.10 or later: https://julialang.org/downloads/"
    )
end

function check_package(pkg_name::String, loaded::Bool)
    if !loaded
        record!(
            "$(pkg_name).jl",
            false,
            "NOT FOUND",
            "Run: julia --project=. -e 'using Pkg; Pkg.instantiate()' to install packages"
        )
        return
    end

    # Try to get the installed version from Pkg.dependencies()
    ver_str = ""
    try
        for (_, info) in Pkg.dependencies()
            if info.name == pkg_name && info.version !== nothing
                ver_str = " ($(info.version))"
                break
            end
        end
    catch
    end

    record!("$(pkg_name).jl", true, "installed$(ver_str)")
end

function check_api_key()
    key = get(ENV, "ANTHROPIC_API_KEY", "")
    ok  = !isempty(key)
    detail = if ok
        # Show first 7 chars and last 3 chars with enough gap that they never overlap
        masked = length(key) >= 14 ?
            "$(key[1:7])...$(key[end-2:end])" : "****"
        "set ($(masked))"
    else
        "NOT SET"
    end
    record!(
        "ANTHROPIC_API_KEY",
        ok,
        detail,
        ok ? "" : "Export your key: export ANTHROPIC_API_KEY=\"sk-ant-...\""
    )
    return ok
end

function check_api_connectivity(key::String)
    if NO_API_PING
        record!("API connectivity", true, "skipped (--no-api-ping)")
        return
    end
    if !_HTTP_OK || !_JSON3_OK
        record!("API connectivity", false,
                "SKIPPED — HTTP.jl or JSON3.jl not loaded",
                "Install missing packages first, then re-run.")
        return
    end

    try
        headers = [
            "x-api-key"         => key,
            "anthropic-version" => "2023-06-01",
            "content-type"      => "application/json",
        ]
        # Minimal 1-token request to verify credentials without spending budget
        body = JSON3.write(Dict(
            "model"      => "claude-haiku-4-20250514",
            "max_tokens" => 1,
            "messages"   => [Dict("role" => "user", "content" => "hi")],
        ))
        resp = HTTP.post(
            "https://api.anthropic.com/v1/messages",
            headers, body;
            connect_timeout=15, readtimeout=30,
            retry=false, status_exception=false
        )
        if resp.status == 200
            record!("API connectivity", true, "OK (test ping succeeded)")
        elseif resp.status == 401
            record!("API connectivity", false,
                    "FAILED — 401 Unauthorized (invalid key)",
                    "Check that ANTHROPIC_API_KEY is correct and has API access.")
        elseif resp.status == 403
            record!("API connectivity", false,
                    "FAILED — 403 Forbidden (insufficient permissions)",
                    "Ensure the API key has Messages API access in your Anthropic console.")
        elseif resp.status == 429
            record!("API connectivity", true,
                    "rate-limited (429) — key is valid but you are being rate-limited")
        else
            body_str = first(String(resp.body), 120)
            record!("API connectivity", false,
                    "FAILED — HTTP $(resp.status): $(body_str)",
                    "Check Anthropic status page: https://status.anthropic.com/")
        end
    catch e
        record!("API connectivity", false,
                "FAILED — $(sprint(showerror, e))",
                "Check network connectivity and try again, or use --no-api-ping to skip.")
    end
end

function check_system_prompt()
    exists = isfile(SYSTEM_PROMPT_PATH)
    detail = if exists
        chars = length(read(SYSTEM_PROMPT_PATH, String))
        "found ($(_fmt(chars)) chars)"
    else
        "NOT FOUND at $(relpath(SYSTEM_PROMPT_PATH, PROJECT_ROOT))"
    end
    record!(
        "system_prompt.md",
        exists,
        detail,
        exists ? "" : "Create system_prompt.md in the project root (see README.md)."
    )
end

function check_manifest(path::String)
    label = "manifests/$(basename(path))"
    if !isfile(path)
        record!(label, false,
                "NOT FOUND at $(relpath(path, PROJECT_ROOT))",
                "Ensure the manifests/ directory is present and the file exists.")
        return
    end
    if !_JSON3_OK
        record!(label, false,
                "SKIPPED — JSON3.jl not loaded",
                "Install missing packages first, then re-run.")
        return
    end
    try
        data       = JSON3.read(read(path, String))
        textbooks  = get(data, :textbooks, nothing)
        n_books    = textbooks === nothing ? 0 : length(textbooks)
        n_chapters = 0
        if textbooks !== nothing
            for tb in textbooks
                chs = get(tb, :chapters, nothing)
                chs !== nothing && (n_chapters += length(chs))
            end
        end
        record!(label, true,
                "valid JSON ($(_fmt(n_books)) textbooks, $(_fmt(n_chapters)) chapters)")
    catch e
        record!(label, false,
                "INVALID JSON — $(sprint(showerror, e))",
                "Validate: julia -e 'using JSON3; JSON3.read(read(\"$(path)\", String))'")
    end
end

function check_output_dir()
    try
        mkpath(OUTPUT_DIR)
    catch
    end
    probe = joinpath(OUTPUT_DIR, ".write_test_$(getpid())")
    ok = try
        write(probe, "ok")
        rm(probe)
        true
    catch
        false
    end
    record!(
        "output/ directory",
        ok,
        ok ? "writable" : "NOT WRITABLE at $(relpath(OUTPUT_DIR, PROJECT_ROOT))",
        ok ? "" : "Check permissions: chmod u+w $(OUTPUT_DIR)"
    )
end

function check_pandoc()
    result = Sys.which("pandoc")
    found  = result !== nothing
    detail = if found
        ver = try
            first(split(strip(read(`pandoc --version`, String)), '\n'))
        catch
            "(version unknown)"
        end
        "found ($(ver))"
    else
        "NOT FOUND in PATH"
    end
    record!(
        "pandoc",
        found,
        detail,
        found ? "" : "Install pandoc: brew install pandoc  OR  apt-get install pandoc"
    )
end

function check_state()
    if !isfile(STATE_PATH)
        record!("state.json", true, "not present (fresh run)")
        return
    end
    if !_JSON3_OK
        record!("state.json", false,
                "SKIPPED — JSON3.jl not loaded",
                "Install missing packages first, then re-run.")
        return
    end
    try
        data      = JSON3.read(read(STATE_PATH, String))
        completed = get(data, :completed, Dict())
        failed    = get(data, :failed,    Dict())
        record!("state.json", true,
                "$(_fmt(length(completed))) completed, $(_fmt(length(failed))) failed")
    catch e
        record!("state.json", false,
                "INVALID JSON — $(sprint(showerror, e))",
                "Delete or repair state.json before running the generator.")
    end
end

# ─────────────────────────────────────────────
# Reporting
# ─────────────────────────────────────────────

function print_banner()
    println()
    println("╔══════════════════════════════════════════╗")
    println("║     PRE-FLIGHT ENVIRONMENT CHECK         ║")
    println("╚══════════════════════════════════════════╝")
    println()
end

function print_results(results::Vector{CheckResult})
    for r in results
        mark = r.passed ? "\e[32m[✓]\e[0m" : "\e[31m[✗]\e[0m"
        println("$(mark) $(rpad(r.label * ":", 26)) $(r.detail)")
        if !r.passed && !isempty(r.hint)
            println("     \e[33m→ $(r.hint)\e[0m")
        end
    end
    println()
end

function print_summary(results::Vector{CheckResult}, total_chapters::Int)
    all_passed = all(r.passed for r in results)
    if all_passed
        println("\e[32mAll checks passed.\e[0m Ready to generate $(_fmt(total_chapters)) chapters.")
    else
        n_failed = count(!r.passed for r in results)
        println("\e[31m$(n_failed) check(s) failed.\e[0m Fix the issues above before starting a run.")
    end
    println()
end

function print_json_output(results::Vector{CheckResult}, total_chapters::Int)
    if !_JSON3_OK
        # Fallback to manual JSON serialization if JSON3 isn't available
        println("{\"error\":\"JSON3.jl not loaded — install packages and re-run\"}")
        return
    end
    all_passed = all(r.passed for r in results)
    checks = [
        Dict(
            "label"  => r.label,
            "passed" => r.passed,
            "detail" => r.detail,
            "hint"   => r.hint,
        )
        for r in results
    ]
    println(JSON3.write(Dict(
        "all_passed"     => all_passed,
        "total_chapters" => total_chapters,
        "checks"         => checks,
    )))
end

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

function main()
    # Run all checks
    check_julia_version()
    check_package("HTTP",  _HTTP_OK)
    check_package("JSON3", _JSON3_OK)

    api_key_ok = check_api_key()
    if api_key_ok
        check_api_connectivity(get(ENV, "ANTHROPIC_API_KEY", ""))
    else
        record!("API connectivity", false, "SKIPPED (no API key)",
                "Set ANTHROPIC_API_KEY first.")
    end

    check_system_prompt()
    for path in MANIFEST_PATHS
        check_manifest(path)
    end
    check_output_dir()
    check_pandoc()
    check_state()

    # Count total chapters from manifests for summary line
    total_chapters = 0
    if _JSON3_OK
        for path in MANIFEST_PATHS
            isfile(path) || continue
            try
                data = JSON3.read(read(path, String))
                tbs  = get(data, :textbooks, nothing)
                tbs === nothing && continue
                for tb in tbs
                    chs = get(tb, :chapters, nothing)
                    chs !== nothing && (total_chapters += length(chs))
                end
            catch
            end
        end
    end

    # Output
    if JSON_OUTPUT
        print_json_output(RESULTS, total_chapters)
    else
        print_banner()
        print_results(RESULTS)
        print_summary(RESULTS, total_chapters)
    end

    # Non-zero exit code when any check fails
    all(r.passed for r in RESULTS) || exit(1)
end

main()
