// Review's charts, drawn as the old Review draws them (web/planner/index.html: barChart, spark, forecastBoard's chart,
// rpScatter, rpCost, rpTailChart and groupOverviewHtml's chart), from the layouts in model.ts. A tip follows the pointer
// over anything with a data-tip, as the old .maptip does. Since 30 Oct (spec docs/specs/2026-10-30-charts-everywhere.md)
// the tip is the chart kit's (src/ui/charts), where the new charts are drawn: so a click opens each chart full size, and
// its text stays 11 px on screen however small the chart is drawn. The route charts' legends are in the page's type
// (Legend), under the chart, so they're never scaled down with it.
import { ChartTip, HBars, Legend, Sized, fitText, hbarLayout } from "../../ui/charts";
import { tailItems } from "./charts";
import {
  barLayout, costParts, groupLayout, loadSparkBars, scatterLayout, sparkBars, sparkWords, type AircraftRow, type AverageFlight, type BarUnit,
  type DirChartLayout, type GroupRow, type HistoryLayout, type ProfitDay, type RouteRow, type StoryChartLayout, type WeeksLayout,
} from "./model";

/** A chart with the old planner's pointer tip: the chart kit's (src/ui/charts, since 30 Oct), which also opens it full
 *  size on a click or tap. */
const ChartWrap = ChartTip;

/** The profit chart: a bar per interval, the zero line, the average. Since 22 Oct also the route page's profit an aircraft
 *  hour by week, in thousands (unit "k"). */
export function BarChart({ pts, avg, figure, unit = "M", empty = "Needs two nights of cash to show a day's profit." }: {
  pts: readonly { x: string; y: number; tip: string }[]; avg: number | null; figure?: string; unit?: BarUnit; empty?: string;
}) {
  if (!pts.length) return <div className="empty">{empty}</div>;
  const g = barLayout(pts, avg, unit);
  return (
    <ChartWrap label={unit === "k" ? "profit an aircraft hour by week" : "profit by day"}>
      <svg className="lchart" viewBox={`0 0 ${g.W} ${g.H}`} role="img" data-figure={figure} data-bars={g.bars.length}>
        {g.grid.map((l, i) => (
          <g key={i}>
            <line x1={g.L} x2={g.W - g.R} y1={l.y.toFixed(1)} y2={l.y.toFixed(1)} className={l.zero ? "zero" : "grid"} />
            <text x={g.L - 6} y={(l.y + 4).toFixed(1)} textAnchor="end">{l.label}</text>
          </g>
        ))}
        {g.bars.map((b, i) => (
          <g key={"b" + i}>
            <rect x={b.x.toFixed(1)} y={b.y.toFixed(1)} width={b.w.toFixed(1)} height={b.h.toFixed(1)} rx="3" className={b.neg ? "bneg" : "bpos"} />
            <rect x={b.hitX.toFixed(1)} y={g.T} width={b.hitW.toFixed(1)} height={g.H - g.T - g.B} className="hitc" data-tip={b.tip} />
            <text x={(b.x + b.w / 2).toFixed(1)} y={g.H - 9} textAnchor="middle">{b.label}</text>
          </g>
        ))}
        {g.avg ? (
          <>
            <line x1={g.L} x2={g.W - g.R} y1={g.avg.y.toFixed(1)} y2={g.avg.y.toFixed(1)} className="avgl" />
            <text x={g.W - g.R} y={(g.avg.y - 5).toFixed(1)} textAnchor="end" className="avgt">{g.avg.text}</text>
          </>
        ) : null}
      </svg>
    </ChartWrap>
  );
}

/** A card's sparkline. */
export function Spark({ days }: { days: readonly ProfitDay[] }) {
  if (!days.length) return null;
  return (
    <svg className="spark" viewBox="0 0 120 30" aria-hidden="true">
      <line x1="0" x2="120" y1="15" y2="15" className="zero" />
      {sparkBars(days).map((b, i) => <rect key={i} x={b.x.toFixed(1)} y={b.y.toFixed(1)} width={b.w.toFixed(1)} height={b.h.toFixed(1)} rx="1.5" className={b.neg ? "bneg" : "bpos"} />)}
    </svg>
  );
}

/** The route profit table's 14-day load sparkline (route_days): a bar a day, under 85% a shade lighter. */
export function LoadSpark({ values }: { values: readonly (number | null)[] }) {
  const bars = loadSparkBars(values);
  return (
    <svg className="lspark" viewBox="0 0 56 16" role="img" aria-label={sparkWords(values)} data-spark-days={bars.length}>
      <title>{sparkWords(values)}</title>
      <line x1="0" x2="56" y1="15.5" y2="15.5" className="zero" />
      {bars.map((b, i) => <rect key={i} x={b.x.toFixed(1)} y={b.y.toFixed(1)} width={b.w.toFixed(1)} height={b.h.toFixed(1)} rx="0.8" className={b.low ? "blow" : "bpos"} />)}
    </svg>
  );
}


/** Load against profit: economy load against profit a flight, bubble size flights a week, colour the mark. Since 22 Oct
 *  the load axis is zoomed to the routes shown, the labels never overlap and the axis title sits inside (scatterLayout).
 *  Since 30 Oct laid out at the width it's shown (the kit's Sized), its text at 11 px, so it's readable on a phone. */
export function Scatter({ routes }: { routes: readonly RouteRow[] }) {
  if (!scatterLayout(routes)) return <div className="dim">No loads matched yet.</div>;
  return (
    <ChartWrap className="chartwrap rpwrap" label="load against profit">
      <Sized fallback={460} min={280}>{(w) => {
        const g = scatterLayout(routes, { W: w, charW: 6.6 });
        if (!g) return null;
        return (
          <svg className="kchart rpscat" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label={`Economy load (${g.x0}% to ${g.x1}%) against profit a flight`}
            data-load-from={g.x0} data-labels={g.labels.length}>
            {g.yTicks.map((t, i) => (
              <g key={i}>
                <line x1={g.pl} x2={g.W - g.pr} y1={t.y} y2={t.y} className="grid" />
                <text x={g.pl - 6} y={t.y + 4} textAnchor="end">{t.label}</text>
              </g>
            ))}
            {g.xTicks.map((t, i) => <text key={"x" + i} x={t.x} y={g.H - g.pb + 16} textAnchor={i === g.xTicks.length - 1 ? "end" : "middle"}>{t.label}</text>)}
            {g.zeroY != null ? <line x1={g.pl} x2={g.W - g.pr} y1={g.zeroY} y2={g.zeroY} stroke="#B4234B" strokeDasharray="3 3" /> : null}
            <text x={g.xTitle.x} y={g.xTitle.y} style={{ textAnchor: "end" }} className="kax">{g.xTitle.text}</text>
            {g.dots.map((d, i) => (
              <circle key={"d" + i} cx={d.x.toFixed(1)} cy={d.y.toFixed(1)} r={d.r.toFixed(1)} fill={d.color} fillOpacity=".55" stroke={d.color} data-tip={d.title} />
            ))}
            {g.labels.map((l, i) => <text key={"l" + i} x={l.x.toFixed(1)} y={l.y.toFixed(1)} style={{ textAnchor: l.anchor }} className="rplab">{l.text}</text>)}
          </svg>
        );
      }}</Sized>
    </ChartWrap>
  );
}

/** An average flight: its profit and margin as a big number, income and where it goes as two bars, and each part with
 *  its amount, in thousands. Since 22 Oct in the page's own type (not a drawing), so it fills the panel beside the
 *  chart at the chart's height, or the width under it on a narrower screen. */
export function CostChart({ avg }: { avg: AverageFlight | null }) {
  const c = costParts(avg);
  if (!c) return <div className="dim">No flights yet.</div>;
  const R = c.income.reduce((a, x) => a + x.k, 0);
  const bar = (label: string, parts: typeof c.income) => (
    <div className="cfrow">
      <span className="cfl">{label}</span>
      <span className="cfbar" role="img" aria-label={`${label}: ${parts.map((p) => `${p.name} ${p.k.toFixed(1)}k`).join(", ")}`}>
        {parts.map((p) => <i key={p.name} style={{ width: `${Math.max(0, p.k / R * 100).toFixed(2)}%`, background: p.color }} title={`${p.name}: ${p.k.toFixed(1)}k`} />)}
      </span>
    </div>
  );
  return (
    <div className="cflight" data-figure="performance: an average flight">
      <div className="cfbig"><b className={c.profitK < 0 ? "neg" : ""}>{c.profitK >= 0 ? "" : "−"}{Math.abs(c.profitK).toFixed(1)}k</b>
        <span>profit a flight · {c.marginPct}% margin</span></div>
      <div className="cfbars">{bar("Income", c.income)}{bar("Costs", c.costs)}</div>
      <ul className="cfkey">
        {[...c.income, ...c.costs].map((p) => <li key={p.name}><i style={{ background: p.color }} />{p.name}<b>{p.k.toFixed(1)}k</b></li>)}
      </ul>
    </div>
  );
}

/** Each aircraft's profit a day after its lease: since 30 Oct the kit's horizontal bars (tailItems), at the width shown. */
export function TailChart({ rows }: { rows: readonly AircraftRow[] }) {
  const items = tailItems(rows);
  return <HBars layout={(W) => hbarLayout(items, { fmt: (v) => `${Math.round(v)}k`, W, L: 84, R: 56, row: 22 })} label="profit a day after lease, by aircraft"
    figure="performance: aircraft chart" />;
}

/** The route page's since-launch chart (spec docs/specs/2026-10-21-route-page.md §3.3): economy and business loads by
 *  day, the fare level as a step line on its own scale (right), each event as a marker on the day axis, a tip for each
 *  day (storyChartLayout() in model.ts). */
export function StoryChart({ g }: { g: StoryChartLayout }) {
  return (
    <ChartWrap label="since launch">
      <svg className="lchart storychart" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label="Loads by day since launch, the fare level and the events"
        data-figure="performance route: since launch" data-days={g.days.length} data-markers={g.markers.length}>
        {g.grid.map((l, i) => (
          <g key={"g" + i}>
            <line x1={g.L} x2={g.W - g.R} y1={l.y.toFixed(1)} y2={l.y.toFixed(1)} className={i === 0 ? "zero" : "grid"} />
            <text x={g.L - 6} y={(l.y + 4).toFixed(1)} textAnchor="end">{l.label}</text>
          </g>
        ))}
        {g.rgrid.map((l, i) => <text key={"r" + i} x={g.W - g.R + 6} y={(l.y + 4).toFixed(1)} className="lvt">{l.label}</text>)}
        {g.level ? <path d={g.level} className="lvl" /> : null}
        {g.levelBus ? <path d={g.levelBus} className="lvl bus" /> : null}
        <path d={g.eco} className="eco" />
        {g.bus ? <path d={g.bus} className="bus" /> : null}
        {g.xLabels.map((l, i) => <text key={"x" + i} x={l.x.toFixed(1)} y={g.H - g.B + 28} textAnchor="middle">{l.label}</text>)}
        {g.markers.map((m, i) => <circle key={"m" + i} cx={m.x.toFixed(1)} cy={m.y.toFixed(1)} r="4.5" className={"mk " + m.kinds} data-tip={m.tip} />)}
        {g.cols.map((c, i) => <rect key={"c" + i} x={c.x.toFixed(1)} y={g.T} width={c.w.toFixed(1)} height={g.H - g.T - g.B} className="hitc" data-tip={c.tip} />)}
      </svg>
      <Legend items={[
        { label: "economy load", color: "var(--ink)" },
        ...(g.bus ? [{ label: "business load", color: "#8C94AD" }] : []),
        ...(g.level ? [{ label: "fare level (right)", color: "#3B3FD8", dashed: true }] : []),
        ...(g.markers.length ? [{ label: "an event", color: "var(--ink)" }] : []),
      ]} />
    </ChartWrap>
  );
}

/** Our share of the pair at each scan since launch, as a small line with a tip on each point. */
export function ShareLine({ s }: { s: { W: number; H: number; path: string; dots: { x: number; y: number; tip: string }[] } }) {
  return (
    <ChartWrap className="chartwrap sharewrap" label="our share at each scan">
      <svg className="shareline" viewBox={`0 0 ${s.W} ${s.H}`} role="img" aria-label="Our share at each scan" data-figure="performance route: share at each scan">
        <line x1="0" x2={s.W} y1={s.H - 4} y2={s.H - 4} className="zero" />
        <path d={s.path} />
        {s.dots.map((d, i) => <circle key={i} cx={d.x.toFixed(1)} cy={d.y.toFixed(1)} r="3" data-tip={d.tip} />)}
      </svg>
    </ChartWrap>
  );
}

/** The group today: one row per airline, flight profit against leases and the week-end closing, net at the end. Since
 *  30 Oct laid out at the width it's shown (groupLayout's W), its text at 11 px. */
export function GroupChart({ rows }: { rows: readonly GroupRow[] }) {
  return (
    <ChartWrap className="chartwrap rpwrap" label="the group today">
      <Sized fallback={900} min={300}>{(w) => {
        const g = groupLayout(rows, w);
        return (
          <svg className="kchart rpgroup" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label="Flight profit against leases, by airline" data-figure="performance: the group today">
            {g.rows.map((x) => (
              <g key={x.r.airline_id} data-group-row={x.r.code ?? x.r.name}>
                <text x="0" y={x.y + 16} className="klab">{fitText(x.r.name, g.x0 - 8)}</text>
                <rect x={g.c} y={x.y + 3} width={x.profitW.toFixed(1)} height="16" rx="3" fill="#1E9E6A" data-tip={x.profitTitle} />
                <rect x={(g.c - x.leaseW).toFixed(1)} y={x.y + 3} width={x.leaseW.toFixed(1)} height="16" rx="3" fill="#E0557A" data-tip={x.leaseTitle} />
                <text x={g.W - 4} y={x.y + 16} style={{ textAnchor: "end", fill: x.neg ? "#B4234B" : "#0A1230", fontWeight: 700 }}>{x.net}</text>
              </g>
            ))}
            <line x1={g.c} x2={g.c} y1="0" y2={g.axisY} stroke="#C3C9D9" />
            <text x={g.c - 6} y={g.labelY} style={{ textAnchor: "end" }} className="kax">← leases and closing</text>
            <text x={g.c + 6} y={g.labelY} className="kax">flight profit →</text>
            <text x={g.W - 4} y={g.netY} style={{ textAnchor: "end" }} className="kax">net a day</text>
          </svg>
        );
      }}</Sized>
    </ChartWrap>
  );
}

/** Load by direction (since 30 Oct, spec docs/specs/2026-10-30-market-pages-planner.md §1): economy load each day, out and
 *  back as two lines, each direction's fare level as a step line on the right axis (dirChartLayout() in model.ts). */
export function DirChart({ g, out, back }: { g: DirChartLayout; out: string; back: string }) {
  return (
    <ChartWrap label="load by direction">
      <svg className="lchart storychart dirchart" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label="Economy load by day, each direction, and each direction's fare level"
        data-figure="performance route: load by direction" data-days={g.days.length}>
        {g.grid.map((l, i) => (
          <g key={"g" + i}>
            <line x1={g.L} x2={g.W - g.R} y1={l.y.toFixed(1)} y2={l.y.toFixed(1)} className={i === 0 ? "zero" : "grid"} />
            <text x={g.L - 6} y={(l.y + 4).toFixed(1)} textAnchor="end">{l.label}</text>
          </g>
        ))}
        {g.rgrid.map((l, i) => <text key={"r" + i} x={g.W - g.R + 6} y={(l.y + 4).toFixed(1)} className="lvt">{l.label}</text>)}
        {g.levelOut ? <path d={g.levelOut} className="lvl" /> : null}
        {g.levelBack ? <path d={g.levelBack} className="lvl back" /> : null}
        <path d={g.out} className="eco" />
        <path d={g.back} className="back" />
        {g.xLabels.map((l, i) => <text key={"x" + i} x={l.x.toFixed(1)} y={g.H - g.B + 28} textAnchor="middle">{l.label}</text>)}
        {g.cols.map((c, i) => <rect key={"c" + i} x={c.x.toFixed(1)} y={g.T} width={c.w.toFixed(1)} height={g.H - g.T - g.B} className="hitc" data-tip={c.tip} />)}
      </svg>
      <Legend items={[
        { label: out, color: "var(--ink)" },
        { label: back, color: "#D9752B" },
        ...(g.levelOut || g.levelBack ? [{ label: "fare level (right)", color: "#3B3FD8", dashed: true }] : []),
      ]} />
    </ChartWrap>
  );
}

/** Rivals over time (since 30 Oct): each airline's direct departures a week at every scan since launch, ours bold. */
export function HistoryChart({ g }: { g: HistoryLayout }) {
  return (
    <ChartWrap label="rivals over time">
      <svg className="lchart histchart" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label="Each airline's departures a week on the pair at each scan"
        data-figure="performance route: rivals over time" data-series={g.series.length}>
        {g.grid.map((l, i) => (
          <g key={"g" + i}>
            <line x1={g.L} x2={g.W - g.R} y1={l.y.toFixed(1)} y2={l.y.toFixed(1)} className={i === 0 ? "zero" : "grid"} />
            <text x={g.L - 6} y={(l.y + 4).toFixed(1)} textAnchor="end">{l.label}</text>
          </g>
        ))}
        {g.xLabels.map((l, i) => <text key={"x" + i} x={l.x.toFixed(1)} y={g.H - g.B + 18} textAnchor="middle">{l.label}</text>)}
        {g.series.map((x, i) => (
          <g key={x.key} className={"hs " + (x.ours ? "ours" : `r${Math.min(i, 6)}`)} data-series={x.key}>
            <path d={x.path} />
            {x.dots.map((d, j) => <circle key={j} cx={d.x.toFixed(1)} cy={d.y.toFixed(1)} r="3" data-tip={d.tip} />)}
          </g>
        ))}
      </svg>
    </ChartWrap>
  );
}

/** The pair's seats offered by calendar week (bars) and price per unit (a line, right axis), since 30 Oct. */
export function WeeksChart({ g }: { g: WeeksLayout }) {
  return (
    <ChartWrap label="seats and price by week">
      <svg className="lchart weekschart" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label="The pair's seats offered and price per unit by week"
        data-figure="performance route: seats and price by week" data-weeks={g.bars.length}>
        {g.grid.map((l, i) => (
          <g key={"g" + i}>
            <line x1={g.L} x2={g.W - g.R} y1={l.y.toFixed(1)} y2={l.y.toFixed(1)} className={i === 0 ? "zero" : "grid"} />
            <text x={g.L - 6} y={(l.y + 4).toFixed(1)} textAnchor="end">{l.label}</text>
          </g>
        ))}
        {g.rgrid.map((l, i) => <text key={"r" + i} x={g.W - g.R + 6} y={(l.y + 4).toFixed(1)} className="lvt">{l.label}</text>)}
        {g.bars.map((b, i) => <rect key={i} x={b.x.toFixed(1)} y={b.y.toFixed(1)} width={b.w.toFixed(1)} height={Math.max(0, b.h).toFixed(1)} rx="2" className="wbar" data-tip={b.tip} />)}
        {g.price ? <path d={g.price} className="wprice" /> : null}
        {g.xLabels.map((l, i) => <text key={"x" + i} x={l.x.toFixed(1)} y={g.H - g.B + 16} textAnchor="middle">{l.label}</text>)}
      </svg>
    </ChartWrap>
  );
}
