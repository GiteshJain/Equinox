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
  /** The first bank it can make however long the wait (the old waveAt's a.n), or 0 when it can make none: the bank the
   *  Hubs screen's flight list names for an arrival, as the old Hubs named it (#18 build pull request 8). */
  next: number;
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
  if (!best) return { n: 0, next: 0, status: "late", wait_min: null, need_min: need, early_by_min: 0 };
  const slack = best.gap - need;
  const status = slack <= arrWin ? "in" : best.gap <= maxWait ? "early" : "late";
  return { n: status === "late" ? 0 : best.w.n, next: best.w.n, status, wait_min: best.gap, need_min: need, early_by_min: Math.max(0, slack - arrWin) };
}

/** The airline's own base at an airport (no other airline's), as the old planner's hubOf(airline, code) finds it. */
export function airlineBaseAt(rules: Rules, code: string, airlineId: number): BaseRow | undefined {
  return rules.bases.find((b) => b.airport_code === code && b.airline_id === airlineId);
}

/** A duration as the old planner writes one (its hhmm): hours and minutes, "1:05", "12:40". */
export const duration = (min: number): string => `${Math.floor(min / 60)}:${String(mod(Math.round(min), 60)).padStart(2, "0")}`;

/** How a frequency fits a base's banks (the old planner's waveAt): ok, warn, bad, or mute where there are no banks. */
export interface Wave {
  level: "ok" | "warn" | "bad" | "mute";
  /** The words on its pill: "B1 out · B2 in", "dep floats · B2 in, 1:05 early", "arr off wave", "dep + arr off wave",
   *  "focus city · times to HUB banks", "no banks set", or "hub?" without a base. */
  text: string;
  /** The departure: the bank it leaves in (n), or ok false when it floats. Null when no departure was given. */
  dep: { ok: boolean; n: number } | null;
  /** The arrival: the bank it feeds. Null when no arrival was given. */
  arr: ArrivalBank | null;
}

/** How a departure and an arrival (local minutes at the base, either may be null) fit its banks: a departure inside a
 *  bank's departure window collects that bank, else it floats; an arrival feeds a bank in its window, early, or late
 *  (nothing within connection_max_wait_h). Bad when the arrival is late; a warning when the departure floats or the
 *  arrival is early. A focus city has no banks of its own. */
export function wave(rules: Rules, base: BaseRow | undefined, depLocal: number | null, arrLocal: number | null): Wave {
  if (!base) return { level: "mute", text: "hub?", dep: null, arr: null };
  if (isFocus(base)) return { level: "mute", text: "focus city" + (base.parent_code ? ` · times to ${base.parent_code} banks` : ""), dep: null, arr: null };
  if (!bankWindows(rules, base).length) return { level: "mute", text: "no banks set", dep: null, arr: null };
  const hit = depLocal == null ? null : bankOfDeparture(rules, base, depLocal);
  const dep = depLocal == null ? null : { ok: !!hit, n: hit?.n ?? 0 };
  const arr = arrLocal == null ? null : bankOfArrival(rules, base, arrLocal);
  const bad = dep && !dep.ok && arr && arr.status === "late" ? "dep + arr off wave" : arr && arr.status === "late" ? "arr off wave" : "";
  const parts: string[] = [];
  if (dep) parts.push(dep.ok ? `B${dep.n} out` : "dep floats");
  if (arr && arr.status === "in") parts.push(`B${arr.n} in`);
  else if (arr && arr.status === "early") parts.push(`B${arr.n} in, ${duration(arr.early_by_min)} early`);
  const level = bad ? "bad" : (dep && !dep.ok) || (arr && arr.status === "early") ? "warn" : "ok";
  return { level, text: bad || parts.join(" · "), dep, arr };
}
