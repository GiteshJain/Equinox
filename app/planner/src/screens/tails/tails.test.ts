// Tails' logic (spec docs/specs/2026-10-13-tails.md, "Checks"): the list's filters, the deliveries' status, the plan card
// checked against the game (same, different, missing, the game not read), filing's one action (each outbound paired with
// its return as the old filePlan pairs them, local times stored in UTC, the aircraft in service, its first cabin fit, the
// card taking the game's times), and adding, editing and removing an aircraft. The planning rules themselves are the
// library's, with their own cases (lib/rules/cases/tails.json, aircraftWeek.json, frequency.json); these run the screen's
// joins on the cases' small world.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildRules, type RulesInput, type TailIssue } from "@rules";
import type { Change } from "../../data/save";
import type { MarketRow, RouteRow } from "../routes/model";
import {
  addTailChanges, cardLegs, checkSummary, compareCard, configsFor, deleteTailChanges, deliveryRows, editTailChange, fileKey, filingChanges, filtersQuery,
  gameLink, issueWords, markCheckedChange, pairLegs, parseFilters, removeTailChanges, shownDeliveries, tailRows, tailsOf, typesFor, weekStrip,
  type ConfigRow, type FilingInput, type GameFlight, type PlanCardRow, type PlanLegRow, type TailAircraft, type TailAirline,
} from "./model";

const base = (JSON.parse(readFileSync(new URL("../../../../../lib/rules/cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
const T0 = "2026-10-12T10:00:00.000001+00:00";
const NOW = Date.parse("2026-10-13T12:00:00Z");
const TODAY = "2026-10-13";
const ALL = [1, 2, 3, 4, 5, 6, 7];

const ac = (id: number, reg: string, x: Partial<TailAircraft> = {}): TailAircraft => ({
  id, registration: reg, airline_id: 1, aircraft_type_id: 1, cabin_config_id: null, base_code: "HUB", status: "active", ordered_on: null, delivery_at: null,
  order_base_code: null, order_config_id: null, order_note: null, checked_on: null, schedule_changed_on: null, maintenance_note: null, retired_on: null,
  extra: { tails_index: id - 1 }, updated_at: T0, ...x,
});
// T-001 flies HUB–AAA every day (07:00, and 10:20 UTC back, two hours each way); T-002 is idle; T-003 (an E195 at FOC) has a
// 40-minute turn; T-005 has arrived and waits to be filed with its plan card; T-006 is on order; O-001 is another airline's
const fleet: TailAircraft[] = [
  ac(1, "T-001"), ac(2, "T-002"), ac(3, "T-003", { aircraft_type_id: 2, base_code: "FOC", cabin_config_id: 12 }), ac(4, "O-001", { airline_id: 2, base_code: "AAA" }),
  ac(5, "T-005", { status: "delivered", base_code: null, delivery_at: "2026-10-12T05:53:00+00:00", order_base_code: "HUB", order_config_id: 11, order_note: "lands HUB · AAA + DDD",
    extra: { deliveries_index: 0 } }),
  ac(6, "T-006", { status: "on_order", base_code: null, delivery_at: "2026-10-15T18:00:00+00:00", order_base_code: "HUB", extra: { deliveries_index: 1 } }),
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

describe("the list", () => {
  it("keeps its filters in the address and reads them back", () => {
    const f = { airline: "TA", base: "HUB", type: "A321 NEO LIGHT", status: "warn" as const, del: "on order" as const, card: "T-005", file: "" };
    expect(parseFilters(filtersQuery(f))).toEqual(f);
    expect(filtersQuery(parseFilters(""))).toBe("");
    expect(parseFilters("?status=nonsense&del=nope").status).toBe("");
  });
  it("lists the airline's aircraft in service in the old planner's order, and filters by base, type and status", () => {
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
    ] as TailIssue[]).map(issueWords);
    expect(words).toEqual(["flies 8.0 h a day — under the 10 h target", "1 short turn a week", "7 short turns a week", "maintenance ≈92% — under 100%, condition will fall",
      "maintenance ≈103% — little headroom", "2 turns a week under the 10-min margin", "1 leg start where the aircraft isn't", "longest gap 2:30 — under the 4 h target",
      "1 rotation off wave"]);
  });
});

describe("deliveries", () => {
  const cards: PlanCardRow[] = [{ id: 7, airline_id: 1, aircraft_id: 5, base_code: "HUB", title: "AAA + DDD", note: null, updated_at: T0 }];
  const flyingDelivered = { ...ac(1, "T-001"), delivery_at: "2026-10-01T00:00:00+00:00", order_base_code: "HUB", extra: { tails_index: 0, deliveries_index: 2 } };
  const list = [flyingDelivered, ...fleet.slice(1)];
  const rows = deliveryRows(list, airlines, rules, configMap, cards, NOW, TODAY);
  it("marks each aircraft arrived and not scheduled, on order or flying, the arrived first, then by day", () => {
    expect(rows.map((r) => [r.a.registration, r.status, r.due, r.plan, r.config, r.card?.id ?? null])).toEqual([
      ["T-005", "unscheduled", "2026-10-12", "AAA + DDD", "321-LEI", 7], ["T-006", "on order", "2026-10-15", "", "", null], ["T-001", "flying", "2026-10-01", "", "", null]]);
    expect(Math.round((rows[1]?.hrs ?? 0) * 10) / 10).toBe(54);
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
  const markets = new Map<number, MarketRow>([[1, { id: 1, airline_id: 1, name: "Asia", default_type_id: 1, default_config_id: 11, fare_y_pct: 105, fare_j_pct: null }]]);
  const x: FilingInput = {
    worldId: 1, today: TODAY, nowMs: NOW, rand: () => 0.5, rules, aircraft: fleet[4] as TailAircraft, card, legs, game: null, cabin: { code: "321-LEI", cost: 450000 },
    cabinLogged: false, tailsIndex: 4, bases: ["HUB", "FOC"], routes, markets,
    profiles: [{ id: 1, code: "S1", airline_id: null, up_to_km: 1000 }, { id: 2, code: "S2", airline_id: null, up_to_km: 99999 }], airports: new Map(),
  };
  const strip = (c: Change[]) => c.map((ch) => ({ ...ch, values: ch.values && { ...ch.values, ...("legacy_key" in ch.values ? { legacy_key: "k" } : {}) } }));
  it("is one action: the aircraft in service, its first cabin fit, and each outbound with its return in UTC", () => {
    const ch = filingChanges(x);
    expect(ch.map((c) => [c.table, c.op])).toEqual([["aircraft", "update"], ["spending_log", "insert"], ["rotations", "insert"], ["flight_legs", "insert"], ["flight_legs", "insert"],
      ["rotations", "insert"], ["flight_legs", "insert"], ["flight_legs", "insert"]]);
    expect(ch[0]).toEqual({ table: "aircraft", op: "update", key: { id: 5 }, base: T0,
      values: { status: "active", base_code: "HUB", cabin_config_id: 11, extra: { deliveries_index: 0, tails_index: 4 } } });
    expect(ch[1]).toEqual({ table: "spending_log", op: "insert", values: { world_id: 1, airline_id: 1, spent_on: TODAY, amount: 450000, kind: "cabin", aircraft_id: 5,
      note: "T-005 first cabin fit (321-LEI)" } });
    expect(strip(ch.slice(2))).toEqual([
      { table: "rotations", op: "insert", as: "rotation 1", values: { world_id: 1, airline_id: 1, legacy_key: "k", launched_on: TODAY, route_id: 4, service_code: "S2", fare_pct: 105 } },
      // HUB 21:00 every day to DDD (+5:30), landing 08:00 the next day there; back at 07:40, which is before the landing, so
      // the day after (the old planner's day; every day, so the same UTC days)
      { table: "flight_legs", op: "insert", from: { rotation_id: "rotation 1" }, values: { world_id: 1, airline_id: 1, leg_no: 1, flight_no: 1201, origin_code: "HUB",
        dest_code: "DDD", aircraft_id: 5, days_utc: ALL, dep_utc_min: 1260, block_min: 330 } },
      { table: "flight_legs", op: "insert", from: { rotation_id: "rotation 1" }, values: { world_id: 1, airline_id: 1, leg_no: 2, flight_no: 1202, origin_code: "DDD",
        dest_code: "HUB", aircraft_id: 5, days_utc: ALL, dep_utc_min: 130, block_min: 360 } },
      { table: "rotations", op: "insert", as: "rotation 2", values: { world_id: 1, airline_id: 1, legacy_key: "k", launched_on: TODAY, route_id: 1, service_code: "S1", fare_pct: null } },
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
    // a card without the old planner's copy of its typed legs is left as it is
    expect(ch.map((c) => c.table)).not.toContain("plan_cards");
  });
  it("drops the old planner's copy of the card's typed legs once they take the game's times, as its own save does", () => {
    const kept = { ...card, extra: { legs: [{ no: "1201", days: "1234567" }], colour: "blue" } };
    const g = game([{ dep: "21:10", arr: "08:10" }, {}, {}, {}]);
    expect(filingChanges({ ...x, card: kept, game: g }).filter((c) => c.table === "plan_cards")).toEqual([
      { table: "plan_cards", op: "update", key: { id: 7 }, base: T0, values: { extra: { colour: "blue" } } }]);
    // the game's times the same as the card's: the legs don't change, and neither does the copy
    expect(filingChanges({ ...x, card: kept, game: game([{}, {}, {}, {}]) }).map((c) => c.table)).not.toContain("plan_cards");
    expect(filingChanges({ ...x, card: kept }).map((c) => c.table)).not.toContain("plan_cards");
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

describe("adding, changing and removing an aircraft", () => {
  it("adds a tail at the end of the list, and refuses a registration in use", () => {
    expect(addTailChanges(1, 1, { id: " T-009 ", type: "A321 NEO LIGHT", config: "321-LEI", base: "HUB" }, rules, configs, fleet, 5)).toEqual({ changes: [
      { table: "aircraft", op: "insert", values: { world_id: 1, registration: "T-009", airline_id: 1, aircraft_type_id: 1, cabin_config_id: 11, base_code: "HUB", status: "active",
        extra: { tails_index: 5 } } }] });
    expect(addTailChanges(1, 1, { id: "T-001", type: "", config: "", base: "" }, rules, configs, fleet, 5)).toEqual({ error: "That tail id exists." });
    expect(addTailChanges(1, 1, { id: "  ", type: "", config: "", base: "" }, rules, configs, fleet, 5)).toEqual({ changes: [] });
    const retired = [...fleet, ac(9, "T-009", { status: "retired", retired_on: "2026-10-01", extra: {} })];
    expect(addTailChanges(1, 1, { id: "T-009", type: "", config: "", base: "FOC" }, rules, configs, retired, 5)).toEqual({ changes: [
      { table: "aircraft", op: "update", key: { id: 9 }, base: T0, values: { airline_id: 1, aircraft_type_id: null, cabin_config_id: null, base_code: "FOC", status: "active",
        retired_on: null, extra: { tails_index: 5 } } }] });
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
      values: { extra: { tails_index: 0, tail: { notes: "spare" } } } }] });
    expect(editTailChange({ ...(fleet[0] as TailAircraft), extra: { tails_index: 0, tail: { notes: "spare" } } }, "notes", "", ctx)).toEqual({ changes: [{ table: "aircraft",
      op: "update", key: { id: 1 }, base: T0, values: { extra: { tails_index: 0 } } }] });
  });
  it("removes an aircraft by retiring it (never a delete), and not while it flies a route", () => {
    expect(removeTailChanges(fleet[0] as TailAircraft, true, TODAY)).toEqual({ error: "This tail still flies routes. Reassign them first." });
    expect(removeTailChanges({ ...(fleet[1] as TailAircraft), extra: { tails_index: 1, deliveries_index: 3, tail: { notes: "x" } } }, false, TODAY)).toEqual({ changes: [
      { table: "aircraft", op: "update", key: { id: 2 }, base: T0, values: { status: "retired", retired_on: TODAY, extra: {} } }] });
    expect(deleteTailChanges(fleet[0] as TailAircraft, [{ id: 1, updated_at: T0, legs: [{ id: 1, updated_at: T0 }, { id: 2, updated_at: T0 }] }], TODAY).map((c) => [c.table, c.op, c.key]))
      .toEqual([["flight_legs", "delete", { id: 1 }], ["flight_legs", "delete", { id: 2 }], ["rotations", "delete", { id: 1 }], ["aircraft", "update", { id: 1 }]]);
    expect(markCheckedChange(fleet[0] as TailAircraft, TODAY)).toEqual({ table: "aircraft", op: "update", key: { id: 1 }, base: T0, values: { checked_on: TODAY } });
  });
});
