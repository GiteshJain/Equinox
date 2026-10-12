// A plan card checked against every rule (manual §4: "every new plan card and every retime is checked at both ends").
// The card is one aircraft's flying: its legs replace whatever that aircraft flies today, and are checked with the rest
// of the schedule. Legs are given as flight_legs stores them (UTC weekdays and minute) or as the game shows them (local
// weekdays and "HH:MM" at the origin); a leg without block_min gets the estimate.
import { forAircraft as aircraftWeek } from "./aircraftWeek.js";
import { bankOfArrival, bankOfDeparture, baseAt, isFocus } from "./banks.js";
import { blockFor, timedLegs } from "./block.js";
import { connectionsAtBothEnds } from "./connections.js";
import { RulesError, findAircraft, findType } from "./input.js";
import { ofWeek as maintenanceOfWeek } from "./maintenance.js";
import { departuresPerAirport, flightNumberClashes, nightBanHits, routeGapHits } from "./schedule.js";
import { DAY, clock, fromLocal, parseClock, toLocal } from "./time.js";
import type { AircraftRow, Rules, TimedLeg } from "./types.js";

export interface CardLeg {
  flight_no?: number | null;
  origin_code: string;
  dest_code: string;
  days_utc?: number[] | null;
  dep_utc_min?: number | null;
  days_local?: number[] | null;
  dep_local?: string | null;
  block_min?: number | null;
}

export interface Card {
  /** The aircraft the card plans, by registration or id (its type and airline come with it). */
  aircraft?: string | number | null;
  /** For an aircraft not in the input yet: its type (id or name) and airline (id, code or name). */
  type?: string | number | null;
  airline?: string | number | null;
  legs: CardLeg[];
}

function airlineOf(rules: Rules, x: string | number | null | undefined): number | null {
  if (x == null) return null;
  for (const a of rules.airlines.values()) {
    if (a.id === x || a.iata_code === x || a.planner_name === x || a.public_name === x || a.game_name === x) return a.id;
  }
  return null;
}

/** Checks a plan card; see the top of this file. */
export function checkCard(rules: Rules, card: Card) {
  if (!card || !Array.isArray(card.legs) || !card.legs.length) throw new RulesError("the card has no legs");
  const ac: AircraftRow | undefined = card.aircraft == null ? undefined : findAircraft(rules, card.aircraft);
  if (card.aircraft != null && !ac) throw new RulesError(`no aircraft ${String(card.aircraft)} in the input`);
  const type = findType(rules, card.type ?? ac?.aircraft_type_id ?? null);
  if (!type) throw new RulesError("the card needs an aircraft in the input, or a type");
  const airlineId = ac?.airline_id ?? airlineOf(rules, card.airline);
  if (airlineId == null) throw new RulesError("the card needs an aircraft in the input, or an airline");

  const legs: TimedLeg[] = card.legs.map((l, i) => {
    let days = l.days_utc ?? null, dep = l.dep_utc_min ?? null;
    if (dep == null && l.dep_local != null) {
      const m = parseClock(l.dep_local);
      if (m == null) throw new RulesError(`leg ${i + 1}: dep_local ${l.dep_local} isn't a clock time`);
      const u = fromLocal(rules, l.origin_code, l.days_local?.length ? l.days_local : [1, 2, 3, 4, 5, 6, 7], m);
      days = u.days_utc;
      dep = u.dep_utc_min;
    }
    if (dep == null) throw new RulesError(`leg ${i + 1}: give dep_utc_min or dep_local`);
    const est = l.block_min == null ? blockFor(rules, l.origin_code, l.dest_code, type.id, airlineId).block_min : null;
    return {
      id: -(i + 1), airline_id: airlineId, rotation_id: null, route_id: null, leg_no: null, flight_no: l.flight_no ?? null,
      origin: l.origin_code, dest: l.dest_code, aircraft_id: ac?.id ?? null, days_utc: (days?.length ? days : [1, 2, 3, 4, 5, 6, 7]).slice().sort((a, b) => a - b),
      dep_utc_min: dep, block_min: l.block_min ?? est ?? 0, block_source: l.block_min == null ? "estimate" : "stored", order: -1,
    };
  });
  const cardIds = new Set(legs.map((l) => l.id));
  const others = timedLegs(rules).filter((l) => ac == null || l.aircraft_id !== ac.id);
  const network = [...others, ...legs];
  const involves = (ids: readonly number[]) => ids.some((x) => cardIds.has(x));

  const pseudo: AircraftRow = ac ?? { id: -1, registration: "(card)", airline_id: airlineId, aircraft_type_id: type.id };
  const week = aircraftWeek(rules, pseudo, legs.map((l) => ({ ...l, aircraft_id: pseudo.id })));
  const maint = maintenanceOfWeek(rules, type, airlineId, week?.legs ?? []);
  const perLeg = legs.map((l, i) => {
    const depLocal = toLocal(rules, l.origin, l.dep_utc_min, DAY), arrLocal = toLocal(rules, l.dest, l.dep_utc_min + l.block_min, DAY);
    const bo = baseAt(rules, l.origin, airlineId), bd = baseAt(rules, l.dest, airlineId);
    const ends = connectionsAtBothEnds(rules, network, l);
    return {
      leg: i + 1, flight_no: l.flight_no, from: l.origin, to: l.dest, days_utc: l.days_utc, dep_utc: clock(l.dep_utc_min),
      dep_local: clock(depLocal), arr_local: clock(arrLocal), block_min: l.block_min, block_source: l.block_source,
      bank_out: bo && !isFocus(bo) ? bankOfDeparture(rules, bo, depLocal)?.n ?? 0 : null,
      bank_in: bd && !isFocus(bd) ? bankOfArrival(rules, bd, arrLocal) : null,
      feeders: ends.feeders.length, onward: ends.onward.length,
      feeders_list: ends.feeders.map((x) => ({ leg_id: x.leg.id, from: x.leg.origin, flight_no: x.leg.flight_no, days: x.days, gap_min: x.gap_min })),
      onward_list: ends.onward.map((x) => ({ leg_id: x.leg.id, to: x.leg.dest, flight_no: x.leg.flight_no, days: x.days, gap_min: x.gap_min })),
    };
  });
  const nightBans = nightBanHits(rules, legs);
  const routeGaps = routeGapHits(rules, network).filter((h) => involves(h.leg_ids));
  const clashes = flightNumberClashes(rules, network).filter((c) => involves(c.leg_ids));
  const touched = new Set(legs.flatMap((l) => [l.origin, l.dest]));
  const caps = departuresPerAirport(rules, network).filter((a) => touched.has(a.airport));
  const turns = (week?.legs ?? []).filter((w) => w.turn && !w.turn.ok);
  const problems: string[] = [];
  for (const w of week?.legs ?? []) {
    if (w.overlap) problems.push(`${w.origin}–${w.dest} day ${w.day_utc}: the next flight leaves before it lands`);
    else if (!w.position_ok) problems.push(`${w.origin}–${w.dest} day ${w.day_utc}: the next flight doesn't leave from ${w.dest}`);
    if (w.turn?.short) problems.push(`${w.origin}–${w.dest} day ${w.day_utc}: turn of ${w.ground_min} min at ${w.dest}, under the game's ${w.turn.min_turn_min}`);
    else if (w.turn?.tight) problems.push(`${w.origin}–${w.dest} day ${w.day_utc}: turn of ${w.ground_min} min at ${w.dest}, under the ${w.turn.need_min} min with the margin`);
  }
  if (maint.ratio == null) problems.push(`maintenance can't be worked out: ${"reason" in maint ? maint.reason : ""}`);
  else if (maint.level === "bad") problems.push(`maintenance ${maint.pct}%, under ${maint.min_pct}%`);
  for (const h of nightBans) problems.push(`${h.airport}: ${h.what} ${h.local}, inside its night ban (${h.ban})`);
  for (const h of routeGaps) problems.push(`${h.origin}–${h.dest}: ${h.gap_min} min from another flight on the route (at least ${h.need_min}, ${h.rule})`);
  for (const c of clashes) problems.push(`flight ${c.flight_no} is used twice on day(s) ${c.days.join(", ")}`);
  for (const a of caps) if (a.over) problems.push(`${a.airport}: ${a.departures_week} departures a week, over the cap of ${a.cap}`);
  return {
    aircraft: ac?.registration ?? null, type: type.name, airline_id: airlineId, ok: problems.length === 0, problems,
    legs: perLeg, turns_not_ok: turns.length, maintenance: maint, night_bans: nightBans, route_gaps: routeGaps, flight_number_clashes: clashes,
    departures: caps, legs_week: week?.legs_week ?? 0, block_hours_day: week?.block_hours_day ?? 0,
  };
}
