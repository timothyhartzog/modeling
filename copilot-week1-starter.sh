#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Universal Modeling Mastery — GitHub Copilot Week 1 Starter
#
# Usage:
#   chmod +x copilot-week1-starter.sh
#   ./copilot-week1-starter.sh
#
# What this script does:
#   1. Checks required dependencies (Julia, Git)
#   2. Instantiates the Julia package environment
#   3. Scaffolds the content/LOGIC/ content area
#   4. Verifies Copilot guide files are in place
#   5. Prints the Week 1 action plan
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ─── Color helpers ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()   { echo -e "${RED}[ERR ]${NC}  $1"; }
step()  { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}"; }
banner(){ echo -e "${CYAN}$1${NC}"; }

# ─── Banner ────────────────────────────────────────────────────────────────
echo ""
banner "  ╔══════════════════════════════════════════════════════════╗"
banner "  ║   Universal Modeling Mastery — Copilot Week 1 Starter   ║"
banner "  ║   Mathematical Logic & Formal Reasoning (LOGIC)         ║"
banner "  ╚══════════════════════════════════════════════════════════╝"
echo ""

# ─── 1. Dependency checks ──────────────────────────────────────────────────
step "Checking dependencies"

MISSING=0

# Julia
if command -v julia &>/dev/null; then
    JULIA_VER=$(julia --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    JULIA_MAJOR=$(echo "$JULIA_VER" | cut -d. -f1)
    JULIA_MINOR=$(echo "$JULIA_VER" | cut -d. -f2)
    if [ "$JULIA_MAJOR" -ge 1 ] && [ "$JULIA_MINOR" -ge 10 ]; then
        ok "Julia $JULIA_VER"
    else
        warn "Julia $JULIA_VER found but ≥ 1.10 is recommended"
    fi
else
    err "Julia not found. Install from https://julialang.org/downloads/"
    MISSING=$((MISSING + 1))
fi

# Git
if command -v git &>/dev/null; then
    GIT_VER=$(git --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    ok "Git $GIT_VER"
else
    err "Git not found. Install from https://git-scm.com/"
    MISSING=$((MISSING + 1))
fi

# Anthropic API key (optional for week 1, but warn)
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    ok "ANTHROPIC_API_KEY is set"
else
    warn "ANTHROPIC_API_KEY not set — chapter generation will fail."
    warn "Set it with: export ANTHROPIC_API_KEY=\"sk-ant-...\""
fi

# pandoc (optional)
if command -v pandoc &>/dev/null; then
    PANDOC_VER=$(pandoc --version | head -1)
    ok "$PANDOC_VER"
else
    warn "pandoc not found — DOCX assembly won't work (optional for week 1)."
fi

if [ "$MISSING" -gt 0 ]; then
    err "$MISSING required dependency/dependencies missing. Fix them and re-run."
    exit 1
fi

# ─── 2. Julia environment ──────────────────────────────────────────────────
step "Setting up Julia environment"

if [ -f "Project.toml" ]; then
    julia --project=. -e 'using Pkg; Pkg.instantiate()' 2>&1
    ok "Julia packages instantiated"
else
    err "Project.toml not found. Are you running from the repository root?"
    exit 1
fi

# ─── 3. Scaffold content/LOGIC/ ────────────────────────────────────────────
step "Scaffolding content/LOGIC/ content area"

LOGIC_DIR="$SCRIPT_DIR/content/LOGIC"

for subdir in exercises proofs notes; do
    if [ ! -d "$LOGIC_DIR/$subdir" ]; then
        mkdir -p "$LOGIC_DIR/$subdir"
        ok "Created $LOGIC_DIR/$subdir/"
    else
        info "$LOGIC_DIR/$subdir/ already exists"
    fi
done

# Seed exercises directory with a starter file
EXERCISES_STARTER="$LOGIC_DIR/exercises/week1_starter.jl"
if [ ! -f "$EXERCISES_STARTER" ]; then
    cat > "$EXERCISES_STARTER" << 'JULIA_EOF'
# Week 1 Starter Exercises — Mathematical Logic (LOGIC)
# Run with: julia --project=. content/LOGIC/exercises/week1_starter.jl

# ── Exercise 1 (Apply) ────────────────────────────────────────────────────
# Implement a truth-table evaluator for propositional formulas.
# A formula is represented as a function Bool... -> Bool.

"""
    truth_table(f, n::Int) -> Matrix{Bool}

Print and return the truth table for an n-variable Boolean function `f`.
Rows enumerate all 2^n combinations of truth values.
"""
function truth_table(f, n::Int)::Matrix{Bool}
    rows = 2^n
    tbl = Matrix{Bool}(undef, rows, n + 1)
    for i in 0:(rows - 1)
        vals = [(i >> (n - k - 1)) & 1 == 1 for k in 0:(n - 1)]
        tbl[i + 1, 1:n] .= vals
        tbl[i + 1, n + 1] = f(vals...)
    end
    return tbl
end

# Example: p ∧ q
f_and(p::Bool, q::Bool) = p && q
println("Truth table for p ∧ q:")
display(truth_table(f_and, 2))

# ── Exercise 2 (Apply) ────────────────────────────────────────────────────
# Cantor pairing function: bijection N×N → N

"""
    cantor_pair(m::Int, n::Int) -> Int

Cantor pairing of non-negative integers `m` and `n`.
"""
function cantor_pair(m::Int, n::Int)::Int
    @assert m >= 0 && n >= 0 "Arguments must be non-negative"
    (m + n) * (m + n + 1) ÷ 2 + m
end

"""
    cantor_unpair(z::Int) -> Tuple{Int,Int}

Inverse of `cantor_pair`: recover (m, n) from the pairing `z`.
"""
function cantor_unpair(z::Int)::Tuple{Int,Int}
    w = floor(Int, (sqrt(8z + 1) - 1) / 2)
    t = (w^2 + w) ÷ 2
    m = z - t
    n = w - m
    return (m, n)
end

println("\nCantor pairing examples:")
for (m, n) in [(0,0), (1,0), (0,1), (2,3)]
    z = cantor_pair(m, n)
    m2, n2 = cantor_unpair(z)
    @assert (m2, n2) == (m, n) "Round-trip failed for ($m, $n)"
    println("  cantor_pair($m, $n) = $z  →  unpair = ($m2, $n2) ✓")
end

# ── Exercise 3 (Analyze) ──────────────────────────────────────────────────
# Show that the set of finite binary strings is countably infinite
# by constructing an explicit enumeration.

"""
    enumerate_binary_strings(n::Int) -> Vector{String}

Return the first `n` binary strings in length-lexicographic order.
"""
function enumerate_binary_strings(n::Int)::Vector{String}
    result = String[]
    k = 0
    len = 0
    while length(result) < n
        for i in 0:(2^len - 1)
            len == 0 && (push!(result, "ε"); break)  # empty string
            push!(result, string(i, base=2, pad=len))
            length(result) >= n && break
        end
        len += 1
    end
    return result[1:min(n, length(result))]
end

println("\nFirst 10 binary strings (length-lex order):")
println(enumerate_binary_strings(10))

println("\nAll Week 1 exercises completed successfully. ✓")
JULIA_EOF
    ok "Created $EXERCISES_STARTER"
fi

# ─── 4. Verify Copilot guide files ─────────────────────────────────────────
step "Verifying Copilot guide files"

COPILOT_DIR="$LOGIC_DIR/.copilot"
GUIDES=("README.md" "week1-guide.md" "copilot-instructions.md")

ALL_OK=true
for guide in "${GUIDES[@]}"; do
    if [ -f "$COPILOT_DIR/$guide" ]; then
        ok "$COPILOT_DIR/$guide"
    else
        err "Missing: $COPILOT_DIR/$guide"
        ALL_OK=false
    fi
done

if [ "$ALL_OK" = false ]; then
    err "Some Copilot guide files are missing. Re-clone or restore from git."
    exit 1
fi

# ─── 5. Quick smoke test ──────────────────────────────────────────────────
step "Running Week 1 Julia starter exercises"

julia --project=. content/LOGIC/exercises/week1_starter.jl 2>&1
ok "Starter exercises passed"

# ─── 6. Print next steps ───────────────────────────────────────────────────
step "Week 1 Action Plan"

echo ""
echo -e "  ${BOLD}Step 1 — Read the Week 1 guide${NC}"
echo -e "  ${CYAN}cat content/LOGIC/.copilot/week1-guide.md${NC}"
echo ""
echo -e "  ${BOLD}Step 2 — Review Copilot custom instructions${NC}"
echo -e "  ${CYAN}cat content/LOGIC/.copilot/copilot-instructions.md${NC}"
echo ""
echo -e "  ${BOLD}Step 3 — Generate a calibration chapter${NC}"
echo -e "  ${CYAN}julia --project=. src/generate.jl --calibrate${NC}"
echo ""
echo -e "  ${BOLD}Step 4 — Review the generated chapter${NC}"
echo -e "  ${CYAN}cat output/markdown/CORE-001/ch01.md${NC}"
echo ""
echo -e "  ${BOLD}Step 5 — Run the exercises you just saw pass${NC}"
echo -e "  ${CYAN}julia --project=. content/LOGIC/exercises/week1_starter.jl${NC}"
echo ""
echo -e "  ${BOLD}Step 6 — Validate with the project checker${NC}"
echo -e "  ${CYAN}julia --project=. src/validate.jl --textbook CORE-001${NC}"
echo ""
echo -e "  ${GREEN}${BOLD}Have a great Week 1! 🚀${NC}"
echo ""
