// Systems' charts (spec docs/specs/2026-10-30-charts-everywhere.md, part C): the database's usage figures (database
// size, report PDFs, the website's data: system_status()'s usage) as gauges against their triggers, and each airline's
// capture verdicts over the last 14 nights as a small history (capture_status() asked as of each of those nights). The
// figures are the board's, unchanged: the tiles and the capture table stay.
import { gaugeLayout, type GaugeLayout, type HeatRow } from "../../ui/charts";
import { USAGE_WARN_SHARE, sizeWords, type SystemStatus } from "./systems";

/** Each usage figure as a gauge: its share of its trigger, amber from 70% (the board's usageMark), red at it. */
export function usageGauges(usage: SystemStatus["usage"]): { key: string; label: string; words: string; g: GaugeLayout }[] {
  return usage.map((u) => {
    const bytes = Number(u.bytes), trigger = Number(u.trigger_bytes);
    return { key: u.key, label: u.label, words: `${sizeWords(bytes)} of ${sizeWords(trigger)}`, g: gaugeLayout(bytes, trigger, USAGE_WARN_SHARE, 120) };
  });
}

/** An airline in one capture_status() answer: its latest capture's verdict and the capture day it belongs to. */
export interface CaptureAt { airline_id: number; code: string | null; name: string | null; verdict: string | null; verdict_words: string | null; verdict_day: string | null }
/** A night's verdict as a number for the history's colour: all good 3, short 2, broken 1, captured but not checked 0;
 *  null for no capture that night. */
export const VERDICT_VALUE: Record<string, number> = { ok: 3, short: 2, broken: 1 };
const DAY_MS = 86_400_000;
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** The last 14 nights, oldest first, ending on `today` (a UTC date; or a later capture day an answer has), and each airline's verdict on each: from
 *  capture_status() asked at several moments (newest first), the newest answer for a capture day wins (it saw that day's
 *  last pages); a night none of the answers has a capture for is empty. Airlines in the newest answer's order. */
export function verdictHistory(answers: readonly (readonly CaptureAt[])[], today: string): { rows: HeatRow[]; cols: string[]; days: string[] } {
  // the last night is today's, or a later capture day when the database's capture day runs ahead of UTC
  const latest = answers.flat().map((a) => a.verdict_day ?? "").reduce((m, d) => (d > m ? d : m), today);
  const end = Date.parse(latest + "T00:00:00Z");
  const days = Array.from({ length: 14 }, (_, i) => new Date(end - (13 - i) * DAY_MS).toISOString().slice(0, 10));
  const order: number[] = [];
  const names = new Map<number, string>();
  const seen = new Map<number, Map<string, { verdict: string | null; words: string | null }>>();
  for (const ans of answers) {
    for (const a of ans) {
      if (!names.has(a.airline_id)) { order.push(a.airline_id); names.set(a.airline_id, a.code ?? a.name ?? String(a.airline_id)); }
      if (!a.verdict_day) continue;
      const m = seen.get(a.airline_id) ?? new Map();
      if (!m.has(a.verdict_day)) m.set(a.verdict_day, { verdict: a.verdict, words: a.verdict_words });
      seen.set(a.airline_id, m);
    }
  }
  const dayWords = (d: string) => `${Number(d.slice(8, 10))} ${MONTHS[Number(d.slice(5, 7)) - 1]}`;
  return {
    days,
    cols: days.map((d) => dayWords(d)),
    rows: order.map((id) => ({
      key: String(id), label: names.get(id) as string,
      cells: days.map((d) => {
        const v = seen.get(id)?.get(d);
        if (!v) return { value: null, tip: `${names.get(id)} · ${dayWords(d)}: no capture` };
        return { value: v.verdict ? VERDICT_VALUE[v.verdict] ?? 0 : 0, tip: `${names.get(id)} · ${dayWords(d)}: ${v.verdict ? v.words ?? v.verdict : "captured before the page checks"}` };
      }),
    })),
  };
}
/** A night's colour: all good green, short amber, broken red, not checked grey; no capture a pale cell. */
export function verdictFill(v: number | null): string {
  return v == null ? "#ECEFF4" : v >= 3 ? "#1A7F55" : v >= 2 ? "#E39B21" : v >= 1 ? "#B4234B" : "#9AA4C4";
}
