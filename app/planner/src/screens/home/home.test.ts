// Home's logic (spec docs/specs/2026-10-13-home.md §3): dates as words, aircraft on order, the key figures and the hero,
// and the network map's drawing. Needs attention, the to-do board and Coming up moved to Today on 20 Oct with their tests
// (screens/today/today.test.ts; spec docs/specs/2026-10-20-today-performance-systems.md).
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildRules, type RulesInput } from "@rules";
import { shortType, familyOf } from "../../ui/aircraftNames";
import { addDays, dayDiff, dueWords, inDays, niceDate, untilText } from "../../ui/dates";
import { greeting, heroFigures, keyFigureTiles, loadTile } from "./figures";
import { arcWidth, clampView, focusView, gcPath, loadColor, mapPoint, nightPolygon, perDayWords, zoomView } from "./map";
import { familyWords, onOrder } from "./onOrder";
import type { AircraftRow, CardsRead, HomeAirline } from "./reads";

const L = "en-US";
const base = (JSON.parse(readFileSync(new URL("../../../../../lib/rules/cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
const airlines: HomeAirline[] = [{ id: 1, name: "Test Air", code: "TA", color: "#123456" }, { id: 2, name: "Other Air", code: "OA", color: "#654321" }];
const T0 = "2026-10-12T10:00:00.000000+00:00";

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
    ], rules, new Map([[2, null]]), airlines, now);
    expect(got.count).toBe(3);
    expect(got.groups.map((g) => [g.airline.name, g.rows.map((r) => r.registration), g.arrived, g.families.map(familyWords)])).toEqual([
      ["Test Air", ["R-2", "R-1"], 1, ["2 A320-family"]], ["Other Air", ["R-4"], 0, ["1 E195"]],
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
  const cards = (load: number | null, from: CardsRead["load_7_days_from"]): CardsRead => ({ airlines: [], load_7_days: load, load_7_days_flights: load == null ? 0 : 412, load_7_days_from: from });
  it("the key figures: the library's, and the group's average load as airline_cards() works it out", () => {
    const tiles = keyFigureTiles({ aircraft: 87, routes_flying: 184, flights_day: 467.857, seats_day: 75_314 }, cards(98.6, "captures"));
    expect(tiles.map((t) => t.value + t.label)).toEqual(["87aircraft", "184routes flying", "468flights a day", "75.3kseats a day", "≈99%average economy load, last 7 days of captures"]);
    expect(loadTile(cards(96.4, "reports"))).toEqual({ value: "≈96%", label: "average load, last 7 days" });
    expect(loadTile(cards(null, null))).toEqual({ value: "—", label: "average load, last 7 days (no reports yet)" });
    expect(loadTile(undefined)).toEqual({ value: "—", label: "average load, last 7 days (no reports yet)" });
  });
  it("the hero: aircraft in the air, flights today, departing in the next hour, aircraft on their routes, the load", () => {
    const h = heroFigures({ in_air: 42, flights_today: 468, departing_next_hour: 19, aircraft: 87, routes_flying: 184 }, cards(98.6, "captures"));
    expect(h.in_air).toBe(42);
    expect(h.tiles.map((t) => [t.id, t.value, t.label])).toEqual([
      ["today", "468", "flights today"], ["next", "19", "departing in the next hour"], ["fleet", "87", "aircraft on 184 routes"], ["load", "≈99%", "average load, last 7 days"],
    ]);
    expect(greeting(new Date("2026-10-13T13:40:00Z"))).toBe("Good morning. Here's the network right now.");
    expect(greeting(new Date("2026-10-13T17:00:00Z"))).toBe("Good afternoon. Here's the network right now.");
    expect(greeting(new Date("2026-10-13T02:00:00Z"))).toBe("Good evening. Here's the network right now.");
  });
});

describe("the network map (the old networkMap's drawing)", () => {
  it("colours a route by its load over 7 days: 95%+ green, 85 amber, 70 orange, under that red, grey with none", () => {
    expect([95, 94.9, 85, 84.9, 70, 69.9, null].map(loadColor)).toEqual(["#3FB37F", "#E0B341", "#E0B341", "#E8853A", "#E8853A", "#E0524B", "#7E8BA3"]);
  });
  it("draws a route wider the more round trips a day it has, up to a limit, and words them as the old tip", () => {
    expect([1, 2, 3, 5, 9].map(arcWidth)).toEqual(["1.10", "1.80", "2.50", "3.30", "3.30"]);
    expect([2, 10 / 7, 0].map(perDayWords)).toEqual(["2", "1.4", "0"]);
  });
  it("zooms around the middle or a point, never past a tenth of the width, and back out to the whole world", () => {
    const v = zoomView(null, 1.6);
    expect(v).toEqual({ x: 187.5, y: 93.75, w: 625, h: 312.5 });
    expect(zoomView(v, 1 / 1.6)).toBeNull();
    expect(zoomView({ x: 0, y: 0, w: 100, h: 50 }, 4)?.w).toBe(90);
    expect(zoomView(null, 2, 1000, 500)).toEqual({ x: 500, y: 250, w: 500, h: 250 });
    expect(clampView({ x: -50, y: 400, w: 400, h: 200 })).toEqual({ x: 0, y: 300, w: 400, h: 200 });
    expect(mapPoint({ left: 10, top: 20, width: 500, height: 250 }, null, 260, 145)).toEqual([500, 250]);
  });
  it("centres one airline on its busiest base with room for its network; the whole world without a place", () => {
    // the base at (499.47, 107.92) on the map; Paris is 6.4 across: the narrowest view, 220 wide, centred on the base
    const v = focusView([51.15, -0.19], [[51.15, -0.19], [48.86, 2.35]]);
    expect([v?.x, v?.y, v?.w, v?.h].map((x) => Math.round((x ?? NaN) * 100) / 100)).toEqual([389.47, 52.92, 220, 110]);
    expect(focusView(undefined, [])).toBeNull();
  });
  it("splits a great circle at the dateline and shades the night side with its polar cap", () => {
    expect((gcPath([35.55, 139.78], [33.94, -118.41]).match(/M/g) ?? []).length).toBe(2);
    expect(gcPath([51, 0], [51, 0])).toBe("");
    const night = nightPolygon(new Date("2026-12-21T12:00:00Z")).split(" ");
    expect(night).toHaveLength(123);
    expect(night.slice(-2)).toEqual(["1000.0,0.0", "0.0,0.0"]);   // the north pole sits in night in December
  });
});
