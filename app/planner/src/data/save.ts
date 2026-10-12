// How the new planner saves (decision #18, design §6 and §14 choices 3 and 4). The rules live here, with no tie to the
// Supabase client or the screens, so the unit tests can run them; data/saving.ts connects them to the planner.
//
// - One call to planner_save() per action, with every row the action changes. Each update or delete sends the row's
//   updated_at as it was read (base), exactly as the database gave it: keep it as the string, never a Date, which
//   would drop its microseconds and make every save clash.
// - All or nothing: if any row was changed elsewhere since it was read, the database writes nothing and answers with
//   those rows as they are now. They go back on screen, the rest of the action is undone on screen, and a message
//   names what changed. Other actions are separate calls, so they still land.
// - A call that doesn't get through (no network) leaves the change on screen as "not saved · retry". Nothing is kept
//   on the device: closing the tab loses it (§14, choice 3).
// - On a preview address (decision #8) nothing is sent, and the state says "preview · not saved".
import type { Database, Json } from "../db/types";

// The 32 planner tables planner_save() writes, the ones the change log covers (migration 20261009210000_planner_tables.sql)
export const PLANNER_TABLES = [
  "worlds", "groups", "airlines", "airline_bases", "airline_aircraft_types",
  "countries", "airports", "world_airports",
  "aircraft_types", "cabin_configs", "aircraft", "aircraft_cabin_keeps",
  "markets", "service_profiles", "routes", "rotations", "flight_legs",
  "plan_cards", "plan_card_legs",
  "todos", "todo_items", "growth_log", "spending_log", "fare_plan", "interline_agreements", "monthly_checks",
  "dismissals", "cash_entries", "load_entries", "load_days",
  "settings", "world_rules",
] as const satisfies readonly (keyof Database["public"]["Tables"])[];
export type PlannerTable = (typeof PLANNER_TABLES)[number];

export type Op = "insert" | "update" | "delete";
/** A row as the data API gives it: column name to value. */
export type Row = { [column: string]: Json | undefined };
/** A row's primary key, e.g. {id: 812}, or {world_id: 1, alert_key: "maint|B-0162"}. */
export type Key = { [column: string]: Json };
export type Values = { [column: string]: Json };
/** One row of an action. base is the row's updated_at as read; an update and a delete need it. */
export type Change = { table: PlannerTable; op: Op; key?: Key; base?: string; values?: Values };

export type SavedRow = { table: string; op: Op; key: Key; updated_at: string | null };
export type Clash = { table: string; key: Key; current: Row | null };
/** What planner_save() answers. */
export type SaveAnswer = { ok: true; rows: SavedRow[] } | { ok: false; clashes: Clash[] };

export type SaveStateKind = "saved" | "saving" | "failed" | "preview";
export const SAVE_LABELS: Record<SaveStateKind, string> = {
  saved: "saved",
  saving: "saving",
  failed: "not saved · retry",
  preview: "preview · not saved",
};

/** What a save came to, for the screen that asked (and for the checks, through window.__eqPlanner). */
export type SaveResult =
  | { status: "saved"; answer: SaveAnswer }
  | { status: "clash"; answer: SaveAnswer; message: string }
  | { status: "failed"; error: string }
  | { status: "preview" };

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

/** Whether a value is a planner_save() answer. */
export function isSaveAnswer(v: unknown): v is SaveAnswer {
  if (!isObject(v)) return false;
  if (v.ok === true) return Array.isArray(v.rows) && v.rows.every((r) => isObject(r) && typeof r.table === "string" && isObject(r.key));
  if (v.ok === false) return Array.isArray(v.clashes) && v.clashes.every((c) => isObject(c) && typeof c.table === "string" && isObject(c.key));
  return false;
}

/** Whether a row is the one a key names (values compared as text, as the data API may give numbers or strings). */
export function sameKey(row: Row, key: Key): boolean {
  const cols = Object.keys(key);
  return cols.length > 0 && cols.every((c) => row[c] !== undefined && row[c] !== null && String(row[c]) === String(key[c]));
}

/** A key for people: its values, e.g. "812", or "1 / maint|B-0162". */
export function describeKey(key: Key): string {
  return Object.keys(key).sort().map((c) => String(key[c])).join(" / ");
}

/** The action's own changes to one table's rows, shown at once: updates merged in, deletes taken out. An insert has
 * no key until the database answers; the screen's data is read again after the save, which brings it in. */
export function applyChanges(rows: Row[], table: string, changes: Change[]): Row[] {
  let out = rows;
  for (const c of changes) {
    if (c.table !== table || !c.key) continue;
    const key = c.key;
    if (c.op === "update") out = out.map((r) => (sameKey(r, key) ? { ...r, ...c.values } : r));
    else if (c.op === "delete") out = out.filter((r) => !sameKey(r, key));
  }
  return out;
}

/**
 * The database's answer, applied to one list of a table's rows as the screen holds it. Only rows already in the list
 * change: a list never gains a row it didn't have (a screen's list may be one airline's, say).
 * - Saved: each changed row takes its new updated_at, the base for its next change.
 * - Clash: nothing was written. The saver has already put the list back as it was before the action; here each
 *   clashing row is replaced by the database's current version, or taken out if it's gone.
 */
export function applyAnswer(rows: Row[], table: string, answer: SaveAnswer): Row[] {
  let out = rows;
  if (answer.ok) {
    for (const saved of answer.rows) {
      if (saved.table !== table) continue;
      if (saved.op === "update") out = out.map((r) => (sameKey(r, saved.key) ? { ...r, updated_at: saved.updated_at } : r));
      else if (saved.op === "delete") out = out.filter((r) => !sameKey(r, saved.key));
    }
    return out;
  }
  for (const clash of answer.clashes) {
    if (clash.table !== table) continue;
    const current = clash.current;
    out = current ? out.map((r) => (sameKey(r, clash.key) ? current : r)) : out.filter((r) => !sameKey(r, clash.key));
  }
  return out;
}

/** A row's place in the before map. */
export const rowId = (table: string, key: Key) => `${table}|${JSON.stringify(Object.keys(key).sort().map((c) => [c, String(key[c])]))}`;

/** The message after a clash: which rows changed elsewhere and how, and that nothing in the action was saved. */
export function clashMessage(clashes: Clash[], before: Map<string, Row | undefined> = new Map()): string {
  const parts = clashes.map((c) => {
    const name = `${c.table} ${describeKey(c.key)}`;
    if (!c.current) return `${name} was removed`;
    const was = before.get(rowId(c.table, c.key));
    const current = c.current;
    const cols = was ? Object.keys(current).filter((k) => k !== "updated_at" && JSON.stringify(current[k] ?? null) !== JSON.stringify(was[k] ?? null)) : [];
    return cols.length ? `${name} (${cols.join(", ")})` : name;
  });
  return `Not saved: changed elsewhere since you opened it: ${parts.join("; ")}. It's shown as it is now; make your change again if you still want it.`;
}

/** Where a saver keeps the screens' data: TanStack Query's cache in the planner, a plain map in the tests. */
export interface SaveCache {
  /** Applies fn to every list of this table's rows the screens hold. */
  update(table: string, fn: (rows: Row[]) => Row[]): void;
  /** The row with this key, as a screen holds it. */
  find(table: string, key: Key): Row | undefined;
  /** Every list of these tables as it is now, to put back if the action clashes. */
  snapshot(tables: string[]): unknown;
  restore(snapshot: unknown): void;
  /** Reads these tables again from the database. */
  refresh(tables: string[]): void;
}

export type SendResult = { data: unknown; error: { message: string } | null };
export type Send = (changes: Change[], client: string) => Promise<SendResult>;
export type SaveState = { kind: SaveStateKind; label: string };

export interface Saver {
  save(changes: Change[]): Promise<SaveResult>;
  /** Sends again every action that didn't get through, in order. */
  retry(): Promise<void>;
  state(): SaveState;
  subscribe(listener: () => void): () => void;
}

/**
 * A saver: one call to send() per action, the state for the header, the answer applied to the cache, and a message on
 * a clash or a failure. preview: send nothing (decision #8).
 */
export function createSaver(opts: { preview: boolean; client: string; send: Send; cache: SaveCache; onMessage?: (m: string) => void }): Saver {
  type Action = { changes: Change[]; before: Map<string, Row | undefined>; snapshot: unknown };
  const listeners = new Set<() => void>();
  const failed: Action[] = [];
  let inFlight = 0;
  let current: SaveState = { kind: opts.preview ? "preview" : "saved", label: SAVE_LABELS[opts.preview ? "preview" : "saved"] };
  const set = () => {
    const kind: SaveStateKind = opts.preview ? "preview" : inFlight > 0 ? "saving" : failed.length > 0 ? "failed" : "saved";
    if (kind !== current.kind) {
      current = { kind, label: SAVE_LABELS[kind] };
      listeners.forEach((l) => l());
    }
  };
  const tablesOf = (changes: Change[]) => [...new Set(changes.map((c) => c.table))];

  async function send(action: Action): Promise<SaveResult> {
    const { changes, before } = action;
    inFlight++;
    set();
    let result: SaveResult;
    try {
      const { data, error } = await opts.send(changes, opts.client);
      if (error) throw new Error(error.message);
      if (!isSaveAnswer(data)) throw new Error("the database's answer wasn't understood");
      if (!data.ok) opts.cache.restore(action.snapshot);   // nothing was written: the action comes off the screen
      for (const t of tablesOf(changes)) opts.cache.update(t, (rows) => applyAnswer(rows, t, data));
      if (data.ok) {
        result = { status: "saved", answer: data };
      } else {
        const message = clashMessage(data.clashes, before);
        opts.onMessage?.(message);
        result = { status: "clash", answer: data, message };
      }
      opts.cache.refresh(tablesOf(changes));
    } catch (e) {
      // no answer (no network, or the database refused): the change stays on screen, not saved, until a retry
      failed.push(action);
      const error = e instanceof Error ? e.message : String(e);
      opts.onMessage?.(`Not saved: ${error}`);
      result = { status: "failed", error };
    } finally {
      inFlight--;
    }
    set();
    return result;
  }

  return {
    async save(changes) {
      const tables = tablesOf(changes);
      const before = new Map<string, Row | undefined>();
      for (const c of changes) if (c.key) before.set(rowId(c.table, c.key), opts.cache.find(c.table, c.key));
      const snapshot = opts.cache.snapshot(tables);
      for (const t of tables) opts.cache.update(t, (rows) => applyChanges(rows, t, changes));
      if (opts.preview) return { status: "preview" };
      return send({ changes, before, snapshot });
    },
    async retry() {
      const again = failed.splice(0, failed.length);
      set();
      for (const action of again) await send(action);
    },
    state: () => current,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
}
