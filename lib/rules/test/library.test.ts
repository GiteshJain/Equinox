/// <reference types="node" />
// The library's own behaviour beyond the cases: the typed builder's checks, settings and world rules, the command
// (src/cli.ts) for each of its commands, a plan card checked, and the case runner's matcher itself.
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { RulesError, buildRules, card, connections, positions, setting, settingNumber, worldRuleNumber, type RulesInput } from "../src/index.js";
import * as browser from "../src/browser.js";
import { run } from "../src/cli.js";
import { mismatches } from "./match.js";
import { mergeInput } from "./ask.js";

const base = (JSON.parse(readFileSync(new URL("../cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
const D7 = [1, 2, 3, 4, 5, 6, 7];
const leg = (id: number, o: string, d: string, dep: number, block: number | null, extra: object = {}) =>
  ({ id, airline_id: 1, rotation_id: null, flight_no: 1000 + id, origin_code: o, dest_code: d, aircraft_id: 1, days_utc: D7, dep_utc_min: dep, block_min: block, ...extra });
const world = (extra: Partial<RulesInput> = {}) => mergeInput(base, extra);
const dir = mkdtempSync(join(tmpdir(), "rules-cli-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));
const file = (name: string, x: unknown) => {
  const p = join(dir, name);
  writeFileSync(p, JSON.stringify(x));
  return p;
};

describe("the typed builder", () => {
  it("refuses a weekday outside 1 to 7", () => {
    expect(() => buildRules(world({ flight_legs: [leg(1, "HUB", "AAA", 360, 75, { days_utc: [0] })] }))).toThrow(RulesError);
  });
  it("refuses a departure minute outside 0 to 1439", () => {
    expect(() => buildRules(world({ flight_legs: [leg(1, "HUB", "AAA", 1440, 75)] }))).toThrow(/outside 0 to 1439/);
  });
  it("refuses something that isn't rules_input()'s document", () => {
    expect(() => buildRules({} as RulesInput)).toThrow(/settings missing/);
  });
  it("reads an airline's override first, then the world's value", () => {
    const r = buildRules(world({ airlines: [{ id: 1, settings: { fare_launch_pct: 85 } }, { id: 2 }], settings: { fare_launch_pct: 100 } }));
    expect(setting(r, "fare_launch_pct", 1)).toBe(85);
    expect(setting(r, "fare_launch_pct", 2)).toBe(100);
    expect(setting(r, "fare_launch_pct")).toBe(100);
  });
  it("names a missing setting rather than guessing it", () => {
    expect(() => settingNumber(buildRules(world()), "no_such_setting")).toThrow(/settings.no_such_setting is missing/);
  });
  it("reads a world rule kept as {value, ...} and one kept as a plain number", () => {
    expect(worldRuleNumber(buildRules(world()), "departures_per_airport_week")).toBe(5000);
    expect(worldRuleNumber(buildRules(world({ world_rules: { departures_per_airport_week: 4000 } })), "departures_per_airport_week")).toBe(4000);
  });
  it("gives the same answer for the same input and moment: no clock", () => {
    const r = buildRules(world({ flight_legs: [leg(1, "HUB", "AAA", 360, 75), leg(2, "AAA", "HUB", 510, 75)] }));
    expect(positions.positionsAt(r, "2026-10-12T06:30:00Z")).toEqual(positions.positionsAt(r, Date.parse("2026-10-12T06:30:00Z")));
  });
});

describe("a plan card checked against every rule", () => {
  const r = buildRules(world({ flight_legs: [leg(9, "BBB", "HUB", 0, 300, { aircraft_id: 2, airline_id: 2, flight_no: 3009 })] }));
  it("a good card: turns, maintenance, night bans and numbers all fine, with its connections at both ends", () => {
    const a = card.checkCard(r, { aircraft: "T-001", legs: [
      { flight_no: 1101, origin_code: "HUB", dest_code: "AAA", dep_local: "06:00" },
      { flight_no: 1102, origin_code: "AAA", dest_code: "HUB", dep_local: "09:31" }] });
    expect(a.problems).toEqual([]);
    expect(a.ok).toBe(true);
    expect(a.legs.map((l) => [l.block_min, l.block_source, l.dep_local, l.arr_local])).toEqual([[75, "estimate", "06:00", "08:15"], [75, "estimate", "09:31", "09:46"]]);
    expect(a.legs[0]?.feeders_list).toEqual([{ leg_id: 9, from: "BBB", flight_no: 3009, days: 7, gap_min: 60 }]);
    expect(a.legs[0]?.bank_out).toBe(1);
    expect(a.maintenance.ratio).toBeGreaterThan(1);
  });
  it("a bad card: a short turn, a night ban and a number used twice are each named", () => {
    const a = card.checkCard(r, { aircraft: "T-001", legs: [
      { flight_no: 1101, origin_code: "HUB", dest_code: "AAA", dep_utc_min: 360, days_utc: D7 },
      { flight_no: 1101, origin_code: "AAA", dest_code: "HUB", dep_utc_min: 460, days_utc: D7, block_min: 75 },
      { flight_no: 1103, origin_code: "HUB", dest_code: "NBN", dep_utc_min: 1360, days_utc: D7 },
      { flight_no: 1104, origin_code: "NBN", dest_code: "HUB", dep_utc_min: 1491 - 1440, days_utc: D7 }] });
    expect(a.ok).toBe(false);
    expect(a.problems.join(" | ")).toMatch(/turn of 25 min at AAA, under the game's 66/);
    expect(a.problems.join(" | ")).toMatch(/NBN: arrives 23:35, inside its night ban/);
    expect(a.problems.join(" | ")).toMatch(/flight 1101 is used twice/);
  });
  it("an aircraft not in the input needs its type and airline", () => {
    expect(() => card.checkCard(r, { legs: [{ origin_code: "HUB", dest_code: "AAA", dep_utc_min: 360 }] })).toThrow(/needs an aircraft in the input, or a type/);
    const a = card.checkCard(r, { type: "A321 NEO LIGHT", airline: "TA", legs: [{ origin_code: "HUB", dest_code: "AAA", dep_utc_min: 360 }, { origin_code: "AAA", dest_code: "HUB", dep_utc_min: 520 }] });
    expect(a.legs_week).toBe(14);
  });
});

describe("the command (node lib/rules/dist/cli.js)", () => {
  const input = file("input.json", world({ flight_legs: [leg(1, "HUB", "AAA", 360, 75), leg(2, "AAA", "HUB", 510, 75), leg(3, "BBB", "HUB", 0, 300, { aircraft_id: 2 })] }));
  it("block <origin> <dest> <type>", () => {
    expect(run(["block", input, "HUB", "AAA", "A321 NEO LIGHT"])).toMatchObject({ block_min: 75, distance_km: 700 });
  });
  it("connections <airport>", () => {
    const a = run(["connections", input, "HUB"]) as { city_pairs: { from: string; to: string; gap_min: number }[] };
    expect(a.city_pairs).toEqual([expect.objectContaining({ from: "BBB", to: "AAA", gap_min: 60 })]);
  });
  it("aircraft: every aircraft's figures, and one aircraft's week", () => {
    const all = run(["aircraft", input]) as { registration: string; legs_week: number; maintenance_pct: number | null }[];
    expect(all.map((a) => [a.registration, a.legs_week])).toEqual([["T-001", 14], ["T-002", 7], ["T-003", 0], ["O-001", 0]]);
    const one = run(["aircraft", input, "T-001"]) as { aircraft_week: { legs: unknown[] }; maintenance: { pct: number } };
    expect(one.aircraft_week.legs).toHaveLength(14);
    expect(one.maintenance.pct).toBeGreaterThan(100);
  });
  it("check-card <card.json>", () => {
    const c = file("card.json", { aircraft: "T-003", legs: [{ origin_code: "FOC", dest_code: "AAA", dep_local: "07:00" }, { origin_code: "AAA", dest_code: "FOC", dep_local: "11:00" }] });
    expect(run(["check-card", input, c])).toMatchObject({ aircraft: "T-003", type: "E195-E2", ok: true });
  });
  it("check-card <card.json>: the cabin the rule calls for, and a card without it is a problem (21 Oct; by distance since 26 Oct)", () => {
    const withCabins = file("cabins.json", world({ cabin_configs: [
      { id: 11, code: "E195-LEI", aircraft_type_id: 2, seats: 112, cabin: "Leisure" }, { id: 12, code: "E195-CMF", aircraft_type_id: 2, seats: 84, cabin: "Comfort" }] }));
    const legs = [{ origin_code: "FOC", dest_code: "AAA", dep_local: "07:00" }, { origin_code: "AAA", dest_code: "FOC", dep_local: "11:00" }];
    const none = run(["check-card", withCabins, file("none.json", { aircraft: "T-003", legs })]) as { ok: boolean; problems: string[]; cabin: { code: string } };
    expect(none.cabin.code).toBe("E195-LEI");
    expect(none.ok).toBe(false);
    expect(none.problems).toEqual(["cabin: none chosen; the rule calls for E195-LEI (under 3,500 km is 100% of block time: Leisure)"]);
    expect(run(["check-card", withCabins, file("lei.json", { aircraft: "T-003", config_id: 11, legs })])).toMatchObject({ ok: true, cabin: { differs: false } });
    // an input made before the rule had its setting (as the briefing sample of 15 Oct): the cabin isn't checked
    const older = world({ cabin_configs: [{ id: 11, code: "E195-LEI", aircraft_type_id: 2, seats: 112, cabin: "Leisure" }] });
    delete (older.settings as Record<string, unknown>).cabin_route_share_pct;
    expect(run(["check-card", file("older.json", older), file("none2.json", { aircraft: "T-003", legs })])).toMatchObject({ ok: true, cabin: null });
  });
  it("an input made before plan_connection_target_h (27 Oct): the card check gives no target figures, the optimiser names the setting", () => {
    const older = world({ flight_legs: [leg(3, "BBB", "HUB", 0, 300, { aircraft_id: 2 })] });
    delete (older.settings as Record<string, unknown>).plan_connection_target_h;
    const path = file("older-target.json", older);
    const c = file("card-target.json", { aircraft: "T-001", legs: [{ origin_code: "HUB", dest_code: "AAA", dep_local: "06:00" }, { origin_code: "AAA", dest_code: "HUB", dep_local: "09:31" }] });
    expect(run(["check-card", path, c])).toMatchObject({
      connections: { target_h: null, total: 1, within_target: null, within_target_share: null },
      legs: [{ feeders: 1, feeders_within_target: null, within_target: null, within_target_share: null }, { onward: 0, onward_within_target: null }],
    });
    expect(() => run(["optimise", path, "HUB", "DDD", "--type", "A321 NEO LIGHT", "--start", "06:00-06:00"])).toThrow(/settings.plan_connection_target_h is missing/);
  });
  it("optimise <base> <dest,...> --type <type> [--start] [--step] [--hubs]", () => {
    const a = run(["optimise", input, "HUB", "DDD", "--type", "A321 NEO LIGHT", "--start", "06:00-07:00", "--step", "30"]) as { considered: number; best: { order: string[] } };
    expect(a.considered).toBe(3);
    expect(a.best.order).toEqual(["DDD"]);
  });
  it("optimise-line --airline --type --hubs --routes [--fixed] [--step] [--work] [--range]: the best 7-day line and its 7 cards (28 Oct)", () => {
    const withGap = file("gap.json", world({ settings: { maintenance_max_gap_h: 40 } }));
    const a = run(["optimise-line", withGap, "--airline", "1", "--type", "A321 NEO LIGHT", "--hubs", "HUB", "--routes", "HUB-BBB,HUB-CCC", "--step", "60", "--work", "40", "--range", "7000", "--seconds", "0"]) as
      { search: { finished: boolean; work: number }; best: { legs: { flight_no: number }[]; cards: { line_day_offset: number; legs: { days_utc: number[] }[] }[] } };
    expect(a.search.work).toBe(40);
    expect(a.best.legs.map((l) => l.flight_no)).toEqual([1001, 1002, 1003, 1004]);
    expect(a.best.cards.map((c) => c.line_day_offset)).toEqual([0, 1, 2, 3, 4, 5, 6]);
    // each card is the line shifted a day: aircraft k flies line day d on weekday ((d + k − 2) mod 7) + 1
    const d0 = a.best.cards[0]?.legs.map((l) => l.days_utc[0] ?? 0) ?? [];
    a.best.cards.forEach((c, k) => expect(c.legs.map((l) => l.days_utc[0])).toEqual(d0.map((d) => ((d + k - 1) % 7) + 1)));
    expect(() => run(["optimise-line", withGap, "--airline", "1", "--type", "A321 NEO LIGHT", "--hubs", "HUB", "--routes", "HUB-BBB", "--range", "5000", "--work", "5"])).toThrow(/beyond the A321 NEO LIGHT's reach of 5,000 km/);
    expect(() => run(["optimise-line", withGap, "--airline", "1", "--type", "A321 NEO LIGHT", "--hubs", "HUB"])).toThrow(/optimise-line --airline/);
  });
  it("check-card <line.json>: a line file of cards is checked as a line, a card as a card (28 Oct)", () => {
    const legs = (day: number) => [{ flight_no: 1001, origin_code: "HUB", dest_code: "BBB", days_utc: [day], dep_utc_min: 0, block_min: 425, service_code: "S3" },
      { flight_no: 1002, origin_code: "BBB", dest_code: "HUB", days_utc: [day], dep_utc_min: 600, block_min: 425, service_code: "S3" }];
    const line = file("line.json", { line: { airline: 1, type: "A321 NEO LIGHT" }, cards: [1, 2, 3].map((d) => ({ legs: legs(d) })) });
    const plain = file("plain.json", world());
    const a = run(["check-card", plain, line]) as { cards: number; complete: boolean; ok: boolean; missing_days: number[]; flights: { flight_no: number; days: number[] }[] };
    expect(a).toMatchObject({ cards: 3, complete: false, ok: true, missing_days: [4, 5, 6, 7] });
    expect(a.flights.map((f) => [f.flight_no, f.days])).toEqual([[1001, [1, 2, 3]], [1002, [1, 2, 3]]]);
    const one = run(["check-card", plain, file("one.json", { airline: 1, type: "A321 NEO LIGHT", legs: legs(1) })]) as { ok: boolean; legs_week: number; maintenance: { max_gap_h: number | null; max_gap_ok: boolean | null } };
    expect(one).toMatchObject({ ok: true, legs_week: 2, maintenance: { max_gap_ok: null } });
  });
  it("answers an unknown command, a missing argument or an unknown airport with an error", () => {
    expect(() => run(["nonsense", input])).toThrow(/unknown command/);
    expect(() => run(["block", input, "HUB"])).toThrow(/block <origin> <dest> <type>/);
    expect(() => run(["aircraft", input, "NO-SUCH"])).toThrow(/no aircraft NO-SUCH/);
  });
  it("reads the input also when saved as the data API answers it", () => {
    const wrapped = file("wrapped.json", [{ rules_input: JSON.parse(readFileSync(input, "utf8")) }]);
    expect(run(["block", wrapped, "HUB", "AAA", "A321 NEO LIGHT"])).toMatchObject({ block_min: 75 });
  });
});

describe("the website's connection test (src/browser.ts, built into web/assets/rules.js)", () => {
  const { isConnection, limitsFrom } = browser.connections;
  it("is the library's own rule: the same limits as connectionLimits() for an airport with and without a minimum", () => {
    const r = buildRules(world({ airports: [{ code: "HUB", utc_offset: 0, mct_min: 60 }, { code: "AAA", utc_offset: 0, mct_min: null }] }));
    for (const code of ["HUB", "AAA"]) {
      const lim = connections.connectionLimits(r, code);
      expect(limitsFrom(r.airports.get(code)?.mct_min, settingNumber(r, "connection_max_wait_h"), settingNumber(r, "connection_buffer_min"))).toEqual(lim);
    }
    expect(browser.connections.isConnection).toBe(connections.isConnection);
  });
  it("counts from the airport's minimum (90 minutes where it has none) to the longest wait, both ends included", () => {
    const at = limitsFrom(60, 8), none = limitsFrom(null, 8);
    expect([isConnection(59, at), isConnection(60, at), isConnection(480, at), isConnection(481, at)]).toEqual([false, true, true, false]);
    expect([none.mct_min, none.mct_source, isConnection(89, none), isConnection(90, none)]).toEqual([90, "default", false, true]);
    expect(isConnection(540, limitsFrom(60, 10))).toBe(true);
  });
});

describe("the case runner's matcher", () => {
  it("passes what matches and names what doesn't", () => {
    expect(mismatches({ a: 1, b: [1, 2], c: "x", extra: true }, { a: 1, b: [1, 2], c: "x" })).toEqual([]);
    expect(mismatches({ a: 1.0000000001 }, { a: 1 })).toEqual([]);
    expect(mismatches({ a: 2 }, { a: 1 })).toEqual(["answer.a: 2, expected 1"]);
    expect(mismatches({ b: [1] }, { b: [1, 2] })[0]).toMatch(/1 item\(s\), expected 2/);
    expect(mismatches({}, { a: null })).toEqual(["answer.a: undefined, expected null"]);
    expect(mismatches(null, { a: 1 })[0]).toMatch(/expected an object/);
  });
});
