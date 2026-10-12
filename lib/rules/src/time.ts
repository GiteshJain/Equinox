// time: local and UTC times at an airport (manual §9: the game runs standard time all year). An airport's offset is the
// world's correction (world_airports.utc_offset_override) if it has one, else the game's (airports.utc_offset); one
// whose offset isn't known counts as UTC, as the old planner and the database's getter count it.
// The old code it follows: the old planner's utcOf; the optimiser's off.
import type { Rules } from "./types.js";

export const DAY = 1440;
export const WEEK = 7 * DAY;

/** a mod n, always 0 to n - 1. */
export const mod = (a: number, n: number): number => ((a % n) + n) % n;

/** The airport's UTC offset in hours, or null when it isn't known. */
export function utcOffsetHours(rules: Rules, code: string): number | null {
  const a = rules.airports.get(code);
  if (!a) return null;
  const v = a.utc_offset_override ?? a.utc_offset;
  return v == null || !Number.isFinite(Number(v)) ? null : Number(v);
}

/** The airport's UTC offset in whole minutes (+330 for Delhi); 0 when it isn't known. */
export function utcOffsetMin(rules: Rules, code: string): number {
  const h = utcOffsetHours(rules, code);
  return h == null ? 0 : Math.round(h * 60);
}

/** A weekday (ISO, 1 = Monday) and minute of the day as a minute of the week, 0 to 10,079. */
export const weekMinute = (day: number, minute: number): number => mod((day - 1) * DAY + minute, WEEK);

/** The weekday (ISO, 1 = Monday) of a minute of the week. */
export const dayOf = (weekMin: number): number => Math.floor(mod(weekMin, WEEK) / DAY) + 1;

/** The minute of the day of a minute of the week. */
export const minuteOf = (weekMin: number): number => mod(weekMin, DAY);

/** A UTC minute (of the day or of the week) as local time at the airport, of the day or of the week alike. */
export function toLocal(rules: Rules, code: string, utcMin: number, span: number = WEEK): number {
  return mod(utcMin + utcOffsetMin(rules, code), span);
}

/** A local minute at the airport (of the day or of the week) as UTC. */
export function toUtc(rules: Rules, code: string, localMin: number, span: number = WEEK): number {
  return mod(localMin - utcOffsetMin(rules, code), span);
}

/** The local weekdays a departure at dep_utc_min on these UTC weekdays leaves on, at the airport. Sorted, no repeats. */
export function localDays(rules: Rules, code: string, daysUtc: readonly number[], depUtcMin: number): number[] {
  return [...new Set(daysUtc.map((d) => dayOf(toLocal(rules, code, weekMinute(d, depUtcMin)))))].sort((a, b) => a - b);
}

/** A departure given in local time at the airport (weekdays and clock minute) as flight_legs stores it, in UTC. */
export function fromLocal(rules: Rules, code: string, daysLocal: readonly number[], depLocalMin: number): { days_utc: number[]; dep_utc_min: number } {
  const off = utcOffsetMin(rules, code);
  const weeks = daysLocal.map((d) => mod(weekMinute(d, depLocalMin) - off, WEEK));
  return { days_utc: [...new Set(weeks.map(dayOf))].sort((a, b) => a - b), dep_utc_min: mod(depLocalMin - off, DAY) };
}

/** "HH:MM" for a minute of the day (a minute of the week is taken modulo the day). */
export function clock(min: number): string {
  const m = mod(Math.round(min), DAY);
  return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
}

/** Minutes after midnight for "HH:MM" (or "H:MM", "HH:MM:SS"), or null when it isn't a clock time. */
export function parseClock(s: string | null | undefined): number | null {
  if (s == null) return null;
  const m = /^(\d{1,2}):(\d{2})(?::\d{2})?$/.exec(String(s).trim());
  if (!m) return null;
  const h = Number(m[1]), mi = Number(m[2]);
  return h > 23 || mi > 59 ? null : h * 60 + mi;
}

/** A moment (an ISO time such as 2026-10-12T14:30:00Z, or milliseconds since 1970) as minutes from Monday 00:00 UTC,
 *  with seconds as a fraction. The moment is always an argument: the library never reads a clock. */
export function weekMinuteAt(moment: string | number): number {
  const t = typeof moment === "number" ? moment : Date.parse(moment);
  if (!Number.isFinite(t)) throw new Error(`not a moment: ${String(moment)}`);
  const d = new Date(t);
  const iso = ((d.getUTCDay() + 6) % 7) + 1;
  return (iso - 1) * DAY + d.getUTCHours() * 60 + d.getUTCMinutes() + d.getUTCSeconds() / 60 + d.getUTCMilliseconds() / 60000;
}
