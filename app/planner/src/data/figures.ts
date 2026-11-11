// The one way the planner reads a captured figure (since 11 Nov; to-do 223, spec docs/specs/2026-11-11-stored-figures.md
// §2). After every capture the database works every figure the planner shows out once and stores the answers
// (planner_figures, part 1); the planner loads that set when it opens and whenever a new one is ready (storedFigures.ts),
// and every screen's figure read comes here:
// - a figure the loaded set holds (by its kind and key, as the migration writes them) is answered from memory;
// - a figure it doesn't hold (an airline added since, other arguments, no set at all), or one marked live after a save,
//   is asked of the database as before, with GET, through the figures' queue (limit.ts);
// - a route's page (route_story) is read from its own stored row when that row is as new as the set's routes_from,
//   otherwise live.
// A save that changes figures marks them live (markLive) until the next set loads, so the board it changes reads the
// database at once, as before, and that answer stands. Nothing is kept on the device (design §14, choice 3).
import { FIGURES_STALE_MS } from "./query";

/** Every kind the database stores in the set the planner loads (spec §1, "What is stored"); route_story is stored row by
 *  row and read one route at a time. */
export const WORLD_KINDS = ["airline_cards", "growth_signals", "hub_progress", "route_loads", "fleet_checks", "cash_log", "shared_pairs_status"] as const;
/** Stored once, in the default world: these take no world. */
export const NO_WORLD_KINDS = ["cabin_charges", "market_service_checks"] as const;
export const AIRLINE_KINDS = ["airline_profit", "cash_forecast", "fare_changes", "fare_plan_status", "fare_ladder", "fare_results", "competition"] as const;
/** Stored for 1, 3 and 7 days. */
export const DAYS_KINDS = ["route_profit", "aircraft_profit"] as const;
export const STORED_KINDS: readonly string[] = [...WORLD_KINDS, ...NO_WORLD_KINDS, ...AIRLINE_KINDS, ...DAYS_KINDS, "route_story"];

export type Args = Record<string, unknown>;

const has = (list: readonly string[], fn: string) => list.includes(fn);
const whole = (v: unknown): number | null => (typeof v === "number" || (typeof v === "string" && v.trim() !== "") ? (Number.isInteger(Number(v)) ? Number(v) : null) : null);

/**
 * The stored row's key for a call, as the migration writes it: '' for a world-wide figure, the airline id, '<airline
 * id>:<days>' for route and aircraft profit, the route id for a route's page. Null when the set doesn't store that call
 * (an argument the planner's stored call doesn't pass, like competition's limit or cash_forecast's orders). p_as_of is
 * never part of it: the set has its own moment.
 */
export function storedKey(fn: string, args: Args): string | null {
  const given = Object.keys(args).filter((k) => k !== "p_as_of" && args[k] !== undefined);
  const only = (...names: string[]) => given.every((k) => names.includes(k));
  if (has(WORLD_KINDS, fn)) return only("p_world_id") ? "" : null;
  if (has(NO_WORLD_KINDS, fn)) return only() ? "" : null;
  if (has(DAYS_KINDS, fn)) {
    const a = whole(args.p_airline_id), d = whole(args.p_days);
    return only("p_airline_id", "p_days") && a !== null && d !== null ? `${a}:${d}` : null;
  }
  if (has(AIRLINE_KINDS, fn)) {
    const a = whole(args.p_airline_id);
    return only("p_airline_id") && a !== null ? String(a) : null;
  }
  if (fn === "route_story") {
    const r = whole(args.p_route_id);
    return only("p_route_id") && r !== null ? String(r) : null;
  }
  return null;
}

/** One stored answer, as planner_figures holds it. */
export interface StoredRow { kind: string; key: string; answer: unknown; as_of: string; generation: number }
/** A whole stored set, as storedFigures.ts reads it: the generation, its moment, what it was worked out from, and every
 *  row but the route pages. */
export interface StoredSet {
  worldId: number;
  generation: number;
  /** The set's moment (sources.as_of). */
  asOf: string | null;
  /** The latest capture page it was worked out from (sources.capture_at). */
  captureAt: string | null;
  /** Route pages worked out at or after this moment are up to date (sources.routes_from). */
  routesFrom: string | null;
  rows: StoredRow[];
}
export type LoadedSet = Omit<StoredSet, "rows">;

export interface FigureDeps {
  /** Calls the function live (GET, through the queue); throws with the database's message. */
  call(fn: string, args: Args): Promise<unknown>;
  /** A route's stored page and its moment, or null when none is stored. */
  routeStory(worldId: number, routeId: number): Promise<{ answer: unknown; as_of: string } | null>;
}

export interface Figures {
  /** Reads a figure: the loaded set's answer when it holds it and it isn't marked live, else the database's. */
  read<T>(fn: string, args: Args): Promise<T>;
  /** Whether a read with these arguments would be answered from the loaded set (route pages: whether a set is loaded). */
  isStored(fn: string, args: Args): boolean;
  /** After a save: these kinds (or all) are read live until the next set loads. */
  markLive(kinds: readonly string[] | "all"): void;
  /** Takes a new set (or none: everything live) and drops every live mark. */
  load(set: StoredSet | null): void;
  /** The set in memory: its generation and moments, without the rows; null when none is loaded. */
  loaded(): LoadedSet | null;
  subscribe(listener: () => void): () => void;
}

const rowId = (kind: string, key: string) => kind + "|" + key;

export function createFigures(deps: FigureDeps): Figures {
  let set: LoadedSet | null = null;
  let rows = new Map<string, StoredRow>();
  let allLive = false;
  const live = new Set<string>();
  const listeners = new Set<() => void>();
  const isLive = (fn: string) => allLive || live.has(fn);

  function hit(fn: string, args: Args): StoredRow | undefined {
    if (!set || isLive(fn) || fn === "route_story") return undefined;
    const key = storedKey(fn, args);
    if (key === null) return undefined;
    // a world's figure answers only for the world the set is of
    if (has(WORLD_KINDS, fn) && whole(args.p_world_id) !== set.worldId) return undefined;
    return rows.get(rowId(fn, key));
  }

  return {
    async read<T>(fn: string, args: Args): Promise<T> {
      if (fn === "route_story" && set && !isLive(fn)) {
        const id = whole(args.p_route_id);
        if (id !== null && storedKey(fn, args) !== null) {
          const from = set.routesFrom ? Date.parse(set.routesFrom) : NaN;
          // a stored page that can't be read is read live instead
          const row = await deps.routeStory(set.worldId, id).catch(() => null);
          if (row && Number.isFinite(from) && Date.parse(row.as_of) >= from) return row.answer as T;
        }
        return (await deps.call(fn, args)) as T;
      }
      const row = hit(fn, args);
      if (row) return row.answer as T;
      return (await deps.call(fn, args)) as T;
    },
    isStored(fn, args) {
      if (fn === "route_story") return !!set && !isLive(fn) && storedKey(fn, args) !== null;
      return hit(fn, args) !== undefined;
    },
    markLive(kinds) {
      if (kinds === "all") allLive = true;
      else for (const k of kinds) live.add(k);
      listeners.forEach((l) => l());
    },
    load(next) {
      if (next) {
        const { rows: list, ...meta } = next;
        set = meta;
        rows = new Map(list.map((r) => [rowId(r.kind, r.key), r]));
      } else {
        set = null;
        rows = new Map();
      }
      allLive = false;
      live.clear();
      listeners.forEach((l) => l());
    },
    loaded: () => set,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
}

/** The figures that are read under a table's key (["table", <table>, …]) rather than ["figures", …]: a save to that table
 *  reads them again (saving.ts), so it marks them live too. */
export const FIGURES_UNDER_TABLES: Readonly<Record<string, readonly string[]>> = {
  fare_plan: ["fare_plan_status", "fare_ladder", "fare_results", "route_story"],
  cash_entries: ["cash_log"],
};

/** The kinds a save to these tables reads again. */
export const kindsForTables = (tables: readonly string[]): string[] => [...new Set(tables.flatMap((t) => FIGURES_UNDER_TABLES[t] ?? []))];

/** What a figure's query adds to its options: its kind (so a new set finds it) and its staleness: none while the loaded set
 *  answers it (the set changes only with a new generation, which reads it again), FIGURES_STALE_MS when it is read live. */
export function figureOptions(figures: Figures, fn: string, args: Args) {
  return {
    meta: { figure: fn },
    staleTime: () => (figures.isStored(fn, args) ? Infinity : FIGURES_STALE_MS),
  };
}
