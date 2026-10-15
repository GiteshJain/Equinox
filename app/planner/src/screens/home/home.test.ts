// Home's logic (spec docs/specs/2026-10-13-home.md §3): the attention grouping and order, dates as words, the dismiss
// keys, the to-do sort (open first by date, done in the last 7 days folded), and the parts around them: coming up,
// aircraft on order, the key figures and the hero, routes to fix (and the load patterns without profit), the airport
// caps and each action's changes. The one-week checks' rule is the planning library's, with its own cases
// (lib/rules/cases/checks.json).
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildRules, checks as checkRules, type OneWeekCheck, type RulesInput } from "@rules";
import { attKind, dismissKey, groupAttention, withoutDismissed, type AttItem } from "../../ui/attention";
import { shortType, familyOf } from "../../ui/aircraftNames";
import { addDays, dayDiff, dueWords, inDays, niceDate, untilText } from "../../ui/dates";
import { homeAttention, type AttentionInput, type HomeAirline } from "./attention";
import { comingUp, upFilters } from "./comingUp";
import { greeting, heroFigures, keyFigureTiles, loadTile } from "./figures";
import { arcWidth, clampView, focusView, gcPath, loadColor, mapPoint, nightPolygon, perDayWords, zoomView } from "./map";
import { familyWords, onOrder } from "./onOrder";
import type { AircraftRow, CardsRead, TodoItemRow, TodoRow } from "./reads";
import { addChanges, deleteChanges, dismissChanges, showAgainChanges, sortTodos, tickChanges, todoBoard, todoViews } from "./todos";

const L = "en-US";
const base = (JSON.parse(readFileSync(new URL("../../../../../lib/rules/cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
const airlines: HomeAirline[] = [{ id: 1, name: "Test Air", code: "TA", color: "#123456" }, { id: 2, name: "Other Air", code: "OA", color: "#654321" }];
const T0 = "2026-10-12T10:00:00.000000+00:00";
const todo = (id: number, x: Partial<TodoRow> = {}): TodoRow => ({
  id, world_id: 1, legacy_key: `t-${id}`, title: `To-do ${id}`, due_on: null, done: false, done_at: null, updated_at: T0, ...x,
});
const item = (a: Partial<AttItem> & Pick<AttItem, "text" | "cls">): AttItem => ({ screen: "check", ...a });

describe("dates as words (the old planner's)", () => {
  it("a day, as the old planner shows it", () => {
    expect(niceDate("2026-10-09", L)).toBe("Fri, Oct 9");
    expect(niceDate("", L)).toBe("");
  });
  it("when a to-do is due: today, overdue · day, a day, or no date", () => {
    expect(dueWords("2026-10-13", "2026-10-13", L)).toBe("today");
    expect(dueWords("2026-10-09", "2026-10-13", L)).toBe("overdue · Fri, Oct 9");
    expect(dueWords("2026-10-14", "2026-10-13", L)).toBe("Wed, Oct 14");
    expect(dueWords(null, "2026-10-13", L)).toBe("no date");
  });
  it("how far ahead, and how long until", () => {
    expect(inDays("2026-10-13", "2026-10-13")).toBe("today");
    expect(inDays("2026-10-14", "2026-10-13")).toBe("in 1 day");
    expect(inDays("2026-10-27", "2026-10-13")).toBe("in 14 days");
    const now = Date.parse("2026-10-13T10:00:00Z");
    expect(untilText(now - 60_000, now)).toBe("arrived");
    expect(untilText(now + 40 * 60_000, now)).toBe("in 40 min");
    expect(untilText(now + 320 * 60_000, now)).toBe("in 5 h 20 min");
    expect(untilText(now + 5 * 3_600_000, now)).toBe("in 5 h");
    expect(untilText(now + 76 * 3_600_000, now)).toBe("in 3 days 4 h");
    expect(untilText(now + 24 * 3_600_000, now)).toBe("in 1 day");
  });
  it("adds days and counts them across a month's end", () => {
    expect(addDays("2026-10-30", 3)).toBe("2026-11-02");
    expect(addDays("2026-10-13", -7)).toBe("2026-10-06");
    expect(dayDiff("2026-10-30", "2026-11-02")).toBe(3);
  });
});

describe("needs attention: grouping and order (the old ATT_KIND and attGrouped)", () => {
  it("knows an item's kind by its key, else by its words", () => {
    expect(attKind({ key: "maint|N001AW", text: "x" })).toBe("maint");
    expect(attKind({ text: "G-AADU is due its one-week check" })).toBe("check");
    expect(attKind({ text: "N001AW: 2 legs with a short turn or wrong position" })).toBe("turn");
    expect(attKind({ text: "JFK–ORD (1002) lands or leaves inside a night ban" })).toBe("ban");
    expect(attKind({ text: "Pan 1002 is used twice (JFK–ORD and JFK–BOS) on the same days" })).toBe("clash");
    expect(attKind({ text: "JFK: 4,200 departures a week — the cap is 5,000 per airport" })).toBe("cap");
    expect(attKind({ text: "Interline: 2 airline–country pairs without an agreement" })).toBe("interline");
    expect(attKind({ text: "something else" })).toBe("other");
  });
  it("groups by kind in the order kinds first come, the most serious kind first, items in their order", () => {
    const items = [
      item({ text: "A is due its one-week check", cls: "warn" }),
      item({ key: "maint|A", text: "A maintenance ≈103% — little headroom", cls: "warn" }),
      item({ key: "order|Test Air|2026-10-13", text: "Test Air can safely order: A321neo", cls: "ok" }),
      item({ text: "B is due its one-week check", cls: "warn" }),
      item({ key: "maint|B", text: "B maintenance ≈95% — condition will fall", cls: "bad" }),
      item({ key: "todo|t-1", text: "To-do: x", cls: "warn" }),
    ];
    const g = groupAttention(items);
    expect(g.map((x) => [x.kind, x.cls, x.items.length])).toEqual([["maint", "bad", 2], ["check", "warn", 2], ["todo", "warn", 1], ["order", "ok", 1]]);
    expect(g[0]?.label).toBe("Maintenance");
    expect(g[1]?.items.map((a) => a.text)).toEqual(["A is due its one-week check", "B is due its one-week check"]);
  });
  it("dismisses under the item's key, or its words when it has none; hidden ones are counted", () => {
    const a = item({ key: "maint|A", text: "A maintenance", cls: "bad" }), b = item({ text: "B is due its one-week check", cls: "warn" });
    expect(dismissKey(a)).toBe("maint|A");
    expect(dismissKey(b)).toBe("B is due its one-week check");
    expect(withoutDismissed([a, b], new Set(["B is due its one-week check"]))).toEqual({ shown: [a], hidden: 1 });
  });
  it("a dismissal is one row keyed by the world and the old planner's key; show again removes every one", () => {
    expect(dismissChanges(1, "maint|A", "2026-10-13")).toEqual([{ table: "dismissals", op: "insert", key: { world_id: 1, alert_key: "maint|A" }, values: { dismissed_on: "2026-10-13" } }]);
    expect(showAgainChanges([{ world_id: 1, alert_key: "a", dismissed_on: null, updated_at: T0 }, { world_id: 1, alert_key: "b", dismissed_on: null, updated_at: T0 }]))
      .toEqual([{ table: "dismissals", op: "delete", key: { world_id: 1, alert_key: "a" }, base: T0 }, { table: "dismissals", op: "delete", key: { world_id: 1, alert_key: "b" }, base: T0 }]);
  });
});

describe("needs attention: the items and their keys (the old renderHome)", () => {
  const now = new Date("2026-10-13T12:00:00Z");
  const input = (x: Partial<AttentionInput> = {}): AttentionInput => ({
    now, today: "2026-10-13", airlines, rules: buildRules(base), checks: [], todos: [], capture: null, backups: null, jobs: null, cards: null,
    growth: null, interlineOpen: null, locale: L, ...x,
  });
  it("interline: the old Home's line, after the airport caps and before the routes to fix, with no key; none when every pair has an answer", () => {
    const leg = (id: number, days: number[]) => ({ id, airline_id: 1, rotation_id: null, flight_no: null, origin_code: "HUB", dest_code: "AAA", aircraft_id: null, days_utc: days, dep_utc_min: 360, block_min: 60 });
    const rules = buildRules({ ...base, world_rules: { departures_per_airport_week: 7 }, flight_legs: [leg(1, [1, 2, 3, 4, 5, 6, 7])] });
    const growth = { profit_captured: false, fix_or_reduce: [], load_patterns: [
      { airline_id: 1, route_id: 3, hub: "HUB", dest: "CCC", mark: "cut" as const, why: "under 85% on most departures — reduce frequency or downgauge" }] };
    expect(homeAttention(input({ rules, growth, interlineOpen: 2 })).map((a) => [a.cls, a.screen, a.key, a.text])).toEqual([
      ["bad", "routes", undefined, "HUB: 7 departures a week — the cap is 7 per airport"],
      ["mute", "interline", undefined, "Interline: 2 airline–country pairs without an agreement"],
      ["warn", "routes", "route|Test Air|HUB|CCC", "HUB–CCC: loads say reduce — under 85% on most departures — reduce frequency or downgauge"],
    ]);
    expect(homeAttention(input({ interlineOpen: 1 }))).toEqual([{ cls: "mute", screen: "interline", text: "Interline: 1 airline–country pair without an agreement" }]);
    expect(attKind({ text: "Interline: 1 airline–country pair without an agreement" })).toBe("interline");
    expect(homeAttention(input({ interlineOpen: 0 }))).toEqual([]);
  });
  it("one-week checks due, to-dos due or overdue, can order: the old words and keys", () => {
    const flown = buildRules({ ...base, rotations: [{ id: 1, airline_id: 1, route_id: 1 }], flight_legs: [
      { id: 1, airline_id: 1, rotation_id: 1, leg_no: 1, flight_no: 1001, origin_code: "HUB", dest_code: "AAA", aircraft_id: 1, days_utc: [1], dep_utc_min: 360, block_min: 75 }] });
    const checks = checkRules.oneWeek(flown, { aircraft: [{ id: 1, checked_on: null, schedule_changed_on: null }], rotations: [{ id: 1, launched_on: "2026-10-05" }] }, "2026-10-13");
    const got = homeAttention(input({
      checks,
      todos: [todo(1, { due_on: "2026-10-13", title: "Today" }), todo(2, { due_on: "2026-10-10", title: "Late" }), todo(3, { due_on: "2026-10-14" }), todo(4, { due_on: "2026-10-01", done: true })],
      cards: [{ airline_id: 1, load_7_days: 90, can_order_now: ["A321 NEO LIGHT", "E195-E2"] }, { airline_id: 2, load_7_days: null, can_order_now: [] }],
    }));
    expect(got).toEqual([
      { cls: "warn", text: "T-001 is due its one-week check", screen: "check" },
      { key: "order|Test Air|2026-10-13", cls: "ok", screen: "review", text: "Test Air can safely order: A321neo, E195" },
      { key: "todo|t-1", cls: "warn", screen: "home", text: "To-do: Today" },
      { key: "todo|t-2", cls: "bad", screen: "home", text: "To-do (overdue): Late" },
    ]);
  });
  it("the checks off (aircraft_check_after_days 0): none in needs attention or Coming up, and no One-week checks filter; at 7 as before", () => {
    // T-001 launched 5 Oct (due 12 Oct), T-002 launched 10 Oct (coming up 17 Oct); today is 13 Oct
    const leg = (id: number, rotation: number, aircraft: number) =>
      ({ id, airline_id: 1, rotation_id: rotation, leg_no: 1, flight_no: 1000 + id, origin_code: "HUB", dest_code: "AAA", aircraft_id: aircraft, days_utc: [1], dep_utc_min: 360, block_min: 75 });
    const flown = (days: number) => buildRules({ ...base, settings: { ...base.settings, aircraft_check_after_days: days },
      rotations: [{ id: 1, airline_id: 1, route_id: 1 }, { id: 2, airline_id: 1, route_id: 1 }], flight_legs: [leg(1, 1, 1), leg(2, 2, 2)] });
    const facts = { aircraft: [{ id: 1, checked_on: null, schedule_changed_on: null }, { id: 2, checked_on: null, schedule_changed_on: null }],
      rotations: [{ id: 1, launched_on: "2026-10-05" }, { id: 2, launched_on: "2026-10-10" }] };
    const on = checkRules.oneWeek(flown(7), facts, "2026-10-13");
    expect(homeAttention(input({ checks: on }))).toEqual([{ cls: "warn", text: "T-001 is due its one-week check", screen: "check" }]);
    expect(comingUp(on, [], "2026-10-13")).toEqual([{ date: "2026-10-17", type: "check", text: "T-002" }]);
    const off = checkRules.oneWeek(flown(0), facts, "2026-10-13");
    expect(off).toEqual([]);
    expect(homeAttention(input({ checks: off }))).toEqual([]);
    expect(comingUp(off, [], "2026-10-13")).toEqual([]);
    // Coming up's filter buttons: One-week checks only while the checks are on (all of them before the rules are read)
    const labels = (r?: ReturnType<typeof buildRules>) => upFilters(r, [1, 2]).map(([, l]) => l);
    expect(labels(flown(7))).toEqual(["All", "One-week checks", "To-dos"]);
    expect(labels(flown(0))).toEqual(["All", "To-dos"]);
    expect(labels()).toEqual(["All", "One-week checks", "To-dos"]);
  });
  it("the capture: one airline late, all late, none captured since two days back", () => {
    const at = (h: number) => new Date(now.getTime() - h * 3_600_000).toISOString();
    expect(homeAttention(input({ capture: { last: [{ airline_id: 1, at: at(3) }, { airline_id: 2, at: at(30) }] } })))
      .toEqual([{ key: "capture|2026-10-13", cls: "warn", screen: "check", text: "Not captured for over a day: Other Air. Press Capture all airlines in the game" }]);
    expect(homeAttention(input({ capture: { last: [{ airline_id: 1, at: at(27.4) }, { airline_id: 2, at: at(30) }] } }))[0]?.text)
      .toBe("No capture for 30 hours: open the game and press Capture all airlines");
    expect(homeAttention(input({ capture: { last: [{ airline_id: 1, at: null }, { airline_id: 2, at: at(30) }] } }))[0])
      .toMatchObject({ cls: "bad", text: "No capture for over 2 days: open the game and press Capture all airlines" });
    expect(homeAttention(input({ capture: { last: [{ airline_id: 1, at: at(26) }, { airline_id: 2, at: at(1) }] } }))).toEqual([]);
  });
  it("the capture's verdicts (#21): a short or broken page the same night, in the capture group, linking to Check", () => {
    const at = (h: number) => new Date(now.getTime() - h * 3_600_000).toISOString();
    const last = [{ airline_id: 1, at: at(1) }, { airline_id: 2, at: at(2) }];
    const got = homeAttention(input({ capture: { last, verdicts: [
      { airline_id: 1, verdict: "short", words: "short: loads 12 of 78 flights", at: at(1) },
      { airline_id: 2, verdict: "broken", words: "broken: balance sheet without the cash account (2800)", at: at(2) },
    ] } }));
    expect(got).toEqual([
      { key: `capture|verdict|Test Air|${at(1)}`, cls: "warn", screen: "check",
        text: "Test Air's capture came in short: loads 12 of 78 flights. Capture that airline again in the game (Check has each page)" },
      { key: `capture|verdict|Other Air|${at(2)}`, cls: "bad", screen: "check",
        text: "Other Air's capture came in broken: balance sheet without the cash account (2800). Capture that airline again in the game (Check has each page)" },
    ]);
    expect(got.map((a) => attKind(a))).toEqual(["capture", "capture"]);
    // all good, or a capture over a day old (the late line says so instead): nothing
    expect(homeAttention(input({ capture: { last, verdicts: [{ airline_id: 1, verdict: "ok", words: "all good", at: at(1) }] } }))).toEqual([]);
    expect(homeAttention(input({ capture: { last: [{ airline_id: 1, at: at(1) }, { airline_id: 2, at: at(1) }], verdicts: [
      { airline_id: 1, verdict: "short", words: "short: statement: no lines", at: at(27) }] } }))).toEqual([]);
  });
  it("the backup: late, failed, none yet; a test run doesn't count", () => {
    const run = (h: number, ok: boolean, kind = "nightly", note: string | null = null) => ({ ran_at: new Date(now.getTime() - h * 3_600_000).toISOString(), kind, ok, note });
    expect(homeAttention(input({ backups: [run(5, true)] }))).toEqual([]);
    expect(homeAttention(input({ backups: [run(1, true, "test"), run(31, true)] }))).toEqual([{ key: "backup|2026-10-13", cls: "warn", screen: "check", text: "Backup: last good copy 31 hours ago" }]);
    expect(homeAttention(input({ backups: [run(2, false), run(60, true)] }))[0]).toMatchObject({ cls: "bad", text: "Backup: last good copy 60 hours ago (the last run failed)" });
    const failed = homeAttention(input({ backups: [run(2, false, "nightly", "upload failed"), run(26, true)] }))[0];
    expect(failed).toMatchObject({ cls: "bad", text: "Backup: the last run failed (Tue, Oct 13 10:00 UTC): upload failed" });
    expect(failed?.key).toBe("backup|failed|" + run(2, false).ran_at);
    expect(homeAttention(input({ backups: [] }))).toEqual([{ key: "backup|2026-10-13", cls: "mute", screen: "check", text: "Backup: no copy yet; the first runs tonight" }]);
  });
  it("the jobs: a late snapshot, the 10:00 UTC job stopped, the archive not run by the 3rd, a failed run", () => {
    const at = (h: number) => new Date(now.getTime() - h * 3_600_000).toISOString();
    const got = homeAttention(input({ jobs: { archiveLast: { started_at: "2026-09-02T07:30:00Z" }, runs: [
      { job: "cleanup", status: "failed", started_at: at(2), for_month: null, note: "3 lines in neither", details: null },
      { job: "snapshot_fallback", status: "ok", started_at: at(31), for_month: null, note: null, details: null },
      { job: "archive", status: "failed", started_at: at(40), for_month: "2026-08-01", note: "the copy didn't check out", details: { table: "game_flights" } },
    ] } }));
    expect(got.map((a) => a.key)).toEqual(["jobs|snapshot|2026-10-13", "jobs|scheduler|2026-10-13", "jobs|archive|2026-10",
      `jobs|failed|cleanup|${at(2)}`, `jobs|failed|archive|${at(40)}`]);
    expect(got[2]?.text).toBe("Monthly archive: hasn't run this month (the nightly backup runs it from the 1st; last ran Wed, Sep 2 07:30 UTC)");
    expect(got[4]?.text).toBe("Monthly archive (game_flights 2026-08): the last run failed (Sun, Oct 11 20:00 UTC): the copy didn't check out");
  });
  const patterns = [
    { airline_id: 1, route_id: 3, hub: "HUB", dest: "CCC", mark: "cut" as const, why: "under 85% on most departures — reduce frequency or downgauge" },
    { airline_id: 1, route_id: 1, hub: "HUB", dest: "AAA", mark: "watch" as const, why: "a third of departures under 85%" },
  ];
  it("routes to fix: airline by airline, keyed by the old planner's route key", () => {
    const got = homeAttention(input({ growth: { profit_captured: true, load_patterns: patterns, fix_or_reduce: [
      { airline_id: 2, hub: "AAA", dest: "BBB", mark: "fix", why: "economy under 75%", profit_week: 0.1, profit_per_flight: 0.01 },
      { airline_id: 1, hub: "HUB", dest: "CCC", mark: "losing", why: "its average flight loses money", profit_week: -0.2, profit_per_flight: -0.03 },
    ] } }));
    expect(got).toEqual([
      { key: "route|Test Air|HUB|CCC", cls: "bad", screen: "review", route: "Test Air|HUB|CCC", text: "HUB–CCC: losing money — its average flight loses money" },
      { key: "route|Other Air|AAA|BBB", cls: "warn", screen: "review", route: "Other Air|AAA|BBB", text: "AAA–BBB: fix or reduce — economy under 75%" },
    ]);
  });
  it("with no profit captured, the routes the load patterns say to reduce instead (the old Home's fallback)", () => {
    expect(homeAttention(input({ growth: { profit_captured: false, load_patterns: patterns, fix_or_reduce: [] } }))).toEqual([
      { key: "route|Test Air|HUB|CCC", cls: "warn", screen: "routes", route: "Test Air|HUB|CCC", text: "HUB–CCC: loads say reduce — under 85% on most departures — reduce frequency or downgauge" },
    ]);
    expect(homeAttention(input({ growth: null }))).toEqual([]);
  });
  it("an airport's departures a week: a warning from airport_cap_warning_pct of the cap, bad at the cap (the library's)", () => {
    const leg = (id: number, origin: string, days: number[]) => ({ id, airline_id: 1, rotation_id: null, flight_no: null, origin_code: origin, dest_code: "AAA", aircraft_id: null, days_utc: days, dep_utc_min: 360, block_min: 60 });
    const rules = buildRules({ ...base, world_rules: { departures_per_airport_week: 10 }, flight_legs: [leg(1, "HUB", [1, 2, 3, 4, 5, 6, 7]), leg(2, "HUB", [1, 2, 3]), leg(3, "FOC", [1, 2, 3, 4, 5, 6, 7]), leg(4, "FOC", [1])] });
    expect(homeAttention(input({ rules })).map((a) => [a.cls, a.text])).toEqual([
      ["bad", "HUB: 10 departures a week — the cap is 10 per airport"], ["warn", "FOC: 8 departures a week — the cap is 10 per airport"],
    ]);
  });
  it("from the planning library: maintenance, short turns, a night ban and a flight number used twice", () => {
    const rules = buildRules({
      ...base,
      rotations: [{ id: 1, airline_id: 1, route_id: 1 }, { id: 2, airline_id: 1, route_id: 6 }],
      flight_legs: [
        // T-001 flies HUB–AAA–HUB 8 times a day back to back: little ground time, and short turns
        { id: 1, airline_id: 1, rotation_id: 1, leg_no: 1, flight_no: 1001, origin_code: "HUB", dest_code: "AAA", aircraft_id: 1, days_utc: [1, 2, 3, 4, 5, 6, 7], dep_utc_min: 360, block_min: 75 },
        { id: 2, airline_id: 1, rotation_id: 1, leg_no: 2, flight_no: 1002, origin_code: "AAA", dest_code: "HUB", aircraft_id: 1, days_utc: [1, 2, 3, 4, 5, 6, 7], dep_utc_min: 470, block_min: 75 },
        // T-002 lands at NBN inside its night ban, and its flight number is 1001 too, on the same days
        { id: 3, airline_id: 1, rotation_id: 2, leg_no: 1, flight_no: 1001, origin_code: "HUB", dest_code: "NBN", aircraft_id: 2, days_utc: [1, 2, 3, 4, 5, 6, 7], dep_utc_min: 1380, block_min: 60 },
        { id: 4, airline_id: 1, rotation_id: 2, leg_no: 2, flight_no: 1004, origin_code: "NBN", dest_code: "HUB", aircraft_id: 2, days_utc: [1, 2, 3, 4, 5, 6, 7], dep_utc_min: 420, block_min: 60 },
      ],
    });
    const got = homeAttention(input({ rules }));
    expect(got.map((a) => a.text)).toEqual([
      "T-001: 7 legs with a short turn or wrong position",
      "HUB–NBN (1001) lands or leaves inside a night ban",
      "Test 1001 is used twice (HUB–AAA and HUB–NBN) on the same days",
    ]);
    expect(got[1]).toMatchObject({ screen: "routes", route: "Test Air|HUB|NBN" });
  });
});

describe("the to-do board (the old todoBoard)", () => {
  const today = "2026-10-13";
  const list = () => todoViews([
    todo(1, { due_on: "2026-10-20" }), todo(2, { done: true, due_on: "2026-10-01", done_at: "2026-10-12T09:00:00+00:00" }),
    todo(3, { due_on: null }), todo(4, { due_on: "2026-10-09" }), todo(5, { done: true, due_on: "2026-09-20", done_at: "2026-09-30T09:00:00+00:00" }),
    todo(6, { done: true, due_on: "2026-10-12", done_at: null }),
  ], [
    { id: 11, todo_id: 1, position: 2, body: "second", updated_at: T0 }, { id: 10, todo_id: 1, position: 1, body: "first", updated_at: T0 },
  ] satisfies TodoItemRow[]);
  it("sorts open first, each by date, no date last", () => {
    expect(sortTodos(list()).map((t) => t.row.id)).toEqual([4, 1, 3, 5, 2, 6]);
  });
  it("shows the open ones with their steps, folds the done ones of the last 7 days, and only counts older ones", () => {
    const b = todoBoard(list(), today);
    expect(b.open.map((t) => t.row.id)).toEqual([4, 1, 3]);
    expect(b.open[1]?.steps.map((s) => s.body)).toEqual(["first", "second"]);
    expect(b.done.map((t) => t.row.id)).toEqual([2, 6]);
    expect(b.older).toBe(1);
  });
  it("a tick sets done and when; an untick clears both", () => {
    const now = new Date("2026-10-13T12:00:00Z");
    expect(tickChanges(todo(1), true, now)).toEqual([{ table: "todos", op: "update", key: { id: 1 }, base: T0, values: { done: true, done_at: "2026-10-13T12:00:00.000Z" } }]);
    expect(tickChanges(todo(1), false, now)[0]?.values).toEqual({ done: false, done_at: null });
  });
  it("adding is one action: the to-do with an old-planner id, and its steps taking its new id", () => {
    const now = new Date("2026-10-13T12:00:00Z");
    expect(addChanges(1, "  Check G-AADU  ", "2026-10-14", ["Open its schedule", "", "  Tell Claude "], now)).toEqual([
      { table: "todos", op: "insert", as: "todo", values: { world_id: 1, legacy_key: "t" + now.getTime().toString(36), title: "Check G-AADU", due_on: "2026-10-14", done: false } },
      { table: "todo_items", op: "insert", from: { todo_id: "todo" }, values: { world_id: 1, position: 1, body: "Open its schedule" } },
      { table: "todo_items", op: "insert", from: { todo_id: "todo" }, values: { world_id: 1, position: 2, body: "Tell Claude" } },
    ]);
  });
  it("deleting is one action: its steps, then the to-do, each from the row as read", () => {
    const steps: TodoItemRow[] = [{ id: 10, todo_id: 1, position: 1, body: "a", updated_at: "x" }];
    expect(deleteChanges(todo(1), steps)).toEqual([
      { table: "todo_items", op: "delete", key: { id: 10 }, base: "x" }, { table: "todos", op: "delete", key: { id: 1 }, base: T0 },
    ]);
  });
});

describe("coming up", () => {
  const check = (aircraft_id: number, registration: string, status: OneWeekCheck["status"], due: string): OneWeekCheck =>
    ({ aircraft_id, registration, airline_id: 1, last: "2026-10-01", due, status, days: 0 });
  const checks = [check(1, "A", "due", "2026-10-10"), check(4, "D", "upcoming", "2026-10-16"), check(2, "B", "upcoming", "2026-10-17"),
    check(5, "E", "upcoming", "2026-10-17"), check(3, "C", "done", "2026-10-12")];
  it("coming up: the next 14 days, checks by day (aircraft together) before to-dos on the same day", () => {
    const todos = [todo(1, { due_on: "2026-10-17", title: "Late one" }), todo(2, { due_on: "2026-10-28" }), todo(3, { due_on: "2026-10-13" })];
    expect(comingUp(checks, todos, "2026-10-13")).toEqual([
      { date: "2026-10-16", type: "check", text: "D" }, { date: "2026-10-17", type: "check", text: "B, E" }, { date: "2026-10-17", type: "todo", text: "Late one" },
    ]);
  });
});

describe("aircraft on order and the key figures", () => {
  const rules = buildRules({ ...base, cabin_configs: [{ id: 7, code: "321-LEI", aircraft_type_id: 1, seats: 200 }] });
  const ac = (id: number, x: Partial<AircraftRow>): AircraftRow => ({
    id, registration: `R-${id}`, airline_id: 1, aircraft_type_id: 1, order_config_id: 7, status: "on_order", delivery_at: null,
    order_base_code: "HUB", order_note: "HUB · AAA + BBB", checked_on: null, schedule_changed_on: null, updated_at: T0, ...x,
  });
  it("lists what isn't in service yet, by airline, soonest first, with what arrived", () => {
    const now = Date.parse("2026-10-13T12:00:00Z");
    const got = onOrder([
      ac(1, { delivery_at: "2026-10-15T05:53:30+00:00" }), ac(2, { delivery_at: "2026-10-12T02:00:00+00:00", status: "delivered" }),
      ac(3, { status: "active" }), ac(4, { airline_id: 2, aircraft_type_id: 2, delivery_at: "2026-10-20T00:00:00+00:00", order_note: null }),
    ], rules, new Set([2]), airlines, now);
    expect(got.count).toBe(3);
    expect(got.groups.map((g) => [g.airline.name, g.rows.map((r) => r.registration), g.arrived, g.families.map(familyWords)])).toEqual([
      ["Test Air", ["R-2", "R-1"], 1, ["2 A320-family"]], ["Other Air", ["R-4"], 0, ["1 E195"]],
    ]);
    expect(got.groups[0]?.rows[1]).toMatchObject({ type: "A321neo", config: "321-LEI", plan: "AAA + BBB", arrived: false, hasCard: false, at: Date.parse("2026-10-15T05:53:00Z") });
    expect(got.groups[0]?.rows[0]).toMatchObject({ arrived: true, hasCard: true });
    expect(shortType("A350-900ULR")).toBe("A350");
    expect(familyOf("A321XLR")).toBe("A320 family");
  });
  const cards = (load: number | null, from: CardsRead["load_7_days_from"]): CardsRead => ({ airlines: [], load_7_days: load, load_7_days_flights: load == null ? 0 : 412, load_7_days_from: from });
  it("the key figures: the library's, and the group's average load as airline_cards() works it out", () => {
    const tiles = keyFigureTiles({ aircraft: 87, routes_flying: 184, flights_day: 467.857, seats_day: 75_314 }, cards(98.6, "captures"));
    expect(tiles.map((t) => t.value + t.label)).toEqual(["87aircraft", "184routes flying", "468flights a day", "75.3kseats a day", "≈99%average economy load, last 7 days of captures"]);
    expect(loadTile(cards(96.4, "reports"))).toEqual({ value: "≈96%", label: "average load, last 7 days" });
    expect(loadTile(cards(null, null))).toEqual({ value: "—", label: "average load, last 7 days (no reports yet)" });
    expect(loadTile(undefined)).toEqual({ value: "—", label: "average load, last 7 days (no reports yet)" });
  });
  it("the hero: aircraft in the air, flights today, departing in the next hour, aircraft on their routes, the load", () => {
    const h = heroFigures({ in_air: 42, flights_today: 468, departing_next_hour: 19, aircraft: 87, routes_flying: 184 }, cards(98.6, "captures"));
    expect(h.in_air).toBe(42);
    expect(h.tiles.map((t) => [t.id, t.value, t.label])).toEqual([
      ["today", "468", "flights today"], ["next", "19", "departing in the next hour"], ["fleet", "87", "aircraft on 184 routes"], ["load", "≈99%", "average load, last 7 days"],
    ]);
    expect(greeting(new Date("2026-10-13T13:40:00Z"))).toBe("Good morning. Here's the network right now.");
    expect(greeting(new Date("2026-10-13T17:00:00Z"))).toBe("Good afternoon. Here's the network right now.");
    expect(greeting(new Date("2026-10-13T02:00:00Z"))).toBe("Good evening. Here's the network right now.");
  });
});

describe("the network map (the old networkMap's drawing)", () => {
  it("colours a route by its load over 7 days: 95%+ green, 85 amber, 70 orange, under that red, grey with none", () => {
    expect([95, 94.9, 85, 84.9, 70, 69.9, null].map(loadColor)).toEqual(["#3FB37F", "#E0B341", "#E0B341", "#E8853A", "#E8853A", "#E0524B", "#7E8BA3"]);
  });
  it("draws a route wider the more round trips a day it has, up to a limit, and words them as the old tip", () => {
    expect([1, 2, 3, 5, 9].map(arcWidth)).toEqual(["1.10", "1.80", "2.50", "3.30", "3.30"]);
    expect([2, 10 / 7, 0].map(perDayWords)).toEqual(["2", "1.4", "0"]);
  });
  it("zooms around the middle or a point, never past a tenth of the width, and back out to the whole world", () => {
    const v = zoomView(null, 1.6);
    expect(v).toEqual({ x: 187.5, y: 93.75, w: 625, h: 312.5 });
    expect(zoomView(v, 1 / 1.6)).toBeNull();
    expect(zoomView({ x: 0, y: 0, w: 100, h: 50 }, 4)?.w).toBe(90);
    expect(zoomView(null, 2, 1000, 500)).toEqual({ x: 500, y: 250, w: 500, h: 250 });
    expect(clampView({ x: -50, y: 400, w: 400, h: 200 })).toEqual({ x: 0, y: 300, w: 400, h: 200 });
    expect(mapPoint({ left: 10, top: 20, width: 500, height: 250 }, null, 260, 145)).toEqual([500, 250]);
  });
  it("centres one airline on its busiest base with room for its network; the whole world without a place", () => {
    // the base at (499.47, 107.92) on the map; Paris is 6.4 across: the narrowest view, 220 wide, centred on the base
    const v = focusView([51.15, -0.19], [[51.15, -0.19], [48.86, 2.35]]);
    expect([v?.x, v?.y, v?.w, v?.h].map((x) => Math.round((x ?? NaN) * 100) / 100)).toEqual([389.47, 52.92, 220, 110]);
    expect(focusView(undefined, [])).toBeNull();
  });
  it("splits a great circle at the dateline and shades the night side with its polar cap", () => {
    expect((gcPath([35.55, 139.78], [33.94, -118.41]).match(/M/g) ?? []).length).toBe(2);
    expect(gcPath([51, 0], [51, 0])).toBe("");
    const night = nightPolygon(new Date("2026-12-21T12:00:00Z")).split(" ");
    expect(night).toHaveLength(123);
    expect(night.slice(-2)).toEqual(["1000.0,0.0", "0.0,0.0"]);   // the north pole sits in night in December
  });
});
