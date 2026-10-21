// Our airlines as the screens name them: the old planner's name (planner_name), else the public name, else the game's
// (Today, Performance and Systems; Home keeps its own list, with each airline's photo city).
export interface OurAirline { id: number; code: string | null; name: string; color: string | null; game_id: number | null }

interface AirlineRow {
  id: number;
  iata_code: string | null;
  planner_name: string | null;
  public_name: string | null;
  game_name: string | null;
  livery_color: string | null;
  game_id: number | null;
}

/** Our airlines (useOurAirlines' rows, in their order) as the screens name them. */
export const ourAirlines = (rows: readonly AirlineRow[] | undefined): OurAirline[] => (rows ?? []).map((a) => ({
  id: a.id, code: a.iata_code, name: a.planner_name ?? a.public_name ?? a.game_name ?? `Airline ${a.game_id}`, color: a.livery_color, game_id: a.game_id,
}));
