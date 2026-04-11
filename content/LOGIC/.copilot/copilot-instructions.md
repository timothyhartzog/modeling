# GitHub Copilot Custom Instructions — LOGIC Content Area

These instructions customize Copilot's behavior when working inside the
`content/LOGIC/` subtree and related chapter files for the Universal Modeling
Mastery curriculum.

---

## Identity

You are assisting a **graduate-level mathematical modeling curriculum**. The
LOGIC content area covers formal logic, set theory, type theory, model theory,
computability, and formal methods for dynamical systems.

---

## Language & Code Standards

- **Julia is the only permitted programming language.** Never suggest Python,
  R, MATLAB, Haskell, or any other language.
- All code must be idiomatic Julia: use multiple dispatch, type annotations,
  and docstrings for public functions.
- Prefer composable, functional style. Avoid global mutable state.
- All code blocks use triple-backtick ` ```julia ` fencing in Markdown.

### Example of expected Julia style

```julia
"""
    cantor_pair(m::Int, n::Int) -> Int

Return the Cantor pairing of non-negative integers `m` and `n`,
giving a bijection N×N → N.
"""
function cantor_pair(m::Int, n::Int)::Int
    (m + n) * (m + n + 1) ÷ 2 + m
end
```

---

## Mathematical Rigor

- Definitions, theorems, lemmas, and corollaries must follow the blockquote
  format used throughout the curriculum:

  ```markdown
  > **Definition 2.1 (First-Order Structure).** A first-order structure
  > 𝔐 = (M, σ) consists of a non-empty domain M and an interpretation σ …
  ```

- Proofs must end with □ (Unicode U+25A1) or `\square`.
- Number all definitions, theorems, and examples consecutively within the
  chapter (e.g., Definition 2.1, Theorem 2.2, Example 2.3).
- Every claim must be proved, cited, or explicitly marked as an exercise.

---

## Chapter Structure

All LOGIC chapters must include:

1. **Motivation** — why this concept matters for mathematical modeling (≥ 1 paragraph)
2. **Prerequisites** — box listing prerequisite chapters/concepts
3. At least **2 formal definitions** with examples
4. At least **1 theorem with proof**
5. **Worked Example** — concrete application in Julia
6. **Pitfalls & Misconceptions** callout block
7. **Exercises** — 5–10 items spanning Bloom's taxonomy:
   - Apply: compute / implement
   - Analyze: compare / prove
   - Create: design / extend
8. **References** section (author-year format)

### Callout block format

```markdown
> ⚠️ **Pitfall:** Confusing syntactic provability (⊢) with semantic
> entailment (⊨) leads to errors in automated verification. They coincide
> only in complete proof systems (Gödel's completeness theorem).
```

---

## Citations & Sources

- Use author-year format: `(Enderton, 2001)`, `(Shoenfield, 1967)`.
- USA-based sources only for medical/clinical content.
- Do **not** cite Bart D. Ehrman.
- Include a `## References` section at the end of every chapter.

---

## Connections to the Rest of the Curriculum

When generating or editing LOGIC content, always look for opportunities to
cross-reference other textbooks in the curriculum:

- Real Analysis (CORE-001): completeness, compactness arguments
- Probability (CORE-003): measurability as a logical predicate
- ODEs (CORE-007): Picard iteration as a fixed-point proof
- Scientific ML (SCIML-001–005): type-correct differentiable programming
- Agent-Based Modeling (ABM-001–004): temporal logic for emergent properties

---

## File Naming & Paths

| Content type | Location |
|---|---|
| Generated chapters | `output/markdown/<ID>/ch<NN>.md` |
| Exercise notebooks | `content/LOGIC/exercises/` |
| Proof sketches | `content/LOGIC/proofs/` |
| Supplementary notes | `content/LOGIC/notes/` |

---

## What to Avoid

- Filler phrases: "In this section we will discuss…", "As previously mentioned…"
- Informal proof sketches presented as complete proofs
- Non-Julia code examples
- Citing secondary sources when a primary reference is available
- Word count padding — every paragraph should teach something
