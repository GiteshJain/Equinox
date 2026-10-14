// What Check reads (design §5, §8 and §9's Check row; spec docs/specs/2026-10-13-check.md), each through TanStack Query.
// The screen's other reads are the earlier screens' own (Home's airline_cards(), Routes' markets and route_loads(), Tails'
// aircraft, cabin layouts, plan cards, launch days, types each airline may have and the game's address):
// - the captured figures at the screen's moment: capture_status() (Capture), growth_signals() (the growth lists and the
//   load patterns) and hub_progress() (main hubs towards their target);
// - the nightly backup's latest runs (the line under Capture), as the old planner read them;
// - the tables Check shows or changes: every route that isn't removed (with its cabin choice: the next move's options and
//   the cabins), the moves logged (growth_log), the "keep as is" decisions (aircraft_cabin_keeps);
// - one day's captured loads (game_loads, the old planner's CAP.loads, which held the last 9 days) and loads typed by hand
//   that day (load_entries, load_days).
// A table's rows are keyed ["table", <table>, ...] (data/query.ts), so a save puts its answer into them and reads them
// again. The database functions that only read are called with GET, so a preview (decision #8) reads them too.
import { useQuery } from "@tanstack/react-query";
import { tableKey } from "../../data/query";
import { supabase } from "../../data/supabase";
import type { Json } from "../../db/types";
import { ROUTE_COLUMNS, type RouteRow } from "../routes/model";

const fail = (what: string, message: string): never => {
  throw new Error(`Couldn't read ${what}: ${message}`);
};
type Answer<T> = PromiseLike<{ data: T | null; error: { message: string } | null }>;
const PAGE = 1000;
async function pages<T>(what: string, page: (from: number, to: number) => Answer<T[]>): Promise<T[]> {
  const out: T[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await page(from, from + PAGE - 1);
    if (error) return fail(what, error.message);
    out.push(...(data ?? []));
    if (!data || data.length < PAGE) return out;
  }
}
const num = (v: Json | undefined): number | null => (v == null ? null : Number(v));
/** The moment a captured figure is asked for: now, to the millisecond, as the database takes it. */
const asOf = () => new Date().toISOString();

// ---------- the captured figures
export interface CapturePages { today: string | null; yesterday: string | null }
export interface CaptureAirline {
  airline_id: number;
  code: string | null;
  name: string | null;
  pages: Record<string, CapturePages> | null;
  flights_today: number | null;
  flights_yesterday: number | null;
  missing: string[];
  status: "complete" | "missing" | "not captured";
}
export interface CaptureRead { today: string; yesterday: string; airlines: CaptureAirline[] }

/** What the capture collected for each airline today and yesterday (UTC), at the moment (capture_status()). Reload reads
 *  it again; the board says when it was read. */
export function useCapture(worldId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "capture_status", "check", worldId],
    enabled: worldId !== undefined,
    queryFn: async (): Promise<CaptureRead> => {
      const { data, error } = await supabase.rpc("capture_status", { p_world_id: worldId ?? 0, p_as_of: asOf() }, { get: true });
      if (error) return fail("the capture", error.message);
      const d = data as unknown as Partial<CaptureRead>;
      return { today: String(d.today ?? ""), yesterday: String(d.yesterday ?? ""), airlines: d.airlines ?? [] };
    },
  });
}

export interface BackupRun { ran_at: string; kind: string | null; ok: boolean | null; tables: number | null; rows: number | null; files: number | null; note: string | null }

/** The nightly backup's latest runs, as the old planner read them for the line under Capture (the latest 10). */
export function useBackupLine() {
  return useQuery({
    queryKey: tableKey("backup_runs", "check"),
    queryFn: async () => {
      const { data, error } = await supabase.from("backup_runs").select("ran_at, kind, ok, tables, rows, files, note").order("ran_at", { ascending: false }).limit(10);
      if (error) return fail("the backups", error.message);
      return (data as unknown as BackupRun[]).map((b) => ({ ...b, rows: num(b.rows as Json) }));
    },
  });
}

/** A route in the growth lists (route_profit()'s): its figures over the growth window, in millions. */
export interface SignalRoute {
  airline_id: number;
  route_id: number | null;
  hub: string;
  dest: string;
  flights: number;
  profit_per_flight: number | null;
  profit_week: number | null;
  economy: number | null;
  economy_fare: number | null;
  sold_out: number;
  with_loads: number;
  mark: string;
  why: string;
}
export interface SignalAircraft { airline_id: number; registration: string; type: string; net_day: number | null; routes: string[] }
export interface Pattern {
  airline_id: number;
  route_id: number;
  hub: string;
  dest: string;
  departures: number;
  full: number;
  under_85: number;
  under_70: number;
  mark: "cut" | "watch" | "add" | "hold";
  why: string;
}
export interface GrowthRead {
  days: number;
  profit_captured: boolean;
  ready_for_another_flight: SignalRoute[];
  raise_fares: SignalRoute[];
  fix_or_reduce: SignalRoute[];
  aircraft_losing_after_lease: SignalAircraft[];
  load_patterns: Pattern[];
}

const signal = (r: SignalRoute): SignalRoute => ({
  ...r, profit_per_flight: num(r.profit_per_flight as Json), profit_week: num(r.profit_week as Json), economy: num(r.economy as Json),
  economy_fare: num(r.economy_fare as Json), flights: Number(r.flights), sold_out: Number(r.sold_out ?? 0), with_loads: Number(r.with_loads ?? 0),
});

/** The growth lists across our airlines and the load patterns, at the moment (growth_signals()). */
export function useGrowthSignals(worldId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "growth_signals", "check", worldId],
    enabled: worldId !== undefined,
    queryFn: async (): Promise<GrowthRead> => {
      const { data, error } = await supabase.rpc("growth_signals", { p_world_id: worldId ?? 0, p_as_of: asOf() }, { get: true });
      if (error) return fail("the growth signals", error.message);
      const d = data as unknown as Partial<GrowthRead>;
      return {
        days: Number(d.days ?? 0), profit_captured: d.profit_captured ?? true,
        ready_for_another_flight: (d.ready_for_another_flight ?? []).map(signal), raise_fares: (d.raise_fares ?? []).map(signal),
        fix_or_reduce: (d.fix_or_reduce ?? []).map(signal),
        aircraft_losing_after_lease: (d.aircraft_losing_after_lease ?? []).map((a) => ({ ...a, net_day: num(a.net_day as Json), routes: a.routes ?? [] })),
        load_patterns: (d.load_patterns ?? []).map((p) => ({ ...p, departures: Number(p.departures), full: Number(p.full) })),
      };
    },
  });
}

export interface HubProgressAirline {
  airline_id: number;
  code: string | null;
  name: string | null;
  main_hub: string | null;
  exempt: boolean;
  target: number;
  departures: number | null;
  planned: number | null;
  percent: number | null;
}

/** Each airline's main hub towards its weekly target (hub_progress()). */
export function useHubProgress(worldId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "hub_progress", "check", worldId],
    enabled: worldId !== undefined,
    queryFn: async (): Promise<HubProgressAirline[]> => {
      const { data, error } = await supabase.rpc("hub_progress", { p_world_id: worldId ?? 0, p_as_of: asOf() }, { get: true });
      if (error) return fail("the main hubs' progress", error.message);
      return ((data as unknown as { airlines?: HubProgressAirline[] }).airlines ?? []).map((a) => ({
        ...a, target: Number(a.target), departures: num(a.departures as Json), planned: num(a.planned as Json), percent: num(a.percent as Json), exempt: !!a.exempt,
      }));
    },
  });
}

// ---------- the tables
export interface CheckRouteRow extends RouteRow { cabin_choice: string | null }

/** Every route that isn't removed, of every airline (the next move's options and the cabins), in the routes' order. */
export function useAllRoutes(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("routes", "check", worldId),
    enabled: worldId !== undefined,
    queryFn: () => pages<CheckRouteRow>("the routes", (from, to) => supabase.from("routes").select(ROUTE_COLUMNS + ", cabin_choice")
      .eq("world_id", worldId ?? 0).eq("removed", false).order("id").range(from, to) as unknown as Answer<CheckRouteRow[]>),
  });
}

export interface GrowthLogRow { id: number; airline_id: number; logged_on: string; move: string; note: string | null; updated_at: string }

/** The moves logged under the order rotation, in the order they were logged. */
export function useGrowthLog(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("growth_log", "check", worldId),
    enabled: worldId !== undefined,
    queryFn: () => pages<GrowthLogRow>("the moves logged", (from, to) => supabase.from("growth_log").select("id, airline_id, logged_on, move, note, updated_at")
      .eq("world_id", worldId ?? 0).order("id").range(from, to) as unknown as Answer<GrowthLogRow[]>),
  });
}

export interface KeepRow { world_id: number; aircraft_id: number; cabin: string; decided_on: string | null; updated_at: string }

/** The "keep as is" decisions. */
export function useCabinKeeps(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("aircraft_cabin_keeps", "check", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.from("aircraft_cabin_keeps").select("world_id, aircraft_id, cabin, decided_on, updated_at").eq("world_id", worldId ?? 0);
      if (error) return fail("the cabins kept as they are", error.message);
      return data as KeepRow[];
    },
  });
}

/** One flight's captured loads, as game_loads lists them: percent by class and passengers against seats. */
export interface CapturedLoad {
  airline: string | null;
  flight_date: string;
  code: string | null;
  eco: number | null;
  bus: number | null;
  fst: number | null;
  cargo: number | null;
  eco_pax: number | null;
  eco_seats: number | null;
  bus_pax: number | null;
  bus_seats: number | null;
  fst_pax: number | null;
  fst_seats: number | null;
}

/** A day's captured loads (by the flight's local departure date, as the game lists them). */
export function useDayLoads(worldId: number | undefined, day: string, enabled: boolean) {
  return useQuery({
    queryKey: ["figures", "game_loads", worldId, day],
    enabled: worldId !== undefined && enabled,
    queryFn: () => pages<CapturedLoad>("the day's loads", (from, to) => supabase.from("game_loads")
      .select("airline, flight_date, code, eco, bus, fst, cargo, eco_pax, eco_seats, bus_pax, bus_seats, fst_pax, fst_seats")
      .eq("flight_date", day).order("airline").order("code").range(from, to) as unknown as Answer<CapturedLoad[]>),
  });
}

export interface HandLoads { done: boolean; values: { airline_id: number; flight_no: number; eco_pct: number | null }[] }

/** Loads typed by hand for a day (economy under 95%), and whether the day was marked complete. */
export function useHandLoads(worldId: number | undefined, day: string) {
  return useQuery({
    queryKey: tableKey("load_entries", "check", worldId, day),
    enabled: worldId !== undefined,
    queryFn: async (): Promise<HandLoads> => {
      const [e, d] = await Promise.all([
        supabase.from("load_entries").select("airline_id, flight_no, eco_pct").eq("world_id", worldId ?? 0).eq("game_date", day),
        supabase.from("load_days").select("done").eq("world_id", worldId ?? 0).eq("game_date", day).maybeSingle(),
      ]);
      if (e.error) return fail("the loads typed by hand", e.error.message);
      if (d.error) return fail("the day's flags", d.error.message);
      return { done: !!d.data?.done, values: (e.data ?? []).map((x) => ({ airline_id: x.airline_id, flight_no: x.flight_no, eco_pct: num(x.eco_pct as Json) })) };
    },
  });
}

// ---------- read fresh when saving
export interface LegNow { id: number; rotation_id: number; leg_no: number; days_utc: number[]; dep_utc_min: number | null; block_min: number | null; updated_at: string }

/** The legs of some rotations as they are now, with their updated_at (a fix from the game changes them). */
export async function readLegs(rotationIds: readonly number[]): Promise<LegNow[]> {
  if (!rotationIds.length) return [];
  const { data, error } = await supabase.from("flight_legs").select("id, rotation_id, leg_no, days_utc, dep_utc_min, block_min, updated_at")
    .in("rotation_id", [...rotationIds]).order("rotation_id").order("leg_no");
  if (error) return fail("the flight legs", error.message);
  return data as unknown as LegNow[];
}
