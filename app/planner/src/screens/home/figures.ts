// Home's figures as the old planner words them: the key figures (aircraft, routes flying, flights a day and seats a day
// from the planning library, summary.keyFigures; the group's average economy load over 7 days from airline_cards(),
// worked out in the database as the old Home did), and the operations hero above them (the old eqHeroUpdate: aircraft in
// the air, flights today, departing in the next hour, aircraft and routes, from summary.now; the load tile repeats the
// key figure). On the old Home the hero carries the figures and the key-figure row stays in the page, hidden.
import { aircraftWeek, block, maintenance, type KeyFigures, type NowFigures, type Rules, type TimedLeg } from "@rules";
import { shownMaint, type GameMaintFigure, type ShownMaint } from "../tails/model";
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

/** An airline card's "lowest maintenance" (since 23 Oct, spec docs/specs/2026-10-23-game-maintenance-on-tails.md): among
 *  the airline's aircraft in service with flights (the library's summary.airlineCards counts the same ones), each one's
 *  game figure from the latest night's fleet pages where it has one, else the planner's estimate; the lowest, or null
 *  when none has a figure. */
export function lowestMaintenance(rules: Rules, airlineId: number, game: ReadonlyMap<number, GameMaintFigure> | undefined,
  legs: readonly TimedLeg[] = block.timedLegs(rules)): ShownMaint | null {
  let low: { m: ShownMaint; v: number } | null = null;
  for (const a of rules.aircraft.values()) {
    if (a.airline_id !== airlineId || a.status !== "active") continue;
    const week = aircraftWeek.forAircraft(rules, a, legs);
    if (!week || !week.legs.length) continue;
    const est = maintenance.forAircraft(rules, a, legs, week);
    const g = game?.get(a.id);
    const m = shownMaint(rules, a.airline_id, est, g);
    if (!m) continue;
    // compared unrounded: the game's percent, the estimate's ratio as a percent
    const v = m.from === "game" && g ? g.pct : est && est.ratio != null ? est.ratio * 100 : m.pct;
    if (!low || v < low.v) low = { m, v };
  }
  return low?.m ?? null;
}
/** The card's pill words: "lowest maintenance 98%" from the game, "lowest maintenance ≈98%" from the estimate. */
export const lowestWords = (m: Pick<ShownMaint, "from" | "pct">): string => `lowest maintenance ${m.from === "game" ? "" : "≈"}${m.pct}%`;
