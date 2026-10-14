// What Interline reads (design §9's Interline row: interline agreements, countries), each through TanStack Query: the
// world's interline_agreements, every country's name, and (with Tails' own reads) the aircraft, their plan cards and the
// cards' legs, the airports those legs use and the world's game address. The rotations, routes, bases and the flown
// airports' countries come from the start's rules input; the interline rules from its settings (interline_rules).
import { useQuery } from "@tanstack/react-query";
import { tableKey } from "../../data/query";
import { supabase } from "../../data/supabase";
import { AGREEMENT_COLUMNS, type AgreementRow } from "./model";

const fail = (what: string, message: string): never => {
  throw new Error(`Couldn't read ${what}: ${message}`);
};

/** Every country (the same in every world), by code. */
export function useCountries() {
  return useQuery({
    queryKey: tableKey("countries", "all"),
    staleTime: 10 * 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.from("countries").select("code, name, region").order("code");
      if (error) return fail("the countries", error.message);
      return data;
    },
  });
}

/** The world's interline agreements, with each row's updated_at (the base for changing it). */
export function useAgreements(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("interline_agreements", "interline", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.from("interline_agreements").select(AGREEMENT_COLUMNS).eq("world_id", worldId ?? 0).order("id");
      if (error) return fail("the interline agreements", error.message);
      return data as unknown as AgreementRow[];
    },
  });
}
