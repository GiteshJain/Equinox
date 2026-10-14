// service: the service profile a route's flights take (the old planner's serviceFor; Reference → service profiles). An
// airline with a profile of its own (Ryanair's R) takes it on every route; every other airline takes the first of the
// shared profiles (no airline) whose "up to km" is more than the route's distance, in order of that distance, or the
// last of them on a longer route. The profiles are service_profiles' rows: rules_input() gives them since build pull
// request 10 (input.service_profiles), and profileFor() also takes them from a caller that has them already.
//
// The plan card's service check (#18 build pull request 10, spec docs/specs/2026-10-14-review.md part 2): each leg's
// service code against the one its route's distance calls for. On 13 Oct, 22 of 37 round trips on the new plan cards had
// S1, S2, S3 given by position on the card instead of by distance. A leg with a code other than the one wanted is flagged,
// and so is a leg with no code (a plan card tells Gitesh what to set in the game). An input without service profiles (one
// made before build pull request 10) can't be checked: the answer says so and flags nothing.
import { distanceBetween, type Distance } from "./block.js";
import type { Rules, ServiceProfileRow } from "./types.js";

/** A service_profiles row: its code, the airline it belongs to (none for the shared ones), and up to how many km. */
export type ServiceProfile = ServiceProfileRow;

/** The profile a route of this airline and distance takes, or null when there's none to take. */
export function profileFor(profiles: readonly ServiceProfile[], airlineId: number, distanceKm: number | null | undefined): ServiceProfile | null {
  const byId = [...profiles].sort((a, b) => (a.id ?? 0) - (b.id ?? 0));
  const own = byId.find((p) => p.airline_id === airlineId);
  if (own) return own;
  const shared = byId.filter((p) => p.airline_id == null && p.up_to_km != null).sort((a, b) => (a.up_to_km ?? 0) - (b.up_to_km ?? 0));
  const km = distanceKm ?? 0;
  return shared.find((p) => km < (p.up_to_km ?? 0)) ?? shared[shared.length - 1] ?? null;
}

/** The input's service profiles, or null when it has none (an input made before build pull request 10). */
export function profilesOf(rules: Rules): readonly ServiceProfile[] | null {
  const p = rules.input.service_profiles;
  return Array.isArray(p) && p.length ? p : null;
}

/** The code a leg between two airports wants for an airline: by the route's distance (the airline's own route either way
 *  round, with any override, else another airline's, else the great circle, as block times take it). Null when the input
 *  has no service profiles or the distance can't be had. */
export function wantedFor(rules: Rules, airlineId: number, origin: string, dest: string): { code: string; km: number; source: Distance["source"] } | null {
  const profiles = profilesOf(rules);
  if (!profiles) return null;
  const d = distanceBetween(rules, origin, dest, airlineId);
  if (!d) return null;
  const p = profileFor(profiles, airlineId, d.km);
  return p && p.code ? { code: p.code, km: d.km, source: d.source } : null;
}

/** A leg as the check reads it: a plan card's leg (plan_card_legs, or the command's card). */
export interface ServiceLeg {
  flight_no?: number | string | null;
  origin_code: string;
  dest_code: string;
  service_code?: string | null;
}

export interface ServiceLegAnswer {
  /** The leg's place on the card, from 1. */
  leg: number;
  flight_no: number | string | null;
  from: string;
  to: string;
  /** The code the card gives, or null for none. */
  given: string | null;
  /** The code its route's distance calls for, or null when it can't be had. */
  wanted: string | null;
  km: number | null;
  distance_source: Distance["source"] | null;
  ok: boolean;
}

export interface ServiceIssue extends ServiceLegAnswer {
  wanted: string;
  km: number;
}

export interface ServiceCheck {
  /** False when the input has no service profiles: nothing is flagged, and why says so. */
  checked: boolean;
  why: string | null;
  legs: ServiceLegAnswer[];
  issues: ServiceIssue[];
}

const code = (x: string | null | undefined): string | null => {
  const t = String(x ?? "").trim();
  return t === "" ? null : t;
};

/** Each leg's service code against the one its route's distance calls for (see the top of this file). */
export function checkLegs(rules: Rules, airlineId: number, legs: readonly ServiceLeg[]): ServiceCheck {
  const checked = profilesOf(rules) != null;
  const answers: ServiceLegAnswer[] = legs.map((l, i) => {
    const w = checked ? wantedFor(rules, airlineId, l.origin_code, l.dest_code) : null;
    const given = code(l.service_code);
    return {
      leg: i + 1, flight_no: l.flight_no ?? null, from: l.origin_code, to: l.dest_code, given, wanted: w?.code ?? null, km: w?.km ?? null,
      distance_source: w?.source ?? null, ok: !w || given === w.code,
    };
  });
  return {
    checked, why: checked ? null : "the input has no service profiles (rules_input() gives them since build pull request 10)",
    legs: answers, issues: answers.filter((a): a is ServiceIssue => !a.ok),
  };
}

const km = (n: number) => Math.round(n).toLocaleString("en-US");

/** An issue in words, naming the leg, the code given and the code wanted. */
export function issueWords(i: ServiceIssue): string {
  const leg = `leg ${i.leg} (${i.flight_no != null && i.flight_no !== "" ? i.flight_no + " " : ""}${i.from}–${i.to})`;
  return `${leg}: ${i.given ? `service ${i.given} given` : "no service code"}, its route's ${km(i.km)} km calls for ${i.wanted}`;
}

/** The same in short, for a plan card's leg on screen: "S1, wants S3" or "none, wants S2". */
export function shortWords(i: ServiceIssue): string {
  return `${i.given ?? "none"}, wants ${i.wanted}`;
}
