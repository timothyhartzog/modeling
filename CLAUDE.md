# CLAUDE.md — Textbook Generation Pipeline

## Project Overview
Parallel batch generation of 52 graduate-level textbooks (438 chapters) for the Master Course of Study in Universal Modeling Mastery. Julia orchestrator calls Anthropic API with async concurrency, writes markdown chapters to disk, assembles into DOCX.

## Architecture
- `src/generate.jl` — Main orchestrator. Loads manifests, builds work queue, fires parallel API calls, tracks state.
- `src/api_client.jl` — Anthropic API wrapper. Claude Sonnet 4, 8192 max tokens, exponential backoff on 429/5xx.
- `src/prompt_builder.jl` — Constructs per-chapter prompts from manifest JSON. Each prompt includes textbook context, TOC, and detailed content specification.
- `src/assemble_docx.jl` — Post-generation. Concatenates per-chapter .md files into single textbook markdown, converts to DOCX/PDF/HTML via pandoc.
- `src/validate.jl` — Post-generation quality checker. Reads every generated .md and runs 6 per-chapter checks; prints structured report; exports failures to JSON for re-queuing.
- `src/stats.jl` — Read-only progress dashboard. Shows overall/by-track/by-textbook completion, failed chapters, and recent completions.
- `src/build_quarto_config.jl` — Regenerates `output/_quarto.yml` from the manifests. Run this whenever a manifest is updated to keep sidebar titles in sync.
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

# Regenerate a single chapter (always re-runs regardless of state)
julia --project=. src/generate.jl --chapter CORE-001/ch03

# Regenerate multiple specific chapters (comma-separated)
julia --project=. src/generate.jl --chapter CORE-001/ch03,BIO-002/ch07

# Force regenerate all chapters in a textbook (ignore completed state)
julia --project=. src/generate.jl --textbook CORE-001 --force

# Assemble DOCX (default)
julia --project=. src/assemble_docx.jl

# Assemble PDF only
julia --project=. src/assemble_docx.jl --format pdf

# Assemble HTML single-file only
julia --project=. src/assemble_docx.jl --format html

# Assemble all formats (DOCX + PDF + HTML)
julia --project=. src/assemble_docx.jl --format all

# Regenerate _quarto.yml from manifests (run after any manifest change)
julia --project=. src/build_quarto_config.jl

# Export to Quarto QMD
julia --project=. src/quarto_export.jl

# Export stubs only (for CI)
julia --project=. src/quarto_export.jl --stubs-only

# Validate all chapters
julia --project=. src/validate.jl

# Validate one textbook
julia --project=. src/validate.jl --textbook CORE-001

# Export failures to JSON for retry
julia --project=. src/validate.jl --export-failures failures.json

# Dry run (show queue)
julia --project=. src/generate.jl --dry-run

# Progress dashboard
julia --project=. src/stats.jl

# Per-textbook breakdown
julia --project=. src/stats.jl --by-textbook

# JSON output
julia --project=. src/stats.jl --json > progress.json
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

## v2 Enhancements (April 2026)

### Enhanced System Prompt (system_prompt_v2.md)
- Motivation sections, Prerequisites boxes, Pitfalls & Misconceptions callouts
- Bloom's taxonomy exercises (Apply/Analyze/Create tiers)
- Computational Laboratory sections (30+ line integrated Julia examples)
- Code quality standards: docstrings, type annotations, explanatory comments
- Activate: `cp system_prompt_v2.md system_prompt.md` or use `./deploy.sh`

### Enhanced Validation (src/validate_v2.jl)
- 16 checks per chapter (up from 6): code parsability via Meta.parse(), cross-reference
  integrity, exercise tier distribution, pitfalls presence, computational lab detection,
  filler phrase detection, non-Julia code detection, worked example counts
- `--fix-report report.md` generates actionable fix list

### Interactive Educational Demos (interactive/)
- `concept-map.jsx` — D3.js force-directed knowledge graph, 55+ nodes, 8 tracks
- `phase-portrait-explorer.jsx` — ODE phase portraits with click-to-place ICs, RK4
- `gradient-descent-visualizer.jsx` — 4 algorithms × 4 test functions, contour plots
- `distribution-playground.jsx` — 6 distributions, real-time PDF/CDF/histogram
- `quiz-engine.jsx` — Spaced repetition, Bloom's tiers, track filtering
- `proof-explorer.jsx` — Collapsible proofs, intuition/formal toggle, exercises

### Concept Graph (src/build_concept_graph.jl)
- Parses all chapters → extracts definitions, theorems, algorithms, cross-refs
- Outputs concept-graph.json consumed by the React concept map navigator

### Quarto Interactive Export (src/quarto_interactive_export.jl)
- Converts static .md → executable .qmd with `{julia}` computation cells
- Adds callout blocks, tabset panels for exercises, setup cells

### Modeling Challenge Labs (labs/)
- 5 multi-textbook capstone labs: Clinical Trial Pipeline, Equation Discovery (UDE+SINDy),
  Spatial Disease Spread, Blood Flow Simulation, Bayesian Model Selection

### Deployment Script (deploy.sh)
```bash
./deploy.sh              # Full pipeline: generate → validate → build site
./deploy.sh --validate   # Run v2 validation only
./deploy.sh --generate   # Activate v2 prompt and regenerate
./deploy.sh --site       # Build Quarto site + React components
./deploy.sh --graph      # Rebuild concept graph
./deploy.sh --status     # Show project dashboard
./deploy.sh --deploy     # Publish to GitHub Pages
```

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
├── docx/              # Final DOCX textbooks
│   ├── CORE-001.docx
│   └── ...
├── pdf/               # Final PDF textbooks (--format pdf)
│   ├── CORE-001.pdf
│   └── ...
├── html/              # Final HTML textbooks (--format html)
│   ├── CORE-001.html
│   └── ...
├── quarto/            # Interactive Quarto QMD site
│   ├── _quarto.yml
│   └── CORE-001/
│       └── ch01.qmd
├── concept-graph.json # Knowledge graph for navigator
└── fix-report.md      # Validation failures
interactive/           # React educational components
labs/                  # Capstone challenge labs
```
