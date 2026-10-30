// The Tails list as bars (spec docs/specs/2026-10-30-charts-everywhere.md, part C): block hours a day per aircraft, coloured
// by the maintenance the list shows, grouped by base in the list's order; the 10- and 12-hour marks.
import { describe, expect, it } from "vitest";
import { TONE } from "../../ui/charts";
import { blockBars, blockMarks } from "./charts";
import type { ShownMaint, TailRow } from "./model";

const maint = (level: ShownMaint["level"], pct: number): ShownMaint => ({ from: "game", pct, level, min_pct: 75, target_pct: 90, title: "" });
const row = (reg: string, base: string, blockDay: number, m: ShownMaint | null): TailRow =>
  ({ a: { registration: reg }, type: "A320neo", config: "Y180", base, fig: { blockDay, legsWk: 28 }, maint: m }) as unknown as TailRow;

describe("block hours a day by base", () => {
  it("a bar per aircraft in the list's order, grouped by base as they first come, coloured by maintenance, with its tip", () => {
    const g = blockBars([row("N1", "JFK", 11.24, maint("ok", 120)), row("N2", "MIA", 9, maint("bad", 60)), row("N3", "JFK", 12.5, null), row("N4", "", 0, maint("warn", 80))]);
    expect(g.map((x) => [x.base, x.items.map((i) => [i.label, i.value, i.text, i.color])])).toEqual([
      ["JFK", [["N1", 11.24, "11.2", TONE.ok], ["N3", 12.5, "12.5", TONE.mute]]], ["MIA", [["N2", 9, "9.0", TONE.bad]]], ["no base", [["N4", 0, "0.0", TONE.warn]]]]);
    expect(g[0]?.items[0]?.tip).toBe("N1 · A320neo Y180 · 11.2 h a day · 28 legs a week · maintenance 120%");
    expect(g[0]?.items[1]?.tip).toContain("maintenance no figure");
  });
  it("the airline's target and 12 hours (the target alone when it is 12)", () => {
    expect(blockMarks(10)).toEqual([{ value: 10, label: "10 h target" }, { value: 12, label: "12 h" }]);
    expect(blockMarks(12)).toEqual([{ value: 12, label: "12 h" }]);
  });
});
