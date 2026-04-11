#!/usr/bin/env julia
"""
    assemble_docx.jl — Post-generation textbook assembly.

    Concatenates per-chapter markdown files into single textbook markdown files,
    then converts to DOCX, PDF, and/or HTML via pandoc.

    Usage:
        julia --project=. src/assemble_docx.jl                         # All textbooks → DOCX (default)
        julia --project=. src/assemble_docx.jl --textbook CORE-001     # One textbook → DOCX
        julia --project=. src/assemble_docx.jl --markdown-only         # Only concatenate, skip conversion
        julia --project=. src/assemble_docx.jl --format pdf            # PDF only
        julia --project=. src/assemble_docx.jl --format html           # HTML single-file only
        julia --project=. src/assemble_docx.jl --format all            # DOCX + PDF + HTML
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
const REFERENCE_DOC = joinpath(PROJECT_ROOT, "templates", "reference.docx")
const PDF_OUTPUT = joinpath(PROJECT_ROOT, "output", "pdf")
const HTML_OUTPUT = joinpath(PROJECT_ROOT, "output", "html")

const VALID_FORMATS = ("docx", "pdf", "html", "all")

function parse_args()
    args = Dict{Symbol,Any}(
        :textbook => nothing,
        :markdown_only => false,
        :format => "docx",
    )
    i = 1
    while i <= length(ARGS)
        if ARGS[i] == "--textbook" && i < length(ARGS)
            args[:textbook] = ARGS[i+1]; i += 2
        elseif ARGS[i] == "--markdown-only"
            args[:markdown_only] = true; i += 1
        elseif ARGS[i] == "--format" && i < length(ARGS)
            fmt = lowercase(ARGS[i+1])
            if fmt ∉ VALID_FORMATS
                @error "Unknown format '$(ARGS[i+1])'. Valid options: $(join(VALID_FORMATS, ", "))"
                exit(1)
            end
            args[:format] = fmt; i += 2
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

    cmd = if isfile(REFERENCE_DOC)
        `pandoc $md_path -o $docx_path
               --from markdown
               --to docx
               --reference-doc=$REFERENCE_DOC
               --toc
               --toc-depth=3
               --number-sections
               --standalone`
    else
        @warn "No reference.docx template found at $REFERENCE_DOC — using pandoc defaults"
        `pandoc $md_path -o $docx_path
               --from markdown
               --to docx
               --toc
               --toc-depth=3
               --number-sections
               --standalone`
    end

    try
        run(cmd)
        println("  📘 Converted → $docx_path")
        return docx_path
    catch e
        @error "pandoc conversion failed for $textbook_id: $e"
        return nothing
    end
end

function convert_to_pdf(md_path::String, textbook_id::String)
    mkpath(PDF_OUTPUT)
    pdf_path = joinpath(PDF_OUTPUT, "$(textbook_id).pdf")

    # Check for pandoc
    try
        run(pipeline(`which pandoc`, devnull))
    catch
        @error "pandoc not found. Install with:\n" *
               "  macOS:  brew install pandoc\n" *
               "  Ubuntu: sudo apt-get install pandoc\n" *
               "  Windows: https://pandoc.org/installing.html"
        return nothing
    end

    # Check for a LaTeX engine
    latex_engine = nothing
    for engine in ("xelatex", "lualatex", "pdflatex")
        try
            run(pipeline(`which $engine`, devnull))
            latex_engine = engine
            break
        catch
        end
    end
    if isnothing(latex_engine)
        @error "No LaTeX engine found. Install one with:\n" *
               "  macOS:  brew install --cask mactex-no-gui\n" *
               "  Ubuntu: sudo apt-get install texlive-xetex\n" *
               "  Windows: https://miktex.org/download"
        return nothing
    end

    cmd = `pandoc $md_path -o $pdf_path
           --from markdown --to pdf
           --pdf-engine=$latex_engine
           --toc --toc-depth=3 --number-sections
           -V geometry:margin=1in
           -V fontsize=11pt
           --standalone`

    try
        run(cmd)
        println("  📕 Converted → $pdf_path")
        return pdf_path
    catch e
        @error "PDF conversion failed for $textbook_id: $e"
        return nothing
    end
end

function convert_to_html(md_path::String, textbook_id::String)
    mkpath(HTML_OUTPUT)
    html_path = joinpath(HTML_OUTPUT, "$(textbook_id).html")

    # Check for pandoc
    try
        run(pipeline(`which pandoc`, devnull))
    catch
        @error "pandoc not found. Install with:\n" *
               "  macOS:  brew install pandoc\n" *
               "  Ubuntu: sudo apt-get install pandoc\n" *
               "  Windows: https://pandoc.org/installing.html"
        return nothing
    end

    cmd = `pandoc $md_path -o $html_path
           --from markdown --to html5
           --toc --toc-depth=3 --number-sections
           --standalone
           --self-contained`

    try
        run(cmd)
        println("  🌐 Converted → $html_path")
        return html_path
    catch e
        @error "HTML conversion failed for $textbook_id: $e"
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
    converted_docx = 0
    converted_pdf  = 0
    converted_html = 0

    fmt = args[:format]
    do_docx = !args[:markdown_only] && (fmt == "docx" || fmt == "all")
    do_pdf  = !args[:markdown_only] && (fmt == "pdf"  || fmt == "all")
    do_html = !args[:markdown_only] && (fmt == "html" || fmt == "all")

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

        if do_docx
            result = convert_to_docx(md_path, id)
            if !isnothing(result)
                converted_docx += 1
            end
        end
        if do_pdf
            result = convert_to_pdf(md_path, id)
            if !isnothing(result)
                converted_pdf += 1
            end
        end
        if do_html
            result = convert_to_html(md_path, id)
            if !isnothing(result)
                converted_html += 1
            end
        end
    end

    println("\n" * "=" ^ 60)
    println("  ASSEMBLY COMPLETE")
    println("  📄 Assembled: $assembled textbooks")
    if do_docx; println("  📘 DOCX:      $converted_docx files"); end
    if do_pdf;  println("  📕 PDF:       $converted_pdf files");  end
    if do_html; println("  🌐 HTML:      $converted_html files"); end
    println("=" ^ 60)
end

main()
