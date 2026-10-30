// Competition's charts (spec docs/specs/2026-10-30-charts-everywhere.md, part B; charts.ts): each chart's figures are
// competition()'s, in order, coloured and with their tips, on small answers made the way competition.test.ts makes them.
import { createElement } from "react";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { SERIES, TONE, donutLayout, hbarLayout, sizedScatterLayout, timelineLayout } from "../../ui/charts";
import { FLEET_SERIES, OURS, fleetRows, marketDonut, openingPoints, orderBookBars, threatTimeline, variantFamily } from "./charts";
import { MarketDonut, OrderBooksChart } from "./CompCharts";
import type { Fleet, Market, Opening, OrderFlag, Threat } from "./model";

const market = (x: Partial<Market> = {}): Market => ({
  market_id: 1, name: "China domestic", pairs: 12, flown: 5, ours: 40, ours_before: 30, ours_change: 10, rivals: 160, rivals_before: 150, rivals_change: 10,
  total: 200, share: 20, share_before: 16.7, share_change: 3.3,
  top: [{ airline_id: 9, name: "Air China", weekly: 100, weekly_before: 90, change: 10, share: 50 }, { airline_id: 8, name: "ANA", weekly: 40, weekly_before: 40, change: 0, share: 20 }],
  ...x,
});
const threat = (x: Partial<Threat> = {}): Threat => ({
  rival_id: 900, rival: "Air China", pair: "CAN-PVG", route: "PVG–CAN", hub: "PVG", dest: "CAN", kind: "started", then: 0, added: 14, now: 14, ours: 21,
  scan_id: 2, on: "2026-10-17T19:00:00.000Z", previous_id: 1, previous_on: "2026-10-06T21:00:00.000Z", until: "2026-10-24T19:00:00.000Z", latest: true,
  words: "Air China started on PVG–CAN, 14 a week", ...x,
});
const opening = (x: Partial<Opening> = {}): Opening => ({
  rank: 1, route_id: 5, route: "PVG–CTU", hub: "PVG", dest: "CTU", pair: "CTU-PVG", city: "Chengdu", stars: 5, distance_km: 1690, market_id: 1,
  rivals_weekly: 63, rivals: [], variant: { type_id: 3, type: "A320neo SHARP", seats: 189, range_km: 3355, size: "mid", for_reach: false },
  allowed: true, allowed_by: "main hub", reason: null, ...x,
});
const flag = (x: Partial<OrderFlag & { meets_codes: string[] }> = {}): OrderFlag & { meets_codes: string[] } => ({
  airline_id: 1, name: "Rival One", kind: "orders", fleet: 99, on_order: 44, share: 44.4, weekly: 500, on_order_change: 6, fleet_change: 0,
  on_pairs: true, at_bases: false, meets: true, words: "44 on order, 44.4% of 99 aircraft", meets_codes: ["MU"], ...x,
});
const day = (iso: string) => Date.parse(iso + "T00:00:00Z");

describe("Market share: a donut per market", () => {
  it("ours in the airline's colour, each top rival, then the other rivals, as shareBar orders them", () => {
    const d = marketDonut(market(), "#C8102E");
    expect(d.map((p) => [p.key, p.label, p.value, p.pct, p.color])).toEqual([
      ["ours", "ours", 40, 20, "#C8102E"], ["r1", "Air China", 100, 50, SERIES[1]], ["r2", "ANA", 40, 20, SERIES[2]], ["others", "others", 20, 10, "#C9CEDB"]]);
    expect(marketDonut(market())[0]?.color).toBe(OURS);
    const g = donutLayout(d, { size: 120, ring: 20 });
    expect(g.arcs.map((a) => a.pct)).toEqual([20, 50, 20, 10]);
  });
  it("no donut for a market with no departures; the card's donut has our share in the middle", () => {
    expect(marketDonut(market({ total: 0 }))).toEqual([]);
    const html = renderToString(createElement(MarketDonut, { m: market() }));
    expect(html).toContain("20.0%");
    expect(html).toContain("Air China 100 a week (50%)");
    expect(renderToString(createElement(MarketDonut, { m: market({ total: 0 }) }))).toBe("");
  });
});

describe("Threats: a timeline by scan day", () => {
  const items = [threat(), threat({ rival_id: 8, rival: "ANA", kind: "added", on: "2026-10-10T19:00:00.000Z", route: "PVG–PEK", hub: "PVG", dest: "PEK", words: "ANA added 7 on PVG–PEK" }),
    threat({ route: "PVG–SZX", dest: "SZX", on: "2026-10-10T19:00:00.000Z", words: "Air China started on PVG–SZX" })];
  it("a row per rival in the order they come, each threat a mark on its day linking to its route page", () => {
    const t = threatTimeline(items, "rival", (x) => `/performance/MU/${x.hub}-${x.dest}`);
    expect(t?.rows.map((r) => [r.label, r.marks.map((m) => [m.t, m.kind, m.href])])).toEqual([
      ["Air China", [[day("2026-10-17"), "started", "/performance/MU/PVG-CAN"], [day("2026-10-10"), "started", "/performance/MU/PVG-SZX"]]],
      ["ANA", [[day("2026-10-10"), "added", "/performance/MU/PVG-PEK"]]]]);
    expect(t?.rows[1]?.marks[0]?.tip).toBe("10 Oct · ANA added 7 on PVG–PEK");
    expect(t?.ticks.map((x) => x.label)).toEqual(["10 Oct", "17 Oct"]);
    expect([t?.t0, t?.t1]).toEqual([day("2026-10-09"), day("2026-10-18")]);
    // up to today when it's later; the layout keeps each mark's link
    expect(threatTimeline(items, "rival", () => null, "2026-10-21")?.t1).toBe(day("2026-10-22"));
    const g = timelineLayout(t!.rows, { t0: t!.t0, t1: t!.t1, W: 560, L: 140 });
    expect(g.rows[0]?.marks.map((m) => m.href)).toEqual(["/performance/MU/PVG-CAN", "/performance/MU/PVG-SZX"]);
  });
  it("by our airline on the group page, its code in the tip; none without threats", () => {
    const t = threatTimeline(items.map((x, i) => ({ ...x, al: { code: i ? "PA" : "MU", name: "" } })), "airline", () => null);
    expect(t?.rows.map((r) => [r.label, r.marks.length])).toEqual([["MU", 1], ["PA", 2]]);
    expect(t?.rows[0]?.marks[0]?.tip).toBe("17 Oct · MU · Air China started on PVG–CAN, 14 a week");
    expect(threatTimeline([], "rival", () => null)).toBeNull();
  });
});

describe("Openings: stars against rivals", () => {
  it("a variant's family is its type up to the model number", () => {
    expect(["A320neo SHARP", "737-9 HGW", "E195-E2", "A350-900", null, "Dash 8"].map(variantFamily)).toEqual(["A320", "737", "E195", "A350", "other", "other"]);
  });
  it("x the rivals a week, y the stars nudged by rank, size the distance, the five commonest families coloured, hubs first ringed", () => {
    const os = [opening(), opening({ rank: 2, route_id: 6, route: "PVG–XIY", stars: 4, rivals_weekly: 10, distance_km: 1300, allowed: false, reason: "main hub under 750",
      variant: { type_id: 4, type: "737-9 HGW", seats: 190, range_km: 3500, size: "mid", for_reach: false } }), opening({ rank: 3, route_id: 7, variant: { type_id: null, type: null, seats: null, range_km: null, size: null, for_reach: false } })];
    const o = openingPoints(os);
    expect(o.families).toEqual([{ label: "737", color: SERIES[0] }, { label: "A320", color: SERIES[1] }, { label: "other", color: "#9AA4C4" }]);
    expect(o.points.map((p) => [p.x, p.y, p.size, p.color, p.ring])).toEqual([
      [63, 5 - 0.06, 1690, SERIES[1], true], [10, 4, 1300, SERIES[0], false], [63, 5 + 0.06, 1690, "#9AA4C4", true]]);
    expect(o.points[1]?.tip).toBe("#2 PVG–XIY · 4★ · 1,300 km · rivals 10 a week · 737-9 HGW · not yet: main hub under 750");
    const g = sizedScatterLayout(o.points, { W: 560, y: { lo: 0.5, hi: 5.5, ticks: [1, 2, 3, 4, 5] } });
    expect(g.points.filter((p) => p.ring).length).toBe(2);
    // the stars' own scale: 1 to 5, a tick each, 12 to 230 px down
    expect(g.yTicks.map((t) => t.y)).toEqual([208.2, 164.6, 121, 77.4, 33.8]);
  });
});

describe("Rival profiles: fleet and orders by type", () => {
  it("a bar per type of its fleet, then on order", () => {
    const f: Fleet = { overall: 99, on_order: 44, avg_age_years: 5, types_count: 7, overall_before: 99, on_order_before: 38, overall_change: 0, on_order_change: 6,
      types: [{ type: "A321XLR", overall: 23, on_order: 10, avg_age_years: 1 }, { type: "737-9 HGW", overall: 23, on_order: null, avg_age_years: 3 }] };
    const rows = fleetRows(f);
    expect(rows.map((r) => [r.label, r.parts])).toEqual([["A321XLR", { fleet: 23, order: 10 }], ["737-9 HGW", { fleet: 23, order: 0 }]]);
    expect(rows[0]?.tip?.(FLEET_SERIES[1]!, 10)).toBe("A321XLR: 10 on order");
    expect(fleetRows(null)).toEqual([]);
  });
});

describe("Order books: orders against fleet, the flag drawn", () => {
  it("each rival's share of its fleet on order, red when it meets us, a starting rival drawn full and said so; the flag as the line", () => {
    const b = orderBookBars([flag(), flag({ airline_id: 2, name: "New Air", kind: "starting", fleet: null, on_order: 12, share: null, meets: false, meets_codes: [] })], 25);
    expect(b.ref).toEqual({ value: 25, label: "flag 25%" });
    expect(b.items.map((x) => [x.label, x.value, x.text, x.color])).toEqual([
      ["Rival One", 44.4, "44.4% · 44 of 99", TONE.bad], ["New Air", 44.4, "12 on order, no flights yet", TONE.mute]]);
    expect(b.items[1]?.tip).toBe("New Air: 44 on order, 44.4% of 99 aircraft · meets none of our airlines");
    expect(orderBookBars([flag()], 25, true).items[0]?.text).toBe("44.4%");
    const g = hbarLayout(b.items, { fmt: (v) => `${Math.round(v)}%`, ref: b.ref, W: 560, L: 150, R: 150 });
    expect(g.bars.map((x) => x.text)).toEqual(["44.4% · 44 of 99", "12 on order, no flights yet"]);
    expect(g.ref?.x).toBeLessThan(g.bars[0]!.x + g.bars[0]!.w);
  });
  it("the chart, with the flag's line", () => {
    const html = renderToString(createElement(OrderBooksChart, { books: [flag()], flagPct: 25 }));
    expect(html).toContain("flag 25%");
    expect(html).toContain('data-figure="competition: order books bars"');
    expect(renderToString(createElement(OrderBooksChart, { books: [], flagPct: 25 }))).toContain("No rival has a big order book");
  });
});
