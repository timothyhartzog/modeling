import { useState, useEffect, useCallback, useMemo } from "react";

// ═══════════════════════════════════════════════════════════════════
// Curriculum Progress Dashboard
// Persistent tracking: chapters read, quizzes passed, labs completed
// Uses window.storage API for cross-session persistence
// ═══════════════════════════════════════════════════════════════════

const CURRICULUM = [
  { track: "CORE", color: "#2563eb", icon: "∑", textbooks: [
    { id: "CORE-001", title: "Real Analysis", chapters: 10 },
    { id: "CORE-002", title: "Linear Algebra", chapters: 8 },
    { id: "CORE-003", title: "Measure-Theoretic Probability", chapters: 8 },
    { id: "CORE-004", title: "Scientific Computing I", chapters: 7 },
    { id: "CORE-005", title: "Functional Analysis", chapters: 8 },
    { id: "CORE-006", title: "Probability Theory II", chapters: 10 },
    { id: "CORE-007", title: "Ordinary DEs", chapters: 10 },
    { id: "CORE-008", title: "Mathematical Statistics", chapters: 8 },
    { id: "CORE-009", title: "PDEs I", chapters: 9 },
    { id: "CORE-010", title: "Stochastic Processes", chapters: 9 },
    { id: "CORE-011", title: "Bayesian Theory", chapters: 9 },
    { id: "CORE-012", title: "Numerical Methods for DEs", chapters: 8 },
    { id: "CORE-013", title: "Differential Geometry", chapters: 7 },
    { id: "CORE-014", title: "PDEs II: Nonlinear", chapters: 8 },
    { id: "CORE-015", title: "Computational Statistics", chapters: 9 },
    { id: "CORE-016", title: "Optimization Theory", chapters: 10 },
    { id: "CORE-017", title: "Numerical Linear Algebra", chapters: 11 },
  ]},
  { track: "BIO", color: "#059669", icon: "🧬", textbooks: [
    { id: "BIO-001", title: "Generalized Linear Models", chapters: 8 },
    { id: "BIO-002", title: "Survival Analysis", chapters: 8 },
    { id: "BIO-003", title: "Longitudinal Data", chapters: 8 },
    { id: "BIO-004", title: "Causal Inference", chapters: 8 },
    { id: "BIO-005", title: "Clinical Trials", chapters: 8 },
    { id: "BIO-006", title: "High-Dimensional Stats", chapters: 8 },
    { id: "BIO-007", title: "Epidemic Models", chapters: 8 },
    { id: "BIO-008", title: "Spatial Epidemiology", chapters: 8 },
  ]},
  { track: "GEO", color: "#d97706", icon: "🌍", textbooks: [
    { id: "GEO-001", title: "Geostatistics & Kriging", chapters: 8 },
    { id: "GEO-002", title: "Point Processes", chapters: 8 },
    { id: "GEO-003", title: "Areal Data", chapters: 8 },
    { id: "GEO-004", title: "Space-Time Models", chapters: 8 },
    { id: "GEO-005", title: "Remote Sensing", chapters: 8 },
  ]},
  { track: "SCIML", color: "#7c3aed", icon: "🧠", textbooks: [
    { id: "SCIML-001", title: "Neural ODEs / UDEs", chapters: 8 },
    { id: "SCIML-002", title: "Deep Learning Theory", chapters: 8 },
    { id: "SCIML-003", title: "Probabilistic ML", chapters: 8 },
    { id: "SCIML-004", title: "Automatic Differentiation", chapters: 8 },
    { id: "SCIML-005", title: "ML for Inverse Problems", chapters: 8 },
  ]},
  { track: "ABM", color: "#dc2626", icon: "🤖", textbooks: [
    { id: "ABM-001", title: "ABM Foundations", chapters: 8 },
    { id: "ABM-002", title: "Network Science", chapters: 8 },
    { id: "ABM-003", title: "Mean-Field Theory", chapters: 8 },
    { id: "ABM-004", title: "Evolutionary Game Theory", chapters: 8 },
  ]},
  { track: "POP", color: "#0891b2", icon: "📈", textbooks: [
    { id: "POP-001", title: "Deterministic Population", chapters: 8 },
    { id: "POP-002", title: "Stochastic Population", chapters: 8 },
    { id: "POP-003", title: "Systems Biology", chapters: 8 },
    { id: "POP-004", title: "Demography", chapters: 8 },
  ]},
  { track: "PHYS", color: "#be185d", icon: "⚙️", textbooks: [
    { id: "PHYS-001", title: "Continuum Mechanics", chapters: 8 },
    { id: "PHYS-002", title: "Geophysical Fluids", chapters: 8 },
    { id: "PHYS-003", title: "Fluid Dynamics", chapters: 8 },
    { id: "PHYS-004", title: "Biomechanics", chapters: 8 },
  ]},
  { track: "XCUT", color: "#4b5563", icon: "🔗", textbooks: [
    { id: "UQ-001", title: "Uncertainty Quantification", chapters: 8 },
    { id: "CROSS-001", title: "Dynamical Systems", chapters: 8 },
    { id: "CROSS-002", title: "Optimal Transport", chapters: 8 },
    { id: "CROSS-003", title: "Inverse Problems", chapters: 8 },
    { id: "CROSS-004", title: "Information Geometry", chapters: 8 },
    { id: "CROSS-005", title: "Multiscale Methods", chapters: 8 },
    { id: "CROSS-006", title: "Model Selection", chapters: 10 },
  ]},
];

const LABS = [
  { id: "lab1", title: "Clinical Trial Pipeline", tracks: ["BIO", "CORE"] },
  { id: "lab2", title: "Equation Discovery", tracks: ["SCIML", "XCUT"] },
  { id: "lab3", title: "Spatial Disease Spread", tracks: ["BIO", "GEO", "ABM"] },
  { id: "lab4", title: "Blood Flow Simulation", tracks: ["PHYS", "CORE"] },
  { id: "lab5", title: "Bayesian Model Selection", tracks: ["CORE", "POP", "XCUT"] },
];

const STORAGE_KEY = "modeling-progress";

function useProgress() {
  const [progress, setProgress] = useState({ chapters: {}, quizzes: {}, labs: {} });
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    async function load() {
      try {
        const result = await window.storage.get(STORAGE_KEY);
        if (result?.value) setProgress(JSON.parse(result.value));
      } catch { /* first load */ }
      setLoaded(true);
    }
    load();
  }, []);

  const save = useCallback(async (newProgress) => {
    setProgress(newProgress);
    try {
      await window.storage.set(STORAGE_KEY, JSON.stringify(newProgress));
    } catch (e) { console.error("Storage save failed:", e); }
  }, []);

  return { progress, save, loaded };
}

function ProgressRing({ percent, size = 48, stroke = 4, color }) {
  const r = (size - stroke) / 2;
  const circ = 2 * Math.PI * r;
  const offset = circ * (1 - percent / 100);
  return (
    <svg width={size} height={size} style={{ transform: "rotate(-90deg)" }}>
      <circle cx={size/2} cy={size/2} r={r} fill="none" stroke="#1e293b" strokeWidth={stroke} />
      <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={color} strokeWidth={stroke}
        strokeDasharray={circ} strokeDashoffset={offset} strokeLinecap="round"
        style={{ transition: "stroke-dashoffset 0.5s ease" }} />
      <text x={size/2} y={size/2} textAnchor="middle" dominantBaseline="central"
        fill="#f8fafc" fontSize={size < 40 ? 9 : 11} fontWeight={700}
        style={{ transform: "rotate(90deg)", transformOrigin: "center" }}>
        {Math.round(percent)}%
      </text>
    </svg>
  );
}

function ChapterGrid({ textbookId, totalChapters, completedChapters, onToggle }) {
  return (
    <div style={{ display: "flex", gap: 3, flexWrap: "wrap" }}>
      {Array.from({ length: totalChapters }, (_, i) => {
        const key = `${textbookId}/ch${String(i + 1).padStart(2, "0")}`;
        const done = completedChapters.has(key);
        return (
          <button key={i} onClick={() => onToggle(key)} title={`Chapter ${i + 1}`}
            style={{
              width: 18, height: 18, borderRadius: 3, border: "none",
              background: done ? "#10b981" : "#1e293b", cursor: "pointer",
              fontSize: 8, color: done ? "#fff" : "#334155", fontFamily: "inherit",
              display: "flex", alignItems: "center", justifyContent: "center",
            }}>
            {i + 1}
          </button>
        );
      })}
    </div>
  );
}

export default function ProgressDashboard() {
  const { progress, save, loaded } = useProgress();
  const [expandedTrack, setExpandedTrack] = useState(null);

  const completedSet = useMemo(() => new Set(Object.keys(progress.chapters || {}).filter(k => progress.chapters[k])), [progress]);
  const quizSet = useMemo(() => new Set(Object.keys(progress.quizzes || {}).filter(k => progress.quizzes[k])), [progress]);
  const labSet = useMemo(() => new Set(Object.keys(progress.labs || {}).filter(k => progress.labs[k])), [progress]);

  const totalChapters = CURRICULUM.reduce((a, t) => a + t.textbooks.reduce((b, tb) => b + tb.chapters, 0), 0);
  const completedChapters = completedSet.size;
  const overallPct = totalChapters > 0 ? (completedChapters / totalChapters) * 100 : 0;

  const toggleChapter = useCallback((key) => {
    const next = { ...progress, chapters: { ...progress.chapters, [key]: !progress.chapters?.[key] } };
    save(next);
  }, [progress, save]);

  const toggleLab = useCallback((labId) => {
    const next = { ...progress, labs: { ...progress.labs, [labId]: !progress.labs?.[labId] } };
    save(next);
  }, [progress, save]);

  const resetAll = useCallback(() => {
    if (confirm("Reset all progress? This cannot be undone.")) {
      save({ chapters: {}, quizzes: {}, labs: {} });
    }
  }, [save]);

  if (!loaded) return <div style={{ background: "#0f172a", color: "#64748b", padding: 40, textAlign: "center", fontFamily: "monospace" }}>Loading...</div>;

  return (
    <div style={{ fontFamily: "'JetBrains Mono', 'Fira Code', monospace", background: "#0f172a", color: "#e2e8f0", minHeight: "100vh", padding: 20 }}>
      <div style={{ maxWidth: 900, margin: "0 auto" }}>
        {/* Header */}
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 24 }}>
          <div>
            <h1 style={{ fontSize: 20, fontWeight: 700, color: "#f8fafc", margin: 0 }}>
              <span style={{ color: "#10b981" }}>◆</span> Progress Dashboard
            </h1>
            <p style={{ fontSize: 11, color: "#64748b", margin: "4px 0 0" }}>
              Track your journey through {totalChapters} chapters
            </p>
          </div>
          <ProgressRing percent={overallPct} size={64} stroke={5} color="#10b981" />
        </div>

        {/* Summary cards */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 12, marginBottom: 24 }}>
          <div style={{ background: "#1e293b", borderRadius: 8, padding: 14, textAlign: "center" }}>
            <div style={{ fontSize: 28, fontWeight: 700, color: "#10b981" }}>{completedChapters}</div>
            <div style={{ fontSize: 10, color: "#64748b" }}>Chapters</div>
          </div>
          <div style={{ background: "#1e293b", borderRadius: 8, padding: 14, textAlign: "center" }}>
            <div style={{ fontSize: 28, fontWeight: 700, color: "#3b82f6" }}>{quizSet.size}</div>
            <div style={{ fontSize: 10, color: "#64748b" }}>Quizzes</div>
          </div>
          <div style={{ background: "#1e293b", borderRadius: 8, padding: 14, textAlign: "center" }}>
            <div style={{ fontSize: 28, fontWeight: 700, color: "#f59e0b" }}>{labSet.size}</div>
            <div style={{ fontSize: 10, color: "#64748b" }}>Labs</div>
          </div>
          <div style={{ background: "#1e293b", borderRadius: 8, padding: 14, textAlign: "center" }}>
            <div style={{ fontSize: 28, fontWeight: 700, color: "#8b5cf6" }}>
              {CURRICULUM.reduce((a, t) => {
                const trackTotal = t.textbooks.reduce((b, tb) => b + tb.chapters, 0);
                const trackDone = t.textbooks.reduce((b, tb) => {
                  let c = 0;
                  for (let i = 1; i <= tb.chapters; i++) {
                    if (completedSet.has(`${tb.id}/ch${String(i).padStart(2, "0")}`)) c++;
                  }
                  return b + (c === tb.chapters ? 1 : 0);
                }, 0);
                return a + trackDone;
              }, 0)}
            </div>
            <div style={{ fontSize: 10, color: "#64748b" }}>Books Done</div>
          </div>
        </div>

        {/* Track progress bars */}
        <div style={{ display: "flex", flexDirection: "column", gap: 6, marginBottom: 24 }}>
          {CURRICULUM.map(track => {
            const trackTotal = track.textbooks.reduce((a, tb) => a + tb.chapters, 0);
            const trackDone = track.textbooks.reduce((a, tb) => {
              let c = 0;
              for (let i = 1; i <= tb.chapters; i++) {
                if (completedSet.has(`${tb.id}/ch${String(i).padStart(2, "0")}`)) c++;
              }
              return a + c;
            }, 0);
            const pct = trackTotal > 0 ? (trackDone / trackTotal) * 100 : 0;
            const isExpanded = expandedTrack === track.track;

            return (
              <div key={track.track}>
                <button onClick={() => setExpandedTrack(isExpanded ? null : track.track)}
                  style={{
                    width: "100%", background: "#1e293b", border: "1px solid #334155",
                    borderRadius: isExpanded ? "8px 8px 0 0" : 8, padding: "10px 14px",
                    cursor: "pointer", display: "flex", alignItems: "center", gap: 10,
                    fontFamily: "inherit", color: "#e2e8f0",
                  }}>
                  <span style={{ fontSize: 14 }}>{track.icon}</span>
                  <span style={{ fontSize: 12, fontWeight: 600, flex: 1, textAlign: "left" }}>{track.track}</span>
                  <span style={{ fontSize: 10, color: "#64748b" }}>{trackDone}/{trackTotal}</span>
                  <div style={{ width: 80, height: 6, background: "#0f172a", borderRadius: 3, overflow: "hidden" }}>
                    <div style={{ width: `${pct}%`, height: "100%", background: track.color, borderRadius: 3, transition: "width 0.3s" }} />
                  </div>
                  <span style={{ fontSize: 10, color: track.color, fontWeight: 600, width: 32, textAlign: "right" }}>{Math.round(pct)}%</span>
                </button>

                {isExpanded && (
                  <div style={{ background: "#1e293b", border: "1px solid #334155", borderTop: "none", borderRadius: "0 0 8px 8px", padding: 12 }}>
                    {track.textbooks.map(tb => {
                      let done = 0;
                      for (let i = 1; i <= tb.chapters; i++) {
                        if (completedSet.has(`${tb.id}/ch${String(i).padStart(2, "0")}`)) done++;
                      }
                      return (
                        <div key={tb.id} style={{ marginBottom: 10, padding: "6px 0", borderBottom: "1px solid #0f172a" }}>
                          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 6 }}>
                            <span style={{ fontSize: 11, color: "#cbd5e1" }}>{tb.id}: {tb.title}</span>
                            <span style={{ fontSize: 10, color: done === tb.chapters ? "#10b981" : "#64748b" }}>
                              {done}/{tb.chapters} {done === tb.chapters ? "✓" : ""}
                            </span>
                          </div>
                          <ChapterGrid textbookId={tb.id} totalChapters={tb.chapters}
                            completedChapters={completedSet} onToggle={toggleChapter} />
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}
        </div>

        {/* Labs */}
        <div style={{ fontSize: 12, fontWeight: 600, color: "#94a3b8", marginBottom: 8 }}>CHALLENGE LABS</div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(160px, 1fr))", gap: 8, marginBottom: 24 }}>
          {LABS.map(lab => (
            <button key={lab.id} onClick={() => toggleLab(lab.id)} style={{
              background: labSet.has(lab.id) ? "#052e16" : "#1e293b",
              border: `1px solid ${labSet.has(lab.id) ? "#10b981" : "#334155"}`,
              borderRadius: 8, padding: 12, cursor: "pointer", textAlign: "left", fontFamily: "inherit",
            }}>
              <div style={{ fontSize: 11, fontWeight: 600, color: labSet.has(lab.id) ? "#10b981" : "#f8fafc", marginBottom: 4 }}>
                {labSet.has(lab.id) ? "✓ " : ""}{lab.title}
              </div>
              <div style={{ display: "flex", gap: 4 }}>
                {lab.tracks.map(t => {
                  const track = CURRICULUM.find(c => c.track === t);
                  return <span key={t} style={{ fontSize: 9, color: track?.color || "#64748b", background: "#0f172a", padding: "1px 4px", borderRadius: 2 }}>{t}</span>;
                })}
              </div>
            </button>
          ))}
        </div>

        {/* Reset */}
        <div style={{ textAlign: "center" }}>
          <button onClick={resetAll} style={{
            background: "transparent", border: "1px solid #334155", borderRadius: 4,
            padding: "4px 12px", color: "#475569", fontSize: 10, cursor: "pointer", fontFamily: "inherit",
          }}>Reset all progress</button>
        </div>
      </div>
    </div>
  );
}
