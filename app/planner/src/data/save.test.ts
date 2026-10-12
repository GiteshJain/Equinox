// How a save's answer is applied (design §6, §14 choices 3 and 4): saved, a clash, and a call that doesn't get through;
// and nothing sent on a preview.
import { describe, expect, it } from "vitest";
import {
  applyAnswer, applyChanges, clashMessage, createSaver, isSaveAnswer, rowId, sameKey,
  type Change, type Key, type Row, type SaveAnswer, type SaveCache, type SendResult,
} from "./save";

// A stand-in for the screens' data: one list of rows per table.
function memoryCache(tables: Record<string, Row[]>) {
  const refreshed: string[] = [];
  const cache: SaveCache = {
    update: (t, fn) => { tables[t] = fn(tables[t] ?? []); },
    find: (t, key: Key) => (tables[t] ?? []).find((r) => sameKey(r, key)),
    snapshot: (ts) => ts.map((t) => [t, tables[t]] as const),
    restore: (s) => { for (const [t, rows] of s as [string, Row[]][]) tables[t] = rows; },
    refresh: (ts) => { refreshed.push(...ts); },
  };
  return { tables, cache, refreshed };
}

const T0 = "2026-10-12T10:00:00.123456+00:00";
const T1 = "2026-10-12T10:05:00.654321+00:00";
const todos = (): Row[] => [
  { id: 1, title: "Check G-AADU", done: false, updated_at: T0 },
  { id: 2, title: "Order A321neo", done: false, updated_at: T0 },
];
const tick: Change = { table: "todos", op: "update", key: { id: 1 }, base: T0, values: { done: true, done_at: "2026-10-12T10:05:00Z" } };
const retitle: Change = { table: "todos", op: "update", key: { id: 2 }, base: T0, values: { title: "Order two A321neos" } };
const ok = (answer: SaveAnswer): Promise<SendResult> => Promise.resolve({ data: answer, error: null });

describe("the answer's shape", () => {
  it("accepts planner_save()'s two answers and nothing else", () => {
    expect(isSaveAnswer({ ok: true, rows: [{ table: "todos", op: "update", key: { id: 1 }, updated_at: T1 }] })).toBe(true);
    expect(isSaveAnswer({ ok: false, clashes: [{ table: "todos", key: { id: 1 }, current: null }] })).toBe(true);
    expect(isSaveAnswer(null)).toBe(false);
    expect(isSaveAnswer({ ok: true })).toBe(false);
    expect(isSaveAnswer({ ok: "yes", rows: [] })).toBe(false);
  });
  it("matches keys by value, whether the API gives numbers or strings", () => {
    expect(sameKey({ id: 812 }, { id: "812" })).toBe(true);
    expect(sameKey({ world_id: 1, alert_key: "maint|B-0162" }, { alert_key: "maint|B-0162", world_id: 1 })).toBe(true);
    expect(sameKey({ id: 1 }, {})).toBe(false);
  });
});

describe("applying an answer", () => {
  it("saved: the change stays and each row takes its new updated_at, the base for its next change", () => {
    const shown = applyChanges(todos(), "todos", [tick]);
    expect(shown[0]).toMatchObject({ id: 1, done: true });
    const after = applyAnswer(shown, "todos", { ok: true, rows: [{ table: "todos", op: "update", key: { id: 1 }, updated_at: T1 }] });
    expect(after[0]).toEqual({ id: 1, title: "Check G-AADU", done: true, done_at: "2026-10-12T10:05:00Z", updated_at: T1 });
    expect(after[1]).toEqual(todos()[1]);
  });

  it("saved: a deleted row goes; an inserted row never lands in a list that didn't have it (the read after the save brings it)", () => {
    const del: Change = { table: "todos", op: "delete", key: { id: 2 }, base: T0 };
    const answer: SaveAnswer = { ok: true, rows: [
      { table: "todos", op: "insert", key: { id: 9 }, updated_at: T1 },
      { table: "todos", op: "delete", key: { id: 2 }, updated_at: null },
    ] };
    expect(applyAnswer(applyChanges(todos(), "todos", [del]), "todos", answer).map((r) => r.id)).toEqual([1]);
    expect(applyAnswer(todos(), "routes", answer)).toEqual(todos());
  });

  it("clash: each clashing row is shown as the database has it now, or taken out if it's gone", () => {
    const current: Row = { id: 1, title: "Check G-AADU in the game", done: false, updated_at: T1 };
    expect(applyAnswer(todos(), "todos", { ok: false, clashes: [{ table: "todos", key: { id: 1 }, current }] })).toEqual([current, todos()[1]]);
    expect(applyAnswer(todos(), "todos", { ok: false, clashes: [{ table: "todos", key: { id: 1 }, current: null }] }).map((r) => r.id)).toEqual([2]);
  });

  it("clash: the message names the row and what changed elsewhere", () => {
    const before = new Map([[rowId("todos", { id: 1 }), todos()[0]]]);
    const current: Row = { id: 1, title: "Check G-AADU in the game", done: false, updated_at: T1 };
    expect(clashMessage([{ table: "todos", key: { id: 1 }, current }], before)).toBe(
      "Not saved: changed elsewhere since you opened it: todos 1 (title). It's shown as it is now; make your change again if you still want it.");
    expect(clashMessage([{ table: "dismissals", key: { world_id: 1, alert_key: "maint|B-0162" }, current: null }])).toContain(
      "dismissals maint|B-0162 / 1 was removed");
  });
});

describe("the saver", () => {
  it("sends one call per action, with the tab's ID, shows the change at once, and says saving then saved", async () => {
    const m = memoryCache({ todos: todos() });
    const calls: { changes: Change[]; client: string }[] = [];
    let release!: () => void;
    const saver = createSaver({ preview: false, client: "tab-test", cache: m.cache, send: (changes, client) => {
      calls.push({ changes, client });
      return new Promise((resolve) => { release = () => resolve({ data: { ok: true, rows: [{ table: "todos", op: "update", key: { id: 1 }, updated_at: T1 }] }, error: null }); });
    } });
    expect(saver.state()).toEqual({ kind: "saved", label: "saved" });
    const pending = saver.save([tick]);
    expect(saver.state().label).toBe("saving");
    expect(m.tables.todos?.[0]).toMatchObject({ done: true, updated_at: T0 });
    release();
    const result = await pending;
    expect(result.status).toBe("saved");
    expect(calls).toEqual([{ changes: [tick], client: "tab-test" }]);
    expect(m.tables.todos?.[0]).toMatchObject({ done: true, updated_at: T1 });
    expect(saver.state().label).toBe("saved");
    expect(m.refreshed).toEqual(["todos"]);
  });

  it("on a clash, takes the whole action off the screen, shows the database's rows and names what changed", async () => {
    const m = memoryCache({ todos: todos() });
    const messages: string[] = [];
    const current: Row = { id: 1, title: "Changed elsewhere", done: false, updated_at: T1 };
    const saver = createSaver({ preview: false, client: "tab-test", cache: m.cache, onMessage: (t) => messages.push(t),
      send: () => ok({ ok: false, clashes: [{ table: "todos", key: { id: 1 }, current }] }) });
    const result = await saver.save([tick, retitle]);
    expect(result.status).toBe("clash");
    expect(m.tables.todos).toEqual([current, todos()[1]]);
    expect(messages).toEqual([expect.stringContaining("todos 1 (title)")]);
    expect(saver.state().label).toBe("saved");
  });

  it("when the call doesn't get through, keeps the change on screen as not saved, keeps nothing on the device, and retries", async () => {
    const m = memoryCache({ todos: todos() });
    const messages: string[] = [];
    let online = false;
    const calls: Change[][] = [];
    const saver = createSaver({ preview: false, client: "tab-test", cache: m.cache, onMessage: (t) => messages.push(t), send: (changes) => {
      calls.push(changes);
      if (!online) return Promise.reject(new TypeError("Failed to fetch"));
      return ok({ ok: true, rows: [{ table: "todos", op: "update", key: { id: 1 }, updated_at: T1 }] });
    } });
    const result = await saver.save([tick]);
    expect(result).toEqual({ status: "failed", error: "Failed to fetch" });
    expect(saver.state()).toEqual({ kind: "failed", label: "not saved · retry" });
    expect(messages).toEqual(["Not saved: Failed to fetch"]);
    expect(m.tables.todos?.[0]).toMatchObject({ done: true, updated_at: T0 });
    expect(typeof localStorage).toBe("undefined");   // the saver has nowhere on the device to keep a copy
    online = true;
    await saver.retry();
    expect(calls).toEqual([[tick], [tick]]);
    expect(saver.state().label).toBe("saved");
    expect(m.tables.todos?.[0]).toMatchObject({ updated_at: T1 });
  });

  it("an error answer from the database is a failure too, not a save", async () => {
    const m = memoryCache({ todos: todos() });
    const saver = createSaver({ preview: false, client: "t", cache: m.cache,
      send: () => Promise.resolve({ data: null, error: { message: "only planner staff can save the planner" } }) });
    expect(await saver.save([tick])).toEqual({ status: "failed", error: "only planner staff can save the planner" });
    expect(saver.state().kind).toBe("failed");
  });

  it("on a preview, sends nothing and says so", async () => {
    const m = memoryCache({ todos: todos() });
    let sent = 0;
    const saver = createSaver({ preview: true, client: "t", cache: m.cache, send: () => { sent++; return ok({ ok: true, rows: [] }); } });
    expect(saver.state()).toEqual({ kind: "preview", label: "preview · not saved" });
    expect(await saver.save([tick])).toEqual({ status: "preview" });
    expect(sent).toBe(0);
    expect(saver.state().label).toBe("preview · not saved");
  });
});
