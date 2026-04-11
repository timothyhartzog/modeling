#!/usr/bin/env julia
"""
    generate.jl — Main orchestrator for parallel textbook chapter generation.

    Usage:
        julia --project=. src/generate.jl                        # Full run, concurrency=5
        julia --project=. src/generate.jl --concurrency 10       # Full run, concurrency=10
        julia --project=. src/generate.jl --calibrate            # Generate 3 test chapters only
        julia --project=. src/generate.jl --resume               # Resume from last state
        julia --project=. src/generate.jl --textbook CORE-001    # Generate one textbook only
        julia --project=. src/generate.jl --dry-run              # Show work queue, don't generate
"""

include("api_client.jl")
include("prompt_builder.jl")

using .APIClient
using .PromptBuilder
using JSON3, Dates, Logging, Printf

# ─────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────
const PROJECT_ROOT = dirname(@__DIR__)
const MANIFESTS = [
    joinpath(PROJECT_ROOT, "manifests", "part1.json"),
    joinpath(PROJECT_ROOT, "manifests", "part2.json")
]
const SYSTEM_PROMPT_PATH = joinpath(PROJECT_ROOT, "system_prompt.md")
const STATE_PATH = joinpath(PROJECT_ROOT, "state.json")
const OUTPUT_DIR = joinpath(PROJECT_ROOT, "output", "markdown")
const LOG_PATH = joinpath(PROJECT_ROOT, "logs", "generation.log")

# Concurrency limits
const MAX_RECOMMENDED_CONCURRENCY = 20
const HARD_MAX_CONCURRENCY = 50

# Claude Sonnet 4 pricing (USD per million tokens)
const PRICE_INPUT_PER_MTOK        = 3.00
const PRICE_OUTPUT_PER_MTOK       = 15.00
const PRICE_CACHE_READ_PER_MTOK   = 0.30
const PRICE_CACHE_CREATE_PER_MTOK = 3.75

# Calibration chapters: one pure math, one SciML/code-heavy, one applied/clinical
const CALIBRATION_KEYS = [
    "CORE-001/ch01",  # Real Analysis — completeness
    "SCIML-001/ch03", # Neural DEs — UDEs (hybrid math + Julia)
    "PHYS-004/ch04",  # Biomechanics — respiratory mechanics
]

# ─────────────────────────────────────────────
# State Management
# ─────────────────────────────────────────────
const STATE_SCHEMA_VERSION = "1.1"

mutable struct GenerationState
    completed::Dict{String,String}  # key → ISO timestamp
    failed::Dict{String,String}     # key → error message
    truncated::Dict{String,Int}     # key → output_tokens (hit max_tokens limit)
    started_at::String
    last_updated::String
end

function load_state()::GenerationState
    if isfile(STATE_PATH)
        raw = JSON3.read(read(STATE_PATH, String))
        version = haskey(raw, :schema_version) ? String(raw.schema_version) : "1.0"

        if version == "1.0"
            @info "Migrating state.json from schema v1.0 → v$(STATE_SCHEMA_VERSION)"
            # v1.0 → v1.1: no structural changes, version field is added on next save
        elseif version != STATE_SCHEMA_VERSION
            error("state.json schema version '$(version)' is not supported by this version of generate.jl " *
                  "(expected $(STATE_SCHEMA_VERSION)). Delete state.json to start fresh, or downgrade the generator.")
        end

        return GenerationState(
            Dict{String,String}(String(k) => String(v) for (k,v) in pairs(raw.completed)),
            haskey(raw, :failed) ? Dict{String,String}(String(k) => String(v) for (k,v) in pairs(raw.failed)) : Dict{String,String}(),
            haskey(raw, :truncated) ? Dict{String,Int}(String(k) => Int(v) for (k,v) in pairs(raw.truncated)) : Dict{String,Int}(),
            String(raw.started_at),
            String(raw.last_updated)
        )
    else
        now_str = string(Dates.now())
        return GenerationState(Dict{String,String}(), Dict{String,String}(), Dict{String,Int}(), now_str, now_str)
    end
end

function save_state(state::GenerationState)
    state.last_updated = string(Dates.now())
    json = JSON3.write(Dict(
        "schema_version" => STATE_SCHEMA_VERSION,
        "completed" => state.completed,
        "failed" => state.failed,
        "truncated" => state.truncated,
        "started_at" => state.started_at,
        "last_updated" => state.last_updated
    ))
    # Atomic write: write to temp, then rename
    tmp = STATE_PATH * ".tmp"
    write(tmp, json)
    mv(tmp, STATE_PATH; force=true)
end

# ─────────────────────────────────────────────
# File I/O
# ─────────────────────────────────────────────
function save_chapter(key::String, content::String)
    parts = split(key, "/")
    textbook_dir = joinpath(OUTPUT_DIR, parts[1])
    mkpath(textbook_dir)
    filepath = joinpath(textbook_dir, "$(parts[2]).md")
    write(filepath, content)
    return filepath
end

# ─────────────────────────────────────────────
# Parse CLI Args
# ─────────────────────────────────────────────
function parse_args()
    args = Dict{Symbol,Any}(
        :concurrency => 5,
        :calibrate => false,
        :resume => false,
        :dry_run => false,
        :textbook => nothing,
        :retry_failed => false,
    )

    i = 1
    while i <= length(ARGS)
        arg = ARGS[i]
        if arg == "--concurrency" && i < length(ARGS)
            requested = parse(Int, ARGS[i+1])
            if requested > HARD_MAX_CONCURRENCY
                @error "--concurrency $requested exceeds hard limit of $HARD_MAX_CONCURRENCY. Clamping to $HARD_MAX_CONCURRENCY."
                requested = HARD_MAX_CONCURRENCY
            elseif requested > MAX_RECOMMENDED_CONCURRENCY
                @warn "--concurrency $requested is above the recommended maximum of $MAX_RECOMMENDED_CONCURRENCY. This may trigger rate limits."
            end
            args[:concurrency] = requested
            i += 2
        elseif arg == "--calibrate"
            args[:calibrate] = true
            i += 1
        elseif arg == "--resume"
            args[:resume] = true
            i += 1
        elseif arg == "--dry-run"
            args[:dry_run] = true
            i += 1
        elseif arg == "--retry-failed"
            args[:retry_failed] = true
            i += 1
        elseif arg == "--textbook" && i < length(ARGS)
            args[:textbook] = ARGS[i+1]
            i += 2
        else
            @warn "Unknown argument: $arg"
            i += 1
        end
    end

    return args
end

# ─────────────────────────────────────────────
# Worker: Generate one chapter
# ─────────────────────────────────────────────
function generate_one(item::WorkItem, system_prompt::String, state::GenerationState,
                      state_lock::ReentrantLock,
                      tok_input::Threads.Atomic{Int}, tok_output::Threads.Atomic{Int},
                      tok_cache_read::Threads.Atomic{Int}, tok_cache_create::Threads.Atomic{Int})
    key = PromptBuilder.work_item_key(item)
    t_start = time()

    try
        prompt = build_chapter_prompt(item)
        result = generate_chapter(system_prompt, prompt)

        filepath = save_chapter(key, result.content)

        # Accumulate token counts (atomic — safe under asyncmap)
        Threads.atomic_add!(tok_input, result.input_tokens)
        Threads.atomic_add!(tok_output, result.output_tokens)
        Threads.atomic_add!(tok_cache_read, result.cache_read_tokens)
        Threads.atomic_add!(tok_cache_create, result.cache_creation_tokens)

        lock(state_lock) do
            state.completed[key] = string(Dates.now())
            delete!(state.failed, key)
            if result.stop_reason == "max_tokens"
                state.truncated[key] = result.output_tokens
            else
                delete!(state.truncated, key)
            end
            save_state(state)
        end

        elapsed = round(time() - t_start, digits=1)
        word_count = length(split(result.content))
        trunc_flag = result.stop_reason == "max_tokens" ? " ⚠️  TRUNCATED" : ""
        @info "✓ $(key) — $(word_count) words in $(elapsed)s → $(filepath)$(trunc_flag)"
        return true

    catch e
        elapsed = round(time() - t_start, digits=1)
        err_msg = sprint(showerror, e)

        lock(state_lock) do
            state.failed[key] = err_msg
            save_state(state)
        end

        @error "✗ $(key) — FAILED in $(elapsed)s: $(err_msg)"
        return false
    end
end

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
function main()
    args = parse_args()

    # Setup logging
    mkpath(dirname(LOG_PATH))
    log_io = open(LOG_PATH, "a")
    logger = SimpleLogger(log_io, Logging.Info)
    global_logger(logger)

    println("=" ^ 60)
    println("  TEXTBOOK GENERATION ORCHESTRATOR")
    println("  $(Dates.now())")
    println("=" ^ 60)

    # Load manifests
    println("\n📚 Loading manifests...")
    all_items = load_manifests(MANIFESTS)
    println("   Found $(length(all_items)) total chapters across $(length(unique(i.textbook_id for i in all_items))) textbooks")

    # Validate calibration keys exist in loaded manifests
    all_keys = Set(PromptBuilder.work_item_key(item) for item in all_items)
    for key in CALIBRATION_KEYS
        key in all_keys || error("Calibration key \"$key\" not found in loaded manifests — update CALIBRATION_KEYS or fix the manifest")
    end

    # Load system prompt
    system_prompt = load_system_prompt(SYSTEM_PROMPT_PATH)
    println("   System prompt loaded ($(length(system_prompt)) chars)")

    # Load state
    state = load_state()
    state_lock = ReentrantLock()
    println("   State: $(length(state.completed)) completed, $(length(state.failed)) failed")

    # Build work queue
    work_queue = if args[:calibrate]
        println("\n🔬 CALIBRATION MODE — generating 3 test chapters")
        filter(item -> PromptBuilder.work_item_key(item) in CALIBRATION_KEYS, all_items)
    elseif !isnothing(args[:textbook])
        tb = args[:textbook]
        println("\n📖 Single textbook mode: $tb")
        filter(item -> item.textbook_id == tb, all_items)
    else
        all_items
    end

    # Filter completed (unless retry-failed)
    if args[:resume] || !args[:retry_failed]
        work_queue = filter(item -> !(PromptBuilder.work_item_key(item) in keys(state.completed)), work_queue)
    end
    if args[:retry_failed]
        # Only retry previously failed items
        work_queue = filter(item -> PromptBuilder.work_item_key(item) in keys(state.failed), work_queue)
    end

    println("   Work queue: $(length(work_queue)) chapters to generate")

    if isempty(work_queue)
        println("\n✅ Nothing to do — all chapters already completed!")
        close(log_io)
        return
    end

    # Dry run
    if args[:dry_run]
        println("\n📋 DRY RUN — would generate:")
        for item in work_queue
            key = PromptBuilder.work_item_key(item)
            println("   $(key): $(item.chapter_title)")
        end
        concurrency = args[:concurrency]
        max_concurrent = concurrency
        limit_status = concurrency <= MAX_RECOMMENDED_CONCURRENCY ? "✓" : "⚠️ above recommended"
        println("\n⚡ Concurrency: $concurrency | Est. ~$max_concurrent req/min | Anthropic Sonnet limit: ~50 req/min $limit_status")
        close(log_io)
        return
    end

    # Confirm
    concurrency = args[:concurrency]
    est_minutes = round(length(work_queue) * 1.0 / concurrency, digits=0)
    println("\n⚡ Starting generation with concurrency=$concurrency")
    println("   Estimated time: ~$(est_minutes) minutes")
    println("   Output: $(OUTPUT_DIR)")
    println("   Press Ctrl+C to stop (safe to resume later)\n")

    # Run
    t_total = time()
    success_count = Threads.Atomic{Int}(0)
    fail_count = Threads.Atomic{Int}(0)
    tok_input        = Threads.Atomic{Int}(0)
    tok_output       = Threads.Atomic{Int}(0)
    tok_cache_read   = Threads.Atomic{Int}(0)
    tok_cache_create = Threads.Atomic{Int}(0)

    # Use asyncmap for concurrent I/O-bound tasks
    asyncmap(work_queue; ntasks=concurrency) do item
        result = generate_one(item, system_prompt, state, state_lock,
                              tok_input, tok_output, tok_cache_read, tok_cache_create)
        if result
            Threads.atomic_add!(success_count, 1)
        else
            Threads.atomic_add!(fail_count, 1)
        end

        # Progress report every 10 chapters
        done = success_count[] + fail_count[]
        total = length(work_queue)
        if done % 10 == 0
            pct = round(100 * done / total, digits=1)
            elapsed = round((time() - t_total) / 60, digits=1)
            rate = round(done / (time() - t_total) * 60, digits=1)
            println("   📊 Progress: $done/$total ($pct%) — $(elapsed)min elapsed — $(rate) ch/min")
        end
    end

    elapsed_total = round((time() - t_total) / 60, digits=1)

    println("\n" * "=" ^ 60)
    println("  GENERATION COMPLETE")
    println("  ✓ Success: $(success_count[])")
    println("  ✗ Failed:  $(fail_count[])")
    println("  ⏱ Time:    $(elapsed_total) minutes")
    println("  📁 Output:  $(OUTPUT_DIR)")
    println("=" ^ 60)

    if fail_count[] > 0
        println("\n⚠️  $(fail_count[]) chapters failed. Re-run with --retry-failed to retry them.")
    end

    # ─── Token usage & cost summary ───────────────────────────────────────────
    n_input   = tok_input[]
    n_output  = tok_output[]
    n_cr      = tok_cache_read[]
    n_cc      = tok_cache_create[]

    # Prices are per million tokens; divide raw counts accordingly
    estimated_cost = (n_input * PRICE_INPUT_PER_MTOK + n_output * PRICE_OUTPUT_PER_MTOK +
                      n_cr * PRICE_CACHE_READ_PER_MTOK + n_cc * PRICE_CACHE_CREATE_PER_MTOK) / 1_000_000

    truncated_count = length(state.truncated)

    format_with_commas(n) = replace(string(n), r"(?<=\d)(?=(\d{3})+$)" => ",")

    println("\n" * "═" ^ 45)
    println("  TOKEN USAGE SUMMARY")
    println("═" ^ 45)
    println("  Input tokens (uncached):     $(lpad(format_with_commas(n_input), 12))")
    println("  Input tokens (cache reads):  $(lpad(format_with_commas(n_cr), 12))")
    println("  Output tokens:               $(lpad(format_with_commas(n_output), 12))")
    println("  Cache creation tokens:       $(lpad(format_with_commas(n_cc), 12))")
    println("─" ^ 45)
    @printf("  Estimated cost:              %12s\n", "~\$$(round(estimated_cost, digits=2))")
    if truncated_count > 0
        println("  Chapters truncated:          $(lpad(string(truncated_count), 12))  ← WARN: hit max_tokens limit")
    else
        println("  Chapters truncated:          $(lpad("0", 12))")
    end
    println("═" ^ 45)
    if truncated_count > 0
        println("\n⚠️  Truncated chapters saved in state.json under \"truncated\" key.")
    end

    close(log_io)
end

main()
