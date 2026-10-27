// The route page's logic (spec docs/specs/2026-10-21-route-page.md §3; model.ts, "the route page"): the header's words,
// the last 7 days against the 7 before, the since-launch chart (under 14 days it says so; the fare level as a step; each
// event a marker with its words in the tip), profit an aircraft hour by week, the events cut to 10, the rivals and our
// share at each scan, the address's route, and the connections at both ends by the planning library's rule. Every figure
// is route_story()'s, tested in database/tests/route_story_test.sql; these test only how the page words and lays them out.
// Last, the page itself renders from a story with every board (and from a short one), with its links.
import { readFileSync } from "node:fs";
import { createElement } from "react";
import { renderToString } from "react-dom/server";
import { MemoryRouter } from "react-router";
import { describe, expect, it } from "vitest";
import { buildRules, type RulesInput } from "@rules";
import { FoldBoard } from "../../ui/FoldBoard";
import {
  barLayout, eventWords, levelSteps, listCut, parseRouteKey, rivalLines, routeConnections, shareLine, shareWeeklyNote, storyChartLayout, storyFareWords, storyHeader, storyLayout, storyWeekOnWeek, weekBars,
  type RouteStory, type StoryDay, type StoryEvent, type StoryWeek,
} from "./model";
import { RouteStoryView } from "./RoutePage";

const nice = (d: string) => d;   // the days as they are, so the words are fixed
const dayAt = (i: number) => new Date(Date.UTC(2026, 9, 2 + i)).toISOString().slice(0, 10);   // 2 Oct + i
const fig = (x: Partial<StoryDay> = {}) => ({
  flights: 2, passengers: 320, seats: 360, load_pct: 88.9, eco_pax: 300, eco_seats: 336, eco_load_pct: 89.3, bus_pax: 20, bus_seats: 24, bus_load_pct: 83.3,
  eco_fare: 300, bus_fare: 900, revenue: 0.1, costs: 0.06, profit: 0.04, block_hours: 4, profit_per_hour: 0.01, ...x,
});
const day = (i: number, x: Partial<StoryDay> = {}): StoryDay => ({ day: dayAt(i), ...fig(x) });
const week = (from: string, to: string, x: Partial<StoryWeek> = {}): StoryWeek => ({ from, to, days: 7, ...fig({ flights: 14, passengers: 2240, profit: 0.28, block_hours: 28, profit_per_hour: 0.01 }), ...x });

function story(x: Partial<RouteStory> = {}): RouteStory {
  return {
    route_id: 7, as_of: "2026-10-21T12:00:00.000Z", latest_day: "2026-10-21",
    route: {
      id: 7, hub: "JFK", dest: "ORD", pair: "JFK-ORD", city: "Chicago", stars: 5, distance_km: 1185, removed: false,
      market: { id: 1, name: "US domestic", layout: "Leisure" },
      airline: { id: 1, code: "PA", name: "Pan Am" }, launched: "2026-10-01", launched_from: "rotation", launched_days: 20,
    },
    now: {
      departures: { out: 14, back: 14 }, rotations: 2, types: [{ type_id: 3, type: "A320NEO LIGHT", aircraft: 2 }],
      fares: [
        { cabin: "economy", level: 105, move: "up", new_level: 110, planned: true, applied: false } as RouteStory["now"]["fares"][number],
        { cabin: "business", level: 100, move: "hold", new_level: 100, planned: false, applied: false } as RouteStory["now"]["fares"][number],
      ],
      launch_pct: 100, week_of: "2026-10-17",
    },
    days: Array.from({ length: 20 }, (_, i) => day(i)),
    weeks: [week("2026-10-15", "2026-10-21", { load_pct: 91.2, passengers: 2300, profit: 0.31, profit_per_hour: 0.011, eco_fare: 315 }),
      week("2026-10-08", "2026-10-14", { load_pct: 88.9, passengers: 2240, profit: 0.28, profit_per_hour: 0.01, eco_fare: 300 }),
      week("2026-10-01", "2026-10-07", { days: 6, profit_per_hour: null, block_hours: null })],
    events: [
      { day: "2026-10-18", kind: "rival", words: "Air China started here, 14 a week", rival: "Air China", change: "started", then: 0, now: 14 },
      { day: "2026-10-17", kind: "fare", words: "economy up to 105%", cabin: "economy", level: 105, move: "up", dropped: false },
      { day: "2026-10-12", kind: "fare", words: "economy +5% fare test, dropped", cabin: "economy", change_pct: 5, dropped: true },
      { day: "2026-10-10", kind: "frequency added", words: "PA 103/104 added, days 135" },
      { day: "2026-10-01", kind: "launched", words: "launched" },
    ],
    rivals: {
      scan: { id: 9, taken_at: "2026-10-18T08:00:00.000Z" }, week_before: { id: 8, taken_at: "2026-10-11T08:00:00.000Z" },
      ours: 28, rivals_weekly: 14, share: 66.7, ours_before: 28, rivals_before: 0, share_before: 100,
      airlines: [{ airline_id: 50, name: "Air China", weekly: 14, weekly_before: 0, change: 14 }],
      shares: [{ scan_id: 8, taken_at: "2026-10-11T08:00:00.000Z", ours: 28, rivals: 0, share: 100 },
        { scan_id: 9, taken_at: "2026-10-18T08:00:00.000Z", ours: 28, rivals: 14, share: 66.7 }],
    },
    scans: { latest: { id: 9, taken_at: "2026-10-18T08:00:00.000Z" }, week_before: { id: 8, taken_at: "2026-10-11T08:00:00.000Z" }, since_launch: [] },
    notes: [],
    ...x,
  };
}

describe("the route page's header", () => {
  it("words the route, its cabin, launch, departures each way, the types and each cabin's fare level with its move", () => {
    const h = storyHeader(story(), nice, "layout Leisure (under 3,500 km)");
    expect(h.title).toBe("JFK–ORD");
    expect(h.city).toBe("Chicago");
    expect(h.line).toBe("Pan Am · 1,185 km · US domestic · layout Leisure (under 3,500 km)");
    expect(h.launched).toBe("launched 2026-10-01 · 20 days");
    expect(h.departures).toBe("14 a week each way");
    expect(h.types).toBe("A320neo ×2");
    expect(h.fares).toEqual(["economy 105% · up to 110% · on the fare plan", "business 100% · hold"]);
  });
  it("says so for a route not flown yet, first flights from the history, and departures that differ each way", () => {
    const s = story();
    expect(storyHeader({ ...s, route: { ...s.route, launched: null, launched_from: null, launched_days: null }, now: { ...s.now, departures: { out: 0, back: 0 }, types: [], fares: [] } }, nice, "layout Leisure (under 3,500 km)"))
      .toMatchObject({ launched: "not flown yet", departures: "no flights in the schedule", types: "", fares: [] });
    expect(storyHeader({ ...s, route: { ...s.route, launched_from: "history", launched_days: 1 }, now: { ...s.now, departures: { out: 7, back: 3 } } }, nice, "layout Leisure (under 3,500 km)"))
      .toMatchObject({ launched: "first flights 2026-10-01 · 1 day", departures: "7 a week out, 3 back" });
    expect(storyFareWords({ cabin: "economy", level: 95, move: "down", new_level: 90, planned: true, applied: true })).toBe("economy 95% · down to 90% · seen in the game");
    // since 26 Oct a row per direction, its airports that way round first
    expect(storyFareWords({ from: "ORD", to: "JFK", cabin: "economy", level: 100, move: "down", new_level: 95, planned: false, applied: false }))
      .toBe("ORD → JFK economy 100% · down to 95%");
  });
});

describe("the layout its distance calls for (manual §5, since 26 Oct)", () => {
  // the library's small world (lib/rules/cases/_base.json): Leisure under 3,500 km, Leisure Plus to under 6,500, Comfort
  // beyond; Test Air (1) flies HUB–AAA 700 km, HUB–BBB 5,600 and HUB–CCC 6,720 (its own choice Leisure Plus, market Comfort)
  const base = (JSON.parse(readFileSync(new URL("../../../../../lib/rules/cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
  const rules = buildRules(base);
  const at = (hub: string, dest: string, km: number | null, id = 1) => ({ hub, dest, distance_km: km, airline: { id, code: "TA", name: "Test Air" } });
  it("is the planning library's range for the route's distance, as Routes' header words it", () => {
    expect(storyLayout(rules, at("HUB", "AAA", 700))).toBe("layout Leisure (under 3,500 km)");
    expect(storyLayout(rules, at("HUB", "BBB", 5600))).toBe("layout Leisure Plus (3,500–6,500 km)");
    expect(storyLayout(rules, at("HUB", "CCC", 6720))).toBe("layout Comfort (6,500 km and over)");
    // the edges: 3,500 km is Leisure Plus, 6,500 Comfort
    expect(storyLayout(rules, at("HUB", "AAA", 3500))).toBe("layout Leisure Plus (3,500–6,500 km)");
    expect(storyLayout(rules, at("HUB", "AAA", 6500))).toBe("layout Comfort (6,500 km and over)");
  });
  it("takes the library's distance (the route's, else the great circle) when the story has none", () => {
    expect(storyLayout(rules, at("HUB", "CCC", null))).toBe("layout Comfort (6,500 km and over)");
    expect(storyLayout(rules, at("ZZZ", "YYY", null))).toBe("no layout (no distance)");
  });
  it("follows the airline's own settings, and a low-cost airline flies Standard whatever the distance", () => {
    const own = buildRules({ ...base, airlines: base.airlines.map((a) => (a.id === 1 ? { ...a, settings: { cabin_leisure_max_km: 6000 } } : a)) });
    expect(storyLayout(own, at("HUB", "BBB", 5600))).toBe("layout Leisure (under 6,000 km)");
    const lcc = buildRules({ ...base, airlines: base.airlines.map((a) => (a.id === 1 ? { ...a, is_lcc: true } : a)) });
    expect(storyLayout(lcc, at("HUB", "CCC", 6720))).toBe("layout Standard");
  });
});

describe("the last 7 days against the 7 before", () => {
  it("compares the week ending on the latest captured day with the one before, each with its arrow", () => {
    const w = storyWeekOnWeek(story());
    expect(w).toMatchObject({ from: "2026-10-15", to: "2026-10-21", compared: true, days: "" });
    // a week with a day missing (a capture missed) isn't like for like: the heading says so
    const s = story();
    expect(storyWeekOnWeek({ ...s, weeks: [s.weeks[0] as StoryWeek, { ...(s.weeks[1] as StoryWeek), days: 5 }] }).days).toBe("7 days with flights against 5");
    expect(w.rows.map((r) => [r.key, r.now, r.then, r.text])).toEqual([
      ["load", "91.2%", "88.9%", "▲ 2.3 pts"],
      ["passengers", "2,300", "2,240", "▲ 60"],
      ["profit", "310k", "280k", "▲ 30k"],
      ["per_hour", "11.0k", "10.0k", "▲ 1.0k"],
      ["eco_fare", "315 AS$", "300 AS$", "▲ 15 AS$"],
      ["bus_fare", "900 AS$", "900 AS$", "= same"],
    ]);
    expect(w.rows.find((r) => r.key === "load")?.arrow).toBe("up");
  });
  it("has nothing to compare without the week before (a gap), and no business row on an economy-only route", () => {
    const s = story({ weeks: [week("2026-10-15", "2026-10-21", { bus_fare: null }), week("2026-10-01", "2026-10-07", { bus_fare: null })] });
    const w = storyWeekOnWeek(s);
    expect(w.compared).toBe(false);
    expect(w.rows.every((r) => r.text === "—" && r.arrow === null)).toBe(true);
    expect(w.rows.map((r) => r.key)).not.toContain("bus_fare");
    expect(storyWeekOnWeek(story({ weeks: [] }))).toMatchObject({ from: null, compared: false });
  });
  it("words a fall and a single point", () => {
    const s = story({ weeks: [week("2026-10-15", "2026-10-21", { load_pct: 87.9, profit: -0.02 }), week("2026-10-08", "2026-10-14", { load_pct: 88.9, profit: 0.03 })] });
    const r = storyWeekOnWeek(s).rows;
    expect(r.find((x) => x.key === "load")).toMatchObject({ arrow: "down", text: "▼ 1 pt" });
    expect(r.find((x) => x.key === "profit")).toMatchObject({ now: "−20k", arrow: "down", text: "▼ 50k" });
  });
  it("words profit an aircraft hour to a tenth of a thousand, so a small rise isn't '▲ 0k' (the copy's DEL–CCU, 21 Oct)", () => {
    const s = story({ weeks: [week("2026-10-15", "2026-10-21", { profit_per_hour: 0.00996 }), week("2026-10-08", "2026-10-14", { profit_per_hour: 0.00956 })] });
    expect(storyWeekOnWeek(s).rows.find((x) => x.key === "per_hour")).toMatchObject({ now: "10.0k", then: "9.6k", arrow: "up", text: "▲ 0.4k" });
  });
});

describe("the since-launch chart", () => {
  it("says so under 14 days of flights", () => {
    expect(storyChartLayout(story({ days: Array.from({ length: 13 }, (_, i) => day(i)) }), nice)).toBeNull();
  });
  it("lays out a column a day to the latest captured day, both cabins' loads, the fare level as a step and each event as a marker", () => {
    // 20 days 2–21 Oct, but none on 9 Oct: its column stays, the lines break there
    const s = story({ days: Array.from({ length: 20 }, (_, i) => day(i)).filter((d) => d.day !== "2026-10-09") });
    const g = storyChartLayout(s, nice);
    expect(g).not.toBeNull();
    if (!g) return;
    expect(g.days.length).toBe(20);
    expect(g.days[0]).toBe("2026-10-02");
    expect(g.days[19]).toBe("2026-10-21");
    expect(g.eco.split("M").length - 1).toBe(2);   // broken once, over 9 Oct
    expect(g.bus).not.toBeNull();
    expect(g.level).not.toBeNull();
    expect(g.level?.split(" L").length).toBeGreaterThan(20);   // a step up on 17 Oct
    expect(g.levelBus).toBeNull();                              // business has no ladder row of its own
    expect(g.rgrid.map((r) => r.label)).toEqual(["95%", "102.5%", "110%"]);
    // the markers: the rival, the fares and the frequency within the range (the launch on 1 Oct is before it)
    expect(g.markers.map((m) => m.kinds)).toEqual(["frequency added", "fare", "fare", "rival"]);
    expect(g.markers[1]?.tip).toBe("2026-10-12 · fare · economy +5% fare test, dropped");
    const col = g.cols[g.days.indexOf("2026-10-17")];
    expect(col?.tip).toBe("2026-10-17 · load 88.9% · economy 89.3% · business 83.3% · 2 flights · fare level 105% · fare · economy up to 105%");
    expect(g.cols[g.days.indexOf("2026-10-09")]?.tip).toBe("2026-10-09 · no flights · fare level 100%");
  });
  it("sets the level from the launch level, each ladder row from its day, never a dropped one, and business only with its own rows", () => {
    const s = story();
    expect(levelSteps(s, "economy", ["2026-10-16", "2026-10-17", "2026-10-20"])).toEqual([100, 105, 105]);
    expect(levelSteps(s, "business", ["2026-10-17"])).toBeNull();
    const withBus = story({ events: [...s.events, { day: "2026-10-19", kind: "fare", words: "business up to 105%", cabin: "business", level: 105, move: "up", dropped: false }] });
    expect(levelSteps(withBus, "business", ["2026-10-18", "2026-10-19"])).toEqual([100, 105]);
    const g = storyChartLayout(withBus, nice);
    expect(g?.levelBus).not.toBeNull();
    // since 26 Oct: the line is the out direction's, so a row for back alone doesn't move it, one for out does
    const dirs = story({ events: [...s.events,
      { day: "2026-10-19", kind: "fare", words: "back: economy up to 110%", cabin: "economy", level: 110, move: "up", dropped: false, direction: "back" },
      { day: "2026-10-20", kind: "fare", words: "out: economy up to 115%", cabin: "economy", level: 115, move: "up", dropped: false, direction: "out" }] });
    expect(levelSteps(dirs, "economy", ["2026-10-18", "2026-10-19", "2026-10-20"])).toEqual([105, 105, 115]);
  });
});

describe("profit an aircraft hour by week", () => {
  it("gives a bar for each week with block hours, oldest first, in thousands", () => {
    const b = weekBars(story(), nice);
    expect(b.map((x) => [x.x, x.y])).toEqual([["2026-10-14", 0.01], ["2026-10-21", 0.011]]);
    expect(b[1]?.tip).toBe("2026-10-15 to 2026-10-21 · 11.0k an aircraft hour · profit 310k over 28 block hours · 14 flights");
    const g = barLayout(b, null, "k");
    expect(g.grid.map((l) => l.label)).toContain("10k");
    expect(g.avg).toBeNull();
  });
});

describe("the events", () => {
  it("words each with its kind, and shows 10 with show all", () => {
    expect(eventWords({ kind: "rival", words: "Air China started here, 14 a week" })).toBe("rival · Air China started here, 14 a week");
    expect(eventWords({ kind: "launched", words: "launched" })).toBe("launched");
    const many: StoryEvent[] = Array.from({ length: 12 }, (_, i) => ({ day: dayAt(12 - i), kind: "retimed", words: `PA 101 ${i}` }));
    expect(listCut(many, false)).toMatchObject({ button: "show all 12" });
    expect(listCut(many, false).shown.length).toBe(10);
    expect(listCut(many, true)).toMatchObject({ button: "show fewer" });
    expect(listCut(story().events, false).button).toBeNull();
  });
});

describe("the rivals on the pair", () => {
  const day10 = (iso: string) => iso.slice(0, 10);
  it("lists each rival with its change, ours and our share, and which scans", () => {
    const r = rivalLines(story(), day10);
    expect(r.none).toBe(false);
    expect(r.rows).toEqual([{ id: 50, name: "Air China", weekly: "14", change: "▲ 14", before: 0, connecting: null, via: "", only: false }]);
    expect(r.connecting).toBe(false);
    expect(r.connectingLine).toBeNull();
    expect(r.ours).toBe("ours 28 a week, 66.7% of the pair (100% in the week-before scan)");
    expect(r.scans).toBe("latest scan 2026-10-18, against 2026-10-11");
  });
  it("since 23 Oct: each rival's connecting departures beside direct, the rivals that only connect after, never one total", () => {
    const s = story();
    const r = rivalLines({ ...s, rivals: { ...s.rivals,
      airlines: [{ ...s.rivals.airlines[0]!, connecting_weekly: 3, connecting_via: [{ via: "PEK", weekly: 3 }] }],
      connecting_weekly: 17,
      connecting_only: [{ airline_id: 60, name: "Icelandair", weekly: 0, weekly_before: null, change: null, connecting_weekly: 14,
                          connecting_via: [{ via: "KEF", weekly: 10 }, { via: "OSL", weekly: 4 }] }] } }, day10);
    expect(r.connecting).toBe(true);
    expect(r.rows).toEqual([
      { id: 50, name: "Air China", weekly: "14", change: "▲ 14", before: 0, connecting: "3", via: "via PEK", only: false },
      { id: 60, name: "Icelandair", weekly: "—", change: "", before: null, connecting: "14", via: "via KEF, OSL", only: true }]);
    expect(r.connectingLine).toBe("rivals 14 direct · 17 connecting a week, shown apart and never added together");
    expect(r.none).toBe(false);
    // a pair only connected on: not "no rival"
    expect(rivalLines({ ...s, rivals: { ...s.rivals, airlines: [], connecting_weekly: 14, connecting_only: [{ airline_id: 60, name: "Icelandair", weekly: 0, weekly_before: null, change: null, connecting_weekly: 14 }] } }, day10).none).toBe(false);
  });
  it("says no rival flies the pair, and no scan yet", () => {
    const s = story();
    const r = rivalLines({ ...s, rivals: { ...s.rivals, scan: null, week_before: null, airlines: [], share: null, share_before: null } }, day10);
    expect(r).toMatchObject({ none: true, ours: "ours 28 a week", scans: "no world scan yet" });
  });
  it("draws our share at each scan since launch as a small line, from two scans", () => {
    const l = shareLine(story().rivals.shares, day10);
    expect(l?.path).toBe("M4.0,4.0 L156.0,14.7");
    expect(l?.dots[1]?.tip).toBe("2026-10-18: 66.7% (ours 28, rivals 14 a week)");
    expect(shareLine(story().rivals.shares.slice(0, 1), day10)).toBeNull();
  });
  it("since 23 Oct: a note under the line when some points are the week's kept scan only, none when every point is a full scan", () => {
    const s = story().rivals.shares;
    expect(shareWeeklyNote(s, null, day10)).toBeNull();
    const weekly = [{ ...s[0]!, weekly: true }, { ...s[0]!, scan_id: 7, taken_at: "2026-10-04T08:00:00.000Z", weekly: true }, s[1]!];
    expect(shareWeeklyNote(weekly, "2026-10-18T08:00:00.000Z", day10))
      .toBe("2 weekly points before 2026-10-18 (one scan a week, kept after the monthly archive); every scan from then");
    expect(shareWeeklyNote(weekly.slice(0, 1), null, day10)).toBe("1 weekly point (one scan a week, kept after the monthly archive)");
    // the weekly points are drawn like any other
    expect(shareLine(weekly, day10)?.dots).toHaveLength(3);
  });
});

describe("the address", () => {
  it("reads the route's two codes, any case, and nothing else", () => {
    expect(parseRouteKey("JFK-ORD")).toEqual({ hub: "JFK", dest: "ORD" });
    expect(parseRouteKey("jfk-ord")).toEqual({ hub: "JFK", dest: "ORD" });
    expect(parseRouteKey("JFK")).toBeNull();
    expect(parseRouteKey("%E0%A4%A")).toBeNull();
    expect(parseRouteKey(undefined)).toBeNull();
  });
});

describe("the connections at both ends", () => {
  // the library's small world (lib/rules/cases/_base.json): Test Air (1) flies HUB–AAA (route 1), out at 07:00 UTC and
  // back at 09:00, 75 minutes each way, daily. At HUB (60 minutes to connect): CCC→HUB lands 05:00 daily (feeds the
  // 07:00, 120 minutes), FOC→HUB lands 06:30 (30 minutes: no); HUB→BBB leaves 11:30 Mon, Wed, Fri (the return lands
  // 10:15: 75 minutes, 3 a week), HUB→CCC at 10:30 (15 minutes: no). At AAA (75 minutes): AAA→DDD leaves 09:30 (the
  // outbound lands 08:15: exactly 75, daily), DDD→AAA lands 08:00 (the 09:00 return: 60 minutes, no). Other Air (2)
  // flies AAA→NBN at 09:45 on Sundays: our airlines interline, so it counts (once).
  const base = (JSON.parse(readFileSync(new URL("../../../../../lib/rules/cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
  const leg = (id: number, airline: number, rot: number | null, no: number | null, from: string, to: string, days: number[], dep: number, blockMin = 75) =>
    ({ id, airline_id: airline, rotation_id: rot, leg_no: no, flight_no: 100 + id, origin_code: from, dest_code: to, aircraft_id: null, days_utc: days, dep_utc_min: dep, block_min: blockMin });
  const daily = [1, 2, 3, 4, 5, 6, 7];
  const input: RulesInput = {
    ...base,
    rotations: [{ id: 1, airline_id: 1, route_id: 1 }],
    flight_legs: [
      leg(1, 1, 1, 1, "HUB", "AAA", daily, 420), leg(2, 1, 1, 2, "AAA", "HUB", daily, 540),
      leg(3, 1, null, null, "CCC", "HUB", daily, 180, 120), leg(4, 1, null, null, "FOC", "HUB", daily, 345, 45),
      leg(5, 1, null, null, "HUB", "BBB", [1, 3, 5], 690, 400), leg(6, 1, null, null, "HUB", "CCC", daily, 630, 400),
      leg(7, 1, null, null, "AAA", "DDD", daily, 570, 300), leg(8, 1, null, null, "DDD", "AAA", daily, 180, 300),
      leg(9, 2, null, null, "AAA", "NBN", [7], 585, 100),
    ],
  };
  const rules = buildRules(input);
  it("counts each city pair at each end, onward and feeding, by the plan card's rule", () => {
    const ends = routeConnections(rules, { id: 1, hub: "HUB", dest: "AAA" });
    expect(ends.map((e) => [e.at, e.other, e.pairs])).toEqual([["HUB", "AAA", 2], ["AAA", "HUB", 2]]);
    expect(ends[0]?.top).toEqual([{ city: "CCC", to: 0, from: 7, total: 7 }, { city: "BBB", to: 3, from: 0, total: 3 }]);
    expect(ends[1]?.top).toEqual([{ city: "DDD", to: 7, from: 0, total: 7 }, { city: "NBN", to: 1, from: 0, total: 1 }]);
  });
  it("keeps the top N, by times a week then by code", () => {
    const ends = routeConnections(rules, { id: 1, hub: "HUB", dest: "AAA" }, 1);
    expect(ends.map((e) => [e.pairs, e.top.map((c) => c.city)])).toEqual([[2, ["CCC"]], [2, ["DDD"]]]);
  });
  it("has none for a route that isn't flown", () => {
    expect(routeConnections(rules, { id: 2, hub: "HUB", dest: "BBB" }).map((e) => e.pairs)).toEqual([0, 0]);
  });
});

describe("the page", () => {
  const render = (s: RouteStory) => renderToString(createElement(MemoryRouter, null, createElement(RouteStoryView, {
    s, code: "PA", back: null, layout: "layout Leisure (under 3,500 km)",
    conns: [{ at: "JFK", other: "ORD", pairs: 12, top: [{ city: "LHR", to: 7, from: 7, total: 14 }] }, { at: "ORD", other: "JFK", pairs: 0, top: [] }],
    board: (k, children, figure) => createElement(FoldBoard, { key: k, k, folded: false, onToggle: () => undefined, figure }, children),
    onCollapse: () => undefined, onExpand: () => undefined,
  })));
  it("renders the header, the week's tiles and every board, with its links", () => {
    const html = render(story());
    expect(html).toContain("JFK–ORD");
    expect(html).toContain("US domestic · layout Leisure (under 3,500 km)");
    expect(html).toContain('href="/routes/PA/JFK-ORD"');
    for (const k of ["Since launch", "Profit an aircraft hour", "Events", "Rivals on the pair", "Connections"]) expect(html).toContain(`data-rkey="${k}"`);
    expect(html).toContain('data-figure="performance route: since launch"');
    expect(html).toContain("Air China");
    expect(html).toContain("ORD–LHR");
    expect(html).toContain("the top 1 of 12");
    expect((html.match(/data-wk=/g) ?? []).length).toBe(6);
  });
  it("says so under 14 days, with no rival and no event", () => {
    const s = story();
    const html = render({ ...s, days: s.days.slice(0, 5), events: [], rivals: { ...s.rivals, airlines: [], shares: [] } });
    expect(html).toContain("5 days with flights so far");
    expect(html).toContain("No rival flies this pair.");
    expect(html).toContain("Nothing has happened on it yet.");
  });
  it("since 23 Oct: a note under our share line only when some points are weekly", () => {
    const s = story();
    expect(render(s)).not.toContain("data-weekly-note");
    const html = render({ ...s, rivals: { ...s.rivals, daily_from: "2026-10-18T08:00:00.000Z", weekly_points: 1,
      shares: [{ ...s.rivals.shares[0]!, weekly: true }, s.rivals.shares[1]!] } });
    expect(html).toContain("data-weekly-note");
    expect(html).toMatch(/1 weekly point before [^<]*18[^<]* \(one scan a week, kept after the monthly archive\); every scan from then/);
  });
});
