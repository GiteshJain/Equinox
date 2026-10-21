// Performance → Flights by day (Check's daily load report until 20 Oct, renamed; decision #18, build pull request 9): the
// day in the address (?day=), each departure's captured loads by airline and number, the day's summary from the captures
// or from loads typed by hand, and a flight's loads by class, as the old report and capLine word them. No screen code, so
// the unit tests run it.
import type { DayFlight } from "@rules";
import { pctWords } from "./growth";
import type { CapturedLoad, HandLoads } from "./reads";

// ---------- the day, in the address (?day=YYYY-MM-DD); today (UTC) without one, as the old planner started
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
export function parseDay(search: string, todayUtc: string): string {
  const d = new URLSearchParams(search).get("day") ?? "";
  return DAY_RE.test(d) && Number.isFinite(Date.parse(d + "T00:00:00Z")) ? d : todayUtc;
}
/** A day n days after (or before) another, as the old planner's ‹ and › move it. */
export function moveDay(day: string, n: number): string {
  return new Date(Date.parse(day + "T00:00:00Z") + n * 86_400_000).toISOString().slice(0, 10);
}
/** The UTC day of a moment (the old ui.lfDate's first value: the report pulled today completes today's departures). */
export const utcToday = (now: Date): string => now.toISOString().slice(0, 10);

/** A flight's key in the day's loads: its airline and number. */
export const loadKey = (airlineName: string, no: number | string): string => `${airlineName}|${no}`;
/** The day's captured loads by airline and flight number (the number from the code, "KF 1048" → 1048), the last one kept
 *  where a number shows twice, as the old CAP.loads keeps it. */
export function loadsByFlight(rows: readonly CapturedLoad[], day: string): Map<string, CapturedLoad> {
  const m = new Map<string, CapturedLoad>();
  for (const r of rows) if (String(r.flight_date).slice(0, 10) === day) m.set(loadKey(r.airline ?? "", String(r.code ?? "").replace(/^\D+/, "").trim()), r);
  return m;
}
/** The old planner's +x: a missing figure counts as 0, as its averages and counts take it. */
const plus = (v: number | null | undefined): number => Number(v ?? 0);
const avgOf = (arr: readonly number[]): number | null => (arr.length ? arr.reduce((x, y) => x + y, 0) / arr.length : null);
const bucket = (v: number): 70 | 85 | 95 => (v < 70 ? 70 : v < 85 ? 85 : 95);

export type DaySummary =
  | { kind: "captured"; departures: number; captured: number; economy: number | null; business: number | null; cargo: number | null; soldOut: number; under85: number }
  | { kind: "hand"; departures: number; under95: number; under85: number; under70: number }
  | { kind: "none"; departures: number };

/** The day's summary (the old report's line): from the captured loads when any flight was captured, else from the loads
 *  typed by hand once the day was marked complete (under 95, 85 and 70%), else not captured. */
export function daySummary(flights: readonly DayFlight[], loadOf: (f: DayFlight) => CapturedLoad | undefined, hand: HandLoads | undefined): DaySummary {
  const capd = flights.map(loadOf).filter((x): x is CapturedLoad => !!x);
  if (capd.length) {
    const nums = (k: "eco" | "bus" | "cargo") => capd.map((c) => plus(c[k])).filter((v) => !Number.isNaN(v));
    return {
      kind: "captured", departures: flights.length, captured: capd.length, economy: avgOf(nums("eco")), business: avgOf(nums("bus")), cargo: avgOf(nums("cargo")),
      soldOut: capd.filter((c) => plus(c.eco) >= 100).length, under85: capd.filter((c) => plus(c.eco) < 85).length,
    };
  }
  if (!hand?.done) return { kind: "none", departures: flights.length };
  const typed = new Map(hand.values.map((v) => [`${v.airline_id}|${v.flight_no}`, v.eco_pct]));
  const counts = { 95: 0, 85: 0, 70: 0 };
  for (const f of flights) {
    const v = typed.get(`${f.airline_id}|${f.no}`);
    if (v && v < 95) counts[bucket(v)]++;
  }
  return { kind: "hand", departures: flights.length, under95: counts[95] + counts[85] + counts[70], under85: counts[85] + counts[70], under70: counts[70] };
}
/** The summary in the old report's words (the sold-out count is bold on screen). */
export function summaryWords(s: DaySummary): string {
  if (s.kind === "captured") {
    return `${s.departures} departures · ${s.captured} captured · economy ${pctWords(s.economy)} · business ${pctWords(s.business)} · cargo ${pctWords(s.cargo)} · `
      + `${s.soldOut} sold out · ${s.under85} under 85%`;
  }
  if (s.kind === "hand") return `${s.departures} departures · entered by hand: under 95% ${s.under95} · under 85% ${s.under85} · under 70% ${s.under70}`;
  return `${s.departures} departures · not captured`;
}
/** One airline's line: departures, and with any captured, how many, the economy average and those sold out; and how
 *  many are in their first week. */
export function airlineDay(flights: readonly DayFlight[], loadOf: (f: DayFlight) => CapturedLoad | undefined) {
  const cl = flights.map(loadOf).filter((x): x is CapturedLoad => !!x);
  return {
    departures: flights.length, captured: cl.length, economy: avgOf(cl.map((c) => plus(c.eco)).filter((v) => !Number.isNaN(v))),
    soldOut: cl.filter((c) => plus(c.eco) >= 100).length, firstWeek: flights.filter((f) => f.leeway).length,
  };
}
/** A flight's loads by class (the old capLine): "Y 98% (176/180) · C 80% (16/20) · cargo 40%", marked low under 85% economy. */
export function capLine(r: CapturedLoad | undefined): { text: string; low: boolean } | null {
  if (!r) return null;
  const one = (lab: string, pct: number | null, p: number | null, n: number | null) =>
    pct == null ? "" : `${lab} ${Math.round(Number(pct))}%${p != null && n ? ` (${p}/${n})` : ""}`;
  const parts = [one("Y", r.eco, r.eco_pax, r.eco_seats), one("C", r.bus, r.bus_pax, r.bus_seats), one("F", r.fst, r.fst_pax, r.fst_seats),
    r.cargo == null ? "" : `cargo ${Math.round(Number(r.cargo))}%`].filter(Boolean);
  return parts.length ? { text: parts.join(" · "), low: r.eco != null && Number(r.eco) < 85 } : null;
}
