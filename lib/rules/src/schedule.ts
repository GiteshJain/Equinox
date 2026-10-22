// schedule: the checks across the whole schedule (manual §4 and §9).
//   - night bans (world_airports.night_ban_from/to, local, both ends included) hit by a departure or an arrival;
//   - a second daily closer than second_daily_gap_h to another flight on the same route (and the game's own
//     same_route_gap_min between departures on a route, world_rules);
//   - a flight number used twice: one airline's number on two legs leaving on the same local weekday at their origin;
//   - departures a week per airport, against world_rules.departures_per_airport_week (per player: all the legs given);
//     Home warns from airport_cap_warning_pct of that cap, and calls it bad at the cap (airportCapWarnings);
//   - the next free flight-number pair at a base: the next odd number above the highest in use in its block; at a station
//     (since 22 Oct, manual §2) in the airline's one station pool, station_flight_no_from to station_flight_no_to.
// The old code it follows: the old planner's attention checks (banAt, flightClashes, the airport caps) and nextPair.
import { inNightBan, nightBanAt } from "./airport.js";
import { departuresOf } from "./connections.js";
import { timedLegs } from "./block.js";
import { RulesError, settingNumber, worldRuleNumber } from "./input.js";
import { DAY, WEEK, clock, localDays, mod, toLocal } from "./time.js";
import type { BaseRow, Rules, TimedLeg } from "./types.js";

export interface NightBanHit {
  leg_id: number;
  flight_no: number | null;
  airport: string;
  what: "departs" | "arrives";
  local: string;
  ban: string;
}

/** Every departure or arrival inside the airport's night ban. */
export function nightBanHits(rules: Rules, legs: readonly TimedLeg[] = timedLegs(rules)): NightBanHit[] {
  const out: NightBanHit[] = [];
  for (const l of legs) {
    const dep = toLocal(rules, l.origin, l.dep_utc_min, DAY), arr = toLocal(rules, l.dest, l.dep_utc_min + l.block_min, DAY);
    if (inNightBan(rules, l.origin, dep)) out.push({ leg_id: l.id, flight_no: l.flight_no, airport: l.origin, what: "departs", local: clock(dep), ban: nightBanAt(rules, l.origin)?.text ?? "" });
    if (inNightBan(rules, l.dest, arr)) out.push({ leg_id: l.id, flight_no: l.flight_no, airport: l.dest, what: "arrives", local: clock(arr), ban: nightBanAt(rules, l.dest)?.text ?? "" });
  }
  return out;
}

/** The shortest time between any departure of one leg and any of another, across the week (either way round). */
export function closestDepartures(a: TimedLeg, b: TimedLeg): number {
  let best = Infinity;
  for (const x of departuresOf(a)) for (const y of departuresOf(b)) best = Math.min(best, mod(x - y, WEEK), mod(y - x, WEEK));
  return best;
}

export interface RouteGapHit {
  leg_ids: [number, number];
  origin: string;
  dest: string;
  gap_min: number;
  need_min: number;
  rule: "second_daily_gap_h" | "same_route_gap_min";
}

/** Two flights on the same route (origin to destination) closer than the second-daily gap, or than the game's gap
 *  between departures on a route. */
export function routeGapHits(rules: Rules, legs: readonly TimedLeg[] = timedLegs(rules)): RouteGapHit[] {
  const sameRoute = worldRuleNumber(rules, "same_route_gap_min");
  const groups = new Map<string, TimedLeg[]>();
  for (const l of legs) {
    const k = `${l.origin}>${l.dest}`;
    const g = groups.get(k);
    if (g) g.push(l);
    else groups.set(k, [l]);
  }
  const out: RouteGapHit[] = [];
  for (const g of groups.values()) {
    for (let i = 0; i < g.length; i++) {
      for (let j = i + 1; j < g.length; j++) {
        const a = g[i], b = g[j];
        if (!a || !b) continue;
        const gap = closestDepartures(a, b);
        const second = settingNumber(rules, "second_daily_gap_h", a.airline_id) * 60;
        if (gap < sameRoute) out.push({ leg_ids: [a.id, b.id], origin: a.origin, dest: a.dest, gap_min: gap, need_min: sameRoute, rule: "same_route_gap_min" });
        else if (gap < second) out.push({ leg_ids: [a.id, b.id], origin: a.origin, dest: a.dest, gap_min: gap, need_min: second, rule: "second_daily_gap_h" });
      }
    }
  }
  return out;
}

export interface FlightNumberClash {
  airline_id: number;
  flight_no: number;
  leg_ids: [number, number];
  /** The local weekdays both leave on, ISO. */
  days: number[];
}

/** One airline's flight number on two legs leaving on the same local weekday at their origins. */
export function flightNumberClashes(rules: Rules, legs: readonly TimedLeg[] = timedLegs(rules)): FlightNumberClash[] {
  const seen = new Map<string, { l: TimedLeg; days: number[] }[]>();
  const out: FlightNumberClash[] = [];
  for (const l of legs) {
    if (l.flight_no == null) continue;
    const k = `${l.airline_id}|${l.flight_no}`;
    const days = localDays(rules, l.origin, l.days_utc, l.dep_utc_min);
    const prev = seen.get(k) ?? [];
    for (const p of prev) {
      const both = days.filter((d) => p.days.includes(d));
      if (both.length) out.push({ airline_id: l.airline_id, flight_no: l.flight_no, leg_ids: [p.l.id, l.id], days: both });
    }
    prev.push({ l, days });
    seen.set(k, prev);
  }
  return out;
}

export interface AirportDepartures {
  airport: string;
  departures_week: number;
  cap: number;
  over: boolean;
}

/** Departures a week from each airport, by all the legs given (the player's), against the game's cap. */
export function departuresPerAirport(rules: Rules, legs: readonly TimedLeg[] = timedLegs(rules)): AirportDepartures[] {
  const cap = worldRuleNumber(rules, "departures_per_airport_week");
  const n = new Map<string, number>();
  for (const l of legs) n.set(l.origin, (n.get(l.origin) ?? 0) + l.days_utc.length);
  return [...n.entries()].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1)).map(([airport, d]) => ({ airport, departures_week: d, cap, over: d > cap }));
}

export interface CapWarning extends AirportDepartures {
  /** airport_cap_warning_pct of the cap: Home warns from here. */
  warn_from: number;
  /** warn from warn_from, bad at the cap itself. */
  level: "warn" | "bad";
}

/** The airports whose departures a week reach airport_cap_warning_pct of the game's cap, busiest first: a warning, and
 *  bad at the cap. The old planner's Home: 4,000 departures a week of the 5,000 cap, bad at 5,000. */
export function airportCapWarnings(rules: Rules, legs: readonly TimedLeg[] = timedLegs(rules)): CapWarning[] {
  const pct = settingNumber(rules, "airport_cap_warning_pct");
  return departuresPerAirport(rules, legs).flatMap((d) => {
    const from = (d.cap * pct) / 100;
    return d.departures_week >= from ? [{ ...d, warn_from: from, level: d.departures_week >= d.cap ? ("bad" as const) : ("warn" as const) }] : [];
  });
}

export interface NextPair {
  base: string;
  airline_id: number;
  out: number;
  back: number;
  highest: number | null;
  from_schedule: number | null;
  last_used: number | null;
  /** At a station only: the airline's station pool (station_flight_no_from to station_flight_no_to), and whether it's
   *  full (no pair left in it: out and back are then past its end and mustn't be used). */
  pool?: { from: number; to: number };
  full?: boolean;
}

/** The next free flight-number pair at a station (manual §2, since 22 Oct): the next odd number above the highest the
 *  airline uses anywhere in its one station pool (station_flight_no_from to station_flight_no_to, an airline's override
 *  first), counting every leg of the airline numbered in the pool and every station's last_flight_no, so no two of its
 *  stations clash. A pool with no pair left says so (full). */
function nextStationNumbers(rules: Rules, base: BaseRow): NextPair {
  const al = base.airline_id;
  const from = settingNumber(rules, "station_flight_no_from", al), to = settingNumber(rules, "station_flight_no_to", al);
  const inPool = (n: number | null | undefined): n is number => n != null && n >= from && n <= to;
  let inSchedule = 0;
  for (const l of rules.legs) if (l.airline_id === al && inPool(l.flight_no)) inSchedule = Math.max(inSchedule, l.flight_no);
  const manualAll = rules.bases.filter((b) => b.airline_id === al && b.role === "station" && inPool(b.last_flight_no)).map((b) => b.last_flight_no as number);
  const manual = manualAll.length ? Math.max(...manualAll) : null;
  const hi = Math.max(inSchedule, manual ?? 0);
  const start = hi || from;
  const out = start % 2 === 0 ? start + 1 : start + 2;
  return {
    base: base.airport_code, airline_id: al, out, back: out + 1, highest: hi || null, from_schedule: inSchedule || null, last_used: manual,
    pool: { from, to }, full: out + 1 > to,
  };
}

/** The next free flight-number pair at a base: the next odd number above the highest in use in the base's block (the
 *  base's flight_no_from up to the airline's next block), counting the schedule and the base's last_flight_no. A station
 *  has no block: its pair comes from the airline's station pool (nextStationNumbers). */
export function nextFlightNumbers(rules: Rules, base: BaseRow): NextPair {
  if (base.role === "station") return nextStationNumbers(rules, base);
  const from = base.flight_no_from;
  if (from == null) throw new RulesError(`base ${base.airport_code} has no flight_no_from`);
  const nextFrom = Math.min(...rules.bases.filter((b) => b.airline_id === base.airline_id && b.flight_no_from != null && b.flight_no_from > from).map((b) => b.flight_no_from as number), Infinity);
  let inSchedule = 0;
  for (const l of rules.legs) {
    if (l.airline_id === base.airline_id && l.flight_no != null && l.flight_no >= from && l.flight_no < nextFrom) inSchedule = Math.max(inSchedule, l.flight_no);
  }
  const manual = base.last_flight_no ?? null;
  const hi = Math.max(inSchedule, manual ?? 0);
  const start = hi || from;
  const out = start % 2 === 0 ? start + 1 : start + 2;
  return { base: base.airport_code, airline_id: base.airline_id, out, back: out + 1, highest: hi || null, from_schedule: inSchedule || null, last_used: manual };
}

/** Every schedule check at once. */
export function scheduleChecks(rules: Rules, legs: readonly TimedLeg[] = timedLegs(rules)) {
  return {
    night_bans: nightBanHits(rules, legs),
    route_gaps: routeGapHits(rules, legs),
    flight_number_clashes: flightNumberClashes(rules, legs),
    airports_over_cap: departuresPerAirport(rules, legs).filter((a) => a.over),
  };
}
