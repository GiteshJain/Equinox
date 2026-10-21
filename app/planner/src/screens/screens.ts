// The ten screens, grouped by when they're used (spec docs/specs/2026-10-20-today-performance-systems.md): Home, Today
// ("what do I do now?"), Routes, Tails, Performance ("how are we doing, and why?"), Competition (since 21 Oct, spec
// docs/specs/2026-10-21-competition-analysis.md: "who are we up against, and where do we open next?"), Interline,
// Photos, Reference and Systems (the plumbing). Their addresses are under /planner/ (design §3, since the switch on 14 Oct): /planner/ for Home,
// /planner/today, /planner/performance/VS and so on. Check, Review and Hubs went on 20 Oct: their old addresses move to
// the new ones (movedTo here inside the planner, web/_redirects for the browser's).
import { BASENAME } from "../data/config";

export type ScreenId = "home" | "today" | "routes" | "tails" | "performance" | "competition" | "interline" | "photos" | "reference" | "systems";
export type Screen = { id: ScreenId; name: string; path: string };

export const SCREENS: readonly Screen[] = [
  { id: "home", name: "Home", path: "" },
  { id: "today", name: "Today", path: "today" },
  { id: "routes", name: "Routes", path: "routes" },
  { id: "tails", name: "Tails", path: "tails" },
  { id: "performance", name: "Performance", path: "performance" },
  { id: "competition", name: "Competition", path: "competition" },
  { id: "interline", name: "Interline", path: "interline" },
  { id: "photos", name: "Photos", path: "photos" },
  { id: "reference", name: "Reference", path: "reference" },
  { id: "systems", name: "Systems", path: "systems" },
];

export function screen(id: ScreenId): Screen {
  const s = SCREENS.find((x) => x.id === id);
  if (!s) throw new Error(`no screen ${id}`);
  return s;
}

/** The screen's own address, as the browser shows it: /planner/ for Home, /planner/routes for Routes. */
export function screenHref(s: Screen): string {
  return `${BASENAME}/${s.path}`;
}

/** The address inside the planner's router (which adds /planner itself). */
export function screenRoute(s: Screen): string {
  return `/${s.path}`;
}

/**
 * Where something is fixed, inside the planner's router: a screen, opened at an aircraft (/tails/N001AW), at one
 * airline's route (/routes/PA/JFK-ORD, /performance/PA/JFK-ORD), at one airline (/performance/PA), or at a part of a
 * screen (/today#todo, /#map).
 */
export function itemRoute(id: ScreenId, at: { tail?: string; airline?: string | null; hub?: string; dest?: string; hash?: string } = {}): string {
  const s = screen(id);
  if (at.hash) return `/${s.path}#${at.hash}`;
  if (id === "home") return "/";
  if (at.tail) return `/${s.path}/${encodeURIComponent(at.tail)}`;
  if (at.airline && at.hub && at.dest) return `/${s.path}/${encodeURIComponent(at.airline)}/${encodeURIComponent(at.hub + "-" + at.dest)}`;
  if (at.airline) return `/${s.path}/${encodeURIComponent(at.airline)}`;
  return `/${s.path}`;
}

/** Which screen an address belongs to: its first part after /planner/, so /planner/performance/VS is Performance.
 * Null for an address outside the planner or a part that isn't a screen (the old planner's /planner/old/ included, which
 * web/_redirects sends to /planner/ since the clean-up, and Check's, Review's and Hubs', which it sends on since 20 Oct). */
export function screenForPath(pathname: string): Screen | null {
  if (pathname !== BASENAME && !pathname.startsWith(BASENAME + "/")) return null;
  const first = pathname.slice(BASENAME.length).split("/").filter(Boolean)[0] ?? "";
  return SCREENS.find((s) => s.path === first) ?? null;
}

/**
 * Where an address of a screen that went on 20 Oct goes now, inside the planner's router (null for any other address):
 * Check's (/check) to Today, but its daily load report's day (?day=) to Performance's Flights by day; Review's
 * (/review, /review/VS, /review/VS/LGW-JFK) to Performance with the airline and route kept; Hubs' (/hubs, /hubs/DEL) to
 * Performance. And Today with a day (/today?day=, where web/_redirects sends /planner/check?day=) to Performance with it.
 * web/_redirects sends the browser's own addresses the same way (301), before the planner opens.
 */
export function movedTo(pathname: string, search = ""): string | null {
  const parts = pathname.split("/").filter(Boolean);
  const q = new URLSearchParams(search);
  const day = q.get("day");
  const first = parts[0] ?? "";
  if (first === "check" || (first === "today" && day)) {
    if (day) return `/performance?${new URLSearchParams({ day }).toString()}`;
    const rest = q.toString();
    return "/today" + (rest ? "?" + rest : "");
  }
  if (first === "review") return "/" + ["performance", ...parts.slice(1)].join("/") + (search && search !== "?" ? (search.startsWith("?") ? search : "?" + search) : "");
  if (first === "hubs") return "/performance";
  return null;
}
