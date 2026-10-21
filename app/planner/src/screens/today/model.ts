// Today's logic (spec docs/specs/2026-10-20-today-performance-systems.md): the answer at the top ("what do I do now?",
// All clear when nothing is waiting), the capture in one line, each airline's orders and the aircraft to file. Every
// figure is its one home's (decision #19): the capture's from capture_status(), can order and the safe types from
// airline_cards() and cash_forecast(), the delivery lines from the planning library's growth.orderQueues, the aircraft
// on order from their table. This file only words them, so the unit tests can try each case.
import type { QueueCell } from "@rules";
import type { OurAirline } from "../../data/airlines";
import { shortType } from "../../ui/aircraftNames";
import { fcDay, type ForecastType, type NextOrder } from "../performance/model";
import type { CaptureRead } from "../home/reads";
import type { OnOrderGroup } from "../home/onOrder";
import { CAPTURE_BAD_H, CAPTURE_LATE_H } from "./attention";

export type Mark = "ok" | "warn" | "bad";

// ---------- the answer at the top: All clear, or what's waiting
export interface Waiting {
  /** Our airlines that can safely order now (airline_cards()'s can order). */
  canOrder: readonly string[];
  /** Aircraft that have arrived with a plan card, waiting to be filed. */
  toFile: number;
  /** Needs attention's items, those dismissed left out. */
  attention: number;
  /** Differences Game check found, once it has been run (0 before). */
  game: number;
}

const plural = (n: number, one: string, many = one + "s") => `${n} ${n === 1 ? one : many}`;

/** The answer at the top of Today: All clear when nothing is waiting (no order possible, nothing to file, no attention
 *  items, no Game check differences), else how many things and what. */
export function waitingWords(w: Waiting): { clear: boolean; title: string; parts: string[] } {
  const parts = [
    ...(w.canOrder.length ? [`${w.canOrder.join(", ")} can order`] : []),
    ...(w.toFile ? [`${plural(w.toFile, "aircraft", "aircraft")} to file`] : []),
    ...(w.attention ? [`${plural(w.attention, "item")} in needs attention`] : []),
    ...(w.game ? [`${plural(w.game, "Game check difference")}`] : []),
  ];
  if (!parts.length) return { clear: true, title: "All clear", parts: ["Nothing to order, file or fix from the game, and nothing needs attention."] };
  const n = (w.canOrder.length ? 1 : 0) + (w.toFile ? 1 : 0) + (w.attention ? 1 : 0) + (w.game ? 1 : 0);
  return { clear: false, title: n === 1 ? "One thing waiting" : `${n} things waiting`, parts };
}

// ---------- the capture in one line
export type CaptureState = "complete" | "missing" | "short" | "broken";
export interface CaptureLine { state: CaptureState; mark: Mark; text: string }

const WORDS = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"];
const numberWord = (n: number): string => WORDS[n] ?? String(n);

/** A moment as the line writes it: "17:08 UTC" on the day it is, else "19 Oct 17:08 UTC". */
export function clockWords(at: string, now: Date): string {
  const d = new Date(at);
  const hm = d.toISOString().slice(11, 16) + " UTC";
  if (d.toISOString().slice(0, 10) === now.toISOString().slice(0, 10)) return hm;
  return `${d.getUTCDate()} ${d.toLocaleString("en-GB", { month: "short", timeZone: "UTC" })} ${hm}`;
}

/** The capture in one line, from capture_status() (Home's read: each airline's latest page, and its latest verdict):
 *  complete ("All six airlines captured, all good, 17:08 UTC"), or what's missing (an airline not captured for over a
 *  day, needs attention's 26 hours; red after 48), short (amber) or broken (red). A verdict counts the same night only,
 *  as needs attention counts it; a capture stored before the page checks counts as good. */
export function captureLine(airlines: readonly Pick<OurAirline, "id" | "name">[], cap: CaptureRead, now: Date): CaptureLine {
  const hours = (at: string | null | undefined) => (at ? (now.getTime() - Date.parse(at)) / 3_600_000 : null);
  // the airlines the capture covers (capture_status()'s: our active airlines with a home base), in our order
  const rows = airlines.filter((a) => cap.last.some((x) => x.airline_id === a.id)).map((a) => {
    const at = cap.last.find((x) => x.airline_id === a.id)?.at ?? null;
    const h = hours(at);
    const v = (cap.verdicts ?? []).filter((x) => x.airline_id === a.id && (hours(x.at) ?? Infinity) <= CAPTURE_LATE_H)
      .sort((x, y) => Date.parse(y.at) - Date.parse(x.at))[0];
    return { a, at, h, captured: h != null && h <= CAPTURE_LATE_H, verdict: v?.verdict ?? null, words: String(v?.words ?? "").replace(/^(short|broken):\s*/, "") };
  });
  const missing = rows.filter((r) => !r.captured);
  const short = rows.filter((r) => r.captured && r.verdict === "short");
  const broken = rows.filter((r) => r.captured && r.verdict === "broken");
  const latest = rows.filter((r) => r.captured && r.at).map((r) => r.at as string).sort((x, y) => Date.parse(y) - Date.parse(x))[0];
  const n = rows.length;
  const head = !missing.length
    ? (n === 1 ? `${rows[0]?.a.name} captured` : `All ${numberWord(n)} airlines captured`)
    : missing.length === n ? "No airline captured in the last day" : `${n - missing.length} of ${n} airlines captured`;
  const when = latest ? clockWords(latest, now) : "";
  const state: CaptureState = broken.length ? "broken" : missing.length ? "missing" : short.length ? "short" : "complete";
  if (state === "complete") return { state, mark: "ok", text: `${head}, all good${when ? ", " + when : ""}` };
  const names = (list: typeof rows) => list.map((r) => r.a.name).join(", ");
  const what = (list: typeof rows) => list.map((r) => (r.words ? `${r.a.name} (${r.words})` : r.a.name)).join(", ");
  const parts = [
    head + (when ? ", " + when : ""),
    ...(missing.length && missing.length < n ? [`not captured: ${names(missing)}`] : []),
    ...(missing.length === n ? ["press Capture all airlines in the game"] : []),
    ...(short.length ? [`short: ${what(short)}`] : []),
    ...(broken.length ? [`broken: ${what(broken)}`] : []),
  ];
  const late = missing.some((r) => r.h == null || r.h > CAPTURE_BAD_H);
  return { state, mark: broken.length || late ? "bad" : "warn", text: parts.join(" · ") };
}

// ---------- orders: whether each airline can order now or from when, the types that are safe, and its delivery lines
export interface OrderRow {
  airline: OurAirline;
  /** Can order now (an action: amber), safe from a day, needs a capture, or not within 14 days. */
  status: { kind: "now" | "later" | "needs" | "none"; text: string };
  /** The types safe to order (cash_forecast()'s), by when: now, then each day from which some are safe; none when it can't say. */
  types: { when: string; now: boolean; names: string[] }[];
  /** Each delivery line the airline may have: how many on order and when it runs dry, or empty. */
  lines: { family: string; text: string; warn: boolean; soon: string | null }[];
}

/** When an order queue runs dry, in UTC: "10-14 05:53". */
export const runsDryWords = (ms: number): string => new Date(ms).toISOString().slice(5, 16).replace("T", " ");
/** How soon: "now" once past, else "in 12 h". */
export const soonWords = (hours: number): string => (hours < 0 ? "now" : "in " + Math.max(0, Math.round(hours)) + " h");

/** An airline's order status, from its card's next order (airline_cards(), from cash_forecast()). */
export function orderStatus(next: NextOrder | null | undefined, canNow: readonly string[] | null | undefined): OrderRow["status"] {
  if (canNow?.length) return { kind: "now", text: "Can order now" };
  if (!next || next.when === "needs") return { kind: "needs", text: `Needs ${next?.missing || "a capture"}` };
  if (next.when === "now") return { kind: "now", text: "Can order now" };
  if (next.when === "later" && next.safe_from) return { kind: "later", text: `Safe from ${fcDay(next.safe_from)}` };
  return { kind: "none", text: "Not within 14 days" };
}

/** The types that are safe, from cash_forecast()'s types, grouped by when: now first, then each first safe day. Each
 *  short name shows once in its group (the forecast lists a type's variants apart, and several share a short name). A
 *  type that isn't safe within 14 days is left out. */
export function safeTypes(types: readonly ForecastType[] | undefined): OrderRow["types"] {
  const groups = new Map<string, { when: string; now: boolean; day: number; names: string[] }>();
  for (const t of types ?? []) {
    if (t.safe_day == null || (t.safe_day !== 0 && !t.safe_from)) continue;
    const now = t.safe_day === 0, when = now ? "now" : `from ${fcDay(t.safe_from as string)}`;
    let g = groups.get(when);
    if (!g) groups.set(when, (g = { when, now, day: t.safe_day, names: [] }));
    const name = shortType(t.type);
    if (!g.names.includes(name)) g.names.push(name);
  }
  return [...groups.values()].sort((a, b) => a.day - b.day).map(({ when, now, names }) => ({ when, now, names }));
}

/** Each delivery line the airline may have (the families not in its fleet left out): how many on order and when the
 *  last arrives, warned when it runs dry within order_queue_warn_h; or empty, standing idle. */
export function deliveryLines(cells: readonly QueueCell[]): OrderRow["lines"] {
  return cells.filter((c) => c.in_fleet).map((c) => (c.count && c.last_ms != null
    ? { family: c.family, text: `${c.count} on order · runs dry ${runsDryWords(c.last_ms)} UTC`, warn: c.warn, soon: c.warn && c.hours != null ? soonWords(c.hours) : null }
    : { family: c.family, text: "empty: nothing on order", warn: false, soon: null }));
}

// ---------- aircraft to file: arrived with a plan card (Home's Aircraft on order, whose File into planner moved here)
export interface FileRow { airline: OnOrderGroup["airline"]; registration: string; type: string; config: string; at: number; base: string; plan: string; href: string }

/** The aircraft that have arrived with a plan card, airline by airline, soonest first, each with its link to file it on
 *  Tails (/tails?airline=PA&file=N123AB). */
export function toFile(groups: readonly OnOrderGroup[]): FileRow[] {
  return groups.flatMap((g) => g.rows.filter((r) => r.arrived && r.hasCard).map((r) => ({
    airline: g.airline, registration: r.registration, type: r.type, config: r.config, at: r.at, base: r.base, plan: r.plan,
    href: "/tails?" + new URLSearchParams({ ...(g.airline.code ? { airline: g.airline.code } : {}), file: r.registration }).toString(),
  })));
}
