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
// Since 28 Oct (spec docs/specs/2026-10-27-long-haul-lines.md, the settings and §3) the figures also give the spacing of
// the stops that count: the longest stretch between two of them over the aircraft's repeating week, wrapping around the
// week's end (spacing), against settings.maintenance_max_gap_h (40 hours: Gitesh, 27 Oct, condition can fall below 50%
// with only one long stop a week). A week with one counting stop has one stretch, the rest of the week; a week with
// none has no stretch to measure (max_gap_h null, and not ok). An input without the setting isn't checked (null).
import { forAircraft as weekOf, type AircraftWeek, type WeekLeg } from "./aircraftWeek.js";
import { timedLegs } from "./block.js";
import { findAircraft, setting, settingNumber, typeOfAircraft } from "./input.js";
import { WEEK, mod } from "./time.js";
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
  /** The stops that count for maintenance in the week (a ground gap at least maint_min_ground_min beyond ground_keep_min). */
  counting_stops: number;
  /** The longest stretch between two counting stops, hours, from the departure after one to the landing at the next,
   *  wrapping around the week's end; null when no stop counts (then the whole week is one stretch). */
  max_gap_h: number | null;
  /** settings.maintenance_max_gap_h (the longest stretch allowed), or null when the input hasn't got it. */
  max_gap_limit_h: number | null;
  /** The stretch is within the limit; null when the input has no limit. False when no stop counts. */
  max_gap_ok: boolean | null;
}

/** The spacing of the counting stops over a sequenced week (aircraftWeek.sequenceWeek, in departure order): how many
 *  count, and the longest stretch between two of them, minutes, measured from the departure after one stop to the
 *  landing at the next and wrapping around the week's end. A week with one counting stop has one stretch: the rest of
 *  the week. A week with no legs, or none that counts, has no stretch (null). Both a plain card (one day repeated) and a
 *  line's card (7 different days) are one repeating week, so the same walk serves both. */
export function spacing(legs: readonly WeekLeg[], keepMin: number, minGroundMin: number): { counting_stops: number; max_gap_min: number | null } {
  const counts = legs.map((l) => l.ground_min != null && !l.overlap && l.ground_min - keepMin >= minGroundMin);
  const stops = counts.map((c, i) => (c ? i : -1)).filter((i) => i >= 0);
  if (!stops.length) return { counting_stops: 0, max_gap_min: null };
  let longest = 0;
  stops.forEach((i, k) => {
    // the stretch ending at this stop starts at the departure after the previous counting stop (itself, with one stop)
    const prev = stops[(k - 1 + stops.length) % stops.length] ?? i;
    const start = legs[(prev + 1) % legs.length], end = legs[i];
    if (!start || !end) return;
    longest = Math.max(longest, mod(end.arr_utc - start.dep_utc, WEEK));
  });
  return { counting_stops: stops.length, max_gap_min: longest };
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
  const sp = spacing(legs, Number(keep), thr);
  const limit = setting(rules, "maintenance_max_gap_h", airlineId) === undefined ? null : settingNumber(rules, "maintenance_max_gap_h", airlineId);
  const gapH = sp.max_gap_min == null ? null : Math.round(sp.max_gap_min / 60 * 10) / 10;
  return {
    ratio, pct: Math.round(ratio * 100), need_min_week: need, have_min_week: have, need_min_day: need / 7, have_min_day: have / 7,
    level: ratio < minPct / 100 ? "bad" : ratio < targetPct / 100 ? "warn" : "ok", min_pct: minPct, target_pct: targetPct,
    counting_stops: sp.counting_stops, max_gap_h: gapH, max_gap_limit_h: limit,
    max_gap_ok: limit == null ? null : sp.max_gap_min != null && sp.max_gap_min <= limit * 60,
  };
}

/** An aircraft's maintenance for its week (by id or registration), from all the legs given (by default the input's). */
export function forAircraft(rules: Rules, aircraft: number | string | AircraftRow, legs: readonly TimedLeg[] = timedLegs(rules), week?: AircraftWeek | null): Maintenance | NoMaintenance | null {
  const a = typeof aircraft === "object" ? aircraft : findAircraft(rules, aircraft);
  if (!a) return null;
  const w = week ?? weekOf(rules, a, legs);
  return w ? ofWeek(rules, typeOfAircraft(rules, a.id), a.airline_id, w.legs) : null;
}
