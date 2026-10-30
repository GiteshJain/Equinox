// The chart kit's layouts (spec docs/specs/2026-10-30-charts-everywhere.md, "Common to all three"): each places what it's
// given, in order, on its scale, with its tips; nothing is worked out but positions. And "show as table" renders the
// chart or the table, with its switch.
import { createElement } from "react";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";
import {
  ChartFrame, ChartOrTable, donutLayout, gaugeLayout, hbarLayout, heatLayout, loadFill, niceCeil, sizedScatterLayout, sparkLayout, stackLayout, stepLayout, ticks, timelineLayout,
  fitText,
} from "./index";

describe("the scale", () => {
  it("rounds up to a nice number and ticks on its step", () => {
    expect([niceCeil(0), niceCeil(0.7), niceCeil(3), niceCeil(23), niceCeil(140)]).toEqual([1, 1, 5, 25, 200]);
    expect(ticks(0, 100, 4)).toEqual([0, 25, 50, 75, 100]);
    expect(ticks(-0.2, 1, 4)).toEqual([0, 0.5, 1]);
  });
});

describe("horizontal bars", () => {
  it("one row each in order, from zero, negatives to the left, the reference line across", () => {
    const g = hbarLayout([{ key: "a", label: "A", value: 10, tip: "a" }, { key: "b", label: "B", value: -5, color: "#f00", tip: "b" }],
      { fmt: (v) => String(v), ref: { value: 5, label: "mid" }, W: 300, L: 50, row: 20 });
    // a line over the bars for the reference line's label (16), and 46 px left of the bars for a losing bar's value
    expect(g.H).toBe(16 + 2 * 20 + 22);
    expect(g.bars.map((b) => [b.key, b.y, b.neg, b.text])).toEqual([["a", 19, false, "10"], ["b", 39, true, "-5"]]);
    // 300 wide, bars from 50 + 46 = 96, 52 right: −5 to 10 over 152 px; zero at 96 + 5/15 × 152 = 146.7
    expect(g.zeroX).toBe(146.7);
    expect(g.bars[0]).toMatchObject({ x: 146.7, w: 101.3, color: "#4B3BA8" });
    expect(g.bars[1]).toMatchObject({ x: 96, w: 50.7, color: "#f00", textX: 92 });
    expect(g.ref).toEqual({ x: 197.3, label: "mid" });
    // with no losing bar and no reference line, the bars start at the labels' edge, the rows at the top
    const h = hbarLayout([{ key: "a", label: "A", value: 10, tip: "a" }], { fmt: String, W: 300, L: 50 });
    expect([h.T, h.zeroX]).toEqual([6, 50]);
  });
});

describe("stacked bars", () => {
  it("each row's parts end to end in the series' order on one scale, its total at its end; a part of 0 has no segment", () => {
    const series = [{ key: "x", label: "X", color: "#1" }, { key: "y", label: "Y", color: "#2" }];
    const g = stackLayout([{ key: "r1", label: "One", parts: { x: 2, y: 2 } }, { key: "r2", label: "Two", parts: { y: 1 } }], series, { W: 210, L: 10, row: 20 });
    // the largest total, 4, over 210 − 10 − 34 = 166 px: 41.5 a unit
    expect(g.max).toBe(4);
    expect(g.rows[0]?.segs.map((s) => [s.key, s.x, s.w, s.tip])).toEqual([["x", 10, 83, "One · X 2"], ["y", 93, 83, "One · Y 2"]]);
    expect(g.rows[1]?.segs.map((s) => [s.key, s.x, s.w])).toEqual([["y", 10, 41.5]]);
    expect(g.rows.map((r) => r.total)).toEqual([4, 1]);
  });
});

describe("a donut", () => {
  it("each part's share of the whole, parts of 0 left out", () => {
    const g = donutLayout([{ key: "a", label: "Ours", value: 30, color: "#1" }, { key: "b", label: "KLM", value: 70, color: "#2" }, { key: "c", label: "none", value: 0, color: "#3" }]);
    expect(g.total).toBe(100);
    expect(g.arcs.map((a) => [a.key, a.pct, a.tip])).toEqual([["a", 30, "Ours 30 (30%)"], ["b", 70, "KLM 70 (70%)"]]);
    expect(g.arcs[0]?.d.startsWith("M70,0 A70,70 0 0 1")).toBe(true);
    expect(g.arcs[1]?.d).toContain(" 0 1 1 ");
  });
});

describe("a step line", () => {
  it("holds each value level to the next point, then steps; the cushion across, each marker at its value, the lowest point bad under the cushion", () => {
    const g = stepLayout([{ t: 0, v: 4 }, { t: 50, v: 2 }], { t0: 0, t1: 100, fmt: (v) => `${v}M`, refs: [{ value: 3, label: "cushion" }],
      markers: [{ t: 50, v: 2, tip: "lease" }], low: { t: 50, v: 2 }, W: 200, H: 120 });
    expect(g).not.toBeNull();
    // x: 52 to 182 over 0..100; y: 14 to 94 over hi 4.32..0
    expect(g?.path).toBe("M52,19.9 L117,19.9 L117,57 L182,57");
    expect(g?.markers).toEqual([{ x: 117, y: 57, tip: "lease", cls: "" }]);
    expect(g?.low).toEqual({ x: 117, y: 57, label: "lowest 2M", bad: true });
    expect(g?.refs[0]?.y).toBe(38.4);
    expect(stepLayout([], { t0: 0, t1: 1, fmt: String })).toBeNull();
  });
});

describe("a timeline", () => {
  it("each row's marks at their moments, clamped to the edges, a line from first to last", () => {
    const g = timelineLayout([{ key: "a", label: "A", marks: [{ t: 0, kind: "planned", tip: "p" }, { t: 10, kind: "seen", tip: "s" }] }, { key: "b", label: "B", marks: [{ t: 20, kind: "planned", tip: "late" }] }],
      { t0: 0, t1: 10, W: 124, L: 10, now: 5 });
    expect(g.rows[0]?.marks.map((m) => m.x)).toEqual([10, 110]);
    expect(g.rows[0]?.span).toEqual({ x0: 10, x1: 110 });
    expect(g.rows[1]?.marks[0]?.x).toBe(110);
    expect(g.rows[1]?.span).toBeNull();
    expect(g.now).toBe(60);
  });
});

describe("a scatter, a gauge, a heat strip and a spark", () => {
  it("sizes points by area, larger first", () => {
    const g = sizedScatterLayout([{ key: "a", x: 1, y: 1, size: 1, color: "#1", tip: "a" }, { key: "b", x: 2, y: 2, size: 4, color: "#2", tip: "b", ring: true }]);
    expect(g.points.map((p) => [p.key, p.r, p.ring])).toEqual([["b", 14, true], ["a", 8.5, false]]);
  });
  it("a gauge's share of its trigger, amber from 70%, red at the trigger", () => {
    expect([gaugeLayout(10, 100).tone, gaugeLayout(70, 100).tone, gaugeLayout(103, 100).tone, gaugeLayout(103, 100).pct]).toEqual(["ok", "warn", "bad", 103]);
    expect(gaugeLayout(0, 100).arc).toBe("");
  });
  it("a heat strip's cells coloured as loads are marked, grey with no figure, nothing for an empty hour", () => {
    expect([loadFill(98), loadFill(90), loadFill(75), loadFill(50), loadFill(null)]).toEqual(["#1E9E6A", "#E3B341", "#E3812B", "#B4234B", "#D9DDE7"]);
    const g = heatLayout([{ key: "PA", label: "PA", cells: [{ value: 96, tip: "t" }, null, { value: null, tip: "n" }] }], ["00", "01", "02"], { W: 130, L: 40 });
    expect(g.rows[0]?.cells.map((c) => [c.x, c.fill, c.empty])).toEqual([[40, "#1E9E6A", false], [70, "none", true], [100, "#D9DDE7", false]]);
  });
  it("a spark breaks its line at a null and draws bars from zero", () => {
    expect(sparkLayout([1, null, 3], "line", { W: 66, H: 26 }).path).toBe("M13,23 M53,3");
    expect(sparkLayout([2, -1], "bar", { W: 66, H: 36 }).bars.map((b) => b.neg)).toEqual([false, true]);
    expect(sparkLayout([null], "line").path).toBeNull();
  });
});

describe("the frame and show as table", () => {
  it("says the empty state in words, and a legend only with more than one series", () => {
    const empty = renderToString(createElement(ChartFrame, { title: "T", note: "n", empty: "Nothing yet." }, createElement("svg")));
    expect(empty).toContain("Nothing yet.");
    expect(empty).not.toContain("<svg");
    expect(renderToString(createElement(ChartFrame, { title: "T", legend: [{ label: "a", color: "#1" }] }))).not.toContain("kcl");
    expect(renderToString(createElement(ChartFrame, { title: "T", legend: [{ label: "a", color: "#1" }, { label: "b", color: "#2" }] }))).toContain("kcl");
  });
  it("shows the chart with \"show as table\", the table not rendered until asked", () => {
    const html = renderToString(createElement(ChartOrTable, { k: "test", chart: createElement("i", { id: "c" }), table: createElement("table", { id: "t" }) }));
    expect(html).toContain('id="c"');
    expect(html).not.toContain('id="t"');
    expect(html).toContain("show as table");
    expect(html).toContain('data-table-toggle="test"');
  });
});

describe("labels kept to their room (part B)", () => {
  it("a row label longer than its column is cut with an ellipsis, a short one kept", () => {
    // 100 px at 6.4 px a character: 15 characters, the last the ellipsis
    expect(fitText("Lufthansa Cargo International", 100)).toBe("Lufthansa Carg…");
    expect(fitText("ANA", 100)).toBe("ANA");
  });
  it("a bar's own words replace its value where given", () => {
    const g = hbarLayout([{ key: "a", label: "A", value: 10, tip: "a", text: "12 on order, no flights yet" }, { key: "b", label: "B", value: 5, tip: "b" }], { fmt: (v) => `${v}%`, W: 400, R: 150 });
    expect(g.bars.map((b) => b.text)).toEqual(["12 on order, no flights yet", "5%"]);
    expect(g.R).toBe(150);
  });
});
