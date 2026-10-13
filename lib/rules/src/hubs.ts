// hubs: one airport's day and week, and which city pairs connect there, as the Hubs screen shows them (#18 build pull
// request 8, spec docs/specs/2026-10-13-hubs.md), across all our airlines (they interline with each other, manual §6):
//   - board(): the day's flights in local time, each with the bank it collects or feeds at its own airline's base there;
//     the departures and arrivals in each hour; the week in 15-minute slots, shaded by the bank windows; departures a week
//     against the game's cap (schedule.departuresPerAirport); and the next free flight-number pair at the base
//     (schedule.nextFlightNumbers). A focus city has no banks of its own (banks.bankWindows);
//   - connectionsTable(): connections.connectionsAt's city pairs by bank (each once, at its shortest connection, from the
//     airport's minimum connection time to connection_max_wait_h, never back where it came from), with the airports
//     arriving and leaving, their flights by country, and the tightest examples.
// Times are local at the airport, as the old Hubs showed them. Days are 0 = Monday to 6 = Sunday at the airport (the
// screen's day buttons). The old code it follows: the old planner's hubBoard, renderHub and hubConnections.
import { airlineBaseAt, bankOfArrival, bankOfDeparture, bankWindows, baseAt, inWindow, isFocus, type BankWindow } from "./banks.js";
import { timedLegs } from "./block.js";
import { connectionLimits, connectionsAt, departuresOf, type ConnectionLimits } from "./connections.js";
import { settingNumber, worldRuleNumber } from "./input.js";
import { departuresPerAirport, nextFlightNumbers, type NextPair } from "./schedule.js";
import { DAY, toLocal } from "./time.js";
import type { BaseRow, Rules, TimedLeg } from "./types.js";

/** The week grid's slot, minutes. */
export const SLOT_MIN = 15;
export const SLOTS = DAY / SLOT_MIN;
/** How many city pairs a bank's row names as examples, tightest first. */
export const EXAMPLES = 8;

export interface HubFlight {
  leg_id: number;
  airline_id: number;
  kind: "dep" | "arr";
  /** Local minute of the day at the airport. */
  local_min: number;
  /** As the old planner showed it: a return with no number of its own takes its outbound's less one. */
  flight_no: number | null;
  /** Where it goes (a departure) or comes from (an arrival). */
  other: string;
  /** The rotation's aircraft (its outbound's, else its return's), as the old planner's frequency's tail. */
  registration: string | null;
  /** At its own airline's base here: the bank a departure collects, or the first bank an arrival can make, however long
   *  the wait (banks.bankOfArrival's next, as the old Hubs named it); 0 off wave (or a hub with no bank times); null
   *  where its airline has no base here, or the base is a focus city. */
  bank: number | null;
}

export interface HubWeekDay {
  /** Departures and arrivals in each 15-minute slot of the local day. */
  departures: number[];
  arrivals: number[];
  departures_total: number;
  arrivals_total: number;
}

export interface HubBoard {
  airport: string;
  /** The board's base: the first at the airport, in the bases' order (the old planner's hub(code)). */
  base: { id: number; airline_id: number; role: string; parent_code: string | null } | null;
  focus: boolean;
  /** The base's bank windows; none for a focus city. */
  banks: BankWindow[];
  /** The day shown, 0 = Monday. */
  day: number;
  /** That day's departures and arrivals in each local hour, and the tallest hour (at least 1). */
  hours: { departures: number[]; arrivals: number[] };
  max_hour: number;
  departures_today: number;
  arrivals_today: number;
  /** That day's flights by local time (the schedule's order on a tie). */
  flights: HubFlight[];
  /** Monday to Sunday in 15-minute slots. */
  week: HubWeekDay[];
  /** Each slot's shading by the bank windows (the slot's middle in a departure window, else an arrival window). */
  slots: ("dep" | "arr" | "")[];
  /** The busiest slot, departures and arrivals together (at least 1). */
  max_slot: number;
  /** Departures a week from the airport, every airline's, against the game's cap per airport. */
  departures_week: number;
  cap: number;
  over_cap: boolean;
  /** The next free flight-number pair at the base, or null when it has no block of numbers. */
  next_pair: NextPair | null;
}

/** Per rotation: its outbound's flight number and its aircraft (the outbound's, else the return's). */
function rotationFacts(rules: Rules): Map<number, { out_no: number | null; aircraft_id: number | null }> {
  const by = new Map<number, { out_no: number | null; aircraft_id: number | null; ret_aircraft: number | null }>();
  for (const l of rules.legs) {
    if (l.rotation_id == null) continue;
    const r = by.get(l.rotation_id) ?? { out_no: null, aircraft_id: null, ret_aircraft: null };
    if ((l.leg_no ?? 1) === 1) {
      r.out_no = l.flight_no;
      r.aircraft_id = l.aircraft_id;
    } else r.ret_aircraft ??= l.aircraft_id;
    by.set(l.rotation_id, r);
  }
  return new Map([...by].map(([k, v]) => [k, { out_no: v.out_no, aircraft_id: v.aircraft_id ?? v.ret_aircraft }]));
}

/** A leg's flight number as the old planner showed it: its own, or for a return with none its outbound's less one. */
export function shownNumber(leg: Pick<TimedLeg, "flight_no" | "leg_no" | "rotation_id">, facts: ReturnType<typeof rotationFacts>): number | null {
  if (leg.flight_no) return leg.flight_no;
  if ((leg.leg_no ?? 1) !== 1 && leg.rotation_id != null) {
    const out = facts.get(leg.rotation_id)?.out_no;
    return out ? out - 1 : null;
  }
  return null;
}

/** The bank a flight collects or feeds at its own airline's base at the airport (HubFlight.bank). */
function bankAt(rules: Rules, code: string, leg: TimedLeg, kind: "dep" | "arr", localMin: number): number | null {
  const base = airlineBaseAt(rules, code, leg.airline_id);
  if (!base || isFocus(base)) return null;
  if (!bankWindows(rules, base).length) return 0;
  return kind === "dep" ? bankOfDeparture(rules, base, localMin)?.n ?? 0 : bankOfArrival(rules, base, localMin).next;
}

/** Each slot's shading by a base's bank windows: "dep" when the slot's middle is in a departure window, else "arr" in an
 *  arrival window. */
export function slotShading(wins: readonly BankWindow[]): HubBoard["slots"] {
  return Array.from({ length: SLOTS }, (_, i) => {
    const mid = i * SLOT_MIN + Math.floor(SLOT_MIN / 2);
    if (wins.some((w) => inWindow(mid, w.dep, w.dep_end))) return "dep";
    if (wins.some((w) => inWindow(mid, w.arr_start, w.arr_end))) return "arr";
    return "";
  });
}

const baseFacts = (b: BaseRow | undefined): HubBoard["base"] =>
  b ? { id: b.id, airline_id: b.airline_id, role: b.role, parent_code: b.parent_code ?? null } : null;

/** One airport's board on one day (0 = Monday), from every leg given (by default all of the input's). */
export function board(rules: Rules, code: string, day: number, legs: readonly TimedLeg[] = timedLegs(rules)): HubBoard {
  if (!Number.isInteger(day) || day < 0 || day > 6) throw new RangeError(`day must be 0 (Monday) to 6 (Sunday), not ${day}`);
  const base = baseAt(rules, code);
  const wins = base ? bankWindows(rules, base) : [];
  const facts = rotationFacts(rules);
  const regOf = (l: TimedLeg) => {
    const id = (l.rotation_id != null ? facts.get(l.rotation_id)?.aircraft_id : null) ?? l.aircraft_id;
    return id == null ? null : rules.aircraft.get(id)?.registration ?? null;
  };
  const week: HubWeekDay[] = Array.from({ length: 7 }, () => ({
    departures: Array<number>(SLOTS).fill(0), arrivals: Array<number>(SLOTS).fill(0), departures_total: 0, arrivals_total: 0,
  }));
  const hours = { departures: Array<number>(24).fill(0), arrivals: Array<number>(24).fill(0) };
  const flights: HubFlight[] = [];
  const place = (l: TimedLeg, kind: "dep" | "arr", utcWeekMin: number) => {
    const local = toLocal(rules, code, utcWeekMin);
    const d = Math.floor(local / DAY), m = local % DAY;
    const w = week[d];
    if (!w) return;
    if (kind === "dep") {
      w.departures[Math.floor(m / SLOT_MIN)]! += 1;
      w.departures_total++;
    } else {
      w.arrivals[Math.floor(m / SLOT_MIN)]! += 1;
      w.arrivals_total++;
    }
    if (d !== day) return;
    (kind === "dep" ? hours.departures : hours.arrivals)[Math.floor(m / 60)]! += 1;
    flights.push({
      leg_id: l.id, airline_id: l.airline_id, kind, local_min: m, flight_no: shownNumber(l, facts),
      other: kind === "dep" ? l.dest : l.origin, registration: regOf(l), bank: bankAt(rules, code, l, kind, m),
    });
  };
  for (const l of legs) {
    if (l.origin === code) for (const t of departuresOf(l)) place(l, "dep", t);
    if (l.dest === code) for (const t of departuresOf(l)) place(l, "arr", t + l.block_min);
  }
  flights.sort((a, b) => a.local_min - b.local_min);   // stable: the schedule's order on a tie
  const cap = worldRuleNumber(rules, "departures_per_airport_week");
  const departuresWeek = departuresPerAirport(rules, legs).find((a) => a.airport === code)?.departures_week ?? 0;
  return {
    airport: code, base: baseFacts(base), focus: isFocus(base), banks: wins, day, hours,
    max_hour: Math.max(1, ...hours.departures, ...hours.arrivals),
    departures_today: hours.departures.reduce((s, n) => s + n, 0), arrivals_today: hours.arrivals.reduce((s, n) => s + n, 0),
    flights, week, slots: slotShading(wins),
    max_slot: Math.max(1, ...week.flatMap((w) => w.departures.map((n, i) => n + (w.arrivals[i] ?? 0)))),
    departures_week: departuresWeek, cap, over_cap: departuresWeek > cap,
    next_pair: base && base.flight_no_from != null ? nextFlightNumbers(rules, base) : null,
  };
}

export interface CountryCount {
  /** The airport's country code (airports.country_code), or "Other" where it isn't known. */
  country: string;
  /** How many of the row's flights come from (or go to) that country. */
  flights: number;
}

export interface HubConnectionRow {
  /** The bank's number, or 0 outside the banks (every connection, where the airport has no banks). */
  n: number;
  /** The bank's departure, local minutes; null for the row outside the banks. */
  dep_local_min: number | null;
  /** The airports arriving in the row, and the arrivals' countries, most flights first. */
  arriving_from: string[];
  arriving_countries: CountryCount[];
  leaving_to: string[];
  leaving_countries: CountryCount[];
  city_pairs: number;
  /** The tightest EXAMPLES city pairs connecting in the row, and how many more there are. */
  examples: { from: string; to: string; gap_min: number }[];
  more: number;
}

export interface HubConnections {
  airport: string;
  /** connection_max_wait_h, as the board's note gives it. */
  max_wait_h: number;
  limits: ConnectionLimits;
  /** Whether the airport's base has bank windows (else one row holds every connection). */
  banked: boolean;
  arrivals: number;
  departures: number;
  /** Each city pair linked, once, at its shortest connection, with the bank it connects in. */
  pairs: { from: string; to: string; gap_min: number; bank: number }[];
  /** A row per bank and one outside the banks, each only where something arrives, leaves or connects. */
  rows: HubConnectionRow[];
}

/** Flights by the country of the airport at their other end, most first (the first seen first on a tie). */
function byCountry(rules: Rules, legs: readonly TimedLeg[], code: string): CountryCount[] {
  const n = new Map<string, number>();
  for (const l of legs) {
    const other = l.origin === code ? l.dest : l.origin;
    const c = rules.airports.get(other)?.country_code || "Other";
    n.set(c, (n.get(c) ?? 0) + 1);
  }
  return [...n].map(([country, flights]) => ({ country, flights })).sort((a, b) => b.flights - a.flights);
}

/** The connections at an airport, across every leg given (by default all of the input's), as the Hubs screen's table:
 *  only legs with a flight number as the old planner showed it connect (its allLegs). */
export function connectionsTable(rules: Rules, code: string, legs: readonly TimedLeg[] = timedLegs(rules)): HubConnections {
  const facts = rotationFacts(rules);
  const numbered = legs.filter((l) => shownNumber(l, facts) != null);
  // DELIBERATE FAILURE (to be reverted): connections allowed up to 9 hours instead of connection_max_wait_h
  const nine: Rules = { ...rules, input: { ...rules.input, settings: { ...rules.input.settings, connection_max_wait_h: 9 } } };
  const ans = connectionsAt(nine, code, numbered);
  const byId = new Map(numbered.map((l) => [l.id, l]));
  const pick = (ids: readonly number[]) => ids.flatMap((id) => byId.get(id) ?? []);
  const rows: HubConnectionRow[] = ans.by_bank.map((r) => {
    const pairs = ans.city_pairs.filter((p) => p.bank === r.n).sort((a, b) => a.gap_min - b.gap_min);
    return {
      n: r.n, dep_local_min: r.dep_local_min,
      arriving_from: r.arriving_from, arriving_countries: byCountry(rules, pick(r.arrival_leg_ids), code),
      leaving_to: r.leaving_to, leaving_countries: byCountry(rules, pick(r.departure_leg_ids), code),
      city_pairs: r.city_pairs, examples: pairs.slice(0, EXAMPLES).map((p) => ({ from: p.from, to: p.to, gap_min: p.gap_min })),
      more: Math.max(0, pairs.length - EXAMPLES),
    };
  });
  return {
    airport: code, max_wait_h: settingNumber(rules, "connection_max_wait_h"), limits: connectionLimits(rules, code), banked: ans.banks.length > 0,
    arrivals: ans.arrivals, departures: ans.departures,
    pairs: ans.city_pairs.map((p) => ({ from: p.from, to: p.to, gap_min: p.gap_min, bank: p.bank })), rows,
  };
}

/** The airports with a board: every base and focus city, in the bases' order (an airport two airlines share once). */
export function airports(rules: Rules): string[] {
  return [...new Set(rules.bases.map((b) => b.airport_code))];
}
