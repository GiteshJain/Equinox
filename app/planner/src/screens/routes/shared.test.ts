// Shared pairs on Routes and the route page (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §1, §4): each row of
// a joined pair marked on both airlines' sides with the other airline's flights a week, and an owner's unjoined pair
// offering Join this pair with the joining airline named on it. The database checks the join itself
// (database/tests/shared_pairs_test.sql); these test what the screen words and shows.
import { createElement } from "react";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { joinWords, pairMarks, pairTitle, type SharedPairRow } from "./model";
import { JoinPair, PairPill } from "./parts";

const airlines = [{ id: 1, code: "PA", name: "Pan Am" }, { id: 2, code: "KF", name: "Kingfisher" }, { id: 6, code: "MH", name: "Malaysia" }];
const row = (x: Partial<SharedPairRow>): SharedPairRow => ({
  world_id: 1, owner_airline_id: 1, joiner_airline_id: 2, owner_route_id: 10, joiner_route_id: null, owner_base: "JFK", joiner_base: "DEL",
  owner_flights_week: 14, joiner_flights_week: 0, joined_on: null, ...x,
});
const pairs = [
  row({}),                                                                                                   // PA owns JFK–DEL, no joiner
  row({ owner_route_id: 11, joiner_route_id: 21, joiner_base: "BOM", joiner_flights_week: 7, joined_on: "2026-11-06" }),   // joined by KF
  row({ owner_airline_id: 6, joiner_airline_id: 1, owner_route_id: 30, joiner_route_id: 31, owner_base: "KUL", joiner_base: "JFK", owner_flights_week: 21, joiner_flights_week: 7 }),
  row({ owner_airline_id: 6, joiner_airline_id: 2, owner_route_id: 40 }),                                    // neither side is PA's
];

describe("shared pairs on Routes", () => {
  it("marks a joined pair on both sides and offers Join on the owner's unjoined pair", () => {
    const pa = pairMarks(pairs, 1, airlines);
    expect([...pa.keys()].sort((a, b) => a - b)).toEqual([10, 11, 31]);
    expect(pa.get(10)).toMatchObject({ role: "owner", joined: false, text: null, join: { ownerRouteId: 10, joinerId: 2, joiner: "Kingfisher" } });
    expect(pa.get(11)).toMatchObject({ role: "owner", joined: true, text: "shared with KF: 7 a week", join: null });
    expect(pa.get(31)).toMatchObject({ role: "joiner", text: "follows MH: 21 a week", join: null });
    // the joiner's side shows its owner's flights, never the pair's whole
    const kf = pairMarks(pairs, 2, airlines);
    expect([...kf.entries()].map(([k, m]) => [k, m.text])).toEqual([[21, "follows PA: 14 a week"]]);
    expect(joinWords(pa.get(10) as never)).toBe("Join this pair: Kingfisher");
    expect(pairTitle(pa.get(31) as never)).toContain("this airline's fares follow Malaysia's ladder");
  });
  it("draws the Join button only where there's one to join, the joining airline named on it", () => {
    const pa = pairMarks(pairs, 1, airlines);
    const html = renderToString(createElement(JoinPair, { mark: pa.get(10) as never }));
    expect(html).toContain('data-join-pair="10"');
    expect(html).toContain("Join this pair: Kingfisher");
    expect(renderToString(createElement(JoinPair, { mark: pa.get(11) as never }))).toBe("");
    expect(renderToString(createElement(PairPill, { mark: pa.get(31) }))).toContain('data-shared="joiner"');
    expect(renderToString(createElement(PairPill, { mark: pa.get(10) }))).toBe("");
  });
});
