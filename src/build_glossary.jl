# Glossary & Notation Index Generator — v1.0
# Parses all generated chapters to build:
#   1. A unified glossary of all definitions across the curriculum
#   2. A notation index mapping symbols to their meanings
#   3. A theorem index with cross-references
#
# Outputs: glossary.json, notation-index.json, theorem-index.json
# Also generates a glossary.qmd for the Quarto website.
#
# Usage:
#   julia --project=. src/build_glossary.jl
#   julia --project=. src/build_glossary.jl --output-dir output/

using JSON3
using Dates

const INPUT_DIR = "output/markdown"

# ─────────────────────────── Structures ───────────────────────────

struct GlossaryEntry
    term::String
    definition::String
    textbook::String
    chapter::Int
    def_number::String   # e.g., "1.3"
    first_appearance::String  # e.g., "CORE-001/ch02"
end

struct NotationEntry
    symbol::String
    meaning::String
    context::String      # e.g., "Linear Algebra", "Probability"
    textbook::String
    chapter::Int
end

struct TheoremEntry
    name::String
    statement::String
    textbook::String
    chapter::Int
    thm_number::String
    proof_present::Bool
end

# ─────────────────────────── Parsing ───────────────────────────

function parse_definitions(content::String, textbook_id::String, chapter_num::Int)
    entries = GlossaryEntry[]
    for m in eachmatch(r"\*\*Definition\s+(\d+\.\d+)\s*\(([^)]+)\)\.\*\*\s*(.*?)(?=\n\n|\n>|\z)"s, content)
        num = m.captures[1]
        term = strip(m.captures[2])
        body = strip(m.captures[3])
        # Clean up markdown formatting
        body = replace(body, r"\*\*" => "")
        body = replace(body, r"\*" => "")
        # Truncate if very long
        if length(body) > 500
            body = body[1:500] * "..."
        end
        push!(entries, GlossaryEntry(term, body, textbook_id, chapter_num, num,
                                      "$(textbook_id)/ch$(lpad(chapter_num, 2, '0'))"))
    end
    return entries
end

function parse_theorems(content::String, textbook_id::String, chapter_num::Int)
    entries = TheoremEntry[]
    for m in eachmatch(r"\*\*Theorem\s+(\d+\.\d+)\s*\(([^)]+)\)\.\*\*\s*(.*?)(?=\n\n|\n>|\*Proof|\z)"s, content)
        num = m.captures[1]
        name = strip(m.captures[2])
        statement = strip(m.captures[3])
        if length(statement) > 500
            statement = statement[1:500] * "..."
        end
        has_proof = occursin(r"\*Proof\.\*", content)
        push!(entries, TheoremEntry(name, statement, textbook_id, chapter_num, num, has_proof))
    end
    # Also parse Lemmas and Corollaries
    for m in eachmatch(r"\*\*(Lemma|Corollary)\s+(\d+\.\d+)\s*\(([^)]+)\)\.\*\*\s*(.*?)(?=\n\n|\n>|\*Proof|\z)"s, content)
        type = m.captures[1]
        num = m.captures[2]
        name = strip(m.captures[3])
        statement = strip(m.captures[4])
        if length(statement) > 500
            statement = statement[1:500] * "..."
        end
        push!(entries, TheoremEntry("$type: $name", statement, textbook_id, chapter_num, num, false))
    end
    return entries
end

function parse_notation(content::String, textbook_id::String, chapter_num::Int)
    entries = NotationEntry[]

    # Common patterns: "Let X denote...", "where X is...", "X = ...", "denote by X"
    notation_patterns = [
        # "Let f: R^n → R be..."
        r"[Ll]et\s+([A-Za-zα-ωΑ-Ω]+[\w₀-₉]*)\s*(?::|∈|⊂)\s*([^.]+)"s,
        # "where κ(A) = ..."
        r"where\s+([A-Za-zα-ωΑ-Ω]+[\w₀-₉()]*)\s*=\s*([^.]+)"s,
        # "denote by X the..."
        r"denote by\s+([A-Za-zα-ωΑ-Ω]+[\w₀-₉]*)\s+(?:the\s+)?([^.]+)"s,
        # "ε_mach" and similar named constants
        r"(ε_mach|u|κ\(A\)|σ_max|σ_min|R₀|p_eff)\s+(?:is|=|denotes)\s+([^.]+)"s,
    ]

    for pattern in notation_patterns
        for m in eachmatch(pattern, content)
            symbol = strip(m.captures[1])
            meaning = strip(m.captures[2])
            # Skip very common symbols that would flood the index
            length(symbol) > 20 && continue
            length(meaning) > 200 && (meaning = meaning[1:200] * "...")

            # Infer context from textbook ID
            context = infer_context(textbook_id)
            push!(entries, NotationEntry(symbol, meaning, context, textbook_id, chapter_num))
        end
    end

    return entries
end

function infer_context(textbook_id::String)::String
    prefix = match(r"^([A-Z]+)-", textbook_id)
    prefix === nothing && return "General"
    p = prefix.captures[1]
    return Dict(
        "CORE" => "Core Mathematics",
        "BIO" => "Biostatistics",
        "GEO" => "Geospatial",
        "ABM" => "Agent-Based Modeling",
        "SCIML" => "Scientific ML",
        "POP" => "Population Dynamics",
        "PHYS" => "Physical Systems",
        "CROSS" => "Cross-Cutting",
        "UQ" => "Uncertainty Quantification",
    )[p]
end

# ─────────────────────────── Output Generation ───────────────────────────

function generate_glossary_qmd(glossary::Vector{GlossaryEntry}, output_path::String)
    # Sort alphabetically by term
    sorted = sort(glossary, by=g -> lowercase(g.term))

    open(output_path, "w") do io
        println(io, """
---
title: "Glossary of Definitions"
subtitle: "Unified reference across all $(length(unique(g.textbook for g in glossary))) textbooks"
---

This glossary contains all $(length(sorted)) formal definitions from the curriculum,
sorted alphabetically. Each entry links to its source textbook and chapter.

""")
        current_letter = ""
        for g in sorted
            first_letter = uppercase(string(g.term[1]))
            if first_letter != current_letter
                current_letter = first_letter
                println(io, "\n## $current_letter\n")
            end

            println(io, "**$(g.term)** ($(g.textbook), Def. $(g.def_number))")
            println(io, ": $(g.definition)\n")
        end
    end
end

# ─────────────────────────── Main ───────────────────────────

function main()
    output_dir = "output"
    for (i, arg) in enumerate(ARGS)
        if arg == "--output-dir" && i < length(ARGS)
            output_dir = ARGS[i+1]
        end
    end

    all_glossary = GlossaryEntry[]
    all_theorems = TheoremEntry[]
    all_notation = NotationEntry[]

    if !isdir(INPUT_DIR)
        println("WARNING: $INPUT_DIR not found. Creating empty indices.")
        mkpath(output_dir)
        for (fname, data) in [("glossary.json", []), ("theorem-index.json", []), ("notation-index.json", [])]
            open(joinpath(output_dir, fname), "w") do io
                JSON3.pretty(io, Dict("generated" => string(Dates.now()), "entries" => data))
            end
        end
        return
    end

    for tb_dir in sort(readdir(INPUT_DIR, join=true))
        isdir(tb_dir) || continue
        tb_id = basename(tb_dir)

        chapters = sort(filter(f -> endswith(f, ".md"), readdir(tb_dir)))
        for (ch_num, chfile) in enumerate(chapters)
            content = read(joinpath(tb_dir, chfile), String)
            append!(all_glossary, parse_definitions(content, tb_id, ch_num))
            append!(all_theorems, parse_theorems(content, tb_id, ch_num))
            append!(all_notation, parse_notation(content, tb_id, ch_num))
        end

        g_count = count(g -> g.textbook == tb_id, all_glossary)
        t_count = count(t -> t.textbook == tb_id, all_theorems)
        (g_count + t_count > 0) && println("  ✓ $tb_id: $g_count definitions, $t_count theorems")
    end

    # Deduplicate glossary by term name (keep first appearance)
    seen_terms = Set{String}()
    unique_glossary = GlossaryEntry[]
    for g in all_glossary
        key = lowercase(g.term)
        if key ∉ seen_terms
            push!(seen_terms, key)
            push!(unique_glossary, g)
        end
    end

    mkpath(output_dir)

    # Write glossary JSON
    open(joinpath(output_dir, "glossary.json"), "w") do io
        JSON3.pretty(io, Dict(
            "generated" => string(Dates.now()),
            "total" => length(unique_glossary),
            "entries" => [Dict(
                "term" => g.term, "definition" => g.definition,
                "textbook" => g.textbook, "chapter" => g.chapter,
                "def_number" => g.def_number, "first_appearance" => g.first_appearance,
            ) for g in sort(unique_glossary, by=g -> lowercase(g.term))]
        ))
    end

    # Write theorem index JSON
    open(joinpath(output_dir, "theorem-index.json"), "w") do io
        JSON3.pretty(io, Dict(
            "generated" => string(Dates.now()),
            "total" => length(all_theorems),
            "entries" => [Dict(
                "name" => t.name, "statement" => t.statement,
                "textbook" => t.textbook, "chapter" => t.chapter,
                "thm_number" => t.thm_number, "proof_present" => t.proof_present,
            ) for t in all_theorems]
        ))
    end

    # Write notation index JSON
    # Deduplicate by symbol
    seen_symbols = Set{String}()
    unique_notation = NotationEntry[]
    for n in all_notation
        if n.symbol ∉ seen_symbols
            push!(seen_symbols, n.symbol)
            push!(unique_notation, n)
        end
    end

    open(joinpath(output_dir, "notation-index.json"), "w") do io
        JSON3.pretty(io, Dict(
            "generated" => string(Dates.now()),
            "total" => length(unique_notation),
            "entries" => [Dict(
                "symbol" => n.symbol, "meaning" => n.meaning,
                "context" => n.context, "textbook" => n.textbook,
                "chapter" => n.chapter,
            ) for n in sort(unique_notation, by=n -> lowercase(n.symbol))]
        ))
    end

    # Generate Quarto glossary page
    generate_glossary_qmd(unique_glossary, joinpath(output_dir, "glossary.qmd"))

    println("\n" * "="^55)
    println("Indices generated:")
    println("  Glossary:   $(length(unique_glossary)) unique definitions → glossary.json + glossary.qmd")
    println("  Theorems:   $(length(all_theorems)) entries → theorem-index.json")
    println("  Notation:   $(length(unique_notation)) symbols → notation-index.json")
    println("  Textbooks:  $(length(unique(g.textbook for g in all_glossary)))")
    println("="^55)
end

main()
