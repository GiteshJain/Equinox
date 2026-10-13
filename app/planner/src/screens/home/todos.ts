// The to-do board (the old planner's todoBoard): open to-dos first, by date (no date last), then the done ones, of which
// those done in the last 7 days are folded away under the open ones and older ones only counted. And the actions on it,
// each one planner_save() call (design §6): tick (or untick), add (with its steps), delete (with its steps); and on
// Needs attention, dismiss and show again.
import type { Change } from "../../data/save";
import { addDays } from "../../ui/dates";
import type { DismissalRow, TodoItemRow, TodoRow } from "./reads";

export interface TodoView {
  row: TodoRow;
  /** The old planner's id for it (todos.legacy_key), its key on the board and in a dismissal ("todo|<id>"). */
  key: string;
  title: string;
  date: string | null;
  done: boolean;
  /** When it was ticked, as the database gives it (UTC). */
  doneAt: string | null;
  steps: TodoItemRow[];
}

export function todoViews(todos: readonly TodoRow[], items: readonly TodoItemRow[]): TodoView[] {
  const steps = new Map<number, TodoItemRow[]>();
  for (const i of [...items].sort((a, b) => a.todo_id - b.todo_id || a.position - b.position)) {
    const list = steps.get(i.todo_id);
    if (list) list.push(i);
    else steps.set(i.todo_id, [i]);
  }
  return todos.map((t) => ({ row: t, key: t.legacy_key ?? String(t.id), title: t.title, date: t.due_on, done: t.done, doneAt: t.done_at, steps: steps.get(t.id) ?? [] }));
}

/** Open first, then done; each by date, no date last; otherwise as the table keeps them (the old planner's sort). */
export function sortTodos(list: readonly TodoView[]): TodoView[] {
  return [...list].sort((a, b) => (Number(a.done) - Number(b.done)) || String(a.date ?? "9999").localeCompare(String(b.date ?? "9999")));
}

export interface TodoBoard {
  open: TodoView[];
  /** Done in the last 7 days (by when it was ticked, else its date): folded away. */
  done: TodoView[];
  /** Done before that: only counted. */
  older: number;
}

/** The board: the sorted list up to its first done to-do is the open list; the rest are the done ones. */
export function todoBoard(list: readonly TodoView[], today: string): TodoBoard {
  const sorted = sortTodos(list);
  const firstDone = sorted.findIndex((t) => t.done);
  const open = firstDone < 0 ? sorted : sorted.slice(0, firstDone);
  const doneAll = sorted.slice(open.length);
  const cutoff = addDays(today, -7);
  const done = doneAll.filter((t) => String(t.doneAt ?? t.date ?? "").slice(0, 10) >= cutoff);
  return { open, done, older: doneAll.length - done.length };
}

/** The class a to-do's line takes: done, late (overdue) or due (today). */
export function todoClass(t: TodoView, today: string): string {
  return t.done ? "done" : t.date && t.date < today ? "late" : t.date === today ? "due" : "";
}

// ---------- the actions, one planner_save() call each

/** Tick a to-do (done, and when), or untick it. */
export function tickChanges(t: TodoRow, done: boolean, now: Date): Change[] {
  return [{ table: "todos", op: "update", key: { id: t.id }, base: t.updated_at, values: { done, done_at: done ? now.toISOString() : null } }];
}

/** A new to-do, due on the date given (today when none), with its steps in order, as one action: the steps take the
 * to-do's new id. Its old-planner id is made as the old planner makes one ("t" and the time), so both planners know it. */
export function addChanges(worldId: number, title: string, date: string, steps: readonly string[], now: Date): Change[] {
  const changes: Change[] = [{
    table: "todos", op: "insert", as: "todo",
    values: { world_id: worldId, legacy_key: "t" + now.getTime().toString(36), title: title.trim(), due_on: date, done: false },
  }];
  steps.map((s) => s.trim()).filter(Boolean).forEach((body, i) => {
    changes.push({ table: "todo_items", op: "insert", from: { todo_id: "todo" }, values: { world_id: worldId, position: i + 1, body } });
  });
  return changes;
}

/** Delete a to-do and its steps, as one action. */
export function deleteChanges(t: TodoRow, steps: readonly TodoItemRow[]): Change[] {
  return [
    ...steps.map((s): Change => ({ table: "todo_items", op: "delete", key: { id: s.id }, base: s.updated_at })),
    { table: "todos", op: "delete", key: { id: t.id }, base: t.updated_at },
  ];
}

/** Dismiss a needs-attention item under its key, as of today (the old planner's dismissed[key] = today()). */
export function dismissChanges(worldId: number, alertKey: string, today: string): Change[] {
  return [{ table: "dismissals", op: "insert", key: { world_id: worldId, alert_key: alertKey }, values: { dismissed_on: today } }];
}

/** Show again: every dismissal goes, as the old planner's show again empties its list. */
export function showAgainChanges(rows: readonly DismissalRow[]): Change[] {
  return rows.map((d) => ({ table: "dismissals", op: "delete", key: { world_id: d.world_id, alert_key: d.alert_key }, base: d.updated_at }));
}
