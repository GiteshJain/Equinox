// Performance's logic (spec docs/specs/2026-10-20-today-performance-systems.md; Review's until 20 Oct, decision #18, build
// pull request 10, spec docs/specs/2026-10-14-review.md), kept apart from its screen so the unit tests can run it. Every
// money figure comes from the database's figures (design §8: airline_cards(), airline_profit(), cash_forecast(),
// route_profit(), aircraft_profit(), fare_changes(), fare_plan_status()); what is here only words them as the old Review
// does (web/planner/index.html: renderFinance, groupOverviewHtml, finStats' card, barChart, spark, fcNext,
// forecastBoard, routeProfitBoard, farePlanBoard and reviewClick), lays out its charts, builds the fare plan's rows exactly
// as the old planner writes them, and sets each scorecard's figures against the same day last week from the daily
// history (airline_days). Manual entry's logic moved to Systems (screens/systems/model.ts) with its board. Since 22 Oct
// (spec docs/specs/2026-10-21-route-page.md §3) the route page's too: route_story()'s answer worded, its charts laid out,
// and the connections at both ends from the planning library.
import { block, connections, time, type Rules, type TimedLeg } from "@rules";
import type { Change } from "../../data/save";
import { shortType } from "../../ui/aircraftNames";

// ---------- the database's answers
export interface NextOrder { when: "needs" | "now" | "later" | "not within 14 days"; missing?: string; types?: string[]; type?: string; safe_from?: string; up_to?: number | string | null }
export interface Card {
  airline_id: number;
  code: string | null;
  name: string;
  profit_day: number | null;
  span_days: number | null;
  early: boolean | null;
  per_aircraft_day: number | null;
  return_on_fleet_pct_week: number | null;
  payback_days: number | null;
  funds_aircraft_every_days: number | null;
  fleet: number;
  fleet_added_this_week: number;
  on_order: number;
  flights_day: number;
  flights_added_this_week: number;
  load_7_days: number | null;
  next_order: NextOrder | null;
  can_order_now: string[] | null;
}
export interface GroupRow {
  airline_id: number;
  code: string | null;
  name: string;
  cash: number | null;
  flight_profit_day: number | null;
  leases_day: number;
  closing_day: number;
  leases_and_closing_day: number;
  net_day: number | null;
}
export interface CardsAnswer { airlines: Card[]; group_today: GroupRow[]; group_today_shown: boolean }
export interface ProfitDay {
  date: string;
  cash: number;
  change: number;
  order_payments: number;
  days: number;
  profit_day: number;
  aircraft: number;
  flights: number;
  load: number | null;
  per_aircraft_day: number | null;
}
export interface ProfitAnswer { airline_id: number; profit_day: number | null; span_days: number | null; early: boolean | null; days: ProfitDay[] }
export interface Payment { at: string; amount: number; what: string | null; repeat: boolean }
export interface ForecastType {
  aircraft_type_id: number;
  type: string;
  price_with_cabin: number;
  lease_week: number;
  lease_seen: boolean;
  safe_day: number | null;
  safe_from: string | null;
  count_today: number | null;
}
export interface Forecast {
  status: "ok" | "missing" | "no capture";
  missing?: string;
  cash?: number;
  cash_at?: string;
  profit_per_flight?: number;
  flights_per_day?: number;
  flight_profit_day?: number;
  cushion?: number;
  payments?: Payment[];
  payments_next_7_days?: number;
  points?: { at: string; balance: number }[];
  lowest?: { at: string; balance: number; payment: Payment | null };
  types?: ForecastType[];
}
export type Mark = "add" | "raise" | "fix" | "losing" | "hold";
export interface RouteRow {
  route_id: number | null;
  hub: string;
  dest: string;
  flights: number;
  margin: number | null;
  profit_per_flight: number;
  flights_week: number;
  profit_week: number;
  economy: number | null;
  business: number | null;
  cargo: number | null;
  economy_fare: number | null;
  sold_out: number;
  with_loads: number;
  mark: Mark;
  why: string;
}
export interface AverageFlight {
  passengers: number; cargo: number; fuel: number; handling: number; onboard: number; landing: number; air_traffic: number; maintenance: number;
  income: number; costs: number; profit: number; margin: number | null;
}
export interface RouteProfitAnswer { days: number; flights: number; matched: number; mixed: number; average_flight: AverageFlight | null; routes: RouteRow[] }
export interface AircraftRow { registration: string; type: string; flights: number; flight_profit_day: number; lease_day: number | null; net_day: number | null; routes: string[] }
export interface FareChange { origin: string; dest: string; date: string; fare_before: number; fare_after: number; economy_before: number | null; economy_after: number | null }
export interface PlanRow {
  id: number;
  legacy_key: string | null;
  route_id: number | null;
  hub: string | null;
  dest: string | null;
  cabin_class: string | null;
  change_pct: number | null;
  fare_from: number | null;
  proposed_on: string | null;
  status: string;
  reason: string | null;
  updated_at: string;
  fare_now: number | null;
  target: number | null;
  applied: boolean;
  seen_on: string | null;
  economy_before: number | null;
  economy_after: number | null;
  /** The fare ladder's rows (since 21 Oct): the level they set, % of the default price, and the move. */
  level_pct?: number | null;
  ladder_move?: string | null;
}
export interface FarePlanAnswer { plan: PlanRow[]; fares: { route_id: number; hub: string; dest: string; day: string; fare: number }[] }

// ---------- words, as the old Review writes its figures (renderFinance's sg, kk and dd; forecastBoard's fcDay and fcWhat)
/** A signed money figure in millions: "+1.23M", "−0.40M". */
export const sg = (v: number, d = 2): string => (v >= 0 ? "+" : "−") + Math.abs(v).toFixed(d) + "M";
/** A signed figure in thousands: "+120k", "−8k". */
export const kk = (v: number): string => (v >= 0 ? "+" : "−") + Math.round(Math.abs(v) * 1000) + "k";
/** Days as a card says them: "—", "under a day", "1 day", "12 days". */
export const dd = (n: number | null | undefined): string => (n == null ? "—" : n < 1 ? "under a day" : Math.round(n) + " day" + (Math.round(n) === 1 ? "" : "s"));
/** A whole percent, or "—". */
export const pc = (v: number | null | undefined): string => (v == null ? "—" : Math.round(v) + "%");
/** A moment as the forecast names its day, in UTC: "Wed, Oct 15". */
export const fcDay = (t: number | string): string =>
  new Date(typeof t === "string" ? Date.parse(t) : t).toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", timeZone: "UTC" });
/** What a payment is: the week-end closing, the lease for a registration, or a payment. */
export function fcWhat(s: string | null | undefined): string {
  const t = String(s ?? "");
  if (/Week-end closing/i.test(t)) return "the week-end closing";
  const m = /Leasing payment for ([A-Z0-9-]+)/i.exec(t);
  return m ? "the lease for " + m[1] : "a payment";
}
export const ms = (iso: string): number => Date.parse(iso);

// ---------- an airline's card (the old renderFinance's card and fcNext)
export interface CardWords {
  big: string;
  bigNeg: boolean;
  sub: string;
  perAircraft: string;
  returnOnFleet: string;
  payback: string;
  fundsEvery: string;
  fleet: string;
  fleetAdded: string;
  onOrder: string;
  flights: string;
  flightsAdded: string;
  load: string;
  next: { text: string; kind: "dim" | "pill" | "plain" };
}

/** The card's "Next order": what's missing, else (since 26 Oct, Gitesh) how much it can spend on an order now, the cash
 *  forecast's up_to: a pill when that buys an aircraft, plain when it doesn't yet. Before up_to: the types, or the first
 *  safe day. */
export function nextOrderWords(n: NextOrder | null | undefined): CardWords["next"] {
  if (!n || n.when === "needs") return { text: `needs ${n?.missing || "a capture"}`, kind: "dim" };
  if (n.up_to != null && Number.isFinite(Number(n.up_to))) return { text: `up to ${Number(n.up_to).toFixed(2)}M`, kind: n.when === "now" ? "pill" : "plain" };
  if (n.when === "now") return { text: `can order ${(n.types ?? []).slice(0, 2).map(shortType).join(" or ")}`, kind: "pill" };
  if (n.when === "later" && n.type && n.safe_from) return { text: `${shortType(n.type)} safe from ${fcDay(n.safe_from)}`, kind: "plain" };
  return { text: "not in the next 14 days", kind: "dim" };
}

/** Every line of a card in the old words, and why there's no figure where there's none yet. */
export function cardWords(c: Card): CardWords {
  const p = c.profit_day, rof = c.return_on_fleet_pct_week;
  const span = c.span_days ?? 0;
  return {
    big: p == null ? "—" : sg(p),
    bigNeg: p != null && p < 0,
    sub: p == null ? "needs two nights of cash" : `profit, ${c.early ? "early read over " + span + " day" + (span === 1 ? "" : "s") : "last 7 days"}`,
    perAircraft: c.per_aircraft_day == null ? "—" : kk(c.per_aircraft_day) + " a day",
    returnOnFleet: rof == null ? "—" : (rof >= 0 ? "" : "−") + Math.abs(rof).toFixed(1) + "% a week",
    payback: dd(c.payback_days),
    fundsEvery: dd(c.funds_aircraft_every_days),
    fleet: `${c.fleet} flying`,
    fleetAdded: c.fleet_added_this_week ? `+${c.fleet_added_this_week} this week` : "",
    onOrder: c.on_order ? ` · ${c.on_order} on order` : "",
    flights: String(c.flights_day),
    flightsAdded: c.flights_added_this_week ? `+${c.flights_added_this_week} this week` : "",
    load: c.load_7_days == null ? "—" : "≈" + Math.round(c.load_7_days) + "%",
    next: nextOrderWords(c.next_order),
  };
}

// ---------- the profit chart (barChart): the last 14 intervals between reported days, with the 7-day average
export const CHART_INTERVALS = 14;
/** The intervals the profit chart shows: the last CHART_INTERVALS of them, oldest first. */
export function chartIntervals<T>(days: readonly T[]): T[] {
  return days.slice(-CHART_INTERVALS);
}
/** A bar's tooltip, as the old barChart's points: the day, its profit a day, over how many days, and order payments. */
export function barTip(d: ProfitDay, nice: (day: string) => string): string {
  return `${nice(d.date)} · ${sg(d.profit_day)} a day${d.days > 1 ? " over " + d.days + " days" : ""}${d.order_payments ? " · includes " + d.order_payments.toFixed(2) + "M of order payments" : ""}`;
}

/** A nice step for an axis: 1, 2, 2.5, 5 or 10 times a power of ten, at least r. */
function niceStep(r: number): number {
  const m = Math.pow(10, Math.floor(Math.log10(r)));
  return [1, 2, 2.5, 5, 10].map((k) => k * m).find((k) => k >= r) ?? 10 * m;
}

export interface BarLayout {
  W: number; H: number; L: number; R: number; T: number; B: number;
  grid: { y: number; v: number; zero: boolean; label: string }[];
  bars: { x: number; y: number; w: number; h: number; neg: boolean; hitX: number; hitW: number; label: string; tip: string }[];
  avg: { y: number; text: string } | null;
}
/** A bar chart's figure: millions ("0.25M", the profit chart's) or, since 22 Oct, thousands ("12k", the route page's
 *  profit per aircraft hour). */
export type BarUnit = "M" | "k";
const barLabel = (v: number, unit: BarUnit): string => (unit === "k" ? `${Math.round(v * 1000)}k` : `${+v.toFixed(2)}M`);
const barAvg = (v: number, unit: BarUnit): string => (unit === "k"
  ? `average ${v >= 0 ? "+" : "−"}${Math.round(Math.abs(v) * 1000)}k`
  : `average ${v >= 0 ? "+" : "−"}${Math.abs(v).toFixed(2)}M a day`);

/** The old barChart's layout: 1120 × 260, a bar per interval, the zero line, gridlines at a nice step, the average. */
export function barLayout(pts: readonly { x: string; y: number; tip: string }[], avg: number | null, unit: BarUnit = "M"): BarLayout {
  const W = 1120, H = 260, L = 58, R = 16, T = 16, B = 30;
  const ys = pts.map((p) => p.y);
  let lo = Math.min(0, ...ys), hi = Math.max(0, ...ys);
  if (hi === lo) hi = lo + 0.1;
  const pad = (hi - lo) * 0.1;
  hi += pad;
  lo -= lo < 0 ? pad : 0;
  const step = niceStep((hi - lo) / 4);
  lo = Math.floor(lo / step) * step;
  hi = Math.ceil(hi / step) * step;
  const bw = Math.min(46, (W - L - R) / Math.max(1, pts.length) * 0.62);
  const X = (i: number) => L + (i + 0.5) * (W - L - R) / pts.length, Y = (v: number) => T + (hi - v) / (hi - lo) * (H - T - B);
  const grid: BarLayout["grid"] = [];
  for (let v = lo; v <= hi + 1e-9; v += step) grid.push({ y: Y(v), v, zero: Math.abs(v) < 1e-9, label: barLabel(v, unit) });
  const bars = pts.map((p, i) => {
    const y0 = Y(0), y1 = Y(p.y);
    return { x: X(i) - bw / 2, y: Math.min(y0, y1), w: bw, h: Math.max(1, Math.abs(y1 - y0)), neg: p.y < 0, hitX: X(i) - bw / 2 - 4, hitW: bw + 8,
      label: `${p.x.slice(8)}/${p.x.slice(5, 7)}`, tip: p.tip };
  });
  return { W, H, L, R, T, B, grid, bars, avg: avg == null ? null : { y: Y(avg), text: barAvg(avg, unit) } };
}

/** The card's sparkline (spark): one small bar per interval, scaled to the largest, above or below the middle. */
export function sparkBars(days: readonly ProfitDay[]): { x: number; y: number; w: number; h: number; neg: boolean }[] {
  if (!days.length) return [];
  const W = 120, H = 30;
  const m = Math.max(0.01, ...days.map((d) => Math.abs(d.profit_day)));
  const bw = Math.min(14, W / days.length * 0.7);
  return days.map((d, i) => {
    const cx = (i + 0.5) * W / days.length, h = Math.abs(d.profit_day) / m * (H / 2 - 2);
    return { x: cx - bw / 2, y: d.profit_day >= 0 ? H / 2 - h : H / 2, w: bw, h: Math.max(1, h), neg: d.profit_day < 0 };
  });
}

// ---------- the cash forecast (forecastBoard)
export const DAY_MS = 86_400_000;
export interface ForecastLayout {
  W: number; H: number; pad: number;
  days: { x: number; label: string | null }[];
  cushionY: number; zeroY: number | null; path: string;
  pays: { x: number; y2: number; repeat: boolean; title: string }[];
  low: { x: number; y: number; bad: boolean; textX: number; text: string };
  start: { x: number; y: number; text: string };
}
/** The old forecast chart's layout: 900 × 190, the 14 days, the cushion, the balance, each payment and the lowest point. */
export function forecastLayout(fc: Forecast, cushion: number): ForecastLayout | null {
  if (fc.status !== "ok" || !fc.points?.length || !fc.cash_at || !fc.lowest) return null;
  const t0 = ms(fc.cash_at), W = 900, H = 190, pad = 34, t1 = t0 + 14 * DAY_MS;
  const pts = fc.points.map((p) => ({ t: ms(p.at), v: p.balance }));
  const vs = pts.map((p) => p.v), lo = Math.min(0, ...vs, cushion), hi = Math.max(...vs) * 1.08 + 0.01;
  const X = (t: number) => pad + (t - t0) / (t1 - t0) * (W - pad * 2), Y = (v: number) => H - 22 - (v - lo) / (hi - lo) * (H - 44);
  let path = "";
  pts.forEach((p, i) => { path += (i ? " L" : "M") + X(p.t).toFixed(1) + "," + Y(p.v).toFixed(1); });
  const low = { t: ms(fc.lowest.at), v: fc.lowest.balance };
  return {
    W, H, pad,
    days: Array.from({ length: 15 }, (_, i) => t0 + i * DAY_MS).map((t, i) => ({ x: X(t), label: i % 2 === 0 ? fcDay(t).replace(/,.*/, "") : null })),
    cushionY: Y(cushion), zeroY: lo < 0 ? Y(0) : null, path,
    pays: (fc.payments ?? []).map((p) => ({ x: X(ms(p.at)), y2: H - 28 - Math.min(14, p.amount * 12), repeat: p.repeat,
      title: `${fcDay(p.at)} · ${p.amount.toFixed(2)}M · ${fcWhat(p.what)}${p.repeat ? " (expected, weekly)" : ""}` })),
    low: { x: X(low.t), y: Y(low.v), bad: low.v < cushion, textX: Math.min(W - pad - 60, X(low.t) + 8), text: `low ${low.v.toFixed(2)}M` },
    start: { x: X(t0) + 4, y: Y(fc.cash ?? 0) - 7, text: `${(fc.cash ?? 0).toFixed(2)}M` },
  };
}
/** "Safe to order": each type with its price (cabin included), its lease, and when; in the database's order (by type). */
export function safeWords(t: ForecastType): { kind: "ok" | "mute" | "warn"; text: string } {
  const d = t.safe_day, n = t.count_today ?? 1;
  const when = d === 0 ? "now" + (n > 1 ? `, up to ${n}${n >= 9 ? "+" : ""}` : "") : d != null && t.safe_from ? "from " + fcDay(t.safe_from) : "not within 14 days";
  return {
    kind: d === 0 ? "ok" : d != null ? "mute" : "warn",
    text: `${shortType(t.type)} (${t.price_with_cabin.toFixed(2)}M with cabin, lease ${t.lease_week.toFixed(2)}M a week${t.lease_seen ? "" : " est."}): ${when}`,
  };
}

// ---------- route profit (routeProfitBoard, rpScatter, rpCost, rpTailChart)
export const MARKS: Record<Mark, { label: string; cls: "ok" | "warn" | "bad" | "mute"; color: string }> = {
  add: { label: "add a flight", cls: "ok", color: "#1E9E6A" },
  raise: { label: "raise fares", cls: "ok", color: "#3B3FD8" },
  fix: { label: "fix or reduce", cls: "warn", color: "#E39B21" },
  losing: { label: "losing money", cls: "bad", color: "#B4234B" },
  hold: { label: "hold", cls: "mute", color: "#9AA4C4" },
};
export const MARK_ORDER: readonly Mark[] = ["add", "raise", "fix", "losing", "hold"];
export type RouteSort = "pwk" | "ppf" | "margin" | "eco";
export const SORTS: readonly [RouteSort, string][] = [["pwk", "a week"], ["ppf", "a flight"], ["margin", "margin"], ["eco", "economy"]];
export const PERIODS: readonly number[] = [1, 3, 7];

/** How many routes carry each mark. */
export function markCounts(routes: readonly RouteRow[]): Partial<Record<Mark, number>> {
  const out: Partial<Record<Mark, number>> = {};
  for (const r of routes) out[r.mark] = (out[r.mark] ?? 0) + 1;
  return out;
}
/** The routes shown: those with the mark picked (all without), sorted as picked (a stable sort on the database's order). */
export function shownRoutes(routes: readonly RouteRow[], mark: Mark | "", sort: RouteSort): RouteRow[] {
  const by: Record<RouteSort, (a: RouteRow, b: RouteRow) => number> = {
    pwk: (a, b) => b.profit_week - a.profit_week,
    ppf: (a, b) => b.profit_per_flight - a.profit_per_flight,
    margin: (a, b) => (b.margin ?? -9) - (a.margin ?? -9),
    eco: (a, b) => (b.economy ?? -1) - (a.economy ?? -1),
  };
  return routes.filter((r) => !mark || r.mark === mark).slice().sort(by[sort] ?? by.pwk);
}
/** The text a route's row is found by: its two codes and their cities, lower case (the old data-rprow). */
export const routeSearchText = (r: { hub: string; dest: string }, city: (code: string) => string): string =>
  `${r.hub} ${r.dest} ${city(r.hub)} ${city(r.dest)}`.toLowerCase();
/** The line under the filters. */
export function capturedLine(a: RouteProfitAnswer, soldOutMin: number | string): string {
  const days = a.days;
  return `${a.flights} flights captured over ${days === 1 ? "the last day" : "the last " + days + " days"}${a.matched < a.flights ? `, ${a.matched} matched to their loads` : ", all matched to their loads"}`
    + `${a.mixed ? ` · ${a.mixed} couldn't be told apart from another flight in the same minute` : ""}. A route needs ${soldOutMin} captured departures before it can be called sold out.`;
}
/** A route's "a week" figure. */
export const weekWords = (r: RouteRow): string => (r.flights_week ? (r.profit_week >= 0 ? "+" : "−") + Math.abs(r.profit_week).toFixed(2) + "M" : "—");

export interface ScatterLabel { x: number; y: number; text: string; anchor: "start" | "end" }
export interface ScatterLayout {
  W: number; H: number; pl: number; pr: number; pb: number; pt: number;
  /** The load axis: from the lowest load among the routes shown, rounded down to the next 5% (never below 40%), to 100%. */
  x0: number; x1: number;
  yTicks: { y: number; label: string }[]; xTicks: { x: number; label: string }[]; zeroY: number | null;
  /** The load axis's title, inside the chart (right-aligned at its right edge, under the ticks). */
  xTitle: { x: number; y: number; text: string };
  dots: { x: number; y: number; r: number; color: string; title: string }[];
  labels: ScatterLabel[];
}
/** How far a 10px label runs, a character at a time (Manrope's average), for keeping labels apart. */
export const SCATTER_CHAR_W = 6;
/** The marks off the pattern, labelled whatever their profit (spec docs/specs/2026-10-22-planner-look-performance.md). */
const OFF_PATTERN: readonly Mark[] = ["fix", "raise", "add"];
/** The load axis's start: the lowest load rounded down to the next 5%, never below 40%, and at least 5% short of 100%. */
export function loadAxisFrom(loads: readonly number[]): number {
  if (!loads.length) return 40;
  return Math.min(95, Math.max(40, Math.floor(Math.min(...loads) / 5) * 5));
}
/** Economy load against profit a flight, bubble size flights a week, colour the mark; null without loads. Since 22 Oct
 *  (spec docs/specs/2026-10-22-planner-look-performance.md) the load axis is zoomed to the routes shown (loadAxisFrom; a
 *  load under 40% sits on the axis's left edge), and only the five routes with the most profit a week and the ones off
 *  the pattern (fix, raise fares, add a flight) are labelled, each placed beside its dot where it overlaps no label
 *  already placed and stays inside the plot, else dropped. */
export function scatterLayout(routes: readonly RouteRow[]): ScatterLayout | null {
  const pts = routes.filter((r) => r.economy != null);
  if (!pts.length) return null;
  const W = 460, H = 250, pl = 48, pr = 14, pt = 12, pb = 44, ys = pts.map((r) => r.profit_per_flight * 1000);
  const x0 = loadAxisFrom(pts.map((r) => r.economy as number)), x1 = 100;
  const y0 = Math.min(0, Math.min(...ys)), y1 = Math.max(1, Math.max(...ys) * 1.12);
  const X = (v: number) => pl + (Math.max(x0, Math.min(x1, v)) - x0) / (x1 - x0) * (W - pl - pr), Y = (v: number) => H - pb - (v - y0) / (y1 - y0) * (H - pt - pb);
  const maxW = Math.max(1, ...pts.map((r) => r.flights_week || 1));
  const step = x1 - x0 <= 30 ? 5 : 10;
  const tx: number[] = [];
  for (let v = x0; v <= x1; v += step) tx.push(v);
  const key = (r: RouteRow) => `${r.hub}–${r.dest}`;
  const top = [...pts].sort((a, b) => b.profit_week - a.profit_week).slice(0, 5);
  const off = pts.filter((r) => OFF_PATTERN.includes(r.mark) && !top.includes(r)).sort((a, b) => b.profit_week - a.profit_week);
  const dots = pts.map((r) => ({ r, x: X(r.economy as number), y: Y(r.profit_per_flight * 1000), rad: 4 + 10 * Math.sqrt((r.flights_week || 1) / maxW) }));
  // each label's box (x0, y0, x1, y1); the first place that fits beside its dot wins, in the plot and clear of the others
  const placed: [number, number, number, number][] = [];
  const labels: ScatterLabel[] = [];
  const hit = (a: [number, number, number, number], b: [number, number, number, number]) => a[0] < b[2] && b[0] < a[2] && a[1] < b[3] && b[1] < a[3];
  for (const r of [...top, ...off]) {
    const d = dots.find((x) => x.r === r);
    if (!d) continue;
    const text = key(r), w = text.length * SCATTER_CHAR_W, h = 11, gap = d.rad * 0.7 + 3;
    const tries: { x: number; y: number; anchor: "start" | "end" }[] = [
      { x: d.x - gap, y: d.y - gap, anchor: "end" }, { x: d.x + gap, y: d.y - gap, anchor: "start" },
      { x: d.x - gap, y: d.y + gap + h - 2, anchor: "end" }, { x: d.x + gap, y: d.y + gap + h - 2, anchor: "start" },
    ];
    for (const t of tries) {
      const left = t.anchor === "end" ? t.x - w : t.x;
      const box: [number, number, number, number] = [left - 1, t.y - h + 2, left + w + 1, t.y + 3];
      if (box[0] < pl || box[2] > W - pr || box[1] < 0 || box[3] > H - pb) continue;
      if (placed.some((b) => hit(b, box))) continue;
      placed.push(box);
      labels.push({ x: t.x, y: t.y, text, anchor: t.anchor });
      break;
    }
  }
  return {
    W, H, pl, pr, pb, pt, x0, x1,
    yTicks: [0, 1, 2, 3, 4].map((i) => y0 + (y1 - y0) * i / 4).map((v) => ({ y: Y(v), label: `${Math.round(v)}k` })),
    xTicks: tx.map((v) => ({ x: X(v), label: `${v}%` })),
    zeroY: y0 < 0 ? Y(0) : null,
    xTitle: { x: W - pr, y: H - 6, text: "economy load →" },
    dots: dots.map(({ r, x, y, rad }) => ({ x, y, r: rad, color: MARKS[r.mark].color,
      title: `${key(r)} · economy ${Math.round(r.economy as number)}% · ${Math.round(r.profit_per_flight * 1000)}k a flight · ${r.flights_week} flights a week · ${MARKS[r.mark].label}` })),
    labels,
  };
}

export interface CostPart { name: string; k: number; color: string }
/** The old rpCost: an average flight's income and where it goes, in thousands; null when it earned nothing. */
export function costParts(a: AverageFlight | null): { income: CostPart[]; costs: CostPart[]; profitK: number; marginPct: number } | null {
  if (!a || !a.income) return null;
  return {
    income: [{ name: "Passengers", k: a.passengers * 1000, color: "#3B3FD8" }, { name: "Cargo", k: a.cargo * 1000, color: "#8D90F2" }],
    costs: [{ name: "Fuel", k: a.fuel * 1000, color: "#B4234B" }, { name: "Handling", k: a.handling * 1000, color: "#E0557A" },
      { name: "On-board", k: a.onboard * 1000, color: "#E39B21" }, { name: "Landing", k: a.landing * 1000, color: "#F2C14E" },
      { name: "Air traffic", k: a.air_traffic * 1000, color: "#9AA4C4" }, { name: "Maintenance", k: a.maintenance * 1000, color: "#5B647E" }],
    profitK: a.profit * 1000,
    marginPct: Math.round((a.margin ?? 0) * 100),
  };
}

/** The old rpTailChart: each aircraft's profit a day after its lease (or before, without one), a bar each. */
export function tailBars(rows: readonly AircraftRow[]): { W: number; H: number; mid: number | null; bars: { y: number; x: number; w: number; pos: boolean; label: string; labelX: number; title: string; reg: string }[] } {
  const v = (t: AircraftRow) => (t.net_day != null ? t.net_day : t.flight_profit_day);
  const W = 900, rh = 22, x0 = 110;
  const mx = Math.max(0.001, ...rows.map((t) => Math.abs(v(t)) * 1000));
  const anyNeg = Math.min(...rows.map(v)) < 0;
  const mid = x0 + (W - x0 - 60) * (anyNeg ? 0.3 : 0), span = W - mid - 60;
  const sc = (x: number) => x / mx * (anyNeg ? span : W - x0 - 60);
  return {
    W, H: rows.length * rh + 6, mid: anyNeg ? mid : null,
    bars: rows.map((t, i) => {
      const k = v(t) * 1000, w = Math.abs(sc(k)), x = k >= 0 ? mid : mid - w;
      return { y: i * rh, x, w, pos: k >= 0, label: (k >= 0 ? "+" : "−") + Math.abs(Math.round(k)) + "k", labelX: k >= 0 ? x + w + 5 : x - 5,
        title: `${t.registration}: ${Math.round(k)}k a day${t.net_day != null ? " after lease" : ""}`, reg: t.registration };
    }),
  };
}

// ---------- the group today (groupOverviewHtml's rows; its group totals left out, manual §5)
/** Each airline's row: flight profit to the right, leases and the week-end closing to the left, net at the end. */
export function groupLayout(rows: readonly GroupRow[]) {
  const W = 900, rh = 30, x0 = 140;
  const mx = Math.max(0.01, ...rows.map((r) => Math.max(r.flight_profit_day ?? 0, r.leases_and_closing_day)));
  const sc = (v: number) => v / mx * (W - x0 - 70) / 2, c = x0 + (W - x0 - 70) / 2;
  return {
    W, H: rows.length * rh + 24, c, axisY: rows.length * rh + 4, labelY: rows.length * rh + 18,
    rows: rows.map((r, i) => ({
      r, y: i * rh + 4, profitW: sc(r.flight_profit_day ?? 0), leaseW: sc(r.leases_and_closing_day),
      profitTitle: `Flight profit ${sg(r.flight_profit_day ?? 0)} a day`, leaseTitle: `Leases and week-end closing −${r.leases_and_closing_day.toFixed(2)}M a day`,
      net: r.net_day == null ? "—" : sg(r.net_day), neg: (r.net_day ?? 0) < 0,
    })),
  };
}

// ---------- the growth lists' cut (21 Oct: Performance ran to 11,890 px with every row of each list)
/** How many rows a growth list shows before "show all N". */
export const LIST_TOP = 10;
/** A growth list's rows as shown: its first LIST_TOP in its own order, with "show all N" to open the rest in place and
 *  "show fewer" to close them again; every row and no button with LIST_TOP or fewer. Its count stays in its heading. */
export function listCut<T>(rows: readonly T[], open: boolean, top = LIST_TOP): { shown: readonly T[]; button: string | null } {
  if (rows.length <= top) return { shown: rows, button: null };
  return open ? { shown: rows, button: "show fewer" } : { shown: rows.slice(0, top), button: `show all ${rows.length}` };
}

// ---------- the fare plan (farePlanBoard) and "+ fare plan"
export function planWords(p: PlanRow, nice: (day: string) => string) {
  return {
    route: `${p.hub ?? ""}–${p.dest ?? ""}`,
    cls: p.cabin_class || "economy",
    change: `${(p.change_pct ?? 0) > 0 ? "+" : ""}${p.change_pct}%`
      + (p.level_pct != null ? ` · ${p.ladder_move ?? "ladder"} to ${Math.round(p.level_pct * 10) / 10}%` : ""),
    fares: `${Math.round(p.fare_from ?? NaN)} → ${Math.round(p.target ?? NaN)}`,
    now: p.fare_now == null ? "—" : String(Math.round(p.fare_now)),
    status: p.applied ? { kind: "ok" as const, text: `seen in the game ${nice(p.seen_on ?? "")}` } : { kind: "warn" as const, text: "to do in the game" },
    loads: p.applied ? pc(p.economy_before) + " → " + pc(p.economy_after) : "—",
    why: p.reason ?? "",
  };
}
/** Whether a route's row offers "+ fare plan": marked raise fares or add a flight, with no change already planned. */
export const offersFarePlan = (r: RouteRow, plan: readonly PlanRow[]): boolean =>
  (r.mark === "raise" || r.mark === "add") && !plan.some((p) => p.route_id != null && p.route_id === r.route_id && p.status === "planned");
/** "+ fare plan" as one insert, the row the old planner's adapter writes: the economy fare rise from the latest captured
 *  fare, rounded, proposed today, "sells out". Null when the route has no captured fare. */
export function farePlanAdd(x: { worldId: number; airlineId: number; routeId: number; fare: number | null | undefined; pct: number; today: string; nowMs: number }): Change | null {
  if (!x.fare) return null;
  return { table: "fare_plan", op: "insert", values: {
    world_id: x.worldId, airline_id: x.airlineId, route_id: x.routeId, legacy_key: "fp" + x.nowMs.toString(36), cabin_class: "economy",
    change_pct: x.pct, fare_from: Math.round(x.fare), proposed_on: x.today, status: "planned", reason: "sells out" } };
}
/** "remove": the change dropped, as the old planner keeps it (status dropped). */
export const farePlanDrop = (p: PlanRow): Change => ({ table: "fare_plan", op: "update", key: { id: p.id }, base: p.updated_at, values: { status: "dropped" } });

// ---------- the scorecards: each figure against the same day last week, from the daily history (airline_days)
/** An airline's row of the daily history, the columns the scorecards compare. */
export interface DayRow { airline_id: number; day: string; aircraft_total: number | null; weekly_departures: number | null; eco_load_pct: number | null }
export type WeekKey = "fleet" | "flights" | "load";
export interface WeekChange {
  /** The figure on the latest day and on the same day a week before (null when the history has none). */
  now: number | null;
  then: number | null;
  /** now − then, to one decimal; null without both. */
  delta: number | null;
  arrow: "up" | "down" | "same" | null;
  /** The change in words: "▲ 2", "▼ 1.4 pts", "= same", or "—" with nothing to compare. */
  text: string;
}
export interface WeekOnWeek {
  /** The latest day of the airline's history (at or before today), and the same day a week before it. */
  day: string | null;
  weekAgo: string | null;
  /** True when the history has that day a week before: without it every change is "—". */
  compared: boolean;
  changes: Record<WeekKey, WeekChange>;
}
const dayMinus = (day: string, n: number): string => new Date(Date.parse(day + "T00:00:00Z") - n * 86_400_000).toISOString().slice(0, 10);
const round1 = (v: number): number => Math.round(v * 10) / 10;

function change(now: number | null, then: number | null, unit = ""): WeekChange {
  if (now == null || then == null) return { now, then, delta: null, arrow: null, text: "—" };
  const delta = round1(now - then);
  if (delta === 0) return { now, then, delta: 0, arrow: "same", text: "= same" };
  const size = Math.abs(delta), u = unit === " pts" && size === 1 ? " pt" : unit;
  return { now, then, delta, arrow: delta > 0 ? "up" : "down", text: `${delta > 0 ? "▲" : "▼"} ${size % 1 ? size.toFixed(1) : String(size)}${u}` };
}

/** The 7 days' average of a figure ending on a day (the days with a figure), or null with none. */
function weekAverage(rows: readonly DayRow[], day: string, pick: (r: DayRow) => number | null): number | null {
  const from = dayMinus(day, 6);
  const vals = rows.filter((r) => r.day >= from && r.day <= day).map(pick).filter((v): v is number => v != null && Number.isFinite(v));
  return vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : null;
}

/** An airline's scorecard figures against the same day last week, from the daily history (airline_days): its latest
 *  day at or before today, and that day a week earlier. Fleet is the aircraft flying (aircraft_total), flights a day the
 *  schedule's departures a week ÷ 7 (weekly_departures), the average load the economy load averaged over the 7 days to
 *  each day (eco_load_pct). An airline with no day a week ago (a new one, or a gap in the history) gets "—" for each. */
export function weekOnWeek(rows: readonly DayRow[], airlineId: number, today: string): WeekOnWeek {
  const mine = rows.filter((r) => r.airline_id === airlineId && r.day <= today).sort((a, b) => (a.day < b.day ? -1 : a.day > b.day ? 1 : 0));
  const last = mine[mine.length - 1];
  const empty = { fleet: change(null, null), flights: change(null, null), load: change(null, null) };
  if (!last) return { day: null, weekAgo: null, compared: false, changes: empty };
  const weekAgo = dayMinus(last.day, 7);
  const then = mine.find((r) => r.day === weekAgo);
  if (!then) return { day: last.day, weekAgo, compared: false, changes: empty };
  const perDay = (r: DayRow) => (r.weekly_departures == null ? null : round1(r.weekly_departures / 7));
  return {
    day: last.day, weekAgo, compared: true,
    changes: {
      fleet: change(last.aircraft_total, then.aircraft_total),
      flights: change(perDay(last), perDay(then)),
      load: change(weekAverage(mine, last.day, (r) => r.eco_load_pct), weekAverage(mine, weekAgo, (r) => r.eco_load_pct), " pts"),
    },
  };
}
/** The first day the scorecards read the history from: two weeks and a day before today (the 7 days' load a week ago). */
export const historyFrom = (today: string): string => dayMinus(today, 15);

// ---------- the fare ladder (manual §5, since 21 Oct; spec docs/specs/2026-10-21-fare-ladder.md): fare_ladder()'s answer,
// worded for the board, sorted, and Put on the fare plan's rows. Every level, move and game action is the database's.
export type LadderMove = "up" | "hold" | "down";
/** What Put on the fare plan writes as ladder_move (since 23 Oct, spec docs/specs/2026-10-23-fare-ladder-under-launch.md):
 *  a jump under launch has move down and a revert move up, so readers of move keep working. */
export type LadderKind = LadderMove | "jump" | "revert";
export type LadderCabin = "economy" | "business";
/** A cabin under launch (since 23 Oct): its state and the figures it is judged on, where they apply. */
export interface UnderLaunch {
  state: "launch" | "holding" | "due" | "done";
  baseline_revenue?: number;
  window_revenue?: number;
  window_load?: number;
  window_flights?: number;
  jumped_on?: string;
  judge_on?: string;
}
export interface LadderRoute {
  route_id: number;
  hub: string;
  dest: string;
  cabin: LadderCabin;
  departures: number;
  sold_out: number;
  sold_out_share: number | null;
  average_fare: number | null;
  /** The fare index's baseline (since 21 Oct): the route's fare on 21 Oct 2026, when every route was at its launch
   *  level, or its first captured fare for a route launched later; and the day it's from. */
  baseline_fare: number | null;
  baseline_on: string | null;
  latest_fare: number | null;
  latest_on: string | null;
  /** Each flight of the latest captured day against the baseline, times the launch level (their average);
   *  index_matches false when any flight is more than 1 point off the level the game should show. */
  fare_index: number | null;
  index_matches: boolean | null;
  /** The level, % of the game's default price, and how many steps above launch. */
  level: number;
  recorded: boolean;
  steps: number;
  move: LadderMove;
  new_level: number;
  new_steps: number;
  change_pct: number | null;
  reason: string;
  contested: boolean;
  floor: number;
  cap: number;
  new_route: boolean;
  /** This Saturday's move is on the fare plan already (and, applied, the captures show it). */
  planned: boolean;
  plan_id: number | null;
  applied: boolean;
  seen_on: string | null;
  /** What Put on the fare plan writes: a level that changes, or a hold that follows a step down. */
  to_plan: boolean;
  /** Off its level and set back to it (since 21 Oct, spec docs/specs/2026-10-21-frequencies-and-fares.md §3), with
   *  why: "captured fare at 100%, level 110%". */
  fix?: boolean;
  fix_reason?: string | null;
  /** Since 23 Oct: up, down, hold, jump or revert (what Put on the fare plan writes as ladder_move); the cabin under
   *  launch; and a cut-or-keep decision for Gitesh at the last jump level. */
  ladder_kind?: LadderKind;
  under_launch?: UnderLaunch | null;
  decide?: boolean;
}
/** One Ticket price adjustment, route by route only since 21 Oct (spec docs/specs/2026-10-21-fare-actions-by-route.md):
 *  never a whole base, each direction its own action (From hub to dest, then From dest to hub). */
export interface LadderAction {
  n: number;
  /** The route, "JFK–ORD". */
  route: string;
  /** The classes it changes: both when the route's two cabins move to the same new level, else one. */
  classes: LadderCabin[];
  from: string;
  to: string;
  level: number;
  sign: "+" | "-";
  pct: number;
  baseline: string;
  /** In the game's words, naming the classes: "From JFK to ORD: +5% of the default price, economy and business". */
  text: string;
  /** A change that sets the route back to its level (since 21 Oct), listed first, with why. */
  fix?: boolean;
  reason?: string | null;
}
export interface LadderAnswer {
  airline_id: number;
  as_of: string;
  week_of: string;
  settings: { step_pts: number; launch_pct: number; cap_pct: number; up_share: number; down_share: number; min_departures: number; hold_weeks: number };
  /** jumps and decisions since 23 Oct: jumps under launch, and cut-or-keep decisions for Gitesh. */
  moves: { up: number; hold: number; down: number; jumps?: number; decisions?: number };
  to_plan: number;
  planned: number;
  /** How many routes are set back to their level (since 21 Oct). */
  off_level?: number;
  routes: LadderRoute[];
  actions: LadderAction[];
  notes: string[];
}

/** The set-back changes (fix, since 21 Oct; spec docs/specs/2026-10-21-frequencies-and-fares.md §3), which the board
 *  lists first in their own short list, and the week's moves, each in fare_ladder()'s order. */
export function splitActions(actions: readonly LadderAction[]): { fixes: LadderAction[]; moves: LadderAction[] } {
  return { fixes: actions.filter((a) => a.fix === true), moves: actions.filter((a) => a.fix !== true) };
}
/** The set-back list's heading, by the routes it sets back: "3 routes off their level", "1 route off its level". */
export function offLevelWords(fixes: readonly LadderAction[]): string {
  const n = new Set(fixes.map((a) => a.route)).size;
  return `${n} route${n === 1 ? "" : "s"} off ${n === 1 ? "its" : "their"} level`;
}
/** This Saturday's moves in one line: "12 up, 30 hold, 2 down", and since 23 Oct the jumps under launch and the
 *  cut-or-keep decisions when there are any: "12 up, 30 hold, 2 down · 2 jumps, 1 decision". */
export const ladderLine = (m: LadderAnswer["moves"]): string => {
  const base = `${m.up} up, ${m.hold} hold, ${m.down} down`;
  const extra = underLaunchLine(m);
  return extra ? `${base} · ${extra}` : base;
};
/** The week's jumps and decisions under launch (since 23 Oct): "2 jumps, 1 decision", "1 jump", "" when none. */
export function underLaunchLine(m: Pick<LadderAnswer["moves"], "jumps" | "decisions">): string {
  const j = m.jumps ?? 0, d = m.decisions ?? 0;
  const parts = [j ? `${j} jump${j === 1 ? "" : "s"}` : "", d ? `${d} decision${d === 1 ? "" : "s"}` : ""].filter(Boolean);
  return parts.join(", ");
}
/** How many changes to make in the game, for the airline's heading: "24 changes in the game", "1 change in the game",
 *  "no changes in the game". */
export const changesWords = (n: number): string => (n ? `${n} change${n === 1 ? "" : "s"} in the game` : "no changes in the game");
const pts = (v: number): string => String(Math.round(v * 10) / 10);
/** Steps above launch in words: "launch", "1 step up", "3 steps up", "1 step under launch". */
export function stepWords(steps: number): string {
  const s = Math.round(steps * 10) / 10;
  if (s === 0) return "launch";
  const n = Math.abs(s);
  return `${pts(n)} step${n === 1 ? "" : "s"} ${s > 0 ? "up" : "under launch"}`;
}
/** A level with its steps above launch: "105% · 1 step up", "100% · launch". */
export const levelWords = (level: number, steps: number): string => `${pts(level)}% · ${stepWords(steps)}`;
/** The move, as the board shows it: up plain, down in amber (colour only for action), hold quiet. */
export function moveWords(r: Pick<LadderRoute, "move" | "new_level"> & Partial<Pick<LadderRoute, "ladder_kind" | "under_launch">>): { text: string; kind: "up" | "down" | "hold" } {
  // under launch (since 23 Oct): a jump in amber as a step down, a revert plain as a step up, the hold after a jump in words
  if (r.ladder_kind === "jump") return { text: `jump to ${pts(r.new_level)}%`, kind: "down" };
  if (r.ladder_kind === "revert") return { text: `back to launch, ${pts(r.new_level)}%`, kind: "up" };
  if (r.move === "hold" && r.under_launch?.state === "holding") return { text: "hold under launch", kind: "hold" };
  if (r.move === "up") return { text: `up to ${pts(r.new_level)}%`, kind: "up" };
  if (r.move === "down") return { text: `down to ${pts(r.new_level)}%`, kind: "down" };
  return { text: "hold", kind: "hold" };
}
/** The sold-out share: "14/14 · 100%", or "no flights" with none captured. */
export const soldWords = (r: Pick<LadderRoute, "departures" | "sold_out" | "sold_out_share">): string =>
  r.departures ? `${r.sold_out}/${r.departures} · ${Math.round(r.sold_out_share ?? (r.sold_out / r.departures) * 100)}%` : "no flights";
/** A move already on the fare plan this Saturday, and whether the captures show it yet. */
export function plannedWords(r: Pick<LadderRoute, "planned" | "applied" | "seen_on">, nice: (day: string) => string): string {
  if (!r.planned) return "";
  return r.applied ? `on the fare plan · seen in the game ${nice(r.seen_on ?? "")}` : "on the fare plan · to do in the game";
}
/** Put on the fare plan's button and the line beside it. */
export function planButton(a: Pick<LadderAnswer, "to_plan" | "planned" | "routes">): { text: string; enabled: boolean; note: string } {
  const seen = a.routes.filter((r) => r.planned && r.applied).length;
  const done = a.planned ? `${a.planned} on the fare plan this Saturday, ${seen} seen in the game` : "";
  if (a.to_plan) return { text: `Put on the fare plan (${a.to_plan})`, enabled: true, note: done };
  if (a.planned) return { text: "On the fare plan", enabled: false, note: done };
  return { text: "Nothing to put on the fare plan", enabled: false, note: "" };
}
/** The routes table's sorts: the moves first (down, up, then holds), by route, by level (highest first), by the
 *  sold-out share (lowest first). Each keeps the database's order (route, then economy before business) on a tie. */
export type LadderSort = "move" | "route" | "level" | "sold";
export const LADDER_SORTS: readonly [LadderSort, string][] = [["move", "moves first"], ["route", "route"], ["level", "level"], ["sold", "sold out"]];
export function ladderRows(rows: readonly LadderRoute[], sort: LadderSort): LadderRoute[] {
  const rank: Record<LadderMove, number> = { down: 0, up: 1, hold: 2 };
  const by: Record<LadderSort, (a: LadderRoute, b: LadderRoute) => number> = {
    move: (a, b) => rank[a.move] - rank[b.move],
    route: () => 0,
    level: (a, b) => b.level - a.level,
    sold: (a, b) => (a.departures ? a.sold_out_share ?? 0 : 101) - (b.departures ? b.sold_out_share ?? 0 : 101),
  };
  return rows.slice().sort(by[sort] ?? by.move);
}
/** Put on the fare plan: one insert per route and cabin the database marks to_plan (each level that changes, each
 *  hold that follows a step down, and since 23 Oct a judgement under launch that holds), all in one planner_save() call.
 *  The level and the move are the ladder's (ladder_move jump or revert from ladder_kind, since 23 Oct); the fare
 *  then is the latest captured fare in that cabin (fare_plan_status() ticks a row off when the captured fare moves by
 *  its change, within 1%); proposed on the UTC day, the day the database's week is counted in. */
export function ladderPlanChanges(x: { worldId: number; airlineId: number; routes: readonly LadderRoute[]; utcDay: string; nowMs: number }): Change[] {
  return x.routes.filter((r) => r.to_plan).map((r, i) => ({ table: "fare_plan", op: "insert", values: {
    world_id: x.worldId, airline_id: x.airlineId, route_id: r.route_id, legacy_key: `fl${x.nowMs.toString(36)}-${i}`, cabin_class: r.cabin,
    change_pct: r.change_pct ?? 0, fare_from: r.latest_fare == null ? null : Math.round(r.latest_fare * 100) / 100, proposed_on: x.utcDay,
    status: "planned", reason: r.reason, level_pct: r.new_level,
    ladder_move: r.ladder_kind === "jump" || r.ladder_kind === "revert" ? r.ladder_kind : r.move } }));
}
/** A cut-or-keep decision for Gitesh (since 23 Oct): the marker beside its reason, "" for any other row. Never in
 *  Needs attention (manual §5: fare moves never are). */
export const decideWords = (r: Pick<LadderRoute, "decide">): string => (r.decide ? "cut or keep?" : "");
/** The fare index for the route profit table, from the ladder's economy row: "105", flagged when the level recorded
 *  differs from it by more than a point. */
export function indexWords(r: Pick<LadderRoute, "fare_index" | "index_matches" | "level"> | undefined): { text: string; flag: string } {
  if (!r || r.fare_index == null) return { text: "—", flag: "" };
  return { text: String(Math.round(r.fare_index)), flag: r.index_matches === false ? `level ${pts(r.level)}%` : "" };
}

// ---------- the route profit table's 14-day load sparkline, from the daily history (route_days)
export interface RouteDayRow { route_id: number | null; origin_code: string; dest_code: string; day: string; passengers: number | null; seats: number | null }
export const SPARK_DAYS = 14;
/** Each route's load on each of the 14 days to today (oldest first), both directions together: the day's passengers ÷
 *  seats on the flights whose loads were captured, at most 100%; null on a day with no seats. By the route's id, or by
 *  its two airports either way round where the history has no route. */
export function loads14(rows: readonly RouteDayRow[], route: { route_id: number | null; hub: string; dest: string }, today: string): (number | null)[] {
  const days = Array.from({ length: SPARK_DAYS }, (_, i) => dayMinus(today, SPARK_DAYS - 1 - i));
  const mine = rows.filter((r) => (route.route_id != null && r.route_id === route.route_id)
    || (r.route_id == null && ((r.origin_code === route.hub && r.dest_code === route.dest) || (r.origin_code === route.dest && r.dest_code === route.hub))));
  return days.map((d) => {
    const on = mine.filter((r) => r.day === d);
    const seats = on.reduce((s, r) => s + (r.seats ?? 0), 0), pax = on.reduce((s, r) => s + (r.passengers ?? 0), 0);
    return seats > 0 ? Math.min(100, (pax / seats) * 100) : null;
  });
}
/** The sparkline: a bar a day, 56 × 16, its height the day's load; a day with none has no bar. */
export function loadSparkBars(values: readonly (number | null)[]): { x: number; y: number; w: number; h: number; low: boolean }[] {
  const W = 56, H = 16, n = Math.max(1, values.length), w = (W / n) * 0.7;
  return values.flatMap((v, i) => (v == null ? [] : [{ x: (i + 0.15) * (W / n), y: H - Math.max(1, (v / 100) * H), w, h: Math.max(1, (v / 100) * H), low: v < 85 }]));
}
/** The sparkline's words, for its title: "14 days' load: 92% to 100%, 98% on average". */
export function sparkWords(values: readonly (number | null)[]): string {
  const vs = values.filter((v): v is number => v != null);
  if (!vs.length) return "no loads in the daily history for the last 14 days";
  return `${vs.length} day${vs.length === 1 ? "" : "s"}' load: ${Math.round(Math.min(...vs))}% to ${Math.round(Math.max(...vs))}%, ${Math.round(vs.reduce((a, b) => a + b, 0) / vs.length)}% on average`;
}

// ---------- the boards: the airline's page, and the group's
// Since 22 Oct (spec docs/specs/2026-10-22-planner-look-performance.md) each is a row that opens: the airline's page
// with Route profit open on arrival (Aircraft and Fare changes, under it until then, are rows of their own); the
// group's all closed (Flights by day open when the address names a day), the fare ladder's cards above them.
export const BOARDS = ["Profit", "Cash, next 14 days", "Route profit", "Aircraft", "Fare changes", "Fare plan"] as const;
export type BoardKey = (typeof BOARDS)[number];
/** The airline's page opens with these folded. */
export const BOARDS_FOLDED: readonly BoardKey[] = BOARDS.filter((k) => k !== "Route profit");
export const GROUP_BOARDS = ["The group today", "Growth signals", "Main hubs", "Flights by day"] as const;
export type GroupBoardKey = (typeof GROUP_BOARDS)[number];
export type FoldKey = BoardKey | GroupBoardKey;
/** Which rows are closed, and on which page ("/performance" or "/performance/<code>"): the group page and each airline's
 *  page keep their own, so what Expand all opened on one never carries to the next (22 Oct). */
export interface FoldState { view: string; folded: ReadonlySet<FoldKey> }
/** A page's rows on arrival: every row closed but the airline's Route profit, and the group's Flights by day when the
 *  address names a day (?day=). */
export function foldsOnArrival(view: string, search: string): FoldState {
  const airline = view !== "/performance";
  const day = new URLSearchParams(search).has("day");
  return { view, folded: new Set<FoldKey>([...BOARDS_FOLDED, ...GROUP_BOARDS.filter((k) => airline || !(k === "Flights by day" && day))]) };
}
/** The rows closed on the page shown: as last left on that same page, else as on arrival. */
export function foldsFor(state: FoldState, view: string, search: string): ReadonlySet<FoldKey> {
  return state.view === view ? state.folded : foldsOnArrival(view, search).folded;
}

// ---------- the answers the page heads and rows give (22 Oct)
const NUMBER_WORDS = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve"];
/** The group page's title: how many airlines are in profit (profit a day above zero), never a group total (manual §1):
 *  "Six airlines, all in profit", else "5 of 6 airlines in profit". An airline with no profit read yet isn't in profit. */
export function profitAnswer(cards: readonly Pick<Card, "profit_day">[]): string {
  const n = cards.length;
  if (!n) return "Performance";
  const up = cards.filter((c) => c.profit_day != null && c.profit_day > 0).length;
  if (up === n) return n === 1 ? "One airline, in profit" : `${NUMBER_WORDS[n] ?? n} airlines, all in profit`;
  return `${up} of ${n} airline${n === 1 ? "" : "s"} in profit`;
}
const plural = (n: number, one: string, many = one + "s") => `${n} ${n === 1 ? one : many}`;
/** The group today's row: how many airlines are ahead after leases and the week-end closing. */
export function groupTodayWords(rows: readonly Pick<GroupRow, "net_day">[]): string {
  const read = rows.filter((r) => r.net_day != null);
  if (!read.length) return "nothing captured yet";
  return `${read.filter((r) => (r.net_day as number) > 0).length} of ${plural(read.length, "airline")} ahead after leases`;
}
/** Growth signals' row: each list's count. */
export function growthWords(x: { profit_captured: boolean; ready: number; raise: number; fix: number; aircraft: number }): string {
  if (!x.profit_captured) return `${x.ready} ready for another flight, from the load reports`;
  return `${x.ready} ready for a flight · ${x.raise} raise fares · ${x.fix} fix or reduce · ${plural(x.aircraft, "aircraft", "aircraft")} losing`;
}
/** Main hubs' row: how many main hubs have reached their weekly target. */
export function hubsWords(progress: readonly { main_hub: string | null; exempt: boolean; departures: number | null; target: number }[]): string {
  const hubs = progress.filter((p) => p.main_hub && !p.exempt);
  if (!hubs.length) return "no main hub yet";
  return `${hubs.filter((p) => (p.departures ?? 0) >= p.target).length} of ${plural(hubs.length, "main hub")} at the target`;
}
/** The airline page's rows: their counts or states. */
export function profitRowWords(p: Pick<ProfitAnswer, "profit_day"> | undefined): string {
  return p?.profit_day == null ? "needs two nights of cash" : `${sg(p.profit_day)} a day, 7-day average`;
}
export function cashRowWords(fc: Pick<Forecast, "status" | "lowest"> | undefined, cushion: number): { text: string; low: boolean } {
  if (!fc || fc.status !== "ok") return { text: "needs a capture", low: false };
  if (!fc.lowest) return { text: "no payments due", low: false };
  return { text: `lowest ${fc.lowest.balance.toFixed(2)}M on ${fcDay(fc.lowest.at)}`, low: fc.lowest.balance < cushion };
}
export function routeRowWords(r: Pick<RouteProfitAnswer, "flights" | "routes" | "days"> | undefined): string {
  if (!r || !r.flights) return "needs a bank statement";
  return `${plural(r.routes.length, "route")} · ${plural(r.flights, "flight")}, ${r.days === 1 ? "last day" : `last ${r.days} days`}`;
}
export function aircraftRowWords(rows: readonly Pick<AircraftRow, "net_day">[]): { text: string; losing: number } {
  return { text: plural(rows.length, "aircraft", "aircraft"), losing: rows.filter((t) => t.net_day != null && t.net_day < 0).length };
}
export const changesRowWords = (n: number): string => (n ? `${plural(n, "change")} spotted` : "none yet");
export const planRowWords = (n: number): string => (n ? `${n} planned` : "nothing planned");

// ---------- the route page (spec docs/specs/2026-10-21-route-page.md §3): a route's story since launch, from
// route_story() (the database's, private.fig_route_story()); here only worded, compared and laid out. Its connections are
// the planning library's (connections.connectionsAtBothEnds, the plan card's rule), on the schedule the planner reads.
export interface StoryFigures {
  flights: number;
  passengers: number | null;
  seats: number | null;
  /** Passengers on the flights whose loads were captured ÷ their seats, both directions. */
  load_pct: number | null;
  eco_pax: number | null;
  eco_seats: number | null;
  eco_load_pct: number | null;
  bus_pax: number | null;
  bus_seats: number | null;
  bus_load_pct: number | null;
  /** AS$, weighted by passengers. */
  eco_fare: number | null;
  bus_fare: number | null;
  /** Millions of AS$. */
  revenue: number | null;
  costs: number | null;
  profit: number | null;
  block_hours: number | null;
  /** Profit ÷ block hours, millions of AS$ an hour. */
  profit_per_hour: number | null;
}
export interface StoryDay extends StoryFigures { day: string }
export interface StoryWeek extends StoryFigures { from: string; to: string; days: number }
export type StoryKind = "launched" | "frequency added" | "frequency removed" | "aircraft changed" | "retimed" | "fare" | "cabin" | "rival";
export interface StoryEvent {
  day: string;
  kind: StoryKind;
  words: string;
  at?: string | null;
  /** A fare event's: its cabin, level (a ladder move) or change (a fare test), move and whether it was dropped. */
  cabin?: string | null;
  level?: number | null;
  change_pct?: number | null;
  move?: string | null;
  dropped?: boolean;
  /** A rival's: who, started or added, and its departures a week then and now. */
  rival?: string;
  rival_id?: number;
  change?: "started" | "added";
  then?: number;
  now?: number;
}
export type StoryFare = Omit<LadderRoute, "route_id" | "hub" | "dest">;
/** A connecting airport and the departures a week through it (since 23 Oct, spec docs/specs/2026-10-23-rival-connections.md). */
export interface StoryVia { via: string; weekly: number }
export interface StoryRival {
  airline_id: number; name: string; weekly: number; weekly_before: number | null; change: number | null;
  /** Since 23 Oct: its one-stop departures a week on the pair in the latest scan, beside weekly and never added to it. */
  connecting_weekly?: number; connecting_via?: StoryVia[];
}
/** Since 23 Oct (spec docs/specs/2026-10-23-rival-pairs-history.md §3) weekly: the point is a week's kept scan read from its
 *  kept rows, its full schedules archived. */
export interface StoryShare { scan_id: number; taken_at: string; ours: number; rivals: number; share: number | null; weekly?: boolean }
export interface ScanRef { id: number; taken_at: string; weekly?: boolean }
export interface RouteStory {
  route_id: number;
  as_of: string;
  latest_day: string | null;
  route: {
    id: number; hub: string; dest: string; pair: string; city: string | null; stars: number | null; distance_km: number | null; removed: boolean;
    market: { id: number; name: string; layout: string | null } | null;
    cabin: { layout: string | null; own: boolean; market_layout: string | null };
    airline: { id: number; code: string | null; name: string };
    launched: string | null; launched_from: "rotation" | "history" | null; launched_days: number | null;
  };
  now: {
    departures: { out: number; back: number };
    rotations: number;
    types: { type_id: number; type: string; aircraft: number }[];
    fares: StoryFare[];
    launch_pct: number | null;
    week_of: string | null;
  };
  days: StoryDay[];
  weeks: StoryWeek[];
  events: StoryEvent[];
  rivals: {
    scan: ScanRef | null; week_before: ScanRef | null;
    ours: number; rivals_weekly: number; share: number | null;
    ours_before: number | null; rivals_before: number | null; share_before: number | null;
    airlines: StoryRival[]; shares: StoryShare[];
    /** Since 23 Oct, when the latest scan has them worked out: every rival's connecting departures on the pair, the rivals
     *  that only connect, and each rival's at each scan read. */
    connecting_weekly?: number;
    connecting_only?: StoryRival[];
    connecting_scans?: { scan_id: number; taken_at: string; weekly: number; airlines: { airline_id: number; name: string; weekly: number; via: StoryVia[] }[] }[];
    /** Since 23 Oct: how many points are weekly (read from the kept rows), and the first point from full schedules
     *  (null when there is no weekly point, or when every point is weekly). */
    weekly_points?: number; daily_from?: string | null;
  };
  scans: { latest: ScanRef | null; week_before: ScanRef | null; since_launch: ScanRef[] };
  notes: string[];
}

const pct1 = (v: number | null | undefined): string => (v == null ? "—" : `${Math.round(v * 10) / 10}%`);
const thousands = (v: number | null | undefined): string => (v == null ? "—" : `${v < 0 ? "−" : ""}${Math.round(Math.abs(v) * 1000)}k`);
/** Profit an aircraft hour, a few thousand: to a tenth of a thousand, so 9.1k to 10.0k doesn't read "9k", "10k", "▲ 0k". */
const thousands1 = (v: number | null | undefined): string => (v == null ? "—" : `${v < 0 ? "−" : ""}${(Math.round(Math.abs(v) * 10000) / 10).toFixed(1)}k`);
const whole = (v: number | null | undefined): string => (v == null ? "—" : Math.round(v).toLocaleString("en-GB"));

/** The route page's header in words: the route and its city, the airline, distance, market and the cabin it calls for,
 *  launched (date and days), departures a week each way, the types, and each cabin's fare level with this Saturday's move. */
export function storyHeader(s: RouteStory, nice: (day: string) => string) {
  const r = s.route, d = s.now.departures;
  const cabin = r.cabin.layout ? `layout ${r.cabin.layout}${r.cabin.own ? " (the route's own)" : ""}` : "no layout";
  const launched = r.launched == null ? "not flown yet"
    : `${r.launched_from === "history" ? "first flights" : "launched"} ${nice(r.launched)}${r.launched_days != null ? ` · ${r.launched_days} day${r.launched_days === 1 ? "" : "s"}` : ""}`;
  const departures = !d.out && !d.back ? "no flights in the schedule"
    : d.out === d.back ? `${d.out} a week each way` : `${d.out} a week out, ${d.back} back`;
  return {
    title: `${r.hub}–${r.dest}`,
    city: r.city ?? "",
    line: [r.airline.name, r.distance_km == null ? null : `${whole(r.distance_km)} km`, r.market?.name ?? "no market", cabin].filter(Boolean).join(" · "),
    launched,
    departures,
    types: s.now.types.map((t) => `${shortType(t.type)}${t.aircraft > 1 ? ` ×${t.aircraft}` : ""}`).join(", "),
    fares: s.now.fares.map((f) => storyFareWords(f)),
  };
}
/** A cabin's fare level with this Saturday's move: "economy 105% · up to 110%", "business 100% · hold", with " · on the
 *  fare plan" (or "· seen in the game") once the move is planned. */
export function storyFareWords(f: Pick<StoryFare, "cabin" | "level" | "move" | "new_level" | "planned" | "applied">): string {
  const m = moveWords(f);
  return `${f.cabin} ${pts(f.level)}% · ${m.text}${f.planned ? (f.applied ? " · seen in the game" : " · on the fare plan") : ""}`;
}

/** One figure of the last 7 days against the 7 before, with its arrow. */
export interface StoryChange { key: string; label: string; now: string; then: string; arrow: "up" | "down" | "same" | null; text: string }
/** The last 7 days (the week ending on the latest captured day) against the 7 before: load %, passengers, profit, profit
 *  an aircraft hour, and the economy and business fares (business only where either week has one). Without either week
 *  each change is "—". */
export function storyWeekOnWeek(s: RouteStory): { from: string | null; to: string | null; compared: boolean; rows: StoryChange[]; days: string } {
  const last = s.latest_day ? s.weeks.find((w) => w.to === s.latest_day) : undefined;
  const prevTo = s.latest_day ? dayMinus(s.latest_day, 7) : null;
  const prev = prevTo ? s.weeks.find((w) => w.to === prevTo) : undefined;
  const one = (key: string, label: string, pick: (w: StoryWeek) => number | null, fmt: (v: number | null) => string, delta: (d: number) => string): StoryChange => {
    const a = last ? pick(last) : null, b = prev ? pick(prev) : null;
    if (a == null || b == null) return { key, label, now: fmt(a), then: fmt(b), arrow: null, text: "—" };
    const dv = Math.round((a - b) * 1e6) / 1e6;
    if (Math.abs(dv) < 1e-9) return { key, label, now: fmt(a), then: fmt(b), arrow: "same", text: "= same" };
    return { key, label, now: fmt(a), then: fmt(b), arrow: dv > 0 ? "up" : "down", text: `${dv > 0 ? "▲" : "▼"} ${delta(Math.abs(dv))}` };
  };
  const fare = (v: number | null): string => (v == null ? "—" : `${whole(v)} AS$`);
  const rows = [
    one("load", "Load", (w) => w.load_pct, pct1, (d) => `${Math.round(d * 10) / 10} pt${Math.round(d * 10) / 10 === 1 ? "" : "s"}`),
    one("passengers", "Passengers", (w) => w.passengers, whole, (d) => whole(d)),
    one("profit", "Profit", (w) => w.profit, thousands, (d) => thousands(d)),
    one("per_hour", "Profit an aircraft hour", (w) => w.profit_per_hour, thousands1, (d) => thousands1(d)),
    one("eco_fare", "Economy fare", (w) => w.eco_fare, fare, (d) => fare(d)),
  ];
  if ((last?.bus_fare ?? prev?.bus_fare) != null) rows.push(one("bus_fare", "Business fare", (w) => w.bus_fare, fare, (d) => fare(d)));
  // the totals of two weeks with different days of flights (a capture missed) aren't like for like: say so
  const days = last && prev && last.days !== prev.days ? `${last.days} days with flights against ${prev.days}` : "";
  return { from: last?.from ?? null, to: last?.to ?? null, compared: !!(last && prev), rows, days };
}

// the since-launch chart: daily economy and business loads, the fare level as a step line on its own scale, and each event
export const STORY_MIN_DAYS = 14;
const KIND_WORDS: Record<StoryKind, string> = {
  launched: "launched", "frequency added": "frequency added", "frequency removed": "frequency removed", "aircraft changed": "aircraft changed",
  retimed: "retimed", fare: "fare", cabin: "cabin", rival: "rival",
};
/** An event as the list shows it: its kind and its words, "rival · Air China started here, 14 a week" ("launched" alone). */
export const eventWords = (e: Pick<StoryEvent, "kind" | "words">): string => {
  const k = KIND_WORDS[e.kind] ?? e.kind;
  return e.words === k ? k : `${k} · ${e.words}`;
};

/** Each cabin's fare level on each day given: the launch level, then each of the ladder's fare plan rows (an event with a
 *  level, not dropped) from the day it was proposed. Null for business with no ladder row of its own. */
export function levelSteps(s: RouteStory, cabin: "economy" | "business", days: readonly string[]): (number | null)[] | null {
  const rows = s.events.filter((e) => e.kind === "fare" && e.level != null && !e.dropped && (e.cabin ?? "economy") === cabin)
    .slice().sort((a, b) => (a.day < b.day ? -1 : a.day > b.day ? 1 : 0));
  if (cabin === "business" && !rows.length) return null;
  return days.map((d) => {
    let lv = s.now.launch_pct;
    for (const r of rows) if (r.day <= d) lv = r.level ?? lv;
    return lv;
  });
}

export interface StoryChartLayout {
  W: number; H: number; L: number; R: number; T: number; B: number;
  days: string[];
  grid: { y: number; label: string }[];
  rgrid: { y: number; label: string }[];
  eco: string; bus: string | null; level: string | null; levelBus: string | null;
  xLabels: { x: number; label: string }[];
  markers: { x: number; y: number; kinds: string; tip: string }[];
  cols: { x: number; w: number; tip: string }[];
}
/** The since-launch chart's layout (1120 × 300, as the profit chart's): a column a day from the first day with flights to
 *  the latest captured day; economy and business loads (0–100%, left) as lines, broken over days without flights; the fare
 *  level (right, its own scale) as a step line, economy, and business dashed when it has a ladder row of its own; each
 *  day's events as a marker on the day axis; a tip for each day. Null under 14 days with flights: the page says so. */
export function storyChartLayout(s: RouteStory, nice: (day: string) => string): StoryChartLayout | null {
  if (s.days.length < STORY_MIN_DAYS) return null;
  const first = s.days[0]?.day ?? "";
  const lastFlown = s.days[s.days.length - 1]?.day ?? first;
  const lastDay = s.latest_day && s.latest_day > lastFlown ? s.latest_day : lastFlown;
  const n = Math.round((Date.parse(lastDay + "T00:00:00Z") - Date.parse(first + "T00:00:00Z")) / 86_400_000) + 1;
  const days = Array.from({ length: n }, (_, i) => dayMinus(first, -i));
  const W = 1120, H = 300, L = 46, R = 52, T = 14, B = 46;
  const cw = (W - L - R) / n, X = (i: number) => L + (i + 0.5) * cw;
  const Y = (v: number) => T + (100 - Math.max(0, Math.min(100, v))) / 100 * (H - T - B);
  const byDay = new Map(s.days.map((d) => [d.day, d]));
  const path = (pick: (d: StoryDay) => number | null): string => {
    let out = "", open = false;
    days.forEach((day, i) => {
      const d = byDay.get(day), v = d ? pick(d) : null;
      if (v == null) { open = false; return; }
      out += `${open ? " L" : out ? " M" : "M"}${X(i).toFixed(1)},${Y(v).toFixed(1)}`;
      open = true;
    });
    return out;
  };
  const eco = path((d) => d.eco_load_pct);
  const bus = s.days.some((d) => d.bus_load_pct != null) ? path((d) => d.bus_load_pct) : null;
  const lv = levelSteps(s, "economy", days), lvb = levelSteps(s, "business", days);
  const all = [...(lv ?? []), ...(lvb ?? [])].filter((v): v is number => v != null);
  const lo = all.length ? Math.floor((Math.min(...all) - 5) / 5) * 5 : 0, hi = all.length ? Math.ceil((Math.max(...all) + 5) / 5) * 5 : 1;
  const RY = (v: number) => T + (hi - v) / (hi - lo || 1) * (H - T - B);
  const step = (vals: (number | null)[] | null): string | null => {
    if (!vals || !vals.some((v) => v != null)) return null;
    let out = "", prev: number | null = null;
    vals.forEach((v, i) => {
      if (v == null) return;
      const x0 = L + i * cw, x1 = L + (i + 1) * cw;
      if (prev == null) out += `M${x0.toFixed(1)},${RY(v).toFixed(1)}`;
      else if (prev !== v) out += ` L${x0.toFixed(1)},${RY(prev).toFixed(1)} L${x0.toFixed(1)},${RY(v).toFixed(1)}`;
      out += ` L${x1.toFixed(1)},${RY(v).toFixed(1)}`;
      prev = v;
    });
    return out;
  };
  const evOn = new Map<string, StoryEvent[]>();
  for (const e of s.events) if (e.day >= first && e.day <= lastDay) evOn.set(e.day, [...(evOn.get(e.day) ?? []), e]);
  const every = Math.max(1, Math.ceil(n / 12));
  return {
    W, H, L, R, T, B, days,
    grid: [0, 25, 50, 75, 100].map((v) => ({ y: Y(v), label: `${v}%` })),
    rgrid: all.length ? [lo, (lo + hi) / 2, hi].map((v) => ({ y: RY(v), label: `${Math.round(v * 10) / 10}%` })) : [],
    eco, bus, level: step(lv), levelBus: step(lvb),
    xLabels: days.flatMap((d, i) => (i % every === 0 || i === n - 1 ? [{ x: X(i), label: `${d.slice(8)}/${d.slice(5, 7)}` }] : [])),
    markers: days.flatMap((d, i) => {
      const ev = evOn.get(d);
      return ev ? [{ x: X(i), y: H - B + 12, kinds: [...new Set(ev.map((e) => e.kind))].join(" "), tip: `${nice(d)} · ${ev.map(eventWords).join(" · ")}` }] : [];
    }),
    cols: days.map((d, i) => {
      const x = byDay.get(d), parts = [nice(d)];
      if (x) {
        parts.push(`load ${pct1(x.load_pct)}`, `economy ${pct1(x.eco_load_pct)}`);
        if (x.bus_load_pct != null) parts.push(`business ${pct1(x.bus_load_pct)}`);
        parts.push(`${x.flights} flight${x.flights === 1 ? "" : "s"}`);
      } else parts.push("no flights");
      const e = lv?.[i], b = lvb?.[i];
      if (e != null) parts.push(`fare level ${pts(e)}%${b != null && b !== e ? `, business ${pts(b)}%` : ""}`);
      for (const ev of evOn.get(d) ?? []) parts.push(eventWords(ev));
      return { x: L + i * cw, w: cw, tip: parts.join(" · ") };
    }),
  };
}

/** Profit an aircraft hour by week, oldest first, for the bar chart (in thousands): a bar for each week with block hours. */
export function weekBars(s: RouteStory, nice: (day: string) => string): { x: string; y: number; tip: string }[] {
  return s.weeks.filter((w) => w.profit_per_hour != null).slice().reverse().map((w) => ({
    x: w.to, y: w.profit_per_hour as number,
    tip: `${nice(w.from)} to ${nice(w.to)} · ${thousands1(w.profit_per_hour)} an aircraft hour · profit ${thousands(w.profit)} over ${Math.round((w.block_hours ?? 0) * 10) / 10} block hours · ${w.flights} flights`,
  }));
}

/** The rivals on the pair in words: each rival with its departures a week and its change against the week-before scan,
 *  ours and our share, and which scans. Since 23 Oct (spec docs/specs/2026-10-23-rival-connections.md §4) each with its
 *  connecting departures and airports in a column of its own (never added to direct), the rivals that only connect after
 *  those that fly it, and a line with the connecting total; none of it when the scan has no connections worked out. */
export function rivalLines(s: RouteStory, day: (iso: string) => string) {
  const r = s.rivals;
  const change = (v: number | null): string => (v == null ? "" : v > 0 ? `▲ ${v}` : v < 0 ? `▼ ${-v}` : "=");
  const conn = r.connecting_weekly != null;
  const via = (v: readonly StoryVia[] | undefined): string => (v?.length ? `via ${v.map((x) => x.via).join(", ")}` : "");
  const row = (a: StoryRival, only: boolean) => ({
    id: a.airline_id, name: a.name, weekly: only ? "—" : String(a.weekly), change: only ? "" : change(a.change), before: only ? null : a.weekly_before,
    connecting: conn ? String(a.connecting_weekly ?? 0) : null, via: conn ? via(a.connecting_via) : "", only,
  });
  return {
    none: !r.airlines.length && !(r.connecting_only ?? []).length,
    connecting: conn,
    rows: [...r.airlines.map((a) => row(a, false)), ...(conn ? (r.connecting_only ?? []).map((a) => row(a, true)) : [])],
    connectingLine: conn ? `rivals ${r.rivals_weekly} direct · ${r.connecting_weekly} connecting a week, shown apart and never added together` : null,
    ours: `ours ${r.ours} a week${r.share != null ? `, ${pct1(r.share)} of the pair` : ""}${r.share_before != null ? ` (${pct1(r.share_before)} in the week-before scan)` : ""}`,
    scans: r.scan ? `latest scan ${day(r.scan.taken_at)}${r.week_before ? `, against ${day(r.week_before.taken_at)}` : ", the only one"}` : "no world scan yet",
  };
}

/** Our share at each scan since launch as a small line (160 × 40, 0–100%), with each point's tip. Null under two scans. */
export function shareLine(shares: readonly StoryShare[], day: (iso: string) => string): { W: number; H: number; path: string; dots: { x: number; y: number; tip: string }[] } | null {
  const shown = shares.filter((x) => x.share != null);
  if (shown.length < 2) return null;
  const W = 160, H = 40, X = (i: number) => 4 + i * (W - 8) / (shown.length - 1), Y = (v: number) => H - 4 - v / 100 * (H - 8);
  return {
    W, H,
    path: shown.map((x, i) => `${i ? "L" : "M"}${X(i).toFixed(1)},${Y(x.share as number).toFixed(1)}`).join(" "),
    dots: shown.map((x, i) => ({ x: X(i), y: Y(x.share as number), tip: `${day(x.taken_at)}: ${pct1(x.share)} (ours ${x.ours}, rivals ${x.rivals} a week)` })),
  };
}

/** The note under our share line when some points are weekly (spec docs/specs/2026-10-23-rival-pairs-history.md §3): the
 *  scans before the last month are the week's kept scan only, their full schedules archived. Null when every point is a
 *  full scan. */
export function shareWeeklyNote(shares: readonly StoryShare[], dailyFrom: string | null | undefined, day: (iso: string) => string): string | null {
  const weekly = shares.filter((x) => x.weekly).length;
  if (!weekly) return null;
  const points = `${weekly} weekly point${weekly === 1 ? "" : "s"}`;
  return dailyFrom
    ? `${points} before ${day(dailyFrom)} (one scan a week, kept after the monthly archive); every scan from then`
    : `${points} (one scan a week, kept after the monthly archive)`;
}

/** A city beyond one end of the route: its times a week onward (to) and feeding (from), and both together. */
export interface EndCity { city: string; to: number; from: number; total: number }
export interface RouteEnd { at: string; other: string; pairs: number; top: EndCity[] }
/** The connections at both ends of a route, from the planning library on the schedule the planner reads (all our
 *  airlines' flights): for each of its legs, connections.connectionsAtBothEnds (the plan card's rule: the airport's minimum
 *  connection time up to connection_max_wait_h). At each end, each city beyond it is a city pair: its times a week onward
 *  (each departure of ours landing there that makes one of the city's flights) and feeding (each departure of ours
 *  leaving there that one of the city's flights connects onto). The top 10 by the two together, then by code. */
export function routeConnections(rules: Rules, route: { id: number; hub: string; dest: string }, top = 10): RouteEnd[] {
  const legs = block.timedLegs(rules);
  const mine = legs.filter((l) => l.route_id === route.id);
  const ends = new Map<string, Map<string, { to: number; from: number }>>([[route.hub, new Map()], [route.dest, new Map()]]);
  const add = (at: string, city: string, k: "to" | "from", n: number) => {
    const m = ends.get(at);
    if (!n || !m) return;
    const c = m.get(city) ?? { to: 0, from: 0 };
    c[k] += n;
    m.set(city, c);
  };
  const cities = (xs: readonly { leg: TimedLeg }[], pick: (l: TimedLeg) => string) => [...new Set(xs.map((x) => pick(x.leg)))];
  for (const leg of mine) {
    const both = connections.connectionsAtBothEnds(rules, legs, leg);
    // onward: our flight lands at leg.dest; each of its departures that makes a flight on to the city counts once
    const onLim = connections.connectionLimits(rules, leg.dest);
    const arrivals = connections.arrivalsOf(leg);
    for (const city of cities(both.onward, (l) => l.dest)) {
      const deps = both.onward.filter((x) => x.leg.dest === city).flatMap((x) => connections.departuresOf(x.leg));
      add(leg.dest, city, "to", arrivals.filter((a) => deps.some((d) => connections.isConnection(time.mod(d - a, time.WEEK), onLim))).length);
    }
    // feeding: our flight leaves leg.origin; each of its departures that a flight from the city connects onto counts once
    const feedLim = connections.connectionLimits(rules, leg.origin);
    const departures = connections.departuresOf(leg);
    for (const city of cities(both.feeders, (l) => l.origin)) {
      const arrs = both.feeders.filter((x) => x.leg.origin === city).flatMap((x) => connections.arrivalsOf(x.leg));
      add(leg.origin, city, "from", departures.filter((d) => arrs.some((a) => connections.isConnection(time.mod(d - a, time.WEEK), feedLim))).length);
    }
  }
  return [[route.hub, route.dest], [route.dest, route.hub]].map(([at = "", other = ""]) => {
    const rows = [...(ends.get(at) ?? new Map<string, { to: number; from: number }>())].map(([city, c]) => ({ city, to: c.to, from: c.from, total: c.to + c.from }))
      .sort((a, b) => b.total - a.total || (a.city < b.city ? -1 : a.city > b.city ? 1 : 0));
    return { at, other, pairs: rows.length, top: rows.slice(0, top) };
  });
}

/** The route page's boards, top to bottom (the header and the week's comparison above them aren't boards). */
export const ROUTE_BOARDS = ["Since launch", "Profit an aircraft hour", "Events", "Rivals on the pair", "Connections"] as const;
export type RouteBoardKey = (typeof ROUTE_BOARDS)[number];
/** The route in the address, "JFK-ORD", as its two codes; null when it isn't two codes. */
export function parseRouteKey(key: string | undefined): { hub: string; dest: string } | null {
  let k: string;
  try { k = decodeURIComponent(key ?? ""); } catch { return null; }
  const m = /^([A-Z0-9]{3,4})-([A-Z0-9]{3,4})$/.exec(k.toUpperCase());
  return m ? { hub: m[1] as string, dest: m[2] as string } : null;
}
