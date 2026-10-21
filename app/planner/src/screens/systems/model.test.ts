// Systems' logic (spec docs/specs/2026-10-20-today-performance-systems.md; Check's and Review's tests for these boards
// until 20 Oct, specs docs/specs/2026-10-13-check.md and docs/specs/2026-10-14-review.md): the capture board's cells and
// the backup's line; the one-week check's status (due, coming up, done, and due again when a schedule changes) as the
// board lists it, and the board shown only while the checks are on; the cabin fit and the keep rule with their saves;
// and Manual entry: cash and fixed costs (the rows the old planner's adapter writes), the nightly log, the load paste
// reader (the old parseLoadPaste, with the old planner test's case) and the typed loads with their rows. The planning
// rules themselves are the library's, with their own cases (lib/rules/cases/checks.json, cabins.json); these run the
// screen's words and saves on the cases' small world. The Systems board's own marks are systems.test.ts's.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildRules, cabins, checks, type RulesInput } from "@rules";
import type { TailAircraft } from "../tails/model";
import {
  BOARDS, backupWords, captureCell, captureStatus, cashChanges, dayStatus, keepChange, loadsChanges, mergeDay, nightlyLog, parseLoadPaste, pasteSaves, patternPill,
  refitChanges, shownBoards, typedLoads, typedSave, underList, undoKeepChange, upcomingByDay, type CashToday,
} from "./model";

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
    expect(BOARDS).toEqual(["Capture", "Manual entry", "Cabins", "Aircraft checks"]);
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
  it("the paste saved: each flight under 95% set, each full one cleared, the ticked days complete", () => {
    const p = parseLoadPaste(paste, codes, "2026-10-14");
    expect(pasteSaves(p, ["2026-10-14"], 123)).toEqual({ "2026-10-14": { set: { "Kingfisher|1008": 68 }, del: ["Kingfisher|1009"], done: true, savedAt: 123 } });
    expect(pasteSaves(p, [], 123)).toEqual({ "2026-10-14": { set: { "Kingfisher|1008": 68 }, del: ["Kingfisher|1009"] } });
  });
  it("typed boxes: number then load, a prefix allowed, each load 0 to 94; a flight that doesn't fly that day is named", () => {
    const valid = new Set(["Pan American|1001", "Pan American|1005"]);
    const t = typedLoads([{ airline: "Pan American", text: "AW1001 93%, 1005 99, 1777 -4" }], valid);
    expect(t).toEqual({ f: { "Pan American|1001": 93, "Pan American|1005": 94, "Pan American|1777": 4 }, unknown: ["Pan 1777"] });
    expect(typedSave("2026-10-14", t.f, 99)).toEqual({ "2026-10-14": { f: t.f, done: true, savedAt: 99 } });
  });
  // the rows a save writes, as the old save_loads() wrote them (private.loads_mirror_days), since the clean-up through
  // planner_save() (build pull request 14)
  const ids = new Map([["Pan American", 1], ["Kingfisher", 2]]);
  const AT = "2026-10-14T12:00:00.000Z";
  const held = { done: true, source: "capture", savedAt: 50, f: { "Pan American|1001": 93, "Pan American|1009": 97 },
    entries: [{ airline_id: 1, flight_no: 1001, eco_pct: 93, updated_at: "2026-10-14T01:00:00+00:00" }],
    flags: { done: true, saved_at_ms: 50, updated_at: "2026-10-14T02:00:00+00:00" } };
  it("a day merged as save_loads() merged it: f replaces the day's flights, or set and del change single ones", () => {
    expect(mergeDay(held, { f: { "Pan American|1005": 61 }, done: true, savedAt: 99 })).toEqual({ f: { "Pan American|1005": 61 }, done: true, savedAt: 99 });
    expect(mergeDay(held, { set: { "Pan American|1005": 61 }, del: ["Pan American|1009"] })).toEqual({ f: { "Pan American|1001": 93, "Pan American|1005": 61 }, done: true, savedAt: 50 });
    expect(mergeDay(null, { set: { "Kingfisher|1": 70 } })).toEqual({ f: { "Kingfisher|1": 70 }, done: false });
  });
  it("typed: a row for each flight that differs (null where it's cleared), the day's row when its mark or saved time changes", () => {
    const ch = loadsChanges(7, "2026-10-14", held, { f: { "Pan American|1001": 90, "Pan American|1005": 61 }, done: true, savedAt: 99 }, ids, AT);
    expect(ch).toEqual([
      { table: "load_entries", op: "update", key: { airline_id: 1, game_date: "2026-10-14", flight_no: 1001 }, base: "2026-10-14T01:00:00+00:00", values: { eco_pct: 90, entered_at: AT } },
      { table: "load_entries", op: "insert", values: { world_id: 7, airline_id: 1, game_date: "2026-10-14", flight_no: 1005, eco_pct: 61, entered_at: AT } },
      { table: "load_entries", op: "insert", values: { world_id: 7, airline_id: 1, game_date: "2026-10-14", flight_no: 1009, eco_pct: null, entered_at: AT } },
      { table: "load_days", op: "update", key: { world_id: 7, game_date: "2026-10-14" }, base: "2026-10-14T02:00:00+00:00", values: { done: true, saved_at_ms: 99, entered_at: AT } },
    ]);
  });
  it("a day with nothing yet: its rows added; nothing written when nothing differs; a flight of an airline not ours left out", () => {
    expect(loadsChanges(7, "2026-10-20", null, { f: { "Kingfisher|1008": 68, "Nobody|5": 50 }, done: true, savedAt: 5 }, ids, AT)).toEqual([
      { table: "load_entries", op: "insert", values: { world_id: 7, airline_id: 2, game_date: "2026-10-20", flight_no: 1008, eco_pct: 68, entered_at: AT } },
      { table: "load_days", op: "insert", values: { world_id: 7, game_date: "2026-10-20", done: true, saved_at_ms: 5, entered_at: AT } },
    ]);
    expect(loadsChanges(7, "2026-10-14", held, { set: { "Pan American|1001": 93 } }, ids, AT)).toEqual([]);
    expect(loadsChanges(7, "2026-10-14", held, { del: ["Pan American|1009"] }, ids, AT).map((c) => [c.table, c.op, c.values?.eco_pct])).toEqual([["load_entries", "insert", null]]);
  });
  it("a day's boxes and status from the day as the planner holds it", () => {
    const d = { done: true, source: "capture", f: { "Pan American|1001": 93, "Pan American|1005": 61, "Pan American|1009": 97, "Kingfisher|1": 50 } };
    expect(underList(d, "Pan American")).toBe("1005 61, 1001 93");
    expect([dayStatus(d), dayStatus({ done: true, f: {} }), dayStatus(null)]).toEqual(["captured", "entered by hand", "nothing yet"]);
  });
});
