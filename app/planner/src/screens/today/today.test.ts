// Today's logic (spec docs/specs/2026-10-20-today-performance-systems.md, "Checks"): All clear and each thing that stops
// it, the capture line's words for complete, missing, short and broken, the orders' words and the aircraft to file; and,
// moved here with their boards on 20 Oct, needs attention (its grouping, order, items, keys and dismissals; Home's tests
// until then, spec docs/specs/2026-10-13-home.md §3), the to-do board and Coming up, and the game check (the comparison,
// the fix and the add as one action each; Check's tests until then, spec docs/specs/2026-10-13-check.md). The planning
// rules themselves are the library's, with their own cases (lib/rules/cases/checks.json, game.json, growth.json).
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildRules, checks as checkRules, game, type GameFlight, type OneWeekCheck, type QueueCell, type RulesInput } from "@rules";
import type { Change } from "../../data/save";
import { familyOf } from "../../ui/aircraftNames";
import { attKind, dismissKey, groupAttention, withoutDismissed, type AttItem } from "../../ui/attention";
import type { OnOrderGroup } from "../home/onOrder";
import type { HomeAirline, TodoItemRow, TodoRow } from "../home/reads";
import type { RouteRow } from "../routes/model";
import type { TailAircraft } from "../tails/model";
import { homeAttention, type AttentionInput } from "./attention";
import { comingUp, upFilters } from "./comingUp";
import { fixChanges, fixRotations, gameSummary, importChanges, noLinkWords } from "./game";
import { captureLine, clockWords, deliveryLines, lineSafe, orderStatus, runsDryWords, safeTypes, soonWords, toFile, waitingWords } from "./model";
import type { LegNow } from "./reads";
import { addChanges, deleteChanges, dismissChanges, showAgainChanges, sortTodos, tickChanges, todoBoard, todoViews } from "./todos";

const L = "en-US";
const base = (JSON.parse(readFileSync(new URL("../../../../../lib/rules/cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
const airlines: HomeAirline[] = [{ id: 1, name: "Test Air", code: "TA", color: "#123456" }, { id: 2, name: "Other Air", code: "OA", color: "#654321" }];
const T0 = "2026-10-12T10:00:00.000001+00:00";
const todo = (id: number, x: Partial<TodoRow> = {}): TodoRow => ({
  id, world_id: 1, legacy_key: `t-${id}`, title: `To-do ${id}`, due_on: null, done: false, done_at: null, updated_at: T0, ...x,
});
const item = (a: Partial<AttItem> & Pick<AttItem, "text" | "cls">): AttItem => ({ screen: "systems", ...a });

describe("the answer at the top: All clear, or what's waiting", () => {
  const nothing = { canOrder: [], toFile: 0, attention: 0, game: 0 };
  it("All clear when nothing is waiting: no order possible, nothing to file, no attention items, no Game check differences", () => {
    expect(waitingWords(nothing)).toEqual({ clear: true, title: "All clear", parts: ["Nothing to order, file or fix from the game, and nothing needs attention."] });
  });
  it("each thing stops it: an airline that can order, an aircraft to file, an attention item, a Game check difference", () => {
    expect(waitingWords({ ...nothing, canOrder: ["Pan Am"] })).toEqual({ clear: false, title: "One thing waiting", parts: ["Pan Am can order"] });
    expect(waitingWords({ ...nothing, toFile: 1 })).toEqual({ clear: false, title: "One thing waiting", parts: ["1 aircraft to file"] });
    expect(waitingWords({ ...nothing, attention: 3 })).toEqual({ clear: false, title: "One thing waiting", parts: ["3 items in needs attention"] });
    expect(waitingWords({ ...nothing, game: 1 })).toEqual({ clear: false, title: "One thing waiting", parts: ["1 Game check difference"] });
    expect(waitingWords({ canOrder: ["Pan Am", "Virgin"], toFile: 2, attention: 1, game: 4 })).toEqual({ clear: false, title: "4 things waiting",
      parts: ["Pan Am, Virgin can order", "2 aircraft to file", "1 item in needs attention", "4 Game check differences"] });
  });
});

describe("the capture in one line (capture_status())", () => {
  const now = new Date("2026-10-20T18:00:00Z");
  const at = (h: number) => new Date(now.getTime() - h * 3_600_000).toISOString();
  const six = ["Pan Am", "Kingfisher", "Ryanair", "Virgin", "China Eastern", "Malaysia"].map((name, i) => ({ id: i + 1, name }));
  const all = (h = 1) => six.map((a) => ({ airline_id: a.id, at: at(h) }));
  it("complete: every airline captured within the day and all good, with the latest page's time", () => {
    const last = all(1).map((x, i) => (i === 2 ? { ...x, at: "2026-10-20T17:08:00.000Z" } : { ...x, at: at(2) }));
    expect(captureLine(six, { last, verdicts: six.map((a) => ({ airline_id: a.id, verdict: "ok" as const, words: "all good", at: at(2) })) }, now))
      .toEqual({ state: "complete", mark: "ok", text: "All six airlines captured, all good, 17:08 UTC" });
    // a capture stored before the page checks (no verdict) counts as good; an earlier day's time names its day
    expect(captureLine(six, { last: all(20) }, now)).toEqual({ state: "complete", mark: "ok", text: "All six airlines captured, all good, 19 Oct 22:00 UTC" });
    expect(clockWords("2026-10-20T03:04:00Z", now)).toBe("03:04 UTC");
  });
  it("missing: an airline not captured for over a day (amber), red after 48 hours; none captured at all", () => {
    const last = all(2).map((x) => (x.airline_id === 4 ? { ...x, at: at(30) } : x));
    expect(captureLine(six, { last }, now)).toEqual({ state: "missing", mark: "warn", text: "5 of 6 airlines captured, 16:00 UTC · not captured: Virgin" });
    expect(captureLine(six, { last: all(2).map((x) => (x.airline_id === 4 ? { ...x, at: null } : x)) }, now).mark).toBe("bad");
    expect(captureLine(six, { last: all(50) }, now)).toEqual({ state: "missing", mark: "bad", text: "No airline captured in the last day · press Capture all airlines in the game" });
  });
  it("short (amber) and broken (red), from the same night's verdicts, with what came in", () => {
    const v = (id: number, verdict: "short" | "broken", words: string, h = 1) => ({ airline_id: id, verdict, words, at: at(h) });
    expect(captureLine(six, { last: all(1), verdicts: [v(2, "short", "short: loads 12 of 78 flights")] }, now))
      .toEqual({ state: "short", mark: "warn", text: "All six airlines captured, 17:00 UTC · short: Kingfisher (loads 12 of 78 flights)" });
    expect(captureLine(six, { last: all(1), verdicts: [v(2, "short", "short: loads 12 of 78 flights"), v(1, "broken", "broken: balance sheet without the cash account (2800)")] }, now))
      .toEqual({ state: "broken", mark: "bad",
        text: "All six airlines captured, 17:00 UTC · short: Kingfisher (loads 12 of 78 flights) · broken: Pan Am (balance sheet without the cash account (2800))" });
    // a verdict older than the day (the capture has moved on since) doesn't count
    expect(captureLine(six, { last: all(1), verdicts: [v(2, "short", "short: x", 27)] }, now).state).toBe("complete");
  });
});

describe("orders: can order now or from when, the types that are safe, and each delivery line", () => {
  it("the status from the card's next order (cash_forecast()'s, through airline_cards())", () => {
    expect(orderStatus({ when: "now", types: ["A321 NEO LIGHT"] }, ["A321 NEO LIGHT"])).toEqual({ kind: "now", text: "Can order now" });
    expect(orderStatus({ when: "later", type: "E195-E2", safe_from: "2026-10-23T05:52:00.000Z" }, [])).toEqual({ kind: "later", text: "Safe from Fri, Oct 23" });
    expect(orderStatus({ when: "needs", missing: "a bank statement capture" }, null)).toEqual({ kind: "needs", text: "Needs a bank statement capture" });
    expect(orderStatus(null, null)).toEqual({ kind: "needs", text: "Needs a capture" });
    expect(orderStatus({ when: "not within 14 days" }, [])).toEqual({ kind: "none", text: "Not within 14 days" });
  });
  it("the safe types: now, or from their first safe day; one not safe within 14 days left out", () => {
    const t = (type: string, safe_day: number | null, safe_from: string | null) =>
      ({ aircraft_type_id: 1, type, price_with_cabin: 60, lease_week: 0.8, lease_seen: true, safe_day, safe_from, count_today: 1 });
    expect(safeTypes([t("A321 NEO LIGHT", 0, "2026-10-20T05:00:00Z"), t("A350-900ULR", 3, "2026-10-23T05:00:00Z"), t("E195-E2", null, null)]))
      .toEqual([{ when: "now", now: true, names: ["A321neo"] }, { when: "from Fri, Oct 23", now: false, names: ["A350"] }]);
    expect(safeTypes(undefined)).toEqual([]);
  });
  it("the safe types grouped by when, now first, each short name once in its group (the screenshots showed the A320neo's variants over and over)", () => {
    const t = (type: string, safe_day: number | null, safe_from: string | null) =>
      ({ aircraft_type_id: 1, type, price_with_cabin: 60, lease_week: 0.8, lease_seen: true, safe_day, safe_from, count_today: 1 });
    expect(safeTypes([
      t("A350-900ULR", 2, "2026-10-22T05:00:00Z"), t("A321 NEO LIGHT", 0, "2026-10-20T05:00:00Z"), t("E195-E2", 0, "2026-10-20T05:00:00Z"),
      t("A321 NEO LIGHT", 0, "2026-10-20T05:00:00Z"), t("A320NEO LIGHT", 2, "2026-10-22T05:00:00Z"), t("A320NEO LIGHT", 2, "2026-10-22T05:00:00Z"),
      t("E190-E2", 2, "2026-10-22T05:00:00Z"), t("A321XLR", 5, "2026-10-25T05:00:00Z"), t("A350-900ULR", null, null),
    ])).toEqual([
      { when: "now", now: true, names: ["A321neo", "E195"] },
      { when: "from Thu, Oct 22", now: false, names: ["A350", "A320neo", "E190-E2"] },
      { when: "from Sun, Oct 25", now: false, names: ["XLR"] },
    ]);
  });
  it("each delivery line it may have: on order and when it runs dry (warned when soon), or empty; families not in its fleet left out", () => {
    const cell = (family: string, x: Partial<QueueCell>): QueueCell => ({ family, in_fleet: true, count: 0, last_ms: null, hours: null, warn: false, ...x });
    expect(deliveryLines([cell("A320 family", { count: 3, last_ms: Date.parse("2026-10-24T05:53:00Z"), hours: 80 }),
      cell("A350", { count: 1, last_ms: Date.parse("2026-10-20T20:00:00Z"), hours: 12.4, warn: true }), cell("E195", {}), cell("A220", { in_fleet: false })])).toEqual([
      { family: "A320 family", safe: null, text: "3 on order · runs dry 10-24 05:53 UTC", warn: false, soon: null },
      { family: "A350", safe: null, text: "1 on order · runs dry 10-20 20:00 UTC", warn: true, soon: "in 12 h" },
      { family: "E195", safe: null, text: "empty: nothing on order", warn: false, soon: null },
    ]);
    expect(runsDryWords(Date.parse("2026-10-14T05:53:00Z"))).toBe("10-14 05:53");
    expect([soonWords(-2), soonWords(0.4), soonWords(21.6)]).toEqual(["now", "in 0 h", "in 22 h"]);
  });

  // 21 Oct: each delivery line says when its first type is safe, so the card reads each line once
  const ft = (type: string, safe_day: number | null, safe_from: string | null) =>
    ({ aircraft_type_id: 1, type, price_with_cabin: 60, lease_week: 0.8, lease_seen: true, safe_day, safe_from, count_today: 1 });
  const fam = (t: { type: string }) => familyOf(t.type);
  const forecast = [
    ft("A321XLR", 2, "2026-10-22T05:00:00Z"), ft("A320NEO LIGHT", 1, "2026-10-21T05:00:00Z"), ft("A321 NEO LIGHT", 4, "2026-10-24T05:00:00Z"),
    ft("E195-E2", 0, "2026-10-20T05:00:00Z"), ft("E190-E2", 3, "2026-10-23T05:00:00Z"),
    ft("A350-900ULR", null, null), ft("A350-900", null, null),
  ];
  it("a line's earliest safe day: now; a day (the earliest of its types); not within 14 days; nothing for a line with no type in the forecast", () => {
    expect(lineSafe("E195", forecast, fam)).toEqual({ now: true, text: "safe now" });
    expect(lineSafe("A320 family", forecast, fam)).toEqual({ now: false, text: "safe from Wed, Oct 21" });
    expect(lineSafe("A350", forecast, fam)).toEqual({ now: false, text: "not safe within 14 days" });
    expect(lineSafe("A220", forecast, fam)).toBeNull();
    expect(lineSafe("A320 family", undefined, fam)).toBeNull();
    expect(lineSafe("A320 family", [], fam)).toBeNull();
  });
  it("each line read once: when it's safe, then what's on order", () => {
    const cell = (family: string, x: Partial<QueueCell>): QueueCell => ({ family, in_fleet: true, count: 0, last_ms: null, hours: null, warn: false, ...x });
    expect(deliveryLines([cell("A320 family", { count: 1, last_ms: Date.parse("2026-10-20T19:14:00Z"), hours: 17, warn: true }), cell("E195", {}),
      cell("A350", {}), cell("A220", { in_fleet: false })], forecast, fam)).toEqual([
      { family: "A320 family", safe: { now: false, text: "safe from Wed, Oct 21" }, text: "1 on order · runs dry 10-20 19:14 UTC", warn: true, soon: "in 17 h" },
      { family: "E195", safe: { now: true, text: "safe now" }, text: "empty: nothing on order", warn: false, soon: null },
      { family: "A350", safe: { now: false, text: "not safe within 14 days" }, text: "empty: nothing on order", warn: false, soon: null },
    ]);
  });
});

describe("aircraft to file: arrived with a plan card", () => {
  it("lists only those, airline by airline, each linking to File into planner on Tails", () => {
    const row = (registration: string, arrived: boolean, hasCard: boolean) =>
      ({ id: 1, registration, type: "A321neo", config: "321-LEI", family: "A320 family", at: 0, arrived, base: "HUB", plan: "AAA", hasCard });
    const groups: OnOrderGroup[] = [
      { airline: airlines[0] as HomeAirline, rows: [row("R-1", true, true), row("R-2", true, false), row("R-3", false, true)], arrived: 2, families: [] },
      { airline: { ...(airlines[1] as HomeAirline), code: null }, rows: [row("R-4", true, true)], arrived: 1, families: [] },
    ];
    expect(toFile(groups).map((r) => [r.registration, r.airline.name, r.href])).toEqual([
      ["R-1", "Test Air", "/tails?airline=TA&file=R-1"], ["R-4", "Other Air", "/tails?file=R-4"],
    ]);
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
      { cls: "warn", text: "T-001 is due its one-week check", screen: "systems" },
      { key: "order|Test Air|2026-10-13", cls: "ok", screen: "performance", text: "Test Air can safely order: A321neo, E195" },
      { key: "todo|t-1", cls: "warn", screen: "today", text: "To-do: Today" },
      { key: "todo|t-2", cls: "bad", screen: "today", text: "To-do (overdue): Late" },
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
    expect(homeAttention(input({ checks: on }))).toEqual([{ cls: "warn", text: "T-001 is due its one-week check", screen: "systems" }]);
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
      .toEqual([{ key: "capture|2026-10-13", cls: "warn", screen: "systems", text: "Not captured for over a day: Other Air. Press Capture all airlines in the game" }]);
    expect(homeAttention(input({ capture: { last: [{ airline_id: 1, at: at(27.4) }, { airline_id: 2, at: at(30) }] } }))[0]?.text)
      .toBe("No capture for 30 hours: open the game and press Capture all airlines");
    expect(homeAttention(input({ capture: { last: [{ airline_id: 1, at: null }, { airline_id: 2, at: at(30) }] } }))[0])
      .toMatchObject({ cls: "bad", text: "No capture for over 2 days: open the game and press Capture all airlines" });
    expect(homeAttention(input({ capture: { last: [{ airline_id: 1, at: at(26) }, { airline_id: 2, at: at(1) }] } }))).toEqual([]);
  });
  it("the capture's verdicts (#21): a short or broken page the same night, in the capture group, linking to Systems", () => {
    const at = (h: number) => new Date(now.getTime() - h * 3_600_000).toISOString();
    const last = [{ airline_id: 1, at: at(1) }, { airline_id: 2, at: at(2) }];
    const got = homeAttention(input({ capture: { last, verdicts: [
      { airline_id: 1, verdict: "short", words: "short: loads 12 of 78 flights", at: at(1) },
      { airline_id: 2, verdict: "broken", words: "broken: balance sheet without the cash account (2800)", at: at(2) },
    ] } }));
    expect(got).toEqual([
      { key: `capture|verdict|Test Air|${at(1)}`, cls: "warn", screen: "systems",
        text: "Test Air's capture came in short: loads 12 of 78 flights. Capture that airline again in the game (Systems has each page)" },
      { key: `capture|verdict|Other Air|${at(2)}`, cls: "bad", screen: "systems",
        text: "Other Air's capture came in broken: balance sheet without the cash account (2800). Capture that airline again in the game (Systems has each page)" },
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
    expect(homeAttention(input({ backups: [run(1, true, "test"), run(31, true)] }))).toEqual([{ key: "backup|2026-10-13", cls: "warn", screen: "systems", text: "Backup: last good copy 31 hours ago" }]);
    expect(homeAttention(input({ backups: [run(2, false), run(60, true)] }))[0]).toMatchObject({ cls: "bad", text: "Backup: last good copy 60 hours ago (the last run failed)" });
    const failed = homeAttention(input({ backups: [run(2, false, "nightly", "upload failed"), run(26, true)] }))[0];
    expect(failed).toMatchObject({ cls: "bad", text: "Backup: the last run failed (Tue, Oct 13 10:00 UTC): upload failed" });
    expect(failed?.key).toBe("backup|failed|" + run(2, false).ran_at);
    expect(homeAttention(input({ backups: [] }))).toEqual([{ key: "backup|2026-10-13", cls: "mute", screen: "systems", text: "Backup: no copy yet; the first runs tonight" }]);
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
      { key: "route|Test Air|HUB|CCC", cls: "bad", screen: "performance", route: "Test Air|HUB|CCC", text: "HUB–CCC: losing money — its average flight loses money" },
      { key: "route|Other Air|AAA|BBB", cls: "warn", screen: "performance", route: "Other Air|AAA|BBB", text: "AAA–BBB: fix or reduce — economy under 75%" },
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

describe("Game check (Check's until 20 Oct)", () => {
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

  describe("the comparison, the fix and the add", () => {
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
});
