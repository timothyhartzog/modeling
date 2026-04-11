# Enhanced Validation Pipeline for Modeling Textbooks — v2.0
# Adds: code parsability, cross-reference integrity, exercise tier distribution,
#        pitfalls sections, motivation block presence, worked example counts,
#        and computational laboratory detection.
#
# Usage:
#   julia --project=. src/validate_v2.jl
#   julia --project=. src/validate_v2.jl --textbook CORE-001
#   julia --project=. src/validate_v2.jl --export-failures failures.json
#   julia --project=. src/validate_v2.jl --fix-report report.md

using JSON3
using Dates

# ─────────────────────────── Configuration ───────────────────────────

const MANIFEST_FILES = ["manifests/part1.json", "manifests/part2.json"]
const OUTPUT_DIR = "output/markdown"
const MIN_WORD_COUNT = 2500
const MAX_WORD_COUNT = 12000
const MIN_WORKED_EXAMPLES = 2
const MIN_EXERCISES = 5
const MIN_JULIA_BLOCKS = 1
const MIN_PITFALLS = 1
const MIN_COMPUTATIONAL_LAB_LINES = 20

# ─────────────────────────── Check Definitions ───────────────────────────

"""
    CheckResult

Result of a single validation check on a chapter.
"""
struct CheckResult
    name::String
    passed::Bool
    severity::Symbol  # :critical, :warning, :info
    message::String
    details::Union{Nothing, Dict{String, Any}}
end

"""
    ChapterReport

Aggregate validation report for one chapter.
"""
struct ChapterReport
    textbook_id::String
    chapter_key::String
    filepath::String
    checks::Vector{CheckResult}
    word_count::Int
    passed::Bool
end

# ─────────────────────────── Utility Functions ───────────────────────────

"""
    extract_julia_blocks(content::String) -> Vector{String}

Extract all Julia code blocks from markdown content.
"""
function extract_julia_blocks(content::String)::Vector{String}
    blocks = String[]
    pattern = r"```julia\s*\n(.*?)```"s
    for m in eachmatch(pattern, content)
        push!(blocks, m.captures[1])
    end
    return blocks
end

"""
    count_words(content::String) -> Int

Count words in content, excluding code blocks and metadata.
"""
function count_words(content::String)::Int
    # Remove code blocks
    stripped = replace(content, r"```.*?```"s => "")
    # Remove markdown formatting
    stripped = replace(stripped, r"[#*>`_\[\]]" => " ")
    return length(split(strip(stripped)))
end

"""
    extract_exercises(content::String) -> NamedTuple

Parse exercises and classify by Bloom's tier.
"""
function extract_exercises(content::String)
    apply_count = length(collect(eachmatch(r"\(Apply\)"i, content)))
    analyze_count = length(collect(eachmatch(r"\(Analyze\)"i, content)))
    create_count = length(collect(eachmatch(r"\(Create\)"i, content)))

    # Also count generic "Exercise N.N" patterns without tier labels
    all_exercises = length(collect(eachmatch(r"\*\*Exercise\s+\d+\.\d+", content)))
    unlabeled = all_exercises - apply_count - analyze_count - create_count

    return (
        total=all_exercises,
        apply=apply_count,
        analyze=analyze_count,
        create=create_count,
        unlabeled=max(0, unlabeled)
    )
end

"""
    extract_cross_references(content::String) -> Vector{String}

Find all textbook cross-references (e.g., "CORE-001", "SCIML-003").
"""
function extract_cross_references(content::String)::Vector{String}
    refs = String[]
    for m in eachmatch(r"\b([A-Z]+-\d{3})\b", content)
        push!(refs, m.captures[1])
    end
    return unique(refs)
end

"""
    load_valid_textbook_ids() -> Set{String}

Load all valid textbook IDs from manifest files.
"""
function load_valid_textbook_ids()::Set{String}
    ids = Set{String}()
    for mf in MANIFEST_FILES
        isfile(mf) || continue
        data = JSON3.read(read(mf, String))
        if haskey(data, :textbooks)
            for tb in data.textbooks
                push!(ids, string(tb.id))
            end
        end
    end
    return ids
end

# ─────────────────────────── Individual Checks ───────────────────────────

function check_word_count(content::String)::CheckResult
    wc = count_words(content)
    if wc < MIN_WORD_COUNT
        return CheckResult("word_count", false, :critical,
            "Chapter has $wc words (minimum: $MIN_WORD_COUNT)", Dict("count" => wc))
    elseif wc > MAX_WORD_COUNT
        return CheckResult("word_count", false, :warning,
            "Chapter has $wc words (maximum recommended: $MAX_WORD_COUNT)", Dict("count" => wc))
    else
        return CheckResult("word_count", true, :info,
            "Word count: $wc", Dict("count" => wc))
    end
end

function check_motivation_section(content::String)::CheckResult
    has_motivation = occursin(r"^##\s+Motivation"mi, content) ||
                     occursin(r"^##\s+.*Motivation"mi, content)
    if !has_motivation
        return CheckResult("motivation_section", false, :warning,
            "Missing ## Motivation section at chapter opening", nothing)
    end
    return CheckResult("motivation_section", true, :info,
        "Motivation section present", nothing)
end

function check_prerequisites(content::String)::CheckResult
    has_prereq = occursin(r"Prerequisite"i, content)
    if !has_prereq
        return CheckResult("prerequisites", false, :info,
            "No prerequisites callout found", nothing)
    end
    return CheckResult("prerequisites", true, :info,
        "Prerequisites section present", nothing)
end

function check_julia_code_blocks(content::String)::CheckResult
    blocks = extract_julia_blocks(content)
    n = length(blocks)
    if n < MIN_JULIA_BLOCKS
        return CheckResult("julia_blocks", false, :critical,
            "Found $n Julia code blocks (minimum: $MIN_JULIA_BLOCKS)", Dict("count" => n))
    end
    return CheckResult("julia_blocks", true, :info,
        "Found $n Julia code blocks", Dict("count" => n))
end

function check_code_parsability(content::String)::CheckResult
    blocks = extract_julia_blocks(content)
    isempty(blocks) && return CheckResult("code_parsability", true, :info,
        "No code blocks to check", nothing)

    errors = String[]
    for (i, block) in enumerate(blocks)
        try
            Meta.parse("begin\n$block\nend")
        catch e
            push!(errors, "Block $i: $(sprint(showerror, e))")
        end
    end

    if !isempty(errors)
        return CheckResult("code_parsability", false, :critical,
            "$(length(errors))/$(length(blocks)) code blocks have parse errors",
            Dict("errors" => errors))
    end
    return CheckResult("code_parsability", true, :info,
        "All $(length(blocks)) code blocks parse successfully", nothing)
end

function check_code_docstrings(content::String)::CheckResult
    blocks = extract_julia_blocks(content)
    functions_without_docs = 0
    total_functions = 0

    for block in blocks
        funcs = collect(eachmatch(r"^function\s+\w+", block, overlap=false))
        total_functions += length(funcs)
        # Check if the block preceding the function has a docstring
        for _ in funcs
            if !occursin(r"\"\"\"\n.*?\n\"\"\"", block)
                functions_without_docs += 1
            end
        end
    end

    if total_functions > 0 && functions_without_docs > 0
        return CheckResult("code_docstrings", false, :warning,
            "$functions_without_docs/$total_functions functions lack docstrings",
            Dict("missing" => functions_without_docs, "total" => total_functions))
    end
    return CheckResult("code_docstrings", true, :info,
        "Docstring check passed ($total_functions functions)", nothing)
end

function check_worked_examples(content::String)::CheckResult
    examples = length(collect(eachmatch(r"\*\*Example\s+\d+\.\d+", content)))
    if examples < MIN_WORKED_EXAMPLES
        return CheckResult("worked_examples", false, :warning,
            "Found $examples worked examples (minimum: $MIN_WORKED_EXAMPLES)",
            Dict("count" => examples))
    end
    return CheckResult("worked_examples", true, :info,
        "Found $examples worked examples", Dict("count" => examples))
end

function check_exercises(content::String)::CheckResult
    ex = extract_exercises(content)
    if ex.total < MIN_EXERCISES
        return CheckResult("exercises", false, :critical,
            "Found $(ex.total) exercises (minimum: $MIN_EXERCISES)",
            Dict("total" => ex.total, "apply" => ex.apply,
                 "analyze" => ex.analyze, "create" => ex.create,
                 "unlabeled" => ex.unlabeled))
    end
    if ex.unlabeled > 0
        return CheckResult("exercises", false, :warning,
            "$(ex.unlabeled)/$(ex.total) exercises lack Bloom's tier labels",
            Dict("total" => ex.total, "unlabeled" => ex.unlabeled))
    end
    return CheckResult("exercises", true, :info,
        "$(ex.total) exercises (Apply:$(ex.apply) Analyze:$(ex.analyze) Create:$(ex.create))",
        Dict("total" => ex.total, "apply" => ex.apply,
             "analyze" => ex.analyze, "create" => ex.create))
end

function check_exercise_tier_distribution(content::String)::CheckResult
    ex = extract_exercises(content)
    ex.total == 0 && return CheckResult("exercise_tiers", false, :critical,
        "No exercises found", nothing)

    missing_tiers = String[]
    ex.apply == 0 && push!(missing_tiers, "Apply")
    ex.analyze == 0 && push!(missing_tiers, "Analyze")
    ex.create == 0 && push!(missing_tiers, "Create")

    if !isempty(missing_tiers)
        return CheckResult("exercise_tiers", false, :warning,
            "Missing exercise tiers: $(join(missing_tiers, ", "))",
            Dict("missing" => missing_tiers))
    end
    return CheckResult("exercise_tiers", true, :info,
        "All three Bloom's tiers represented", nothing)
end

function check_pitfalls(content::String)::CheckResult
    pitfall_sections = length(collect(eachmatch(r"Pitfalls?\s+(and|&)\s+Misconception"i, content)))
    if pitfall_sections < MIN_PITFALLS
        return CheckResult("pitfalls", false, :warning,
            "Found $pitfall_sections Pitfalls sections (minimum: $MIN_PITFALLS)",
            Dict("count" => pitfall_sections))
    end
    return CheckResult("pitfalls", true, :info,
        "Found $pitfall_sections Pitfalls sections", Dict("count" => pitfall_sections))
end

function check_computational_laboratory(content::String)::CheckResult
    has_lab = occursin(r"Computational\s+Laboratory"i, content)
    if !has_lab
        return CheckResult("computational_lab", false, :warning,
            "Missing Computational Laboratory section", nothing)
    end

    # Check if there's a substantial code block after the lab heading
    lab_match = match(r"Computational\s+Laboratory.*?```julia\s*\n(.*?)```"si, content)
    if lab_match !== nothing
        lines = count(c -> c == '\n', lab_match.captures[1])
        if lines < MIN_COMPUTATIONAL_LAB_LINES
            return CheckResult("computational_lab", false, :warning,
                "Computational Laboratory code is only $lines lines (minimum: $MIN_COMPUTATIONAL_LAB_LINES)",
                Dict("lines" => lines))
        end
    end
    return CheckResult("computational_lab", true, :info,
        "Computational Laboratory section present", nothing)
end

function check_cross_references(content::String, valid_ids::Set{String},
                                 own_textbook_id::String)::CheckResult
    refs = extract_cross_references(content)
    # Filter out the chapter's own textbook ID
    external_refs = filter(r -> r != own_textbook_id, refs)

    invalid = filter(r -> r ∉ valid_ids, external_refs)
    if !isempty(invalid)
        return CheckResult("cross_references", false, :warning,
            "Invalid textbook references: $(join(invalid, ", "))",
            Dict("invalid" => invalid))
    end
    return CheckResult("cross_references", true, :info,
        "$(length(external_refs)) valid cross-references found",
        Dict("refs" => external_refs))
end

function check_references_section(content::String)::CheckResult
    has_refs = occursin(r"^##\s+References"mi, content)
    if !has_refs
        return CheckResult("references_section", false, :warning,
            "Missing ## References section", nothing)
    end
    # Count citation entries
    citations = length(collect(eachmatch(r"\(\w+,\s*\d{4}\)", content)))
    return CheckResult("references_section", true, :info,
        "References section present with ~$citations inline citations",
        Dict("citations" => citations))
end

function check_connections_section(content::String)::CheckResult
    has_conn = occursin(r"^##\s+Connections"mi, content)
    if !has_conn
        return CheckResult("connections", false, :info,
            "Missing ## Connections section", nothing)
    end
    return CheckResult("connections", true, :info,
        "Connections section present", nothing)
end

function check_no_filler(content::String)::CheckResult
    filler_patterns = [
        r"In this section we will discuss"i,
        r"As we mentioned earlier"i,
        r"It is worth noting that"i,
        r"It should be noted that"i,
        r"In this chapter, we"i,
        r"Let us now turn to"i,
        r"We now proceed to"i,
    ]
    found = String[]
    for p in filler_patterns
        if occursin(p, content)
            push!(found, string(p.pattern))
        end
    end
    if !isempty(found)
        return CheckResult("no_filler", false, :warning,
            "Found $(length(found)) filler phrase patterns",
            Dict("patterns" => found))
    end
    return CheckResult("no_filler", true, :info,
        "No filler phrases detected", nothing)
end

function check_non_julia_code(content::String)::CheckResult
    # Check for Python, R, MATLAB code blocks
    violations = String[]
    occursin(r"```python"i, content) && push!(violations, "Python")
    occursin(r"```r\b"i, content) && push!(violations, "R")
    occursin(r"```matlab"i, content) && push!(violations, "MATLAB")
    occursin(r"```py\b"i, content) && push!(violations, "Python (```py)")

    if !isempty(violations)
        return CheckResult("julia_only", false, :critical,
            "Non-Julia code blocks found: $(join(violations, ", "))",
            Dict("languages" => violations))
    end
    return CheckResult("julia_only", true, :info,
        "No non-Julia code blocks detected", nothing)
end

# ─────────────────────────── Main Validation ───────────────────────────

"""
    validate_chapter(filepath, textbook_id, valid_ids) -> ChapterReport

Run all validation checks on a single chapter.
"""
function validate_chapter(filepath::String, textbook_id::String,
                          valid_ids::Set{String})::ChapterReport
    chapter_key = join([textbook_id, basename(filepath)], "/")

    if !isfile(filepath)
        return ChapterReport(textbook_id, chapter_key, filepath,
            [CheckResult("file_exists", false, :critical, "File not found", nothing)],
            0, false)
    end

    content = read(filepath, String)
    wc = count_words(content)

    checks = CheckResult[
        check_word_count(content),
        check_motivation_section(content),
        check_prerequisites(content),
        check_julia_code_blocks(content),
        check_code_parsability(content),
        check_code_docstrings(content),
        check_worked_examples(content),
        check_exercises(content),
        check_exercise_tier_distribution(content),
        check_pitfalls(content),
        check_computational_laboratory(content),
        check_cross_references(content, valid_ids, textbook_id),
        check_references_section(content),
        check_connections_section(content),
        check_no_filler(content),
        check_non_julia_code(content),
    ]

    critical_pass = all(c -> c.passed || c.severity != :critical, checks)
    return ChapterReport(textbook_id, chapter_key, filepath, checks, wc, critical_pass)
end

# ─────────────────────────── CLI and Reporting ───────────────────────────

function print_report(reports::Vector{ChapterReport})
    total = length(reports)
    passed = count(r -> r.passed, reports)
    failed = total - passed

    println("\n" * "="^72)
    println("  VALIDATION REPORT — $(Dates.now())")
    println("="^72)
    println("  Total chapters: $total")
    println("  Passed:         $passed ($(round(100*passed/max(total,1), digits=1))%)")
    println("  Failed:         $failed")
    println("="^72)

    # Aggregate check statistics
    check_names = unique(vcat([map(c -> c.name, r.checks) for r in reports]...))
    println("\n  Check-level summary:")
    println("  " * "-"^68)
    for cn in check_names
        relevant = [c for r in reports for c in r.checks if c.name == cn]
        pass_count = count(c -> c.passed, relevant)
        total_count = length(relevant)
        pct = round(100 * pass_count / max(total_count, 1), digits=1)
        status = pass_count == total_count ? "✓" : "✗"
        println("  $status  $cn: $pass_count/$total_count ($pct%)")
    end

    # Print failures
    if failed > 0
        println("\n  " * "="^68)
        println("  FAILURES:")
        println("  " * "-"^68)
        for r in filter(r -> !r.passed, reports)
            println("\n  ✗ $(r.chapter_key) ($(r.word_count) words)")
            for c in filter(c -> !c.passed, r.checks)
                sev = c.severity == :critical ? "CRITICAL" :
                      c.severity == :warning ? "WARNING" : "INFO"
                println("    [$sev] $(c.name): $(c.message)")
            end
        end
    end

    println("\n" * "="^72)
    return failed == 0 ? 0 : 1
end

function export_failures(reports::Vector{ChapterReport}, filepath::String)
    failures = [
        Dict(
            "chapter_key" => r.chapter_key,
            "textbook_id" => r.textbook_id,
            "failed_checks" => [
                Dict("name" => c.name, "severity" => string(c.severity), "message" => c.message)
                for c in r.checks if !c.passed
            ]
        )
        for r in reports if !r.passed
    ]
    open(filepath, "w") do io
        JSON3.pretty(io, failures)
    end
    println("Exported $(length(failures)) failures to $filepath")
end

function generate_fix_report(reports::Vector{ChapterReport}, filepath::String)
    open(filepath, "w") do io
        println(io, "# Validation Fix Report — $(Dates.today())\n")
        println(io, "Chapters requiring attention: $(count(r -> !r.passed, reports))\n")

        for r in filter(r -> !r.passed, reports)
            println(io, "## $(r.chapter_key)\n")
            println(io, "Word count: $(r.word_count)\n")
            for c in filter(c -> !c.passed, r.checks)
                println(io, "- **$(c.name)** [$(c.severity)]: $(c.message)")
            end
            println(io)
        end
    end
    println("Fix report written to $filepath")
end

function main()
    args = ARGS
    textbook_filter = nothing
    export_file = nothing
    fix_report_file = nothing

    i = 1
    while i <= length(args)
        if args[i] == "--textbook" && i < length(args)
            textbook_filter = args[i+1]
            i += 2
        elseif args[i] == "--export-failures" && i < length(args)
            export_file = args[i+1]
            i += 2
        elseif args[i] == "--fix-report" && i < length(args)
            fix_report_file = args[i+1]
            i += 2
        else
            i += 1
        end
    end

    valid_ids = load_valid_textbook_ids()
    println("Loaded $(length(valid_ids)) textbook IDs from manifests")

    # Discover chapters
    reports = ChapterReport[]
    if !isdir(OUTPUT_DIR)
        println("ERROR: Output directory '$OUTPUT_DIR' not found")
        exit(1)
    end

    for tb_dir in readdir(OUTPUT_DIR, join=true)
        isdir(tb_dir) || continue
        tb_id = basename(tb_dir)
        textbook_filter !== nothing && tb_id != textbook_filter && continue

        for chfile in sort(readdir(tb_dir, join=true))
            endswith(chfile, ".md") || continue
            push!(reports, validate_chapter(chfile, tb_id, valid_ids))
        end
    end

    if isempty(reports)
        println("No chapters found to validate.")
        exit(0)
    end

    exit_code = print_report(reports)

    export_file !== nothing && export_failures(reports, export_file)
    fix_report_file !== nothing && generate_fix_report(reports, fix_report_file)

    exit(exit_code)
end

main()
