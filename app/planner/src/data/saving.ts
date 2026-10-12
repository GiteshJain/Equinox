// The planner's saver (save.ts) connected to the database and the screens: planner_save() through the one Supabase
// client, TanStack Query's cache as the screens' data, and the messages at the foot of the screen.
import { useSyncExternalStore } from "react";
import type { QueryKey } from "@tanstack/react-query";
import type { Json } from "../db/types";
import { showMessage } from "../ui/messages";
import { PREVIEW } from "./preview";
import { queryClient, tableKey } from "./query";
import { createSaver, sameKey, type Change, type Key, type PlannerTable, type Row, type SaveCache, type SaveResult, type SaveState } from "./save";
import { supabase } from "./supabase";

/** This tab's ID, made once per page load; planner_save() writes it into the change log (decision #15). */
export const CLIENT = "tab-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8);

const rowsOf = (data: unknown): Row[] | null => (Array.isArray(data) ? (data as Row[]) : null);

const cache: SaveCache = {
  update(table, fn) {
    queryClient.setQueriesData<unknown>({ queryKey: tableKey(table) }, (old: unknown) => {
      const rows = rowsOf(old);
      return rows ? fn(rows) : old;
    });
  },
  find(table, key) {
    for (const [, data] of queryClient.getQueriesData<unknown>({ queryKey: tableKey(table) })) {
      const row = rowsOf(data)?.find((r) => sameKey(r, key));
      if (row) return row;
    }
    return undefined;
  },
  snapshot(tables) {
    return tables.flatMap((t) => queryClient.getQueriesData<unknown>({ queryKey: tableKey(t) }));
  },
  restore(snapshot) {
    for (const [key, data] of snapshot as [QueryKey, unknown][]) queryClient.setQueryData(key, data);
  },
  refresh(tables) {
    for (const t of tables) void queryClient.invalidateQueries({ queryKey: tableKey(t) });
  },
};

export const saver = createSaver({
  preview: PREVIEW,
  client: CLIENT,
  cache,
  onMessage: showMessage,
  send: async (changes, client) => {
    const { data, error } = await supabase.rpc("planner_save", { p_changes: changes as Json, p_client: client });
    return { data, error: error ? { message: error.message } : null };
  },
});

/** The save state for the header: saved, saving, not saved · retry, or preview · not saved. */
export function useSaveState(): SaveState {
  return useSyncExternalStore(saver.subscribe, saver.state);
}

/** Rows of a planner table through the planner's own client, kept in the screens' data like any read. */
async function readRows(table: PlannerTable, match: Record<string, Json>): Promise<Row[]> {
  return queryClient.fetchQuery({
    queryKey: tableKey(table, "rows", match),
    staleTime: 0,
    queryFn: async () => {
      const { data, error } = await supabase.from(table).select("*").match(match);
      if (error) throw new Error(error.message);
      return (data ?? []) as Row[];
    },
  });
}

// For the checks only (tests/planner_next_test.py): until the screens exist there's no button that saves, so the
// rehearsal's test reads and saves through this, exactly as a screen will. Nothing in the planner calls it.
export type PlannerCheckHook = {
  client: string;
  preview: boolean;
  save(changes: Change[]): Promise<SaveResult>;
  read(table: PlannerTable, match: Record<string, Json>): Promise<Row[]>;
  cached(table: PlannerTable, key: Key): Row | null;
  state(): SaveState;
  retry(): Promise<void>;
};

declare global {
  interface Window {
    __eqPlanner?: PlannerCheckHook;
  }
}

export function exposeForChecks(): void {
  window.__eqPlanner = {
    client: CLIENT,
    preview: PREVIEW,
    save: (changes) => saver.save(changes),
    read: readRows,
    cached: (table, key) => cache.find(table, key) ?? null,
    state: () => saver.state(),
    retry: () => saver.retry(),
  };
}
