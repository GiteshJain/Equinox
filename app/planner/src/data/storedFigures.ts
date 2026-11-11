// The planner's figure reads connected to the database (since 11 Nov; to-do 223, spec
// docs/specs/2026-11-11-stored-figures.md §2): the one figures store (figures.ts) with its live calls (GET, through the
// figures' queue, limit.ts), every screen's figure read (readFigure), what a figure's query adds to its options
// (storedOptions), the marks a save makes (refreshStored), and the stored set's read (readStoredSet: the state row, then
// every row but the route pages, a thousand at a time).
import type { Query } from "@tanstack/react-query";
import { createFigures, figureOptions, STORED_KINDS, type Args, type StoredRow, type StoredSet } from "./figures";
import { limited } from "./limit";
import { queryClient } from "./query";
import { supabase } from "./supabase";

export const figures = createFigures({
  async call(fn, args) {
    const { data, error } = await limited(() => supabase.rpc(fn as never, args as never, { get: true }));
    if (error) throw new Error(error.message);
    return data;
  },
  async routeStory(worldId, routeId) {
    const { data, error } = await limited(() => supabase.from("planner_figures").select("answer, as_of")
      .eq("world_id", worldId).eq("kind", "route_story").eq("key", String(routeId)).maybeSingle());
    if (error) throw new Error(error.message);
    return data ?? null;
  },
});

/** Reads a figure (the loaded set's answer, or the database's), with the screen's words for what failed. */
export async function readFigure<T>(what: string, fn: string, args: Args): Promise<T> {
  try {
    return await figures.read<T>(fn, args);
  } catch (e) {
    throw new Error(`Couldn't read ${what}: ${e instanceof Error ? e.message : String(e)}`, { cause: e });
  }
}

/** A figure query's kind and staleness (figures.ts' figureOptions on the planner's store). */
export const storedOptions = (fn: string, args: Args) => figureOptions(figures, fn, args);

const figureOf = (q: Query) => (q.meta as { figure?: unknown } | undefined)?.figure;

/** After a save: these figures (or all) are read live until the next set loads, and read again now. */
export function refreshStored(kinds: readonly string[] | "all"): void {
  if (kinds !== "all" && !kinds.length) return;
  figures.markLive(kinds);
  void queryClient.invalidateQueries({ predicate: (q) => { const f = figureOf(q); return typeof f === "string" && (kinds === "all" || kinds.includes(f)); } });
}

/** After a new set loads: every figure query reads again (from the new set, or live where it doesn't hold one). */
export function rereadStored(): void {
  void queryClient.invalidateQueries({ predicate: (q) => { const f = figureOf(q); return typeof f === "string" && STORED_KINDS.includes(f); } });
}

const PAGE = 1000;

/** The stored set of a world (planner_figures_state, then planner_figures without the route pages), or null when there is
 *  none yet (generation 0: everything is read live). A set stored while it was being read is read again. */
export async function readStoredSet(worldId: number): Promise<StoredSet | null> {
  for (let attempt = 0; attempt < 3; attempt++) {
    const st = await limited(() => supabase.from("planner_figures_state").select("generation, sources").eq("world_id", worldId).maybeSingle());
    if (st.error) throw new Error(st.error.message);
    const generation = Number(st.data?.generation ?? 0);
    if (!st.data || !generation) return null;
    const rows: StoredRow[] = [];
    for (let from = 0; ; from += PAGE) {
      const { data, error } = await limited(() => supabase.from("planner_figures").select("kind, key, answer, as_of, generation")
        .eq("world_id", worldId).neq("kind", "route_story").order("kind").order("key").range(from, from + PAGE - 1));
      if (error) throw new Error(error.message);
      rows.push(...(data ?? []).map((r) => ({ ...r, generation: Number(r.generation) })));
      if (!data || data.length < PAGE) break;
    }
    if (rows.every((r) => r.generation <= generation)) {
      const src = (st.data.sources ?? {}) as { as_of?: string | null; capture_at?: string | null; routes_from?: string | null };
      return { worldId, generation, asOf: src.as_of ?? null, captureAt: src.capture_at ?? null, routesFrom: src.routes_from ?? null, rows };
    }
  }
  throw new Error("the stored figures kept changing while they were read");
}
