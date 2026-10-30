// The chart kit (spec docs/specs/2026-10-30-charts-everywhere.md, "Common to all three"): the planner's charts, drawn by
// hand in SVG from layout.ts's layouts, with no chart library.
//   - ChartFrame: a chart's title, its one-line note, a legend where there's more than one series (in the page's type, so
//     never scaled down), and its empty state in words.
//   - ChartTip: every chart's box. Hover anything with a data-tip for its exact figure. A click or tap on the chart, or
//     Enter on it (it's a button with a label), opens it full size in an overlay: most of the window, the whole screen on
//     a phone, drawn again at that size, with its tips (tap for them there) and, where the chart stands in front of a
//     table, its "show as table". Esc, the X or a click outside closes it. A click on something of the chart's own (a
//     segment that opens a list, a link, a button) does that instead.
//   - Readable where it sits: the kit's charts are laid out at the width they're shown (Sized), so their text is 11 px
//     on screen; a chart drawn at a fixed width (the route story's, the pair's) keeps its text at 11 px on screen however
//     much the chart shrinks (readable()). Either way, axis labels that would then run into each other are dropped,
//     never shrunk.
//   - ChartOrTable: "show as table", remembered per board in this browser.
import { createContext, useCallback, useContext, useEffect, useLayoutEffect, useRef, useState, type KeyboardEvent, type MouseEvent as RMouseEvent, type ReactNode, type RefObject } from "react";
import { createPortal } from "react-dom";
import type {
  DonutLayout, GaugeLayout, HBarLayout, HeatLayout, SizedScatterLayout, SparkLayout, StackLayout, StepLayout, TimelineLayout,
} from "./layout";

/** The smallest text a chart shows, in screen px. */
export const MIN_TEXT_PX = 11;

/** True inside the large view: there a tap shows a tip, and nothing opens another large view. */
const InBig = createContext(false);

const useIsoLayoutEffect = typeof window !== "undefined" ? useLayoutEffect : useEffect;

/** The width a box is shown at, kept up to date as it's resized; `fallback` before it's measured (and on the server and
 *  in the tests, which have no layout). */
export function useWidth(fallback: number): [RefObject<HTMLDivElement | null>, number] {
  const ref = useRef<HTMLDivElement>(null);
  const [w, setW] = useState(fallback);
  useIsoLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const set = () => { const x = Math.round(el.clientWidth); if (x > 0) setW((old) => (Math.abs(old - x) > 1 ? x : old)); };
    set();
    if (typeof ResizeObserver === "undefined") return;
    const ro = new ResizeObserver(set);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  return [ref, w];
}
/** Draws its children at the width it's shown (at least `min`), so a chart's text stays its own size; `big` says it's
 *  the large view. */
export function Sized({ fallback = 560, min = 260, children }: { fallback?: number; min?: number; children: (w: number, big: boolean) => ReactNode }) {
  const [ref, w] = useWidth(fallback);
  const big = useContext(InBig);
  return <div className="ksized" ref={ref}>{children(Math.max(min, w), big)}</div>;
}

/** Keeps a chart's text at MIN_TEXT_PX on screen (the inverse of its scale, as a CSS variable its text reads) and drops
 *  axis labels that would then run into each other: x labels (middle-anchored, on one line) left to right, y labels
 *  (end-anchored, in one column) top to bottom. A dropped label is hidden, never shrunk. */
export function readable(box: HTMLElement) {
  for (const svg of Array.from(box.querySelectorAll<SVGSVGElement>("svg.lchart, svg.kchart"))) {
    const vb = svg.viewBox?.baseVal, shown = svg.getBoundingClientRect().width;
    if (!vb || !vb.width || !shown) continue;
    const scale = shown / vb.width;
    svg.style.setProperty("--kfs", `${(MIN_TEXT_PX / scale).toFixed(2)}px`);
    const groups = new Map<string, SVGTextElement[]>();
    for (const t of Array.from(svg.querySelectorAll<SVGTextElement>("text"))) {
      t.style.visibility = "";
      const a = t.getAttribute("text-anchor");
      if (a !== "middle" && a !== "end") continue;
      const k = a === "middle" ? `x|${t.getAttribute("y")}` : `y|${t.getAttribute("x")}`;
      const list = groups.get(k);
      if (list) list.push(t); else groups.set(k, [t]);
    }
    for (const [k, list] of groups) {
      if (list.length < 3) continue;
      const across = k.startsWith("x");
      const sorted = list.map((t) => ({ t, r: t.getBoundingClientRect() })).sort((a, b) => (across ? a.r.left - b.r.left : a.r.top - b.r.top));
      let last: DOMRect | null = null;
      for (const x of sorted) {
        if (last && (across ? x.r.left < last.right + 4 : x.r.top < last.bottom)) { x.t.style.visibility = "hidden"; continue; }
        last = x.r;
      }
    }
  }
}

/** The table a chart stands in front of (from ChartOrTable), for the large view's "show as table". */
const TableCtx = createContext<ReactNode | null>(null);

/** A chart's box: its tips, its large view on click, and its text kept readable (see the top of this file). */
export function ChartTip({ children, className = "chartwrap", label = "chart" }: { children: ReactNode; className?: string; label?: string }) {
  const wrap = useRef<HTMLDivElement>(null), tip = useRef<HTMLDivElement>(null);
  const [big, setBig] = useState(false);
  const inBig = useContext(InBig);
  const close = useCallback(() => { setBig(false); wrap.current?.focus(); }, []);
  useIsoLayoutEffect(() => {
    const el = wrap.current;
    if (!el) return;
    readable(el);
    if (typeof ResizeObserver === "undefined") return;
    const ro = new ResizeObserver(() => readable(el));
    ro.observe(el);
    return () => ro.disconnect();
  });
  const show = (e: RMouseEvent<HTMLDivElement>) => {
    const t = tip.current, w = wrap.current;
    if (!t || !w) return;
    const el = (e.target as Element).closest?.("[data-tip]");
    if (!el || !el.getAttribute("data-tip")) { t.style.display = "none"; return; }
    const r = w.getBoundingClientRect();
    t.textContent = el.getAttribute("data-tip");
    t.style.display = "block";
    const x = e.clientX - r.left, y = e.clientY - r.top;
    t.style.left = Math.max(0, Math.min(x + 14, r.width - t.offsetWidth - 6)) + "px";
    t.style.top = (y + 16 + t.offsetHeight > r.height ? y - t.offsetHeight - 10 : y + 16) + "px";
  };
  const click = (e: RMouseEvent<HTMLDivElement>) => {
    if (inBig) { show(e); return; }
    if ((e.target as Element).closest?.("a, button, .kpick")) return;
    if (tip.current) tip.current.style.display = "none";
    setBig(true);
  };
  const key = (e: KeyboardEvent<HTMLDivElement>) => {
    if (inBig || e.target !== e.currentTarget || (e.key !== "Enter" && e.key !== " ")) return;
    e.preventDefault();
    setBig(true);
  };
  return (
    <>
      <div className={className + (inBig ? "" : " kopen")} ref={wrap} onMouseMove={show} onClick={click} onKeyDown={key}
        onMouseLeave={() => { if (tip.current) tip.current.style.display = "none"; }}
        role={inBig ? undefined : "button"} tabIndex={inBig ? undefined : 0} aria-label={inBig ? undefined : `Open the ${label} full size`}
        data-chart-open={inBig ? undefined : label}>
        {children}
        <div className="maptip" ref={tip} />
      </div>
      {big ? <BigView label={label} onClose={close}>{children}</BigView> : null}
    </>
  );
}

/** The large view: the chart drawn again at most of the window's size, with "show as table" when it has a table. */
function BigView({ label, onClose, children }: { label: string; onClose: () => void; children: ReactNode }) {
  const table = useContext(TableCtx);
  const [showTable, setShowTable] = useState(false);
  const panel = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const esc = (e: globalThis.KeyboardEvent) => { if (e.key === "Escape") { e.stopPropagation(); onClose(); } };
    document.addEventListener("keydown", esc);
    const was = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    panel.current?.focus();
    return () => { document.removeEventListener("keydown", esc); document.body.style.overflow = was; };
  }, [onClose]);
  const view = (
    <div className="kbig" data-chart-big={label} onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="kbigp" role="dialog" aria-modal="true" aria-label={label} tabIndex={-1} ref={panel}>
        <div className="kbigh">
          <b>{label.charAt(0).toUpperCase() + label.slice(1)}</b>
          {table ? <button type="button" className="link sm" data-big-table-toggle aria-pressed={showTable} onClick={() => setShowTable((x) => !x)}>{showTable ? "show as chart" : "show as table"}</button> : null}
          <button type="button" className="kbigx" aria-label="Close" data-big-close onClick={onClose}>×</button>
        </div>
        <div className="kbigb">
          <InBig.Provider value={true}>
            {showTable && table ? table : <ChartTip className="chartwrap kbigc" label={label}>{children}</ChartTip>}
          </InBig.Provider>
        </div>
      </div>
    </div>
  );
  return typeof document !== "undefined" ? createPortal(view, document.body) : view;
}

export interface LegendItem { label: string; color: string; dashed?: boolean }
/** A legend in the page's own type, so it's never scaled down with a chart (nothing for a single series). */
export function Legend({ items }: { items: readonly LegendItem[] }) {
  return items.length > 1 ? (
    <ul className="kcl">{items.map((l) => <li key={l.label}><i className={l.dashed ? "dash" : undefined} style={{ background: l.dashed ? undefined : l.color, borderColor: l.color }} />{l.label}</li>)}</ul>
  ) : null;
}
/** A chart's frame: its title and one-line note (as the boards have), its legend, and its empty state in words. */
export function ChartFrame({ title, note, legend, empty, figure, children }: {
  title?: ReactNode; note?: ReactNode; legend?: readonly LegendItem[]; empty?: string | null; figure?: string; children?: ReactNode;
}) {
  return (
    <div className="kc" data-figure={figure} data-chart-empty={empty ? "yes" : undefined}>
      {title ? <div className="kct">{title}{note ? <span className="dim"> · {note}</span> : null}</div> : null}
      {empty ? <div className="dim kce">{empty}</div> : <>
        {children}
        {legend ? <Legend items={legend} /> : null}
      </>}
    </div>
  );
}

/** Horizontal bars, with the reference line and its label, laid out at the width shown. */
export function HBars({ layout, figure, label = "bar chart" }: { layout: (W: number) => HBarLayout; figure?: string; label?: string }) {
  return (
    <ChartTip label={label}>
      <Sized>{(w) => {
        const g = layout(w);
        return (
          <svg className="kchart khbar" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label={label} data-figure={figure} data-bars={g.bars.length}>
            {g.ticks.map((t, i) => <g key={i}><line x1={t.x} x2={t.x} y1={g.T} y2={g.H - 18} className="grid" /><text x={t.x} y={g.H - 5} textAnchor="middle">{t.label}</text></g>)}
            <line x1={g.zeroX} x2={g.zeroX} y1={g.T} y2={g.H - 18} className="zero" />
            {g.bars.map((b) => (
              <g key={b.key} data-bar={b.key}>
                <text x={g.L - 6} y={b.y + b.h / 2 + 4} textAnchor="end" className="klab">{b.label}</text>
                <rect x={b.x} y={b.y} width={b.w} height={b.h} rx="3" fill={b.color} data-tip={b.tip} />
                <text x={b.textX} y={b.y + b.h / 2 + 4} textAnchor={b.neg ? "end" : "start"} className="kval">{b.text}</text>
              </g>
            ))}
            {g.ref ? <g className="kref"><line x1={g.ref.x} x2={g.ref.x} y1={0} y2={g.H - 18} />
              {g.ref.x > g.W * 0.6 ? <text x={g.ref.x - 4} y={10} style={{ textAnchor: "end" }}>{g.ref.label}</text> : <text x={g.ref.x + 4} y={10}>{g.ref.label}</text>}</g> : null}
          </svg>
        );
      }}</Sized>
    </ChartTip>
  );
}

/** Stacked bars: a row per category, each segment a series; a segment may open something (onPick). */
export function StackedBars({ layout, figure, onPick, label = "bar chart" }: { layout: (W: number) => StackLayout; figure?: string; onPick?: (row: string, series: string) => void; label?: string }) {
  return (
    <ChartTip label={label}>
      <Sized>{(w) => {
        const g = layout(w);
        return (
          <svg className="kchart kstack" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label={label} data-figure={figure} data-rows={g.rows.length}>
            {g.rows.map((r) => (
              <g key={r.key} data-stack-row={r.key}>
                <text x={g.L - 6} y={r.y + r.h / 2 + 4} textAnchor="end" className="klab">{r.label}</text>
                {r.segs.map((s) => (
                  <rect key={s.key} x={s.x} y={r.y} width={s.w} height={r.h} fill={s.color} data-tip={s.tip} data-seg={`${r.key}|${s.key}`}
                    className={onPick ? "kpick" : undefined} onClick={onPick ? () => onPick(r.key, s.key) : undefined} />
                ))}
                {r.total ? <text x={r.totalX} y={r.y + r.h / 2 + 4} className="kval">{r.total}</text> : <text x={g.L + 4} y={r.y + r.h / 2 + 4} className="kval dim">none</text>}
              </g>
            ))}
          </svg>
        );
      }}</Sized>
    </ChartTip>
  );
}

/** A donut, with its middle words (drawn at its own size: it doesn't stretch). */
export function Donut({ g, middle, figure, label = "share" }: { g: DonutLayout; middle?: ReactNode; figure?: string; label?: string }) {
  return (
    <ChartTip className="chartwrap kdonutw" label={label}>
      <svg className="kchart kdonut" viewBox={`0 0 ${g.size} ${g.size}`} role="img" aria-label={label} data-figure={figure} style={{ maxWidth: g.size }}>
        {g.arcs.map((a) => <path key={a.key} d={a.d} fill={a.color} data-tip={a.tip} />)}
        {middle ? <text x={g.size / 2} y={g.size / 2 + 5} style={{ textAnchor: "middle" }} className="kmid">{middle}</text> : null}
      </svg>
    </ChartTip>
  );
}

/** A step line on a time axis, with its reference lines, markers and lowest point, laid out at the width shown. */
export function StepLine({ layout, figure, label }: { layout: (W: number, H?: number) => StepLayout | null; figure?: string; label: string }) {
  return (
    <ChartTip label={label}>
      <Sized fallback={900}>{(w, big) => {
        // full size, taller too (most of the window, as wide charts go)
        const g = layout(w, big ? Math.round(Math.max(260, Math.min(560, w * 0.42))) : undefined);
        if (!g) return null;
        return (
          <svg className="kchart kstep" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label={label} data-figure={figure} data-markers={g.markers.length}>
            {g.yTicks.map((t, i) => <g key={i}><line x1={g.L} x2={g.W - g.R} y1={t.y} y2={t.y} className="grid" /><text x={g.L - 6} y={t.y + 4} textAnchor="end">{t.label}</text></g>)}
            {g.xTicks.map((t, i) => <text key={i} x={t.x} y={g.H - 8} textAnchor="middle">{t.label}</text>)}
            {g.zeroY != null ? <line x1={g.L} x2={g.W - g.R} y1={g.zeroY} y2={g.zeroY} className="zero" /> : null}
            {g.refs.map((r, i) => <g key={i} className={"kref " + r.cls}><line x1={g.L} x2={g.W - g.R} y1={r.y} y2={r.y} /><text x={g.L + 4} y={r.y - 4}>{r.label}</text></g>)}
            <path d={g.path} className="kline" />
            {g.markers.map((m, i) => <circle key={i} cx={m.x} cy={m.y} r="4.5" className={"kmark " + m.cls} data-tip={m.tip} />)}
            {g.low ? <g className={"klow" + (g.low.bad ? " bad" : "")}><circle cx={g.low.x} cy={g.low.y} r="6" /><text {...lowLabel(g)}>{g.low.label}</text></g> : null}
          </svg>
        );
      }}</Sized>
    </ChartTip>
  );
}

/** The lowest point's words: beside the point on the side with room, under it unless that's the bottom or a reference
 *  line's label is there. */
function lowLabel(g: StepLayout): { x: number; y: number; style?: { textAnchor: "end" } } {
  const low = g.low!, right = low.x > (g.L + g.W - g.R) / 2;
  const under = low.y + 18, crowded = under > g.H - g.B - 2 || g.refs.some((r) => Math.abs(r.y - 4 - under) < 14);
  return { x: right ? low.x - 9 : low.x + 9, y: crowded ? low.y - 10 : under, ...(right ? { style: { textAnchor: "end" as const } } : {}) };
}

/** A timeline: a row per thing, each mark at its moment; kinds are classes (styled in styles.css). */
export function Timeline({ layout, figure, label = "timeline" }: { layout: (W: number) => TimelineLayout; figure?: string; label?: string }) {
  return (
    <ChartTip label={label}>
      <Sized>{(w) => {
        const g = layout(w);
        return (
          <svg className="kchart ktime" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label={label} data-figure={figure} data-rows={g.rows.length}>
            {g.ticks.map((t, i) => <g key={i}><line x1={t.x} x2={t.x} y1={0} y2={g.H - 20} className="grid" /><text x={t.x} y={g.H - 6} textAnchor="middle">{t.label}</text></g>)}
            {g.now != null ? <line x1={g.now} x2={g.now} y1={0} y2={g.H - 20} className="know" /> : null}
            {g.rows.map((r) => (
              <g key={r.key} data-time-row={r.key}>
                <text x={g.L - 6} y={r.y + 4} textAnchor="end" className="klab">{r.label}</text>
                {r.span ? <line x1={r.span.x0} x2={r.span.x1} y1={r.y} y2={r.y} className="kspan" /> : null}
                {r.marks.map((m, i) => <circle key={i} cx={m.x} cy={r.y} r="5.5" className={"kmark " + m.kind} data-tip={m.tip} data-mark={m.kind} />)}
              </g>
            ))}
          </svg>
        );
      }}</Sized>
    </ChartTip>
  );
}

/** A scatter with sized points; a ring marks a point (hubs first, say). */
export function SizedScatter({ layout, figure, xLabel, yLabel }: { layout: (W: number) => SizedScatterLayout; figure?: string; xLabel: string; yLabel: string }) {
  const label = `${yLabel} against ${xLabel}`;
  return (
    <ChartTip label={label}>
      <Sized>{(w) => {
        const g = layout(w);
        return (
          <svg className="kchart kscatter" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label={label} data-figure={figure} data-points={g.points.length}>
            {g.yTicks.map((t, i) => <g key={i}><line x1={g.L} x2={g.W - 16} y1={t.y} y2={t.y} className="grid" /><text x={g.L - 6} y={t.y + 4} textAnchor="end">{t.label}</text></g>)}
            {g.xTicks.map((t, i) => <text key={i} x={t.x} y={g.H - g.B + 16} textAnchor="middle">{t.label}</text>)}
            <text x={g.W - 16} y={g.H - 2} style={{ textAnchor: "end" }} className="kax">{xLabel}</text>
            <text x={4} y={10} className="kax">{yLabel}</text>
            {g.points.map((p) => <circle key={p.key} cx={p.cx} cy={p.cy} r={p.r} fill={p.color} className={p.ring ? "kring" : undefined} data-tip={p.tip} />)}
          </svg>
        );
      }}</Sized>
    </ChartTip>
  );
}

/** A gauge: the figure's share of its trigger, in its tone. */
export function Gauge({ g, label, figure }: { g: GaugeLayout; label: ReactNode; figure?: string }) {
  return (
    <div className="kgauge" data-figure={figure} data-tone={g.tone}>
      <svg viewBox={`0 0 ${g.size} ${g.size / 2 + 6}`} role="img" aria-label={`${g.pct}% of its trigger`}>
        <path d={g.track} className="ktrack" />
        {g.arc ? <path d={g.arc} className={"karc " + g.tone} /> : null}
        <text x={g.size / 2} y={g.size / 2} textAnchor="middle" className="kmid">{g.pct}%</text>
      </svg>
      <div className="kgl">{label}</div>
    </div>
  );
}

/** A heat strip: rows of cells, each coloured by its value, with column labels under them, laid out at the width shown. */
export function HeatStrip({ layout, figure, label = "heat strip" }: { layout: (W: number) => HeatLayout; figure?: string; label?: string }) {
  return (
    <ChartTip label={label}>
      <Sized fallback={720}>{(w) => {
        const g = layout(w);
        return (
          <svg className="kchart kheat" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label={label} data-figure={figure} data-rows={g.rows.length}>
            {g.rows.map((r) => (
              <g key={r.key} data-heat-row={r.key}>
                <text x={g.L - 6} y={r.y + g.row / 2 + 4} textAnchor="end" className="klab">{r.label}</text>
                {r.cells.map((c, i) => (c.empty ? <rect key={i} x={c.x + 1} y={r.y + 2} width={Math.max(0, g.cw - 2)} height={g.row - 4} className="kcell0" />
                  : <rect key={i} x={c.x + 1} y={r.y + 2} width={Math.max(0, g.cw - 2)} height={g.row - 4} rx="2" fill={c.fill} data-tip={c.tip} />))}
              </g>
            ))}
            {g.cols.map((c, i) => <text key={i} x={c.x} y={g.H - 4} textAnchor="middle">{c.label}</text>)}
          </svg>
        );
      }}</Sized>
    </ChartTip>
  );
}

/** A small line or bar chart for small multiples, with its tip (put the multiples in a ChartTip). */
export function Spark({ g, tip, label }: { g: SparkLayout; tip: string; label: string }) {
  return (
    <svg className="kspark" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label={label} data-tip={tip} preserveAspectRatio="none">
      {g.zeroY != null ? <line x1="0" x2={g.W} y1={g.zeroY} y2={g.zeroY} className="zero" vectorEffect="non-scaling-stroke" /> : null}
      {g.path ? <path d={g.path} vectorEffect="non-scaling-stroke" /> : null}
      {g.bars.map((b, i) => <rect key={i} x={b.x} y={b.y} width={b.w} height={b.h} className={b.neg ? "neg" : "pos"} />)}
      <rect x="0" y="0" width={g.W} height={g.H} fill="transparent" data-tip={tip} />
    </svg>
  );
}

// ---------- a table one tap away: "show as table", remembered per board
const STORE = "eq.showTable.";
const read = (k: string): boolean => {
  try { return typeof localStorage !== "undefined" && localStorage.getItem(STORE + k) === "1"; } catch { return false; }
};
/** Whether the board shows its table (remembered in this browser, per board), and the switch. */
export function useShowTable(k: string): [boolean, () => void] {
  const [on, setOn] = useState(() => read(k));
  const flip = () => setOn((x) => {
    const n = !x;
    try { if (typeof localStorage !== "undefined") { if (n) localStorage.setItem(STORE + k, "1"); else localStorage.removeItem(STORE + k); } } catch { /* a private window: not remembered */ }
    return n;
  });
  return [on, flip];
}
/** The chart, or the table it replaced, with "show as table" / "show as chart" to switch (remembered per board). The
 *  chart's large view has the same switch. */
export function ChartOrTable({ k, chart, table }: { k: string; chart: ReactNode; table: ReactNode }) {
  const [on, flip] = useShowTable(k);
  return (
    <div className="kcot" data-chart-or-table={k} data-showing={on ? "table" : "chart"}>
      <div className="kcotb"><button type="button" className="link sm" data-table-toggle={k} aria-pressed={on} onClick={flip}>{on ? "show as chart" : "show as table"}</button></div>
      {on ? table : <TableCtx.Provider value={table}>{chart}</TableCtx.Provider>}
    </div>
  );
}
