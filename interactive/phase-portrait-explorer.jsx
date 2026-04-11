import { useState, useRef, useEffect, useCallback } from "react";

// ═══════════════════════════════════════════════════════════════════
// ODE Phase Portrait Explorer
// Lotka-Volterra, Van der Pol, SIR, and custom 2D systems
// Click to place initial conditions, sliders to adjust parameters
// ═══════════════════════════════════════════════════════════════════

const SYSTEMS = {
  "lotka-volterra": {
    name: "Lotka–Volterra (Predator–Prey)",
    params: [
      { key: "alpha", label: "α (prey growth)", min: 0.1, max: 3, step: 0.05, default: 1.1 },
      { key: "beta", label: "β (predation rate)", min: 0.1, max: 2, step: 0.05, default: 0.4 },
      { key: "delta", label: "δ (predator growth)", min: 0.01, max: 1, step: 0.01, default: 0.1 },
      { key: "gamma", label: "γ (predator death)", min: 0.1, max: 3, step: 0.05, default: 0.4 },
    ],
    fn: (x, y, p) => [p.alpha * x - p.beta * x * y, p.delta * x * y - p.gamma * y],
    xLabel: "Prey", yLabel: "Predator", xRange: [0, 12], yRange: [0, 12],
    nullclines: (p, xr, yr) => {
      const pts = [];
      // x-nullcline: alpha - beta*y = 0 => y = alpha/beta (horizontal line)
      const yNull = p.alpha / p.beta;
      if (yNull >= yr[0] && yNull <= yr[1]) pts.push({ type: "x-nullcline", label: `y = ${yNull.toFixed(2)}`, points: [[xr[0], yNull], [xr[1], yNull]] });
      // y-nullcline: delta*x - gamma = 0 => x = gamma/delta (vertical line)
      const xNull = p.gamma / p.delta;
      if (xNull >= xr[0] && xNull <= xr[1]) pts.push({ type: "y-nullcline", label: `x = ${xNull.toFixed(2)}`, points: [[xNull, yr[0]], [xNull, yr[1]]] });
      return pts;
    },
  },
  "van-der-pol": {
    name: "Van der Pol Oscillator",
    params: [
      { key: "mu", label: "μ (nonlinearity)", min: 0.1, max: 5, step: 0.1, default: 1.0 },
    ],
    fn: (x, y, p) => [y, p.mu * (1 - x * x) * y - x],
    xLabel: "x", yLabel: "dx/dt", xRange: [-4, 4], yRange: [-6, 6],
    nullclines: (p, xr, yr) => {
      const xNull = [];
      for (let x = xr[0]; x <= xr[1]; x += 0.05) xNull.push([x, 0]);
      const yNull = [];
      for (let x = xr[0]; x <= xr[1]; x += 0.05) {
        const y = x / (p.mu * (1 - x * x));
        if (isFinite(y) && y >= yr[0] && y <= yr[1]) yNull.push([x, y]);
      }
      return [
        { type: "x-nullcline", label: "ẋ = 0 (y = 0)", points: xNull },
        { type: "y-nullcline", label: "ẏ = 0", points: yNull },
      ];
    },
  },
  "sir": {
    name: "SIR Epidemic Model",
    params: [
      { key: "beta", label: "β (transmission)", min: 0.1, max: 2, step: 0.05, default: 0.5 },
      { key: "gamma", label: "γ (recovery)", min: 0.05, max: 1, step: 0.05, default: 0.15 },
    ],
    fn: (S, I, p) => [-p.beta * S * I, p.beta * S * I - p.gamma * I],
    xLabel: "Susceptible", yLabel: "Infected", xRange: [0, 1], yRange: [0, 0.5],
    nullclines: (p, xr, yr) => {
      const yNull = p.gamma / p.beta;
      return [
        { type: "x-nullcline", label: "I = 0", points: [[xr[0], 0], [xr[1], 0]] },
        { type: "y-nullcline", label: `S = γ/β = ${yNull.toFixed(2)}`, points: [[yNull, yr[0]], [yNull, yr[1]]] },
      ];
    },
  },
  "damped-pendulum": {
    name: "Damped Pendulum",
    params: [
      { key: "b", label: "b (damping)", min: 0, max: 2, step: 0.05, default: 0.3 },
      { key: "g_l", label: "g/L", min: 0.5, max: 5, step: 0.1, default: 1.0 },
    ],
    fn: (theta, omega, p) => [omega, -p.b * omega - p.g_l * Math.sin(theta)],
    xLabel: "θ (angle)", yLabel: "ω (angular velocity)", xRange: [-6, 6], yRange: [-4, 4],
    nullclines: (p, xr, yr) => {
      const xNull = [];
      for (let t = xr[0]; t <= xr[1]; t += 0.05) xNull.push([t, 0]);
      const yNull = [];
      for (let t = xr[0]; t <= xr[1]; t += 0.05) {
        const o = -p.g_l * Math.sin(t) / p.b;
        if (isFinite(o) && o >= yr[0] && o <= yr[1]) yNull.push([t, o]);
      }
      return [
        { type: "x-nullcline", label: "ω = 0", points: xNull },
        { type: "y-nullcline", label: "ω̇ = 0", points: yNull },
      ];
    },
  },
};

function rk4Step(fn, x, y, params, dt) {
  const k1 = fn(x, y, params);
  const k2 = fn(x + 0.5 * dt * k1[0], y + 0.5 * dt * k1[1], params);
  const k3 = fn(x + 0.5 * dt * k2[0], y + 0.5 * dt * k2[1], params);
  const k4 = fn(x + dt * k3[0], y + dt * k3[1], params);
  return [
    x + (dt / 6) * (k1[0] + 2*k2[0] + 2*k3[0] + k4[0]),
    y + (dt / 6) * (k1[1] + 2*k2[1] + 2*k3[1] + k4[1]),
  ];
}

function integrate(fn, x0, y0, params, dt, steps, xRange, yRange) {
  const traj = [[x0, y0]];
  let x = x0, y = y0;
  for (let i = 0; i < steps; i++) {
    [x, y] = rk4Step(fn, x, y, params, dt);
    if (!isFinite(x) || !isFinite(y)) break;
    if (x < xRange[0] * 3 || x > xRange[1] * 3 || y < yRange[0] * 3 || y > yRange[1] * 3) break;
    traj.push([x, y]);
  }
  return traj;
}

export default function PhasePortraitExplorer() {
  const canvasRef = useRef(null);
  const [systemKey, setSystemKey] = useState("lotka-volterra");
  const system = SYSTEMS[systemKey];
  const [params, setParams] = useState(() => {
    const p = {};
    system.params.forEach(pp => p[pp.key] = pp.default);
    return p;
  });
  const [trajectories, setTrajectories] = useState([]);
  const [showNullclines, setShowNullclines] = useState(true);
  const [showField, setShowField] = useState(true);
  const [dt] = useState(0.02);
  const [steps] = useState(3000);

  // Reset params when system changes
  useEffect(() => {
    const p = {};
    SYSTEMS[systemKey].params.forEach(pp => p[pp.key] = pp.default);
    setParams(p);
    setTrajectories([]);
  }, [systemKey]);

  const W = 640, H = 520, PAD = 50;
  const sys = SYSTEMS[systemKey];
  const xr = sys.xRange, yr = sys.yRange;
  const sx = (x) => PAD + (x - xr[0]) / (xr[1] - xr[0]) * (W - 2 * PAD);
  const sy = (y) => H - PAD - (y - yr[0]) / (yr[1] - yr[0]) * (H - 2 * PAD);
  const ix = (px) => xr[0] + (px - PAD) / (W - 2 * PAD) * (xr[1] - xr[0]);
  const iy = (py) => yr[0] + (H - PAD - py) / (H - 2 * PAD) * (yr[1] - yr[0]);

  const handleCanvasClick = useCallback((e) => {
    const rect = canvasRef.current.getBoundingClientRect();
    const px = e.clientX - rect.left;
    const py = e.clientY - rect.top;
    const x0 = ix(px), y0 = iy(py);
    if (x0 < xr[0] || x0 > xr[1] || y0 < yr[0] || y0 > yr[1]) return;
    const traj = integrate(sys.fn, x0, y0, params, dt, steps, xr, yr);
    const colors = ["#3b82f6", "#ef4444", "#10b981", "#f59e0b", "#8b5cf6", "#ec4899", "#06b6d4", "#f97316"];
    setTrajectories(prev => [...prev, { points: traj, color: colors[prev.length % colors.length] }]);
  }, [sys, params, dt, steps, xr, yr]);

  // Draw everything
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, W, H);

    // Background
    ctx.fillStyle = "#0f172a";
    ctx.fillRect(0, 0, W, H);

    // Grid
    ctx.strokeStyle = "#1e293b";
    ctx.lineWidth = 0.5;
    const xTicks = 10, yTicks = 8;
    for (let i = 0; i <= xTicks; i++) {
      const x = PAD + i * (W - 2*PAD) / xTicks;
      ctx.beginPath(); ctx.moveTo(x, PAD); ctx.lineTo(x, H - PAD); ctx.stroke();
    }
    for (let i = 0; i <= yTicks; i++) {
      const y = PAD + i * (H - 2*PAD) / yTicks;
      ctx.beginPath(); ctx.moveTo(PAD, y); ctx.lineTo(W - PAD, y); ctx.stroke();
    }

    // Axis labels
    ctx.fillStyle = "#64748b";
    ctx.font = "11px 'JetBrains Mono', monospace";
    ctx.textAlign = "center";
    ctx.fillText(sys.xLabel, W / 2, H - 10);
    ctx.save();
    ctx.translate(14, H / 2);
    ctx.rotate(-Math.PI / 2);
    ctx.fillText(sys.yLabel, 0, 0);
    ctx.restore();

    // Tick labels
    ctx.font = "9px 'JetBrains Mono', monospace";
    for (let i = 0; i <= xTicks; i++) {
      const v = xr[0] + i * (xr[1] - xr[0]) / xTicks;
      ctx.fillText(v.toFixed(1), PAD + i * (W - 2*PAD) / xTicks, H - PAD + 14);
    }
    ctx.textAlign = "right";
    for (let i = 0; i <= yTicks; i++) {
      const v = yr[0] + i * (yr[1] - yr[0]) / yTicks;
      ctx.fillText(v.toFixed(1), PAD - 6, H - PAD - i * (H - 2*PAD) / yTicks + 3);
    }

    // Vector field
    if (showField) {
      const nx = 20, ny = 16;
      ctx.strokeStyle = "#334155";
      ctx.lineWidth = 0.8;
      for (let i = 0; i < nx; i++) {
        for (let j = 0; j < ny; j++) {
          const x = xr[0] + (i + 0.5) * (xr[1] - xr[0]) / nx;
          const y = yr[0] + (j + 0.5) * (yr[1] - yr[0]) / ny;
          const [dx, dy] = sys.fn(x, y, params);
          const mag = Math.sqrt(dx*dx + dy*dy);
          if (mag < 1e-10) continue;
          const scale = Math.min(12, 6 * Math.log(1 + mag));
          const ndx = dx / mag * scale, ndy = dy / mag * scale;
          const px = sx(x), py = sy(y);
          ctx.beginPath();
          ctx.moveTo(px - ndx * 0.5, py + ndy * 0.5);
          ctx.lineTo(px + ndx * 0.5, py - ndy * 0.5);
          ctx.stroke();
          // Arrow head
          const hx = px + ndx * 0.5, hy = py - ndy * 0.5;
          const angle = Math.atan2(-ndy, ndx);
          ctx.beginPath();
          ctx.moveTo(hx, hy);
          ctx.lineTo(hx - 4 * Math.cos(angle - 0.4), hy - 4 * Math.sin(angle - 0.4));
          ctx.moveTo(hx, hy);
          ctx.lineTo(hx - 4 * Math.cos(angle + 0.4), hy - 4 * Math.sin(angle + 0.4));
          ctx.stroke();
        }
      }
    }

    // Nullclines
    if (showNullclines && sys.nullclines) {
      const ncs = sys.nullclines(params, xr, yr);
      const ncColors = ["#f472b6", "#34d399"];
      ncs.forEach((nc, idx) => {
        if (nc.points.length < 2) return;
        ctx.strokeStyle = ncColors[idx % 2];
        ctx.lineWidth = 2;
        ctx.setLineDash([6, 4]);
        ctx.beginPath();
        nc.points.forEach(([x, y], i) => {
          const px = sx(x), py = sy(y);
          if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
        });
        ctx.stroke();
        ctx.setLineDash([]);
        // Label
        const mid = nc.points[Math.floor(nc.points.length / 4)];
        ctx.fillStyle = ncColors[idx % 2];
        ctx.font = "10px 'JetBrains Mono', monospace";
        ctx.textAlign = "left";
        ctx.fillText(nc.label, sx(mid[0]) + 4, sy(mid[1]) - 6);
      });
    }

    // Trajectories
    trajectories.forEach(({ points, color }) => {
      if (points.length < 2) return;
      ctx.strokeStyle = color;
      ctx.lineWidth = 1.8;
      ctx.globalAlpha = 0.85;
      ctx.beginPath();
      points.forEach(([x, y], i) => {
        const px = sx(x), py = sy(y);
        if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
      });
      ctx.stroke();
      ctx.globalAlpha = 1;

      // Start marker
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(sx(points[0][0]), sy(points[0][1]), 5, 0, 2 * Math.PI);
      ctx.fill();
      ctx.strokeStyle = "#fff";
      ctx.lineWidth = 1;
      ctx.stroke();

      // End marker (arrowhead)
      const last = points[points.length - 1];
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(sx(last[0]), sy(last[1]), 3, 0, 2 * Math.PI);
      ctx.fill();
    });

    // R₀ annotation for SIR
    if (systemKey === "sir") {
      const R0 = params.beta / params.gamma;
      ctx.fillStyle = R0 > 1 ? "#ef4444" : "#10b981";
      ctx.font = "bold 13px 'JetBrains Mono', monospace";
      ctx.textAlign = "right";
      ctx.fillText(`R₀ = β/γ = ${R0.toFixed(2)}`, W - PAD, PAD - 8);
      ctx.font = "10px 'JetBrains Mono', monospace";
      ctx.fillText(R0 > 1 ? "Epidemic spreads" : "Epidemic dies out", W - PAD, PAD + 6);
    }
  }, [sys, params, trajectories, showNullclines, showField, systemKey]);

  return (
    <div style={{ fontFamily: "'JetBrains Mono', monospace", background: "#0f172a", color: "#e2e8f0", minHeight: "100vh", padding: 24 }}>
      <div style={{ maxWidth: 900, margin: "0 auto" }}>
        <h1 style={{ fontSize: 20, fontWeight: 700, marginBottom: 4, color: "#f8fafc" }}>
          <span style={{ color: "#3b82f6" }}>◆</span> Phase Portrait Explorer
        </h1>
        <p style={{ fontSize: 12, color: "#64748b", marginBottom: 20 }}>
          Click the canvas to place initial conditions. Adjust parameters with sliders.
        </p>

        {/* System selector */}
        <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
          {Object.entries(SYSTEMS).map(([key, s]) => (
            <button key={key} onClick={() => setSystemKey(key)} style={{
              background: systemKey === key ? "#2563eb" : "#1e293b",
              border: "1px solid #334155", borderRadius: 6, padding: "6px 14px",
              color: systemKey === key ? "#fff" : "#94a3b8", fontSize: 11,
              cursor: "pointer", fontFamily: "inherit"
            }}>{s.name}</button>
          ))}
        </div>

        <div style={{ display: "flex", gap: 20, flexWrap: "wrap" }}>
          {/* Canvas */}
          <div>
            <canvas ref={canvasRef} width={W} height={H}
              onClick={handleCanvasClick}
              style={{ borderRadius: 8, border: "1px solid #1e293b", cursor: "crosshair" }}
            />
            <div style={{ display: "flex", gap: 12, marginTop: 8 }}>
              <label style={{ fontSize: 11, color: "#94a3b8", display: "flex", alignItems: "center", gap: 4 }}>
                <input type="checkbox" checked={showField} onChange={e => setShowField(e.target.checked)} /> Vector field
              </label>
              <label style={{ fontSize: 11, color: "#94a3b8", display: "flex", alignItems: "center", gap: 4 }}>
                <input type="checkbox" checked={showNullclines} onChange={e => setShowNullclines(e.target.checked)} /> Nullclines
              </label>
              <button onClick={() => setTrajectories([])} style={{
                background: "#1e293b", border: "1px solid #334155", borderRadius: 4,
                padding: "3px 10px", color: "#94a3b8", fontSize: 11, cursor: "pointer", fontFamily: "inherit"
              }}>Clear trajectories</button>
            </div>
          </div>

          {/* Parameter sliders */}
          <div style={{ minWidth: 220 }}>
            <div style={{ fontSize: 12, fontWeight: 600, color: "#94a3b8", marginBottom: 12 }}>PARAMETERS</div>
            {sys.params.map(pp => (
              <div key={pp.key} style={{ marginBottom: 14 }}>
                <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11, color: "#cbd5e1", marginBottom: 4 }}>
                  <span>{pp.label}</span>
                  <span style={{ color: "#3b82f6", fontWeight: 600 }}>{params[pp.key]?.toFixed(2)}</span>
                </div>
                <input type="range" min={pp.min} max={pp.max} step={pp.step}
                  value={params[pp.key] ?? pp.default}
                  onChange={e => {
                    const val = parseFloat(e.target.value);
                    setParams(prev => ({ ...prev, [pp.key]: val }));
                    setTrajectories([]);
                  }}
                  style={{ width: "100%", accentColor: "#3b82f6" }}
                />
              </div>
            ))}

            <div style={{ fontSize: 12, fontWeight: 600, color: "#94a3b8", marginTop: 20, marginBottom: 8 }}>TRAJECTORIES</div>
            {trajectories.length === 0 ? (
              <div style={{ fontSize: 11, color: "#475569" }}>Click canvas to add</div>
            ) : (
              trajectories.map((t, i) => (
                <div key={i} style={{ fontSize: 11, color: "#94a3b8", display: "flex", alignItems: "center", gap: 6, marginBottom: 4 }}>
                  <div style={{ width: 10, height: 10, borderRadius: "50%", background: t.color }} />
                  IC: ({t.points[0][0].toFixed(2)}, {t.points[0][1].toFixed(2)}) — {t.points.length} pts
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
