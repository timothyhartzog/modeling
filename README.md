# Master Course of Study — Universal Modeling Mastery

Parallel batch generation pipeline for 52 graduate-level textbooks (438 chapters) covering biostatistics, geospatial modeling, agent-based modeling, scientific machine learning, population dynamics, biomechanics, atmospheric science, and their common mathematical foundations.

## Quick Start

```bash
# Clone
cd ~/Documents/github
git clone https://github.com/timothyhartzog/modeling.git
cd modeling

# Install Julia dependencies
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
```

## Architecture

| File | Purpose |
|------|---------|
| `src/generate.jl` | Main orchestrator — parallel async API calls with resume |
| `src/api_client.jl` | Anthropic API wrapper with exponential backoff |
| `src/prompt_builder.jl` | Constructs per-chapter prompts from manifest JSON |
| `src/assemble_docx.jl` | Concatenates chapters → DOCX via pandoc |
| `src/validate.jl` | Post-generation quality checker — 6 per-chapter checks |
| `src/stats.jl` | Read-only progress dashboard — overall, by-track, by-textbook |
| `system_prompt.md` | Locked system prompt for consistent generation |
| `manifests/part1.json` | 24 textbooks, 212 chapters |
| `manifests/part2.json` | 28 textbooks, 226 chapters |
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

## Requirements

- Julia 1.10+
- Anthropic API key (Sonnet tier)
- pandoc (for DOCX conversion): `brew install pandoc`

## Cost Estimate

~438 chapters × ~8K tokens output = ~$18–26 total at Sonnet pricing.
