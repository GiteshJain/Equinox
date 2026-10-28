/// <reference types="node" />
// A saved 7-day line read by everything that used to assume an aircraft repeats one day (spec
// docs/specs/2026-10-27-long-haul-lines.md §4 and §6; 28 Oct): the Pan Am A350-900 sample line of the line optimiser's
// fixture (tests/fixtures/line_a350_2026-10-12.json, its 7 cards), filed as filing files it, each outbound with its return
// flown by the same aircraft days later (2001 Monday out, 2002 Thursday back on the first card), against the 12 Oct
// sample's other flights at the six airports. Then the Game check, the flights by day, the aircraft's week (block hours a
// day), the connections at a hub and the offset re-timing read it, and a plain aircraft reads as before.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { aircraftWeek, buildRules, connections, frequency, game, loadReport, time, type GameFlight, type LegRow, type Rules, type RulesInput } from "../src/index.js";
import { mergeInput } from "./ask.js";

const base = (JSON.parse(readFileSync(new URL("../cases/_base.json", import.meta.url), "utf8")) as { input: RulesInput }).input;
interface CardLegIn { flight_no: number; origin_code: string; dest_code: string; days_utc: number[]; dep_utc_min: number; block_min: number }
const fixture = JSON.parse(readFileSync(new URL("../../../tests/fixtures/line_a350_2026-10-12.json", import.meta.url), "utf8")) as {
  input: RulesInput; cases: { ask: { what: string; line?: { cards: { line_day_offset: number; legs: CardLegIn[] }[] } } }[];
};
const cards = (fixture.cases.find((c) => c.ask.what === "check_line" && c.ask.line?.cards.length === 7)?.ask.line?.cards ?? []);
const A350 = (fixture.input.aircraft_types.find((t) => t.name === "A350-900") as { id: number }).id;

/** The line's cards filed: aircraft L-k at offset k, each outbound (odd number) with its return (one more) as a rotation
 *  on the route from the outbound's origin, each leg on its own weekday; rotation and leg ids from 90000. */
function filed(n = 7): { input: RulesInput; rules: Rules; legs: LegRow[] } {
  const routes = new Map<string, number>();
  const rotations: RulesInput["rotations"] = [], legs: LegRow[] = [];
  const aircraft: RulesInput["aircraft"] = [];
  let rot = 90000, leg = 90000;
  for (const c of cards.slice(0, n)) {
    const acId = 9100 + c.line_day_offset;
    aircraft.push({ id: acId, registration: `L-${c.line_day_offset}`, airline_id: 1, aircraft_type_id: A350, base_code: "SFO", status: "active" });
    for (const out of c.legs.filter((l) => l.flight_no % 2 === 1)) {
      const back = c.legs.find((l) => l.flight_no === out.flight_no + 1);
      const key = `${out.origin_code}|${out.dest_code}`;
      if (!routes.has(key)) routes.set(key, 9000 + routes.size);
      rotations.push({ id: ++rot, airline_id: 1, route_id: routes.get(key) as number });
      const row = (l: CardLegIn, k: 1 | 2): LegRow => ({ id: ++leg, airline_id: 1, rotation_id: rot, leg_no: k, flight_no: l.flight_no, origin_code: l.origin_code,
        dest_code: l.dest_code, aircraft_id: acId, days_utc: l.days_utc, dep_utc_min: l.dep_utc_min, block_min: l.block_min });
      legs.push(row(out, 1));
      if (back) legs.push(row(back, 2));
    }
  }
  const km = { "SFO|LGW": 8616, "LGW|SEA": 7710, "SEA|PKX": 8710, "LGW|LAX": 8780, "SFO|PVG": 9877, "PVG|LAX": 10460 } as Record<string, number>;
  const input = mergeInput(base, fixture.input, { settings: { ...base.settings, maintenance_max_gap_h: 40, line_min_km: 7750, line_aircraft: 7 } }, {
    aircraft: [...fixture.input.aircraft, ...aircraft],
    routes: [...fixture.input.routes, ...[...routes].map(([k, id]) => ({ id, airline_id: 1, hub_code: k.split("|")[0] as string, dest_code: k.split("|")[1] as string, distance_km: km[k] ?? 9000 }))],
    rotations: [...fixture.input.rotations, ...rotations],
    flight_legs: [...fixture.input.flight_legs, ...legs],
  });
  return { input, rules: buildRules(input), legs };
}

/** The game's public schedule for the line's flights, worked out from the card legs alone (not the library's frequency
 *  model): each number at its local times, on the local weekdays of every filed aircraft. */
function gameSchedule(rules: Rules, legs: readonly LegRow[]): GameFlight[] {
  const by = new Map<string, GameFlight>();
  for (const l of legs) {
    const dep = time.clock(time.toLocal(rules, l.origin_code, l.dep_utc_min as number, time.DAY));
    const arr = time.clock(time.toLocal(rules, l.dest_code, (l.dep_utc_min as number) + (l.block_min as number), time.DAY));
    const days = time.localDays(rules, l.origin_code, l.days_utc, l.dep_utc_min as number);
    const k = String(l.flight_no);
    const g = by.get(k) ?? { no: k, from: l.origin_code, to: l.dest_code, dep, arr, days: "" };
    g.days = game.sortDays([...new Set([...g.days, ...days.join("")])].join(""));
    by.set(k, g);
  }
  return [...by.values()];
}

describe("a 7-day line filed (spec §4)", () => {
  const all = filed();
  const lineIds = new Set(cards.map((c) => 9100 + c.line_day_offset));

  it("the sample's 7 cards: 12 legs each, on 7 different weekdays, every leg on one", () => {
    expect(cards).toHaveLength(7);
    expect(cards.every((c) => c.legs.length === 12 && aircraftWeek.linePattern(c.legs))).toBe(true);
    expect([...aircraftWeek.lineAircraft(all.rules)].sort()).toEqual([...lineIds].sort());
    // the 12 Oct sample's own aircraft repeat one day
    expect(fixture.input.aircraft.some((a) => aircraftWeek.lineAircraft(all.rules).has(a.id))).toBe(false);
    expect(aircraftWeek.linePattern([{ days_utc: [1, 2, 3, 4, 5, 6, 7] }, { days_utc: [1, 2, 3, 4, 5, 6, 7] }])).toBe(false);
    expect(aircraftWeek.linePattern([{ days_utc: [1] }, { days_utc: [1] }])).toBe(false);
  });

  it("each rotation's return on its own day: 2002 three days after 2001, not the day the old rule gives", () => {
    const f = game.frequencies(all.rules, 1).find((x) => x.leg1?.aircraft_id === 9100 && x.leg1?.flight_no === 2001);
    expect(f?.own_days).toBe(true);
    expect(f?.local.days).toEqual([1]);       // SFO Monday 10:00 local
    expect(f?.back_days).toEqual([4]);        // LGW Thursday 08:13 local
    // the old rule: the first 08:13 after the Tuesday landing, Wednesday
    const v = frequency.view(all.rules, (f as game.Frequency).ends, (f as game.Frequency).local);
    expect(frequency.shiftDays([1], v.back?.dep_day ?? 0)).not.toEqual([4]);
    expect(frequency.returnOnOwnDays(all.rules, (f as game.Frequency).ends, f?.leg1 as LegRow, f?.leg2 as LegRow)).toBe(true);
  });

  it("Game check: all 7 filed, every flight daily in the game, no differences", () => {
    const c = game.compare(all.rules, 1, gameSchedule(all.rules, all.legs));
    expect(c.issues.filter((i) => Number(i.no) >= 2001 && Number(i.no) <= 2012)).toEqual([]);
    expect(c.ok).toBeGreaterThanOrEqual(12);
  });

  it("Game check: 3 of 7 filed, each flight on those 3 days in the planner and the game, no differences", () => {
    const three = filed(3);
    const c = game.compare(three.rules, 1, gameSchedule(three.rules, three.legs));
    expect(c.issues.filter((i) => Number(i.no) >= 2001 && Number(i.no) <= 2012)).toEqual([]);
    const P = game.plannerFlights(three.rules, 1);
    expect(P.get("2002")?.map((e) => e.days)).toEqual(["456"]);
  });

  it("Game check: a line flight at another time can be fixed, and keeps every aircraft's day; another day can't", () => {
    const sched = gameSchedule(all.rules, all.legs).map((g) => (g.no === "2002" ? { ...g, dep: "08:43" } : g));
    const c = game.compare(all.rules, 1, sched);
    const i = c.issues.find((x) => x.no === "2002");
    expect(i?.text).toBe("Different: departure");
    expect(i?.fix).not.toBeNull();
    const fixes = game.fixTimes(all.rules, 1, [i as game.GameIssue]);
    expect(fixes.size).toBe(7);
    for (const [, x] of fixes) {
      expect(x.freq.own_days).toBe(true);
      const { leg2 } = frequency.toLegs(all.rules, x.freq.ends, x.local, x.freq.back_days);
      expect(leg2.days_utc).toEqual(x.freq.leg2?.days_utc);
      expect(leg2.dep_utc_min).toBe((x.freq.leg2?.dep_utc_min as number) + 30);
    }
    // the game lists 2001 on 6 days: which aircraft are filed, not a time to take, so no fix
    const six = gameSchedule(all.rules, all.legs).map((g) => (g.no === "2001" ? { ...g, days: "123456" } : g));
    const d = game.compare(all.rules, 1, six).issues.find((x) => x.no === "2001");
    expect(d?.text).toBe("Different: days");
    expect(d?.fix).toBeNull();
  });

  it("filing's check day by day: a line card's leg against the game's flight on its day", () => {
    const sched = gameSchedule(all.rules, all.legs);
    const legs = (cards[0]?.legs ?? []).map((l) => ({ no: String(l.flight_no), from: l.origin_code, to: l.dest_code,
      dep: time.clock(time.toLocal(all.rules, l.origin_code, l.dep_utc_min, time.DAY)),
      arr: time.clock(time.toLocal(all.rules, l.dest_code, l.dep_utc_min + l.block_min, time.DAY)),
      days: time.localDays(all.rules, l.origin_code, l.days_utc, l.dep_utc_min).join("") }));
    expect(game.compareCard(legs, sched, "", true).allSame).toBe(true);
    // the whole card at once, as for a plain card, every leg differs by days
    expect(game.compareCard(legs, sched).diff).toBe(12);
    // a game listing that doesn't fly the leg's day
    const notMon = sched.map((g) => (g.no === "2001" ? { ...g, days: "234567" } : g));
    const c = game.compareCard(legs, notMon, "", true);
    expect(c.rows.find((r) => r.L.no === "2001")?.same).toBe(false);
    expect(c.diff).toBe(1);
  });

  it("flights by day: each line flight once a day, its return on its own day", () => {
    const day = loadReport.flightsOn(all.rules, "2026-10-15");   // a Thursday
    const ours = day.filter((x) => x.rotation_id > 90000);
    expect(ours.map((x) => x.no).sort((a, b) => a - b)).toEqual([2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012]);
    const three = loadReport.flightsOn(filed(3).rules, "2026-10-12").filter((x) => x.rotation_id > 90000 && x.no === 2002);   // Monday: no filed aircraft flies 2002 back
    expect(three).toEqual([]);
  });

  it("Tails' block hours a day: the week's average over the line's 7 days", () => {
    const w = aircraftWeek.forAircraft(all.rules, 9100);
    const block = (cards[0]?.legs ?? []).reduce((s, l) => s + l.block_min, 0);
    expect(w?.legs_week).toBe(12);
    expect(w?.block_hours_day).toBeCloseTo(block / 60 / 7, 6);
    expect(w?.block_hours_day).toBeCloseTo(17.7, 1);
    expect(w?.legs.every((l) => l.position_ok)).toBe(true);
  });

  it("connections: each line leg on its own day, so a daily line flight connects as a daily one", () => {
    const at = connections.connectionsAt(all.rules, "LGW");
    // 2001 lands at LGW from SFO each day (7 aircraft, one day each), and 2012 leaves to LAX each day
    const c = at.connections.filter((x) => x.from === "SFO" && x.to === "SEA");
    expect(c.every((x) => x.of === 1 && x.days === 1)).toBe(true);
    const fromLine = at.connections.filter((x) => all.legs.some((l) => l.id === x.arrival_leg_id));
    expect(fromLine.every((x) => x.of === 1)).toBe(true);
  });

  it("an offset change keeps each line leg's local time and its own day", () => {
    const f = game.frequencies(all.rules, 1).find((x) => x.leg1?.aircraft_id === 9100 && x.leg1?.flight_no === 2001) as game.Frequency;
    const after = frequency.withOffset(all.rules, "LGW", (time.utcOffsetHours(all.rules, "LGW") ?? 0) + 1);
    const s = (l: LegRow | undefined) => ({ days_utc: l?.days_utc ?? [], dep_utc_min: l?.dep_utc_min ?? null, block_min: l?.block_min ?? null });
    const kept = frequency.retime(all.rules, after, f.ends, s(f.leg1), s(f.leg2), true);
    expect(kept.leg2.days_utc).toEqual(f.leg2?.days_utc);
    expect(kept.leg2.dep_utc_min).toBe((f.leg2?.dep_utc_min as number) - 60);
    expect(frequency.ownBackDays(after, f.ends, kept.leg2)).toEqual(f.back_days);
    // the old rule would move the return to the day after the landing
    expect(frequency.retime(all.rules, after, f.ends, s(f.leg1), s(f.leg2)).leg2.days_utc).not.toEqual(f.leg2?.days_utc);
    expect(frequency.retimeDayShift(all.rules, after, "LGW", 30)).toBe(-1);
    expect(frequency.retimeDayShift(all.rules, after, "LGW", 600)).toBe(0);
  });

  it("a plain aircraft reads as before: no own days, its return on the old rule's day", () => {
    const plain = game.frequencies(all.rules, 1).filter((x) => !lineIds.has(x.leg1?.aircraft_id ?? -1));
    expect(plain.length).toBeGreaterThan(0);
    for (const f of plain) {
      expect(f.own_days).toBe(false);
      const v = frequency.view(all.rules, f.ends, f.local);
      expect(f.back_days).toEqual(frequency.shiftDays(f.local.days, v.back?.dep_day ?? 0));
    }
  });
});
