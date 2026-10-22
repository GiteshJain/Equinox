// What Tails reads (design §5 and §9, spec docs/specs/2026-10-13-tails.md), each through TanStack Query:
// - every aircraft of the world (any status: the list is the active ones, the deliveries those with a delivery), with
//   each row's updated_at, the base for changing it;
// - the cabin layouts (code, cabin, cost), the types each airline may have, and the plan cards with their legs;
// - the rotations' launch days (useLaunches: Performance's Flights by day; Tails and its aircraft pop-up read them for
//   the one-week check until it went on 22 Oct, spec docs/specs/2026-10-22-remove-aircraft-checks.md);
// - and, when filing, fresh from the tables: the aircraft, its card's legs, the airline's routes, markets and service
//   profiles, whether its first cabin fit is logged, how many aircraft are in the old planner's list of tails, the
//   airports the card uses, the order's cabin (order_cabin(), the database's one home for it) and the game's schedule
//   (/api/game-schedule).
// Every figure is the planning library's, on the start's rules (rules_input(world, 'flown'), src/data/rules.ts), which
// carry every aircraft, rotation and leg. A table's rows are keyed ["table", <table>, ...] (data/query.ts), so a save puts
// its answer into them and reads them again.
import { useQuery } from "@tanstack/react-query";
import { tableKey } from "../../data/query";
import { supabase } from "../../data/supabase";
import { MARKET_ROW_COLUMNS, ROUTE_COLUMNS, type MarketRow, type RouteRow } from "../routes/model";
import type { ServiceRow } from "../routes/reads";
import {
  AIRCRAFT_COLUMNS, PLAN_CARD_COLUMNS, PLAN_LEG_COLUMNS, type BuyTypeRow, type ConfigRow, type GameFlight, type PlanCardRow, type PlanLegRow, type TailAircraft,
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

export function useTailsAircraft(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("aircraft", "tails", worldId),
    enabled: worldId !== undefined,
    queryFn: () => rows<TailAircraft>("the aircraft", supabase.from("aircraft").select(AIRCRAFT_COLUMNS).eq("world_id", worldId ?? 0).order("id") as unknown as Answer<TailAircraft[]>),
  });
}

export function useConfigs(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("cabin_configs", "tails", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => (await rows<ConfigRow>("the cabin layouts", supabase.from("cabin_configs").select("id, code, aircraft_type_id, cabin, cost")
      .eq("world_id", worldId ?? 0).order("id") as unknown as Answer<ConfigRow[]>)).map((c) => ({ ...c, cost: num(c.cost) })),
  });
}

export function useBuyTypes(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("airline_aircraft_types", "tails", worldId),
    enabled: worldId !== undefined,
    queryFn: () => rows<BuyTypeRow>("the types each airline may have", supabase.from("airline_aircraft_types").select("airline_id, aircraft_type_id")
      .eq("world_id", worldId ?? 0) as unknown as Answer<BuyTypeRow[]>),
  });
}

export function usePlanCards(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("plan_cards", "tails", worldId),
    enabled: worldId !== undefined,
    queryFn: () => rows<PlanCardRow>("the plan cards", supabase.from("plan_cards").select(PLAN_CARD_COLUMNS).eq("world_id", worldId ?? 0).order("id") as unknown as Answer<PlanCardRow[]>),
  });
}

export function usePlanLegs(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("plan_card_legs", "tails", worldId),
    enabled: worldId !== undefined,
    queryFn: () => rows<PlanLegRow>("the plan cards' legs", supabase.from("plan_card_legs").select(PLAN_LEG_COLUMNS).eq("world_id", worldId ?? 0)
      .order("plan_card_id").order("position") as unknown as Answer<PlanLegRow[]>),
  });
}

export interface LaunchRow { id: number; launched_on: string | null; updated_at: string }
export function useLaunches(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("rotations", "tails", worldId),
    enabled: worldId !== undefined,
    queryFn: () => rows<LaunchRow>("the rotations", supabase.from("rotations").select("id, launched_on, updated_at").eq("world_id", worldId ?? 0) as unknown as Answer<LaunchRow[]>),
  });
}

/** The world's game address (worlds.game_host), for an airline's public schedule. */
export function useGameHost(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("worlds", "game_host", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.from("worlds").select("game_host").eq("id", worldId ?? 0).maybeSingle();
      if (error) return fail("the world's game address", error.message);
      return data?.game_host ?? null;
    },
  });
}

/** Low cost or not, for each airline (its cabins). */
export function useLowCost(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("airlines", "low cost", worldId),
    enabled: worldId !== undefined,
    queryFn: () => rows<{ id: number; is_lcc: boolean | null }>("the airlines", supabase.from("airlines").select("id, is_lcc").eq("world_id", worldId ?? 0) as unknown as Answer<{ id: number; is_lcc: boolean | null }[]>),
  });
}

// ---------- read fresh when filing or deleting
export async function readAircraft(id: number): Promise<TailAircraft | null> {
  const { data, error } = await supabase.from("aircraft").select(AIRCRAFT_COLUMNS).eq("id", id).maybeSingle();
  if (error) return fail("the aircraft", error.message);
  return (data as unknown as TailAircraft | null) ?? null;
}
export async function readCardLegs(cardId: number): Promise<PlanLegRow[]> {
  return rows<PlanLegRow>("the plan card's legs", supabase.from("plan_card_legs").select(PLAN_LEG_COLUMNS).eq("plan_card_id", cardId).order("position") as unknown as Answer<PlanLegRow[]>);
}
export async function readCard(aircraftId: number): Promise<PlanCardRow | null> {
  const { data, error } = await supabase.from("plan_cards").select(PLAN_CARD_COLUMNS).eq("aircraft_id", aircraftId).maybeSingle();
  if (error) return fail("the plan card", error.message);
  return (data as unknown as PlanCardRow | null) ?? null;
}
/** Rotations and their legs, with each row's updated_at (Delete aircraft… removes them). */
export async function readRotationsWithLegs(ids: readonly number[]): Promise<{ id: number; updated_at: string; legs: { id: number; updated_at: string }[] }[]> {
  if (!ids.length) return [];
  const [r, l] = await Promise.all([
    rows<{ id: number; updated_at: string }>("the rotations", supabase.from("rotations").select("id, updated_at").in("id", [...ids]).order("id") as unknown as Answer<{ id: number; updated_at: string }[]>),
    rows<{ id: number; rotation_id: number; updated_at: string }>("the flight legs", supabase.from("flight_legs").select("id, rotation_id, updated_at").in("rotation_id", [...ids])
      .order("rotation_id").order("leg_no") as unknown as Answer<{ id: number; rotation_id: number; updated_at: string }[]>),
  ]);
  return r.map((x) => ({ ...x, legs: l.filter((y) => y.rotation_id === x.id).map((y) => ({ id: y.id, updated_at: y.updated_at })) }));
}
/** The airline's routes, removed ones too (filing brings one back rather than adding it twice). */
export async function readAirlineRoutes(airlineId: number): Promise<RouteRow[]> {
  const out: RouteRow[] = [];
  for (let from = 0; ; from += 1000) {
    const page = await rows<RouteRow>("the routes", supabase.from("routes").select(ROUTE_COLUMNS).eq("airline_id", airlineId).order("id").range(from, from + 999) as unknown as Answer<RouteRow[]>);
    out.push(...page);
    if (page.length < 1000) return out;
  }
}
/** The markets: name and layout (all a market keeps since 21 Oct). */
export async function readMarkets(worldId: number): Promise<MarketRow[]> {
  return rows<MarketRow>("the markets", supabase.from("markets").select(MARKET_ROW_COLUMNS)
    .eq("world_id", worldId).order("id") as unknown as Answer<MarketRow[]>);
}
export async function readProfiles(worldId: number): Promise<ServiceRow[]> {
  return rows<ServiceRow>("the service profiles", supabase.from("service_profiles").select("id, code, airline_id, up_to_km").eq("world_id", worldId).order("id") as unknown as Answer<ServiceRow[]>);
}
/** Whether a first cabin fit is logged for a registration already (the old filePlan's check: a cabin entry whose note
 *  starts with it). */
export async function cabinLogged(worldId: number, registration: string): Promise<boolean> {
  const list = await rows<{ note: string | null }>("the money spent", supabase.from("spending_log").select("note").eq("world_id", worldId).eq("kind", "cabin") as unknown as Answer<{ note: string | null }[]>);
  return list.some((x) => String(x.note ?? "").startsWith(registration + " "));
}
/** The airline's public schedule from the game (the existing Pages Function), or why it couldn't be read. */
export async function readGameSchedule(link: string): Promise<{ flights: GameFlight[] } | { error: string }> {
  try {
    const r = await fetch("/api/game-schedule?u=" + encodeURIComponent(link));
    const j = (await r.json()) as { flights?: GameFlight[]; error?: string };
    if (!r.ok) return { error: j.error || String(r.status) };
    return { flights: j.flights ?? [] };
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) };
  }
}

/** What the old adapter looked at when an aircraft left both its lists (removing a delivery): whether the capture or money
 *  spent knows it (game_flights, game_payments, spending_log), and whether a flight, a plan card or a kept cabin points at
 *  it. Read fresh when asked. */
export async function removalFacts(worldId: number, aircraftId: number): Promise<{ money: boolean; pointedAt: boolean }> {
  const any = async (table: string) => {
    const { data, error } = await supabase.from(table as never).select("aircraft_id").eq("aircraft_id", aircraftId).limit(1);
    if (error) return fail(`what points at the aircraft (${table})`, error.message);
    return (data ?? []).length > 0;
  };
  void worldId;
  const [f, p, s, l, c, k] = await Promise.all(["game_flights", "game_payments", "spending_log", "flight_legs", "plan_cards", "aircraft_cabin_keeps"].map(any));
  return { money: !!(f || p || s), pointedAt: !!(l || c || k) };
}
