import { useState, useCallback } from "react";

// ═══════════════════════════════════════════════════════════════════
// Proof Explorer
// Collapsible proof steps, justification tooltips, intuition vs formal toggle
// Fill-in-the-blank exercises with instant feedback
// ═══════════════════════════════════════════════════════════════════

const SAMPLE_PROOFS = [
  {
    id: "banach-fixed-point",
    title: "Banach Fixed-Point Theorem",
    statement: "Let (X, d) be a complete metric space and T: X → X be a contraction mapping with constant 0 ≤ q < 1. Then T has a unique fixed point x* ∈ X, and for any x₀ ∈ X, the sequence xₙ = T(xₙ₋₁) converges to x*.",
    textbook: "CORE-001",
    chapter: 3,
    steps: [
      {
        id: 1,
        label: "Show {xₙ} is Cauchy",
        formal: "For m > n, by the triangle inequality and contraction:\n\nd(xₙ, xₘ) ≤ Σₖ₌ₙᵐ⁻¹ d(xₖ, xₖ₊₁) ≤ Σₖ₌ₙᵐ⁻¹ qᵏ d(x₀, x₁)\n\n≤ qⁿ/(1-q) · d(x₀, x₁) → 0 as n → ∞",
        intuition: "Each step of the iteration brings points closer together by a factor of q. So the total distance from xₙ to any later term xₘ is bounded by a geometric series that shrinks to zero. Think of it like each step covering at most q fraction of the remaining distance.",
        justification: "Triangle inequality + geometric series formula",
        exercise: null,
      },
      {
        id: 2,
        label: "Conclude xₙ → x* by completeness",
        formal: "Since (X, d) is complete and {xₙ} is Cauchy, there exists x* ∈ X such that xₙ → x* as n → ∞.",
        intuition: "Completeness is the key assumption here — it means 'there are no holes in the space.' Without it, the sequence could converge to a point that isn't in X. For example, the rationals ℚ are not complete: a Cauchy sequence of rationals can converge to √2, which isn't rational.",
        justification: "Definition of completeness (every Cauchy sequence converges)",
        exercise: "What goes wrong if X = (0, 1) with the usual metric and T(x) = x/2?",
        exerciseAnswer: "The iterates xₙ = x₀/2ⁿ → 0, but 0 ∉ (0,1). The space is not complete, so the fixed point doesn't exist in X."
      },
      {
        id: 3,
        label: "Show x* is a fixed point",
        formal: "d(x*, T(x*)) ≤ d(x*, xₙ) + d(xₙ, T(x*))\n= d(x*, xₙ) + d(T(xₙ₋₁), T(x*))\n≤ d(x*, xₙ) + q · d(xₙ₋₁, x*)\n→ 0 + 0 = 0\n\nHence d(x*, T(x*)) = 0, so x* = T(x*).",
        intuition: "We squeeze the distance d(x*, T(x*)) between two terms that both go to zero: the first because xₙ → x*, the second because T is a contraction and xₙ₋₁ → x* too. If the distance is zero, the points are the same.",
        justification: "Triangle inequality + contraction property + limit laws",
        exercise: null,
      },
      {
        id: 4,
        label: "Show uniqueness",
        formal: "Suppose x* and y* are both fixed points. Then:\n\nd(x*, y*) = d(T(x*), T(y*)) ≤ q · d(x*, y*)\n\nSince 0 ≤ q < 1, this implies d(x*, y*) = 0, hence x* = y*.",
        intuition: "If there were two fixed points, applying T wouldn't move either one. But T is a contraction — it must shrink the distance between any two points. The only way a contraction can leave the distance unchanged is if the distance is already zero. So the two 'different' fixed points must actually be the same point.",
        justification: "Contraction property + q < 1 forces d = 0",
        exercise: "Why does this argument fail if q = 1?",
        exerciseAnswer: "If q = 1, we only get d(x*, y*) ≤ d(x*, y*), which is trivially true and tells us nothing. Example: T(x) = x (identity) has every point as a fixed point."
      },
    ],
  },
  {
    id: "cauchy-schwarz",
    title: "Cauchy–Schwarz Inequality",
    statement: "For all vectors u, v in an inner product space: |⟨u, v⟩|² ≤ ⟨u, u⟩ · ⟨v, v⟩, with equality iff u and v are linearly dependent.",
    textbook: "CORE-002",
    chapter: 2,
    steps: [
      {
        id: 1,
        label: "If v = 0, the result is trivial",
        formal: "If v = 0, then both sides equal 0. ✓",
        intuition: "The zero vector is parallel to everything, so equality holds trivially.",
        justification: "Inner product axiom: ⟨u, 0⟩ = 0",
        exercise: null,
      },
      {
        id: 2,
        label: "Consider p(t) = ⟨u - tv, u - tv⟩ ≥ 0",
        formal: "For any scalar t ∈ ℝ, the inner product ⟨u - tv, u - tv⟩ ≥ 0 by positive-definiteness.\n\nExpanding: p(t) = ⟨u,u⟩ - 2t⟨u,v⟩ + t²⟨v,v⟩ ≥ 0",
        intuition: "Think of p(t) as the squared norm of the vector u - tv. A squared norm is always non-negative — you can't have a vector with negative length squared. By expanding this, we get a quadratic in t that must be non-negative for all t.",
        justification: "Positive-definiteness axiom + bilinearity of inner product",
        exercise: null,
      },
      {
        id: 3,
        label: "Apply the discriminant condition",
        formal: "p(t) = At² - 2Bt + C ≥ 0 for all t, where A = ⟨v,v⟩, B = ⟨u,v⟩, C = ⟨u,u⟩.\n\nA non-negative quadratic has non-positive discriminant:\n\n4B² - 4AC ≤ 0  ⟹  ⟨u,v⟩² ≤ ⟨u,u⟩·⟨v,v⟩  □",
        intuition: "A parabola that never dips below the x-axis must have at most one real root — its discriminant must be ≤ 0. That discriminant condition is exactly the Cauchy-Schwarz inequality.",
        justification: "Discriminant of a non-negative quadratic ≤ 0",
        exercise: "When does equality hold? Relate this to the discriminant being exactly zero.",
        exerciseAnswer: "Equality holds when the discriminant is zero, meaning the quadratic has exactly one root t*. This means u - t*v = 0, i.e., u = t*v, so u and v are linearly dependent."
      },
    ],
  },
];

function ProofStep({ step, mode, isOpen, onToggle }) {
  const [showExercise, setShowExercise] = useState(false);
  const [showAnswer, setShowAnswer] = useState(false);
  const [userAnswer, setUserAnswer] = useState("");
  const content = mode === "intuition" ? step.intuition : step.formal;

  return (
    <div style={{ marginBottom: 2 }}>
      <button onClick={onToggle} style={{
        width: "100%", textAlign: "left", padding: "12px 16px",
        background: isOpen ? "#1e293b" : "#0f172a",
        border: "1px solid #334155", borderRadius: isOpen ? "8px 8px 0 0" : 8,
        color: "#f8fafc", fontSize: 13, fontWeight: 600, cursor: "pointer",
        fontFamily: "inherit", display: "flex", justifyContent: "space-between", alignItems: "center"
      }}>
        <span>
          <span style={{ color: "#3b82f6", marginRight: 8 }}>Step {step.id}.</span>
          {step.label}
        </span>
        <span style={{ color: "#475569", fontSize: 16 }}>{isOpen ? "−" : "+"}</span>
      </button>

      {isOpen && (
        <div style={{
          background: "#1e293b", border: "1px solid #334155", borderTop: "none",
          borderRadius: "0 0 8px 8px", padding: 16
        }}>
          {/* Content */}
          <pre style={{
            fontFamily: "'JetBrains Mono', monospace", fontSize: 12, color: "#cbd5e1",
            whiteSpace: "pre-wrap", lineHeight: 1.7, margin: 0, marginBottom: 12
          }}>
            {content}
          </pre>

          {/* Justification tooltip */}
          <div style={{
            display: "inline-flex", alignItems: "center", gap: 6,
            background: "#0f172a", border: "1px solid #334155", borderRadius: 4,
            padding: "4px 10px", fontSize: 10, color: "#94a3b8"
          }}>
            <span style={{ color: "#3b82f6" }}>⚡</span> {step.justification}
          </div>

          {/* Exercise */}
          {step.exercise && (
            <div style={{ marginTop: 16 }}>
              <button onClick={() => setShowExercise(!showExercise)} style={{
                background: "transparent", border: "1px solid #f59e0b", borderRadius: 6,
                padding: "6px 14px", color: "#f59e0b", fontSize: 11, cursor: "pointer",
                fontFamily: "inherit"
              }}>
                {showExercise ? "Hide Exercise" : "🧩 Try an Exercise"}
              </button>

              {showExercise && (
                <div style={{
                  marginTop: 10, background: "#1a1a2e", border: "1px solid #f59e0b33",
                  borderRadius: 6, padding: 12
                }}>
                  <div style={{ fontSize: 12, color: "#fbbf24", marginBottom: 8 }}>
                    {step.exercise}
                  </div>
                  <textarea
                    value={userAnswer}
                    onChange={e => setUserAnswer(e.target.value)}
                    placeholder="Type your answer..."
                    rows={3}
                    style={{
                      width: "100%", background: "#0f172a", border: "1px solid #334155",
                      borderRadius: 4, padding: 8, color: "#e2e8f0", fontSize: 12,
                      fontFamily: "inherit", resize: "vertical", boxSizing: "border-box"
                    }}
                  />
                  <button onClick={() => setShowAnswer(true)} style={{
                    marginTop: 8, background: "#334155", border: "none", borderRadius: 4,
                    padding: "6px 14px", color: "#f8fafc", fontSize: 11, cursor: "pointer",
                    fontFamily: "inherit"
                  }}>Show Solution</button>

                  {showAnswer && (
                    <div style={{
                      marginTop: 8, background: "#052e16", border: "1px solid #10b98144",
                      borderRadius: 4, padding: 10, fontSize: 12, color: "#a7f3d0", lineHeight: 1.6
                    }}>
                      {step.exerciseAnswer}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default function ProofExplorer() {
  const [selectedProof, setSelectedProof] = useState(0);
  const [mode, setMode] = useState("intuition");
  const [openSteps, setOpenSteps] = useState(new Set([1]));

  const proof = SAMPLE_PROOFS[selectedProof];

  const toggleStep = useCallback((id) => {
    setOpenSteps(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const expandAll = () => setOpenSteps(new Set(proof.steps.map(s => s.id)));
  const collapseAll = () => setOpenSteps(new Set());

  return (
    <div style={{ fontFamily: "'JetBrains Mono', monospace", background: "#0f172a", color: "#e2e8f0", minHeight: "100vh", padding: 24 }}>
      <div style={{ maxWidth: 750, margin: "0 auto" }}>
        <h1 style={{ fontSize: 20, fontWeight: 700, marginBottom: 4, color: "#f8fafc" }}>
          <span style={{ color: "#ec4899" }}>◆</span> Proof Explorer
        </h1>
        <p style={{ fontSize: 12, color: "#64748b", marginBottom: 20 }}>
          Step through proofs with intuition or formal rigor. Try the exercises.
        </p>

        {/* Proof selector */}
        <div style={{ display: "flex", gap: 8, marginBottom: 20, flexWrap: "wrap" }}>
          {SAMPLE_PROOFS.map((p, i) => (
            <button key={p.id} onClick={() => { setSelectedProof(i); setOpenSteps(new Set([1])); }} style={{
              background: selectedProof === i ? "#ec4899" : "#1e293b",
              border: "1px solid #334155", borderRadius: 6, padding: "6px 14px",
              color: selectedProof === i ? "#fff" : "#94a3b8", fontSize: 11,
              cursor: "pointer", fontFamily: "inherit"
            }}>{p.title}</button>
          ))}
        </div>

        {/* Theorem statement */}
        <div style={{
          background: "#172554", border: "1px solid #2563eb44", borderRadius: 8,
          padding: 16, marginBottom: 20
        }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: "#93c5fd", marginBottom: 4 }}>
            Theorem ({proof.textbook}, Ch. {proof.chapter})
          </div>
          <div style={{ fontSize: 13, color: "#e2e8f0", lineHeight: 1.6 }}>
            {proof.statement}
          </div>
        </div>

        {/* Controls */}
        <div style={{ display: "flex", gap: 8, marginBottom: 16, alignItems: "center" }}>
          <div style={{ display: "flex", borderRadius: 6, overflow: "hidden", border: "1px solid #334155" }}>
            <button onClick={() => setMode("intuition")} style={{
              background: mode === "intuition" ? "#334155" : "transparent",
              border: "none", padding: "6px 14px", color: mode === "intuition" ? "#f8fafc" : "#64748b",
              fontSize: 11, cursor: "pointer", fontFamily: "inherit"
            }}>💡 Intuition</button>
            <button onClick={() => setMode("formal")} style={{
              background: mode === "formal" ? "#334155" : "transparent",
              border: "none", padding: "6px 14px", color: mode === "formal" ? "#f8fafc" : "#64748b",
              fontSize: 11, cursor: "pointer", fontFamily: "inherit"
            }}>📐 Formal</button>
          </div>
          <div style={{ flex: 1 }} />
          <button onClick={expandAll} style={{
            background: "transparent", border: "1px solid #334155", borderRadius: 4,
            padding: "4px 10px", color: "#64748b", fontSize: 10, cursor: "pointer", fontFamily: "inherit"
          }}>Expand all</button>
          <button onClick={collapseAll} style={{
            background: "transparent", border: "1px solid #334155", borderRadius: 4,
            padding: "4px 10px", color: "#64748b", fontSize: 10, cursor: "pointer", fontFamily: "inherit"
          }}>Collapse all</button>
        </div>

        {/* Proof steps */}
        <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          {proof.steps.map(step => (
            <ProofStep
              key={step.id}
              step={step}
              mode={mode}
              isOpen={openSteps.has(step.id)}
              onToggle={() => toggleStep(step.id)}
            />
          ))}
        </div>

        {/* QED */}
        <div style={{ textAlign: "right", fontSize: 18, color: "#64748b", marginTop: 12 }}>□</div>
      </div>
    </div>
  );
}
