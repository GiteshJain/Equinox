// The salary table (since 16 Nov; to-do 245, spec docs/specs/2026-11-16-salary-table.md; manual §7): how Systems'
// Salaries board and Today's one item word salary_table()'s answer. The capture reads each airline's Employee overview
// page and its country page; the table compares next week's salary (the box the capture and Gitesh set) with the target,
// the country page's average plus salary_above_average_pct (5%), and flags a position more than salary_flag_pct (1%)
// under or over it. A position with no staff is listed but never flagged (Gitesh, 16 Nov, choice 4 A). The database does
// every sum; this file only words it. No screen code, so the unit tests run it.
import type { AttItem } from "../../ui/attention";

export type SalaryFlag = "under" | "over" | "no_average";

export interface SalaryRow {
  position: string;
  group: string | null;
  employed: number | null;
  /** This week's salary per employee, AS$. */
  salary: number | null;
  /** Next week's salary per employee, AS$: the one compared. */
  salary_next: number | null;
  /** The country average the Employee overview page shows (the one the capture sets from). */
  overview_avg: number | null;
  /** The country page's average. */
  country_avg: number | null;
  target: number | null;
  diff: number | null;
  diff_pct: number | null;
  flag: SalaryFlag | null;
  averages_differ: boolean | null;
  raised_to: number | null;
}

export interface SalaryCounts { positions: number; flagged: number; under: number; over: number; no_average: number; averages_differ: number }

export interface SalaryAirline {
  airline_id: number;
  code: string | null;
  name: string;
  read_at: string | null;
  unattended: boolean | null;
  verdict: "ok" | "short" | "broken" | null;
  note: string | null;
  country: { id: number | null; name: string | null; code: string | null; ok: boolean } | null;
  counts: SalaryCounts;
  rows: SalaryRow[];
}

export interface SalaryTable {
  as_of: string;
  flag_pct: number;
  above_pct: number | null;
  counts: { flagged: number; under: number; over: number; no_average: number; airlines_flagged: number; not_read: number };
  airlines: SalaryAirline[];
}

export const SALARY_FLAG_WORDS: Record<SalaryFlag, string> = { under: "under target", over: "over target", no_average: "no country average" };

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;
/** A whole AS$ figure: "1,784"; "—" when there is none. */
export const asWords = (v: number | null | undefined): string => (v == null || !Number.isFinite(Number(v)) ? "—" : Math.round(Number(v)).toLocaleString("en-US"));
/** A signed difference: "+11" and "+1.05%", "−10" and "−0.95%"; "—" when there is none. */
export function diffWords(r: Pick<SalaryRow, "diff" | "diff_pct">): string {
  if (r.diff == null || r.diff_pct == null) return "—";
  const sign = (v: number) => (v > 0 ? "+" : v < 0 ? "−" : "");
  const pct = Math.abs(Number(r.diff_pct));
  return `${sign(r.diff)}${asWords(Math.abs(r.diff))} (${sign(Number(r.diff_pct))}${pct.toFixed(pct < 10 ? 2 : 1)}%)`;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** When it was read, in UTC: "16 Nov, 21:34 UTC". */
export function readAtWords(iso: string | null | undefined): string {
  if (!iso) return "not read yet";
  const d = new Date(iso);
  if (!Number.isFinite(d.getTime())) return "not read yet";
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}, ${iso.slice(11, 16)} UTC`;
}

/** An airline's heading line: "read 16 Nov, 21:34 UTC by the unattended capture · India (IN) · 2 off target". */
export function airlineReadWords(a: SalaryAirline): string {
  if (!a.read_at) return "not read yet: the next capture reads it";
  const parts = [`read ${readAtWords(a.read_at)}${a.unattended ? " by the unattended capture" : ""}`];
  if (a.country?.name) parts.push(`${a.country.name}${a.country.code ? ` (${a.country.code})` : ""}`);
  if (a.counts.flagged) parts.push(`${a.counts.flagged} off target`);
  else if (a.verdict !== "broken") parts.push("all within target");
  return parts.join(" · ");
}

/** The board's line: "5 positions more than 1% off target in 3 airlines · 1 with no country average", "every position
 *  within 1% of its target", or that nothing has been read yet. */
export function salaryCountsWords(t: SalaryTable): string {
  const read = t.airlines.filter((a) => a.read_at).length;
  if (!read) return "no salaries read yet: the next capture reads them";
  const c = t.counts;
  const head = c.flagged
    ? `${plural(c.flagged, "position", "positions")} more than ${t.flag_pct}% off target in ${plural(c.airlines_flagged, "airline", "airlines")}`
    : `every position with staff within ${t.flag_pct}% of its target`;
  const tail = [c.no_average ? `${c.no_average} with no country average` : "", c.not_read ? `${plural(c.not_read, "airline", "airlines")} not read yet` : ""].filter(Boolean);
  return [head, ...tail].join(" · ");
}

/** Today's needs attention: one item when any position is flagged, "Salaries: 5 positions more than 1% off target in 3
 *  airlines", keyed by the flagged positions themselves so a new one shows again after a dismissal; null when none. */
export function salaryAttention(t: SalaryTable | null | undefined): AttItem | null {
  if (!t) return null;
  const flagged = t.airlines.flatMap((a) => a.rows.filter((r) => r.flag === "under" || r.flag === "over").map((r) => `${a.code ?? a.airline_id}:${r.position}:${r.flag}`));
  if (!flagged.length) return null;
  const airlines = new Set(flagged.map((k) => k.split(":")[0])).size;
  return {
    key: "salary|" + [...flagged].sort().join(","), cls: "warn", screen: "systems",
    text: `Salaries: ${plural(flagged.length, "position", "positions")} more than ${t.flag_pct}% off target in ${plural(airlines, "airline", "airlines")}`,
  };
}
