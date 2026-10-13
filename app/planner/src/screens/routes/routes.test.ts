// Routes' logic (spec docs/specs/2026-10-13-routes.md §4): local and UTC times both ways (across midnight, and the
// return's next day), the list's filters and sorts as the old planner's routeRows, the address that keeps them, an
// offset change keeping the local times, and each action's save: a frequency added, changed and removed, a route added,
// edited and removed. The rules themselves are the planning library's, with their own cases (lib/rules/cases/
// frequency.json, banks.json, service.json); these run the screen's joins on the cases' small world.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildRules, type RulesInput } from "@rules";
import {
  addFrequencyChanges, addRouteChanges, alt, changeFrequency, deleteFrequencyChanges, disp, editRouteChange, filtersQuery, freqOf, fromInput, listRows,
  liveRules, marketChips, moveWords, newLegacyKey, offsetChanges, parseFilters, parseOffset, removeRoutesChanges, routeOf, summaryOf, tailsWords,
  type AircraftRow, type AirportInfo, type Filters, type LegRow, type MarketRow, type RotationRow, type Route, type RouteRow, type RouteSummary,
} from "./model";

const base = (JSON.parse(readFileSync(new URL("../../../../../lib/rules/cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
const T0 = "2026-10-12T10:00:00.000001+00:00";
const markets = new Map<number, MarketRow>([
  [1, { id: 1, airline_id: 1, name: "Europe", default_type_id: 1, default_config_id: null, fare_y_pct: 100, fare_j_pct: null }],
  [2, { id: 2, airline_id: 1, name: "Long haul", default_type_id: 1, default_config_id: null, fare_y_pct: 110, fare_j_pct: 120 }],
]);
const routeRow = (id: number, hub: string, dest: string, km: number, x: Partial<RouteRow> = {}): RouteRow => ({
  id, airline_id: 1, hub_code: hub, dest_code: dest, city: dest.toLowerCase(), country_label: null, distance_km: km, market_id: 1, stars: 3, source: "research",
  removed: false, removed_note: null, city_override: null, distance_override_km: null, market_override_id: null, market_cleared: false, stars_override: null,
  updated_at: T0, ...x,
});
const ac: AircraftRow = { id: 1, registration: "T-001", airline_id: 1, aircraft_type_id: 1, status: "active", schedule_changed_on: "2026-10-01", tails_index: 0, updated_at: T0 };
const ac2: AircraftRow = { ...ac, id: 2, registration: "T-002", tails_index: 1 };
const aircraft = new Map([[1, ac], [2, ac2]]);
const byReg = new Map([["T-001", ac], ["T-002", ac2]]);
const rot = (id: number, routeId: number): RotationRow => ({ id, airline_id: 1, route_id: routeId, legacy_key: "k" + id, service_code: "S1", fare_pct: 100, launched_on: "2026-10-01", note: null, extra: {}, updated_at: T0 });
const leg = (id: number, rotation: number, n: 1 | 2, from: string, to: string, days: number[], dep: number | null, blockMin: number | null, x: Partial<LegRow> = {}): LegRow => ({
  id, airline_id: 1, rotation_id: rotation, leg_no: n, flight_no: 1000 + id, origin_code: from, dest_code: to, aircraft_id: 1, days_utc: days, dep_utc_min: dep, block_min: blockMin, updated_at: T0, ...x,
});

// HUB (UTC) to CCC (+5:30): HUB 22:00 Mon, Wed, Fri lands CCC 11:30 the next day; the 13:00 return leaves that day
const routes: Route[] = [routeRow(3, "HUB", "CCC", 6720, { market_id: 2 }), routeRow(1, "HUB", "AAA", 700), routeRow(9, "FOC", "AAA", 840, { stars: 5 }),
  routeRow(8, "HUB", "FOC", 280, { stars: 4 }), routeRow(10, "HUB", "BBB", 5600, { stars: null, market_id: null })].map((r) => routeOf(r, markets));
const legs: LegRow[] = [leg(1, 1, 1, "HUB", "CCC", [1, 3, 5], 1320, 480), leg(2, 1, 2, "CCC", "HUB", [2, 4, 6], 450, 540)];
const rules = liveRules(buildRules(base), 1, routes, [rot(1, 3)], legs);
const ccc = routes[0] as Route;
const f = freqOf(rules, ccc, rot(1, 3), legs, aircraft, markets);
const ctx = { mode: "local" as const, today: "2026-10-13", aircraft, byRegistration: byReg, markets, route: ccc };

describe("local and UTC times, both ways", () => {
  it("shows stored UTC legs in local time, across midnight, with the return's next day", () => {
    expect(f.local).toMatchObject({ days: [1, 3, 5], dep_hub: 1320, arr_dest: 690, dep_dest: 780, arr_hub: 990 });
    expect(f.view.out).toMatchObject({ dep: 1320, arr: 690, arr_day: 1, block: 480, est: false });
    expect(f.view.back).toMatchObject({ dep: 780, dep_day: 1, arr: 990, arr_day: 1, block: 540 });
  });
  it("words a time local or UTC, with the other shown small", () => {
    expect(disp(690, 330, "local")).toBe("11:30");
    expect(disp(690, 330, "utc")).toBe("06:00");
    expect(alt(690, 330, "local")).toBe("06:00Z");
    expect(alt(690, 330, "utc")).toBe("11:30 local");
    expect(disp(60, 330, "utc")).toBe("19:30");   // 01:00 at +5:30 is 19:30 UTC the day before
  });
  it("reads a typed time: local as typed, UTC moved to local; 0630 is 06:30; a bad one is refused", () => {
    expect(fromInput("0630", 330, "local")).toBe(390);
    expect(fromInput("19:30", 330, "utc")).toBe(60);
    expect(fromInput("", 0, "local")).toBeNull();
    expect(fromInput("25:00", 0, "local")).toBe("bad");
    expect(fromInput("noon", 0, "local")).toBe("bad");
  });
  it("a departure typed in UTC is stored as that UTC time", () => {
    const res = changeFrequency(rules, f, "depHub", "21:00", { ...ctx, mode: "utc" });
    expect(res).toEqual({ changes: [
      { table: "flight_legs", op: "update", key: { id: 1 }, base: T0, values: { dep_utc_min: 1260, block_min: 540 } },
      { table: "aircraft", op: "update", key: { id: 1 }, base: T0, values: { schedule_changed_on: "2026-10-13" } },
    ] });
  });
  it("the return's day: a return typed earlier than the outbound lands leaves the next day", () => {
    // the return at 10:00 CCC (before the 11:30 landing): the day after the landing, so two days after the outbound
    const res = changeFrequency(rules, f, "depDest", "10:00", ctx);
    expect("changes" in res && res.changes[0]).toEqual({ table: "flight_legs", op: "update", key: { id: 2 }, base: T0,
      values: { days_utc: [3, 5, 7], dep_utc_min: 270, block_min: 720 } });
  });
});

describe("the list: the old planner's routeRows", () => {
  const summaries = new Map<number, RouteSummary>([[3, summaryOf([f])]]);
  const loads = new Map([[3, { departures: 6, sum: 540, full: 3, under_95: 3, under_85: 0, under_70: 0, days: 3 }]]);
  const lc = { focus: ["FOC"], hubs: ["HUB"], summaries, loads };
  const F = (x: Partial<Filters> = {}): Filters => ({ ...parseFilters(""), ...x });
  const keys = (rows: { route: Route }[]) => rows.map((r) => `${r.route.hub}-${r.route.dest}`);

  it("filters by the bases picked, stars, markets, distance, search and active only", () => {
    expect(keys(listRows(routes, F(), ["HUB"], lc))).toEqual(["HUB-FOC", "HUB-AAA", "HUB-BBB", "HUB-CCC"]);
    expect(keys(listRows(routes, F(), [], lc))).toHaveLength(5);
    expect(keys(listRows(routes, F({ stars: [4, 5] }), [], lc))).toEqual(["FOC-AAA", "HUB-FOC"]);
    expect(keys(listRows(routes, F({ markets: ["Long haul"] }), [], lc))).toEqual(["HUB-CCC"]);
    expect(keys(listRows(routes, F({ markets: [""] }), [], lc))).toEqual(["HUB-BBB"]);
    expect(keys(listRows(routes, F({ kmFrom: "500", kmTo: "1000" }), [], lc))).toEqual(["FOC-AAA", "HUB-AAA"]);
    expect(keys(listRows(routes, F({ q: "cc" }), [], lc))).toEqual(["HUB-CCC"]);
    expect(keys(listRows(routes, F({ active: true }), [], lc))).toEqual(["HUB-CCC"]);
  });
  it("a focus city picked lists its routes and the hub's routes to it, trunks first; trunks only", () => {
    expect(keys(listRows(routes, F(), ["FOC"], lc))).toEqual(["HUB-FOC", "FOC-AAA"]);
    expect(keys(listRows(routes, F({ trunks: true }), ["FOC"], lc))).toEqual(["HUB-FOC"]);
  });
  it("sorts by stars then distance, distance either way, destination, and load (unflown last) then stars", () => {
    expect(keys(listRows(routes, F(), [], lc))).toEqual(["FOC-AAA", "HUB-FOC", "HUB-AAA", "HUB-BBB", "HUB-CCC"]);
    expect(keys(listRows(routes, F({ sort: "distUp" }), [], lc))).toEqual(["HUB-FOC", "HUB-AAA", "FOC-AAA", "HUB-BBB", "HUB-CCC"]);
    expect(keys(listRows(routes, F({ sort: "distDown" }), [], lc))).toEqual(["HUB-CCC", "HUB-BBB", "FOC-AAA", "HUB-AAA", "HUB-FOC"]);
    expect(keys(listRows(routes, F({ sort: "dest" }), [], lc))).toEqual(["HUB-AAA", "FOC-AAA", "HUB-BBB", "HUB-CCC", "HUB-FOC"]);
    expect(keys(listRows(routes, F({ sort: "load" }), [], lc))).toEqual(["HUB-CCC", "FOC-AAA", "HUB-FOC", "HUB-AAA", "HUB-BBB"]);
  });
  it("a route without stars counts 3, its overrides win, a cleared market is none", () => {
    expect(routes.find((r) => r.id === 10)?.stars).toBe(3);
    const r = routeOf(routeRow(4, "HUB", "DDD", 1400, { stars_override: 5, city_override: "Bombay", distance_override_km: 1500, market_cleared: true }), markets);
    expect(r).toMatchObject({ stars: 5, city: "Bombay", dist: 1500, market: "", market_id: null });
    expect(marketChips(routes)).toEqual(["", "Europe", "Long haul"]);
  });
  it("keeps the filters in the address, and reads them back", () => {
    const f1 = F({ airline: "TA", bases: ["HUB", "FOC"], stars: [5, 4], markets: ["Long haul", "Europe & more"], kmFrom: "500", kmTo: "", active: true, sort: "load", q: "chi" });
    const q = filtersQuery(f1);
    expect(q).toBe("?airline=TA&bases=HUB,FOC&stars=5,4&markets=Long+haul,Europe+%26+more&km=500-&active=1&sort=load&q=chi");
    expect(parseFilters(q)).toEqual({ ...f1, markets: ["Long haul", "Europe & more"] });
    expect(parseFilters("?bases=all").bases).toEqual([]);
    expect(parseFilters("").bases).toBeNull();
    expect(filtersQuery(F())).toBe("");
  });
  it("words a row's tails and its summary", () => {
    expect(tailsWords(["A", "B", "C", "D", "E"])).toBe("A, B, C +2");
    expect(summaryOf([f])).toMatchObject({ count: 1, rtWk: 3, tails: ["T-001"], numbers: "1001–1002", allOk: true });
  });
});

describe("an offset change keeps the local times", () => {
  const info: AirportInfo = { code: "CCC", city: null, country_code: null, country_name: null, lat: null, lon: null, utc_offset: 5.5, correction: null, world_row: null };
  it("re-times every leg touching the airport, sets the world's correction, and lists what moves", () => {
    const plan = offsetChanges(rules, 1, info, 6, { rotations: [{ rotation_id: 1, ends: f.ends, leg1: legs[0], leg2: legs[1] }], planLegs: [
      { id: 7, plan_card_id: 1, position: 1, flight_no: 9001, origin_code: "CCC", dest_code: "HUB", dep_utc_min: 450, updated_at: T0 },
      { id: 8, plan_card_id: 1, position: 2, flight_no: 9002, origin_code: "HUB", dest_code: "CCC", dep_utc_min: 600, updated_at: T0 },
    ] });
    expect(plan.changes).toEqual([
      { table: "world_airports", op: "insert", key: { world_id: 1, airport_code: "CCC" }, values: { utc_offset_override: 6 } },
      // the outbound still lands 11:30 local: 30 min sooner in UTC; the return still leaves 13:00 local: 30 min earlier in UTC
      { table: "flight_legs", op: "update", key: { id: 1 }, base: T0, values: { block_min: 450 } },
      { table: "flight_legs", op: "update", key: { id: 2 }, base: T0, values: { dep_utc_min: 420, block_min: 570 } },
      { table: "plan_card_legs", op: "update", key: { id: 7 }, base: T0, values: { dep_utc_min: 420 } },
    ]);
    // read back with the new offset, the local times are the same
    const after = liveRules(buildRules({ ...base, airports: base.airports.map((a) => (a.code === "CCC" ? { ...a, utc_offset: 6 } : a)) }), 1, routes, [rot(1, 3)],
      [{ ...legs[0], block_min: 450 } as LegRow, { ...legs[1], dep_utc_min: 420, block_min: 570 } as LegRow]);
    expect(freqOf(after, ccc, rot(1, 3), after.legs.map((l) => ({ ...l, updated_at: T0 })) as LegRow[], aircraft, markets).local).toEqual(f.local);
    expect(moveWords(plan.moves[1] as never, "TA")).toBe("TA 1002 CCC–HUB: leaves 07:00 UTC instead of 07:30, block 9:30 instead of 9:00");
  });
  it("updates the world's row when it has one; an empty box clears the correction", () => {
    const plan = offsetChanges(rules, 1, { ...info, correction: 6, world_row: { updated_at: T0 } }, null, { rotations: [], planLegs: [] });
    expect(plan.changes).toEqual([{ table: "world_airports", op: "update", key: { world_id: 1, airport_code: "CCC" }, base: T0, values: { utc_offset_override: null } }]);
    expect(parseOffset("")).toBeNull();
    expect(parseOffset("-5")).toBe(-5);
    expect(parseOffset("five")).toBe("bad");
  });
});

describe("each action's save, one planner_save() call", () => {
  it("adds a frequency: a rotation and its two legs as one action, the legs taking the rotation's new id", () => {
    expect(newLegacyKey(() => 0.123456789)).toMatch(/^[0-9a-z]{7}$/);
    expect(addFrequencyChanges(1, ccc, { out: 1003, back: 1004 }, "S4", 110, "2026-10-13", "abc1234")).toEqual([
      { table: "rotations", op: "insert", as: "rotation", values: { world_id: 1, airline_id: 1, route_id: 3, legacy_key: "abc1234", service_code: "S4", fare_pct: 110, launched_on: "2026-10-13" } },
      { table: "flight_legs", op: "insert", from: { rotation_id: "rotation" }, values: { world_id: 1, airline_id: 1, leg_no: 1, flight_no: 1003, origin_code: "HUB", dest_code: "CCC",
        aircraft_id: null, days_utc: [1, 2, 3, 4, 5, 6, 7], dep_utc_min: null, block_min: null } },
      { table: "flight_legs", op: "insert", from: { rotation_id: "rotation" }, values: { world_id: 1, airline_id: 1, leg_no: 2, flight_no: 1004, origin_code: "CCC", dest_code: "HUB",
        aircraft_id: null, days_utc: [1, 2, 3, 4, 5, 6, 7], dep_utc_min: null, block_min: null } },
    ]);
  });
  it("changes its days on both legs (the return a day later), and stamps the aircraft's schedule change", () => {
    expect(changeFrequency(rules, f, "days", "15", ctx)).toEqual({ changes: [
      { table: "flight_legs", op: "update", key: { id: 1 }, base: T0, values: { days_utc: [1, 5] } },
      { table: "flight_legs", op: "update", key: { id: 2 }, base: T0, values: { days_utc: [2, 6] } },
      { table: "aircraft", op: "update", key: { id: 1 }, base: T0, values: { schedule_changed_on: "2026-10-13" } },
    ] });
    expect(changeFrequency(rules, f, "days", "531", ctx)).toEqual({ changes: [] });
  });
  it("moves it to another aircraft: both legs, and both aircraft's schedule change", () => {
    expect(changeFrequency(rules, f, "tail", "T-002", ctx)).toEqual({ changes: [
      { table: "flight_legs", op: "update", key: { id: 1 }, base: T0, values: { aircraft_id: 2 } },
      { table: "flight_legs", op: "update", key: { id: 2 }, base: T0, values: { aircraft_id: 2 } },
      { table: "aircraft", op: "update", key: { id: 1 }, base: T0, values: { schedule_changed_on: "2026-10-13" } },
      { table: "aircraft", op: "update", key: { id: 2 }, base: T0, values: { schedule_changed_on: "2026-10-13" } },
    ] });
    expect(changeFrequency(rules, f, "tail", "X-999", ctx)).toEqual({ error: "No aircraft X-999" });
  });
  it("clears an arrival: no block stored, the estimate shown; a number, the service, the notes and the load typed", () => {
    expect(changeFrequency(rules, f, "arrDest", "", ctx)).toMatchObject({ changes: [{ table: "flight_legs", key: { id: 1 }, values: { block_min: null } }, { table: "aircraft" }] });
    expect(changeFrequency(rules, f, "noBack", "1010", ctx)).toMatchObject({ changes: [{ table: "flight_legs", key: { id: 2 }, values: { flight_no: 1010 } }, { table: "aircraft" }] });
    expect(changeFrequency(rules, f, "service", "S3", ctx)).toEqual({ changes: [{ table: "rotations", op: "update", key: { id: 1 }, base: T0, values: { service_code: "S3" } }] });
    expect(changeFrequency(rules, f, "notes", "first one", ctx)).toEqual({ changes: [{ table: "rotations", op: "update", key: { id: 1 }, base: T0, values: { note: "first one" } }] });
    expect(changeFrequency(rules, f, "slfOut", "84", ctx)).toEqual({ changes: [{ table: "rotations", op: "update", key: { id: 1 }, base: T0, values: { extra: { slfOut: "84" } } }] });
    expect(changeFrequency(rules, f, "depHub", "7pm", ctx)).toEqual({ error: "Time as hh:mm" });
  });
  it("removes it: its legs, then its rotation, as one action, and stamps the aircraft", () => {
    expect(deleteFrequencyChanges(f, "2026-10-13")).toEqual([
      { table: "flight_legs", op: "delete", key: { id: 1 }, base: T0 },
      { table: "flight_legs", op: "delete", key: { id: 2 }, base: T0 },
      { table: "rotations", op: "delete", key: { id: 1 }, base: T0 },
      { table: "aircraft", op: "update", key: { id: 1 }, base: T0, values: { schedule_changed_on: "2026-10-13" } },
    ]);
  });
  it("adds a route as added, brings a removed one back with its edits cleared, and adds an airport the list lacks", () => {
    const v = { city: "Delhi", country: "India", km: 6720, marketId: 2 };
    expect(addRouteChanges(1, 1, "HUB", "DEL", v, null, false)).toEqual([{ table: "routes", op: "insert", values: {
      world_id: 1, airline_id: 1, hub_code: "HUB", dest_code: "DEL", city: "Delhi", country_label: "India", distance_km: 6720, market_id: 2, stars: 3, source: "added" } }]);
    const removed = routeRow(12, "HUB", "DEL", 6000, { removed: true, stars_override: 2 });
    expect(addRouteChanges(1, 1, "HUB", "DEL", v, removed, true)).toEqual([
      { table: "airports", op: "insert", values: { code: "DEL", city: "Delhi" } },
      { table: "routes", op: "update", key: { id: 12 }, base: T0, values: { city: "Delhi", country_label: "India", distance_km: 6720, market_id: 2, stars: 3, source: "added",
        removed: false, removed_note: null, city_override: null, distance_override_km: null, market_override_id: null, market_cleared: false, stars_override: null } },
    ]);
  });
  it("edits a route into its override columns; a market cleared; removes routes, never deleting them", () => {
    const one = (values: object) => ({ changes: [{ table: "routes", op: "update", key: { id: 3 }, base: T0, values }] });
    expect(editRouteChange(ccc, "stars", "5", [...markets.values()])).toEqual(one({ stars_override: 5 }));
    expect(editRouteChange(ccc, "market", "Europe", [...markets.values()])).toEqual(one({ market_override_id: 1, market_cleared: false }));
    expect(editRouteChange(ccc, "market", "", [...markets.values()])).toEqual(one({ market_override_id: null, market_cleared: true }));
    expect(editRouteChange(ccc, "dist", "6800", [...markets.values()])).toEqual(one({ distance_override_km: 6800 }));
    expect(editRouteChange(ccc, "city", "New Delhi", [...markets.values()])).toEqual(one({ city_override: "New Delhi" }));
    expect(editRouteChange(ccc, "stars", "9", [...markets.values()])).toEqual({ error: "Stars are 1 to 5" });
    expect(removeRoutesChanges([ccc], "removed in Routes on 2026-10-13")).toEqual([
      { table: "routes", op: "update", key: { id: 3 }, base: T0, values: { removed: true, removed_note: "removed in Routes on 2026-10-13" } }]);
  });
});
