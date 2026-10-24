// What Competition reads (spec docs/specs/2026-10-21-competition-analysis.md §3), through TanStack Query at the screen's
// moment, through the figures' queue (data/limit.ts): competition() for each of our airlines (the group page, and Today's threats from the latest scan) or for one
// (its page), with GET, so a preview reads it too. The answer is the database's (private.fig_competition()).
import { useQueries, useQuery, type UseQueryResult } from "@tanstack/react-query";
import { limited } from "../../data/limit";
import { supabase } from "../../data/supabase";
import { latestThreats, type CompetitionAnswer, type ThreatItem } from "./model";

/** The moment a captured figure is asked for: now, to the millisecond, as the database takes it. */
const asOf = () => new Date().toISOString();

async function competition(airlineId: number): Promise<CompetitionAnswer> {
  const { data, error } = await limited(() => supabase.rpc("competition", { p_airline_id: airlineId, p_as_of: asOf() }, { get: true }));
  if (error) throw new Error(`Couldn't read the competition analysis: ${error.message}`);
  return data as unknown as CompetitionAnswer;
}

/** competition() for one airline: its market share, threats, openings (the top 50) and rival profiles. */
export function useCompetition(airlineId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "competition", airlineId],
    enabled: airlineId !== undefined,
    queryFn: () => competition(airlineId ?? 0),
  });
}

/** competition() for each airline (the same reads as useCompetition): the group page. */
export function useCompetitions(airlineIds: readonly number[]) {
  return useQueries({
    queries: airlineIds.map((id) => ({ queryKey: ["figures", "competition", id], queryFn: () => competition(id) })),
  });
}

/** Today's threats, combined once every airline's answer is in (and the same object while none changes). */
const combineThreats = (results: UseQueryResult<CompetitionAnswer>[]): { threats: ThreatItem[] | null; error: unknown } => ({
  threats: results.every((r) => r.data) ? latestThreats(results.map((r) => r.data)) : null,
  error: results.find((r) => r.error)?.error ?? null,
});

/** The rivals' moves the latest world scan showed on each airline's routes (competition()'s threats with latest true),
 *  for Today's needs attention: the same reads as the Competition screen's. */
export function useLatestThreats(airlineIds: readonly number[]) {
  return useQueries({
    queries: airlineIds.map((id) => ({ queryKey: ["figures", "competition", id], queryFn: () => competition(id) })),
    combine: combineThreats,
  });
}
