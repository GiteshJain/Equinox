// Local or UTC times (design §5): the default is settings.planner_time_mode, as the old planner's toggle; once you
// switch, your choice is remembered on this device. Stored times are always UTC.
import { useSyncExternalStore } from "react";
import { TIME_MODE_STORAGE_KEY } from "./config";
import { parseTimeMode, useTimeModeSetting, useWorld, type TimeMode } from "./reads";

const listeners = new Set<() => void>();

function readStored(): TimeMode | null {
  try {
    return parseTimeMode(localStorage.getItem(TIME_MODE_STORAGE_KEY));
  } catch {
    return null;   // storage blocked: the setting's default applies
  }
}
let stored = readStored();

function setStored(mode: TimeMode): void {
  stored = mode;
  try {
    localStorage.setItem(TIME_MODE_STORAGE_KEY, mode);
  } catch {
    // remembered for this page only
  }
  listeners.forEach((l) => l());
}

export function useTimeMode(): [TimeMode, () => void] {
  const world = useWorld();
  const setting = useTimeModeSetting(world.data?.id);
  const mine = useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => stored,
  );
  const mode = mine ?? setting.data ?? "local";
  return [mode, () => setStored(mode === "utc" ? "local" : "utc")];
}

/**
 * A moment for people, e.g. "12 Oct 2026, 14:03 UTC". In local mode a moment that belongs to no airport (like the
 * latest change) is shown in this device's time zone; flight times will use each airport's own (the planning library,
 * build pull request 2).
 */
export function formatMoment(iso: string, mode: TimeMode): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat("en-GB", {
    day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", hour12: false,
    timeZone: mode === "utc" ? "UTC" : undefined, timeZoneName: "short",
  }).format(d);
}
