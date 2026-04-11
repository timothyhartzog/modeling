#!/usr/bin/env julia
"""
    build_quarto_config.jl — Regenerate output/_quarto.yml from manifest data.

    Reads manifests/part1.json and manifests/part2.json, then writes a fresh
    output/_quarto.yml whose sidebar entries exactly match the textbook titles
    and IDs stored in the manifests.  Run this script whenever a manifest is
    updated so that the Quarto website stays in sync.

    Usage:
        julia --project=. src/build_quarto_config.jl
"""

using JSON3

const PROJECT_ROOT = dirname(@__DIR__)
const MANIFESTS = [
    joinpath(PROJECT_ROOT, "manifests", "part1.json"),
    joinpath(PROJECT_ROOT, "manifests", "part2.json"),
]
const QUARTO_YML = joinpath(PROJECT_ROOT, "output", "_quarto.yml")

# ── Section definitions ────────────────────────────────────────────────────────
# Maps ID prefix → (sidebar section label, insertion order)
const SECTION_FOR_PREFIX = Dict(
    "CORE"  => (label = "📖 Core Foundations",              order = 1),
    "BIO"   => (label = "🧬 Biology & Life Sciences",       order = 2),
    "GEO"   => (label = "🌍 Geospatial & Environmental",    order = 3),
    "SCIML" => (label = "🤖 Machine Learning & AI",         order = 4),
    "PHYS"  => (label = "⚛️ Physics",                       order = 5),
    "POP"   => (label = "📊 Population & Dynamics",         order = 6),
    "ABM"   => (label = "🔀 Advanced Integration",          order = 7),
    "CROSS" => (label = "🔀 Advanced Integration",          order = 7),
    "UQ"    => (label = "📈 Uncertainty & Quantification",  order = 8),
)

# ── Load manifests ─────────────────────────────────────────────────────────────
function load_textbooks()
    textbooks = []
    for path in MANIFESTS
        raw = JSON3.read(read(path, String))
        for tb in raw.textbooks
            push!(textbooks, (id = String(tb.id), title = String(tb.title)))
        end
    end
    return textbooks
end

# ── ID prefix helper ───────────────────────────────────────────────────────────
function id_prefix(id::String)
    m = match(r"^([A-Z]+)-", id)
    m === nothing && error("Cannot parse prefix from textbook id: $id")
    return m.captures[1]
end

# ── Sort key: prefix order first, then numeric suffix ─────────────────────────
function sort_key(id::String)
    prefix = id_prefix(id)
    m = match(r"-(\d+)$", id)
    num = m === nothing ? 0 : parse(Int, m.captures[1])
    order = get(SECTION_FOR_PREFIX, prefix, (label="", order=99)).order
    return (order, prefix, num)
end

# ── Build sections ─────────────────────────────────────────────────────────────
function build_sections(textbooks)
    # Group by section label
    sections = Dict{String, Vector{NamedTuple}}()
    section_order = Dict{String, Int}()

    for tb in textbooks
        prefix = id_prefix(tb.id)
        info = get(SECTION_FOR_PREFIX, prefix, nothing)
        if info === nothing
            @warn "Unknown prefix for textbook $(tb.id); skipping"
            continue
        end
        label = info.label
        if !haskey(sections, label)
            sections[label] = []
            section_order[label] = info.order
        end
        push!(sections[label], tb)
    end

    # Sort entries within each section by ID
    for (label, entries) in sections
        sort!(entries, by = e -> sort_key(e.id))
    end

    # Return sections in display order
    sorted_labels = sort(collect(keys(sections)), by = l -> section_order[l])
    return [(label = l, entries = sections[l]) for l in sorted_labels]
end

# ── YAML generation ────────────────────────────────────────────────────────────
function generate_yaml(sections)
    lines = String[]

    push!(lines, "project:")
    push!(lines, "  type: website")
    push!(lines, "  output-dir: _site")
    push!(lines, "  execute-dir: project")
    push!(lines, "")
    push!(lines, "website:")
    push!(lines, "  title: \"Master Course of Study in Universal Modeling Mastery\"")
    push!(lines, "  description: \"52 graduate-level textbooks covering universal modeling across disciplines\"")
    push!(lines, "")
    push!(lines, "  navbar:")
    push!(lines, "    title: \"📚 Modeling Mastery\"")
    push!(lines, "    search: true")
    push!(lines, "    pinned: true")
    push!(lines, "    right:")
    push!(lines, "      - icon: github")
    push!(lines, "        href: https://github.com/timothyhartzog/modeling")
    push!(lines, "      - icon: search")
    push!(lines, "")
    push!(lines, "  sidebar:")
    push!(lines, "    style: \"floating\"")
    push!(lines, "    collapse-level: 1")
    push!(lines, "    contents:")

    for section in sections
        push!(lines, "      - section: \"$(section.label)\"")
        push!(lines, "        contents:")
        for tb in section.entries
            id_lower = lowercase(tb.id)
            # Escape any double-quotes in the title
            safe_title = replace(tb.title, "\"" => "\\\"")
            push!(lines, "          - text: \"$(tb.id): $(safe_title)\"")
            push!(lines, "            href: generated/$(id_lower).qmd")
        end
        push!(lines, "")
    end

    push!(lines, "format:")
    push!(lines, "  html:")
    push!(lines, "    theme: cosmo")
    push!(lines, "    toc: true")
    push!(lines, "    toc-depth: 2")
    push!(lines, "    number-sections: true")
    push!(lines, "    code-fold: false")
    push!(lines, "    code-line-numbers: true")
    push!(lines, "    smooth-scroll: true")
    push!(lines, "    highlight-style: github")

    return join(lines, "\n") * "\n"
end

# ── Main ───────────────────────────────────────────────────────────────────────
function main()
    println("Loading manifests…")
    textbooks = load_textbooks()
    println("  Loaded $(length(textbooks)) textbooks.")

    sections = build_sections(textbooks)
    total = sum(length(s.entries) for s in sections)
    println("  Organized into $(length(sections)) sidebar sections ($(total) entries).")

    yaml = generate_yaml(sections)

    write(QUARTO_YML, yaml)
    println("Wrote $(QUARTO_YML)")
end

main()
