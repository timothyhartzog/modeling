#!/usr/bin/env julia
"""
    generate.jl — Main orchestrator for parallel textbook chapter generation.

    Usage:
        julia --project=. src/generate.jl                                   # Full run, concurrency=5
        julia --project=. src/generate.jl --concurrency 10                  # Full run, concurrency=10
        julia --project=. src/generate.jl --calibrate                       # Generate 3 test chapters only
        julia --project=. src/generate.jl --resume                          # Resume from last state
        julia --project=. src/generate.jl --textbook CORE-001               # Generate one textbook only
        julia --project=. src/generate.jl --dry-run                         # Show work queue, don't generate
        julia --project=. src/generate.jl --chapter CORE-001/ch03           # Regenerate a single chapter
        julia --project=. src/generate.jl --chapter CORE-001/ch03,BIO-002/ch07  # Multiple specific chapters
        julia --project=. src/generate.jl --textbook CORE-001 --force       # Regenerate all chapters, ignoring state
"""

if !isdefined(Main, :APIClient)
    include("api_client.jl")
end
if !isdefined(Main, :PromptBuilder)
    include("prompt_builder.jl")
end

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

function load_state(path::String=STATE_PATH)::GenerationState
    if isfile(path)
        raw = JSON3.read(read(path, String))
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

function save_state(state::GenerationState, path::String=STATE_PATH)
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
    tmp = path * ".tmp"
    write(tmp, json)
    mv(tmp, path; force=true)
end

# ─────────────────────────────────────────────
# File I/O
# ─────────────────────────────────────────────
function save_chapter(key::String, content::String, output_dir::String=OUTPUT_DIR)
    parts = split(key, "/")
    textbook_dir = joinpath(output_dir, parts[1])
    mkpath(textbook_dir)
    filepath = joinpath(textbook_dir, "$(parts[2]).md")
    write(filepath, content)
    return filepath
end

# ─────────────────────────────────────────────
# Parse CLI Args
# ─────────────────────────────────────────────
function parse_args(args_vec::Vector{String}=ARGS)
    args = Dict{Symbol,Any}(
        :concurrency => 5,
        :calibrate => false,
        :resume => false,
        :dry_run => false,
        :textbook => nothing,
        :retry_failed => false,
        :chapters => nothing,
        :force => false,
    )

    i = 1
    while i <= length(args_vec)
        arg = args_vec[i]
        if arg == "--concurrency" && i < length(args_vec)
            requested = parse(Int, args_vec[i+1])
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
        elseif arg == "--textbook" && i < length(args_vec)
            args[:textbook] = args_vec[i+1]
            i += 2
        elseif arg == "--chapter" && i < length(args_vec)
            args[:chapters] = split(args_vec[i+1], ",")
            i += 2
        elseif arg == "--force"
            args[:force] = true
            i += 1
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
                      tok_cache_read::Threads.Atomic{Int}, tok_cache_create::Threads.Atomic{Int};
                      calibrate::Bool=false)
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
        if calibrate
            println("   ✓ $(key) — $(word_count) words in $(elapsed)s")
        end
        return true

    catch e
        elapsed = round(time() - t_start, digits=1)
        err_msg = sprint(showerror, e)

        lock(state_lock) do
            state.failed[key] = err_msg
            save_state(state)
        end

        @error "✗ $(key) — FAILED in $(elapsed)s: $(err_msg)"
        if calibrate
            println("   ✗ $(key) — FAILED in $(elapsed)s: $(err_msg)")
        end
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
    work_queue = if !isnothing(args[:chapters])
        target_keys = Set(args[:chapters])
        all_keys = Set(PromptBuilder.work_item_key(item) for item in all_items)
        invalid_keys = setdiff(target_keys, all_keys)
        if !isempty(invalid_keys)
            println("\n❌ ERROR: The following chapter keys were not found in any manifest:")
            for k in sort(collect(invalid_keys))
                println("   $k")
            end
            println("   Keys must be in the format TEXTBOOK-ID/chNN (e.g. CORE-001/ch03)")
            close(log_io)
            exit(1)
        end
        # Always regenerate targeted chapters — strip from completed/failed first
        lock(state_lock) do
            for key in target_keys
                delete!(state.completed, key)
                delete!(state.failed, key)
            end
        end
        println("\n🎯 Chapter mode — targeting $(length(target_keys)) chapter(s): $(join(sort(collect(target_keys)), ", "))")
        if args[:force]
            println("   ℹ️  --force has no additional effect in --chapter mode (chapters are always regenerated)")
        end
        filter(item -> PromptBuilder.work_item_key(item) in target_keys, all_items)
    elseif args[:calibrate]
        println("\n🔬 CALIBRATION MODE — generating 3 test chapters")
        filter(item -> PromptBuilder.work_item_key(item) in CALIBRATION_KEYS, all_items)
    elseif !isnothing(args[:textbook])
        tb = args[:textbook]
        println("\n📖 Single textbook mode: $tb")
        filter(item -> item.textbook_id == tb, all_items)
    else
        all_items
    end

    # Filter completed (unless retry-failed, --chapter, or --force)
    if !args[:force] && isnothing(args[:chapters])
        if args[:resume] || !args[:retry_failed]
            work_queue = filter(item -> !(PromptBuilder.work_item_key(item) in keys(state.completed)), work_queue)
        end
        if args[:retry_failed]
            # Only retry previously failed items
            work_queue = filter(item -> PromptBuilder.work_item_key(item) in keys(state.failed), work_queue)
        end
    elseif args[:force] && isnothing(args[:chapters])
        println("   ⚡ --force: bypassing completed-chapter filter")
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
                              tok_input, tok_output, tok_cache_read, tok_cache_create;
                              calibrate=args[:calibrate])
        if result
            Threads.atomic_add!(success_count, 1)
        else
            Threads.atomic_add!(fail_count, 1)
        end

        # Progress report at 25%, 50%, 75%, and 100% milestones (scales to any queue size)
        done = success_count[] + fail_count[]
        total = length(work_queue)
        prev_pct = floor(Int, 100 * (done - 1) / total / 25)
        curr_pct = floor(Int, 100 * done / total / 25)
        if curr_pct > prev_pct || done == total
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

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
