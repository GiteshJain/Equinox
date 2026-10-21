// Competition's logic (spec docs/specs/2026-10-21-competition-analysis.md §3): the scans' line (two scans, one, none),
// the group line, a market's share with its arrow and its bar (ours first, the top rivals, the rest as others), the
// airline's share across its markets, the threats' numbers and days, the openings' words (stars, distance, rivals,
// variant, hubs first), a profile's line, and Today's threat items (the latest scan's only, each with its key and words,
// linking to Competition). Every figure itself is competition()'s (database/tests/competition_test.sql).
import { describe, expect, it } from "vitest";
import { buildRules, type RulesInput } from "@rules";
import { readFileSync } from "node:fs";
import { homeAttention, type AttentionInput } from "../today/attention";
import { ATT_KIND, attKind, groupAttention } from "../../ui/attention";
import {
  allowedWords, changeWords, dayWords, groupWords, kmWords, latestThreats, n0, openingsLine, otherListsWords, overallShare, pctWords, profileWords, rivalsWords,
  scansWords, shareBar, starsWords, threatKey, threatNumbers, threatWhen, threatsLine, trunkMonthWords, variantWords, type CompetitionAnswer, type Market, type Opening,
  type Threat,
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
      checks: [], todos: [], capture: null, backups: null, jobs: null, cards: null, growth: null, interlineOpen: null,
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
