import { useState, useEffect, useRef, useCallback, useMemo } from "react";
import * as d3 from "d3";

// ═══════════════════════════════════════════════════════════════════
// CONCEPT MAP DATA — Cross-Textbook Knowledge Graph
// Each node is a major concept; edges are dependency/generalization links
// ═══════════════════════════════════════════════════════════════════

const TRACKS = {
  CORE: { label: "Core Mathematics", color: "#2563eb", bg: "#dbeafe" },
  BIOS: { label: "Biostatistics", color: "#059669", bg: "#d1fae5" },
  GEO:  { label: "Geospatial", color: "#d97706", bg: "#fef3c7" },
  ABM:  { label: "Agent-Based", color: "#dc2626", bg: "#fee2e2" },
  SCIML:{ label: "Scientific ML", color: "#7c3aed", bg: "#ede9fe" },
  POP:  { label: "Population Dynamics", color: "#0891b2", bg: "#cffafe" },
  PHYS: { label: "Physical Systems", color: "#be185d", bg: "#fce7f3" },
  XCUT: { label: "Cross-Cutting", color: "#4b5563", bg: "#f3f4f6" },
};

const NODES = [
  // CORE Mathematics
  { id: "real-analysis", label: "Real Analysis", track: "CORE", textbook: "CORE-001", chapter: 1, tier: 1 },
  { id: "metric-spaces", label: "Metric Spaces", track: "CORE", textbook: "CORE-001", chapter: 2, tier: 1 },
  { id: "measure-theory", label: "Measure Theory", track: "CORE", textbook: "CORE-003", chapter: 1, tier: 1 },
  { id: "lebesgue-integration", label: "Lebesgue Integration", track: "CORE", textbook: "CORE-003", chapter: 3, tier: 1 },
  { id: "linear-algebra", label: "Linear Algebra", track: "CORE", textbook: "CORE-002", chapter: 1, tier: 1 },
  { id: "eigendecomposition", label: "Eigenvalue Decomposition", track: "CORE", textbook: "CORE-002", chapter: 4, tier: 1 },
  { id: "svd", label: "Singular Value Decomposition", track: "CORE", textbook: "CORE-002", chapter: 5, tier: 1 },
  { id: "probability-theory", label: "Probability Theory", track: "CORE", textbook: "CORE-003", chapter: 5, tier: 1 },
  { id: "odes", label: "Ordinary DEs", track: "CORE", textbook: "CORE-006", chapter: 1, tier: 1 },
  { id: "pdes", label: "Partial DEs", track: "CORE", textbook: "CORE-007", chapter: 1, tier: 1 },
  { id: "functional-analysis", label: "Functional Analysis", track: "CORE", textbook: "CORE-005", chapter: 1, tier: 2 },
  { id: "hilbert-spaces", label: "Hilbert Spaces", track: "CORE", textbook: "CORE-005", chapter: 3, tier: 2 },
  { id: "banach-spaces", label: "Banach Spaces", track: "CORE", textbook: "CORE-005", chapter: 2, tier: 2 },
  { id: "optimization", label: "Optimization Theory", track: "CORE", textbook: "CORE-011", chapter: 1, tier: 1 },
  { id: "convex-optimization", label: "Convex Optimization", track: "CORE", textbook: "CORE-011", chapter: 3, tier: 2 },
  { id: "numerical-methods", label: "Numerical Methods", track: "CORE", textbook: "CORE-009", chapter: 1, tier: 1 },
  { id: "differential-geometry", label: "Differential Geometry", track: "CORE", textbook: "CORE-010", chapter: 1, tier: 2 },
  { id: "bayesian-theory", label: "Bayesian Theory", track: "CORE", textbook: "CORE-008", chapter: 1, tier: 1 },
  { id: "mcmc", label: "MCMC Methods", track: "CORE", textbook: "CORE-008", chapter: 4, tier: 2 },
  { id: "scientific-computing", label: "Scientific Computing", track: "CORE", textbook: "CORE-004", chapter: 1, tier: 1 },

  // Biostatistics
  { id: "glms", label: "Generalized Linear Models", track: "BIOS", textbook: "BIOS-001", chapter: 1, tier: 2 },
  { id: "survival-analysis", label: "Survival Analysis", track: "BIOS", textbook: "BIOS-002", chapter: 1, tier: 2 },
  { id: "longitudinal-data", label: "Longitudinal Data", track: "BIOS", textbook: "BIOS-003", chapter: 1, tier: 2 },
  { id: "causal-inference", label: "Causal Inference", track: "BIOS", textbook: "BIOS-004", chapter: 1, tier: 2 },
  { id: "clinical-trials", label: "Clinical Trials Design", track: "BIOS", textbook: "BIOS-005", chapter: 1, tier: 2 },
  { id: "high-dim-stats", label: "High-Dimensional Stats", track: "BIOS", textbook: "BIOS-006", chapter: 1, tier: 3 },
  { id: "epidemic-models", label: "Epidemic Models", track: "BIOS", textbook: "BIOS-007", chapter: 1, tier: 2 },
  { id: "spatial-epi", label: "Spatial Epidemiology", track: "BIOS", textbook: "BIOS-008", chapter: 1, tier: 3 },

  // Geospatial
  { id: "geostatistics", label: "Geostatistics / Kriging", track: "GEO", textbook: "GEO-001", chapter: 1, tier: 2 },
  { id: "point-processes", label: "Spatial Point Processes", track: "GEO", textbook: "GEO-002", chapter: 1, tier: 2 },
  { id: "areal-data", label: "Areal / Lattice Data", track: "GEO", textbook: "GEO-003", chapter: 1, tier: 2 },
  { id: "space-time", label: "Space-Time Models", track: "GEO", textbook: "GEO-004", chapter: 1, tier: 3 },
  { id: "remote-sensing", label: "Remote Sensing", track: "GEO", textbook: "GEO-005", chapter: 1, tier: 2 },

  // Agent-Based
  { id: "abm-foundations", label: "ABM Foundations", track: "ABM", textbook: "ABM-001", chapter: 1, tier: 2 },
  { id: "network-science", label: "Network Science", track: "ABM", textbook: "ABM-002", chapter: 1, tier: 2 },
  { id: "mean-field", label: "Mean-Field Theory", track: "ABM", textbook: "ABM-003", chapter: 1, tier: 3 },
  { id: "game-theory", label: "Evolutionary Game Theory", track: "ABM", textbook: "ABM-004", chapter: 1, tier: 2 },

  // Scientific ML
  { id: "deep-learning", label: "Deep Learning Theory", track: "SCIML", textbook: "SCIML-001", chapter: 1, tier: 2 },
  { id: "neural-odes", label: "Neural ODEs / UDEs / PINNs", track: "SCIML", textbook: "SCIML-002", chapter: 1, tier: 3 },
  { id: "prob-ml", label: "Probabilistic ML", track: "SCIML", textbook: "SCIML-003", chapter: 1, tier: 3 },
  { id: "autodiff", label: "Automatic Differentiation", track: "SCIML", textbook: "SCIML-004", chapter: 1, tier: 2 },
  { id: "ml-inverse", label: "ML for Inverse Problems", track: "SCIML", textbook: "SCIML-005", chapter: 1, tier: 3 },

  // Population Dynamics
  { id: "det-pop", label: "Deterministic Population", track: "POP", textbook: "POP-001", chapter: 1, tier: 2 },
  { id: "stoch-pop", label: "Stochastic Population", track: "POP", textbook: "POP-002", chapter: 1, tier: 2 },
  { id: "systems-bio", label: "Systems Biology", track: "POP", textbook: "POP-003", chapter: 1, tier: 3 },
  { id: "demography", label: "Mathematical Demography", track: "POP", textbook: "POP-004", chapter: 1, tier: 2 },

  // Physical Systems
  { id: "continuum-mech", label: "Continuum Mechanics", track: "PHYS", textbook: "PHYS-001", chapter: 1, tier: 2 },
  { id: "fluid-dynamics", label: "Fluid Dynamics", track: "PHYS", textbook: "PHYS-002", chapter: 1, tier: 2 },
  { id: "biomechanics", label: "Biomechanics", track: "PHYS", textbook: "PHYS-003", chapter: 1, tier: 3 },
  { id: "atmos-climate", label: "Atmospheric / Climate", track: "PHYS", textbook: "PHYS-004", chapter: 1, tier: 3 },

  // Cross-Cutting
  { id: "uq", label: "Uncertainty Quantification", track: "XCUT", textbook: "XCUT-001", chapter: 1, tier: 3 },
  { id: "inverse-problems", label: "Inverse Problems", track: "XCUT", textbook: "XCUT-002", chapter: 1, tier: 3 },
  { id: "dynamical-systems", label: "Dynamical Systems", track: "XCUT", textbook: "XCUT-003", chapter: 1, tier: 2 },
  { id: "optimal-transport", label: "Optimal Transport", track: "XCUT", textbook: "XCUT-004", chapter: 1, tier: 3 },
  { id: "info-geometry", label: "Information Geometry", track: "XCUT", textbook: "XCUT-005", chapter: 1, tier: 3 },

  // CORE-017 — Numerical Linear Algebra (new)
  { id: "nla-floating-point", label: "Floating-Point Arithmetic", track: "CORE", textbook: "CORE-017", chapter: 1, tier: 1 },
  { id: "nla-direct-solvers", label: "Direct Solvers (LU/QR)", track: "CORE", textbook: "CORE-017", chapter: 2, tier: 2 },
  { id: "nla-svd-computation", label: "SVD Computation", track: "CORE", textbook: "CORE-017", chapter: 4, tier: 2 },
  { id: "nla-krylov", label: "Krylov Methods (CG/GMRES)", track: "CORE", textbook: "CORE-017", chapter: 6, tier: 2 },
  { id: "nla-sparse", label: "Sparse Matrix Computation", track: "CORE", textbook: "CORE-017", chapter: 7, tier: 2 },
  { id: "nla-randomized", label: "Randomized NLA", track: "CORE", textbook: "CORE-017", chapter: 8, tier: 3 },
  { id: "nla-matrix-exp", label: "Matrix Exponential", track: "CORE", textbook: "CORE-017", chapter: 9, tier: 3 },

  // CROSS-006 — Model Selection (new)
  { id: "model-selection", label: "Model Selection", track: "XCUT", textbook: "CROSS-006", chapter: 1, tier: 2 },
  { id: "info-criteria", label: "AIC / BIC / DIC", track: "XCUT", textbook: "CROSS-006", chapter: 2, tier: 2 },
  { id: "cross-validation", label: "Cross-Validation Theory", track: "XCUT", textbook: "CROSS-006", chapter: 3, tier: 2 },
  { id: "bayes-factors", label: "Bayes Factors", track: "XCUT", textbook: "CROSS-006", chapter: 4, tier: 3 },
  { id: "waic-loo", label: "WAIC / PSIS-LOO", track: "XCUT", textbook: "CROSS-006", chapter: 5, tier: 3 },
  { id: "model-averaging", label: "Model Averaging", track: "XCUT", textbook: "CROSS-006", chapter: 8, tier: 3 },
];

const EDGES = [
  // Core dependency chains
  { source: "real-analysis", target: "metric-spaces", type: "depends" },
  { source: "metric-spaces", target: "functional-analysis", type: "depends" },
  { source: "functional-analysis", target: "banach-spaces", type: "depends" },
  { source: "functional-analysis", target: "hilbert-spaces", type: "depends" },
  { source: "real-analysis", target: "measure-theory", type: "depends" },
  { source: "measure-theory", target: "lebesgue-integration", type: "depends" },
  { source: "measure-theory", target: "probability-theory", type: "depends" },
  { source: "linear-algebra", target: "eigendecomposition", type: "depends" },
  { source: "eigendecomposition", target: "svd", type: "depends" },
  { source: "linear-algebra", target: "optimization", type: "depends" },
  { source: "optimization", target: "convex-optimization", type: "depends" },
  { source: "real-analysis", target: "odes", type: "depends" },
  { source: "odes", target: "pdes", type: "depends" },
  { source: "linear-algebra", target: "numerical-methods", type: "depends" },
  { source: "probability-theory", target: "bayesian-theory", type: "depends" },
  { source: "bayesian-theory", target: "mcmc", type: "depends" },
  { source: "numerical-methods", target: "scientific-computing", type: "depends" },

  // Core → Biostat
  { source: "probability-theory", target: "glms", type: "depends" },
  { source: "glms", target: "survival-analysis", type: "depends" },
  { source: "glms", target: "longitudinal-data", type: "depends" },
  { source: "probability-theory", target: "causal-inference", type: "depends" },
  { source: "glms", target: "clinical-trials", type: "depends" },
  { source: "svd", target: "high-dim-stats", type: "depends" },
  { source: "odes", target: "epidemic-models", type: "depends" },
  { source: "geostatistics", target: "spatial-epi", type: "depends" },
  { source: "epidemic-models", target: "spatial-epi", type: "depends" },

  // Core → Geospatial
  { source: "probability-theory", target: "geostatistics", type: "depends" },
  { source: "probability-theory", target: "point-processes", type: "depends" },
  { source: "geostatistics", target: "areal-data", type: "depends" },
  { source: "geostatistics", target: "space-time", type: "depends" },
  { source: "pdes", target: "space-time", type: "depends" },
  { source: "linear-algebra", target: "remote-sensing", type: "depends" },

  // Core → ABM
  { source: "probability-theory", target: "abm-foundations", type: "depends" },
  { source: "linear-algebra", target: "network-science", type: "depends" },
  { source: "abm-foundations", target: "mean-field", type: "depends" },
  { source: "odes", target: "mean-field", type: "depends" },
  { source: "optimization", target: "game-theory", type: "depends" },

  // Core → SciML
  { source: "linear-algebra", target: "deep-learning", type: "depends" },
  { source: "optimization", target: "deep-learning", type: "depends" },
  { source: "odes", target: "neural-odes", type: "depends" },
  { source: "deep-learning", target: "neural-odes", type: "depends" },
  { source: "bayesian-theory", target: "prob-ml", type: "depends" },
  { source: "deep-learning", target: "prob-ml", type: "depends" },
  { source: "numerical-methods", target: "autodiff", type: "depends" },
  { source: "neural-odes", target: "ml-inverse", type: "depends" },
  { source: "inverse-problems", target: "ml-inverse", type: "generalizes" },

  // Core → Pop Dynamics
  { source: "odes", target: "det-pop", type: "depends" },
  { source: "probability-theory", target: "stoch-pop", type: "depends" },
  { source: "det-pop", target: "stoch-pop", type: "depends" },
  { source: "det-pop", target: "systems-bio", type: "depends" },
  { source: "linear-algebra", target: "demography", type: "depends" },

  // Core → Physical
  { source: "pdes", target: "continuum-mech", type: "depends" },
  { source: "continuum-mech", target: "fluid-dynamics", type: "depends" },
  { source: "continuum-mech", target: "biomechanics", type: "depends" },
  { source: "fluid-dynamics", target: "atmos-climate", type: "depends" },
  { source: "pdes", target: "atmos-climate", type: "depends" },

  // Core → Cross-Cutting
  { source: "probability-theory", target: "uq", type: "depends" },
  { source: "bayesian-theory", target: "uq", type: "depends" },
  { source: "pdes", target: "inverse-problems", type: "depends" },
  { source: "optimization", target: "inverse-problems", type: "depends" },
  { source: "odes", target: "dynamical-systems", type: "depends" },
  { source: "measure-theory", target: "optimal-transport", type: "depends" },
  { source: "optimization", target: "optimal-transport", type: "depends" },
  { source: "differential-geometry", target: "info-geometry", type: "depends" },
  { source: "probability-theory", target: "info-geometry", type: "depends" },

  // CORE-017 Numerical Linear Algebra edges
  { source: "linear-algebra", target: "nla-floating-point", type: "depends" },
  { source: "nla-floating-point", target: "nla-direct-solvers", type: "depends" },
  { source: "nla-direct-solvers", target: "nla-svd-computation", type: "depends" },
  { source: "svd", target: "nla-svd-computation", type: "generalizes" },
  { source: "nla-direct-solvers", target: "nla-krylov", type: "depends" },
  { source: "nla-krylov", target: "nla-sparse", type: "depends" },
  { source: "nla-svd-computation", target: "nla-randomized", type: "depends" },
  { source: "odes", target: "nla-matrix-exp", type: "depends" },
  { source: "nla-direct-solvers", target: "nla-matrix-exp", type: "depends" },
  { source: "nla-krylov", target: "inverse-problems", type: "depends" },
  { source: "nla-sparse", target: "neural-odes", type: "depends" },

  // CROSS-006 Model Selection edges
  { source: "probability-theory", target: "model-selection", type: "depends" },
  { source: "bayesian-theory", target: "model-selection", type: "depends" },
  { source: "model-selection", target: "info-criteria", type: "depends" },
  { source: "model-selection", target: "cross-validation", type: "depends" },
  { source: "bayesian-theory", target: "bayes-factors", type: "depends" },
  { source: "model-selection", target: "bayes-factors", type: "depends" },
  { source: "mcmc", target: "waic-loo", type: "depends" },
  { source: "bayes-factors", target: "waic-loo", type: "depends" },
  { source: "model-selection", target: "model-averaging", type: "depends" },
  { source: "cross-validation", target: "model-averaging", type: "depends" },
];

// ═══════════════════════════════════════════════════════════════════
// COMPONENTS
// ═══════════════════════════════════════════════════════════════════

const NODE_RADIUS = { 1: 18, 2: 14, 3: 11 };

function ConceptMapNavigator() {
  const svgRef = useRef(null);
  const containerRef = useRef(null);
  const [selectedNode, setSelectedNode] = useState(null);
  const [hoveredNode, setHoveredNode] = useState(null);
  const [activeTrack, setActiveTrack] = useState(null);
  const [searchTerm, setSearchTerm] = useState("");
  const [dimensions, setDimensions] = useState({ width: 1000, height: 700 });
  const simulationRef = useRef(null);

  const filteredNodes = useMemo(() => {
    let nodes = NODES;
    if (activeTrack) nodes = nodes.filter(n => n.track === activeTrack);
    if (searchTerm) {
      const term = searchTerm.toLowerCase();
      nodes = nodes.filter(n =>
        n.label.toLowerCase().includes(term) ||
        n.textbook.toLowerCase().includes(term)
      );
    }
    return nodes;
  }, [activeTrack, searchTerm]);

  const filteredNodeIds = useMemo(() => new Set(filteredNodes.map(n => n.id)), [filteredNodes]);

  const filteredEdges = useMemo(() =>
    EDGES.filter(e => filteredNodeIds.has(e.source) && filteredNodeIds.has(e.target)),
    [filteredNodeIds]
  );

  // Get neighbors of selected node
  const neighbors = useMemo(() => {
    if (!selectedNode) return new Set();
    const s = new Set();
    s.add(selectedNode);
    EDGES.forEach(e => {
      if (e.source === selectedNode || (typeof e.source === "object" && e.source.id === selectedNode)) {
        const tid = typeof e.target === "object" ? e.target.id : e.target;
        s.add(tid);
      }
      if (e.target === selectedNode || (typeof e.target === "object" && e.target.id === selectedNode)) {
        const sid = typeof e.source === "object" ? e.source.id : e.source;
        s.add(sid);
      }
    });
    return s;
  }, [selectedNode]);

  useEffect(() => {
    const obs = new ResizeObserver(entries => {
      for (const e of entries) {
        setDimensions({ width: e.contentRect.width, height: Math.max(600, e.contentRect.height) });
      }
    });
    if (containerRef.current) obs.observe(containerRef.current);
    return () => obs.disconnect();
  }, []);

  useEffect(() => {
    if (!svgRef.current) return;
    const { width, height } = dimensions;
    const svg = d3.select(svgRef.current);
    svg.selectAll("*").remove();

    // Defs for arrowheads
    const defs = svg.append("defs");
    defs.append("marker")
      .attr("id", "arrow-depends")
      .attr("viewBox", "0 -5 10 10").attr("refX", 25).attr("refY", 0)
      .attr("markerWidth", 6).attr("markerHeight", 6).attr("orient", "auto")
      .append("path").attr("d", "M0,-5L10,0L0,5").attr("fill", "#94a3b8");
    defs.append("marker")
      .attr("id", "arrow-generalizes")
      .attr("viewBox", "0 -5 10 10").attr("refX", 25).attr("refY", 0)
      .attr("markerWidth", 6).attr("markerHeight", 6).attr("orient", "auto")
      .append("path").attr("d", "M0,-5L10,0L0,5").attr("fill", "none").attr("stroke", "#94a3b8").attr("stroke-width", 1.5);

    // Background gradient
    const bgGrad = defs.append("radialGradient").attr("id", "bg-grad");
    bgGrad.append("stop").attr("offset", "0%").attr("stop-color", "#1e293b");
    bgGrad.append("stop").attr("offset", "100%").attr("stop-color", "#0f172a");
    svg.append("rect").attr("width", width).attr("height", height).attr("fill", "url(#bg-grad)");

    // Grid lines for visual texture
    const gridG = svg.append("g").attr("opacity", 0.06);
    for (let x = 0; x < width; x += 40) {
      gridG.append("line").attr("x1", x).attr("y1", 0).attr("x2", x).attr("y2", height).attr("stroke", "#64748b");
    }
    for (let y = 0; y < height; y += 40) {
      gridG.append("line").attr("x1", 0).attr("y1", y).attr("x2", width).attr("y2", y).attr("stroke", "#64748b");
    }

    const g = svg.append("g");

    // Zoom behavior
    const zoom = d3.zoom().scaleExtent([0.3, 4]).on("zoom", (event) => {
      g.attr("transform", event.transform);
    });
    svg.call(zoom);

    // Prepare data copies
    const nodes = filteredNodes.map(n => ({ ...n }));
    const edges = filteredEdges.map(e => ({ ...e }));

    // Force simulation
    const simulation = d3.forceSimulation(nodes)
      .force("link", d3.forceLink(edges).id(d => d.id).distance(100).strength(0.7))
      .force("charge", d3.forceManyBody().strength(-300))
      .force("center", d3.forceCenter(width / 2, height / 2))
      .force("collision", d3.forceCollide().radius(d => NODE_RADIUS[d.tier] + 8))
      .force("x", d3.forceX(width / 2).strength(0.05))
      .force("y", d3.forceY(height / 2).strength(0.05));

    simulationRef.current = simulation;

    // Draw edges
    const link = g.append("g")
      .selectAll("line")
      .data(edges)
      .join("line")
      .attr("stroke", d => d.type === "generalizes" ? "#fbbf24" : "#475569")
      .attr("stroke-width", d => d.type === "generalizes" ? 2 : 1.2)
      .attr("stroke-dasharray", d => d.type === "generalizes" ? "6,3" : "none")
      .attr("marker-end", d => `url(#arrow-${d.type})`)
      .attr("opacity", 0.5);

    // Draw nodes
    const node = g.append("g")
      .selectAll("g")
      .data(nodes)
      .join("g")
      .attr("cursor", "pointer")
      .call(d3.drag()
        .on("start", (event, d) => {
          if (!event.active) simulation.alphaTarget(0.3).restart();
          d.fx = d.x; d.fy = d.y;
        })
        .on("drag", (event, d) => { d.fx = event.x; d.fy = event.y; })
        .on("end", (event, d) => {
          if (!event.active) simulation.alphaTarget(0);
          d.fx = null; d.fy = null;
        })
      );

    // Node glow
    node.append("circle")
      .attr("r", d => NODE_RADIUS[d.tier] + 4)
      .attr("fill", d => TRACKS[d.track].color)
      .attr("opacity", 0.15)
      .attr("filter", "blur(4px)");

    // Node circle
    node.append("circle")
      .attr("r", d => NODE_RADIUS[d.tier])
      .attr("fill", d => TRACKS[d.track].color)
      .attr("stroke", "#e2e8f0")
      .attr("stroke-width", 1.5);

    // Node labels
    node.append("text")
      .text(d => d.label)
      .attr("dy", d => NODE_RADIUS[d.tier] + 14)
      .attr("text-anchor", "middle")
      .attr("fill", "#cbd5e1")
      .attr("font-size", d => d.tier === 1 ? "11px" : "9px")
      .attr("font-family", "'JetBrains Mono', monospace")
      .attr("pointer-events", "none");

    // Interactions
    node.on("click", (event, d) => {
      event.stopPropagation();
      setSelectedNode(prev => prev === d.id ? null : d.id);
    });
    node.on("mouseenter", (event, d) => setHoveredNode(d.id));
    node.on("mouseleave", () => setHoveredNode(null));
    svg.on("click", () => setSelectedNode(null));

    simulation.on("tick", () => {
      link.attr("x1", d => d.source.x).attr("y1", d => d.source.y)
        .attr("x2", d => d.target.x).attr("y2", d => d.target.y);
      node.attr("transform", d => `translate(${d.x},${d.y})`);
    });

    return () => simulation.stop();
  }, [filteredNodes, filteredEdges, dimensions]);

  // Highlight neighbors when selected
  useEffect(() => {
    if (!svgRef.current) return;
    const svg = d3.select(svgRef.current);

    svg.selectAll("g > g > g").each(function () {
      const g = d3.select(this);
      const d = g.datum();
      if (!d) return;

      if (selectedNode && !neighbors.has(d.id)) {
        g.attr("opacity", 0.15);
      } else {
        g.attr("opacity", 1);
      }
    });

    svg.selectAll("g > g > line").each(function () {
      const line = d3.select(this);
      const d = line.datum();
      if (!d) return;
      const sid = typeof d.source === "object" ? d.source.id : d.source;
      const tid = typeof d.target === "object" ? d.target.id : d.target;

      if (selectedNode && !(neighbors.has(sid) && neighbors.has(tid))) {
        line.attr("opacity", 0.05);
      } else {
        line.attr("opacity", 0.5);
      }
    });
  }, [selectedNode, neighbors]);

  const selectedData = NODES.find(n => n.id === selectedNode);
  const hoveredData = NODES.find(n => n.id === hoveredNode);
  const infoNode = selectedData || hoveredData;

  const prereqs = useMemo(() => {
    if (!infoNode) return [];
    return EDGES
      .filter(e => (typeof e.target === "string" ? e.target : e.target.id) === infoNode.id)
      .map(e => NODES.find(n => n.id === (typeof e.source === "string" ? e.source : e.source.id)))
      .filter(Boolean);
  }, [infoNode]);

  const dependents = useMemo(() => {
    if (!infoNode) return [];
    return EDGES
      .filter(e => (typeof e.source === "string" ? e.source : e.source.id) === infoNode.id)
      .map(e => NODES.find(n => n.id === (typeof e.target === "string" ? e.target : e.target.id)))
      .filter(Boolean);
  }, [infoNode]);

  return (
    <div style={{ fontFamily: "'JetBrains Mono', 'Fira Code', monospace", background: "#0f172a", color: "#e2e8f0", minHeight: "100vh", display: "flex", flexDirection: "column" }}>
      {/* Header */}
      <div style={{ padding: "16px 24px", borderBottom: "1px solid #1e293b", display: "flex", alignItems: "center", gap: 16, flexWrap: "wrap" }}>
        <div style={{ fontSize: 18, fontWeight: 700, color: "#f8fafc", letterSpacing: "-0.5px" }}>
          <span style={{ color: "#3b82f6" }}>◆</span> Concept Map
        </div>
        <input
          type="text"
          placeholder="Search concepts..."
          value={searchTerm}
          onChange={e => setSearchTerm(e.target.value)}
          style={{
            background: "#1e293b", border: "1px solid #334155", borderRadius: 6,
            padding: "6px 12px", color: "#e2e8f0", fontSize: 12, width: 200,
            outline: "none", fontFamily: "inherit"
          }}
        />
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          <button
            onClick={() => setActiveTrack(null)}
            style={{
              background: !activeTrack ? "#334155" : "transparent",
              border: "1px solid #475569", borderRadius: 4, padding: "4px 10px",
              color: "#cbd5e1", fontSize: 11, cursor: "pointer", fontFamily: "inherit"
            }}
          >All</button>
          {Object.entries(TRACKS).map(([key, track]) => (
            <button
              key={key}
              onClick={() => setActiveTrack(prev => prev === key ? null : key)}
              style={{
                background: activeTrack === key ? track.color : "transparent",
                border: `1px solid ${track.color}`,
                borderRadius: 4, padding: "4px 10px",
                color: activeTrack === key ? "#fff" : track.color,
                fontSize: 11, cursor: "pointer", fontFamily: "inherit"
              }}
            >{track.label}</button>
          ))}
        </div>
      </div>

      {/* Main area */}
      <div style={{ flex: 1, display: "flex", position: "relative" }} ref={containerRef}>
        <svg ref={svgRef} width={dimensions.width} height={dimensions.height} style={{ flex: 1 }} />

        {/* Info panel */}
        {infoNode && (
          <div style={{
            position: "absolute", top: 16, right: 16, width: 280,
            background: "#1e293b", border: "1px solid #334155", borderRadius: 8,
            padding: 16, boxShadow: "0 8px 32px rgba(0,0,0,0.4)"
          }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12 }}>
              <div style={{
                width: 12, height: 12, borderRadius: "50%",
                background: TRACKS[infoNode.track].color
              }} />
              <span style={{ fontSize: 14, fontWeight: 600, color: "#f8fafc" }}>{infoNode.label}</span>
            </div>
            <div style={{ fontSize: 11, color: "#94a3b8", marginBottom: 8 }}>
              {TRACKS[infoNode.track].label} • {infoNode.textbook} Ch.{infoNode.chapter}
            </div>
            <div style={{ fontSize: 10, color: "#64748b", marginBottom: 12 }}>
              Tier {infoNode.tier} • {infoNode.tier === 1 ? "Foundation" : infoNode.tier === 2 ? "Intermediate" : "Advanced"}
            </div>

            {prereqs.length > 0 && (
              <div style={{ marginBottom: 10 }}>
                <div style={{ fontSize: 10, color: "#64748b", fontWeight: 600, marginBottom: 4 }}>PREREQUISITES</div>
                {prereqs.map(p => (
                  <div key={p.id} style={{ fontSize: 11, color: "#94a3b8", padding: "2px 0", cursor: "pointer" }}
                    onClick={() => setSelectedNode(p.id)}>
                    ← {p.label}
                  </div>
                ))}
              </div>
            )}

            {dependents.length > 0 && (
              <div>
                <div style={{ fontSize: 10, color: "#64748b", fontWeight: 600, marginBottom: 4 }}>ENABLES</div>
                {dependents.map(p => (
                  <div key={p.id} style={{ fontSize: 11, color: "#94a3b8", padding: "2px 0", cursor: "pointer" }}
                    onClick={() => setSelectedNode(p.id)}>
                    → {p.label}
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* Legend */}
        <div style={{
          position: "absolute", bottom: 16, left: 16,
          background: "#1e293bcc", borderRadius: 6, padding: "8px 12px",
          fontSize: 10, color: "#64748b"
        }}>
          <div>— Dependency &nbsp; - - - Generalization</div>
          <div style={{ marginTop: 4 }}>Drag nodes • Scroll to zoom • Click to inspect</div>
        </div>
      </div>
    </div>
  );
}

export default ConceptMapNavigator;
