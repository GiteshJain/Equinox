// One-week aircraft checks (manual §1: Gitesh's, done in the game): each aircraft in service is due a check a week after
// its latest launch or schedule change, and done once it's checked on or after that day. As the old planner's
// tailChecks(). Home shows the ones due and coming up; the Check screen will mark them (build pull request 9).
// This rule has no home of its own yet in the library or the database (decision #19); it lives here until it does.
import { addDays, dayDiff } from "../ui/dates";

/** The days after the latest launch or schedule change that a check falls due (the old planner's addDays(last, 7)). */
export const CHECK_AFTER_DAYS = 7;

export interface CheckAircraft {
  id: number;
  registration: string;
  checked_on: string | null;
  schedule_changed_on: string | null;
}

export interface OneWeekCheck {
  aircraft_id: number;
  registration: string;
  /** The latest launch or schedule change. */
  last: string;
  due: string;
  status: "due" | "upcoming" | "done";
  /** Days from today to the due day (negative once past). */
  days: number;
}

/**
 * The checks of the aircraft given, in the old planner's order: due first, then coming up, then done, each by due day
 * (the aircraft's own order for a tie). launches: each aircraft's rotations' launch days (rotations.launched_on of the
 * rotations it flies). An aircraft with no launched rotation has no check.
 */
export function oneWeekChecks(aircraft: readonly CheckAircraft[], launches: ReadonlyMap<number, readonly string[]>, today: string): OneWeekCheck[] {
  const rank = { due: 0, upcoming: 1, done: 2 } as const;
  const out: OneWeekCheck[] = [];
  for (const a of aircraft) {
    const launched = launches.get(a.id) ?? [];
    if (!launched.length) continue;
    const last = [...launched, a.schedule_changed_on ?? ""].filter(Boolean).sort().pop() ?? "";
    const due = addDays(last, CHECK_AFTER_DAYS);
    const status = a.checked_on && a.checked_on >= due ? "done" : today >= due ? "due" : "upcoming";
    out.push({ aircraft_id: a.id, registration: a.registration, last, due, status, days: dayDiff(today, due) });
  }
  return out.map((c, i) => ({ c, i }))
    .sort((x, y) => rank[x.c.status] - rank[y.c.status] || x.c.due.localeCompare(y.c.due) || x.i - y.i)
    .map((x) => x.c);
}
