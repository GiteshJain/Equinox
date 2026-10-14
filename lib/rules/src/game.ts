// game: the planner's schedule against an airline's public schedule in the game (/api/game-schedule): the Check screen's
// Game check (#18 build pull request 9, spec docs/specs/2026-10-13-check.md) and Tails' check before filing a plan card
// (pull request 7), one home for both (#19).
//   - The game's flights are as the schedule check gives them: a flight number, its two airports, its local departure and
//     arrival ("HH:MM") and its local weekdays ("1234567"); a flight valid only from or until a date says so in valid.
//   - The planner's flights are each frequency's two legs in local time (frequency.localTimes, the old planner's typed
//     times): the outbound on its local weekdays at the hub, the return on those moved to the day it leaves.
//   - Each flight number is compared: the same when every planner entry has a game entry with the same airports, times and
//     days (and the game has no other entry for it, unless that one is valid only for some dates); otherwise in the planner
//     only, in the game only, or different (route, departure, arrival, days). A difference that is only a time or a day
//     change (one entry each side, the same airports) can be fixed from the game: the frequency takes the game's times.
//   - The game's numbers the planner doesn't fly are paired into round trips to add: each with the first other one flying
//     back with a number one apart.
// The old code it follows: the old planner's plannerFlights, compareFlights, applyGameFix and importCandidates, and its
// checkBeforeFile (Tails' compareCard). Plain data in and out; the game itself is read by the screen.
import { type FrequencyEnds, type LocalTimes, localTimes, shiftDays, view, weekdays } from "./frequency.js";
import { typeOfAircraft } from "./input.js";
import { clock, parseClock } from "./time.js";
import type { LegRow, Rules } from "./types.js";

/** One flight of an airline's public schedule, as /api/game-schedule gives it. */
export interface GameFlight { code?: string; no: string; from: string; to: string; days: string; dep: string; arr: string; type?: string; valid?: string }

/** The weekdays' short names, Monday first. */
export const DAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
/** Weekdays as a sorted string; none is every day ("1234567"). */
export const sortDays = (x: string | null | undefined): string => String(x || "1234567").split("").sort().join("");
/** Weekdays in words: "daily", or "Mon Wed Fri". */
export const daysLabel = (d: string): string => (d === "1234567" ? "daily" : [...d].map((ch) => DAY_NAMES[Number(ch) - 1] ?? "?").join(" "));

// ---------- a plan card's legs against the game (Tails' check before filing)
/** A leg to check: its number, airports, local times ("HH:MM", arrival "" when not typed) and local weekdays. */
export interface LegToCheck { no: string; from: string; to: string; dep: string; arr: string; days: string }
export interface CheckRow<L extends LegToCheck = LegToCheck> { L: L; g: GameFlight | null; same: boolean }
export interface CardCheck<L extends LegToCheck = LegToCheck> { rows: CheckRow<L>[]; err: string; found: number; diff: number; miss: number; allSame: boolean }

/** Whether the game flies a leg at its times: its departure, its arrival (when the game gives one) and days. */
export function sameTimes(L: Pick<LegToCheck, "dep" | "arr" | "days">, g: GameFlight): boolean {
  return g.dep === L.dep && (!g.arr || g.arr === L.arr) && (!g.days || sortDays(g.days) === sortDays(L.days));
}

/** Each leg with the game's flight of the same number and airports, and whether its times and days are the same. */
export function compareCard<L extends LegToCheck>(legs: readonly L[], flights: readonly GameFlight[] | null, err = ""): CardCheck<L> {
  const rows = legs.map((L) => {
    const g = flights ? flights.find((x) => String(x.no) === String(L.no) && x.from === L.from && x.to === L.to) ?? null : null;
    return { L, g, same: !!g && sameTimes(L, g) };
  });
  const found = rows.filter((r) => r.g).length, diff = rows.filter((r) => r.g && !r.same).length;
  return { rows, err, found, diff, miss: rows.length - found, allSame: !err && rows.length > 0 && rows.every((r) => r.same) };
}

// ---------- an airline's frequencies in local time
/** One rotation of the airline's, with its two legs and their local times. */
export interface Frequency {
  rotation_id: number;
  route_id: number;
  hub: string;
  dest: string;
  leg1: LegRow | undefined;
  leg2: LegRow | undefined;
  ends: FrequencyEnds;
  local: LocalTimes;
}

/** Each rotation of the airline's (every airline's with null), in id order, with its local times. An empty arrival's
 *  estimate uses the rotation's aircraft's type, else its market's aircraft (marketTypes: markets.default_type_id), as the
 *  old planner's estBlock. */
export function frequencies(rules: Rules, airlineId: number | null, marketTypes?: ReadonlyMap<number, number | null>): Frequency[] {
  const byRotation = new Map<number, { leg1?: LegRow; leg2?: LegRow }>();
  for (const l of rules.legs) {
    if (l.rotation_id == null) continue;
    const r = byRotation.get(l.rotation_id) ?? {};
    if ((l.leg_no ?? 1) === 1) r.leg1 ??= l;
    else r.leg2 ??= l;
    byRotation.set(l.rotation_id, r);
  }
  const out: Frequency[] = [];
  const ids = [...rules.rotations.keys()].sort((a, b) => a - b);
  for (const id of ids) {
    const rot = rules.rotations.get(id);
    const route = rot ? rules.routes.get(rot.route_id) : undefined;
    if (!rot || !route) continue;
    if (airlineId != null && route.airline_id !== airlineId) continue;
    const { leg1, leg2 } = byRotation.get(id) ?? {};
    const acId = leg1?.aircraft_id ?? leg2?.aircraft_id ?? null;
    const typeId = typeOfAircraft(rules, acId)?.id ?? (route.market_id != null ? marketTypes?.get(route.market_id) ?? null : null);
    const ends: FrequencyEnds = { airline_id: route.airline_id, hub: route.hub_code, dest: route.dest_code, distance_km: route.distance_km, type_id: typeId };
    const stored = (l: LegRow | undefined) => ({ days_utc: l?.days_utc ?? [], dep_utc_min: l?.dep_utc_min ?? null, block_min: l?.block_min ?? null });
    out.push({ rotation_id: id, route_id: route.id, hub: route.hub_code, dest: route.dest_code, leg1, leg2, ends, local: localTimes(rules, ends, stored(leg1), stored(leg2)) });
  }
  return out;
}

const hhmm = (m: number | null): string => (m == null ? "" : clock(m));
const daysOf = (d: readonly number[]): string => d.join("");

// ---------- the airline's flights against the game's (the Check screen's Game check)
/** The planner's flights of one number: an entry for each different set of airports and times, with every day it flies. */
export interface PlannerEntry { from: string; to: string; dep: string; arr: string; days: string }

/** The airline's flights by number, as the planner has them (the old plannerFlights): the outbound on its local weekdays,
 *  the return on those moved to the day it leaves; a leg with no number of its own is left out. */
export function plannerFlights(rules: Rules, airlineId: number, marketTypes?: ReadonlyMap<number, number | null>): Map<string, PlannerEntry[]> {
  const map = new Map<string, { from: string; to: string; dep: string; arr: string; days: Set<string> }[]>();
  const add = (no: string, from: string, to: string, dep: string, arr: string, days: string) => {
    if (!no) return;
    const e = map.get(no) ?? [];
    let m = e.find((x) => x.from === from && x.to === to && x.dep === dep && x.arr === arr);
    if (!m) e.push(m = { from, to, dep, arr, days: new Set() });
    for (const ch of days) m.days.add(ch);
    map.set(no, e);
  };
  for (const f of frequencies(rules, airlineId, marketTypes)) {
    const v = view(rules, f.ends, f.local);
    const days = daysOf(f.local.days);
    add(f.leg1?.flight_no == null ? "" : String(f.leg1.flight_no), f.hub, f.dest, hhmm(f.local.dep_hub), hhmm(f.local.arr_dest), days);
    add(f.leg2?.flight_no == null ? "" : String(f.leg2.flight_no), f.dest, f.hub, hhmm(f.local.dep_dest), hhmm(f.local.arr_hub),
      daysOf(shiftDays(f.local.days, v.back ? v.back.dep_day : 0)));
  }
  return new Map([...map].map(([no, e]) => [no, e.map((m) => ({ from: m.from, to: m.to, dep: m.dep, arr: m.arr, days: [...m.days].sort().join("") }))]));
}

/** A difference that is only a time or a day change: the game's airports, times and days, and the planner's days. */
export interface GameFix { from: string; to: string; dep: string; arr: string; days: string; pDays: string }
export interface GameIssue {
  no: string;
  kind: "planner" | "game" | "diff";
  text: string;
  /** The planner's and the game's entries in words: "DEL–BOM 06:00–08:10 daily", several joined by "; ". */
  p: string;
  g: string;
  fix: GameFix | null;
}
export interface GameComparison { ok: number; issues: GameIssue[]; in_game: number; in_planner: number }

interface GameEntry { from: string; to: string; dep: string; arr: string; valid: string; days: string }
const fmt = (x: { from: string; to: string; dep: string; arr: string; days: string; valid?: string }): string =>
  `${x.from}–${x.to} ${x.dep}–${x.arr || "?"} ${daysLabel(x.days)}${x.valid ? " (" + x.valid + ")" : ""}`;

/** The game's flights by number, the same entries merged with their days. */
function gameEntries(game: readonly GameFlight[]): Map<string, GameEntry[]> {
  const G = new Map<string, { from: string; to: string; dep: string; arr: string; valid: string; days: Set<string> }[]>();
  for (const g of game) {
    const e = G.get(g.no) ?? [];
    const valid = g.valid ?? "";
    let m = e.find((x) => x.from === g.from && x.to === g.to && x.dep === g.dep && x.arr === g.arr && x.valid === valid);
    if (!m) e.push(m = { from: g.from, to: g.to, dep: g.dep, arr: g.arr, valid, days: new Set() });
    for (const ch of g.days ?? "") m.days.add(ch);
    G.set(g.no, e);
  }
  return new Map([...G].map(([no, e]) => [no, e.map((m) => ({ ...m, days: [...m.days].sort().join("") }))]));
}

/** Every flight number of the planner's and the game's for an airline, compared (the old compareFlights), in number order. */
export function compare(rules: Rules, airlineId: number, game: readonly GameFlight[], marketTypes?: ReadonlyMap<number, number | null>): GameComparison {
  const P = plannerFlights(rules, airlineId, marketTypes), G = gameEntries(game);
  const issues: GameIssue[] = [];
  let ok = 0;
  const nums = [...new Set([...P.keys(), ...G.keys()])].sort((a, b) => Number(a) - Number(b));
  const same = (a: PlannerEntry, b: GameEntry) => a.from === b.from && a.to === b.to && a.dep === b.dep && a.arr === b.arr && a.days === b.days;
  for (const no of nums) {
    const p = P.get(no) ?? [], g = G.get(no) ?? [];
    if (!g.length) { issues.push({ no, kind: "planner", text: "In the planner, not in the game", p: p.map(fmt).join("; "), g: "", fix: null }); continue; }
    if (!p.length) { issues.push({ no, kind: "game", text: "In the game, not in the planner", p: "", g: g.map(fmt).join("; "), fix: null }); continue; }
    const unmatchedP = p.filter((x) => !g.some((y) => same(x, y)));
    if (!unmatchedP.length && g.every((y) => y.valid || p.some((x) => same(x, y)))) { ok++; continue; }
    const a = (unmatchedP[0] ?? p[0]) as PlannerEntry, b = (g.find((y) => !p.some((x) => same(x, y))) ?? g[0]) as GameEntry;
    const what: string[] = [];
    if (a.from !== b.from || a.to !== b.to) what.push("route");
    if (a.dep !== b.dep) what.push("departure");
    if (a.arr !== b.arr) what.push(a.arr ? "arrival" : "arrival not entered");
    if (a.days !== b.days) what.push("days");
    const fix = p.length === 1 && g.length === 1 && a.from === b.from && a.to === b.to
      ? { from: b.from, to: b.to, dep: b.dep, arr: b.arr, days: b.days, pDays: a.days } : null;
    issues.push({ no, kind: "diff", text: "Different: " + (what.join(", ") || "schedule"), p: p.map(fmt).join("; "), g: g.map(fmt).join("; "), fix });
  }
  return { ok, issues, in_game: game.length, in_planner: [...P.values()].reduce((s, e) => s + e.length, 0) };
}

/** Keys in the order a JavaScript object keeps them (the old planner's Object.keys): whole numbers below 2³² − 1
 *  without leading zeros first, in ascending order, then the rest in the order they came. */
function objectKeyOrder(keys: readonly string[]): string[] {
  const isIndex = (k: string) => /^(0|[1-9]\d*)$/.test(k) && Number(k) < 4294967295;
  return [...keys.filter(isIndex).sort((a, b) => Number(a) - Number(b)), ...keys.filter((k) => !isIndex(k))];
}

/** A round trip to add from the game: its outbound and, when there is one, the return numbered one apart. */
export interface ImportCandidate { a: GameFlight; b: GameFlight | null }

/** The game's flight numbers the planner doesn't have (its own numbers, or a return's outbound less one), paired into round
 *  trips (the old importCandidates): in number order, each with the first other one flying back with a number one apart. */
export function importCandidates(rules: Rules, airlineId: number, game: readonly GameFlight[]): ImportCandidate[] {
  const have = new Set<string>();
  for (const f of frequencies(rules, airlineId)) {
    const out = f.leg1?.flight_no || null;
    const back = f.leg2?.flight_no || (out ? out - 1 : null);
    if (out) have.add(String(out));
    if (back) have.add(String(back));
  }
  const g = new Map<string, GameFlight[]>();
  for (const x of game) if (!have.has(x.no)) g.set(x.no, [...(g.get(x.no) ?? []), x]);
  const keys = objectKeyOrder([...g.keys()]);
  const out: ImportCandidate[] = [], used = new Set<string>();
  for (const no of [...g.keys()].sort((a, b) => Number(a) - Number(b))) {
    if (used.has(no)) continue;
    const a = (g.get(no) as GameFlight[])[0] as GameFlight;
    const back = keys.map((k) => (g.get(k) as GameFlight[])[0] as GameFlight)
      .find((y) => !used.has(y.no) && y.no !== no && y.from === a.to && y.to === a.from && Math.abs(Number(y.no) - Number(no)) === 1) ?? null;
    used.add(no);
    if (back) used.add(back.no);
    out.push({ a, b: back });
  }
  return out;
}

/** Each frequency the fixes change, with its local times once they're applied, in the order given (the old applyGameFix,
 *  one fix after another): a matching outbound takes the game's departure, its arrival when the game gives one and its
 *  days when they differ; a matching return takes its departure and arrival, and the days only when it leaves on the
 *  outbound's day. */
export function fixTimes(rules: Rules, airlineId: number, fixes: readonly { no: string; fix: GameFix | null }[],
  marketTypes?: ReadonlyMap<number, number | null>): Map<number, { freq: Frequency; local: LocalTimes }> {
  const freqs = frequencies(rules, airlineId, marketTypes);
  const out = new Map<number, { freq: Frequency; local: LocalTimes }>();
  for (const i of fixes) {
    const x = i.fix;
    if (!x) continue;
    for (const f of freqs) {
      const cur = out.get(f.rotation_id)?.local ?? { ...f.local, days: [...f.local.days] };
      const changeDays = !!x.days && x.days !== x.pDays;
      if (String(f.leg1?.flight_no ?? "") === i.no && f.hub === x.from && f.dest === x.to) {
        const next = { ...cur, dep_hub: parseClock(x.dep) };
        if (x.arr) next.arr_dest = parseClock(x.arr);
        if (changeDays) next.days = weekdays(x.days);
        out.set(f.rotation_id, { freq: f, local: next });
      } else if (String(f.leg2?.flight_no ?? "") === i.no && f.dest === x.from && f.hub === x.to) {
        const next = { ...cur, dep_dest: parseClock(x.dep) };
        if (x.arr) next.arr_hub = parseClock(x.arr);
        const v = view(rules, f.ends, next);
        if (changeDays && !(v.back && v.back.dep_day)) next.days = weekdays(x.days);
        out.set(f.rotation_id, { freq: f, local: next });
      }
    }
  }
  return out;
}
