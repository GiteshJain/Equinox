// Performance's charts (spec docs/specs/2026-10-30-charts-everywhere.md, part A; charts.ts): each chart's figures are the
// screen's own, in order, coloured and with their tips. On small samples made the way performance.test.ts makes them.
import { readFileSync } from "node:fs";
import { createElement } from "react";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { buildRules, loadReport, type DayFlight, type RulesInput } from "@rules";
import { hbarLayout, stackLayout, timelineLayout } from "../../ui/charts";
import { GROWTH_SERIES, WEEK_SERIES, flightsHeat, forecastSteps, growthList, growthStack, kHour, ladderWeek, planTimeline, routeHourBars, scoreMultiples, weekKind } from "./charts";
import { CashSteps, RouteHourChart } from "./PerfCharts";
import { MARKS, type Forecast, type LadderRoute, type PlanRow, type ProfitDay, type RouteRow } from "./model";
import type { CapturedLoad, GrowthRead } from "./reads";

const route = (hub: string, dest: string, x: Partial<RouteRow> = {}): RouteRow => ({
  route_id: 1, hub, dest, flights: 7, margin: 0.3, profit_per_flight: 0.02, flights_week: 14, profit_week: 0.28, economy: 90, business: 60, cargo: 40, economy_fare: 300,
  sold_out: 5, with_loads: 7, mark: "hold", why: "", ...x,
});

describe("Route profit: profit an aircraft hour by route", () => {
  const rs = [route("HUB", "AAA", { mark: "add", profit_per_aircraft_hour: 0.012 }), route("HUB", "BBB", { mark: "raise", profit_per_aircraft_hour: 0.004 }),
    route("HUB", "CCC", { mark: "losing", profit_per_aircraft_hour: -0.002, profit_per_flight: -0.01 }), route("FOC", "AAA", { mark: "hold", profit_per_aircraft_hour: null })];
  it("highest first, each its mark's colour, the middle route as route_profit() picks it, the routes with no hours counted", () => {
    const b = routeHourBars(rs);
    expect(b.items.map((x) => [x.label, x.value, x.color])).toEqual([["HUB–AAA", 0.012, MARKS.add.color], ["HUB–BBB", 0.004, MARKS.raise.color], ["HUB–CCC", -0.002, MARKS.losing.color]]);
    // sorted −0.002, 0.004, 0.012: the middle is the second
    expect(b.ref).toEqual({ value: 0.004, label: "middle route +4.0k" });
    expect(b.without).toBe(1);
    expect(b.items[2]?.tip).toBe("HUB–CCC · −2.0k an aircraft hour · losing money · 7 flights, −10.0k a flight");
  });
  it("the mark picked filters the bars, never the middle route; the layout puts the losing route left of zero", () => {
    expect(routeHourBars(rs, "add").items.map((x) => x.label)).toEqual(["HUB–AAA"]);
    expect(routeHourBars(rs, "add").ref?.value).toBe(0.004);
    const g = hbarLayout(routeHourBars(rs).items, { fmt: kHour, ref: routeHourBars(rs).ref });
    expect(g.bars.map((x) => [x.text, x.neg])).toEqual([["+12.0k", false], ["+4.0k", false], ["−2.0k", true]]);
    expect(g.ref?.x).toBeGreaterThan(g.zeroX);
  });
  it("says so with no route with hours", () => {
    expect(renderToString(createElement(RouteHourChart, { routes: [route("A", "B")], mark: "" }))).toContain("No route has aircraft hours in the period yet");
  });
});

describe("Cash, next 14 days: a step line", () => {
  const fc: Forecast = {
    status: "ok", cash: 3, cash_at: "2026-10-30T04:00:00.000Z",
    points: [{ at: "2026-10-30T04:00:00.000Z", balance: 3 }, { at: "2026-10-31T12:00:00.000Z", balance: 2.4 }, { at: "2026-11-01T00:00:00.000Z", balance: 0.3 }],
    payments: [{ at: "2026-10-31T12:00:00.000Z", amount: 0.6, what: "Leasing payment for N001AW", repeat: false },
      { at: "2026-11-01T00:00:00.000Z", amount: 2.1, what: "Week-end closing", repeat: false }, { at: "2026-12-01T00:00:00.000Z", amount: 1, what: "x", repeat: true }],
    lowest: { at: "2026-11-01T00:00:00.000Z", balance: 0.3, payment: null },
  };
  it("the cushion as a line, each payment within the 14 days a dot at the cash after it, the lowest point", () => {
    const x = forecastSteps(fc, 0.5);
    expect(x?.refs).toEqual([{ value: 0.5, label: "cushion 0.5M", cls: "cushion" }]);
    expect(x?.markers.map((m) => [m.cls, m.v, m.tip])).toEqual([
      ["lease", 2.4, "Sat, Oct 31 · 0.60M · the lease for N001AW · 2.40M after it"], ["closing", 0.3, "Sun, Nov 1 · 2.10M · the week-end closing · 0.30M after it"]]);
    expect(x?.low).toEqual({ t: Date.parse("2026-11-01T00:00:00.000Z"), v: 0.3 });
    expect(x?.xTicks.length).toBe(8);
    const html = renderToString(createElement(CashSteps, { fc, cushion: 0.5 }));
    expect(html).toContain('data-markers="2"');
    expect(html).toContain("lowest 0.3M");
    expect(html).toContain("klow bad");
  });
  it("none for a forecast that isn't complete", () => {
    expect(forecastSteps({ status: "missing", missing: "a capture" }, 0.5)).toBeNull();
  });
});

const lr = (hub: string, dest: string, x: Partial<LadderRoute> = {}): LadderRoute => ({
  route_id: 1, hub, dest, direction: "out", from: hub, to: dest, cabin: "economy", departures: 14, sold_out: 14, sold_out_share: 100, load: 100,
  average_fare: 300, baseline_fare: 300, baseline_on: "2026-10-06", latest_fare: 300, latest_on: "2026-10-20", fare_index: 100, index_matches: true, level: 100, recorded: false,
  steps: 0, move: "up", new_level: 105, new_steps: 1, change_pct: 5, reason: "", contested: false, floor: 100, cap: 120, new_route: false, planned: false, plan_id: null,
  applied: false, seen_on: null, to_plan: true, ...x,
});

describe("the fare ladder's week", () => {
  it("one kind each: a decision first, then a set-back, a jump, else the move", () => {
    expect([weekKind({ move: "up" }), weekKind({ move: "hold", decide: true, fix: true }), weekKind({ move: "up", fix: true }), weekKind({ move: "down", ladder_kind: "jump" })])
      .toEqual(["up", "decide", "set back", "jump"]);
  });
  it("a bar per cabin and direction the ladder has, each kind counted", () => {
    const rows = ladderWeek([lr("A", "B"), lr("A", "C", { move: "hold" }), lr("A", "B", { direction: "back", move: "down" }), lr("A", "B", { cabin: "business", move: "hold", fix: true })]);
    expect(rows.map((r) => [r.label, r.parts])).toEqual([["economy out", { up: 1, hold: 1 }], ["economy back", { down: 1 }], ["business out", { "set back": 1 }]]);
    const g = stackLayout(rows, WEEK_SERIES);
    expect(g.rows[0]?.segs.map((s) => [s.key, s.tip])).toEqual([["up", "economy out · up: 1 direction"], ["hold", "economy out · hold: 1 direction"]]);
  });
});

describe("the fare plan's timeline", () => {
  const p = (id: number, x: Partial<PlanRow>): PlanRow => ({ id, legacy_key: null, route_id: 1, hub: "JFK", dest: "ORD", cabin_class: "economy", change_pct: 5, fare_from: 300,
    proposed_on: "2026-10-24", status: "planned", reason: null, updated_at: "", fare_now: null, target: null, applied: false, seen_on: null, economy_before: null, economy_after: null, ...x });
  it("planned, and seen once the captures show it, or waiting at today", () => {
    const t = planTimeline([p(1, { seen_on: "2026-10-26", level_pct: 105, ladder_move: "up", direction: "out" }), p(2, {})], "2026-10-30");
    expect(t.rows.map((r) => [r.label, r.marks.map((m) => m.kind)])).toEqual([["JFK–ORD economy out", ["planned", "seen"]], ["JFK–ORD economy", ["planned", "waiting"]]]);
    expect(t.rows[0]?.marks[0]?.tip).toBe("JFK–ORD economy out · up to 105% · planned Sat, Oct 24");
    const g = timelineLayout(t.rows, { t0: t.t0, t1: t.t1, now: t.now });
    expect(g.rows[1]?.marks[1]?.x).toBe(g.now);
  });
});

describe("the group's small multiples", () => {
  const pd = (date: string, profit: number): ProfitDay => ({ date, cash: 1, change: profit, order_payments: 0, days: 1, profit_day: profit, aircraft: 3, flights: 9, load: 90, per_aircraft_day: null } as ProfitDay);
  it("profit a day by report, load and fleet on each of the 14 days to today, a gap where the history has none", () => {
    const m = scoreMultiples([{ airline_id: 1, name: "Pan Am", color: "#123" }], new Map([[1, { days: [pd("2026-10-28", 0.1), pd("2026-10-29", -0.05)] }]]),
      [{ airline_id: 1, day: "2026-10-29", aircraft_total: 10, weekly_departures: 70, eco_load_pct: 88 }, { airline_id: 1, day: "2026-10-30", aircraft_total: 11, weekly_departures: 70, eco_load_pct: 91.5 }],
      "2026-10-30");
    expect(m[0]?.profit.values).toEqual([0.1, -0.05]);
    expect(m[0]?.load.values.slice(-3)).toEqual([null, 88, 91.5]);
    expect(m[0]?.fleet.values.length).toBe(14);
    expect(m[0]?.fleet.tip).toBe("Pan Am: fleet, 14 days · 10 → 11");
    expect(m[0]?.profit.tip).toBe("Pan Am: profit a day, last 2 reports · +0.10M → −0.05M");
  });
});

describe("growth signals by airline", () => {
  const sr = (airline_id: number) => ({ airline_id, route_id: 1, hub: "A", dest: "B", flights: 7, profit_per_flight: 0.01, profit_week: 0.1, economy: 90, economy_fare: 300, sold_out: 7, with_loads: 7, mark: "add", why: "" });
  const s: GrowthRead = { days: 7, profit_captured: true, ready_for_another_flight: [sr(1), sr(1)], raise_fares: [sr(2)], fix_or_reduce: [sr(1)],
    aircraft_losing_after_lease: [{ airline_id: 2, registration: "X", type: "t", net_day: -0.01, routes: [] }], load_patterns: [] };
  it("each airline's four lists counted, each segment naming the list it opens", () => {
    const rows = growthStack(s, [{ id: 1, name: "Pan Am" }, { id: 2, name: "Kingfisher" }]);
    expect(rows.map((r) => r.parts)).toEqual([{ ready: 2, raise: 0, fix: 1, losing: 0 }, { ready: 0, raise: 1, fix: 0, losing: 1 }]);
    expect(stackLayout(rows, GROWTH_SERIES).rows[0]?.segs[0]?.tip).toBe("Pan Am · ready for another flight: 2 · tap to open the list");
    expect([growthList("losing", true), growthList("fix", false), growthList("ready", false)]).toEqual(["losing", "reduce", "ready"]);
  });
  it("without profit captured: ready from the load reports, fix from the patterns marked cut", () => {
    const rows = growthStack({ ...s, profit_captured: false, load_patterns: [{ airline_id: 2, route_id: 1, hub: "A", dest: "B", departures: 7, full: 0, under_85: 5, under_70: 1, mark: "cut", why: "" }] },
      [{ id: 1, name: "Pan Am" }, { id: 2, name: "Kingfisher" }], [{ route: { airline_id: 1 } }]);
    expect(rows.map((r) => r.parts)).toEqual([{ ready: 1, fix: 0 }, { ready: 0, fix: 1 }]);
  });
});

describe("Flights by day: loads by hour", () => {
  const base = (JSON.parse(readFileSync(new URL("../../../../../lib/rules/cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
  const ALL = [1, 2, 3, 4, 5, 6, 7];
  const leg = (id: number, rot: number, n: 1 | 2, from: string, to: string, dep: number, no: number) => ({
    id, airline_id: 1, rotation_id: rot, leg_no: n, flight_no: no, origin_code: from, dest_code: to, aircraft_id: 1, days_utc: ALL, dep_utc_min: dep, block_min: 75 });
  const rules = buildRules({ ...base, rotations: [{ id: 1, airline_id: 1, route_id: 1 }], flight_legs: [leg(1, 1, 1, "HUB", "AAA", 360, 1001), leg(2, 1, 2, "AAA", "HUB", 510, 1002)] } as RulesInput);
  const flights: DayFlight[] = loadReport.flightsOn(rules, "2026-10-12", [{ id: 1, launched_on: "2026-10-01" }]);
  it("each airline's departures by local hour, its average economy load, grey when none was captured", () => {
    const loads = new Map<number, CapturedLoad>([[1001, { eco: 96 } as CapturedLoad]]);
    const h = flightsHeat(flights, (f) => loads.get(f.no), [{ id: 1, name: "Test Air", code: "TA" }, { id: 2, name: "Other", code: "OA" }]);
    expect(h.cols.length).toBe(24);
    expect(h.rows.map((r) => r.label)).toEqual(["TA"]);
    const cells = h.rows[0]?.cells ?? [];
    expect(cells.flatMap((c, i) => (c ? [[i, c.value]] : []))).toEqual([[6, 96], [9, null]]);
    expect(cells[6]?.tip).toBe("Test Air · 06:00–06:59 local · 1 departure (1001) · economy 96% over 1 captured");
    expect(cells[9]?.tip).toContain("not captured");
  });
});
