// optimiser: the best day's schedule for one aircraft from a base and a set of destinations (manual §4). It tries every
// order of the destinations and every start time in the window, flying out and back to each in turn with the type's
// turn (min_turn_min + turn_margin_min) between legs, every day. A plan is feasible when:
//   - the night on the ground at the base is at least a turn;
//   - no departure or arrival falls in a night ban;
//   - maintenance is at least maintenance_min_pct (maintenance, on the aircraft's week);
//   - no new flight comes within second_daily_gap_h (or the game's same_route_gap_min) of a flight already on its route.
// The best plan makes the most connections at the base (and any extra hubs) involving its new flights, counted as
// pairs of arrival and departure that connect on at least one day. Since 27 Oct (manual §4; brief
// docs/briefs/2026-10-27-connection-waits.md) the score has three keys, in order: the connections within the planning
// target, from the minimum connection time to plan_connection_target_h (connections_within_target); then all
// connections, to connection_max_wait_h (connections); then the most maintenance. Ties keep the first plan found, in
// the order the orders and start times are tried (itertools.permutations' order, then start time), as plan.py did.
// The old code it follows: scripts/planning/plan.py (retired by pull request 4).
import { sequenceWeek, weekLegsOf } from "./aircraftWeek.js";
import { inNightBan } from "./airport.js";
import { baseAt } from "./banks.js";
import { blockFor, timedLegs } from "./block.js";
import { connectionLimits, link, planTargetH, targetLimits, type ConnectionLimits } from "./connections.js";
import { RulesError, findType, settingNumber, worldRuleNumber } from "./input.js";
import { ofWeek as maintenanceOfWeek } from "./maintenance.js";
import { closestDepartures } from "./schedule.js";
import { DAY, WEEK, clock, dayOf, minuteOf, mod, utcOffsetMin } from "./time.js";
import { turnNeed } from "./turns.js";
import type { Rules, TimedLeg } from "./types.js";

export interface OptimiseOptions {
  base: string;
  destinations: string[];
  /** The aircraft type, by id or name. */
  type: number | string;
  /** The airline (whose settings apply); the base's airline when not given. */
  airlineId?: number | null;
  /** The first departure's window, local minutes at the base, both ends included. */
  start: { from: number; to: number };
  /** Minutes between the start times tried. */
  step: number;
  /** Other airports whose connections count too. */
  extraHubs?: string[];
  /** Local weekdays it flies at the base (ISO); every day when not given. */
  days?: number[];
}

export interface PlannedLeg {
  from: string;
  to: string;
  /** Local clock times at each end. */
  dep_local: string;
  arr_local: string;
  dep_utc_min: number;
  days_utc: number[];
  block_min: number;
}

export interface OptimisedPlan {
  order: string[];
  start_local: string;
  start_local_min: number;
  /** Connections from the minimum connection time to connection_max_wait_h: every connection that counts. */
  connections: number;
  /** Of those, the ones within the planning target (to plan_connection_target_h): the score's first key, since 27 Oct. */
  connections_within_target: number;
  maintenance_ratio: number;
  maintenance_pct: number;
  block_hours_day: number;
  /** The night on the ground at the base, minutes. */
  night_at_base_min: number;
  legs: PlannedLeg[];
}

export interface OptimiseAnswer {
  base: string;
  type: string;
  airline_id: number;
  turn_min: number;
  /** settings.plan_connection_target_h, the planning target the score counts first (since 27 Oct). */
  connection_target_h: number;
  considered: number;
  feasible: number;
  rejected: { turn: number; night_ban: number; maintenance: number; route_gap: number };
  best: OptimisedPlan | null;
}

/** Every order of the items, in itertools.permutations' order. */
export function permutations<T>(items: readonly T[]): T[][] {
  if (items.length <= 1) return [items.slice()];
  const out: T[][] = [];
  items.forEach((x, i) => {
    for (const rest of permutations([...items.slice(0, i), ...items.slice(i + 1)])) out.push([x, ...rest]);
  });
  return out;
}

const EPS = 1e-9;

/** The connections a plan's new legs make at the hubs with the existing legs and with each other (the old plan.py's
 *  conns): every arrival and departure pair that connects on at least one day (all), and those whose tightest
 *  connection, on any of its days, is within the planning target (within; the short limits). A departure back to where
 *  the arrival came from doesn't count. Shared with the line optimiser (lineOptimiser, since 28 Oct), so a line and a
 *  day's schedule are scored the same way. */
export function countConnections(rules: Rules, hubs: readonly string[], limits: ReadonlyMap<string, ConnectionLimits>,
  short: ReadonlyMap<string, ConnectionLimits>, legs: readonly TimedLeg[], existing: readonly TimedLeg[]): { all: number; within: number } {
  let c = 0, s = 0;
  for (const h of hubs) {
    const lim = limits.get(h), lims = short.get(h);
    if (!lim || !lims) continue;
    const newArr = legs.filter((l) => l.dest === h), newDep = legs.filter((l) => l.origin === h);
    const oldArr = existing.filter((l) => l.dest === h), oldDep = existing.filter((l) => l.origin === h);
    const count = (i: TimedLeg, o: TimedLeg) => {
      if (o.dest === i.origin) return;
      const k = link(rules, i, o, lim);
      if (!k) return;
      c++;
      if (k.gap_min <= lims.max_min) s++;
    };
    for (const i of newArr) for (const o of [...oldDep, ...newDep]) count(i, o);
    for (const i of oldArr) for (const o of newDep) count(i, o);
  }
  return { all: c, within: s };
}

/** The best day's schedule; see the top of this file. */
export function optimise(rules: Rules, opts: OptimiseOptions, existing: readonly TimedLeg[] = timedLegs(rules)): OptimiseAnswer {
  const type = findType(rules, opts.type);
  if (!type) throw new RulesError(`no aircraft type ${String(opts.type)} in the input`);
  const airlineId = opts.airlineId ?? baseAt(rules, opts.base)?.airline_id;
  if (airlineId == null) throw new RulesError(`no airline for ${opts.base}: it isn't a base, so give the airline`);
  if (!opts.destinations.length) throw new RulesError("no destinations to plan");
  if (!(opts.step > 0)) throw new RulesError("the start times' step must be above 0");
  const turn = turnNeed(rules, type, airlineId);
  const minPct = settingNumber(rules, "maintenance_min_pct", airlineId);
  const second = settingNumber(rules, "second_daily_gap_h", airlineId) * 60;
  const sameRoute = worldRuleNumber(rules, "same_route_gap_min");
  const days = (opts.days?.length ? opts.days : [1, 2, 3, 4, 5, 6, 7]).slice().sort((a, b) => a - b);
  const block = new Map(opts.destinations.map((d) => [d, blockFor(rules, opts.base, d, type.id, airlineId).block_min] as const));
  const offBase = utcOffsetMin(rules, opts.base);
  const hubs = [opts.base, ...(opts.extraHubs ?? []).filter((h) => h !== opts.base)];
  const limits = new Map(hubs.map((h) => [h, connectionLimits(rules, h)] as const));
  const targetH = planTargetH(rules);
  const short = new Map(hubs.map((h) => [h, targetLimits(rules, h, limits.get(h), targetH)] as const));
  const routeLegs = (from: string, to: string) => existing.filter((l) => l.origin === from && l.dest === to);
  const answer: OptimiseAnswer = {
    base: opts.base, type: type.name, airline_id: airlineId, turn_min: turn, connection_target_h: targetH, considered: 0, feasible: 0,
    rejected: { turn: 0, night_ban: 0, maintenance: 0, route_gap: 0 }, best: null,
  };
  let bestKey: { s: number; c: number; m: number } | null = null;

  // a new leg leaving `from` at base-local minute t (may run past midnight), on each of the plan's local days
  const newLeg = (id: number, from: string, to: string, t: number, b: number): TimedLeg => {
    const weeks = days.map((d) => mod((d - 1) * DAY + t - offBase, WEEK));
    const first = weeks[0] ?? 0;
    return {
      id, airline_id: airlineId, rotation_id: null, route_id: null, leg_no: null, flight_no: null, origin: from, dest: to, aircraft_id: null,
      days_utc: [...new Set(weeks.map(dayOf))].sort((a, b) => a - b), dep_utc_min: minuteOf(first), block_min: b, block_source: "estimate", order: -1,
    };
  };

  for (const order of permutations(opts.destinations)) {
    for (let st = opts.start.from; st <= opts.start.to; st += opts.step) {
      answer.considered++;
      let t = st, blk = 0, id = -1;
      const legs: TimedLeg[] = [];
      const local: { from: string; to: string; dep: number; arr: number; b: number }[] = [];
      for (const d of order) {
        const b = block.get(d) ?? 0;
        blk += 2 * b;
        const offD = utcOffsetMin(rules, d);
        legs.push(newLeg(id--, opts.base, d, t, b));
        local.push({ from: opts.base, to: d, dep: mod(t, DAY), arr: mod(t + b + offD - offBase, DAY), b });
        const t2 = t + b + turn;
        legs.push(newLeg(id--, d, opts.base, t2, b));
        local.push({ from: d, to: opts.base, dep: mod(t2 + offD - offBase, DAY), arr: mod(t2 + b, DAY), b });
        t = t2 + b + turn;
      }
      const night = DAY - (t - turn - st);
      if (night < turn) { answer.rejected.turn++; continue; }
      if (local.some((x) => inNightBan(rules, x.from, x.dep) || inNightBan(rules, x.to, x.arr))) { answer.rejected.night_ban++; continue; }
      const week = sequenceWeek(rules, legs.flatMap((l) => weekLegsOf(rules, l)), type, airlineId);
      const m = maintenanceOfWeek(rules, type, airlineId, week);
      if (m.ratio == null || m.ratio < minPct / 100) { answer.rejected.maintenance++; continue; }
      if (legs.some((nl) => routeLegs(nl.origin, nl.dest).some((l) => { const g = closestDepartures(l, nl); return g < second || g < sameRoute; }))) {
        answer.rejected.route_gap++;
        continue;
      }
      answer.feasible++;
      const { all: c, within: s } = countConnections(rules, hubs, limits, short, legs, existing);
      if (bestKey === null || s > bestKey.s || (s === bestKey.s && (c > bestKey.c || (c === bestKey.c && m.ratio > bestKey.m + EPS)))) {
        bestKey = { s, c, m: m.ratio };
        answer.best = {
          order: [...order], start_local: clock(st), start_local_min: st, connections: c, connections_within_target: s,
          maintenance_ratio: m.ratio, maintenance_pct: m.pct,
          block_hours_day: blk / 60, night_at_base_min: night,
          legs: legs.map((l, k) => ({
            from: l.origin, to: l.dest, dep_local: clock(local[k]?.dep ?? 0), arr_local: clock(local[k]?.arr ?? 0),
            dep_utc_min: l.dep_utc_min, days_utc: l.days_utc, block_min: l.block_min,
          })),
        };
      }
    }
  }
  return answer;
}
