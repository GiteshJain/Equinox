// What Routes reads (design §5 and §9, spec docs/specs/2026-10-13-routes.md §1), each through TanStack Query:
// - one airline's routes at a time from the tables (routes, with their overrides), not the whole research at start; the
//   flown routes of every airline are in the start already (rules_input(world, 'flown'), src/data/rules.ts);
// - that airline's rotations and flight legs, with each row's updated_at (the base for changing it);
// - the markets (name and layout), the service profiles and our aircraft (their types, and the order of the old planner's
//   tails);
// - the two airports of the route open (offsets and the world's correction, for the header and an offset change);
// - each route's and each flight's loads over 7 days (route_loads()) and the load patterns (growth_signals()), at the
//   screen's moment.
// A table's rows are keyed ["table", <table>, ...] (data/query.ts), so a save puts its answer into them and reads them
// again. The database functions that only read are called with GET, so a preview reads them too.
import { useQuery } from "@tanstack/react-query";
import { limited } from "../../data/limit";
import { tableKey } from "../../data/query";
import { supabase } from "../../data/supabase";
import {
  LEG_COLUMNS, MARKET_ROW_COLUMNS, ROTATION_COLUMNS, ROUTE_COLUMNS,
  type AircraftRow, type AirportInfo, type LegRow, type LineLegRow, type Load, type MarketRow, type PlanLegRow, type RotationRow, type RouteRow,
} from "./model";

const fail = (what: string, message: string): never => {
  throw new Error(`Couldn't read ${what}: ${message}`);
};

/** The data API gives at most 1,000 rows a call: a list longer than that (an airline's researched routes) is read in pages. */
const PAGE = 1000;
async function pages<T>(what: string, page: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>): Promise<T[]> {
  const out: T[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await page(from, from + PAGE - 1);
    if (error) return fail(what, error.message);
    out.push(...(data ?? []));
    if (!data || data.length < PAGE) return out;
  }
}

/** One airline's routes that aren't removed, in the research's order (by id). */
export function useAirlineRoutes(worldId: number | undefined, airlineId: number | undefined) {
  return useQuery({
    queryKey: tableKey("routes", "airline", worldId, airlineId),
    enabled: worldId !== undefined && airlineId !== undefined,
    queryFn: () => pages<RouteRow>("the routes", (from, to) => supabase.from("routes").select(ROUTE_COLUMNS)
      .eq("world_id", worldId ?? 0).eq("airline_id", airlineId ?? 0).eq("removed", false).order("id").range(from, to) as unknown as PromiseLike<{ data: RouteRow[] | null; error: { message: string } | null }>),
  });
}

/** One route of an airline by its airports, removed or not (Add route brings a removed one back); null when there's none. */
export async function routeByAirports(airlineId: number, hub: string, dest: string): Promise<RouteRow | null> {
  const { data, error } = await supabase.from("routes").select(ROUTE_COLUMNS).eq("airline_id", airlineId).eq("hub_code", hub).eq("dest_code", dest).maybeSingle();
  if (error) return fail("the route", error.message);
  return (data as unknown as RouteRow | null) ?? null;
}

/** One route by its id (the route pop-up on Home), with its overrides. */
export function useRouteRow(routeId: number | null) {
  return useQuery({
    queryKey: tableKey("routes", "one", routeId),
    enabled: routeId != null,
    queryFn: async () => {
      const { data, error } = await supabase.from("routes").select(ROUTE_COLUMNS).eq("id", routeId ?? 0).maybeSingle();
      if (error) return fail("the route", error.message);
      return (data as unknown as RouteRow | null) ?? null;
    },
  });
}

/** A route as every airline's list holds it, with its cabin choice (ROUTE_COLUMNS carries it since 21 Oct). */
export interface AllRouteRow extends RouteRow { cabin_choice: string | null }

/** Every route that isn't removed, of every airline, in the routes' order (Performance's growth lists from the load
 *  reports; Check's until 20 Oct, and Systems' cabins until 21 Oct). */
export function useAllRoutes(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("routes", "check", worldId),
    enabled: worldId !== undefined,
    queryFn: () => pages<AllRouteRow>("the routes", (from, to) => supabase.from("routes").select(ROUTE_COLUMNS)
      .eq("world_id", worldId ?? 0).eq("removed", false).order("id").range(from, to) as unknown as PromiseLike<{ data: AllRouteRow[] | null; error: { message: string } | null }>),
  });
}

/** Every airline's markets in the world: name and, since 21 Oct, only its layout (its default aircraft, cabin and fares
 *  went; spec docs/specs/2026-10-21-cabins-new-rule.md §2). */
export function useMarkets(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("markets", "routes", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.from("markets").select(MARKET_ROW_COLUMNS)
        .eq("world_id", worldId ?? 0).order("id");
      if (error) return fail("the markets", error.message);
      return data as MarketRow[];
    },
  });
}

export interface ServiceRow { id: number; code: string; airline_id: number | null; up_to_km: number | null }

/** The service profiles (Reference → service profiles). */
export function useServiceProfiles(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("service_profiles", "routes", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.from("service_profiles").select("id, code, airline_id, up_to_km").eq("world_id", worldId ?? 0).order("id");
      if (error) return fail("the service profiles", error.message);
      return data as ServiceRow[];
    },
  });
}

/** Our aircraft: registration, type and status, in the order they were added. */
export function useRoutesAircraft(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("aircraft", "routes", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.from("aircraft")
        .select("id, registration, airline_id, aircraft_type_id, status, updated_at")
        .eq("world_id", worldId ?? 0).order("id");
      if (error) return fail("the aircraft", error.message);
      return data as AircraftRow[];
    },
  });
}

/** One airline's rotations, and their legs. */
export function useAirlineRotations(worldId: number | undefined, airlineId: number | undefined) {
  return useQuery({
    queryKey: tableKey("rotations", "airline", worldId, airlineId),
    enabled: worldId !== undefined && airlineId !== undefined,
    queryFn: () => pages<RotationRow>("the rotations", (from, to) => supabase.from("rotations").select(ROTATION_COLUMNS)
      .eq("world_id", worldId ?? 0).eq("airline_id", airlineId ?? 0).order("id").range(from, to) as unknown as PromiseLike<{ data: RotationRow[] | null; error: { message: string } | null }>),
  });
}

export function useAirlineLegs(worldId: number | undefined, airlineId: number | undefined) {
  return useQuery({
    queryKey: tableKey("flight_legs", "airline", worldId, airlineId),
    enabled: worldId !== undefined && airlineId !== undefined,
    queryFn: () => pages<LegRow>("the flight legs", (from, to) => supabase.from("flight_legs").select(LEG_COLUMNS)
      .eq("world_id", worldId ?? 0).eq("airline_id", airlineId ?? 0).order("rotation_id").order("leg_no").range(from, to) as unknown as PromiseLike<{ data: LegRow[] | null; error: { message: string } | null }>),
  });
}

/** Airports by their codes: the game's offset and the world's correction (with its row), place, city and country. */
export function useAirports(worldId: number | undefined, codes: readonly string[]) {
  const sorted = [...new Set(codes)].sort();
  return useQuery({
    queryKey: tableKey("world_airports", "routes", worldId, sorted.join(",")),
    enabled: worldId !== undefined && sorted.length > 0,
    queryFn: () => readAirports(worldId ?? 0, sorted),
  });
}

export async function readAirports(worldId: number, codes: readonly string[]): Promise<AirportInfo[]> {
  const [a, w] = await Promise.all([
    supabase.from("airports").select("code, city, country_code, lat, lon, utc_offset, countries(name, region)").in("code", [...codes]),
    supabase.from("world_airports").select("airport_code, utc_offset_override, updated_at").eq("world_id", worldId).in("airport_code", [...codes]),
  ]);
  if (a.error) return fail("the airports", a.error.message);
  if (w.error) return fail("the airports' corrections", w.error.message);
  const rows = a.data as unknown as { code: string; city: string | null; country_code: string | null; lat: number | null; lon: number | null; utc_offset: number | null; countries: { name: string; region: string } | null }[];
  return rows.map((x) => {
    const wr = (w.data ?? []).find((r) => r.airport_code === x.code);
    return {
      code: x.code, city: x.city, country_code: x.country_code, country_name: x.countries?.name ?? null, region: x.countries?.region ?? null,
      lat: x.lat == null ? null : Number(x.lat), lon: x.lon == null ? null : Number(x.lon), utc_offset: x.utc_offset == null ? null : Number(x.utc_offset),
      correction: wr?.utc_offset_override == null ? null : Number(wr.utc_offset_override), world_row: wr ? { updated_at: wr.updated_at } : null,
    };
  });
}

/** Every flight leg touching an airport (any airline's) and the other leg of each one's rotation, the plan cards' legs
 *  leaving it and, since 28 Oct, the 7-day lines' legs leaving it: what an offset change there re-times. Read fresh, with
 *  each row's updated_at. */
export async function legsAt(worldId: number, code: string): Promise<{ legs: LegRow[]; planLegs: PlanLegRow[]; lineLegs: LineLegRow[] }> {
  const touching = await supabase.from("flight_legs").select("rotation_id").eq("world_id", worldId).or(`origin_code.eq.${code},dest_code.eq.${code}`);
  if (touching.error) return fail("the flights at " + code, touching.error.message);
  const ids = [...new Set((touching.data ?? []).map((r) => r.rotation_id))];
  const legs = ids.length ? await supabase.from("flight_legs").select(LEG_COLUMNS).in("rotation_id", ids).order("rotation_id").order("leg_no") : { data: [], error: null };
  if (legs.error) return fail("the flights at " + code, legs.error.message);
  const plan = await supabase.from("plan_card_legs").select("id, plan_card_id, position, flight_no, origin_code, dest_code, days_utc, dep_utc_min, updated_at")
    .eq("world_id", worldId).eq("origin_code", code).order("plan_card_id").order("position");
  if (plan.error) return fail("the plan cards at " + code, plan.error.message);
  const line = await supabase.from("plan_line_legs").select("id, line_id, position, line_day, flight_no, origin_code, dest_code, dep_utc_min, updated_at")
    .eq("world_id", worldId).eq("origin_code", code).order("line_id").order("position");
  if (line.error) return fail("the lines at " + code, line.error.message);
  return { legs: legs.data as unknown as LegRow[], planLegs: plan.data as PlanLegRow[], lineLegs: line.data as LineLegRow[] };
}

export interface RouteLoadRow extends Load { airline_id: number; route_id: number; average: number }
export interface FlightLoadRow extends Load { airline_id: number; flight_no: number; average: number }

/** Each route's and each flight's economy loads over the last 7 days (route_loads()), at the screen's moment. */
export function useLoads(worldId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "route_loads", "routes and flights", worldId],
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await limited(() => supabase.rpc("route_loads", { p_world_id: worldId ?? 0, p_as_of: new Date().toISOString() }, { get: true }));
      if (error) return fail("the loads", error.message);
      const d = data as { routes?: RouteLoadRow[]; flights?: FlightLoadRow[] };
      return { routes: d.routes ?? [], flights: d.flights ?? [] };
    },
  });
}

export interface PatternRow { airline_id: number; route_id: number; mark: "cut" | "watch" | "add" | "hold"; why: string }

/** The load patterns over the load window (growth_signals()), for the route pop-up's signal. */
export function usePatterns(worldId: number | undefined, enabled = true) {
  return useQuery({
    queryKey: ["figures", "growth_signals", "patterns", worldId],
    enabled: worldId !== undefined && enabled,
    queryFn: async () => {
      const { data, error } = await limited(() => supabase.rpc("growth_signals", { p_world_id: worldId ?? 0, p_as_of: new Date().toISOString() }, { get: true }));
      if (error) return fail("the load patterns", error.message);
      return ((data as { load_patterns?: PatternRow[] }).load_patterns ?? []);
    },
  });
}
