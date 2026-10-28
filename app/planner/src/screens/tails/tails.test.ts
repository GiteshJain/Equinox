// Tails' logic (spec docs/specs/2026-10-13-tails.md, "Checks"): the list's filters, the deliveries' status, the plan card
// checked against the game (same, different, missing, the game not read), filing's one action (each outbound paired with
// its return as the old filePlan pairs them, local times stored in UTC, the aircraft in service, its first cabin fit, the
// card taking the game's times), the cabin the card's routes call for (21 Oct), each route's fare level on the card (21
// Oct), and adding, editing and removing an aircraft. The planning rules themselves are the
// library's, with their own cases (lib/rules/cases/tails.json, aircraftWeek.json, frequency.json); these run the screen's
// joins on the cases' small world.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildRules, type RulesInput, type TailIssue } from "@rules";
import type { Change } from "../../data/save";
import type { MarketRow, RouteRow } from "../routes/model";
import {
  addTailChanges, cabinDiffers, cardCabin, cardCabinChange, cardFareLevels, cardLegs, checkSummary, fareCells, compareCard, configsFor, deleteTailChanges, deliveryRows, editTailChange, fileKey, filingCabin,
  filingChanges, maintPill, stationsOf, filtersQuery, gameLink, issueWords, pairLegs, parseFilters, removeDeliveryChanges, removeTailChanges, shownDeliveries,
  acquiredWords, deliveryCounts, headerPills, routesCell, headerWords, issuesShown, routeNames, tailCounts, tailsAnswer, shownMaint, shownPill, suggestionWords, tailRows, tailsOf, typesFor, weekStrip, withRoutes,
  lineCandidates, lineCardChanges, lineCheck, lineCheckWords, lineSize, lineSlots, nextFreeOffset, slotState,
  type ConfigRow, type FilingInput, type GameFlight, type PlanCardRow, type PlanLegRow, type PlanLineLegRow, type PlanLineRow, type TailAircraft, type TailAirline,
} from "./model";

const base = (JSON.parse(readFileSync(new URL("../../../../../lib/rules/cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
const T0 = "2026-10-12T10:00:00.000001+00:00";
const NOW = Date.parse("2026-10-13T12:00:00Z");
const TODAY = "2026-10-13";
const ALL = [1, 2, 3, 4, 5, 6, 7];

const ac = (id: number, reg: string, x: Partial<TailAircraft> = {}): TailAircraft => ({
  id, registration: reg, airline_id: 1, aircraft_type_id: 1, cabin_config_id: null, base_code: "HUB", status: "active", ordered_on: null, delivery_at: null,
  order_base_code: null, order_config_id: null, order_note: null, checked_on: null, schedule_changed_on: null, maintenance_note: null, retired_on: null,
  extra: {}, updated_at: T0, ...x,
});
// T-001 flies HUB–AAA every day (07:00, and 10:20 UTC back, two hours each way); T-002 is idle; T-003 (an E195 at FOC) has a
// 40-minute turn; T-005 has arrived and waits to be filed with its plan card; T-006 is on order; O-001 is another airline's
const fleet: TailAircraft[] = [
  ac(1, "T-001"), ac(2, "T-002"), ac(3, "T-003", { aircraft_type_id: 2, base_code: "FOC", cabin_config_id: 12 }), ac(4, "O-001", { airline_id: 2, base_code: "AAA" }),
  ac(5, "T-005", { status: "delivered", base_code: null, delivery_at: "2026-10-12T05:53:00+00:00", order_base_code: "HUB", order_config_id: 11, order_note: "lands HUB · AAA + DDD" }),
  ac(6, "T-006", { status: "on_order", base_code: null, delivery_at: "2026-10-15T18:00:00+00:00", order_base_code: "HUB" }),
];
const legRow = (id: number, rot: number, n: 1 | 2, from: string, to: string, aircraft: number, dep: number, blk: number, no: number) => ({
  id, airline_id: 1, rotation_id: rot, leg_no: n, flight_no: no, origin_code: from, dest_code: to, aircraft_id: aircraft, days_utc: ALL, dep_utc_min: dep, block_min: blk,
});
const input: RulesInput = {
  ...base,
  aircraft: [...base.aircraft, { id: 5, registration: "T-005", airline_id: 1, aircraft_type_id: 1, base_code: null, status: "delivered" },
    { id: 6, registration: "T-006", airline_id: 1, aircraft_type_id: 1, base_code: null, status: "on_order" }],
  rotations: [{ id: 1, airline_id: 1, route_id: 1 }, { id: 2, airline_id: 1, route_id: 8 }],
  flight_legs: [legRow(1, 1, 1, "HUB", "AAA", 1, 420, 120, 1001), legRow(2, 1, 2, "AAA", "HUB", 1, 620, 120, 1002),
    legRow(3, 2, 1, "HUB", "FOC", 3, 480, 60, 1101), legRow(4, 2, 2, "FOC", "HUB", 3, 580, 60, 1102)],
};
const rules = buildRules(input);
const configs: ConfigRow[] = [
  { id: 11, code: "321-LEI", aircraft_type_id: 1, cabin: "Leisure", cost: 450000 }, { id: 13, code: "321-STD", aircraft_type_id: 1, cabin: "Standard", cost: 300000 },
  { id: 12, code: "E195-LEI", aircraft_type_id: 2, cabin: "Leisure", cost: 250000 }, { id: 14, code: "321-CMF", aircraft_type_id: 1, cabin: "Comfort", cost: 600000 },
];
const configMap = new Map(configs.map((c) => [c.id, c]));
const airlines: TailAirline[] = [{ id: 1, code: "TA", name: "Test Air", color: "#123456", is_lcc: false, game_id: 113 }, { id: 2, code: "OA", name: "Other Air", color: null, is_lcc: true, game_id: 114 }];

describe("the pop-up's replacement line (22 Oct, spec docs/specs/2026-10-22-aircraft-age-check.md §2)", () => {
  it("says how the aircraft came and the age it's replaced at, from the settings", () => {
    const ages = buildRules({ ...input, settings: { ...input.settings, replace_new_years: 3, replace_used_years: 10 } });
    expect(acquiredWords(ages, ac(1, "T-001"))).toBe("came new, replace at 3 years");
    expect(acquiredWords(ages, ac(1, "T-001", { acquired: "new" }))).toBe("came new, replace at 3 years");
    expect(acquiredWords(ages, ac(1, "T-001", { acquired: "used" }))).toBe("came used, replace at 10 years");
    expect(acquiredWords(rules, ac(1, "T-001", { acquired: "used" }))).toBe("came used");
  });
});

describe("the list", () => {
  it("keeps its filters in the address and reads them back", () => {
    const f = { airline: "TA", base: "HUB", type: "A321 NEO LIGHT", status: "warn" as const, del: "on order" as const, card: "T-005", file: "" };
    expect(parseFilters(filtersQuery(f))).toEqual(f);
    expect(filtersQuery(parseFilters(""))).toBe("");
    expect(parseFilters("?status=nonsense&del=nope").status).toBe("");
  });
  it("lists the airline's aircraft in service in the order they were added, and filters by base, type and status", () => {
    const mine = tailsOf(fleet, 1);
    expect(mine.map((a) => a.registration)).toEqual(["T-001", "T-002", "T-003"]);
    const all = tailRows(mine, { base: "", type: "", status: "" }, rules, configMap);
    expect(all.map((r) => [r.a.registration, r.fig.legsWk, r.fig.blockDay, r.fig.routes, r.config])).toEqual([
      ["T-001", 14, 4, 1, ""], ["T-002", 0, 0, 0, ""], ["T-003", 14, 2, 1, "E195-LEI"]]);
    expect(tailRows(mine, { base: "FOC", type: "", status: "" }, rules, configMap).map((r) => r.a.registration)).toEqual(["T-003"]);
    expect(tailRows(mine, { base: "", type: "E195-E2", status: "" }, rules, configMap).map((r) => r.a.registration)).toEqual(["T-003"]);
    expect(tailRows(mine, { base: "", type: "", status: "flying" }, rules, configMap).map((r) => r.a.registration)).toEqual(["T-001", "T-003"]);
    expect(tailRows(mine, { base: "", type: "", status: "idle" }, rules, configMap).map((r) => r.a.registration)).toEqual(["T-002"]);
    // T-003's 40-minute turn at FOC is short (the red dot); its maintenance is fine
    const warn = tailRows(mine, { base: "", type: "", status: "warn" }, rules, configMap);
    expect(warn.map((r) => [r.a.registration, r.fig.marked])).toEqual([["T-003", true]]);
  });
  it("offers the types the airline may have and the cabins for its kind of airline", () => {
    expect(typesFor(rules, [{ airline_id: 1, aircraft_type_id: 2 }, { airline_id: 1, aircraft_type_id: 1 }, { airline_id: 2, aircraft_type_id: 1 }], 1)).toEqual(["A321 NEO LIGHT", "E195-E2"]);
    expect(configsFor(rules, configs, { is_lcc: false })).toEqual(["321-LEI", "E195-LEI", "321-CMF"]);
    expect(configsFor(rules, configs, { is_lcc: false }, "A321 neo light")).toEqual(["321-LEI", "321-CMF"]);
    expect(configsFor(rules, configs, { is_lcc: true }, "A321 NEO LIGHT")).toEqual(["321-STD"]);
  });
  it("draws the week strip in the base's local time, split at midnight", () => {
    const fig = tailRows([fleet[0] as TailAircraft], { base: "", type: "", status: "" }, rules, configMap)[0]?.fig;
    const s = weekStrip(rules, fleet[0] as TailAircraft, fig?.week ?? null);
    expect(s.base).toBe("HUB");
    expect(s.bars.filter((b) => b.day === 0).map((b) => [b.left.toFixed(3), b.width.toFixed(3), b.text, b.title])).toEqual([
      ["29.167", "8.333", "HUB–AAA", "1001 HUB 07:00 → AAA 10:00"], ["43.056", "8.333", "AAA–HUB", "1002 AAA 11:20 → HUB 12:20"]]);
  });
  it("words each issue as the old tailIssues", () => {
    const words = ([
      { kind: "block_hours", block_hours_day: 8.04, target_h: 10 }, { kind: "short_turns", count: 1 }, { kind: "short_turns", count: 7 },
      { kind: "maintenance", level: "bad", pct: 92, min_pct: 100, target_pct: 105 }, { kind: "maintenance", level: "warn", pct: 103, min_pct: 100, target_pct: 105 },
      { kind: "tight_turns", count: 2, margin_min: 10 }, { kind: "positions", count: 1 }, { kind: "longest_gap", gap_min: 150, target_h: 4 },
      { kind: "off_wave", count: 1, rotation_ids: [9] },
      { kind: "maintenance_gap", max_gap_h: 78, limit_h: 40, counting_stops: 4 }, { kind: "maintenance_gap", max_gap_h: null, limit_h: 40, counting_stops: 0 },
    ] as TailIssue[]).map(issueWords);
    expect(words).toEqual(["flies 8.0 h a day — under the 10 h target", "1 short turn a week", "7 short turns a week", "maintenance ≈92% — under 100%, condition will fall",
      "maintenance ≈103% — little headroom", "2 turns a week under the 10-min margin", "1 leg start where the aircraft isn't", "longest gap 2:30 — under the 4 h target",
      "1 rotation off wave", "no maintenance stop for 78 h, over 40", "no maintenance stop all week, over 40 h"]);
  });
});

describe("the game's maintenance on Tails (23 Oct, spec docs/specs/2026-10-23-game-maintenance-on-tails.md)", () => {
  const mine = tailsOf(fleet, 1);
  const game = new Map([[1, { pct: 106.4, night: "2026-10-22" }], [3, { pct: 97.2, night: "2026-10-22" }]]);
  const rows = tailRows(mine, { base: "", type: "", status: "" }, rules, configMap, game);
  it("an aircraft on the fleet pages shows the game's figure with no ≈, its class from the settings and the capture's tooltip", () => {
    const t1 = rows.find((r) => r.a.registration === "T-001");
    expect(shownPill(t1?.maint ?? null)).toEqual({ text: "106%", cls: "ok", title: "In the game, last night's capture (22 Oct)" });
    expect(shownPill(rows.find((r) => r.a.registration === "T-003")?.maint ?? null)).toMatchObject({ text: "97%", cls: "bad" });
    const at = (pct: number) => shownPill(shownMaint(rules, 1, null, { pct, night: "2026-10-22" }));
    expect([99.9, 100, 104.9, 105, 400, 458.7].map((p) => [at(p)?.text, at(p)?.cls])).toEqual([
      ["100%", "bad"], ["100%", "warn"], ["105%", "warn"], ["105%", "ok"], ["400%", "ok"], ["400+%", "ok"]]);
  });
  it("one not on the fleet pages keeps the estimate with its ≈ and its hours", () => {
    const est = tailRows(mine, { base: "", type: "", status: "" }, rules, configMap);
    const t1 = est.find((r) => r.a.registration === "T-001");
    expect(t1?.maint?.from).toBe("estimate");
    expect(shownPill(t1?.maint ?? null)).toEqual(maintPill(t1?.fig.maint));
    expect(shownPill(t1?.maint ?? null)?.text).toMatch(/^≈/);
    // an idle aircraft has no estimate and no game figure: no pill
    expect(rows.find((r) => r.a.registration === "T-002")?.maint).toBeNull();
  });
  it("the issue words follow the shown figure: the game's without ≈, none when the game's is fine", () => {
    const est: TailIssue[] = [{ kind: "short_turns", count: 1 }, { kind: "maintenance", level: "warn", pct: 103, min_pct: 100, target_pct: 105 }, { kind: "positions", count: 1 }];
    const bad = shownMaint(rules, 1, null, { pct: 97.2, night: "2026-10-22" });
    expect(issuesShown(est, bad).map(issueWords)).toEqual(["1 short turn a week", "maintenance 97% — under 100%, condition will fall", "1 leg start where the aircraft isn't"]);
    const ok = shownMaint(rules, 1, null, { pct: 110, night: "2026-10-22" });
    expect(issuesShown(est, ok).map(issueWords)).toEqual(["1 short turn a week", "1 leg start where the aircraft isn't"]);
    const warn = shownMaint(rules, 1, null, { pct: 102.6, night: "2026-10-22" });
    expect(issuesShown([{ kind: "positions", count: 2 }], warn).map(issueWords)).toEqual(["maintenance 103% — little headroom", "2 legs start where the aircraft isn't"]);
    // with no game figure the estimate's issues stay as they are, with ≈
    expect(issuesShown(est, null).map(issueWords)[1]).toBe("maintenance ≈103% — little headroom");
  });
});

describe("the look (23 Oct, spec docs/specs/2026-10-23-planner-look-tails.md)", () => {
  const mine = tailsOf(fleet, 1);
  const rows = tailRows(mine, { base: "", type: "", status: "" }, rules, configMap);
  it("counts the rows as the status filters do, and words the answer", () => {
    const c = tailCounts(rows);
    expect(c).toMatchObject({ all: 3, flying: 2, idle: 1, warn: 1 });
    expect(c.flying).toBe(tailRows(mine, { base: "", type: "", status: "flying" }, rules, configMap).length);
    expect(c.idle).toBe(tailRows(mine, { base: "", type: "", status: "idle" }, rules, configMap).length);
    expect(c.warn).toBe(tailRows(mine, { base: "", type: "", status: "warn" }, rules, configMap).length);
    expect(c.blockDay).toBeCloseTo(2, 5);
    expect(tailsAnswer(c)).toEqual({ title: "1 aircraft needs a look", pill: "3 aircraft · 2.0 block h/day on average" });
    expect(tailsAnswer({ ...c, warn: 2 }).title).toBe("2 aircraft need a look");
    expect(tailsAnswer({ ...c, warn: 0 }).title).toBe("All 3 aircraft flying well");
    expect(tailCounts([])).toEqual({ all: 0, flying: 0, idle: 0, warn: 0, blockDay: 0 });
  });
  it("counts the deliveries on order, arrived and to file (arrived with a plan card)", () => {
    const cards: PlanCardRow[] = [{ id: 7, airline_id: 1, aircraft_id: 5, base_code: "HUB", title: "AAA + DDD", note: null, updated_at: T0 }];
    expect(deliveryCounts(deliveryRows(fleet, airlines, rules, configMap, cards, NOW, TODAY))).toEqual({ onOrder: 1, arrived: 1, toFile: 1 });
    expect(deliveryCounts(deliveryRows(fleet, airlines, rules, configMap, [], NOW, TODAY))).toEqual({ onOrder: 1, arrived: 1, toFile: 0 });
  });
  it("names the routes each aircraft flies, and keeps the header's words as pills", () => {
    const t1 = rows.find((r) => r.a.registration === "T-001");
    expect(routeNames(rules, t1?.fig.week ?? null)).toHaveLength(t1?.fig.routes ?? -1);
    expect(routeNames(rules, null)).toEqual([]);
  });
  it("shows a dim dash, not 0, in the Routes cell of an aircraft with no routes (23 Oct: N002AW showed 0)", () => {
    const t2 = rows.find((r) => r.a.registration === "T-002");
    if (!t2) throw new Error("no T-002");
    expect(routesCell(t2.fig.routes, routeNames(rules, t2.fig.week))).toEqual({ kind: "none", text: "—" });
    expect(routesCell(0, [])).toEqual({ kind: "none", text: "—" });
    expect(routesCell(2, ["HUB–AAA", "HUB–FOC"])).toEqual({ kind: "names", text: "HUB–AAA, HUB–FOC" });
    // routes the start doesn't name: their count, never blank
    expect(routesCell(3, [])).toEqual({ kind: "count", text: "3" });
    const t3 = rows.find((r) => r.a.registration === "T-003");
    if (!t3) throw new Error("no T-003");
    const pills = headerPills(rules, t3.a, configMap, t3.fig).map((p) => p.text);
    expect(pills.join(" · ") + " · maintenance").toBe(headerWords(rules, t3.a, configMap, t3.fig));
  });
});

describe("deliveries", () => {
  const cards: PlanCardRow[] = [{ id: 7, airline_id: 1, aircraft_id: 5, base_code: "HUB", title: "AAA + DDD", note: null, updated_at: T0 }];
  const flyingDelivered = { ...ac(1, "T-001"), delivery_at: "2026-10-01T00:00:00+00:00", order_base_code: "HUB" };
  const list = [flyingDelivered, ...fleet.slice(1)];
  const rows = deliveryRows(list, airlines, rules, configMap, cards, NOW, TODAY);
  it("marks each aircraft arrived and not scheduled, on order or flying, the arrived first, then by day", () => {
    expect(rows.map((r) => [r.a.registration, r.status, r.due, r.plan, r.config, r.card?.id ?? null])).toEqual([
      ["T-005", "unscheduled", "2026-10-12", "AAA + DDD", "321-LEI", 7], ["T-006", "on order", "2026-10-15", "", "", null], ["T-001", "flying", "2026-10-01", "", "", null]]);
    expect(Math.round((rows[1]?.hrs ?? 0) * 10) / 10).toBe(54);
  });
  it("names each one's plan card by its title, else by the old order note (21 Oct: a card with no order note showed blank)", () => {
    const noNote = { ...ac(9, "T-009"), delivery_at: "2026-10-20T07:08:00+00:00", order_base_code: "HUB" };
    const noteOnly = { ...ac(10, "T-010"), delivery_at: "2026-10-20T08:00:00+00:00", order_base_code: "HUB", order_note: "lands HUB · BBB" };
    const both = { ...ac(11, "T-011"), delivery_at: "2026-10-20T09:00:00+00:00", order_base_code: "HUB", order_note: "lands HUB · old words" };
    const blankTitle = { ...ac(12, "T-012"), delivery_at: "2026-10-20T10:00:00+00:00", order_base_code: "HUB", order_note: "lands HUB · CCC" };
    const cards2: PlanCardRow[] = [
      { id: 21, airline_id: 1, aircraft_id: 9, base_code: "HUB", title: "MCI + STL + IND", note: null, updated_at: T0 },
      { id: 22, airline_id: 1, aircraft_id: 11, base_code: "HUB", title: "AAA + DDD", note: null, updated_at: T0 },
      { id: 23, airline_id: 1, aircraft_id: 12, base_code: "HUB", title: "  ", note: null, updated_at: T0 },
    ];
    const plans = new Map(deliveryRows([noNote, noteOnly, both, blankTitle], airlines, rules, configMap, cards2, NOW, TODAY).map((r) => [r.a.registration, r.plan]));
    expect(plans).toEqual(new Map([["T-009", "MCI + STL + IND"], ["T-010", "BBB"], ["T-011", "AAA + DDD"], ["T-012", "CCC"]]));
  });
  it("shows the open ones by default, and each status, base and type when asked", () => {
    expect(shownDeliveries(rows, 1, { base: "", type: "", del: "" }).map((r) => r.a.registration)).toEqual(["T-005", "T-006"]);
    expect(shownDeliveries(rows, 1, { base: "", type: "", del: "flying" }).map((r) => r.a.registration)).toEqual(["T-001"]);
    expect(shownDeliveries(rows, 1, { base: "", type: "", del: "on order" }).map((r) => r.a.registration)).toEqual(["T-006"]);
    expect(shownDeliveries(rows, 1, { base: "FOC", type: "", del: "" })).toEqual([]);
    expect(shownDeliveries(rows, 1, { base: "", type: "a321 neo light", del: "" }).length).toBe(2);
    expect(shownDeliveries(rows, 2, { base: "", type: "", del: "" })).toEqual([]);
  });
});

// T-005's card: HUB–DDD at 21:00 local and back from DDD at 07:40 (DDD is +5:30, its world's correction), then HUB–AAA
const planLegs: PlanLegRow[] = [
  { id: 71, plan_card_id: 7, position: 1, flight_no: 1201, origin_code: "HUB", dest_code: "DDD", days_utc: ALL, dep_utc_min: 1260, block_min: 330, service_code: "S2", updated_at: T0 },
  { id: 72, plan_card_id: 7, position: 2, flight_no: 1202, origin_code: "DDD", dest_code: "HUB", days_utc: ALL, dep_utc_min: 130, block_min: 360, service_code: "S2", updated_at: T0 },
  { id: 73, plan_card_id: 7, position: 3, flight_no: 1203, origin_code: "HUB", dest_code: "AAA", days_utc: ALL, dep_utc_min: 900, block_min: 80, service_code: "S1", updated_at: T0 },
  { id: 74, plan_card_id: 7, position: 4, flight_no: 1204, origin_code: "AAA", dest_code: "HUB", days_utc: ALL, dep_utc_min: 1030, block_min: 85, service_code: "S1", updated_at: T0 },
];
const legs = cardLegs(rules, planLegs);
const game = (x: Partial<GameFlight>[] = []): GameFlight[] => legs.map((L, i) => ({ code: "TA", no: L.no, from: L.from, to: L.to, days: "1234567", dep: L.dep, arr: L.arr, ...(x[i] ?? {}) }));

describe("the plan card against the game", () => {
  it("shows the card's legs in local time", () => {
    expect(legs.map((l) => [l.no, l.from, l.to, l.dep, l.arr, l.block, l.svc, l.days])).toEqual([
      ["1201", "HUB", "DDD", "21:00", "08:00", "5:30", "S2", "1234567"], ["1202", "DDD", "HUB", "07:40", "08:10", "6:00", "S2", "1234567"],
      ["1203", "HUB", "AAA", "15:00", "17:20", "1:20", "S1", "1234567"], ["1204", "AAA", "HUB", "18:10", "18:35", "1:25", "S1", "1234567"]]);
  });
  it("is the same when every leg's times and days are", () => {
    const c = compareCard(legs, game());
    expect([c.allSame, c.found, c.diff, c.miss, checkSummary(c)]).toEqual([true, 4, 0, 0, "Everything matches."]);
    // the game gives no arrival: only the departure and days count
    expect(compareCard(legs, game([{ arr: "" }])).allSame).toBe(true);
  });
  it("differs where the game's departure, arrival or days differ", () => {
    const c = compareCard(legs, game([{ dep: "21:10" }, {}, { arr: "17:25" }, { days: "135" }]));
    expect(c.rows.map((r) => r.same)).toEqual([false, true, false, false]);
    expect([c.allSame, c.diff, checkSummary(c)]).toEqual([false, 3, "3 of 4 flights differ from the plan card. The game's times are the real ones."]);
  });
  it("is missing where the game has no such flight (another number, or another way)", () => {
    const flights = game().filter((g) => g.no !== "1204").map((g) => (g.no === "1203" ? { ...g, to: "BBB" } : g));
    const c = compareCard(legs, [...flights, { no: "1201", from: "DDD", to: "HUB", days: "1234567", dep: "09:00", arr: "11:00" }]);
    expect(c.rows.map((r) => [r.L.no, !!r.g, r.same])).toEqual([["1201", true, true], ["1202", true, true], ["1203", false, false], ["1204", false, false]]);
    expect(checkSummary(c)).toBe("2 of 4 flights aren't in the game's schedule yet.");
  });
  it("can't be checked when the game can't be read, and never files at once then", () => {
    const c = compareCard(legs, null, "The game answered 503.");
    expect([c.allSame, c.found, c.miss, c.err]).toEqual([false, 0, 4, "The game answered 503."]);
  });
  it("reads the airline's schedule from its game link", () => {
    expect(gameLink("gander.airlinesim.aero", 113)).toBe("https://gander.airlinesim.aero/app/info/enterprises/113?tab=3");
    expect(gameLink(null, 113)).toBeNull();
  });
});

describe("filing", () => {
  it("pairs each outbound with the return numbered one apart, as filePlan does", () => {
    expect(pairLegs([{ no: "1201", from: "HUB", to: "DDD" }, { no: "1202", from: "DDD", to: "HUB" }, { no: "1203", from: "HUB", to: "AAA" }, { no: "1204", from: "AAA", to: "HUB" }]))
      .toEqual([[0, 1], [2, 3]]);
    // two apart is not a pair; the return is filed alone
    expect(pairLegs([{ no: "1201", from: "HUB", to: "AAA" }, { no: "1203", from: "AAA", to: "HUB" }])).toEqual([[0, null], [1, null]]);
    // a return listed first pairs with the outbound after it
    expect(pairLegs([{ no: "1202", from: "DDD", to: "HUB" }, { no: "1201", from: "HUB", to: "DDD" }])).toEqual([[0, 1]]);
  });
  it("makes a frequency id as importFlight does", () => {
    expect(fileKey(NOW, () => 0.123456789)).toBe("f" + NOW.toString(36) + "4fz");
  });
  const card: PlanCardRow = { id: 7, airline_id: 1, aircraft_id: 5, base_code: "HUB", title: "AAA + DDD", note: null, updated_at: T0 };
  const routes: RouteRow[] = [
    { id: 4, airline_id: 1, hub_code: "HUB", dest_code: "DDD", city: "Mumbai", country_label: "India", distance_km: 1400, market_id: 1, stars: 3, source: "research", removed: false,
      removed_note: null, city_override: null, distance_override_km: null, market_override_id: null, market_cleared: false, stars_override: null, updated_at: T0 },
    { id: 1, airline_id: 1, hub_code: "HUB", dest_code: "AAA", city: "Paris", country_label: "France", distance_km: 700, market_id: null, stars: 3, source: "research", removed: false,
      removed_note: null, city_override: null, distance_override_km: null, market_override_id: null, market_cleared: false, stars_override: null, updated_at: T0 },
  ];
  const markets = new Map<number, MarketRow>([[1, { id: 1, airline_id: 1, name: "Asia", layout: "Leisure Plus" }]]);
  // the launch fare (fare_launch_pct) is a new frequency's fare since 21 Oct, whatever its market (the market's fare until then)
  const launch = buildRules({ ...input, settings: { ...input.settings, fare_launch_pct: 100 } });
  const x: FilingInput = {
    worldId: 1, today: TODAY, nowMs: NOW, rand: () => 0.5, rules: launch, aircraft: fleet[4] as TailAircraft, card, legs, game: null, cabin: { id: 11, code: "321-LEI", cost: 450000 },
    cabinLogged: false, bases: ["HUB", "FOC"], routes, markets,
    profiles: [{ id: 1, code: "S1", airline_id: null, up_to_km: 1000 }, { id: 2, code: "S2", airline_id: null, up_to_km: 99999 }], airports: new Map(),
  };
  const strip = (c: Change[]) => c.map((ch) => ({ ...ch, values: ch.values && { ...ch.values, ...("legacy_key" in ch.values ? { legacy_key: "k" } : {}) } }));
  it("is one action: the aircraft in service, its first cabin fit, and each outbound with its return in UTC", () => {
    const ch = filingChanges(x);
    expect(ch.map((c) => [c.table, c.op])).toEqual([["aircraft", "update"], ["spending_log", "insert"], ["rotations", "insert"], ["flight_legs", "insert"], ["flight_legs", "insert"],
      ["rotations", "insert"], ["flight_legs", "insert"], ["flight_legs", "insert"]]);
    expect(ch[0]).toEqual({ table: "aircraft", op: "update", key: { id: 5 }, base: T0,
      values: { status: "active", base_code: "HUB", cabin_config_id: 11 } });
    expect(ch[1]).toEqual({ table: "spending_log", op: "insert", values: { world_id: 1, airline_id: 1, spent_on: TODAY, amount: 450000, kind: "cabin", aircraft_id: 5,
      note: "T-005 first cabin fit (321-LEI)" } });
    expect(strip(ch.slice(2))).toEqual([
      { table: "rotations", op: "insert", as: "rotation 1", values: { world_id: 1, airline_id: 1, legacy_key: "k", launched_on: TODAY, route_id: 4, service_code: "S2", fare_pct: 100 } },
      // HUB 21:00 every day to DDD (+5:30), landing 08:00 the next day there; back at 07:40, which is before the landing, so
      // the day after (the old planner's day; every day, so the same UTC days)
      { table: "flight_legs", op: "insert", from: { rotation_id: "rotation 1" }, values: { world_id: 1, airline_id: 1, leg_no: 1, flight_no: 1201, origin_code: "HUB",
        dest_code: "DDD", aircraft_id: 5, days_utc: ALL, dep_utc_min: 1260, block_min: 330 } },
      { table: "flight_legs", op: "insert", from: { rotation_id: "rotation 1" }, values: { world_id: 1, airline_id: 1, leg_no: 2, flight_no: 1202, origin_code: "DDD",
        dest_code: "HUB", aircraft_id: 5, days_utc: ALL, dep_utc_min: 130, block_min: 360 } },
      { table: "rotations", op: "insert", as: "rotation 2", values: { world_id: 1, airline_id: 1, legacy_key: "k", launched_on: TODAY, route_id: 1, service_code: "S1", fare_pct: 100 } },
      { table: "flight_legs", op: "insert", from: { rotation_id: "rotation 2" }, values: { world_id: 1, airline_id: 1, leg_no: 1, flight_no: 1203, origin_code: "HUB",
        dest_code: "AAA", aircraft_id: 5, days_utc: ALL, dep_utc_min: 900, block_min: 80 } },
      { table: "flight_legs", op: "insert", from: { rotation_id: "rotation 2" }, values: { world_id: 1, airline_id: 1, leg_no: 2, flight_no: 1204, origin_code: "AAA",
        dest_code: "HUB", aircraft_id: 5, days_utc: ALL, dep_utc_min: 1030, block_min: 85 } },
    ]);
    expect(String((ch[2]?.values as { legacy_key: string }).legacy_key)).toMatch(new RegExp("^f" + NOW.toString(36) + "[0-9a-z]{3}$"));
  });
  it("with the game's times, files them and the plan card takes them too (departure, arrival and days)", () => {
    const g = game([{ dep: "21:10", arr: "08:10" }, {}, { dep: "15:30", arr: "17:55" }, {}]);
    const ch = filingChanges({ ...x, game: g });
    const legsOut = ch.filter((c) => c.table === "flight_legs").map((c) => [c.values?.flight_no, c.values?.dep_utc_min, c.values?.block_min]);
    expect(legsOut).toEqual([[1201, 1270, 330], [1202, 130, 360], [1203, 930, 85], [1204, 1030, 85]]);
    expect(ch.filter((c) => c.table === "plan_card_legs")).toEqual([
      { table: "plan_card_legs", op: "update", key: { id: 71 }, base: T0, values: { dep_utc_min: 1270 } },
      { table: "plan_card_legs", op: "update", key: { id: 73 }, base: T0, values: { dep_utc_min: 930, block_min: 85 } }]);
    // the card itself is left as it is: its legs are its rows (the old planner's copy of them went with the clean-up)
    expect(ch.map((c) => c.table)).not.toContain("plan_cards");
  });
  // 18 Oct: filing gave every new aircraft its order's cabin (none) and logged the type's default cabin's price
  it("fits the plan card's cabin over the order's, and logs the first fit at its price", () => {
    const cfg = new Map(configs.map((c) => [c.id, c]));
    // the card names 321-CMF (14) and the order 321-LEI (11): the card's wins
    const cabin = filingCabin({ config_id: 14 }, fleet[4] as TailAircraft, cfg);
    expect(cabin).toEqual({ id: 14, code: "321-CMF", cost: 600000, from: "card" });
    const ch = filingChanges({ ...x, card: { ...card, config_id: 14 }, cabin });
    expect(ch[0]?.values).toEqual({ status: "active", base_code: "HUB", cabin_config_id: 14 });
    expect(ch[1]).toEqual({ table: "spending_log", op: "insert", values: { world_id: 1, airline_id: 1, spent_on: TODAY, amount: 600000, kind: "cabin", aircraft_id: 5,
      note: "T-005 first cabin fit (321-CMF)" } });
    // no cabin on the card: the order's
    expect(filingCabin({ config_id: null }, fleet[4] as TailAircraft, cfg)).toEqual({ id: 11, code: "321-LEI", cost: 450000, from: "order" });
  });
  it("with no cabin on the card or the order, sets none and logs nothing (never the type's default)", () => {
    const cfg = new Map(configs.map((c) => [c.id, c]));
    const bare = { ...(fleet[4] as TailAircraft), order_config_id: null };
    expect(filingCabin({ config_id: null }, bare, cfg)).toBeNull();
    const ch = filingChanges({ ...x, aircraft: bare, cabin: null });
    expect(ch[0]?.values).toEqual({ status: "active", base_code: "HUB" });
    expect(ch.map((c) => c.table)).not.toContain("spending_log");
    // an aircraft given a cabin by hand before filing keeps it
    expect(filingChanges({ ...x, aircraft: { ...bare, cabin_config_id: 13 }, cabin: null })[0]?.values).toEqual({ status: "active", base_code: "HUB" });
  });
  it("knows where an airline has a station: only where it has an active route (every airport its active flights touch)", () => {
    const s = stationsOf(rules, 1);
    for (const code of ["HUB", "AAA", "FOC"]) expect(s.has(code)).toBe(true);
    // DDD is only on T-005's plan card: no station yet
    expect(s.has("DDD")).toBe(false);
    // 22 Oct bug (N022AW (JFK)'s card left MCI and STL unmarked): a base or point-to-point station with no flights isn't a
    // station in the game, nor is an airport flown only by a retired aircraft or by a leg that flies on no day
    const withPlans = buildRules({ ...input,
      airline_bases: [...input.airline_bases,
        { id: 9, airline_id: 1, airport_code: "CCC", role: "station", is_main: false, bank_times: null, flight_no_from: null, last_flight_no: null, position: 9 },
        { id: 10, airline_id: 1, airport_code: "EEE", role: "focus", is_main: false, bank_times: null, flight_no_from: null, last_flight_no: null, position: 10 }],
      aircraft: [...input.aircraft, { ...(input.aircraft[0] as (typeof input.aircraft)[number]), id: 7, registration: "T-007", status: "retired" }],
      flight_legs: [...input.flight_legs,
        { ...(input.flight_legs[0] as (typeof input.flight_legs)[number]), id: 90, aircraft_id: 7, origin_code: "HUB", dest_code: "GGG" },
        { ...(input.flight_legs[0] as (typeof input.flight_legs)[number]), id: 91, days_utc: [], origin_code: "HUB", dest_code: "HHH" }] });
    const p = stationsOf(withPlans, 1);
    for (const code of ["CCC", "EEE", "GGG", "HHH"]) expect(p.has(code)).toBe(false);
    expect(p.has("HUB")).toBe(true);
  });
  it("chooses or clears a plan card's cabin as one change on the card", () => {
    expect(cardCabinChange(card, 14)).toEqual([{ table: "plan_cards", op: "update", key: { id: 7 }, base: T0, values: { config_id: 14 } }]);
    expect(cardCabinChange({ ...card, config_id: 14 }, null)).toEqual([{ table: "plan_cards", op: "update", key: { id: 7 }, base: T0, values: { config_id: null } }]);
    expect(cardCabinChange({ ...card, config_id: 14 }, 14)).toEqual([]);
  });
  // 21 Oct (spec docs/specs/2026-10-21-cabins-new-rule.md §3): the card suggests its cabin by the rule (manual §5); by
  // distance since 26 Oct (the range over 65% of block time decides; no market or route choice overrides it)
  it("suggests the cabin the card's routes call for by distance, with the airline's routes laid in", () => {
    // the start without the card's two routes (as rules_input('flown') when they aren't flown yet), the layouts with their names
    const start = buildRules({ ...input, routes: input.routes.filter((r) => r.id !== 4 && r.id !== 1), cabin_configs: [
      { id: 11, code: "321-LEI", aircraft_type_id: 1, seats: 195, cabin: "Leisure" }, { id: 13, code: "321-STD", aircraft_type_id: 1, seats: 216, cabin: "Standard" },
      { id: 12, code: "E195-LEI", aircraft_type_id: 2, seats: 112, cabin: "Leisure" }, { id: 14, code: "321-CMF", aircraft_type_id: 1, seats: 141, cabin: "Comfort" },
      { id: 15, code: "321-LP", aircraft_type_id: 1, seats: 166, cabin: "Leisure Plus" }] });
    // HUB–DDD at 4,200 km is in the Leisure Plus range (3,500 to 6,500)
    const far = routes.map((r) => (r.id === 4 ? { ...r, distance_km: 4200 } : r));
    const laid = withRoutes(start, far, [...markets.values()]);
    expect(laid.routes.get(4)).toMatchObject({ market_id: 1, market: "Asia", market_layout: "Leisure Plus", cabin_choice: null });
    // HUB–DDD is 690 of the card's 855 block minutes a day: 81% in the 3,500–6,500 km range, over 65%: Leisure Plus
    const s = cardCabin(laid, card, planLegs);
    expect(s).toMatchObject({ code: "321-LP", config_id: 15, reason: "3,500–6,500 km is 81% of block time: Leisure Plus", missing: true, differs: true });
    expect(suggestionWords(s)).toEqual({ text: "suggested: 321-LP", reason: "3,500–6,500 km is 81% of block time: Leisure Plus" });
    // a card's cabin that differs shows in amber; the suggestion itself doesn't, nor no cabin (that has its own pill)
    expect([cabinDiffers(s, "321-LEI"), cabinDiffers(s, "321-LP"), cabinDiffers(s, ""), cabinDiffers(null, "321-LEI")]).toEqual([true, false, false, false]);
    expect(cardCabin(laid, { ...card, config_id: 15 }, planLegs)).toMatchObject({ missing: false, differs: false });
    // Use the suggestion is the card-cabin save there already is
    expect(cardCabinChange(card, s?.config_id ?? null)).toEqual([{ table: "plan_cards", op: "update", key: { id: 7 }, base: T0, values: { config_id: 15 } }]);
    // since 26 Oct a route's own choice no longer wins: distance alone decides
    const own = withRoutes(start, far.map((r) => (r.id === 4 ? { ...r, cabin_choice: "Comfort" } : r)), [...markets.values()]);
    expect(cardCabin(own, card, planLegs)?.code).toBe("321-LP");
    // nor does the markets' layout matter: without them read, the same
    expect(cardCabin(withRoutes(start, far), card, planLegs)).toMatchObject({ code: "321-LP", reason: "3,500–6,500 km is 81% of block time: Leisure Plus" });
    // at its own 1,400 km HUB–DDD is short haul with HUB–AAA: all of it under 3,500 km, Leisure
    expect(cardCabin(withRoutes(start, routes, [...markets.values()]), card, planLegs)).toMatchObject({ code: "321-LEI", reason: "under 3,500 km is 100% of block time: Leisure" });
    // an aircraft the start doesn't hold: nothing to suggest
    expect(cardCabin(laid, { ...card, aircraft_id: 99 }, planLegs)).toBeNull();
  });
  // 21 Oct (spec docs/specs/2026-10-21-frequencies-and-fares.md §2): every plan card shows the fare level of each route it flies
  it("shows each route's fare level once per direction, on its first leg that way: the ladder's levels, the new one once on the fare plan, launch for a route not flown yet", () => {
    // since 26 Oct (spec docs/specs/2026-10-26-fare-ladder-per-direction.md §3) each direction has its own level
    const ladder = { settings: { launch_pct: 100 }, routes: [
      { route_id: 1, hub: "HUB", dest: "AAA", direction: "out", cabin: "economy", level: 110, new_level: 115, planned: true },
      { route_id: 1, hub: "HUB", dest: "AAA", direction: "out", cabin: "business", level: 105, new_level: 110, planned: false },
      { route_id: 1, hub: "HUB", dest: "AAA", direction: "back", cabin: "economy", level: 100, new_level: 100, planned: false },
      { route_id: 1, hub: "HUB", dest: "AAA", direction: "back", cabin: "business", level: 95, new_level: 95, planned: false }] };
    // HUB–DDD (legs 71 and 72) isn't on the ladder: launch each way; HUB–AAA out (73) at its levels, economy's move on the
    // fare plan, and back (74) at its own
    const fares = cardFareLevels(launch, card, planLegs, ladder);
    expect(fares?.map((f) => [f.route, f.direction, f.flown, f.words])).toEqual([
      ["HUB–DDD", "out", false, "launch (+0% of the default price)"], ["HUB–DDD", "back", false, "launch (+0% of the default price)"],
      ["HUB–AAA", "out", true, "economy +15%, business +5% of the default price"], ["HUB–AAA", "back", true, "economy +0%, business −5% of the default price"]]);
    expect([...fareCells(legs, fares)]).toEqual([[71, "launch (+0% of the default price)"], [72, "launch (+0% of the default price)"],
      [73, "economy +15%, business +5% of the default price"], [74, "economy +0%, business −5% of the default price"]]);
    // an answer from before 26 Oct (no from and to): matched by its route, either way round
    expect([...fareCells(legs, [{ route_id: 1, route: "HUB–AAA", flown: true, cabins: [], launch_pct: 100, words: "economy +5% of the default price" } as never])])
      .toEqual([[73, "economy +5% of the default price"], [74, "economy +5% of the default price"]]);
    // Ryanair's launch: −15%, from the airline's own setting when the ladder gives none
    const ryan = buildRules({ ...input, settings: { ...input.settings, fare_launch_pct: 100 },
      airlines: input.airlines.map((a) => (a.id === 1 ? { ...a, settings: { fare_launch_pct: 85 } } : a)) });
    expect(cardFareLevels(ryan, card, planLegs, { routes: [] })?.map((f) => f.words)).toEqual(Array(4).fill("launch (−15% of the default price)"));
    // no ladder read yet, or an aircraft the start doesn't hold: nothing shown
    expect(cardFareLevels(launch, card, planLegs, undefined)).toBeNull();
    expect(cardFareLevels(launch, { ...card, aircraft_id: 99 }, planLegs, ladder)).toBeNull();
    expect(fareCells(legs, null).size).toBe(0);
  });
  it("logs no second cabin fit and leaves an aircraft already in service as it is", () => {
    expect(filingChanges({ ...x, cabinLogged: true }).map((c) => c.table)).not.toContain("spending_log");
    const active = { ...(fleet[4] as TailAircraft), status: "active" };
    expect(filingChanges({ ...x, aircraft: active }).map((c) => c.table)).toEqual(["rotations", "flight_legs", "flight_legs", "rotations", "flight_legs", "flight_legs"]);
    expect(filingChanges({ ...x, cabin: { code: "321-LEI", cost: 0 } }).map((c) => c.table)).not.toContain("spending_log");
  });
  it("flies a pair the airline has only the other way round as that route, and adds a route it doesn't have", () => {
    const flip = { ...x, legs: [legs[1], legs[0]].filter((l) => !!l) as typeof legs, bases: ["FOC"] };
    const ch = filingChanges(flip);
    expect(ch.filter((c) => c.table === "flight_legs").map((c) => [c.values?.leg_no, c.values?.origin_code, c.values?.dest_code, c.values?.flight_no]))
      .toEqual([[1, "HUB", "DDD", 1201], [2, "DDD", "HUB", 1202]]);
    const none = filingChanges({ ...x, routes: [], airports: new Map([["DDD", { code: "DDD", city: "Mumbai", country_code: "IN", country_name: "India", lat: 19.09, lon: 72.87, utc_offset: 5,
      correction: 5.5, world_row: null }], ["HUB", { code: "HUB", city: "Hub", country_code: "GB", country_name: null, lat: 51.15, lon: -0.19, utc_offset: 0, correction: null, world_row: null }]]) });
    expect(none.filter((c) => c.table === "routes")).toEqual([
      { table: "routes", op: "insert", as: "route 1", values: { world_id: 1, airline_id: 1, hub_code: "HUB", dest_code: "DDD", city: "Mumbai", country_label: "India", distance_km: 7194,
        market_id: null, stars: 3, source: "added" } },
      { table: "routes", op: "insert", as: "route 2", values: { world_id: 1, airline_id: 1, hub_code: "HUB", dest_code: "AAA", city: "AAA", country_label: null, distance_km: 0,
        market_id: null, stars: 3, source: "added" } }]);
    expect(none.filter((c) => c.table === "rotations").map((c) => c.from)).toEqual([{ route_id: "route 1" }, { route_id: "route 2" }]);
  });
});

describe("filing a station route (spec docs/specs/2026-10-22-station-role.md)", () => {
  // Test Air gets a station at CCC (point-to-point, no banks) and the route CCC–DDD; the card flies it with station
  // numbers, the return listed first
  const stInput: RulesInput = { ...input, settings: { ...input.settings, fare_launch_pct: 100, station_flight_no_from: 100, station_flight_no_to: 999 },
    airline_bases: [...input.airline_bases, { id: 9, airline_id: 1, airport_code: "CCC", role: "station", is_main: false, bank_times: null, flight_no_from: null, last_flight_no: null, position: 9 }] };
  const stRules = buildRules(stInput);
  const stRoute: RouteRow = { id: 30, airline_id: 1, hub_code: "CCC", dest_code: "DDD", city: "Mumbai", country_label: "India", distance_km: 1100, market_id: null, stars: 4,
    source: "research", removed: false, removed_note: null, city_override: null, distance_override_km: null, market_override_id: null, market_cleared: false, stars_override: null, updated_at: T0 };
  const stLegs = cardLegs(stRules, [
    { id: 81, plan_card_id: 8, position: 1, flight_no: 102, origin_code: "DDD", dest_code: "CCC", days_utc: ALL, dep_utc_min: 600, block_min: 110, service_code: "S2", updated_at: T0 },
    { id: 82, plan_card_id: 8, position: 2, flight_no: 101, origin_code: "CCC", dest_code: "DDD", days_utc: ALL, dep_utc_min: 420, block_min: 110, service_code: "S2", updated_at: T0 },
  ]);
  it("files it as a base route: one rotation on the station's route, its outbound from the station first", () => {
    const ch = filingChanges({
      worldId: 1, today: TODAY, nowMs: NOW, rand: () => 0.5, rules: stRules, aircraft: fleet[4] as TailAircraft,
      card: { id: 8, airline_id: 1, aircraft_id: 5, base_code: "CCC", title: "DDD", note: null, updated_at: T0 }, legs: stLegs, game: null, cabin: null, cabinLogged: false,
      bases: ["HUB", "FOC", "CCC"], routes: [stRoute], markets: new Map(), profiles: [{ id: 2, code: "S2", airline_id: null, up_to_km: 99999 }], airports: new Map(),
    });
    expect(ch.filter((c) => c.table === "routes")).toEqual([]);
    expect(ch.filter((c) => c.table === "rotations").map((c) => [c.values?.route_id, c.values?.service_code, c.values?.fare_pct])).toEqual([[30, "S2", 100]]);
    expect(ch.filter((c) => c.table === "flight_legs").map((c) => [c.values?.leg_no, c.values?.origin_code, c.values?.dest_code, c.values?.flight_no]))
      .toEqual([[1, "CCC", "DDD", 101], [2, "DDD", "CCC", 102]]);
  });
});

describe("adding, changing and removing an aircraft", () => {
  it("adds a tail in service, and refuses a registration in use", () => {
    expect(addTailChanges(1, 1, { id: " T-009 ", type: "A321 NEO LIGHT", config: "321-LEI", base: "HUB", acquired: "used" }, rules, configs, fleet)).toEqual({ changes: [
      { table: "aircraft", op: "insert", values: { world_id: 1, registration: "T-009", airline_id: 1, aircraft_type_id: 1, cabin_config_id: 11, base_code: "HUB", status: "active", acquired: "used" } }] });
    // since 26 Oct a new aircraft must say whether it came new or used
    expect(addTailChanges(1, 1, { id: "T-009", type: "A321 NEO LIGHT", config: "321-LEI", base: "HUB" }, rules, configs, fleet)).toEqual({ error: "Say whether it came new or used." });
    expect(addTailChanges(1, 1, { id: "T-009", type: "A321 NEO LIGHT", config: "321-LEI", base: "HUB", acquired: "" }, rules, configs, fleet)).toEqual({ error: "Say whether it came new or used." });
    expect(addTailChanges(1, 1, { id: "T-001", type: "", config: "", base: "" }, rules, configs, fleet)).toEqual({ error: "That tail id exists." });
    expect(addTailChanges(1, 1, { id: "  ", type: "", config: "", base: "" }, rules, configs, fleet)).toEqual({ changes: [] });
    const retired = [...fleet, ac(9, "T-009", { status: "retired", retired_on: "2026-10-01", extra: {} })];
    expect(addTailChanges(1, 1, { id: "T-009", type: "", config: "", base: "FOC" }, rules, configs, retired)).toEqual({ changes: [
      { table: "aircraft", op: "update", key: { id: 9 }, base: T0, values: { airline_id: 1, aircraft_type_id: null, cabin_config_id: null, base_code: "FOC", status: "active",
        retired_on: null } }] });
  });
  const ctx = { rules, configs, aircraft: fleet, airline: { is_lcc: false } };
  it("changes one field of one row at a time", () => {
    expect(editTailChange(fleet[0] as TailAircraft, "id", " t-010 ", ctx)).toEqual({ changes: [{ table: "aircraft", op: "update", key: { id: 1 }, base: T0, values: { registration: "T-010" } }] });
    expect(editTailChange(fleet[0] as TailAircraft, "id", "t-002", ctx)).toEqual({ error: "That registration already exists." });
    expect(editTailChange(fleet[0] as TailAircraft, "id", "T-001", ctx)).toEqual({ changes: [] });
    // a new type: the cabin goes unless the type has it, and becomes the type's only one where it has just one
    expect(editTailChange(fleet[2] as TailAircraft, "type", "A321 NEO LIGHT", ctx)).toEqual({ changes: [{ table: "aircraft", op: "update", key: { id: 3 }, base: T0,
      values: { aircraft_type_id: 1, cabin_config_id: null } }] });
    expect(editTailChange({ ...(fleet[0] as TailAircraft), aircraft_type_id: 1, cabin_config_id: null }, "type", "E195-E2", ctx)).toEqual({ changes: [{ table: "aircraft", op: "update",
      key: { id: 1 }, base: T0, values: { aircraft_type_id: 2, cabin_config_id: 12 } }] });
    expect(editTailChange(fleet[0] as TailAircraft, "config", "321-CMF", ctx)).toEqual({ changes: [{ table: "aircraft", op: "update", key: { id: 1 }, base: T0, values: { cabin_config_id: 14 } }] });
    expect(editTailChange(fleet[0] as TailAircraft, "base", "FOC", ctx)).toEqual({ changes: [{ table: "aircraft", op: "update", key: { id: 1 }, base: T0, values: { base_code: "FOC" } }] });
    expect(editTailChange(fleet[0] as TailAircraft, "maint", "HUB nights", ctx)).toEqual({ changes: [{ table: "aircraft", op: "update", key: { id: 1 }, base: T0,
      values: { maintenance_note: "HUB nights" } }] });
    expect(editTailChange(fleet[0] as TailAircraft, "notes", "spare", ctx)).toEqual({ changes: [{ table: "aircraft", op: "update", key: { id: 1 }, base: T0,
      values: { extra: { tail: { notes: "spare" } } } }] });
    expect(editTailChange({ ...(fleet[0] as TailAircraft), extra: { tail: { notes: "spare" } } }, "notes", "", ctx)).toEqual({ changes: [{ table: "aircraft",
      op: "update", key: { id: 1 }, base: T0, values: { extra: {} } }] });
  });
  it("removes an aircraft by retiring it (never a delete), and not while it flies a route", () => {
    expect(removeTailChanges(fleet[0] as TailAircraft, true, TODAY)).toEqual({ error: "This tail still flies routes. Reassign them first." });
    expect(removeTailChanges({ ...(fleet[1] as TailAircraft), extra: { tail: { notes: "x" } } }, false, TODAY)).toEqual({ changes: [
      { table: "aircraft", op: "update", key: { id: 2 }, base: T0, values: { status: "retired", retired_on: TODAY } }] });
    expect(deleteTailChanges(fleet[0] as TailAircraft, [{ id: 1, updated_at: T0, legs: [{ id: 1, updated_at: T0 }, { id: 2, updated_at: T0 }] }], TODAY).map((c) => [c.table, c.op, c.key]))
      .toEqual([["flight_legs", "delete", { id: 1 }], ["flight_legs", "delete", { id: 2 }], ["rotations", "delete", { id: 1 }], ["aircraft", "update", { id: 1 }]]);
  });
});

// remove a delivery (the old data-deldel, build pull request 12): it leaves the deliveries board, as it left the old list
describe("removing a delivery", () => {
  const ordered = (id: number, reg: string, x: Partial<TailAircraft> = {}) => ac(id, reg, { status: "on_order", delivery_at: "2026-10-20T08:00:00+00:00",
    order_note: "plan", ...x });
  const fleet = [ac(1, "T-001"), ac(2, "T-002"), ordered(5, "T-005"), ordered(6, "T-006"), ordered(7, "T-007")];
  const order = { ordered_on: null, delivery_at: null, order_base_code: null, order_config_id: null, order_note: null };
  it("one nothing points at is removed; the others are left as they are", () => {
    expect(removeDeliveryChanges(fleet[2] as TailAircraft, { money: false, pointedAt: false }, TODAY)).toEqual([
      { table: "aircraft", op: "delete", key: { id: 5 }, base: T0 },
    ]);
  });
  it("one with a plan card keeps its row with its order cleared, so it leaves the board; one the capture or money spent knows is retired today", () => {
    expect(removeDeliveryChanges(fleet[4] as TailAircraft, { money: false, pointedAt: true }, TODAY))
      .toEqual([{ table: "aircraft", op: "update", key: { id: 7 }, base: T0, values: order }]);
    expect(removeDeliveryChanges(fleet[4] as TailAircraft, { money: true, pointedAt: true }, TODAY))
      .toEqual([{ table: "aircraft", op: "update", key: { id: 7 }, base: T0, values: { status: "retired", retired_on: TODAY } }]);
    const kept = { ...(fleet[4] as TailAircraft), ...order };
    expect(deliveryRows([kept], [], buildRules(base), new Map(), [], NOW, TODAY)).toEqual([]);
  });
  it("one in service too loses only its order, and stays a tail", () => {
    const filed = ac(8, "T-008", { delivery_at: "2026-10-01T08:00:00+00:00", ordered_on: "2026-09-20", order_base_code: "HUB", order_note: "plan",
      extra: { tail: { notes: "n" } } });
    expect(removeDeliveryChanges(filed, { money: true, pointedAt: true }, TODAY)).toEqual([
      { table: "aircraft", op: "update", key: { id: 8 }, base: T0, values: order },
    ]);
  });
  it("the deliveries board lists every aircraft with a delivery that isn't retired, in the order they were added", () => {
    const retired = ac(9, "T-009", { status: "retired", delivery_at: "2026-10-20T08:00:00+00:00" });
    expect(deliveryRows([retired], [], buildRules(base), new Map(), [], NOW, TODAY)).toEqual([]);
    expect(deliveryRows([fleet[3] as TailAircraft, fleet[2] as TailAircraft], [], buildRules(base), new Map(), [], NOW, TODAY).map((r) => r.a.registration))
      .toEqual(["T-005", "T-006"]);
  });
});

describe("7-day lines on the deliveries board (28 Oct, spec docs/specs/2026-10-27-long-haul-lines.md §2)", () => {
  const line: PlanLineRow = { id: 40, airline_id: 1, aircraft_type_id: 1, name: "TA line 1", note: null, updated_at: T0 };
  const lineLegs: PlanLineLegRow[] = [
    { id: 401, line_id: 40, position: 1, line_day: 1, flight_no: 1201, origin_code: "HUB", dest_code: "BBB", dep_utc_min: 0, block_min: 425, service_code: "S3", updated_at: T0 },
    { id: 402, line_id: 40, position: 2, line_day: 1, flight_no: 1202, origin_code: "BBB", dest_code: "HUB", dep_utc_min: 600, block_min: 425, service_code: "S3", updated_at: T0 },
  ];
  const card = (id: number, aircraft: number, offset: number | null): PlanCardRow => ({
    id, airline_id: 1, aircraft_id: aircraft, base_code: "HUB", title: null, note: null, config_id: null, line_id: offset == null ? null : 40, line_day_offset: offset, updated_at: T0 });
  // T-005 (arrived) holds day 1, T-006 (on order) day 3; T-007 was retired from day 2; T-008 and T-009 are on order without a card
  const lineFleet = [...fleet, ac(7, "T-007", { status: "retired" }), ac(8, "T-008", { status: "on_order", delivery_at: "2026-10-20T00:00:00+00:00", order_base_code: "FOC" }),
    ac(9, "T-009", { status: "on_order", delivery_at: "2026-10-18T00:00:00+00:00" }), ac(10, "T-010", { status: "on_order", aircraft_type_id: 2 })];
  const cards = [card(1, 5, 0), card(2, 6, 2), card(3, 7, 1), card(4, 1, null)];
  const slots = lineSlots(line, cards, lineFleet, new Set([1]), NOW, 7);

  it("each slot with the aircraft that holds it and its state; a retired aircraft's card frees its place", () => {
    expect(slots.map((s) => [s.offset, s.aircraft?.registration ?? "", s.state])).toEqual([
      [0, "T-005", "arrived"], [1, "", "empty"], [2, "T-006", "ordered"], [3, "", "empty"], [4, "", "empty"], [5, "", "empty"], [6, "", "empty"]]);
    expect(slots[1]?.retired).toEqual(["T-007"]);
    expect(nextFreeOffset(slots)).toBe(1);
    expect(slotState(ac(1, "T-001"), new Set(), NOW)).toBe("filed");
    expect(slotState(ac(6, "T-006", { status: "on_order", delivery_at: "2026-10-12T00:00:00+00:00" }), new Set(), NOW)).toBe("arrived");
    expect(nextFreeOffset(lineSlots(line, [0, 1, 2, 3, 4, 5, 6].map((k) => card(10 + k, k === 3 ? 5 : 100 + k, k)), [...lineFleet, ...[0, 1, 2, 4, 5, 6].map((k) => ac(100 + k, `L-${k}`))], new Set(), NOW))).toBeNull();
  });
  it("the size is settings.line_aircraft, 7 without it", () => {
    expect(lineSize(rules)).toBe(7);
    expect(lineSize(buildRules({ ...input, settings: { ...input.settings, line_aircraft: 7 } }))).toBe(7);
  });
  it("the aircraft that can take the next card: the line's airline and type, on order or arrived, no card, soonest first", () => {
    expect(lineCandidates(line, lineFleet, cards).map((a) => a.registration)).toEqual(["T-009", "T-008"]);
  });
  it("Write the next card: the card on the line at the offset and its legs on their weekdays, as one action", () => {
    const res = lineCardChanges({ worldId: 1, line, legs: lineLegs, aircraft: lineFleet.find((a) => a.id === 8) as TailAircraft, offset: 1, size: 7 });
    expect("changes" in res && res.changes).toEqual([
      { table: "plan_cards", op: "insert", as: "card", values: { world_id: 1, airline_id: 1, aircraft_id: 8, base_code: "FOC", title: "TA line 1 · 2 of 7", line_id: 40, line_day_offset: 1 } },
      { table: "plan_card_legs", op: "insert", from: { plan_card_id: "card" }, values: { world_id: 1, position: 1, flight_no: 1201, origin_code: "HUB", dest_code: "BBB", days_utc: [2], dep_utc_min: 0, block_min: 425, service_code: "S3" } },
      { table: "plan_card_legs", op: "insert", from: { plan_card_id: "card" }, values: { world_id: 1, position: 2, flight_no: 1202, origin_code: "BBB", dest_code: "HUB", days_utc: [2], dep_utc_min: 600, block_min: 425, service_code: "S3" } },
    ] satisfies Change[]);
    // the base falls back to where the line starts
    const r2 = lineCardChanges({ worldId: 1, line, legs: lineLegs, aircraft: ac(9, "T-009", { status: "on_order" }), offset: 6, size: 7 });
    expect("changes" in r2 && r2.changes[0]?.values).toMatchObject({ base_code: "HUB", line_day_offset: 6 });
    expect("changes" in r2 && r2.changes[1]?.values).toMatchObject({ days_utc: [7] });
    expect(lineCardChanges({ worldId: 1, line, legs: lineLegs, aircraft: lineFleet.find((a) => a.id === 10) as TailAircraft, offset: 1, size: 7 })).toEqual({ error: "T-010 isn't this line's airline and type." });
    expect(lineCardChanges({ worldId: 1, line, legs: lineLegs, aircraft: ac(9, "T-009"), offset: 7, size: 7 })).toEqual({ error: "a line's offset is 0 to 6, not 7" });
  });
  it("the line's check across the cards that exist: the days missing until all 7, then complete", () => {
    const legsFor = (offset: number, cardId: number): PlanLegRow[] => lineLegs.map((l, i) => ({
      id: cardId * 10 + i, plan_card_id: cardId, position: i + 1, flight_no: l.flight_no, origin_code: l.origin_code, dest_code: l.dest_code,
      days_utc: [((l.line_day + offset - 1) % 7) + 1], dep_utc_min: l.dep_utc_min, block_min: l.block_min, service_code: l.service_code, updated_at: T0 }));
    const legsBy = new Map([[1, legsFor(0, 1)], [2, legsFor(2, 2)]]);
    const c = lineCheck(rules, line, slots, (id) => legsBy.get(id) ?? []);
    expect(c && !("error" in c) && [c.cards, c.complete, c.missing_days]).toEqual([2, false, [2, 4, 5, 6, 7]]);
    expect(lineCheckWords(c)).toMatchObject({ text: "2 of 7 cards · missing Tue Thu Fri Sat Sun", level: "warn" });
    expect(lineCheck(rules, line, slots.map((s) => ({ ...s, card: null, aircraft: null, state: "empty" as const })), () => [])).toBeNull();
    expect(lineCheckWords(null)).toMatchObject({ text: "no cards yet" });
    // all 7: complete, every flight daily
    const all = [0, 1, 2, 3, 4, 5, 6].map((k) => ac(200 + k, `L-${k}`, { status: "on_order" }));
    const allCards = all.map((a, k) => card(300 + k, a.id, k));
    const allLegs = new Map(allCards.map((c2, k) => [c2.id, legsFor(k, c2.id)]));
    const r7 = buildRules({ ...input, aircraft: [...input.aircraft, ...all.map((a) => ({ id: a.id, registration: a.registration, airline_id: 1, aircraft_type_id: 1, base_code: null, status: "on_order" }))] });
    const full = lineCheck(r7, line, lineSlots(line, allCards, all, new Set(), NOW), (id) => allLegs.get(id) ?? []);
    expect(lineCheckWords(full)).toMatchObject({ text: "complete: every flight daily, each route both ways", level: "ok" });
  });
});
