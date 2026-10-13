// aircraftWeek: one aircraft's week, the Tails screen's figures. Every departure of every leg it flies, in UTC order,
// with the ground time to the next one; legs a week, block hours a day and the routes flown.
// The old code it follows: the old planner's legsForTail and the Tails screen (renderTailsCore).
import { timedLegs } from "./block.js";
import { findAircraft, typeOfAircraft } from "./input.js";
import { WEEK, dayOf, mod, toLocal, weekMinute } from "./time.js";
import { checkTurn, type TurnCheck } from "./turns.js";
import type { AircraftRow, AircraftTypeRow, Rules, TimedLeg } from "./types.js";

/** One departure of a leg in the week. */
export interface WeekLeg {
  leg_id: number;
  flight_no: number | null;
  route_id: number | null;
  origin: string;
  dest: string;
  /** UTC weekday it departs, ISO. */
  day_utc: number;
  /** Minutes from Monday 00:00 UTC. */
  dep_utc: number;
  arr_utc: number;
  /** Local minutes of the week at its own airport. */
  dep_local: number;
  arr_local: number;
  block_min: number;
  block_source: "stored" | "estimate";
  /** Minutes on the ground until the aircraft's next departure; null when it flies only this one. */
  ground_min: number | null;
  /** The next departure leaves before this one lands. */
  overlap: boolean;
  /** The next departure starts where this one lands. */
  position_ok: boolean;
  /** The turn before the next departure, when there is one and it isn't an overlap. */
  turn: TurnCheck | null;
}

export interface AircraftWeek {
  aircraft_id: number;
  registration: string;
  airline_id: number;
  type: string | null;
  base_code: string | null;
  legs: WeekLeg[];
  legs_week: number;
  block_min_week: number;
  block_hours_day: number;
  routes: number;
  route_ids: number[];
  /** Ground gaps at least the type's target maintenance gap (gap_target_h), when the type has one. */
  gaps_at_target: number | null;
  /** Departures whose block is an estimate (no block_min stored). */
  estimated_legs: number;
}

/** A leg's departures in the week, unsorted. */
export function weekLegsOf(rules: Rules, l: TimedLeg): WeekLeg[] {
  return l.days_utc.map((d) => {
    const dep = weekMinute(d, l.dep_utc_min), arr = mod(dep + l.block_min, WEEK);
    return {
      leg_id: l.id, flight_no: l.flight_no, route_id: l.route_id, origin: l.origin, dest: l.dest, day_utc: dayOf(dep),
      dep_utc: dep, arr_utc: arr, dep_local: toLocal(rules, l.origin, dep), arr_local: toLocal(rules, l.dest, arr),
      block_min: l.block_min, block_source: l.block_source, ground_min: null, overlap: false, position_ok: true, turn: null,
    };
  });
}

/** Puts departures in order and works out each ground gap, overlap, position and turn. */
export function sequenceWeek(rules: Rules, list: WeekLeg[], type: AircraftTypeRow | undefined, airlineId: number | null): WeekLeg[] {
  const legs = list.map((x, i) => ({ x, i })).sort((a, b) => a.x.dep_utc - b.x.dep_utc || a.i - b.i).map((v) => ({ ...v.x }));
  const n = legs.length;
  const canTurn = !!type && type.min_turn_min != null;
  legs.forEach((cur, i) => {
    const nx = legs[(i + 1) % n];
    if (n < 2 || !nx) return;
    cur.ground_min = mod(nx.dep_utc - cur.arr_utc, WEEK);
    cur.overlap = mod(nx.dep_utc - cur.dep_utc, WEEK) < cur.block_min;
    cur.position_ok = cur.dest === nx.origin;
    cur.turn = canTurn && type && !cur.overlap ? checkTurn(rules, type, cur.ground_min, airlineId) : null;
  });
  return legs;
}

/** The week of an aircraft (by id or registration), from all the legs given (by default the input's). */
export function forAircraft(rules: Rules, aircraft: number | string | AircraftRow, legs: readonly TimedLeg[] = timedLegs(rules)): AircraftWeek | null {
  const a = typeof aircraft === "object" ? aircraft : findAircraft(rules, aircraft);
  if (!a) return null;
  const type = typeOfAircraft(rules, a.id);
  const mine = legs.filter((l) => l.aircraft_id === a.id);
  const week = sequenceWeek(rules, mine.flatMap((l) => weekLegsOf(rules, l)), type, a.airline_id);
  const blockWeek = week.reduce((s, l) => s + l.block_min, 0);
  const routeIds = [...new Set(week.map((l) => l.route_id).filter((r): r is number => r != null))];
  const target = type?.gap_target_h == null ? null : Number(type.gap_target_h) * 60;
  return {
    aircraft_id: a.id, registration: a.registration, airline_id: a.airline_id, type: type?.name ?? null, base_code: a.base_code ?? null,
    legs: week, legs_week: week.length, block_min_week: blockWeek, block_hours_day: blockWeek / 60 / 7,
    routes: routeIds.length, route_ids: routeIds,
    gaps_at_target: target == null ? null : week.filter((l) => l.ground_min != null && l.ground_min >= target).length,
    estimated_legs: week.filter((l) => l.block_source === "estimate").length,
  };
}
