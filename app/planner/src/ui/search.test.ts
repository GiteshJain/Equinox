// The header's search (spec docs/specs/2026-10-14-interline-photos-reference.md, "Checks": a flight number with and without
// the airline's code in front, a registration, an airport), as the old searchAll found them, each opening its new screen.
import { describe, expect, it } from "vitest";
import { searchAll, type SearchData } from "./search";

const data: SearchData = {
  airlines: [{ id: 1, name: "Kingfisher", code: "KF" }, { id: 2, name: "Pan American", code: "AW" }],
  freqs: [
    { airline_id: 1, hub: "DEL", dest: "BOM", noOut: 1007, noBack: 1008 },
    { airline_id: 1, hub: "DEL", dest: "AMS", noOut: 1101, noBack: 1100 },
    { airline_id: 2, hub: "JFK", dest: "ORD", noOut: 1001, noBack: null },
  ],
  tails: [{ registration: "VT-AAE", airline_id: 1, type: "A321 NEO LIGHT" }, { registration: "N101AW", airline_id: 2, type: "E195-E2" }],
  deliveries: [
    { registration: "VT-AAE", airline_id: 1, plan: "Delhi", delivery_at: "2026-10-01T08:00Z", legs: null },
    { registration: "VT-AAX", airline_id: 1, plan: "lands DEL", delivery_at: "2026-10-16T09:30Z", legs: [{ no: 1015, from: "DEL", to: "GOI" }, { no: 1016, from: "GOI", to: "DEL" }] },
  ],
  routes: [
    { airline_id: 1, hub: "DEL", dest: "BOM" }, { airline_id: 1, hub: "DEL", dest: "AMS" }, { airline_id: 1, hub: "BOM", dest: "GOI" },
    { airline_id: 2, hub: "JFK", dest: "ORD" }, { airline_id: 2, hub: "JFK", dest: "BOM" },
  ],
  cities: new Map([["DEL", "Delhi"], ["BOM", "Mumbai"], ["AMS", "Amsterdam"], ["GOI", "Goa"], ["JFK", "New York"], ["ORD", "Chicago"]]),
};
const find = (q: string) => searchAll(q, data).map((h) => `${h.kind}: ${h.label} → ${h.to}`);

describe("the header's search", () => {
  it("a flight number finds every flight whose number starts with it, both ways, and a plan card's", () => {
    expect(find("100")).toEqual([
      "Flight: Kingfisher 1007 · DEL–BOM → /routes/KF/DEL-BOM", "Flight: Kingfisher 1008 · BOM–DEL → /routes/KF/DEL-BOM",
      "Flight: Pan 1001 · JFK–ORD → /routes/AW/JFK-ORD",
    ]);
    expect(find("1015")).toEqual(["Planned: Kingfisher 1015 · DEL–GOI · VT-AAX → /tails?airline=KF&card=VT-AAX"]);
  });
  it("with the airline's code in front, with or without a space, it finds the same", () => {
    expect(find("KF 1008")).toEqual(["Flight: Kingfisher 1008 · BOM–DEL → /routes/KF/DEL-BOM"]);
    expect(find("kf1008")).toEqual(find("KF 1008"));
  });
  it("a registration, any part of it and dashes ignored: in service, and on order (not yet in service)", () => {
    expect(find("vtaa")).toEqual([
      "Aircraft: VT-AAE · Kingfisher · A321 NEO LIGHT → /tails/VT-AAE",
      `On order: VT-AAX · Kingfisher · lands DEL · ${new Date(2026, 9, 16).toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" })} 09:30 UTC → /tails?airline=KF&card=VT-AAX`,
    ]);
  });
  it("an airport: each airline's routes there, with how many", () => {
    expect(find("BOM")).toEqual([
      "Airport: BOM Mumbai · Kingfisher · 2 routes → /routes?airline=KF&q=BOM", "Airport: BOM Mumbai · Pan American · 1 route → /routes?airline=AW&q=BOM",
    ]);
    expect(find("mum")).toEqual(find("BOM"));
  });
  it("two airports: the routes between them first, either way, flying or not", () => {
    expect(find("BOM-DEL")[0]).toBe("Route: DEL–BOM · Kingfisher · flying → /routes/KF/DEL-BOM");
    expect(find("JFK BOM")[0]).toBe("Route: JFK–BOM · Pan American → /routes/AW/JFK-BOM");
  });
  it("less than two letters finds nothing; at most 14 results", () => {
    expect(find("1")).toEqual([]);
    expect(searchAll("10", { ...data, freqs: Array.from({ length: 20 }, (_, i) => ({ airline_id: 1, hub: "DEL", dest: "BOM", noOut: 1000 + i, noBack: null })) }).length).toBe(14);
  });
});
