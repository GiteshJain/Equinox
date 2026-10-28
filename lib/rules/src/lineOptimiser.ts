// lineOptimiser: the best 7-day rotating line for one aircraft type at one airline (spec
// docs/specs/2026-10-27-long-haul-lines.md §1; manual §4, long haul in lines, decided 27 Oct). A line is 168 hours of one
// aircraft's flying over a set of routes, closing on itself: 7 aircraft fly it a day apart, so every leg on it operates
// daily at the same time. The library plans one aircraft's week and hands back the 7 cards.
//
// The line: each chosen route is flown once each way, and the legs form one closed walk over the routes (an Eulerian
// circuit of the doubled graph: each route's two directions), starting at one of the hubs. Line day d of a leg is its
// UTC weekday on the first aircraft's card, and aircraft k flies line day d on weekday ((d + k − 2) mod 7) + 1 (the
// spec's formula): each card is the whole line shifted a day, as the game's copy and offset makes it. A line day may be
// away from base; the days chain.
//
// Feasible when: every ground gap is at least the turn (the type's turnaround plus turn_margin_min); no departure or
// arrival in a night ban; every new leg at least same_route_gap_min from an existing flight on its route (world rules);
// every route within the type's reach (aircraft_types.range_km, or the caller's figure, since rules_input() doesn't
// carry it yet: a route beyond it is refused with the reason, asking first being the Scheduling chat's job; a reach the
// library hasn't got is an error naming it, never a guess); maintenance at or above maintenance_min_pct on the week; no stretch longer than maintenance_max_gap_h
// without a counting stop (maintenance.spacing); the week closing on itself after 168 hours.
//
// Scored by, in order: the connections within plan_connection_target_h at the hubs (the planning target, manual §4),
// then every connection to connection_max_wait_h, then routes covered, then block hours, then maintenance. The
// connections are counted as the day optimiser counts them (optimiser.countConnections): every arrival and departure
// pair at a hub, with the existing network and among the line's own legs, each leg daily.
//
// The search is a heuristic with a budget, never exhaustive: for each set of routes (all of them first, then each with
// one dropped, then two, only while nothing feasible is found), each start hub and each closed walk (in a fixed order),
// the first departure is tried at each time on the start hub's bank ladder (every bank's departure window by the step),
// and the rest of the legs are timed by a greedy chain kept as a small beam: at a hub each candidate time on its ladder
// within a day, everywhere the earliest departure and the earliest that makes a counting maintenance stop, each pushed
// past a night ban; the beam keeps the partial lines with the most connections within the target. Every complete line
// is checked in full and scored; then local moves on the best line's departure times polish it. The budget is a number
// of chains started and lines evaluated (work) and a time check the caller gives (the command's run-time cap: the library reads no clock); when it
// runs out the answer is the best found and says the search didn't finish. Given the same input and budget the answer is
// the same: there is no randomness.
import { sequenceWeek, weekLegsOf } from "./aircraftWeek.js";
import { inNightBan, nightBanAt } from "./airport.js";
import { bankOfArrival, bankOfDeparture, bankWindows, baseAt, hasBanks } from "./banks.js";
import { blockFor, distanceBetween, timedLegs } from "./block.js";
import { connectionLimits, link, planTargetH, targetLimits, type ConnectionLimits } from "./connections.js";
import { RulesError, findType, pairKey, setting, settingNumber, worldRuleNumber } from "./input.js";
import { ofWeek as maintenanceOfWeek, type Maintenance } from "./maintenance.js";
import { countConnections } from "./optimiser.js";
import { closestDepartures, nextFlightNumbers } from "./schedule.js";
import { wantedFor } from "./service.js";
import { DAY, WEEK, clock, dayOf, minuteOf, mod, toLocal, utcOffsetMin } from "./time.js";
import { turnNeed } from "./turns.js";
import type { AircraftTypeRow, BaseRow, Rules, TimedLeg } from "./types.js";
import type { Card, CardLeg } from "./card.js";

/** A route as the caller names it: its two airports, either way round. */
export type RoutePair = readonly [string, string];

export interface LineOptions {
  /** The airline (its settings and flight numbers). */
  airlineId: number;
  /** The aircraft type, by id or name. */
  type: number | string;
  /** The hubs: where connections are scored and whose bank ladders give the candidate times; the line starts at one. */
  hubs: string[];
  /** The candidate routes: the long ones and the medium fillers. */
  routes: RoutePair[];
  /** Routes that must be on the line. */
  fixed?: RoutePair[];
  /** Minutes between the candidate times on a bank ladder. */
  step: number;
  /** The search budget: at most this much work (chains started plus lines evaluated in full, search.work), and a check
   *  the caller makes for time (the command's run-time cap). Without either the search runs to the end. */
  budget?: { work?: number | null; timeUp?: (() => boolean) | null };
  /** Flight numbers already taken outside flight_legs (plan_card_legs' numbers for the airline). */
  usedFlightNumbers?: number[];
  /** The type's reach in km, when the input doesn't carry aircraft_types.range_km (rules_input() doesn't yet), or to
   *  override it. */
  rangeKm?: number | null;
  /** How many partial lines the greedy chain keeps at each leg (the beam); 12 by default. */
  beam?: number;
}

/** One leg of the line, in flying order. */
export interface LineLeg {
  leg: number;
  /** The line day it departs on, 1 to 7 (the first aircraft's UTC weekday). */
  line_day: number;
  from: string;
  to: string;
  flight_no: number;
  service_code: string | null;
  /** The departure as a minute of the line's week (from Monday 00:00 UTC on the first aircraft's card) and of the day. */
  dep_week_min: number;
  dep_utc_min: number;
  dep_utc: string;
  dep_local: string;
  arr_local: string;
  /** The weekday it lands on, for the first aircraft. */
  arr_line_day: number;
  block_min: number;
  distance_km: number;
  /** Minutes on the ground after it, to the next departure (the last leg's runs to the week's close). */
  ground_min: number;
  /** The ground after it counts as a maintenance stop. */
  maintenance_stop: boolean;
  /** The bank it leaves in and the bank it feeds, at a hub with banks; null elsewhere. */
  bank_out: number | null;
  bank_in: number | null;
}

/** One line day: the legs departing on it (UTC weekday, the first aircraft's), in time order; day d + 1 starts where day
 *  d ends, and day 7 ends where day 1 starts. */
export interface LineDay {
  day: number;
  starts_at: string;
  ends_at: string;
  legs: number[];
  block_min: number;
}

export interface LineScore {
  connections_within_target: number;
  connections: number;
  routes: number;
  block_hours_week: number;
  maintenance_ratio: number;
}

export interface Line {
  /** The routes on it, as the caller named them ("SFO–LGW"), in the order first flown. */
  routes: string[];
  start_hub: string;
  legs: LineLeg[];
  days: LineDay[];
  block_hours_day: number;
  maintenance: Maintenance;
  connections: number;
  connections_within_target: number;
  score: LineScore;
  flight_numbers: { base: string; from: number; to: number | null; used: number[] };
  /** The 7 aircraft cards, as check-card takes them: aircraft k's legs on weekday ((line day + k − 2) mod 7) + 1. */
  cards: (Card & { line_day_offset: number })[];
}

export interface LineAnswer {
  airline_id: number;
  type: string;
  hubs: string[];
  routes: string[];
  fixed: string[];
  step: number;
  turn_min: number;
  connection_target_h: number;
  maintenance_max_gap_h: number | null;
  /** The reach the routes were checked against (aircraft_types.range_km, or the caller's). */
  range_km: number;
  search: {
    route_sets: number;
    circuits: number;
    /** Greedy chains started (a circuit from one first departure). */
    chains: number;
    /** Chains plus lines evaluated: what the work budget counts. */
    work: number;
    lines_evaluated: number;
    feasible: number;
    /** False when the budget ran out: the answer is the best found so far. */
    finished: boolean;
    note: string;
  };
  /** Why lines were dropped: hours (the routes and turns don't fit 168 hours), not_connected (no closed walk from a
   *  hub), no_fit (the chain found no departure time within the week's slack and the spacing limit), and the full
   *  check's night_ban, turn, route_gap, maintenance and spacing. */
  rejected: { hours: number; not_connected: number; no_fit: number; night_ban: number; turn: number; route_gap: number; maintenance: number; spacing: number };
  best: Line | null;
}

/** An arc of the doubled graph: one direction of a route. */
interface Arc {
  route: number;
  from: string;
  to: string;
  block: number;
}

interface Ctx {
  rules: Rules;
  type: AircraftTypeRow;
  airlineId: number;
  hubs: string[];
  /** Each route as the caller named it ("SFO–LGW"), by the arcs' route index. */
  routeNames: string[];
  turn: number;
  keep: number;
  minGround: number;
  minPct: number;
  gapLimitMin: number | null;
  sameRoute: number;
  step: number;
  beam: number;
  existing: readonly TimedLeg[];
  limits: Map<string, ConnectionLimits>;
  short: Map<string, ConnectionLimits>;
  /** Each hub's bank ladder as local minutes of the day (a hub without banks: every half hour, a search setting). */
  ladders: Map<string, number[]>;
  /** Each hub's arrival deadlines (the last minute of each bank's arrival window), local minutes of the day. */
  arrivals: Map<string, number[]>;
  /** Existing legs by airport: arrivals there and departures from there (for the greedy chain's local score). */
  arrAt: Map<string, TimedLeg[]>;
  depAt: Map<string, TimedLeg[]>;
  answer: LineAnswer;
  budget: { work: number | null; timeUp: (() => boolean) | null };
  out: boolean;
}

const routeName = (p: RoutePair): string => `${p[0]}–${p[1]}`;
const pairOf = (p: RoutePair): string => pairKey(p[0], p[1]);
const EPS = 1e-9;
/** The ladder at a hub with no bank windows: every half hour (a search setting, as the step is; not a rule). */
const NO_BANKS_STEP = 30;
/** How many steps the walk over a route set may take before it gives up (a search setting). */
const CIRCUIT_STEPS = 200000;

/** The score's keys in order; true when a beats b. */
function better(a: LineScore, b: LineScore): boolean {
  if (a.connections_within_target !== b.connections_within_target) return a.connections_within_target > b.connections_within_target;
  if (a.connections !== b.connections) return a.connections > b.connections;
  if (a.routes !== b.routes) return a.routes > b.routes;
  if (Math.abs(a.block_hours_week - b.block_hours_week) > EPS) return a.block_hours_week > b.block_hours_week;
  return a.maintenance_ratio > b.maintenance_ratio + EPS;
}

/** Whether the budget is spent: lines evaluated against the cap, or the caller's time check. */
function spent(ctx: Ctx): boolean {
  if (ctx.out) return true;
  const b = ctx.budget;
  if ((b.work != null && ctx.answer.search.work >= b.work) || (b.timeUp && b.timeUp())) ctx.out = true;
  return ctx.out;
}

/** A daily leg for scoring (every weekday), from an arc and its departure minute of the week. */
function dailyLeg(ctx: Ctx, id: number, a: Arc, dep: number): TimedLeg {
  return {
    id, airline_id: ctx.airlineId, rotation_id: null, route_id: null, leg_no: null, flight_no: null, origin: a.from, dest: a.to,
    aircraft_id: null, days_utc: [1, 2, 3, 4, 5, 6, 7], dep_utc_min: minuteOf(dep), block_min: a.block, block_source: "estimate", order: -1,
  };
}

/** The same leg on one aircraft's card: the one weekday it departs on. */
function cardLeg(ctx: Ctx, id: number, a: Arc, dep: number): TimedLeg {
  return { ...dailyLeg(ctx, id, a, dep), days_utc: [dayOf(mod(dep, WEEK))] };
}

/** The first minute at or after `from` whose local time at the airport is `local` (a minute of the day). */
function nextLocal(ctx: Ctx, code: string, from: number, local: number): number {
  const utc = mod(local - utcOffsetMin(ctx.rules, code), DAY);
  return from + mod(utc - mod(from, DAY), DAY);
}

/** A departure pushed past the night bans at both ends: a departure inside its origin's ban moves to just after the
 *  ban; an arrival inside its destination's moves the departure so it lands just after. Null when no push settles it. */
function pastBans(ctx: Ctx, a: Arc, dep: number): number | null {
  let d = dep;
  for (let i = 0; i < 3; i++) {
    const banO = nightBanAt(ctx.rules, a.from), banD = nightBanAt(ctx.rules, a.to);
    const depLocal = toLocal(ctx.rules, a.from, d, DAY), arrLocal = toLocal(ctx.rules, a.to, d + a.block, DAY);
    if (banO && inNightBan(ctx.rules, a.from, depLocal)) d = nextLocal(ctx, a.from, d, mod(banO.to + 1, DAY));
    else if (banD && inNightBan(ctx.rules, a.to, arrLocal)) d = nextLocal(ctx, a.to, d + a.block, mod(banD.to + 1, DAY)) - a.block;
    else return d;
  }
  return null;
}

/** The candidate departure times for an arc leaving at or after `earliest` and no later than `latest`: the earliest,
 *  the earliest that makes the ground before it a counting maintenance stop (from the landing at `landed`), and at a
 *  hub every ladder time within a day; each pushed past the night bans, no repeats, in time order. */
function candidates(ctx: Ctx, a: Arc, landed: number, earliest: number, latest: number): number[] {
  const raw = new Set<number>([earliest, Math.max(earliest, landed + ctx.keep + ctx.minGround)]);
  const ladder = ctx.ladders.get(a.from);
  if (ladder) for (const local of ladder) raw.add(nextLocal(ctx, a.from, earliest, local));
  // landing at a hub: the last minute of each bank's arrival window (just in time for the bank)
  for (const w of ctx.arrivals.get(a.to) ?? []) raw.add(nextLocal(ctx, a.to, earliest + a.block, w) - a.block);
  const out = new Set<number>();
  for (const d of raw) {
    if (d > latest) continue;
    const p = pastBans(ctx, a, d);
    if (p != null && p >= earliest && p <= latest) out.add(p);
  }
  return [...out].sort((x, y) => x - y);
}

/** The connections one new leg (daily) makes with the existing legs at the hubs, and with the line's legs placed so far:
 *  for the greedy chain's local score. The same test as countConnections, applied to one leg. */
function legGain(ctx: Ctx, leg: TimedLeg, placed: readonly TimedLeg[]): { within: number; all: number } {
  let all = 0, within = 0;
  const count = (i: TimedLeg, o: TimedLeg, at: string) => {
    if (o.dest === i.origin) return;
    const lim = ctx.limits.get(at), lims = ctx.short.get(at);
    if (!lim || !lims) return;
    const k = link(ctx.rules, i, o, lim);
    if (!k) return;
    all++;
    if (k.gap_min <= lims.max_min) within++;
  };
  if (ctx.limits.has(leg.dest)) for (const o of [...(ctx.depAt.get(leg.dest) ?? []), ...placed.filter((p) => p.origin === leg.dest)]) count(leg, o, leg.dest);
  if (ctx.limits.has(leg.origin)) for (const i of [...(ctx.arrAt.get(leg.origin) ?? []), ...placed.filter((p) => p.dest === leg.origin)]) count(i, leg, leg.origin);
  return { within, all };
}

interface PartialLine {
  deps: number[];
  used: number;
  /** The departure after the last counting stop so far (the start, until one counts). */
  sinceStop: number;
  stops: number;
  within: number;
  all: number;
  placed: TimedLeg[];
}

/** A complete line checked in full: null with the reason counted when it isn't feasible, else its figures. */
function evaluate(ctx: Ctx, arcs: readonly Arc[], deps: readonly number[], startHub: string): Line | null {
  ctx.answer.search.lines_evaluated++;
  ctx.answer.search.work++;
  const daily = arcs.map((a, i) => dailyLeg(ctx, -(i + 1), a, deps[i] ?? 0));
  // night bans (the candidates were pushed past them; the polish re-checks)
  for (const l of daily) {
    if (inNightBan(ctx.rules, l.origin, toLocal(ctx.rules, l.origin, l.dep_utc_min, DAY))
      || inNightBan(ctx.rules, l.dest, toLocal(ctx.rules, l.dest, l.dep_utc_min + l.block_min, DAY))) { ctx.answer.rejected.night_ban++; return null; }
  }
  // the same-route gap against the existing flights on each route
  for (const l of daily) {
    for (const e of ctx.existing) {
      if (e.origin === l.origin && e.dest === l.dest && closestDepartures(e, l) < ctx.sameRoute) { ctx.answer.rejected.route_gap++; return null; }
    }
  }
  // one aircraft's week: the legs on their own weekdays, sequenced; turns, maintenance and spacing on it
  const week = sequenceWeek(ctx.rules, arcs.flatMap((a, i) => weekLegsOf(ctx.rules, cardLeg(ctx, -(i + 1), a, deps[i] ?? 0))), ctx.type, ctx.airlineId);
  if (week.some((w) => w.overlap || !w.position_ok || (w.turn && !w.turn.ok))) { ctx.answer.rejected.turn++; return null; }
  const m = maintenanceOfWeek(ctx.rules, ctx.type, ctx.airlineId, week);
  if (m.ratio == null || m.ratio < ctx.minPct / 100) { ctx.answer.rejected.maintenance++; return null; }
  if (m.max_gap_ok === false) { ctx.answer.rejected.spacing++; return null; }
  ctx.answer.search.feasible++;
  const c = countConnections(ctx.rules, ctx.hubs, ctx.limits, ctx.short, daily, ctx.existing);
  const blockWeek = arcs.reduce((s, a) => s + a.block, 0);
  const routesSeen: string[] = [];
  for (const a of arcs) { const n = ctx.routeNames[a.route] ?? `${a.from}–${a.to}`; if (!routesSeen.includes(n)) routesSeen.push(n); }
  const score: LineScore = { connections_within_target: c.within, connections: c.all, routes: routesSeen.length, block_hours_week: blockWeek / 60, maintenance_ratio: m.ratio };
  // the legs in flying order, with the ground after each (the week's legs are in departure order, which the chain is)
  const byDep = new Map(week.map((w) => [w.leg_id, w] as const));
  const legs: LineLeg[] = arcs.map((a, i) => {
    const dep = deps[i] ?? 0, w = byDep.get(-(i + 1));
    const ground = w?.ground_min ?? 0;
    const bo = ctx.limits.has(a.from) ? baseAt(ctx.rules, a.from) : undefined, bd = ctx.limits.has(a.to) ? baseAt(ctx.rules, a.to) : undefined;
    const depLocal = toLocal(ctx.rules, a.from, dep, DAY), arrLocal = toLocal(ctx.rules, a.to, dep + a.block, DAY);
    return {
      leg: i + 1, line_day: dayOf(mod(dep, WEEK)), from: a.from, to: a.to, flight_no: 0, service_code: wantedFor(ctx.rules, ctx.airlineId, a.from, a.to)?.code ?? null,
      dep_week_min: mod(dep, WEEK), dep_utc_min: minuteOf(dep), dep_utc: clock(dep), dep_local: clock(depLocal), arr_local: clock(arrLocal),
      arr_line_day: dayOf(mod(dep + a.block, WEEK)), block_min: a.block, distance_km: distanceBetween(ctx.rules, a.from, a.to, ctx.airlineId)?.km ?? 0,
      ground_min: ground, maintenance_stop: w != null && w.ground_min != null && !w.overlap && w.ground_min - ctx.keep >= ctx.minGround,
      bank_out: bo && hasBanks(bo) ? bankOfDeparture(ctx.rules, bo, depLocal)?.n ?? 0 : null,
      bank_in: bd && hasBanks(bd) ? bankOfArrival(ctx.rules, bd, arrLocal).n : null,
    };
  });
  // each line day's legs in UTC order (the chain may wrap past the week's end), so day d + 1 starts where day d ends
  const days: LineDay[] = [];
  for (let d = 1; d <= 7; d++) {
    const mine = legs.filter((l) => l.line_day === d).sort((a, b) => a.dep_utc_min - b.dep_utc_min);
    const first = mine[0], last = mine[mine.length - 1];
    days.push({ day: d, starts_at: first?.from ?? "", ends_at: last?.to ?? "", legs: mine.map((l) => l.leg), block_min: mine.reduce((s, l) => s + l.block_min, 0) });
  }
  return {
    routes: routesSeen, start_hub: startHub, legs, days, block_hours_day: blockWeek / 60 / 7, maintenance: m, connections: c.all,
    connections_within_target: c.within, score, flight_numbers: { base: "", from: 0, to: null, used: [] }, cards: [],
  };
}

/** The greedy chain through the banks for one closed walk from one first departure: the beam of partial lines, and
 *  every complete line it reaches evaluated. Returns the best feasible line found, if any. */
function chain(ctx: Ctx, arcs: readonly Arc[], t0: number, startHub: string, best: Line | null): Line | null {
  ctx.answer.search.chains++;
  ctx.answer.search.work++;
  const blockSum = arcs.reduce((s, a) => s + a.block, 0);
  const slack = WEEK - blockSum - arcs.length * ctx.turn;
  if (slack < 0) { ctx.answer.rejected.hours++; return best; }
  const first = arcs[0];
  if (!first) return best;
  const d0 = pastBans(ctx, first, t0);
  if (d0 == null || d0 !== t0) { ctx.answer.rejected.night_ban++; return best; }
  const firstLeg = dailyLeg(ctx, -1, first, t0);
  const g0 = legGain(ctx, firstLeg, []);
  let beam: PartialLine[] = [{ deps: [t0], used: 0, sinceStop: t0, stops: 0, within: g0.within, all: g0.all, placed: [firstLeg] }];
  for (let i = 1; i < arcs.length; i++) {
    const a = arcs[i], prev = arcs[i - 1];
    if (!a || !prev) break;
    const next: PartialLine[] = [];
    for (const p of beam) {
      const landed = (p.deps[i - 1] ?? 0) + prev.block;
      const earliest = landed + ctx.turn, latest = earliest + (slack - p.used);
      for (const d of candidates(ctx, a, landed, earliest, latest)) {
        const ground = d - landed;
        const counts = ground - ctx.keep >= ctx.minGround;
        const since = counts ? d : p.sinceStop;
        if (ctx.gapLimitMin != null && d + a.block - since > ctx.gapLimitMin) continue;
        const leg = dailyLeg(ctx, -(i + 1), a, d);
        const g = legGain(ctx, leg, p.placed);
        next.push({ deps: [...p.deps, d], used: p.used + (ground - ctx.turn), sinceStop: since, stops: p.stops + (counts ? 1 : 0), within: p.within + g.within, all: p.all + g.all, placed: [...p.placed, leg] });
      }
    }
    if (!next.length) { ctx.answer.rejected.no_fit++; return best; }
    next.sort((x, y) => y.within - x.within || y.all - x.all || y.stops - x.stops || x.used - y.used);
    beam = next.slice(0, ctx.beam);
  }
  for (const p of beam) {
    if (spent(ctx)) return best;
    const line = evaluate(ctx, arcs, p.deps, startHub);
    if (line && (!best || better(line.score, best.score))) best = line;
  }
  return best;
}

/** Local moves on the best line's departure times: each leg tried at every candidate time between its neighbours,
 *  keeping the rest; an improvement is kept and the pass repeated, up to a few passes. */
function polish(ctx: Ctx, arcs: readonly Arc[], line: Line): Line {
  let cur = line;
  for (let pass = 0; pass < 6; pass++) {
    let improved = false;
    for (let i = 1; i < arcs.length && !spent(ctx); i++) {
      const a = arcs[i], prev = arcs[i - 1];
      if (!a || !prev) continue;
      const deps = cur.legs.map((l) => l.dep_week_min);
      // the week's minutes from the first leg forward, unwrapped
      const abs = deps.map((d, k) => (k === 0 ? d : 0));
      for (let k = 1; k < deps.length; k++) abs[k] = (abs[k - 1] ?? 0) + mod((deps[k] ?? 0) - (deps[k - 1] ?? 0), WEEK);
      const landed = (abs[i - 1] ?? 0) + prev.block;
      const nextDep = i + 1 < arcs.length ? abs[i + 1] ?? 0 : (abs[0] ?? 0) + WEEK;
      const latest = nextDep - a.block - ctx.turn;
      for (const d of candidates(ctx, a, landed, landed + ctx.turn, latest)) {
        if (d === abs[i]) continue;
        const trial = abs.slice();
        trial[i] = d;
        const got = evaluate(ctx, arcs, trial, cur.start_hub);
        if (got && better(got.score, cur.score)) { cur = got; improved = true; break; }
        if (spent(ctx)) return cur;
      }
    }
    if (!improved) break;
  }
  return cur;
}

/** Whether every arc can be reached from the start (the doubled graph is balanced, so a closed walk over every arc
 *  exists exactly when it is connected). */
function connected(arcs: readonly Arc[], start: string): boolean {
  const seen = new Set<string>([start]);
  const queue = [start];
  while (queue.length) {
    const at = queue.pop() ?? "";
    for (const a of arcs) if (a.from === at && !seen.has(a.to)) { seen.add(a.to); queue.push(a.to); }
  }
  return arcs.every((a) => seen.has(a.from) && seen.has(a.to));
}

/** The closed walks over the arcs from the start, each arc once, in a fixed order (depth first, the arcs in the routes'
 *  order, out before back, an arc back to the start last, so the walk only returns there when it must), handed to
 *  `visit` until it says stop or the walk's steps pass `maxSteps` (a dead end is backtracked, and a tangled set could
 *  take forever; the cap keeps the search deterministic). */
function circuits(arcs: readonly Arc[], start: string, maxSteps: number, visit: (walk: Arc[]) => boolean): void {
  const used = new Array<boolean>(arcs.length).fill(false);
  const walk: Arc[] = [];
  let stop = false, steps = 0;
  const go = (at: string) => {
    if (stop) return;
    if (walk.length === arcs.length) {
      if (at === start) stop = !visit(walk.slice());
      return;
    }
    if (++steps > maxSteps) { stop = true; return; }
    const next = arcs.map((a, k) => ({ a, k })).filter(({ a, k }) => !used[k] && a.from === at);
    for (const { a, k } of [...next.filter((x) => x.a.to !== start), ...next.filter((x) => x.a.to === start)]) {
      if (stop) return;
      used[k] = true;
      walk.push(a);
      go(a.to);
      walk.pop();
      used[k] = false;
    }
  };
  go(start);
}

/** The route sets tried, level by level: all the routes, then each with one dropped, then two… The next level is asked
 *  for only while nothing feasible has been found. The fixed routes are never dropped. */
function routeSets(all: readonly number[], fixed: ReadonlySet<number>, level: number): number[][] {
  const free = all.filter((r) => !fixed.has(r));
  if (level > free.length) return [];
  const out: number[][] = [];
  const drop = (from: number, chosen: number[]) => {
    if (chosen.length === level) { out.push(all.filter((r) => !chosen.includes(r))); return; }
    for (let k = from; k < free.length; k++) drop(k + 1, [...chosen, free[k] ?? -1]);
  };
  drop(0, []);
  return out;
}

/** Numbers the line's legs from the airline's pool at its start hub: pairs above the highest in use in the base's block
 *  (schedule.nextFlightNumbers: flight_legs and the base's last number), skipping any taken by a plan card
 *  (usedFlightNumbers); the first traversal of a route takes the odd number, the way back the next. */
function numberLegs(ctx: Ctx, line: Line, used: ReadonlySet<number>): void {
  const base: BaseRow | undefined = ctx.rules.bases.find((b) => b.airport_code === line.start_hub && b.airline_id === ctx.airlineId)
    ?? ctx.rules.bases.find((b) => b.airline_id === ctx.airlineId && ctx.hubs.includes(b.airport_code))
    ?? ctx.rules.bases.find((b) => b.airline_id === ctx.airlineId && b.is_main);
  if (!base) throw new RulesError(`airline ${ctx.airlineId} has no base at ${line.start_hub} or any of the hubs: no flight-number pool`);
  const np = nextFlightNumbers(ctx.rules, base);
  const to = np.pool?.to ?? (() => {
    const from = base.flight_no_from ?? 0;
    const next = Math.min(...ctx.rules.bases.filter((b) => b.airline_id === base.airline_id && b.flight_no_from != null && b.flight_no_from > from).map((b) => b.flight_no_from as number), Infinity);
    return Number.isFinite(next) ? next - 1 : null;
  })();
  let n = np.out;
  const taken = new Set<number>(used);
  const pairNo = new Map<string, number>();
  const picked: number[] = [];
  for (const l of line.legs) {
    const k = pairKey(l.from, l.to);
    let no = pairNo.get(k);
    if (no == null) {
      while (taken.has(n) || taken.has(n + 1)) n += 2;
      if (to != null && n + 1 > to) throw new RulesError(`the flight-number pool at ${base.airport_code} (${base.flight_no_from ?? np.pool?.from}–${to}) has no pair left for ${l.from}–${l.to}`);
      no = n;
      pairNo.set(k, no);
      picked.push(no, no + 1);
      n += 2;
      l.flight_no = no;
    } else l.flight_no = no + 1;
  }
  line.flight_numbers = { base: base.airport_code, from: np.out, to, used: picked };
}

/** The 7 aircraft cards of a line (the spec's formula): aircraft k, offset k − 1, flies line day d on weekday
 *  ((d + k − 2) mod 7) + 1; each card is the whole line, shifted. */
export function lineCards(line: Line, type: string, airlineId: number): (Card & { line_day_offset: number })[] {
  const out: (Card & { line_day_offset: number })[] = [];
  for (let k = 1; k <= 7; k++) {
    const legs: CardLeg[] = line.legs.map((l) => ({
      flight_no: l.flight_no, origin_code: l.from, dest_code: l.to, days_utc: [mod(l.line_day + k - 2, 7) + 1], dep_utc_min: l.dep_utc_min,
      block_min: l.block_min, service_code: l.service_code,
    }));
    out.push({ aircraft: null, type, airline: airlineId, line_day_offset: k - 1, legs });
  }
  return out;
}

/** The best 7-day line; see the top of this file. */
export function optimiseLine(rules: Rules, opts: LineOptions, existing: readonly TimedLeg[] = timedLegs(rules)): LineAnswer {
  const type = findType(rules, opts.type);
  if (!type) throw new RulesError(`no aircraft type ${String(opts.type)} in the input`);
  if (!rules.airlines.has(opts.airlineId)) throw new RulesError(`no airline ${opts.airlineId} in the input`);
  if (!opts.hubs?.length) throw new RulesError("give the hubs the line may start at (where its connections count)");
  if (!opts.routes?.length) throw new RulesError("no routes to plan");
  if (!(opts.step > 0)) throw new RulesError("the ladder's step must be above 0");
  for (const h of opts.hubs) if (!rules.airports.has(h)) throw new RulesError(`no airport ${h} in the input`);
  const airlineId = opts.airlineId;
  const turn = turnNeed(rules, type, airlineId);
  const keep = type.ground_keep_min, mc = type.maint_per_cycle, mh = type.maint_per_hour;
  if (keep == null || mc == null || mh == null) throw new RulesError(`aircraft type ${type.name} lacks maint_per_cycle, maint_per_hour or ground_keep_min`);
  const minGround = settingNumber(rules, "maint_min_ground_min", airlineId);
  const minPct = settingNumber(rules, "maintenance_min_pct", airlineId);
  const gapLimit = setting(rules, "maintenance_max_gap_h", airlineId) === undefined ? null : settingNumber(rules, "maintenance_max_gap_h", airlineId);
  const sameRoute = worldRuleNumber(rules, "same_route_gap_min");
  const targetH = planTargetH(rules);
  // the routes, each named once, the fixed ones among them; each within reach
  const pairs: RoutePair[] = [];
  const seen = new Set<string>();
  for (const p of [...(opts.fixed ?? []), ...opts.routes]) {
    if (!p || p.length !== 2 || p[0] === p[1]) throw new RulesError(`a route needs two different airports: ${JSON.stringify(p)}`);
    for (const c of p) if (!rules.airports.has(c)) throw new RulesError(`no airport ${c} in the input (route ${routeName(p)})`);
    if (seen.has(pairOf(p))) continue;
    seen.add(pairOf(p));
    pairs.push(p);
  }
  const fixedIdx = new Set<number>();
  for (const f of opts.fixed ?? []) fixedIdx.add(pairs.findIndex((p) => pairOf(p) === pairOf(f)));
  const range = opts.rangeKm ?? (type.range_km == null ? null : Number(type.range_km));
  if (range == null) throw new RulesError(`aircraft_types.range_km is missing for the ${type.name}: the input doesn't carry its reach (give it as --range)`);
  const arcsOf = pairs.map((p, r): [Arc, Arc] => {
    const d = distanceBetween(rules, p[0], p[1], airlineId);
    if (!d) throw new RulesError(`no distance for ${routeName(p)}: no route and no airport positions`);
    if (d.km > range) throw new RulesError(`${routeName(p)} is ${d.km.toLocaleString("en-US")} km, beyond the ${type.name}'s reach of ${range.toLocaleString("en-US")} km (aircraft_types.range_km)`);
    const b = blockFor(rules, p[0], p[1], type.id, airlineId).block_min;
    return [{ route: r, from: p[0], to: p[1], block: b }, { route: r, from: p[1], to: p[0], block: b }];
  });
  const hubs = [...new Set(opts.hubs)];
  const limits = new Map(hubs.map((h) => [h, connectionLimits(rules, h)] as const));
  const short = new Map(hubs.map((h) => [h, targetLimits(rules, h, limits.get(h), targetH)] as const));
  const ladders = new Map<string, number[]>(), arrivals = new Map<string, number[]>();
  for (const h of hubs) {
    const b = baseAt(rules, h);
    const wins = b && hasBanks(b) ? bankWindows(rules, b) : [];
    const times: number[] = [];
    for (const w of wins) for (let t = 0; t <= mod(w.dep_end - w.dep, DAY); t += opts.step) times.push(mod(w.dep + t, DAY));
    // a hub with no bank windows (a focus city, or no bank times set): every half hour of the day, a search setting
    if (!times.length) for (let t = 0; t < DAY; t += NO_BANKS_STEP) times.push(t);
    ladders.set(h, [...new Set(times)].sort((a, b) => a - b));
    if (wins.length) arrivals.set(h, wins.map((w) => w.arr_end));
  }
  const arrAt = new Map<string, TimedLeg[]>(), depAt = new Map<string, TimedLeg[]>();
  for (const l of existing) {
    if (limits.has(l.dest)) arrAt.set(l.dest, [...(arrAt.get(l.dest) ?? []), l]);
    if (limits.has(l.origin)) depAt.set(l.origin, [...(depAt.get(l.origin) ?? []), l]);
  }
  const answer: LineAnswer = {
    airline_id: airlineId, type: type.name, hubs, routes: pairs.map(routeName), fixed: [...fixedIdx].map((i) => routeName(pairs[i] ?? ["?", "?"])), step: opts.step,
    turn_min: turn, connection_target_h: targetH, maintenance_max_gap_h: gapLimit, range_km: range,
    search: { route_sets: 0, circuits: 0, chains: 0, work: 0, lines_evaluated: 0, feasible: 0, finished: true, note: "" },
    rejected: { hours: 0, not_connected: 0, no_fit: 0, night_ban: 0, turn: 0, route_gap: 0, maintenance: 0, spacing: 0 },
    best: null,
  };
  const ctx: Ctx = {
    rules, type, airlineId, hubs, routeNames: pairs.map(routeName), turn, keep: Number(keep), minGround, minPct, gapLimitMin: gapLimit == null ? null : gapLimit * 60, sameRoute,
    step: opts.step, beam: opts.beam ?? 12, existing, limits, short, ladders, arrivals, arrAt, depAt, answer,
    budget: { work: opts.budget?.work ?? null, timeUp: opts.budget?.timeUp ?? null }, out: false,
  };
  let best: Line | null = null;
  let bestArcs: Arc[] | null = null;
  const all = pairs.map((_, i) => i);
  for (let level = 0; level <= all.length && !spent(ctx); level++) {
    if (level > 0 && best) break;
    const sets = routeSets(all, fixedIdx, level);
    if (!sets.length) break;
    for (const set of sets) {
      if (spent(ctx)) break;
      answer.search.route_sets++;
      const arcs = set.flatMap((r) => arcsOf[r] ?? []);
      const blockSum = arcs.reduce((s, a) => s + a.block, 0);
      if (blockSum + arcs.length * turn > WEEK) { answer.rejected.hours++; continue; }
      const inSet = new Set(arcs.map((a) => a.from));
      const starts = hubs.filter((h) => inSet.has(h));
      if (!starts.length || !starts.some((h) => connected(arcs, h))) { answer.rejected.not_connected++; continue; }
      let any = false;
      for (const start of starts) {
        if (spent(ctx)) break;
        circuits(arcs, start, CIRCUIT_STEPS, (walk) => {
          any = true;
          answer.search.circuits++;
          const first = walk[0];
          if (!first) return true;
          const t0s = ladders.get(start) ?? [];
          for (const local of t0s) {
            if (spent(ctx)) return false;
            const t0 = mod(local - utcOffsetMin(rules, start), DAY);
            const got = chain(ctx, walk, t0, start, best);
            if (got !== best) { best = got; bestArcs = walk; }
          }
          return !spent(ctx);
        });
      }
      if (!any) answer.rejected.not_connected++;
    }
  }
  if (best && bestArcs) {
    best = polish(ctx, bestArcs, best);
    numberLegs(ctx, best, new Set(opts.usedFlightNumbers ?? []));
    best.cards = lineCards(best, type.name, airlineId);
  }
  answer.search.finished = !ctx.out;
  answer.search.note = ctx.out
    ? `best found with ${answer.search.lines_evaluated} lines evaluated, search not finished (the budget ran out: ${answer.search.work} of ${ctx.budget.work ?? "the time"})`
    : `search finished: ${answer.search.lines_evaluated} lines evaluated, ${answer.search.feasible} feasible`;
  answer.best = best;
  return answer;
}
