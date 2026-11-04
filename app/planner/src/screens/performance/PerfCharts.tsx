// Performance's charts (spec docs/specs/2026-10-30-charts-everywhere.md, part A), drawn with the chart kit
// (src/ui/charts) from charts.ts's shapes: Route profit's profit an aircraft hour, Cash's step line, the fare ladder's
// week, the fare plan's timeline, the group's small multiples, the growth signals by airline and Flights by day's heat
// strip. Each has its title, note, legend, tips and an empty state in words; the tables they stand in front of stay one
// tap away (ChartOrTable, in Performance.tsx and FlightsByDay.tsx).
import type { DayFlight } from "@rules";
import type { OurAirline } from "../../data/airlines";
import { AirlineMark } from "../../ui/AirlineMark";
import {
  ChartFrame, ChartTip, HBars, HeatStrip, Sized, Spark, StackedBars, StepLine, Timeline, hbarLayout, heatLayout, sparkLayout, stackLayout, stepLayout, timelineLayout,
} from "../../ui/charts";
import {
  GROWTH_SERIES, WEEK_SERIES, fareDotLayout, fareResultDots, flightsHeat, forecastSteps, growthList, growthStack, kHour, ladderWeek, planTimeline, routeHourBars, scoreMultiples, type Multiple,
} from "./charts";
import { MARKS, MARK_ORDER, sg, type DayRow, type FareResultRow, type Forecast, type LadderRoute, type PlanRow, type ProfitDay, type RouteRow } from "./model";
import type { CapturedLoad, GrowthRead } from "./reads";

/** Route profit: each route's profit an aircraft hour as a bar, coloured by its mark, the middle route as a line. */
export function RouteHourChart({ routes, mark, moveOf }: { routes: readonly RouteRow[]; mark: string; moveOf?: (r: RouteRow) => string }) {
  const b = routeHourBars(routes, mark, moveOf);
  const marks = MARK_ORDER.filter((m) => b.items.some((x) => x.color === MARKS[m].color));
  return (
    <ChartFrame title="Profit an aircraft hour" note={`each route, highest first, coloured by its signal · the line is the airline's middle route${b.without ? ` · ${b.without} route${b.without === 1 ? "" : "s"} with no aircraft hours not drawn` : ""}`}
      legend={marks.map((m) => ({ label: MARKS[m].label, color: MARKS[m].color }))} figure="performance: route profit chart"
      empty={b.items.length ? null : "No route has aircraft hours in the period yet: show as table for each route's figures."}>
      <HBars layout={(W) => hbarLayout(b.items, { fmt: kHour, ref: b.ref, row: 20, W })} figure="performance: profit an aircraft hour" label="profit an aircraft hour" />
    </ChartFrame>
  );
}

/** Cash, next 14 days: the forecast as a step line, the cushion, each payment and the lowest point. */
export function CashSteps({ fc, cushion }: { fc: Forecast; cushion: number }) {
  const x = forecastSteps(fc, cushion);
  const layout = (W: number, H?: number) => (x ? stepLayout(x.points, { t0: x.t0, t1: x.t1, fmt: (v) => `${v.toFixed(1)}M`, refs: x.refs, markers: x.markers, low: x.low, xTicks: x.xTicks, W, H }) : null);
  return (
    <ChartFrame title="Cash in hand" note="each step a payment · the dashed line is the cushion an order must leave" figure="performance: cash step line"
      legend={[{ label: "cash", color: "#0E1630" }, { label: "cushion", color: "#B4234B", dashed: true }, { label: "lease", color: "#4B3BA8" }, { label: "week-end closing", color: "#E39B21" }]}
      empty={x && x.points.length ? null : "No forecast points yet."}>
      <StepLine layout={layout} label="cash for the next 14 days" figure="performance: cash forecast" />
    </ChartFrame>
  );
}

/** The fare ladder's week: a stacked bar per cabin and direction of this Saturday's moves. */
export function LadderWeek({ routes }: { routes: readonly LadderRoute[] }) {
  const rows = ladderWeek(routes);
  const used = WEEK_SERIES.filter((s) => rows.some((r) => (r.parts[s.key] ?? 0) > 0));
  return (
    <ChartFrame title="This Saturday's moves" note="each cabin and direction, a bar of its routes by move" legend={used.map((s) => ({ label: s.label, color: s.color }))}
      figure="performance: fare ladder week" empty={rows.length ? null : "No route on the fare ladder yet."}>
      <StackedBars layout={(W) => stackLayout(rows, WEEK_SERIES, { L: 120, W })} figure="performance: the week's moves" label="this Saturday's moves" />
    </ChartFrame>
  );
}

/** The fare plan as a timeline: when each change was planned and when the captures saw it. */
export function PlanTimeline({ plan, today }: { plan: readonly PlanRow[]; today: string }) {
  const t = planTimeline(plan, today);
  return (
    <ChartFrame title="Planned and seen" note="each change on the fare plan: when it was planned, and when the captures saw it in the game"
      legend={[{ label: "planned", color: "#4B3BA8" }, { label: "seen in the game", color: "#1A7F55" }, { label: "not seen yet", color: "#E39B21" }]} figure="performance: fare plan timeline">
      <Timeline layout={(W) => timelineLayout(t.rows, { t0: t.t0, t1: t.t1, ticks: t.ticks, now: t.now, L: 170, W })} figure="performance: fare plan chart" label="fare plan, planned and seen" />
    </ChartFrame>
  );
}

/** The group's scorecards as small multiples: each airline's profit a day, average load and fleet over 14 days. */
export function Multiples({ airlines, profitOf, days, today }: {
  airlines: readonly { airline_id: number; name: string; color: string | null }[]; profitOf: ReadonlyMap<number, { days: readonly ProfitDay[] }>; days: readonly DayRow[]; today: string;
}) {
  const ms = scoreMultiples(airlines, profitOf, days, today);
  const panel = (m: Multiple) => (
    <div className="kmult" key={m.airline_id} data-multiple={m.name}>
      <div className="kmh"><AirlineMark color={m.color} /><b>{m.name}</b></div>
      <div className="kmr"><span className="dim">Profit a day</span><Spark g={sparkLayout(m.profit.values, "bar")} tip={m.profit.tip} label={m.profit.tip} />
        <b>{last(m.profit.values, sg)}</b></div>
      <div className="kmr"><span className="dim">Average load</span><Spark g={sparkLayout(m.load.values, "line", { lo: 0, hi: 100 })} tip={m.load.tip} label={m.load.tip} />
        <b>{last(m.load.values, (v) => `${Math.round(v)}%`)}</b></div>
      <div className="kmr"><span className="dim">Fleet</span><Spark g={sparkLayout(m.fleet.values, "line")} tip={m.fleet.tip} label={m.fleet.tip} />
        <b>{last(m.fleet.values, String)}</b></div>
    </div>
  );
  return (
    <ChartFrame title="The last 14 days" note="each airline: profit a day by report, average load and fleet by day, from the daily history" figure="performance: small multiples"
      empty={ms.length ? null : "No airline with figures yet."}>
      <ChartTip className="chartwrap kmultw" label="last 14 days, each airline"><div className="kmults">{ms.map(panel)}</div></ChartTip>
    </ChartFrame>
  );
}
const last = (vs: readonly (number | null)[], fmt: (v: number) => string): string => {
  const v = [...vs].reverse().find((x): x is number => x != null);
  return v == null ? "—" : fmt(v);
};

/** Growth signals by airline: a stacked bar each, each segment opening its list below. */
export function GrowthStack({ s, airlines, ready }: { s: GrowthRead; airlines: readonly OurAirline[]; ready: readonly { route: { airline_id: number } }[] }) {
  const rows = growthStack(s, airlines, ready);
  const series = s.profit_captured ? GROWTH_SERIES : GROWTH_SERIES.filter((x) => x.key === "ready" || x.key === "fix");
  const open = (_row: string, key: string) => {
    const el = document.querySelector(`[data-figure="performance: growth lists"] [data-list="${growthList(key, s.profit_captured)}"]`)
      ?? document.querySelector(`[data-figure="performance: growth lists"] [data-list^="${growthList(key, s.profit_captured)}"]`);
    if (el) {
      el.closest("details")?.setAttribute("open", "");
      el.scrollIntoView({ block: "center", behavior: "smooth" });
    }
  };
  const any = rows.some((r) => Object.values(r.parts).some((v) => (v ?? 0) > 0));
  return (
    <ChartFrame title="By airline" note="each airline's signals by kind · tap a segment for its list" legend={series.map((x) => ({ label: x.label, color: x.color }))}
      figure="performance: growth chart" empty={any ? null : "No growth signal yet."}>
      <StackedBars layout={(W) => stackLayout(rows, series, { W })} figure="performance: growth by airline" onPick={open} label="growth signals by airline" />
    </ChartFrame>
  );
}

/** Flights by day as a heat strip: each airline's departures by local hour, coloured by their average economy load. */
export function FlightsHeat({ flights, loadOf, airlines }: { flights: readonly DayFlight[]; loadOf: (f: DayFlight) => CapturedLoad | undefined; airlines: readonly OurAirline[] }) {
  const h = flightsHeat(flights, loadOf, airlines);
  return (
    <ChartFrame title="Loads by hour" note="each airline's departures by local hour, coloured by their average economy load"
      legend={[{ label: "95%+", color: "#1E9E6A" }, { label: "85–94%", color: "#E3B341" }, { label: "70–84%", color: "#E3812B" }, { label: "under 70%", color: "#B4234B" }, { label: "not captured", color: "#D9DDE7" }]}
      figure="performance: flights heat" empty={h.rows.length ? null : "No flights scheduled that day."}>
      <HeatStrip layout={(W) => heatLayout(h.rows, h.cols, { L: 44, every: W < 520 ? 6 : 3, W })} figure="performance: loads by hour" label="loads by hour" />
    </ChartFrame>
  );
}

/** Fare results (since 3 Nov; spec docs/specs/2026-11-03-fare-results.md §2): a dot per repriced direction, its economy
 *  level now across and its profit a flight change up, the rest of the airline's change as a line. A dot opens its route
 *  page (onPick). */
export function FareResultsChart({ rows, baselinePct, onPick }: { rows: readonly FareResultRow[]; baselinePct: number | null; onPick: (hub: string, dest: string) => void }) {
  const dots = fareResultDots(rows);
  const cut = dots.filter((d) => d.cut).length;
  return (
    <ChartFrame title="Level against profit" note={`each repriced direction: its economy level now across, its profit a flight against the week before its first change up · the line is the airline's other directions over the same days · tap a dot for its route${cut ? ` · ${cut} beyond ±100% drawn at the edge` : ""}`}
      legend={[{ label: "repriced", color: "#4B3BA8" }, { label: "load fell", color: "#E39B21" }, { label: "too soon", color: "#9AA4C4" }, { label: "the rest", color: "#5B647E", dashed: true }]}
      figure="performance: fare results chart" empty={dots.length ? null : "No direction to draw yet: each needs a level and a week either side of its first change."}>
      <ChartTip label="economy level against profit a flight change">
        <Sized>{(w) => {
          const g = fareDotLayout(dots, baselinePct, { W: w });
          return (
            <svg className="kchart kscatter frdots" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label="economy level against profit a flight change" data-figure="performance: fare results dots" data-points={g.dots.length}>
              {g.yTicks.map((t, i) => <g key={i}><line x1={g.L} x2={g.W - g.R} y1={t.y} y2={t.y} className="grid" /><text x={g.L - 6} y={t.y + 4} textAnchor="end">{t.label}</text></g>)}
              {g.xTicks.map((t, i) => <text key={i} x={t.x} y={g.H - g.B + 16} textAnchor="middle">{t.label}</text>)}
              <line x1={g.L} x2={g.W - g.R} y1={g.zeroY} y2={g.zeroY} className="zero" />
              {g.ref ? <g data-fare-rest><line x1={g.L} x2={g.W - g.R} y1={g.ref.y} y2={g.ref.y} className="frrest" /><text x={g.W - g.R} y={g.ref.y - 4} style={{ textAnchor: "end" }} className="kax">{g.ref.label}</text></g> : null}
              <text x={g.W - g.R} y={g.H - 2} style={{ textAnchor: "end" }} className="kax">economy level now</text>
              <text x={4} y={10} className="kax">profit a flight</text>
              {g.dots.map((d) => <circle key={d.key} cx={d.cx} cy={d.cy} r={5} fill={d.color} className="kpick" data-tip={d.tip} data-fare-dot={d.key}
                onClick={() => onPick(d.hub, d.dest)} />)}
            </svg>
          );
        }}</Sized>
      </ChartTip>
    </ChartFrame>
  );
}
