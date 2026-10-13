// block: block minutes for a leg not yet timed = block_allowance_min + distance ÷ the type's cruise_kmh, rounded
// (manual §4). A leg with block_min stored (from the game's times) uses that. Worked out in the same order as the old
// planner's blockMin and plan.py's block (distance ÷ speed × 60 + allowance), so the same distance gives the same
// minute. Unlike the old planner's estBlockFor, nothing is fitted to the times typed in (spec §5, "block estimates").
import { RulesError, findType, pairKey, settingNumber, typeOfAircraft } from "./input.js";
import type { AircraftTypeRow, LegRow, Rules, TimedLeg } from "./types.js";

/** The Earth's mean radius in km, for the great-circle distance between two airports no route links. */
const EARTH_KM = 6371;

/** Great-circle km between two airports, rounded as the old planner's haversine rounds it, or null without positions. */
export function greatCircleKm(rules: Rules, a: string, b: string): number | null {
  return greatCircleBetween(rules.airports.get(a), rules.airports.get(b));
}

/** Great-circle km between two positions (degrees), rounded as the old planner's haversine rounds it, or null when either
 *  has none: for an airport outside the input, such as a new route's destination (the Routes screen's Add route). */
export function greatCircleBetween(A: { lat?: number | string | null; lon?: number | string | null } | null | undefined,
  B: { lat?: number | string | null; lon?: number | string | null } | null | undefined): number | null {
  if (A?.lat == null || A.lon == null || B?.lat == null || B.lon == null) return null;
  const [la1, lo1, la2, lo2] = [A.lat, A.lon, B.lat, B.lon].map(Number) as [number, number, number, number];
  const p = Math.PI / 180;
  const h = Math.sin((la2 - la1) * p / 2) ** 2 + Math.cos(la1 * p) * Math.cos(la2 * p) * Math.sin((lo2 - lo1) * p / 2) ** 2;
  return Math.round(2 * EARTH_KM * Math.asin(Math.sqrt(h)));
}

export interface Distance {
  km: number;
  source: "route" | "great circle";
  route_id: number | null;
}

/** The distance between two airports: the route's (either direction; the airline's own first, with any override
 *  applied), else the great circle. Null when neither is known. */
export function distanceBetween(rules: Rules, a: string, b: string, airlineId?: number | null): Distance | null {
  let any: Distance | null = null;
  for (const r of rules.routesByPair.get(pairKey(a, b)) ?? []) {
    if (r.distance_km == null) continue;
    const d: Distance = { km: r.distance_km, source: "route", route_id: r.id };
    if (airlineId == null || r.airline_id === airlineId) return d;
    any ??= d;
  }
  if (any) return any;
  const km = greatCircleKm(rules, a, b);
  return km == null ? null : { km, source: "great circle", route_id: null };
}

/** Block minutes for a distance flown by a type: block_allowance_min + km ÷ cruise_kmh, rounded (manual §4). */
export function estimateBlock(rules: Rules, distanceKm: number, type: AircraftTypeRow, airlineId?: number | null): number {
  const cruise = type.cruise_kmh;
  if (cruise == null || !(cruise > 0)) throw new RulesError(`aircraft type ${type.name} has no cruise_kmh`);
  return Math.round(distanceKm / cruise * 60 + settingNumber(rules, "block_allowance_min", airlineId));
}

export interface BlockAnswer {
  origin: string;
  dest: string;
  type: string;
  distance_km: number;
  distance_source: Distance["source"];
  cruise_kmh: number;
  allowance_min: number;
  block_min: number;
}

/** The estimate for a leg not yet timed, from origin to dest on a type (by id or name). */
export function blockFor(rules: Rules, origin: string, dest: string, type: number | string, airlineId?: number | null): BlockAnswer {
  const ty = findType(rules, type);
  if (!ty) throw new RulesError(`no aircraft type ${String(type)} in the input`);
  const d = distanceBetween(rules, origin, dest, airlineId);
  if (!d) throw new RulesError(`no distance for ${origin}–${dest}: no route and no airport positions`);
  return {
    origin, dest, type: ty.name, distance_km: d.km, distance_source: d.source, cruise_kmh: ty.cruise_kmh ?? 0,
    allowance_min: settingNumber(rules, "block_allowance_min", airlineId), block_min: estimateBlock(rules, d.km, ty, airlineId),
  };
}

/** A leg's block: block_min where it is stored, else the estimate for its route's distance and its aircraft's type.
 *  Null when neither can be had (no aircraft or type, or no distance). */
export function legBlock(rules: Rules, leg: LegRow): { minutes: number; source: "stored" | "estimate" } | null {
  if (leg.block_min != null) return { minutes: leg.block_min, source: "stored" };
  const ty = typeOfAircraft(rules, leg.aircraft_id);
  if (!ty || ty.cruise_kmh == null) return null;
  const rot = leg.rotation_id == null ? undefined : rules.rotations.get(leg.rotation_id);
  const route = rot ? rules.routes.get(rot.route_id) : undefined;
  const km = route?.distance_km ?? distanceBetween(rules, leg.origin_code, leg.dest_code, leg.airline_id)?.km;
  return km == null ? null : { minutes: estimateBlock(rules, km, ty, leg.airline_id), source: "estimate" };
}

/** A leg placed in the week, or null when it has no departure time yet or no block can be had. */
export function timedLeg(rules: Rules, leg: LegRow, order: number): TimedLeg | null {
  if (leg.dep_utc_min == null || !leg.days_utc.length) return null;
  const b = legBlock(rules, leg);
  if (!b) return null;
  const rot = leg.rotation_id == null ? undefined : rules.rotations.get(leg.rotation_id);
  return {
    id: leg.id, airline_id: leg.airline_id, rotation_id: leg.rotation_id, route_id: rot?.route_id ?? null,
    leg_no: leg.leg_no ?? null, flight_no: leg.flight_no, origin: leg.origin_code, dest: leg.dest_code,
    aircraft_id: leg.aircraft_id, days_utc: [...leg.days_utc].sort((a, b) => a - b), dep_utc_min: leg.dep_utc_min,
    block_min: b.minutes, block_source: b.source, order,
  };
}

/** Every leg of the input that can be placed in the week, in the input's order. */
export function timedLegs(rules: Rules): TimedLeg[] {
  const out: TimedLeg[] = [];
  rules.legs.forEach((l, i) => {
    const t = timedLeg(rules, l, i);
    if (t) out.push(t);
  });
  return out;
}
