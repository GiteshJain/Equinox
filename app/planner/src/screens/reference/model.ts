// Reference's rows and the changes its edits make (the old planner's renderRef, renderRefRaw and their change and click
// handlers, with the old adapter's steps for what each writes: planner_apply_reference, planner_apply_routes and
// planner_apply_tidy, migration 20261010210000_adapter_write_side.sql). Plain data in, plain data out, so the unit tests
// can run it. Each edit is one planner_save() action writing exactly the rows the old planner writes.
import type { Change } from "../../data/save";
import type { Json } from "../../db/types";

// ---------- the sections, in the old order; each folds, and the open one is in the address (/reference/<slug>)
export const SECTIONS = [
  ["hubs", "Hubs, focus cities and banks"], ["constants", "Constants"], ["aircraft", "Aircraft"], ["configs", "Configs"],
  ["markets", "Markets"], ["services", "Service profiles"], ["removed", "Removed routes"], ["night-bans", "Night bans"],
  ["schedules", "Game schedules"], ["time-zones", "Time zones"], ["storage", "Storage"], ["data", "Data"],
] as const;
export type SectionSlug = (typeof SECTIONS)[number][0];
export const sectionOf = (slug: string | undefined): SectionSlug | null =>
  (SECTIONS.find(([s]) => s === (slug ?? "").toLowerCase().replace(/\/$/, ""))?.[0] ?? null);

// ---------- what the boxes hold, as the old planner turned a typed value into its document and the adapter into a column
/** The old planner's number test (a typed value that is a number became one). */
const NUMBER = /^-?\d+(\.\d+)?$/;
/** A whole number as the adapter read it (private.json_int): a number, or a number typed, with no fraction; else none. */
export function intOf(typed: string, limit = 2_000_000_000): number | null {
  const v = typed.trim();
  if (!NUMBER.test(v)) return null;
  const n = Number(v);
  return Number.isInteger(n) && Math.abs(n) < limit ? n : null;
}
/** A number as the adapter read it (private.json_num), or none. */
export function numOf(typed: string, limit = 1000): number | null {
  const v = typed.trim();
  if (!NUMBER.test(v)) return null;
  const n = Number(v);
  return Math.abs(n) < limit ? n : null;
}
/** A clock time as the adapter read it (private.clock_min): "H:MM" or "HH:MM", up to 23:59; as "HH:MM", or none. */
export function clockOf(typed: string): string | null {
  const m = /^(\d{1,2}):(\d{2})$/.exec(typed.trim());
  if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) return null;
  return `${String(Number(m[1])).padStart(2, "0")}:${m[2]}`;
}
/** A stored time ("06:45:00") as the old planner shows it ("06:45"). */
export const hhmm = (t: string | null | undefined): string => (t ? String(t).slice(0, 5) : "");

// ---------- hubs, focus cities and banks (airline_bases, and world_airports' connection time)
export interface BaseRow {
  id: number; airline_id: number; airport_code: string; role: string; is_main: boolean | null; parent_base_id: number | null;
  bank_times: (string | null)[] | null; flight_no_from: number | null; last_flight_no: number | null; hold_note: string | null;
  position: number | null; updated_at: string;
}
export const BASE_COLUMNS = "id, airline_id, airport_code, role, is_main, parent_base_id, bank_times, flight_no_from, last_flight_no, hold_note, position, updated_at";
export const basesInOrder = (rows: readonly BaseRow[]) => [...rows].sort((a, b) => (a.position ?? 1e9) - (b.position ?? 1e9) || a.id - b.id);

/** The four bank boxes as the old planner shows them: each bank time, empty for none. */
export const bankBoxes = (b: Pick<BaseRow, "bank_times">): string[] => [0, 1, 2, 3].map((k) => hhmm(b.bank_times?.[k] ?? null));

export type BaseField = "role" | "parent" | "block" | "lastUsed" | "banks.0" | "banks.1" | "banks.2" | "banks.3";
/** A base's box changed (the old data-ref hubs.<i>.<field>): its airline_bases row. The parent is the airline's own base at
 *  the airport chosen, else any base there (none for "—"). */
export function baseChange(b: BaseRow, field: BaseField, typed: string, all: readonly BaseRow[]): Change | null {
  let values: Record<string, Json>;
  if (field === "role") values = { role: typed === "focus" ? "focus" : "hub" };
  else if (field === "parent") {
    const there = all.filter((x) => x.airport_code === typed && x.id !== b.id).sort((x, y) => Number(y.airline_id === b.airline_id) - Number(x.airline_id === b.airline_id) || x.id - y.id);
    values = { parent_base_id: typed ? there[0]?.id ?? null : null };
  } else if (field === "block") values = { flight_no_from: intOf(typed) };
  else if (field === "lastUsed") values = { last_flight_no: intOf(typed) };
  else {
    const k = Number(field.slice(6));
    // the old document kept every box it showed (four), so the bank list has at least four places
    const banks = bankBoxes(b).map((s) => clockOf(s));
    for (let i = 4; i < (b.bank_times?.length ?? 0); i++) banks.push(clockOf(hhmm(b.bank_times?.[i] ?? null)));
    banks[k] = clockOf(typed);
    values = { bank_times: banks };
  }
  const [col, v] = Object.entries(values)[0] as [keyof BaseRow, Json];
  const now = col === "bank_times" ? JSON.stringify((b.bank_times ?? []).map((t) => (t ? hhmm(t) : null))) : JSON.stringify(b[col] ?? null);
  if (now === JSON.stringify(v)) return null;
  return { table: "airline_bases", op: "update", key: { id: b.id }, base: b.updated_at, values };
}

/** world_airports as Reference reads it. */
export interface WorldAirportRow {
  airport_code: string; mct_min: number | null; night_ban_from: string | null; night_ban_to: string | null; utc_offset_override: number | null;
  game_airport_id: number | null; closed: boolean; note: string | null; updated_at: string;
}
export const WORLD_AIRPORT_COLUMNS = "airport_code, mct_min, night_ban_from, night_ban_to, utc_offset_override, game_airport_id, closed, note, updated_at";
/** A base's MCT box: hours, as the old document held it (mct_min ÷ 60, without trailing zeros). */
export const mctHours = (w: Pick<WorldAirportRow, "mct_min"> | undefined): string => (w?.mct_min == null ? "" : String(Number(w.mct_min) / 60));

/** A base's MCT changed: the world's row for its airport, as the adapter wrote it (hours × 60 when that is whole, else none;
 *  none typed takes the website's figure, site_content.mct; the first base at an airport in the list is the one that
 *  counts). A row nothing describes any more goes. */
export function mctChange(worldId: number, b: BaseRow, typed: string, bases: readonly BaseRow[], row: WorldAirportRow | undefined,
  siteMct: Readonly<Record<string, Json>>): Change | null {
  const first = basesInOrder(bases).find((x) => x.airport_code === b.airport_code);
  if (first && first.id !== b.id) return null;
  const h = numOf(typed, 1e12);
  const m = h == null ? siteMinutes(siteMct[b.airport_code]) : h * 60;
  const mct = m != null && Number.isInteger(m) && Math.abs(m) < 32000 ? m : null;
  return worldRowChange(worldId, b.airport_code, row, { mct_min: mct }, true, siteMct);
}
const siteMinutes = (v: Json | undefined): number | null => (typeof v === "number" ? v : typeof v === "string" && NUMBER.test(v.trim()) ? Number(v) : null);

/** A change to the world's row for an airport, as the adapter made it: an insert where there is none (its connection time
 *  from the website's figure), an update where there is one, and a removal when nothing describes it any more (no
 *  connection time, night ban or offset, nothing from the game, open, no note, not on the website's list, not a base). */
export function worldRowChange(worldId: number, code: string, row: WorldAirportRow | undefined, set: Partial<Pick<WorldAirportRow, "mct_min" | "night_ban_from" | "night_ban_to" | "utc_offset_override">>,
  isBase: boolean, siteMct: Readonly<Record<string, Json>>): Change | null {
  if (!row) {
    const siteM = siteMinutes(siteMct[code]);
    const values = { mct_min: siteM != null && Number.isInteger(siteM) && Math.abs(siteM) < 32000 ? siteM : null, night_ban_from: null, night_ban_to: null, utc_offset_override: null, ...set };
    if (values.mct_min == null && values.night_ban_from == null && values.night_ban_to == null && values.utc_offset_override == null) return null;
    return { table: "world_airports", op: "insert", values: { world_id: worldId, airport_code: code, ...values } };
  }
  const next = { ...row, ...set };
  const empty = next.mct_min == null && next.night_ban_from == null && next.night_ban_to == null && next.utc_offset_override == null
    && next.game_airport_id == null && !next.closed && next.note == null && !Object.prototype.hasOwnProperty.call(siteMct, code) && !isBase;
  const key = { world_id: worldId, airport_code: code };
  if (empty) return { table: "world_airports", op: "delete", key, base: row.updated_at };
  const values: Record<string, Json> = {};
  for (const [k, v] of Object.entries(set)) if (JSON.stringify((row as unknown as Record<string, unknown>)[k] ?? null) !== JSON.stringify(v ?? null)) values[k] = v ?? null;
  if (!Object.keys(values).length) return null;
  return { table: "world_airports", op: "update", key, base: row.updated_at, values };
}

// ---------- night bans (world_airports.night_ban_from and _to)
/** A night ban as the old planner shows it: "00:01-05:59". */
export const banText = (w: Pick<WorldAirportRow, "night_ban_from" | "night_ban_to">): string => `${hhmm(w.night_ban_from)}-${hhmm(w.night_ban_to)}`;
/** A ban typed: "00:01-05:59" (spaces dropped), or none; the adapter took only two clock times. */
export function banOf(typed: string): { from: string | null; to: string | null } {
  const m = /^(\d{1,2}:\d{2})-(\d{1,2}:\d{2})$/.exec(typed.replace(/\s/g, ""));
  const from = m ? clockOf(m[1] as string) : null, to = m ? clockOf(m[2] as string) : null;
  return { from: from ? from + ":00" : null, to: to ? to + ":00" : null };
}
/** A ban typed, as the world row's two columns. */
export const banSet = (typed: string) => { const b = banOf(typed); return { night_ban_from: b.from, night_ban_to: b.to }; };
/** The old Add's check: a three-letter code and two clock times. */
export const canAddBan = (code: string, typed: string) => /^[A-Z0-9]{3}$/.test(code.trim().toUpperCase()) && /^\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2}$/.test(typed.trim());

// ---------- constants (settings and the departures cap in world_rules)
export const CONSTANTS: readonly [string, string, string][] = [
  ["buf", "Buffer beyond MCT (min)", "bank_buffer_min"], ["arrwin", "Arrival window (min)", "bank_arrival_window_min"],
  ["depwin", "Departure window (min)", "bank_departure_window_min"], ["ovh", "Block overhead per leg (min)", "block_allowance_min"],
  ["legalGap", "Legal minimum gap (h)", "legal_gap_h"], ["maxWait", "Max connection wait (h)", "connection_max_wait_h"],
  ["turnMargin", "Turn margin over the game turnaround (min)", "turn_margin_min"],
  ["maintMinGround", "Shortest maintenance window the game uses, beyond turnaround (min)", "maint_min_ground_min"],
  ["leeway", "New-route leeway (days)", "load_leeway_days"], ["lfWindow", "Load pattern window (days)", "load_window_days"],
  ["depCap", "Departures cap per airport per week", "departures_per_airport_week"],
  // since 21 Oct (spec docs/specs/2026-10-21-competition-analysis.md §3): how often the evening capture scans the world
  ["scanEvery", "World scan every (capture days; 1 = every evening)", "scan_every_days"],
];
export interface SettingRow { id: number; key: string; value: Json; updated_at: string }
export interface WorldRuleRow { id: number; key: string; value: Json; updated_at: string }
/** A constant's box: the setting's value (the cap: the world rule's value). */
export function constantValue(key: string, settings: readonly SettingRow[], rules: readonly WorldRuleRow[]): string {
  if (key === "departures_per_airport_week") {
    const r = rules.find((x) => x.key === key)?.value;
    return r && typeof r === "object" && !Array.isArray(r) && "value" in r ? String(r.value ?? "") : "";
  }
  const v = settings.find((s) => s.key === key)?.value;
  return v == null ? "" : String(v);
}
/** A constant changed: its setting's row (the cap: the world rule's value). Only a number is saved: the old planner
 *  stored anything typed, and a word in a rule number stops the planning library. */
export function constantChange(key: string, typed: string, settings: readonly SettingRow[], rules: readonly WorldRuleRow[]): Change | { error: string } | null {
  const n = numOf(typed, 1e12);
  if (n == null) return { error: `A rule number has to be a number (${typed.trim() || "nothing"} isn't); it wasn't saved.` };
  if (key === "departures_per_airport_week") {
    const r = rules.find((x) => x.key === key);
    if (!r || !r.value || typeof r.value !== "object" || Array.isArray(r.value)) return { error: "The departures cap isn't in world_rules." };
    if (r.value.value === n) return null;
    return { table: "world_rules", op: "update", key: { id: r.id }, base: r.updated_at, values: { value: { ...r.value, value: n } } };
  }
  const s = settings.find((x) => x.key === key);
  if (!s) return { error: `The setting ${key} isn't there.` };
  if (s.value === n) return null;
  return { table: "settings", op: "update", key: { id: s.id }, base: s.updated_at, values: { value: n } };
}

// ---------- aircraft types, configs and service profiles
export interface TypeRow {
  id: number; name: string; family_no: number | null; seats_max: number | null; cruise_kmh: number | null; min_turn_min: number | null;
  gap_target_h: number | null; order_config_id: number | null; updated_at: string;
}
export const TYPE_COLUMNS = "id, name, family_no, seats_max, cruise_kmh, min_turn_min, gap_target_h, order_config_id, updated_at";
export type TypeField = "name" | "family" | "seats" | "cruise" | "minTurn" | "gap";
export const TYPE_FIELDS: readonly [TypeField, keyof TypeRow][] = [["name", "name"], ["family", "family_no"], ["seats", "seats_max"], ["cruise", "cruise_kmh"], ["minTurn", "min_turn_min"], ["gap", "gap_target_h"]];
export function typeChange(t: TypeRow, field: TypeField, typed: string): Change | null {
  const col = (TYPE_FIELDS.find(([f]) => f === field) as [TypeField, keyof TypeRow])[1];
  const v: Json = field === "name" ? typed : field === "gap" ? numOf(typed) : field === "minTurn" ? intOf(typed, 32000) : intOf(typed);
  if (JSON.stringify(t[col] ?? null) === JSON.stringify(v)) return null;
  return { table: "aircraft_types", op: "update", key: { id: t.id }, base: t.updated_at, values: { [col]: v } };
}
/** Add type: the old planner's new row. */
export const addType = (worldId: number): Change => ({ table: "aircraft_types", op: "insert", values: {
  world_id: worldId, name: "New type", family_no: 0, seats_max: 0, cruise_kmh: 830, min_turn_min: 60, gap_target_h: 3, maint_per_hour: null,
  maint_per_cycle: null, ground_keep_min: null, price: null } });

export interface ConfigRow { id: number; code: string; aircraft_type_id: number | null; cabin: string | null; seats: number | null; updated_at: string }
export const CONFIG_COLUMNS = "id, code, aircraft_type_id, cabin, seats, updated_at";
export type ConfigField = "code" | "type" | "cabin" | "seats";
export function configChange(c: ConfigRow, field: ConfigField, typed: string, types: readonly TypeRow[]): Change | null {
  const [col, v]: [keyof ConfigRow, Json] = field === "code" ? ["code", typed] : field === "cabin" ? ["cabin", typed] : field === "seats" ? ["seats", intOf(typed)]
    : ["aircraft_type_id", [...types].sort((a, b) => a.id - b.id).find((t) => t.name === typed)?.id ?? null];
  if (JSON.stringify(c[col] ?? null) === JSON.stringify(v)) return null;
  return { table: "cabin_configs", op: "update", key: { id: c.id }, base: c.updated_at, values: { [col]: v } };
}
export const addConfig = (worldId: number): Change => ({ table: "cabin_configs", op: "insert", values: {
  world_id: worldId, code: "NEW", aircraft_type_id: null, cabin: "", seats: 0, business_seats: null, economy_seats: null, cost: null, note: null } });

export interface ServiceRow { id: number; code: string; airline_id: number | null; up_to_km: number | null; note: string | null; updated_at: string }
export const SERVICE_COLUMNS = "id, code, airline_id, up_to_km, note, updated_at";
export type ServiceField = "code" | "airline" | "upTo" | "note";
/** A service profile's box: "Legacy" is every airline without its own (no airline); an airline by its planner name. */
export function serviceChange(s: ServiceRow, field: ServiceField, typed: string, airlineByName: (name: string) => number | null): Change | null {
  const [col, v]: [keyof ServiceRow, Json] = field === "code" ? ["code", typed] : field === "note" ? ["note", typed] : field === "upTo" ? ["up_to_km", intOf(typed)]
    : ["airline_id", typed === "Legacy" ? null : airlineByName(typed)];
  if (JSON.stringify(s[col] ?? null) === JSON.stringify(v)) return null;
  return { table: "service_profiles", op: "update", key: { id: s.id }, base: s.updated_at, values: { [col]: v } };
}
export const addService = (worldId: number): Change => ({ table: "service_profiles", op: "insert", values: { world_id: worldId, airline_id: null, code: "S5", up_to_km: 99999, note: "" } });

// ---------- the cabin an order comes with (spec docs/specs/2026-10-15-last-leftovers.md §1): the type's
// (aircraft_types.order_config_id), and an airline's own where it differs (airline_order_cabins), which the database's
// private.fig_order_cabin() reads for Tails, the cash forecast and the briefing. Each pick is one planner_save() action.
/** The layouts an order of a type can come with: the type's own, by id. */
export const layoutsOf = (configs: readonly ConfigRow[], typeId: number): ConfigRow[] =>
  configs.filter((c) => c.aircraft_type_id === typeId).sort((a, b) => a.id - b.id);
/** A layout picked in an order-cabin box (its id as typed, "" for none): one of the type's layouts, else none. */
const layoutPicked = (configs: readonly ConfigRow[], typeId: number, picked: string): number | null =>
  picked === "" ? null : layoutsOf(configs, typeId).find((c) => String(c.id) === picked)?.id ?? null;
/** A type's order cabin picked (the Aircraft table): its row. */
export function orderCabinChange(t: TypeRow, picked: string, configs: readonly ConfigRow[]): Change | null {
  const v = layoutPicked(configs, t.id, picked);
  if ((t.order_config_id ?? null) === v) return null;
  return { table: "aircraft_types", op: "update", key: { id: t.id }, base: t.updated_at, values: { order_config_id: v } };
}
/** An airline's own order cabin for a type (airline_order_cabins); none means its orders come with no layout. */
export interface OwnOrderCabin { airline_id: number; aircraft_type_id: number; order_config_id: number | null; updated_at: string }
export const OWN_ORDER_COLUMNS = "airline_id, aircraft_type_id, order_config_id, updated_at";
const ownKey = (o: Pick<OwnOrderCabin, "airline_id" | "aircraft_type_id">) => ({ airline_id: o.airline_id, aircraft_type_id: o.aircraft_type_id });
/** An airline's own order cabin picked: its row. */
export function ownOrderChange(o: OwnOrderCabin, picked: string, configs: readonly ConfigRow[]): Change | null {
  const v = layoutPicked(configs, o.aircraft_type_id, picked);
  if ((o.order_config_id ?? null) === v) return null;
  return { table: "airline_order_cabins", op: "update", key: ownKey(o), base: o.updated_at, values: { order_config_id: v } };
}
/** Add an airline's own for a type: it starts as the type's, so nothing moves until another is picked; none if it has one. */
export function addOwnOrder(worldId: number, airlineId: number, t: TypeRow, own: readonly OwnOrderCabin[]): Change | null {
  if (own.some((o) => o.airline_id === airlineId && o.aircraft_type_id === t.id)) return null;
  return { table: "airline_order_cabins", op: "insert", values: { world_id: worldId, airline_id: airlineId, aircraft_type_id: t.id, order_config_id: t.order_config_id } };
}
/** remove: the airline takes the type's order cabin again. */
export const removeOwnOrder = (o: OwnOrderCabin): Change => ({ table: "airline_order_cabins", op: "delete", key: ownKey(o), base: o.updated_at });

/** What still uses a type or a layout: the adapter left such a row in place when the old planner removed it. */
export interface InUse { types: ReadonlySet<number>; configs: ReadonlySet<number>; markets: ReadonlySet<number> }
export const removeRow = (table: "aircraft_types" | "cabin_configs" | "service_profiles" | "markets", row: { id: number; updated_at: string }): Change =>
  ({ table, op: "delete", key: { id: row.id }, base: row.updated_at });

// ---------- markets (Market defaults until 21 Oct: each market keeps only its layout since; spec
// docs/specs/2026-10-21-cabins-new-rule.md §2)
export interface MarketRow { id: number; airline_id: number; name: string; layout: string; updated_at: string }
export const MARKET_COLUMNS = "id, airline_id, name, layout, updated_at";
/** The layouts a market may call for (markets.layout's check; manual §5). */
export const LAYOUTS = ["Standard", "Leisure", "Leisure Plus", "Comfort"] as const;
/** A market's layout chosen: one change on the market; nothing when it's the same or not one of the four. */
export function marketChange(m: MarketRow, typed: string): Change | null {
  if (!(LAYOUTS as readonly string[]).includes(typed) || typed === m.layout) return null;
  return { table: "markets", op: "update", key: { id: m.id }, base: m.updated_at, values: { layout: typed } };
}
/** The old document's market order: its keys ("Airline|Market") as JSON keys come back as the database keeps a jsonb
 *  object's keys, shortest first in bytes (UTF-8: a dash "–" is three), then byte by byte. The rehearsal found "Ryanair|Europe
 *  – low" (20 letters, 22 bytes) placed before "Pan American|Transcon" (21) when letters were counted. */
const utf8 = new TextEncoder();
export function keyOrder(a: string, b: string): number {
  const x = utf8.encode(a), y = utf8.encode(b);
  if (x.length !== y.length) return x.length - y.length;
  for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return (x[i] ?? 0) - (y[i] ?? 0);
  return 0;
}

// ---------- removed routes
export interface RemovedRoute {
  id: number; airline_id: number; hub_code: string; dest_code: string; removed_note: string | null; city_override: string | null;
  distance_override_km: number | null; market_override_id: number | null; market_cleared: boolean; stars_override: number | null;
  edit_kept: boolean; updated_at: string;
}
export const REMOVED_COLUMNS = "id, airline_id, hub_code, dest_code, removed_note, city_override, distance_override_km, market_override_id, market_cleared, stars_override, edit_kept, updated_at";
/** restore (the old data-restore and restore all): the route is no longer removed and its other edits stay; an edit left
 *  with nothing in it is kept as one (edit_kept), as the adapter wrote it. */
export function restoreChange(r: RemovedRoute): Change {
  const kept = r.removed_note == null && r.city_override == null && r.distance_override_km == null && r.market_override_id == null && !r.market_cleared
    && r.stars_override == null;
  return { table: "routes", op: "update", key: { id: r.id }, base: r.updated_at, values: kept === r.edit_kept ? { removed: false } : { removed: false, edit_kept: kept } };
}
/** A removed route as the old list names it: "Kingfisher · BLR–SYD". */
export const removedWords = (airline: string, r: Pick<RemovedRoute, "hub_code" | "dest_code">) => `${airline} · ${r.hub_code}–${r.dest_code}`;

// ---------- game schedules
/** The game's public schedule page for an airline, as the old planner's getter gives it. */
export const scheduleLink = (host: string | null, gameId: number | null) => (host && gameId != null ? `https://${host}/app/info/enterprises/${gameId}?tab=3` : "");
export const pageId = (link: string) => /enterprises\/(\d+)/.exec(link)?.[1] ?? (/^\d+$/.test(link) ? link : "");

// ---------- the flights' CSV (the old Export flights)
export const CSV_HEAD = ["Flight", "Airline", "From", "To", "Days", "Dep local", "Arr local", "+d", "Duration", "Tail", "Aircraft", "Config", "Seats", "Service", "Price", "SLF", "Wave"];
export const csvLine = (r: readonly (string | number | null | undefined)[]) => r.map((v) => `"${String(v == null ? "" : v).replace(/"/g, '""')}"`).join(",");
/** The CSV's Wave column for the outbound and the return, as the old flightsCsv wrote it from its waveAt: the bank the
 *  outbound leaves in ("B1"), and the bank the return comes into, which is the first it can make even when that's
 *  beyond the wait and the route's pill says "arr off wave" (the library's `next`); "off" for none. The rehearsal found
 *  "off" on returns the old file named "B1". */
export function csvBanks(w: { dep: { ok: boolean; n: number } | null; arr: { next: number } | null }): [string, string] {
  return [w.dep?.ok && w.dep.n ? `B${w.dep.n}` : "off", w.arr?.next ? `B${w.arr.next}` : "off"];
}
