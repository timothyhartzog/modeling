import React from "react";
import { createRoot } from "react-dom/client";

const DEMOS = [
  {
    id: "concept-map",
    title: "Concept Map",
    description: "D3.js force-directed knowledge graph across all 52 textbooks — 55+ nodes, 8 tracks.",
    icon: "🗺️",
    href: "./pages/concept-map.html",
  },
  {
    id: "phase-portrait",
    title: "Phase Portrait Explorer",
    description: "ODE phase portraits with click-to-place initial conditions and RK4 trajectory integration.",
    icon: "🌀",
    href: "./pages/phase-portrait.html",
  },
  {
    id: "gradient-descent",
    title: "Gradient Descent Visualizer",
    description: "4 optimization algorithms × 4 test functions with animated contour plots.",
    icon: "📉",
    href: "./pages/gradient-descent.html",
  },
  {
    id: "distribution",
    title: "Distribution Playground",
    description: "6 probability distributions with real-time PDF/CDF/histogram and parameter sliders.",
    icon: "📊",
    href: "./pages/distribution.html",
  },
  {
    id: "quiz",
    title: "Quiz Engine",
    description: "Spaced-repetition self-assessment with Bloom's taxonomy tiers and track filtering.",
    icon: "🧠",
    href: "./pages/quiz.html",
  },
  {
    id: "proof-explorer",
    title: "Proof Explorer",
    description: "Collapsible proofs with intuition/formal toggle and inline exercises.",
    icon: "📐",
    href: "./pages/proof-explorer.html",
  },
];

function App() {
  return (
    <div style={{ fontFamily: "'Inter', sans-serif", minHeight: "100vh", background: "#0f172a", color: "#f1f5f9" }}>
      {/* Header */}
      <header style={{ borderBottom: "1px solid #1e293b", padding: "2rem", textAlign: "center" }}>
        <h1 style={{ fontSize: "1.75rem", fontWeight: 700, color: "#f1f5f9" }}>
          📚 Universal Modeling Mastery
        </h1>
        <p style={{ marginTop: "0.5rem", color: "#94a3b8", fontSize: "1rem" }}>
          52 graduate-level textbooks · 438 chapters · interactive educational demos
        </p>
      </header>

      {/* Demo grid */}
      <main style={{ maxWidth: "900px", margin: "0 auto", padding: "2.5rem 1.5rem" }}>
        <h2 style={{ fontSize: "1.1rem", fontWeight: 600, color: "#94a3b8", marginBottom: "1.5rem", textTransform: "uppercase", letterSpacing: "0.08em" }}>
          Interactive Demos
        </h2>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(260px, 1fr))", gap: "1rem" }}>
          {DEMOS.map((demo) => (
            <a
              key={demo.id}
              href={demo.href}
              style={{
                display: "block",
                background: "#1e293b",
                border: "1px solid #334155",
                borderRadius: "0.75rem",
                padding: "1.5rem",
                textDecoration: "none",
                color: "inherit",
                transition: "border-color 0.15s, background 0.15s",
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.borderColor = "#3b82f6";
                e.currentTarget.style.background = "#1e3a5f";
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.borderColor = "#334155";
                e.currentTarget.style.background = "#1e293b";
              }}
            >
              <div style={{ fontSize: "2rem", marginBottom: "0.75rem" }}>{demo.icon}</div>
              <h3 style={{ fontSize: "1rem", fontWeight: 600, color: "#f1f5f9", marginBottom: "0.5rem" }}>{demo.title}</h3>
              <p style={{ fontSize: "0.875rem", color: "#94a3b8", lineHeight: 1.5 }}>{demo.description}</p>
            </a>
          ))}
        </div>
      </main>

      {/* Footer */}
      <footer style={{ borderTop: "1px solid #1e293b", padding: "1.5rem", textAlign: "center", color: "#475569", fontSize: "0.8rem" }}>
        <code style={{ fontFamily: "'JetBrains Mono', monospace" }}>
          julia --project=. src/generate.jl --resume
        </code>
      </footer>
    </div>
  );
}

createRoot(document.getElementById("root")).render(<App />);
