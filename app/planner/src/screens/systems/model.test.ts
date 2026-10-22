// Systems' logic (spec docs/specs/2026-10-20-today-performance-systems.md; Check's and Review's tests for these boards
// until 20 Oct, specs docs/specs/2026-10-13-check.md and docs/specs/2026-10-14-review.md): the capture board's cells and
// the backup's line; the boards in their order (the Cabins board's fit, keep and refit went with it on 21 Oct, the
// Aircraft checks board with the one-week checks on 22 Oct); Cabin charges (22 Oct): the board's line, each row's words,
// Use the game's amount and Today's one item; and Manual entry: cash and fixed costs (the rows the old planner's adapter
// writes), the nightly log, the load paste reader (the old parseLoadPaste, with the old planner test's case) and the
// typed loads with their rows. The Systems board's own marks are systems.test.ts's.
import { describe, expect, it } from "vitest";
import {
  BOARDS, CABIN_STATE_WORDS, asd, backupWords, cabinAttention, cabinCountsWords, cabinGameWords, cabinLoggedWords, captureCell, captureStatus, cashChanges,
  dayStatus, gameAmountChange, loadsChanges, mergeDay, nightlyLog, parseLoadPaste, pasteSaves, signedAsd, typedLoads, typedSave,
  underList, type CabinCharges, type CabinProblem, type CashToday,
} from "./model";

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

describe("the boards", () => {
  it("are Capture, Cabin charges and Manual entry, in that order", () => {
    // the Cabins board went on 21 Oct (spec docs/specs/2026-10-21-cabins-new-rule.md §1); Cabin charges came on 22 Oct
    // (spec docs/specs/2026-10-21-tidy-ups.md §3), after Capture; Aircraft checks went on 22 Oct (spec
    // docs/specs/2026-10-22-remove-aircraft-checks.md)
    expect(BOARDS).toEqual(["Capture", "Cabin charges", "Manual entry"]);
  });
});

describe("Cabin charges (22 Oct): each first fit against the game's charge", () => {
  const problem = (x: Partial<CabinProblem> = {}): CabinProblem => ({
    state: "differs", airline_id: 6, code: "MH", airline: "Malaysia Airlines", registration: "9M-AAV", aircraft_id: 41,
    logged: { id: 77, spent_on: "2026-10-19", amount: 97000, config: "E195-LEI", updated_at: "2026-10-19T02:10:11.123456+00:00" },
    lines: [{ id: 501, paid_at: "2026-10-18T22:04:00.000Z", amount: 99000, descr: "Installation of cabin interior (9M-AAV)" }],
    game_amount: 99000, difference: 2000, ...x,
  });
  const charges = (problems: CabinProblem[], x: Partial<CabinCharges["counts"]> = {}): CabinCharges => ({
    check_from: "2026-10-18", wait_days: 2, problems,
    counts: { checked: 16, matches: 14, differs: 1, charged_twice: 0, not_charged: 0, waiting: 1, not_logged: 0, problems: problems.length, ...x },
  });
  it("the board's line: what was checked and how it came out, nothing without the setting", () => {
    expect(cabinCountsWords(charges([problem()]))).toBe("first fits since 18 Oct: 14 match · 1 differs · 1 waiting for the game's charge");
    expect(cabinCountsWords(charges([], { matches: 1, differs: 0, waiting: 0, charged_twice: 2, not_charged: 1, not_logged: 3 })))
      .toBe("first fits since 18 Oct: 1 matches · 2 charged twice · 1 not charged yet · 3 not logged");
    expect(cabinCountsWords({ ...charges([]), check_from: null })).toBe("nothing checked: the world has no cabin_charge_check_from setting");
  });
  it("each row: what we logged, what the game charged (each line), the difference with its sign", () => {
    expect(cabinLoggedWords(problem())).toBe("19 Oct · AS$97,000 · E195-LEI");
    expect(cabinLoggedWords(problem({ state: "not_logged", logged: null }))).toBe("—");
    expect(cabinGameWords(problem())).toEqual(["18 Oct 22:04 · AS$99,000"]);
    expect(cabinGameWords(problem({ state: "not_charged", lines: [] }))).toEqual(["—"]);
    expect([signedAsd(2000), signedAsd(-500.4), signedAsd(null)]).toEqual(["+AS$2,000", "−AS$500", "—"]);
    expect(asd(97000.4)).toBe("AS$97,000");
    expect(CABIN_STATE_WORDS.not_charged).toBe("not charged yet");
  });
  it("Use the game's amount: the fit's spending_log amount from the figure's updated_at, one change; nothing on any other state", () => {
    expect(gameAmountChange(problem())).toEqual([{ table: "spending_log", op: "update", key: { id: 77 }, base: "2026-10-19T02:10:11.123456+00:00", values: { amount: 99000 } }]);
    for (const state of ["charged_twice", "not_charged", "not_logged"] as const) expect(gameAmountChange(problem({ state }))).toEqual([]);
    expect(gameAmountChange(problem({ logged: null }))).toEqual([]);
  });
  it("Today's one item: how many don't match, keyed by the problems so a new one shows again; none when all match", () => {
    expect(cabinAttention(charges([problem(), problem({ state: "not_logged", logged: null, registration: "9M-AAZ", lines: [{ id: 502, paid_at: "2026-10-20T01:00:00Z", amount: 88000, descr: "x" }] })])))
      .toEqual({ key: "cabin|differs:77,not_logged:p502", text: "2 cabin charges don't match what we logged" });
    expect(cabinAttention(charges([problem()]))?.text).toBe("1 cabin charge doesn't match what we logged");
    expect(cabinAttention(charges([]))).toBeNull();
    expect(cabinAttention(null)).toBeNull();
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
