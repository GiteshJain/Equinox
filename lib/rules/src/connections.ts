// connections: an arrival connects onto a departure at the same airport when the departure leaves at least the
// airport's minimum connection time (world_airports.mct_min) plus connection_buffer_min after the landing, and no more
// than connection_max_wait_h after it (manual §4: "with no extra margin", "within 8 hours"). Worked across the week,
// day by day, in UTC (the same instants as local time at the airport). An airport with no minimum connection time
// uses 90 minutes (spec §5). Our airlines interline with each other (manual §6), so connections are across all of them.
// The old code it follows: the old planner's link, onward, feeders and hubConnections; plan.py's conns.
import { DEFAULT_MCT_MIN, mctAt } from "./airport.js";
import { bankOfArrival, bankOfDeparture, bankWindows, baseAt, isFocus } from "./banks.js";
import { timedLegs } from "./block.js";
import { settingNumber } from "./input.js";
import { DAY, WEEK, mod, toLocal, weekMinute } from "./time.js";
import type { Rules, TimedLeg } from "./types.js";

export interface Link {
  /** On how many of the arrival's days it makes the departure. */
  days: number;
  /** How many days the arrival flies. */
  of: number;
  /** The tightest connection, minutes from landing to departure. */
  gap_min: number;
}

export interface ConnectionLimits {
  mct_min: number;
  mct_source: "airport" | "default";
  buffer_min: number;
  /** The shortest valid connection: mct_min + buffer_min. */
  min_min: number;
  max_min: number;
}

/** The connection limits at an airport: from mct_min + connection_buffer_min to connection_max_wait_h. */
export function connectionLimits(rules: Rules, code: string): ConnectionLimits {
  const m = mctAt(rules, code);
  const buffer = settingNumber(rules, "connection_buffer_min");
  return { mct_min: m.minutes, mct_source: m.source, buffer_min: buffer, min_min: m.minutes + buffer, max_min: settingNumber(rules, "connection_max_wait_h") * 60 };
}

/** Whether a gap between landing and departure is a valid connection at the airport. */
export const isConnection = (gap: number, lim: ConnectionLimits): boolean => gap >= lim.min_min && gap <= lim.max_min;

/** Minute of the week each of a leg's departures leaves, and lands, in UTC. */
export const departuresOf = (l: TimedLeg): number[] => l.days_utc.map((d) => weekMinute(d, l.dep_utc_min));
export const arrivalsOf = (l: TimedLeg): number[] => departuresOf(l).map((t) => mod(t + l.block_min, WEEK));

/** On which days an arrival makes a departure at the airport it lands at, and the tightest connection; null if never. */
export function link(rules: Rules, arr: TimedLeg, dep: TimedLeg, limits: ConnectionLimits = connectionLimits(rules, arr.dest)): Link | null {
  const deps = departuresOf(dep);
  let n = 0, best: number | null = null;
  for (const a of arrivalsOf(arr)) {
    let ok: number | null = null;
    for (const d of deps) {
      const g = mod(d - a, WEEK);
      if (isConnection(g, limits) && (ok === null || g < ok)) ok = g;
    }
    if (ok !== null) {
      n++;
      if (best === null || ok < best) best = ok;
    }
  }
  return n && best !== null ? { days: n, of: arr.days_utc.length, gap_min: best } : null;
}

export interface LinkedLeg extends Link {
  leg: TimedLeg;
}

const localDep = (rules: Rules, l: TimedLeg) => toLocal(rules, l.origin, l.dep_utc_min, DAY);
const localArr = (rules: Rules, l: TimedLeg) => toLocal(rules, l.dest, l.dep_utc_min + l.block_min, DAY);

/** The flights leaving where this leg lands that it connects onto (not back where it came from), by local departure. */
export function onward(rules: Rules, legs: readonly TimedLeg[], leg: TimedLeg): LinkedLeg[] {
  const lim = connectionLimits(rules, leg.dest);
  const out: LinkedLeg[] = [];
  for (const L of legs) {
    if (L.origin !== leg.dest || L.dest === leg.origin || L.id === leg.id) continue;
    const k = link(rules, leg, L, lim);
    if (k) out.push({ leg: L, ...k });
  }
  return out.sort((a, b) => localDep(rules, a.leg) - localDep(rules, b.leg));
}

/** The flights landing where this leg leaves that connect onto it (not from where it is going), by local arrival. */
export function feeders(rules: Rules, legs: readonly TimedLeg[], leg: TimedLeg): LinkedLeg[] {
  const lim = connectionLimits(rules, leg.origin);
  const out: LinkedLeg[] = [];
  for (const L of legs) {
    if (L.dest !== leg.origin || L.origin === leg.dest || L.id === leg.id) continue;
    const k = link(rules, L, leg, lim);
    if (k) out.push({ leg: L, ...k });
  }
  return out.sort((a, b) => localArr(rules, a.leg) - localArr(rules, b.leg));
}

export interface CityPair {
  from: string;
  to: string;
  /** The tightest connection between the two, minutes. */
  gap_min: number;
  days: number;
  /** The bank it connects in (the departure's bank, else the arrival's), 0 outside the banks. */
  bank: number;
  arrival_leg_id: number;
  departure_leg_id: number;
}

export interface BankRow {
  /** The bank's number, or 0 for outside the banks (or every connection, where the airport has no banks). */
  n: number;
  dep_local_min: number | null;
  arriving_from: string[];
  leaving_to: string[];
  city_pairs: number;
}

export interface ConnectionsAnswer {
  airport: string;
  limits: ConnectionLimits;
  base: { id: number; airline_id: number; role: string } | null;
  banks: ReturnType<typeof bankWindows>;
  arrivals: number;
  departures: number;
  /** Every arrival and departure that connect: their leg ids, on how many days, and the tightest gap. */
  connections: { arrival_leg_id: number; departure_leg_id: number; from: string; to: string; days: number; of: number; gap_min: number }[];
  /** Each city pair linked, once, at its shortest connection. */
  city_pairs: CityPair[];
  by_bank: BankRow[];
}

/** Every connection at an airport across all the legs given (by default all of the input's), with the city pairs they
 *  link and, at a hub, which bank each falls in: the Hubs screen's connections. */
export function connectionsAt(rules: Rules, code: string, legs: readonly TimedLeg[] = timedLegs(rules)): ConnectionsAnswer {
  const arrs = legs.filter((L) => L.dest === code);
  const deps = legs.filter((L) => L.origin === code);
  const H = baseAt(rules, code);
  const banked = !!H && !isFocus(H);
  const bankDep = (L: TimedLeg) => (banked && H ? bankOfDeparture(rules, H, localDep(rules, L))?.n ?? 0 : 0);
  const bankArr = (L: TimedLeg) => (banked && H ? bankOfArrival(rules, H, localArr(rules, L)).n : 0);
  const connections: ConnectionsAnswer["connections"] = [];
  const pairs = new Map<string, CityPair>();
  for (const A of arrs) {
    for (const x of onward(rules, legs, A)) {
      connections.push({ arrival_leg_id: A.id, departure_leg_id: x.leg.id, from: A.origin, to: x.leg.dest, days: x.days, of: x.of, gap_min: x.gap_min });
      if (x.leg.dest === A.origin) continue;
      const k = `${A.origin}>${x.leg.dest}`;
      const cur = pairs.get(k);
      if (!cur || x.gap_min < cur.gap_min) {
        pairs.set(k, { from: A.origin, to: x.leg.dest, gap_min: x.gap_min, days: x.days, bank: bankDep(x.leg) || bankArr(A), arrival_leg_id: A.id, departure_leg_id: x.leg.id });
      }
    }
  }
  const wins = banked && H ? bankWindows(rules, H) : [];
  const rows: BankRow[] = [];
  for (const n of [...wins.map((w) => w.n), 0]) {
    const A = arrs.filter((L) => bankArr(L) === n), D = deps.filter((L) => bankDep(L) === n);
    const P = [...pairs.values()].filter((p) => p.bank === n);
    if (!A.length && !D.length && !P.length) continue;
    rows.push({
      n, dep_local_min: wins.find((w) => w.n === n)?.dep ?? null,
      arriving_from: [...new Set(A.map((L) => L.origin))], leaving_to: [...new Set(D.map((L) => L.dest))], city_pairs: P.length,
    });
  }
  return {
    airport: code, limits: connectionLimits(rules, code), base: H ? { id: H.id, airline_id: H.airline_id, role: H.role } : null, banks: wins,
    arrivals: arrs.length, departures: deps.length, connections, city_pairs: [...pairs.values()], by_bank: rows,
  };
}

/** The check at both ends of a leg (manual §4: "every new plan card and every retime is checked at both ends"): the
 *  flights feeding it where it leaves, and the flights it feeds where it lands. */
export function connectionsAtBothEnds(rules: Rules, legs: readonly TimedLeg[], leg: TimedLeg) {
  return { leg_id: leg.id, feeders: feeders(rules, legs, leg), onward: onward(rules, legs, leg) };
}

export { DEFAULT_MCT_MIN };
