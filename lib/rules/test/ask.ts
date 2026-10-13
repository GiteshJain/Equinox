// The questions a case can ask, each answered by the library. Kept apart from the runner so the cases stay plain JSON
// that another home (pull request 3's database tests) can answer the same way.
import {
  aircraftWeek, banks, block, buildRules, card, connections, maintenance, optimiser, positions, schedule, summary, time, turns, findType,
  type Card, type Json, type Rules, type RulesInput,
} from "../src/index.js";

export type Ask = { what: string; [key: string]: Json };

/** A case's input: the base world, with the file's and the case's own keys in place. settings and world_rules merge key
 *  by key; every other key (a list) is replaced whole. */
export function mergeInput(...parts: (Partial<RulesInput> | undefined)[]): RulesInput {
  const out: Record<string, unknown> = {};
  for (const p of parts) {
    if (!p) continue;
    for (const [k, v] of Object.entries(p)) {
      out[k] = (k === "settings" || k === "world_rules") && v && typeof v === "object" ? { ...(out[k] as object), ...(v as object) } : v;
    }
  }
  return out as unknown as RulesInput;
}

const str = (x: Json | undefined, what: string): string => {
  if (typeof x !== "string") throw new Error(`the case's ask needs ${what}`);
  return x;
};
const num = (x: Json | undefined, what: string): number => {
  if (typeof x !== "number") throw new Error(`the case's ask needs ${what}`);
  return x;
};
const clockArg = (x: Json | undefined, what: string): number => {
  const m = time.parseClock(str(x, what));
  if (m == null) throw new Error(`${what} must be HH:MM`);
  return m;
};

function legById(rules: Rules, id: number) {
  const l = block.timedLegs(rules).find((x) => x.id === id);
  if (!l) throw new Error(`no timed leg ${id} in the case`);
  return l;
}

/** Answers one question on the case's world. */
export function ask(input: RulesInput, q: Ask): unknown {
  const rules = buildRules(input);
  switch (q.what) {
    case "local": {
      const ap = str(q.airport, "airport"), m = num(q.utc_week_min, "utc_week_min");
      const local = time.toLocal(rules, ap, m);
      return { offset_min: time.utcOffsetMin(rules, ap), local_week_min: local, day: time.dayOf(local), clock: time.clock(local) };
    }
    case "local_days":
      return { days_local: time.localDays(rules, str(q.airport, "airport"), q.days_utc as number[], num(q.dep_utc_min, "dep_utc_min")) };
    case "from_local":
      return time.fromLocal(rules, str(q.airport, "airport"), q.days_local as number[], clockArg(q.dep_local, "dep_local"));
    case "week_minute_at":
      return { week_min: time.weekMinuteAt(str(q.at, "at")) };
    case "block":
      return block.blockFor(rules, str(q.origin, "origin"), str(q.dest, "dest"), q.type as string | number, (q.airline_id as number | undefined) ?? null);
    case "leg_block":
      return block.legBlock(rules, rules.legs.find((l) => l.id === num(q.leg_id, "leg_id")) ?? (() => { throw new Error("no such leg"); })());
    case "timed_leg":
      return legById(rules, num(q.leg_id, "leg_id"));
    case "turn": {
      const ty = findType(rules, q.type as string | number);
      if (!ty) throw new Error("no such type");
      return turns.checkTurn(rules, ty, num(q.ground_min, "ground_min"), (q.airline_id as number | undefined) ?? null);
    }
    case "link":
      return connections.link(rules, legById(rules, num(q.arrival_leg_id, "arrival_leg_id")), legById(rules, num(q.departure_leg_id, "departure_leg_id")));
    case "onward":
    case "feeders": {
      const legs = block.timedLegs(rules);
      const leg = legById(rules, num(q.leg_id, "leg_id"));
      const list = q.what === "onward" ? connections.onward(rules, legs, leg) : connections.feeders(rules, legs, leg);
      return list.map((x) => ({ leg_id: x.leg.id, days: x.days, of: x.of, gap_min: x.gap_min }));
    }
    case "connections":
      return connections.connectionsAt(rules, str(q.airport, "airport"));
    case "banks": {
      const b = banks.baseAt(rules, str(q.airport, "airport"));
      if (!b) throw new Error("no base there");
      return banks.bankWindows(rules, b).map((w) => ({ n: w.n, dep: time.clock(w.dep), dep_end: time.clock(w.dep_end), arr_start: time.clock(w.arr_start), arr_end: time.clock(w.arr_end) }));
    }
    case "bank_of_departure": {
      const b = banks.baseAt(rules, str(q.airport, "airport"));
      if (!b) throw new Error("no base there");
      return { n: banks.bankOfDeparture(rules, b, clockArg(q.local, "local"))?.n ?? 0 };
    }
    case "bank_of_arrival": {
      const b = banks.baseAt(rules, str(q.airport, "airport"));
      if (!b) throw new Error("no base there");
      return banks.bankOfArrival(rules, b, clockArg(q.local, "local"));
    }
    case "aircraft": {
      const reg = str(q.registration, "registration");
      const week = aircraftWeek.forAircraft(rules, reg);
      return { week, maintenance: maintenance.forAircraft(rules, reg, undefined, week) };
    }
    case "aircraft_leg": {
      const week = aircraftWeek.forAircraft(rules, str(q.registration, "registration"));
      return week?.legs[num(q.index, "index")] ?? null;
    }
    case "schedule":
      return { ...schedule.scheduleChecks(rules), departures: schedule.departuresPerAirport(rules) };
    case "next_flight_numbers": {
      const b = banks.baseAt(rules, str(q.airport, "airport"), (q.airline_id as number | undefined) ?? null);
      if (!b) throw new Error("no base there");
      return schedule.nextFlightNumbers(rules, b);
    }
    case "positions":
      return positions.positionsAt(rules, str(q.at, "at"));
    case "key_figures":
      return summary.keyFigures(rules);
    case "optimise": {
      const [from, to] = str(q.start, "start").split("-");
      return optimiser.optimise(rules, {
        base: str(q.base, "base"), destinations: q.destinations as string[], type: q.type as string | number,
        airlineId: (q.airline_id as number | undefined) ?? null, start: { from: clockArg(from ?? null, "start"), to: clockArg(to ?? null, "start") },
        step: num(q.step, "step"), extraHubs: (q.extra_hubs as string[] | undefined) ?? [],
      });
    }
    case "check_card":
      return card.checkCard(rules, q.card as unknown as Card);
    default:
      throw new Error(`unknown question ${q.what}`);
  }
}
