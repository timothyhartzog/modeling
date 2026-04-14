# Question Bank Generator — v1.0
# Parses generated chapters and extracts:
#   1. Definitions → "Which of these is NOT a property of X?"
#   2. Theorems → "What does Theorem X require?" / "When does X fail?"
#   3. Exercises → parsed with tier labels
#   4. Pitfalls → "Which statement about X is FALSE?"
#
# Output: question-bank.json for the React quiz engine
#
# Usage:
#   julia --project=. src/generate_question_bank.jl
#   julia --project=. src/generate_question_bank.jl --output output/question-bank.json

using JSON3
using Dates

const INPUT_DIR = "output/markdown"

# ─────────────────────────── Track Inference ───────────────────────────

const TRACK_MAP = Dict(
    "CORE" => "Core Mathematics",
    "BIO"  => "Biostatistics",
    "GEO"  => "Geospatial",
    "ABM"  => "Agent-Based",
    "SCIML"=> "Scientific ML",
    "POP"  => "Population Dynamics",
    "PHYS" => "Physical Systems",
    "CROSS"=> "Cross-Cutting",
    "UQ"   => "Cross-Cutting",
)

function infer_track(textbook_id::String)::String
    prefix = match(r"^([A-Z]+)-", textbook_id)
    prefix === nothing && return "XCUT"
    return get(TRACK_MAP, prefix.captures[1], "XCUT")
end

function infer_track_key(textbook_id::String)::String
    prefix = match(r"^([A-Z]+)-", textbook_id)
    prefix === nothing && return "XCUT"
    key = prefix.captures[1]
    return key in ("CROSS", "UQ") ? "XCUT" : key
end

# ─────────────────────────── Extraction Functions ───────────────────────────

struct RawQuestion
    textbook::String
    chapter::Int
    track::String
    track_key::String
    type::String           # "definition", "theorem", "exercise", "pitfall"
    difficulty::String     # "apply", "analyze", "create"
    source_label::String   # e.g., "Definition 1.3 (Metric Space)"
    source_text::String    # the full text of the definition/theorem
end

"""
    extract_definitions(content, textbook_id, chapter_num) -> Vector{RawQuestion}

Extract definitions from a chapter and create quiz-ready questions.
"""
function extract_definitions(content::String, textbook_id::String, chapter_num::Int)
    questions = RawQuestion[]
    track = infer_track(textbook_id)
    track_key = infer_track_key(textbook_id)

    for m in eachmatch(r"\*\*Definition\s+(\d+\.\d+)\s*\(([^)]+)\)\.\*\*\s*(.*?)(?=\n\n|\n>|\z)"s, content)
        num = m.captures[1]
        name = strip(m.captures[2])
        body = strip(m.captures[3])

        push!(questions, RawQuestion(
            textbook_id, chapter_num, track, track_key,
            "definition", "apply",
            "Definition $num ($name)",
            body
        ))
    end
    return questions
end

"""
    extract_theorems(content, textbook_id, chapter_num) -> Vector{RawQuestion}

Extract theorems and create quiz-ready questions about assumptions/conclusions.
"""
function extract_theorems(content::String, textbook_id::String, chapter_num::Int)
    questions = RawQuestion[]
    track = infer_track(textbook_id)
    track_key = infer_track_key(textbook_id)

    for m in eachmatch(r"\*\*Theorem\s+(\d+\.\d+)\s*\(([^)]+)\)\.\*\*\s*(.*?)(?=\n\n|\n>|\*Proof|\z)"s, content)
        num = m.captures[1]
        name = strip(m.captures[2])
        body = strip(m.captures[3])

        push!(questions, RawQuestion(
            textbook_id, chapter_num, track, track_key,
            "theorem", "analyze",
            "Theorem $num ($name)",
            body
        ))
    end
    return questions
end

"""
    extract_exercises(content, textbook_id, chapter_num) -> Vector{RawQuestion}

Extract labeled exercises with their Bloom's tier.
"""
function extract_exercises(content::String, textbook_id::String, chapter_num::Int)
    questions = RawQuestion[]
    track = infer_track(textbook_id)
    track_key = infer_track_key(textbook_id)

    for m in eachmatch(r"\*\*Exercise\s+(\d+\.\d+)\s*\((\w+)\)\.\*\*\s*(.*?)(?=\n\n\*\*Exercise|\n\n##|\z)"s, content)
        num = m.captures[1]
        tier = lowercase(strip(m.captures[2]))
        body = strip(m.captures[3])

        push!(questions, RawQuestion(
            textbook_id, chapter_num, track, track_key,
            "exercise", tier,
            "Exercise $num",
            body
        ))
    end
    return questions
end

"""
    extract_pitfalls(content, textbook_id, chapter_num) -> Vector{RawQuestion}

Extract pitfall items and convert to "which is FALSE" style questions.
"""
function extract_pitfalls(content::String, textbook_id::String, chapter_num::Int)
    questions = RawQuestion[]
    track = infer_track(textbook_id)
    track_key = infer_track_key(textbook_id)

    # Match individual pitfall items
    for m in eachmatch(r"\*\*\"([^\"]+)\"\*\*\s*(.*?)(?=\n>\s*\d+\.|\n\n|\z)"s, content)
        misconception = strip(m.captures[1])
        explanation = strip(m.captures[2])

        push!(questions, RawQuestion(
            textbook_id, chapter_num, track, track_key,
            "pitfall", "analyze",
            "Pitfall: $misconception",
            explanation
        ))
    end

    # Also match numbered pitfall patterns
    for m in eachmatch(r"\*\*Confusing\s+([^.]+)\.\*\*\s*(.*?)(?=\n>\s*\d+\.|\n\n|\z)"s, content)
        topic = strip(m.captures[1])
        explanation = strip(m.captures[2])

        push!(questions, RawQuestion(
            textbook_id, chapter_num, track, track_key,
            "pitfall", "analyze",
            "Pitfall: Confusing $topic",
            explanation
        ))
    end
    return questions
end

# ─────────────────────────── Question Formatting ───────────────────────────

"""
    format_question(raw::RawQuestion, id::Int) -> Dict

Convert a RawQuestion into the JSON format consumed by the quiz engine.
Currently outputs as free-response; in production, an LLM call would generate
multiple-choice distractors.
"""
function format_question(raw::RawQuestion, id::Int)::Dict
    # Determine question text based on type
    question_text = if raw.type == "definition"
        "Regarding $(raw.source_label): $(first_sentence(raw.source_text)) Which of the following is a key property or requirement of this definition?"
    elseif raw.type == "theorem"
        "$(raw.source_label) states a result about a mathematical object. What assumption or condition is essential for this theorem to hold?"
    elseif raw.type == "pitfall"
        "$(raw.source_label) — Why is this a common misconception?"
    else
        raw.source_text
    end

    return Dict(
        "id" => id,
        "track" => raw.track_key,
        "track_label" => raw.track,
        "textbook" => raw.textbook,
        "chapter" => raw.chapter,
        "type" => "free_response",
        "difficulty" => raw.difficulty,
        "source_type" => raw.type,
        "source_label" => raw.source_label,
        "question" => question_text,
        "reference_answer" => raw.source_text,
    )
end

function first_sentence(text::String)::String
    m = match(r"^[^.!?]+[.!?]", text)
    return m !== nothing ? m.match : (length(text) > 120 ? text[1:120] * "..." : text)
end

# ─────────────────────────── Main ───────────────────────────

function main()
    output_file = "output/question-bank.json"
    for (i, arg) in enumerate(ARGS)
        if arg == "--output" && i < length(ARGS)
            output_file = ARGS[i+1]
        end
    end

    all_questions = RawQuestion[]

    if !isdir(INPUT_DIR)
        println("WARNING: $INPUT_DIR not found. Creating empty question bank.")
        mkpath(dirname(output_file))
        open(output_file, "w") do io
            JSON3.pretty(io, Dict("generated" => string(Dates.now()),
                                   "questions" => [], "stats" => Dict()))
        end
        return
    end

    for tb_dir in sort(readdir(INPUT_DIR, join=true))
        isdir(tb_dir) || continue
        tb_id = basename(tb_dir)

        chapters = sort(filter(f -> endswith(f, ".md"), readdir(tb_dir)))
        for (ch_num, chfile) in enumerate(chapters)
            content = read(joinpath(tb_dir, chfile), String)
            append!(all_questions, extract_definitions(content, tb_id, ch_num))
            append!(all_questions, extract_theorems(content, tb_id, ch_num))
            append!(all_questions, extract_exercises(content, tb_id, ch_num))
            append!(all_questions, extract_pitfalls(content, tb_id, ch_num))
        end
        ch_count = length(chapters)
        q_count = count(q -> q.textbook == tb_id, all_questions)
        q_count > 0 && println("  ✓ $tb_id: $ch_count chapters → $q_count questions")
    end

    # Format all questions
    formatted = [format_question(q, i) for (i, q) in enumerate(all_questions)]

    # Stats
    stats = Dict(
        "total" => length(formatted),
        "by_type" => Dict(
            "definition" => count(q -> q.type == "definition", all_questions),
            "theorem" => count(q -> q.type == "theorem", all_questions),
            "exercise" => count(q -> q.type == "exercise", all_questions),
            "pitfall" => count(q -> q.type == "pitfall", all_questions),
        ),
        "by_difficulty" => Dict(
            "apply" => count(q -> q.difficulty == "apply", all_questions),
            "analyze" => count(q -> q.difficulty == "analyze", all_questions),
            "create" => count(q -> q.difficulty == "create", all_questions),
        ),
        "by_track" => Dict(
            k => count(q -> q.track_key == k, all_questions)
            for k in unique(q.track_key for q in all_questions)
        ),
        "textbooks_covered" => length(unique(q.textbook for q in all_questions)),
    )

    output = Dict(
        "generated" => string(Dates.now()),
        "version" => "1.0",
        "stats" => stats,
        "questions" => formatted,
    )

    mkpath(dirname(output_file))
    open(output_file, "w") do io
        JSON3.pretty(io, output)
    end

    println("\n" * "="^50)
    println("Question bank: $(length(formatted)) questions → $output_file")
    println("  Definitions: $(stats["by_type"]["definition"])")
    println("  Theorems:    $(stats["by_type"]["theorem"])")
    println("  Exercises:   $(stats["by_type"]["exercise"])")
    println("  Pitfalls:    $(stats["by_type"]["pitfall"])")
    println("  Textbooks:   $(stats["textbooks_covered"])")
    println("="^50)
end

main()
