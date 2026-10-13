// What Home reads (design §9, spec docs/specs/2026-10-13-home.md §2), each through TanStack Query:
// - the planning library's input, the lighter start: rules_input(world, 'flown') (design §5);
// - the planner tables it shows: aircraft (on order, and the one-week checks), rotations' launch days, plan cards, to-dos
//   and their steps, dismissals;
// - the jobs' records: job_runs and backup_runs;
// - the captured figures, at the screen's moment: capture_status(), airline_cards(), growth_signals().
// The database functions that only read are called with GET, so a preview (decision #8), which refuses every other
// call to the data API, reads them too. A table's rows are keyed ["table", <table>, ...] (data/query.ts), so a save puts
// its answer into them and reads them again.
import { useQuery } from "@tanstack/react-query";
import { buildRules, type Rules, type RulesInput } from "@rules";
import { tableKey } from "../../data/query";
import { supabase } from "../../data/supabase";

const fail = (what: string, message: string): never => {
  throw new Error(`Couldn't read ${what}: ${message}`);
};

/** The moment a captured figure is asked for: now, to the millisecond, as the database takes it. */
const asOf = (offsetMs = 0) => new Date(Date.now() - offsetMs).toISOString();

export interface RulesRead {
  rules: Rules;
}

/** The planning library's input for the world: only the flown routes and the airports they use (design §5). */
export function useRules(worldId: number | undefined) {
  return useQuery({
    queryKey: ["rules", "flown", worldId],
    enabled: worldId !== undefined,
    queryFn: async (): Promise<RulesRead> => {
      const { data, error } = await supabase.rpc("rules_input", { p_world_id: worldId ?? 0, p_routes: "flown" }, { get: true });
      if (error) return fail("the planning rules", error.message);
      return { rules: buildRules(data as unknown as RulesInput) };
    },
  });
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

export interface PlanCardRow { id: number; aircraft_id: number; updated_at: string }

/** Which aircraft have a plan card (Aircraft on order: "File into planner"). */
export function usePlanCards(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("plan_cards", "home", worldId),
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.from("plan_cards").select("id, aircraft_id, updated_at").eq("world_id", worldId ?? 0);
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

export interface CaptureAirline { airline_id: number; pages: Record<string, { today: string | null; yesterday: string | null }> | null }
export interface CaptureRead {
  /** Each of our airlines (capture_status's, in order) with its latest page since midnight UTC two days ago, or null. */
  last: { airline_id: number; at: string | null }[];
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
      return {
        last: ((now.data as { airlines?: CaptureAirline[] }).airlines ?? []).map((a) => {
          const at = [latest(a), latest(earlier.get(a.airline_id))].filter((x): x is string => !!x)
            .reduce<string | null>((m, x) => (m == null || Date.parse(x) > Date.parse(m) ? x : m), null);
          return { airline_id: a.airline_id, at };
        }),
      };
    },
  });
}

export interface AirlineCard { airline_id: number; load_7_days: number | null; can_order_now: string[] | null }

/** Review's cards for our airlines at the moment: the average load and what each can order now (cash_forecast()). */
export function useAirlineCards(worldId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "airline_cards", worldId],
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("airline_cards", { p_world_id: worldId ?? 0, p_as_of: asOf() }, { get: true });
      if (error) return fail("the airlines' cards", error.message);
      return ((data as { airlines?: AirlineCard[] }).airlines ?? []);
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

/** The routes to fix or reduce across our airlines (growth_signals()). */
export function useRoutesToFix(worldId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "growth_signals", worldId],
    enabled: worldId !== undefined,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("growth_signals", { p_world_id: worldId ?? 0, p_as_of: asOf() }, { get: true });
      if (error) return fail("the growth signals", error.message);
      return ((data as { fix_or_reduce?: FixRoute[] }).fix_or_reduce ?? []);
    },
  });
}
