// The stored figures while the planner is open (since 11 Nov; to-do 223, spec docs/specs/2026-11-11-stored-figures.md §2):
// - on opening, the stored set (storedFigures.ts' readStoredSet) and the tables the screens read with rules_input(world,
//   'flown') (opening.ts), every read through the figures' queue (limit.ts, at most four at a time), counted for the
//   landing page's "Loading… n of m";
// - planner_figures_status(world) every 30 s while the planner is open, with GET, never again while the last ask is
//   unanswered (a setTimeout after each answer, never setInterval);
// - a new generation in the status: the new set read and loaded, every live mark dropped and the figure queries read
//   again (from the new set);
// - the landing page's decision, from ui/landing/model.ts.
// Kept for the page's life, once per world (a sign-out and back in reuses it); nothing on the device (design §14, choice 3).
import { useEffect, useMemo, useSyncExternalStore } from "react";
import type { QueryFunction } from "@tanstack/react-query";
import { decide, needsLoad, nextPollMs, sawRunning, type Decision, type FiguresStatus, type LandingInput } from "../ui/landing/model";
import type { StoredSet } from "./figures";
import { limited } from "./limit";
import { openingQueries } from "./opening";
import { queryClient } from "./query";
import { useOurAirlines, useWorld, type TimeMode } from "./reads";
import { figures, readStoredSet, rereadStored } from "./storedFigures";
import { supabase } from "./supabase";
import { useTimeMode } from "./timeMode";

interface State extends Omit<LandingInput, "time"> {
  started: number | null;
  loaded: { generation: number; captureAt: string | null; asOf: string | null } | null;
  /** When the first opening began and when its landing page went (performance.now()), for the checks' timings. */
  openedMs: number | null;
}

let state: State = {
  started: null, status: null, failures: 0, statusError: null, loaded: null, opening: { done: 0, total: 1 }, reloading: null, sawRunningAt: null,
  showing: true, openedMs: null, loadError: null,
};
const listeners = new Set<() => void>();
const utc = (iso: string) => iso.slice(11, 16) + " UTC";

function set(patch: Partial<State>): void {
  const next = { ...state, ...patch };
  // the decision at UTC words: only whether it shows is kept (the screens word it in their own time mode)
  next.showing = decide({ ...next, time: utc }).show;
  state = next;
  listeners.forEach((l) => l());
}

function apply(s: StoredSet | null): void {
  figures.load(s);
  set({ loaded: s ? { generation: s.generation, captureAt: s.captureAt, asOf: s.asOf } : { generation: 0, captureAt: null, asOf: null } });
  rereadStored();
}

async function loadSet(worldId: number): Promise<void> {
  try {
    const s = await readStoredSet(worldId);
    set({ loadError: null });
    apply(s);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.warn("The stored figures couldn't be read:", message);
    set({ loadError: message });
    // none loaded yet (a database without the stored figures, or the read failed): every figure is read live, as before;
    // a set already loaded stays, and the next status tries again
    if (!state.loaded) apply(null);
  }
}

/** The opening: the stored set, the planning library's input and the screens' tables, each counted as it comes back. */
function start(worldId: number, airlineIds: readonly number[]): void {
  if (state.started !== null) return;
  const queries = openingQueries(worldId, airlineIds);
  const total = queries.length + 1;
  let done = 0;
  const one = (p: Promise<unknown>) => p.catch(() => undefined).finally(() => set({ opening: { done: ++done, total } }));
  set({ started: worldId, opening: { done, total } });
  const t0 = typeof performance === "undefined" ? 0 : performance.now();
  void Promise.all([
    one(loadSet(worldId)),
    // kept for the page's life (gcTime: a later screen change finds them however long after), read again when stale
    ...queries.map((q) => one(queryClient.prefetchQuery({ ...q, gcTime: Infinity, queryFn: (ctx) => limited(() => (q.queryFn as QueryFunction)(ctx)) }))),
  ]).then(() => {
    set({ opening: null, openedMs: typeof performance === "undefined" ? 0 : performance.now() - t0 });
    // a set stored while the opening read the last one: read now, not at the next status
    if (needsLoad(state.status, state.loaded?.generation ?? null, reloading)) void reload(worldId);
  });
}

// ---------- the status, every 30 s
let polling: number | null = null;
let timer: ReturnType<typeof setTimeout> | null = null;
let asking = false;
let reloading = false;

async function reload(worldId: number): Promise<void> {
  reloading = true;
  set({ reloading: { done: 0, total: 1 } });
  await loadSet(worldId);
  reloading = false;
  set({ reloading: null });
}

async function ask(): Promise<void> {
  const worldId = polling;
  if (worldId === null || asking) return;
  timer = null;
  asking = true;
  try {
    const { data, error } = await supabase.rpc("planner_figures_status", { p_world: worldId }, { get: true });
    if (error) throw new Error(error.message);
    const s = data as unknown as FiguresStatus;
    set({ status: s, failures: 0, statusError: null, sawRunningAt: sawRunning(state.sawRunningAt, s) });
    if (needsLoad(s, state.loaded?.generation ?? null, reloading)) void reload(worldId);
  } catch (e) {
    set({ failures: state.failures + 1, statusError: e instanceof Error ? e.message : String(e) });
  } finally {
    asking = false;
    if (polling !== null && !timer) timer = setTimeout(() => void ask(), nextPollMs(state.failures, state.showing));
  }
}

function startPolling(worldId: number): void {
  polling = worldId;
  if (!asking && !timer) void ask();
}

function stopPolling(): void {
  polling = null;
  if (timer) clearTimeout(timer);
  timer = null;
}

const subscribe = (l: () => void) => {
  listeners.add(l);
  return () => listeners.delete(l);
};
const snapshot = () => state;

/** A moment as the landing page and the as-of line say it: "11 Nov, 15:02 UTC" (or the device's zone in local mode). */
export function figuresTime(iso: string, mode: TimeMode): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat("en-GB", {
    day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hour12: false,
    timeZone: mode === "utc" ? "UTC" : undefined, timeZoneName: "short",
  }).format(d);
}

/** The shell's view: whether the landing page shows (and its line), or the screens with the line at their top. */
export function useStoredFigures(): Decision {
  const world = useWorld();
  const w = world.data?.id;
  const airlines = useOurAirlines(w);
  const [mode] = useTimeMode();
  const st = useSyncExternalStore(subscribe, snapshot, snapshot);
  const ids = useMemo(() => (airlines.data ?? []).filter((a) => a.active).map((a) => a.id), [airlines.data]);
  const airlinesIn = airlines.isSuccess || airlines.isError;
  useEffect(() => {
    if (w !== undefined && airlinesIn) start(w, ids);
  }, [w, airlinesIn, ids]);
  useEffect(() => {
    if (w === undefined) return;
    startPolling(w);
    return stopPolling;
  }, [w]);
  return useMemo(() => {
    // no world to read (the screens say why): nothing to wait for
    if (world.isError) return { show: false, note: null };
    return decide({ ...st, time: (iso) => figuresTime(iso, mode) });
  }, [st, mode, world.isError]);
}

/** The loaded set's moment, for the as-of line ("Figures as of 11 Nov, 15:02 UTC"); null with no stored set. */
export function useFiguresAsOf(): string | null {
  const st = useSyncExternalStore(subscribe, snapshot, snapshot);
  return st.loaded && st.loaded.generation > 0 ? st.loaded.asOf : null;
}

/** For the checks (tests/planner_next_test.py): the generation in memory and how long the first opening took. */
export const openingFacts = () => ({ generation: state.loaded?.generation ?? null, openedMs: state.openedMs, showing: state.showing });
