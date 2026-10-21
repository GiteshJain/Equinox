// What Home reads (design §9, spec docs/specs/2026-10-13-home.md §2), each through TanStack Query. Since 20 Oct Today
// reads most of these too, for needs attention, Coming up and the to-do board, which moved there from Home (spec
// docs/specs/2026-10-20-today-performance-systems.md):
// - the planning library's input, the lighter start: rules_input(world, 'flown') (design §5; src/data/rules.ts);
// - the planner tables it shows: aircraft (on order, and the one-week checks' dates), rotations' launch days, plan cards
//   (and, for the map's Planned routes, their legs and those legs' airports), to-dos and their steps, dismissals;
// - the jobs' records: job_runs and backup_runs;
// - the captured figures, at the screen's moment: capture_status(), airline_cards() (with the group's average load),
//   growth_signals() (routes to fix, whether profit was captured, the load patterns) and, with one airline picked on the
//   map, route_loads();
// - the website's photos (site_public()), for the airline cards' hub-city photos, as the old Home shows them.
// The database functions that only read are called with GET, so a preview (decision #8), which refuses every other
// call to the data API, reads them too. A table's rows are keyed ["table", <table>, ...] (data/query.ts), so a save puts
// its answer into them and reads them again.
import { useQuery } from "@tanstack/react-query";
import { tableKey } from "../../data/query";
import { supabase } from "../../data/supabase";

const fail = (what: string, message: string): never => {
  throw new Error(`Couldn't read ${what}: ${message}`);
};

/** The moment a captured figure is asked for: now, to the millisecond, as the database takes it. */
const asOf = (offsetMs = 0) => new Date(Date.now() - offsetMs).toISOString();

/** One of our airlines as Home names it: the old planner's name (Pan American), so its words and keys are the old ones
 *  (Today's needs attention keys its items by it too). */
export interface HomeAirline {
  id: number;
  name: string;
  code: string | null;
  color: string | null;
  /** The city whose photo the airline's card shows (airlines.photo_city). */
  photo?: string | null;
}

export interface AircraftRow {
  id: number;
  registration: string;
  airline_id: number;
  aircraft_type_id: number | null;
  order_config_id: number | null;
  status: string;
  delivery_at: string | null;
  order_base_code: string | null;
  order_note: string | null;
  checked_on: string | null;
  schedule_changed_on: string | null;
  updated_at: string;
}

/** Our aircraft on order, arrived but not filed, and in service. */
export function useHomeAircraft(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("aircraft", "home", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.from("aircraft")
        .select("id, registration, airline_id, aircraft_type_id, order_config_id, status, delivery_at, order_base_code, order_note, checked_on, schedule_changed_on, updated_at")
        .eq("world_id", worldId ?? 0).in("status", ["on_order", "delivered", "active"]).order("id");
      if (error) return fail("the aircraft", error.message);
      return data as AircraftRow[];
    },
  });
}

export interface RotationRow { id: number; airline_id: number; route_id: number; launched_on: string | null; updated_at: string }

/** Every rotation's launch day (the one-week checks). */
export function useRotations(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("rotations", "home", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.from("rotations").select("id, airline_id, route_id, launched_on, updated_at")
        .eq("world_id", worldId ?? 0).order("id");
      if (error) return fail("the rotations", error.message);
      return data as RotationRow[];
    },
  });
}

export interface PlanCardRow { id: number; aircraft_id: number; title: string | null; updated_at: string }

/** Which aircraft have a plan card, with its title (Aircraft on order: "File into planner", and its Plan column). */
export function usePlanCards(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("plan_cards", "home", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.from("plan_cards").select("id, aircraft_id, title, updated_at").eq("world_id", worldId ?? 0);
      if (error) return fail("the plan cards", error.message);
      return data as PlanCardRow[];
    },
  });
}

export interface TodoRow {
  id: number;
  world_id: number;
  legacy_key: string | null;
  title: string;
  due_on: string | null;
  done: boolean;
  done_at: string | null;
  updated_at: string;
}
export interface TodoItemRow { id: number; todo_id: number; position: number; body: string; updated_at: string }

/** The to-do board, in the order the old planner keeps it (the table's own order). */
export function useTodos(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("todos", "home", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.from("todos").select("id, world_id, legacy_key, title, due_on, done, done_at, updated_at")
        .eq("world_id", worldId ?? 0).order("id");
      if (error) return fail("the to-dos", error.message);
      return data as TodoRow[];
    },
  });
}

export function useTodoItems(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("todo_items", "home", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.from("todo_items").select("id, todo_id, position, body, updated_at")
        .eq("world_id", worldId ?? 0).order("todo_id").order("position");
      if (error) return fail("the to-dos' steps", error.message);
      return data as TodoItemRow[];
    },
  });
}

export interface DismissalRow { world_id: number; alert_key: string; dismissed_on: string | null; updated_at: string }

export function useDismissals(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("dismissals", "home", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.from("dismissals").select("world_id, alert_key, dismissed_on, updated_at").eq("world_id", worldId ?? 0);
      if (error) return fail("the dismissed items", error.message);
      return data as DismissalRow[];
    },
  });
}

export interface BackupRun { ran_at: string; kind: string | null; ok: boolean | null; note: string | null }

/** The nightly backup's latest runs, as the old planner reads them (the latest 10). */
export function useBackups() {
  return useQuery({
    queryKey: tableKey("backup_runs", "home"),
    queryFn: async () => {
      const { data, error } = await supabase.from("backup_runs").select("ran_at, kind, ok, note").order("ran_at", { ascending: false }).limit(10);
      if (error) return fail("the backups", error.message);
      return data as BackupRun[];
    },
  });
}

export interface JobRun {
  job: string;
  status: string;
  started_at: string;
  for_month: string | null;
  note: string | null;
  details: { table?: string } | null;
}
export interface JobsRead { runs: JobRun[]; archiveLast: { started_at: string } | null }

/** The automatic jobs' runs of the last 40 days (snapshot, the 10:00 UTC fallback, clean-up, archive) and the archive's
 * latest run, as the old planner reads them for Home's warnings. */
export function useJobs() {
  return useQuery({
    queryKey: tableKey("job_runs", "home"),
    queryFn: async (): Promise<JobsRead> => {
      const [j, a] = await Promise.all([
        supabase.from("job_runs").select("job, status, started_at, for_month, note, details")
          .in("job", ["snapshot", "snapshot_fallback", "cleanup", "archive"]).gte("started_at", asOf(40 * 86_400_000))
          .order("started_at", { ascending: false }).limit(500),
        supabase.from("job_runs").select("started_at").eq("job", "archive").order("started_at", { ascending: false }).limit(1),
      ]);
      if (j.error) return fail("the nightly jobs", j.error.message);
      if (a.error) return fail("the nightly jobs", a.error.message);
      return { runs: j.data as JobRun[], archiveLast: (a.data[0] as { started_at: string } | undefined) ?? null };
    },
  });
}

export interface CaptureAirline {
  airline_id: number;
  pages: Record<string, { today: string | null; yesterday: string | null }> | null;
  /** The airline's latest capture's verdict (#21): ok, short or broken; null when none was judged. */
  verdict?: "ok" | "short" | "broken" | null;
  /** "all good", or what came in short or broken ("short: loads 12 of 78 flights"). */
  verdict_words?: string | null;
  /** That capture's latest page. */
  verdict_at?: string | null;
}
/** An airline's latest capture as judged page by page (#21). */
export interface CaptureVerdict { airline_id: number; verdict: "ok" | "short" | "broken"; words: string; at: string }
export interface CaptureRead {
  /** Each of our airlines (capture_status's, in order) with its latest page since midnight UTC two days ago, or null. */
  last: { airline_id: number; at: string | null }[];
  /** Each airline's latest capture's verdict, where one was judged (#21). */
  verdicts?: CaptureVerdict[];
}

/** When each airline was last captured. capture_status() gives today and yesterday (UTC) at its moment; asked again a
 * day earlier it gives the two days before, so together they reach back to midnight UTC two days ago, as far as the old
 * planner's Home read the capture (game_capture_raw since utcDay(-2)). */
export function useCaptureStatus(worldId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "capture_status", worldId],
    enabled: worldId !== undefined,
    queryFn: async (): Promise<CaptureRead> => {
      const [now, before] = await Promise.all([
        supabase.rpc("capture_status", { p_world_id: worldId ?? 0, p_as_of: asOf() }, { get: true }),
        supabase.rpc("capture_status", { p_world_id: worldId ?? 0, p_as_of: asOf(86_400_000) }, { get: true }),
      ]);
      if (now.error) return fail("the capture", now.error.message);
      if (before.error) return fail("the capture", before.error.message);
      const latest = (a: CaptureAirline | undefined) => Object.values(a?.pages ?? {})
        .flatMap((p) => [p.today, p.yesterday]).filter((x): x is string => !!x)
        .reduce<string | null>((m, x) => (m == null || Date.parse(x) > Date.parse(m) ? x : m), null);
      const earlier = new Map(((before.data as { airlines?: CaptureAirline[] }).airlines ?? []).map((a) => [a.airline_id, a]));
      const airlines = (now.data as { airlines?: CaptureAirline[] }).airlines ?? [];
      return {
        last: airlines.map((a) => {
          const at = [latest(a), latest(earlier.get(a.airline_id))].filter((x): x is string => !!x)
            .reduce<string | null>((m, x) => (m == null || Date.parse(x) > Date.parse(m) ? x : m), null);
          return { airline_id: a.airline_id, at };
        }),
        verdicts: airlines.flatMap((a) => (a.verdict && a.verdict_at
          ? [{ airline_id: a.airline_id, verdict: a.verdict, words: a.verdict_words ?? "", at: a.verdict_at }] : [])),
      };
    },
  });
}

export interface AirlineCard { airline_id: number; load_7_days: number | null; can_order_now: string[] | null }

export interface CardsRead {
  airlines: AirlineCard[];
  /** The group's average economy load over 7 days (the old Home's figure), how many flights it covers, and whether it
   * comes from the captures or, with none captured, from the load reports; null with neither. */
  load_7_days: number | null;
  load_7_days_flights: number;
  load_7_days_from: "captures" | "reports" | null;
}

/** Review's cards for our airlines at the moment: what each can order now (cash_forecast()), and the group's load. */
export function useAirlineCards(worldId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "airline_cards", worldId],
    enabled: worldId !== undefined,
    queryFn: async (): Promise<CardsRead> => {
      const { data, error } = await supabase.rpc("airline_cards", { p_world_id: worldId ?? 0, p_as_of: asOf() }, { get: true });
      if (error) return fail("the airlines' cards", error.message);
      const d = data as Partial<CardsRead>;
      return {
        airlines: d.airlines ?? [], load_7_days: d.load_7_days == null ? null : Number(d.load_7_days),
        load_7_days_flights: Number(d.load_7_days_flights ?? 0), load_7_days_from: d.load_7_days_from ?? null,
      };
    },
  });
}

export interface FixRoute {
  airline_id: number;
  hub: string;
  dest: string;
  mark: "losing" | "fix";
  why: string;
  profit_week: number | null;
  profit_per_flight: number | null;
}

export interface LoadPattern { airline_id: number; route_id: number; hub: string; dest: string; mark: "cut" | "watch" | "add" | "hold"; why: string }

export interface GrowthRead {
  fix_or_reduce: FixRoute[];
  /** Any profit captured in the old Home's 8 days; without, Home lists the routes the load patterns mark cut. */
  profit_captured: boolean;
  load_patterns: LoadPattern[];
}

/** The routes to fix or reduce across our airlines, and the load patterns to fall back on (growth_signals()). */
export function useGrowth(worldId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "growth_signals", worldId],
    enabled: worldId !== undefined,
    queryFn: async (): Promise<GrowthRead> => {
      const { data, error } = await supabase.rpc("growth_signals", { p_world_id: worldId ?? 0, p_as_of: asOf() }, { get: true });
      if (error) return fail("the growth signals", error.message);
      const d = data as Partial<GrowthRead>;
      return { fix_or_reduce: d.fix_or_reduce ?? [], profit_captured: d.profit_captured ?? true, load_patterns: d.load_patterns ?? [] };
    },
  });
}

export interface RouteLoad { airline_id: number; route_id: number; hub: string; dest: string; departures: number; average: number; days: number }

/** Each route's economy loads over the last 7 days (route_loads()): the map colours one airline's routes by them. */
export function useRouteLoads(worldId: number | undefined, enabled: boolean) {
  return useQuery({
    queryKey: ["figures", "route_loads", worldId],
    enabled: worldId !== undefined && enabled,
    queryFn: async (): Promise<RouteLoad[]> => {
      const { data, error } = await supabase.rpc("route_loads", { p_world_id: worldId ?? 0, p_as_of: asOf() }, { get: true });
      if (error) return fail("the loads per route", error.message);
      return ((data as { routes?: RouteLoad[] }).routes ?? []).map((r) => ({ ...r, average: Number(r.average) }));
    },
  });
}

/** The website's destination photos by city (site_public()'s media.photos), as the old Home's airline cards use them. */
export function useSitePhotos() {
  return useQuery({
    queryKey: ["site", "photos"],
    queryFn: async (): Promise<Record<string, { url: string }>> => {
      const { data, error } = await supabase.rpc("site_public", undefined, { get: true });
      if (error) return fail("the website's photos", error.message);
      return ((data as { content?: { media?: { photos?: Record<string, { url: string }> } } } | null)?.content?.media?.photos) ?? {};
    },
  });
}

export interface PlannedLeg { plan_card_id: number; aircraft_id: number; position: number; origin_code: string; dest_code: string }
export interface AirportPlace { code: string; city: string | null; lat: number | null; lon: number | null }

/** The legs on every plan card, and the place of each airport they use, for the map's Planned routes (read when shown). */
export function usePlannedLegs(worldId: number | undefined, enabled: boolean) {
  return useQuery({
    queryKey: tableKey("plan_card_legs", "home", worldId),
    enabled: worldId !== undefined && enabled,
    queryFn: async () => {
      const [cards, legs] = await Promise.all([
        supabase.from("plan_cards").select("id, aircraft_id").eq("world_id", worldId ?? 0),
        supabase.from("plan_card_legs").select("plan_card_id, position, origin_code, dest_code").eq("world_id", worldId ?? 0).order("plan_card_id").order("position"),
      ]);
      if (cards.error) return fail("the plan cards", cards.error.message);
      if (legs.error) return fail("the plan cards' legs", legs.error.message);
      const aircraftOf = new Map(cards.data.map((c) => [c.id, c.aircraft_id]));
      const list: PlannedLeg[] = legs.data.flatMap((l) => {
        const a = aircraftOf.get(l.plan_card_id);
        return a == null || !l.origin_code || !l.dest_code ? [] : [{ plan_card_id: l.plan_card_id, aircraft_id: a, position: l.position, origin_code: l.origin_code, dest_code: l.dest_code }];
      });
      const codes = [...new Set(list.flatMap((l) => [l.origin_code, l.dest_code]))];
      const places = codes.length ? await supabase.from("airports").select("code, city, lat, lon").in("code", codes) : { data: [], error: null };
      if (places.error) return fail("the airports", places.error.message);
      return { legs: list, airports: (places.data ?? []).map((a) => ({ ...a, lat: a.lat == null ? null : Number(a.lat), lon: a.lon == null ? null : Number(a.lon) })) as AirportPlace[] };
    },
  });
}
