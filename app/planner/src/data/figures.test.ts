import { describe, expect, it } from "vitest";
import { createFigures, kindsForTables, storedKey, type Args, type StoredSet } from "./figures";

/** A figures store whose live calls and route pages are recorded, not sent. */
function store(routePages: Record<number, { answer: unknown; as_of: string }> = {}) {
  const calls: { fn: string; args: Args }[] = [];
  const pages: number[] = [];
  const f = createFigures({
    call: async (fn, args) => {
      calls.push({ fn, args });
      return { live: fn };
    },
    routeStory: async (_w, id) => {
      pages.push(id);
      return routePages[id] ?? null;
    },
  });
  return { f, calls, pages };
}

const set = (generation = 4, rows: StoredSet["rows"] = []): StoredSet => ({
  worldId: 1, generation, asOf: "2026-11-11T10:31:00.000Z", captureAt: "2026-11-11T09:58:12.000Z", routesFrom: "2026-11-11T10:31:00.000Z",
  rows: rows.length ? rows : [
    { kind: "airline_cards", key: "", answer: { stored: "cards" }, as_of: "2026-11-11T10:31:00.000Z", generation },
    { kind: "cabin_charges", key: "", answer: { stored: "charges" }, as_of: "2026-11-11T10:31:00.000Z", generation },
    { kind: "cash_forecast", key: "12", answer: { stored: "forecast 12" }, as_of: "2026-11-11T10:31:00.000Z", generation },
    { kind: "competition", key: "12", answer: { stored: "competition 12" }, as_of: "2026-11-11T10:31:00.000Z", generation },
    { kind: "route_profit", key: "12:7", answer: { stored: "route profit 12 7" }, as_of: "2026-11-11T10:31:00.000Z", generation },
    { kind: "fare_ladder", key: "12", answer: { stored: "ladder 12" }, as_of: "2026-11-11T10:31:00.000Z", generation: generation - 1 },
  ],
});
const AT = "2026-11-11T12:00:00.000Z";

describe("storedKey: the keys as the migration writes them", () => {
  it("'' for a world's figure and for the ones that take no world", () => {
    expect(storedKey("growth_signals", { p_world_id: 1, p_as_of: AT })).toBe("");
    expect(storedKey("route_loads", { p_world_id: 1 })).toBe("");
    expect(storedKey("cabin_charges", { p_as_of: AT })).toBe("");
    expect(storedKey("market_service_checks", {})).toBe("");
  });
  it("the airline id, '<airline id>:<days>' for route and aircraft profit, the route id for a route's page", () => {
    expect(storedKey("cash_forecast", { p_airline_id: 12, p_as_of: AT })).toBe("12");
    expect(storedKey("fare_results", { p_airline_id: "12" })).toBe("12");
    expect(storedKey("route_profit", { p_airline_id: 12, p_days: 7, p_as_of: AT })).toBe("12:7");
    expect(storedKey("aircraft_profit", { p_airline_id: 12, p_days: 1 })).toBe("12:1");
    expect(storedKey("route_story", { p_route_id: 812, p_as_of: AT })).toBe("812");
  });
  it("none for a call the set doesn't store: other arguments, a function it doesn't hold", () => {
    expect(storedKey("competition", { p_airline_id: 12, p_limit: 10 })).toBeNull();
    expect(storedKey("cash_forecast", { p_airline_id: 12, p_orders: [{ type: 3 }] })).toBeNull();
    expect(storedKey("route_profit", { p_airline_id: 12 })).toBeNull();
    expect(storedKey("cabin_charges", { p_world_id: 1 })).toBeNull();
    expect(storedKey("capture_status", { p_world_id: 1 })).toBeNull();
    expect(storedKey("loads_by_day", { p_world_id: 1, p_from: "2026-11-10", p_to: "2026-11-10" })).toBeNull();
  });
});

describe("reading a figure", () => {
  it("with no stored set, every figure is asked of the database", async () => {
    const { f, calls } = store();
    expect(await f.read("airline_cards", { p_world_id: 1, p_as_of: AT })).toEqual({ live: "airline_cards" });
    expect(f.isStored("airline_cards", { p_world_id: 1 })).toBe(false);
    expect(calls.map((c) => c.fn)).toEqual(["airline_cards"]);
  });

  it("a figure the loaded set holds is answered from it, with no call", async () => {
    const { f, calls } = store();
    f.load(set());
    expect(await f.read("airline_cards", { p_world_id: 1, p_as_of: AT })).toEqual({ stored: "cards" });
    expect(await f.read("cabin_charges", { p_as_of: AT })).toEqual({ stored: "charges" });
    expect(await f.read("cash_forecast", { p_airline_id: 12, p_as_of: AT })).toEqual({ stored: "forecast 12" });
    expect(await f.read("route_profit", { p_airline_id: 12, p_days: 7, p_as_of: AT })).toEqual({ stored: "route profit 12 7" });
    // a figure that failed in this set keeps its older generation's answer, and still answers
    expect(await f.read("fare_ladder", { p_airline_id: 12, p_as_of: AT })).toEqual({ stored: "ladder 12" });
    expect(calls).toEqual([]);
    expect(f.isStored("airline_cards", { p_world_id: 1 })).toBe(true);
    expect(f.loaded()).toMatchObject({ generation: 4, worldId: 1, captureAt: "2026-11-11T09:58:12.000Z" });
  });

  it("falls back to the database for a key the set doesn't have, another world or other arguments", async () => {
    const { f, calls } = store();
    f.load(set());
    await f.read("cash_forecast", { p_airline_id: 99, p_as_of: AT });           // an airline added since
    await f.read("route_profit", { p_airline_id: 12, p_days: 14, p_as_of: AT }); // days the set doesn't keep
    await f.read("airline_cards", { p_world_id: 2, p_as_of: AT });               // another world
    await f.read("competition", { p_airline_id: 12, p_limit: 5, p_as_of: AT });  // the limit the planner doesn't pass
    await f.read("loads_by_day", { p_world_id: 1, p_from: "2026-11-10", p_to: "2026-11-10" });
    expect(calls.map((c) => c.fn)).toEqual(["cash_forecast", "route_profit", "airline_cards", "competition", "loads_by_day"]);
    // the live call gets the arguments as the screen gave them, p_as_of included
    expect(calls[0]?.args).toEqual({ p_airline_id: 99, p_as_of: AT });
  });

  it("after a save marks a figure live, it's read live until the next set loads, and only that kind", async () => {
    const { f, calls } = store();
    f.load(set());
    f.markLive(["cash_forecast", "route_profit"]);
    expect(f.isStored("cash_forecast", { p_airline_id: 12 })).toBe(false);
    expect(await f.read("cash_forecast", { p_airline_id: 12, p_as_of: AT })).toEqual({ live: "cash_forecast" });
    expect(await f.read("route_profit", { p_airline_id: 12, p_days: 7, p_as_of: AT })).toEqual({ live: "route_profit" });
    expect(await f.read("competition", { p_airline_id: 12, p_as_of: AT })).toEqual({ stored: "competition 12" });
    expect(calls.map((c) => c.fn)).toEqual(["cash_forecast", "route_profit"]);
  });

  it("a mark on every figure (a pair joined) reads them all live", async () => {
    const { f, calls } = store();
    f.load(set());
    f.markLive("all");
    await f.read("airline_cards", { p_world_id: 1, p_as_of: AT });
    await f.read("competition", { p_airline_id: 12, p_as_of: AT });
    expect(calls.map((c) => c.fn)).toEqual(["airline_cards", "competition"]);
  });

  it("a new generation drops every live mark and answers from the new set", async () => {
    const { f, calls } = store();
    f.load(set(4));
    f.markLive(["cash_forecast"]);
    f.markLive("all");
    f.load(set(5, [{ kind: "cash_forecast", key: "12", answer: { stored: "forecast 12, gen 5" }, as_of: AT, generation: 5 }]));
    expect(await f.read("cash_forecast", { p_airline_id: 12, p_as_of: AT })).toEqual({ stored: "forecast 12, gen 5" });
    // a figure the old set had and the new one doesn't: live
    expect(await f.read("airline_cards", { p_world_id: 1, p_as_of: AT })).toEqual({ live: "airline_cards" });
    expect(calls.map((c) => c.fn)).toEqual(["airline_cards"]);
    expect(f.loaded()?.generation).toBe(5);
    f.load(null);
    expect(f.loaded()).toBeNull();
  });

  it("a route's page: its stored row when it's as new as the set's routes_from, otherwise live", async () => {
    const { f, calls, pages } = store({
      7: { answer: { stored: "route 7" }, as_of: "2026-11-11T10:31:00.000Z" },
      8: { answer: { stored: "route 8, before the capture" }, as_of: "2026-11-11T08:00:00.000Z" },
    });
    // no set: live, and its stored row isn't asked for
    await f.read("route_story", { p_route_id: 7, p_as_of: AT });
    expect(pages).toEqual([]);
    f.load(set());
    expect(await f.read("route_story", { p_route_id: 7, p_as_of: AT })).toEqual({ stored: "route 7" });
    expect(await f.read("route_story", { p_route_id: 8, p_as_of: AT })).toEqual({ live: "route_story" });
    expect(await f.read("route_story", { p_route_id: 9, p_as_of: AT })).toEqual({ live: "route_story" });
    expect(pages).toEqual([7, 8, 9]);
    f.markLive(["route_story"]);
    await f.read("route_story", { p_route_id: 7, p_as_of: AT });
    expect(pages).toEqual([7, 8, 9]);
    expect(calls.map((c) => c.args.p_route_id)).toEqual([7, 8, 9, 7]);
  });

  it("a route page that can't be read is read live", async () => {
    const calls: string[] = [];
    const f = createFigures({ call: async (fn) => { calls.push(fn); return "live"; }, routeStory: () => Promise.reject(new Error("offline")) });
    f.load(set());
    expect(await f.read("route_story", { p_route_id: 7, p_as_of: AT })).toBe("live");
    expect(calls).toEqual(["route_story"]);
  });

  it("a failed live call passes its error to the screen", async () => {
    const f = createFigures({ call: () => Promise.reject(new Error("timeout")), routeStory: async () => null });
    await expect(f.read("airline_cards", { p_world_id: 1 })).rejects.toThrow("timeout");
  });
});

describe("the figures a save to a table reads again", () => {
  it("the fare plan's figures and the cash log, read under their tables' keys", () => {
    expect(kindsForTables(["fare_plan"])).toEqual(["fare_plan_status", "fare_ladder", "fare_results", "route_story"]);
    expect(kindsForTables(["cash_entries", "todos"])).toEqual(["cash_log"]);
    expect(kindsForTables(["todos"])).toEqual([]);
  });
});
