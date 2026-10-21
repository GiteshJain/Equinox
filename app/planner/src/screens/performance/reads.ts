// What Performance reads (spec docs/specs/2026-10-20-today-performance-systems.md; before 20 Oct Review's reads, spec
// docs/specs/2026-10-14-review.md, and Check's growth and load report reads), each through TanStack Query, at the
// screen's moment:
// - the captured figures: airline_cards() (the scorecards and the group today), airline_profit() for every airline (the
//   scorecards' sparklines, and the airline page's chart and table), cash_forecast() (the airline page; Today's orders
//   too), route_profit() and aircraft_profit() for the period picked, fare_changes(), fare_plan_status(),
//   growth_signals() (the growth signals) and hub_progress() (main hubs towards their target);
// - the daily history, airline_days (each airline's fleet, schedule and loads each evening: the scorecards' change
//   against the same day last week; staff read it);
// - for Flights by day, one day's captured loads (game_loads, the old planner's CAP.loads, which held the last 9 days)
//   and the loads typed by hand that day (load_entries, load_days).
// The functions that only read are called with GET, so a preview (decision #8) reads them too. The fare plan is keyed
// under its table (["table", "fare_plan", ...]), so a save to it reads it again.
import { useQueries, useQuery } from "@tanstack/react-query";
import { queryClient, tableKey } from "../../data/query";
import { supabase } from "../../data/supabase";
import type { Json } from "../../db/types";
import type { AircraftRow, CardsAnswer, DayRow, FareChange, FarePlanAnswer, Forecast, ProfitAnswer, RouteProfitAnswer } from "./model";

const fail = (what: string, message: string): never => {
  throw new Error(`Couldn't read ${what}: ${message}`);
};
/** The moment a captured figure is asked for: now, to the millisecond, as the database takes it. */
const asOf = () => new Date().toISOString();
const num = (v: Json | undefined): number | null => (v == null ? null : Number(v));
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

async function rpc<T>(what: string, fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn as never, args as never, { get: true });
  if (error) return fail(what, error.message);
  return data as unknown as T;
}

/** After a save that changes cash or the fare plan, the figures that build on them are read again. */
export function refreshFigures() {
  for (const k of ["airline_cards", "airline_profit", "cash_forecast", "route_profit"]) void queryClient.invalidateQueries({ queryKey: ["figures", k] });
}

/** The scorecards for every airline, and the group today (airline_cards()). */
export function useReviewCards(worldId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "airline_cards", "review", worldId],
    enabled: worldId !== undefined,
    queryFn: () => rpc<CardsAnswer>("the airlines' cards", "airline_cards", { p_world_id: worldId ?? 0, p_as_of: asOf() }),
  });
}

/** Each airline's profit by day (airline_profit()), for the scorecards' sparklines and the airline page. */
export function useProfits(airlineIds: readonly number[]) {
  return useQueries({
    queries: airlineIds.map((id) => ({
      queryKey: ["figures", "airline_profit", id],
      queryFn: () => rpc<ProfitAnswer>("the profit by day", "airline_profit", { p_airline_id: id, p_as_of: asOf() }),
    })),
  });
}

/** Cash, next 14 days, for one airline (cash_forecast()). */
export function useForecast(airlineId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "cash_forecast", airlineId],
    enabled: airlineId !== undefined,
    queryFn: () => rpc<Forecast>("the cash forecast", "cash_forecast", { p_airline_id: airlineId ?? 0, p_as_of: asOf() }),
  });
}

/** Cash, next 14 days, for each airline (cash_forecast(), the same reads as useForecast): Today's types safe to order. */
export function useForecasts(airlineIds: readonly number[]) {
  return useQueries({
    queries: airlineIds.map((id) => ({
      queryKey: ["figures", "cash_forecast", id],
      queryFn: () => rpc<Forecast>("the cash forecast", "cash_forecast", { p_airline_id: id, p_as_of: asOf() }),
    })),
  });
}

/** Route profit over the period (route_profit()). */
export function useRouteProfit(airlineId: number | undefined, days: number) {
  return useQuery({
    queryKey: ["figures", "route_profit", airlineId, days],
    enabled: airlineId !== undefined,
    queryFn: () => rpc<RouteProfitAnswer>("the route profit", "route_profit", { p_airline_id: airlineId ?? 0, p_days: days, p_as_of: asOf() }),
  });
}

/** Each aircraft's profit a day over the period (aircraft_profit()). */
export function useAircraftProfit(airlineId: number | undefined, days: number) {
  return useQuery({
    queryKey: ["figures", "aircraft_profit", airlineId, days],
    enabled: airlineId !== undefined,
    queryFn: async () => (await rpc<{ aircraft: AircraftRow[] }>("the aircraft's profit", "aircraft_profit", { p_airline_id: airlineId ?? 0, p_days: days, p_as_of: asOf() })).aircraft ?? [],
  });
}

/** Fare changes seen in the captures (fare_changes()). */
export function useFareChanges(airlineId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "fare_changes", airlineId],
    enabled: airlineId !== undefined,
    queryFn: async () => (await rpc<{ changes: FareChange[] }>("the fare changes", "fare_changes", { p_airline_id: airlineId ?? 0, p_as_of: asOf() })).changes ?? [],
  });
}

/** The fare plan and each route's latest captured fare (fare_plan_status()). */
export function useFarePlan(airlineId: number | undefined) {
  return useQuery({
    queryKey: tableKey("fare_plan", "status", airlineId),
    enabled: airlineId !== undefined,
    queryFn: () => rpc<FarePlanAnswer>("the fare plan", "fare_plan_status", { p_airline_id: airlineId ?? 0, p_as_of: asOf() }),
  });
}

/** The daily history's rows for our airlines from a day to another (airline_days): what the scorecards compare with the
 *  same day last week. Only the columns they use. */
export function useAirlineDays(worldId: number | undefined, from: string, to: string) {
  return useQuery({
    queryKey: tableKey("airline_days", "scorecards", worldId, from, to),
    enabled: worldId !== undefined,
    queryFn: async (): Promise<DayRow[]> => {
      const rows = await pages<DayRow>("the daily history", (a, b) => supabase.from("airline_days")
        .select("airline_id, day, aircraft_total, weekly_departures, eco_load_pct")
        .eq("world_id", worldId ?? 0).gte("day", from).lte("day", to).order("airline_id").order("day").range(a, b) as unknown as Answer<DayRow[]>);
      return rows.map((r) => ({ ...r, aircraft_total: num(r.aircraft_total as Json), weekly_departures: num(r.weekly_departures as Json), eco_load_pct: num(r.eco_load_pct as Json) }));
    },
  });
}

// ---------- the growth signals and main hubs (Check → Growth until 20 Oct)
/** A route in the growth lists (route_profit()'s): its figures over the growth window, in millions. */
export interface SignalRoute {
  airline_id: number;
  route_id: number | null;
  hub: string;
  dest: string;
  flights: number;
  profit_per_flight: number | null;
  /** Hours a flight ties up the aircraft: block time plus the type's turnaround and the turn margin (since 17 Oct). */
  aircraft_hours?: number | null;
  /** Profit a flight ÷ its aircraft hours, what sold-out routes are marked add or raise by (manual §3, 17 Oct). */
  profit_per_aircraft_hour?: number | null;
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

// ---------- Flights by day (Check's daily load report until 20 Oct)
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
