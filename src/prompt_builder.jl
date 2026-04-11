"""
    prompt_builder.jl — Constructs per-chapter prompts from manifest JSON data.
"""
module PromptBuilder

using JSON3

export load_manifests, build_chapter_prompt, WorkItem, load_system_prompt, validate_manifest

"""
    WorkItem — A single chapter generation task.
"""
struct WorkItem
    textbook_id::String
    textbook_title::String
    track::String
    chapter_number::Int
    chapter_title::String
    content_outline::String
    textbook_description::String
    prerequisites::Vector{String}
    total_chapters::Int
    all_chapter_titles::Vector{String}
end

"""
    load_system_prompt(path::String) → String
"""
function load_system_prompt(path::String)
    return read(path, String)
end

"""
    validate_manifest(raw, path::String)

Validate that a parsed manifest has all required fields with correct types.
Throws an informative error if any required field is missing or has a wrong type.
"""
function validate_manifest(raw, path::String)
    required_textbook_fields = [:id, :title, :track, :description, :chapters]
    required_chapter_fields = [:chapter_number, :title, :content_outline]

    haskey(raw, :textbooks) || error("Manifest $path: missing top-level 'textbooks' array")

    for (i, tb) in enumerate(raw.textbooks)
        for field in required_textbook_fields
            haskey(tb, field) || error("Manifest $path textbook[$i]: missing field '$field'")
        end
        tb_id = string(tb.id)
        for (j, ch) in enumerate(tb.chapters)
            for field in required_chapter_fields
                haskey(ch, field) || error("Manifest $path textbook[$tb_id] chapter[$j]: missing field '$field'")
            end
            isa(ch.chapter_number, Integer) || error("Manifest $path textbook[$tb_id] chapter[$j]: chapter_number must be an integer, got $(typeof(ch.chapter_number))")
        end
    end
end

"""
    load_manifests(paths::Vector{String}) → Vector{WorkItem}

Load one or more manifest JSON files and return a flat list of WorkItems.
"""
function load_manifests(paths::Vector{String})
    items = WorkItem[]

    for path in paths
        raw = JSON3.read(read(path, String))
        validate_manifest(raw, path)
        textbooks = raw.textbooks

        for tb in textbooks
            id = String(tb.id)
            title = String(tb.title)
            track = String(tb.track)
            desc = String(tb.description)
            prereqs = haskey(tb, :prerequisites) ? String.(tb.prerequisites) : String[]
            chapters = tb.chapters
            total = length(chapters)
            all_titles = [String(ch.title) for ch in chapters]

            for ch in chapters
                push!(items, WorkItem(
                    id, title, track,
                    Int(ch.chapter_number),
                    String(ch.title),
                    String(ch.content_outline),
                    desc, prereqs, total, all_titles
                ))
            end
        end
    end

    return items
end

"""
    build_chapter_prompt(item::WorkItem) → String

Construct the user prompt for generating a single chapter.
"""
function build_chapter_prompt(item::WorkItem)
    # Build table of contents for context
    toc_lines = ["$i. $(item.all_chapter_titles[i])" for i in 1:item.total_chapters]
    toc = join(toc_lines, "\n")

    prereq_text = if isempty(item.prerequisites)
        "None specified."
    else
        join(item.prerequisites, ", ")
    end

    return """
    Write Chapter $(item.chapter_number) of the graduate textbook "$(item.textbook_title)".

    ## Textbook Context
    - **Track**: $(item.track)
    - **Textbook Description**: $(item.textbook_description)
    - **Prerequisites**: $(prereq_text)

    ## Full Table of Contents (for cross-reference context)
    $(toc)

    ## Chapter to Write
    - **Chapter $(item.chapter_number): $(item.chapter_title)**

    ## Detailed Content Specification
    $(item.content_outline)

    ## Instructions
    1. Write this chapter in full, following the content specification above exhaustively.
    2. Every topic mentioned in the content specification must be covered in depth.
    3. Include formal definitions, theorems with proofs, and worked examples.
    4. Include Julia code blocks demonstrating key computational concepts.
    5. End with 5-10 exercises (mix of proof-based and Julia computational).
    6. End with a References section citing foundational works.
    7. Target length: 4,000-7,000 words of substantive content.
    8. Begin directly with the chapter heading — no preamble.
    """
end

"""
    work_item_key(item::WorkItem) → String

Unique key for a work item, used for state tracking.
"""
function work_item_key(item::WorkItem)
    ch_str = lpad(item.chapter_number, 2, '0')
    return "$(item.textbook_id)/ch$(ch_str)"
end

end # module
