// loadReport: the day's departures for the Check screen's daily load report (#18 build pull request 9, spec
// docs/specs/2026-10-13-check.md). A day is a local date at departure, as the game's loads page lists flights:
//   - each frequency's outbound departs on its local weekdays at the hub, when it has a number;
//   - its return departs on the day it leaves, with its own number or the outbound's less one, when it has a departure:
//     since 28 Oct its own row's local weekdays (game.Frequency.back_days, as private.fig_flights_on reads them), so a
//     7-day line's return, days after its outbound, is on its day (spec docs/specs/2026-10-27-long-haul-lines.md §4);
//   - a departure in its frequency's first load_leeway_days (from the rotation's launch day) is "in its first week".
// In order of airline (airlines' position), then departure time as the old planner sorted its "HH:MM" text.
// The old code it follows: the old planner's flightsOn. The database's own copy of the same rule (private.fig_flights_on)
// feeds its load figures; this one gives the screen each flight's airports and time.
import { frequencies } from "./game.js";
import { view } from "./frequency.js";
import { settingNumber } from "./input.js";
import { clock } from "./time.js";
import type { Rules } from "./types.js";

/** One departure on the day. */
export interface DayFlight {
  airline_id: number;
  rotation_id: number;
  route_id: number;
  /** The flight number shown: its own, or for a return with none its outbound's less one. */
  no: number;
  from: string;
  to: string;
  /** Its local departure "HH:MM", "" when not typed. */
  dep: string;
  way: "out" | "back";
  /** The rotation's launch day, or null. */
  launched: string | null;
  /** It departs within its frequency's first load_leeway_days. */
  leeway: boolean;
}

const DAY_MS = 86_400_000;
const dayMs = (d: string): number => {
  const t = Date.parse(d.slice(0, 10) + "T00:00:00Z");
  if (!Number.isFinite(t)) throw new Error(`not a day: ${d}`);
  return t;
};
/** The ISO weekday of a day "YYYY-MM-DD" (1 = Monday). */
export const weekdayOf = (d: string): number => ((new Date(dayMs(d)).getUTCDay() + 6) % 7) + 1;
const dayDiff = (a: string, b: string): number => Math.round((dayMs(b) - dayMs(a)) / DAY_MS);

/** Every departure on a local date. launches: each rotation's launch day (rotations.launched_on). */
export function flightsOn(rules: Rules, day: string, launches: readonly { id: number; launched_on: string | null }[] = []): DayFlight[] {
  const wd = weekdayOf(day);
  const launched = new Map(launches.map((r) => [r.id, r.launched_on ? r.launched_on.slice(0, 10) : null]));
  const position = new Map([...rules.airlines.values()].map((a) => [a.id, a.position ?? Number.MAX_SAFE_INTEGER]));
  const out: DayFlight[] = [];
  for (const f of frequencies(rules, null)) {
    const v = view(rules, f.ends, f.local);
    const l = launched.get(f.rotation_id) ?? null;
    const leeway = l ? dayDiff(l, day) < settingNumber(rules, "load_leeway_days", f.ends.airline_id) : false;
    const noOut = f.leg1?.flight_no || null;
    const noBack = f.leg2?.flight_no || (noOut ? noOut - 1 : null);
    const base = { airline_id: f.ends.airline_id, rotation_id: f.rotation_id, route_id: f.route_id, launched: l, leeway };
    if (noOut && f.local.days.includes(wd)) {
      out.push({ ...base, no: noOut, from: f.hub, to: f.dest, dep: f.local.dep_hub == null ? "" : clock(f.local.dep_hub), way: "out" });
    }
    if (v.back && noBack) {
      if (f.back_days.includes(wd)) out.push({ ...base, no: noBack, from: f.dest, to: f.hub, dep: f.local.dep_dest == null ? "" : clock(f.local.dep_dest), way: "back" });
    }
  }
  return out.map((x, i) => ({ x, i }))
    .sort((a, b) => (position.get(a.x.airline_id) ?? 0) - (position.get(b.x.airline_id) ?? 0) || a.x.airline_id - b.x.airline_id
      || (a.x.dep < b.x.dep ? -1 : a.x.dep > b.x.dep ? 1 : 0) || a.i - b.i)
    .map((v) => v.x);
}
