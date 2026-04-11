#!/usr/bin/env julia
"""
    stats.jl — Read-only generation progress dashboard.

    Usage:
        julia --project=. src/stats.jl              # Full dashboard
        julia --project=. src/stats.jl --by-textbook # Per-textbook breakdown
        julia --project=. src/stats.jl --json        # Machine-readable JSON output
"""

include("prompt_builder.jl")

using .PromptBuilder
using JSON3, Dates

# ─────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────
const PROJECT_ROOT = dirname(@__DIR__)
const MANIFESTS = [
    joinpath(PROJECT_ROOT, "manifests", "part1.json"),
    joinpath(PROJECT_ROOT, "manifests", "part2.json")
]
const STATE_PATH = joinpath(PROJECT_ROOT, "state.json")

# ─────────────────────────────────────────────
# State Loading (read-only — no side effects)
# ─────────────────────────────────────────────
function load_state()
    if isfile(STATE_PATH)
        raw = JSON3.read(read(STATE_PATH, String))
        completed = Dict{String,String}(String(k) => String(v) for (k, v) in pairs(raw.completed))
        failed = haskey(raw, :failed) ?
            Dict{String,String}(String(k) => String(v) for (k, v) in pairs(raw.failed)) :
            Dict{String,String}()
        return completed, failed
    else
        return Dict{String,String}(), Dict{String,String}()
    end
end

# ─────────────────────────────────────────────
# Track Normalization
# ─────────────────────────────────────────────
function normalize_track(track::String)::String
    t = lowercase(track)
    if occursin("core mathematics", t)
        return "Core Mathematics"
    elseif occursin("biostatistics", t)
        return "Biostatistics"
    elseif occursin("geospatial", t)
        return "Geospatial"
    elseif occursin("agent-based", t)
        return "Agent-Based"
    elseif occursin("scientific ml", t) || occursin("scientific machine learning", t)
        return "Scientific ML"
    elseif occursin("population dynamics", t)
        return "Population Dynamics"
    elseif occursin("physical systems", t)
        return "Physical Systems"
    elseif occursin("cross-cutting", t)
        return "Cross-Cutting"
    else
        return track
    end
end

# ─────────────────────────────────────────────
# Progress Bar
# ─────────────────────────────────────────────
function progress_bar(n_completed::Int, total::Int; width::Int = 22)::String
    total == 0 && return "░" ^ width
    filled = clamp(round(Int, width * n_completed / total), 0, width)
    return "█" ^ filled * "░" ^ (width - filled)
end

# ─────────────────────────────────────────────
# Statistics Structs
# ─────────────────────────────────────────────
struct ChapterInfo
    key::String
    title::String
    status::String  # "completed" | "failed" | "pending"
end

mutable struct TextbookStats
    title::String
    track::String
    chapters::Vector{ChapterInfo}
    n_completed::Int
    n_failed::Int
    TextbookStats(title, track) = new(title, track, ChapterInfo[], 0, 0)
end

mutable struct TrackStats
    n_total::Int
    n_completed::Int
    n_failed::Int
    TrackStats() = new(0, 0, 0)
end

# ─────────────────────────────────────────────
# Build Statistics
# ─────────────────────────────────────────────
function build_stats(all_items::Vector{WorkItem},
                     completed::Dict{String,String},
                     failed::Dict{String,String})
    track_stats    = Dict{String,TrackStats}()
    textbook_stats = Dict{String,TextbookStats}()

    for item in all_items
        key   = PromptBuilder.work_item_key(item)
        track = normalize_track(item.track)
        tid   = item.textbook_id

        status = if haskey(completed, key)
            "completed"
        elseif haskey(failed, key)
            "failed"
        else
            "pending"
        end

        # Accumulate track stats
        ts = get!(track_stats, track, TrackStats())
        ts.n_total += 1
        status == "completed" && (ts.n_completed += 1)
        status == "failed"    && (ts.n_failed    += 1)

        # Accumulate textbook stats
        tbs = get!(textbook_stats, tid, TextbookStats(item.textbook_title, track))
        push!(tbs.chapters, ChapterInfo(key, item.chapter_title, status))
        status == "completed" && (tbs.n_completed += 1)
        status == "failed"    && (tbs.n_failed    += 1)
    end

    return track_stats, textbook_stats
end

# ─────────────────────────────────────────────
# CLI Argument Parsing
# ─────────────────────────────────────────────
function parse_args()
    by_textbook = false
    as_json     = false
    for arg in ARGS
        if arg == "--by-textbook"
            by_textbook = true
        elseif arg == "--json"
            as_json = true
        else
            println(stderr, "Warning: unknown argument: $arg")
        end
    end
    return by_textbook, as_json
end

# ─────────────────────────────────────────────
# Dashboard Output
# ─────────────────────────────────────────────
const TRACK_ORDER = [
    "Core Mathematics", "Biostatistics", "Geospatial", "Agent-Based",
    "Scientific ML", "Population Dynamics", "Physical Systems", "Cross-Cutting"
]

function print_dashboard(total::Int, n_completed::Int, n_failed::Int, n_pending::Int,
                         track_stats::Dict{String,TrackStats},
                         textbook_stats::Dict{String,TextbookStats},
                         failed::Dict{String,String},
                         recent::Vector{Pair{String,String}},
                         by_textbook::Bool)
    sep      = "═" ^ 63
    now_str  = Dates.format(Dates.now(), "yyyy-mm-dd HH:MM")
    pct      = total > 0 ? round(100 * n_completed / total, digits = 1) : 0.0

    println(sep)
    println("GENERATION STATUS REPORT — $now_str")
    println(sep)
    println("OVERALL PROGRESS: $n_completed / $total chapters ($pct%)")
    println("  ✓ Completed:  $(lpad(n_completed, 4))")
    println("  ✗ Failed:     $(lpad(n_failed,    4))")
    println("  ○ Pending:    $(lpad(n_pending,   4))")
    println()

    println("BY TRACK:")
    ordered = vcat(
        [t for t in TRACK_ORDER if haskey(track_stats, t)],
        sort([t for t in keys(track_stats) if t ∉ TRACK_ORDER])
    )
    name_width = max(20, maximum(length(t) for t in keys(track_stats); init = 0))

    for track in ordered
        ts    = track_stats[track]
        pct_t = ts.n_total > 0 ? round(100 * ts.n_completed / ts.n_total, digits = 1) : 0.0
        bar   = progress_bar(ts.n_completed, ts.n_total)
        println("  $(rpad(track, name_width))  $(lpad(ts.n_completed, 4)) / $(lpad(ts.n_total, 4))  ($(lpad(string(pct_t), 5))%)  $bar")
    end
    println()

    if !isempty(failed)
        println("FAILED CHAPTERS ($(length(failed))):")
        for key in sort(collect(keys(failed)))
            msg       = failed[key]
            short_msg = length(msg) > 60 ? msg[1:57] * "..." : msg
            println("  $key — $short_msg")
        end
        println()
    end

    if !isempty(recent)
        println("RECENTLY COMPLETED (last $(length(recent))):")
        for (key, ts) in recent
            println("  $(rpad(key, 18))  $ts")
        end
        println()
    end

    if by_textbook
        println("BY TEXTBOOK:")
        println()
        for tid in sort(collect(keys(textbook_stats)))
            tbs      = textbook_stats[tid]
            n_total  = length(tbs.chapters)
            pct_t    = n_total > 0 ? round(100 * tbs.n_completed / n_total, digits = 1) : 0.0
            bar      = progress_bar(tbs.n_completed, n_total)
            println("  [$tid] $(tbs.title)")
            println("  Track: $(tbs.track)  |  $(tbs.n_completed)/$(n_total) ($pct_t%)  $bar")
            for ch in tbs.chapters
                icon = ch.status == "completed" ? "✓" : ch.status == "failed" ? "✗" : "○"
                println("    $icon  $(rpad(ch.key, 16))  $(ch.title)")
            end
            println()
        end
    end

    println(sep)
end

# ─────────────────────────────────────────────
# JSON Output
# ─────────────────────────────────────────────
function print_json(total::Int, n_completed::Int, n_failed::Int, n_pending::Int,
                    track_stats::Dict{String,TrackStats},
                    textbook_stats::Dict{String,TextbookStats},
                    failed::Dict{String,String},
                    recent::Vector{Pair{String,String}},
                    completed::Dict{String,String})
    data = Dict(
        "generated_at" => string(Dates.now()),
        "overall" => Dict(
            "total"        => total,
            "completed"    => n_completed,
            "failed"       => n_failed,
            "pending"      => n_pending,
            "pct_complete" => total > 0 ? round(100 * n_completed / total, digits = 1) : 0.0
        ),
        "by_track" => Dict(
            track => Dict(
                "total"        => ts.n_total,
                "completed"    => ts.n_completed,
                "failed"       => ts.n_failed,
                "pending"      => ts.n_total - ts.n_completed - ts.n_failed,
                "pct_complete" => ts.n_total > 0 ?
                    round(100 * ts.n_completed / ts.n_total, digits = 1) : 0.0
            )
            for (track, ts) in track_stats
        ),
        "by_textbook" => Dict(
            tid => Dict(
                "title"        => tbs.title,
                "track"        => tbs.track,
                "total"        => length(tbs.chapters),
                "completed"    => tbs.n_completed,
                "failed"       => tbs.n_failed,
                "pending"      => length(tbs.chapters) - tbs.n_completed - tbs.n_failed,
                "pct_complete" => length(tbs.chapters) > 0 ?
                    round(100 * tbs.n_completed / length(tbs.chapters), digits = 1) : 0.0,
                "chapters"     => [
                    Dict("key" => ch.key, "title" => ch.title, "status" => ch.status)
                    for ch in tbs.chapters
                ]
            )
            for (tid, tbs) in textbook_stats
        ),
        "failed_chapters"      => failed,
        "recently_completed"   => [
            Dict("key" => k, "completed_at" => v) for (k, v) in recent
        ],
        "completed_chapters"   => completed
    )
    println(JSON3.write(data))
end

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
function main()
    by_textbook, as_json = parse_args()

    all_items          = load_manifests(MANIFESTS)
    completed, failed  = load_state()

    total       = length(all_items)
    n_completed = count(item -> haskey(completed, PromptBuilder.work_item_key(item)), all_items)
    n_failed    = count(item -> haskey(failed,    PromptBuilder.work_item_key(item)), all_items)
    n_pending   = total - n_completed - n_failed

    track_stats, textbook_stats = build_stats(all_items, completed, failed)

    # Recently completed: sort by timestamp descending, take up to 10
    recent = sort(collect(completed), by = x -> x[2], rev = true)[1:min(10, length(completed))]

    if as_json
        print_json(total, n_completed, n_failed, n_pending,
                   track_stats, textbook_stats, failed, recent, completed)
    else
        print_dashboard(total, n_completed, n_failed, n_pending,
                        track_stats, textbook_stats, failed, recent, by_textbook)
    end
end

main()
