// Systems' charts (spec docs/specs/2026-10-30-charts-everywhere.md, part C): the usage gauges against their triggers, and
// each airline's capture verdicts over the last 14 nights from capture_status() asked at several moments.
import { describe, expect, it } from "vitest";
import { usageGauges, verdictFill, verdictHistory, type CaptureAt } from "./charts";

describe("usage as gauges", () => {
  it("each figure's share of its trigger, amber from 70%, red at it, with its words", () => {
    const g = usageGauges([{ key: "db", label: "Database", bytes: 350 * 1048576, trigger_bytes: 500 * 1048576 },
      { key: "pdf", label: "Report PDFs", bytes: 100 * 1024, trigger_bytes: 1048576 }, { key: "site", label: "Website data", bytes: 2 * 1048576, trigger_bytes: 1048576 }]);
    expect(g.map((x) => [x.label, x.words, x.g.pct, x.g.tone])).toEqual([
      ["Database", "350.0 MB of 500.0 MB", 70, "warn"], ["Report PDFs", "100 KB of 1.0 MB", 10, "ok"], ["Website data", "2.0 MB of 1.0 MB", 200, "bad"]]);
  });
});

describe("the capture's last 14 nights", () => {
  const at = (id: number, verdict: string | null, day: string | null, words: string | null = null): CaptureAt => ({ airline_id: id, code: id === 1 ? "PA" : "KF", name: null, verdict, verdict_words: words, verdict_day: day });
  it("14 nights ending today, each airline's newest answer for a day winning, a night with none empty", () => {
    const h = verdictHistory([
      [at(1, "ok", "2026-10-30", "all good"), at(2, "short", "2026-10-29", "short: loads not captured")],
      [at(1, "broken", "2026-10-30", "broken: x"), at(2, "short", "2026-10-29", "short: earlier")],
      [at(1, null, "2026-10-28"), at(2, "ok", "2026-10-27", "all good")],
    ], "2026-10-30");
    expect([h.days[0], h.days[13], h.cols[13]]).toEqual(["2026-10-17", "2026-10-30", "30 Oct"]);
    expect(h.rows.map((r) => [r.label, r.cells.slice(10).map((c) => c?.value ?? null)])).toEqual([["PA", [null, 0, null, 3]], ["KF", [3, null, 2, null]]]);
    expect(h.rows[1]?.cells[12]?.tip).toBe("KF · 29 Oct: short: loads not captured");
    expect(h.rows[0]?.cells[11]?.tip).toBe("PA · 28 Oct: captured before the page checks");
    expect(h.rows[0]?.cells[12]?.tip).toBe("PA · 29 Oct: no capture");
  });
  it("ends on a later capture day when an answer has one; the colours", () => {
    expect(verdictHistory([[at(1, "ok", "2026-10-31")]], "2026-10-30").days[13]).toBe("2026-10-31");
    expect([3, 2, 1, 0, null].map(verdictFill)).toEqual(["#1A7F55", "#E39B21", "#B4234B", "#9AA4C4", "#ECEFF4"]);
  });
});
