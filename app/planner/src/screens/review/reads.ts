// What Review reads (design §5, §8 and §9's Review row; spec docs/specs/2026-10-14-review.md), each through TanStack
// Query, at the screen's moment:
// - the captured figures: airline_cards() (the cards and the group today), airline_profit() for every airline (the cards'
//   sparklines, and the airline page's chart and table), cash_forecast(), route_profit() and aircraft_profit() for the
//   period picked, fare_changes(), fare_plan_status() and cash_log() (the nightly log and the cash entry form);
// - a loads day as the old planner holds it (planner_loads_get(), the route its "Loads by hand" reads and save_loads()
//   writes, since loads are saved that way: spec, "use the same route").
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

/** A loads day as the old planner holds it (planner_loads_get()'s month for the day), or null when it has none. Keyed
 *  under load_entries, so it is read again after a save. */
export function useLoadsDay(worldId: number | undefined, day: string) {
  return useQuery({
    queryKey: tableKey("load_entries", "planner_loads_get", worldId, day.slice(0, 7)),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("planner_loads_get", { p_world_id: worldId ?? 0 }, { get: true });
      if (error) return fail("the loads", error.message);
      const row = (data ?? []).find((r) => r.month === day.slice(0, 7));
      const month = row ? (JSON.parse(row.json) as Record<string, LoadsDay>) : {};
      return month;
    },
    select: (month: Record<string, LoadsDay>) => month[day] ?? null,
  });
}
