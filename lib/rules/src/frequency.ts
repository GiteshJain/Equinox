// frequency: a frequency as the Routes screen shows and saves it (#18 build pull request 6, spec
// docs/specs/2026-10-13-routes.md §1). A frequency is a rotation: its outbound (leg 1, hub to destination) and its return
// (leg 2, back to the hub), flying on the same local weekdays. Times are typed in local time at each end and stored in
// UTC (flight_legs: dep_utc_min, days_utc, block_min), as #13's design §4 says:
//   - the outbound leaves on the typed local weekdays at the hub; its UTC weekdays are those, moved a day where the UTC
//     time falls on another day;
//   - the return's day follows the old planner's rule: the first departure of its typed time after the outbound lands
//     (the outbound's arrival day, or the next day when the return leaves earlier in the day than the outbound lands),
//     so within 24 hours of the landing;
//   - a typed arrival sets the block time; with none the block is the estimate (block_allowance_min + distance ÷ the
//     type's cruise_kmh, block.ts), stored as null and marked "est".
// The view back from UTC is the old planner's getter and its computeFreq: the outbound's local weekdays at the hub, the
// four local times, each way's arrival day and block, and the ground time at the destination. The checks on a frequency
// are the library's own (banks.wave, turns, schedule, aircraftWeek, connections), gathered for its two legs.
// The old code it follows: the old planner's computeFreq and the getter's and planner_state_put()'s frequency
// conversion (migration 20261010210000_adapter_write_side.sql); private.shift_weekdays.
import { forAircraft as aircraftWeekOf } from "./aircraftWeek.js";
import { estimateBlock, timedLeg, timedLegs } from "./block.js";
import { connectionsAtBothEnds } from "./connections.js";
import { findType, typeOfAircraft } from "./input.js";
import { flightNumberClashes, nightBanHits, routeGapHits, type NightBanHit } from "./schedule.js";
import { DAY, mod, toLocal, utcOffsetMin } from "./time.js";
import { checkTurn, type TurnCheck } from "./turns.js";
import type { AirportRow, LegRow, Rules, RulesInput, TimedLeg } from "./types.js";

/** What a frequency's times depend on besides the times themselves: its route's two airports, the airline (for its
 *  settings), and the distance and aircraft type its estimate uses (the aircraft's type, else the market's aircraft, as
 *  the old planner's estBlock). */
export interface FrequencyEnds {
  airline_id: number;
  hub: string;
  dest: string;
  distance_km?: number | null;
  type_id?: number | null;
}

/** A frequency in local time, as typed: the outbound's local weekdays at the hub (ISO, 1 = Monday) and the four clock
 *  times in minutes after midnight, local at their airport. An arrival left empty (null) is estimated. */
export interface LocalTimes {
  days: number[];
  dep_hub: number | null;
  arr_dest: number | null;
  dep_dest: number | null;
  arr_hub: number | null;
}

/** One leg as flight_legs stores it. */
export interface StoredLeg {
  days_utc: number[];
  dep_utc_min: number | null;
  block_min: number | null;
}

/** One way of a frequency in local time: departure and arrival minutes (local at each end), the days after the outbound's
 *  local day at the hub that it leaves and lands, and its block (typed, or the estimate: est). */
export interface Way {
  dep: number;
  dep_day: number;
  arr: number;
  arr_day: number;
  block: number;
  est: boolean;
}

/** A frequency as the Routes screen shows it (the old computeFreq). */
export interface FrequencyView extends LocalTimes {
  offset_hub_min: number;
  offset_dest_min: number;
  /** The estimate an empty arrival takes, or null without a type or a distance. */
  est_block: number | null;
  out: Way | null;
  back: Way | null;
  /** Minutes on the ground at the destination between the outbound's landing and the return. */
  ground_dest: number | null;
  /** Round trips a week: the outbound's days. */
  round_trips_week: number;
}

const WEEKDAYS = [1, 2, 3, 4, 5, 6, 7];

/** ISO weekdays moved by n days (private.shift_weekdays): sorted, no repeats. */
export function shiftDays(days: readonly number[], n: number): number[] {
  return [...new Set(days.map((d) => mod(d - 1 + n, 7) + 1))].sort((a, b) => a - b);
}

/** Weekdays as typed ("1357", "1 3 5", [1, 3, 5]): only 1 to 7, sorted, no repeats; none is every day, as
 *  planner_state_put() stores an empty one. */
export function weekdays(typed: string | readonly number[] | null | undefined): number[] {
  const list = typeof typed === "string" ? [...typed].filter((c) => /[1-7]/.test(c)).map(Number) : [...(typed ?? [])].filter((d) => Number.isInteger(d) && d >= 1 && d <= 7);
  const out = [...new Set(list)].sort((a, b) => a - b);
  return out.length ? out : [...WEEKDAYS];
}

/** The estimate an empty arrival takes on this frequency: block_allowance_min + distance ÷ cruise_kmh, or null without
 *  a type with a cruise speed or a distance. */
export function estimateFor(rules: Rules, ends: FrequencyEnds): number | null {
  const ty = ends.type_id == null ? undefined : findType(rules, ends.type_id);
  if (!ty || ty.cruise_kmh == null || !(ty.cruise_kmh > 0) || ends.distance_km == null) return null;
  return estimateBlock(rules, ends.distance_km, ty, ends.airline_id);
}

/** The two stored legs back in local time, as the old planner's getter gives them: the outbound's local weekdays at the
 *  hub, its departure at the hub, its arrival when its block is stored, the return's departure and its arrival when its
 *  block is stored. */
export function localTimes(rules: Rules, ends: FrequencyEnds, leg1: StoredLeg, leg2: StoredLeg): LocalTimes {
  const oh = utcOffsetMin(rules, ends.hub), od = utcOffsetMin(rules, ends.dest);
  const d1 = leg1.dep_utc_min, d2 = leg2.dep_utc_min;
  return {
    days: d1 == null ? weekdays(leg1.days_utc) : shiftDays(leg1.days_utc, Math.floor((d1 + oh) / DAY)),
    dep_hub: d1 == null ? null : mod(d1 + oh, DAY),
    arr_dest: d1 == null || leg1.block_min == null ? null : mod(d1 + leg1.block_min + od, DAY),
    dep_dest: d2 == null ? null : mod(d2 + od, DAY),
    arr_hub: d2 == null || leg2.block_min == null ? null : mod(d2 + leg2.block_min + oh, DAY),
  };
}

/** A frequency in local time worked out as the old planner's computeFreq: each way's arrival (local at its end) and the
 *  days it leaves and lands after the outbound's local day at the hub, its block, and the ground time at the destination. */
export function view(rules: Rules, ends: FrequencyEnds, local: LocalTimes): FrequencyView {
  const oh = utcOffsetMin(rules, ends.hub), od = utcOffsetMin(rules, ends.dest);
  const est = estimateFor(rules, ends);
  let out: Way | null = null, back: Way | null = null;
  if (local.dep_hub != null) {
    const typed = local.arr_dest != null;
    const dur = local.arr_dest != null ? mod(local.arr_dest - local.dep_hub - (od - oh), DAY) : est;
    if (dur != null) {
      const abs = local.dep_hub + dur + (od - oh);
      out = { dep: local.dep_hub, dep_day: 0, arr: mod(abs, DAY), arr_day: Math.floor(abs / DAY), block: dur, est: !typed };
    }
  }
  if (local.dep_dest != null) {
    const typed = local.arr_hub != null;
    const dur = local.arr_hub != null ? mod(local.arr_hub - local.dep_dest - (oh - od), DAY) : est;
    if (dur != null) {
      const depDay = out ? out.arr_day + (local.dep_dest < out.arr ? 1 : 0) : 0;
      const abs = local.dep_dest + dur + (oh - od);
      back = { dep: local.dep_dest, dep_day: depDay, arr: mod(abs, DAY), arr_day: depDay + Math.floor(abs / DAY), block: dur, est: !typed };
    }
  }
  return {
    ...local, days: [...local.days], offset_hub_min: oh, offset_dest_min: od, est_block: est, out, back,
    ground_dest: out && back ? mod(back.dep - out.arr, DAY) : null, round_trips_week: local.days.length,
  };
}

/** The day after the outbound's local day at the hub that the return leaves: the outbound's arrival day, or the next
 *  when the return leaves earlier in the day than the outbound lands (the old planner's rule). 0 without both
 *  departures or a block for the outbound (typed, else the estimate). */
export function returnDay(rules: Rules, ends: FrequencyEnds, local: LocalTimes): number {
  return view(rules, ends, local).back?.dep_day ?? 0;
}

/** A frequency typed in local time as its two legs in UTC, to store: the inverse of localTimes(). backDays, when given
 *  (a 7-day line's rotation, since 28 Oct: spec docs/specs/2026-10-27-long-haul-lines.md §4), are the local weekdays
 *  the return leaves on at the destination, its own, in place of the day the old planner's rule gives it (within 24
 *  hours of the landing): on a line the return is often days later, flown by the same aircraft. */
export function toLegs(rules: Rules, ends: FrequencyEnds, local: LocalTimes, backDays?: readonly number[] | null): { leg1: StoredLeg; leg2: StoredLeg } {
  const oh = utcOffsetMin(rules, ends.hub), od = utcOffsetMin(rules, ends.dest);
  const days = weekdays(local.days);
  const back = returnDay(rules, ends, { ...local, days });
  const dh = local.dep_hub, dd = local.dep_dest;
  const returnDays = backDays ? weekdays(backDays) : shiftDays(days, back);
  return {
    leg1: {
      days_utc: dh == null ? days : shiftDays(days, Math.floor((dh - oh) / DAY)),
      dep_utc_min: dh == null ? null : mod(dh - oh, DAY),
      block_min: dh == null || local.arr_dest == null ? null : mod(local.arr_dest - dh - (od - oh), DAY),
    },
    leg2: {
      days_utc: shiftDays(returnDays, dd == null ? 0 : Math.floor((dd - od) / DAY)),
      dep_utc_min: dd == null ? null : mod(dd - od, DAY),
      block_min: dd == null || local.arr_hub == null ? null : mod(local.arr_hub - dd - (oh - od), DAY),
    },
  };
}

/** The local weekdays a stored return leaves on at its origin (the frequency's destination), its own: its UTC weekdays
 *  moved to local time; untimed, its UTC weekdays (none is every day). */
export function ownBackDays(rules: Rules, ends: FrequencyEnds, leg2: StoredLeg): number[] {
  const d2 = leg2.dep_utc_min;
  return d2 == null ? weekdays(leg2.days_utc) : shiftDays(weekdays(leg2.days_utc), Math.floor((d2 + utcOffsetMin(rules, ends.dest)) / DAY));
}

/** Whether a rotation's return flies on days of its own: its stored weekdays aren't those the old planner's rule gives
 *  it (the first departure of its time after the outbound lands). A 7-day line's rotation (an outbound and its return
 *  days apart, both one weekday) is; a plain frequency stored by toLegs() isn't. False without both departures. */
export function returnOnOwnDays(rules: Rules, ends: FrequencyEnds, leg1: StoredLeg, leg2: StoredLeg): boolean {
  if (leg1.dep_utc_min == null || leg2.dep_utc_min == null) return false;
  const want = toLegs(rules, ends, localTimes(rules, ends, leg1, leg2)).leg2.days_utc;
  return want.join(",") !== [...new Set(leg2.days_utc)].sort((a, b) => a - b).join(",");
}

/** The same rules with one airport's UTC offset set to the hours given (the world's correction, or the game's own offset
 *  when the correction is cleared). */
export function withOffset(rules: Rules, code: string, hours: number | null, correction: number | null = hours): Rules {
  const input: RulesInput = {
    ...rules.input,
    airports: rules.input.airports.map((a): AirportRow => (a.code === code ? { ...a, utc_offset: hours, utc_offset_override: correction } : a)),
  };
  const airports = new Map(rules.airports);
  const a = airports.get(code);
  airports.set(code, { ...(a ?? { code, mct_min: null }), utc_offset: hours, utc_offset_override: correction });
  return { ...rules, input, airports };
}

/** A rotation's two legs after an airport's offset changes, keeping their local times (the old planner keeps the local
 *  times when an offset changes): read in local time with the old offsets, stored again with the new ones. ownDays (a
 *  7-day line's rotation, since 28 Oct): the return keeps its own local weekdays, not the day the old rule would give it
 *  after the move. */
export function retime(before: Rules, after: Rules, ends: FrequencyEnds, leg1: StoredLeg, leg2: StoredLeg, ownDays = false): { leg1: StoredLeg; leg2: StoredLeg } {
  return toLegs(after, ends, localTimes(before, ends, leg1, leg2), ownDays ? ownBackDays(before, ends, leg2) : null);
}

/** A departure stored in UTC (a plan card's leg) after its airport's offset changes, keeping its local time. */
export function retimeDeparture(before: Rules, after: Rules, code: string, depUtcMin: number): number {
  return mod(depUtcMin + utcOffsetMin(before, code) - utcOffsetMin(after, code), DAY);
}

/** How many UTC days a departure moves when its airport's offset changes and its local time is kept: −1, 0 or 1 (a
 *  leg on one weekday, a line's or a line card's, moves its day with it; since 28 Oct). */
export function retimeDayShift(before: Rules, after: Rules, code: string, depUtcMin: number): number {
  return Math.floor((depUtcMin + utcOffsetMin(before, code) - utcOffsetMin(after, code)) / DAY);
}

/** One of the frequency's legs and another leg it meets in a check. */
export interface OtherLeg {
  leg_id: number;
  other_leg_id: number;
  flight_no: number | null;
  origin: string;
  dest: string;
}

/** A flight the frequency connects with at one of its airports. */
export interface ConnectingFlight {
  leg_id: number;
  airline_id: number;
  flight_no: number | null;
  origin: string;
  dest: string;
  /** Local at the airport where the connection is made: the flight's departure (onward) or arrival (feeding). */
  local_min: number;
  days: number;
  of: number;
  gap_min: number;
}

export interface FrequencyChecks {
  /** The two legs as the checks placed them in the week; null where a leg has no time yet (or no block). */
  legs: [TimedLeg | null, TimedLeg | null];
  /** Departures and arrivals inside an airport's night ban. */
  night_bans: NightBanHit[];
  /** Another leg of the airline's with one of the frequency's numbers, leaving on a same local weekday. */
  flight_numbers: OtherLeg[];
  /** Another flight on the same route closer than the second-daily gap (or the game's own gap). */
  route_gaps: (OtherLeg & { gap_min: number; need_min: number; rule: string })[];
  /** Departures after which the aircraft's next flight doesn't leave where this one lands, a week. */
  positions: { leg_id: number; flight_no: number | null; at: string; next_from: string; times_week: number }[];
  /** The turn at the destination between the outbound and the return, on the aircraft's type. */
  turn_dest: TurnCheck | null;
  /** Each leg's connections: onward where it lands, feeding where it leaves. */
  connections: { leg_id: number; onward: ConnectingFlight[]; feeders: ConnectingFlight[] }[];
}

/** Every check on one rotation's two legs, against the whole schedule given (by default the input's legs). */
export function checks(rules: Rules, rotationId: number, legs: readonly TimedLeg[] = timedLegs(rules)): FrequencyChecks {
  const rows = rules.legs.filter((l) => l.rotation_id === rotationId);
  const row = (n: number): LegRow | undefined => rows.find((l) => (l.leg_no ?? (rows.indexOf(l) + 1)) === n);
  const timed = (r: LegRow | undefined) => (r ? legs.find((t) => t.id === r.id) ?? timedLeg(rules, r, -1) : null);
  const t1 = timed(row(1)), t2 = timed(row(2));
  const mine = [t1, t2].filter((t): t is TimedLeg => t != null);
  const ids = new Set(mine.map((t) => t.id));
  const byId = new Map(legs.map((l) => [l.id, l] as const));
  const other = (ours: number, theirs: number): OtherLeg => {
    const o = byId.get(theirs);
    return { leg_id: ours, other_leg_id: theirs, flight_no: o?.flight_no ?? null, origin: o?.origin ?? "", dest: o?.dest ?? "" };
  };
  const pairs = <T extends { leg_ids: [number, number] }>(hits: T[]) => hits.flatMap((h) => {
    const [a, b] = h.leg_ids;
    // as the old planner lists a clash: on each frequency, the other leg of the pair (the earlier one when both are its own)
    return ids.has(b) ? [{ h, x: other(b, a) }] : ids.has(a) ? [{ h, x: other(a, b) }] : [];
  });
  const clashes = pairs(flightNumberClashes(rules, legs).map((c) => ({ ...c, leg_ids: c.leg_ids }))).map(({ x }) => x);
  const gaps = pairs(routeGapHits(rules, legs)).map(({ h, x }) => ({ ...x, gap_min: h.gap_min, need_min: h.need_min, rule: h.rule }));

  // positions: the aircraft's week, each of this rotation's departures and the departure that follows it
  const positions: FrequencyChecks["positions"] = [];
  const aircraftId = t1?.aircraft_id ?? t2?.aircraft_id ?? null;
  if (aircraftId != null) {
    const week = aircraftWeekOf(rules, aircraftId, legs);
    const list = week?.legs ?? [];
    list.forEach((w, i) => {
      if (!ids.has(w.leg_id) || w.position_ok || list.length < 2) return;
      const next = list[(i + 1) % list.length];
      if (!next) return;
      const have = positions.find((p) => p.leg_id === w.leg_id && p.next_from === next.origin);
      if (have) have.times_week++;
      else positions.push({ leg_id: w.leg_id, flight_no: w.flight_no, at: w.dest, next_from: next.origin, times_week: 1 });
    });
  }

  // the turn at the destination, on the aircraft's type (none without an aircraft)
  let turn: TurnCheck | null = null;
  const ty = typeOfAircraft(rules, aircraftId);
  if (t1 && t2 && ty && ty.min_turn_min != null) {
    const ground = mod(t2.dep_utc_min - (t1.dep_utc_min + t1.block_min), DAY);
    turn = checkTurn(rules, ty, ground, t1.airline_id);
  }

  const flight = (at: string, which: "dep" | "arr") => (x: { leg: TimedLeg; days: number; of: number; gap_min: number }): ConnectingFlight => ({
    leg_id: x.leg.id, airline_id: x.leg.airline_id, flight_no: x.leg.flight_no, origin: x.leg.origin, dest: x.leg.dest,
    local_min: toLocal(rules, at, which === "dep" ? x.leg.dep_utc_min : x.leg.dep_utc_min + x.leg.block_min, DAY),
    days: x.days, of: x.of, gap_min: x.gap_min,
  });
  return {
    legs: [t1, t2],
    night_bans: nightBanHits(rules, mine),
    flight_numbers: clashes,
    route_gaps: gaps,
    positions,
    turn_dest: turn,
    connections: mine.map((l) => {
      const ends = connectionsAtBothEnds(rules, legs, l);
      return { leg_id: l.id, onward: ends.onward.map(flight(l.dest, "dep")), feeders: ends.feeders.map(flight(l.origin, "arr")) };
    }),
  };
}

/** Flight numbers as one line, runs joined: [1001, 1002, 1003, 1010] → "1001–1003, 1010" (the old planner's ranges). */
export function numberRanges(nums: readonly number[]): string {
  const u = [...new Set(nums.filter((n) => Number.isFinite(n) && n > 0))].sort((a, b) => a - b);
  if (!u.length) return "";
  const out: string[] = [];
  let s = u[0] as number, p = s;
  for (let i = 1; i <= u.length; i++) {
    const n = u[i];
    if (n === p + 1) {
      p = n;
      continue;
    }
    out.push(s === p ? String(s) : `${s}–${p}`);
    if (n !== undefined) s = p = n;
  }
  return out.join(", ");
}

export { WEEKDAYS };
