// Competition's logic (spec docs/specs/2026-10-21-competition-analysis.md §3): the scans' line (two scans, one, none),
// the group line, a market's share with its arrow and its bar (ours first, the top rivals, the rest as others), the
// airline's share across its markets, the threats' numbers and days, the openings' words (stars, distance, rivals,
// variant, hubs first), a profile's line, and Today's threat items (the latest scan's only, each with its key and words,
// linking to Competition). Since 23 Oct (spec docs/specs/2026-10-23-planner-look-competition.md) the page's answers (the
// titles), a tile's top opening, a threat's move in short, the threats newest first and the rows' counts. Since 23 Oct (spec
// docs/specs/2026-10-23-rival-fleets.md §5) a rival's fleet line and top types, and the group's order books. Every figure itself is competition()'s (database/tests/competition_test.sql).
import { describe, expect, it } from "vitest";
import { buildRules, type RulesInput } from "@rules";
import { readFileSync } from "node:fs";
import { homeAttention, type AttentionInput } from "../today/attention";
import { ATT_KIND, attKind, groupAttention } from "../../ui/attention";
import {
  airlineHeadline, groupHeadline, marketsRowWords, profilesRowWords, threatMoveWords, threatsNewestFirst, threatsRowWords, topOpeningWords,
  allowedWords, changeWords, dayWords, groupWords, kmWords, latestThreats, n0, openingsLine, otherListsWords, overallShare, pctWords, profileWords, rivalsWords,
  scansWords, shareBar, starsWords, threatKey, threatNumbers, threatWhen, threatsLine, trunkMonthWords, variantNoteWords, variantWords, type CompetitionAnswer,
  type Market, type Opening,
  type Threat, fleetWords, fleetTypesWords, orderBooks, orderBookWords, meetsWords, orderBooksRowWords, type Fleet, type OrderFlag,
} from "./model";

const scan = (id: number, at: string) => ({ id, taken_at: at });
const threat = (x: Partial<Threat> = {}): Threat => ({
  rival_id: 900, rival: "Air China", pair: "CAN-PVG", route: "PVG–CAN", hub: "PVG", dest: "CAN", kind: "started", then: 0, added: 14, now: 14, ours: 21,
  scan_id: 2, on: "2026-10-17T19:00:00.000Z", previous_id: 1, previous_on: "2026-10-06T21:00:00.000Z", until: "2026-10-24T19:00:00.000Z", latest: true,
  words: "Air China started on PVG–CAN, 14 a week", ...x,
});
const market = (x: Partial<Market> = {}): Market => ({
  market_id: 1, name: "China domestic", pairs: 12, flown: 5, ours: 40, ours_before: 30, ours_change: 10, rivals: 160, rivals_before: 150, rivals_change: 10,
  total: 200, share: 20, share_before: 16.7, share_change: 3.3,
  top: [{ airline_id: 9, name: "Air China", weekly: 100, weekly_before: 90, change: 10, share: 50 }, { airline_id: 8, name: "ANA", weekly: 40, weekly_before: 40, change: 0, share: 20 }],
  ...x,
});
const opening = (x: Partial<Opening> = {}): Opening => ({
  rank: 1, route_id: 5, route: "PVG–CTU", hub: "PVG", dest: "CTU", pair: "CTU-PVG", city: "Chengdu", stars: 5, distance_km: 1690, market_id: 1,
  rivals_weekly: 63, rivals: [{ airline_id: 9, name: "Air China", weekly: 42 }, { airline_id: 8, name: "ANA", weekly: 14 }, { airline_id: 7, name: "Qantas", weekly: 7 }],
  variant: { type_id: 3, type: "A320neo SHARP", seats: 189, range_km: 3355, size: "mid", for_reach: false }, allowed: true, allowed_by: "main hub", reason: null, ...x,
});
const answer = (x: Partial<CompetitionAnswer> = {}): CompetitionAnswer => ({
  airline_id: 5, code: "MU", name: "China Eastern", as_of: "2026-10-21T12:00:00.000Z", limit: 50,
  scans: { latest: scan(2, "2026-10-17T19:00:00.000Z"), week_before: scan(1, "2026-10-06T21:00:00.000Z"), previous: scan(1, "2026-10-06T21:00:00.000Z") },
  hubs_first: { main_hub: "PVG", departures: 420, target: 750, exempt: false, open: false },
  group: { ours: 4016, world: 97960, share: 4.1, ours_before: 3274, world_before: 83792, share_before: 3.9, ours_change: 742, world_change: 14168, share_change: 0.2 },
  markets: [market()], threats: [threat()], openings: [opening()], openings_count: 1, openings_allowed: 1, openings_left_out: 0, profiles: [],
  pairs_flown: 5, pairs_listed: 12, notes: [], ...x,
});

describe("the scans and the group line", () => {
  it("names the scans' days: two compared, one alone, none", () => {
    expect(dayWords("2026-10-17T19:00:00.000Z")).toBe("17 Oct");
    expect(scansWords(answer().scans)).toBe("latest scan 17 Oct, compared with 6 Oct");
    expect(scansWords({ latest: scan(2, "2026-10-17T19:00:00Z"), week_before: null, previous: null })).toBe("latest scan 17 Oct, the only one: nothing to compare with yet");
    expect(scansWords({ latest: null, week_before: null, previous: null })).toMatch(/^no world scan yet/);
  });
  it("the group line and its arrow in points", () => {
    expect(groupWords(answer().group)).toBe("Our airlines: 4,016 of 97,960 departures a week, 4.1% of the world");
    expect(groupWords(null)).toBe("no world scan yet");
    expect(changeWords(0.2, true)).toEqual({ arrow: "up", text: "▲ 0.2 pts" });
    expect(changeWords(-1.94, true)).toEqual({ arrow: "down", text: "▼ 1.9 pts" });
    expect(changeWords(1540)).toEqual({ arrow: "up", text: "▲ 1,540" });
    expect(changeWords(0)).toEqual({ arrow: "flat", text: "=" });
    expect(changeWords(0, true)).toEqual({ arrow: "flat", text: "= no change" });
    expect(changeWords(null)).toBeNull();
  });
});

describe("market share", () => {
  it("the bar: ours first, then the top rivals, the rest as others, adding up to 100", () => {
    const bar = shareBar(market());
    expect(bar.map((p) => [p.label, Math.round(p.pct), p.ours])).toEqual([["ours", 20, true], ["Air China", 50, false], ["ANA", 20, false], ["others", 10, false]]);
    expect(bar.reduce((s, p) => s + p.pct, 0)).toBeCloseTo(100);
    expect(shareBar(market({ total: 0, ours: 0, rivals: 0, top: [] }))).toEqual([]);
    expect(pctWords(20)).toBe("20.0%");
    expect(pctWords(null)).toBe("—");
  });
  it("the airline's share across its markets, with its change when every market has the week before", () => {
    const two = [market(), market({ market_id: 2, ours: 10, ours_before: 10, rivals: 90, rivals_before: 60, total: 100 })];
    expect(overallShare(two)).toEqual({ ours: 50, total: 300, share: 16.7, before: 16, change: 0.7 });
    expect(overallShare([market({ ours_before: null, rivals_before: null })]).change).toBeNull();
    expect(overallShare([]).share).toBeNull();
  });
});

describe("threats, openings and profiles", () => {
  it("a threat's numbers and day, and the fare pause until", () => {
    expect(threatNumbers(threat())).toBe("ours 21 a week");
    expect(threatWhen(threat())).toBe("17 Oct · fares paused until 24 Oct");
    expect(threatsLine(0)).toBe("no threats in the last 7 days");
    expect(threatsLine(2)).toBe("2 threats in the last 7 days");
  });
  it("an opening's words: stars, distance, rivals, the variant and hubs first", () => {
    expect([starsWords(5), starsWords(null), kmWords(1690), kmWords(null)]).toEqual(["5★", "—", "1,690 km", "—"]);
    expect(rivalsWords(opening())).toBe("Air China 42, ANA 14 +1 more");
    expect(rivalsWords(opening({ rivals: [] }))).toBe("none");
    expect(variantWords(opening().variant)).toBe("A320neo SHARP");
    expect(variantWords({ ...opening().variant, type: "A321XLR", for_reach: true })).toBe("A321XLR (for reach)");
    expect(allowedWords(opening())).toEqual({ ok: true, text: "yes", why: "main hub" });
    expect(allowedWords(opening({ allowed: false, allowed_by: null, reason: "hubs first: PVG at 420 of 750 departures a week, and KMG isn't contested" })))
      .toEqual({ ok: false, text: "not yet", why: "hubs first: PVG at 420 of 750 departures a week, and KMG isn't contested" });
    expect(openingsLine({ openings_count: 419, openings_allowed: 120, openings_left_out: 2 })).toBe("419 openings, 120 allowed under hubs first · 2 beyond every type's reach");
    expect(openingsLine({ openings_count: 1, openings_allowed: 1, openings_left_out: 0 })).toBe("1 opening, 1 allowed under hubs first");
  });
  it("November's trunks (manual §4): the month's line, a trunk on another airline's type, another airline's list", () => {
    expect(trunkMonthWords({ trunk_month: { on: true, from: "2026-11-01", to: "2026-11-30" }, openings_trunks: 4 }))
      .toBe("November's trunks first (1 Nov–30 Nov): 4 trunks, shortest first, hubs first suspended for them (manual §4). Whether each makes sense stays the Scheduling chat's call.");
    expect(trunkMonthWords({ trunk_month: { on: false, from: "2026-11-01", to: "2026-11-30" }, openings_trunks: 0 })).toBeNull();
    expect(trunkMonthWords({})).toBeNull();
    expect(variantWords({ ...opening().variant, type: "A350-900", for_reach: true, own: false })).toBe("A350-900 (for reach) (not on its list)");
    expect(otherListsWords(opening({ other_lists: ["VS"] }))).toBe("also on VS's list");
    expect(otherListsWords(opening())).toBeNull();
    expect(allowedWords(opening({ trunk: true, allowed_by: "November trunk" }))).toEqual({ ok: true, text: "yes", why: "November trunk" });
  });
  it("a thin 1-star city (22 Oct): the E190 under the variant, in the database's words; nothing on any other opening", () => {
    const thin = opening({ stars: 1, variant: { ...opening().variant, type: "E195-E2", seats: 146, size: "small" }, variant_alt: "E190-E2", variant_note: "or the E190-E2 if thin" });
    expect([variantWords(thin.variant), variantNoteWords(thin)]).toEqual(["E195-E2", "or the E190-E2 if thin"]);
    expect(variantNoteWords(opening())).toBeNull();
    expect(variantNoteWords(opening({ variant_note: null }))).toBeNull();
  });
  it("a profile's line: its size, growth since the week-before scan and airports", () => {
    const p = { airline_id: 9, name: "Air China", pairs_shared: 12, weekly_on_pairs: 140, weekly: 6552, weekly_before: 5012, change: 1540, airports: 120, pairs: [], biggest_airports: [] };
    expect(profileWords(p, "6 Oct")).toBe("6,552 a week (▲ 1,540 since 6 Oct) · 120 airports");
    expect(profileWords({ ...p, change: null, weekly_before: null }, "")).toBe("6,552 a week · 120 airports");
    expect(n0(null)).toBe("—");
  });
});

describe("Today: the rivals' moves from the latest scan in needs attention", () => {
  it("only the latest scan's threats, each airline's in order, the biggest first", () => {
    const a = answer({ threats: [threat({ latest: false, rival: "Old", words: "Old started on PVG–XIY, 7 a week" }), threat({ now: 7, rival: "ANA", rival_id: 8, words: "ANA started on PVG–CAN, 7 a week" }), threat()] });
    const b = answer({ airline_id: 6, code: "MH", threats: [threat({ pair: "KUL-SIN", route: "KUL–SIN", words: "Air China added on KUL–SIN, 7 → 21 a week", kind: "added", then: 7, now: 21 })] });
    const got = latestThreats([a, undefined, b]);
    expect(got.map((x) => [x.code, x.threat.words])).toEqual([
      ["MU", "Air China started on PVG–CAN, 14 a week"], ["MU", "ANA started on PVG–CAN, 7 a week"], ["MH", "Air China added on KUL–SIN, 7 → 21 a week"]]);
    expect(threatKey(got[0] as (typeof got)[number])).toBe("threat|MU|CAN-PVG|900|2026-10-17");
  });
  it("each is an amber item linking to Competition, grouped under Rival moves", () => {
    const base = (JSON.parse(readFileSync(new URL("../../../../../lib/rules/cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
    const input: AttentionInput = {
      now: new Date("2026-10-21T12:00:00Z"), today: "2026-10-21", airlines: [{ id: 5, name: "China Eastern", code: "MU", color: null }], rules: buildRules(base),
      todos: [], capture: null, backups: null, jobs: null, cards: null, growth: null, interlineOpen: null,
      threats: latestThreats([answer({ threats: [threat(), threat({ rival_id: 8, rival: "ANA", now: 7, words: "ANA started on PVG–CAN, 7 a week" })] })]),
    };
    const items = homeAttention(input);
    expect(items).toEqual([
      { key: "threat|MU|CAN-PVG|900|2026-10-17", cls: "warn", screen: "competition", text: "Air China started on PVG–CAN, 14 a week" },
      { key: "threat|MU|CAN-PVG|8|2026-10-17", cls: "warn", screen: "competition", text: "ANA started on PVG–CAN, 7 a week" },
    ]);
    expect(items.map(attKind)).toEqual(["threat", "threat"]);
    expect(groupAttention(items).map((g) => g.label)).toEqual([ATT_KIND.threat]);
    expect(ATT_KIND.threat).toBe("Rival moves");
    // none until read, and none when the latest scan showed none
    expect(homeAttention({ ...input, threats: null })).toEqual([]);
    expect(homeAttention({ ...input, threats: [] })).toEqual([]);
  });
});

describe("the page's answers and rows (23 Oct, the new look)", () => {
  it("the titles: the group's share of the world's departures, an airline's share of its markets", () => {
    expect(groupHeadline(answer().group)).toBe("4.1% of the world's departures");
    expect(groupHeadline(null)).toBe("Competition");
    expect(airlineHeadline(overallShare([market()]))).toBe("20.0% of its markets");
    expect(airlineHeadline(overallShare([]))).toBe("No markets yet");
  });
  it("a tile's top opening in one line, and none", () => {
    expect(topOpeningWords(answer())).toBe("PVG–CTU · 5★ · A320neo SHARP");
    expect(topOpeningWords(answer({ openings: [] }))).toBe("no openings");
  });
  it("a threat's move in short: started, or added with then and now", () => {
    expect(threatMoveWords(threat())).toBe("started, 14 a week");
    expect(threatMoveWords(threat({ kind: "added", then: 7, added: 7 }))).toBe("added 7: 7 → 14 a week");
  });
  it("the threats newest first, the database's order kept within a day", () => {
    const a = threat({ rival_id: 1, on: "2026-10-17T19:00:00.000Z" });
    const b = threat({ rival_id: 2, on: "2026-10-20T19:00:00.000Z" });
    const c = threat({ rival_id: 3, on: "2026-10-17T19:00:00.000Z" });
    expect(threatsNewestFirst([a, b, c]).map((t) => t.rival_id)).toEqual([2, 1, 3]);
  });
  it("the rows' counts", () => {
    expect([marketsRowWords(0), marketsRowWords(1), marketsRowWords(4)]).toEqual(["no routes yet", "1 market", "4 markets"]);
    expect([profilesRowWords(0), profilesRowWords(10)]).toEqual(["no rivals", "10 rivals"]);
    expect([threatsRowWords(0), threatsRowWords(3)]).toEqual(["none in 7 days", "3 in 7 days"]);
  });
});

describe("rivals' fleets and the order books (23 Oct, spec docs/specs/2026-10-23-rival-fleets.md)", () => {
  const fleet = (x: Partial<Fleet> = {}): Fleet => ({
    overall: 99, on_order: 44, avg_age_years: 2.1, types_count: 8,
    types: [{ type: "Airbus A321XLR", overall: 23, on_order: 10, avg_age_years: 0.2 }, { type: "Boeing 737-9 HGW", overall: 23, on_order: 5, avg_age_years: 0.1 },
            { type: "Airbus A321LR", overall: 21, on_order: 10, avg_age_years: 0.1 }, { type: "Boeing 737-8 HGW", overall: 16, on_order: 10, avg_age_years: 0.2 },
            { type: "Boeing 757-200", overall: 4, on_order: 0, avg_age_years: 24.1 }],
    overall_before: 99, on_order_before: 38, overall_change: 0, on_order_change: 6, ...x,
  });
  const flag = (x: Partial<OrderFlag> = {}): OrderFlag => ({
    airline_id: 101, name: "Icelandair", kind: "orders", fleet: 99, on_order: 44, share: 44.4, weekly: 186, on_order_change: 6, fleet_change: 0,
    on_pairs: false, at_bases: false, meets: false, words: "Icelandair: 44 on order, 44.4% of its 99 aircraft", ...x,
  });
  it("a rival's fleet: size, on order and the week's change, or why there's none", () => {
    expect(fleetWords(fleet())).toBe("99 aircraft, 44 on order, +6 on order this week");
    expect(fleetWords(fleet({ on_order_change: -3 }))).toBe("99 aircraft, 44 on order, −3 on order this week");
    expect(fleetWords(fleet({ on_order_change: 0 }))).toBe("99 aircraft, 44 on order, no change in orders this week");
    expect(fleetWords(fleet({ on_order_change: null }))).toBe("99 aircraft, 44 on order");
    expect(fleetWords(null)).toBe("fleet not read in the latest scan");
    expect(fleetWords(undefined)).toBe("fleet not read in the latest scan");
  });
  it("its top types, with what's on order, and how many more", () => {
    expect(fleetTypesWords(fleet())).toBe("Airbus A321XLR 23 (10 on order) · Boeing 737-9 HGW 23 (5 on order) · Airbus A321LR 21 (10 on order) · Boeing 737-8 HGW 16 (10 on order) · Boeing 757-200 4 +3 more");
    expect(fleetTypesWords(fleet({ types: [], types_count: 0 }))).toBeNull();
    expect(fleetTypesWords(null)).toBeNull();
  });
  it("the order books: one row per rival across our airlines, biggest share first (starting first), with whom it meets", () => {
    const pa = answer({ airline_id: 1, code: "PA", order_flags: [flag({ meets: true, on_pairs: true }), flag({ airline_id: 7, name: "New Air", kind: "starting", fleet: 0, on_order: 12, share: null, weekly: 0 }),
                                                                  flag({ airline_id: 8, name: "Mid Air", share: 30, on_order: 9, fleet: 30 })] });
    const kf = answer({ airline_id: 2, code: "KF", order_flags: [flag({ meets: true, at_bases: true }), flag({ airline_id: 7, name: "New Air", kind: "starting", fleet: 0, on_order: 12, share: null, weekly: 0 }),
                                                                  flag({ airline_id: 8, name: "Mid Air", share: 30, on_order: 9, fleet: 30 })] });
    const books = orderBooks([pa, kf, undefined]);
    expect(books.map((b) => [b.name, b.meets, b.meets_codes, b.on_pairs, b.at_bases])).toEqual([
      ["New Air", false, [], false, false], ["Icelandair", true, ["PA", "KF"], true, true], ["Mid Air", false, [], false, false]]);
    expect(orderBooks([answer()])).toEqual([]);
  });
  it("an order book's words, whom it meets, and the row's count", () => {
    expect(orderBookWords(flag())).toBe("44 on order, 44.4% of 99 aircraft");
    expect(orderBookWords(flag({ kind: "starting", fleet: 0, on_order: 12, share: null }))).toBe("12 on order, no flights yet");
    expect(orderBookWords(flag({ kind: "starting", fleet: 3, on_order: 12, share: 400 }))).toBe("12 on order, no flights yet (3 aircraft)");
    expect(meetsWords(["PA", "KF"])).toBe("meets PA, KF");
    expect(meetsWords([])).toBe("meets none of our airlines");
    expect([orderBooksRowWords(0), orderBooksRowWords(1), orderBooksRowWords(3)]).toEqual(["none", "1 rival", "3 rivals"]);
  });
});
