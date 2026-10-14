// Review's logic (spec docs/specs/2026-10-14-review.md, "Checks"): the cards' wording when a figure is missing, the
// profit chart's intervals (the last 14), the load paste reader (the old parseLoadPaste, with the old planner test's
// case), the typed loads and the saves (each the payload or the rows the old planner writes), the fare plan's words and
// its add and drop, the route profit's filters, and the plan card's service check as Tails shows it. Every money figure
// itself is the database's (database/tests/review_test.sql); these run the screen's words and saves.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildRules, type RulesInput } from "@rules";
import { cardLegs, cardServiceIssues, withRoutes, type PlanLegRow } from "../tails/model";
import type { RouteRow as TableRoute } from "../routes/model";
import {
  CHART_INTERVALS, barLayout, barTip, capturedLine, cardWords, cashChanges, chartIntervals, costParts, dayStatus, dd, farePlanAdd, farePlanDrop, fcDay, fcWhat, kk,
  markCounts, nextOrderWords, nightlyLog, offersFarePlan, parseLoadPaste, pasteSaves, planWords, safeWords, sg, shownRoutes, sparkBars, typedLoads, typedSave,
  underList, type Card, type CashToday, type PlanRow, type ProfitDay, type RouteRow,
} from "./model";

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

const today = (x: Partial<CashToday> = {}): CashToday => ({
  day: "2026-10-14", shown_cash: 10, shown_fixed: 1.25, stored_cash: 10, stored_fixed: 1.25, captured_cash: 10, captured_fixed: 1.25, entry: null, ...x,
});

describe("cash and fixed costs for today: the rows the old planner's adapter writes", () => {
  const now = "2026-10-14T12:00:00.000Z";
  it("nothing when the figures are the ones the tables hold", () => {
    expect(cashChanges(1, [{ airline_id: 5, today: today(), cash: "10", fixed: "1.25" }], now)).toEqual([]);
    expect(cashChanges(1, [{ airline_id: 5, today: today(), cash: "", fixed: "" }], now)).toEqual([]);
  });
  it("a typed figure that differs from the capture's gets a row, in AS$; the other stays empty while it agrees", () => {
    expect(cashChanges(1, [{ airline_id: 5, today: today(), cash: "12.34", fixed: "1.25" }], now)).toEqual([
      { table: "cash_entries", op: "insert", values: { world_id: 1, airline_id: 5, day: "2026-10-14", cash: 12340000, fixed_next7: null, entered_at: now } }]);
    expect(cashChanges(1, [{ airline_id: 5, today: today({ captured_cash: null, captured_fixed: null, stored_cash: null, stored_fixed: null, shown_cash: null, shown_fixed: null }),
      cash: "1,234.5", fixed: "2" }], now)).toEqual([
      { table: "cash_entries", op: "insert", values: { world_id: 1, airline_id: 5, day: "2026-10-14", cash: 1234500000, fixed_next7: 2000000, entered_at: now } }]);
  });
  it("a typed row changed, or taken away once both agree with the capture again", () => {
    const entry = { cash: 12340000, fixed_next7: null, updated_at: "2026-10-14T09:00:00.5+00:00" };
    const t = today({ stored_cash: 12.34, entry });
    expect(cashChanges(1, [{ airline_id: 5, today: t, cash: "12.5", fixed: "" }], now)).toEqual([
      { table: "cash_entries", op: "update", key: { airline_id: 5, day: "2026-10-14" }, base: entry.updated_at, values: { cash: 12500000, fixed_next7: null, entered_at: now } }]);
    expect(cashChanges(1, [{ airline_id: 5, today: t, cash: "10", fixed: "" }], now)).toEqual([
      { table: "cash_entries", op: "delete", key: { airline_id: 5, day: "2026-10-14" }, base: entry.updated_at }]);
  });
  it("the nightly log: every reported day, newest first, a dash where an airline has none", () => {
    const rows = nightlyLog({ today: "2026-10-14", airlines: [
      { airline_id: 1, code: "A", name: "Pan American", days: [{ day: "2026-10-12", cash: 5, fixed: 0.7 }, { day: "2026-10-14", cash: 9.125, fixed: null }], today: today() },
      { airline_id: 2, code: "B", name: "Kingfisher", days: [{ day: "2026-10-13", cash: 3, fixed: 1 }], today: today() }] });
    expect(rows).toEqual([
      { day: "2026-10-14", cells: [{ cash: "9.13", fixed: null }, null] },
      { day: "2026-10-13", cells: [null, { cash: "3.00", fixed: "1.00" }] },
      { day: "2026-10-12", cells: [{ cash: "5.00", fixed: "0.70" }, null] }]);
  });
});

describe("loads by hand", () => {
  const codes = new Map([["KF", "Kingfisher"], ["AW", "Pan American"]]);
  const dm = "14.10.";
  // the old planner test's paste (tests/planner_test.py, manual_loads): one flight under 95% and one full
  const paste = [`KF 1008\tVT-AAE\tAMS\t${dm} 02:45 LT\tDEL\t${dm} 10:00 LT\t500\t100 / 150\t900\t10 / 12\t--\t--\t--\t--`,
    `KF 1009\tVT-AAE\tDEL\t${dm} 12:00 LT\tAMS\t${dm} 18:00 LT\t500\t150 / 150\t900\t12 / 12\t--\t--\t--\t--`].join("\n");
  it("reads the game's load table: economy, business and first together, without cargo", () => {
    const p = parseLoadPaste(paste, codes, "2026-10-14");
    expect(p.map((x) => [x.key, x.date, x.dep, x.from, x.to, x.tail, x.pax, x.seats, x.pct])).toEqual([
      ["Kingfisher|1008", "2026-10-14", "02:45", "AMS", "DEL", "VT-AAE", 110, 162, 68], ["Kingfisher|1009", "2026-10-14", "12:00", "DEL", "AMS", "VT-AAE", 162, 162, 100]]);
  });
  it("skips what isn't one of ours or isn't a flight; numbers with commas; a date far ahead is last year's; cargo left out", () => {
    const text = [`ZZ 1\tX\tAAA\t${dm} 01:00\tBBB\t-\t1\t1 / 2`, "AW 0101\tN1\tJFK\tnot a date\tLHR\t-\t1\t1 / 2",
      `AW 101\tN1\tJFK\t31.12. 23:50 LT\tLHR\t01.01. 06:00 LT\t900\t1,200 / 1,500\t--\t--\t--\t--\t70\t5 / 10`].join("\n");
    const p = parseLoadPaste(text, codes, "2026-10-14");
    expect(p.map((x) => [x.key, x.date, x.pax, x.seats, x.pct])).toEqual([["Pan American|101", "2025-12-31", 1200, 1500, 80]]);
    expect(parseLoadPaste("nothing here", codes, "2026-10-14")).toEqual([]);
  });
  it("the paste saved: each flight under 95% set, each full one cleared, the ticked days complete, one call per month", () => {
    const p = parseLoadPaste(paste, codes, "2026-10-14");
    expect(pasteSaves(p, ["2026-10-14"], 123)).toEqual([{ p_month: "2026-10", p_days: { "2026-10-14": { set: { "Kingfisher|1008": 68 }, del: ["Kingfisher|1009"], done: true, savedAt: 123 } } }]);
    expect(pasteSaves(p, [], 123)).toEqual([{ p_month: "2026-10", p_days: { "2026-10-14": { set: { "Kingfisher|1008": 68 }, del: ["Kingfisher|1009"] } } }]);
  });
  it("typed boxes: number then load, a prefix allowed, each load 0 to 94; a flight that doesn't fly that day is named", () => {
    const valid = new Set(["Pan American|1001", "Pan American|1005"]);
    const t = typedLoads([{ airline: "Pan American", text: "AW1001 93%, 1005 99, 1777 -4" }], valid);
    expect(t).toEqual({ f: { "Pan American|1001": 93, "Pan American|1005": 94, "Pan American|1777": 4 }, unknown: ["Pan 1777"] });
    expect(typedSave("2026-10-14", t.f, 99)).toEqual({ p_month: "2026-10", p_days: { "2026-10-14": { f: t.f, done: true, savedAt: 99 } } });
  });
  it("a day's boxes and status from the day as the planner holds it", () => {
    const d = { done: true, source: "capture", f: { "Pan American|1001": 93, "Pan American|1005": 61, "Pan American|1009": 97, "Kingfisher|1": 50 } };
    expect(underList(d, "Pan American")).toBe("1005 61, 1001 93");
    expect([dayStatus(d), dayStatus({ done: true, f: {} }), dayStatus(null)]).toEqual(["captured", "entered by hand", "nothing yet"]);
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
