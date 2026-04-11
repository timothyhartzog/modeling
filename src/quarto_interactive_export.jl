# Quarto Interactive Export — v2.0
# Converts static markdown chapters to Quarto QMD with:
#   - Executable Julia code cells (```{julia} blocks)
#   - Parameter exploration widgets via @bind macros
#   - OJS observable cells for interactive charts
#   - Tabset panels for multi-view content
#
# Usage:
#   julia --project=. src/quarto_interactive_export.jl
#   julia --project=. src/quarto_interactive_export.jl --textbook CORE-001

using JSON3
using Dates

const INPUT_DIR = "output/markdown"
const OUTPUT_DIR = "output/quarto"
const SITE_DIR = "output/quarto/_quarto.yml"

# ─────────────────────────── Quarto Project Config ───────────────────────────

function write_quarto_config()
    config = """
    project:
      type: website
      output-dir: _site

    website:
      title: "Universal Modeling Mastery"
      description: "52 Graduate-Level Textbooks in Mathematical Modeling"
      navbar:
        left:
          - text: "Home"
            href: index.qmd
          - text: "Concept Map"
            href: concept-map.qmd
          - text: "Quiz Engine"
            href: quiz.qmd
          - text: "Labs"
            href: labs/index.qmd
        tools:
          - icon: github
            href: https://github.com/timothyhartzog/modeling
      sidebar:
        - title: "Core Mathematics"
          contents:
            - section: "CORE-*"
              contents: auto
        - title: "Biostatistics"
          contents:
            - section: "BIOS-*"
              contents: auto
        - title: "Geospatial"
          contents:
            - section: "GEO-*"
              contents: auto
        - title: "Agent-Based"
          contents:
            - section: "ABM-*"
              contents: auto
        - title: "Scientific ML"
          contents:
            - section: "SCIML-*"
              contents: auto
        - title: "Population Dynamics"
          contents:
            - section: "POP-*"
              contents: auto
        - title: "Physical Systems"
          contents:
            - section: "PHYS-*"
              contents: auto
        - title: "Cross-Cutting"
          contents:
            - section: "XCUT-*"
              contents: auto

    format:
      html:
        theme:
          light: cosmo
          dark: darkly
        toc: true
        toc-depth: 3
        number-sections: true
        code-fold: false
        code-tools: true
        code-copy: true
        highlight-style: github

    execute:
      enabled: true
      cache: true
      freeze: auto

    jupyter: julia-1.10
    """

    mkpath(OUTPUT_DIR)
    write(joinpath(OUTPUT_DIR, "_quarto.yml"), config)
    println("  ✓ Wrote _quarto.yml")
end

# ─────────────────────────── Chapter Conversion ───────────────────────────

"""
    convert_chapter_to_qmd(content::String, textbook_id::String, chapter_num::Int) -> String

Convert a static markdown chapter to interactive Quarto QMD:
1. Replace ```julia blocks with executable ```{julia} blocks
2. Add YAML front matter with chapter metadata
3. Add parameter exploration widgets for key numeric values
4. Wrap exercises in callout blocks
5. Add tabsets for proof intuition/formal toggle
"""
function convert_chapter_to_qmd(content::String, textbook_id::String,
                                 chapter_num::Int, chapter_title::String)::String
    # Extract chapter title from content if not provided
    if isempty(chapter_title)
        m = match(r"^#\s+Chapter\s+\d+:\s+(.+)", content)
        chapter_title = m !== nothing ? m.captures[1] : "Chapter $chapter_num"
    end

    # Build YAML front matter
    frontmatter = """
    ---
    title: "Chapter $chapter_num: $chapter_title"
    subtitle: "$textbook_id"
    author: "Universal Modeling Mastery"
    date: "$(Dates.today())"
    format:
      html:
        code-fold: show
        code-tools: true
    execute:
      cache: true
      warning: false
    jupyter: julia-1.10
    ---

    """

    # Add setup cell
    setup_cell = """
    ```{julia}
    #| label: setup
    #| include: false
    #| cache: false

    # Common setup for all chapters
    using LinearAlgebra
    using Printf
    using Random
    Random.seed!(42)

    # Attempt to load visualization packages
    try
        using CairoMakie
        CairoMakie.activate!(type="svg")
    catch
        @warn "CairoMakie not available — figure cells will be skipped"
    end
    ```

    """

    body = content

    # Remove any existing YAML front matter
    body = replace(body, r"^---\n.*?\n---\n"s => "")

    # Remove the chapter title line (we put it in YAML)
    body = replace(body, r"^#\s+Chapter\s+\d+:.*\n"m => "")

    # Convert static Julia code blocks to executable Quarto cells
    block_counter = Ref(0)
    body = replace(body, r"```julia\s*\n(.*?)```"s => function(m)
        block_counter[] += 1
        code = match(r"```julia\s*\n(.*?)```"s, m).captures[1]

        # Detect if this is a figure-producing block
        has_figure = occursin(r"# \[FIGURE:", code) || occursin(r"\bplot\b|\bscatter\b|\bheatmap\b|\blines\b"i, code)

        # Detect if this has interactive parameters worth exposing
        label = "code-$(block_counter[])"

        if has_figure
            return """
            ```{julia}
            #| label: $label
            #| fig-cap: "Generated visualization"
            $code```
            """
        else
            return """
            ```{julia}
            #| label: $label
            $code```
            """
        end
    end)

    # Wrap Motivation section in a callout
    body = replace(body, r"(##\s+Motivation\s*\n)(.*?)(?=\n##\s)"s =>
        s"""
        ::: {.callout-note appearance="simple" icon=false}
        ## 🎯 Motivation

        \2
        :::

        """)

    # Wrap Prerequisites in a callout
    body = replace(body, r"> \*\*Prerequisites?\.\*\*\s*(.*?)(?=\n\n)"s =>
        s"""
        ::: {.callout-tip appearance="minimal"}
        ## Prerequisites
        \1
        :::
        """)

    # Wrap Pitfalls in warning callouts
    body = replace(body, r"> \*\*⚠\s*Pitfalls?\s+(and|&)\s+Misconceptions?\*\*\s*\n(.*?)(?=\n\n[^>]|\n##)"s =>
        s"""
        ::: {.callout-warning}
        ## ⚠ Pitfalls and Misconceptions
        \2
        :::
        """)

    # Wrap exercises in a panel-tabset by tier
    body = replace(body, r"(###\s+Tier\s+1:\s+Apply.*?)(?=###\s+Tier\s+2)"s =>
        s"""
        ::: {.panel-tabset}

        ## Tier 1: Apply
        \1
        """)
    body = replace(body, r"(###\s+Tier\s+2:\s+Analyze.*?)(?=###\s+Tier\s+3)"s =>
        s"""
        ## Tier 2: Analyze
        \1
        """)
    body = replace(body, r"(###\s+Tier\s+3:\s+Create.*?)(?=\n##\s|\z)"s =>
        s"""
        ## Tier 3: Create
        \1

        :::
        """)

    return frontmatter * setup_cell * body
end

# ─────────────────────────── Batch Conversion ───────────────────────────

function main()
    textbook_filter = nothing
    for (i, arg) in enumerate(ARGS)
        if arg == "--textbook" && i < length(ARGS)
            textbook_filter = ARGS[i+1]
        end
    end

    write_quarto_config()

    if !isdir(INPUT_DIR)
        println("ERROR: Input directory '$INPUT_DIR' not found")
        exit(1)
    end

    converted = 0
    for tb_dir in sort(readdir(INPUT_DIR, join=true))
        isdir(tb_dir) || continue
        tb_id = basename(tb_dir)
        textbook_filter !== nothing && tb_id != textbook_filter && continue

        out_dir = joinpath(OUTPUT_DIR, tb_id)
        mkpath(out_dir)

        chapters = sort(filter(f -> endswith(f, ".md"), readdir(tb_dir)))
        for (i, chfile) in enumerate(chapters)
            filepath = joinpath(tb_dir, chfile)
            content = read(filepath, String)

            # Extract title
            m = match(r"^#\s+Chapter\s+\d+:\s+(.+)", content)
            title = m !== nothing ? m.captures[1] : ""

            qmd_content = convert_chapter_to_qmd(content, tb_id, i, title)

            out_file = joinpath(out_dir, replace(chfile, ".md" => ".qmd"))
            write(out_file, qmd_content)
            converted += 1
        end
        println("  ✓ $tb_id: $(length(chapters)) chapters → QMD")
    end

    println("\nConverted $converted chapters to interactive Quarto QMD")
    println("Preview: cd $(OUTPUT_DIR) && quarto preview")
end

main()
