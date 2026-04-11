#!/usr/bin/env julia
"""
    quarto_export.jl — Export assembled markdown textbooks to Quarto QMD format.

    Reads assembled markdown from output/assembled/<ID>.md, adds Quarto YAML
    front-matter, and writes the result to output/generated/<id-lowercase>.qmd.

    Usage:
        julia --project=. src/quarto_export.jl                     # All textbooks
        julia --project=. src/quarto_export.jl --textbook CORE-001  # One textbook
        julia --project=. src/quarto_export.jl --stubs-only         # Write stubs even without assembled MD
"""

using JSON3, Dates

const PROJECT_ROOT = dirname(@__DIR__)
const MANIFESTS = [
    joinpath(PROJECT_ROOT, "manifests", "part1.json"),
    joinpath(PROJECT_ROOT, "manifests", "part2.json")
]
const MD_ASSEMBLED = joinpath(PROJECT_ROOT, "output", "assembled")
const QMD_OUTPUT   = joinpath(PROJECT_ROOT, "output", "generated")

# ─────────────────────────────────────────────
# CLI Args
# ─────────────────────────────────────────────
function parse_args()
    args = Dict{Symbol,Any}(
        :textbook   => nothing,
        :stubs_only => false,
    )
    i = 1
    while i <= length(ARGS)
        if ARGS[i] == "--textbook" && i < length(ARGS)
            args[:textbook] = ARGS[i+1]; i += 2
        elseif ARGS[i] == "--stubs-only"
            args[:stubs_only] = true; i += 1
        else
            i += 1
        end
    end
    return args
end

# ─────────────────────────────────────────────
# Manifest loading
# ─────────────────────────────────────────────
function load_textbook_metadata()
    textbooks = Dict{String,Any}()
    for path in MANIFESTS
        raw = JSON3.read(read(path, String))
        for tb in raw.textbooks
            id = String(tb.id)
            textbooks[id] = (
                title       = String(tb.title),
                track       = String(tb.track),
                description = String(tb.description),
                chapters    = [(num=Int(ch.chapter_number), title=String(ch.title)) for ch in tb.chapters],
            )
        end
    end
    return textbooks
end

# ─────────────────────────────────────────────
# Build Quarto front-matter block
# ─────────────────────────────────────────────
function front_matter(meta)
    return """---
title: "$(meta.title)"
subtitle: "$(meta.track)"
date: "$(Dates.today())"
toc: true
toc-depth: 2
number-sections: true
---
"""
end

# ─────────────────────────────────────────────
# Build a stub QMD (no assembled MD available)
# ─────────────────────────────────────────────
function stub_body(meta)
    toc = join(["$(ch.num). $(ch.title)" for ch in meta.chapters], "\n")
    sections = join([
        "## Chapter $(ch.num): $(ch.title)\n\n*This chapter has not yet been generated. " *
        "Run the generation pipeline to produce full content.*"
        for ch in meta.chapters
    ], "\n\n")

    return """
# $(meta.title)

**Track**: $(meta.track)

$(meta.description)

## Table of Contents

$(toc)

---

$(sections)
"""
end

# ─────────────────────────────────────────────
# Export one textbook
# ─────────────────────────────────────────────
function export_textbook(textbook_id::String, meta; stubs_only::Bool=false)
    qmd_id   = lowercase(textbook_id)
    qmd_path = joinpath(QMD_OUTPUT, "$(qmd_id).qmd")
    mkpath(QMD_OUTPUT)

    md_path = joinpath(MD_ASSEMBLED, "$(textbook_id).md")

    if !stubs_only && isfile(md_path)
        # Prepend Quarto front-matter to the existing assembled markdown
        assembled = read(md_path, String)
        # Strip any existing YAML front-matter from the assembled file
        body = if startswith(assembled, "---")
            # Find the closing "---" and strip it
            rest = assembled[4:end]
            close_idx = findfirst("---", rest)
            if !isnothing(close_idx)
                rest[close_idx.stop+1:end]
            else
                assembled
            end
        else
            assembled
        end
        write(qmd_path, front_matter(meta) * body)
        println("  ✅ Exported  $textbook_id  (from assembled MD) → $qmd_path")
    else
        # Write a well-formed stub so Quarto render doesn't fail
        write(qmd_path, front_matter(meta) * stub_body(meta))
        if stubs_only
            println("  📄 Stub      $textbook_id → $qmd_path")
        else
            println("  📄 Stub      $textbook_id  (no assembled MD found) → $qmd_path")
        end
    end

    return qmd_path
end

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
function main()
    args = parse_args()

    println("=" ^ 60)
    println("  QUARTO EXPORT")
    println("  $(Dates.now())")
    println("=" ^ 60)

    metadata = load_textbook_metadata()
    println("\n📚 Found $(length(metadata)) textbooks in manifests")

    ids = if !isnothing(args[:textbook])
        [args[:textbook]]
    else
        sort(collect(keys(metadata)))
    end

    exported = 0
    for id in ids
        if !haskey(metadata, id)
            @warn "Unknown textbook ID: $id"
            continue
        end
        export_textbook(id, metadata[id]; stubs_only=args[:stubs_only])
        exported += 1
    end

    println("\n" * "=" ^ 60)
    println("  EXPORT COMPLETE")
    println("  📄 Exported: $exported QMD files → $QMD_OUTPUT")
    println("=" ^ 60)
end

main()
