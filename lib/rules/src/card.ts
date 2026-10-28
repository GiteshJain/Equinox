// A plan card checked against every rule (manual §4: "every new plan card and every retime is checked at both ends").
// The card is one aircraft's flying: its legs replace whatever that aircraft flies today, and are checked with the rest
// of the schedule. Legs are given as flight_legs stores them (UTC weekdays and minute) or as the game shows them (local
// weekdays and "HH:MM" at the origin); a leg without block_min gets the estimate. Each leg's service code is checked
// against the one its route's distance calls for (service.ts's checkLegs, #18 build pull request 10): a wrong code or
// none is a problem naming the leg, the code given and the code wanted. Since 21 Oct (manual §5; spec
// docs/specs/2026-10-21-cabins-new-rule.md §3) the card's cabin is checked too: cabinFor() works out the cabin the rule
// calls for, and a card whose cabin is missing or differs from it is a problem with the reason. And since 21 Oct (manual
// §5; spec docs/specs/2026-10-21-frequencies-and-fares.md §2) the check gives each route's fare level when it is handed
// fare_ladder()'s answer for the card's airline (cardFares): a new flight is priced like the rest of its route; since 26 Oct
// (spec docs/specs/2026-10-26-fare-ladder-per-direction.md §3) each leg its own direction's level. Since 27 Oct (manual
// §4; spec docs/specs/2026-10-27-planning-connection-target.md §3) beside the connections at both ends it reports how
// many fall within the planning target (plan_connection_target_h), count and share, for each leg and the card; it is a
// figure, never a problem: a card isn't wrong for having long connections. Since 28 Oct (spec
// docs/specs/2026-10-27-long-haul-lines.md §3) the maintenance figures carry the spacing of the counting stops, and a
// stretch longer than maintenance_max_gap_h without one is a problem ("no maintenance stop for 78 h, over 40").
import { forAircraft as aircraftWeek } from "./aircraftWeek.js";
import { bankOfArrival, bankOfDeparture, baseAt, hasBanks } from "./banks.js";
import { blockFor, distanceBetween, timedLegs } from "./block.js";
import { connectionsAtBothEnds, planTargetH, type LinkedLeg } from "./connections.js";
import { RulesError, buildRules, findAircraft, findType, pairKey, setting, settingNumber } from "./input.js";
import { ofWeek as maintenanceOfWeek } from "./maintenance.js";
import { departuresPerAirport, flightNumberClashes, nightBanHits, routeGapHits } from "./schedule.js";
import { checkLegs as serviceCheck, issueWords as serviceWords } from "./service.js";
import { DAY, clock, fromLocal, localDays, mod, parseClock, toLocal } from "./time.js";
import type { AircraftRow, AircraftTypeRow, CabinConfigRow, LegRow, Rules, TimedLeg } from "./types.js";

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

// ---------- the cabin the rule calls for (manual §5: by distance since 26 Oct, brief
// docs/briefs/2026-10-26-cabin-layout-by-distance.md; by market from 20 Oct, spec docs/specs/2026-10-21-cabins-new-rule.md §3)
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
  /** Its distance (the route's, else the great circle), km; null when neither is known. */
  km: number | null;
  /** The layout its distance calls for (its range: Leisure, Leisure Plus or Comfort); null when its distance isn't known. */
  layout: string | null;
  /** Where that layout comes from: its distance (since 26 Oct), or null when it has none. */
  from: "distance" | null;
}

/** One distance range's share of the card's block time (since 26 Oct): every route in it together. */
export interface CabinRangeShare {
  /** Leisure (under cabin_leisure_max_km), Leisure Plus (to under cabin_leisure_plus_max_km) or Comfort (beyond). */
  layout: string;
  /** "under 3,500 km", "3,500–6,500 km", "6,500 km and over". */
  range: string;
  block_min: number;
  pct: number;
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
  /** Why, in words: "3,500–6,500 km is 72% of block time: Leisure Plus", "no distance range over 65%: the most seats". */
  reason: string;
  /** cabin_route_share_pct, the airline's own where it has one. */
  threshold_pct: number;
  /** Each route's share of the card's block time, most first. */
  routes: CabinRouteShare[];
  /** Each distance range's share of the card's block time, most first (since 26 Oct). */
  ranges: CabinRangeShare[];
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

const kmWords = (km: number) => km.toLocaleString("en-US");
/** The distance range a route's km falls in (manual §5, since 26 Oct): Leisure under cabin_leisure_max_km, Leisure Plus
 *  to under cabin_leisure_plus_max_km, Comfort beyond. */
export function cabinRange(km: number, leisureMax: number, leisurePlusMax: number): { layout: string; range: string } {
  if (km < leisureMax) return { layout: "Leisure", range: `under ${kmWords(leisureMax)} km` };
  if (km < leisurePlusMax) return { layout: "Leisure Plus", range: `${kmWords(leisureMax)}–${kmWords(leisurePlusMax)} km` };
  return { layout: "Comfort", range: `${kmWords(leisurePlusMax)} km and over` };
}

/** The cabin the rule calls for (manual §5, since 26 Oct): each route is in a distance range (Leisure under
 *  cabin_leisure_max_km, Leisure Plus to under cabin_leisure_plus_max_km, Comfort beyond; the route's distance, else the
 *  great circle), and the range taking more than cabin_route_share_pct of the card's block time decides its layout;
 *  with no range over it, the layout with the most seats. Distance alone decides: no market layout or route choice
 *  overrides it. A low-cost airline (Ryanair) flies Standard only. The cabin is the card's variant's layout of that
 *  name, among the layouts the airline may choose for the variant, as Tails' Cabin box offers them (a low-cost airline's
 *  Standard ones, the others' every other layout); without one of that name, the one with the most seats, and the
 *  reason says why. A leg's block time is its block_min, else the library's estimate (block.blockFor), times the days it
 *  flies; a leg no estimate can be had for counts nothing, and one whose distance isn't known counts towards the total
 *  but no range. A card with no legs gets the most seats. */
export function cabinFor(rules: Rules, card: Card): CabinSuggestion {
  if (!card || !Array.isArray(card.legs)) throw new RulesError("the card has no list of legs");
  const { type, airlineId } = cardBasics(rules, card);
  const airline = rules.airlines.get(airlineId);
  const lcc = !!airline?.is_lcc;
  const threshold = settingNumber(rules, "cabin_route_share_pct", airlineId);
  const leisureMax = settingNumber(rules, "cabin_leisure_max_km", airlineId);
  const leisurePlusMax = settingNumber(rules, "cabin_leisure_plus_max_km", airlineId);
  const all = [...rules.configs.values()];
  const variant = all.filter((c) => c.aircraft_type_id === type.id && (lcc ? c.cabin === "Standard" : c.cabin !== "Standard"));

  // each route's block minutes a week, and its distance range
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
    let x = shares.get(key);
    if (!x) {
      const km = distanceBetween(rules, l.origin_code, l.dest_code, airlineId)?.km ?? null;
      x = {
        route_id: route?.id ?? null, route: route ? `${route.hub_code}–${route.dest_code}` : `${l.origin_code}–${l.dest_code}`, block_min: 0, pct: 0,
        km: km == null ? null : Math.round(km), layout: km == null ? null : cabinRange(km, leisureMax, leisurePlusMax).layout, from: km == null ? null : "distance",
      };
    }
    x.block_min += blk * days;
    total += blk * days;
    shares.set(key, x);
  }
  const routes = [...shares.values()].map((x, i) => ({ x: { ...x, pct: total > 0 ? x.block_min / total * 100 : 0 }, i }))
    .sort((a, b) => b.x.block_min - a.x.block_min || a.i - b.i).map((v) => v.x);
  // each range's block minutes: its routes together
  const byRange = new Map<string, CabinRangeShare>();
  for (const r of routes) {
    if (r.km == null) continue;
    const { layout, range } = cabinRange(r.km, leisureMax, leisurePlusMax);
    const g = byRange.get(layout) ?? { layout, range, block_min: 0, pct: 0 };
    g.block_min += r.block_min;
    g.pct = total > 0 ? g.block_min / total * 100 : 0;
    byRange.set(layout, g);
  }
  const ranges = [...byRange.values()].sort((a, b) => b.block_min - a.block_min);

  // the layout the rule calls for, and why
  let layout: string | null, reason: string;
  const top = ranges[0];
  if (lcc) {
    layout = "Standard";
    reason = `${airline?.planner_name ?? airline?.public_name ?? "a low-cost airline"} flies Standard only`;
  } else if (top && top.pct > threshold) {
    layout = top.layout;
    reason = `${top.range} is ${pctWords(top.pct, threshold)} of block time: ${top.layout}`;
  } else {
    layout = null;
    reason = routes.length ? `no distance range over ${threshold}%: the most seats` : "no legs yet: the most seats";
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
    layout: pick?.cabin ?? null, config_id: pick?.id ?? null, code: pick?.code ?? null, reason, threshold_pct: threshold, routes, ranges,
    card_config_id: own?.id ?? null, card_code: own?.code ?? null, missing: !own && !!pick, differs: !!pick && own?.id !== pick.id,
  };
}

// ---------- the fare level of each route the card flies (manual §5, since 21 Oct; spec
// docs/specs/2026-10-21-frequencies-and-fares.md §2): a new flight on a route already flown launches at that route's level
/** One route, cabin and direction of fare_ladder()'s answer, as much as the card needs (the briefing's fare_ladder has the
 *  same). Since 26 Oct (spec docs/specs/2026-10-26-fare-ladder-per-direction.md) each direction has its own row: out from
 *  the route's hub, back to it; a row without a direction (an answer from before) counts for both. */
export interface FareLadderRow {
  route_id?: number | null;
  hub: string;
  dest: string;
  direction?: "out" | "back" | string | null;
  cabin: string;
  /** Its level, % of the game's default price. */
  level: number | string;
  /** This Saturday's new level, and whether it's on the fare plan already. */
  new_level?: number | string | null;
  planned?: boolean | null;
}
/** fare_ladder()'s answer for the card's airline (or the briefing's fare_ladder): its routes and cabins, and the launch
 *  level for a route the airline doesn't fly yet. */
export interface FareLadder {
  routes: readonly FareLadderRow[];
  settings?: { launch_pct?: number | string | null } | null;
}
/** One cabin's level on a route: the ladder's, or this week's new level once it's on the fare plan. */
export interface CabinFare {
  cabin: string;
  level: number;
  /** The level is this week's move, on the fare plan already. */
  planned: boolean;
}
/** The fare level of one route the card flies, in one direction (since 26 Oct). */
export interface RouteFare {
  /** The airline's route (the ladder's, else its route list's), or null when it has none for the airports yet. */
  route_id: number | null;
  /** "JFK–LHR": the route's hub and destination, or the leg's airports when the airline has no route for them. */
  route: string;
  /** Since 26 Oct the direction the leg flies: out from the route's hub, back to it (null when the airline has no route
   *  for the airports yet), with its airports that way round. */
  direction: "out" | "back" | null;
  from: string;
  to: string;
  /** On the fare ladder, so flown already; otherwise it launches at the launch level. */
  flown: boolean;
  /** Each cabin's level, economy first: the ladder's cabins for a route flown, none for one that isn't. */
  cabins: CabinFare[];
  /** settings.fare_launch_pct, the airline's own where it has one (Ryanair 85). */
  launch_pct: number;
  /** What to set in the game's Ticket price adjustment (baseline default price): "economy +10%, business +5% of the
   *  default price", or for a route not flown yet "launch (+0% of the default price)" ("launch (−15% …)" for Ryanair). */
  words: string;
}
const asNumber = (v: number | string | null | undefined): number | null => (v == null || v === "" || !Number.isFinite(Number(v)) ? null : Number(v));
/** A level against the game's default price, as Ticket price adjustment takes it: 110 → "+10%", 85 → "−15%", 100 → "+0%". */
export function levelPct(level: number): string {
  const d = Math.round((level - 100) * 10) / 10;
  return `${d < 0 ? "−" : "+"}${Math.abs(d)}%`;
}
/** The fare level of each route the card flies in each direction it flies it, once per direction, in the order of its
 *  legs (manual §5, since 21 Oct; per direction since 26 Oct, spec docs/specs/2026-10-26-fare-ladder-per-direction.md):
 *  from fare_ladder()'s routes for the card's airline, the level in each cabin it has there for the leg's direction (out
 *  when the leg leaves the route's hub, else back; a row without a direction counts for both), this week's new level
 *  once the move is on the fare plan; a route not on the ladder (one the airline doesn't fly yet) launches at the launch
 *  level, the ladder's settings.launch_pct, else the airline's fare_launch_pct. Nothing is stored on the card. */
export function cardFares(rules: Rules, card: Card, ladder: FareLadder): RouteFare[] {
  if (!card || !Array.isArray(card.legs)) throw new RulesError("the card has no list of legs");
  if (!ladder || !Array.isArray(ladder.routes)) throw new RulesError("the fare ladder has no list of routes (fare_ladder()'s answer for the card's airline)");
  const { airlineId } = cardBasics(rules, card);
  const launch = asNumber(ladder.settings?.launch_pct) ?? settingNumber(rules, "fare_launch_pct", airlineId);
  const byPair = new Map<string, FareLadderRow[]>();
  for (const r of ladder.routes) {
    const k = pairKey(r.hub, r.dest);
    byPair.set(k, [...(byPair.get(k) ?? []), r]);
  }
  const out: RouteFare[] = [];
  const seen = new Set<string>();
  // a pair the airline has no route for is named by the airports of its first leg on the card, both ways
  const named = new Map<string, string>();
  for (const l of card.legs) {
    const leg = `${l.origin_code}>${l.dest_code}`;
    if (seen.has(leg)) continue;
    seen.add(leg);
    const pair = pairKey(l.origin_code, l.dest_code);
    if (!named.has(pair)) named.set(pair, `${l.origin_code}–${l.dest_code}`);
    const all = byPair.get(pair) ?? [];
    const route = (rules.routesByPair.get(pair) ?? []).find((r) => r.airline_id === airlineId);
    const first = all[0];
    const hub = first?.hub ?? route?.hub_code ?? null;
    const direction: "out" | "back" | null = hub == null ? null : l.origin_code === hub ? "out" : "back";
    // the leg's direction's rows; a row without a direction (an answer from before 26 Oct) counts for both
    const rows = all.filter((r) => r.direction == null || r.direction === direction);
    const cabins: CabinFare[] = rows
      .map((r) => {
        const planned = !!r.planned && asNumber(r.new_level) != null;
        return { cabin: r.cabin, level: (planned ? asNumber(r.new_level) : asNumber(r.level)) ?? launch, planned };
      })
      .sort((a, b) => Number(a.cabin === "business") - Number(b.cabin === "business") || a.cabin.localeCompare(b.cabin));
    const flown = cabins.length > 0;
    out.push({
      route_id: first?.route_id ?? route?.id ?? null,
      route: first ? `${first.hub}–${first.dest}` : route ? `${route.hub_code}–${route.dest_code}` : named.get(pair) ?? `${l.origin_code}–${l.dest_code}`,
      direction, from: l.origin_code, to: l.dest_code,
      flown, cabins, launch_pct: launch,
      words: flown ? `${cabins.map((c) => `${c.cabin} ${levelPct(c.level)}`).join(", ")} of the default price` : `launch (${levelPct(launch)} of the default price)`,
    });
  }
  return out;
}

/** The cabin check's problem, or null: none chosen while there is one to suggest, or one that differs. */
function cabinProblem(c: CabinSuggestion): string | null {
  if (!c.code) return null;
  if (c.missing) return `cabin: none chosen; the rule calls for ${c.code} (${c.reason})`;
  if (c.differs) return `cabin ${c.card_code ?? "?"}: the rule calls for ${c.code} (${c.reason})`;
  return null;
}

/** The share of connections within the target, percent to one decimal; null with no connections. */
const shareOf = (within: number, all: number): number | null => (all > 0 ? Math.round(within / all * 1000) / 10 : null);

/** Checks a plan card; see the top of this file. With fare_ladder()'s answer for the card's airline (options.fares), the
 *  answer's fares gives each route's fare level in each direction the card flies it (cardFares, since 21 Oct; per
 *  direction since 26 Oct); without it, fares is null. */
export function checkCard(rules: Rules, card: Card, options: { fares?: FareLadder | null } = {}) {
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
  // the planning target (since 27 Oct): an input without plan_connection_target_h (made before it came) gets no target
  // figures (null), as an input without the cabin settings skips the cabin check
  const targetH = setting(rules, "plan_connection_target_h") === undefined ? null : planTargetH(rules);
  const within = (xs: readonly LinkedLeg[]) => (targetH == null ? null : xs.filter((x) => x.gap_min <= targetH * 60).length);
  const pairs = new Map<string, boolean>();
  const perLeg = legs.map((l, i) => {
    const depLocal = toLocal(rules, l.origin, l.dep_utc_min, DAY), arrLocal = toLocal(rules, l.dest, l.dep_utc_min + l.block_min, DAY);
    const bo = baseAt(rules, l.origin, airlineId), bd = baseAt(rules, l.dest, airlineId);
    const ends = connectionsAtBothEnds(rules, network, l);
    const fw = within(ends.feeders), ow = within(ends.onward), all = ends.feeders.length + ends.onward.length;
    // the card's connections, each arrival and departure pair once (a connection between two of the card's own legs is
    // one leg's onward and the other's feeder)
    for (const x of ends.feeders) pairs.set(`${x.leg.id}>${l.id}`, targetH != null && x.gap_min <= targetH * 60);
    for (const x of ends.onward) pairs.set(`${l.id}>${x.leg.id}`, targetH != null && x.gap_min <= targetH * 60);
    return {
      leg: i + 1, flight_no: l.flight_no, from: l.origin, to: l.dest, days_utc: l.days_utc, dep_utc: clock(l.dep_utc_min),
      dep_local: clock(depLocal), arr_local: clock(arrLocal), block_min: l.block_min, block_source: l.block_source,
      bank_out: hasBanks(bo) && bo ? bankOfDeparture(rules, bo, depLocal)?.n ?? 0 : null,
      bank_in: hasBanks(bd) && bd ? bankOfArrival(rules, bd, arrLocal) : null,
      service_given: svc.legs[i]?.given ?? null, service_wanted: svc.legs[i]?.wanted ?? null,
      feeders: ends.feeders.length, onward: ends.onward.length,
      feeders_within_target: fw, onward_within_target: ow,
      within_target: fw == null || ow == null ? null : fw + ow,
      within_target_share: fw == null || ow == null ? null : shareOf(fw + ow, all),
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
  // the maintenance spacing (since 28 Oct, spec docs/specs/2026-10-27-long-haul-lines.md §3): an input without
  // maintenance_max_gap_h isn't checked
  if (maint.ratio != null && maint.max_gap_ok === false && maint.max_gap_limit_h != null) {
    problems.push(maint.max_gap_h == null ? `no maintenance stop all week, over ${maint.max_gap_limit_h} h`
      : `no maintenance stop for ${maint.max_gap_h} h, over ${maint.max_gap_limit_h}`);
  }
  for (const h of nightBans) problems.push(`${h.airport}: ${h.what} ${h.local}, inside its night ban (${h.ban})`);
  for (const h of routeGaps) problems.push(`${h.origin}–${h.dest}: ${h.gap_min} min from another flight on the route (at least ${h.need_min}, ${h.rule})`);
  for (const c of clashes) problems.push(`flight ${c.flight_no} is used twice on day(s) ${c.days.join(", ")}`);
  for (const a of caps) if (a.over) problems.push(`${a.airport}: ${a.departures_week} departures a week, over the cap of ${a.cap}`);
  for (const i of svc.issues) problems.push(serviceWords(i));
  // the cabin (21 Oct; by distance since 26 Oct): an input without cabin_route_share_pct or the two distance settings
  // (made before the rule had them) isn't checked, as
  // an input without service profiles skips the service check; cabinFor() itself refuses without it
  const cabin = setting(rules, "cabin_route_share_pct", airlineId) === undefined || setting(rules, "cabin_leisure_max_km", airlineId) === undefined
    || setting(rules, "cabin_leisure_plus_max_km", airlineId) === undefined ? null : cabinFor(rules, card);
  const cabinIssue = cabin ? cabinProblem(cabin) : null;
  if (cabinIssue) problems.push(cabinIssue);
  const nWithin = [...pairs.values()].filter(Boolean).length;
  const connections = {
    target_h: targetH, total: pairs.size, within_target: targetH == null ? null : nWithin,
    within_target_share: targetH == null ? null : shareOf(nWithin, pairs.size),
  };
  return {
    aircraft: ac?.registration ?? null, type: type.name, airline_id: airlineId, ok: problems.length === 0, problems,
    legs: perLeg, connections, turns_not_ok: turns.length, maintenance: maint, night_bans: nightBans, route_gaps: routeGaps, flight_number_clashes: clashes,
    departures: caps, legs_week: week?.legs_week ?? 0, block_hours_day: week?.block_hours_day ?? 0, service: svc, cabin,
    fares: options.fares ? cardFares(rules, card, options.fares) : null,
  };
}

// ---------- a card written from a line (since 28 Oct; spec docs/specs/2026-10-27-long-haul-lines.md §2)
/** One leg of a line as plan_line_legs keeps it (the optimiser's legs, from/to, are given the same way by lineCards). */
export interface LineCardLeg {
  /** The line day it departs on, 1 to 7: the UTC weekday on the card of the aircraft at offset 0. */
  line_day: number;
  flight_no?: number | null;
  origin_code: string;
  dest_code: string;
  dep_utc_min: number;
  block_min?: number | null;
  service_code?: string | null;
}

/** The UTC weekday the aircraft at an offset flies a line day on (the spec's formula, aircraft k = offset + 1:
 *  ((d + k − 2) mod 7) + 1). */
export function lineWeekday(lineDay: number, offset: number): number {
  return mod(lineDay + offset - 1, 7) + 1;
}

/** The legs of the card of the aircraft at an offset (0 to 6) on a line: every leg of the line, in the line's order, each
 *  on its own UTC weekday (lineWeekday), as the line optimiser writes its 7 cards. */
export function fromLine(line: { legs: readonly LineCardLeg[] }, offset: number): CardLeg[] {
  if (!Number.isInteger(offset) || offset < 0 || offset > 6) throw new RulesError(`a line's offset is 0 to 6, not ${offset}`);
  if (!line?.legs?.length) throw new RulesError("the line has no legs");
  return line.legs.map((l, i) => {
    if (!Number.isInteger(l.line_day) || l.line_day < 1 || l.line_day > 7) throw new RulesError(`leg ${i + 1}: line day ${l.line_day} isn't 1 to 7`);
    return {
      flight_no: l.flight_no ?? null, origin_code: l.origin_code, dest_code: l.dest_code, days_utc: [lineWeekday(l.line_day, offset)], dep_utc_min: l.dep_utc_min,
      block_min: l.block_min ?? null, service_code: l.service_code ?? null,
    };
  });
}

// ---------- a line of cards (since 28 Oct; spec docs/specs/2026-10-27-long-haul-lines.md §3): up to 7 cards of one
// 7-day rotating line, each checked as today, and across them whether every leg operates daily once all 7 exist
/** A line file for check-card: its cards (1 to 7), each as a card is given. */
export interface LineFile {
  line?: { name?: string | null; airline?: string | number | null; type?: string | number | null } | null;
  cards: (Card & { line_day_offset?: number | null })[];
}

/** One flight of the line (a flight number, or the airports and departure where it has none) across the cards. */
export interface LineFlight {
  flight_no: number | null;
  from: string;
  to: string;
  dep_utc: string;
  /** The local weekdays it flies at its origin, across the cards. */
  days: number[];
  /** The local weekdays it doesn't fly yet (with fewer than 7 cards); empty when it operates daily. */
  missing: number[];
  daily: boolean;
  /** On which cards it is (their places in the file, from 1). */
  cards: number[];
}

/** Checks a line of up to 7 cards: each card on its own (checkCard, with the other cards of the line laid into the
 *  network, so a line's own flights count as its connections and a same-day clash between two cards shows), then the
 *  line as a whole: every flight operates daily once all 7 cards exist (and which weekdays are missing until then), the
 *  same flight number on different weekdays of different cards isn't a clash (two cards with it on the same local
 *  weekday is), and each route is flown both ways every day. A line with every card and a flight missing a day, or a
 *  route not flown back daily, is a problem; with fewer cards the missing days are reported and not a problem. */
export function checkLine(rules: Rules, line: LineFile, options: { fares?: FareLadder | null } = {}) {
  if (!line || !Array.isArray(line.cards) || !line.cards.length) throw new RulesError("the line has no cards");
  if (line.cards.length > 7) throw new RulesError(`a line has at most 7 cards, not ${line.cards.length}`);
  const cards = line.cards.map((c) => ({ ...c, type: c.type ?? line.line?.type ?? null, airline: c.airline ?? line.line?.airline ?? null }));
  const basics = cards.map((c) => cardBasics(rules, c));
  const airlineId = basics[0]?.airlineId ?? null, type = basics[0]?.type ?? null;
  const problems: string[] = [];
  basics.forEach((b, i) => {
    if (b.airlineId !== airlineId) problems.push(`card ${i + 1} is another airline's (${b.airlineId}); a line is one airline's`);
    if (b.type.id !== type?.id) problems.push(`card ${i + 1} is a ${b.type.name}; a line is one type's (${type?.name ?? "?"})`);
  });
  // each card's legs as flight_legs rows, so the other cards can be laid into the network each card is checked against
  let nextId = -1;
  const extra = cards.map((c, i) => {
    const owner = c.aircraft == null ? undefined : findAircraft(rules, c.aircraft);
    return c.legs.map((l, k): LegRow => {
      let days = l.days_utc ?? null, dep = l.dep_utc_min ?? null;
      if (dep == null && l.dep_local != null) {
        const m = parseClock(l.dep_local);
        if (m == null) throw new RulesError(`card ${i + 1}, leg ${k + 1}: dep_local ${l.dep_local} isn't a clock time`);
        const u = fromLocal(rules, l.origin_code, l.days_local?.length ? l.days_local : [1, 2, 3, 4, 5, 6, 7], m);
        days = u.days_utc;
        dep = u.dep_utc_min;
      }
      if (dep == null) throw new RulesError(`card ${i + 1}, leg ${k + 1}: give dep_utc_min or dep_local`);
      const b = basics[i];
      const est = l.block_min == null && b ? blockFor(rules, l.origin_code, l.dest_code, b.type.id, b.airlineId).block_min : null;
      return {
        id: nextId--, airline_id: b?.airlineId ?? 0, rotation_id: null, leg_no: null, flight_no: l.flight_no ?? null, origin_code: l.origin_code, dest_code: l.dest_code,
        aircraft_id: owner?.id ?? -(1000 + i), days_utc: (days?.length ? days : [1, 2, 3, 4, 5, 6, 7]).slice().sort((a, b) => a - b), dep_utc_min: dep, block_min: l.block_min ?? est ?? 0,
      };
    });
  });
  // an aircraft of the line already flying (filed) has its flight_legs in the input: its card stands for them, so they're
  // left out, or each of its flights would clash with itself on the other cards' checks
  const lineAircraft = new Set(cards.map((c) => (c.aircraft == null ? undefined : findAircraft(rules, c.aircraft)?.id)).filter((x): x is number => x != null));
  const network = lineAircraft.size ? rules.input.flight_legs.filter((l) => l.aircraft_id == null || !lineAircraft.has(l.aircraft_id)) : rules.input.flight_legs;
  const checks = cards.map((c, i) => {
    const others = extra.filter((_, k) => k !== i).flat();
    // the other cards' legs laid into the input, each on its own stand-in aircraft (one not in the input is -1001, -1002…)
    const laid = buildRules({ ...rules.input, flight_legs: [...network, ...others],
      aircraft: [...rules.input.aircraft, ...cards.flatMap((x, k) => (k === i || (x.aircraft != null && findAircraft(rules, x.aircraft)) ? []
        : [{ id: -(1000 + k), registration: `(line card ${k + 1})`, airline_id: basics[k]?.airlineId ?? 0, aircraft_type_id: basics[k]?.type.id ?? null, status: "active" }]))] });
    return checkCard(laid, c, options);
  });
  checks.forEach((c, i) => { for (const p of c.problems) problems.push(`card ${i + 1}: ${p}`); });
  // across the line: each flight's local weekdays over the cards
  const flights = new Map<string, LineFlight>();
  extra.forEach((legs, i) => {
    for (const l of legs) {
      const key = l.flight_no != null ? `${l.flight_no}` : `${l.origin_code}>${l.dest_code}@${l.dep_utc_min}`;
      const local = localDays(rules, l.origin_code, l.days_utc, l.dep_utc_min ?? 0);
      const f = flights.get(key) ?? { flight_no: l.flight_no, from: l.origin_code, to: l.dest_code, dep_utc: clock(l.dep_utc_min ?? 0), days: [], missing: [], daily: false, cards: [] };
      if (f.from !== l.origin_code || f.to !== l.dest_code || f.dep_utc !== clock(l.dep_utc_min ?? 0)) {
        problems.push(`flight ${l.flight_no} on card ${i + 1} is ${l.origin_code}–${l.dest_code} at ${clock(l.dep_utc_min ?? 0)} UTC, but ${f.from}–${f.to} at ${f.dep_utc} on card ${(f.cards[0] ?? 0)}`);
      }
      for (const d of local) {
        if (f.days.includes(d)) problems.push(`flight ${l.flight_no ?? `${l.origin_code}–${l.dest_code}`} is on card ${i + 1} and card ${f.cards[f.days.indexOf(d)] ?? "?"} on the same local weekday ${d}`);
        else { f.days.push(d); f.cards.push(i + 1); }
      }
      flights.set(key, f);
    }
  });
  const complete = cards.length === 7;
  for (const f of flights.values()) {
    const pairs = f.days.map((d, k) => ({ d, c: f.cards[k] ?? 0 })).sort((a, b) => a.d - b.d);
    f.days = pairs.map((p) => p.d);
    f.cards = pairs.map((p) => p.c);
    f.missing = [1, 2, 3, 4, 5, 6, 7].filter((d) => !f.days.includes(d));
    f.daily = f.missing.length === 0;
    if (complete && !f.daily) problems.push(`flight ${f.flight_no ?? `${f.from}–${f.to}`} doesn't operate on weekday(s) ${f.missing.join(", ")} across the 7 cards`);
  }
  // each route both ways every day: the days the line flies out against the days it flies back
  // (named as the airline's route, hub first, where it has one; else as first flown)
  const routes = new Map<string, { out: Set<number>; back: Set<number>; a: string; b: string }>();
  for (const f of flights.values()) {
    const k = pairKey(f.from, f.to);
    const own = (rules.routesByPair.get(k) ?? []).find((r) => r.airline_id === airlineId);
    const r = routes.get(k) ?? { out: new Set<number>(), back: new Set<number>(), a: own?.hub_code ?? f.from, b: own?.dest_code ?? f.to };
    for (const d of f.days) (f.from === r.a ? r.out : r.back).add(d);
    routes.set(k, r);
  }
  const bothWays = [...routes.values()].map((r) => ({
    route: `${r.a}–${r.b}`, out_days: [...r.out].sort((x, y) => x - y), back_days: [...r.back].sort((x, y) => x - y),
    both_ways_daily: r.out.size === 7 && r.back.size === 7,
  }));
  if (complete) for (const r of bothWays) if (!r.both_ways_daily) problems.push(`${r.route} isn't flown both ways every day (out on ${r.out_days.join(", ") || "none"}, back on ${r.back_days.join(", ") || "none"})`);
  // the days still missing until the line is complete, over every flight
  const missingDays = [...new Set([...flights.values()].flatMap((f) => f.missing))].sort((a, b) => a - b);
  return {
    name: line.line?.name ?? null, airline_id: airlineId, type: type?.name ?? null, cards: cards.length, complete, ok: problems.length === 0, problems,
    flights: [...flights.values()], routes: bothWays, missing_days: missingDays,
    card_checks: checks,
  };
}
