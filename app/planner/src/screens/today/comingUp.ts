// Coming up: the next 14 days of to-dos, as the old planner's Home lists them (by day). The one-week checks it also
// listed went on 22 Oct (spec docs/specs/2026-10-22-remove-aircraft-checks.md).
import { dayDiff } from "../../ui/dates";
import type { TodoRow } from "../home/reads";

export const COMING_UP_DAYS = 14;

export interface UpEvent {
  date: string;
  type: "todo";
  text: string;
}

export const UP_LABEL: Record<UpEvent["type"], string> = { todo: "To-do" };

/** Coming up's filter buttons. */
export const UP_FILTERS = [["", "All"], ["todo", "To-dos"]] as const;

export function comingUp(todos: readonly TodoRow[], today: string): UpEvent[] {
  const events: (UpEvent & { sort: string })[] = [];
  for (const t of todos) if (!t.done && t.due_on && t.due_on > today) events.push({ date: t.due_on, type: "todo", text: t.title, sort: t.due_on + "T0003" });
  events.sort((a, b) => a.sort.localeCompare(b.sort));
  return events.filter((e) => e.date >= today && dayDiff(today, e.date) <= COMING_UP_DAYS).map(({ date, type, text }) => ({ date, type, text }));
}
