import { useState, useRef, useEffect, useCallback } from "react";

// ═══════════════════════════════════════════════════════════════════
// Agent-Based Epidemic Simulator
// Agents move on a 2D grid with SIR dynamics. Compare to ODE predictions.
// ═══════════════════════════════════════════════════════════════════

const STATES = { S: 0, I: 1, R: 2 };
const STATE_COLORS = { 0: "#3b82f6", 1: "#ef4444", 2: "#6b7280" };
const STATE_LABELS = { 0: "Susceptible", 1: "Infected", 2: "Recovered" };

function createAgents(n, gridSize, initialInfected) {
  const agents = [];
  for (let i = 0; i < n; i++) {
    agents.push({
      x: Math.random() * gridSize,
      y: Math.random() * gridSize,
      vx: (Math.random() - 0.5) * 2,
      vy: (Math.random() - 0.5) * 2,
      state: i < initialInfected ? STATES.I : STATES.S,
      infectedAt: i < initialInfected ? 0 : -1,
    });
  }
  return agents;
}

function stepAgents(agents, gridSize, infectionRadius, infectionProb, recoveryTime, tick) {
  const next = agents.map(a => ({ ...a }));

  // Move
  for (const a of next) {
    a.x += a.vx;
    a.y += a.vy;
    // Bounce off walls
    if (a.x < 0 || a.x > gridSize) { a.vx *= -1; a.x = Math.max(0, Math.min(gridSize, a.x)); }
    if (a.y < 0 || a.y > gridSize) { a.vy *= -1; a.y = Math.max(0, Math.min(gridSize, a.y)); }
    // Small random perturbation
    a.vx += (Math.random() - 0.5) * 0.3;
    a.vy += (Math.random() - 0.5) * 0.3;
    const speed = Math.sqrt(a.vx * a.vx + a.vy * a.vy);
    if (speed > 2) { a.vx *= 2 / speed; a.vy *= 2 / speed; }
  }

  // Infect
  for (let i = 0; i < next.length; i++) {
    if (next[i].state !== STATES.S) continue;
    for (let j = 0; j < next.length; j++) {
      if (next[j].state !== STATES.I) continue;
      const dx = next[i].x - next[j].x;
      const dy = next[i].y - next[j].y;
      if (dx * dx + dy * dy < infectionRadius * infectionRadius) {
        if (Math.random() < infectionProb) {
          next[i].state = STATES.I;
          next[i].infectedAt = tick;
          break;
        }
      }
    }
  }

  // Recover
  for (const a of next) {
    if (a.state === STATES.I && tick - a.infectedAt >= recoveryTime) {
      a.state = STATES.R;
    }
  }

  return next;
}

function solveSIR(beta, gamma, S0, I0, R0, steps) {
  const dt = 1;
  const N = S0 + I0 + R0;
  const curve = [{ S: S0 / N, I: I0 / N, R: R0 / N }];
  let S = S0 / N, I = I0 / N, R = R0 / N;
  for (let t = 0; t < steps; t++) {
    const dS = -beta * S * I * dt;
    const dI = (beta * S * I - gamma * I) * dt;
    const dR = gamma * I * dt;
    S += dS; I += dI; R += dR;
    S = Math.max(0, S); I = Math.max(0, I); R = Math.max(0, R);
    curve.push({ S, I, R });
  }
  return curve;
}

export default function EpidemicSimulator() {
  const canvasRef = useRef(null);
  const animRef = useRef(null);
  const [running, setRunning] = useState(false);
  const [tick, setTick] = useState(0);
  const [nAgents, setNAgents] = useState(300);
  const [initialInf, setInitialInf] = useState(5);
  const [infRadius, setInfRadius] = useState(8);
  const [infProb, setInfProb] = useState(0.3);
  const [recTime, setRecTime] = useState(60);
  const [speed, setSpeed] = useState(1);
  const [agents, setAgents] = useState(() => createAgents(300, 400, 5));
  const [history, setHistory] = useState([]);
  const GRID = 400;

  const reset = useCallback(() => {
    setRunning(false);
    if (animRef.current) cancelAnimationFrame(animRef.current);
    const a = createAgents(nAgents, GRID, initialInf);
    setAgents(a);
    setTick(0);
    setHistory([{
      S: a.filter(x => x.state === 0).length,
      I: a.filter(x => x.state === 1).length,
      R: a.filter(x => x.state === 2).length,
    }]);
  }, [nAgents, initialInf]);

  useEffect(() => { reset(); }, [nAgents, initialInf]);

  // Animation loop
  useEffect(() => {
    if (!running) return;
    let localAgents = agents;
    let localTick = tick;

    function frame() {
      for (let s = 0; s < speed; s++) {
        localTick++;
        localAgents = stepAgents(localAgents, GRID, infRadius, infProb, recTime, localTick);
      }
      setAgents(localAgents);
      setTick(localTick);
      setHistory(prev => {
        const h = [...prev, {
          S: localAgents.filter(x => x.state === 0).length,
          I: localAgents.filter(x => x.state === 1).length,
          R: localAgents.filter(x => x.state === 2).length,
        }];
        return h.length > 500 ? h.slice(-500) : h;
      });
      animRef.current = requestAnimationFrame(frame);
    }
    animRef.current = requestAnimationFrame(frame);
    return () => { if (animRef.current) cancelAnimationFrame(animRef.current); };
  }, [running, speed, infRadius, infProb, recTime]);

  // Draw agents
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#0f172a";
    ctx.fillRect(0, 0, GRID, GRID);

    // Grid dots
    ctx.fillStyle = "#1e293b";
    for (let x = 0; x < GRID; x += 20) for (let y = 0; y < GRID; y += 20) {
      ctx.beginPath(); ctx.arc(x, y, 0.5, 0, Math.PI * 2); ctx.fill();
    }

    // Agents
    for (const a of agents) {
      ctx.fillStyle = STATE_COLORS[a.state];
      ctx.globalAlpha = a.state === STATES.R ? 0.4 : 0.9;
      ctx.beginPath();
      ctx.arc(a.x, a.y, a.state === STATES.I ? 4 : 3, 0, Math.PI * 2);
      ctx.fill();

      // Infection radius halo
      if (a.state === STATES.I) {
        ctx.strokeStyle = "#ef444433";
        ctx.lineWidth = 0.5;
        ctx.beginPath();
        ctx.arc(a.x, a.y, infRadius, 0, Math.PI * 2);
        ctx.stroke();
      }
    }
    ctx.globalAlpha = 1;
  }, [agents, infRadius]);

  const counts = {
    S: agents.filter(a => a.state === 0).length,
    I: agents.filter(a => a.state === 1).length,
    R: agents.filter(a => a.state === 2).length,
  };

  // Epidemic curve mini-chart
  const chartW = 260, chartH = 80;
  const drawCurve = (data, key, color) => {
    if (data.length < 2) return "";
    const max = nAgents;
    return data.map((d, i) =>
      `${(i / Math.max(data.length - 1, 1)) * chartW},${chartH - (d[key] / max) * chartH}`
    ).join(" ");
  };

  // ODE comparison
  const effectiveBeta = infProb * Math.PI * infRadius * infRadius / (GRID * GRID) * nAgents;
  const effectiveGamma = 1 / recTime;
  const R0 = effectiveBeta / effectiveGamma;

  return (
    <div style={{ fontFamily: "'JetBrains Mono', monospace", background: "#0f172a", color: "#e2e8f0", minHeight: "100vh", padding: 20 }}>
      <div style={{ maxWidth: 750, margin: "0 auto" }}>
        <h1 style={{ fontSize: 20, fontWeight: 700, marginBottom: 4, color: "#f8fafc" }}>
          <span style={{ color: "#ef4444" }}>◆</span> ABM Epidemic Simulator
        </h1>
        <p style={{ fontSize: 11, color: "#64748b", marginBottom: 16 }}>
          Agents move on a 2D plane with SIR dynamics. Compare to ODE mean-field predictions.
        </p>

        <div style={{ display: "flex", gap: 16, flexWrap: "wrap" }}>
          {/* Canvas */}
          <div>
            <canvas ref={canvasRef} width={GRID} height={GRID}
              style={{ borderRadius: 8, border: "1px solid #1e293b" }} />
            <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
              <button onClick={() => setRunning(!running)} style={{
                background: running ? "#dc2626" : "#10b981", border: "none", borderRadius: 6,
                padding: "6px 16px", color: "#fff", fontSize: 11, fontWeight: 600,
                cursor: "pointer", fontFamily: "inherit",
              }}>{running ? "⏸ Pause" : "▶ Run"}</button>
              <button onClick={reset} style={{
                background: "#334155", border: "none", borderRadius: 6,
                padding: "6px 12px", color: "#94a3b8", fontSize: 11,
                cursor: "pointer", fontFamily: "inherit",
              }}>⟲ Reset</button>
              <span style={{ fontSize: 10, color: "#64748b", alignSelf: "center" }}>t = {tick}</span>
            </div>
          </div>

          {/* Controls + stats */}
          <div style={{ flex: 1, minWidth: 220 }}>
            {/* Live counts */}
            <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
              {Object.entries(STATE_LABELS).map(([k, label]) => (
                <div key={k} style={{ flex: 1, background: "#1e293b", borderRadius: 6, padding: 8, textAlign: "center", borderTop: `3px solid ${STATE_COLORS[k]}` }}>
                  <div style={{ fontSize: 18, fontWeight: 700, color: STATE_COLORS[k] }}>{counts[["S","I","R"][k]]}</div>
                  <div style={{ fontSize: 9, color: "#64748b" }}>{label}</div>
                </div>
              ))}
            </div>

            {/* Epidemic curve */}
            <div style={{ background: "#1e293b", borderRadius: 6, padding: 8, marginBottom: 12 }}>
              <div style={{ fontSize: 9, color: "#64748b", marginBottom: 4 }}>EPIDEMIC CURVE</div>
              <svg width={chartW} height={chartH} style={{ display: "block" }}>
                <polyline points={drawCurve(history, "S", "#3b82f6")} fill="none" stroke="#3b82f6" strokeWidth={1.5} />
                <polyline points={drawCurve(history, "I", "#ef4444")} fill="none" stroke="#ef4444" strokeWidth={1.5} />
                <polyline points={drawCurve(history, "R", "#6b7280")} fill="none" stroke="#6b7280" strokeWidth={1.5} />
              </svg>
            </div>

            {/* R₀ */}
            <div style={{ background: R0 > 1 ? "#310a0a" : "#052e16", border: `1px solid ${R0 > 1 ? "#ef4444" : "#10b981"}44`, borderRadius: 6, padding: 8, marginBottom: 12, textAlign: "center" }}>
              <div style={{ fontSize: 10, color: "#64748b" }}>Effective R₀</div>
              <div style={{ fontSize: 20, fontWeight: 700, color: R0 > 1 ? "#ef4444" : "#10b981" }}>{R0.toFixed(2)}</div>
              <div style={{ fontSize: 9, color: "#64748b" }}>{R0 > 1 ? "Epidemic spreads" : "Epidemic dies out"}</div>
            </div>

            {/* Parameters */}
            <div style={{ fontSize: 10, fontWeight: 600, color: "#94a3b8", marginBottom: 6 }}>PARAMETERS</div>
            {[
              { label: "Agents", value: nAgents, set: setNAgents, min: 50, max: 800, step: 25 },
              { label: "Initial infected", value: initialInf, set: setInitialInf, min: 1, max: 50, step: 1 },
              { label: "Infection radius", value: infRadius, set: setInfRadius, min: 2, max: 30, step: 1 },
              { label: "Infection prob", value: infProb, set: setInfProb, min: 0.01, max: 1, step: 0.01 },
              { label: "Recovery time", value: recTime, set: setRecTime, min: 10, max: 200, step: 5 },
              { label: "Speed", value: speed, set: setSpeed, min: 1, max: 5, step: 1 },
            ].map(p => (
              <div key={p.label} style={{ marginBottom: 8 }}>
                <div style={{ display: "flex", justifyContent: "space-between", fontSize: 10, color: "#cbd5e1", marginBottom: 2 }}>
                  <span>{p.label}</span>
                  <span style={{ color: "#ef4444", fontWeight: 600 }}>{typeof p.value === "number" && p.value < 1 ? p.value.toFixed(2) : p.value}</span>
                </div>
                <input type="range" min={p.min} max={p.max} step={p.step} value={p.value}
                  onChange={e => p.set(parseFloat(e.target.value))}
                  style={{ width: "100%", accentColor: "#ef4444", height: 4 }} />
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
