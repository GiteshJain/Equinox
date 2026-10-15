// The Check screen's logic (decision #18, build pull request 9; spec docs/specs/2026-10-13-check.md): how each board words
// what the database's figures and the planning library answer, as the old planner's renderReview words it (captureBoard,
// growthBoard and hubProgressHtml, the aircraft checks, cabinsBoard, renderGameCheck and gcDetail, the daily load report
// and capLine), the load report's summary, and every action as the rows of one planner_save() call: mark checked, log a
// refit, keep a cabin as is and show it again, log an order under the rotation, fix one or every difference from the game,
// and add a flight from the game (the old importFlight, through Tails' filing). No screen code, so the unit tests run it.
import { cabins, checks, frequency, game, growth, loadReport, time, type CabinFit, type DayFlight, type GameFlight, type GameIssue, type ImportCandidate, type Move, type Rules } from "@rules";
import type { Change, Values } from "../../data/save";
import type { AirportInfo, MarketRow, RouteRow } from "../routes/model";
import { filingChanges, withAirports, type CardLeg, type PlanCardRow, type TailAircraft } from "../tails/model";
import type { BackupRun, CaptureAirline, CapturedLoad, CapturePages, HandLoads, HubProgressAirline, LegNow } from "./reads";

/** One of our airlines, as the screen names it. */
export interface CheckAirline { id: number; code: string | null; name: string; color: string | null; game_id: number | null }

// ---------- the boards, in the old Check's order: each folds open and shut by its title
export const BOARDS = ["Capture", "Growth", "Aircraft checks", "Cabins", "Game check", "Daily load report"] as const;
export type BoardKey = (typeof BOARDS)[number];
/** The boards shown: Aircraft checks only while the checks are on for one of our airlines (aircraft_check_after_days
 *  above 0, the library's checks.on; spec docs/specs/2026-10-15-aircraft-checks-off.md). */
export function shownBoards(rules: Rules, airlineIds: readonly number[]): readonly BoardKey[] {
  return airlineIds.some((id) => checks.on(rules, id)) ? BOARDS : BOARDS.filter((k) => k !== "Aircraft checks");
}
/** The line under Check's title: aircraft checks named only while their board is shown. */
export const checkSubtitle = (boards: readonly BoardKey[]): string =>
  `Last night's capture, ${boards.includes("Aircraft checks") ? "aircraft checks, " : ""}growth signals, Game check and the daily load report.`;

// ---------- the load report's day, in the address (?day=YYYY-MM-DD); today (UTC) without one, as the old planner started
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
export function parseDay(search: string, todayUtc: string): string {
  const d = new URLSearchParams(search).get("day") ?? "";
  return DAY_RE.test(d) && Number.isFinite(Date.parse(d + "T00:00:00Z")) ? d : todayUtc;
}
/** A day n days after (or before) another, as the old planner's ‹ and › move it. */
export function moveDay(day: string, n: number): string {
  return new Date(Date.parse(day + "T00:00:00Z") + n * 86_400_000).toISOString().slice(0, 10);
}
/** The UTC day of a moment (the old ui.lfDate's first value: the report pulled today completes today's departures). */
export const utcToday = (now: Date): string => now.toISOString().slice(0, 10);

// ---------- Capture
/** The capture's five pages, in the old board's order, with its names for them. */
export const CAPTURE_KINDS: readonly (readonly [string, string])[] = [["loads", "Loads"], ["statement", "Statement"], ["events", "Events"], ["pnl", "Income"], ["balance", "Balance"]];
/** A page's cell: today's time, else yesterday's (dim), else a dash. */
export function captureCell(p: CapturePages | undefined): { text: string; dim: boolean } {
  if (p?.today) return { text: p.today.slice(11, 16), dim: false };
  if (p?.yesterday) return { text: "yesterday " + p.yesterday.slice(11, 16), dim: true };
  return { text: "—", dim: true };
}
/** The airline's line for today: complete, missing some pages, or not captured. */
export function captureStatus(a: Pick<CaptureAirline, "missing">): { cls: "ok" | "warn"; text: string } {
  const label = (k: string) => CAPTURE_KINDS.find((x) => x[0] === k)?.[1] ?? k;
  if (a.missing.length === CAPTURE_KINDS.length) return { cls: "warn", text: "not captured" };
  if (a.missing.length) return { cls: "warn", text: "missing " + a.missing.map(label).join(", ") };
  return { cls: "ok", text: "complete" };
}
/** The line under Capture: last night's backup, from the backup job's own report (none when it couldn't be read). */
export function backupWords(runs: readonly BackupRun[] | undefined, niceDate: (d: string) => string): { ok: boolean | null; text: string } | null {
  if (!runs) return null;
  const b = runs.find((x) => x.kind !== "test");
  if (!b) return { ok: null, text: "Backup: no copy yet. The first runs tonight." };
  const when = `${niceDate(String(b.ran_at).slice(0, 10))} ${String(b.ran_at).slice(11, 16)} UTC`;
  return b.ok
    ? { ok: true, text: `Backup: copied ${when} · ${b.tables ?? "?"} tables, ${b.rows != null ? Number(b.rows).toLocaleString("en-US") : "?"} rows, ${b.files ?? "?"} files · restore check passed` }
    : { ok: false, text: `${when} · ${String(b.note ?? "").slice(0, 200)}` };
}

// ---------- Growth
/** The rotation's moves in the old planner's words. */
export const MOVES: Readonly<Record<Move, string>> = { big: "Big market", freq: "Frequency", feeder: "Smaller feeder" };
export const MOVE_BUTTONS: Readonly<Record<Move, string>> = { big: "Big", freq: "Frequency", feeder: "Feeder" };
export const movePill = (m: Move): "warn" | "ok" | "mute" => (m === "big" ? "warn" : m === "freq" ? "ok" : "mute");
/** The rotation and hubs first in words (the old SPEND_ORDER), from the moves and hub_progress()'s target and exemptions. */
export function spendOrder(target: number, exempt: readonly string[]): string {
  return `each airline rotates its orders: ${growth.CYCLE.map((m) => MOVES[m].toLowerCase()).join(" → ")} → repeat · opening a new base counts as a big-market move, `
    + `once the main hub reaches ${target} weekly departures${exempt.length ? ` (${exempt.join(", ")} exempt)` : ""}`;
}

export interface HubRow { airline_id: number; name: string; hub: string; departures: number; planned: number; target: number; width: string; pend: string; pct: number }
/** Main hubs towards their weekly target: every airline with a main hub that isn't exempt, in the airlines' order. */
export function hubRows(progress: readonly HubProgressAirline[], name: (id: number) => string): HubRow[] {
  return progress.filter((x) => !x.exempt && x.main_hub).map((x) => {
    const dep = x.departures ?? 0, add = x.planned ?? 0, target = x.target || 1;
    const a = Math.min(100, dep / target * 100), b = Math.min(100 - a, add / target * 100);
    return { airline_id: x.airline_id, name: name(x.airline_id), hub: x.main_hub as string, departures: dep, planned: add, target: x.target, width: a.toFixed(1) + "%", pend: b.toFixed(1) + "%", pct: Math.round(dep / target * 100) };
  });
}
/** Money in thousands, as the old k(): "+120k", "−45k". */
export const kWords = (v: number): string => (v >= 0 ? "+" : "−") + Math.round(Math.abs(v) * 1000) + "k";
/** A week's profit in millions: "+1.20M". */
export const weekWords = (v: number): string => (v >= 0 ? "+" : "−") + Math.abs(v).toFixed(2) + "M";
export const pctWords = (v: number | null | undefined): string => (v == null ? "—" : Math.round(v) + "%");
/** Round trips a day as the old list writes them: "2×", "1.4×". */
export const perDayWords = (x: number): string => (x % 1 ? x.toFixed(1) : String(x)) + "×";
/** When an order queue runs dry, in UTC: "10-14 05:53". */
export const runsDryWords = (ms: number): string => new Date(ms).toISOString().slice(5, 16).replace("T", " ");
/** How soon: "now" once past, else "in 12 h". */
export const soonWords = (hours: number): string => (hours < 0 ? "now" : "in " + Math.max(0, Math.round(hours)) + " h");
/** A bank's departure "HH:MM". */
export const H = (m: number): string => time.clock(m);

// ---------- Aircraft checks
/** Aircraft by the day their check comes up, in the checks' order. */
export function upcomingByDay(list: readonly { due: string; registration: string }[]): [string, string[]][] {
  const by = new Map<string, string[]>();
  for (const c of list) by.set(c.due, [...(by.get(c.due) ?? []), c.registration]);
  return [...by].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
}
/** The order the old checks listed an aircraft's load-pattern pills in: the routes as the load window's days first show
 *  them, from two days ahead backwards, each day's departures by time (the old patterns() met them in that order). */
export function patternRanks(rules: Rules, today: string, windowDays: number): Map<number, number> {
  const rank = new Map<number, number>();
  for (let i = 1; i <= windowDays; i++) {
    for (const f of loadReport.flightsOn(rules, moveDay(today, 2 - i + 1))) if (!rank.has(f.route_id)) rank.set(f.route_id, rank.size);
  }
  return rank;
}
/** A load pattern's pill on a check: its route, and its share of departures at 95%+. */
export function patternPill(p: { hub: string; dest: string; departures: number; full: number; mark: string }): { cls: string; text: string } {
  return {
    cls: p.mark === "cut" ? "bad" : p.mark === "watch" ? "warn" : p.mark === "add" ? "ok" : "mute",
    text: `${p.hub}–${p.dest}: ${p.departures ? Math.round(p.full / p.departures * 100) : 0}% of departures 95%+`,
  };
}

// ---------- Cabins
/** The cabin it has, as the board shows it: its layout's cabin, else its layout's code, else a dash. */
export const haveWords = (x: Pick<CabinFit, "have" | "have_code">): string => x.have || x.have_code || "—";
export const mixWords = (x: Pick<CabinFit, "mix">): string => x.mix.map((m) => `${m.cabin} ${m.pct}%`).join(" · ");
/** A refit's cost in millions, as the old note writes it ("0.2M"). */
export const costWords = (cost: number): string => `${Number((cost / 1_000_000).toFixed(4))}M`;
/** The kept-as-is key the old planner used: "registration|cabin". */
export const keepKey = (x: Pick<CabinFit, "registration" | "want">): string => `${x.registration}|${x.want}`;

// ---------- Game check
/** One airline's result: the game's flights compared, or why it couldn't be checked. */
export type GameResult = { error: string } | { flights: GameFlight[] };
/** What the airline's row says: how many in the game and the planner, the differences, how many can be fixed, and the
 *  flights to add. */
export function gameSummary(c: { issues: readonly GameIssue[]; in_game: number; in_planner: number }, cands: readonly ImportCandidate[]) {
  const n = c.issues.length, nf = c.issues.filter((i) => i.fix).length, nc = cands.length;
  return {
    counts: `${c.in_game} flights in the game · ${c.in_planner} in the planner`,
    pill: n ? { cls: "bad", text: `${n} difference${n === 1 ? "" : "s"}` } : { cls: "ok", text: "everything matches" },
    fixAll: nf ? `Fix ${nf === n ? "all" : nf} from the game` : null,
    review: n || nc ? `Review ${n ? n + " difference" + (n === 1 ? "" : "s") : ""}${n && nc ? " and " : ""}${nc ? nc + " flight" + (nc === 1 ? "" : "s") + " to add" : ""}` : null,
  };
}
/** "no link yet for X, Y (add in Reference)", for our airlines without a game link. */
export const noLinkWords = (names: readonly string[]): string => (names.length ? ` · no link yet for ${names.join(", ")} (add in Reference)` : "");
/** The time a check finished, as the old toLocaleTimeString(hour, minute) shows it. */
export const checkedAtWords = (at: Date, locale?: string): string => "Last checked " + at.toLocaleTimeString(locale ?? [], { hour: "2-digit", minute: "2-digit" });

// ---------- the daily load report
/** A flight's key in the day's loads: its airline and number. */
export const loadKey = (airlineName: string, no: number | string): string => `${airlineName}|${no}`;
/** The day's captured loads by airline and flight number (the number from the code, "KF 1048" → 1048), the last one kept
 *  where a number shows twice, as the old CAP.loads keeps it. */
export function loadsByFlight(rows: readonly CapturedLoad[], day: string): Map<string, CapturedLoad> {
  const m = new Map<string, CapturedLoad>();
  for (const r of rows) if (String(r.flight_date).slice(0, 10) === day) m.set(loadKey(r.airline ?? "", String(r.code ?? "").replace(/^\D+/, "").trim()), r);
  return m;
}
/** The old planner's +x: a missing figure counts as 0, as its averages and counts take it. */
const plus = (v: number | null | undefined): number => Number(v ?? 0);
const avgOf = (arr: readonly number[]): number | null => (arr.length ? arr.reduce((x, y) => x + y, 0) / arr.length : null);
const bucket = (v: number): 70 | 85 | 95 => (v < 70 ? 70 : v < 85 ? 85 : 95);

export type DaySummary =
  | { kind: "captured"; departures: number; captured: number; economy: number | null; business: number | null; cargo: number | null; soldOut: number; under85: number }
  | { kind: "hand"; departures: number; under95: number; under85: number; under70: number }
  | { kind: "none"; departures: number };

/** The day's summary (the old report's line): from the captured loads when any flight was captured, else from the loads
 *  typed by hand once the day was marked complete (under 95, 85 and 70%), else not captured. */
export function daySummary(flights: readonly DayFlight[], loadOf: (f: DayFlight) => CapturedLoad | undefined, hand: HandLoads | undefined): DaySummary {
  const capd = flights.map(loadOf).filter((x): x is CapturedLoad => !!x);
  if (capd.length) {
    const nums = (k: "eco" | "bus" | "cargo") => capd.map((c) => plus(c[k])).filter((v) => !Number.isNaN(v));
    return {
      kind: "captured", departures: flights.length, captured: capd.length, economy: avgOf(nums("eco")), business: avgOf(nums("bus")), cargo: avgOf(nums("cargo")),
      soldOut: capd.filter((c) => plus(c.eco) >= 100).length, under85: capd.filter((c) => plus(c.eco) < 85).length,
    };
  }
  if (!hand?.done) return { kind: "none", departures: flights.length };
  const typed = new Map(hand.values.map((v) => [`${v.airline_id}|${v.flight_no}`, v.eco_pct]));
  const counts = { 95: 0, 85: 0, 70: 0 };
  for (const f of flights) {
    const v = typed.get(`${f.airline_id}|${f.no}`);
    if (v && v < 95) counts[bucket(v)]++;
  }
  return { kind: "hand", departures: flights.length, under95: counts[95] + counts[85] + counts[70], under85: counts[85] + counts[70], under70: counts[70] };
}
/** The summary in the old report's words (the sold-out count is bold on screen). */
export function summaryWords(s: DaySummary): string {
  if (s.kind === "captured") {
    return `${s.departures} departures · ${s.captured} captured · economy ${pctWords(s.economy)} · business ${pctWords(s.business)} · cargo ${pctWords(s.cargo)} · `
      + `${s.soldOut} sold out · ${s.under85} under 85%`;
  }
  if (s.kind === "hand") return `${s.departures} departures · entered by hand: under 95% ${s.under95} · under 85% ${s.under85} · under 70% ${s.under70}`;
  return `${s.departures} departures · not captured`;
}
/** One airline's line: departures, and with any captured, how many, the economy average and those sold out; and how
 *  many are in their first week. */
export function airlineDay(flights: readonly DayFlight[], loadOf: (f: DayFlight) => CapturedLoad | undefined) {
  const cl = flights.map(loadOf).filter((x): x is CapturedLoad => !!x);
  return {
    departures: flights.length, captured: cl.length, economy: avgOf(cl.map((c) => plus(c.eco)).filter((v) => !Number.isNaN(v))),
    soldOut: cl.filter((c) => plus(c.eco) >= 100).length, firstWeek: flights.filter((f) => f.leeway).length,
  };
}
/** A flight's loads by class (the old capLine): "Y 98% (176/180) · C 80% (16/20) · cargo 40%", marked low under 85% economy. */
export function capLine(r: CapturedLoad | undefined): { text: string; low: boolean } | null {
  if (!r) return null;
  const one = (lab: string, pct: number | null, p: number | null, n: number | null) =>
    pct == null ? "" : `${lab} ${Math.round(Number(pct))}%${p != null && n ? ` (${p}/${n})` : ""}`;
  const parts = [one("Y", r.eco, r.eco_pax, r.eco_seats), one("C", r.bus, r.bus_pax, r.bus_seats), one("F", r.fst, r.fst_pax, r.fst_seats),
    r.cargo == null ? "" : `cargo ${Math.round(Number(r.cargo))}%`].filter(Boolean);
  return parts.length ? { text: parts.join(" · "), low: r.eco != null && Number(r.eco) < 85 } : null;
}

// ---------- the actions, each one planner_save() call
/** Log a refit done in the game (the old data-refit): the aircraft takes the layout, and the refit's cost is a loss that
 *  day (spending_log, as the old planner's capex entry "cabin refit REG → CODE" is stored: no aircraft named). */
export function refitChanges(worldId: number, a: Pick<TailAircraft, "id" | "airline_id" | "registration" | "updated_at">, target: { id: number; code: string },
  cost: number, today: string): Change[] {
  return [
    { table: "aircraft", op: "update", key: { id: a.id }, base: a.updated_at, values: { cabin_config_id: target.id } },
    { table: "spending_log", op: "insert", values: {
      world_id: worldId, airline_id: a.airline_id, spent_on: today, amount: cost, kind: "loss", aircraft_id: null, note: `cabin refit ${a.registration} → ${target.code}` } },
  ];
}
/** Keep as is (the old data-cabkeep): the cabin its routes call for, kept from today. */
export const keepChange = (worldId: number, aircraftId: number, cabin: string, today: string): Change =>
  ({ table: "aircraft_cabin_keeps", op: "insert", values: { world_id: worldId, aircraft_id: aircraftId, cabin, decided_on: today } });
/** Show again (the old data-cabundo): the decision goes. */
export const undoKeepChange = (k: { aircraft_id: number; cabin: string; updated_at: string }): Change =>
  ({ table: "aircraft_cabin_keeps", op: "delete", key: { aircraft_id: k.aircraft_id, cabin: k.cabin }, base: k.updated_at });
/** Log an order as a move of the rotation (the old data-gmove). */
export const logMoveChange = (worldId: number, airlineId: number, move: Move, today: string): Change =>
  ({ table: "growth_log", op: "insert", values: { world_id: worldId, airline_id: airlineId, logged_on: today, move, note: "logged in the planner" } });

function legUpdate(leg: LegNow | undefined, want: { days_utc: number[]; dep_utc_min: number | null; block_min: number | null }): Change[] {
  if (!leg) return [];
  const values: Values = {};
  if (JSON.stringify(want.days_utc) !== JSON.stringify([...leg.days_utc].sort((a, b) => a - b))) values.days_utc = want.days_utc;
  if (want.dep_utc_min !== leg.dep_utc_min) values.dep_utc_min = want.dep_utc_min;
  if (want.block_min !== leg.block_min) values.block_min = want.block_min;
  return Object.keys(values).length ? [{ table: "flight_legs", op: "update", key: { id: leg.id }, base: leg.updated_at, values }] : [];
}

/** Use the game's times (one difference) or Fix all from the game (every one that's only a time or a day change), as
 *  one action (the old applyGameFix, one after another): each frequency they change, its two legs stored again in UTC
 *  from its local times. legs: those frequencies' legs as they are now. */
export function fixChanges(rules: Rules, airlineId: number, issues: readonly GameIssue[], legs: readonly LegNow[],
  marketTypes?: ReadonlyMap<number, number | null>): Change[] {
  const out: Change[] = [];
  for (const [rotationId, x] of game.fixTimes(rules, airlineId, issues, marketTypes)) {
    const { leg1, leg2 } = frequency.toLegs(rules, x.freq.ends, x.local);
    out.push(...legUpdate(legs.find((l) => l.rotation_id === rotationId && l.leg_no === 1), leg1),
      ...legUpdate(legs.find((l) => l.rotation_id === rotationId && l.leg_no === 2), leg2));
  }
  return out;
}
/** The rotations a set of fixes changes (whose legs to read fresh). */
export const fixRotations = (rules: Rules, airlineId: number, issues: readonly GameIssue[], marketTypes?: ReadonlyMap<number, number | null>): number[] =>
  [...game.fixTimes(rules, airlineId, issues, marketTypes).keys()];

const NO_ROW = { id: 0, plan_card_id: 0, position: 0, flight_no: null, origin_code: "", dest_code: "", days_utc: [], dep_utc_min: null, block_min: null, service_code: null, updated_at: "" };
const NO_CARD: PlanCardRow = { id: 0, airline_id: 0, aircraft_id: 0, base_code: null, title: null, note: null, updated_at: "" };
const asLeg = (g: GameFlight): CardLeg => ({ row: NO_ROW, no: g.no, from: g.from, to: g.to, dep: g.dep, arr: g.arr, block: "", svc: "", days: g.days || "1234567" });

export interface ImportInput {
  worldId: number;
  today: string;
  nowMs: number;
  rand?: () => number;
  rules: Rules;
  airlineId: number;
  cand: ImportCandidate;
  /** The aircraft chosen: one of the airline's in service, or a registration typed for a new one. */
  tail: { aircraft: TailAircraft } | { registration: string };
  /** Every aircraft (a typed registration may be an aircraft on order, or retired), and the airline's tails. */
  aircraft: readonly TailAircraft[];
  tails: readonly TailAircraft[];
  bases: readonly string[];
  routes: readonly RouteRow[];
  markets: ReadonlyMap<number, MarketRow>;
  profiles: Parameters<typeof filingChanges>[0]["profiles"];
  airports: ReadonlyMap<string, AirportInfo>;
}

/** The most common value among the airline's tails (the old common(k)): the first seen among the most frequent. */
function common<T>(list: readonly T[]): T | null {
  const n = new Map<T, number>();
  for (const x of list) n.set(x, (n.get(x) ?? 0) + 1);
  let best: T | null = null, most = 0;
  for (const [k, v] of n) if (v > most) { best = k; most = v; }
  return best;
}

/** Add to planner (the old importFlight), as one action: the round trip as a rotation with its two legs, launched today, on
 *  its route (added, or a removed one brought back, where the airline has none), flown by the aircraft chosen. A
 *  registration typed for a new tail (the old "new tail…") puts that aircraft in service first: an aircraft on order with
 *  it takes its order's type, cabin and base, otherwise it's the airline's most common type and cabin, based where the
 *  flight starts. */
export function importChanges(x: ImportInput): Change[] {
  const legs = [asLeg(x.cand.a), ...(x.cand.b ? [asLeg(x.cand.b)] : [])];
  // a destination none of our flights serves yet isn't in the start's input: its offset comes from the tables, as filing's
  const rules = withAirports(x.rules, [...x.airports.values()]);
  const base = { worldId: x.worldId, today: x.today, nowMs: x.nowMs, rand: x.rand, rules, card: NO_CARD, legs, game: null, cabin: null, cabinLogged: true,
    bases: x.bases, routes: x.routes, markets: x.markets, profiles: x.profiles, airports: x.airports };
  if ("aircraft" in x.tail) return filingChanges({ ...base, aircraft: x.tail.aircraft });
  const reg = x.tail.registration.trim().toUpperCase();
  const have = x.aircraft.find((a) => a.registration === reg);
  if (have && have.status === "active") return filingChanges({ ...base, aircraft: have });
  const order = have && have.status !== "retired" ? have : undefined;
  const typeId = order?.aircraft_type_id ?? common(x.tails.map((t) => t.aircraft_type_id));
  const configId = order?.order_config_id ?? common(x.tails.map((t) => t.cabin_config_id));
  const values: Values = { airline_id: x.airlineId, aircraft_type_id: typeId ?? null, cabin_config_id: configId ?? null, base_code: order?.order_base_code || x.cand.a.from, status: "active" };
  const lead: Change = have
    ? { table: "aircraft", op: "update", key: { id: have.id }, base: have.updated_at, values: {
        ...values, retired_on: null, checked_on: null, schedule_changed_on: null, maintenance_note: null } }
    : { table: "aircraft", op: "insert", as: "new aircraft", values: { world_id: x.worldId, registration: reg, ...values } };
  const stand: TailAircraft = {
    id: have?.id ?? -1, registration: reg, airline_id: x.airlineId, aircraft_type_id: typeId ?? null, cabin_config_id: configId ?? null, base_code: null, status: "active",
    ordered_on: null, delivery_at: null, order_base_code: null, order_config_id: null, order_note: null, checked_on: null, schedule_changed_on: null, maintenance_note: null,
    retired_on: null, extra: null, updated_at: have?.updated_at ?? "",
  };
  const flights = filingChanges({ ...base, aircraft: stand });
  if (have) return [lead, ...flights];
  // a new aircraft: its legs take its id from the row added in the same action
  return [lead, ...flights.map((c): Change => {
    if (c.table !== "flight_legs" || !c.values || c.values.aircraft_id !== -1) return c;
    const values = { ...c.values };
    delete values.aircraft_id;
    return { ...c, values, from: { ...(c.from ?? {}), aircraft_id: "new aircraft" } };
  })];
}

/** Each refit's cost for the airline (cabin_refit_cost). */
export const refitCost = (rules: Rules, airlineId: number): number => cabins.refitCost(rules, airlineId);
