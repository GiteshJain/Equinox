// Performance's logic (spec docs/specs/2026-10-20-today-performance-systems.md; Review's until 20 Oct, decision #18, build
// pull request 10, spec docs/specs/2026-10-14-review.md), kept apart from its screen so the unit tests can run it. Every
// money figure comes from the database's figures (design §8: airline_cards(), airline_profit(), cash_forecast(),
// route_profit(), aircraft_profit(), fare_changes(), fare_plan_status()); what is here only words them as the old Review
// does (web/planner/index.html: renderFinance, groupOverviewHtml, finStats' card, barChart, spark, fcNext,
// forecastBoard, routeProfitBoard, farePlanBoard and reviewClick), lays out its charts, builds the fare plan's rows exactly
// as the old planner writes them, and sets each scorecard's figures against the same day last week from the daily
// history (airline_days). Manual entry's logic moved to Systems (screens/systems/model.ts) with its board.
import type { Change } from "../../data/save";
import { shortType } from "../../ui/aircraftNames";

// ---------- the database's answers
export interface NextOrder { when: "needs" | "now" | "later" | "not within 14 days"; missing?: string; types?: string[]; type?: string; safe_from?: string }
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

/** The card's "Next order": what's missing, what can be ordered now (the two dearest), or the first safe day. */
export function nextOrderWords(n: NextOrder | null | undefined): CardWords["next"] {
  if (!n || n.when === "needs") return { text: `needs ${n?.missing || "a capture"}`, kind: "dim" };
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
/** The old barChart's layout: 1120 × 260, a bar per interval, the zero line, gridlines at a nice step, the average. */
export function barLayout(pts: readonly { x: string; y: number; tip: string }[], avg: number | null): BarLayout {
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
  for (let v = lo; v <= hi + 1e-9; v += step) grid.push({ y: Y(v), v, zero: Math.abs(v) < 1e-9, label: `${+v.toFixed(2)}M` });
  const bars = pts.map((p, i) => {
    const y0 = Y(0), y1 = Y(p.y);
    return { x: X(i) - bw / 2, y: Math.min(y0, y1), w: bw, h: Math.max(1, Math.abs(y1 - y0)), neg: p.y < 0, hitX: X(i) - bw / 2 - 4, hitW: bw + 8,
      label: `${p.x.slice(8)}/${p.x.slice(5, 7)}`, tip: p.tip };
  });
  return { W, H, L, R, T, B, grid, bars, avg: avg == null ? null : { y: Y(avg), text: `average ${avg >= 0 ? "+" : "−"}${Math.abs(avg).toFixed(2)}M a day` } };
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

export interface ScatterLayout {
  W: number; H: number; pl: number; pr: number; pb: number;
  yTicks: { y: number; label: string }[]; xTicks: { x: number; label: string }[]; zeroY: number | null;
  dots: { x: number; y: number; r: number; color: string; title: string }[];
  labels: { x: number; y: number; text: string }[];
}
/** The old rpScatter: economy load against profit a flight, bubble size flights a week, colour the mark. Null without loads. */
export function scatterLayout(routes: readonly RouteRow[]): ScatterLayout | null {
  const pts = routes.filter((r) => r.economy != null);
  if (!pts.length) return null;
  const W = 460, H = 240, pl = 48, pr = 14, pt = 12, pb = 32, ys = pts.map((r) => r.profit_per_flight * 1000);
  const x0 = Math.min(40, Math.floor(Math.min(...pts.map((r) => r.economy as number)) / 10) * 10), x1 = 100;
  const y0 = Math.min(0, Math.min(...ys)), y1 = Math.max(1, Math.max(...ys) * 1.12);
  const X = (v: number) => pl + (v - x0) / (x1 - x0) * (W - pl - pr), Y = (v: number) => H - pb - (v - y0) / (y1 - y0) * (H - pt - pb);
  const maxW = Math.max(1, ...pts.map((r) => r.flights_week || 1));
  const tx: number[] = [];
  for (let v = x0; v <= 100; v += 10) tx.push(v);
  const key = (r: RouteRow) => `${r.hub}–${r.dest}`;
  const lab = new Set([...pts].sort((a, b) => b.profit_week - a.profit_week).slice(0, 4).concat(pts.filter((r) => r.mark === "losing")).map(key));
  return {
    W, H, pl, pr, pb,
    yTicks: [0, 1, 2, 3, 4].map((i) => y0 + (y1 - y0) * i / 4).map((v) => ({ y: Y(v), label: `${Math.round(v)}k` })),
    xTicks: tx.map((v) => ({ x: X(v), label: `${v}%` })),
    zeroY: y0 < 0 ? Y(0) : null,
    dots: pts.map((r) => ({ x: X(r.economy as number), y: Y(r.profit_per_flight * 1000), r: 4 + 10 * Math.sqrt((r.flights_week || 1) / maxW), color: MARKS[r.mark].color,
      title: `${key(r)} · economy ${Math.round(r.economy as number)}% · ${Math.round(r.profit_per_flight * 1000)}k a flight · ${r.flights_week} flights a week · ${MARKS[r.mark].label}` })),
    labels: pts.filter((r) => lab.has(key(r))).map((r) => ({ x: X(r.economy as number) - 6, y: Y(r.profit_per_flight * 1000) - 9, text: key(r) })),
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
export type LadderCabin = "economy" | "business";
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
  moves: { up: number; hold: number; down: number };
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
/** This Saturday's moves in one line: "12 up, 30 hold, 2 down". */
export const ladderLine = (m: LadderAnswer["moves"]): string => `${m.up} up, ${m.hold} hold, ${m.down} down`;
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
export function moveWords(r: Pick<LadderRoute, "move" | "new_level">): { text: string; kind: "up" | "down" | "hold" } {
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
/** Put on the fare plan: one insert per route and cabin the database marks to_plan (each level that changes, and each
 *  hold that follows a step down), all in one planner_save() call. The level and the move are the ladder's; the fare
 *  then is the latest captured fare in that cabin (fare_plan_status() ticks a row off when the captured fare moves by
 *  its change, within 1%); proposed on the UTC day, the day the database's week is counted in. */
export function ladderPlanChanges(x: { worldId: number; airlineId: number; routes: readonly LadderRoute[]; utcDay: string; nowMs: number }): Change[] {
  return x.routes.filter((r) => r.to_plan).map((r, i) => ({ table: "fare_plan", op: "insert", values: {
    world_id: x.worldId, airline_id: x.airlineId, route_id: r.route_id, legacy_key: `fl${x.nowMs.toString(36)}-${i}`, cabin_class: r.cabin,
    change_pct: r.change_pct ?? 0, fare_from: r.latest_fare == null ? null : Math.round(r.latest_fare * 100) / 100, proposed_on: x.utcDay,
    status: "planned", reason: r.reason, level_pct: r.new_level, ladder_move: r.move } }));
}
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
export const BOARDS = ["Profit", "Cash, next 14 days", "Route profit", "Fare plan"] as const;
export type BoardKey = (typeof BOARDS)[number];
export const GROUP_BOARDS = ["Fare ladder", "The group today", "Growth signals", "Main hubs", "Flights by day"] as const;
export type GroupBoardKey = (typeof GROUP_BOARDS)[number];
