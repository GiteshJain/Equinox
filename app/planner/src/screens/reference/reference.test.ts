// Reference's edits, each the rows the old planner's adapter wrote for it (planner_apply_reference, planner_apply_routes,
// planner_apply_tidy), and its addresses.
import { describe, expect, it } from "vitest";
import {
  addService, addType, banOf, banSet, banText, bankBoxes, baseChange, canAddBan, clockOf, configChange, constantChange, constantValue, intOf, keyOrder, marketChange,
  mctChange, mctHours, numOf, pageId, restoreChange, scheduleLink, sectionOf, serviceChange, typeChange, worldRowChange,
  type BaseRow, type RemovedRoute, type WorldAirportRow,
} from "./model";

const base = (x: Partial<BaseRow>): BaseRow => ({ id: 1, airline_id: 1, airport_code: "JFK", role: "hub", is_main: true, parent_base_id: null,
  bank_times: ["06:45:00", "14:45:00", "22:45:00", null], flight_no_from: 1000, last_flight_no: null, hold_note: null, position: 0, updated_at: "t", ...x });
const wa = (x: Partial<WorldAirportRow>): WorldAirportRow => ({ airport_code: "ZRH", mct_min: null, night_ban_from: "00:01:00", night_ban_to: "05:59:00",
  utc_offset_override: null, game_airport_id: null, closed: false, note: null, updated_at: "w", ...x });

describe("what the boxes hold, as the adapter read them", () => {
  it("whole numbers, numbers and clock times", () => {
    expect([intOf("1000"), intOf(" 12 "), intOf("1.5"), intOf(""), intOf("abc")]).toEqual([1000, 12, null, null, null]);
    expect([numOf("1.5"), numOf("-4"), numOf("x")]).toEqual([1.5, -4, null]);
    expect([clockOf("6:45"), clockOf("06:45"), clockOf("24:00"), clockOf("0645"), clockOf("")]).toEqual(["06:45", "06:45", null, null, null]);
  });
  it("the sections in the address, and the old document's key order", () => {
    expect([sectionOf("constants"), sectionOf("night-bans/"), sectionOf(""), sectionOf("nope")]).toEqual(["constants", "night-bans", null, null]);
    expect(["Ryanair|Europe", "Kingfisher|Africa", "Pan American|Canada", "Ryanair|Asia"].sort(keyOrder)).toEqual(["Ryanair|Asia", "Ryanair|Europe", "Kingfisher|Africa", "Pan American|Canada"]);
  });
});

describe("hubs, focus cities and banks", () => {
  it("a bank time: the base's bank list with that place changed (four places, an empty box none)", () => {
    expect(bankBoxes(base({}))).toEqual(["06:45", "14:45", "22:45", ""]);
    expect(baseChange(base({}), "banks.3", "5:30", [])).toEqual({ table: "airline_bases", op: "update", key: { id: 1 }, base: "t",
      values: { bank_times: ["06:45", "14:45", "22:45", "05:30"] } });
    expect(baseChange(base({}), "banks.0", "06:45", [])).toBeNull();
    expect(baseChange(base({}), "banks.1", "", [])?.values).toEqual({ bank_times: ["06:45", null, "22:45", null] });
  });
  it("role, the hub a focus city feeds (the airline's own base there first), block and last number used", () => {
    const all = [base({}), base({ id: 2, airline_id: 2, airport_code: "LGW" }), base({ id: 3, airport_code: "LGW" })];
    expect(baseChange(base({}), "role", "focus", all)?.values).toEqual({ role: "focus" });
    expect(baseChange(base({ id: 4, airport_code: "ORD", role: "focus" }), "parent", "LGW", all)?.values).toEqual({ parent_base_id: 3 });
    expect(baseChange(base({}), "lastUsed", "1234", all)?.values).toEqual({ last_flight_no: 1234 });
    expect(baseChange(base({}), "block", "x", all)?.values).toEqual({ flight_no_from: null });
  });
  it("MCT in hours: the airport's world row in minutes, the website's figure when emptied; only the first base at an airport counts", () => {
    const jfk = wa({ airport_code: "JFK", mct_min: 90, night_ban_from: null, night_ban_to: null });
    expect(mctHours(jfk)).toBe("1.5");
    expect(mctChange(1, base({}), "1.75", [base({})], jfk, {})).toEqual({ table: "world_airports", op: "update", key: { world_id: 1, airport_code: "JFK" }, base: "w", values: { mct_min: 105 } });
    expect(mctChange(1, base({}), "", [base({})], jfk, { JFK: 75 })?.values).toEqual({ mct_min: 75 });
    expect(mctChange(1, base({ id: 2, position: 5 }), "2", [base({}), base({ id: 2, position: 5 })], jfk, {})).toBeNull();
  });
});

describe("night bans and the world's rows", () => {
  it("a ban as typed and shown; the old Add's check", () => {
    expect(banOf("0:01 - 5:59")).toEqual({ from: "00:01:00", to: "05:59:00" });
    expect(banOf("nonsense")).toEqual({ from: null, to: null });
    expect(banText(wa({}))).toBe("00:01-05:59");
    expect([canAddBan("zrh", "00:01-05:59"), canAddBan("ZR", "00:01-05:59"), canAddBan("ZRH", "late")]).toEqual([true, false, false]);
  });
  it("a new ban adds the row (its connection time from the website's figure); a changed one updates it; one removed takes the row with it when nothing else describes it", () => {
    expect(worldRowChange(1, "ZRH", undefined, banSet("00:01-05:59"), false, { ZRH: 60 })).toEqual({ table: "world_airports", op: "insert",
      values: { world_id: 1, airport_code: "ZRH", mct_min: 60, night_ban_from: "00:01:00", night_ban_to: "05:59:00", utc_offset_override: null } });
    expect(worldRowChange(1, "ZRH", wa({}), banSet("23:00-06:00"), false, {})?.values).toEqual({ night_ban_from: "23:00:00", night_ban_to: "06:00:00" });
    expect(worldRowChange(1, "ZRH", wa({}), banSet(""), false, {})).toEqual({ table: "world_airports", op: "delete", key: { world_id: 1, airport_code: "ZRH" }, base: "w" });
    expect(worldRowChange(1, "ZRH", wa({ mct_min: 60 }), banSet(""), false, {})?.op).toBe("update");
    expect(worldRowChange(1, "ZRH", wa({}), banSet(""), false, { ZRH: 60 })?.op).toBe("update");
    expect(worldRowChange(1, "ZRH", wa({}), banSet(""), true, {})?.op).toBe("update");
  });
});

describe("constants, types, layouts, markets and service profiles", () => {
  const settings = [{ id: 7, key: "bank_buffer_min", value: 0, updated_at: "s" }];
  const rules = [{ id: 8, key: "departures_per_airport_week", value: { value: 5000, note: "the game's cap" }, updated_at: "r" }];
  it("a constant is its setting's row; the departures cap its world rule's value; only numbers", () => {
    expect(constantValue("bank_buffer_min", settings, rules)).toBe("0");
    expect(constantValue("departures_per_airport_week", settings, rules)).toBe("5000");
    expect(constantChange("bank_buffer_min", "15", settings, rules)).toEqual({ table: "settings", op: "update", key: { id: 7 }, base: "s", values: { value: 15 } });
    expect(constantChange("departures_per_airport_week", "4000", settings, rules)).toEqual({ table: "world_rules", op: "update", key: { id: 8 }, base: "r",
      values: { value: { value: 4000, note: "the game's cap" } } });
    expect(constantChange("bank_buffer_min", "0", settings, rules)).toBeNull();
    expect(constantChange("bank_buffer_min", "soon", settings, rules)).toHaveProperty("error");
  });
  it("a type's, a layout's, a market's and a profile's box: that column only", () => {
    const t = { id: 3, name: "E195-E2", family_no: 83, seats_max: 146, cruise_kmh: 831, min_turn_min: 67, gap_target_h: 3, updated_at: "y" };
    expect(typeChange(t, "cruise", "840")?.values).toEqual({ cruise_kmh: 840 });
    expect(typeChange(t, "gap", "3.5")?.values).toEqual({ gap_target_h: 3.5 });
    expect(typeChange(t, "name", "E195-E2")).toBeNull();
    const c = { id: 4, code: "E195-STD", aircraft_type_id: 3, cabin: "Standard", seats: 124, updated_at: "c" };
    expect(configChange(c, "type", "", [t])?.values).toEqual({ aircraft_type_id: null });
    expect(configChange(c, "seats", "120", [t])?.values).toEqual({ seats: 120 });
    const m = { id: 5, airline_id: 1, name: "Europe", default_type_id: 3, default_config_id: 4, fare_y_pct: 100, fare_j_pct: 100, updated_at: "m" };
    expect(marketChange(m, "priceY", "", [t], [c])?.values).toEqual({ fare_y_pct: null });
    expect(marketChange(m, "config", "E195-STD", [t], [c])).toBeNull();
    const s = { id: 6, code: "R", airline_id: 3, up_to_km: 99999, note: "Ryanair", updated_at: "p" };
    expect(serviceChange(s, "airline", "Legacy", () => 3)?.values).toEqual({ airline_id: null });
    expect(serviceChange(s, "upTo", "5000", () => 3)?.values).toEqual({ up_to_km: 5000 });
  });
  it("Add type and Add profile: the old planner's new rows", () => {
    expect(addType(1).values).toMatchObject({ name: "New type", family_no: 0, seats_max: 0, cruise_kmh: 830, min_turn_min: 60, gap_target_h: 3 });
    expect(addService(1).values).toEqual({ world_id: 1, airline_id: null, code: "S5", up_to_km: 99999, note: "" });
  });
});

describe("removed routes and game schedules", () => {
  const r = (x: Partial<RemovedRoute>): RemovedRoute => ({ id: 9, airline_id: 1, hub_code: "DEL", dest_code: "SYD", removed_note: null, city_override: null,
    distance_override_km: null, market_override_id: null, market_cleared: false, stars_override: null, edit_kept: false, updated_at: "r", ...x });
  it("restore: no longer removed; an edit left with nothing else in it is kept as one, its other edits stay", () => {
    expect(restoreChange(r({}))).toEqual({ table: "routes", op: "update", key: { id: 9 }, base: "r", values: { removed: false, edit_kept: true } });
    expect(restoreChange(r({ removed_note: "too far" })).values).toEqual({ removed: false });
    expect(restoreChange(r({ edit_kept: true })).values).toEqual({ removed: false });
  });
  it("the schedule link from the airline's game ID, and its page id", () => {
    const link = scheduleLink("gander.airlinesim.aero", 113);
    expect(link).toBe("https://gander.airlinesim.aero/app/info/enterprises/113?tab=3");
    expect([pageId(link), pageId("208"), pageId("")]).toEqual(["113", "208", ""]);
  });
});
