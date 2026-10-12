// What a world says about an airport that the rules need: its minimum connection time and its night ban.
import { parseClock } from "./time.js";
import type { Rules } from "./types.js";

/** The minimum connection time used where an airport has none (spec §5): the old planner's figure for any airport that
 *  isn't one of our bases (mctAt). The only connection figure not read from the input. */
export const DEFAULT_MCT_MIN = 90;

/** An airport's minimum connection time, minutes (world_airports.mct_min), and where it came from. */
export function mctAt(rules: Rules, code: string): { minutes: number; source: "airport" | "default" } {
  const v = rules.airports.get(code)?.mct_min;
  return v == null ? { minutes: DEFAULT_MCT_MIN, source: "default" } : { minutes: Number(v), source: "airport" };
}

/** An airport's night ban as local minutes [from, to] (inclusive, and it may wrap past midnight), or null. */
export function nightBanAt(rules: Rules, code: string): { from: number; to: number; text: string } | null {
  const a = rules.airports.get(code);
  const from = parseClock(a?.night_ban_from), to = parseClock(a?.night_ban_to);
  if (from == null || to == null) return null;
  return { from, to, text: `${a?.night_ban_from?.slice(0, 5)}–${a?.night_ban_to?.slice(0, 5)}` };
}

/** Whether a local minute of the day falls inside the airport's night ban (both ends included, as the old planner's
 *  banAt and plan.py's in_curfew count it). */
export function inNightBan(rules: Rules, code: string, localMin: number): boolean {
  const b = nightBanAt(rules, code);
  if (!b) return false;
  const m = ((Math.round(localMin) % 1440) + 1440) % 1440;
  return b.from <= b.to ? m >= b.from && m <= b.to : m >= b.from || m <= b.to;
}
