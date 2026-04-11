import { useState, useMemo, useCallback } from "react";
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, AreaChart, Area, BarChart, Bar, Legend } from "recharts";

// ═══════════════════════════════════════════════════════════════════
// Distribution Playground
// Adjust parameters, see PDF/CDF/quantiles, compare distributions
// ═══════════════════════════════════════════════════════════════════

// Simple distributions implemented in JS (no external stats lib needed)
const DISTS = {
  normal: {
    name: "Normal (Gaussian)",
    params: [
      { key: "mu", label: "μ (mean)", min: -5, max: 5, step: 0.1, default: 0 },
      { key: "sigma", label: "σ (std dev)", min: 0.1, max: 5, step: 0.1, default: 1 },
    ],
    pdf: (x, { mu, sigma }) => {
      const z = (x - mu) / sigma;
      return Math.exp(-0.5 * z * z) / (sigma * Math.sqrt(2 * Math.PI));
    },
    cdf: (x, { mu, sigma }) => 0.5 * (1 + erf((x - mu) / (sigma * Math.sqrt(2)))),
    range: (p) => [p.mu - 4 * p.sigma, p.mu + 4 * p.sigma],
    mean: (p) => p.mu,
    variance: (p) => p.sigma ** 2,
    color: "#3b82f6",
  },
  exponential: {
    name: "Exponential",
    params: [
      { key: "lambda", label: "λ (rate)", min: 0.1, max: 5, step: 0.1, default: 1 },
    ],
    pdf: (x, { lambda }) => x < 0 ? 0 : lambda * Math.exp(-lambda * x),
    cdf: (x, { lambda }) => x < 0 ? 0 : 1 - Math.exp(-lambda * x),
    range: (p) => [0, 5 / p.lambda],
    mean: (p) => 1 / p.lambda,
    variance: (p) => 1 / p.lambda ** 2,
    color: "#ef4444",
  },
  gamma: {
    name: "Gamma",
    params: [
      { key: "alpha", label: "α (shape)", min: 0.5, max: 10, step: 0.5, default: 2 },
      { key: "beta", label: "β (rate)", min: 0.1, max: 5, step: 0.1, default: 1 },
    ],
    pdf: (x, { alpha, beta }) => {
      if (x <= 0) return 0;
      return (beta ** alpha / gammaFn(alpha)) * x ** (alpha - 1) * Math.exp(-beta * x);
    },
    cdf: (x, { alpha, beta }) => x <= 0 ? 0 : lowerGamma(alpha, beta * x) / gammaFn(alpha),
    range: (p) => [0, (p.alpha + 3 * Math.sqrt(p.alpha)) / p.beta],
    mean: (p) => p.alpha / p.beta,
    variance: (p) => p.alpha / p.beta ** 2,
    color: "#10b981",
  },
  beta: {
    name: "Beta",
    params: [
      { key: "a", label: "α", min: 0.1, max: 10, step: 0.1, default: 2 },
      { key: "b", label: "β", min: 0.1, max: 10, step: 0.1, default: 5 },
    ],
    pdf: (x, { a, b }) => {
      if (x <= 0 || x >= 1) return 0;
      return x ** (a - 1) * (1 - x) ** (b - 1) / betaFn(a, b);
    },
    cdf: (x, { a, b }) => x <= 0 ? 0 : x >= 1 ? 1 : incompleteBeta(x, a, b),
    range: () => [0, 1],
    mean: (p) => p.a / (p.a + p.b),
    variance: (p) => (p.a * p.b) / ((p.a + p.b) ** 2 * (p.a + p.b + 1)),
    color: "#f59e0b",
  },
  uniform: {
    name: "Uniform",
    params: [
      { key: "a", label: "a (lower)", min: -5, max: 4, step: 0.5, default: 0 },
      { key: "b", label: "b (upper)", min: -4, max: 5, step: 0.5, default: 1 },
    ],
    pdf: (x, { a, b }) => x >= a && x <= b ? 1 / (b - a) : 0,
    cdf: (x, { a, b }) => x < a ? 0 : x > b ? 1 : (x - a) / (b - a),
    range: (p) => [p.a - 0.5, p.b + 0.5],
    mean: (p) => (p.a + p.b) / 2,
    variance: (p) => (p.b - p.a) ** 2 / 12,
    color: "#8b5cf6",
  },
  t: {
    name: "Student's t",
    params: [
      { key: "nu", label: "ν (degrees of freedom)", min: 1, max: 30, step: 1, default: 3 },
    ],
    pdf: (x, { nu }) => {
      return (gammaFn((nu + 1) / 2) / (Math.sqrt(nu * Math.PI) * gammaFn(nu / 2))) *
        (1 + x * x / nu) ** (-(nu + 1) / 2);
    },
    cdf: (x, { nu }) => {
      // Approximate via numerical integration
      let sum = 0;
      const dx = 0.01;
      for (let t = -15; t <= x; t += dx) {
        sum += DISTS.t.pdf(t, { nu }) * dx;
      }
      return Math.max(0, Math.min(1, sum));
    },
    range: () => [-6, 6],
    mean: (p) => p.nu > 1 ? 0 : NaN,
    variance: (p) => p.nu > 2 ? p.nu / (p.nu - 2) : Infinity,
    color: "#06b6d4",
  },
};

// ── Math helpers ──

function erf(x) {
  const t = 1 / (1 + 0.3275911 * Math.abs(x));
  const poly = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))));
  const result = 1 - poly * Math.exp(-x * x);
  return x >= 0 ? result : -result;
}

function gammaFn(n) {
  if (n === 1) return 1;
  if (n === 0.5) return Math.sqrt(Math.PI);
  if (n < 0.5) return Math.PI / (Math.sin(Math.PI * n) * gammaFn(1 - n));
  // Stirling approx for larger values
  n -= 1;
  const coeffs = [1, 1/12, 1/288, -139/51840];
  let result = Math.sqrt(2 * Math.PI / (n + 1)) * ((n + 1) / Math.E) ** (n + 1);
  let term = 1;
  for (let i = 1; i < coeffs.length; i++) {
    term *= 1 / (n + 1);
    result *= 1 + coeffs[i] * term * (n + 1);
  }
  // For small integers, use factorial
  if (Number.isInteger(n) && n >= 0 && n < 20) {
    let f = 1;
    for (let i = 2; i <= n; i++) f *= i;
    return f;
  }
  return result;
}

function betaFn(a, b) {
  return gammaFn(a) * gammaFn(b) / gammaFn(a + b);
}

function lowerGamma(s, x) {
  // Series expansion
  let sum = 0, term = 1 / s;
  for (let n = 0; n < 200; n++) {
    sum += term;
    term *= x / (s + n + 1);
    if (Math.abs(term) < 1e-15) break;
  }
  return Math.exp(-x + s * Math.log(x)) * sum;
}

function incompleteBeta(x, a, b) {
  // Numerical integration (simple but sufficient for visualization)
  const n = 200;
  const dx = x / n;
  let sum = 0;
  for (let i = 0; i < n; i++) {
    const t = (i + 0.5) * dx;
    sum += t ** (a - 1) * (1 - t) ** (b - 1) * dx;
  }
  return sum / betaFn(a, b);
}

// ── Random sampling for histogram ──

function sampleNormal(mu, sigma) {
  const u1 = Math.random(), u2 = Math.random();
  return mu + sigma * Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
}

function generateSamples(distKey, params, n) {
  // Use inverse CDF method (approximate) or Box-Muller for normal
  const dist = DISTS[distKey];
  const range = dist.range(params);
  const samples = [];
  if (distKey === "normal") {
    for (let i = 0; i < n; i++) samples.push(sampleNormal(params.mu, params.sigma));
  } else {
    // Rejection sampling
    const maxPdf = (() => {
      let max = 0;
      const dx = (range[1] - range[0]) / 200;
      for (let x = range[0]; x <= range[1]; x += dx) {
        max = Math.max(max, dist.pdf(x, params));
      }
      return max * 1.1;
    })();
    let attempts = 0;
    while (samples.length < n && attempts < n * 100) {
      const x = range[0] + Math.random() * (range[1] - range[0]);
      const u = Math.random() * maxPdf;
      if (u <= dist.pdf(x, params)) samples.push(x);
      attempts++;
    }
  }
  return samples;
}

export default function DistributionPlayground() {
  const [distKey, setDistKey] = useState("normal");
  const [params, setParams] = useState(() => {
    const p = {};
    DISTS.normal.params.forEach(pp => p[pp.key] = pp.default);
    return p;
  });
  const [view, setView] = useState("pdf");
  const [nSamples, setNSamples] = useState(500);
  const [showOverlay, setShowOverlay] = useState(null);
  const [overlayParams, setOverlayParams] = useState({});

  const dist = DISTS[distKey];

  // Change dist
  const switchDist = useCallback((key) => {
    setDistKey(key);
    const p = {};
    DISTS[key].params.forEach(pp => p[pp.key] = pp.default);
    setParams(p);
    setShowOverlay(null);
  }, []);

  // Generate chart data
  const chartData = useMemo(() => {
    const range = dist.range(params);
    const n = 200;
    const dx = (range[1] - range[0]) / n;
    const data = [];
    for (let i = 0; i <= n; i++) {
      const x = range[0] + i * dx;
      const point = { x: parseFloat(x.toFixed(4)) };
      if (view === "pdf") {
        point.y = dist.pdf(x, params);
      } else {
        point.y = dist.cdf(x, params);
      }
      // Overlay distribution
      if (showOverlay && DISTS[showOverlay]) {
        const oDist = DISTS[showOverlay];
        point.overlay = view === "pdf" ? oDist.pdf(x, overlayParams) : oDist.cdf(x, overlayParams);
      }
      data.push(point);
    }
    return data;
  }, [dist, params, view, showOverlay, overlayParams]);

  // Histogram data
  const histData = useMemo(() => {
    if (view !== "histogram") return [];
    const samples = generateSamples(distKey, params, nSamples);
    const range = dist.range(params);
    const nBins = 40;
    const binWidth = (range[1] - range[0]) / nBins;
    const bins = Array(nBins).fill(0);
    samples.forEach(s => {
      const idx = Math.floor((s - range[0]) / binWidth);
      if (idx >= 0 && idx < nBins) bins[idx]++;
    });
    return bins.map((count, i) => ({
      x: parseFloat((range[0] + (i + 0.5) * binWidth).toFixed(3)),
      count,
      density: count / (nSamples * binWidth),
      theoretical: dist.pdf(range[0] + (i + 0.5) * binWidth, params),
    }));
  }, [distKey, params, nSamples, view]);

  const mu = dist.mean(params);
  const v = dist.variance(params);

  return (
    <div style={{ fontFamily: "'JetBrains Mono', monospace", background: "#0f172a", color: "#e2e8f0", minHeight: "100vh", padding: 24 }}>
      <div style={{ maxWidth: 900, margin: "0 auto" }}>
        <h1 style={{ fontSize: 20, fontWeight: 700, marginBottom: 4, color: "#f8fafc" }}>
          <span style={{ color: "#10b981" }}>◆</span> Distribution Playground
        </h1>
        <p style={{ fontSize: 12, color: "#64748b", marginBottom: 20 }}>
          Adjust parameters and watch the distribution respond in real time
        </p>

        {/* Distribution selector */}
        <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
          {Object.entries(DISTS).map(([key, d]) => (
            <button key={key} onClick={() => switchDist(key)} style={{
              background: distKey === key ? d.color : "#1e293b",
              border: `1px solid ${d.color}`, borderRadius: 6, padding: "6px 12px",
              color: distKey === key ? "#fff" : d.color, fontSize: 11,
              cursor: "pointer", fontFamily: "inherit"
            }}>{d.name}</button>
          ))}
        </div>

        <div style={{ display: "flex", gap: 24, flexWrap: "wrap" }}>
          {/* Chart */}
          <div style={{ flex: 1, minWidth: 400 }}>
            {/* View toggles */}
            <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
              {["pdf", "cdf", "histogram"].map(v => (
                <button key={v} onClick={() => setView(v)} style={{
                  background: view === v ? "#334155" : "transparent",
                  border: "1px solid #475569", borderRadius: 4, padding: "4px 12px",
                  color: view === v ? "#f8fafc" : "#64748b", fontSize: 11,
                  cursor: "pointer", fontFamily: "inherit", textTransform: "uppercase"
                }}>{v}</button>
              ))}
            </div>

            <div style={{ background: "#1e293b", borderRadius: 8, padding: "16px 8px 8px 0" }}>
              <ResponsiveContainer width="100%" height={360}>
                {view === "histogram" ? (
                  <BarChart data={histData}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
                    <XAxis dataKey="x" tick={{ fill: "#64748b", fontSize: 10 }} />
                    <YAxis tick={{ fill: "#64748b", fontSize: 10 }} />
                    <Tooltip contentStyle={{ background: "#1e293b", border: "1px solid #334155", fontSize: 11 }} />
                    <Bar dataKey="density" fill={dist.color} opacity={0.6} name="Sample density" />
                    <Line type="monotone" dataKey="theoretical" stroke="#fbbf24" strokeWidth={2} dot={false} name="Theoretical PDF" />
                  </BarChart>
                ) : (
                  <AreaChart data={chartData}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
                    <XAxis dataKey="x" tick={{ fill: "#64748b", fontSize: 10 }} />
                    <YAxis tick={{ fill: "#64748b", fontSize: 10 }} />
                    <Tooltip contentStyle={{ background: "#1e293b", border: "1px solid #334155", fontSize: 11 }} />
                    <Area type="monotone" dataKey="y" stroke={dist.color} fill={dist.color} fillOpacity={0.15} strokeWidth={2} name={view.toUpperCase()} dot={false} />
                    {showOverlay && <Area type="monotone" dataKey="overlay" stroke={DISTS[showOverlay]?.color || "#888"} fill="none" strokeWidth={2} strokeDasharray="5 3" name={`${DISTS[showOverlay]?.name} overlay`} dot={false} />}
                  </AreaChart>
                )}
              </ResponsiveContainer>
            </div>
          </div>

          {/* Controls */}
          <div style={{ width: 240 }}>
            <div style={{ fontSize: 12, fontWeight: 600, color: "#94a3b8", marginBottom: 10 }}>PARAMETERS</div>
            {dist.params.map(pp => (
              <div key={pp.key} style={{ marginBottom: 14 }}>
                <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11, color: "#cbd5e1", marginBottom: 4 }}>
                  <span>{pp.label}</span>
                  <span style={{ color: dist.color, fontWeight: 600 }}>{(params[pp.key] ?? pp.default).toFixed(2)}</span>
                </div>
                <input type="range" min={pp.min} max={pp.max} step={pp.step}
                  value={params[pp.key] ?? pp.default}
                  onChange={e => setParams(prev => ({ ...prev, [pp.key]: parseFloat(e.target.value) }))}
                  style={{ width: "100%", accentColor: dist.color }}
                />
              </div>
            ))}

            {view === "histogram" && (
              <div style={{ marginBottom: 14 }}>
                <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11, color: "#cbd5e1", marginBottom: 4 }}>
                  <span>n (samples)</span>
                  <span style={{ color: dist.color, fontWeight: 600 }}>{nSamples}</span>
                </div>
                <input type="range" min={50} max={5000} step={50}
                  value={nSamples}
                  onChange={e => setNSamples(parseInt(e.target.value))}
                  style={{ width: "100%", accentColor: dist.color }}
                />
              </div>
            )}

            {/* Summary statistics */}
            <div style={{ fontSize: 12, fontWeight: 600, color: "#94a3b8", marginTop: 20, marginBottom: 8 }}>SUMMARY</div>
            <div style={{ background: "#1e293b", borderRadius: 6, padding: 12, fontSize: 11 }}>
              <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
                <span style={{ color: "#64748b" }}>Mean</span>
                <span style={{ color: "#f8fafc" }}>{isFinite(mu) ? mu.toFixed(4) : "undefined"}</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
                <span style={{ color: "#64748b" }}>Variance</span>
                <span style={{ color: "#f8fafc" }}>{isFinite(v) ? v.toFixed(4) : "∞"}</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
                <span style={{ color: "#64748b" }}>Std Dev</span>
                <span style={{ color: "#f8fafc" }}>{isFinite(v) ? Math.sqrt(v).toFixed(4) : "∞"}</span>
              </div>
            </div>

            {/* Overlay selector */}
            <div style={{ fontSize: 12, fontWeight: 600, color: "#94a3b8", marginTop: 20, marginBottom: 8 }}>COMPARE WITH</div>
            <select value={showOverlay || ""} onChange={e => {
              const key = e.target.value || null;
              setShowOverlay(key);
              if (key) {
                const p = {};
                DISTS[key].params.forEach(pp => p[pp.key] = pp.default);
                setOverlayParams(p);
              }
            }} style={{
              width: "100%", background: "#1e293b", border: "1px solid #334155",
              borderRadius: 4, padding: "6px 8px", color: "#e2e8f0", fontSize: 11,
              fontFamily: "inherit"
            }}>
              <option value="">None</option>
              {Object.entries(DISTS).filter(([k]) => k !== distKey).map(([k, d]) => (
                <option key={k} value={k}>{d.name}</option>
              ))}
            </select>
          </div>
        </div>
      </div>
    </div>
  );
}
