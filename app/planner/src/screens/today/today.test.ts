// Today's logic (spec docs/specs/2026-10-20-today-performance-systems.md, "Checks"): All clear and each thing that stops
// it, the capture line's words for complete, missing, short and broken, the orders' words and the aircraft to file; and,
// moved here with their boards on 20 Oct, needs attention (its grouping, order, items, keys and dismissals; Home's tests
// until then, spec docs/specs/2026-10-13-home.md §3), the to-do board and Coming up, and the game check (the comparison,
// the fix and the add as one action each; Check's tests until then, spec docs/specs/2026-10-13-check.md). The planning
// rules themselves are the library's, with their own cases (lib/rules/cases/game.json, growth.json). The one-week checks
// (needs attention's group and Coming up's) went on 22 Oct (spec docs/specs/2026-10-22-remove-aircraft-checks.md).
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildRules, game, type GameFlight, type QueueCell, type RulesInput } from "@rules";
import type { Change } from "../../data/save";
import { familyOf, shortType } from "../../ui/aircraftNames";
import { attKind, dismissKey, groupAttention, withoutDismissed, type AttItem } from "../../ui/attention";
import { onOrder, type OnOrderGroup } from "./onOrder";
import type { AircraftRow, HomeAirline, TodoItemRow, TodoRow } from "../home/reads";
import type { RouteRow } from "../routes/model";
import type { TailAircraft } from "../tails/model";
import type { FleetChecks } from "../systems/model";
import { homeAttention, type AttentionInput } from "./attention";
import { comingUp, UP_FILTERS } from "./comingUp";
import { fixChanges, fixRotations, gameSummary, importChanges, noLinkWords } from "./game";
import { attentionAnchor, captureLine, clockWords, countTiles, deliveryLines, lineCell, lineColumns, lineSafe, orderStatus, runsDryWords, safeTypes, soonWords, tileForHash, toFile, waitingCards, waitingWords, type FileRow, type OrderRow } from "./model";
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
  const nothing = { canOrder: [], toFile: 0, attention: [], game: 0 };
  it("All clear when nothing is waiting: no order possible, nothing to file, no attention items, no Game check differences", () => {
    expect(waitingWords(nothing)).toEqual({ clear: true, title: "All clear", parts: ["Nothing to order, file or fix from the game, and nothing needs attention."] });
    expect(waitingWords({ ...nothing, attention: [{ label: "Routes to fix", count: 0 }] }).clear).toBe(true);
  });
  it("each thing stops it: an airline that can order, an aircraft to file, an attention item, a Game check difference", () => {
    expect(waitingWords({ ...nothing, canOrder: ["Pan Am"] })).toEqual({ clear: false, title: "One thing waiting", parts: ["Pan Am can order"] });
    expect(waitingWords({ ...nothing, toFile: 1 })).toEqual({ clear: false, title: "One thing waiting", parts: ["1 aircraft to file"] });
    expect(waitingWords({ ...nothing, attention: [{ label: "Routes to fix", count: 3 }] })).toEqual({ clear: false, title: "One thing waiting", parts: ["3 in Routes to fix"] });
    expect(waitingWords({ ...nothing, game: 1 })).toEqual({ clear: false, title: "One thing waiting", parts: ["1 Game check difference"] });
  });
  it("counts a thing per section Today shows (23 Oct): each group of needs attention its own, as its section is", () => {
    // the 22 Oct handover's mismatch: three groups counted as one thing while the cards showed three
    const w = waitingWords({ canOrder: ["Pan Am", "Virgin"], toFile: 2, attention: [{ label: "Routes to fix", count: 3 }, { label: "Rival moves", count: 1 },
      { label: "Fleet", count: 2 }], game: 4 });
    expect(w).toEqual({ clear: false, title: "6 things waiting",
      parts: ["Pan Am, Virgin can order", "2 aircraft to file", "3 in Routes to fix", "1 in Rival moves", "2 in Fleet", "4 Game check differences"] });
    expect(Number(w.title.split(" ")[0])).toBe(w.parts.length);
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

describe("aircraft on order, for Aircraft to file (Home's board's until 23 Oct)", () => {
  const rules = buildRules({ ...base, cabin_configs: [{ id: 7, code: "321-LEI", aircraft_type_id: 1, seats: 200 }] });
  const ac = (id: number, x: Partial<AircraftRow>): AircraftRow => ({
    id, registration: `R-${id}`, airline_id: 1, aircraft_type_id: 1, order_config_id: 7, status: "on_order", delivery_at: null,
    order_base_code: "HUB", order_note: "HUB · AAA + BBB", updated_at: T0, ...x,
  });
  it("lists what isn't in service yet, by airline, soonest first, with what arrived", () => {
    const now = Date.parse("2026-10-13T12:00:00Z");
    const got = onOrder([
      ac(1, { delivery_at: "2026-10-15T05:53:30+00:00" }), ac(2, { delivery_at: "2026-10-12T02:00:00+00:00", status: "delivered" }),
      ac(3, { status: "active" }), ac(4, { airline_id: 2, aircraft_type_id: 2, delivery_at: "2026-10-20T00:00:00+00:00", order_note: null }),
    ], rules, new Map([[2, null]]), airlines, now);
    expect(got.count).toBe(3);
    expect(got.groups.map((g) => [g.airline.name, g.rows.map((r) => r.registration), g.arrived, g.families])).toEqual([
      ["Test Air", ["R-2", "R-1"], 1, [["A320 family", 2]]], ["Other Air", ["R-4"], 0, [["E195", 1]]],
    ]);
    expect(got.groups[0]?.rows[1]).toMatchObject({ type: "A321neo", config: "321-LEI", plan: "AAA + BBB", arrived: false, hasCard: false, at: Date.parse("2026-10-15T05:53:00Z") });
    expect(got.groups[0]?.rows[0]).toMatchObject({ arrived: true, hasCard: true });
    expect(shortType("A350-900ULR")).toBe("A350");
    expect(familyOf("A321XLR")).toBe("A320 family");
  });
  it("names each one's plan by its card's title, else the old order note (21 Oct: a card with no order note showed blank)", () => {
    const now = Date.parse("2026-10-21T23:00:00Z");
    const got = onOrder([
      ac(5, { delivery_at: "2026-10-22T07:08:00+00:00", order_note: null }), ac(6, { delivery_at: "2026-10-22T07:10:00+00:00" }),
      ac(7, { delivery_at: "2026-10-22T08:00:00+00:00", order_note: "HUB · old words" }), ac(8, { delivery_at: "2026-10-22T09:00:00+00:00" }),
    ], rules, new Map<number, string | null>([[5, "MCI + STL + IND"], [7, "AAA + DDD"], [8, " "]]), airlines, now);
    expect(got.groups[0]?.rows.map((r) => [r.registration, r.plan, r.hasCard])).toEqual([
      ["R-5", "MCI + STL + IND", true], ["R-6", "AAA + BBB", false], ["R-7", "AAA + DDD", true], ["R-8", "AAA + BBB", true]]);
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
    expect(attKind({ text: "N001AW: 2 legs with a short turn or wrong position" })).toBe("turn");
    expect(attKind({ text: "JFK–ORD (1002) lands or leaves inside a night ban" })).toBe("ban");
    expect(attKind({ text: "Pan 1002 is used twice (JFK–ORD and JFK–BOS) on the same days" })).toBe("clash");
    expect(attKind({ text: "JFK: 4,200 departures a week — the cap is 5,000 per airport" })).toBe("cap");
    expect(attKind({ text: "Interline: 2 airline–country pairs without an agreement" })).toBe("interline");
    expect(attKind({ text: "something else" })).toBe("other");
  });
  it("groups by kind in the order kinds first come, the most serious kind first, items in their order", () => {
    const items = [
      item({ text: "A: 2 legs with a short turn or wrong position", cls: "warn" }),
      item({ key: "maint|A", text: "A maintenance ≈103% — little headroom", cls: "warn" }),
      item({ key: "order|Test Air|2026-10-13", text: "Test Air can safely order: A321neo", cls: "ok" }),
      item({ text: "B: 1 leg with a short turn or wrong position", cls: "warn" }),
      item({ key: "maint|B", text: "B maintenance ≈95% — condition will fall", cls: "bad" }),
      item({ key: "todo|t-1", text: "To-do: x", cls: "warn" }),
    ];
    const g = groupAttention(items);
    expect(g.map((x) => [x.kind, x.cls, x.items.length])).toEqual([["maint", "bad", 2], ["turn", "warn", 2], ["todo", "warn", 1], ["order", "ok", 1]]);
    expect(g[0]?.label).toBe("Maintenance");
    expect(g[1]?.items.map((a) => a.text)).toEqual(["A: 2 legs with a short turn or wrong position", "B: 1 leg with a short turn or wrong position"]);
  });
  it("dismisses under the item's key, or its words when it has none; hidden ones are counted", () => {
    const a = item({ key: "maint|A", text: "A maintenance", cls: "bad" }), b = item({ text: "B: 1 leg with a short turn or wrong position", cls: "warn" });
    expect(dismissKey(a)).toBe("maint|A");
    expect(dismissKey(b)).toBe("B: 1 leg with a short turn or wrong position");
    expect(withoutDismissed([a, b], new Set(["B: 1 leg with a short turn or wrong position"]))).toEqual({ shown: [a], hidden: 1 });
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
    now, today: "2026-10-13", airlines, rules: buildRules(base), todos: [], capture: null, backups: null, jobs: null, cards: null,
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
  it("to-dos due or overdue, can order: the old words and keys", () => {
    const got = homeAttention(input({
      todos: [todo(1, { due_on: "2026-10-13", title: "Today" }), todo(2, { due_on: "2026-10-10", title: "Late" }), todo(3, { due_on: "2026-10-14" }), todo(4, { due_on: "2026-10-01", done: true })],
      cards: [{ airline_id: 1, load_7_days: 90, can_order_now: ["A321 NEO LIGHT", "E195-E2"] }, { airline_id: 2, load_7_days: null, can_order_now: [] }],
    }));
    expect(got).toEqual([
      { key: "order|Test Air|2026-10-13", cls: "ok", screen: "performance", text: "Test Air can safely order: A321neo, E195" },
      { key: "todo|t-1", cls: "warn", screen: "today", text: "To-do: Today" },
      { key: "todo|t-2", cls: "bad", screen: "today", text: "To-do (overdue): Late" },
    ]);
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
  it("the cabin charges (22 Oct): one amber item when any doesn't match, after the capture, grouped as Cabin charges, linking to Systems", () => {
    const at = (h: number) => new Date(now.getTime() - h * 3_600_000).toISOString();
    const problem = (state: "differs" | "not_logged", id: number) => ({
      state, airline_id: 1, code: "TA", airline: "Test Air", registration: `T-00${id}`, aircraft_id: id,
      logged: state === "differs" ? { id, spent_on: "2026-10-12", amount: 97000, config: "E195-LEI", updated_at: T0 } : null,
      lines: [{ id: 100 + id, paid_at: at(20), amount: 99000, descr: `Installation of cabin interior (T-00${id})` }],
      game_amount: state === "differs" ? 99000 : null, difference: state === "differs" ? 2000 : null,
    });
    const cabins = (problems: ReturnType<typeof problem>[]) => ({
      check_from: "2026-10-18", wait_days: 2, problems,
      counts: { checked: 3, matches: 2, differs: 1, charged_twice: 0, not_charged: 0, waiting: 0, not_logged: problems.length - 1, problems: problems.length },
    });
    const got = homeAttention(input({ capture: { last: [{ airline_id: 1, at: at(30) }, { airline_id: 2, at: at(1) }] }, cabins: cabins([problem("differs", 1), problem("not_logged", 2)]) }));
    expect(got.map((a) => [a.key, a.cls, a.screen, a.text])).toEqual([
      ["capture|2026-10-13", "warn", "systems", "Not captured for over a day: Test Air. Press Capture all airlines in the game"],
      ["cabin|differs:1,not_logged:p102", "warn", "systems", "2 cabin charges don't match what we logged"],
    ]);
    expect(groupAttention(got).map((g) => g.label)).toEqual(["Capture", "Cabin charges"]);
    // all match, or not read yet: nothing
    expect(homeAttention(input({ cabins: cabins([]) }))).toEqual([]);
    expect(homeAttention(input({ cabins: null }))).toEqual([]);
  });
  it("the fleet (22 Oct): one item per problem fleet_checks() finds, in its order, in the Fleet group; none before it's read", () => {
    const fleet: FleetChecks = { night: "2026-10-22", counts: { maintenance: 1, crew: 0, cabin: 0, not_in_planner: 1, not_in_game: 0, replace: 0, age: 0, problems: 2 }, airlines: [],
      problems: [
        { kind: "maintenance", airline_id: 1, code: "TA", registration: "N003AW", base: "JFK", aircraft_id: 13, words: "N003AW (JFK): maintenance 0.0%, condition 83%" },
        { kind: "not_in_planner", airline_id: 1, code: "TA", registration: "N099AW", base: "JFK", aircraft_id: null, words: "N099AW: in the game (JFK fleet), not in the planner" },
      ] };
    const got = homeAttention(input({ fleet }));
    expect(got).toEqual([
      { key: "fleet|maintenance|N003AW|2026-10-22", cls: "bad", screen: "tails", tail: "N003AW", text: "N003AW (JFK): maintenance 0.0%, condition 83%" },
      { key: "fleet|not_in_planner|N099AW|2026-10-22", cls: "warn", screen: "systems", text: "N099AW: in the game (JFK fleet), not in the planner" },
    ]);
    expect(got.map(attKind)).toEqual(["fleet", "fleet"]);
    expect(groupAttention(got).map((g) => [g.label, g.cls, g.items.length])).toEqual([["Fleet", "bad", 2]]);
    expect(homeAttention(input({ fleet: null }))).toEqual([]);
  });
  it("maintenance (23 Oct): an aircraft on the fleet pages is judged on the game's figure, the estimate's ≈ item only for one without", () => {
    const all = [1, 2, 3, 4, 5, 6, 7];
    const leg = (id: number, n: 1 | 2, from: string, to: string, dep: number, blk: number) => ({
      id, airline_id: 1, rotation_id: 1, leg_no: n, flight_no: 1000 + id, origin_code: from, dest_code: to, aircraft_id: 1, days_utc: all, dep_utc_min: dep, block_min: blk,
    });
    // T-001 flies almost all day: the estimate says its maintenance is under the minimum
    const rules = buildRules({ ...base, rotations: [{ id: 1, airline_id: 1, route_id: 1 }],
      flight_legs: [leg(1, 1, "HUB", "AAA", 0, 300), leg(2, 2, "AAA", "HUB", 390, 300), leg(3, 1, "HUB", "AAA", 780, 300), leg(4, 2, "AAA", "HUB", 1170, 220)] });
    const maintItems = (got: AttItem[]) => got.filter((a) => a.key?.startsWith("maint|") || a.key?.startsWith("fleet|maintenance|")).map((a) => [a.key, a.cls, a.text]);
    // no fleet pages (or not read yet): the estimate, with ≈
    expect(maintItems(homeAttention(input({ rules })))).toEqual([["maint|T-001", "bad", "T-001 maintenance ≈0% — condition will fall"]]);
    const fleet = (pct: number, problems: FleetChecks["problems"] = []): FleetChecks => ({
      night: "2026-10-22", counts: { maintenance: problems.length, crew: 0, cabin: 0, not_in_planner: 0, not_in_game: 0, replace: 0, age: 0, problems: problems.length }, problems,
      airlines: [{ airline_id: 1, code: "TA", name: "Test Air", maintenance_min_pct: 100, pages: { read: 1, ok: 1, expected: 1, all_ok: true }, at: "2026-10-22T23:10:00.000Z",
        aircraft: [{ registration: "T-001", aircraft_id: 1, base: "HUB", fleet: "HUB", type: "A321 NEO LIGHT", nickname: null, from: "HUB", to: null, flight: null,
          age_years: 0.1, acquired: "new", replace_at_years: 3, condition_pct: 97, maintenance_pct: pct, y: 180, c: 0, f: 0, pilots: true, owned: false, contract: "active",
          captured_at: "2026-10-22T23:10:00.000Z", problems: pct < 100 ? ["maintenance"] : [] }] }],
    });
    // the game's figure at or above the minimum: no item at all, whatever the estimate says
    expect(maintItems(homeAttention(input({ rules, fleet: fleet(112.4) })))).toEqual([]);
    expect(maintItems(homeAttention(input({ rules, fleet: fleet(100) })))).toEqual([]);
    // under it: only the Fleet group's item, in the game's words with no ≈, never the estimate's beside it
    const under = homeAttention(input({ rules, fleet: fleet(97.5, [{ kind: "maintenance", airline_id: 1, code: "TA", registration: "T-001", base: "HUB", aircraft_id: 1,
      words: "T-001 (HUB): maintenance 97.5%, condition 97%" }]) }));
    expect(maintItems(under)).toEqual([["fleet|maintenance|T-001|2026-10-22", "bad", "T-001 (HUB): maintenance 97.5%, condition 97%"]]);
    expect(under.some((a) => a.text.includes("≈"))).toBe(false);
    // its short turns are still the planner's to say
    expect(under.some((a) => a.text === "T-001: 7 legs with a short turn or wrong position")).toBe(true);
  });
  it("the aircraft age check (22 Oct): replace and looks used listed in the Fleet group with fleet_checks()'s words, after the others", () => {
    const fleet: FleetChecks = { night: "2029-08-01", counts: { maintenance: 0, crew: 0, cabin: 0, not_in_planner: 0, not_in_game: 0, replace: 2, age: 1, problems: 3 }, airlines: [],
      problems: [
        { kind: "replace", airline_id: 1, code: "TA", registration: "N001AW", base: "JFK", aircraft_id: 11, words: "N001AW (JFK): replace at 3 years (now 2.9): order its replacement" },
        { kind: "replace", airline_id: 1, code: "TA", registration: "N002AW", base: "JFK", aircraft_id: 12, words: "N002AW (JFK): past its replacement age (3 years, now 3.0)" },
        { kind: "age", airline_id: 1, code: "TA", registration: "N023AW", base: "JFK", aircraft_id: 33, words: "N023AW (JFK): looks used (3.6 years in the game), marked new" },
      ] };
    const got = homeAttention(input({ fleet }));
    expect(got).toEqual([
      { key: "fleet|replace|N001AW|2029-08-01", cls: "warn", screen: "tails", tail: "N001AW", text: "N001AW (JFK): replace at 3 years (now 2.9): order its replacement" },
      { key: "fleet|replace|N002AW|2029-08-01", cls: "warn", screen: "tails", tail: "N002AW", text: "N002AW (JFK): past its replacement age (3 years, now 3.0)" },
      { key: "fleet|age|N023AW|2029-08-01", cls: "warn", screen: "tails", tail: "N023AW", text: "N023AW (JFK): looks used (3.6 years in the game), marked new" },
    ]);
    expect(groupAttention(got).map((g) => [g.label, g.cls, g.items.length])).toEqual([["Fleet", "warn", 3]]);
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
  it("coming up: the next 14 days of to-dos, by day; the filters All and To-dos", () => {
    const todos = [todo(1, { due_on: "2026-10-17", title: "Late one" }), todo(2, { due_on: "2026-10-28" }), todo(3, { due_on: "2026-10-13" }),
      todo(4, { due_on: "2026-10-15", title: "Done one", done: true }), todo(5, { due_on: "2026-10-14", title: "Next" })];
    expect(comingUp(todos, "2026-10-13")).toEqual([
      { date: "2026-10-14", type: "todo", text: "Next" }, { date: "2026-10-17", type: "todo", text: "Late one" },
    ]);
    expect(UP_FILTERS.map(([, l]) => l)).toEqual(["All", "To-dos"]);
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
    // 28 Oct (spec docs/specs/2026-10-27-long-haul-lines.md §4): a 7-day line's aircraft, each leg on its own weekday
    it("a line aircraft: its return days after its outbound isn't a difference, a time fix keeps its days, a days difference isn't fixed", () => {
      const lineInput: RulesInput = { ...input, aircraft: [...input.aircraft, { id: 7, registration: "L-007", airline_id: 1, aircraft_type_id: 1, base_code: "HUB", status: "active" }],
        rotations: [...input.rotations, { id: 7, airline_id: 1, route_id: 4 }, { id: 8, airline_id: 1, route_id: 1 }],
        flight_legs: [...input.flight_legs, leg(7, 7, 1, "HUB", "DDD", 7, [1], 1200, 150, 3001), leg(8, 7, 2, "DDD", "HUB", 7, [4], 60, 160, 3002),
          leg(9, 8, 1, "HUB", "AAA", 7, [5], 360, 75, 3003), leg(10, 8, 2, "AAA", "HUB", 7, [5], 510, 75, 3004)] };
      const lr = buildRules(lineInput);
      const lp = game.plannerFlights(lr, 1);
      expect(lp.get("3002")?.map((e) => e.days)).toEqual(["4"]);
      const lf = [...flights, ...[...lp].filter(([no]) => Number(no) >= 3001).map(([no, e]) => g(no, e[0]?.from ?? "", e[0]?.to ?? "", e[0]?.dep ?? "", e[0]?.arr ?? "", e[0]?.days))];
      expect(game.compare(lr, 1, lf).issues.filter((i) => Number(i.no) >= 3001)).toEqual([]);
      const moved = lf.map((x) => (x.no === "3002" ? { ...x, dep: "07:00" } : x.no === "3003" ? { ...x, days: "15" } : x));
      const c = game.compare(lr, 1, moved);
      expect(c.issues.filter((i) => Number(i.no) >= 3001).map((i) => [i.no, i.text, !!i.fix])).toEqual([["3002", "Different: departure", true], ["3003", "Different: days", false]]);
      const now: LegNow[] = lineInput.flight_legs.filter((l) => l.rotation_id === 7)
        .map((l) => ({ id: l.id, rotation_id: l.rotation_id as number, leg_no: l.leg_no as number, days_utc: l.days_utc, dep_utc_min: l.dep_utc_min, block_min: l.block_min, updated_at: T0 }));
      // 07:00 at DDD (+5:30) is 01:30 UTC, still on the Thursday, landing at the same time: the departure and block change,
      // not the day (the old rule would have moved it to the Tuesday after the landing)
      expect(fixChanges(lr, 1, c.issues.filter((i) => i.no === "3002"), now)).toEqual([
        { table: "flight_legs", op: "update", key: { id: 8 }, base: T0, values: { dep_utc_min: 90, block_min: 130 } },
      ]);
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
      const fresh = importChanges({ ...common, tail: { registration: "T-777", acquired: "new" } });
      expect(fresh[0]).toMatchObject({ table: "aircraft", op: "insert", as: "new aircraft", values: { registration: "T-777", aircraft_type_id: 1, cabin_config_id: 1, base_code: "HUB", acquired: "new" } });
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

describe("the new look (spec docs/specs/2026-10-22-planner-look-today.md): cards, the orders table and the count tiles", () => {
  const al = (id: number, name: string, code: string | null = name.slice(0, 2).toUpperCase()) => ({ id, code, name, color: null, game_id: null });
  const line = (family: string, x: Partial<OrderRow["lines"][number]> = {}): OrderRow["lines"][number] =>
    ({ family, safe: null, text: "empty: nothing on order", warn: false, soon: null, ...x });
  it("a delivery line in short, as the table's cell says it", () => {
    expect(lineCell(line("A320 family", { safe: { now: false, text: "safe from Wed, Oct 21" }, text: "1 on order · runs dry 10-20 19:14 UTC", warn: true, soon: "in 17 h" })))
      .toEqual({ safe: { now: false, text: "Safe from Wed, Oct 21" }, onOrder: "1 on order", dry: "10-20 19:14", soon: "in 17 h", warn: true });
    expect(lineCell(line("E195", { safe: { now: true, text: "safe now" } })))
      .toEqual({ safe: { now: true, text: "Safe now" }, onOrder: "Nothing on order", dry: null, soon: null, warn: false });
    expect(lineCell(line("A350", { text: "2 on order · runs dry 10-24 05:53 UTC" }))).toEqual({ safe: null, onOrder: "2 on order", dry: "10-24 05:53", soon: null, warn: false });
  });
  it("the table's columns: every line any airline has, A320 family, then E195, then A350", () => {
    expect(lineColumns([{ lines: [line("A350"), line("A320 family")] }, { lines: [line("E195"), line("A320 family")] }])).toEqual(["A320 family", "E195", "A350"]);
    expect(lineColumns([{ lines: [line("B737"), line("A350")] }])).toEqual(["A350", "B737"]);
    expect(lineColumns([])).toEqual([]);
  });
  const order = (a: ReturnType<typeof al>, kind: OrderRow["status"]["kind"], types: OrderRow["types"] = []): OrderRow =>
    ({ airline: a, status: { kind, text: kind === "now" ? "Can order now" : "Safe from Thu, Oct 22" }, types, lines: [] });
  const file: FileRow = { airline: airlines[0] as HomeAirline, registration: "N023AW", type: "A321neo", config: "Y180", at: 0, base: "JFK", plan: "JFK–ORD", href: "/tails?airline=TA&file=N023AW" };
  const href = (a: AttItem) => "/" + a.screen;
  const base0 = { orders: [], toFile: [], attention: [], todos: [], game: 0, today: "2026-10-22", hrefOf: href, screenName: (a: AttItem) => a.screen, locale: L };
  it("a card for each thing waiting, the first airline that can order the one urgent card", () => {
    const cards = waitingCards({
      ...base0,
      orders: [order(al(1, "Pan Am"), "later"), order(al(2, "Virgin", "VS"), "now", [{ when: "now", now: true, names: ["A321neo", "E195"] }, { when: "from Thu, Oct 22", now: false, names: ["XLR"] }]),
        order(al(3, "Kingfisher", "IT"), "now")],
      toFile: [file],
      attention: [
        item({ key: "order|Virgin|2026-10-22", cls: "ok", screen: "performance", text: "Virgin can safely order: A321neo, E195" }),
        item({ key: "todo|t-7", cls: "bad", screen: "today", text: "To-do (overdue): Ring the bank" }),
        item({ key: "route|Pan Am|JFK|ORD", cls: "bad", screen: "performance", text: "JFK–ORD: losing money — x" }),
        item({ key: "route|Pan Am|JFK|BOS", cls: "warn", screen: "performance", text: "JFK–BOS: fix or reduce — y" }),
        item({ cls: "mute", screen: "interline", text: "Interline: 3 airline–country pairs without an agreement" }),
      ],
      todos: [todo(7, { title: "Ring the bank", due_on: "2026-10-20" })],
      game: 2,
    });
    expect(cards.map((c) => [c.kind, c.label, c.heading, c.detail, c.urgent, c.action.text, c.action.href])).toEqual([
      ["order", "Order now", "Virgin can safely order: A321neo, E195", "Also safe from Thu, Oct 22: XLR", true, "Cash, next 14 days", "/performance/VS"],
      ["order", "Order now", "Kingfisher can order now", null, false, "Cash, next 14 days", "/performance/IT"],
      ["due", "Overdue · due " + "Tue, Oct 20", "Ring the bank", null, false, "Open the to-do", "/today#todo"],
      ["file", "To file", "N023AW has arrived for Test Air", "A321neo Y180 · JFK · JFK–ORD", false, "File into planner", "/tails?airline=TA&file=N023AW"],
      ["attention", "Needs attention", "JFK–ORD: losing money — x", "and 1 more in Routes to fix", false, "See all 2", "/today#att-route"],
      ["attention", "Needs attention", "Interline: 3 airline–country pairs without an agreement", "Interline", false, "Open interline", "/interline"],
      ["game", "Needs attention", "2 Game check differences", "between the planner and the game's schedules", false, "Go to Game check", "/today#game-check"],
    ]);
  });
  it("the game's maintenance under the limit (22 Oct): the Fleet card next after order now, urgent when nothing can order", () => {
    const maint = item({ key: "fleet|maintenance|N003AW|2026-10-22", cls: "bad", screen: "tails", tail: "N003AW", text: "N003AW (JFK): maintenance 0.0%, condition 83%" });
    const crew = item({ key: "fleet|crew|N004AW|2026-10-22", cls: "bad", screen: "tails", tail: "N004AW", text: "N004AW (JFK): no pilots" });
    const route = item({ key: "route|Pan Am|JFK|ORD", cls: "bad", screen: "performance", text: "JFK–ORD: losing money — x" });
    const cards = waitingCards({ ...base0, orders: [order(al(2, "Virgin", "VS"), "now")], toFile: [file], attention: [route, maint, crew],
      todos: [todo(7, { title: "Ring the bank", due_on: "2026-10-20" })] });
    expect(cards.map((c) => [c.kind, c.label, c.heading, c.detail, c.urgent, c.action.text, c.action.href])).toEqual([
      ["order", "Order now", "Virgin can order now", null, true, "Cash, next 14 days", "/performance/VS"],
      ["maint", "Fleet · maintenance", "N003AW (JFK): maintenance 0.0%, condition 83%", "and 1 more in Fleet", false, "See all 2", "/today#att-fleet"],
      ["file", "To file", "N023AW has arrived for Test Air", "A321neo Y180 · JFK · JFK–ORD", false, "File into planner", "/tails?airline=TA&file=N023AW"],
      ["attention", "Needs attention", "JFK–ORD: losing money — x", "Routes to fix", false, "Open performance", "/performance"],
    ]);
    const alone = waitingCards({ ...base0, attention: [maint] });
    expect(alone.map((c) => [c.kind, c.urgent, c.detail, c.action.text, c.action.href])).toEqual([["maint", true, "Fleet", "Open tails", "/tails"]]);
    // a Fleet group without a maintenance problem is an ordinary needs attention card, in its place
    expect(waitingCards({ ...base0, attention: [route, crew] }).map((c) => [c.kind, c.label, c.urgent])).toEqual([
      ["attention", "Needs attention", false], ["attention", "Needs attention", false]]);
  });
  it("a to-do due today says so; nothing waiting, no cards", () => {
    const cards = waitingCards({ ...base0, attention: [item({ key: "todo|t-8", cls: "warn", screen: "today", text: "To-do: File the plan" })],
      todos: [todo(8, { title: "File the plan", due_on: "2026-10-22" })] });
    expect(cards.map((c) => c.label)).toEqual(["Due today"]);
    expect(waitingCards(base0)).toEqual([]);
  });
  it("the count tiles: Aircraft to file first, then each group of needs attention, the most serious first", () => {
    expect(countTiles(0, [
      item({ cls: "mute", screen: "interline", text: "Interline: 3 airline–country pairs without an agreement" }),
      item({ key: "route|a", cls: "warn", text: "A–B: fix or reduce — y" }),
      item({ key: "route|b", cls: "bad", text: "A–C: losing money — x" }),
      item({ key: "route|c", cls: "warn", text: "A–D: fix or reduce — z" }),
    ])).toEqual([
      { key: "to-file", count: 0, name: "Aircraft to file", cls: "file", line: "nothing has arrived" },
      { key: "route", count: 3, name: "Routes to fix", cls: "bad", line: "1 urgent · 2 to look at" },
      { key: "interline", count: 1, name: "Interline", cls: "mute", line: "1 for information" },
    ]);
    expect(countTiles(2, [])).toEqual([{ key: "to-file", count: 2, name: "Aircraft to file", cls: "file", line: "arrived with a plan card" }]);
  });
  it("each section's anchor (23 Oct): Aircraft to file's own, a group's att-<kind>; an address's anchor opens that section", () => {
    expect(attentionAnchor("to-file")).toBe("to-file");
    expect(attentionAnchor("route")).toBe("att-route");
    expect(attentionAnchor("todo")).toBe("att-todo");   // never #todo, the To-do board's
    expect(tileForHash("#att-route")).toBe("route");
    expect(tileForHash("#to-file")).toBe("to-file");
    expect(tileForHash("#todo")).toBeNull();
    expect(tileForHash("#att-")).toBeNull();
    expect(tileForHash("")).toBeNull();
    // every tile Today shows has a section Home's buttons can open, and back
    const tiles = countTiles(1, [item({ key: "route|a", cls: "warn", text: "A–B: fix or reduce — y" }), item({ key: "threat|PA|x", cls: "warn", screen: "competition", text: "x" })]);
    expect(tiles.map((t) => tileForHash("#" + attentionAnchor(t.key)))).toEqual(tiles.map((t) => t.key));
  });
});
