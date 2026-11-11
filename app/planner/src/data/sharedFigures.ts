// The figures several screens read, one query each (since 11 Nov; spec docs/specs/2026-11-11-stored-figures.md §2, "One key
// per figure"): growth_signals() (Home's routes to fix, Performance's growth signals, Routes' load patterns), route_loads()
// (Home's map, Routes' loads) and airline_cards() (Home's and Today's cards, Performance's scorecards). Each screen keeps
// its own reading of the answer, as a select on the one query, so the figure is read once, under one key.
import { readFigure, storedOptions } from "./storedFigures";

/** The moment a captured figure is asked for: now, to the millisecond, as the database takes it. */
const asOf = () => new Date().toISOString();

function worldFigure(fn: "growth_signals" | "route_loads" | "airline_cards", what: string, worldId: number | undefined, enabled = true) {
  return {
    queryKey: ["figures", fn, worldId] as const,
    enabled: worldId !== undefined && enabled,
    queryFn: () => readFigure<unknown>(what, fn, { p_world_id: worldId ?? 0, p_as_of: asOf() }),
    ...storedOptions(fn, { p_world_id: worldId ?? 0 }),
  };
}

/** growth_signals() of the world: the growth lists, whether profit was captured, the load patterns. */
export const growthSignalsQuery = (worldId: number | undefined, enabled = true) => worldFigure("growth_signals", "the growth signals", worldId, enabled);
/** route_loads() of the world: each route's and each flight's economy loads over 7 days. */
export const routeLoadsQuery = (worldId: number | undefined, enabled = true) => worldFigure("route_loads", "the loads per route", worldId, enabled);
/** airline_cards() of the world: each airline's card and the group today. */
export const airlineCardsQuery = (worldId: number | undefined, enabled = true) => worldFigure("airline_cards", "the airlines' cards", worldId, enabled);
