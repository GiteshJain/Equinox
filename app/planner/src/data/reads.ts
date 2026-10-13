// The shell's reads (design §5), each through TanStack Query and keyed by its table (query.ts), with the generated
// types. Screens add their own reads in their own folders as they are built.
import { useQuery } from "@tanstack/react-query";
import type { Json } from "../db/types";
import { tableKey } from "./query";
import { supabase } from "./supabase";

const fail = (what: string, message: string): never => {
  throw new Error(`Couldn't read ${what}: ${message}`);
};

/** The world the planner shows: the default one (#14: a switcher appears only once there's a second world). */
export function useWorld() {
  return useQuery({
    queryKey: tableKey("worlds", "default"),
    queryFn: async () => {
      const { data, error } = await supabase.from("worlds").select("id, name, is_default")
        .order("is_default", { ascending: false }).order("id").limit(1);
      if (error) return fail("the world", error.message);
      const world = data[0];
      if (!world) return fail("the world", "the database has no world");
      return world;
    },
  });
}

/** Our group's airlines in the world, in their display order (airlines.position), with their names and colours. */
export function useOurAirlines(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("airlines", "ours", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const w = worldId ?? 0;
      const groups = await supabase.from("groups").select("id").eq("world_id", w).eq("kind", "ours");
      if (groups.error) return fail("our airlines", groups.error.message);
      const ids = groups.data.map((g) => g.id);
      if (ids.length === 0) return [];
      const { data, error } = await supabase.from("airlines")
        .select("id, game_id, public_name, planner_name, game_name, iata_code, livery_color, position, active")
        .eq("world_id", w).in("group_id", ids)
        .order("position", { ascending: true, nullsFirst: false }).order("id");
      if (error) return fail("our airlines", error.message);
      return data;
    },
  });
}

/** When the planner's data last changed: the newest change_log row. */
export function useLatestChange() {
  return useQuery({
    queryKey: tableKey("change_log", "latest"),
    queryFn: async () => {
      const { data, error } = await supabase.from("change_log").select("changed_at").order("changed_at", { ascending: false }).limit(1);
      if (error) return fail("the change log", error.message);
      return data[0]?.changed_at ?? null;
    },
  });
}

/** settings.planner_time_mode for the world: "local" or "utc", or null when it isn't set. */
export function useTimeModeSetting(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("settings", "planner_time_mode", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.from("settings").select("value")
        .eq("world_id", worldId ?? 0).is("airline_id", null).eq("key", "planner_time_mode").maybeSingle();
      if (error) return fail("the time setting", error.message);
      return parseTimeMode(data?.value ?? null);
    },
  });
}

export type TimeMode = "local" | "utc";
export function parseTimeMode(value: Json | null): TimeMode | null {
  return value === "utc" || value === "local" ? value : null;
}
