// Review's logic, kept apart from its screen so the unit tests can run it (decision #18, build pull request 10; spec
// docs/specs/2026-10-14-review.md). Every money figure comes from the database's figures (design §8: airline_cards(),
// airline_profit(), cash_forecast(), route_profit(), aircraft_profit(), fare_changes(), fare_plan_status(), cash_log());
// what is here only words them as the old Review does (web/planner/index.html: renderFinance, groupOverviewHtml,
// finStats' card, barChart, spark, fcNext, forecastBoard, routeProfitBoard, farePlanBoard, cashEntryHtml, manualLoadsHtml,
// parseLoadPaste, lfPastePreview and reviewClick), lays out its charts, reads a paste from the game, and builds each
// save's rows exactly as the old planner writes them.
import type { Change, Values } from "../../data/save";
import { shortType } from "../../ui/aircraftNames";
import { dayDiff } from "../../ui/dates";

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
}
export interface FarePlanAnswer { plan: PlanRow[]; fares: { route_id: number; hub: string; dest: string; day: string; fare: number }[] }
export interface CashToday {
  day: string;
  shown_cash: number | null;
  shown_fixed: number | null;
  stored_cash: number | null;
  stored_fixed: number | null;
  captured_cash: number | null;
  captured_fixed: number | null;
  entry: { cash: number | null; fixed_next7: number | null; updated_at: string } | null;
}
export interface CashLogAirline { airline_id: number; code: string | null; name: string; days: { day: string; cash: number; fixed: number | null }[]; today: CashToday }
export interface CashLog { today: string; airlines: CashLogAirline[] }

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

// ---------- the fare plan (farePlanBoard) and "+ fare plan"
export function planWords(p: PlanRow, nice: (day: string) => string) {
  return {
    route: `${p.hub ?? ""}–${p.dest ?? ""}`,
    cls: p.cabin_class || "economy",
    change: `${(p.change_pct ?? 0) > 0 ? "+" : ""}${p.change_pct}%`,
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

// ---------- cash and fixed costs for today (cashEntryHtml and its save, as the old planner's adapter writes them)
/** A typed box: the number in it, or null when it's empty or not a number (the old parseFloat, commas dropped). */
export function typedNumber(s: string | null | undefined): number | null {
  const v = parseFloat(String(s ?? "").replace(/,/g, ""));
  return Number.isNaN(v) ? null : v;
}
/** What a box shows to begin with: the figure as the old planner held it, or empty. */
export const boxValue = (v: number | null | undefined): string => (v == null ? "" : String(v));

/** Save cash and fixed costs: for each airline whose figure changed from what the tables hold, a cash_entries row keeps a
 *  figure only where it differs from the capture's (rounded as the planner rounds), in AS$; the row goes once both agree
 *  again (the old planner's planner_apply_money). One action. */
export function cashChanges(worldId: number, rows: readonly { airline_id: number; today: CashToday; cash: string; fixed: string }[], nowIso: string): Change[] {
  const out: Change[] = [];
  const same = (a: number | null | undefined, b: number | null | undefined) => (a ?? null) === (b ?? null);
  const asd = (v: number | null, cap: number | null) => (v != null && v !== cap && Math.abs(v) < 1_000_000 ? Math.round(v * 1_000_000 * 100) / 100 : null);
  for (const r of rows) {
    const t = r.today;
    const stCash = typedNumber(r.cash) ?? t.shown_cash, stFixed = typedNumber(r.fixed) ?? t.shown_fixed;
    if (same(stCash, t.stored_cash) && same(stFixed, t.stored_fixed)) continue;
    const cash = asd(stCash, t.captured_cash), fixed = asd(stFixed, t.captured_fixed);
    const key = { airline_id: r.airline_id, day: t.day };
    if (cash != null || fixed != null) {
      if (!t.entry) {
        out.push({ table: "cash_entries", op: "insert", values: { world_id: worldId, airline_id: r.airline_id, day: t.day, cash, fixed_next7: fixed, entered_at: nowIso } });
      } else if (!same(t.entry.cash, cash) || !same(t.entry.fixed_next7, fixed)) {
        out.push({ table: "cash_entries", op: "update", key, base: t.entry.updated_at, values: { cash, fixed_next7: fixed, entered_at: nowIso } });
      }
    } else if (t.entry) {
      out.push({ table: "cash_entries", op: "delete", key, base: t.entry.updated_at });
    }
  }
  return out;
}

/** The nightly log: every reported day across our airlines, newest first, with each airline's cash and fixed costs. */
export function nightlyLog(log: CashLog): { day: string; cells: ({ cash: string; fixed: string | null } | null)[] }[] {
  const days = [...new Set(log.airlines.flatMap((a) => a.days.map((d) => d.day)))].sort().reverse();
  return days.map((day) => ({
    day,
    cells: log.airlines.map((a) => {
      const p = a.days.find((d) => d.day === day);
      return p ? { cash: p.cash.toFixed(2), fixed: p.fixed != null ? p.fixed.toFixed(2) : null } : null;
    }),
  }));
}
/** An airline's short name, as the old entry boxes and log head it: its first word. */
export const firstWord = (name: string): string => name.split(" ")[0] ?? name;

// ---------- loads by hand (manualLoadsHtml, parseLoadPaste, lfPastePreview), saved through planner_save() into load_entries
// and load_days (since the clean-up, build pull request 14; until then through the old planner's save_loads())
/** A loads day as the planner holds it (loads_by_day()): the flights' economy loads keyed "Airline|number" (captured or
 *  typed, the latest wins), whether it is complete, whether a capture reached it (source "capture"), when it was last saved
 *  by hand (savedAt, ms); and the typed rows behind it, with their updated_at, the base a save changes them from. */
export interface LoadsDay {
  done: boolean;
  f: Record<string, number>;
  source?: string;
  savedAt?: number;
  entries?: { airline_id: number; flight_no: number; eco_pct: number | null; updated_at: string }[];
  flags?: { done: boolean; saved_at_ms: number | null; updated_at: string } | null;
}
/** A day's change as the old planner's save sent it: the whole day's flights (f), or single flights set and cleared, and
 *  the day's flags. */
export interface DayPatch { f?: Record<string, number>; set?: Record<string, number>; del?: string[]; done?: boolean; savedAt?: number }
/** The day after the change, as the old save_loads() merged it: f replaces the day's flights, or set and del change single
 *  ones; done and savedAt as given, else as they were. */
export function mergeDay(got: LoadsDay | null, p: DayPatch): { f: Record<string, number>; done: boolean; savedAt?: number } {
  let f: Record<string, number>;
  if (p.f !== undefined) f = { ...p.f };
  else {
    f = { ...(got?.f ?? {}), ...(p.set ?? {}) };
    for (const k of p.del ?? []) delete f[k];
  }
  const savedAt = p.savedAt !== undefined ? p.savedAt : got?.savedAt;
  return { f, done: p.done !== undefined ? p.done : got?.done ?? false, ...(savedAt !== undefined ? { savedAt } : {}) };
}
/** The rows a day's change writes, as the old save_loads() wrote them (private.loads_mirror_days): a load_entries row for
 *  each flight whose load now differs from the day as it stood (null where it's cleared), and the day's load_days row
 *  when its complete mark or its saved time changed, each stamped as entered now. A row there already is changed from its
 *  updated_at; otherwise it's added. airlines: our airlines' names (the key's first part) to their ids. */
export function loadsChanges(worldId: number, day: string, got: LoadsDay | null, p: DayPatch, airlines: ReadonlyMap<string, number>, nowIso: string): Change[] {
  const v = mergeDay(got, p);
  const gotF = got?.f ?? {};
  const out: Change[] = [];
  for (const k of [...new Set([...Object.keys(gotF), ...Object.keys(v.f)])].sort()) {
    const tv = v.f[k], gv = gotF[k];
    if (tv === gv) continue;
    const [name, no] = [k.slice(0, k.lastIndexOf("|")), Number(k.slice(k.lastIndexOf("|") + 1))];
    const airline = airlines.get(name);
    if (airline === undefined || !Number.isInteger(no) || no < 0 || no > 2000000000) continue;
    const eco = typeof tv === "number" && Number.isFinite(tv) && Math.abs(tv) < 10000 ? tv : null;
    const row = got?.entries?.find((e) => e.airline_id === airline && e.flight_no === no);
    out.push(row
      ? { table: "load_entries", op: "update", key: { airline_id: airline, game_date: day, flight_no: no }, base: row.updated_at, values: { eco_pct: eco, entered_at: nowIso } }
      : { table: "load_entries", op: "insert", values: { world_id: worldId, airline_id: airline, game_date: day, flight_no: no, eco_pct: eco, entered_at: nowIso } });
  }
  if (v.done !== (got?.done ?? false) || v.savedAt !== got?.savedAt) {
    const values: Values = { done: v.done, saved_at_ms: v.savedAt ?? null, entered_at: nowIso };
    out.push(got?.flags
      ? { table: "load_days", op: "update", key: { world_id: worldId, game_date: day }, base: got.flags.updated_at, values }
      : { table: "load_days", op: "insert", values: { world_id: worldId, game_date: day, ...values } });
  }
  return out;
}
/** The day's status after its date. */
export const dayStatus = (d: LoadsDay | null): string => (d?.done ? (d.source === "capture" ? "captured" : "entered by hand") : "nothing yet");
/** An airline's box: its flights under 95%, lowest first, "flight load" pairs. */
export function underList(d: LoadsDay | null, airline: string): string {
  return Object.entries(d?.f ?? {}).filter(([k, v]) => k.startsWith(airline + "|") && +v < 95).sort((x, y) => x[1] - y[1])
    .map(([k, v]) => k.split("|")[1] + " " + v).join(", ");
}

/** The typed boxes read as the old lfsave reads them: number then load, pairs, an airline prefix ("AW") allowed, each load
 *  kept to 0 to 94; flights that don't operate that day are named (they're saved, but won't count). */
export function typedLoads(boxes: readonly { airline: string; text: string }[], valid: ReadonlySet<string>): { f: Record<string, number>; unknown: string[] } {
  const f: Record<string, number> = {}, unknown: string[] = [];
  for (const b of boxes) {
    const toks = (b.text || "").toUpperCase().replace(/[A-Z]{2}\s*(?=\d)/g, "").replace(/%/g, "").split(/[^0-9.]+/).filter(Boolean).map(Number);
    for (let i = 0; i + 1 < toks.length; i += 2) {
      const no = String(Math.round(toks[i] as number)), val = toks[i + 1] as number, key = b.airline + "|" + no;
      if (!valid.has(key)) unknown.push(firstWord(b.airline) + " " + no);
      f[key] = Math.min(94, Math.max(0, Math.round(val)));
    }
  }
  return { f, unknown };
}
/** The typed day's change: that day's flights (replacing them), complete, saved now. */
export const typedSave = (day: string, f: Record<string, number>, nowMs: number): Record<string, DayPatch> => ({ [day]: { f, done: true, savedAt: nowMs } });

export interface PastedLoad { airline: string; no: string; tail: string; from: string; to: string; date: string; dep: string; pax: number; seats: number; pct: number; key: string }
/** The game's load table pasted (parseLoadPaste): each row from its flight code (an airline of ours by its code), tail,
 *  airports, local departure "DD.MM. HH:MM" and each cabin's price then "pax / seats"; the load is economy, business and
 *  first together (no cargo). A date more than 60 days after today is last year's. codes: our airlines' codes → names. */
export function parseLoadPaste(text: string, codes: ReadonlyMap<string, string>, today: string): PastedLoad[] {
  const toks = String(text || "").split(/\t|\r?\n/).map((x) => x.trim()).filter(Boolean);
  const out: PastedLoad[] = [];
  const yNow = +today.slice(0, 4);
  for (let i = 0; i < toks.length; i++) {
    const m = /^([A-Z0-9]{2})\s*(\d{1,4})$/.exec(toks[i] as string);
    const airline = m ? codes.get(m[1] as string) : undefined;
    if (!m || !airline) continue;
    const tail = toks[i + 1] || "", from = toks[i + 2] || "", dm = /^(\d{2})\.(\d{2})\.?\s+(\d{2}):(\d{2})/.exec(toks[i + 3] || ""), to = toks[i + 4] || "";
    if (!dm || !/^[A-Z0-9]{3}$/.test(from) || !/^[A-Z0-9]{3}$/.test(to)) continue;
    let date = `${yNow}-${dm[2]}-${dm[1]}`;
    if (dayDiff(today, date) > 60) date = `${yNow - 1}-${dm[2]}-${dm[1]}`;
    let j = i + 6;
    const cab: ({ pax: number; seats: number } | null)[] = [];
    for (let c = 0; c < 4 && j < toks.length; c++) {
      const price = toks[j++];
      const pax = toks[j++] || "";
      const pm = /^([\d,]+)\s*\/\s*([\d,]+)/.exec(pax);
      cab.push(pm ? { pax: +(pm[1] as string).replace(/,/g, ""), seats: +(pm[2] as string).replace(/,/g, "") } : null);
      if (price === undefined) break;
    }
    const pcs = cab.slice(0, 3).filter((c): c is { pax: number; seats: number } => !!c);
    const pax = pcs.reduce((a, c) => a + c.pax, 0), seats = pcs.reduce((a, c) => a + c.seats, 0);
    if (!seats) continue;
    const no = String(+(m[2] as string));
    out.push({ airline, no, tail, from, to, date, dep: dm[3] + ":" + dm[4], pax, seats, pct: Math.round(pax / seats * 100), key: airline + "|" + no });
    i = j - 1;
  }
  return out;
}
/** A pasted load's pill, as the preview colours it. */
export const pastePill = (pct: number): "ok" | "warn" | "orange" | "bad" => (pct >= 95 ? "ok" : pct >= 85 ? "warn" : pct >= 70 ? "orange" : "bad");
/** The pasted loads saved (lfpaste-save): each day's flights under 95% set and those at 95% or more cleared, and the days
 *  ticked marked complete. */
export function pasteSaves(parsed: readonly PastedLoad[], marked: readonly string[], nowMs: number): Record<string, DayPatch> {
  const send: Record<string, { set: Record<string, number>; del: string[]; done?: boolean; savedAt?: number }> = {};
  const patch = (d: string) => (send[d] ??= { set: {}, del: [] });
  for (const x of parsed) {
    const p = patch(x.date);
    if (x.pct < 95) p.set[x.key] = x.pct;
    else p.del.push(x.key);
  }
  for (const d of marked) Object.assign(patch(d), { done: true, savedAt: nowMs });
  return send;
}

// ---------- the fold
export const BOARDS = ["The group today", "Profit", "Cash, next 14 days", "Route profit", "Fare plan", "Manual entry"] as const;
export type BoardKey = (typeof BOARDS)[number];
