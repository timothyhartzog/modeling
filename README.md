# Master Course of Study — Universal Modeling Mastery

Parallel batch generation pipeline for 52 graduate-level textbooks (438 chapters) covering biostatistics, geospatial modeling, agent-based modeling, scientific machine learning, population dynamics, biomechanics, atmospheric science, and their common mathematical foundations.

## Quick Start

```bash
# Clone
cd ~/Documents/github
git clone https://github.com/timothyhartzog/modeling.git
cd modeling

# Install Julia dependencies (uses pinned versions from Manifest.toml — do not run Pkg.update())
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Set API key
export ANTHROPIC_API_KEY="sk-ant-..."

# Calibration run (3 test chapters)
julia --project=. src/generate.jl --calibrate

# Review output/markdown/CORE-001/ch01.md, SCIML-001/ch03.md, PHYS-004/ch04.md
# Tune system_prompt.md if needed

# Full batch generation (~90 min at concurrency=8)
julia --project=. src/generate.jl --concurrency 8 --resume

# Assemble into DOCX textbooks
julia --project=. src/assemble_docx.jl

# Export to Quarto QMD for website
julia --project=. src/quarto_export.jl

# Preview website locally (requires Quarto)
cd output && quarto preview
```

## v2 Deployment (Full Pipeline)

```bash
# Full pipeline: activate v2 prompt → generate → validate → build interactive site
./deploy.sh

# Or step by step:
./deploy.sh --validate     # Check existing chapters against 16 v2 checks
./deploy.sh --generate     # Activate v2 prompt, calibrate, then batch generate
./deploy.sh --graph        # Build concept-graph.json from chapters
./deploy.sh --site         # Build Quarto site + install React component deps
./deploy.sh --status       # Dashboard of progress
./deploy.sh --deploy       # Publish to GitHub Pages

# Interactive demos (standalone dev server — opens at localhost:5173)
cd interactive
npm install
npm run dev

# Interactive Quarto preview (after ./deploy.sh --site)
cd output/quarto
quarto preview             # Opens at localhost:4200
```

## Architecture

| File | Purpose |
|------|---------|
| `src/generate.jl` | Main orchestrator — parallel async API calls with resume |
| `src/api_client.jl` | Anthropic API wrapper with exponential backoff |
| `src/prompt_builder.jl` | Constructs per-chapter prompts from manifest JSON |
| `src/assemble_docx.jl` | Concatenates chapters → DOCX via pandoc |
| `src/validate.jl` | Post-generation quality checker — 6 per-chapter checks |
| `src/validate_v2.jl` | Enhanced quality checker — 16 per-chapter checks with fix report |
| `src/stats.jl` | Read-only progress dashboard — overall, by-track, by-textbook |
| `src/quarto_export.jl` | Converts assembled markdown → Quarto QMD stubs for website |
| `src/quarto_interactive_export.jl` | Converts chapters → interactive Quarto QMD (v2) |
| `src/build_concept_graph.jl` | Parses chapters → concept-graph.json for navigator |
| `src/build_quarto_config.jl` | Regenerates output/_quarto.yml from manifests |
| `system_prompt.md` | Active system prompt for generation |
| `system_prompt_v2.md` | Enhanced v2 prompt (Bloom's, Pitfalls, Comp. Lab) |
| `manifests/part1.json` | 24 textbooks, 212 chapters |
| `manifests/part2.json` | 28 textbooks, 226 chapters |
| `interactive/` | React educational demos (Vite + D3 + Recharts) |
| `deploy.sh` | Full deployment orchestrator |
| `state.json` | Resume state — tracks completed/failed chapters |
| `CLAUDE.md` | Claude Code state continuity |

## CLI Options

### generate.jl
```
--concurrency N     Parallel API calls (default: 5, recommended: 8, max: 50)
--calibrate         Generate 3 test chapters only
--resume            Skip already-completed chapters
--retry-failed      Re-run only previously failed chapters
--textbook ID       Generate one textbook (e.g., CORE-001)
--chapter KEY       Regenerate specific chapter(s) by key (e.g., CORE-001/ch03); comma-separated for multiple
--force             Bypass completed-chapter filter for any mode (always regenerate)
--dry-run           Show work queue without generating
```

### validate.jl
```
--textbook ID            Validate one textbook only
--export-failures FILE   Write failed chapter keys to JSON for re-queuing
```

Exits with code 1 when any chapter fails a critical check (suitable for CI).

## Progress Dashboard

```bash
# Full status report (overall + by-track + failures + recent)
julia --project=. src/stats.jl

# Per-textbook chapter-level breakdown
julia --project=. src/stats.jl --by-textbook

# Machine-readable JSON output
julia --project=. src/stats.jl --json > progress.json
```

### Concurrency Guidelines

| Tier | Recommended | Notes |
|------|-------------|-------|
| Standard Sonnet | `--concurrency 8` | Safe default for most accounts |
| High-throughput | `--concurrency 20` | Maximum recommended; monitor for 429s |
| Hard cap | `--concurrency 50` | Automatically clamped; values above this are rejected |

Values above 50 are clamped with an error message. Values above 20 produce a warning.
The pipeline handles 429 rate-limit responses with exponential backoff, so lower concurrency
is often more efficient overall — fewer retries mean faster net throughput.

## Curriculum Coverage

- **Core Mathematics (16 textbooks)**: Real Analysis, Linear Algebra, Measure-Theoretic Probability, Scientific Computing, Functional Analysis, ODEs, PDEs, Bayesian Theory, Numerical Methods, Differential Geometry, Optimization
- **Biostatistics (8 textbooks)**: GLMs, Survival Analysis, Longitudinal Data, Causal Inference, Clinical Trials, High-Dimensional Stats, Epidemic Models, Spatial Epidemiology
- **Geospatial (5 textbooks)**: Geostatistics, Point Processes, Areal Data, Space-Time, Remote Sensing
- **Agent-Based Modeling (4 textbooks)**: ABM Foundations, Network Science, Mean-Field Theory, Game Theory
- **Scientific ML (5 textbooks)**: Deep Learning Theory, Neural DEs/UDEs/PINNs, Probabilistic ML, Automatic Differentiation, ML Inverse Problems
- **Population Dynamics (4 textbooks)**: Deterministic, Stochastic, Systems Biology, Demography
- **Physical Systems (4 textbooks)**: Continuum Mechanics, Fluid Dynamics, Biomechanics, Atmospheric/Climate
- **Cross-Cutting (5 textbooks)**: UQ, Inverse Problems, Dynamical Systems, Optimal Transport, Information Geometry, Multiscale Methods

## DOCX Reference Template

All 52 textbooks are styled using `templates/reference.docx`. This file is committed to the repository and defines heading styles, body font, code block formatting, page margins, and header/footer layout.

To regenerate or customise the template:

```bash
# Generate a fresh base template from pandoc defaults
pandoc --print-default-data-file reference.docx > templates/reference.docx

# Then open templates/reference.docx in Microsoft Word (or LibreOffice),
# modify the paragraph/character styles as needed, save, and commit.
```

If `templates/reference.docx` is absent at assembly time, `assemble_docx.jl` falls back to pandoc's built-in defaults with a warning.

## Dependency Management

`Manifest.toml` is committed to this repository to pin exact package versions for reproducibility. Always use `Pkg.instantiate()` to install dependencies — **do not** run `Pkg.update()` as that will upgrade packages to newer versions and may break compatibility.

```bash
# Correct: installs exact pinned versions
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Incorrect: upgrades to latest compatible versions (breaks reproducibility)
# julia --project=. -e 'using Pkg; Pkg.update()'
```

If you intentionally want to upgrade a dependency, run `Pkg.update("PackageName")`, review the diff in `Manifest.toml`, test thoroughly, and commit the updated lockfile.

## Requirements

- Julia 1.10+
- Anthropic API key (Sonnet tier)
- pandoc (for DOCX conversion): `brew install pandoc`

## Cost Estimate

~438 chapters × ~8K tokens output = ~$18–26 total at Sonnet pricing.
