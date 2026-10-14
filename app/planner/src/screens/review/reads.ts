// What Review reads (design §5, §8 and §9's Review row; spec docs/specs/2026-10-14-review.md), each through TanStack
// Query, at the screen's moment:
// - the captured figures: airline_cards() (the cards and the group today), airline_profit() for every airline (the cards'
//   sparklines, and the airline page's chart and table), cash_forecast(), route_profit() and aircraft_profit() for the
//   period picked, fare_changes(), fare_plan_status() and cash_log() (the nightly log and the cash entry form);
// - a loads day as the planner holds it (loads_by_day(): the captured and typed loads, the latest winning, and the typed
//   rows behind them, which "Loads by hand" saves through planner_save() since the clean-up, build pull request 14).
// The functions that only read are called with GET, so a preview (decision #8) reads them too. The fare plan and the cash
// log are keyed under their tables (["table", "fare_plan", ...], ["table", "cash_entries", ...]), so a save to those tables
// reads them again.
import { useQueries, useQuery } from "@tanstack/react-query";
import { tableKey } from "../../data/query";
import { supabase } from "../../data/supabase";
import type { AircraftRow, CardsAnswer, CashLog, FareChange, FarePlanAnswer, Forecast, LoadsDay, ProfitAnswer, RouteProfitAnswer } from "./model";

const fail = (what: string, message: string): never => {
  throw new Error(`Couldn't read ${what}: ${message}`);
};
/** The moment a captured figure is asked for: now, to the millisecond, as the database takes it. */
const asOf = () => new Date().toISOString();

async function rpc<T>(what: string, fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn as never, args as never, { get: true });
  if (error) return fail(what, error.message);
  return data as unknown as T;
}

/** Review's cards for every airline, and the group today (airline_cards()). */
export function useReviewCards(worldId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "airline_cards", "review", worldId],
    enabled: worldId !== undefined,
    queryFn: () => rpc<CardsAnswer>("the airlines' cards", "airline_cards", { p_world_id: worldId ?? 0, p_as_of: asOf() }),
  });
}

/** Each airline's profit by day (airline_profit()), for the cards' sparklines and the airline page. */
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

/** The nightly log and today's cash entry figures (cash_log()). */
export function useCashLog(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("cash_entries", "log", worldId),
    enabled: worldId !== undefined,
    queryFn: () => rpc<CashLog>("the nightly log", "cash_log", { p_world_id: worldId ?? 0, p_as_of: asOf() }),
  });
}

/** The loads days from one date to another as the planner holds them (loads_by_day()), by date; a day with nothing captured
 *  or typed isn't there. */
export async function readLoadsDays(worldId: number, from: string, to: string): Promise<Record<string, LoadsDay>> {
  return rpc<Record<string, LoadsDay>>("the loads", "loads_by_day", { p_world_id: worldId, p_from: from, p_to: to });
}

/** A loads day as the planner holds it, or null when it has nothing yet. Keyed under load_entries, so a save to it reads it
 *  again (Loads by hand also reads it again after a save to load_days alone). */
export function useLoadsDay(worldId: number | undefined, day: string) {
  return useQuery({
    queryKey: tableKey("load_entries", "loads_by_day", worldId, day),
    enabled: worldId !== undefined,
    queryFn: async () => (await readLoadsDays(worldId ?? 0, day, day))[day] ?? null,
  });
}
