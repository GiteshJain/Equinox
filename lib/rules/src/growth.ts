// growth: the planning parts of the Check screen's Growth board (#18 build pull request 9, spec
// docs/specs/2026-10-13-check.md). The captured figures (what each airline can order, the growth lists, main hubs'
// progress) are the database's; these are worked out from the schedule:
//   - the order rotation (manual §3): each airline's orders rotate big market → frequency → smaller feeder; the next move
//     follows the last one logged (growth_log), skipping a move that has nothing ready;
//   - what each move would do next: big markets are routes from a base the airline flies from (or will, with an order's
//     base) with at least growth_big_min_stars stars, feeders those with fewer from a hub with banks, neither flown by any
//     of our airlines nor on a waiting plan card; frequency, the routes sold out on every departure (growth_ready_full_share
//     of them at 95%+) over at least growth_ready_min_days reported days;
//   - hub readiness: for each bank of each hub, the cities whose flights feed it now and with the waiting plan cards;
//   - the order queues: each airline's aircraft still to arrive, by family, and when each queue runs dry (a delivery up to
//     order_queue_grace_h ago still counts; one running dry within order_queue_warn_h is flagged).
// The old code it follows: the old planner's growthBoard, lastMove, nextMove and moveCandidates (its 4 stars, 5 days and
// 95%, and its 6 and 48 hours, are settings here). The old planner's suggested aircraft size for each route was a rule in
// its code with no home in the database, so it isn't worked out here (the pull request says so).
import { bankOfArrival, bankWindows, isFocus } from "./banks.js";
import { timedLegs } from "./block.js";
import { pairKey, settingNumber } from "./input.js";
import { DAY, mod, toLocal } from "./time.js";
import type { Rules, TimedLeg } from "./types.js";

export type Move = "big" | "freq" | "feeder";
/** The order rotation, in its order. */
export const CYCLE: readonly Move[] = ["big", "freq", "feeder"];

/** A growth_log row: the airline, the day and the move logged. */
export interface LoggedMove { airline_id: number; logged_on: string; move: string }

/** The airline's last move logged (the latest day; the log's order for a tie), or null. */
export function lastMove<T extends LoggedMove>(log: readonly T[], airlineId: number): T | null {
  const mine = log.map((x, i) => ({ x, i })).filter((v) => v.x.airline_id === airlineId)
    .sort((a, b) => (a.x.logged_on < b.x.logged_on ? -1 : a.x.logged_on > b.x.logged_on ? 1 : 0) || a.i - b.i);
  return mine.length ? (mine[mine.length - 1] as { x: T }).x : null;
}

/** The move after the last one logged, or a big market when none is. */
export function nextMove(log: readonly LoggedMove[], airlineId: number): Move {
  const l = lastMove(log, airlineId);
  if (!l) return "big";
  return CYCLE[(CYCLE.indexOf(l.move as Move) + 1) % CYCLE.length] as Move;
}

/** A route of the airline's, as the planner has it (with the planner's edits applied; removed ones left out). */
export interface GrowthRoute { id: number; hub: string; dest: string; stars: number; dist: number | null }
/** A route's economy loads over the last 7 days (route_loads()). */
export interface RouteLoad { route_id: number; departures: number; full: number; days: number }

export interface MoveFacts {
  /** The airline's routes, in the routes' order. */
  routes: readonly GrowthRoute[];
  /** The legs on the plan cards of its aircraft not yet filed, and those aircraft's bases as ordered. */
  planned: readonly { from: string; to: string }[];
  orderBases: readonly (string | null)[];
  /** The routes' loads (route_loads()). */
  loads: readonly RouteLoad[];
}

export interface MoveCandidates { big: GrowthRoute[]; freq: GrowthRoute[]; feeder: GrowthRoute[] }

/** What each move would do next for an airline, best first (the old moveCandidates). */
export function moveCandidates(rules: Rules, airlineId: number, facts: MoveFacts): MoveCandidates {
  const flown = new Set<string>();
  const liveCodes = new Set<string>();
  for (const rot of [...rules.rotations.values()]) {
    const r = rules.routes.get(rot.route_id);
    if (!r) continue;
    flown.add(pairKey(r.hub_code, r.dest_code));
    if (r.airline_id === airlineId) liveCodes.add(r.hub_code);
  }
  for (const L of facts.planned) flown.add(pairKey(L.from, L.to));
  for (const b of facts.orderBases) if (b) liveCodes.add(b);
  const bases = rules.bases.filter((b) => b.airline_id === airlineId && liveCodes.has(b.airport_code));
  const live = new Set(bases.map((b) => b.airport_code));
  const banked = new Set(bases.filter((b) => (b.role || "hub") === "hub").map((b) => b.airport_code));
  const minStars = settingNumber(rules, "growth_big_min_stars", airlineId);
  const open = facts.routes.filter((r) => live.has(r.hub) && !flown.has(pairKey(r.hub, r.dest)));
  const byStars = (list: GrowthRoute[]) => list.map((r, i) => ({ r, i }))
    .sort((a, b) => b.r.stars - a.r.stars || (a.r.dist ?? NaN) - (b.r.dist ?? NaN) || a.i - b.i).map((v) => v.r);
  const minDays = settingNumber(rules, "growth_ready_min_days", airlineId);
  const fullShare = settingNumber(rules, "growth_ready_full_share", airlineId);
  const loads = new Map(facts.loads.map((x) => [x.route_id, x]));
  const rtWeek = new Map<number, number>();
  const legsOf = new Map<number, { leg_no: number | null | undefined; days: number }[]>();
  for (const l of rules.legs) if (l.rotation_id != null) legsOf.set(l.rotation_id, [...(legsOf.get(l.rotation_id) ?? []), { leg_no: l.leg_no, days: l.days_utc.length }]);
  for (const rot of rules.rotations.values()) {
    const ls = legsOf.get(rot.id) ?? [];
    rtWeek.set(rot.route_id, (rtWeek.get(rot.route_id) ?? 0) + ((ls.find((l) => l.leg_no === 1) ?? ls[0])?.days ?? 0));
  }
  const freq = facts.routes.map((r, i) => ({ r, i, a: loads.get(r.id) }))
    .filter((x) => x.a && x.a.days >= minDays && x.a.departures > 0 && x.a.full / x.a.departures >= fullShare)
    .sort((x, y) => y.r.stars - x.r.stars || (rtWeek.get(x.r.id) ?? 0) - (rtWeek.get(y.r.id) ?? 0) || x.i - y.i).map((x) => x.r);
  return {
    big: byStars(open.filter((r) => r.stars >= minStars)),
    freq,
    feeder: byStars(open.filter((r) => r.stars < minStars && banked.has(r.hub))),
  };
}

/** The move to show for an airline: the next in the rotation, or the one after it while a move has nothing ready. */
export function shownMove(next: Move, c: MoveCandidates): Move {
  let nx = next;
  for (let k = 0; k < 3 && !c[nx].length; k++) nx = CYCLE[(CYCLE.indexOf(nx) + 1) % 3] as Move;
  return nx;
}

/** The routes ready for another flight from the load reports alone (shown when no profit was captured): sold out on every
 *  departure (growth_ready_full_share at 95%+) over at least growth_ready_min_days reported days, most stars first, then
 *  fewest flights a day. */
export function readyFromLoads(rules: Rules, routes: readonly (GrowthRoute & { airline_id: number })[], loads: readonly RouteLoad[]): (GrowthRoute & { airline_id: number; round_trips_day: number })[] {
  const byRoute = new Map(loads.map((x) => [x.route_id, x]));
  const rt = new Map<number, number>();
  const legsOf = new Map<number, { leg_no: number | null | undefined; days: number }[]>();
  for (const l of rules.legs) if (l.rotation_id != null) legsOf.set(l.rotation_id, [...(legsOf.get(l.rotation_id) ?? []), { leg_no: l.leg_no, days: l.days_utc.length }]);
  for (const rot of rules.rotations.values()) {
    const ls = legsOf.get(rot.id) ?? [];
    rt.set(rot.route_id, (rt.get(rot.route_id) ?? 0) + ((ls.find((l) => l.leg_no === 1) ?? ls[0])?.days ?? 0));
  }
  return routes.map((r, i) => ({ r, i, a: byRoute.get(r.id) }))
    .filter((x) => x.a && x.a.days >= settingNumber(rules, "growth_ready_min_days", x.r.airline_id) && x.a.departures > 0
      && x.a.full / x.a.departures >= settingNumber(rules, "growth_ready_full_share", x.r.airline_id))
    .map((x) => ({ ...x, d: (rt.get(x.r.id) ?? 0) / 7 }))
    .sort((x, y) => y.r.stars - x.r.stars || x.d - y.d || x.i - y.i)
    .map((x) => ({ ...x.r, round_trips_day: x.d }));
}

// ---------- hub readiness
export interface ReadinessRow {
  base_id: number;
  airline_id: number;
  airport: string;
  bank: number;
  /** The bank's departure, local minutes. */
  dep: number;
  /** Cities whose flights feed the bank now, and with the waiting plan cards' too. */
  flying: number;
  with_planned: number;
  /** Those cities by country (airports.country_code), most first. */
  countries: { country: string; cities: number }[];
}

/** A leg on a waiting plan card, as plan_card_legs stores it. */
export interface PlannedCardLeg { from: string; to: string; dep_utc_min: number | null; block_min: number | null }

/** For each bank of each hub (not focus cities), in the bases' order: the cities feeding it (the old Hub readiness).
 *  An arrival feeds a bank when it lands in time for it, inside its arrival window or early within connection_max_wait_h.
 *  Every flight of our airlines landing there counts, with a number; a plan card's leg counts when its arrival is known.
 *  countries: each airport's country, for airports the rules don't carry. */
export function hubReadiness(rules: Rules, planned: readonly PlannedCardLeg[], countries: ReadonlyMap<string, string | null> = new Map(),
  legs: readonly TimedLeg[] = timedLegs(rules)): ReadinessRow[] {
  const outNo = new Map<number, number | null>();
  for (const l of rules.legs) if (l.rotation_id != null && (l.leg_no ?? 1) === 1) outNo.set(l.rotation_id, l.flight_no);
  const numbered = legs.filter((l) => {
    const out = l.rotation_id != null ? outNo.get(l.rotation_id) ?? null : l.flight_no;
    return (l.leg_no ?? 1) === 1 ? !!l.flight_no : !!(l.flight_no || out);
  });
  const countryOf = (code: string) => rules.airports.get(code)?.country_code ?? countries.get(code) ?? "";
  const out: ReadinessRow[] = [];
  for (const base of rules.bases) {
    if (isFocus(base)) continue;
    const wins = bankWindows(rules, base);
    if (!wins.length) continue;
    const code = base.airport_code;
    const arriving = numbered.filter((l) => l.dest === code).map((l) => ({ from: l.origin, arr: mod(toLocal(rules, code, l.dep_utc_min + l.block_min), DAY) }));
    const plannedHere = planned.filter((L) => L.to === code && L.dep_utc_min != null && L.block_min != null)
      .map((L) => ({ from: L.from, arr: mod(toLocal(rules, code, (L.dep_utc_min as number) + (L.block_min as number)), DAY) }));
    for (const w of wins) {
      const feeds = (arr: number) => { const z = bankOfArrival(rules, base, arr); return (z.status === "in" || z.status === "early") && z.n === w.n; };
      const now1 = new Set(arriving.filter((L) => feeds(L.arr)).map((L) => L.from));
      const all = new Set([...now1, ...plannedHere.filter((L) => feeds(L.arr)).map((L) => L.from)]);
      if (!all.size) continue;
      const rc = new Map<string, number>();
      for (const c of all) { const k = countryOf(c) || "?"; rc.set(k, (rc.get(k) ?? 0) + 1); }
      out.push({
        base_id: base.id, airline_id: base.airline_id, airport: code, bank: w.n, dep: w.dep, flying: now1.size, with_planned: all.size,
        countries: [...rc].map((x, i) => ({ x, i })).sort((a, b) => b.x[1] - a.x[1] || a.i - b.i).map((v) => ({ country: v.x[0], cities: v.x[1] })),
      });
    }
  }
  return out;
}

// ---------- the order queues
export interface QueueCell {
  family: string;
  /** Not one of the families the airline may have. */
  in_fleet: boolean;
  /** Aircraft still to arrive (or arrived within order_queue_grace_h). */
  count: number;
  /** When the last of them arrives (ms), or null with none. */
  last_ms: number | null;
  /** Hours from now to then (negative once past). */
  hours: number | null;
  /** It runs dry within order_queue_warn_h. */
  warn: boolean;
}

/** Each airline's queue for each family: its aircraft not yet filed whose arrival is after now less order_queue_grace_h,
 *  and when the last one arrives. families: the families shown, in order; allowed: each family the airline may have. */
export function orderQueues(rules: Rules, airlineId: number, families: readonly string[], allowed: ReadonlySet<string>,
  deliveries: readonly { family: string; delivery_ms: number | null }[], nowMs: number): QueueCell[] {
  const grace = settingNumber(rules, "order_queue_grace_h", airlineId) * 3_600_000;
  const warnH = settingNumber(rules, "order_queue_warn_h", airlineId);
  return families.map((family) => {
    if (!allowed.has(family)) return { family, in_fleet: false, count: 0, last_ms: null, hours: null, warn: false };
    const q = deliveries.filter((d) => d.family === family && d.delivery_ms != null && d.delivery_ms > nowMs - grace);
    if (!q.length) return { family, in_fleet: true, count: 0, last_ms: null, hours: null, warn: false };
    const last = Math.max(...q.map((d) => d.delivery_ms as number));
    const hours = (last - nowMs) / 3_600_000;
    return { family, in_fleet: true, count: q.length, last_ms: last, hours, warn: hours < warnH };
  });
}
