import { useState, useRef, useEffect, useCallback } from "react";

// ═══════════════════════════════════════════════════════════════════
// Gradient Descent Visualizer
// Watch iterates move across contour plots, compare algorithms
// ═══════════════════════════════════════════════════════════════════

const FUNCTIONS = {
  rosenbrock: {
    name: "Rosenbrock (banana)",
    fn: (x, y) => (1 - x) ** 2 + 100 * (y - x ** 2) ** 2,
    grad: (x, y) => [
      -2 * (1 - x) - 400 * x * (y - x ** 2),
      200 * (y - x ** 2),
    ],
    hess: (x, y) => [
      [2 + 1200 * x * x - 400 * y, -400 * x],
      [-400 * x, 200],
    ],
    xRange: [-2, 2], yRange: [-1, 3],
    minima: [[1, 1]],
    defaultStart: [-1.5, 2.0],
    contourLevels: [0.5, 1, 2, 5, 10, 25, 50, 100, 200, 500, 1000, 2000],
  },
  beale: {
    name: "Beale's Function",
    fn: (x, y) => (1.5 - x + x * y) ** 2 + (2.25 - x + x * y ** 2) ** 2 + (2.625 - x + x * y ** 3) ** 2,
    grad: (x, y) => {
      const a = 1.5 - x + x * y, b = 2.25 - x + x * y * y, c = 2.625 - x + x * y * y * y;
      return [
        2 * a * (-1 + y) + 2 * b * (-1 + y * y) + 2 * c * (-1 + y * y * y),
        2 * a * x + 2 * b * 2 * x * y + 2 * c * 3 * x * y * y,
      ];
    },
    hess: null,
    xRange: [-4.5, 4.5], yRange: [-4.5, 4.5],
    minima: [[3, 0.5]],
    defaultStart: [-3, 3],
    contourLevels: [0.1, 0.5, 1, 2, 5, 10, 25, 50, 100, 500, 2000, 10000],
  },
  quadratic: {
    name: "Ill-Conditioned Quadratic",
    fn: (x, y) => 0.5 * (x * x + 50 * y * y),
    grad: (x, y) => [x, 50 * y],
    hess: () => [[1, 0], [0, 50]],
    xRange: [-5, 5], yRange: [-5, 5],
    minima: [[0, 0]],
    defaultStart: [4, 4],
    contourLevels: [0.5, 1, 2, 5, 10, 25, 50, 100, 200, 400],
  },
  himmelblau: {
    name: "Himmelblau's (4 minima)",
    fn: (x, y) => (x * x + y - 11) ** 2 + (x + y * y - 7) ** 2,
    grad: (x, y) => [
      4 * x * (x * x + y - 11) + 2 * (x + y * y - 7),
      2 * (x * x + y - 11) + 4 * y * (x + y * y - 7),
    ],
    hess: null,
    xRange: [-5, 5], yRange: [-5, 5],
    minima: [[3, 2], [-2.805, 3.131], [-3.779, -3.283], [3.584, -1.848]],
    defaultStart: [-4, -4],
    contourLevels: [0.5, 1, 2, 5, 10, 25, 50, 100, 200, 500],
  },
};

const ALGORITHMS = {
  gd: {
    name: "Gradient Descent",
    color: "#3b82f6",
    step: (fn, grad, hess, x, y, lr) => {
      const [gx, gy] = grad(x, y);
      return [x - lr * gx, y - lr * gy];
    },
  },
  momentum: {
    name: "Momentum (β=0.9)",
    color: "#ef4444",
    step: (fn, grad, hess, x, y, lr, state) => {
      if (!state.vx) { state.vx = 0; state.vy = 0; }
      const [gx, gy] = grad(x, y);
      state.vx = 0.9 * state.vx - lr * gx;
      state.vy = 0.9 * state.vy - lr * gy;
      return [x + state.vx, y + state.vy];
    },
  },
  nesterov: {
    name: "Nesterov Momentum",
    color: "#10b981",
    step: (fn, grad, hess, x, y, lr, state) => {
      if (!state.vx) { state.vx = 0; state.vy = 0; }
      const lookX = x + 0.9 * state.vx, lookY = y + 0.9 * state.vy;
      const [gx, gy] = grad(lookX, lookY);
      state.vx = 0.9 * state.vx - lr * gx;
      state.vy = 0.9 * state.vy - lr * gy;
      return [x + state.vx, y + state.vy];
    },
  },
  adam: {
    name: "Adam",
    color: "#f59e0b",
    step: (fn, grad, hess, x, y, lr, state) => {
      if (!state.t) { state.t = 0; state.mx = 0; state.my = 0; state.vvx = 0; state.vvy = 0; }
      state.t++;
      const [gx, gy] = grad(x, y);
      state.mx = 0.9 * state.mx + 0.1 * gx;
      state.my = 0.9 * state.my + 0.1 * gy;
      state.vvx = 0.999 * state.vvx + 0.001 * gx * gx;
      state.vvy = 0.999 * state.vvy + 0.001 * gy * gy;
      const mxh = state.mx / (1 - 0.9 ** state.t);
      const myh = state.my / (1 - 0.9 ** state.t);
      const vxh = state.vvx / (1 - 0.999 ** state.t);
      const vyh = state.vvy / (1 - 0.999 ** state.t);
      return [x - lr * mxh / (Math.sqrt(vxh) + 1e-8), y - lr * myh / (Math.sqrt(vyh) + 1e-8)];
    },
  },
};

export default function GradientDescentVisualizer() {
  const canvasRef = useRef(null);
  const [funcKey, setFuncKey] = useState("rosenbrock");
  const [activeAlgos, setActiveAlgos] = useState(["gd"]);
  const [lr, setLr] = useState(0.001);
  const [maxIter, setMaxIter] = useState(500);
  const [paths, setPaths] = useState({});
  const [isRunning, setIsRunning] = useState(false);
  const animRef = useRef(null);

  const func = FUNCTIONS[funcKey];
  const W = 640, H = 520, PAD = 50;
  const xr = func.xRange, yr = func.yRange;
  const sx = (x) => PAD + (x - xr[0]) / (xr[1] - xr[0]) * (W - 2 * PAD);
  const sy = (y) => H - PAD - (y - yr[0]) / (yr[1] - yr[0]) * (H - 2 * PAD);

  const runOptimization = useCallback(() => {
    const newPaths = {};
    activeAlgos.forEach(algoKey => {
      const algo = ALGORITHMS[algoKey];
      const path = [[...func.defaultStart]];
      let [x, y] = func.defaultStart;
      const state = {};
      for (let i = 0; i < maxIter; i++) {
        [x, y] = algo.step(func.fn, func.grad, func.hess, x, y, lr, state);
        if (!isFinite(x) || !isFinite(y)) break;
        path.push([x, y]);
        if (Math.abs(func.grad(x, y)[0]) + Math.abs(func.grad(x, y)[1]) < 1e-8) break;
      }
      newPaths[algoKey] = { points: path, color: algo.color, fval: func.fn(x, y) };
    });
    setPaths(newPaths);
  }, [funcKey, activeAlgos, lr, maxIter, func]);

  useEffect(() => { runOptimization(); }, [runOptimization]);

  // Draw
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, W, H);

    // Background
    ctx.fillStyle = "#0f172a";
    ctx.fillRect(0, 0, W, H);

    // Contour plot
    const res = 2;
    for (let px = PAD; px < W - PAD; px += res) {
      for (let py = PAD; py < H - PAD; py += res) {
        const x = xr[0] + (px - PAD) / (W - 2 * PAD) * (xr[1] - xr[0]);
        const y = yr[0] + (H - PAD - py) / (H - 2 * PAD) * (yr[1] - yr[0]);
        const val = func.fn(x, y);
        const logVal = Math.log10(val + 1);
        const maxLog = Math.log10(func.contourLevels[func.contourLevels.length - 1] + 1);
        const t = Math.min(1, logVal / maxLog);
        const r = Math.floor(15 + t * 30);
        const g = Math.floor(23 + t * 20);
        const b = Math.floor(42 + t * 60);
        ctx.fillStyle = `rgb(${r},${g},${b})`;
        ctx.fillRect(px, py, res, res);
      }
    }

    // Contour lines
    ctx.lineWidth = 0.6;
    func.contourLevels.forEach((level, li) => {
      const hue = 200 + li * 8;
      ctx.strokeStyle = `hsla(${hue}, 40%, 50%, 0.4)`;
      // March along rows
      for (let py = PAD; py < H - PAD; py += 3) {
        let inContour = false;
        for (let px = PAD; px < W - PAD; px += 2) {
          const x = xr[0] + (px - PAD) / (W - 2 * PAD) * (xr[1] - xr[0]);
          const y = yr[0] + (H - PAD - py) / (H - 2 * PAD) * (yr[1] - yr[0]);
          const val = func.fn(x, y);
          const cross = Math.abs(val - level) < level * 0.08 + 0.1;
          if (cross && !inContour) {
            ctx.beginPath(); ctx.arc(px, py, 0.6, 0, 2 * Math.PI); ctx.stroke();
            inContour = true;
          } else if (!cross) {
            inContour = false;
          }
        }
      }
    });

    // Minima markers
    ctx.fillStyle = "#fbbf24";
    func.minima.forEach(([mx, my]) => {
      ctx.beginPath();
      ctx.arc(sx(mx), sy(my), 6, 0, 2 * Math.PI);
      ctx.fill();
      ctx.strokeStyle = "#0f172a";
      ctx.lineWidth = 2;
      ctx.stroke();
      // Star shape
      ctx.fillStyle = "#0f172a";
      ctx.font = "bold 9px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("★", sx(mx), sy(my) + 3);
      ctx.fillStyle = "#fbbf24";
    });

    // Optimization paths
    Object.entries(paths).forEach(([algoKey, { points, color }]) => {
      if (points.length < 2) return;
      ctx.strokeStyle = color;
      ctx.lineWidth = 2;
      ctx.globalAlpha = 0.9;
      ctx.beginPath();
      points.forEach(([x, y], i) => {
        const px = sx(x), py = sy(y);
        if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
      });
      ctx.stroke();
      ctx.globalAlpha = 1;

      // Start point
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(sx(points[0][0]), sy(points[0][1]), 6, 0, 2 * Math.PI);
      ctx.fill();
      ctx.strokeStyle = "#fff";
      ctx.lineWidth = 1.5;
      ctx.stroke();

      // End point
      const last = points[points.length - 1];
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(sx(last[0]), sy(last[1]), 4, 0, 2 * Math.PI);
      ctx.fill();

      // Iteration markers every 50 steps
      points.forEach(([x, y], i) => {
        if (i > 0 && i % 50 === 0) {
          ctx.fillStyle = color;
          ctx.globalAlpha = 0.5;
          ctx.beginPath();
          ctx.arc(sx(x), sy(y), 2, 0, 2 * Math.PI);
          ctx.fill();
          ctx.globalAlpha = 1;
        }
      });
    });

    // Axis labels
    ctx.fillStyle = "#64748b";
    ctx.font = "11px 'JetBrains Mono', monospace";
    ctx.textAlign = "center";
    ctx.fillText("x₁", W / 2, H - 10);
    ctx.save();
    ctx.translate(14, H / 2);
    ctx.rotate(-Math.PI / 2);
    ctx.fillText("x₂", 0, 0);
    ctx.restore();
  }, [func, paths]);

  const toggleAlgo = (key) => {
    setActiveAlgos(prev =>
      prev.includes(key) ? prev.filter(k => k !== key) : [...prev, key]
    );
  };

  return (
    <div style={{ fontFamily: "'JetBrains Mono', monospace", background: "#0f172a", color: "#e2e8f0", minHeight: "100vh", padding: 24 }}>
      <div style={{ maxWidth: 950, margin: "0 auto" }}>
        <h1 style={{ fontSize: 20, fontWeight: 700, marginBottom: 4, color: "#f8fafc" }}>
          <span style={{ color: "#f59e0b" }}>◆</span> Gradient Descent Visualizer
        </h1>
        <p style={{ fontSize: 12, color: "#64748b", marginBottom: 20 }}>
          Compare optimization algorithms on classic test functions
        </p>

        {/* Function selector */}
        <div style={{ display: "flex", gap: 8, marginBottom: 12, flexWrap: "wrap" }}>
          {Object.entries(FUNCTIONS).map(([key, f]) => (
            <button key={key} onClick={() => { setFuncKey(key); setPaths({}); }} style={{
              background: funcKey === key ? "#1e40af" : "#1e293b",
              border: "1px solid #334155", borderRadius: 6, padding: "6px 12px",
              color: funcKey === key ? "#fff" : "#94a3b8", fontSize: 11,
              cursor: "pointer", fontFamily: "inherit"
            }}>{f.name}</button>
          ))}
        </div>

        <div style={{ display: "flex", gap: 20, flexWrap: "wrap" }}>
          <div>
            <canvas ref={canvasRef} width={W} height={H} style={{ borderRadius: 8, border: "1px solid #1e293b" }} />
          </div>

          <div style={{ minWidth: 240 }}>
            {/* Algorithm toggles */}
            <div style={{ fontSize: 12, fontWeight: 600, color: "#94a3b8", marginBottom: 8 }}>ALGORITHMS</div>
            {Object.entries(ALGORITHMS).map(([key, algo]) => (
              <label key={key} style={{
                display: "flex", alignItems: "center", gap: 8, marginBottom: 6,
                fontSize: 11, color: activeAlgos.includes(key) ? algo.color : "#475569", cursor: "pointer"
              }}>
                <input type="checkbox" checked={activeAlgos.includes(key)} onChange={() => toggleAlgo(key)} style={{ accentColor: algo.color }} />
                <div style={{ width: 10, height: 10, borderRadius: "50%", background: algo.color, opacity: activeAlgos.includes(key) ? 1 : 0.3 }} />
                {algo.name}
              </label>
            ))}

            {/* Learning rate */}
            <div style={{ marginTop: 16 }}>
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11, color: "#cbd5e1", marginBottom: 4 }}>
                <span>Learning rate</span>
                <span style={{ color: "#f59e0b", fontWeight: 600 }}>{lr.toExponential(1)}</span>
              </div>
              <input type="range" min={-5} max={-1} step={0.1}
                value={Math.log10(lr)}
                onChange={e => setLr(10 ** parseFloat(e.target.value))}
                style={{ width: "100%", accentColor: "#f59e0b" }}
              />
            </div>

            {/* Max iterations */}
            <div style={{ marginTop: 12 }}>
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11, color: "#cbd5e1", marginBottom: 4 }}>
                <span>Max iterations</span>
                <span style={{ color: "#f59e0b", fontWeight: 600 }}>{maxIter}</span>
              </div>
              <input type="range" min={50} max={5000} step={50}
                value={maxIter}
                onChange={e => setMaxIter(parseInt(e.target.value))}
                style={{ width: "100%", accentColor: "#f59e0b" }}
              />
            </div>

            {/* Results */}
            <div style={{ fontSize: 12, fontWeight: 600, color: "#94a3b8", marginTop: 20, marginBottom: 8 }}>RESULTS</div>
            {Object.entries(paths).map(([key, { points, color, fval }]) => (
              <div key={key} style={{ fontSize: 10, color: "#94a3b8", marginBottom: 8, padding: "6px 8px", background: "#1e293b", borderRadius: 4, borderLeft: `3px solid ${color}` }}>
                <div style={{ fontWeight: 600, color, marginBottom: 2 }}>{ALGORITHMS[key].name}</div>
                <div>Iters: {points.length - 1}</div>
                <div>Final: ({points[points.length-1][0].toFixed(4)}, {points[points.length-1][1].toFixed(4)})</div>
                <div>f(x*): {fval.toExponential(3)}</div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
