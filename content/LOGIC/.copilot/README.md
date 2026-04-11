# LOGIC — Mathematical Logic & Formal Reasoning
## Content Area Overview

This directory contains GitHub Copilot guidance for the **LOGIC** content area of the Master Course of Study in Universal Modeling Mastery.

**LOGIC** covers the foundational formal machinery that underpins all mathematical modeling:

| Module | Topics |
|--------|--------|
| Propositional & First-Order Logic | Syntax, semantics, proof theory, completeness |
| Set Theory | ZFC axioms, ordinals, cardinals, transfinite induction |
| Type Theory & Proof Assistants | Dependent types, Curry-Howard, Lean/Coq integration |
| Model Theory for Modelers | Structures, satisfaction, compactness, Löwenheim-Skolem |
| Computability & Complexity | Turing machines, decidability, complexity classes |
| Formal Methods for Dynamical Systems | Temporal logic, model checking, hybrid automata |

---

## Repository Layout

```
content/LOGIC/
├── .copilot/                  ← Copilot guides (you are here)
│   ├── README.md              ← This file
│   ├── week1-guide.md         ← Week 1 Copilot workflow
│   └── copilot-instructions.md← Custom Copilot instructions
├── exercises/                 ← Julia exercise notebooks
├── proofs/                    ← Formal proof sketches
└── notes/                     ← Supplementary lecture notes
```

---

## Quick Start

```bash
# Run the starter script first if you haven't already
chmod +x copilot-week1-starter.sh
./copilot-week1-starter.sh

# Then open the Week 1 guide
cat content/LOGIC/.copilot/week1-guide.md

# Copilot custom instructions are in
cat content/LOGIC/.copilot/copilot-instructions.md
```

---

## Connection to the Curriculum

LOGIC prerequisites underlie every textbook in the curriculum:

- **CORE-001 (Real Analysis)**: completeness arguments, formal epsilon-delta proofs
- **CORE-003 (Measure-Theoretic Probability)**: σ-algebra axioms, measurability conditions
- **CORE-007 (ODEs)**: existence/uniqueness proofs via Picard iteration (fixed-point logic)
- **SCIML-001 (Neural DEs)**: differentiable programming requires type-correct composition
- **ABM-001 (Agent-Based Modeling)**: temporal logic for specifying emergent behavior

---

## Contributing

All Julia code in this content area must follow the project's standards:
- Julia is the **exclusive** programming language
- Use `docstrings`, type annotations, and explanatory comments
- Exercises should span Bloom's taxonomy tiers (Apply / Analyze / Create)
