// Home's logic (spec docs/specs/2026-10-13-home.md §3): the attention grouping and order, dates as words, the dismiss
// keys, the to-do sort (open first by date, done in the last 7 days folded), and the parts around them: one-week checks,
// coming up, aircraft on order, the key figures and each action's changes.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildRules, type RulesInput } from "@rules";
import { oneWeekChecks } from "../../data/checks";
import { attKind, dismissKey, groupAttention, withoutDismissed, type AttItem } from "../../ui/attention";
import { shortType, familyOf } from "../../ui/aircraftNames";
import { addDays, dayDiff, dueWords, inDays, niceDate, untilText } from "../../ui/dates";
import { homeAttention, type AttentionInput, type HomeAirline } from "./attention";
import { comingUp } from "./comingUp";
import { averageLoad, keyFigureTiles } from "./figures";
import { familyWords, onOrder } from "./onOrder";
import type { AircraftRow, TodoItemRow, TodoRow } from "./reads";
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
    routesToFix: null, locale: L, ...x,
  });
  it("one-week checks due, to-dos due or overdue, can order: the old words and keys", () => {
    const checks = oneWeekChecks([{ id: 1, registration: "T-001", checked_on: null, schedule_changed_on: null }], new Map([[1, ["2026-10-05"]]]), "2026-10-13");
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
  it("routes to fix: airline by airline, keyed by the old planner's route key", () => {
    const got = homeAttention(input({ routesToFix: [
      { airline_id: 2, hub: "AAA", dest: "BBB", mark: "fix", why: "economy under 75%", profit_week: 0.1, profit_per_flight: 0.01 },
      { airline_id: 1, hub: "HUB", dest: "CCC", mark: "losing", why: "its average flight loses money", profit_week: -0.2, profit_per_flight: -0.03 },
    ] }));
    expect(got).toEqual([
      { key: "route|Test Air|HUB|CCC", cls: "bad", screen: "review", route: "Test Air|HUB|CCC", text: "HUB–CCC: losing money — its average flight loses money" },
      { key: "route|Other Air|AAA|BBB", cls: "warn", screen: "review", route: "Other Air|AAA|BBB", text: "AAA–BBB: fix or reduce — economy under 75%" },
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

describe("one-week checks and coming up", () => {
  const checks = oneWeekChecks([
    { id: 1, registration: "A", checked_on: null, schedule_changed_on: null },
    { id: 2, registration: "B", checked_on: null, schedule_changed_on: "2026-10-10" },
    { id: 3, registration: "C", checked_on: "2026-10-12", schedule_changed_on: null },
    { id: 4, registration: "D", checked_on: null, schedule_changed_on: null },
    { id: 5, registration: "E", checked_on: null, schedule_changed_on: null },
  ], new Map([[1, ["2026-10-01", "2026-10-03"]], [2, ["2026-10-01"]], [3, ["2026-10-05"]], [4, ["2026-10-09"]], [5, ["2026-10-10"]]]), "2026-10-13");
  it("are due a week after the latest launch or schedule change, done once checked on or after that", () => {
    expect(checks.map((c) => [c.registration, c.status, c.due])).toEqual([
      ["A", "due", "2026-10-10"], ["D", "upcoming", "2026-10-16"], ["B", "upcoming", "2026-10-17"], ["E", "upcoming", "2026-10-17"], ["C", "done", "2026-10-12"],
    ]);
  });
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
  it("the key figures: the library's, and the airlines' average load from airline_cards()", () => {
    expect(averageLoad([{ airline_id: 1, load_7_days: 97.4, can_order_now: [] }, { airline_id: 2, load_7_days: 99, can_order_now: [] }, { airline_id: 3, load_7_days: null, can_order_now: [] }])).toBe(98);
    const tiles = keyFigureTiles({ aircraft: 87, routes_flying: 184, flights_day: 467.857, seats_day: 75_314 }, [{ airline_id: 1, load_7_days: 98.6, can_order_now: [] }], () => "Test Air");
    expect(tiles.map((t) => t.value + t.label)).toEqual(["87aircraft", "184routes flying", "468flights a day", "75.3kseats a day", "≈99%average economy load, last 7 days of captures"]);
    expect(keyFigureTiles({ aircraft: 0, routes_flying: 0, flights_day: 0, seats_day: 0 }, [], () => "")[4]).toEqual({ value: "—", label: "average load, last 7 days (no reports yet)" });
  });
});
