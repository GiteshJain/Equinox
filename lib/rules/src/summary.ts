// summary: the whole schedule's key figures, as the planner's Home shows them (#18 build pull request 5, spec
// docs/specs/2026-10-13-home.md §2: key figures come from the library). For the group and for each airline:
//   aircraft: every aircraft in service (status active: the old planner's tails);
//   routes flying: every route that has a rotation (and is in the input);
//   flights a day: every departure in the week by an aircraft in service, ÷ 7;
//   seats a day: each of those departures' seats (its aircraft's cabin layout; the type's seats_max when it has no
//     layout; none when its layout has no seat count), ÷ 7.
// The old code it follows: the old planner's renderHome (fleet, routesActive, legsDay from legsForTail, seatsWk from
// computeFreq's seats × round trips × 2).
import { timedLegs } from "./block.js";
import { typeOfAircraft } from "./input.js";
import type { AircraftRow, Rules, TimedLeg } from "./types.js";

export interface KeyFigures {
  aircraft: number;
  routes_flying: number;
  flights_day: number;
  seats_day: number;
}

export interface SummaryFigures extends KeyFigures {
  /** The same for each airline of the input, in its order. */
  by_airline: (KeyFigures & { airline_id: number })[];
}

/** The seats an aircraft flies with: its cabin layout's, else its type's seats_max; 0 when its layout has no count. */
export function seatsOf(rules: Rules, a: AircraftRow): number {
  if (a.cabin_config_id != null) {
    const c = rules.configs.get(a.cabin_config_id);
    if (c) return c.seats ?? 0;
  }
  return typeOfAircraft(rules, a.id)?.seats_max ?? 0;
}

/** The key figures for the whole input and for each airline in it. */
export function keyFigures(rules: Rules, legs: readonly TimedLeg[] = timedLegs(rules)): SummaryFigures {
  // counted in whole departures and seats a week, and divided by 7 once at the end
  type Count = { aircraft: number; routes: number; departures: number; seats: number };
  const empty = (): Count => ({ aircraft: 0, routes: 0, departures: 0, seats: 0 });
  const all = empty();
  const per = new Map<number, Count>([...rules.airlines.keys()].map((id) => [id, empty()]));
  const of = (airlineId: number) => {
    let x = per.get(airlineId);
    if (!x) per.set(airlineId, (x = empty()));
    return x;
  };
  for (const a of rules.aircraft.values()) {
    if (a.status !== "active") continue;
    all.aircraft++;
    of(a.airline_id).aircraft++;
  }
  const routes = new Set<number>();
  for (const r of rules.rotations.values()) {
    const route = rules.routes.get(r.route_id);
    if (!route || routes.has(r.route_id)) continue;
    routes.add(r.route_id);
    all.routes++;
    of(route.airline_id).routes++;
  }
  for (const l of legs) {
    const a = l.aircraft_id == null ? undefined : rules.aircraft.get(l.aircraft_id);
    if (!a || a.status !== "active") continue;
    const n = l.days_utc.length, seats = seatsOf(rules, a) * n;
    const x = of(l.airline_id);
    all.departures += n;
    all.seats += seats;
    x.departures += n;
    x.seats += seats;
  }
  const figures = (x: Count): KeyFigures => ({ aircraft: x.aircraft, routes_flying: x.routes, flights_day: x.departures / 7, seats_day: x.seats / 7 });
  return { ...figures(all), by_airline: [...per.entries()].map(([airline_id, x]) => ({ airline_id, ...figures(x) })) };
}
