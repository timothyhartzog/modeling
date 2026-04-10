#!/usr/bin/env julia
"""
    assemble_docx.jl — Post-generation DOCX assembly.

    Concatenates per-chapter markdown files into single textbook markdown files,
    then converts to DOCX via pandoc.

    Usage:
        julia --project=. src/assemble_docx.jl                    # All textbooks
        julia --project=. src/assemble_docx.jl --textbook CORE-001  # One textbook
        julia --project=. src/assemble_docx.jl --markdown-only     # Only concatenate, skip DOCX
"""

using JSON3, Dates

const PROJECT_ROOT = dirname(@__DIR__)
const MANIFESTS = [
    joinpath(PROJECT_ROOT, "manifests", "part1.json"),
    joinpath(PROJECT_ROOT, "manifests", "part2.json")
]
const MD_INPUT = joinpath(PROJECT_ROOT, "output", "markdown")
const MD_ASSEMBLED = joinpath(PROJECT_ROOT, "output", "assembled")
const DOCX_OUTPUT = joinpath(PROJECT_ROOT, "output", "docx")

function parse_args()
    args = Dict{Symbol,Any}(
        :textbook => nothing,
        :markdown_only => false,
    )
    i = 1
    while i <= length(ARGS)
        if ARGS[i] == "--textbook" && i < length(ARGS)
            args[:textbook] = ARGS[i+1]; i += 2
        elseif ARGS[i] == "--markdown-only"
            args[:markdown_only] = true; i += 1
        else
            i += 1
        end
    end
    return args
end

function load_textbook_metadata()
    textbooks = Dict{String, Any}()
    for path in MANIFESTS
        raw = JSON3.read(read(path, String))
        for tb in raw.textbooks
            id = String(tb.id)
            textbooks[id] = (
                title = String(tb.title),
                track = String(tb.track),
                description = String(tb.description),
                chapters = [(num=Int(ch.chapter_number), title=String(ch.title)) for ch in tb.chapters]
            )
        end
    end
    return textbooks
end

function assemble_textbook(textbook_id::String, meta)
    chapter_dir = joinpath(MD_INPUT, textbook_id)

    if !isdir(chapter_dir)
        @warn "No chapters found for $textbook_id at $chapter_dir — skipping"
        return nothing
    end

    # Collect available chapter files
    parts = String[]

    # Front matter
    push!(parts, """
    ---
    title: "$(meta.title)"
    subtitle: "$(meta.track)"
    date: "$(Dates.today())"
    ---

    # $(meta.title)

    **Track**: $(meta.track)

    $(meta.description)

    ---

    """)

    # Table of contents
    push!(parts, "## Table of Contents\n")
    for ch in meta.chapters
        push!(parts, "$(ch.num). $(ch.title)\n")
    end
    push!(parts, "\n---\n\n")

    # Chapters
    found = 0
    missing_chapters = String[]
    for ch in meta.chapters
        ch_file = joinpath(chapter_dir, "ch$(lpad(ch.num, 2, '0')).md")
        if isfile(ch_file)
            content = read(ch_file, String)
            push!(parts, content)
            push!(parts, "\n\n---\n\n")
            found += 1
        else
            push!(parts, "# Chapter $(ch.num): $(ch.title)\n\n*[Chapter not yet generated]*\n\n---\n\n")
            push!(missing_chapters, "Ch.$(ch.num): $(ch.title)")
        end
    end

    if found == 0
        @warn "No chapter files found for $textbook_id — skipping"
        return nothing
    end

    # Write assembled markdown
    mkpath(MD_ASSEMBLED)
    md_path = joinpath(MD_ASSEMBLED, "$(textbook_id).md")
    write(md_path, join(parts))

    println("  📄 Assembled $textbook_id: $found/$(length(meta.chapters)) chapters → $md_path")
    if !isempty(missing_chapters)
        println("     ⚠️  Missing: $(join(missing_chapters, ", "))")
    end

    return md_path
end

function convert_to_docx(md_path::String, textbook_id::String)
    mkpath(DOCX_OUTPUT)
    docx_path = joinpath(DOCX_OUTPUT, "$(textbook_id).docx")

    # Check for pandoc
    try
        run(pipeline(`which pandoc`, devnull))
    catch
        @error "pandoc not found. Install with: brew install pandoc"
        return nothing
    end

    cmd = `pandoc $md_path -o $docx_path
           --from markdown
           --to docx
           --toc
           --toc-depth=3
           --number-sections
           --standalone`

    try
        run(cmd)
        println("  📘 Converted → $docx_path")
        return docx_path
    catch e
        @error "pandoc conversion failed for $textbook_id: $e"
        return nothing
    end
end

function main()
    args = parse_args()

    println("=" ^ 60)
    println("  TEXTBOOK ASSEMBLY")
    println("  $(Dates.now())")
    println("=" ^ 60)

    metadata = load_textbook_metadata()
    println("\n📚 Found $(length(metadata)) textbooks in manifests")

    # Filter if single textbook requested
    ids = if !isnothing(args[:textbook])
        [args[:textbook]]
    else
        sort(collect(keys(metadata)))
    end

    assembled = 0
    converted = 0

    for id in ids
        if !haskey(metadata, id)
            @warn "Unknown textbook ID: $id"
            continue
        end

        md_path = assemble_textbook(id, metadata[id])
        if isnothing(md_path)
            continue
        end
        assembled += 1

        if !args[:markdown_only]
            result = convert_to_docx(md_path, id)
            if !isnothing(result)
                converted += 1
            end
        end
    end

    println("\n" * "=" ^ 60)
    println("  ASSEMBLY COMPLETE")
    println("  📄 Assembled: $assembled textbooks")
    if !args[:markdown_only]
        println("  📘 Converted: $converted DOCX files")
    end
    println("=" ^ 60)
end

main()
