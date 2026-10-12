// maintenance: usable ground time against the need, for an aircraft's week (manual §4: at or above 100% is firm, aim
// for 105%; manual §9: the need depends on take-offs and landings as well as hours, and maintenance can be done at any
// airport with a long enough ground gap).
//   need = each departure's maint_per_cycle + its block hours × maint_per_hour (the type's figures);
//   have = each ground gap's time beyond the type's ground_keep_min (the turn the game keeps at each end), counted
//          when that is at least maint_min_ground_min.
// The share have ÷ need is bad under maintenance_min_pct and a warning under maintenance_target_pct.
// The old code it follows: the old planner's maintFor. One change: a gap the old planner took for an overlap only
// because it is longer than 156 hours (its "gap > WEEK − 720") is counted here, since the aircraft really is on the
// ground; an overlap is a next departure before the landing (aircraftWeek).
import { forAircraft as weekOf, type AircraftWeek, type WeekLeg } from "./aircraftWeek.js";
import { timedLegs } from "./block.js";
import { findAircraft, settingNumber, typeOfAircraft } from "./input.js";
import type { AircraftRow, AircraftTypeRow, Rules, TimedLeg } from "./types.js";

export interface Maintenance {
  /** have ÷ need. */
  ratio: number;
  /** The ratio as a whole percent, as the planner shows it. */
  pct: number;
  need_min_week: number;
  have_min_week: number;
  need_min_day: number;
  have_min_day: number;
  level: "ok" | "warn" | "bad";
  min_pct: number;
  target_pct: number;
}

/** Why there is no figure: no legs, or the type lacks a figure the rule needs. */
export interface NoMaintenance {
  ratio: null;
  reason: string;
}

/** Maintenance for a sequenced week of departures on a type (see aircraftWeek.sequenceWeek). */
export function ofWeek(rules: Rules, type: AircraftTypeRow | undefined, airlineId: number | null, legs: readonly WeekLeg[]): Maintenance | NoMaintenance {
  if (!type) return { ratio: null, reason: "no aircraft type" };
  const mc = type.maint_per_cycle, mh = type.maint_per_hour, keep = type.ground_keep_min;
  if (mc == null || mh == null || keep == null) return { ratio: null, reason: `aircraft type ${type.name} lacks maint_per_cycle, maint_per_hour or ground_keep_min` };
  if (!legs.length) return { ratio: null, reason: "no flights" };
  const thr = settingNumber(rules, "maint_min_ground_min", airlineId);
  let need = 0, have = 0;
  for (const l of legs) {
    need += Number(mc) + Number(mh) * l.block_min / 60;
    if (l.ground_min != null && !l.overlap && l.ground_min - Number(keep) >= thr) have += l.ground_min - Number(keep);
  }
  if (!need) return { ratio: null, reason: "no maintenance need" };
  const ratio = have / need;
  const minPct = settingNumber(rules, "maintenance_min_pct", airlineId), targetPct = settingNumber(rules, "maintenance_target_pct", airlineId);
  return {
    ratio, pct: Math.round(ratio * 100), need_min_week: need, have_min_week: have, need_min_day: need / 7, have_min_day: have / 7,
    level: ratio < minPct / 100 ? "bad" : ratio < targetPct / 100 ? "warn" : "ok", min_pct: minPct, target_pct: targetPct,
  };
}

/** An aircraft's maintenance for its week (by id or registration), from all the legs given (by default the input's). */
export function forAircraft(rules: Rules, aircraft: number | string | AircraftRow, legs: readonly TimedLeg[] = timedLegs(rules), week?: AircraftWeek | null): Maintenance | NoMaintenance | null {
  const a = typeof aircraft === "object" ? aircraft : findAircraft(rules, aircraft);
  if (!a) return null;
  const w = week ?? weekOf(rules, a, legs);
  return w ? ofWeek(rules, typeOfAircraft(rules, a.id), a.airline_id, w.legs) : null;
}
