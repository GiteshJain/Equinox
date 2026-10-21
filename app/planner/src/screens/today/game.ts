// Today → Game check's logic (moved from Check on 20 Oct; decision #18, build pull request 9, spec
// docs/specs/2026-10-13-check.md): how an airline's line words the planning library's comparison (the old
// renderGameCheck and gcDetail), and its actions as the rows of one planner_save() call each: fix one or every difference
// from the game, and add a flight from the game (the old importFlight, through Tails' filing). No screen code, so the unit
// tests run it.
import { frequency, game, type GameFlight, type GameIssue, type ImportCandidate, type Rules } from "@rules";
import type { Change, Values } from "../../data/save";
import type { AirportInfo, MarketRow, RouteRow } from "../routes/model";
import { filingChanges, withAirports, type CardLeg, type PlanCardRow, type TailAircraft } from "../tails/model";
import type { LegNow } from "./reads";

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
 *  from its local times. legs: those frequencies' legs as they are now. A rotation with no aircraft estimates its block on
 *  the airline's most-flown type (the library's; its market's aircraft until 21 Oct). */
export function fixChanges(rules: Rules, airlineId: number, issues: readonly GameIssue[], legs: readonly LegNow[]): Change[] {
  const out: Change[] = [];
  for (const [rotationId, x] of game.fixTimes(rules, airlineId, issues)) {
    const { leg1, leg2 } = frequency.toLegs(rules, x.freq.ends, x.local);
    out.push(...legUpdate(legs.find((l) => l.rotation_id === rotationId && l.leg_no === 1), leg1),
      ...legUpdate(legs.find((l) => l.rotation_id === rotationId && l.leg_no === 2), leg2));
  }
  return out;
}
/** The rotations a set of fixes changes (whose legs to read fresh). */
export const fixRotations = (rules: Rules, airlineId: number, issues: readonly GameIssue[]): number[] =>
  [...game.fixTimes(rules, airlineId, issues).keys()];

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
