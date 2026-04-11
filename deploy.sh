#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# Universal Modeling Mastery — Full Deployment Script
# Sets up the interactive educational platform: Quarto site with
# React demos, validation pipeline, concept graph, and quiz engine.
# ═══════════════════════════════════════════════════════════════════
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh              # Full setup
#   ./deploy.sh --validate   # Run validation only
#   ./deploy.sh --generate   # Regenerate chapters with v2 prompt
#   ./deploy.sh --site       # Build Quarto site only
#   ./deploy.sh --graph      # Rebuild concept graph only
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ─────────────────────────── Colors ───────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo -e "\n${CYAN}═══ $1 ═══${NC}"; }

# ─────────────────────────── Dependency Checks ───────────────────────────

check_dependencies() {
    step "Checking dependencies"
    
    # Julia
    if command -v julia &>/dev/null; then
        JULIA_VERSION=$(julia --version 2>&1 | grep -oP '\d+\.\d+\.\d+')
        ok "Julia $JULIA_VERSION"
    else
        err "Julia not found. Install from https://julialang.org/downloads/"
        exit 1
    fi
    
    # Node.js (for React component bundling)
    if command -v node &>/dev/null; then
        NODE_VERSION=$(node --version)
        ok "Node.js $NODE_VERSION"
    else
        warn "Node.js not found. React components won't be bundled."
        warn "Install from https://nodejs.org/ or: brew install node"
    fi
    
    # Quarto
    if command -v quarto &>/dev/null; then
        QUARTO_VERSION=$(quarto --version 2>&1)
        ok "Quarto $QUARTO_VERSION"
    else
        warn "Quarto not found. Site won't build."
        warn "Install from https://quarto.org/docs/get-started/"
    fi
    
    # pandoc
    if command -v pandoc &>/dev/null; then
        PANDOC_VERSION=$(pandoc --version | head -1)
        ok "$PANDOC_VERSION"
    else
        warn "pandoc not found. DOCX assembly won't work."
        warn "Install: brew install pandoc"
    fi
    
    # Anthropic API key
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        ok "ANTHROPIC_API_KEY set"
    else
        warn "ANTHROPIC_API_KEY not set. Chapter generation will fail."
        warn "Export it: export ANTHROPIC_API_KEY=\"sk-ant-...\""
    fi
}

# ─────────────────────────── Julia Environment ───────────────────────────

setup_julia() {
    step "Setting up Julia environment"
    julia --project=. -e 'using Pkg; Pkg.instantiate()' 2>&1
    ok "Julia packages installed"
}

# ─────────────────────────── Activate v2 System Prompt ───────────────────

activate_v2_prompt() {
    step "Activating v2 system prompt"
    
    if [ -f "system_prompt.md" ] && [ -f "system_prompt_v2.md" ]; then
        # Backup original
        if [ ! -f "system_prompt_v1_backup.md" ]; then
            cp system_prompt.md system_prompt_v1_backup.md
            ok "Backed up original prompt → system_prompt_v1_backup.md"
        fi
        
        # Replace with v2
        cp system_prompt_v2.md system_prompt.md
        ok "system_prompt.md updated to v2"
        info "Changes: +Motivation sections, +Prerequisites boxes, +Pitfalls callouts"
        info "         +Bloom's exercises, +Computational Lab, +Code quality standards"
    else
        warn "system_prompt_v2.md not found"
    fi
}

# ─────────────────────────── Calibration Run ───────────────────────────

run_calibration() {
    step "Running calibration (3 test chapters with v2 prompt)"
    
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        err "ANTHROPIC_API_KEY not set. Skipping calibration."
        return 1
    fi
    
    julia --project=. src/generate.jl --calibrate 2>&1
    ok "Calibration complete. Review output/markdown/ for quality."
    info "Check for: Motivation section, Pitfalls callouts, Bloom's exercises"
}

# ─────────────────────────── Full Generation ───────────────────────────

run_generation() {
    step "Running full chapter generation"
    
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        err "ANTHROPIC_API_KEY not set."
        return 1
    fi
    
    local CONCURRENCY="${1:-8}"
    info "Concurrency: $CONCURRENCY"
    info "Estimated time: ~90 min at concurrency 8"
    
    julia --project=. src/generate.jl --concurrency "$CONCURRENCY" --resume 2>&1
    ok "Generation complete"
}

# ─────────────────────────── Validation ───────────────────────────

run_validation() {
    step "Running v2 validation (16 checks per chapter)"
    
    julia --project=. src/validate_v2.jl --fix-report output/fix-report.md 2>&1
    local EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        ok "All chapters passed validation"
    else
        warn "Some chapters have issues. See output/fix-report.md"
        info "To retry failed chapters: julia --project=. src/generate.jl --retry-failed"
    fi
    
    return $EXIT_CODE
}

# ─────────────────────────── Concept Graph ───────────────────────────

build_concept_graph() {
    step "Building concept graph from chapters"
    
    julia --project=. src/build_concept_graph.jl --output output/concept-graph.json 2>&1
    
    if [ -f "output/concept-graph.json" ]; then
        local NODES=$(python3 -c "import json; d=json.load(open('output/concept-graph.json')); print(d['stats']['total_nodes'])" 2>/dev/null || echo "?")
        local EDGES=$(python3 -c "import json; d=json.load(open('output/concept-graph.json')); print(d['stats']['edges'])" 2>/dev/null || echo "?")
        ok "Concept graph: $NODES nodes, $EDGES edges → output/concept-graph.json"
    else
        warn "Concept graph generation failed"
    fi
}

# ─────────────────────────── DOCX Assembly ───────────────────────────

assemble_docx() {
    step "Assembling DOCX textbooks"
    
    julia --project=. src/assemble_docx.jl 2>&1
    
    local COUNT=$(find output/docx -name "*.docx" 2>/dev/null | wc -l)
    ok "Assembled $COUNT DOCX textbooks → output/docx/"
}

# ─────────────────────────── Quarto Interactive Export ───────────────

build_quarto() {
    step "Converting chapters to interactive Quarto QMD"
    
    julia --project=. src/quarto_interactive_export.jl 2>&1
    ok "Quarto QMD files generated → output/quarto/"
}

# ─────────────────────────── React Components Setup ───────────────────

setup_react_components() {
    step "Setting up interactive React components"
    
    if ! command -v node &>/dev/null; then
        warn "Node.js not available. Skipping React setup."
        return 0
    fi
    
    # Create package.json for the interactive components
    if [ ! -f "interactive/package.json" ]; then
        cat > interactive/package.json << 'PACKAGE_EOF'
{
  "name": "modeling-interactive",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "d3": "^7.8.5",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "recharts": "^2.10.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.0",
    "vite": "^5.0.0"
  }
}
PACKAGE_EOF
        info "Created interactive/package.json"
    fi
    
    # Create Vite config
    if [ ! -f "interactive/vite.config.js" ]; then
        cat > interactive/vite.config.js << 'VITE_EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  base: '/modeling/interactive/',
  build: {
    outDir: '../output/_site/interactive',
    rollupOptions: {
      input: {
        'concept-map': './pages/concept-map.html',
        'phase-portrait': './pages/phase-portrait.html',
        'gradient-descent': './pages/gradient-descent.html',
        'distribution': './pages/distribution.html',
        'quiz': './pages/quiz.html',
        'proof-explorer': './pages/proof-explorer.html',
      }
    }
  }
})
VITE_EOF
        info "Created interactive/vite.config.js"
    fi
    
    # Create entry pages for each component
    mkdir -p interactive/pages
    
    for COMPONENT in concept-map phase-portrait-explorer gradient-descent-visualizer distribution-playground quiz-engine proof-explorer; do
        local SHORT=$(echo "$COMPONENT" | sed 's/-explorer//' | sed 's/-visualizer//' | sed 's/-playground//' | sed 's/-engine//')
        local PAGE="interactive/pages/${SHORT}.html"
        
        if [ ! -f "$PAGE" ]; then
            cat > "$PAGE" << HTML_EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Modeling Mastery — ${COMPONENT}</title>
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600;700&display=swap" rel="stylesheet">
  <style>* { margin: 0; padding: 0; box-sizing: border-box; }</style>
</head>
<body>
  <div id="root"></div>
  <script type="module">
    import React from 'react'
    import { createRoot } from 'react-dom/client'
    import App from '../${COMPONENT}.jsx'
    createRoot(document.getElementById('root')).render(React.createElement(App))
  </script>
</body>
</html>
HTML_EOF
        fi
    done
    
    info "Installing npm dependencies..."
    cd interactive
    npm install 2>&1 | tail -3
    cd ..
    
    ok "React components ready. Run: cd interactive && npm run dev"
}

# ─────────────────────────── Quarto Site Build ───────────────────────────

build_site() {
    step "Building Quarto website"
    
    if ! command -v quarto &>/dev/null; then
        warn "Quarto not installed. Skipping site build."
        return 0
    fi
    
    cd output/quarto
    quarto render 2>&1 | tail -5
    cd "$SCRIPT_DIR"
    
    ok "Site built → output/quarto/_site/"
    info "Preview: cd output/quarto && quarto preview"
}

# ─────────────────────────── GitHub Pages Deploy ───────────────────────────

deploy_pages() {
    step "Deploying to GitHub Pages"
    
    if [ ! -d "output/quarto/_site" ]; then
        warn "Site not built yet. Run ./deploy.sh --site first."
        return 1
    fi
    
    # Check if gh-pages branch exists
    if git rev-parse --verify gh-pages &>/dev/null 2>&1; then
        info "gh-pages branch exists"
    else
        info "Creating gh-pages branch"
        git checkout --orphan gh-pages
        git rm -rf . 2>/dev/null || true
        git commit --allow-empty -m "Initialize gh-pages"
        git checkout main
    fi
    
    # Use quarto publish if available
    if command -v quarto &>/dev/null; then
        cd output/quarto
        quarto publish gh-pages --no-browser 2>&1 | tail -3
        cd "$SCRIPT_DIR"
        ok "Published to GitHub Pages"
    else
        warn "Quarto not available for publishing"
    fi
}

# ─────────────────────────── Progress Dashboard ───────────────────────────

show_status() {
    step "Project Status Dashboard"
    
    # Chapter counts
    local TOTAL_MD=$(find output/markdown -name "*.md" 2>/dev/null | wc -l)
    local TOTAL_QMD=$(find output/quarto -name "*.qmd" 2>/dev/null | wc -l)
    local TOTAL_DOCX=$(find output/docx -name "*.docx" 2>/dev/null | wc -l)
    
    echo ""
    echo "  Chapters generated:  $TOTAL_MD / 438"
    echo "  Quarto QMD files:    $TOTAL_QMD"
    echo "  DOCX textbooks:      $TOTAL_DOCX"
    echo ""
    
    # Interactive components
    local JSX_COUNT=$(find interactive -name "*.jsx" 2>/dev/null | wc -l)
    echo "  React components:    $JSX_COUNT"
    
    # Concept graph
    if [ -f "output/concept-graph.json" ]; then
        echo "  Concept graph:       ✓ exists"
    else
        echo "  Concept graph:       ✗ not built"
    fi
    
    # Labs
    local LAB_COUNT=$(grep -c "^# Lab" labs/MODELING_CHALLENGE_LABS.md 2>/dev/null || echo 0)
    echo "  Challenge labs:      $LAB_COUNT"
    echo ""
    
    # System prompt version
    if grep -q "Bloom's Taxonomy" system_prompt.md 2>/dev/null; then
        echo "  System prompt:       v2 (enhanced)"
    else
        echo "  System prompt:       v1 (original)"
    fi
    
    echo ""
    
    # Run Julia stats if available
    if [ -f "src/stats.jl" ]; then
        julia --project=. src/stats.jl 2>/dev/null || true
    fi
}

# ─────────────────────────── Main ───────────────────────────

main() {
    echo ""
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║  Universal Modeling Mastery — Deployment Tool    ║"
    echo "  ║  52 Textbooks · 438 Chapters · Interactive Site  ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo ""
    
    local MODE="${1:---full}"
    
    case "$MODE" in
        --validate)
            check_dependencies
            setup_julia
            run_validation
            ;;
        --generate)
            check_dependencies
            setup_julia
            activate_v2_prompt
            run_calibration
            echo ""
            read -p "Calibration OK? Proceed with full generation? [y/N] " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                run_generation "${2:-8}"
            fi
            ;;
        --site)
            check_dependencies
            setup_julia
            build_quarto
            setup_react_components
            build_site
            ;;
        --graph)
            check_dependencies
            setup_julia
            build_concept_graph
            ;;
        --status)
            show_status
            ;;
        --deploy)
            deploy_pages
            ;;
        --full)
            check_dependencies
            setup_julia
            activate_v2_prompt
            run_calibration
            echo ""
            read -p "Calibration OK? Proceed with full generation? [y/N] " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                run_generation 8
            fi
            run_validation
            build_concept_graph
            assemble_docx
            build_quarto
            setup_react_components
            build_site
            show_status
            echo ""
            ok "Full deployment complete!"
            info "Preview site:          cd output/quarto && quarto preview"
            info "Interactive demos:     cd interactive && npm run dev"
            info "Publish to GH Pages:   ./deploy.sh --deploy"
            ;;
        *)
            echo "Usage: ./deploy.sh [--full|--validate|--generate|--site|--graph|--status|--deploy]"
            echo ""
            echo "  --full       Complete pipeline: generate → validate → build → site"
            echo "  --validate   Run v2 validation on all chapters"
            echo "  --generate   Activate v2 prompt and regenerate chapters"
            echo "  --site       Build Quarto site + React components"
            echo "  --graph      Rebuild concept graph from chapters"
            echo "  --status     Show project dashboard"
            echo "  --deploy     Publish to GitHub Pages"
            ;;
    esac
}

main "$@"
