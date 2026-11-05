// Shared pairs on Performance (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §4): the route profit table's mark
// on a joined pair's rows, and the group page's Shared pairs row from shared_pairs_status() (tested in
// database/tests/shared_pairs_figures_test.sql); these test the words.
import { describe, expect, it } from "vitest";
import { sharedPairsView, sharedRowWords, type SharedPairsAnswer } from "./model";

describe("the route profit table's shared pair mark", () => {
  it("names the other airline with its flights a week and load, owner or joiner", () => {
    const pair = { airline_id: 2, code: "KF", airline: "Kingfisher", route_id: 20, flights: 14, flights_week: 14, profit: 0.2, economy: 99.6, sold_out: 13, with_loads: 14, sold_out_share: 0.93 };
    expect(sharedRowWords({ shared_role: "owner", pair })).toBe("shared with Kingfisher: 14 a week, 100%");
    expect(sharedRowWords({ shared_role: "joiner", pair: { ...pair, airline: "Malaysia", flights_week: 21, economy: 98 } })).toBe("follows Malaysia: 21 a week, 98%");
    expect(sharedRowWords({ shared_role: "owner", pair: { ...pair, economy: null } })).toBe("shared with Kingfisher: 14 a week, no loads");
    expect(sharedRowWords({})).toBeNull();
  });
});

describe("the group page's Shared pairs row", () => {
  const a: SharedPairsAnswer = {
    joined: 2, limit: { pairs: 6, from: "2026-11-06", until: "2026-11-20", left: 4 },
    pairs: [
      { owner_airline_id: 6, owner: "Malaysia", owner_code: "MH", owner_route_id: 30, joiner_airline_id: 2, joiner: "Kingfisher", joiner_code: "KF", joiner_route_id: 31,
        owner_base: "KUL", joiner_base: "DEL", joined_on: "2026-11-06", owner_flights_week: 21, joiner_flights_week: 7, owner_load: 99, joiner_load: 96, load: 98.3,
        sold_out_share: 0.8, levels: [{ direction: "out", cabin: "economy", level: 115, from: "KUL", to: "DEL" }, { direction: "back", cabin: "economy", level: 110, from: "DEL", to: "KUL" },
          { direction: "out", cabin: "business", level: 105, from: "KUL", to: "DEL" }], launch_pct: 100 },
      { owner_airline_id: 1, owner: "Pan Am", owner_code: "PA", owner_route_id: 40, joiner_airline_id: 4, joiner: "Virgin", joiner_code: "VS", joiner_route_id: 41,
        owner_base: "JFK", joiner_base: "LHR", joined_on: "2026-11-07", owner_flights_week: 14, joiner_flights_week: 0, owner_load: 97, joiner_load: null, load: null,
        sold_out_share: null, levels: [], launch_pct: 100 },
    ],
  };
  it("words the limit while it applies and each pair's flights, load and level", () => {
    const v = sharedPairsView(a, (d) => d);
    expect(v.head).toBe("2 pairs joined · at most 6 until 2026-11-20, 4 left");
    expect(v.rows.map((r) => [r.title, r.words])).toEqual([
      ["KUL–DEL · Malaysia and Kingfisher", "MH 21 + KF 7 a week · 98% full · level KUL→DEL 115%, DEL→KUL 110%"],
      ["JFK–LHR · Pan Am and Virgin", "PA 14 + VS 0 a week · no loads yet · level launch 100%"]]);
    expect(v.rows[0]?.parts).toEqual({ "6": 21, "2": 7 });
    expect(v.rows[0]?.href).toEqual({ airline: "MH", hub: "KUL", dest: "DEL" });
    expect(sharedPairsView({ joined: 0, limit: null, pairs: [] }, (d) => d)).toEqual({ head: "No pair joined yet", rows: [] });
  });
});
