// The Routes screen's logic (decision #18, build pull request 6; spec docs/specs/2026-10-13-routes.md): the list's filters
// and sorts as the old planner's routeRows, each route as it stands with its overrides, each frequency as the planning
// library sees it, the figures the screen words, and every action as one planner_save() call. No screen code, so the
// unit tests run it. Every rule is the library's (lib/rules: frequency, banks, schedule, service); this file only joins
// the tables' rows to it and words what it answers.
import { banks, block, buildRules, card, frequency, game, schedule, service, setting, time, type FrequencyEnds, type FrequencyView, type LocalTimes, type Rules,
  type ServiceProfile, type StoredLeg, type Wave } from "@rules";
import type { Change, Values } from "../../data/save";
import type { Json } from "../../db/types";

// ---------- the rows the screen reads
export interface RouteRow {
  id: number;
  airline_id: number;
  hub_code: string;
  dest_code: string;
  city: string | null;
  country_label: string | null;
  distance_km: number | null;
  market_id: number | null;
  stars: number | null;
  source: string;
  removed: boolean;
  removed_note: string | null;
  city_override: string | null;
  distance_override_km: number | null;
  market_override_id: number | null;
  market_cleared: boolean;
  stars_override: number | null;
  /** The route's own cabin choice, which wins over its market's layout (manual §5; read since 21 Oct). */
  cabin_choice?: string | null;
  updated_at: string;
}
export const ROUTE_COLUMNS = "id, airline_id, hub_code, dest_code, city, country_label, distance_km, market_id, stars, source, removed, removed_note, "
  + "city_override, distance_override_km, market_override_id, market_cleared, stars_override, cabin_choice, updated_at";

/** A market: since 21 Oct only its layout (Standard, Leisure, Leisure Plus or Comfort; spec
 *  docs/specs/2026-10-21-cabins-new-rule.md §2); its default aircraft, cabin and fares went. */
export interface MarketRow {
  id: number;
  airline_id: number;
  name: string;
  layout: string;
}
export const MARKET_ROW_COLUMNS = "id, airline_id, name, layout";

export interface RotationRow {
  id: number;
  airline_id: number;
  route_id: number;
  legacy_key: string | null;
  service_code: string | null;
  fare_pct: number | null;
  launched_on: string | null;
  note: string | null;
  extra: Json;
  updated_at: string;
}
export const ROTATION_COLUMNS = "id, airline_id, route_id, legacy_key, service_code, fare_pct, launched_on, note, extra, updated_at";

export interface LegRow {
  id: number;
  airline_id: number;
  rotation_id: number;
  leg_no: number;
  flight_no: number | null;
  origin_code: string;
  dest_code: string;
  aircraft_id: number | null;
  days_utc: number[];
  dep_utc_min: number | null;
  block_min: number | null;
  updated_at: string;
}
export const LEG_COLUMNS = "id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min, updated_at";

export interface AircraftRow {
  id: number;
  registration: string;
  airline_id: number;
  aircraft_type_id: number | null;
  status: string;
  updated_at: string;
}

/** An airport as a route's header needs it: the game's offset, the world's correction (with its row's updated_at, the
 *  base for changing it; none when the world has no row for the airport), its place and city. */
export interface AirportInfo {
  code: string;
  city: string | null;
  country_code: string | null;
  country_name: string | null;
  /** The country's region (countries.region), where it's read (Check's hub readiness). */
  region?: string | null;
  lat: number | null;
  lon: number | null;
  utc_offset: number | null;
  correction: number | null;
  world_row: { updated_at: string } | null;
}

/** A plan card's leg leaving an airport, for an offset change (its departure is kept local, as the old planner keeps it). */
export interface PlanLegRow { id: number; plan_card_id: number; position: number; flight_no: number | null; origin_code: string; dest_code: string; dep_utc_min: number | null; updated_at: string }

/** One of our airlines, as the screen names it. */
export interface Airline { id: number; code: string | null; name: string; color: string | null }

// ---------- a route as it stands: the research's figures with the planner's overrides (the old planner's routeEdits)
export interface Route {
  row: RouteRow;
  id: number;
  airline_id: number;
  hub: string;
  dest: string;
  city: string;
  dist: number | null;
  market_id: number | null;
  /** The market's name, "" without one. */
  market: string;
  /** The market's layout (manual §5), "" without a market. */
  layout: string;
  stars: number;
}

export function routeOf(row: RouteRow, markets: ReadonlyMap<number, MarketRow>): Route {
  const marketId = row.market_cleared ? null : row.market_override_id ?? row.market_id;
  const m = marketId == null ? undefined : markets.get(marketId);
  return {
    row, id: row.id, airline_id: row.airline_id, hub: row.hub_code, dest: row.dest_code,
    city: row.city_override ?? row.city ?? "", dist: row.distance_override_km ?? row.distance_km,
    market_id: marketId, market: m?.name ?? "", layout: m?.layout ?? "",
    // a research route without stars counts as 3, as the old planner's model
    stars: row.stars_override ?? (row.stars || 3),
  };
}

// ---------- the planning library's view of the airline's routes, as the tables have them now
/** The rules with this airline's routes, rotations and legs taken from the tables (all its routes, flown or not), and
 *  any airports the screen read that the start didn't carry. Everything else is rules_input(world, 'flown')'s. */
export function liveRules(rules: Rules, airlineId: number, routes: readonly Route[], rotations: readonly RotationRow[], legs: readonly LegRow[],
  airports: readonly AirportInfo[] = []): Rules {
  const input = rules.input;
  const have = new Set(input.airports.map((a) => a.code));
  const extra = airports.filter((a) => !have.has(a.code)).map((a) => ({
    code: a.code, city: a.city, country_code: a.country_code, lat: a.lat, lon: a.lon, utc_offset: a.correction ?? a.utc_offset,
    utc_offset_override: a.correction, mct_min: null,
  }));
  const flight = [...input.flight_legs.filter((l) => l.airline_id !== airlineId), ...legs.map((l) => ({
    id: l.id, airline_id: l.airline_id, rotation_id: l.rotation_id, leg_no: l.leg_no, flight_no: l.flight_no, origin_code: l.origin_code,
    dest_code: l.dest_code, aircraft_id: l.aircraft_id, days_utc: [...l.days_utc], dep_utc_min: l.dep_utc_min, block_min: l.block_min,
  }))].sort((a, b) => (a.rotation_id ?? 0) - (b.rotation_id ?? 0) || (a.leg_no ?? 0) - (b.leg_no ?? 0) || a.id - b.id);
  return buildRules({
    ...input,
    airports: [...input.airports, ...extra],
    routes: [...input.routes.filter((r) => r.airline_id !== airlineId), ...routes.map((r) => ({
      id: r.id, airline_id: r.airline_id, hub_code: r.hub, dest_code: r.dest, distance_km: r.dist, market_id: r.market_id, market: r.market || null,
      market_layout: r.layout || null, cabin_choice: r.row.cabin_choice ?? null,
    }))],
    rotations: [...input.rotations.filter((r) => r.airline_id !== airlineId), ...rotations.map((r) => ({ id: r.id, airline_id: r.airline_id, route_id: r.route_id, legacy_key: r.legacy_key }))]
      .sort((a, b) => a.id - b.id),
    flight_legs: flight,
  });
}

// ---------- a frequency: a rotation and its two legs, as the library sees it
export interface Freq {
  rot: RotationRow;
  leg1: LegRow | undefined;
  leg2: LegRow | undefined;
  aircraft: AircraftRow | undefined;
  ends: FrequencyEnds;
  local: LocalTimes;
  view: FrequencyView;
  noOut: number | null;
  /** The return's number, or the outbound's less one when it has none (as the old planner shows it). */
  noBack: number | null;
  wave: Wave;
  waveDest: Wave | null;
}

const stored = (l: LegRow | undefined): StoredLeg => ({ days_utc: l?.days_utc ?? [], dep_utc_min: l?.dep_utc_min ?? null, block_min: l?.block_min ?? null });

/** What a rotation's times depend on: its route's airports and distance, and the type its estimate uses: its aircraft's,
 *  else the airline's most-flown type (the library's game.mostFlownType; its market's aircraft until 21 Oct, as the old
 *  planner's estBlock). */
export function endsOf(rules: Rules, route: Route, aircraft: AircraftRow | undefined): FrequencyEnds {
  return { airline_id: route.airline_id, hub: route.hub, dest: route.dest, distance_km: route.dist, type_id: aircraft?.aircraft_type_id ?? game.mostFlownType(rules, route.airline_id) };
}

export function freqOf(rules: Rules, route: Route, rot: RotationRow, legs: readonly LegRow[], aircraft: ReadonlyMap<number, AircraftRow>): Freq {
  const leg1 = legs.find((l) => l.rotation_id === rot.id && l.leg_no === 1), leg2 = legs.find((l) => l.rotation_id === rot.id && l.leg_no === 2);
  const acId = leg1?.aircraft_id ?? leg2?.aircraft_id ?? null;
  const ac = acId == null ? undefined : aircraft.get(acId);
  const ends = endsOf(rules, route, ac);
  const local = frequency.localTimes(rules, ends, stored(leg1), stored(leg2));
  const view = frequency.view(rules, ends, local);
  const noOut = leg1?.flight_no ?? null;
  const hubBase = banks.airlineBaseAt(rules, route.hub, route.airline_id), destBase = banks.airlineBaseAt(rules, route.dest, route.airline_id);
  return {
    rot, leg1, leg2, aircraft: ac, ends, local, view, noOut, noBack: leg2?.flight_no ?? (noOut ? noOut - 1 : null),
    wave: banks.wave(rules, hubBase, local.dep_hub, view.back?.arr ?? null),
    waveDest: destBase ? banks.wave(rules, destBase, local.dep_dest, view.out?.arr ?? null) : null,
  };
}

export interface RouteSummary {
  count: number;
  rtWk: number;
  rtDay: number;
  tails: string[];
  numbers: string;
  /** Every frequency fits the banks at both ends (none off wave); null without frequencies. */
  allOk: boolean | null;
}

/** A route's frequencies summed up as the list and the header show them (the old routeSummary). */
export function summaryOf(freqs: readonly Freq[]): RouteSummary {
  const rtWk = freqs.reduce((s, f) => s + f.view.round_trips_week, 0);
  return {
    count: freqs.length, rtWk, rtDay: rtWk / 7,
    tails: [...new Set(freqs.map((f) => f.aircraft?.registration ?? "").filter(Boolean))],
    numbers: frequency.numberRanges(freqs.flatMap((f) => [f.noOut, f.noBack]).filter((n): n is number => n != null)),
    allOk: freqs.length ? freqs.every((f) => f.wave.level !== "bad" && !(f.waveDest && f.waveDest.level === "bad")) : null,
  };
}

// ---------- the list: filters in the address, and the old planner's routeRows
export type Sort = "stars" | "distUp" | "distDown" | "dest" | "load";
export const SORTS: readonly [Sort, string][] = [["stars", "Sort: stars"], ["distUp", "Sort: distance ↑"], ["distDown", "Sort: distance ↓"], ["dest", "Sort: destination"], ["load", "Sort: load ↑"]];

export interface Filters {
  /** The airline's code; null for the first of ours. */
  airline: string | null;
  /** The bases picked; null when the address names none (the airline's first base, or the open route's hub). */
  bases: string[] | null;
  trunks: boolean;
  stars: number[];
  markets: string[];
  kmFrom: string;
  kmTo: string;
  active: boolean;
  sort: Sort;
  q: string;
}

const list = (v: string | null) => (v ? v.split(",").map(decodeURIComponent).filter((x) => x !== "") : []);

/** The filters an address holds: /planner/routes?airline=PA&bases=JFK,ORD&stars=5,4&markets=Europe&km=500-2000&active=1&sort=load&q=chi. */
export function parseFilters(search: string): Filters {
  const p = new URLSearchParams(search);
  const bases = p.get("bases");
  const km = (p.get("km") ?? "").split("-");
  const sort = p.get("sort") as Sort | null;
  return {
    airline: p.get("airline") || null,
    bases: bases == null ? null : bases === "all" ? [] : list(bases),
    trunks: p.get("trunks") === "1",
    stars: list(p.get("stars")).map(Number).filter((n) => n >= 1 && n <= 5),
    markets: p.has("markets") ? (p.get("markets") ?? "").split(",").map(decodeURIComponent) : [],
    kmFrom: km[0] ?? "", kmTo: km[1] ?? "",
    active: p.get("active") === "1",
    sort: sort && SORTS.some(([s]) => s === sort) ? sort : "stars",
    q: p.get("q") ?? "",
  };
}

/** The address's query for the filters: only what differs from the defaults, in a fixed order. */
export function filtersQuery(f: Filters): string {
  const p: string[] = [];
  const enc = (xs: readonly string[]) => xs.map((x) => encodeURIComponent(x).replace(/%20/g, "+")).join(",");
  if (f.airline) p.push("airline=" + encodeURIComponent(f.airline));
  if (f.bases) p.push("bases=" + (f.bases.length ? enc(f.bases) : "all"));
  if (f.trunks) p.push("trunks=1");
  if (f.stars.length) p.push("stars=" + f.stars.join(","));
  if (f.markets.length) p.push("markets=" + enc(f.markets));
  if (f.kmFrom || f.kmTo) p.push("km=" + encodeURIComponent(f.kmFrom) + "-" + encodeURIComponent(f.kmTo));
  if (f.active) p.push("active=1");
  if (f.sort !== "stars") p.push("sort=" + f.sort);
  if (f.q) p.push("q=" + encodeURIComponent(f.q));
  return p.length ? "?" + p.join("&") : "";
}

/** A route's loads over 7 days, as route_loads() gives them (its route's or a flight's). */
export interface Load { departures: number; sum: number; full: number; under_95: number; under_85: number; under_70: number; days: number }
export const loadAverage = (a: Load): number => Number(a.sum) / a.departures;

export interface ListContext {
  /** The airline's focus cities and its hubs. */
  focus: readonly string[];
  hubs: readonly string[];
  summaries: ReadonlyMap<number, RouteSummary>;
  loads: ReadonlyMap<number, Load>;
}

export interface ListRow { route: Route; summary: RouteSummary }

const NO_SUMMARY: RouteSummary = { count: 0, rtWk: 0, rtDay: 0, tails: [], numbers: "", allOk: null };

/** The airline's bases as the base picker and the add-route form list them: its hubs and focus cities in their order,
 *  then its stations (since 22 Oct, manual §2: airports it flies point-to-point routes from, never hubs). */
export function pickerBases<B extends { role: string }>(bases: readonly B[]): B[] {
  return [...bases.filter((b) => b.role !== "station"), ...bases.filter((b) => b.role === "station")];
}

/** A base's words in the base picker: "From DEL", "From HYD (focus)", "From LKO (station)". */
export const baseLabel = (b: { airport_code: string; role: string }): string =>
  `From ${b.airport_code}${b.role === "focus" ? " (focus)" : b.role === "station" ? " (station)" : ""}`;

/** The list's focus cities and hubs from the airline's bases: a station is neither, so a station pair is never a trunk. */
export const listBases = (bases: readonly { airport_code: string; role: string }[]): Pick<ListContext, "focus" | "hubs"> => ({
  focus: bases.filter((b) => b.role === "focus").map((b) => b.airport_code),
  hubs: bases.filter((b) => b.role !== "focus" && b.role !== "station").map((b) => b.airport_code),
});

/** A trunk: a route between one of the airline's focus cities and one of its hubs. */
export const isTrunk = (r: Route, ctx: Pick<ListContext, "focus" | "hubs">): boolean =>
  (ctx.focus.includes(r.hub) && ctx.hubs.includes(r.dest)) || (ctx.focus.includes(r.dest) && ctx.hubs.includes(r.hub));

/** The list as the old planner's routeRows gives it: the airline's routes (in the research's order) filtered, then sorted,
 *  then, with a focus city picked, its trunks to the airline's hubs first. picked: the bases picked. */
export function listRows(routes: readonly Route[], f: Filters, picked: readonly string[], ctx: ListContext): ListRow[] {
  const q = f.q.trim().toUpperCase();
  const dmin = Number(f.kmFrom) || 0, dmax = Number(f.kmTo) || Infinity;
  const focusSel = picked.filter((c) => ctx.focus.includes(c));
  const hubMatch = (r: Route) => {
    if (!picked.length) return true;
    if (picked.includes(r.hub)) return !focusSel.includes(r.hub) || !f.trunks || ctx.hubs.includes(r.dest);
    return focusSel.includes(r.dest) && ctx.hubs.includes(r.hub);
  };
  const dist = (r: Route) => r.dist ?? 0;
  const rows = routes.filter((r) => hubMatch(r) && (!f.markets.length || f.markets.includes(r.market))
    && (!f.stars.length || f.stars.includes(r.stars)) && dist(r) >= dmin && dist(r) <= dmax
    && (!q || r.dest.includes(q) || r.city.toUpperCase().includes(q)))
    .map((route) => ({ route, summary: ctx.summaries.get(route.id) ?? NO_SUMMARY }))
    .filter((x) => !f.active || x.summary.count > 0);
  const load = (r: Route) => { const a = ctx.loads.get(r.id); return a ? loadAverage(a) : 999; };
  const cmp: Record<Sort, (a: ListRow, b: ListRow) => number> = {
    stars: (a, b) => b.route.stars - a.route.stars || dist(a.route) - dist(b.route),
    distUp: (a, b) => dist(a.route) - dist(b.route),
    distDown: (a, b) => dist(b.route) - dist(a.route),
    dest: (a, b) => a.route.dest.localeCompare(b.route.dest),
    load: (a, b) => load(a.route) - load(b.route) || b.route.stars - a.route.stars,
  };
  rows.sort(cmp[f.sort]);
  if (focusSel.length) rows.sort((a, b) => Number(isTrunk(b.route, ctx)) - Number(isTrunk(a.route, ctx)));
  return rows;
}

/** The markets' chips: every market the airline's routes name, sorted ("" for a route without one). */
export const marketChips = (routes: readonly Route[]): string[] => [...new Set(routes.map((r) => r.market))].sort();

// ---------- how the screen words things, as the old planner does
export type Mode = "local" | "utc";
/** A clock time, "HH:MM" (the old fmt); "" for none. */
export const fmt = (m: number | null | undefined): string => (m == null || Number.isNaN(m) ? "" : time.clock(m));
/** A local time as the screen shows it: local, or UTC in UTC mode. off: the airport's offset in minutes. */
export const disp = (local: number | null, off: number, mode: Mode): string => (local == null ? "" : fmt(mode === "utc" ? local - off : local));
/** The other one, shown small: "06:00Z" in local mode, "07:00 local" in UTC mode. */
export const alt = (local: number | null, off: number, mode: Mode): string => (local == null ? "" : mode === "utc" ? `${fmt(local)} local` : `${fmt(local - off)}Z`);
/** A duration, "1:15" (the old hhmm). */
export const hhmm = (m: number | null | undefined): string => (m == null ? "" : banks.duration(m));

/** A time typed in a box ("6:30", "0630"; local, or UTC in UTC mode) as a local minute; null for an empty box, "bad"
 *  when it isn't a time (the old planner: "Time as hh:mm"). */
export function fromInput(typed: string, off: number, mode: Mode): number | null | "bad" {
  const v = typed.trim().replace(/^(\d{1,2})(\d{2})$/, "$1:$2");
  if (!v) return null;
  const m = /^(\d{1,2}):(\d{2})$/.exec(v);
  if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) return "bad";
  const t = Number(m[1]) * 60 + Number(m[2]);
  return mode === "utc" ? ((t + off) % 1440 + 1440) % 1440 : t;
}

export const starsText = (n: number) => ({ on: "★".repeat(Math.max(0, Math.min(5, n))), off: "★".repeat(Math.max(0, 5 - n)) });
/** Round trips a day as the old list writes them: 2, or 1.4. */
export const perDay = (x: number): string => (x % 1 ? x.toFixed(1) : String(x));
/** The tails on a route's row: the first three and "+N". */
export const tailsWords = (t: readonly string[]): string => (t.length > 3 ? t.slice(0, 3).join(", ") + " +" + (t.length - 3) : t.join(", "));

// ---------- the list's words since the new look (spec docs/specs/2026-10-22-planner-look-routes.md §3–§5)
/** The list's count in words: "32 flying · 243 to open" (the routes shown, flown and not). */
export const countWords = (shown: number, flying: number): string => `${flying.toLocaleString()} flying · ${(shown - flying).toLocaleString()} to open`;

/** How many of the Filters panel's settings differ from the defaults (demand, markets, km, active only, sort, trunks). */
export const filtersOn = (f: Filters): number =>
  (f.stars.length ? 1 : 0) + (f.markets.length ? 1 : 0) + (f.kmFrom || f.kmTo ? 1 : 0) + (f.active ? 1 : 0) + (f.sort !== "stars" ? 1 : 0) + (f.trunks ? 1 : 0);

/** The base picker's words: "From JFK", "From JFK + ORD", "All bases". */
export const baseWords = (picked: readonly string[]): string => (picked.length ? "From " + picked.join(" + ") : "All bases");

/** A list row's code: the destination's alone when the row leaves the one base picked, else the pair ("JFK–ATL"). */
export const rowCode = (r: Pick<Route, "hub" | "dest">, picked: readonly string[]): string =>
  (picked.length === 1 && picked[0] === r.hub ? r.dest : `${r.hub}–${r.dest}`);

/** A route's name in the detail: "New York → Atlanta" from the airports' cities (the codes where a city isn't known). */
export const routeName = (hubCity: string | null | undefined, hub: string, destCity: string | null | undefined, dest: string): string =>
  `${(hubCity ?? "").trim() || hub} → ${(destCity ?? "").trim() || dest}`;

/** A frequency's aircraft named by its tail and the base it flies from (manual §4): "N003AW (JFK)". */
export const tailName = (registration: string | null | undefined, hub: string): string => (registration ? `${registration} (${hub})` : "");
/** A load's pill class: ok from 95%, warn from 85, orange from 70, else bad (the old lfCls). */
export const loadClass = (avg: number): string => (avg >= 95 ? "ok" : avg >= 85 ? "warn" : avg >= 70 ? "orange" : "bad");
export const loadTip = (a: Load): string =>
  `Estimated from the last 7 days of load reports: ${a.departures} departure${a.departures === 1 ? "" : "s"} — ${a.full} at 95%+, ${a.under_95} under 95, ${a.under_85} under 85, ${a.under_70} under 70.`;
/** A connection's days, as the old planner words them. */
export const daysWords = (k: { days: number; of: number }): string => (k.days === 7 ? "daily" : k.days === k.of ? `${k.days}× a week` : `${k.days} of ${k.of} weekly`);

/** The service profile a route's new frequency starts with, and its fare (the old serviceFor and priceFor). */
export function serviceFor(profiles: readonly ServiceProfile[], route: Route): string {
  return service.profileFor(profiles, route.airline_id, route.dist)?.code ?? "";
}
/** The layout a route calls for, as its header words it (manual §5, by distance since 26 Oct): its distance's range,
 *  Leisure under cabin_leisure_max_km, Leisure Plus to under cabin_leisure_plus_max_km, Comfort beyond (the airline's own
 *  settings where it has them; a low-cost airline flies Standard). An aircraft's cabin follows the range over
 *  cabin_route_share_pct of its block time (the plan card's suggestion); no market or route choice overrides it. */
export function layoutWords(rules: Rules, route: Pick<Route, "dist" | "airline_id">): string {
  if (rules.airlines.get(route.airline_id)?.is_lcc) return "layout Standard";
  const num = (k: string) => { const v = setting(rules, k, route.airline_id); const n = typeof v === "string" ? Number(v) : v; return typeof n === "number" && Number.isFinite(n) ? n : null; };
  const lo = num("cabin_leisure_max_km"), hi = num("cabin_leisure_plus_max_km");
  if (route.dist == null || lo == null || hi == null) return "no layout (no distance)";
  const r = card.cabinRange(route.dist, lo, hi);
  return `layout ${r.layout} (${r.range})`;
}
/** A new frequency's fare: the airline's launch fare (settings.fare_launch_pct, Ryanair's own 85%; manual §5). Until 21 Oct
 *  it was the market's economy fare, which went with the markets' fares (spec docs/specs/2026-10-21-cabins-new-rule.md
 *  §2; every market had the launch fare). Null when the setting is missing. */
export function priceFor(rules: Rules, route: Pick<Route, "airline_id">): number | null {
  const v = setting(rules, "fare_launch_pct", route.airline_id);
  const n = typeof v === "string" && v.trim() !== "" ? Number(v) : v;
  return typeof n === "number" && Number.isFinite(n) ? n : null;
}

/** The next free flight-number pair at the route's hub (the library's nextFlightNumbers), or null without a base there.
 *  At a station the pair comes from the airline's station pool (since 22 Oct); a full pool gives the pair marked full. */
export function nextPair(rules: Rules, route: Route) {
  const b = banks.airlineBaseAt(rules, route.hub, route.airline_id);
  if (!b || (b.flight_no_from == null && !banks.isStation(b))) return null;
  return schedule.nextFlightNumbers(rules, b);
}

/** The pair a new frequency takes: the next free pair, or none when there's no base or the station pool is full. */
export const pairForNew = (nx: ReturnType<typeof nextPair>): { out: number; back: number } | null => (nx && !nx.full ? nx : null);

/** The route detail's words for the next free numbers: "101 out / 102 back (highest used 99)", "station numbers 100–999
 *  all used", or "—". */
export function nextPairWords(nx: ReturnType<typeof nextPair>): string {
  if (!nx) return "—";
  if (nx.full) return `station numbers ${nx.pool?.from ?? "?"}–${nx.pool?.to ?? "?"} all used`;
  return `${nx.out} out / ${nx.back} back${nx.highest ? ` (highest used ${nx.highest})` : ""}`;
}

/** The route detail's words on its hub's banks: the bank times, "station · no banks", or "no bank at this hub". */
export function bankWords(base: { role: string; bank_times?: readonly (string | null)[] | null } | undefined, shown: (t: string) => string): string {
  if (!base) return "no bank at this hub";
  if (base.role === "station") return "station · no banks";
  return "banks " + (base.bank_times ?? []).filter((b): b is string => !!b).map(shown).join(" ");
}

// ---------- the actions, one planner_save() call each
/** A new frequency's old-planner id, made as the old planner's uid(): seven letters and digits. */
export const newLegacyKey = (rand: () => number = Math.random): string => {
  let s = "";
  while (s.length < 7) s += rand().toString(36).slice(2);
  return s.slice(0, 7);
};

const ALL_DAYS = [1, 2, 3, 4, 5, 6, 7];

/** Add frequency (the old add-freq): a rotation and its two legs, as one action, every day, no times yet, the next free
 *  numbers at the hub, the route's service profile and fare, launched today. */
export function addFrequencyChanges(worldId: number, route: Route, next: { out: number; back: number } | null, serviceCode: string, price: number | null,
  today: string, legacyKey: string): Change[] {
  const leg = (n: 1 | 2): Change => ({
    table: "flight_legs", op: "insert", from: { rotation_id: "rotation" },
    values: {
      world_id: worldId, airline_id: route.airline_id, leg_no: n, flight_no: next ? (n === 1 ? next.out : next.back) : null,
      origin_code: n === 1 ? route.hub : route.dest, dest_code: n === 1 ? route.dest : route.hub, aircraft_id: null,
      days_utc: ALL_DAYS, dep_utc_min: null, block_min: null,
    },
  });
  return [
    { table: "rotations", op: "insert", as: "rotation", values: {
      world_id: worldId, airline_id: route.airline_id, route_id: route.id, legacy_key: legacyKey, service_code: serviceCode || null,
      fare_pct: price, launched_on: today } },
    leg(1), leg(2),
  ];
}

/** The fields of a frequency's form, in the old planner's order. (The first eight, its schedule, stamped its aircraft's
 *  schedule_changed_on for the one-week check until the check went on 22 Oct, spec
 *  docs/specs/2026-10-22-remove-aircraft-checks.md.) */
export type FreqField = "days" | "tail" | "noOut" | "noBack" | "depHub" | "arrDest" | "depDest" | "arrHub" | "service" | "price" | "slfOut" | "slfBack" | "launched" | "notes";
const TIME: Partial<Record<FreqField, keyof LocalTimes>> = { depHub: "dep_hub", arrDest: "arr_dest", depDest: "dep_dest", arrHub: "arr_hub" };

function legUpdate(leg: LegRow | undefined, want: Partial<StoredLeg> & { aircraft_id?: number | null; flight_no?: number | null }): Change[] {
  if (!leg) return [];
  const values: Values = {};
  if (want.days_utc && JSON.stringify(want.days_utc) !== JSON.stringify([...leg.days_utc].sort((a, b) => a - b))) values.days_utc = want.days_utc;
  if (want.dep_utc_min !== undefined && want.dep_utc_min !== leg.dep_utc_min) values.dep_utc_min = want.dep_utc_min;
  if (want.block_min !== undefined && want.block_min !== leg.block_min) values.block_min = want.block_min;
  if (want.aircraft_id !== undefined && want.aircraft_id !== leg.aircraft_id) values.aircraft_id = want.aircraft_id;
  if (want.flight_no !== undefined && want.flight_no !== leg.flight_no) values.flight_no = want.flight_no;
  return Object.keys(values).length ? [{ table: "flight_legs", op: "update", key: { id: leg.id }, base: leg.updated_at, values }] : [];
}

/** A frequency's legs as its local times say, with its aircraft (for the estimate and the return's day). */
function legsFor(rules: Rules, f: Freq, local: LocalTimes, ends: FrequencyEnds = f.ends): Change[] {
  const { leg1, leg2 } = frequency.toLegs(rules, ends, local);
  return [...legUpdate(f.leg1, leg1), ...legUpdate(f.leg2, leg2)];
}

export type ChangeAnswer = { changes: Change[] } | { error: string };

/** One field of a frequency's form changed (the old planner's change on .freq [data-k]): the rows it changes, as one
 *  action. Times are typed local, or UTC in UTC mode; empty clears. Nothing when nothing changes. */
export function changeFrequency(rules: Rules, f: Freq, field: FreqField, typed: string, ctx: {
  mode: Mode; aircraft: ReadonlyMap<number, AircraftRow>; byRegistration: ReadonlyMap<string, AircraftRow>; route: Route;
}): ChangeAnswer {
  const v = typed.trim();
  const out: Change[] = [];
  const tf = TIME[field];
  if (tf) {
    const off = tf === "dep_hub" || tf === "arr_hub" ? f.view.offset_hub_min : f.view.offset_dest_min;
    const m = fromInput(v, off, ctx.mode);
    if (m === "bad") return { error: "Time as hh:mm" };
    out.push(...legsFor(rules, f, { ...f.local, [tf]: m }));
  } else if (field === "days") {
    const days = frequency.weekdays(v.replace(/[^1-7]/g, ""));
    out.push(...legsFor(rules, f, { ...f.local, days }));
  } else if (field === "tail") {
    const ac = v ? ctx.byRegistration.get(v) : undefined;
    if (v && !ac) return { error: `No aircraft ${v}` };
    const id = ac?.id ?? null;
    const ends = endsOf(rules, ctx.route, ac);
    const { leg1, leg2 } = frequency.toLegs(rules, ends, f.local);
    out.push(...legUpdate(f.leg1, { ...leg1, aircraft_id: id }), ...legUpdate(f.leg2, { ...leg2, aircraft_id: id }));
    return { changes: out };
  } else if (field === "noOut" || field === "noBack") {
    const n = v === "" ? null : Number(v);
    if (n != null && !(Number.isInteger(n) && n >= 0)) return { error: "A flight number is a whole number" };
    const leg = field === "noOut" ? f.leg1 : f.leg2;
    out.push(...legUpdate(leg, { flight_no: n }));
  } else {
    const r = f.rot;
    const values: Values = {};
    if (field === "service") { if ((r.service_code ?? "") !== v) values.service_code = v || null; }
    else if (field === "price") {
      const n = v === "" ? null : Number(v);
      if (n != null && !Number.isFinite(n)) return { error: "The price is a percentage" };
      if (n !== (r.fare_pct == null ? null : Number(r.fare_pct))) values.fare_pct = n;
    } else if (field === "launched") { if ((r.launched_on ?? "") !== v) values.launched_on = v || null; }
    else if (field === "notes") { if ((r.note ?? "") !== v) values.note = v || null; }
    else {
      const extra = { ...((r.extra && typeof r.extra === "object" && !Array.isArray(r.extra) ? r.extra : {}) as Record<string, Json>) };
      if (String(extra[field] ?? "") !== v) {
        if (v) extra[field] = v;
        else delete extra[field];
        values.extra = extra;
      }
    }
    return { changes: Object.keys(values).length ? [{ table: "rotations", op: "update", key: { id: r.id }, base: r.updated_at, values }] : [] };
  }
  return { changes: out };
}

/** Remove a frequency (the old data-del): its legs, then its rotation, as one action. */
export function deleteFrequencyChanges(f: Freq): Change[] {
  return [
    ...[f.leg1, f.leg2].filter((l): l is LegRow => !!l).map((l): Change => ({ table: "flight_legs", op: "delete", key: { id: l.id }, base: l.updated_at })),
    { table: "rotations", op: "delete", key: { id: f.rot.id }, base: f.rot.updated_at },
  ];
}

/** Add route (the old r-add): a route of the airline's, added in the planner (source added), with the city and distance
 *  from the airport list when they weren't typed, the market, and 3 stars. A route removed earlier comes back as added,
 *  its edits cleared (the old planner drops its routeEdits). An airport the list doesn't have yet is added with it. */
export function addRouteChanges(worldId: number, airlineId: number, hub: string, dest: string, v: { city: string; country: string | null; km: number; marketId: number | null },
  existing: RouteRow | null, newAirport: boolean): Change[] {
  const figures: Values = { city: v.city, country_label: v.country, distance_km: v.km, market_id: v.marketId, stars: 3, source: "added" };
  const out: Change[] = newAirport ? [{ table: "airports", op: "insert", values: { code: dest, city: v.city } }] : [];
  if (existing) {
    out.push({ table: "routes", op: "update", key: { id: existing.id }, base: existing.updated_at, values: {
      ...figures, removed: false, removed_note: null, city_override: null, distance_override_km: null, market_override_id: null, market_cleared: false,
      stars_override: null } });
  } else {
    out.push({ table: "routes", op: "insert", values: { world_id: worldId, airline_id: airlineId, hub_code: hub, dest_code: dest, ...figures } });
  }
  return out;
}

export type RouteField = "stars" | "market" | "dist" | "city";

/** Edit route (the old routeEdits): stars, market ("" clears it), distance or city, into the route's override columns. */
export function editRouteChange(route: Route, field: RouteField, typed: string, markets: readonly MarketRow[]): ChangeAnswer {
  const v = typed.trim(), row = route.row;
  const one = (values: Values): ChangeAnswer => ({ changes: [{ table: "routes", op: "update", key: { id: row.id }, base: row.updated_at, values }] });
  if (field === "stars") {
    const n = Number(v);
    if (!(Number.isInteger(n) && n >= 1 && n <= 5)) return { error: "Stars are 1 to 5" };
    return n === row.stars_override ? { changes: [] } : one({ stars_override: n });
  }
  if (field === "market") {
    if (!v) return row.market_cleared ? { changes: [] } : one({ market_override_id: null, market_cleared: true });
    const m = markets.find((x) => x.airline_id === route.airline_id && x.name === v);
    if (!m) return { error: `No market ${v}` };
    return m.id === row.market_override_id && !row.market_cleared ? { changes: [] } : one({ market_override_id: m.id, market_cleared: false });
  }
  if (field === "dist") {
    const n = v === "" ? null : Number(v);
    if (n != null && !(Number.isInteger(n) && n >= 0)) return { error: "The distance is whole km" };
    return n === row.distance_override_km ? { changes: [] } : one({ distance_override_km: n });
  }
  const city = v || null;
  return city === row.city_override ? { changes: [] } : one({ city_override: city });
}

/** Remove route, and Remove unflown routes shown: removed, never deleted (Reference restores them). */
export function removeRoutesChanges(routes: readonly Route[], note: string): Change[] {
  return routes.map((r) => ({ table: "routes", op: "update", key: { id: r.id }, base: r.row.updated_at, values: { removed: true, removed_note: note } }));
}

// ---------- a UTC offset: the world's correction, every leg touching the airport re-timed to keep its local times
export interface OffsetMove {
  leg: LegRow | PlanLegRow;
  kind: "flight" | "plan card";
  airline_id: number | null;
  flight_no: number | null;
  origin: string;
  dest: string;
  before: StoredLeg;
  after: StoredLeg;
}

/** The legs that move when an airport's offset becomes the hours given (correction: the world's correction to store, or
 *  null to clear it and use the game's), and the one action that sets it: the world's row for the airport and every
 *  leg touching it, each rotation re-timed in local time (frequency.retime) so its local times stay; a plan card's legs
 *  leaving the airport keep their local departure. */
export function offsetChanges(rules: Rules, worldId: number, airport: AirportInfo, correction: number | null, flights: {
  rotations: readonly { rotation_id: number; ends: FrequencyEnds; leg1: LegRow | undefined; leg2: LegRow | undefined }[];
  planLegs: readonly PlanLegRow[];
}): { moves: OffsetMove[]; changes: Change[] } {
  const hours = correction ?? airport.utc_offset;
  const after = frequency.withOffset(rules, airport.code, hours, correction);
  const moves: OffsetMove[] = [];
  const changes: Change[] = [];
  const world: Change = airport.world_row
    ? { table: "world_airports", op: "update", key: { world_id: worldId, airport_code: airport.code }, base: airport.world_row.updated_at, values: { utc_offset_override: correction } }
    : { table: "world_airports", op: "insert", key: { world_id: worldId, airport_code: airport.code }, values: { utc_offset_override: correction } };
  changes.push(world);
  for (const r of flights.rotations) {
    const res = frequency.retime(rules, after, r.ends, stored(r.leg1), stored(r.leg2));
    for (const [leg, want] of [[r.leg1, res.leg1], [r.leg2, res.leg2]] as const) {
      const c = legUpdate(leg, want);
      if (!leg || !c.length) continue;
      changes.push(...c);
      moves.push({ leg, kind: "flight", airline_id: leg.airline_id, flight_no: leg.flight_no, origin: leg.origin_code, dest: leg.dest_code, before: stored(leg), after: want });
    }
  }
  for (const p of flights.planLegs) {
    if (p.dep_utc_min == null || p.origin_code !== airport.code) continue;
    const dep = frequency.retimeDeparture(rules, after, airport.code, p.dep_utc_min);
    if (dep === p.dep_utc_min) continue;
    changes.push({ table: "plan_card_legs", op: "update", key: { id: p.id }, base: p.updated_at, values: { dep_utc_min: dep } });
    moves.push({ leg: p, kind: "plan card", airline_id: null, flight_no: p.flight_no, origin: p.origin_code, dest: p.dest_code,
      before: { days_utc: [], dep_utc_min: p.dep_utc_min, block_min: null }, after: { days_utc: [], dep_utc_min: dep, block_min: null } });
  }
  return { moves, changes };
}

/** An offset as typed in its box ("5.5", "-5", "" to clear the world's correction), or "bad". */
export function parseOffset(typed: string): number | null | "bad" {
  const v = typed.trim();
  if (v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) && n >= -12 && n <= 14 ? n : "bad";
}

export const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
/** A move in the offset question's list, in words: "KF 1001 DEL–BOM leaves 06:40 UTC instead of 06:10, block 2:10 instead of 1:40". */
export function moveWords(m: OffsetMove, code: string | null): string {
  const parts: string[] = [];
  if (m.before.dep_utc_min !== m.after.dep_utc_min) parts.push(`leaves ${fmt(m.after.dep_utc_min)} UTC instead of ${fmt(m.before.dep_utc_min)}`);
  if (JSON.stringify(m.before.days_utc) !== JSON.stringify(m.after.days_utc) && m.kind === "flight") {
    parts.push(`on ${m.after.days_utc.map((d) => DAYS[d - 1]).join(" ")} (UTC) instead of ${m.before.days_utc.map((d) => DAYS[d - 1]).join(" ")}`);
  }
  if (m.before.block_min !== m.after.block_min) parts.push(`block ${hhmm(m.after.block_min)} instead of ${hhmm(m.before.block_min)}`);
  const name = m.kind === "plan card" ? "plan card" : [code, m.flight_no].filter((x) => x != null && x !== "").join(" ");
  return `${name} ${m.origin}–${m.dest}: ${parts.join(", ")}`;
}

export { block };
