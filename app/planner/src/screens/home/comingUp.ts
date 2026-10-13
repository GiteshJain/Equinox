// Coming up: the next 14 days, one-week checks (the aircraft due that day) and to-dos, as the old planner's Home lists
// them (by day; checks before to-dos on the same day).
import type { OneWeekCheck } from "@rules";
import { dayDiff } from "../../ui/dates";
import type { TodoRow } from "./reads";

export const COMING_UP_DAYS = 14;

export interface UpEvent {
  date: string;
  type: "check" | "todo";
  text: string;
}

export const UP_LABEL: Record<UpEvent["type"], string> = { check: "Check", todo: "To-do" };

export function comingUp(checks: readonly OneWeekCheck[], todos: readonly TodoRow[], today: string): UpEvent[] {
  const byDay = new Map<string, string[]>();
  for (const c of checks) {
    if (c.status !== "upcoming") continue;
    const list = byDay.get(c.due);
    if (list) list.push(c.registration);
    else byDay.set(c.due, [c.registration]);
  }
  const events: (UpEvent & { sort: string })[] = [];
  for (const [d, regs] of byDay) events.push({ date: d, type: "check", text: regs.join(", "), sort: d + "T0000" });
  for (const t of todos) if (!t.done && t.due_on && t.due_on > today) events.push({ date: t.due_on, type: "todo", text: t.title, sort: t.due_on + "T0003" });
  events.sort((a, b) => a.sort.localeCompare(b.sort));
  return events.filter((e) => e.date >= today && dayDiff(today, e.date) <= COMING_UP_DAYS).map(({ date, type, text }) => ({ date, type, text }));
}
