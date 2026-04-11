import { useState, useEffect, useCallback, useMemo } from "react";

// ═══════════════════════════════════════════════════════════════════
// Self-Assessment Quiz Engine
// Spaced repetition, multiple question types, track-based filtering
// ═══════════════════════════════════════════════════════════════════

const TRACKS = {
  CORE: { label: "Core Mathematics", color: "#2563eb", icon: "∑" },
  BIOS: { label: "Biostatistics", color: "#059669", icon: "📊" },
  GEO:  { label: "Geospatial", color: "#d97706", icon: "🌍" },
  ABM:  { label: "Agent-Based", color: "#dc2626", icon: "🤖" },
  SCIML:{ label: "Scientific ML", color: "#7c3aed", icon: "🧠" },
  POP:  { label: "Population", color: "#0891b2", icon: "📈" },
  PHYS: { label: "Physical Systems", color: "#be185d", icon: "⚙️" },
  XCUT: { label: "Cross-Cutting", color: "#4b5563", icon: "🔗" },
};

// Question bank — in production this would be generated from chapter content
const QUESTIONS = [
  // CORE — Real Analysis
  { id: 1, track: "CORE", textbook: "CORE-001", chapter: 2, type: "mc", difficulty: "apply",
    question: "Which of the following is NOT a property required for (X, d) to be a metric space?",
    options: ["d(x, y) ≥ 0 for all x, y", "d(x, y) = 0 if and only if x = y", "d(x, y) + d(y, z) ≥ d(x, z)", "d(x, y) ≤ d(x, z) · d(z, y)"],
    correct: 3, explanation: "The triangle inequality states d(x,z) ≤ d(x,y) + d(y,z), which is additive, not multiplicative. The multiplicative version is not a metric space axiom." },
  { id: 2, track: "CORE", textbook: "CORE-001", chapter: 3, type: "mc", difficulty: "analyze",
    question: "The Bolzano-Weierstrass theorem guarantees that every bounded sequence in ℝⁿ has a convergent subsequence. Which assumption, if removed, causes the theorem to FAIL?",
    options: ["The sequence must be in ℝⁿ (finite dimensional)", "The sequence must be bounded", "The sequence must have infinitely many terms", "All of the above are individually necessary"],
    correct: 3, explanation: "All three conditions are necessary: (1) In infinite-dimensional spaces, the unit ball is not sequentially compact. (2) The sequence (n) in ℝ is unbounded and has no convergent subsequence. (3) A finite sequence trivially has only finitely many subsequences." },
  { id: 3, track: "CORE", textbook: "CORE-001", chapter: 1, type: "tf", difficulty: "apply",
    question: "Every Cauchy sequence in ℝ converges.",
    correct: true, explanation: "ℝ is complete, meaning every Cauchy sequence converges. This is the completeness axiom of the real numbers." },
  { id: 4, track: "CORE", textbook: "CORE-001", chapter: 4, type: "mc", difficulty: "analyze",
    question: "Which statement about uniform convergence is FALSE?",
    options: [
      "If fₙ → f uniformly and each fₙ is continuous, then f is continuous",
      "If fₙ → f uniformly on [a,b], then ∫fₙ → ∫f",
      "If fₙ → f uniformly and each fₙ is differentiable, then f is differentiable",
      "Uniform convergence implies pointwise convergence"
    ],
    correct: 2, explanation: "Uniform convergence of differentiable functions does NOT guarantee differentiability of the limit. You also need the derivatives to converge uniformly. Classic counterexample: fₙ(x) = xⁿ/n on [0,1]." },

  // CORE — Linear Algebra
  { id: 5, track: "CORE", textbook: "CORE-002", chapter: 4, type: "mc", difficulty: "apply",
    question: "If A is a 3×3 matrix with eigenvalues 2, 3, 5, what is det(A)?",
    options: ["10", "30", "15", "Cannot be determined"],
    correct: 1, explanation: "The determinant equals the product of eigenvalues: det(A) = 2 × 3 × 5 = 30." },
  { id: 6, track: "CORE", textbook: "CORE-002", chapter: 5, type: "mc", difficulty: "analyze",
    question: "The condition number κ(A) = σₘₐₓ/σₘᵢₙ of a matrix measures sensitivity to perturbations. If κ(A) = 10¹², which is the best strategy?",
    options: ["Use standard LU factorization", "Use iterative refinement or regularization", "Increase floating-point precision to quad", "The problem is unsolvable"],
    correct: 1, explanation: "With κ(A) ≈ 10¹² in double precision (≈15 digits), you lose about 12 digits of accuracy, leaving only ~3 reliable digits. Iterative refinement or Tikhonov regularization can recover accuracy. Simply increasing precision is wasteful; the ill-conditioning is a property of the problem, not the arithmetic." },

  // CORE — Probability
  { id: 7, track: "CORE", textbook: "CORE-003", chapter: 5, type: "mc", difficulty: "apply",
    question: "If X ~ N(0,1), what is P(|X| > 1.96)?",
    options: ["0.01", "0.025", "0.05", "0.10"],
    correct: 2, explanation: "P(|X| > 1.96) = 2 × P(X > 1.96) ≈ 2 × 0.025 = 0.05. This is the basis of the 95% confidence interval for the normal distribution." },

  // CORE — ODEs
  { id: 8, track: "CORE", textbook: "CORE-006", chapter: 1, type: "mc", difficulty: "apply",
    question: "For the ODE y' = f(t, y), the Picard-Lindelöf theorem guarantees existence and uniqueness of solutions when f is:",
    options: ["Continuous in both arguments", "Lipschitz continuous in y", "Differentiable in both arguments", "Continuous in t and Lipschitz in y"],
    correct: 3, explanation: "The Picard-Lindelöf theorem requires f to be continuous in t and Lipschitz continuous in y. Continuity alone (Peano's theorem) gives existence but not uniqueness." },

  // CORE — Bayesian
  { id: 9, track: "CORE", textbook: "CORE-008", chapter: 1, type: "mc", difficulty: "apply",
    question: "In Bayesian inference, the posterior is proportional to:",
    options: ["Prior × Evidence", "Likelihood × Evidence", "Prior × Likelihood", "Likelihood / Prior"],
    correct: 2, explanation: "Bayes' theorem: P(θ|data) ∝ P(data|θ) × P(θ) = Likelihood × Prior. The evidence P(data) is a normalizing constant." },
  { id: 10, track: "CORE", textbook: "CORE-008", chapter: 4, type: "mc", difficulty: "analyze",
    question: "Which is NOT a valid diagnostic for MCMC convergence?",
    options: ["R̂ (Gelman-Rubin) close to 1", "Effective sample size > 400", "Trace plots showing no trend", "All posterior samples are positive"],
    correct: 3, explanation: "Positive samples simply reflect the posterior's support — they say nothing about convergence. R̂, ESS, and stationary trace plots are all standard convergence diagnostics." },

  // BIOS
  { id: 11, track: "BIOS", textbook: "BIOS-001", chapter: 1, type: "mc", difficulty: "apply",
    question: "In a GLM, the link function g(·) maps:",
    options: ["Predictors to responses", "Mean response to linear predictor", "Variance to mean", "Residuals to normal distribution"],
    correct: 1, explanation: "The link function maps the expected value of the response E[Y] = μ to the linear predictor η = Xβ: g(μ) = η." },
  { id: 12, track: "BIOS", textbook: "BIOS-002", chapter: 1, type: "mc", difficulty: "analyze",
    question: "The Cox proportional hazards model assumes:",
    options: ["Exponential baseline hazard", "Hazard ratios are constant over time", "Survival times are normally distributed", "Censoring depends on covariates"],
    correct: 1, explanation: "The key assumption is proportional hazards: the hazard ratio between any two individuals is constant over time. The baseline hazard is left unspecified (semi-parametric)." },
  { id: 13, track: "BIOS", textbook: "BIOS-004", chapter: 1, type: "mc", difficulty: "analyze",
    question: "The fundamental problem of causal inference is:",
    options: ["We cannot randomize in observational studies", "We can never observe both potential outcomes for the same unit", "Confounding is always present", "Sample sizes are never large enough"],
    correct: 1, explanation: "The fundamental problem is that for any unit, we observe at most one potential outcome (the one under the treatment actually received). The counterfactual outcome is always missing." },

  // SCIML
  { id: 14, track: "SCIML", textbook: "SCIML-002", chapter: 1, type: "mc", difficulty: "analyze",
    question: "A Physics-Informed Neural Network (PINN) embeds physical constraints by:",
    options: ["Training only on simulation data", "Adding PDE residual terms to the loss function", "Using physics-based activation functions", "Constraining network weights to be positive"],
    correct: 1, explanation: "PINNs add the PDE residual (evaluated at collocation points) as an additional term in the loss function, penalizing solutions that violate the governing equations." },
  { id: 15, track: "SCIML", textbook: "SCIML-004", chapter: 1, type: "mc", difficulty: "apply",
    question: "Forward-mode automatic differentiation computes derivatives by:",
    options: ["Finite differences", "Symbolic differentiation", "Propagating tangent vectors through the computation graph", "Backpropagating adjoint vectors through the computation graph"],
    correct: 2, explanation: "Forward-mode AD propagates tangent (directional derivative) information forward through the computation graph using dual numbers. Reverse-mode (option D) propagates adjoint information backward." },

  // POP
  { id: 16, track: "POP", textbook: "POP-001", chapter: 1, type: "mc", difficulty: "apply",
    question: "In the logistic growth model dN/dt = rN(1 - N/K), the parameter K represents:",
    options: ["Growth rate", "Initial population", "Carrying capacity", "Death rate"],
    correct: 2, explanation: "K is the carrying capacity — the maximum population the environment can sustain. As N → K, the growth rate approaches zero." },

  // PHYS
  { id: 17, track: "PHYS", textbook: "PHYS-002", chapter: 1, type: "mc", difficulty: "analyze",
    question: "The Reynolds number Re determines whether fluid flow is laminar or turbulent. Which statement is correct?",
    options: ["High Re → laminar flow", "Re = inertial forces / viscous forces", "Re is dimensionless only in SI units", "Re depends on temperature but not velocity"],
    correct: 1, explanation: "Re = ρvL/μ = inertial forces / viscous forces. It is a dimensionless number (unit-system independent). High Re indicates turbulent flow; low Re indicates laminar flow." },

  // XCUT
  { id: 18, track: "XCUT", textbook: "XCUT-001", chapter: 1, type: "mc", difficulty: "analyze",
    question: "In uncertainty quantification, epistemic uncertainty differs from aleatoric uncertainty because:",
    options: ["Epistemic uncertainty is always larger", "Epistemic uncertainty can be reduced with more data", "Aleatoric uncertainty is always Gaussian", "They are mathematically identical"],
    correct: 1, explanation: "Epistemic uncertainty arises from lack of knowledge and can be reduced with more data or better models. Aleatoric uncertainty is inherent randomness in the system and cannot be reduced by collecting more data." },
];

// Spaced repetition helpers
function getNextReview(box) {
  const intervals = [0, 1, 3, 7, 14, 30, 60]; // days
  return intervals[Math.min(box, intervals.length - 1)];
}

function shuffleArray(arr) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

export default function QuizEngine() {
  const [activeTrack, setActiveTrack] = useState(null);
  const [activeDifficulty, setActiveDifficulty] = useState(null);
  const [mode, setMode] = useState("menu"); // menu | quiz | review
  const [queue, setQueue] = useState([]);
  const [currentIdx, setCurrentIdx] = useState(0);
  const [selectedAnswer, setSelectedAnswer] = useState(null);
  const [showExplanation, setShowExplanation] = useState(false);
  const [results, setResults] = useState([]); // {id, correct, timestamp}
  const [stats, setStats] = useState({}); // id -> {box, lastReview, correct, total}

  const filteredQuestions = useMemo(() => {
    let qs = QUESTIONS;
    if (activeTrack) qs = qs.filter(q => q.track === activeTrack);
    if (activeDifficulty) qs = qs.filter(q => q.difficulty === activeDifficulty);
    return qs;
  }, [activeTrack, activeDifficulty]);

  const startQuiz = useCallback((n = 10) => {
    const shuffled = shuffleArray(filteredQuestions).slice(0, n);
    setQueue(shuffled);
    setCurrentIdx(0);
    setSelectedAnswer(null);
    setShowExplanation(false);
    setResults([]);
    setMode("quiz");
  }, [filteredQuestions]);

  const currentQ = queue[currentIdx];

  const submitAnswer = useCallback(() => {
    if (selectedAnswer === null) return;
    setShowExplanation(true);
    const isCorrect = currentQ.type === "tf"
      ? selectedAnswer === (currentQ.correct ? 0 : 1)
      : selectedAnswer === currentQ.correct;
    setResults(prev => [...prev, { id: currentQ.id, correct: isCorrect }]);
    setStats(prev => {
      const old = prev[currentQ.id] || { box: 0, correct: 0, total: 0 };
      return {
        ...prev,
        [currentQ.id]: {
          box: isCorrect ? Math.min(old.box + 1, 6) : Math.max(old.box - 1, 0),
          correct: old.correct + (isCorrect ? 1 : 0),
          total: old.total + 1,
          lastReview: Date.now(),
        },
      };
    });
  }, [selectedAnswer, currentQ]);

  const nextQuestion = useCallback(() => {
    if (currentIdx < queue.length - 1) {
      setCurrentIdx(prev => prev + 1);
      setSelectedAnswer(null);
      setShowExplanation(false);
    } else {
      setMode("review");
    }
  }, [currentIdx, queue.length]);

  const score = results.filter(r => r.correct).length;
  const total = results.length;

  // ── Menu Screen ──
  if (mode === "menu") {
    return (
      <div style={{ fontFamily: "'JetBrains Mono', monospace", background: "#0f172a", color: "#e2e8f0", minHeight: "100vh", padding: 24 }}>
        <div style={{ maxWidth: 700, margin: "0 auto" }}>
          <h1 style={{ fontSize: 22, fontWeight: 700, marginBottom: 4, color: "#f8fafc" }}>
            <span style={{ color: "#8b5cf6" }}>◆</span> Quiz Engine
          </h1>
          <p style={{ fontSize: 12, color: "#64748b", marginBottom: 24 }}>
            Spaced-repetition self-assessment across the modeling curriculum
          </p>

          {/* Track filter */}
          <div style={{ fontSize: 12, fontWeight: 600, color: "#94a3b8", marginBottom: 8 }}>FILTER BY TRACK</div>
          <div style={{ display: "flex", gap: 8, marginBottom: 20, flexWrap: "wrap" }}>
            <button onClick={() => setActiveTrack(null)} style={{
              background: !activeTrack ? "#334155" : "transparent",
              border: "1px solid #475569", borderRadius: 6, padding: "6px 14px",
              color: !activeTrack ? "#f8fafc" : "#64748b", fontSize: 11, cursor: "pointer", fontFamily: "inherit"
            }}>All ({QUESTIONS.length})</button>
            {Object.entries(TRACKS).map(([key, t]) => {
              const count = QUESTIONS.filter(q => q.track === key).length;
              return (
                <button key={key} onClick={() => setActiveTrack(prev => prev === key ? null : key)} style={{
                  background: activeTrack === key ? t.color : "transparent",
                  border: `1px solid ${t.color}`, borderRadius: 6, padding: "6px 14px",
                  color: activeTrack === key ? "#fff" : t.color, fontSize: 11, cursor: "pointer", fontFamily: "inherit"
                }}>{t.icon} {t.label} ({count})</button>
              );
            })}
          </div>

          {/* Difficulty filter */}
          <div style={{ fontSize: 12, fontWeight: 600, color: "#94a3b8", marginBottom: 8 }}>DIFFICULTY</div>
          <div style={{ display: "flex", gap: 8, marginBottom: 24 }}>
            {[null, "apply", "analyze", "create"].map(d => (
              <button key={d || "all"} onClick={() => setActiveDifficulty(d)} style={{
                background: activeDifficulty === d ? "#334155" : "transparent",
                border: "1px solid #475569", borderRadius: 6, padding: "6px 14px",
                color: activeDifficulty === d ? "#f8fafc" : "#64748b", fontSize: 11, cursor: "pointer", fontFamily: "inherit"
              }}>{d ? d.charAt(0).toUpperCase() + d.slice(1) : "All"}</button>
            ))}
          </div>

          {/* Start */}
          <div style={{ background: "#1e293b", borderRadius: 8, padding: 24, textAlign: "center" }}>
            <div style={{ fontSize: 32, marginBottom: 8 }}>{filteredQuestions.length}</div>
            <div style={{ fontSize: 12, color: "#64748b", marginBottom: 20 }}>questions available</div>
            <button onClick={() => startQuiz(Math.min(10, filteredQuestions.length))} disabled={filteredQuestions.length === 0} style={{
              background: "#2563eb", border: "none", borderRadius: 8, padding: "12px 32px",
              color: "#fff", fontSize: 14, fontWeight: 600, cursor: "pointer", fontFamily: "inherit",
              opacity: filteredQuestions.length === 0 ? 0.3 : 1
            }}>Start Quiz ({Math.min(10, filteredQuestions.length)} questions)</button>
          </div>

          {/* Stats summary */}
          {Object.keys(stats).length > 0 && (
            <div style={{ marginTop: 24 }}>
              <div style={{ fontSize: 12, fontWeight: 600, color: "#94a3b8", marginBottom: 8 }}>YOUR PROGRESS</div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 12 }}>
                <div style={{ background: "#1e293b", borderRadius: 6, padding: 12, textAlign: "center" }}>
                  <div style={{ fontSize: 24, color: "#10b981" }}>{Object.values(stats).reduce((a, s) => a + s.correct, 0)}</div>
                  <div style={{ fontSize: 10, color: "#64748b" }}>Correct</div>
                </div>
                <div style={{ background: "#1e293b", borderRadius: 6, padding: 12, textAlign: "center" }}>
                  <div style={{ fontSize: 24, color: "#f8fafc" }}>{Object.values(stats).reduce((a, s) => a + s.total, 0)}</div>
                  <div style={{ fontSize: 10, color: "#64748b" }}>Attempted</div>
                </div>
                <div style={{ background: "#1e293b", borderRadius: 6, padding: 12, textAlign: "center" }}>
                  <div style={{ fontSize: 24, color: "#fbbf24" }}>{Object.values(stats).filter(s => s.box >= 3).length}</div>
                  <div style={{ fontSize: 10, color: "#64748b" }}>Mastered</div>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    );
  }

  // ── Review Screen ──
  if (mode === "review") {
    const pct = total > 0 ? Math.round(100 * score / total) : 0;
    return (
      <div style={{ fontFamily: "'JetBrains Mono', monospace", background: "#0f172a", color: "#e2e8f0", minHeight: "100vh", padding: 24 }}>
        <div style={{ maxWidth: 600, margin: "0 auto", textAlign: "center" }}>
          <div style={{ fontSize: 64, marginBottom: 8 }}>{pct >= 80 ? "🎯" : pct >= 50 ? "📚" : "💪"}</div>
          <h2 style={{ fontSize: 24, fontWeight: 700, color: "#f8fafc", marginBottom: 8 }}>Quiz Complete</h2>
          <div style={{ fontSize: 48, fontWeight: 700, color: pct >= 80 ? "#10b981" : pct >= 50 ? "#fbbf24" : "#ef4444", marginBottom: 8 }}>
            {score}/{total}
          </div>
          <div style={{ fontSize: 14, color: "#64748b", marginBottom: 32 }}>{pct}% correct</div>

          {/* Per-question review */}
          <div style={{ textAlign: "left" }}>
            {queue.map((q, i) => {
              const r = results[i];
              if (!r) return null;
              return (
                <div key={q.id} style={{
                  background: "#1e293b", borderRadius: 6, padding: 12, marginBottom: 8,
                  borderLeft: `3px solid ${r.correct ? "#10b981" : "#ef4444"}`
                }}>
                  <div style={{ fontSize: 11, color: r.correct ? "#10b981" : "#ef4444", marginBottom: 4 }}>
                    {r.correct ? "✓ Correct" : "✗ Incorrect"} — {q.textbook} Ch.{q.chapter}
                  </div>
                  <div style={{ fontSize: 12, color: "#cbd5e1" }}>{q.question}</div>
                </div>
              );
            })}
          </div>

          <button onClick={() => setMode("menu")} style={{
            background: "#2563eb", border: "none", borderRadius: 8, padding: "12px 32px",
            color: "#fff", fontSize: 14, fontWeight: 600, cursor: "pointer", fontFamily: "inherit", marginTop: 24
          }}>Back to Menu</button>
        </div>
      </div>
    );
  }

  // ── Quiz Screen ──
  const track = TRACKS[currentQ.track];
  const isCorrect = currentQ.type === "tf"
    ? selectedAnswer === (currentQ.correct ? 0 : 1)
    : selectedAnswer === currentQ.correct;

  const options = currentQ.type === "tf"
    ? ["True", "False"]
    : currentQ.options;

  return (
    <div style={{ fontFamily: "'JetBrains Mono', monospace", background: "#0f172a", color: "#e2e8f0", minHeight: "100vh", padding: 24 }}>
      <div style={{ maxWidth: 650, margin: "0 auto" }}>
        {/* Progress bar */}
        <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 20 }}>
          <div style={{ flex: 1, height: 4, background: "#1e293b", borderRadius: 2, overflow: "hidden" }}>
            <div style={{ width: `${((currentIdx + 1) / queue.length) * 100}%`, height: "100%", background: "#2563eb", transition: "width 0.3s" }} />
          </div>
          <span style={{ fontSize: 11, color: "#64748b" }}>{currentIdx + 1}/{queue.length}</span>
          <span style={{ fontSize: 11, color: "#64748b" }}>Score: {score}/{total}</span>
        </div>

        {/* Question card */}
        <div style={{ background: "#1e293b", borderRadius: 12, padding: 24, marginBottom: 16 }}>
          {/* Meta */}
          <div style={{ display: "flex", gap: 8, marginBottom: 16 }}>
            <span style={{ background: track.color, color: "#fff", padding: "2px 8px", borderRadius: 4, fontSize: 10 }}>{track.label}</span>
            <span style={{ background: "#334155", padding: "2px 8px", borderRadius: 4, fontSize: 10, color: "#94a3b8" }}>{currentQ.textbook} Ch.{currentQ.chapter}</span>
            <span style={{ background: "#334155", padding: "2px 8px", borderRadius: 4, fontSize: 10, color: "#94a3b8", textTransform: "capitalize" }}>{currentQ.difficulty}</span>
          </div>

          {/* Question */}
          <div style={{ fontSize: 15, lineHeight: 1.6, color: "#f8fafc", marginBottom: 24 }}>
            {currentQ.question}
          </div>

          {/* Options */}
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {options.map((opt, i) => {
              let bg = "#0f172a";
              let border = "#334155";
              let textColor = "#cbd5e1";

              if (showExplanation) {
                const correctIdx = currentQ.type === "tf" ? (currentQ.correct ? 0 : 1) : currentQ.correct;
                if (i === correctIdx) { bg = "#052e16"; border = "#10b981"; textColor = "#10b981"; }
                else if (i === selectedAnswer && !isCorrect) { bg = "#310a0a"; border = "#ef4444"; textColor = "#ef4444"; }
              } else if (selectedAnswer === i) {
                bg = "#172554"; border = "#2563eb"; textColor = "#93c5fd";
              }

              return (
                <button key={i} onClick={() => !showExplanation && setSelectedAnswer(i)} disabled={showExplanation} style={{
                  background: bg, border: `1px solid ${border}`, borderRadius: 8,
                  padding: "12px 16px", textAlign: "left", cursor: showExplanation ? "default" : "pointer",
                  color: textColor, fontSize: 13, fontFamily: "inherit", transition: "all 0.15s",
                  display: "flex", alignItems: "flex-start", gap: 10
                }}>
                  <span style={{ color: "#475569", fontWeight: 600, minWidth: 20 }}>{String.fromCharCode(65 + i)}.</span>
                  <span>{opt}</span>
                </button>
              );
            })}
          </div>
        </div>

        {/* Explanation */}
        {showExplanation && (
          <div style={{
            background: isCorrect ? "#052e16" : "#310a0a",
            border: `1px solid ${isCorrect ? "#10b981" : "#ef4444"}`,
            borderRadius: 8, padding: 16, marginBottom: 16
          }}>
            <div style={{ fontSize: 13, fontWeight: 600, color: isCorrect ? "#10b981" : "#ef4444", marginBottom: 8 }}>
              {isCorrect ? "✓ Correct!" : "✗ Incorrect"}
            </div>
            <div style={{ fontSize: 12, color: "#cbd5e1", lineHeight: 1.6 }}>
              {currentQ.explanation}
            </div>
          </div>
        )}

        {/* Action buttons */}
        <div style={{ display: "flex", justifyContent: "flex-end", gap: 12 }}>
          {!showExplanation ? (
            <button onClick={submitAnswer} disabled={selectedAnswer === null} style={{
              background: selectedAnswer !== null ? "#2563eb" : "#1e293b",
              border: "none", borderRadius: 8, padding: "10px 28px",
              color: "#fff", fontSize: 13, fontWeight: 600, cursor: selectedAnswer !== null ? "pointer" : "default",
              fontFamily: "inherit", opacity: selectedAnswer !== null ? 1 : 0.4
            }}>Check Answer</button>
          ) : (
            <button onClick={nextQuestion} style={{
              background: "#2563eb", border: "none", borderRadius: 8, padding: "10px 28px",
              color: "#fff", fontSize: 13, fontWeight: 600, cursor: "pointer", fontFamily: "inherit"
            }}>{currentIdx < queue.length - 1 ? "Next Question →" : "See Results"}</button>
          )}
        </div>
      </div>
    </div>
  );
}
