// Performance's charts (spec docs/specs/2026-10-30-charts-everywhere.md, part A): what each chart draws, from the
// figures the screen already reads, shaped for the chart kit (src/ui/charts). No figure is worked out anew: the routes'
// profit an aircraft hour and marks are route_profit()'s, the forecast cash_forecast()'s, the moves fare_ladder()'s, the
// fare plan fare_plan_status()'s, the scorecards' days airline_profit()'s and the daily history's, the growth lists
// growth_signals()'s, and the flights of a day the planning library's with their captured loads. Here they're only put in
// order, coloured and given their tips; the unit tests (charts.test.ts) check each layout's figures.
import type { DayFlight } from "@rules";
import { SERIES, TONE, type HBarItem, type HeatRow, type StackRow, type StackSeries, type StepMarker, type StepPoint, type TimelineRow } from "../../ui/charts";
import type { OurAirline } from "../../data/airlines";
import {
  MARKS, chartIntervals, fcDay, fcWhat, ms, sg, DAY_MS,
  type AircraftRow, type DayRow, type Forecast, type LadderRoute, type PlanRow, type ProfitDay, type RouteRow,
} from "./model";
import type { CapturedLoad, GrowthRead, Pattern } from "./reads";

// ---------- Route profit: profit an aircraft hour, a bar a route
/** Thousands of AS$ an hour, signed: "+12.3k". */
export const kHour = (v: number): string => `${v < 0 ? "−" : "+"}${(Math.round(Math.abs(v) * 10000) / 10).toFixed(1)}k`;
/** The bars: each route with its profit an aircraft hour (route_profit()'s, the figure sold-out routes are marked add or
 *  sold out by; raise until 31 Oct), highest first, coloured by its mark; the reference line is the airline's middle route by that figure, as
 *  route_profit() picks it (the middle of every route with hours, sorted); `without` counts the routes with no hours
 *  (no legs on record), which aren't drawn. The mark picked on the board filters the bars, never the middle route. A
 *  sold-out route's tip has the fare ladder's move beside its mark (moveOf, since 31 Oct). */
export function routeHourBars(routes: readonly RouteRow[], mark: string = "", moveOf?: (r: RouteRow) => string): { items: HBarItem[]; ref: { value: number; label: string } | null; without: number } {
  const withH = routes.filter((r) => r.profit_per_aircraft_hour != null);
  const sorted = withH.map((r) => Number(r.profit_per_aircraft_hour)).sort((a, b) => a - b);
  const mid = sorted.length ? sorted[Math.floor(sorted.length / 2)] as number : null;
  const shown = withH.filter((r) => !mark || r.mark === mark).slice()
    .sort((a, b) => Number(b.profit_per_aircraft_hour) - Number(a.profit_per_aircraft_hour) || (a.hub + a.dest).localeCompare(b.hub + b.dest));
  return {
    items: shown.map((r) => ({
      key: `${r.hub}-${r.dest}`, label: `${r.hub}–${r.dest}`, value: Number(r.profit_per_aircraft_hour), color: MARKS[r.mark].color,
      tip: `${r.hub}–${r.dest} · ${kHour(Number(r.profit_per_aircraft_hour))} an aircraft hour · ${MARKS[r.mark].label}${r.mark === "sold_out" && moveOf?.(r) ? ` (the ladder: ${moveOf(r)})` : ""} · ${r.flights} flight${r.flights === 1 ? "" : "s"}, ${kHour(r.profit_per_flight)} a flight`,
    })),
    ref: mid == null ? null : { value: mid, label: `middle route ${kHour(mid)}` },
    without: routes.filter((r) => !mark || r.mark === mark).length - shown.length,
  };
}

// ---------- Cash, next 14 days: a step line
/** The forecast as a step line: cash in hand from the capture, stepping at each point cash_forecast() gives; the
 *  cushion (order_cushion) as a reference line; each lease and week-end closing a dot on the line after it, with its tip;
 *  the lowest point marked. Null when the forecast isn't complete (the board says what's missing). */
export function forecastSteps(fc: Forecast, cushion: number): {
  points: StepPoint[]; markers: StepMarker[]; low: StepPoint | null; t0: number; t1: number; refs: { value: number; label: string; cls?: string }[]; xTicks: { t: number; label: string }[];
} | null {
  if (fc.status !== "ok" || !fc.points?.length || !fc.cash_at) return null;
  const t0 = ms(fc.cash_at), t1 = t0 + 14 * DAY_MS;
  const points = fc.points.map((p) => ({ t: ms(p.at), v: p.balance })).sort((a, b) => a.t - b.t);
  const at = (t: number) => { let v = points[0]?.v ?? 0; for (const p of points) if (p.t <= t) v = p.v; return v; };
  return {
    t0, t1, points,
    refs: [{ value: cushion, label: `cushion ${cushion.toFixed(1)}M`, cls: "cushion" }],
    markers: (fc.payments ?? []).filter((p) => ms(p.at) >= t0 && ms(p.at) <= t1).map((p) => ({
      t: ms(p.at), v: at(ms(p.at)), cls: /Week-end closing/i.test(String(p.what ?? "")) ? "closing" : p.repeat ? "expected" : "lease",
      tip: `${fcDay(p.at)} · ${p.amount.toFixed(2)}M · ${fcWhat(p.what)}${p.repeat ? " (expected, weekly)" : ""} · ${at(ms(p.at)).toFixed(2)}M after it`,
    })),
    low: fc.lowest ? { t: ms(fc.lowest.at), v: fc.lowest.balance } : null,
    xTicks: Array.from({ length: 8 }, (_, i) => t0 + i * 2 * DAY_MS).map((t) => ({ t, label: fcDay(t).replace(/,.*/, "") })),
  };
}

// ---------- the fare ladder's week: a stacked bar per cabin and direction
export type WeekKind = "up" | "hold" | "down" | "jump" | "decide" | "set back";
export const WEEK_SERIES: readonly StackSeries[] = [
  { key: "up", label: "up", color: TONE.ok }, { key: "hold", label: "hold", color: TONE.mute }, { key: "down", label: "down", color: TONE.warn },
  { key: "jump", label: "jump under launch", color: "#E86A92" }, { key: "decide", label: "cut or keep?", color: TONE.bad }, { key: "set back", label: "set back to its level", color: TONE.violet },
];
/** A ladder row's kind this Saturday, one each: a cut-or-keep decision first, then a set-back (off its level), a jump
 *  under launch, else its move. */
export function weekKind(r: Pick<LadderRoute, "move"> & Partial<Pick<LadderRoute, "decide" | "fix" | "ladder_kind">>): WeekKind {
  if (r.decide) return "decide";
  if (r.fix) return "set back";
  if (r.ladder_kind === "jump") return "jump";
  return r.move;
}
/** This Saturday's moves, one stacked bar per cabin and direction (economy out, economy back, business out, business
 *  back: those the ladder has), each segment a kind with its count. */
export function ladderWeek(routes: readonly LadderRoute[]): StackRow[] {
  const keys: [LadderRoute["cabin"], LadderRoute["direction"]][] = [["economy", "out"], ["economy", "back"], ["business", "out"], ["business", "back"]];
  return keys.flatMap(([cabin, dir]) => {
    const rows = routes.filter((r) => r.cabin === cabin && r.direction === dir);
    if (!rows.length) return [];
    const parts: Partial<Record<string, number>> = {};
    for (const r of rows) { const k = weekKind(r); parts[k] = (parts[k] ?? 0) + 1; }
    const label = `${cabin} ${dir}`;
    return [{ key: `${cabin}|${dir}`, label, parts, tip: (s: StackSeries, n: number) => `${label} · ${s.label}: ${n} direction${n === 1 ? "" : "s"}` }];
  });
}

// ---------- the fare plan: a small timeline
/** Each planned change a row: when it was proposed and, once the captures show it, when they saw it. From a day before
 *  the first proposal to a day after today. */
export function planTimeline(plan: readonly PlanRow[], today: string): { rows: TimelineRow[]; t0: number; t1: number; ticks: { t: number; label: string }[]; now: number } {
  const now = Date.parse(today + "T12:00:00Z");
  const days = plan.flatMap((p) => [p.proposed_on, p.seen_on].filter((d): d is string => !!d).map((d) => Date.parse(String(d).slice(0, 10) + "T12:00:00Z")));
  const t0 = Math.min(now, ...days) - DAY_MS, t1 = now + DAY_MS;
  const n = Math.round((t1 - t0) / DAY_MS), every = Math.max(1, Math.ceil(n / 7));
  return {
    t0, t1, now,
    ticks: Array.from({ length: n + 1 }, (_, i) => t0 + i * DAY_MS).filter((_, i) => i % every === 0).map((t) => ({ t, label: fcDay(t).replace(/^\w+, /, "") })),
    rows: plan.map((p) => {
      const label = `${p.hub ?? ""}–${p.dest ?? ""} ${p.cabin_class ?? "economy"}${p.direction ? " " + p.direction : ""}`;
      const what = p.level_pct != null ? `${p.ladder_move ?? "move"} to ${p.level_pct}%` : `${(p.change_pct ?? 0) > 0 ? "+" : ""}${p.change_pct ?? 0}%`;
      const marks = [];
      if (p.proposed_on) marks.push({ t: Date.parse(String(p.proposed_on).slice(0, 10) + "T12:00:00Z"), kind: "planned", tip: `${label} · ${what} · planned ${fcDay(String(p.proposed_on).slice(0, 10) + "T12:00:00Z")}` });
      if (p.seen_on) marks.push({ t: Date.parse(String(p.seen_on).slice(0, 10) + "T12:00:00Z"), kind: "seen", tip: `${label} · seen in the captures ${fcDay(String(p.seen_on).slice(0, 10) + "T12:00:00Z")}` });
      else marks.push({ t: now, kind: "waiting", tip: `${label} · not seen in the captures yet` });
      return { key: String(p.id), label, marks };
    }),
  };
}

// ---------- the group's scorecards: small multiples
export interface Multiple {
  airline_id: number; name: string; color: string | null;
  profit: { values: (number | null)[]; tip: string };
  load: { values: (number | null)[]; tip: string };
  fleet: { values: (number | null)[]; tip: string };
}
/** One panel per airline: profit a day for each of its last 14 reported intervals (airline_profit()'s, as the profit
 *  chart shows them), and its average load and fleet on each of the 14 days to today from the daily history (airline_days). */
export function scoreMultiples(airlines: readonly { airline_id: number; name: string; color: string | null }[], profitOf: ReadonlyMap<number, { days: readonly ProfitDay[] }>,
  days: readonly DayRow[], today: string): Multiple[] {
  const dayList = Array.from({ length: 14 }, (_, i) => new Date(Date.parse(today + "T00:00:00Z") - (13 - i) * DAY_MS).toISOString().slice(0, 10));
  const span = (vals: (number | null)[], fmt: (v: number) => string) => {
    const xs = vals.filter((v): v is number => v != null);
    return xs.length ? `${fmt(xs[0] as number)} → ${fmt(xs[xs.length - 1] as number)}` : "none yet";
  };
  return airlines.map((a) => {
    const iv = chartIntervals(profitOf.get(a.airline_id)?.days ?? []);
    const mine = new Map(days.filter((d) => d.airline_id === a.airline_id).map((d) => [d.day, d]));
    const load = dayList.map((d) => { const v = mine.get(d)?.eco_load_pct; return v == null ? null : Number(v); });
    const fleet = dayList.map((d) => { const v = mine.get(d)?.aircraft_total; return v == null ? null : Number(v); });
    return {
      airline_id: a.airline_id, name: a.name, color: a.color,
      profit: { values: iv.map((x) => x.profit_day), tip: `${a.name}: profit a day, last ${iv.length} reports · ${span(iv.map((x) => x.profit_day), (v) => sg(v))}` },
      load: { values: load, tip: `${a.name}: average load, 14 days · ${span(load, (v) => `${Math.round(v)}%`)}` },
      fleet: { values: fleet, tip: `${a.name}: fleet, 14 days · ${span(fleet, (v) => String(v))}` },
    };
  });
}

// ---------- growth signals: a stacked bar per airline
export const GROWTH_SERIES: readonly StackSeries[] = [
  { key: "ready", label: "ready for another flight", color: TONE.ok }, { key: "sold_out", label: "sold out · fares climbing", color: "#3B3FD8" },
  { key: "fix", label: "fix or reduce", color: TONE.warn }, { key: "losing", label: "aircraft losing after lease", color: TONE.bad },
];
/** Each airline's growth signals by kind: from the capture (growth_signals()'s four lists), or without profit captured,
 *  ready from the load reports (the ready rows given) and fix or reduce from the load patterns marked cut. The segment's
 *  key is the list it opens. */
export function growthStack(s: GrowthRead, airlines: readonly Pick<OurAirline, "id" | "name">[], readyFromLoads: readonly { route: { airline_id: number } }[] = []): StackRow[] {
  const count = (xs: readonly { airline_id: number }[], id: number) => xs.filter((x) => x.airline_id === id).length;
  const cut = s.load_patterns.filter((p: Pattern) => p.mark === "cut");
  return airlines.map((a) => ({
    key: String(a.id), label: a.name,
    parts: s.profit_captured
      ? { ready: count(s.ready_for_another_flight, a.id), sold_out: count(s.sold_out, a.id), fix: count(s.fix_or_reduce, a.id), losing: count(s.aircraft_losing_after_lease, a.id) }
      : { ready: readyFromLoads.filter((r) => r.route.airline_id === a.id).length, fix: count(cut, a.id) },
    tip: (x: StackSeries, n: number) => `${a.name} · ${x.label}: ${n} · tap to open the list`,
  }));
}
/** The list a segment opens (Growth.tsx's data-list). */
export function growthList(series: string, profitCaptured: boolean): string {
  if (!profitCaptured) return series === "fix" ? "reduce" : "ready";
  return series;
}

// ---------- Flights by day: a heat strip by hour and airline
const plus = (v: number | null | undefined): number => Number(v ?? 0);
/** Each airline's departures of the day by the hour they leave (local time at the origin, as the list shows them):
 *  each hour's average economy load over the flights captured, grey for flights none of which was captured, nothing
 *  for an hour with no flight. */
export function flightsHeat(flights: readonly DayFlight[], loadOf: (f: DayFlight) => CapturedLoad | undefined, airlines: readonly Pick<OurAirline, "id" | "name" | "code">[]): { rows: HeatRow[]; cols: string[] } {
  const cols = Array.from({ length: 24 }, (_, h) => String(h).padStart(2, "0"));
  const rows = airlines.flatMap((a) => {
    const mine = flights.filter((f) => f.airline_id === a.id);
    if (!mine.length) return [];
    return [{
      key: String(a.id), label: a.code ?? a.name,
      cells: cols.map((hh) => {
        const at = mine.filter((f) => f.dep.slice(0, 2) === hh);
        if (!at.length) return null;
        const caps = at.map(loadOf).filter((x): x is CapturedLoad => !!x);
        const v = caps.length ? Math.round(caps.reduce((t, c) => t + plus(c.eco), 0) / caps.length * 10) / 10 : null;
        return { value: v, tip: `${a.name} · ${hh}:00–${hh}:59 local · ${at.length} departure${at.length === 1 ? "" : "s"} (${at.map((f) => f.no).join(", ")})`
          + (v == null ? " · not captured" : ` · economy ${Math.round(v)}% over ${caps.length} captured`) };
      }),
    }];
  });
  return { rows, cols };
}

/** A colour for an airline, its own or one from the kit's run. */
export const colorFor = (color: string | null | undefined, i: number): string => color || (SERIES[i % SERIES.length] as string);

/** Aircraft (since 30 Oct drawn with the kit, as the old rpTailChart's figures): each aircraft's profit a day after its
 *  lease (before, without one), in thousands, green or red. */
export function tailItems(rows: readonly AircraftRow[]): HBarItem[] {
  return rows.map((t) => {
    const k = (t.net_day != null ? t.net_day : t.flight_profit_day) * 1000;
    return { key: t.registration, label: t.registration, value: k, color: k >= 0 ? "#1E9E6A" : "#B4234B",
      text: (k >= 0 ? "+" : "−") + Math.abs(Math.round(k)) + "k", tip: `${t.registration}: ${Math.round(k)}k a day${t.net_day != null ? " after lease" : ""}` };
  });
}
