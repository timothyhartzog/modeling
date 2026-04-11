#!/usr/bin/env julia
"""
    validate.jl — Post-generation chapter quality checker.

    Reads every generated .md file and validates it against the content
    standards defined in system_prompt.md and CLAUDE.md.

    Usage:
        julia --project=. src/validate.jl                              # Validate all chapters
        julia --project=. src/validate.jl --textbook CORE-001          # Validate one textbook
        julia --project=. src/validate.jl --export-failures out.json   # Export failed keys to JSON
"""

using JSON3, Dates, Printf

const PROJECT_ROOT = dirname(@__DIR__)
const MANIFESTS = [
    joinpath(PROJECT_ROOT, "manifests", "part1.json"),
    joinpath(PROJECT_ROOT, "manifests", "part2.json")
]
const OUTPUT_DIR = joinpath(PROJECT_ROOT, "output", "markdown")

# ─────────────────────────────────────────────
# Thresholds
# ─────────────────────────────────────────────
const WORD_COUNT_MIN        = 3_000   # target floor
const WORD_COUNT_MAX        = 8_000   # target ceiling
const WORD_COUNT_WARN_LOW   = 2_500   # warning when below this (critical if also below WARN_LOW)
const WORD_COUNT_WARN_HIGH  = 9_000   # warning/critical boundary on the upper end

# ─────────────────────────────────────────────
# Result types
# ─────────────────────────────────────────────
struct CheckResult
    passed::Bool
    critical::Bool      # true → failure; false → warning only
    message::String
end

struct ChapterResult
    key::String          # e.g. "CORE-001/ch04"
    checks::Vector{CheckResult}
end

passed(r::ChapterResult) = all(c.passed for c in r.checks)
failed(r::ChapterResult) = any(!c.passed && c.critical  for c in r.checks)
warned(r::ChapterResult) = !failed(r) && any(!c.passed && !c.critical for c in r.checks)

const REPORT_LINE_WIDTH = 43

# ─────────────────────────────────────────────
# Individual checks
# ─────────────────────────────────────────────

"""Count words (whitespace-separated tokens) in a string."""
function word_count(text::String)::Int
    return length(split(text; keepempty=false))
end

"""Check word count is within the target range."""
function check_word_count(text::String)::CheckResult
    wc = word_count(text)
    if wc < WORD_COUNT_WARN_LOW
        return CheckResult(false, true,  "word count $wc (min $WORD_COUNT_MIN)")
    elseif wc > WORD_COUNT_WARN_HIGH
        return CheckResult(false, true,  "word count $wc (max $WORD_COUNT_MAX)")
    elseif wc < WORD_COUNT_MIN
        return CheckResult(false, false, "word count $wc (below target $WORD_COUNT_MIN)")
    elseif wc > WORD_COUNT_MAX
        return CheckResult(false, false, "word count $wc (above target $WORD_COUNT_MAX)")
    else
        return CheckResult(true,  true,  "word count $wc ✓")
    end
end

"""Check that at least one ```julia code block is present."""
function check_julia_code(text::String)::CheckResult
    if occursin(r"```julia"i, text)
        return CheckResult(true,  true, "Julia code block found ✓")
    else
        return CheckResult(false, true, "no Julia code block found")
    end
end

"""Check that an Exercises heading exists."""
function check_exercises(text::String)::CheckResult
    if occursin(r"^#{1,2} Exercises"m, text)
        return CheckResult(true,  true, "Exercises section found ✓")
    else
        return CheckResult(false, true, "no Exercises section found")
    end
end

"""Check that a References heading exists."""
function check_references(text::String)::CheckResult
    if occursin(r"^#{1,2} References"m, text)
        return CheckResult(true,  true, "References section found ✓")
    else
        return CheckResult(false, true, "no References section found")
    end
end

"""Check that the first non-blank line is a '# Chapter N:' heading."""
function check_chapter_heading(text::String)::CheckResult
    for line in split(text, '\n')
        stripped = strip(line)
        if !isempty(stripped)
            if occursin(r"^# Chapter \d+:"i, stripped)
                return CheckResult(true,  true, "chapter heading found ✓")
            else
                return CheckResult(false, true, "first non-blank line is not '# Chapter N:' — got: $(first(stripped, 80))")
            end
        end
    end
    return CheckResult(false, true, "file appears empty")
end

"""Check that at least one Definition or Theorem blockquote is present."""
function check_definitions(text::String)::CheckResult
    if occursin(r"^> \*\*(Definition|Theorem)"m, text)
        return CheckResult(true,  true, "Definition/Theorem block found ✓")
    else
        return CheckResult(false, true, "no Definition or Theorem blockquote found")
    end
end

"""Run all checks on a chapter file and return a ChapterResult."""
function validate_chapter(key::String, filepath::String)::ChapterResult
    text = read(filepath, String)
    checks = CheckResult[
        check_chapter_heading(text),
        check_word_count(text),
        check_julia_code(text),
        check_exercises(text),
        check_references(text),
        check_definitions(text),
    ]
    return ChapterResult(key, checks)
end

# ─────────────────────────────────────────────
# Manifest / file discovery
# ─────────────────────────────────────────────

function load_textbook_ids()::Vector{String}
    ids = String[]
    for path in MANIFESTS
        isfile(path) || continue
        raw = JSON3.read(read(path, String))
        for tb in raw.textbooks
            push!(ids, String(tb.id))
        end
    end
    return ids
end

"""Return all chapter keys that have been generated (file exists on disk).
   Optionally restrict to a single textbook_id."""
function discover_chapters(; textbook_filter::Union{Nothing,String}=nothing)::Vector{Tuple{String,String}}
    chapters = Tuple{String,String}[]

    if !isdir(OUTPUT_DIR)
        return chapters
    end

    all_ids = load_textbook_ids()
    ids = isnothing(textbook_filter) ? all_ids : filter(id -> id == textbook_filter, all_ids)

    for tb_id in ids
        tb_dir = joinpath(OUTPUT_DIR, tb_id)
        isdir(tb_dir) || continue
        for fname in sort(readdir(tb_dir))
            if endswith(fname, ".md")
                chnum = replace(fname, ".md" => "")  # e.g. "ch01"
                key      = "$tb_id/$chnum"
                filepath = joinpath(tb_dir, fname)
                push!(chapters, (key, filepath))
            end
        end
    end
    return chapters
end

# ─────────────────────────────────────────────
# Reporting
# ─────────────────────────────────────────────

const LINE = '═' ^ REPORT_LINE_WIDTH

function print_report(results::Vector{ChapterResult}, date_str::String)
    total   = length(results)
    nfailed = count(failed, results)
    nwarned = count(warned, results)
    npassed = count(passed, results)

    pct(n) = total > 0 ? @sprintf("%.1f%%", 100n / total) : "—"

    println("\nValidation Report — $date_str")
    println(LINE)
    println("Total chapters checked:  $(lpad(total,   5))")
    println("✓ Passed all checks:     $(lpad(npassed, 5))  ($(pct(npassed)))")
    println("⚠ Warnings (minor):      $(lpad(nwarned, 5))  ($(pct(nwarned)))")
    println("✗ Failed (critical):     $(lpad(nfailed, 5))  ($(pct(nfailed)))")

    # Failed chapters
    failed_results = filter(failed, results)
    if !isempty(failed_results)
        println("\nFAILED CHAPTERS:")
        for r in failed_results
            for c in r.checks
                if !c.passed && c.critical
                    println("  $(r.key) — $(c.message)")
                end
            end
        end
    end

    # Warnings
    warned_results = filter(warned, results)
    if !isempty(warned_results)
        println("\nWARNINGS:")
        for r in warned_results
            for c in r.checks
                if !c.passed && !c.critical
                    println("  $(r.key) — $(c.message)")
                end
            end
        end
    end

    println(LINE)
end

# ─────────────────────────────────────────────
# Export failures
# ─────────────────────────────────────────────

"""Write failed chapter keys as a JSON object compatible with state.json format.
   Keys map to the string "validation_failure" so the generate orchestrator can
   treat them as failed chapters and re-queue them."""
function export_failures(results::Vector{ChapterResult}, path::String)
    failed_keys = Dict{String,String}(
        r.key => "validation_failure" for r in results if failed(r)
    )
    json = JSON3.write(Dict(
        "completed"   => Dict{String,String}(),
        "failed"      => failed_keys,
        "started_at"  => string(Dates.now()),
        "last_updated"=> string(Dates.now()),
    ))
    write(path, json)
    println("  Exported $(length(failed_keys)) failed chapter(s) → $path")
end

# ─────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────

function parse_args()
    args = Dict{Symbol,Any}(
        :textbook        => nothing,
        :export_failures => nothing,
    )
    i = 1
    while i <= length(ARGS)
        arg = ARGS[i]
        if arg == "--textbook" && i < length(ARGS)
            args[:textbook] = ARGS[i+1]; i += 2
        elseif arg == "--export-failures" && i < length(ARGS)
            args[:export_failures] = ARGS[i+1]; i += 2
        else
            @warn "Unknown argument: $arg"
            i += 1
        end
    end
    return args
end

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

function main()
    args = parse_args()

    println("=" ^ 60)
    println("  CHAPTER QUALITY VALIDATOR")
    println("  $(Dates.now())")
    println("=" ^ 60)

    chapters = discover_chapters(; textbook_filter=args[:textbook])

    if isempty(chapters)
        filter_note = isnothing(args[:textbook]) ? "" : " for textbook '$(args[:textbook])'"
        println("\n⚠  No generated chapters found$filter_note in $(OUTPUT_DIR)")
        println("   Run the generation pipeline first.")
        exit(0)
    end

    println("\n🔍 Validating $(length(chapters)) chapter(s)…\n")

    results = ChapterResult[]
    for (key, filepath) in chapters
        result = validate_chapter(key, filepath)
        push!(results, result)
        status = failed(result) ? "✗" : (warned(result) ? "⚠" : "✓")
        println("  $status  $key")
    end

    print_report(results, string(Dates.today()))

    if !isnothing(args[:export_failures])
        export_failures(results, args[:export_failures])
    end

    # Non-zero exit code when any chapter fails a critical check (CI integration)
    any_failed = any(failed, results)
    exit(any_failed ? 1 : 0)
end

main()
