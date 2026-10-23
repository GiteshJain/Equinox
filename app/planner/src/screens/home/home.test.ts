// Home's logic (spec docs/specs/2026-10-13-home.md §3): dates as words, the key figures and the hero, and the network
// map's drawing; since 23 Oct (spec docs/specs/2026-10-23-attention-on-home.md) needs attention's summary cards, Today's
// until then, and no aircraft on order board (its words, onOrder, moved to screens/today/ for Aircraft to file, with its
// tests there). Needs attention, the to-do board and Coming up moved to Today on 20 Oct with their tests
// (screens/today/today.test.ts; spec docs/specs/2026-10-20-today-performance-systems.md).
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildRules, summary, type RulesInput } from "@rules";
import { addDays, dayDiff, dueWords, inDays, niceDate, untilText } from "../../ui/dates";
import { cardClean, greeting, heroFigures, keyFigureTiles, loadTile, lowestMaintenance, lowestWords } from "./figures";
import { arcWidth, clampView, focusView, gcPath, loadColor, mapPoint, nightPolygon, perDayWords, zoomView } from "./map";
import { attentionAnchor, attentionHref, countTiles, tileForHash, waitingCards, type CardsInput } from "../today/model";
import { groupAttention, withoutDismissed, type AttItem } from "../../ui/attention";
import { screen } from "../screens";
import type { CardsRead } from "./reads";

const L = "en-US";
const base = (JSON.parse(readFileSync(new URL("../../../../../lib/rules/cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
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

describe("the key figures", () => {
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

describe("the airline cards' lowest maintenance (23 Oct, spec docs/specs/2026-10-23-game-maintenance-on-tails.md)", () => {
  const all = [1, 2, 3, 4, 5, 6, 7];
  const leg = (id: number, rot: number, n: 1 | 2, from: string, to: string, aircraft: number, dep: number, blk: number) => ({
    id, airline_id: 1, rotation_id: rot, leg_no: n, flight_no: 1000 + id, origin_code: from, dest_code: to, aircraft_id: aircraft, days_utc: all, dep_utc_min: dep, block_min: blk,
  });
  const rules = buildRules({ ...base, rotations: [{ id: 1, airline_id: 1, route_id: 1 }, { id: 2, airline_id: 1, route_id: 8 }],
    flight_legs: [leg(1, 1, 1, "HUB", "AAA", 1, 420, 120), leg(2, 1, 2, "AAA", "HUB", 1, 620, 120), leg(3, 2, 1, "HUB", "FOC", 3, 480, 60), leg(4, 2, 2, "FOC", "HUB", 3, 580, 60)] });
  const libLowest = summary.airlineCards(rules).find((c) => c.airline_id === 1)?.lowest_maintenance;
  it("without fleet pages: the library's lowest estimate, with ≈", () => {
    const m = lowestMaintenance(rules, 1, undefined);
    expect(m?.from).toBe("estimate");
    expect([m?.pct, m?.level]).toEqual([libLowest?.pct, libLowest?.level]);
    expect(lowestWords(m ?? { from: "estimate", pct: 0 })).toBe(`lowest maintenance ≈${libLowest?.pct}%`);
  });
  it("the game's figure where the aircraft is on the fleet pages, without ≈; the estimate only for one without", () => {
    const both = lowestMaintenance(rules, 1, new Map([[1, { pct: 98.4, night: "2026-10-22" }], [3, { pct: 250, night: "2026-10-22" }]]));
    expect([both?.from, both?.pct, both?.level, both && lowestWords(both)]).toEqual(["game", 98, "bad", "lowest maintenance 98%"]);
    // every flying aircraft on the fleet pages, all fine: the lowest of the game's
    const fine = lowestMaintenance(rules, 1, new Map([[1, { pct: 300, night: "2026-10-22" }], [3, { pct: 180.2, night: "2026-10-22" }]]));
    expect([fine?.from, fine?.pct, fine?.level]).toEqual(["game", 180, "ok"]);
    // T-001 on the fleet pages, T-003 not: T-003 is judged on its estimate, with ≈, when that is the lower
    const t3 = summary.airlineCards(buildRules({ ...rules.input, flight_legs: rules.input.flight_legs.filter((l) => l.aircraft_id === 3) }))
      .find((c) => c.airline_id === 1)?.lowest_maintenance;
    const mixed = lowestMaintenance(rules, 1, new Map([[1, { pct: 9999, night: "2026-10-22" }]]));
    expect([mixed?.from, mixed?.pct]).toEqual(["estimate", t3?.pct]);
    // "clean" follows the same figure: the library's card on the estimate, the game's where there is one
    const card = summary.airlineCards(rules).find((c) => c.airline_id === 1);
    if (!card) throw new Error("no card");
    expect(cardClean(card, lowestMaintenance(rules, 1, undefined))).toBe(card.clean);
    const flat = { ...card, short_turns: 0, tight_turns: 0 };
    expect(cardClean(flat, fine)).toBe(true);
    expect(cardClean(flat, both)).toBe(false);
    expect(cardClean(flat, lowestMaintenance(rules, 1, new Map([[1, { pct: 104.9, night: "2026-10-22" }], [3, { pct: 300, night: "2026-10-22" }]])))).toBe(false);
    expect(cardClean({ ...flat, short_turns: 1 }, fine)).toBe(false);
    expect(cardClean({ ...flat, flying: false }, fine)).toBe(false);
    expect(cardClean(flat, null)).toBe(false);
    // an idle aircraft (T-002) counts for nothing, as on the library's card
    expect(lowestMaintenance(rules, 1, new Map([[2, { pct: 10, night: "2026-10-22" }], [1, { pct: 300, night: "2026-10-22" }], [3, { pct: 300, night: "2026-10-22" }]]))?.pct).toBe(300);
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

describe("needs attention's summary cards on Home (23 Oct, spec docs/specs/2026-10-23-attention-on-home.md)", () => {
  // a sample as Today had it on 22 Oct: an airline that can order, an aircraft to file, a to-do due, routes to fix, a
  // rival move, the Fleet group with the game's maintenance under the limit, one dismissed item
  const pa = { id: 1, name: "Pan Am", code: "PA", color: "#123456", game_id: null }, vs = { id: 2, name: "Virgin", code: "VS", color: "#654321", game_id: null };
  const items: AttItem[] = [
    { key: "fleet|maintenance|N003AW|2026-10-22", cls: "bad", screen: "tails", tail: "N003AW", text: "N003AW (JFK): maintenance 0.0%, condition 83%" },
    { key: "fleet|crew|N004AW|2026-10-22", cls: "bad", screen: "tails", tail: "N004AW", text: "N004AW (JFK): no pilots" },
    { key: "route|Pan Am|JFK|ORD", cls: "bad", screen: "performance", route: "Pan Am|JFK|ORD", text: "JFK–ORD: losing money — x" },
    { key: "route|Pan Am|JFK|BOS", cls: "warn", screen: "performance", route: "Pan Am|JFK|BOS", text: "JFK–BOS: fix or reduce — y" },
    { key: "route|Pan Am|JFK|MIA", cls: "warn", screen: "performance", route: "Pan Am|JFK|MIA", text: "JFK–MIA: fix or reduce — z" },
    { key: "threat|VS|LGW-CAI|EgyptAir|2026-10-22", cls: "warn", screen: "competition", text: "EgyptAir started on LGW–CAI, 7 a week" },
    { key: "order|Virgin|2026-10-22", cls: "ok", screen: "performance", text: "Virgin can safely order: A321neo" },
    { key: "todo|t-7", cls: "bad", screen: "today", text: "To-do (overdue): Ring the bank" },
  ];
  const shown = withoutDismissed(items, new Set(["route|Pan Am|JFK|MIA"])).shown;
  const input: CardsInput = {
    orders: [{ airline: pa, status: { kind: "later", text: "Safe from Thu, Oct 22" }, types: [], lines: [] },
      { airline: vs, status: { kind: "now", text: "Can order now" }, types: [{ when: "now", now: true, names: ["A321neo"] }], lines: [] }],
    toFile: [{ airline: pa, registration: "N023AW", type: "A321neo", config: "Y180", at: 0, base: "JFK", plan: "JFK–ORD", href: "/tails?airline=PA&file=N023AW" }],
    attention: shown,
    todos: [{ id: 7, world_id: 1, legacy_key: "t-7", title: "Ring the bank", due_on: "2026-10-20", done: false, done_at: null, updated_at: T0 }],
    game: 0, today: "2026-10-22", hrefOf: (a) => attentionHref(a, [pa, vs]), screenName: (a) => screen(a.screen).name, locale: L,
  };

  it("builds the same cards Today built on the same sample: same groups, same words, same order, dismissed left out", () => {
    const cards = waitingCards(input);
    expect(cards.map((c) => [c.kind, c.label, c.heading, c.detail, c.urgent, c.action.text])).toEqual([
      ["order", "Order now", "Virgin can safely order: A321neo", null, true, "Cash, next 14 days"],
      ["maint", "Fleet · maintenance", "N003AW (JFK): maintenance 0.0%, condition 83%", "and 1 more in Fleet", false, "See all 2"],
      ["due", "Overdue · due Tue, Oct 20", "Ring the bank", null, false, "Open the to-do"],
      ["file", "To file", "N023AW has arrived for Pan Am", "A321neo Y180 · JFK · JFK–ORD", false, "File into planner"],
      ["attention", "Needs attention", "JFK–ORD: losing money — x", "and 1 more in Routes to fix", false, "See all 2"],
      ["attention", "Needs attention", "EgyptAir started on LGW–CAI, 7 a week", "Rival moves", false, "Open Competition"],
    ]);
  });

  it("each See all opens its group's section on Today, by an anchor Today gives that section", () => {
    const cards = waitingCards(input);
    const sections = countTiles(input.toFile.length, shown).map((t) => t.key);
    const seeAll = cards.filter((c) => c.action.text.startsWith("See all"));
    expect(seeAll.map((c) => c.action.href)).toEqual(["/today#att-fleet", "/today#att-route"]);
    for (const c of seeAll) {
      const [path, hash = ""] = (c.action.href ?? "").split("#");
      expect(path).toBe("/today");
      const tile = tileForHash("#" + hash);
      expect(sections).toContain(tile);
      expect(attentionAnchor(tile as string)).toBe(hash);
      // the section lists the group whole, as many as the card says
      expect(groupAttention(shown).find((g) => g.kind === tile)?.items.length).toBe(Number(c.action.text.replace("See all ", "")));
    }
    // a card with one item opens where it's fixed, as on Today; a route its page on Performance, a rival its airline
    expect(cards.find((c) => c.heading.startsWith("EgyptAir"))?.action.href).toBe("/competition/VS");
    expect(attentionHref(shown[2] as AttItem, [pa, vs])).toBe("/performance/PA/JFK-ORD");
  });

  it("with nothing waiting there are no cards, and Home says so in one line", () => {
    expect(waitingCards({ ...input, orders: [], toFile: [], attention: [], todos: [] })).toEqual([]);
    const src = readFileSync(new URL("./Home.tsx", import.meta.url), "utf8");
    expect(src).toContain("Nothing to order or file, and nothing needs attention.");
  });

  it("sits right after the hero, before the network map; Home has no aircraft on order board any more", () => {
    const src = readFileSync(new URL("./Home.tsx", import.meta.url), "utf8");
    const at = (s: string) => src.indexOf(s);
    expect(at("<AttentionCards")).toBeGreaterThan(at("<Hero"));
    expect(at("<AttentionCards")).toBeLessThan(at("<NetworkMap"));
    expect(src).not.toMatch(/OnOrderBoard|Aircraft on order"|onOrder\(/);
    expect(() => readFileSync(new URL("./onOrder.ts", import.meta.url), "utf8")).toThrow();
  });

  it("Today no longer renders the cards but keeps every section, each with its anchor", () => {
    const src = readFileSync(new URL("../today/Today.tsx", import.meta.url), "utf8");
    expect(src).not.toMatch(/waitingCards|data-wait-card=\{/);
    expect(src).toContain('id={attentionAnchor(g.kind)}');
    expect(src).toContain('id={attentionAnchor("to-file")}');
    expect(src).toContain("onDismiss");
    expect(src).toContain("data-show-again");
  });
});
