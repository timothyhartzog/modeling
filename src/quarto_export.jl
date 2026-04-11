#!/usr/bin/env julia
"""
    quarto_export.jl — Convert assembled markdown to Quarto QMD for website.

    Reads assembled .md files from output/assembled/ and writes .qmd files with
    proper Quarto YAML front-matter to output/generated/.  For textbooks that
    have not yet been assembled a placeholder .qmd is written so that
    `quarto render` never fails on a missing file.

    Usage:
        julia --project=. src/quarto_export.jl                      # All textbooks
        julia --project=. src/quarto_export.jl --textbook CORE-001  # One textbook
        julia --project=. src/quarto_export.jl --stubs-only         # Placeholders only
"""

using JSON3, Dates

const PROJECT_ROOT = dirname(@__DIR__)
const MANIFESTS = [
    joinpath(PROJECT_ROOT, "manifests", "part1.json"),
    joinpath(PROJECT_ROOT, "manifests", "part2.json")
]
const MD_ASSEMBLED  = joinpath(PROJECT_ROOT, "output", "assembled")
const QMD_OUTPUT    = joinpath(PROJECT_ROOT, "output", "generated")

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Manifest loading
# ---------------------------------------------------------------------------

function load_textbook_metadata()
    textbooks = Dict{String, Any}()
    for path in MANIFESTS
        raw = JSON3.read(read(path, String))
        for tb in raw.textbooks
            id = String(tb.id)
            textbooks[id] = (
                title       = String(tb.title),
                track       = String(tb.track),
                description = String(tb.description),
            )
        end
    end
    return textbooks
end

# ---------------------------------------------------------------------------
# YAML front-matter helpers
# ---------------------------------------------------------------------------

const YAML_OPEN_DELIM = "---"
const YAML_OPEN_DELIM_LEN = length(YAML_OPEN_DELIM) + 1   # +1 for exclusive slice start

"""
    strip_yaml_frontmatter(content) → String

Remove a leading YAML front-matter block (`---` … `---`) if present.
Returns the remaining body text, stripped of leading blank lines.
"""
function strip_yaml_frontmatter(content::String)
    # Must start with '---' (optionally followed by spaces/newline)
    if !startswith(content, YAML_OPEN_DELIM)
        return content
    end
    # Find the closing '---' delimiter (must be on its own line)
    rest = content[YAML_OPEN_DELIM_LEN:end]   # skip opening ---
    # Consume an optional newline immediately after the opening ---
    if startswith(rest, "\r\n")
        rest = rest[3:end]
    elseif startswith(rest, "\n")
        rest = rest[2:end]
    end
    # Search for closing delimiter
    closing = r"(?m)^---[ \t]*$"
    m = match(closing, rest)
    if isnothing(m)
        return content          # malformed — return as-is
    end
    body = rest[m.offset + length(m.match):end]
    # Strip leading blank lines
    return lstrip(body, ['\n', '\r', ' ', '\t'])
end

"""
    build_frontmatter(id, meta) → String

Return a Quarto-compatible YAML front-matter block.
"""
function build_frontmatter(id::String, meta)
    # Escape any double-quotes in fields that will be quoted
    esc(s) = replace(String(s), "\"" => "\\\"")
    today  = string(Dates.today())
    return """---
title: "$(esc(meta.title))"
subtitle: "$(id) | $(esc(meta.track))"
description: "$(esc(meta.description))"
date: "$(today)"
toc: true
toc-depth: 3
number-sections: true
---

"""
end

# ---------------------------------------------------------------------------
# Per-textbook export
# ---------------------------------------------------------------------------

function export_textbook(id::String, meta; stubs_only::Bool=false)
    qmd_path   = joinpath(QMD_OUTPUT, "$(lowercase(id)).qmd")
    assembled  = joinpath(MD_ASSEMBLED, "$(id).md")

    if stubs_only || !isfile(assembled)
        # Write placeholder
        frontmatter = build_frontmatter(id, meta)
        placeholder = frontmatter * """
# $(meta.title)

*Content not yet generated.*

Run the generation pipeline and then `src/quarto_export.jl` to populate this page.
"""
        write(qmd_path, placeholder)
        label = stubs_only ? "stub" : "placeholder"
        println("  📄 $(label): $(id) → $(basename(qmd_path))")
        return qmd_path
    end

    # Read assembled markdown and strip any existing front-matter
    raw_content = read(assembled, String)
    body        = strip_yaml_frontmatter(raw_content)
    frontmatter = build_frontmatter(id, meta)

    write(qmd_path, frontmatter * body)
    println("  ✅ Exported: $(id) → $(basename(qmd_path))")
    return qmd_path
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function main()
    args = parse_args()

    println("=" ^ 60)
    println("  QUARTO EXPORT")
    println("  $(Dates.now())")
    if args[:stubs_only]
        println("  Mode: stubs-only")
    end
    println("=" ^ 60)

    mkpath(QMD_OUTPUT)

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
    println("  EXPORT COMPLETE — $(exported) QMD files written")
    println("  Output: $(QMD_OUTPUT)")
    println("=" ^ 60)
end

main()
