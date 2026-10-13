// Dates as the old planner writes them (web/planner/index.html: iso, today, addDays, dayDiff, niceDate, untilText and
// the to-do board's and Coming up's words), shared by every screen. A day is the device's own calendar day, as the old
// planner counts it; times from the database are UTC.

const pad = (n: number) => String(n).padStart(2, "0");

/** A day as YYYY-MM-DD, on this device's calendar (the old planner's iso()). */
export function isoDay(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** Today on this device's calendar, at the moment given. */
export const todayAt = (now: Date): string => isoDay(now);

/** A day n days after (or before) a YYYY-MM-DD day. */
export function addDays(day: string, n: number): string {
  const [y, m, d] = day.split("-").map(Number);
  return isoDay(new Date(y ?? 1970, (m ?? 1) - 1, (d ?? 1) + n));
}

/** Whole days from a to b (YYYY-MM-DD). */
export function dayDiff(a: string, b: string): number {
  const p = (s: string) => {
    const [y, m, d] = s.split("-").map(Number);
    return Date.UTC(y ?? 1970, (m ?? 1) - 1, d ?? 1);
  };
  return Math.round((p(b) - p(a)) / 86_400_000);
}

/** A day as the old planner shows it: "Fri, Oct 9" in American English, in the device's own language elsewhere. The
 * locale is an argument only so the tests can fix it. */
export function niceDate(day: string | null | undefined, locale?: string): string {
  if (!day) return "";
  const [y, m, d] = day.split("-").map(Number);
  return new Date(y ?? 1970, (m ?? 1) - 1, d ?? 1).toLocaleDateString(locale, { weekday: "short", day: "numeric", month: "short" });
}

/** When a to-do is due, in words: "today", "overdue · Fri, Oct 9", "Wed, Oct 14" or "no date". */
export function dueWords(day: string | null | undefined, today: string, locale?: string): string {
  if (!day) return "no date";
  if (day === today) return "today";
  return day < today ? "overdue · " + niceDate(day, locale) : niceDate(day, locale);
}

/** How far ahead a day is: "today", "in 1 day", "in 3 days" (Coming up). */
export function inDays(day: string, today: string): string {
  if (day === today) return "today";
  const n = dayDiff(today, day);
  return `in ${n} day${n === 1 ? "" : "s"}`;
}

/** How long until a moment: "arrived" once past, "in 40 min", "in 5 h 20 min", "in 3 days 4 h" (the old untilText). */
export function untilText(at: number, now: number): string {
  const mins = Math.round((at - now) / 60_000);
  if (mins < 0) return "arrived";
  if (mins < 60) return `in ${mins} min`;
  const hh = Math.floor(mins / 60);
  if (hh < 24) return `in ${hh} h` + (mins % 60 ? ` ${mins % 60} min` : "");
  const dd = Math.floor(hh / 24);
  return `in ${dd} day${dd === 1 ? "" : "s"}` + (hh % 24 ? ` ${hh % 24} h` : "");
}

/** A moment from the database ("2026-10-12T16:42:13.5+00:00") as its UTC day and clock, as the old planner slices it. */
export const utcDay = (iso: string): string => String(iso).slice(0, 10);
export const utcClock = (iso: string): string => String(iso).slice(11, 16);

/** A moment to the minute, as the old planner's documents stored delivery times ("2026-10-09T05:53Z"). */
export function toMinute(iso: string): number {
  const t = Date.parse(iso);
  return Number.isFinite(t) ? Math.floor(t / 60_000) * 60_000 : NaN;
}
