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

/** Which screen an address belongs to: its first part after /planner/next/, so /planner/next/review/VS is Review.
 * Null for an address outside the planner or a part that isn't a screen. */
export function screenForPath(pathname: string): Screen | null {
  if (pathname !== BASENAME && !pathname.startsWith(BASENAME + "/")) return null;
  const first = pathname.slice(BASENAME.length).split("/").filter(Boolean)[0] ?? "";
  return SCREENS.find((s) => s.path === first) ?? null;
}
