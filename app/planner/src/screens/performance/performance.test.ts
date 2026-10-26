// Performance's logic (spec docs/specs/2026-10-20-today-performance-systems.md; Review's tests until 20 Oct, spec
// docs/specs/2026-10-14-review.md, and Check's growth and load report tests, spec docs/specs/2026-10-13-check.md): the
// scorecards' wording when a figure is missing and their change against the same day last week (an airline with no day a
// week ago included), the profit chart's intervals (the last 14), the fare plan's words and its add and drop, the route
// profit's filters, the main hubs with their readiness folded in, Flights by day's day and summary (captured, typed by
// hand, not captured), and the plan card's service check as Tails shows it. Every money figure itself is the
// database's (database/tests/review_test.sql); these run the screen's words and saves. Manual entry's tests moved to
// Systems with its board (screens/systems/model.test.ts).
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildRules, loadReport, type DayFlight, type RulesInput } from "@rules";
import { cardLegs, cardServiceIssues, withRoutes, type PlanLegRow } from "../tails/model";
import type { RouteRow as TableRoute } from "../routes/model";
import { airlineDay, capLine, daySummary, loadKey, loadsByFlight, moveDay, parseDay, summaryWords } from "./flights";
import { hubRows, kWords, pctWords, perDayWords, readinessOf, weekWords as growthWeekWords } from "./growth";
import {
  BOARDS, BOARDS_FOLDED, GROUP_BOARDS, foldsFor, foldsOnArrival, SCATTER_CHAR_W, aircraftRowWords, cashRowWords, changesRowWords, groupTodayWords, growthWords, hubsWords, loadAxisFrom,
  planRowWords, profitAnswer, profitRowWords, routeRowWords, scatterLayout,
  CHART_INTERVALS, LADDER_SORTS, LIST_TOP, SPARK_DAYS, barLayout, barTip, capturedLine, cardWords, changesWords, chartIntervals, costParts, dd, farePlanAdd, farePlanDrop, fcDay,
  fcWhat, historyFrom, indexWords, kk, ladderLine, ladderPlanChanges, ladderRows, levelWords, listCut, loadSparkBars, loads14, loadsWords, markCounts, moveWords, nextOrderWords,
  decideWords, offLevelWords, offersFarePlan, underLaunchLine, planButton, planWords, plannedWords, safeWords, sg, shownRoutes, soldWords, sparkBars, sparkWords, splitActions, stepWords, weekOnWeek,
  type Card, type DayRow,
  type LadderAction, type LadderRoute, type PlanRow, type ProfitDay, type RouteDayRow, type RouteRow,
} from "./model";
import type { CapturedLoad, HandLoads } from "./reads";

// the planning library's small world (lib/rules/cases/_base.json), with the flights the load report lists
const base = (JSON.parse(readFileSync(new URL("../../../../../lib/rules/cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
const ALL = [1, 2, 3, 4, 5, 6, 7];
const leg = (id: number, rot: number, n: 1 | 2, from: string, to: string, aircraft: number, days: number[], dep: number, blk: number | null, no: number | null) => ({
  id, airline_id: 1, rotation_id: rot, leg_no: n, flight_no: no, origin_code: from, dest_code: to, aircraft_id: aircraft, days_utc: days, dep_utc_min: dep, block_min: blk,
});
// T-001 flies HUB–AAA daily (1001 at 06:00, 1002 back at 09:30) and HUB–DDD on Mon, Wed and Fri (1003 at 20:00, 1004 back
// the next morning at 06:30); T-002 flies HUB–NBN daily (1007, back with no number of its own, so 1006)
const input: RulesInput = {
  ...base,
  routes: base.routes.map((r) => (r.id === 1 ? { ...r, market_id: 1 } : r.id === 4 ? { ...r, market_id: 2 } : r)),
  rotations: [{ id: 1, airline_id: 1, route_id: 1 }, { id: 2, airline_id: 1, route_id: 4 }, { id: 3, airline_id: 1, route_id: 6 }],
  flight_legs: [
    leg(1, 1, 1, "HUB", "AAA", 1, ALL, 360, 75, 1001), leg(2, 1, 2, "AAA", "HUB", 1, ALL, 510, 75, 1002),
    leg(3, 2, 1, "HUB", "DDD", 1, [1, 3, 5], 1200, 150, 1003), leg(4, 2, 2, "DDD", "HUB", 1, [2, 4, 6], 60, 160, 1004),
    leg(5, 3, 1, "HUB", "NBN", 2, ALL, 600, 60, 1007), leg(6, 3, 2, "NBN", "HUB", 2, ALL, 720, 60, null),
  ],
};
const rules = buildRules(input);

const card = (x: Partial<Card> = {}): Card => ({
  airline_id: 1, code: "TA", name: "Test Air", profit_day: 0.4567, span_days: 7, early: false, per_aircraft_day: 0.0456, return_on_fleet_pct_week: 2.345,
  payback_days: 33.4, funds_aircraft_every_days: 0.6, fleet: 10, fleet_added_this_week: 2, on_order: 3, flights_day: 40, flights_added_this_week: 0,
  load_7_days: 87.6, next_order: { when: "now", types: ["A350-900ULR", "A321XLR", "A321 NEO LIGHT"] }, can_order_now: [], ...x,
});

describe("an airline's card, as the old Review words it", () => {
  it("a card with every figure", () => {
    expect(cardWords(card())).toMatchObject({
      big: "+0.46M", bigNeg: false, sub: "profit, last 7 days", perAircraft: "+46k a day", returnOnFleet: "2.3% a week", payback: "33 days",
      fundsEvery: "under a day", fleet: "10 flying", fleetAdded: "+2 this week", onOrder: " · 3 on order", flights: "40", flightsAdded: "", load: "≈88%",
      next: { text: "can order A350 or XLR", kind: "pill" },
    });
  });
  it("says why there's no profit yet, and a dash for each figure that needs it", () => {
    const x = cardWords(card({ profit_day: null, span_days: null, early: null, per_aircraft_day: null, return_on_fleet_pct_week: null, payback_days: null,
      funds_aircraft_every_days: null, load_7_days: null, on_order: 0, fleet_added_this_week: 0 }));
    expect(x).toMatchObject({ big: "—", sub: "needs two nights of cash", perAircraft: "—", returnOnFleet: "—", payback: "—", fundsEvery: "—", load: "—", onOrder: "", fleetAdded: "" });
  });
  it("an early read names its days; a loss is red, with a minus", () => {
    expect(cardWords(card({ early: true, span_days: 1 })).sub).toBe("profit, early read over 1 day");
    expect(cardWords(card({ early: true, span_days: 3 })).sub).toBe("profit, early read over 3 days");
    const x = cardWords(card({ profit_day: -0.125, per_aircraft_day: -0.0125, return_on_fleet_pct_week: -1.25, payback_days: 1 }));
    expect([x.big, x.bigNeg, x.perAircraft, x.returnOnFleet, x.payback]).toEqual(["−0.13M", true, "−13k a day", "−1.3% a week", "1 day"]);
  });
  it("next order: what's missing, the first safe day, or nothing within 14 days", () => {
    expect(nextOrderWords({ when: "needs", missing: "a capture" })).toEqual({ text: "needs a capture", kind: "dim" });
    expect(nextOrderWords({ when: "needs", missing: "a bank statement capture" }).text).toBe("needs a bank statement capture");
    expect(nextOrderWords(null)).toEqual({ text: "needs a capture", kind: "dim" });
    expect(nextOrderWords({ when: "later", type: "E195-E2", safe_from: "2026-10-16T05:52:00.000Z" })).toEqual({ text: "E195 safe from Fri, Oct 16", kind: "plain" });
    expect(nextOrderWords({ when: "not within 14 days" })).toEqual({ text: "not in the next 14 days", kind: "dim" });
    // since 26 Oct: the fare ladder's loads each way (out from the hub · back)
    expect(loadsWords({ load_out: 96.4, load_back: "87.6", departures_out: 7, departures_back: 7 })).toBe("96% · 88%");
    expect(loadsWords({ load_out: 100, load_back: null, departures_out: 3, departures_back: 0 })).toBe("100% · —");
    expect(loadsWords({})).toBe("");
    // since 26 Oct: how much it can spend now, whether or not that buys an aircraft yet
    expect(nextOrderWords({ when: "now", types: ["A321 NEO", "A321 NEO LIGHT"], up_to: 2.731 })).toEqual({ text: "up to 2.73M", kind: "pill" });
    expect(nextOrderWords({ when: "later", type: "E195-E2", safe_from: "2026-10-16T05:52:00.000Z", up_to: "1.34" })).toEqual({ text: "up to 1.34M", kind: "plain" });
    expect(nextOrderWords({ when: "later", type: "E195-E2", up_to: 0 })).toEqual({ text: "up to 0.00M", kind: "plain" });
    expect(nextOrderWords({ when: "needs", missing: "a capture", up_to: 1 })).toEqual({ text: "needs a capture", kind: "dim" });
  });
  it("the old formats: millions, thousands, days, the forecast's day and payment", () => {
    expect([sg(0.005), sg(-0.004), kk(0.0004), kk(-0.0125), dd(0.5), dd(1.4), dd(null)]).toEqual(["+0.01M", "−0.00M", "+0k", "−13k", "under a day", "1 day", "—"]);
    expect(fcDay("2026-10-14T23:30:00Z")).toBe("Wed, Oct 14");
    expect([fcWhat("Week-end closing of Pan Am"), fcWhat("Leasing payment for N123AW (A321)"), fcWhat("Salaries")]).toEqual(["the week-end closing", "the lease for N123AW", "a payment"]);
  });
});

const day = (date: string, profit: number, x: Partial<ProfitDay> = {}): ProfitDay => ({
  date, cash: 10, change: profit, order_payments: 0, days: 1, profit_day: profit, aircraft: 4, flights: 20, load: 90, per_aircraft_day: profit / 4, ...x,
});

describe("the profit chart", () => {
  const days = Array.from({ length: 20 }, (_, i) => day(`2026-09-${String(i + 1).padStart(2, "0")}`, i % 3 ? 0.2 : -0.1));
  it("shows the last 14 intervals, oldest first", () => {
    expect(CHART_INTERVALS).toBe(14);
    const iv = chartIntervals(days);
    expect(iv).toHaveLength(14);
    expect([iv[0]?.date, iv[13]?.date]).toEqual(["2026-09-07", "2026-09-20"]);
    expect(chartIntervals(days.slice(0, 5))).toHaveLength(5);
    expect(chartIntervals([])).toEqual([]);
  });
  it("a bar per interval, labelled day/month, with the old tip and the average line", () => {
    const g = barLayout(chartIntervals(days).map((x) => ({ x: x.date, y: x.profit_day, tip: x.date })), 0.1234);
    expect(g.bars).toHaveLength(14);
    expect(g.bars[0]?.label).toBe("07/09");
    expect(g.bars.filter((b) => b.neg)).toHaveLength(5);
    expect(g.avg?.text).toBe("average +0.12M a day");
    expect(g.grid.some((l) => l.zero)).toBe(true);
    expect(barTip(day("2026-09-03", 0.25, { days: 2, order_payments: 1.5 }), (d) => d)).toBe("2026-09-03 · +0.25M a day over 2 days · includes 1.50M of order payments");
    expect(barTip(day("2026-09-03", -0.25), (d) => d)).toBe("2026-09-03 · −0.25M a day");
  });
  it("the sparkline scales to the largest interval, above and below the middle", () => {
    const s = sparkBars([day("a", 0.5), day("b", -0.25)]);
    expect(s.map((b) => [Math.round(b.h * 10) / 10, b.neg])).toEqual([[13, false], [6.5, true]]);
  });
});

describe("the cash forecast's words", () => {
  it("each type: now (and how many), from a day, or not within 14 days, with its price and lease", () => {
    const t = { aircraft_type_id: 1, type: "A321 NEO LIGHT", price_with_cabin: 62.5, lease_week: 0.875, lease_seen: true, safe_day: 0, safe_from: "2026-10-14T05:00:00Z", count_today: 9 };
    expect(safeWords(t)).toEqual({ kind: "ok", text: "A321neo (62.50M with cabin, lease 0.88M a week): now, up to 9+" });
    expect(safeWords({ ...t, count_today: 1, lease_seen: false }).text).toBe("A321neo (62.50M with cabin, lease 0.88M a week est.): now");
    expect(safeWords({ ...t, safe_day: 3, safe_from: "2026-10-17T05:00:00Z" })).toEqual({ kind: "mute", text: "A321neo (62.50M with cabin, lease 0.88M a week): from Sat, Oct 17" });
    expect(safeWords({ ...t, safe_day: null, safe_from: null }).kind).toBe("warn");
  });
});

const route = (hub: string, dest: string, x: Partial<RouteRow> = {}): RouteRow => ({
  route_id: 1, hub, dest, flights: 7, margin: 0.3, profit_per_flight: 0.02, flights_week: 14, profit_week: 0.28, economy: 90, business: 60, cargo: 40, economy_fare: 300,
  sold_out: 5, with_loads: 7, mark: "hold", why: "", ...x,
});

describe("route profit", () => {
  const rs = [route("HUB", "AAA", { mark: "add", profit_week: 1 }), route("HUB", "BBB", { mark: "raise", profit_week: 0.5, margin: null, profit_per_flight: 0.05 }),
    route("HUB", "CCC", { mark: "losing", profit_week: -0.2, economy: null }), route("FOC", "AAA", { mark: "add", profit_week: 0.1, margin: 0.6 })];
  it("counts the marks, and filters and sorts as the old buttons do", () => {
    expect(markCounts(rs)).toEqual({ add: 2, raise: 1, losing: 1 });
    expect(shownRoutes(rs, "add", "pwk").map((r) => r.dest)).toEqual(["AAA", "AAA"]);
    expect(shownRoutes(rs, "", "margin").map((r) => r.hub + r.dest)).toEqual(["FOCAAA", "HUBAAA", "HUBCCC", "HUBBBB"]);
    expect(shownRoutes(rs, "", "eco").map((r) => r.dest).slice(-1)).toEqual(["CCC"]);
    expect(shownRoutes(rs, "", "ppf")[0]?.dest).toBe("BBB");
  });
  it("the line under the filters, with the sold-out minimum from the settings", () => {
    expect(capturedLine({ days: 7, flights: 161, matched: 161, mixed: 0, average_flight: null, routes: [] }, 4))
      .toBe("161 flights captured over the last 7 days, all matched to their loads. A route needs 4 captured departures before it can be called sold out.");
    expect(capturedLine({ days: 1, flights: 20, matched: 18, mixed: 2, average_flight: null, routes: [] }, 4))
      .toBe("20 flights captured over the last day, 18 matched to their loads · 2 couldn't be told apart from another flight in the same minute. A route needs 4 captured departures before it can be called sold out.");
  });
  it("an average flight in thousands, with the database's profit and margin; nothing when it earned nothing", () => {
    const a = { passengers: 0.05, cargo: 0.002, fuel: 0.02, handling: 0.003, onboard: 0.001, landing: 0.002, air_traffic: 0.001, maintenance: 0.004, income: 0.052, costs: 0.031, profit: 0.021, margin: 0.4038 };
    const c = costParts(a);
    expect([c?.income.map((x) => x.k), c?.profitK, c?.marginPct]).toEqual([[50, 2], 21, 40]);
    expect(costParts({ ...a, income: 0 })).toBeNull();
    expect(costParts(null)).toBeNull();
  });
});

const plan = (x: Partial<PlanRow> = {}): PlanRow => ({
  id: 7, legacy_key: "fp1", route_id: 1, hub: "HUB", dest: "AAA", cabin_class: "economy", change_pct: 5, fare_from: 300, proposed_on: "2026-10-10", status: "planned",
  reason: "sells out", updated_at: "2026-10-10T10:00:00.123456+00:00", fare_now: 310.4, target: 315, applied: false, seen_on: null, economy_before: null, economy_after: null, ...x,
});

describe("the fare plan", () => {
  it("words each change: to do, or seen in the game with the load before and after", () => {
    expect(planWords(plan(), (d) => d)).toMatchObject({ route: "HUB–AAA", cls: "economy", change: "+5%", fares: "300 → 315", now: "310", status: { kind: "warn", text: "to do in the game" }, loads: "—" });
    expect(planWords(plan({ applied: true, seen_on: "2026-10-12", economy_before: 99.4, economy_after: 91.6, change_pct: -3 }), (d) => d))
      .toMatchObject({ change: "-3%", status: { kind: "ok", text: "seen in the game 2026-10-12" }, loads: "99% → 92%" });
  });
  it("+ fare plan on a route that sells out with nothing planned; the row the old planner writes; remove drops it", () => {
    expect(offersFarePlan(route("HUB", "AAA", { mark: "add" }), [])).toBe(true);
    expect(offersFarePlan(route("HUB", "AAA", { mark: "add" }), [plan()])).toBe(false);
    expect(offersFarePlan(route("HUB", "AAA", { mark: "hold" }), [])).toBe(false);
    expect(farePlanAdd({ worldId: 1, airlineId: 2, routeId: 3, fare: 304.6, pct: 5, today: "2026-10-14", nowMs: 1_791_000_000_000 })).toEqual({
      table: "fare_plan", op: "insert", values: { world_id: 1, airline_id: 2, route_id: 3, legacy_key: "fp" + (1_791_000_000_000).toString(36), cabin_class: "economy",
        change_pct: 5, fare_from: 305, proposed_on: "2026-10-14", status: "planned", reason: "sells out" } });
    expect(farePlanAdd({ worldId: 1, airlineId: 2, routeId: 3, fare: null, pct: 5, today: "2026-10-14", nowMs: 1 })).toBeNull();
    expect(farePlanDrop(plan())).toEqual({ table: "fare_plan", op: "update", key: { id: 7 }, base: "2026-10-10T10:00:00.123456+00:00", values: { status: "dropped" } });
  });
});

describe("the scorecards: each figure against the same day last week, from the daily history", () => {
  const row = (airline: number, day: string, fleet: number | null, weekly: number | null, eco: number | null): DayRow =>
    ({ airline_id: airline, day, aircraft_total: fleet, weekly_departures: weekly, eco_load_pct: eco });
  // Test Air: every day from 1 to 15 Oct, two more aircraft and 21 more departures a week by the 15th, its load falling
  const history: DayRow[] = [
    ...Array.from({ length: 15 }, (_, i) => row(1, `2026-10-${String(i + 1).padStart(2, "0")}`, i < 8 ? 10 : 12, i < 8 ? 280 : 301, 90 - i * 0.5)),
    // Other Air: new, its first day the 12th, so nothing a week ago
    row(2, "2026-10-12", 4, 56, 80), row(2, "2026-10-13", 4, 56, 81), row(2, "2026-10-14", 5, 70, 82),
    // Third Air: the same fleet and schedule as a week ago, and a day after today left out
    row(3, "2026-10-07", 6, 140, 95), row(3, "2026-10-14", 6, 140, 95), row(3, "2026-10-16", 9, 200, 50),
  ];
  it("the latest day against the same day a week earlier: fleet, flights a day (departures a week ÷ 7) and the 7 days' economy load", () => {
    const x = weekOnWeek(history, 1, "2026-10-15");
    expect([x.day, x.weekAgo, x.compared]).toEqual(["2026-10-15", "2026-10-08", true]);
    expect(x.changes.fleet).toEqual({ now: 12, then: 10, delta: 2, arrow: "up", text: "▲ 2" });
    expect(x.changes.flights).toEqual({ now: 43, then: 40, delta: 3, arrow: "up", text: "▲ 3" });
    // the 7 days to the 15th (9th–15th) average 84.5%; to the 8th (2nd–8th) 88%
    expect(x.changes.load).toMatchObject({ delta: -3.5, arrow: "down", text: "▼ 3.5 pts" });
  });
  it("an airline with no day a week ago: nothing to compare, each change a dash", () => {
    const x = weekOnWeek(history, 2, "2026-10-15");
    expect([x.day, x.weekAgo, x.compared]).toEqual(["2026-10-14", "2026-10-07", false]);
    expect(Object.values(x.changes).map((c) => [c.text, c.arrow, c.delta])).toEqual([["—", null, null], ["—", null, null], ["—", null, null]]);
  });
  it("no change is the same; a day after today isn't read; an airline with no history at all", () => {
    const x = weekOnWeek(history, 3, "2026-10-15");
    expect([x.day, x.changes.fleet.text, x.changes.flights.arrow, x.changes.load.text]).toEqual(["2026-10-14", "= same", "same", "= same"]);
    expect(weekOnWeek(history, 9, "2026-10-15")).toMatchObject({ day: null, weekAgo: null, compared: false });
    expect(weekOnWeek([row(1, "2026-10-08", null, 280, null), row(1, "2026-10-15", 12, 301, null)], 1, "2026-10-15").changes)
      .toMatchObject({ fleet: { text: "—" }, flights: { text: "▲ 3" }, load: { text: "—" } });
    expect(historyFrom("2026-10-15")).toBe("2026-09-30");
  });
  it("one point of load is \"1 pt\", not \"1 pts\" (the rehearsal's screenshots)", () => {
    const x = weekOnWeek([row(1, "2026-10-08", 10, 280, 90), row(1, "2026-10-15", 10, 280, 91)], 1, "2026-10-15");
    expect(x.changes.load.text).toBe("▲ 1 pt");
    expect(weekOnWeek([row(1, "2026-10-08", 10, 280, 90), row(1, "2026-10-15", 10, 280, 88)], 1, "2026-10-15").changes.load.text).toBe("▼ 2 pts");
  });
});

describe("the growth lists cut to their first 10 rows (21 Oct: Performance ran to 11,890 px)", () => {
  const rows = Array.from({ length: 94 }, (_, i) => ({ route: `R${i + 1}` }));
  it("10 shown of 94, in the list's own order, with \"show all 94\"", () => {
    const c = listCut(rows, false);
    expect(c.shown.map((r) => r.route)).toEqual(["R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9", "R10"]);
    expect(c.button).toBe("show all 94");
    expect(LIST_TOP).toBe(10);
  });
  it("all 94 shown when opened, with \"show fewer\"", () => {
    const c = listCut(rows, true);
    expect(c.shown).toHaveLength(94);
    expect(c.shown[93]).toEqual({ route: "R94" });
    expect(c.button).toBe("show fewer");
  });
  it("no button with 10 rows or fewer, open or not", () => {
    expect(listCut(rows.slice(0, 10), false)).toEqual({ shown: rows.slice(0, 10), button: null });
    expect(listCut(rows.slice(0, 10), true)).toEqual({ shown: rows.slice(0, 10), button: null });
    expect(listCut(rows.slice(0, 3), false).shown).toHaveLength(3);
    expect(listCut([], false)).toEqual({ shown: [], button: null });
    expect(listCut(rows.slice(0, 11), false)).toEqual({ shown: rows.slice(0, 10), button: "show all 11" });
  });
});

const lr = (hub: string, dest: string, x: Partial<LadderRoute> = {}): LadderRoute => ({
  route_id: 1, hub, dest, cabin: "economy", departures: 14, sold_out: 14, sold_out_share: 100, average_fare: 300, baseline_fare: 300, baseline_on: "2026-10-06",
  latest_fare: 300, latest_on: "2026-10-20", fare_index: 100, index_matches: true, level: 100, recorded: false, steps: 0, move: "up", new_level: 105, new_steps: 1,
  change_pct: 5, reason: "sold out 14 of 14", contested: false, floor: 100, cap: 120, new_route: false, planned: false, plan_id: null, applied: false, seen_on: null,
  to_plan: true, ...x,
});

describe("the fare ladder (21 Oct, manual §5): the board's words, its sorts and Put on the fare plan's rows", () => {
  it("this Saturday's moves in one line", () => {
    expect(ladderLine({ up: 12, hold: 30, down: 2 })).toBe("12 up, 30 hold, 2 down");
    expect(ladderLine({ up: 0, hold: 0, down: 0 })).toBe("0 up, 0 hold, 0 down");
    // since 23 Oct, the jumps under launch and the cut-or-keep decisions, when there are any
    expect(ladderLine({ up: 2, hold: 6, down: 3, jumps: 2, decisions: 1 })).toBe("2 up, 6 hold, 3 down · 2 jumps, 1 decision");
    expect(ladderLine({ up: 1, hold: 0, down: 1, jumps: 0, decisions: 0 })).toBe("1 up, 0 hold, 1 down");
    expect([underLaunchLine({ jumps: 1, decisions: 0 }), underLaunchLine({ jumps: 0, decisions: 2 }), underLaunchLine({})]).toEqual(["1 jump", "2 decisions", ""]);
  });
  it("the count of changes in the game for the airline's heading (21 Oct: route by route, each direction its own change)", () => {
    expect([changesWords(24), changesWords(1), changesWords(0)]).toEqual(["24 changes in the game", "1 change in the game", "no changes in the game"]);
    // a route's two cabins moving to the same level: one action each way, both classes ticked (the type has no base, kind
    // or cabin any more, so an action with one fails the type check)
    const out: LadderAction = { n: 7, route: "ZD1–ZE9", classes: ["economy", "business"], from: "ZD1", to: "ZE9", level: 105, sign: "+", pct: 5,
      baseline: "default price", text: "From ZD1 to ZE9: +5% of the default price, economy and business" };
    const back: LadderAction = { ...out, n: 8, from: "ZE9", to: "ZD1", text: "From ZE9 to ZD1: +5% of the default price, economy and business" };
    expect(changesWords([out, back].length)).toBe("2 changes in the game");
  });
  it("a level with its steps above launch", () => {
    expect([levelWords(100, 0), levelWords(105, 1), levelWords(120, 4), levelWords(102, 0.4), levelWords(95, -1)])
      .toEqual(["100% · launch", "105% · 1 step up", "120% · 4 steps up", "102% · 0.4 steps up", "95% · 1 step under launch"]);
    expect(stepWords(2)).toBe("2 steps up");
  });
  it("the move: up plain, down in amber, hold quiet", () => {
    expect(moveWords(lr("A", "B"))).toEqual({ text: "up to 105%", kind: "up" });
    expect(moveWords(lr("A", "B", { move: "down", new_level: 100 }))).toEqual({ text: "down to 100%", kind: "down" });
    expect(moveWords(lr("A", "B", { move: "hold", new_level: 90 }))).toEqual({ text: "hold", kind: "hold" });
  });
  it("under launch (23 Oct): a jump in amber, a revert plain, the hold after a jump in words, and cut or keep?", () => {
    expect(moveWords(lr("A", "B", { move: "down", ladder_kind: "jump", new_level: 80 }))).toEqual({ text: "jump to 80%", kind: "down" });
    expect(moveWords(lr("A", "B", { move: "up", ladder_kind: "revert", new_level: 100 }))).toEqual({ text: "back to launch, 100%", kind: "up" });
    expect(moveWords(lr("A", "B", { move: "hold", ladder_kind: "hold", level: 80, new_level: 80, under_launch: { state: "holding", jumped_on: "2026-10-25", judge_on: "2026-11-08" } })))
      .toEqual({ text: "hold under launch", kind: "hold" });
    expect(moveWords(lr("A", "B", { move: "hold", ladder_kind: "hold", new_level: 80, under_launch: { state: "done" } }))).toEqual({ text: "hold", kind: "hold" });
    expect([decideWords(lr("A", "B", { decide: true })), decideWords(lr("A", "B", { decide: false })), decideWords(lr("A", "B"))]).toEqual(["cut or keep?", "", ""]);
  });
  it("the sold-out share, and a route with no flights captured", () => {
    expect(soldWords(lr("A", "B", { sold_out: 13, sold_out_share: 92.9 }))).toBe("13/14 · 93%");
    expect(soldWords(lr("A", "B", { departures: 0, sold_out: 0, sold_out_share: null }))).toBe("no flights");
  });
  it("a move on the fare plan already: to do in the game, or seen", () => {
    expect(plannedWords(lr("A", "B"), (d) => d)).toBe("");
    expect(plannedWords(lr("A", "B", { planned: true }), (d) => d)).toBe("on the fare plan · to do in the game");
    expect(plannedWords(lr("A", "B", { planned: true, applied: true, seen_on: "2026-10-25" }), (d) => d)).toBe("on the fare plan · seen in the game 2026-10-25");
  });
  it("Put on the fare plan: how many, or on the plan already, or nothing to put", () => {
    const routes = [lr("A", "B"), lr("A", "C", { to_plan: false, planned: true, applied: true }), lr("A", "D", { to_plan: false, planned: true })];
    expect(planButton({ to_plan: 1, planned: 2, routes })).toEqual({ text: "Put on the fare plan (1)", enabled: true, note: "2 on the fare plan this Saturday, 1 seen in the game" });
    expect(planButton({ to_plan: 0, planned: 2, routes })).toEqual({ text: "On the fare plan", enabled: false, note: "2 on the fare plan this Saturday, 1 seen in the game" });
    expect(planButton({ to_plan: 0, planned: 0, routes: [] })).toEqual({ text: "Nothing to put on the fare plan", enabled: false, note: "" });
  });
  it("sorts: moves first (down, up, hold), by route, by level, by the sold-out share (lowest first, no flights last); ties keep the database's order", () => {
    const rows = [lr("A", "B", { move: "hold", level: 110 }), lr("A", "C", { move: "up", sold_out_share: 100 }), lr("A", "D", { move: "down", sold_out_share: 70, level: 115 }),
      lr("A", "E", { move: "up", cabin: "business", departures: 0, sold_out_share: null }), lr("A", "F", { move: "hold", sold_out_share: 93 })];
    expect(ladderRows(rows, "move").map((r) => r.dest)).toEqual(["D", "C", "E", "B", "F"]);
    expect(ladderRows(rows, "route").map((r) => r.dest)).toEqual(["B", "C", "D", "E", "F"]);
    expect(ladderRows(rows, "level").map((r) => r.dest)).toEqual(["D", "B", "C", "E", "F"]);
    expect(ladderRows(rows, "sold").map((r) => r.dest)).toEqual(["D", "F", "B", "C", "E"]);
    expect(LADDER_SORTS.map((s) => s[0])).toEqual(["move", "route", "level", "sold"]);
  });
  it("Put on the fare plan's rows: one insert per route and cabin marked to_plan, the level and move the ladder's, on the UTC day", () => {
    const routes = [lr("A", "B", { route_id: 7 }), lr("A", "C", { route_id: 8, to_plan: false }),
      lr("A", "D", { route_id: 9, cabin: "business", move: "hold", new_level: 105, level: 105, change_pct: 0, reason: "held after a step down on 18 Oct", latest_fare: 912.346 }),
      lr("A", "E", { route_id: 10, move: "down", level: 110, new_level: 105, change_pct: -4.5, reason: "sold out 11 of 14", latest_fare: null })];
    const ch = ladderPlanChanges({ worldId: 1, airlineId: 2, routes, utcDay: "2026-10-24", nowMs: 1_793_000_000_000 });
    const key = (i: number) => `fl${(1_793_000_000_000).toString(36)}-${i}`;
    expect(ch).toEqual([
      { table: "fare_plan", op: "insert", values: { world_id: 1, airline_id: 2, route_id: 7, legacy_key: key(0), cabin_class: "economy", change_pct: 5, fare_from: 300,
        proposed_on: "2026-10-24", status: "planned", reason: "sold out 14 of 14", level_pct: 105, ladder_move: "up" } },
      { table: "fare_plan", op: "insert", values: { world_id: 1, airline_id: 2, route_id: 9, legacy_key: key(1), cabin_class: "business", change_pct: 0, fare_from: 912.35,
        proposed_on: "2026-10-24", status: "planned", reason: "held after a step down on 18 Oct", level_pct: 105, ladder_move: "hold" } },
      { table: "fare_plan", op: "insert", values: { world_id: 1, airline_id: 2, route_id: 10, legacy_key: key(2), cabin_class: "economy", change_pct: -4.5, fare_from: null,
        proposed_on: "2026-10-24", status: "planned", reason: "sold out 11 of 14", level_pct: 105, ladder_move: "down" } },
    ]);
    expect(ladderPlanChanges({ worldId: 1, airlineId: 2, routes: [routes[1] as LadderRoute], utcDay: "2026-10-24", nowMs: 1 })).toEqual([]);
  });
  it("Put on the fare plan under launch (23 Oct): ladder_move jump or revert from the row's ladder_kind, else the move", () => {
    const routes = [lr("A", "B", { route_id: 7, move: "down", ladder_kind: "jump", new_level: 80, change_pct: -20, reason: "41% full over 14 days at launch: to 80% for 2 weeks" }),
      lr("A", "C", { route_id: 8, move: "up", ladder_kind: "revert", level: 60, new_level: 100, change_pct: 66.7, decide: true, reason: "back to launch; cut or keep? (Saturday review)" }),
      lr("A", "D", { route_id: 9, move: "hold", ladder_kind: "hold", level: 80, new_level: 80, change_pct: 0, reason: "at 80%: paid off" }),
      lr("A", "E", { route_id: 10, ladder_kind: "up" })];
    expect(ladderPlanChanges({ worldId: 1, airlineId: 2, routes, utcDay: "2026-10-24", nowMs: 5 }).map((c) => [c.values?.route_id, c.values?.level_pct, c.values?.ladder_move]))
      .toEqual([[7, 80, "jump"], [8, 100, "revert"], [9, 80, "hold"], [10, 105, "up"]]);
  });
  it("the fare plan words a ladder row with its move and level, and a fare test as before", () => {
    expect(planWords(plan({ change_pct: 5, level_pct: 105, ladder_move: "up" }), (d) => d).change).toBe("+5% · up to 105%");
    expect(planWords(plan({ change_pct: 0, level_pct: 105, ladder_move: "hold" }), (d) => d).change).toBe("0% · hold to 105%");
    expect(planWords(plan(), (d) => d).change).toBe("+5%");
  });
  it("the route profit table's fare index, flagged when the level recorded doesn't match it", () => {
    expect(indexWords(lr("A", "B", { fare_index: 104.96 }))).toEqual({ text: "105", flag: "" });
    expect(indexWords(lr("A", "B", { fare_index: 100, index_matches: false, level: 110 }))).toEqual({ text: "100", flag: "level 110%" });
    expect(indexWords(lr("A", "B", { fare_index: null }))).toEqual({ text: "—", flag: "" });
    expect(indexWords(undefined)).toEqual({ text: "—", flag: "" });
  });
  // 21 Oct (spec docs/specs/2026-10-21-frequencies-and-fares.md §3): the set-back changes first, in their own short list
  it("the set-back changes apart from the week's moves, and their heading by the routes they set back", () => {
    const act = (n: number, route: string, fix: boolean): LadderAction => ({ n, route, classes: ["economy"], from: route.slice(0, 3), to: route.slice(4), level: 110,
      sign: "+", pct: 10, baseline: "default price", text: `From ${route.slice(0, 3)} to ${route.slice(4)}: +10% of the default price, economy`, fix,
      reason: fix ? "captured fare at 100%, level 110%" : null });
    const actions = [act(1, "AAA–BBB", true), act(2, "AAA–BBB", true), act(3, "AAA–CCC", true), act(4, "AAA–CCC", true), act(5, "AAA–DDD", false), act(6, "AAA–DDD", false)];
    const { fixes, moves } = splitActions(actions);
    expect(fixes.map((a) => a.n)).toEqual([1, 2, 3, 4]);
    expect(moves.map((a) => a.n)).toEqual([5, 6]);
    expect(offLevelWords(fixes)).toBe("2 routes off their level");
    expect(offLevelWords(fixes.slice(0, 2))).toBe("1 route off its level");
    // a ladder from before 21 Oct has no fix: every action is a move
    expect(splitActions(actions.map((a) => ({ ...a, fix: undefined }))).fixes).toEqual([]);
  });
  it("the 14-day load sparkline: both directions together, by the route or its two airports, at most 100%, a day with no seats empty", () => {
    const d = (day: string, o: string, t: string, pax: number | null, seats: number | null, route_id: number | null = 7): RouteDayRow =>
      ({ route_id, origin_code: o, dest_code: t, day, passengers: pax, seats });
    const rows = [d("2026-10-20", "AAA", "BBB", 170, 180), d("2026-10-20", "BBB", "AAA", 190, 180), d("2026-10-19", "AAA", "BBB", 90, 180),
      d("2026-10-18", "BBB", "AAA", 200, 180, null), d("2026-10-06", "AAA", "BBB", 180, 180), d("2026-10-07", "AAA", "BBB", 50, null), d("2026-10-20", "AAA", "CCC", 10, 180, 8)];
    const v = loads14(rows, { route_id: 7, hub: "AAA", dest: "BBB" }, "2026-10-20");
    expect(v).toHaveLength(SPARK_DAYS);
    expect(v.slice(-3)).toEqual([100, 50, 100]);
    expect(v[0]).toBeNull();
    expect(v[1]).toBeNull();
    expect(v.filter((x) => x != null)).toHaveLength(3);
    const bars = loadSparkBars(v);
    expect(bars).toHaveLength(3);
    expect(bars.map((b) => [b.h, b.low])).toEqual([[16, false], [8, true], [16, false]]);
    expect(sparkWords(v)).toBe("3 days' load: 50% to 100%, 83% on average");
    expect(sparkWords(Array(14).fill(null))).toBe("no loads in the daily history for the last 14 days");
  });
});

describe("the growth signals and main hubs (Check → Growth until 20 Oct)", () => {
  it("draws main hubs towards their target: exempt airlines and those without a main hub left out, the planned part lighter", () => {
    const rows = hubRows([
      { airline_id: 1, code: "TA", name: "Test Air", main_hub: "HUB", exempt: false, target: 750, departures: 600, planned: 210, percent: 80 },
      { airline_id: 2, code: "OA", name: "Other Air", main_hub: "AAA", exempt: true, target: 750, departures: 20, planned: 0, percent: 2.7 },
    ], () => "Test Air");
    expect(rows).toEqual([{ airline_id: 1, name: "Test Air", hub: "HUB", departures: 600, planned: 210, target: 750, width: "80.0%", pend: "20.0%", pct: 80 }]);
  });
  it("folds each airline's hub readiness into its line: its banks, the planned cities as more", () => {
    const r = (airline: number, airport: string, bank: number, dep: number, flying: number, planned: number) =>
      ({ base_id: airline * 10, airline_id: airline, airport, bank, dep, flying, with_planned: planned, regions: [{ region: "Europe", cities: flying }] });
    const rows = [r(1, "HUB", 1, 360, 12, 15), r(1, "HUB", 2, 720, 1, 1), r(1, "FOC", 1, 480, 3, 3), r(2, "AAA", 1, 600, 5, 5)];
    expect(readinessOf(rows, 1)).toEqual({ rows: rows.slice(0, 3), line: "HUB B1 06:00 12 cities (+3 planned) · B2 12:00 1 city · FOC B1 08:00 3 cities" });
    expect(readinessOf(rows, 3)).toEqual({ rows: [], line: "" });
  });
  it("writes money as the old board did", () => {
    expect([kWords(0.1234), kWords(-0.045), growthWeekWords(1.2), growthWeekWords(-0.456), pctWords(87.6), pctWords(null), perDayWords(2), perDayWords(1.4)])
      .toEqual(["+123k", "−45k", "+1.20M", "−0.46M", "88%", "—", "2×", "1.4×"]);
  });
});

describe("Flights by day (Check's daily load report until 20 Oct)", () => {
  it("reads the day from the address, today without one or with a bad one, and moves it a day at a time", () => {
    expect(parseDay("?day=2026-10-09", "2026-10-13")).toBe("2026-10-09");
    expect(parseDay("", "2026-10-13")).toBe("2026-10-13");
    expect(parseDay("?day=13-10-2026", "2026-10-13")).toBe("2026-10-13");
    expect(moveDay("2026-10-01", -1)).toBe("2026-09-30");
    expect(moveDay("2026-12-31", 1)).toBe("2027-01-01");
  });
});

describe("Flights by day: the departures and their loads", () => {
  const day = "2026-10-12";
  const flights: DayFlight[] = loadReport.flightsOn(rules, day, [{ id: 1, launched_on: "2026-10-01" }, { id: 2, launched_on: "2026-10-08" }]);
  const row = (code: string, eco: number | null, x: Partial<CapturedLoad> = {}): CapturedLoad => ({ airline: "Test Air", flight_date: day, code, eco, bus: null, fst: null, cargo: null,
    eco_pax: null, eco_seats: null, bus_pax: null, bus_seats: null, fst_pax: null, fst_seats: null, ...x });
  it("lists the day's departures and finds each one's captured loads by its airline and number", () => {
    expect(flights.map((f) => f.no)).toEqual([1001, 1002, 1007, 1006, 1003]);
    const m = loadsByFlight([row("TA 1001", 100), row("TA 1002", 80, { flight_date: "2026-10-11" })], day);
    expect([...m.keys()]).toEqual([loadKey("Test Air", 1001)]);
  });
  it("sums up the day from the captured loads: averages by class (a missing figure counting as 0, as the old report's), sold out, under 85%", () => {
    const m = loadsByFlight([row("TA 1001", 100, { bus: 80, cargo: 40 }), row("TA 1002", 82), row("TA 1007", 96, { bus: 90 })], day);
    const of = (f: DayFlight) => m.get(loadKey("Test Air", f.no));
    const s = daySummary(flights, of, { done: false, values: [] });
    expect(s).toEqual({ kind: "captured", departures: 5, captured: 3, economy: (100 + 82 + 96) / 3, business: (80 + 0 + 90) / 3, cargo: 40 / 3, soldOut: 1, under85: 1 });
    expect(summaryWords(s)).toBe("5 departures · 3 captured · economy 93% · business 57% · cargo 13% · 1 sold out · 1 under 85%");
    expect(airlineDay(flights, of)).toEqual({ departures: 5, captured: 3, economy: (100 + 82 + 96) / 3, soldOut: 1, firstWeek: 1 });
  });
  it("without captured loads: from the loads typed by hand once the day is complete, else not captured", () => {
    const hand: HandLoads = { done: true, values: [{ airline_id: 1, flight_no: 1001, eco_pct: 92 }, { airline_id: 1, flight_no: 1003, eco_pct: 64 }, { airline_id: 1, flight_no: 1007, eco_pct: 99 }] };
    const s = daySummary(flights, () => undefined, hand);
    expect(s).toEqual({ kind: "hand", departures: 5, under95: 2, under85: 1, under70: 1 });
    expect(summaryWords(s)).toBe("5 departures · entered by hand: under 95% 2 · under 85% 1 · under 70% 1");
    expect(summaryWords(daySummary(flights, () => undefined, { done: false, values: hand.values }))).toBe("5 departures · not captured");
  });
  it("writes a flight's loads by class, marked low under 85% economy", () => {
    expect(capLine(row("TA 1001", 97.6, { eco_pax: 176, eco_seats: 180, bus: 80, bus_pax: 16, bus_seats: 20, cargo: 40.4 })))
      .toEqual({ text: "Y 98% (176/180) · C 80% (16/20) · cargo 40%", low: false });
    expect(capLine(row("TA 1002", 70))).toEqual({ text: "Y 70%", low: true });
    expect(capLine(row("TA 1003", null))).toBeNull();
    expect(capLine(undefined)).toBeNull();
  });
});

describe("the plan card's service check on Tails", () => {
  const base = (JSON.parse(readFileSync(new URL("../../../../../lib/rules/cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
  const profiles = [{ id: 1, code: "S1", airline_id: null, up_to_km: 800 }, { id: 2, code: "S2", airline_id: null, up_to_km: 1500 },
    { id: 3, code: "S3", airline_id: null, up_to_km: 4192 }, { id: 4, code: "S4", airline_id: null, up_to_km: 99999 }, { id: 5, code: "R", airline_id: 2, up_to_km: 99999 }];
  // the start carries only HUB–AAA; HUB–EEE is a route of the airline's that isn't flown yet (1,600 km: S3)
  const rules = buildRules({ ...base, routes: base.routes.filter((r) => r.id === 1), service_profiles: profiles,
    airports: [...base.airports, { code: "EEE", lat: 40, lon: 0, utc_offset: 0, mct_min: null }] });
  const T = "2026-10-12T10:00:00+00:00";
  const leg = (id: number, pos: number, from: string, to: string, svc: string | null): PlanLegRow => ({
    id, plan_card_id: 9, position: pos, flight_no: 1100 + pos, origin_code: from, dest_code: to, days_utc: [1, 2, 3, 4, 5, 6, 7], dep_utc_min: 360 + pos * 200, block_min: 90,
    service_code: svc, updated_at: T,
  });
  const table: TableRoute = {
    id: 99, airline_id: 1, hub_code: "HUB", dest_code: "EEE", city: null, country_label: null, distance_km: 1550, market_id: null, stars: 3, source: "research", removed: false,
    removed_note: null, city_override: null, distance_override_km: 1600, market_override_id: null, market_cleared: false, stars_override: null, updated_at: T,
  } as TableRoute;
  it("flags a wrong code and a missing one by the leg's route distance, the airline's routes laid in first", () => {
    const legs = cardLegs(rules, [leg(1, 1, "HUB", "AAA", "S1"), leg(2, 2, "AAA", "HUB", "S2"), leg(3, 3, "HUB", "EEE", "S3"), leg(4, 4, "EEE", "HUB", null)]);
    const issues = cardServiceIssues(withRoutes(rules, [table]), 1, legs);
    expect([...issues]).toEqual([[2, "S2, wants S1"], [4, "none, wants S3"]]);
  });
  it("Ryanair (its own R) wants R everywhere", () => {
    const legs = cardLegs(rules, [leg(1, 1, "HUB", "AAA", "R"), leg(2, 2, "AAA", "HUB", "S1")]);
    expect([...cardServiceIssues(rules, 2, legs)]).toEqual([[2, "S1, wants R"]]);
  });
});

// 22 Oct (spec docs/specs/2026-10-22-planner-look-performance.md): the page heads' answers, the rows' counts, the charts
describe("Performance's new look", () => {
  it("the group page's title says how many airlines are in profit, never a group total", () => {
    expect(profitAnswer([0.4, 0.1, 0.2, 0.3, 0.5, 0.9].map((p) => ({ profit_day: p })))).toBe("Six airlines, all in profit");
    expect(profitAnswer([0.4, -0.1, 0.2, 0.3, 0.5, 0.9].map((p) => ({ profit_day: p })))).toBe("5 of 6 airlines in profit");
    expect(profitAnswer([{ profit_day: 0.2 }, { profit_day: null }])).toBe("1 of 2 airlines in profit");
    expect(profitAnswer([{ profit_day: 0 }])).toBe("0 of 1 airline in profit");
    expect(profitAnswer([{ profit_day: 0.1 }])).toBe("One airline, in profit");
    expect(profitAnswer([])).toBe("Performance");
  });
  it("the rows: Route profit alone open on the airline's page, the fare ladder no longer a row", () => {
    expect(BOARDS).toEqual(["Profit", "Cash, next 14 days", "Route profit", "Aircraft", "Fare changes", "Fare plan"]);
    expect(BOARDS_FOLDED).toEqual(["Profit", "Cash, next 14 days", "Aircraft", "Fare changes", "Fare plan"]);
    expect(GROUP_BOARDS).toEqual(["The group today", "Growth signals", "Main hubs", "Flights by day"]);
  });
  it("each page arrives with its own rows: Expand all on the group page doesn't carry to an airline's, nor one airline's to another's", () => {
    const sorted = (x: ReadonlySet<string>) => [...x].sort();
    const airlineArrival = sorted(foldsOnArrival("/performance/AW", "").folded);
    expect(GROUP_BOARDS.every((k) => airlineArrival.includes(k))).toBe(true);
    expect(BOARDS.filter((k) => !airlineArrival.includes(k))).toEqual(["Route profit"]);
    expect(GROUP_BOARDS.filter((k) => !foldsOnArrival("/performance", "?day=2026-10-19").folded.has(k))).toEqual(["Flights by day"]);
    expect(GROUP_BOARDS.filter((k) => !foldsOnArrival("/performance", "").folded.has(k))).toEqual([]);
    // Expand all on the group page, then the first scorecard opens AW's page
    const expanded = { view: "/performance", folded: new Set<never>() };
    expect(foldsFor(expanded, "/performance", "").size).toBe(0);
    expect(sorted(foldsFor(expanded, "/performance/AW", ""))).toEqual(airlineArrival);
    // and from AW's page, all open, the switch to PA
    expect(sorted(foldsFor({ view: "/performance/AW", folded: new Set<never>() }, "/performance/PA", ""))).toEqual(sorted(foldsOnArrival("/performance/PA", "").folded));
    // back on the group page with a day in the address: the group's arrival, Flights by day open
    expect([...GROUP_BOARDS].filter((k) => !foldsFor(expanded, "/performance/AW", "?day=x").has(k))).toEqual([]);
  });
  it("each row's count or state", () => {
    expect(groupTodayWords([{ net_day: 0.2 }, { net_day: -0.1 }, { net_day: null }])).toBe("1 of 2 airlines ahead after leases");
    expect(groupTodayWords([])).toBe("nothing captured yet");
    expect(growthWords({ profit_captured: true, ready: 3, raise: 2, fix: 1, aircraft: 1 })).toBe("3 ready for a flight · 2 raise fares · 1 fix or reduce · 1 aircraft losing");
    expect(growthWords({ profit_captured: false, ready: 4, raise: 0, fix: 0, aircraft: 0 })).toBe("4 ready for another flight, from the load reports");
    expect(hubsWords([{ main_hub: "JFK", exempt: false, departures: 760, target: 750 }, { main_hub: "LHR", exempt: false, departures: 500, target: 750 },
      { main_hub: "PVG", exempt: true, departures: 100, target: 750 }])).toBe("1 of 2 main hubs at the target");
    expect(hubsWords([])).toBe("no main hub yet");
    expect(profitRowWords({ profit_day: 0.25 })).toBe("+0.25M a day, 7-day average");
    expect(profitRowWords({ profit_day: null })).toBe("needs two nights of cash");
    expect(cashRowWords({ status: "ok", lowest: { at: "2026-10-24T00:00:00Z", balance: 0.4, payment: null } }, 0.5)).toEqual({ text: "lowest 0.40M on Sat, Oct 24", low: true });
    expect(cashRowWords({ status: "missing" }, 0.5)).toEqual({ text: "needs a capture", low: false });
    expect(routeRowWords({ flights: 120, days: 7, routes: [route("A", "B"), route("A", "C")] })).toBe("2 routes · 120 flights, last 7 days");
    expect(routeRowWords({ flights: 1, days: 1, routes: [route("A", "B")] })).toBe("1 route · 1 flight, last day");
    expect(routeRowWords({ flights: 0, days: 7, routes: [] })).toBe("needs a bank statement");
    expect(aircraftRowWords([{ net_day: -0.01 }, { net_day: 0.02 }, { net_day: null }])).toEqual({ text: "3 aircraft", losing: 1 });
    expect(changesRowWords(0)).toBe("none yet");
    expect(changesRowWords(1)).toBe("1 change spotted");
    expect(planRowWords(3)).toBe("3 planned");
  });
  it("the load axis starts at the lowest load rounded down to 5%, never below 40% or above 95%", () => {
    expect(loadAxisFrom([88, 97, 100])).toBe(85);
    expect(loadAxisFrom([90, 99])).toBe(90);
    expect(loadAxisFrom([22, 90])).toBe(40);
    expect(loadAxisFrom([100, 100])).toBe(95);
  });
  it("load against profit: the axis zoomed to the routes, every dot inside it, five top routes and the off-pattern ones labelled, none overlapping", () => {
    const rs = Array.from({ length: 24 }, (_, i) => route("JFK", `D${String(i).padStart(2, "0")}`, {
      economy: 86 + (i % 8) * 2, profit_per_flight: 0.01 + (i % 5) * 0.002, profit_week: 1 - i * 0.02, flights_week: 7 + i,
      mark: i === 20 ? "fix" : i === 21 ? "raise" : i === 22 ? "add" : i === 23 ? "losing" : "hold",
    }));
    const g = scatterLayout(rs);
    if (!g) throw new Error("no layout");
    expect([g.x0, g.x1]).toEqual([85, 100]);
    expect(g.xTicks.map((t) => t.label)).toEqual(["85%", "90%", "95%", "100%"]);
    for (const d of g.dots) expect(d.x).toBeGreaterThanOrEqual(g.pl);
    for (const d of g.dots) expect(d.x).toBeLessThanOrEqual(g.W - g.pr);
    // only the top five and fix, raise, add are candidates; the losing route isn't labelled for its mark alone
    const allowed = new Set(["JFK–D00", "JFK–D01", "JFK–D02", "JFK–D03", "JFK–D04", "JFK–D20", "JFK–D21", "JFK–D22"]);
    expect(g.labels.length).toBeGreaterThan(0);
    for (const l of g.labels) expect(allowed.has(l.text)).toBe(true);
    const box = (l: (typeof g.labels)[number]): [number, number, number, number] => {
      const w = l.text.length * SCATTER_CHAR_W, left = l.anchor === "end" ? l.x - w : l.x;
      return [left, l.y - 9, left + w, l.y + 3];
    };
    const bs = g.labels.map(box);
    bs.forEach((a, i) => bs.forEach((b, j) => {
      if (i < j) expect(a[0] < b[2] && b[0] < a[2] && a[1] < b[3] && b[1] < a[3]).toBe(false);
    }));
    // inside the plot, and the axis title inside the chart
    for (const b of bs) { expect(b[0]).toBeGreaterThanOrEqual(g.pl); expect(b[2]).toBeLessThanOrEqual(g.W - g.pr); expect(b[3]).toBeLessThanOrEqual(g.H - g.pb); }
    expect(g.xTitle.x).toBeLessThanOrEqual(g.W);
    expect(g.xTitle.y).toBeLessThan(g.H);
    expect(g.xTitle.y).toBeGreaterThan(g.H - g.pb + 16);
  });
  it("a label that can't be placed clear of another is dropped, not overlapped", () => {
    // five routes on one spot: at most four places beside it, so at least one label goes
    const rs = Array.from({ length: 5 }, (_, i) => route("JFK", `X${i}`, { economy: 95, profit_per_flight: 0.02, profit_week: 1 - i * 0.1, flights_week: 14 }));
    const g = scatterLayout(rs);
    expect(g?.labels.length).toBeLessThan(5);
    expect(new Set(g?.labels.map((l) => `${l.x}|${l.y}|${l.anchor}`)).size).toBe(g?.labels.length);
  });
});
