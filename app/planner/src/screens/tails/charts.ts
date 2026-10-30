// The Tails list as a chart (spec docs/specs/2026-10-30-charts-everywhere.md, part C): a bar per aircraft of its block
// hours a day against the 10- and 12-hour marks (aircraft_block_target_h, and 12), coloured by its maintenance (the
// figure the list shows: the game's where it has one, else the estimate), grouped by base in the list's order. The
// figures are the list's (tailRows), unchanged; the table stays one tap away.
import { TONE, type HBarItem } from "../../ui/charts";
import { shownPill, type TailRow } from "./model";

/** The colour of a maintenance class, and grey with no figure. */
const MAINT_COLOR = { ok: TONE.ok, warn: TONE.warn, bad: TONE.bad } as const;

/** The bars, a group per base (in the order the bases first come in the list; "no base" for an aircraft without one). */
export function blockBars(rows: readonly TailRow[]): { base: string; items: HBarItem[] }[] {
  const groups = new Map<string, HBarItem[]>();
  for (const r of rows) {
    const base = r.base || "no base";
    const p = shownPill(r.maint);
    const item: HBarItem = {
      key: r.a.registration, label: r.a.registration, value: r.fig.blockDay, text: r.fig.blockDay.toFixed(1), color: p ? MAINT_COLOR[p.cls] : TONE.mute,
      tip: `${r.a.registration} · ${r.type}${r.config ? " " + r.config : ""} · ${r.fig.blockDay.toFixed(1)} h a day · ${r.fig.legsWk} legs a week · maintenance ${p ? p.text : "no figure"}`,
    };
    const g = groups.get(base);
    if (g) g.push(item); else groups.set(base, [item]);
  }
  return [...groups.entries()].map(([base, items]) => ({ base, items }));
}
/** The marks: the airline's target (aircraft_block_target_h) and 12 hours; the target alone when it is 12. */
export function blockMarks(target: number): { value: number; label: string }[] {
  return target === 12 ? [{ value: 12, label: "12 h" }] : [{ value: target, label: `${target} h target` }, { value: 12, label: "12 h" }];
}
