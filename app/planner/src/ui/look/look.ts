// The glass look's switch and the period of the day (to-do 225, spec docs/specs/2026-11-11-glass-look.md, step 1).
// While the look is built, it shows only to someone who turns it on in the account menu, and is kept in this browser
// (as the Local/UTC choice is). The look is two attributes on <html>: data-look="glass" when on (none when off) and
// data-period (day, dusk or night, by this computer's own clock). Every glass rule in styles.css hangs off
// [data-look="glass"], so with the switch off nothing changes.
import { useSyncExternalStore } from "react";
import { LOOK_STORAGE_KEY } from "../../data/config";

export type Period = "day" | "dusk" | "night";

/** The period for an hour of this computer's clock: Day 07:00–16:59, Dusk 17:00–19:59 and 05:00–06:59, Night
 *  20:00–04:59 (to-do 225's note, item 6). */
export function periodOf(hour: number): Period {
  if (hour >= 7 && hour < 17) return "day";
  if ((hour >= 17 && hour < 20) || (hour >= 5 && hour < 7)) return "dusk";
  return "night";
}

/** Whether the glass look is on in this browser: only the exact stored value "glass" is on; anything else, nothing
 *  stored, or storage that can't be read is off. */
export function readLook(storage: Pick<Storage, "getItem"> | null = safeStorage()): boolean {
  try {
    return storage?.getItem(LOOK_STORAGE_KEY) === "glass";
  } catch {
    return false;
  }
}

function safeStorage(): Storage | null {
  try {
    return typeof localStorage === "undefined" ? null : localStorage;
  } catch {
    return null;
  }
}

const listeners = new Set<() => void>();
let on = readLook();

/** Puts the look's attribute on <html> (data-look="glass", or none). */
export function applyLook(glass: boolean, root: HTMLElement | null = typeof document === "undefined" ? null : document.documentElement): void {
  if (!root) return;
  if (glass) root.dataset.look = "glass";
  else delete root.dataset.look;
}

/** Turns the glass look on or off in this browser: kept in storage (for this page only when storage is blocked), the
 *  attribute set at once, and every useLook() told. */
export function setLook(glass: boolean, storage: Pick<Storage, "setItem" | "removeItem"> | null = safeStorage()): void {
  on = glass;
  try {
    if (glass) storage?.setItem(LOOK_STORAGE_KEY, "glass");
    else storage?.removeItem(LOOK_STORAGE_KEY);
  } catch {
    // remembered for this page only
  }
  applyLook(glass);
  listeners.forEach((l) => l());
}

/** Whether the glass look is on, and a way to flip it. */
export function useLook(): [boolean, () => void] {
  const glass = useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => on,
  );
  return [glass, () => setLook(!glass)];
}

/** Puts the period's attribute on <html> (data-period="day|dusk|night"). */
export function applyPeriod(period: Period, root: HTMLElement | null = typeof document === "undefined" ? null : document.documentElement): void {
  if (root && root.dataset.period !== period) root.dataset.period = period;
}
