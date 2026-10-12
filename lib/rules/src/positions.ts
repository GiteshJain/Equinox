// positions: where each aircraft is at a given UTC moment, for the live map: in the air between two airports with the
// share of the leg flown, or on the ground at an airport since its last landing and until its next departure. The
// moment is an argument; the library never reads a clock.
// The old code it follows: the old planner's and the website's map code (eqAirborne: in the air when the share flown is
// strictly between 0 and 1, across the week's wrap).
import { sequenceWeek, weekLegsOf } from "./aircraftWeek.js";
import { timedLegs } from "./block.js";
import { typeOfAircraft } from "./input.js";
import { WEEK, mod, weekMinuteAt } from "./time.js";
import type { Rules, TimedLeg } from "./types.js";

export interface Position {
  aircraft_id: number;
  registration: string;
  airline_id: number;
  state: "air" | "ground" | "idle";
  /** In the air: the leg, its airports and the share flown (0 to 1). */
  leg_id: number | null;
  flight_no: number | null;
  from: string | null;
  to: string | null;
  share: number | null;
  /** On the ground (or idle at its base): where, since its last landing and until its next departure (minutes of the
   *  week, UTC). */
  at: string | null;
  since_utc: number | null;
  until_utc: number | null;
}

/** Every aircraft with flights, and every active one without, at the moment (an ISO time or milliseconds). */
export function positionsAt(rules: Rules, moment: string | number, legs: readonly TimedLeg[] = timedLegs(rules)): Position[] {
  const m = weekMinuteAt(moment);
  const out: Position[] = [];
  for (const a of rules.aircraft.values()) {
    const mine = legs.filter((l) => l.aircraft_id === a.id);
    const base: Position = {
      aircraft_id: a.id, registration: a.registration, airline_id: a.airline_id, state: "idle", leg_id: null, flight_no: null,
      from: null, to: null, share: null, at: a.base_code ?? null, since_utc: null, until_utc: null,
    };
    if (!mine.length) {
      if (a.status === "active") out.push(base);
      continue;
    }
    const week = sequenceWeek(rules, mine.flatMap((l) => weekLegsOf(rules, l)), typeOfAircraft(rules, a.id), a.airline_id);
    let air: Position | null = null;
    for (const l of week) {
      for (const w of [-WEEK, 0, WEEK]) {
        const p = (m - (l.dep_utc + w)) / l.block_min;
        if (p > 0 && p < 1 && !air) air = { ...base, state: "air", leg_id: l.leg_id, flight_no: l.flight_no, from: l.origin, to: l.dest, share: p, at: null };
      }
    }
    if (air) {
      out.push(air);
      continue;
    }
    let last = week[0], next = week[0];
    for (const l of week) {
      if (last && mod(m - l.arr_utc, WEEK) < mod(m - last.arr_utc, WEEK)) last = l;
      if (next && mod(l.dep_utc - m, WEEK) < mod(next.dep_utc - m, WEEK)) next = l;
    }
    out.push({ ...base, state: "ground", at: last?.dest ?? null, since_utc: last?.arr_utc ?? null, until_utc: next?.dep_utc ?? null });
  }
  return out.sort((x, y) => x.aircraft_id - y.aircraft_id);
}
