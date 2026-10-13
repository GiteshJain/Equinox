// The planning library's input, read once for the whole planner (design §5, "Rules at start"): rules_input(world,
// 'flown'), only the routes that have rotations and the airports they use. Home's figures and the game clocks under the
// header (src/ui/Clocks.tsx) both build on it. Read with GET, so a preview (decision #8) reads it too.
import { useQuery } from "@tanstack/react-query";
import { buildRules, type Rules, type RulesInput } from "@rules";
import { supabase } from "./supabase";

export interface RulesRead {
  rules: Rules;
}

export const rulesKey = (worldId: number | undefined) => ["rules", "flown", worldId] as const;

/** The planning library's input for the world: only the flown routes and the airports they use. */
export function useRules(worldId: number | undefined) {
  return useQuery({
    queryKey: rulesKey(worldId),
    enabled: worldId !== undefined,
    queryFn: async (): Promise<RulesRead> => {
      const { data, error } = await supabase.rpc("rules_input", { p_world_id: worldId ?? 0, p_routes: "flown" }, { get: true });
      if (error) throw new Error(`Couldn't read the planning rules: ${error.message}`);
      return { rules: buildRules(data as unknown as RulesInput) };
    },
  });
}
