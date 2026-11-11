// What the planner reads while its landing page shows on opening (since 11 Nov; spec docs/specs/2026-11-11-stored-figures.md
// §2, "Reading"), beside the stored set: the planning library's input (rules_input(world, 'flown')) and the tables the
// screens read (routes, rotations, flight legs, aircraft, plan cards and their legs, the 7-day lines, the world's airports
// and settings, to-dos, dismissals, interline agreements, and the few small ones Today and Routes open with), each with the
// very query its screen makes, so moving to a screen finds it in the cache. Their normal staleness rules stay: a screen
// opened later reads a stale one again in the background while it shows what was loaded.
import type { FetchQueryOptions } from "@tanstack/react-query";
import { agreementsQuery, countriesQuery } from "../screens/interline/reads";
import { backupsQuery, dismissalsQuery, homeAircraftQuery, jobsQuery, planCardsQuery as homePlanCardsQuery, todoItemsQuery, todosQuery } from "../screens/home/reads";
import { settingsQuery, worldAirportsQuery } from "../screens/reference/reads";
import {
  airlineLegsQuery, airlineRotationsQuery, airlineRoutesQuery, allRoutesQuery, marketsQuery, routesAircraftQuery, serviceProfilesQuery, sharedPairsQuery,
} from "../screens/routes/reads";
import { backupLineQuery } from "../screens/systems/reads";
import {
  buyTypesQuery, configsQuery, gameHostQuery, launchesQuery, lowCostQuery, planCardsQuery as tailsPlanCardsQuery, planLegsQuery, planLineLegsQuery, planLinesQuery,
  tailsAircraftQuery,
} from "../screens/tails/reads";
import { rulesQuery } from "./rules";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type OpeningQuery = FetchQueryOptions<any, any, any, any>;

/** Every read the opening makes (the stored set aside), in the order they're asked. */
export function openingQueries(worldId: number, airlineIds: readonly number[]): OpeningQuery[] {
  const w = worldId;
  return [
    rulesQuery(w),
    // Home and Today
    homeAircraftQuery(w), homePlanCardsQuery(w), todosQuery(w), todoItemsQuery(w), dismissalsQuery(w), backupsQuery(), jobsQuery(),
    // Tails (and Today's orders and lines)
    tailsAircraftQuery(w), configsQuery(w), buyTypesQuery(w), tailsPlanCardsQuery(w), planLegsQuery(w), planLinesQuery(w), planLineLegsQuery(w),
    launchesQuery(w), gameHostQuery(w), lowCostQuery(w),
    // Routes: the world's, then each airline's routes, rotations and legs
    allRoutesQuery(w), sharedPairsQuery(w), marketsQuery(w), serviceProfilesQuery(w), routesAircraftQuery(w),
    ...airlineIds.flatMap((a) => [airlineRoutesQuery(w, a), airlineRotationsQuery(w, a), airlineLegsQuery(w, a)]),
    // Interline, Reference's world airports and settings (Competition reads the settings too), Systems' backup line
    agreementsQuery(w), countriesQuery(), worldAirportsQuery(w), settingsQuery(w), backupLineQuery(),
  ] as OpeningQuery[];
}
