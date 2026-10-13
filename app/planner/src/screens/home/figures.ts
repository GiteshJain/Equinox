// Home's key figures, as the old planner shows them: aircraft, routes flying, flights a day and seats a day from the
// planning library (summary.keyFigures), and the average economy load over the last 7 days from airline_cards() (each
// airline's Review figure; the tile shows their average, as the old Home showed one figure for the group).
import type { KeyFigures } from "@rules";
import type { AirlineCard } from "./reads";

export interface Tile {
  value: string;
  label: string;
  title?: string;
}

/** The average of the airlines' 7-day economy loads (those that have one), rounded as the old planner rounds it. */
export function averageLoad(cards: readonly AirlineCard[] | null | undefined): number | null {
  const loads = (cards ?? []).map((c) => c.load_7_days).filter((x): x is number => x != null && Number.isFinite(Number(x))).map(Number);
  return loads.length ? Math.round(loads.reduce((s, x) => s + x, 0) / loads.length) : null;
}

export function keyFigureTiles(f: KeyFigures, cards: readonly AirlineCard[] | null | undefined, names: (id: number) => string): Tile[] {
  const load = averageLoad(cards);
  const each = (cards ?? []).filter((c) => c.load_7_days != null).map((c) => `${names(c.airline_id)} ≈${Math.round(Number(c.load_7_days))}%`).join(" · ");
  return [
    { value: String(f.aircraft), label: "aircraft" },
    { value: String(f.routes_flying), label: "routes flying" },
    { value: String(Math.round(f.flights_day)), label: "flights a day" },
    { value: (f.seats_day / 1000).toFixed(1) + "k", label: "seats a day" },
    load != null
      ? { value: "≈" + load + "%", label: "average economy load, last 7 days of captures", title: each }
      : { value: "—", label: "average load, last 7 days (no reports yet)" },
  ];
}
