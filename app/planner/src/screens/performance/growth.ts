// Performance → Growth signals and Main hubs towards 750 (moved from Check → Growth on 20 Oct; decision #18, build pull
// request 9): how the boards word the database's figures (growth_signals(), hub_progress()) and the planning library's
// hub readiness, as the old growthBoard and hubProgressHtml did. The order rotation's next move went with it (spec
// decision 2: route first, then airline, manual §3). No screen code, so the unit tests run it.
import { time, type ReadinessRow } from "@rules";
import type { HubProgressAirline } from "./reads";

export interface HubRow { airline_id: number; name: string; hub: string; departures: number; planned: number; target: number; width: string; pend: string; pct: number }
/** Main hubs towards their weekly target: every airline with a main hub that isn't exempt, in the airlines' order. */
export function hubRows(progress: readonly HubProgressAirline[], name: (id: number) => string): HubRow[] {
  return progress.filter((x) => !x.exempt && x.main_hub).map((x) => {
    const dep = x.departures ?? 0, add = x.planned ?? 0, target = x.target || 1;
    const a = Math.min(100, dep / target * 100), b = Math.min(100 - a, add / target * 100);
    return { airline_id: x.airline_id, name: name(x.airline_id), hub: x.main_hub as string, departures: dep, planned: add, target: x.target, width: a.toFixed(1) + "%", pend: b.toFixed(1) + "%", pct: Math.round(dep / target * 100) };
  });
}

/** Hub readiness folded into each airline's line (spec: "Main hubs towards 750 … with Hub readiness folded into its
 *  line"): each airline's banks, in the library's order, and a short line of them ("DEL B1 06:00 12 cities (+3 planned)
 *  · B2 …"). Airlines with readiness but no main hub row keep theirs too, after the others. */
export function readinessOf(rows: readonly ReadinessRow[], airlineId: number): { rows: ReadinessRow[]; line: string } {
  const mine = rows.filter((r) => r.airline_id === airlineId);
  let last = "";
  const words = mine.map((r) => {
    const at = r.airport === last ? "" : r.airport + " ";
    last = r.airport;
    const more = r.with_planned - r.flying;
    return `${at}B${r.bank} ${H(r.dep)} ${r.flying} cit${r.flying === 1 ? "y" : "ies"}${more > 0 ? ` (+${more} planned)` : ""}`;
  });
  return { rows: mine, line: words.join(" · ") };
}

/** Money in thousands, as the old k(): "+120k", "−45k". */
export const kWords = (v: number): string => (v >= 0 ? "+" : "−") + Math.round(Math.abs(v) * 1000) + "k";
/** A week's profit in millions: "+1.20M". */
export const weekWords = (v: number): string => (v >= 0 ? "+" : "−") + Math.abs(v).toFixed(2) + "M";
export const pctWords = (v: number | null | undefined): string => (v == null ? "—" : Math.round(v) + "%");
/** Round trips a day as the old list writes them: "2×", "1.4×". */
export const perDayWords = (x: number): string => (x % 1 ? x.toFixed(1) : String(x)) + "×";
/** A bank's departure "HH:MM". */
export const H = (m: number): string => time.clock(m);
