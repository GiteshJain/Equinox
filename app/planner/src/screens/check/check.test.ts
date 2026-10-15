// Check's logic (spec docs/specs/2026-10-13-check.md, "Checks"): the one-week check's status (due, coming up, done, and
// due again when a schedule changes) as the board lists it, the cabin fit and the keep rule with their saves, the game
// comparison (the same, different, missing, extra, the game not read) with the fix and the add as one action each, and the
// daily load report's summary (captured, typed by hand, not captured). The planning rules themselves are the library's,
// with their own cases (lib/rules/cases/checks.json, cabins.json, game.json, loadReport.json, growth.json); these run the
// screen's words and saves on the cases' small world.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildRules, cabins, checks, game, loadReport, type DayFlight, type GameFlight, type RulesInput } from "@rules";
import type { Change } from "../../data/save";
import type { RouteRow } from "../routes/model";
import type { TailAircraft } from "../tails/model";
import {
  BOARDS, airlineDay, backupWords, capLine, captureCell, checkSubtitle, captureStatus, daySummary, fixChanges, fixRotations, gameSummary, hubRows, importChanges, keepChange, kWords,
  loadKey, loadsByFlight, logMoveChange, moveDay, noLinkWords, parseDay, patternPill, refitChanges, runsDryWords, shownBoards, soonWords, spendOrder, summaryWords,
  undoKeepChange, upcomingByDay, weekWords,
} from "./model";
import type { CapturedLoad, HandLoads, LegNow } from "./reads";

const base = (JSON.parse(readFileSync(new URL("../../../../../lib/rules/cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
const T0 = "2026-10-12T10:00:00.000001+00:00";
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
const ac = (id: number, reg: string, x: Partial<TailAircraft> = {}): TailAircraft => ({
  id, registration: reg, airline_id: 1, aircraft_type_id: 1, cabin_config_id: 1, base_code: "HUB", status: "active", ordered_on: null, delivery_at: null,
  order_base_code: null, order_config_id: null, order_note: null, checked_on: null, schedule_changed_on: null, maintenance_note: null, retired_on: null,
  extra: {}, updated_at: T0, ...x,
});

describe("the address and the day", () => {
  it("reads the report's day from the address, today without one or with a bad one, and moves it a day at a time", () => {
    expect(parseDay("?day=2026-10-09", "2026-10-13")).toBe("2026-10-09");
    expect(parseDay("", "2026-10-13")).toBe("2026-10-13");
    expect(parseDay("?day=13-10-2026", "2026-10-13")).toBe("2026-10-13");
    expect(moveDay("2026-10-01", -1)).toBe("2026-09-30");
    expect(moveDay("2026-12-31", 1)).toBe("2027-01-01");
  });
});

describe("Capture", () => {
  it("shows today's time, else yesterday's, else a dash; complete, missing some pages or not captured", () => {
    expect(captureCell({ today: "2026-10-13T08:41:12+00:00", yesterday: null })).toEqual({ text: "08:41", dim: false });
    expect(captureCell({ today: null, yesterday: "2026-10-12T21:05:00+00:00" })).toEqual({ text: "yesterday 21:05", dim: true });
    expect(captureCell(undefined)).toEqual({ text: "—", dim: true });
    expect(captureStatus({ missing: [] })).toEqual({ cls: "ok", text: "complete" });
    expect(captureStatus({ missing: ["events", "pnl"] })).toEqual({ cls: "warn", text: "missing Events, Income" });
    expect(captureStatus({ missing: ["loads", "statement", "events", "pnl", "balance"] })).toEqual({ cls: "warn", text: "not captured" });
  });
  it("words the backup's line as the old planner did, leaving out test runs", () => {
    const nd = (d: string) => d;
    expect(backupWords(undefined, nd)).toBeNull();
    expect(backupWords([{ ran_at: "2026-10-13T03:10:00+00:00", kind: "test", ok: true, tables: 1, rows: 1, files: 0, note: null }], nd)?.text).toBe("Backup: no copy yet. The first runs tonight.");
    expect(backupWords([{ ran_at: "2026-10-13T03:10:00+00:00", kind: "nightly", ok: true, tables: 71, rows: 123456, files: 12, note: null }], nd))
      .toEqual({ ok: true, text: "Backup: copied 2026-10-13 03:10 UTC · 71 tables, 123,456 rows, 12 files · restore check passed" });
    expect(backupWords([{ ran_at: "2026-10-13T03:10:00+00:00", kind: "nightly", ok: false, tables: null, rows: null, files: null, note: "R2 refused" }], nd))
      .toEqual({ ok: false, text: "2026-10-13 03:10 UTC · R2 refused" });
  });
});

describe("Growth's words", () => {
  it("words the rotation and hubs first from the moves, the target and the exemptions", () => {
    expect(spendOrder(750, ["Ryanair"])).toBe("each airline rotates its orders: big market → frequency → smaller feeder → repeat · opening a new base counts as a "
      + "big-market move, once the main hub reaches 750 weekly departures (Ryanair exempt)");
  });
  it("draws main hubs towards their target: exempt airlines and those without a main hub left out, the planned part lighter", () => {
    const rows = hubRows([
      { airline_id: 1, code: "TA", name: "Test Air", main_hub: "HUB", exempt: false, target: 750, departures: 600, planned: 210, percent: 80 },
      { airline_id: 2, code: "OA", name: "Other Air", main_hub: "AAA", exempt: true, target: 750, departures: 20, planned: 0, percent: 2.7 },
    ], () => "Test Air");
    expect(rows).toEqual([{ airline_id: 1, name: "Test Air", hub: "HUB", departures: 600, planned: 210, target: 750, width: "80.0%", pend: "20.0%", pct: 80 }]);
  });
  it("writes money and the queues as the old board did", () => {
    expect([kWords(0.1234), kWords(-0.045), weekWords(1.2), weekWords(-0.456)]).toEqual(["+123k", "−45k", "+1.20M", "−0.46M"]);
    expect(runsDryWords(Date.parse("2026-10-14T05:53:00Z"))).toBe("10-14 05:53");
    expect([soonWords(-2), soonWords(0.4), soonWords(21.6)]).toEqual(["now", "in 0 h", "in 22 h"]);
  });
  it("logs an order under the rotation as one growth_log row", () => {
    expect(logMoveChange(1, 2, "freq", "2026-10-13")).toEqual({ table: "growth_log", op: "insert",
      values: { world_id: 1, airline_id: 2, logged_on: "2026-10-13", move: "freq", note: "logged in the planner" } });
  });
});

describe("the aircraft checks", () => {
  const facts = (checked: string | null, changed: string | null) => ({
    aircraft: [{ id: 1, checked_on: checked, schedule_changed_on: changed }, { id: 2, checked_on: null, schedule_changed_on: null }],
    rotations: [{ id: 1, launched_on: "2026-10-01" }, { id: 2, launched_on: "2026-10-01" }, { id: 3, launched_on: "2026-10-09" }],
  });
  it("lists one due, one coming up and one done, and the one coming up by its day", () => {
    const list = checks.oneWeek(rules, facts("2026-10-08", null), "2026-10-12");
    expect(list.map((c) => [c.registration, c.status, c.due])).toEqual([["T-002", "upcoming", "2026-10-16"], ["T-001", "done", "2026-10-08"]]);
    expect(upcomingByDay(list.filter((c) => c.status === "upcoming"))).toEqual([["2026-10-16", ["T-002"]]]);
  });
  it("brings a checked aircraft back when its schedule changes: coming up a week after the change, then due", () => {
    expect(checks.oneWeek(rules, facts("2026-10-08", "2026-10-10"), "2026-10-12").find((c) => c.registration === "T-001")).toMatchObject({ status: "upcoming", due: "2026-10-17" });
    expect(checks.oneWeek(rules, facts("2026-10-08", "2026-10-10"), "2026-10-17").find((c) => c.registration === "T-001")).toMatchObject({ status: "due", days: 0 });
    expect(checks.oneWeek(rules, facts("2026-10-17", "2026-10-10"), "2026-10-17").find((c) => c.registration === "T-001")).toMatchObject({ status: "done" });
  });
  it("the board shows only while the checks are on: gone at 0 or missing, kept by an airline's own number above 0", () => {
    const at = (settings: RulesInput["settings"], airlines = input.airlines) => buildRules({ ...input, settings, airlines });
    const without = Object.fromEntries(Object.entries(input.settings).filter(([k]) => k !== "aircraft_check_after_days"));
    const noChecks = BOARDS.filter((k) => k !== "Aircraft checks");
    expect(shownBoards(rules, [1, 2])).toEqual(BOARDS);
    expect(shownBoards(at({ ...input.settings, aircraft_check_after_days: 0 }), [1, 2])).toEqual(noChecks);
    expect(shownBoards(at(without), [1, 2])).toEqual(noChecks);
    expect(shownBoards(at({ ...input.settings, aircraft_check_after_days: 0 }, [{ id: 1 }, { id: 2, settings: { aircraft_check_after_days: 7 } }]), [1, 2])).toEqual(BOARDS);
    expect(checks.oneWeek(at({ ...input.settings, aircraft_check_after_days: 0 }), facts(null, null), "2026-10-12")).toEqual([]);
    expect(checkSubtitle(BOARDS)).toBe("Last night's capture, aircraft checks, growth signals, Game check and the daily load report.");
    expect(checkSubtitle(noChecks)).toBe("Last night's capture, growth signals, Game check and the daily load report.");
  });
  it("words a route's load pattern on a check: its share of departures at 95%+ and its mark", () => {
    expect(patternPill({ hub: "HUB", dest: "AAA", departures: 14, full: 13, mark: "add" })).toEqual({ cls: "ok", text: "HUB–AAA: 93% of departures 95%+" });
    expect(patternPill({ hub: "HUB", dest: "DDD", departures: 0, full: 0, mark: "hold" })).toEqual({ cls: "mute", text: "HUB–DDD: 0% of departures 95%+" });
  });
});

describe("the cabins", () => {
  const configs = [
    { id: 1, code: "321-LEI", aircraft_type_id: 1, cabin: "Leisure" }, { id: 2, code: "321-STD", aircraft_type_id: 1, cabin: "Standard" },
    { id: 3, code: "321-CMF", aircraft_type_id: 1, cabin: "Comfort" },
  ];
  const facts = (keeps: { aircraft_id: number; cabin: string; decided_on: string | null }[]) => ({
    aircraft: [{ id: 1, cabin_config_id: 1 }, { id: 2, cabin_config_id: 2 }], configs, routes: [{ id: 6, cabin_choice: "Comfort" }],
    markets: [{ id: 1, default_config_id: 2 }, { id: 2, default_config_id: 3 }], keeps,
  });
  it("lists each aircraft whose cabin isn't what most of its flying wants, by share, with the layout to refit to", () => {
    const list = cabins.fit(rules, facts([]));
    expect(list.map((x) => [x.registration, x.have, x.want, x.share, x.target?.code, x.strong])).toEqual([["T-002", "Standard", "Comfort", 100, "321-CMF", true],
      ["T-001", "Leisure", "Standard", 53, "321-STD", false]]);
  });
  it("keeps one as is until its routes call for a different cabin", () => {
    expect(cabins.fit(rules, facts([{ aircraft_id: 1, cabin: "Standard", decided_on: "2026-10-10" }])).find((x) => x.registration === "T-001"))
      .toMatchObject({ kept: true, kept_on: "2026-10-10" });
    expect(cabins.fit(rules, facts([{ aircraft_id: 1, cabin: "Comfort", decided_on: "2026-10-10" }])).find((x) => x.registration === "T-001"))
      .toMatchObject({ kept: false, kept_on: null });
  });
  it("saves a refit (the aircraft's cabin and the loss), a keep and its undo as one action each", () => {
    expect(refitChanges(1, ac(1, "T-001"), { id: 2, code: "321-STD" }, 200000, "2026-10-13")).toEqual([
      { table: "aircraft", op: "update", key: { id: 1 }, base: T0, values: { cabin_config_id: 2 } },
      { table: "spending_log", op: "insert", values: { world_id: 1, airline_id: 1, spent_on: "2026-10-13", amount: 200000, kind: "loss", aircraft_id: null, note: "cabin refit T-001 → 321-STD" } },
    ]);
    expect(keepChange(1, 1, "Standard", "2026-10-13")).toEqual({ table: "aircraft_cabin_keeps", op: "insert", values: { world_id: 1, aircraft_id: 1, cabin: "Standard", decided_on: "2026-10-13" } });
    expect(undoKeepChange({ aircraft_id: 1, cabin: "Standard", updated_at: T0 })).toEqual({ table: "aircraft_cabin_keeps", op: "delete", key: { aircraft_id: 1, cabin: "Standard" }, base: T0 });
  });
});

describe("the game check", () => {
  const g = (no: string, from: string, to: string, dep: string, arr: string, days = "1234567", valid = ""): GameFlight => ({ code: "TA", no, from, to, days, dep, arr, type: "32N", valid });
  const flights = [g("1001", "HUB", "AAA", "06:00", "08:15"), g("1002", "AAA", "HUB", "09:40", "09:55"), g("1003", "HUB", "DDD", "20:00", "04:00", "1357"),
    g("1007", "HUB", "FOC", "10:00", "11:00"), g("2001", "HUB", "CCC", "09:00", "21:00"), g("2002", "CCC", "HUB", "23:00", "04:00")];
  it("compares every number: the same, different, in the planner only, in the game only; and words the airline's line", () => {
    const c = game.compare(rules, 1, flights);
    expect(c.issues.map((i) => [i.no, i.kind, i.text, !!i.fix])).toEqual([
      ["1002", "diff", "Different: departure, arrival", true], ["1003", "diff", "Different: days", true], ["1004", "planner", "In the planner, not in the game", false],
      ["1007", "diff", "Different: route", false], ["2001", "game", "In the game, not in the planner", false], ["2002", "game", "In the game, not in the planner", false],
    ]);
    const cands = game.importCandidates(rules, 1, flights);
    expect(gameSummary(c, cands)).toEqual({ counts: "6 flights in the game · 5 in the planner", pill: { cls: "bad", text: "6 differences" },
      fixAll: "Fix 2 from the game", review: "Review 6 differences and 1 flight to add" });
    expect(gameSummary({ issues: [], in_game: 5, in_planner: 5 }, [])).toEqual({ counts: "5 flights in the game · 5 in the planner", pill: { cls: "ok", text: "everything matches" }, fixAll: null, review: null });
    expect(noLinkWords(["Other Air"])).toBe(" · no link yet for Other Air (add in Reference)");
  });
  it("fixes from the game as one action: only the legs whose times change, from their rows as they are now", () => {
    const c = game.compare(rules, 1, flights);
    const fixable = c.issues.filter((i) => i.fix);
    expect(fixRotations(rules, 1, fixable)).toEqual([1, 2]);
    const now: LegNow[] = input.flight_legs.filter((l) => l.rotation_id === 1 || l.rotation_id === 2)
      .map((l) => ({ id: l.id, rotation_id: l.rotation_id as number, leg_no: l.leg_no as number, days_utc: l.days_utc, dep_utc_min: l.dep_utc_min, block_min: l.block_min, updated_at: T0 }));
    expect(fixChanges(rules, 1, fixable, now)).toEqual([
      { table: "flight_legs", op: "update", key: { id: 2 }, base: T0, values: { dep_utc_min: 520 } },
      { table: "flight_legs", op: "update", key: { id: 3 }, base: T0, values: { days_utc: [1, 3, 5, 7] } },
      { table: "flight_legs", op: "update", key: { id: 4 }, base: T0, values: { days_utc: [1, 2, 4, 6] } },
    ]);
    expect(fixChanges(rules, 1, [c.issues[0] as (typeof c.issues)[number]], now)).toHaveLength(1);
  });
  it("adds a round trip from the game as one action: its route added, a rotation launched today and its two legs on the aircraft chosen", () => {
    const cand = game.importCandidates(rules, 1, flights)[0] as ReturnType<typeof game.importCandidates>[number];
    const route = (id: number, hub: string, dest: string): RouteRow => ({ id, airline_id: 1, hub_code: hub, dest_code: dest, city: dest, country_label: null, distance_km: 700,
      market_id: null, stars: 3, source: "research", removed: false, removed_note: null, city_override: null, distance_override_km: null, market_override_id: null,
      market_cleared: false, stars_override: null, updated_at: T0 });
    const common = {
      worldId: 1, today: "2026-10-13", nowMs: Date.parse("2026-10-13T12:00:00Z"), rand: () => 0.5, rules, airlineId: 1, cand,
      aircraft: [ac(1, "T-001"), ac(2, "T-002"), ac(9, "T-009", { status: "delivered", order_base_code: "HUB", order_config_id: 3 })],
      tails: [ac(1, "T-001"), ac(2, "T-002")], bases: ["HUB", "FOC"], routes: [route(1, "HUB", "AAA")], markets: new Map(), profiles: [],
      airports: new Map([["CCC", { code: "CCC", city: "Delhi", country_code: "IN", country_name: "India", lat: 28.56, lon: 77.1, utc_offset: 5.5, correction: null, world_row: null }],
        ["HUB", { code: "HUB", city: "Hub", country_code: "GB", country_name: "United Kingdom", lat: 51.15, lon: -0.19, utc_offset: 0, correction: null, world_row: null }]]),
    };
    const ch = importChanges({ ...common, tail: { aircraft: ac(1, "T-001") } });
    expect(ch.map((c: Change) => `${c.table} ${c.op}`)).toEqual(["routes insert", "rotations insert", "flight_legs insert", "flight_legs insert"]);
    const legs = ch.filter((c) => c.table === "flight_legs").map((c) => c.values);
    expect(legs).toMatchObject([{ leg_no: 1, flight_no: 2001, origin_code: "HUB", dest_code: "CCC", aircraft_id: 1, dep_utc_min: 540 },
      { leg_no: 2, flight_no: 2002, origin_code: "CCC", dest_code: "HUB", aircraft_id: 1 }]);
    expect(ch[1]?.values).toMatchObject({ world_id: 1, airline_id: 1, launched_on: "2026-10-13", legacy_key: expect.stringMatching(/^f[0-9a-z]+$/) });
    // a new tail typed: an aircraft arrived and waiting becomes a tail first; a registration nobody has is added
    const arrived = importChanges({ ...common, tail: { registration: "t-009" } });
    expect(arrived[0]).toMatchObject({ table: "aircraft", op: "update", key: { id: 9 }, values: { status: "active", base_code: "HUB", cabin_config_id: 3 } });
    expect(arrived[0]?.values).not.toHaveProperty("extra");
    expect(arrived.filter((c) => c.table === "flight_legs").every((c) => c.values?.aircraft_id === 9)).toBe(true);
    const fresh = importChanges({ ...common, tail: { registration: "T-777" } });
    expect(fresh[0]).toMatchObject({ table: "aircraft", op: "insert", as: "new aircraft", values: { registration: "T-777", aircraft_type_id: 1, cabin_config_id: 1, base_code: "HUB" } });
    expect(fresh[0]?.values).not.toHaveProperty("extra");
    expect(fresh.filter((c) => c.table === "flight_legs").map((c) => [c.values?.aircraft_id, c.from?.aircraft_id])).toEqual([[undefined, "new aircraft"], [undefined, "new aircraft"]]);
  });
  it("adds a round trip to an airport none of our flights serves yet with that airport's offset from the tables (found by the side by side: it was taken as UTC)", () => {
    const away = [g("2101", "HUB", "ZZZ", "10:00", "13:00"), g("2102", "ZZZ", "HUB", "14:30", "20:30")];
    const cand = game.importCandidates(rules, 1, away)[0] as ReturnType<typeof game.importCandidates>[number];
    const ch = importChanges({
      worldId: 1, today: "2026-10-13", nowMs: Date.parse("2026-10-13T12:00:00Z"), rand: () => 0.5, rules, airlineId: 1, cand, tail: { aircraft: ac(1, "T-001") },
      aircraft: [ac(1, "T-001")], tails: [ac(1, "T-001")], bases: ["HUB", "FOC"], routes: [], markets: new Map(), profiles: [],
      airports: new Map([["ZZZ", { code: "ZZZ", city: "Away", country_code: "AG", country_name: "Antigua", lat: 17.14, lon: -61.79, utc_offset: -4, correction: null, world_row: null }]]),
    });
    // 10:00 at HUB (UTC) is 600; 13:00 at ZZZ (UTC−4) is 17:00 UTC, 7 hours; back at 14:30 there (18:30 UTC), landing 20:30 UTC: 2 hours
    expect(ch.filter((c) => c.table === "flight_legs").map((c) => [c.values?.dep_utc_min, c.values?.block_min])).toEqual([[600, 420], [1110, 120]]);
  });
});

describe("the daily load report", () => {
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
