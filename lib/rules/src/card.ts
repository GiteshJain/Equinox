// A plan card checked against every rule (manual §4: "every new plan card and every retime is checked at both ends").
// The card is one aircraft's flying: its legs replace whatever that aircraft flies today, and are checked with the rest
// of the schedule. Legs are given as flight_legs stores them (UTC weekdays and minute) or as the game shows them (local
// weekdays and "HH:MM" at the origin); a leg without block_min gets the estimate. Each leg's service code is checked
// against the one its route's distance calls for (service.ts's checkLegs, #18 build pull request 10): a wrong code or
// none is a problem naming the leg, the code given and the code wanted. Since 21 Oct (manual §5; spec
// docs/specs/2026-10-21-cabins-new-rule.md §3) the card's cabin is checked too: cabinFor() works out the cabin the rule
// calls for, and a card whose cabin is missing or differs from it is a problem with the reason.
import { forAircraft as aircraftWeek } from "./aircraftWeek.js";
import { bankOfArrival, bankOfDeparture, baseAt, isFocus } from "./banks.js";
import { blockFor, timedLegs } from "./block.js";
import { connectionsAtBothEnds } from "./connections.js";
import { RulesError, findAircraft, findType, pairKey, setting, settingNumber } from "./input.js";
import { ofWeek as maintenanceOfWeek } from "./maintenance.js";
import { departuresPerAirport, flightNumberClashes, nightBanHits, routeGapHits } from "./schedule.js";
import { checkLegs as serviceCheck, issueWords as serviceWords } from "./service.js";
import { DAY, clock, fromLocal, parseClock, toLocal } from "./time.js";
import type { AircraftRow, AircraftTypeRow, CabinConfigRow, Rules, TimedLeg } from "./types.js";

export interface CardLeg {
  flight_no?: number | null;
  origin_code: string;
  dest_code: string;
  days_utc?: number[] | null;
  dep_utc_min?: number | null;
  days_local?: number[] | null;
  dep_local?: string | null;
  block_min?: number | null;
  /** The service code the card gives the leg (plan_card_legs.service_code): S1, S2, …, or Ryanair's R. */
  service_code?: string | null;
}

export interface Card {
  /** The aircraft the card plans, by registration or id (its type and airline come with it). */
  aircraft?: string | number | null;
  /** For an aircraft not in the input yet: its type (id or name) and airline (id, code or name). */
  type?: string | number | null;
  airline?: string | number | null;
  /** The card's cabin (plan_cards.config_id): a cabin_configs id, or a layout's code ("321-LP"); none = not chosen yet. */
  config_id?: number | string | null;
  legs: CardLeg[];
}

function airlineOf(rules: Rules, x: string | number | null | undefined): number | null {
  if (x == null) return null;
  for (const a of rules.airlines.values()) {
    if (a.id === x || a.iata_code === x || a.planner_name === x || a.public_name === x || a.game_name === x) return a.id;
  }
  return null;
}

/** The card's aircraft (when it's in the input), its type (the variant) and its airline. */
function cardBasics(rules: Rules, card: Card): { ac: AircraftRow | undefined; type: AircraftTypeRow; airlineId: number } {
  const ac: AircraftRow | undefined = card.aircraft == null ? undefined : findAircraft(rules, card.aircraft);
  if (card.aircraft != null && !ac) throw new RulesError(`no aircraft ${String(card.aircraft)} in the input`);
  const type = findType(rules, card.type ?? ac?.aircraft_type_id ?? null);
  if (!type) throw new RulesError("the card needs an aircraft in the input, or a type");
  const airlineId = ac?.airline_id ?? airlineOf(rules, card.airline);
  if (airlineId == null) throw new RulesError("the card needs an aircraft in the input, or an airline");
  return { ac, type, airlineId };
}

// ---------- the cabin the rule calls for (manual §5, since 20 Oct; spec docs/specs/2026-10-21-cabins-new-rule.md §3)
/** One route's share of the card's block time. */
export interface CabinRouteShare {
  /** The airline's route for the leg's airports (either way round), or null when it has none yet. */
  route_id: number | null;
  /** "JFK–LHR": the route's hub and destination, or the leg's airports when the airline has no route for them. */
  route: string;
  /** Its legs' block minutes a week: each leg's block (stored, else the estimate) times the days it flies. */
  block_min: number;
  /** Its share of the card's block minutes, percent (not rounded). */
  pct: number;
  /** The layout it calls for: its own cabin choice, else its market's layout; null when it has neither. */
  layout: string | null;
  /** Where that layout comes from. */
  from: "route" | "market" | null;
}

/** The cabin a plan card's routes call for, and whether the card's own cabin differs. */
export interface CabinSuggestion {
  /** The layout of the suggested cabin (Standard, Leisure, Leisure Plus or Comfort). Null when the variant has no layouts
   *  in the input (then nothing is suggested or checked). */
  layout: string | null;
  /** The suggested cabin: the variant's layout of the name the rule calls for (the one with the most seats where there are
   *  two), or its layout with the most seats. Null when the variant has no layouts in the input. */
  config_id: number | null;
  code: string | null;
  /** Why, in words: "JFK–LHR is 72% of block time: Leisure Plus", "no route over 65%: the most seats". */
  reason: string;
  /** cabin_route_share_pct, the airline's own where it has one. */
  threshold_pct: number;
  /** Each route's share of the card's block time, most first. */
  routes: CabinRouteShare[];
  /** The card's own cabin, as given (null: not chosen). */
  card_config_id: number | null;
  card_code: string | null;
  /** The card has no cabin yet, while there is one to suggest. */
  missing: boolean;
  /** The card's cabin isn't the suggestion (a missing one included). */
  differs: boolean;
}

const seatsOf = (c: CabinConfigRow) => Number(c.seats ?? 0) || 0;
/** The layout with the most seats (the lowest id on a tie). */
const mostSeats = (list: readonly CabinConfigRow[]): CabinConfigRow | undefined =>
  [...list].sort((a, b) => seatsOf(b) - seatsOf(a) || a.id - b.id)[0];
/** A share in words: a whole percent, with one decimal where rounding would hide which side of the threshold it is. */
function pctWords(pct: number, threshold: number): string {
  const r = Math.round(pct);
  return (pct > threshold && r <= threshold) || (pct <= threshold && r > threshold) ? `${pct.toFixed(1)}%` : `${r}%`;
}

/** The cabin the rule calls for (manual §5): if one route takes more than cabin_route_share_pct of the card's block time,
 *  the layout that route calls for (its own cabin_choice, else its market's layout); otherwise the layout with the most
 *  seats; a low-cost airline (Ryanair) flies Standard only. The cabin is the card's variant's layout of that name, among
 *  the layouts the airline may choose for the variant, as Tails' Cabin box offers them (a low-cost airline's Standard
 *  ones, the others' every other layout); without one of that name, the one with the most seats, and the reason says
 *  why. A leg's block time is its block_min, else the library's estimate (block.blockFor), times the days it flies; a
 *  leg no estimate can be had for counts nothing. A card with no legs gets the most seats. */
export function cabinFor(rules: Rules, card: Card): CabinSuggestion {
  if (!card || !Array.isArray(card.legs)) throw new RulesError("the card has no list of legs");
  const { type, airlineId } = cardBasics(rules, card);
  const airline = rules.airlines.get(airlineId);
  const lcc = !!airline?.is_lcc;
  const threshold = settingNumber(rules, "cabin_route_share_pct", airlineId);
  const all = [...rules.configs.values()];
  const variant = all.filter((c) => c.aircraft_type_id === type.id && (lcc ? c.cabin === "Standard" : c.cabin !== "Standard"));

  // each route's block minutes a week
  const shares = new Map<string, CabinRouteShare>();
  let total = 0;
  for (const l of card.legs) {
    const days = (l.days_utc?.length ? l.days_utc : l.days_local?.length ? l.days_local : [1, 2, 3, 4, 5, 6, 7]).length;
    let blk = l.block_min ?? null;
    if (blk == null) {
      try {
        blk = blockFor(rules, l.origin_code, l.dest_code, type.id, airlineId).block_min;
      } catch (e) {
        if (!(e instanceof RulesError)) throw e;
        blk = 0;
      }
    }
    const pair = pairKey(l.origin_code, l.dest_code);
    const route = (rules.routesByPair.get(pair) ?? []).find((r) => r.airline_id === airlineId);
    const key = route ? `route ${route.id}` : `pair ${pair}`;
    const own = route?.cabin_choice || null, market = route?.market_layout || null;
    const x: CabinRouteShare = shares.get(key) ?? {
      route_id: route?.id ?? null, route: route ? `${route.hub_code}–${route.dest_code}` : `${l.origin_code}–${l.dest_code}`, block_min: 0, pct: 0,
      layout: own ?? market, from: own ? "route" : market ? "market" : null,
    };
    x.block_min += blk * days;
    total += blk * days;
    shares.set(key, x);
  }
  const routes = [...shares.values()].map((x, i) => ({ x: { ...x, pct: total > 0 ? x.block_min / total * 100 : 0 }, i }))
    .sort((a, b) => b.x.block_min - a.x.block_min || a.i - b.i).map((v) => v.x);

  // the layout the rule calls for, and why
  let layout: string | null, reason: string;
  const top = routes[0];
  if (lcc) {
    layout = "Standard";
    reason = `${airline?.planner_name ?? airline?.public_name ?? "a low-cost airline"} flies Standard only`;
  } else if (top && top.pct > threshold) {
    const share = `${top.route} is ${pctWords(top.pct, threshold)} of block time`;
    layout = top.layout;
    reason = top.layout ? `${share}: ${top.layout}${top.from === "route" ? " (the route's own choice)" : ""}` : `${share}, but it has no market layout: the most seats`;
  } else {
    layout = null;
    reason = routes.length ? `no route over ${threshold}%: the most seats` : "no legs yet: the most seats";
  }

  // from the layout to the variant's cabin
  let pick: CabinConfigRow | undefined;
  if (!variant.length) reason += ` (the ${type.name} has no ${lcc ? "Standard " : ""}layouts in the input)`;
  else if (layout) {
    pick = mostSeats(variant.filter((c) => c.cabin === layout));
    if (!pick) {
      pick = mostSeats(variant);
      reason += `, but the ${type.name} has no ${layout} layout: the most seats`;
    }
  } else pick = mostSeats(variant);

  // the card's own cabin, by id or by code
  const given = card.config_id;
  const own = given == null || given === "" ? undefined : typeof given === "number" ? rules.configs.get(given) : all.find((c) => c.code === given);
  if (given != null && given !== "" && !own) throw new RulesError(`no cabin layout ${String(given)} in the input`);
  return {
    layout: pick?.cabin ?? null, config_id: pick?.id ?? null, code: pick?.code ?? null, reason, threshold_pct: threshold, routes,
    card_config_id: own?.id ?? null, card_code: own?.code ?? null, missing: !own && !!pick, differs: !!pick && own?.id !== pick.id,
  };
}

/** The cabin check's problem, or null: none chosen while there is one to suggest, or one that differs. */
function cabinProblem(c: CabinSuggestion): string | null {
  if (!c.code) return null;
  if (c.missing) return `cabin: none chosen; the rule calls for ${c.code} (${c.reason})`;
  if (c.differs) return `cabin ${c.card_code ?? "?"}: the rule calls for ${c.code} (${c.reason})`;
  return null;
}

/** Checks a plan card; see the top of this file. */
export function checkCard(rules: Rules, card: Card) {
  if (!card || !Array.isArray(card.legs) || !card.legs.length) throw new RulesError("the card has no legs");
  const { ac, type, airlineId } = cardBasics(rules, card);

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
  const svc = serviceCheck(rules, airlineId, card.legs);
  const perLeg = legs.map((l, i) => {
    const depLocal = toLocal(rules, l.origin, l.dep_utc_min, DAY), arrLocal = toLocal(rules, l.dest, l.dep_utc_min + l.block_min, DAY);
    const bo = baseAt(rules, l.origin, airlineId), bd = baseAt(rules, l.dest, airlineId);
    const ends = connectionsAtBothEnds(rules, network, l);
    return {
      leg: i + 1, flight_no: l.flight_no, from: l.origin, to: l.dest, days_utc: l.days_utc, dep_utc: clock(l.dep_utc_min),
      dep_local: clock(depLocal), arr_local: clock(arrLocal), block_min: l.block_min, block_source: l.block_source,
      bank_out: bo && !isFocus(bo) ? bankOfDeparture(rules, bo, depLocal)?.n ?? 0 : null,
      bank_in: bd && !isFocus(bd) ? bankOfArrival(rules, bd, arrLocal) : null,
      service_given: svc.legs[i]?.given ?? null, service_wanted: svc.legs[i]?.wanted ?? null,
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
  for (const i of svc.issues) problems.push(serviceWords(i));
  // the cabin (21 Oct): an input without cabin_route_share_pct (made before the rule had its setting) isn't checked, as
  // an input without service profiles skips the service check; cabinFor() itself refuses without it
  const cabin = setting(rules, "cabin_route_share_pct", airlineId) === undefined ? null : cabinFor(rules, card);
  const cabinIssue = cabin ? cabinProblem(cabin) : null;
  if (cabinIssue) problems.push(cabinIssue);
  return {
    aircraft: ac?.registration ?? null, type: type.name, airline_id: airlineId, ok: problems.length === 0, problems,
    legs: perLeg, turns_not_ok: turns.length, maintenance: maint, night_bans: nightBans, route_gaps: routeGaps, flight_number_clashes: clashes,
    departures: caps, legs_week: week?.legs_week ?? 0, block_hours_day: week?.block_hours_day ?? 0, service: svc, cabin,
  };
}
