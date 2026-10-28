// tails: an aircraft's issues, as the Tails screen lists them (#18 build pull request 7, spec docs/specs/2026-10-13-tails.md):
// in the old planner's order, each worked out from the aircraft's week (aircraftWeek), its maintenance (maintenance) and
// how each of its rotations fits the banks at both ends (banks.wave on frequency's local times):
//   - it flies fewer block hours a day than aircraft_block_target_h (a flag, not a floor: manual §4 sets none);
//   - short turns a week (under the type's turnaround);
//   - maintenance under maintenance_min_pct (bad: condition will fall) or under maintenance_target_pct (little headroom);
//   - tight turns a week (under the turnaround plus turn_margin_min);
//   - legs a week that start where the aircraft isn't;
//   - its longest ground gap under the type's target maintenance gap (gap_target_h), when it flies;
//   - since 28 Oct (spec docs/specs/2026-10-27-long-haul-lines.md §3) a stretch without a counting maintenance stop
//     longer than maintenance_max_gap_h (maintenance.spacing; an input without the setting isn't checked);
//   - rotations off wave: an arrival that feeds no bank at either end (banks.wave's level bad).
// The old code it follows: the old planner's tailIssues(). Its numbers there (10 h, 1 and 1.05) are settings here.
import { forAircraft as weekOf, type AircraftWeek } from "./aircraftWeek.js";
import { airlineBaseAt, wave } from "./banks.js";
import { timedLegs } from "./block.js";
import { localTimes, view } from "./frequency.js";
import { findAircraft, settingNumber, typeOfAircraft } from "./input.js";
import { ofWeek as maintenanceOfWeek, type Maintenance, type NoMaintenance } from "./maintenance.js";
import type { AircraftRow, LegRow, Rules, TimedLeg } from "./types.js";

export type TailIssue =
  | { kind: "block_hours"; block_hours_day: number; target_h: number }
  | { kind: "short_turns"; count: number }
  | { kind: "maintenance"; level: "bad" | "warn"; pct: number; min_pct: number; target_pct: number }
  | { kind: "tight_turns"; count: number; margin_min: number }
  | { kind: "positions"; count: number }
  | { kind: "longest_gap"; gap_min: number; target_h: number }
  /** No maintenance stop that counts for max_gap_h hours, over the limit (maintenance_max_gap_h); max_gap_h null when no
   *  stop counts in the whole week. */
  | { kind: "maintenance_gap"; max_gap_h: number | null; limit_h: number; counting_stops: number }
  | { kind: "off_wave"; count: number; rotation_ids: number[] };

/** The rotations an aircraft flies (its outbound's aircraft, else its return's, as the old planner's frequency's tail)
 *  that fit no bank at one of their ends. Every rotation counts, timed or not, as the old tailIssues counts them. */
export function offWave(rules: Rules, aircraftId: number): number[] {
  const byRotation = new Map<number, { leg1?: LegRow; leg2?: LegRow }>();
  for (const l of rules.legs) {
    if (l.rotation_id == null) continue;
    const r = byRotation.get(l.rotation_id) ?? {};
    if ((l.leg_no ?? 1) === 1) r.leg1 = l;
    else r.leg2 = l;
    byRotation.set(l.rotation_id, r);
  }
  const type = typeOfAircraft(rules, aircraftId);
  const out: number[] = [];
  for (const [id, { leg1, leg2 }] of byRotation) {
    if ((leg1?.aircraft_id ?? leg2?.aircraft_id ?? null) !== aircraftId) continue;
    const rot = rules.rotations.get(id), route = rot ? rules.routes.get(rot.route_id) : undefined;
    if (!route) continue;
    const ends = { airline_id: route.airline_id, hub: route.hub_code, dest: route.dest_code, distance_km: route.distance_km, type_id: type?.id ?? null };
    const stored = (l: LegRow | undefined) => ({ days_utc: l?.days_utc ?? [], dep_utc_min: l?.dep_utc_min ?? null, block_min: l?.block_min ?? null });
    const local = localTimes(rules, ends, stored(leg1), stored(leg2));
    const v = view(rules, ends, local);
    const atHub = wave(rules, airlineBaseAt(rules, route.hub_code, route.airline_id), local.dep_hub, v.back?.arr ?? null);
    const destBase = airlineBaseAt(rules, route.dest_code, route.airline_id);
    const atDest = destBase ? wave(rules, destBase, local.dep_dest, v.out?.arr ?? null) : null;
    if (atHub.level === "bad" || atDest?.level === "bad") out.push(id);
  }
  return out.sort((a, b) => a - b);
}

/** An aircraft's issues (by id or registration), in the old planner's order; none when it's clean. The week and its
 *  maintenance can be given when the caller has them already. */
export function issues(rules: Rules, aircraft: number | string | AircraftRow, legs: readonly TimedLeg[] = timedLegs(rules),
  week?: AircraftWeek | null, maint?: Maintenance | NoMaintenance | null): TailIssue[] {
  const a = typeof aircraft === "object" ? aircraft : findAircraft(rules, aircraft);
  if (!a) return [];
  const w = week ?? weekOf(rules, a, legs);
  if (!w) return [];
  const type = typeOfAircraft(rules, a.id);
  const m = maint ?? maintenanceOfWeek(rules, type, a.airline_id, w.legs);
  const out: TailIssue[] = [];
  const target = settingNumber(rules, "aircraft_block_target_h", a.airline_id);
  if (w.block_hours_day < target) out.push({ kind: "block_hours", block_hours_day: w.block_hours_day, target_h: target });
  const short = w.legs.filter((l) => l.turn?.short).length;
  if (short) out.push({ kind: "short_turns", count: short });
  if (m && m.ratio != null && "level" in m && m.level !== "ok") {
    out.push({ kind: "maintenance", level: m.level, pct: m.pct, min_pct: m.min_pct, target_pct: m.target_pct });
  }
  const tight = w.legs.filter((l) => l.turn?.tight).length;
  if (tight) out.push({ kind: "tight_turns", count: tight, margin_min: settingNumber(rules, "turn_margin_min", a.airline_id) });
  const pos = w.legs.filter((l) => !l.position_ok).length;
  if (pos) out.push({ kind: "positions", count: pos });
  if (type?.gap_target_h != null && w.legs.length) {
    const longest = Math.max(0, ...w.legs.map((l) => l.ground_min ?? 0));
    if (longest < Number(type.gap_target_h) * 60) out.push({ kind: "longest_gap", gap_min: longest, target_h: Number(type.gap_target_h) });
  }
  if (m && m.ratio != null && "max_gap_ok" in m && m.max_gap_ok === false && m.max_gap_limit_h != null) {
    out.push({ kind: "maintenance_gap", max_gap_h: m.max_gap_h, limit_h: m.max_gap_limit_h, counting_stops: m.counting_stops });
  }
  const off = offWave(rules, a.id);
  if (off.length) out.push({ kind: "off_wave", count: off.length, rotation_ids: off });
  return out;
}

/** Whether the old Tails marks the aircraft (its red dot, and the "Needs a look" filter's legs): a short turn or a leg
 *  that starts where the aircraft isn't. */
export const marked = (w: AircraftWeek): boolean => w.legs.some((l) => l.turn?.short || !l.position_ok);

/** The old Tails' "Needs a look" filter: marked, or maintenance under maintenance_target_pct. */
export const needsALook = (w: AircraftWeek, m: Maintenance | NoMaintenance | null | undefined): boolean =>
  marked(w) || (!!m && m.ratio != null && "level" in m && m.level !== "ok");
