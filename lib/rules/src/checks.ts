// checks: the one-week aircraft checks (manual §1: Gitesh's, done in the game; Claude never marks one checked). Each
// aircraft in service falls due aircraft_check_after_days (a setting, an airline's own where it has one) after its
// latest launch or schedule change, and is done once it was checked on or after that day. An aircraft with no launched
// rotation has no check. A rotation belongs to the aircraft its outbound leg flies (else its return's).
// The dates the rule needs (aircraft.checked_on and schedule_changed_on, rotations.launched_on) aren't in
// rules_input(); the caller passes them from the tables. Days are "YYYY-MM-DD"; today is an argument (the library never
// reads a clock).
// The old code it follows: the old planner's tailChecks() (#18 build pull request 5, the Building chat's review: the
// rule moves here from the new planner's screen code, so it has one home, #19).
import { settingNumber } from "./input.js";
import type { Rules } from "./types.js";

/** What the rule needs from the tables. */
export interface CheckFacts {
  /** Each aircraft's last check and last schedule change ("YYYY-MM-DD" or null). */
  aircraft: readonly { id: number; checked_on: string | null; schedule_changed_on: string | null }[];
  /** Each rotation's launch day ("YYYY-MM-DD" or null: not launched). */
  rotations: readonly { id: number; launched_on: string | null }[];
}

export interface OneWeekCheck {
  aircraft_id: number;
  registration: string;
  airline_id: number;
  /** The latest launch or schedule change. */
  last: string;
  due: string;
  status: "due" | "upcoming" | "done";
  /** Days from today to the due day (negative once past). */
  days: number;
}

const DAY_MS = 86_400_000;
const dayMs = (d: string): number => {
  const t = Date.parse(d.slice(0, 10) + "T00:00:00Z");
  if (!Number.isFinite(t)) throw new Error(`not a day: ${d}`);
  return t;
};
/** The day n days after d ("YYYY-MM-DD"). */
export const addDays = (d: string, n: number): string => new Date(dayMs(d) + n * DAY_MS).toISOString().slice(0, 10);
/** Whole days from a to b. */
export const dayDiff = (a: string, b: string): number => Math.round((dayMs(b) - dayMs(a)) / DAY_MS);

/**
 * Every aircraft in service's one-week check, in the old planner's order: due first, then coming up, then done, each
 * by its due day (the input's aircraft order for a tie).
 */
export function oneWeek(rules: Rules, facts: CheckFacts, today: string): OneWeekCheck[] {
  const flownBy = new Map<number, number>();
  for (const l of rules.legs) {
    if (l.rotation_id == null || l.aircraft_id == null) continue;
    if (l.leg_no === 1 || !flownBy.has(l.rotation_id)) flownBy.set(l.rotation_id, l.aircraft_id);
  }
  const launches = new Map<number, string[]>();
  for (const r of facts.rotations) {
    const a = flownBy.get(r.id);
    if (a == null || !r.launched_on) continue;
    launches.set(a, [...(launches.get(a) ?? []), r.launched_on.slice(0, 10)]);
  }
  const dates = new Map(facts.aircraft.map((a) => [a.id, a]));
  const rank = { due: 0, upcoming: 1, done: 2 } as const;
  const out: OneWeekCheck[] = [];
  for (const a of rules.aircraft.values()) {
    if (a.status !== "active") continue;
    const launched = launches.get(a.id) ?? [];
    if (!launched.length) continue;
    const d = dates.get(a.id);
    const last = [...launched, d?.schedule_changed_on?.slice(0, 10) ?? ""].filter(Boolean).sort().pop() ?? "";
    const due = addDays(last, settingNumber(rules, "aircraft_check_after_days", a.airline_id));
    const checked = d?.checked_on?.slice(0, 10) ?? null;
    const status = checked && checked >= due ? "done" : today >= due ? "due" : "upcoming";
    out.push({ aircraft_id: a.id, registration: a.registration, airline_id: a.airline_id, last, due, status, days: dayDiff(today, due) });
  }
  return out.map((c, i) => ({ c, i }))
    .sort((x, y) => rank[x.c.status] - rank[y.c.status] || (x.c.due < y.c.due ? -1 : x.c.due > y.c.due ? 1 : 0) || x.i - y.i)
    .map((x) => x.c);
}
