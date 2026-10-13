// The nine screens, in the old planner's order and with its names (design §9), and their addresses under
// /planner/next/ (design §3): /planner/next/ for Home, /planner/next/routes, /planner/next/review/VS and so on.
import { BASENAME } from "../data/config";

export type ScreenId = "home" | "routes" | "tails" | "hubs" | "check" | "review" | "interline" | "photos" | "reference";
export type Screen = { id: ScreenId; name: string; path: string };

export const SCREENS: readonly Screen[] = [
  { id: "home", name: "Home", path: "" },
  { id: "routes", name: "Routes", path: "routes" },
  { id: "tails", name: "Tails", path: "tails" },
  { id: "hubs", name: "Hubs", path: "hubs" },
  { id: "check", name: "Check", path: "check" },
  { id: "review", name: "Review", path: "review" },
  { id: "interline", name: "Interline", path: "interline" },
  { id: "photos", name: "Photos", path: "photos" },
  { id: "reference", name: "Reference", path: "reference" },
];

export function screen(id: ScreenId): Screen {
  const s = SCREENS.find((x) => x.id === id);
  if (!s) throw new Error(`no screen ${id}`);
  return s;
}

/** The screen's own address, as the browser shows it: /planner/next/ for Home, /planner/next/routes for Routes. */
export function screenHref(s: Screen): string {
  return `${BASENAME}/${s.path}`;
}

/** The address inside the planner's router (which adds /planner/next itself). */
export function screenRoute(s: Screen): string {
  return `/${s.path}`;
}

/**
 * Where something is fixed, inside the planner's router: a screen, opened at an aircraft (/tails/N001AW), at one
 * airline's route (/routes/PA/JFK-ORD, /review/PA/JFK-ORD), at an airport's board on a day (/hubs/JFK?day=2, Monday
 * being day 0 and left out), or at a part of Home (/#todo). A screen not rebuilt yet shows its link to the old planner;
 * each takes these addresses as it's rebuilt.
 */
export function itemRoute(id: ScreenId, at: { tail?: string; airline?: string | null; hub?: string; dest?: string; day?: number; hash?: string } = {}): string {
  const s = screen(id);
  if (id === "home") return at.hash ? `/#${at.hash}` : "/";
  if (id === "hubs" && at.hub) return `/${s.path}/${encodeURIComponent(at.hub)}${at.day ? `?day=${at.day}` : ""}`;
  if (at.tail) return `/${s.path}/${encodeURIComponent(at.tail)}`;
  if (at.airline && at.hub && at.dest) return `/${s.path}/${encodeURIComponent(at.airline)}/${encodeURIComponent(at.hub + "-" + at.dest)}`;
  return `/${s.path}`;
}

/** Which screen an address belongs to: its first part after /planner/next/, so /planner/next/review/VS is Review.
 * Null for an address outside the planner or a part that isn't a screen. */
export function screenForPath(pathname: string): Screen | null {
  if (pathname !== BASENAME && !pathname.startsWith(BASENAME + "/")) return null;
  const first = pathname.slice(BASENAME.length).split("/").filter(Boolean)[0] ?? "";
  return SCREENS.find((s) => s.path === first) ?? null;
}
