// Builds the typed Rules object from rules_input()'s answer, and reads the rule numbers from it. Every number the
// library uses comes from here: settings (with an airline's override where it has one), world_rules, aircraft_types
// and the airports. A number that is missing is an error, never a default typed into the code.
import type { AircraftTypeRow, Json, RouteRow, Rules, RulesInput } from "./types.js";

/** A rule number or a row the calculation needs is missing or isn't usable. */
export class RulesError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RulesError";
  }
}

/** A type's name as the old planner compares them: capitals and digits only ("A321 NEO LIGHT" = "a321neolight"). */
export const typeKey = (name: string | null | undefined): string => String(name ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");

/** Two airports as one key, whichever way round: "AAA|BBB" with the codes sorted. */
export const pairKey = (a: string, b: string): string => (a < b ? `${a}|${b}` : `${b}|${a}`);

function list<T>(x: T[] | null | undefined, what: string): T[] {
  if (x == null) return [];
  if (!Array.isArray(x)) throw new RulesError(`rules input: ${what} must be a list`);
  return x;
}

/** The typed builder: checks the shape of rules_input()'s answer and indexes it. Pure: the input isn't changed. */
export function buildRules(input: RulesInput): Rules {
  if (input == null || typeof input !== "object") throw new RulesError("rules input: expected rules_input()'s JSON document");
  if (input.settings == null || typeof input.settings !== "object") throw new RulesError("rules input: settings missing");
  const airports = new Map(list(input.airports, "airports").map((a) => [a.code, a] as const));
  const typeRows = list(input.aircraft_types, "aircraft_types");
  const types = new Map(typeRows.map((t) => [t.id, t] as const));
  const typesByName = new Map<string, AircraftTypeRow>();
  for (const t of typeRows) if (!typesByName.has(typeKey(t.name))) typesByName.set(typeKey(t.name), t);
  const aircraftRows = list(input.aircraft, "aircraft");
  const legs = list(input.flight_legs, "flight_legs");
  for (const l of legs) {
    if (!Array.isArray(l.days_utc)) throw new RulesError(`rules input: flight leg ${l.id} has no days_utc list`);
    for (const d of l.days_utc) {
      if (!Number.isInteger(d) || d < 1 || d > 7) throw new RulesError(`rules input: flight leg ${l.id} has a weekday ${String(d)} outside 1 to 7`);
    }
    if (l.dep_utc_min != null && (!Number.isInteger(l.dep_utc_min) || l.dep_utc_min < 0 || l.dep_utc_min > 1439)) {
      throw new RulesError(`rules input: flight leg ${l.id} departs at minute ${l.dep_utc_min}, outside 0 to 1439`);
    }
  }
  const routeRows = list(input.routes, "routes");
  const routesByPair = new Map<string, RouteRow[]>();
  for (const r of routeRows) {
    const k = pairKey(r.hub_code, r.dest_code);
    const have = routesByPair.get(k);
    if (have) have.push(r);
    else routesByPair.set(k, [r]);
  }
  const bases = list(input.airline_bases, "airline_bases")
    .map((b, i) => ({ b, i }))
    .sort((x, y) => (x.b.position ?? Number.MAX_SAFE_INTEGER) - (y.b.position ?? Number.MAX_SAFE_INTEGER) || x.b.id - y.b.id || x.i - y.i)
    .map((x) => x.b);
  return {
    input,
    world: { id: input.world?.id ?? null, name: input.world?.name ?? null },
    airports,
    types,
    typesByName,
    configs: new Map(list(input.cabin_configs, "cabin_configs").map((c) => [c.id, c] as const)),
    airlines: new Map(list(input.airlines, "airlines").map((a) => [a.id, a] as const)),
    bases,
    aircraft: new Map(aircraftRows.map((a) => [a.id, a] as const)),
    aircraftByRegistration: new Map(aircraftRows.map((a) => [a.registration, a] as const)),
    routes: new Map(routeRows.map((r) => [r.id, r] as const)),
    routesByPair,
    rotations: new Map(list(input.rotations, "rotations").map((r) => [r.id, r] as const)),
    legs,
  };
}

/** A setting's value for an airline (its override, else the world's), or for the world when no airline is given. */
export function setting(rules: Rules, key: string, airlineId?: number | null): Json | undefined {
  if (airlineId != null) {
    const own = rules.airlines.get(airlineId)?.settings;
    if (own && Object.prototype.hasOwnProperty.call(own, key)) return own[key];
  }
  return Object.prototype.hasOwnProperty.call(rules.input.settings, key) ? rules.input.settings[key] : undefined;
}

/** A setting that must be a number; a missing or non-numeric one is an error naming it. */
export function settingNumber(rules: Rules, key: string, airlineId?: number | null): number {
  const v = setting(rules, key, airlineId);
  const n = typeof v === "string" && v.trim() !== "" ? Number(v) : v;
  if (typeof n !== "number" || !Number.isFinite(n)) {
    throw new RulesError(`settings.${key} is ${v === undefined ? "missing" : "not a number"}; it comes from the settings table`);
  }
  return n;
}

/** A world rule's value. A rule kept as {value, ...} (departures_per_airport_week) gives its value. */
export function worldRule(rules: Rules, key: string): Json | undefined {
  const r = rules.input.world_rules ?? {};
  if (!Object.prototype.hasOwnProperty.call(r, key)) return undefined;
  const v = r[key];
  if (v != null && typeof v === "object" && !Array.isArray(v) && "value" in v) return v.value ?? null;
  return v;
}

export function worldRuleNumber(rules: Rules, key: string): number {
  const v = worldRule(rules, key);
  const n = typeof v === "string" && v.trim() !== "" ? Number(v) : v;
  if (typeof n !== "number" || !Number.isFinite(n)) {
    throw new RulesError(`world_rules.${key} is ${v === undefined ? "missing" : "not a number"}; it comes from the world_rules table`);
  }
  return n;
}

/** An aircraft type by its id or its name (compared as the old planner compares names). */
export function findType(rules: Rules, idOrName: number | string | null | undefined): AircraftTypeRow | undefined {
  if (idOrName == null) return undefined;
  if (typeof idOrName === "number") return rules.types.get(idOrName);
  return rules.typesByName.get(typeKey(idOrName));
}

/** An aircraft's type, or undefined. */
export function typeOfAircraft(rules: Rules, aircraftId: number | null | undefined): AircraftTypeRow | undefined {
  if (aircraftId == null) return undefined;
  const a = rules.aircraft.get(aircraftId);
  return a ? findType(rules, a.aircraft_type_id) : undefined;
}

/** An aircraft by its id or registration. */
export function findAircraft(rules: Rules, idOrRegistration: number | string) {
  return typeof idOrRegistration === "number" ? rules.aircraft.get(idOrRegistration) : rules.aircraftByRegistration.get(idOrRegistration);
}
