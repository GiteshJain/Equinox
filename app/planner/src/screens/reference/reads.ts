// What Reference reads (design §9's Reference row: bases and banks, aircraft types, cabins, markets, service profiles,
// removed routes, night bans, time zones, game schedules), each through TanStack Query, keyed by its table so a save reads
// it again: the world's airline_bases, world_airports, settings (the world's), the departures cap (world_rules),
// aircraft_types (with their order cabin), the airlines' own order cabins (airline_order_cabins, since 15 Oct),
// cabin_configs, markets, service_profiles and removed routes, each row with its updated_at (the base for
// changing it); what still uses a type, a layout or a market (the adapter kept such a row); the website's connection
// times (site_content.mct, which the old adapter fell back on); the airports' cities; and the counts the Storage line
// gives. The bank windows and next free numbers are the planning library's, on the start's rules input.
import { useQuery } from "@tanstack/react-query";
import { tableKey } from "../../data/query";
import { supabase } from "../../data/supabase";
import type { Json } from "../../db/types";
import {
  BASE_COLUMNS, CONFIG_COLUMNS, MARKET_COLUMNS, OWN_ORDER_COLUMNS, REMOVED_COLUMNS, SERVICE_COLUMNS, TYPE_COLUMNS, WORLD_AIRPORT_COLUMNS,
  type BaseRow, type ConfigRow, type MarketRow, type OwnOrderCabin, type RemovedRoute, type ServiceRow, type SettingRow, type TypeRow, type WorldAirportRow,
  type WorldRuleRow,
} from "./model";

const fail = (what: string, message: string): never => {
  throw new Error(`Couldn't read ${what}: ${message}`);
};
type Answer<T> = PromiseLike<{ data: T | null; error: { message: string } | null }>;
async function rows<T>(what: string, q: Answer<T[]>): Promise<T[]> {
  const { data, error } = await q;
  if (error) return fail(what, error.message);
  return data ?? [];
}
const num = (v: unknown): number | null => (v == null ? null : Number(v));
const sel = (table: string, cols: string, w: number) => supabase.from(table as never).select(cols).eq("world_id", w);
/** Every row, a thousand at a time (the data API gives at most a thousand in one answer). */
function paged<T>(page: (from: number, to: number) => Answer<T[]>): Answer<T[]> {
  return (async () => {
    const out: T[] = [];
    for (let from = 0; ; from += 1000) {
      const { data, error } = await page(from, from + 999);
      if (error) return { data: null, error };
      out.push(...(data ?? []));
      if ((data ?? []).length < 1000) return { data: out, error: null };
    }
  })();
}

function useRows<T>(table: string, part: string, worldId: number | undefined, what: string, read: (w: number) => Answer<T[]>, map?: (r: T) => T) {
  return useQuery({
    queryKey: tableKey(table, "reference", part, worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const got = await rows<T>(what, read(worldId ?? 0));
      return map ? got.map(map) : got;
    },
  });
}

export const useBases = (w: number | undefined) =>
  useRows<BaseRow>("airline_bases", "bases", w, "the bases", (id) => sel("airline_bases", BASE_COLUMNS, id).order("position").order("id") as unknown as Answer<BaseRow[]>);
export const useWorldAirports = (w: number | undefined) =>
  useRows<WorldAirportRow>("world_airports", "all", w, "what the world says about its airports",
    (id) => paged((from, to) => sel("world_airports", WORLD_AIRPORT_COLUMNS, id).order("airport_code").range(from, to) as unknown as Answer<WorldAirportRow[]>),
    (r) => ({ ...r, mct_min: num(r.mct_min), utc_offset_override: num(r.utc_offset_override) }));
export const useSettings = (w: number | undefined) =>
  useRows<SettingRow>("settings", "world", w, "the settings", (id) => sel("settings", "id, key, value, updated_at", id).is("airline_id", null) as unknown as Answer<SettingRow[]>);
export const useWorldRules = (w: number | undefined) =>
  useRows<WorldRuleRow>("world_rules", "all", w, "the world's rules", (id) => sel("world_rules", "id, key, value, updated_at", id) as unknown as Answer<WorldRuleRow[]>);
export const useTypes = (w: number | undefined) =>
  useRows<TypeRow>("aircraft_types", "reference", w, "the aircraft types", (id) => sel("aircraft_types", TYPE_COLUMNS, id).order("id") as unknown as Answer<TypeRow[]>,
    (r) => ({ ...r, gap_target_h: num(r.gap_target_h) }));
export const useConfigs = (w: number | undefined) =>
  useRows<ConfigRow>("cabin_configs", "reference", w, "the cabin layouts", (id) => sel("cabin_configs", CONFIG_COLUMNS, id).order("id") as unknown as Answer<ConfigRow[]>);
export const useMarkets = (w: number | undefined) =>
  useRows<MarketRow>("markets", "reference", w, "the markets", (id) => sel("markets", MARKET_COLUMNS, id).order("id") as unknown as Answer<MarketRow[]>,
    (r) => ({ ...r, fare_y_pct: num(r.fare_y_pct), fare_j_pct: num(r.fare_j_pct) }));
export const useServices = (w: number | undefined) =>
  useRows<ServiceRow>("service_profiles", "reference", w, "the service profiles", (id) => sel("service_profiles", SERVICE_COLUMNS, id).order("id") as unknown as Answer<ServiceRow[]>);
/** Each airline's own order cabin, where it differs from its type's (airline_order_cabins). */
export const useOwnOrders = (w: number | undefined) =>
  useRows<OwnOrderCabin>("airline_order_cabins", "reference", w, "the airlines' own order cabins",
    (id) => sel("airline_order_cabins", OWN_ORDER_COLUMNS, id).order("airline_id").order("aircraft_type_id") as unknown as Answer<OwnOrderCabin[]>);
export const useRemoved = (w: number | undefined) =>
  useRows<RemovedRoute>("routes", "removed", w, "the removed routes", (id) => sel("routes", REMOVED_COLUMNS, id).eq("removed", true).order("id") as unknown as Answer<RemovedRoute[]>);

/** Whether a type, a layout or a market is still used (by an aircraft, a layout, a market, the types an airline may have,
 *  an order cabin or a route), asked when it's removed: the old adapter kept such a row, and the database would refuse to
 *  remove it. */
export async function stillUsed(w: number, what: "aircraft_types" | "cabin_configs" | "markets", id: number): Promise<string | null> {
  const any = async (table: string, filter: string, label: string) => {
    const { data, error } = await supabase.from(table as never).select("world_id").eq("world_id", w).or(filter).limit(1);
    if (error) return fail(label, error.message);
    return (data ?? []).length ? label : null;
  };
  const checks = what === "aircraft_types"
    ? [any("aircraft", `aircraft_type_id.eq.${id}`, "an aircraft"), any("cabin_configs", `aircraft_type_id.eq.${id}`, "a cabin layout"),
       any("markets", `default_type_id.eq.${id}`, "a market"), any("airline_aircraft_types", `aircraft_type_id.eq.${id}`, "the types an airline may have"),
       any("airline_order_cabins", `aircraft_type_id.eq.${id}`, "an airline's own order cabin")]
    : what === "cabin_configs"
      ? [any("aircraft", `cabin_config_id.eq.${id},order_config_id.eq.${id}`, "an aircraft"), any("markets", `default_config_id.eq.${id}`, "a market"),
         any("aircraft_types", `order_config_id.eq.${id}`, "an aircraft type's order cabin"), any("airline_order_cabins", `order_config_id.eq.${id}`, "an airline's own order cabin")]
      : [any("routes", `market_id.eq.${id},market_override_id.eq.${id}`, "a route")];
  return (await Promise.all(checks)).find((x) => x) ?? null;
}

/** The website's connection times (site_content.mct, {airport: minutes}), which the old adapter fell back on. */
export function useSiteMct() {
  return useQuery({
    queryKey: tableKey("site_content", "mct"),
    queryFn: async (): Promise<Record<string, Json>> => {
      const { data, error } = await supabase.from("site_content").select("value").eq("key", "mct").maybeSingle();
      if (error) return fail("the website's connection times", error.message);
      const v = data?.value;
      return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, Json>) : {};
    },
  });
}

/** The cities of the airports given (the night bans' list names each). */
export function useCities(codes: readonly string[]) {
  const sorted = [...new Set(codes)].sort();
  return useQuery({
    queryKey: ["table", "airports", "cities", sorted.join(",")],
    enabled: sorted.length > 0,
    queryFn: async () => {
      const out = new Map<string, string | null>();
      for (let i = 0; i < sorted.length; i += 300) {
        const { data, error } = await supabase.from("airports").select("code, city").in("code", sorted.slice(i, i + 300));
        if (error) return fail("the airports' cities", error.message);
        for (const a of data ?? []) out.set(a.code, a.city);
      }
      return out;
    },
  });
}

/** The Storage line's counts: frequencies (rotations), tails (aircraft in the old list of tails), route edits (routes with
 *  an edit kept), markets and service profiles are read from the screen's own lists. */
export function useCounts(w: number | undefined) {
  return useQuery({
    queryKey: ["table", "rotations", "reference", "counts", w],
    enabled: w !== undefined,
    queryFn: async () => {
      const id = w ?? 0;
      const head = (t: string, f?: (q: ReturnType<typeof sel>) => unknown) => {
        const q = supabase.from(t as never).select("id", { count: "exact", head: true }).eq("world_id", id);
        return (f ? f(q as never) : q) as unknown as PromiseLike<{ count: number | null; error: { message: string } | null }>;
      };
      const [rot, tails, edits] = await Promise.all([
        head("rotations"),
        head("aircraft", (q) => (q as unknown as { eq: (c: string, v: string) => unknown }).eq("status", "active")),
        head("routes", (q) => (q as unknown as { or: (f: string) => unknown }).or("edit_kept.is.true,removed.is.true,removed_note.not.is.null,city_override.not.is.null,"
          + "distance_override_km.not.is.null,market_override_id.not.is.null,market_cleared.is.true,stars_override.not.is.null")),
      ]);
      for (const r of [rot, tails, edits]) if (r.error) return fail("the counts", r.error.message);
      return { freqs: rot.count ?? 0, tails: tails.count ?? 0, edits: edits.count ?? 0 };
    },
  });
}
