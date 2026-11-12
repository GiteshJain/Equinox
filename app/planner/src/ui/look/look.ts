// The glass look's period of the day (to-do 225, spec docs/specs/2026-11-11-glass-look.md). Since step 6 (glass for
// everyone, 12 Nov) the glass look is the planner's only look: <html data-look="glass"> is in index.html, and every glass
// rule in styles.css hangs off it. The period is data-period on <html> (day, dusk or night, by this computer's own
// clock), set by Backdrop.tsx each minute. The switch that turned the look on, and its stored setting
// (equinox-planner-look), went with step 6; a value a browser kept is never read.
export type Period = "day" | "dusk" | "night";

/** The period for an hour of this computer's clock: Day 07:00–16:59, Dusk 17:00–19:59 and 05:00–06:59, Night
 *  20:00–04:59 (to-do 225's note, item 6). */
export function periodOf(hour: number): Period {
  if (hour >= 7 && hour < 17) return "day";
  if ((hour >= 17 && hour < 20) || (hour >= 5 && hour < 7)) return "dusk";
  return "night";
}

/** Puts the period's attribute on <html> (data-period="day|dusk|night"). */
export function applyPeriod(period: Period, root: HTMLElement | null = typeof document === "undefined" ? null : document.documentElement): void {
  if (root && root.dataset.period !== period) root.dataset.period = period;
}
