# Week 1 — GitHub Copilot Workflow Guide (LOGIC)

Welcome to Week 1 of the LOGIC content area. This guide walks you through using GitHub Copilot effectively while working with the Universal Modeling Mastery pipeline for formal-logic content.

---

## Goals for Week 1

By the end of Week 1 you should be able to:

- [ ] Run the full generation pipeline for a single LOGIC chapter
- [ ] Use Copilot to review and extend Julia proof-sketch implementations
- [ ] Understand how Copilot's custom instructions (`.copilot/copilot-instructions.md`) shape its suggestions
- [ ] Submit your first validated chapter via the standard PR workflow

---

## Day 1 — Environment & Calibration

### 1. Verify your environment

```bash
julia --version          # ≥ 1.10 required
git --version
echo $ANTHROPIC_API_KEY  # should be non-empty
```

### 2. Instantiate Julia packages

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### 3. Run a calibration chapter

Generate the first LOGIC-area chapter as a smoke test:

```bash
julia --project=. src/generate.jl --calibrate
```

Review `output/markdown/CORE-001/ch01.md` for expected structure:
- Motivation section
- Formal Definition / Theorem / Proof blocks
- Worked example in Julia
- 5–10 exercises spanning Bloom's tiers

---

## Day 2 — Copilot for Proof Scaffolding

### Opening a chapter for editing

```bash
code output/markdown/CORE-001/ch01.md
```

### Suggested Copilot prompts (inline comments)

Paste these comments inside a Julia code block and let Copilot complete:

```julia
# Prove: the set of rational numbers is countably infinite.
# Strategy: construct a bijection Q → N using Cantor's pairing function.
```

```julia
# Implement a Turing machine simulator in Julia.
# State: Dict{Int,Tuple{Symbol,Int,Symbol}} mapping state → (write_symbol, move, next_state)
```

```julia
# Formalize the ε-δ definition of limit and verify a simple example.
# Return true if |f(x) - L| < ε for all x with 0 < |x - a| < δ.
```

### What Copilot does well here

- Filling in type signatures and docstrings for mathematical functions
- Generating boilerplate for proof-by-induction exercises
- Suggesting standard Julia idioms (`enumerate`, `zip`, broadcasting) for combinatorial arguments
- Expanding `# [FIGURE: ...]` placeholder comments into Makie.jl code

---

## Day 3 — Validation & Quality Checks

Run the project validator on your chapter:

```bash
julia --project=. src/validate.jl --textbook CORE-001
```

The validator checks:
1. Minimum word count (≥ 3,000 words)
2. At least one Julia code block
3. At least 5 exercises
4. Presence of `## References` section
5. No filler phrases
6. All cross-references resolve to existing chapters

Fix any failures Copilot suggests. The validator exits with code 1 on failures (suitable for CI).

---

## Day 4 — PR Workflow

### Commit your changes

```bash
git checkout -b logic/ch01-improvements
git add output/markdown/CORE-001/ch01.md
git commit -m "logic(CORE-001/ch01): improve proof scaffolding and exercises"
git push
```

### Open a PR

Follow the PR template in `.github/pull_request_template.md`. Key checklist items:
- [ ] No API keys exposed
- [ ] Validator passes
- [ ] Julia code is idiomatic

---

## Day 5 — Extending with a New Exercise

Use Copilot to add a Bloom's **Create**-tier exercise to a chapter:

1. Open the chapter in your editor
2. Scroll to the Exercises section
3. Add a comment: `# Exercise [N+1] — Create tier: design a Julia function that...`
4. Let Copilot generate the exercise stem and solution sketch
5. Review, refine, and commit

---

## Tips & Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Copilot suggests Python | Add `# Julia only` to your comment |
| Generated proof is hand-wavy | Ask: `# Provide a rigorous epsilon-delta proof` |
| Code doesn't run | Run `julia --project=. -e 'include("your_file.jl")'` to test |
| Missing references | Add `(Author, Year)` inline and a `## References` entry |
| Filler phrases crept in | Search for "In this section" and delete |

---

## Resources

- [Julia documentation](https://docs.julialang.org/)
- [DifferentialEquations.jl docs](https://docs.sciml.ai/DiffEqDocs/)
- Project system prompt: `system_prompt.md`
- Full CLI reference: `README.md`
