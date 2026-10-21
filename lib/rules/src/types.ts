// The planning library's input and answers (decision #19, design §7, spec docs/specs/2026-10-12-rules-library.md).
// The input is exactly what the database function rules_input(world) answers: plain JSON, one document per world.
// Times are minutes. A leg departs at dep_utc_min (0 to 1439) on each UTC weekday in days_utc (ISO: 1 = Monday), so a
// moment in the week is (day - 1) × 1440 + minute, 0 to 10,079 from Monday 00:00 UTC, as flight_legs stores it.

export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };

/** One of rules_input()'s aircraft_types rows: a type's figures in the world. */
export interface AircraftTypeRow {
  id: number;
  name: string;
  family_no?: number | null;
  seats_max?: number | null;
  cruise_kmh: number | null;
  min_turn_min: number | null;
  gap_target_h?: number | null;
  maint_per_cycle: number | null;
  maint_per_hour: number | null;
  ground_keep_min: number | null;
}

export interface CabinConfigRow {
  id: number;
  code: string;
  aircraft_type_id: number | null;
  seats: number | null;
  /** The layout's name (cabin_configs.cabin): Standard, Leisure, Leisure Plus or Comfort; since 21 Oct, for the plan
   *  card's cabin (card.cabinFor). */
  cabin?: string | null;
}

/** An airport as the world sees it. utc_offset already has the world's correction applied (hours, standard time all
 *  year); utc_offset_override is that correction, when there is one. Night bans are local clock times "HH:MM". */
export interface AirportRow {
  code: string;
  city?: string | null;
  country_code?: string | null;
  /** The country's region (countries.region, since build pull request 12); null for an airport with no country. */
  region?: string | null;
  lat?: number | null;
  lon?: number | null;
  utc_offset: number | null;
  utc_offset_override?: number | null;
  mct_min: number | null;
  night_ban_from?: string | null;
  night_ban_to?: string | null;
  closed?: boolean | null;
}

export interface AirlineRow {
  id: number;
  iata_code?: string | null;
  game_id?: number | null;
  game_name?: string | null;
  planner_name?: string | null;
  public_name?: string | null;
  position?: number | null;
  active?: boolean | null;
  ours?: boolean | null;
  /** A low-cost airline (airlines.is_lcc, since 21 Oct): it flies Standard layouts only (manual §5, card.cabinFor). */
  is_lcc?: boolean | null;
  /** The settings as they apply to this airline: the world's, with the airline's own overrides in their place. */
  settings?: Record<string, Json>;
}

export interface BaseRow {
  id: number;
  airline_id: number;
  airport_code: string;
  role: "hub" | "focus" | string;
  is_main?: boolean | null;
  parent_base_id?: number | null;
  parent_code?: string | null;
  /** Local clock times "HH:MM", in bank order; null for an empty slot. */
  bank_times?: (string | null)[] | null;
  flight_no_from?: number | null;
  last_flight_no?: number | null;
  position?: number | null;
}

export interface AircraftRow {
  id: number;
  registration: string;
  airline_id: number;
  aircraft_type_id: number | null;
  cabin_config_id?: number | null;
  base_code?: string | null;
  status?: string | null;
}

export interface RouteRow {
  id: number;
  airline_id: number;
  hub_code: string;
  dest_code: string;
  /** With any override applied. */
  distance_km: number | null;
  market_id?: number | null;
  market?: string | null;
  /** The layout its market calls for (markets.layout: Standard, Leisure, Leisure Plus or Comfort; since 21 Oct). */
  market_layout?: string | null;
  /** The route's own cabin choice (routes.cabin_choice), which wins over its market's layout (since 21 Oct). */
  cabin_choice?: string | null;
}

/** One of rules_input()'s service_profiles rows (since build pull request 10): on-board service by distance (S1, S2, …),
 *  airline_id null for the shared profiles, an airline's own (Ryanair's R) otherwise; up to how many km. */
export interface ServiceProfileRow {
  id?: number;
  code: string;
  airline_id: number | null;
  up_to_km: number | null;
}

export interface RotationRow {
  id: number;
  airline_id: number;
  route_id: number;
  legacy_key?: string | null;
}

export interface LegRow {
  id: number;
  airline_id: number;
  rotation_id: number | null;
  leg_no?: number | null;
  flight_no: number | null;
  origin_code: string;
  dest_code: string;
  aircraft_id: number | null;
  days_utc: number[];
  dep_utc_min: number | null;
  /** From the game's times; null = arrival not typed (the library estimates it). */
  block_min: number | null;
}

/** rules_input(world)'s answer. */
export interface RulesInput {
  world?: { id: number; name?: string | null } | null;
  settings: Record<string, Json>;
  world_rules: Record<string, Json>;
  aircraft_types: AircraftTypeRow[];
  cabin_configs?: CabinConfigRow[];
  airports: AirportRow[];
  airlines: AirlineRow[];
  airline_bases: BaseRow[];
  aircraft: AircraftRow[];
  routes: RouteRow[];
  rotations: RotationRow[];
  flight_legs: LegRow[];
  /** The service profiles (service_profiles), since build pull request 10; an input without them skips the plan card's
   *  service check. */
  service_profiles?: ServiceProfileRow[];
}

/** The input, typed and indexed by buildRules(). Plain data plus lookups; nothing in it changes after it is built. */
export interface Rules {
  readonly input: RulesInput;
  readonly world: { id: number | null; name: string | null };
  readonly airports: ReadonlyMap<string, AirportRow>;
  readonly types: ReadonlyMap<number, AircraftTypeRow>;
  readonly typesByName: ReadonlyMap<string, AircraftTypeRow>;
  readonly configs: ReadonlyMap<number, CabinConfigRow>;
  readonly airlines: ReadonlyMap<number, AirlineRow>;
  readonly bases: readonly BaseRow[];
  readonly aircraft: ReadonlyMap<number, AircraftRow>;
  readonly aircraftByRegistration: ReadonlyMap<string, AircraftRow>;
  readonly routes: ReadonlyMap<number, RouteRow>;
  /** Routes by their two airports, in either order ("AAA|BBB", the codes sorted), in the input's order. */
  readonly routesByPair: ReadonlyMap<string, readonly RouteRow[]>;
  readonly rotations: ReadonlyMap<number, RotationRow>;
  /** Every leg, in the input's order (rotation, then leg 1 before leg 2). */
  readonly legs: readonly LegRow[];
}

/** A leg with everything needed to place it in the week: its block time (stored, or estimated when it isn't). */
export interface TimedLeg {
  id: number;
  airline_id: number;
  rotation_id: number | null;
  route_id: number | null;
  leg_no: number | null;
  flight_no: number | null;
  origin: string;
  dest: string;
  aircraft_id: number | null;
  days_utc: number[];
  dep_utc_min: number;
  block_min: number;
  block_source: "stored" | "estimate";
  /** Where the leg sits in the input (its order breaks ties, as the old planner's list order did). */
  order: number;
}
