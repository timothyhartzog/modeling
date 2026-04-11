# Concept Graph Generator — v1.0
# Parses all generated chapters and builds a JSON knowledge graph
# of definitions, theorems, algorithms, and their cross-references.
#
# Usage:
#   julia --project=. src/build_concept_graph.jl
#   julia --project=. src/build_concept_graph.jl --output concept-graph.json
#
# Output: JSON file with nodes (concepts) and edges (dependencies)
# consumed by the React Concept Map Navigator component.

using JSON3
using Dates

const INPUT_DIR = "output/markdown"
const MANIFEST_FILES = ["manifests/part1.json", "manifests/part2.json"]

struct ConceptNode
    id::String
    label::String
    type::Symbol           # :definition, :theorem, :algorithm, :concept
    track::String          # e.g., "CORE"
    textbook::String       # e.g., "CORE-001"
    chapter::Int
    section::String
    line_number::Int
end

struct ConceptEdge
    source::String
    target::String
    type::Symbol           # :depends, :generalizes, :applied_in, :cross_ref
end

# ─────────────────────────── Track Inference ───────────────────────────

function infer_track(textbook_id::String)::String
    prefix = match(r"^([A-Z]+)-", textbook_id)
    return prefix !== nothing ? prefix.captures[1] : "XCUT"
end

# ─────────────────────────── Chapter Parsing ───────────────────────────

"""
    parse_chapter(filepath, textbook_id, chapter_num) -> (nodes, edges)

Extract definitions, theorems, algorithms, and cross-references from a chapter.
"""
function parse_chapter(filepath::String, textbook_id::String, chapter_num::Int)
    content = read(filepath, String)
    lines = split(content, '\n')
    track = infer_track(textbook_id)
    
    nodes = ConceptNode[]
    edges = ConceptEdge[]
    
    current_section = ""
    
    for (i, line) in enumerate(lines)
        # Track current section
        m_sec = match(r"^##\s+(.+)", line)
        if m_sec !== nothing
            current_section = strip(m_sec.captures[1])
        end
        
        # Parse definitions
        m_def = match(r"\*\*Definition\s+(\d+\.\d+)\s*\(([^)]+)\)", line)
        if m_def !== nothing
            num = m_def.captures[1]
            name = strip(m_def.captures[2])
            id = "$(textbook_id)-def-$(num)"
            push!(nodes, ConceptNode(id, name, :definition, track, textbook_id,
                                      chapter_num, current_section, i))
        end
        
        # Parse theorems
        m_thm = match(r"\*\*Theorem\s+(\d+\.\d+)\s*\(([^)]+)\)", line)
        if m_thm !== nothing
            num = m_thm.captures[1]
            name = strip(m_thm.captures[2])
            id = "$(textbook_id)-thm-$(num)"
            push!(nodes, ConceptNode(id, name, :theorem, track, textbook_id,
                                      chapter_num, current_section, i))
        end
        
        # Parse lemmas
        m_lem = match(r"\*\*Lemma\s+(\d+\.\d+)\s*\(([^)]+)\)", line)
        if m_lem !== nothing
            num = m_lem.captures[1]
            name = strip(m_lem.captures[2])
            id = "$(textbook_id)-lem-$(num)"
            push!(nodes, ConceptNode(id, name, :theorem, track, textbook_id,
                                      chapter_num, current_section, i))
        end
        
        # Parse corollaries
        m_cor = match(r"\*\*Corollary\s+(\d+\.\d+)\s*\(([^)]+)\)", line)
        if m_cor !== nothing
            num = m_cor.captures[1]
            name = strip(m_cor.captures[2])
            id = "$(textbook_id)-cor-$(num)"
            push!(nodes, ConceptNode(id, name, :theorem, track, textbook_id,
                                      chapter_num, current_section, i))
        end
        
        # Parse algorithm blocks (heuristic: look for "Algorithm N.N" patterns)
        m_alg = match(r"\*\*Algorithm\s+(\d+\.\d+)\s*[:\(]?\s*([^*\)]+)", line)
        if m_alg !== nothing
            num = m_alg.captures[1]
            name = strip(m_alg.captures[2])
            id = "$(textbook_id)-alg-$(num)"
            push!(nodes, ConceptNode(id, name, :algorithm, track, textbook_id,
                                      chapter_num, current_section, i))
        end
        
        # Parse cross-references to other textbooks
        for m in eachmatch(r"([A-Z]+-\d{3}),?\s*(?:Chapter\s+(\d+)|Theorem\s+(\d+\.\d+)|Definition\s+(\d+\.\d+))", line)
            ref_textbook = m.captures[1]
            if ref_textbook != textbook_id
                # Create edge from current context to referenced concept
                if m.captures[3] !== nothing
                    target_id = "$(ref_textbook)-thm-$(m.captures[3])"
                    # We don't know if this node exists yet, but we record the edge
                    push!(edges, ConceptEdge(
                        "$(textbook_id)-ch$(chapter_num)",
                        target_id,
                        :cross_ref
                    ))
                elseif m.captures[4] !== nothing
                    target_id = "$(ref_textbook)-def-$(m.captures[4])"
                    push!(edges, ConceptEdge(
                        "$(textbook_id)-ch$(chapter_num)",
                        target_id,
                        :cross_ref
                    ))
                end
            end
        end
        
        # Parse "see Chapter N" internal references
        for m in eachmatch(r"(?:see|from|in)\s+Chapter\s+(\d+)", line)
            ref_ch = parse(Int, m.captures[1])
            if ref_ch != chapter_num
                push!(edges, ConceptEdge(
                    "$(textbook_id)-ch$(ref_ch)",
                    "$(textbook_id)-ch$(chapter_num)",
                    :depends
                ))
            end
        end
    end
    
    return nodes, edges
end

# ─────────────────────────── Main ───────────────────────────

function main()
    output_file = "output/concept-graph.json"
    for (i, arg) in enumerate(ARGS)
        if arg == "--output" && i < length(ARGS)
            output_file = ARGS[i+1]
        end
    end
    
    all_nodes = ConceptNode[]
    all_edges = ConceptEdge[]
    
    # Also create chapter-level nodes
    chapter_nodes = ConceptNode[]
    
    if !isdir(INPUT_DIR)
        println("ERROR: Input directory '$INPUT_DIR' not found")
        exit(1)
    end
    
    for tb_dir in sort(readdir(INPUT_DIR, join=true))
        isdir(tb_dir) || continue
        tb_id = basename(tb_dir)
        track = infer_track(tb_id)
        
        chapters = sort(filter(f -> endswith(f, ".md"), readdir(tb_dir)))
        for (ch_num, chfile) in enumerate(chapters)
            filepath = joinpath(tb_dir, chfile)
            
            # Create a chapter-level node
            content = read(filepath, String)
            m_title = match(r"^#\s+Chapter\s+\d+:\s+(.+)", content)
            ch_title = m_title !== nothing ? m_title.captures[1] : "Chapter $ch_num"
            push!(chapter_nodes, ConceptNode(
                "$(tb_id)-ch$(ch_num)", ch_title, :concept,
                track, tb_id, ch_num, "", 0
            ))
            
            # Parse for definitions, theorems, etc.
            nodes, edges = parse_chapter(filepath, tb_id, ch_num)
            append!(all_nodes, nodes)
            append!(all_edges, edges)
        end
        
        println("  ✓ $(tb_id): $(length(chapters)) chapters parsed")
    end
    
    append!(all_nodes, chapter_nodes)
    
    # Deduplicate edges
    edge_set = Set{Tuple{String,String,Symbol}}()
    unique_edges = ConceptEdge[]
    for e in all_edges
        key = (e.source, e.target, e.type)
        if key ∉ edge_set
            push!(edge_set, key)
            push!(unique_edges, e)
        end
    end
    
    # Build output
    output = Dict(
        "generated" => string(Dates.now()),
        "stats" => Dict(
            "total_nodes" => length(all_nodes),
            "definitions" => count(n -> n.type == :definition, all_nodes),
            "theorems" => count(n -> n.type == :theorem, all_nodes),
            "algorithms" => count(n -> n.type == :algorithm, all_nodes),
            "chapters" => count(n -> n.type == :concept, all_nodes),
            "edges" => length(unique_edges),
        ),
        "nodes" => [
            Dict(
                "id" => n.id,
                "label" => n.label,
                "type" => string(n.type),
                "track" => n.track,
                "textbook" => n.textbook,
                "chapter" => n.chapter,
                "section" => n.section,
            )
            for n in all_nodes
        ],
        "edges" => [
            Dict(
                "source" => e.source,
                "target" => e.target,
                "type" => string(e.type),
            )
            for e in unique_edges
        ],
    )
    
    mkpath(dirname(output_file))
    open(output_file, "w") do io
        JSON3.pretty(io, output)
    end
    
    println("\n" * "="^50)
    println("Concept graph written to $output_file")
    println("  Nodes: $(length(all_nodes)) ($(output["stats"]["definitions"]) defs, $(output["stats"]["theorems"]) thms, $(output["stats"]["algorithms"]) algs)")
    println("  Edges: $(length(unique_edges))")
    println("="^50)
end

main()
