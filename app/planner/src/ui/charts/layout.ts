// The chart kit's layouts (spec docs/specs/2026-10-30-charts-everywhere.md, "Common to all three"): the planner draws
// its charts by hand in SVG, with no chart library. Each function here only places what it's given: positions, sizes,
// colours and the words of each tip, so the unit tests can check a chart's figures without drawing it. The figures
// themselves come from the screens' own model functions, unchanged. Charts.tsx (beside this) draws them.

/** The planner's good, warn and bad colours (styles.css's --ok, --warn and --bad, as SVG fills need them), and its quiet
 *  grey and ink. */
export const TONE = { ok: "#1A7F55", warn: "#E39B21", bad: "#B4234B", mute: "#9AA4C4", ink: "#0E1630", violet: "#4B3BA8" } as const;
/** A run of quiet colours for series with no colour of their own (the rivals, the rest). */
export const SERIES = ["#4B3BA8", "#E86A92", "#1A7F55", "#E39B21", "#3B8FD8", "#8C94AD", "#B4234B", "#0E1630"] as const;

/** The next "nice" number at or above v (1, 2, 2.5 or 5 times a power of ten); 1 for 0 or less. */
export function niceCeil(v: number): number {
  if (!(v > 0) || !Number.isFinite(v)) return 1;
  const p = 10 ** Math.floor(Math.log10(v));
  for (const m of [1, 2, 2.5, 5, 10]) if (m * p >= v - 1e-12) return m * p;
  return 10 * p;
}
/** Tick values from lo to hi (lo and hi included when they're on a step), about n of them, on a nice step. */
export function ticks(lo: number, hi: number, n = 4): number[] {
  if (!(hi > lo)) return [lo];
  const step = niceCeil((hi - lo) / n);
  const out: number[] = [];
  for (let v = Math.ceil(lo / step - 1e-9) * step; v <= hi + 1e-9; v += step) out.push(Math.round(v * 1e9) / 1e9 || 0);
  return out;
}
const f1 = (v: number) => Number(v.toFixed(1));

// ---------- horizontal bars, with an optional reference line
export interface HBarItem { key: string; label: string; value: number; color?: string; tip: string }
export interface HBarLayout {
  W: number; H: number; L: number; R: number; T: number;
  zeroX: number;
  bars: { key: string; label: string; y: number; h: number; x: number; w: number; color: string; tip: string; text: string; textX: number; neg: boolean }[];
  ref: { x: number; label: string } | null;
  ticks: { x: number; label: string }[];
}
/** One row per item in the order given, a bar from zero to its value (left of zero when negative), its value at its end,
 *  the reference line (the airline's middle route, say) across every row; a tick axis along the bottom. */
export function hbarLayout(items: readonly HBarItem[], opts: { fmt: (v: number) => string; ref?: { value: number; label: string } | null; W?: number; row?: number; L?: number }): HBarLayout {
  // T leaves the reference line's label a line of its own over the bars; a losing bar's value is written left of it, so
  // the bars start that much right of the labels
  const W = opts.W ?? 560, row = opts.row ?? 22, L = opts.L ?? 96, R = 52, T = opts.ref ? 16 : 6, B = 22;
  const vals = items.map((x) => x.value).concat(opts.ref ? [opts.ref.value] : []);
  const lo = Math.min(0, ...vals), hi = Math.max(0, ...vals);
  const span = hi - lo || 1, x0 = L + (items.some((x) => x.value < 0) ? 46 : 0);
  const X = (v: number) => x0 + (v - lo) / span * (W - x0 - R);
  const H = T + items.length * row + B;
  return {
    W, H, L, R, T, zeroX: f1(X(0)),
    bars: items.map((x, i) => {
      const a = X(Math.min(0, x.value)), b = X(Math.max(0, x.value)), neg = x.value < 0;
      return { key: x.key, label: x.label, y: T + i * row + 3, h: row - 6, x: f1(a), w: f1(Math.max(b - a, x.value === 0 ? 0 : 1)), color: x.color ?? TONE.violet,
        tip: x.tip, text: opts.fmt(x.value), textX: f1(neg ? a - 4 : b + 4), neg };
    }),
    ref: opts.ref ? { x: f1(X(opts.ref.value)), label: opts.ref.label } : null,
    ticks: ticks(lo, hi, 4).map((v) => ({ x: f1(X(v)), label: opts.fmt(v) })),
  };
}

// ---------- stacked bars: one row per category, its parts side by side, each a series' colour
export interface StackSeries { key: string; label: string; color: string }
export interface StackRow { key: string; label: string; parts: Partial<Record<string, number>>; tip?: (series: StackSeries, n: number) => string }
export interface StackLayout {
  W: number; H: number; L: number;
  rows: { key: string; label: string; y: number; h: number; total: number; totalX: number; segs: { key: string; x: number; w: number; color: string; tip: string; value: number }[] }[];
  max: number;
}
/** Each row's parts in the series' order, laid end to end on one scale (the largest row's total), with its total at its
 *  end. A part of 0 has no segment. */
export function stackLayout(rows: readonly StackRow[], series: readonly StackSeries[], opts: { W?: number; row?: number; L?: number } = {}): StackLayout {
  const W = opts.W ?? 560, row = opts.row ?? 24, L = opts.L ?? 110, R = 34;
  const totals = rows.map((r) => series.reduce((t, s) => t + Math.max(0, r.parts[s.key] ?? 0), 0));
  const max = Math.max(1, ...totals);
  const per = (W - L - R) / max;
  return {
    W, H: rows.length * row + 4, L, max,
    rows: rows.map((r, i) => {
      let x = L;
      const segs = series.flatMap((s) => {
        const v = Math.max(0, r.parts[s.key] ?? 0);
        if (!v) return [];
        const seg = { key: s.key, x: f1(x), w: f1(v * per), color: s.color, value: v, tip: r.tip ? r.tip(s, v) : `${r.label} · ${s.label} ${v}` };
        x += v * per;
        return [seg];
      });
      return { key: r.key, label: r.label, y: i * row + 3, h: row - 8, total: totals[i] ?? 0, totalX: f1(x + 5), segs };
    }),
  };
}

// ---------- a donut: each part's arc of the whole
export interface DonutPart { key: string; label: string; value: number; color: string }
export interface DonutLayout { size: number; total: number; arcs: { key: string; d: string; color: string; pct: number; tip: string }[] }
/** Arcs clockwise from the top, each part's share of the total (parts of 0 left out), as SVG paths of a ring. */
export function donutLayout(parts: readonly DonutPart[], opts: { size?: number; ring?: number; fmt?: (v: number) => string } = {}): DonutLayout {
  const size = opts.size ?? 140, R = size / 2, r = R - (opts.ring ?? 22), c = R;
  const shown = parts.filter((p) => p.value > 0);
  const total = shown.reduce((t, p) => t + p.value, 0);
  let a0 = 0;
  const pt = (rad: number, a: number) => `${f1(c + rad * Math.sin(a))},${f1(c - rad * Math.cos(a))}`;
  return {
    size, total,
    arcs: shown.map((p) => {
      const frac = total ? p.value / total : 0;
      // a whole ring can't be one arc: draw it as two halves
      const a1 = a0 + Math.min(frac, 0.99999) * 2 * Math.PI, big = frac > 0.5 ? 1 : 0;
      const d = `M${pt(R, a0)} A${R},${R} 0 ${big} 1 ${pt(R, a1)} L${pt(r, a1)} A${r},${r} 0 ${big} 0 ${pt(r, a0)} Z`;
      a0 += frac * 2 * Math.PI;
      const pct = Math.round(frac * 1000) / 10;
      return { key: p.key, d, color: p.color, pct, tip: `${p.label} ${opts.fmt ? opts.fmt(p.value) : p.value} (${pct}%)` };
    }),
  };
}

// ---------- a step line on a time axis, with reference lines, markers and its lowest point
export interface StepPoint { t: number; v: number }
export interface StepMarker { t: number; v: number; tip: string; cls?: string }
export interface StepLayout {
  W: number; H: number; L: number; R: number; T: number; B: number;
  path: string;
  refs: { y: number; label: string; cls: string }[];
  markers: { x: number; y: number; tip: string; cls: string }[];
  low: { x: number; y: number; label: string; bad: boolean } | null;
  yTicks: { y: number; label: string }[];
  xTicks: { x: number; label: string }[];
  zeroY: number | null;
}
/** The value holds level until the next point, then steps (a balance that moves at each payment); the reference lines
 *  (a cushion) across the whole width; each marker a dot at its moment and value; the lowest point marked and called bad
 *  when it's under the first reference line. */
export function stepLayout(points: readonly StepPoint[], opts: {
  t0: number; t1: number; fmt: (v: number) => string; refs?: { value: number; label: string; cls?: string }[]; markers?: readonly StepMarker[];
  low?: StepPoint | null; xTicks?: { t: number; label: string }[]; W?: number; H?: number;
}): StepLayout | null {
  if (!points.length) return null;
  const W = opts.W ?? 900, H = opts.H ?? 210, L = 52, R = 18, T = 14, B = 26;
  const vals = points.map((p) => p.v).concat((opts.refs ?? []).map((r) => r.value)).concat((opts.markers ?? []).map((m) => m.v));
  const lo = Math.min(0, ...vals), hi = Math.max(...vals) * 1.08 || 1;
  const X = (t: number) => L + (Math.max(opts.t0, Math.min(opts.t1, t)) - opts.t0) / ((opts.t1 - opts.t0) || 1) * (W - L - R);
  const Y = (v: number) => T + (hi - v) / ((hi - lo) || 1) * (H - T - B);
  let path = "";
  points.forEach((p, i) => {
    if (!i) { path = `M${f1(X(p.t))},${f1(Y(p.v))}`; return; }
    path += ` L${f1(X(p.t))},${f1(Y((points[i - 1] as StepPoint).v))} L${f1(X(p.t))},${f1(Y(p.v))}`;
  });
  const last = points[points.length - 1] as StepPoint;
  if (X(last.t) < W - R) path += ` L${f1(W - R)},${f1(Y(last.v))}`;
  const first = opts.refs?.[0];
  return {
    W, H, L, R, T, B, path,
    refs: (opts.refs ?? []).map((r) => ({ y: f1(Y(r.value)), label: r.label, cls: r.cls ?? "ref" })),
    markers: (opts.markers ?? []).map((m) => ({ x: f1(X(m.t)), y: f1(Y(m.v)), tip: m.tip, cls: m.cls ?? "" })),
    low: opts.low ? { x: f1(X(opts.low.t)), y: f1(Y(opts.low.v)), label: `lowest ${opts.fmt(opts.low.v)}`, bad: !!first && opts.low.v < first.value } : null,
    yTicks: ticks(lo, hi, 4).map((v) => ({ y: f1(Y(v)), label: opts.fmt(v) })),
    xTicks: (opts.xTicks ?? []).map((x) => ({ x: f1(X(x.t)), label: x.label })),
    zeroY: lo < 0 ? f1(Y(0)) : null,
  };
}

// ---------- a timeline: one row per thing, a marker at each of its moments
export interface TimelineMark { t: number; kind: string; tip: string }
export interface TimelineRow { key: string; label: string; marks: readonly TimelineMark[] }
export interface TimelineLayout {
  W: number; H: number; L: number; R: number;
  rows: { key: string; label: string; y: number; marks: { x: number; kind: string; tip: string }[]; span: { x0: number; x1: number } | null }[];
  ticks: { x: number; label: string }[];
  now: number | null;
}
/** Rows top to bottom, each mark at its moment between t0 and t1 (clamped to the edges), a thin line joining a row's
 *  first and last mark; ticks under the rows; "now" a line when given. */
export function timelineLayout(rows: readonly TimelineRow[], opts: { t0: number; t1: number; ticks?: { t: number; label: string }[]; now?: number; W?: number; row?: number; L?: number }): TimelineLayout {
  const W = opts.W ?? 560, row = opts.row ?? 22, L = opts.L ?? 130, R = 14;
  const X = (t: number) => f1(L + (Math.max(opts.t0, Math.min(opts.t1, t)) - opts.t0) / ((opts.t1 - opts.t0) || 1) * (W - L - R));
  return {
    W, H: rows.length * row + 24, L, R,
    rows: rows.map((r, i) => {
      const xs = r.marks.map((m) => X(m.t));
      return { key: r.key, label: r.label, y: i * row + row / 2, marks: r.marks.map((m, j) => ({ x: xs[j] as number, kind: m.kind, tip: m.tip })),
        span: xs.length > 1 ? { x0: Math.min(...xs), x1: Math.max(...xs) } : null };
    }),
    ticks: (opts.ticks ?? []).map((x) => ({ x: X(x.t), label: x.label })),
    now: opts.now != null ? X(opts.now) : null,
  };
}

// ---------- a scatter with sized points
export interface SizedPoint { key: string; x: number; y: number; size: number; color: string; tip: string; ring?: boolean }
export interface SizedScatterLayout {
  W: number; H: number; L: number; B: number;
  points: { key: string; cx: number; cy: number; r: number; color: string; tip: string; ring: boolean }[];
  xTicks: { x: number; label: string }[]; yTicks: { y: number; label: string }[];
}
/** Each point at its x and y, its area by its size (radius 3 to 14 px), the larger drawn first so the small stay on top. */
export function sizedScatterLayout(points: readonly SizedPoint[], opts: { fmtX?: (v: number) => string; fmtY?: (v: number) => string; W?: number; H?: number } = {}): SizedScatterLayout {
  const W = opts.W ?? 560, H = opts.H ?? 260, L = 44, R = 16, T = 12, B = 30;
  const xs = points.map((p) => p.x), ys = points.map((p) => p.y), ss = points.map((p) => p.size);
  const x0 = Math.min(0, ...xs), x1 = Math.max(1, ...xs) * 1.05, y0 = Math.min(0, ...ys), y1 = Math.max(1, ...ys) * 1.08;
  const smax = Math.max(1, ...ss);
  const X = (v: number) => L + (v - x0) / (x1 - x0) * (W - L - R), Y = (v: number) => T + (y1 - v) / (y1 - y0) * (H - T - B);
  return {
    W, H, L, B,
    points: points.map((p) => ({ key: p.key, cx: f1(X(p.x)), cy: f1(Y(p.y)), r: f1(3 + 11 * Math.sqrt(Math.max(0, p.size) / smax)), color: p.color, tip: p.tip, ring: !!p.ring }))
      .sort((a, b) => b.r - a.r),
    xTicks: ticks(x0, x1, 4).map((v) => ({ x: f1(X(v)), label: (opts.fmtX ?? String)(v) })),
    yTicks: ticks(y0, y1, 4).map((v) => ({ y: f1(Y(v)), label: (opts.fmtY ?? String)(v) })),
  };
}

// ---------- a gauge: a figure against its trigger
export interface GaugeLayout { pct: number; tone: "ok" | "warn" | "bad"; arc: string; track: string; size: number }
/** Half a ring, filled to the figure's share of its trigger (at most all of it): amber from warnShare, red at the
 *  trigger, as the Systems board marks usage. */
export function gaugeLayout(value: number, trigger: number, warnShare = 0.7, size = 120): GaugeLayout {
  const share = trigger > 0 ? value / trigger : 0, s = Math.max(0, Math.min(1, share));
  const R = size / 2 - 8, c = size / 2, cy = size / 2;
  const at = (f: number) => { const a = Math.PI * (1 - f); return `${f1(c + R * Math.cos(a))},${f1(cy - R * Math.sin(a))}`; };
  return {
    pct: Math.round(share * 100), tone: share >= 1 ? "bad" : share >= warnShare ? "warn" : "ok", size,
    track: `M${at(0)} A${R},${R} 0 0 1 ${at(1)}`,
    arc: s > 0 ? `M${at(0)} A${R},${R} 0 0 1 ${at(s)}` : "",
  };
}

// ---------- a heat strip: rows of cells, each coloured by its value
export interface HeatRow { key: string; label: string; cells: readonly ({ value: number | null; tip: string } | null)[] }
export interface HeatLayout {
  W: number; H: number; L: number; cw: number; row: number;
  rows: { key: string; label: string; y: number; cells: { x: number; fill: string; tip: string; value: number | null; empty: boolean }[] }[];
  cols: { x: number; label: string }[];
}
/** A load's colour as the planner marks loads: 95% and up green, 85 amber, 70 orange, under that red; grey with no
 *  figure (a cell with flights and no load), nothing for an empty cell. */
export function loadFill(v: number | null): string {
  if (v == null) return "#D9DDE7";
  return v >= 95 ? "#1E9E6A" : v >= 85 ? "#E3B341" : v >= 70 ? "#E3812B" : "#B4234B";
}
/** Each row's cells left to right, one column per label, coloured by fill (loadFill unless given). */
export function heatLayout(rows: readonly HeatRow[], cols: readonly string[], opts: { W?: number; row?: number; L?: number; fill?: (v: number | null) => string; every?: number } = {}): HeatLayout {
  const W = opts.W ?? 720, row = opts.row ?? 20, L = opts.L ?? 96;
  const cw = (W - L) / Math.max(1, cols.length);
  const fill = opts.fill ?? loadFill, every = opts.every ?? 1;
  return {
    W, H: rows.length * row + 20, L, cw: f1(cw), row,
    rows: rows.map((r, i) => ({
      key: r.key, label: r.label, y: i * row,
      cells: r.cells.map((c, j) => ({ x: f1(L + j * cw), fill: c ? fill(c.value) : "none", tip: c?.tip ?? "", value: c?.value ?? null, empty: !c })),
    })),
    cols: cols.flatMap((c, j) => (j % every === 0 ? [{ x: f1(L + (j + 0.5) * cw), label: c }] : [])),
  };
}

// ---------- a small line or bars for small multiples
export interface SparkLayout { W: number; H: number; path: string | null; bars: { x: number; y: number; w: number; h: number; neg: boolean }[]; zeroY: number | null; last: number | null }
/** Values left to right (nulls break a line; a bar's null is no bar), on their own scale (0 included for bars). */
export function sparkLayout(values: readonly (number | null)[], kind: "line" | "bar", opts: { W?: number; H?: number; lo?: number; hi?: number } = {}): SparkLayout {
  const W = opts.W ?? 120, H = opts.H ?? 34, pad = 3;
  const vs = values.filter((v): v is number => v != null);
  const last = [...values].reverse().find((v): v is number => v != null) ?? null;
  if (!vs.length) return { W, H, path: null, bars: [], zeroY: null, last: null };
  const lo = opts.lo ?? (kind === "bar" ? Math.min(0, ...vs) : Math.min(...vs)), hi0 = opts.hi ?? (kind === "bar" ? Math.max(0, ...vs) : Math.max(...vs));
  const hi = hi0 > lo ? hi0 : lo + 1;
  const Y = (v: number) => pad + (hi - v) / (hi - lo) * (H - pad * 2);
  const n = values.length, cw = (W - pad * 2) / Math.max(1, n);
  if (kind === "bar") {
    const z = Y(0);
    return { W, H, path: null, zeroY: f1(z), last,
      bars: values.flatMap((v, i) => (v == null ? [] : [{ x: f1(pad + i * cw + cw * 0.15), y: f1(Math.min(z, Y(v))), w: f1(cw * 0.7), h: f1(Math.max(0.5, Math.abs(Y(v) - z))), neg: v < 0 }])) };
  }
  let path = "", open = false;
  values.forEach((v, i) => {
    if (v == null) { open = false; return; }
    path += `${open ? " L" : path ? " M" : "M"}${f1(pad + (i + 0.5) * cw)},${f1(Y(v))}`;
    open = true;
  });
  return { W, H, path, bars: [], zeroY: null, last };
}
