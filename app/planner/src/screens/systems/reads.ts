// What Systems reads (spec docs/specs/2026-10-20-today-performance-systems.md; Check's and Review's reads for these boards
// until 20 Oct), each through TanStack Query. Its other reads are the earlier screens' own (Tails' aircraft and launch
// days, Performance's growth signals for the load patterns on a check); the Cabins board's (the layouts, markets, every
// route and the "keep as is" decisions) went with it on 21 Oct:
// - the Systems board's figures (#23): system_status(), at the screen's moment;
// - the capture board: capture_status() at the screen's moment, and the nightly backup's latest runs (its line);
// - Manual entry: the nightly log and today's cash entry figures (cash_log()), and a loads day as the planner holds it
//   (loads_by_day(): the captured and typed loads, the latest winning, and the typed rows behind them, which Loads by
//   hand saves through planner_save() since the clean-up, build pull request 14).
// A table's rows are keyed ["table", <table>, ...] (data/query.ts), so a save puts its answer into them and reads them
// again. The database functions that only read are called with GET, so a preview (decision #8) reads them too.
import { useQuery } from "@tanstack/react-query";
import { tableKey } from "../../data/query";
import { supabase } from "../../data/supabase";
import type { Json } from "../../db/types";
import type { CashLog, LoadsDay } from "./model";
import type { SystemStatus } from "./systems";

const fail = (what: string, message: string): never => {
  throw new Error(`Couldn't read ${what}: ${message}`);
};
const num = (v: Json | undefined): number | null => (v == null ? null : Number(v));
/** The moment a captured figure is asked for: now, to the millisecond, as the database takes it. */
const asOf = () => new Date().toISOString();

async function rpc<T>(what: string, fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn as never, args as never, { get: true });
  if (error) return fail(what, error.message);
  return data as unknown as T;
}

// ---------- the capture board
export interface CapturePages { today: string | null; yesterday: string | null }
export interface CaptureAirline {
  airline_id: number;
  code: string | null;
  name: string | null;
  pages: Record<string, CapturePages> | null;
  flights_today: number | null;
  flights_yesterday: number | null;
  missing: string[];
  status: "complete" | "missing" | "not captured";
}
export interface CaptureBoard { today: string; yesterday: string; airlines: CaptureAirline[] }

/** What the capture collected for each airline today and yesterday (UTC), at the moment (capture_status()). Reload reads
 *  it again; the board says when it was read. */
export function useCapture(worldId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "capture_status", "check", worldId],
    enabled: worldId !== undefined,
    queryFn: async (): Promise<CaptureBoard> => {
      const { data, error } = await supabase.rpc("capture_status", { p_world_id: worldId ?? 0, p_as_of: asOf() }, { get: true });
      if (error) return fail("the capture", error.message);
      const d = data as unknown as Partial<CaptureBoard>;
      return { today: String(d.today ?? ""), yesterday: String(d.yesterday ?? ""), airlines: d.airlines ?? [] };
    },
  });
}

/** The Systems board's figures (#23): system_status(), one staff call that only reads, at the screen's moment. */
export function useSystemStatus(worldId: number | undefined) {
  return useQuery({
    queryKey: ["figures", "system_status", worldId],
    enabled: worldId !== undefined,
    queryFn: async (): Promise<SystemStatus> => {
      const { data, error } = await supabase.rpc("system_status", { p_world_id: worldId ?? 0, p_as_of: asOf() }, { get: true });
      if (error) return fail("the systems board", error.message);
      const d = data as unknown as Partial<SystemStatus>;
      return {
        as_of: String(d.as_of ?? ""), capture: d.capture ?? [], snapshot: d.snapshot ?? {}, backup: d.backup ?? { last: null, last_good: null },
        archive: d.archive ?? null, cleanup: d.cleanup ?? null, scan: d.scan ?? null, usage: d.usage ?? [],
      };
    },
  });
}

export interface BackupRun { ran_at: string; kind: string | null; ok: boolean | null; tables: number | null; rows: number | null; files: number | null; note: string | null }

/** The nightly backup's latest runs, as the old planner read them for the line under Capture (the latest 10). */
export function useBackupLine() {
  return useQuery({
    queryKey: tableKey("backup_runs", "check"),
    queryFn: async () => {
      const { data, error } = await supabase.from("backup_runs").select("ran_at, kind, ok, tables, rows, files, note").order("ran_at", { ascending: false }).limit(10);
      if (error) return fail("the backups", error.message);
      return (data as unknown as BackupRun[]).map((b) => ({ ...b, rows: num(b.rows as Json) }));
    },
  });
}

// ---------- Manual entry
/** The nightly log and today's cash entry figures (cash_log()). */
export function useCashLog(worldId: number | undefined) {
  return useQuery({
    queryKey: tableKey("cash_entries", "log", worldId),
    enabled: worldId !== undefined,
    queryFn: () => rpc<CashLog>("the nightly log", "cash_log", { p_world_id: worldId ?? 0, p_as_of: asOf() }),
  });
}

/** The loads days from one date to another as the planner holds them (loads_by_day()), by date; a day with nothing captured
 *  or typed isn't there. */
export async function readLoadsDays(worldId: number, from: string, to: string): Promise<Record<string, LoadsDay>> {
  return rpc<Record<string, LoadsDay>>("the loads", "loads_by_day", { p_world_id: worldId, p_from: from, p_to: to });
}

/** A loads day as the planner holds it, or null when it has nothing yet. Keyed under load_entries, so a save to it reads it
 *  again (Loads by hand also reads it again after a save to load_days alone). */
export function useLoadsDay(worldId: number | undefined, day: string) {
  return useQuery({
    queryKey: tableKey("load_entries", "loads_by_day", worldId, day),
    enabled: worldId !== undefined,
    queryFn: async () => (await readLoadsDays(worldId ?? 0, day, day))[day] ?? null,
  });
}
