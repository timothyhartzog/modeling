# CLAUDE.md — Textbook Generation Pipeline

## Project Overview
Parallel batch generation of 52 graduate-level textbooks (438 chapters) for the Master Course of Study in Universal Modeling Mastery. Julia orchestrator calls Anthropic API with async concurrency, writes markdown chapters to disk, assembles into DOCX.

## Architecture
- `src/generate.jl` — Main orchestrator. Loads manifests, builds work queue, fires parallel API calls, tracks state.
- `src/api_client.jl` — Anthropic API wrapper. Claude Sonnet 4, 8192 max tokens, exponential backoff on 429/5xx.
- `src/prompt_builder.jl` — Constructs per-chapter prompts from manifest JSON. Each prompt includes textbook context, TOC, and detailed content specification.
- `src/assemble_docx.jl` — Post-generation. Concatenates per-chapter .md files into single textbook markdown, converts to DOCX via pandoc.
- `src/quarto_export.jl` — Quarto export. Reads assembled .md files, strips existing front-matter, writes Quarto-compatible .qmd files to output/generated/. Supports --stubs-only for CI.
- `system_prompt.md` — Locked system prompt for all API calls. Julia-only code, graduate rigor, USA sources.
- `state.json` — Progress tracker. Atomic write. Maps chapter keys ("CORE-001/ch01") to completion timestamps.
- `manifests/part1.json` — 24 textbooks, 212 chapters (core math + flagship domain courses).
- `manifests/part2.json` — 28 textbooks, 226 chapters (remaining domain tracks).

## Key Commands
```bash
# Install dependencies
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Calibration (3 chapters)
julia --project=. src/generate.jl --calibrate

# Full batch
julia --project=. src/generate.jl --concurrency 8 --resume

# Single textbook
julia --project=. src/generate.jl --textbook CORE-001

# Retry failures
julia --project=. src/generate.jl --retry-failed --resume

# Assemble DOCX
julia --project=. src/assemble_docx.jl

# Export to Quarto QMD
julia --project=. src/quarto_export.jl

# Export stubs only (for CI)
julia --project=. src/quarto_export.jl --stubs-only

# Dry run (show queue)
julia --project=. src/generate.jl --dry-run
```

## Content Standards
- Julia is the exclusive programming language for all code examples
- USA-based sources only for medical/clinical topics
- Exclude Bart D. Ehrman from all references
- Graduate-level rigor: proofs, definitions, theorems, worked examples
- 3,000–8,000 words per chapter, 5–10 exercises per chapter

## State
- Resume is safe: state.json tracks completed chapters, orchestrator skips them
- Ctrl+C is safe: state is written after each chapter completion
- Failed chapters logged in state.json with error messages

## Output Structure
```
output/
├── markdown/          # Per-chapter files
│   ├── CORE-001/
│   │   ├── ch01.md
│   │   └── ...
│   └── ...
├── assembled/         # Concatenated per-textbook markdown
│   ├── CORE-001.md
│   └── ...
└── docx/              # Final DOCX textbooks
    ├── CORE-001.docx
    └── ...
```
