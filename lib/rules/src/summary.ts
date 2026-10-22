// summary: the whole schedule's key figures, as the planner's Home shows them (#18 build pull request 5, spec
// docs/specs/2026-10-13-home.md §2: key figures come from the library). For the group and for each airline:
//   aircraft: every aircraft in service (status active: the old planner's tails);
//   routes flying: every route that has a rotation (and is in the input);
//   flights a day: every departure in the week by an aircraft in service, ÷ 7;
//   seats a day: each of those departures' seats (its aircraft's cabin layout; the type's seats_max when it has no
//     layout; none when its layout has no seat count), ÷ 7.
// The old code it follows: the old planner's renderHome (fleet, routesActive, legsDay from legsForTail, seatsWk from
// computeFreq's seats × round trips × 2).
// Also, from the Building chat's review of pull request 5 (Home as the old Home shows it):
//   airlineCards: each airline's card at the foot of Home (the old renderHome's per[airline] and its airline grid):
//     aircraft in service, routes flying, flights and block hours a day of its aircraft (aircraftWeek), the lowest
//     maintenance among them (maintenance, with its level), departures with a short turn or a wrong position, tight
//     turns, flying (any flights), clean (flying, none short or tight, the lowest maintenance at its target), and its
//     bases, hubs before focus cities, each live when a flying route leaves from it;
//   now: the hero's figures at a moment (the old eqStats): aircraft in the air (positions), flights departing today (UTC
//     weekday) and in the next hour of today, aircraft in service and routes flying;
//   roundTrips: each flying route's round trips a week (the old routeSummary's rtWk: its rotations' outbound days).
import { forAircraft as weekOf } from "./aircraftWeek.js";
import { timedLegs } from "./block.js";
import { typeOfAircraft } from "./input.js";
import { ofWeek, type Maintenance } from "./maintenance.js";
import { positionsAt } from "./positions.js";
import { DAY, dayOf, weekMinuteAt } from "./time.js";
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

export interface CardBase {
  code: string;
  role: string;
  /** For a focus city, the hub it feeds. */
  parent_code: string | null;
  /** A flying route of the airline's leaves from it. */
  live: boolean;
}

export interface AirlineCard {
  airline_id: number;
  aircraft: number;
  routes: number;
  /** Departures a week of its aircraft in service ÷ 7, and their block hours a day, summed over its aircraft. */
  flights_day: number;
  block_hours_day: number;
  flying: boolean;
  /** The lowest maintenance among its aircraft in service with flights, or null when none has a figure. */
  lowest_maintenance: Maintenance | null;
  /** Departures a week followed by a short turn or a wrong position, and by a tight turn. */
  short_turns: number;
  tight_turns: number;
  /** Flying, with no short or tight turns and the lowest maintenance at its target. */
  clean: boolean;
  bases: CardBase[];
}

/** Each airline's card, in the input's airline order. */
export function airlineCards(rules: Rules, legs: readonly TimedLeg[] = timedLegs(rules)): AirlineCard[] {
  const keys = keyFigures(rules, legs);
  const flyingRoutes = [...new Set([...rules.rotations.values()].map((r) => r.route_id))].flatMap((id) => {
    const r = rules.routes.get(id);
    return r ? [r] : [];
  });
  return keys.by_airline.map((k) => {
    let flights = 0, block = 0, short = 0, tight = 0;
    let lowest: Maintenance | null = null;
    for (const a of rules.aircraft.values()) {
      if (a.airline_id !== k.airline_id || a.status !== "active") continue;
      const week = weekOf(rules, a, legs);
      if (!week || !week.legs.length) continue;
      flights += week.legs_week / 7;
      block += week.block_hours_day;
      short += week.legs.filter((l) => l.turn?.short || !l.position_ok).length;
      tight += week.legs.filter((l) => l.turn?.tight).length;
      const m = ofWeek(rules, typeOfAircraft(rules, a.id), a.airline_id, week.legs);
      if (m.ratio != null && (lowest == null || m.ratio < lowest.ratio)) lowest = m;
    }
    const from = new Set(flyingRoutes.filter((r) => r.airline_id === k.airline_id).map((r) => r.hub_code));
    // its hubs, then its focus cities; never its stations (since 22 Oct: a station is no base, manual §2)
    const bases = rules.bases.filter((b) => b.airline_id === k.airline_id && b.role !== "station")
      .map((b, i) => ({ b, i })).sort((x, y) => Number(x.b.role === "focus") - Number(y.b.role === "focus") || x.i - y.i)
      .map(({ b }) => ({ code: b.airport_code, role: b.role, parent_code: b.parent_code ?? null, live: from.has(b.airport_code) }));
    const flying = flights > 0;
    const low = lowest as Maintenance | null;
    return {
      airline_id: k.airline_id, aircraft: k.aircraft, routes: k.routes_flying, flights_day: flights, block_hours_day: block, flying,
      lowest_maintenance: low, short_turns: short, tight_turns: tight, clean: flying && !short && !tight && low?.level === "ok", bases,
    };
  });
}

export interface NowFigures {
  /** Aircraft in the air at the moment. */
  in_air: number;
  /** Departures on the moment's UTC weekday, and those of them leaving in the hour from the moment (not past midnight). */
  flights_today: number;
  departing_next_hour: number;
  aircraft: number;
  routes_flying: number;
}

/** The hero's figures at a moment (an ISO time or milliseconds; the library never reads a clock). */
export function now(rules: Rules, moment: string | number, legs: readonly TimedLeg[] = timedLegs(rules)): NowFigures {
  const m = weekMinuteAt(moment), day = dayOf(m), minute = Math.floor(m % DAY);
  let today = 0, nextHour = 0;
  for (const l of legs) {
    if (!l.days_utc.includes(day)) continue;
    today++;
    const dt = l.dep_utc_min - minute;
    if (dt >= 0 && dt < 60) nextHour++;
  }
  const k = keyFigures(rules, legs);
  return {
    in_air: positionsAt(rules, moment, legs).filter((p) => p.state === "air").length,
    flights_today: today, departing_next_hour: nextHour, aircraft: k.aircraft, routes_flying: k.routes_flying,
  };
}

/** Each flying route's round trips a week: its rotations' outbound days (the return's when it has no outbound). */
export function roundTrips(rules: Rules): { route_id: number; airline_id: number; round_trips_week: number }[] {
  const legsOf = new Map<number, { leg_no: number | null | undefined; days: number }[]>();
  for (const l of rules.legs) {
    if (l.rotation_id == null) continue;
    legsOf.set(l.rotation_id, [...(legsOf.get(l.rotation_id) ?? []), { leg_no: l.leg_no, days: l.days_utc.length }]);
  }
  const out = new Map<number, { route_id: number; airline_id: number; round_trips_week: number }>();
  for (const r of rules.rotations.values()) {
    const route = rules.routes.get(r.route_id);
    if (!route) continue;
    const ls = legsOf.get(r.id) ?? [];
    const days = (ls.find((l) => l.leg_no === 1) ?? ls[0])?.days ?? 0;
    const x = out.get(route.id) ?? { route_id: route.id, airline_id: route.airline_id, round_trips_week: 0 };
    x.round_trips_week += days;
    out.set(route.id, x);
  }
  return [...out.values()];
}
