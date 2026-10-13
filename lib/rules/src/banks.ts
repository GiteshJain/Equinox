// banks: each hub's bank windows (manual §4: three banks per hub, bank times in airline_bases.bank_times, local clock
// time), and which bank a departure collects and an arrival feeds. A focus city has no banks of its own.
// A bank departing at T: its departures leave from T to T + bank_departure_window_min; its arrivals must land by
// T − the airport's minimum connection time − bank_buffer_min, in a window of bank_arrival_window_min before that.
// An arrival feeds the first bank it can make (at least the minimum connection time plus the buffer before the bank
// departs): "in" inside the arrival window, "early" before it but within connection_max_wait_h, otherwise "late".
// The old code it follows: the old planner's bankWindows and waveAt.
import { mctAt } from "./airport.js";
import { settingNumber } from "./input.js";
import { DAY, mod, parseClock } from "./time.js";
import type { BaseRow, Rules } from "./types.js";

export interface BankWindow {
  /** The bank's number: its slot in bank_times, from 1. */
  n: number;
  /** Local minutes of the day at the hub. */
  dep: number;
  dep_end: number;
  arr_start: number;
  arr_end: number;
}

export const isFocus = (base: BaseRow | undefined | null): boolean => !!base && base.role === "focus";

/** The base at an airport: the airline's own if one is given and it has one there, else the first in the bases' order
 *  (as the old planner's hub(code) finds it). */
export function baseAt(rules: Rules, code: string, airlineId?: number | null): BaseRow | undefined {
  const here = rules.bases.filter((b) => b.airport_code === code);
  return (airlineId == null ? undefined : here.find((b) => b.airline_id === airlineId)) ?? here[0];
}

/** Whether a local minute t falls in the window s..e (both included, wrapping past midnight). */
export const inWindow = (t: number, s: number, e: number): boolean => mod(t - s, DAY) <= mod(e - s, DAY);

/** A hub's bank windows; none for a focus city. */
export function bankWindows(rules: Rules, base: BaseRow): BankWindow[] {
  if (isFocus(base)) return [];
  const al = base.airline_id;
  const mct = mctAt(rules, base.airport_code).minutes;
  const buf = settingNumber(rules, "bank_buffer_min", al);
  const arrWin = settingNumber(rules, "bank_arrival_window_min", al);
  const depWin = settingNumber(rules, "bank_departure_window_min", al);
  const out: BankWindow[] = [];
  (base.bank_times ?? []).forEach((s, i) => {
    const t = parseClock(s);
    if (t == null) return;
    const deadline = mod(t - mct - buf, DAY);
    out.push({ n: i + 1, dep: t, dep_end: mod(t + depWin, DAY), arr_start: mod(deadline - arrWin, DAY), arr_end: deadline });
  });
  return out;
}

/** The bank a departure at this local minute collects, or null when it leaves outside every departure window. */
export function bankOfDeparture(rules: Rules, base: BaseRow, depLocal: number): BankWindow | null {
  return bankWindows(rules, base).find((w) => inWindow(mod(depLocal, DAY), w.dep, w.dep_end)) ?? null;
}

export interface ArrivalBank {
  /** The bank it feeds, or 0 when none within the wait. */
  n: number;
  status: "in" | "early" | "late";
  /** Minutes from landing to that bank's departure. */
  wait_min: number | null;
  /** The minimum connection time plus the buffer. */
  need_min: number;
  /** How far before the arrival window it lands. */
  early_by_min: number;
}

/** The bank an arrival at this local minute feeds. */
export function bankOfArrival(rules: Rules, base: BaseRow, arrLocal: number): ArrivalBank {
  const al = base.airline_id;
  const need = mctAt(rules, base.airport_code).minutes + settingNumber(rules, "bank_buffer_min", al);
  const arrWin = settingNumber(rules, "bank_arrival_window_min", al);
  const maxWait = settingNumber(rules, "connection_max_wait_h", al) * 60;
  let best: { w: BankWindow; gap: number } | null = null;
  for (const w of bankWindows(rules, base)) {
    const gap = mod(w.dep - arrLocal, DAY);
    if (gap >= need && (!best || gap < best.gap)) best = { w, gap };
  }
  if (!best) return { n: 0, status: "late", wait_min: null, need_min: need, early_by_min: 0 };
  const slack = best.gap - need;
  const status = slack <= arrWin ? "in" : best.gap <= maxWait ? "early" : "late";
  return { n: status === "late" ? 0 : best.w.n, status, wait_min: best.gap, need_min: need, early_by_min: Math.max(0, slack - arrWin) };
}
