// Home's figures as the old planner words them: the key figures (aircraft, routes flying, flights a day and seats a day
// from the planning library, summary.keyFigures; the group's average economy load over 7 days from airline_cards(),
// worked out in the database as the old Home did), and the operations hero above them (the old eqHeroUpdate: aircraft in
// the air, flights today, departing in the next hour, aircraft and routes, from summary.now; the load tile repeats the
// key figure). On the old Home the hero carries the figures and the key-figure row stays in the page, hidden.
import type { KeyFigures, NowFigures } from "@rules";
import type { CardsRead } from "./reads";

export interface Tile {
  value: string;
  label: string;
  title?: string;
}

/** The group's average economy load tile: from the captures, from the load reports when none was captured, or none. */
export function loadTile(cards: CardsRead | null | undefined): Tile {
  const v = cards?.load_7_days;
  if (v == null || !Number.isFinite(v)) return { value: "—", label: "average load, last 7 days (no reports yet)" };
  return {
    value: "≈" + Math.round(v) + "%",
    label: cards?.load_7_days_from === "captures" ? "average economy load, last 7 days of captures" : "average load, last 7 days",
  };
}

export function keyFigureTiles(f: KeyFigures, cards: CardsRead | null | undefined): Tile[] {
  return [
    { value: String(f.aircraft), label: "aircraft" },
    { value: String(f.routes_flying), label: "routes flying" },
    { value: String(Math.round(f.flights_day)), label: "flights a day" },
    { value: (f.seats_day / 1000).toFixed(1) + "k", label: "seats a day" },
    loadTile(cards),
  ];
}

/** The hero's greeting, by the hour at UTC−5 (the old planner's). */
export function greeting(now: Date): string {
  const hr = (now.getUTCHours() - 5 + 24) % 24;
  return (hr < 12 ? "Good morning." : hr < 18 ? "Good afternoon." : "Good evening.") + " Here's the network right now.";
}

export interface HeroFigures {
  in_air: number;
  tiles: (Tile & { id: "today" | "next" | "fleet" | "load" })[];
}

export function heroFigures(n: NowFigures, cards: CardsRead | null | undefined): HeroFigures {
  return {
    in_air: n.in_air,
    tiles: [
      { id: "today", value: String(n.flights_today), label: "flights today" },
      { id: "next", value: String(n.departing_next_hour), label: "departing in the next hour" },
      { id: "fleet", value: String(n.aircraft), label: `aircraft on ${n.routes_flying} routes` },
      { id: "load", value: loadTile(cards).value, label: "average load, last 7 days" },
    ],
  };
}
