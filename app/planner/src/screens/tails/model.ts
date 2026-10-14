// The Tails screen's logic (decision #18, build pull request 7; spec docs/specs/2026-10-13-tails.md): the list and its
// filters as the old renderTailsCore, an aircraft's page as renderTailDetail (its week strip, its legs by flight number,
// its issues), the deliveries board as deliveryRows and renderDeliveries, a plan card as planCard, the check against the
// game before filing (checkBeforeFile), and every action as one planner_save() call: add, edit and remove an aircraft,
// mark its one-week check, and filing (filePlan and importFlight). No screen code, so the unit tests run it. Every
// planning figure is the library's (aircraftWeek, maintenance, tails, frequency, time); this file joins the tables'
// rows to it and words what it answers, as the old planner words it.
import {
  aircraftWeek, banks, block, buildRules, frequency, game, maintenance, service, tails, time, type AircraftWeek, type AirportRow, type CardCheck as LibCardCheck,
  type CheckRow as LibCheckRow, type GameFlight as LibGameFlight, type LocalTimes, type Maintenance, type NoMaintenance, type Rules, type ServiceProfile,
  type TailIssue, type TimedLeg, type WeekLeg,
} from "@rules";
import type { Change, Values } from "../../data/save";
import type { Json } from "../../db/types";
import { toMinute } from "../../ui/dates";
import { addRouteChanges, priceFor, routeOf, type AirportInfo, type MarketRow, type RouteRow } from "../routes/model";

// ---------- the rows the screen reads
export interface TailAircraft {
  id: number;
  registration: string;
  airline_id: number;
  aircraft_type_id: number | null;
  cabin_config_id: number | null;
  base_code: string | null;
  /** on_order, delivered (arrived, not filed), active (the old planner's tail) or retired. */
  status: string;
  ordered_on: string | null;
  delivery_at: string | null;
  order_base_code: string | null;
  order_config_id: number | null;
  order_note: string | null;
  checked_on: string | null;
  schedule_changed_on: string | null;
  maintenance_note: string | null;
  retired_on: string | null;
  extra: Json;
  updated_at: string;
}
export const AIRCRAFT_COLUMNS = "id, registration, airline_id, aircraft_type_id, cabin_config_id, base_code, status, ordered_on, delivery_at, "
  + "order_base_code, order_config_id, order_note, checked_on, schedule_changed_on, maintenance_note, retired_on, extra, updated_at";

export interface ConfigRow { id: number; code: string; aircraft_type_id: number | null; cabin: string | null; cost: number | null }
export interface BuyTypeRow { airline_id: number; aircraft_type_id: number }
/** A plan card. extra is the old planner's: where a card's typed legs didn't fit its leg rows (their weekdays, say), its
 *  storage keeps them whole in extra.legs, and the old planner shows those. */
export interface PlanCardRow { id: number; airline_id: number; aircraft_id: number; base_code: string | null; title: string | null; note: string | null; extra?: Json; updated_at: string }
export const PLAN_CARD_COLUMNS = "id, airline_id, aircraft_id, base_code, title, note, extra, updated_at";
export interface PlanLegRow {
  id: number;
  plan_card_id: number;
  position: number;
  flight_no: number | null;
  origin_code: string;
  dest_code: string;
  days_utc: number[];
  dep_utc_min: number | null;
  block_min: number | null;
  service_code: string | null;
  updated_at: string;
}
export const PLAN_LEG_COLUMNS = "id, plan_card_id, position, flight_no, origin_code, dest_code, days_utc, dep_utc_min, block_min, service_code, updated_at";

/** One of our airlines, as the screen names it, with what Tails needs: low cost (its cabins) and its game ID (its link). */
export interface TailAirline { id: number; code: string | null; name: string; color: string | null; is_lcc: boolean; game_id: number | null }

/** One flight of the airline's public schedule, as /api/game-schedule gives it (the library's). */
export type GameFlight = LibGameFlight;

const isObj = (v: Json | undefined): v is { [k: string]: Json } => !!v && typeof v === "object" && !Array.isArray(v);
/** A number kept in an aircraft's extra (tails_index, deliveries_index), or null. */
export function extraIndex(a: Pick<TailAircraft, "extra">, key: "tails_index" | "deliveries_index"): number | null {
  const v = isObj(a.extra) ? a.extra[key] : undefined;
  return typeof v === "number" ? v : typeof v === "string" && v !== "" && Number.isFinite(Number(v)) ? Number(v) : null;
}
/** The notes the old planner kept on a tail (the table has no column for them: extra.tail.notes). */
export function tailNotes(a: Pick<TailAircraft, "extra">): string {
  const t = isObj(a.extra) ? a.extra.tail : undefined;
  return isObj(t) && typeof t.notes === "string" ? t.notes : "";
}

// ---------- how the screen words things, as the old planner does
export const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const pad = (n: number) => String(n).padStart(2, "0");
/** A clock time, "HH:MM" (the old H). */
export const H = (m: number): string => time.clock(m);
/** A duration, "1:15" (the old hhmm). */
export const hhmm = (m: number): string => banks.duration(m);
/** A day list as the old Tails writes it: "daily", or "Mon Wed Fri" (0 = Monday). */
export function daysText(ds: readonly number[]): string {
  const u = [...new Set(ds)].sort((a, b) => a - b);
  return u.length === 7 ? "daily" : u.map((d) => DAYS[d] ?? "?").join(" ");
}
/** A type's name as the old planner keeps it, for a type id. */
export const typeName = (rules: Rules, id: number | null | undefined): string => (id == null ? "" : rules.types.get(id)?.name ?? "");
export const configCode = (configs: ReadonlyMap<number, ConfigRow>, id: number | null | undefined): string => (id == null ? "" : configs.get(id)?.code ?? "");
const norm = (s: string | null | undefined) => String(s ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");

/** The maintenance pill (the old maintPill): ≈P% ("400+" above 400), its class, and the hours behind it. */
export function maintPill(m: Maintenance | NoMaintenance | null | undefined): { text: string; cls: "ok" | "warn" | "bad"; title: string } | null {
  if (!m || m.ratio == null || !("level" in m)) return null;
  return {
    text: `≈${m.pct > 400 ? "400+" : m.pct}%`, cls: m.level,
    title: `Estimated maintenance ratio: ${hhmm(Math.round(m.have_min_day))} of usable ground time a day against about ${hhmm(Math.round(m.need_min_day))} needed`,
  };
}

/** An issue in the old tailIssues' words. */
export function issueWords(i: TailIssue): string {
  const s = (n: number) => (n > 1 ? "s" : "");
  switch (i.kind) {
    case "block_hours": return `flies ${i.block_hours_day.toFixed(1)} h a day — under the ${i.target_h} h target`;
    case "short_turns": return `${i.count} short turn${s(i.count)} a week`;
    case "maintenance": return i.level === "bad" ? `maintenance ≈${i.pct}% — under ${i.min_pct}%, condition will fall` : `maintenance ≈${i.pct}% — little headroom`;
    case "tight_turns": return `${i.count} turn${s(i.count)} a week under the ${i.margin_min}-min margin`;
    case "positions": return `${i.count} leg${s(i.count)} start where the aircraft isn't`;
    case "longest_gap": return `longest gap ${hhmm(i.gap_min)} — under the ${i.target_h} h target`;
    case "off_wave": return `${i.count} rotation${s(i.count)} off wave`;
  }
}

// ---------- an aircraft's figures, from the library
export interface TailFigures {
  week: AircraftWeek | null;
  maint: Maintenance | NoMaintenance | null;
  legsWk: number;
  blockDay: number;
  routes: number;
  /** A short turn or a leg starting where the aircraft isn't (the list's red dot). */
  marked: boolean;
  needsALook: boolean;
}
export function figuresOf(rules: Rules, aircraftId: number, legs = rulesLegs(rules)): TailFigures {
  const ac = rules.aircraft.get(aircraftId);
  const week = ac ? aircraftWeek.forAircraft(rules, ac, legs) : null;
  const maint = ac ? maintenance.forAircraft(rules, ac, legs, week) : null;
  return {
    week, maint, legsWk: week?.legs_week ?? 0, blockDay: week?.block_hours_day ?? 0, routes: week?.routes ?? 0,
    marked: week ? tails.marked(week) : false, needsALook: week ? tails.needsALook(week, maint) : false,
  };
}
const legsCache = new WeakMap<Rules, TimedLeg[]>();
/** The rules' timed legs, worked out once per rules. */
export function rulesLegs(rules: Rules): TimedLeg[] {
  let l = legsCache.get(rules);
  if (!l) {
    l = block.timedLegs(rules);
    legsCache.set(rules, l);
  }
  return l;
}

/** A week leg's flight number as the old planner shows it: a return with none takes its outbound's less one. */
export function legNumber(rules: Rules, w: Pick<WeekLeg, "leg_id" | "flight_no">): number | null {
  if (w.flight_no != null) return w.flight_no;
  const row = rules.legs.find((l) => l.id === w.leg_id);
  if (!row || row.rotation_id == null || (row.leg_no ?? 1) !== 2) return null;
  const out = rules.legs.find((l) => l.rotation_id === row.rotation_id && (l.leg_no ?? 1) === 1);
  return out?.flight_no ? out.flight_no - 1 : null;
}

// ---------- the list: filters in the address, as the old ui.tf (base, type, status) and ui.df (the deliveries' status)
export type TailStatus = "" | "flying" | "idle" | "warn";
export type DeliveryStatus = "" | "on order" | "unscheduled" | "flying";
export interface Filters {
  /** The airline's code; null for the first of ours. */
  airline: string | null;
  base: string;
  type: string;
  status: TailStatus;
  del: DeliveryStatus;
  /** The plan card shown open on the deliveries board, and one to file at once (Home's "File into planner"). */
  card: string;
  file: string;
}
const TAIL_STATUSES: readonly TailStatus[] = ["", "flying", "idle", "warn"];
const DEL_STATUSES: readonly DeliveryStatus[] = ["", "on order", "unscheduled", "flying"];
export function parseFilters(search: string): Filters {
  const p = new URLSearchParams(search);
  const st = (p.get("status") ?? "") as TailStatus, del = (p.get("del") ?? "") as DeliveryStatus;
  return {
    airline: p.get("airline") || null, base: p.get("base") ?? "", type: p.get("type") ?? "",
    status: TAIL_STATUSES.includes(st) ? st : "", del: DEL_STATUSES.includes(del) ? del : "", card: p.get("card") ?? "", file: p.get("file") ?? "",
  };
}
export function filtersQuery(f: Filters): string {
  const p = new URLSearchParams();
  if (f.airline) p.set("airline", f.airline);
  if (f.base) p.set("base", f.base);
  if (f.type) p.set("type", f.type);
  if (f.status) p.set("status", f.status);
  if (f.del) p.set("del", f.del);
  if (f.card) p.set("card", f.card);
  if (f.file) p.set("file", f.file);
  const s = p.toString();
  return s ? "?" + s : "";
}

/** The airline's tails (status active), in the old planner's list order (aircraft.extra.tails_index, then id). */
export function tailsOf(aircraft: readonly TailAircraft[], airlineId: number | undefined): TailAircraft[] {
  return aircraft.filter((a) => a.airline_id === airlineId && a.status === "active")
    .sort((a, b) => (extraIndex(a, "tails_index") ?? 1e9) - (extraIndex(b, "tails_index") ?? 1e9) || a.id - b.id);
}

export interface TailRow { a: TailAircraft; type: string; config: string; base: string; fig: TailFigures }

/** The list as renderTailsCore shows it: the airline's tails with the base, type and status filters. */
export function tailRows(mine: readonly TailAircraft[], f: Pick<Filters, "base" | "type" | "status">, rules: Rules, configs: ReadonlyMap<number, ConfigRow>): TailRow[] {
  const legs = rulesLegs(rules);
  const out: TailRow[] = [];
  for (const a of mine) {
    const row = { a, type: typeName(rules, a.aircraft_type_id), config: configCode(configs, a.cabin_config_id), base: a.base_code ?? "", fig: figuresOf(rules, a.id, legs) };
    if (f.base && row.base !== f.base) continue;
    if (f.type && row.type !== f.type) continue;
    if (f.status === "flying" && !row.fig.legsWk) continue;
    if (f.status === "idle" && row.fig.legsWk) continue;
    if (f.status === "warn" && !row.fig.needsALook) continue;
    out.push(row);
  }
  return out;
}
/** The base and type chips: each one the airline's tails have, sorted. */
export function chips(mine: readonly TailAircraft[], rules: Rules): { bases: string[]; types: string[] } {
  return {
    bases: [...new Set(mine.map((a) => a.base_code ?? "").filter(Boolean))].sort(),
    types: [...new Set(mine.map((a) => typeName(rules, a.aircraft_type_id)).filter(Boolean))].sort(),
  };
}

// ---------- the types and cabins an airline's aircraft may have, and its bases (the old typesFor, configsFor, hubsOf)
/** The types the airline may have: airline_aircraft_types (the old planner's BUY_TYPES), in the types' order. */
export function typesFor(rules: Rules, buy: readonly BuyTypeRow[], airlineId: number): string[] {
  const ids = new Set(buy.filter((b) => b.airline_id === airlineId).map((b) => b.aircraft_type_id));
  return [...rules.types.values()].filter((t) => ids.has(t.id)).sort((a, b) => a.id - b.id).map((t) => t.name);
}
/** The cabin layouts for the airline (a low-cost airline's Standard ones, the others' every other cabin), of one type
 *  when given, in the layouts' order. */
export function configsFor(rules: Rules, configs: readonly ConfigRow[], airline: Pick<TailAirline, "is_lcc">, type?: string): string[] {
  return configs.filter((c) => (!type || norm(typeName(rules, c.aircraft_type_id)) === norm(type)) && (airline.is_lcc ? c.cabin === "Standard" : c.cabin !== "Standard"))
    .sort((a, b) => a.id - b.id).map((c) => c.code);
}
/** The airline's bases, hubs and focus cities, in their order. */
export const basesOf = (rules: Rules, airlineId: number): string[] => rules.bases.filter((b) => b.airline_id === airlineId).map((b) => b.airport_code);

// ---------- an aircraft's page: its header, the week strip and its legs by flight number
export function headerWords(rules: Rules, a: TailAircraft, configs: ReadonlyMap<number, ConfigRow>, fig: TailFigures): string {
  const ty = a.aircraft_type_id == null ? undefined : rules.types.get(a.aircraft_type_id);
  const gap = ty ? String(ty.gap_target_h ?? "undefined") : "?", turn = ty ? String(ty.min_turn_min ?? "undefined") : "?";
  return `${typeName(rules, a.aircraft_type_id)} · ${configCode(configs, a.cabin_config_id)} · ${fig.legsWk} legs/wk · ${fig.blockDay.toFixed(1)} block h/day · `
    + `gap target ${gap} h, min turn ${turn} min · ${fig.week?.gaps_at_target ?? 0} gaps ≥ target this week · maintenance`;
}

export interface StripBar { day: number; left: number; width: number; bad: boolean; title: string; text: string }
/** The week strip: each leg as bars in the base's local time (the aircraft's base, else its first leg's origin), split at
 *  midnight; red where the turn is short or the next leg starts elsewhere (the old renderTailDetail). */
export function weekStrip(rules: Rules, a: TailAircraft, week: AircraftWeek | null): { base: string; bars: StripBar[] } {
  const legs = week?.legs ?? [];
  const base = a.base_code || legs[0]?.origin || "";
  const off = time.utcOffsetMin(rules, base || "DEL");
  const WEEK = time.WEEK, DAY = time.DAY;
  const bars: StripBar[] = [];
  for (const l of legs) {
    const s = time.mod(l.dep_utc + off, WEEK), e = s + l.block_min;
    const no = legNumber(rules, l);
    const title = `${no ?? "null"} ${l.origin} ${H(l.dep_local)} → ${l.dest} ${H(l.arr_local)}`;
    for (let x = s; x < e;) {
      const dayStart = Math.floor(x / DAY) * DAY, dayEnd = dayStart + DAY;
      const x0 = x - dayStart, x1 = Math.min(e, dayEnd) - dayStart;
      const len = x1 - x0;
      bars.push({ day: Math.floor(x / DAY) % 7, left: x0 / DAY * 100, width: len / DAY * 100, bad: !!l.turn?.short || !l.position_ok, title,
        text: len > 75 ? `${l.origin}–${l.dest}` : len > 34 ? l.dest : "" });
      x = dayEnd;
    }
  }
  return { base, bars };
}

export interface LegGroup { no: number | null; from: string; to: string; days: number[]; dep: number; arr: number; arrNextDay: boolean; block: number; gaps: number[];
  pill: { cls: "bad" | "warn" | "ok"; text: string } | null }
/** One line per flight number and times, its days combined (the old renderTailDetail's table), by departure time. */
export function legGroups(rules: Rules, a: TailAircraft, week: AircraftWeek | null): LegGroup[] {
  const ty = a.aircraft_type_id == null ? undefined : rules.types.get(a.aircraft_type_id);
  const target = ty?.gap_target_h == null ? null : Number(ty.gap_target_h) * 60;
  const m = new Map<string, { l: WeekLeg; no: number | null; days: number[]; gaps: number[]; short: boolean; tight: boolean; pos: boolean; big: boolean }>();
  for (const l of week?.legs ?? []) {
    const no = legNumber(rules, l);
    const dep = time.mod(l.dep_local, time.DAY), arr = time.mod(l.arr_local, time.DAY);
    const k = [no, l.origin, l.dest, dep, arr].join("|");
    let g = m.get(k);
    if (!g) m.set(k, g = { l, no, days: [], gaps: [], short: false, tight: false, pos: true, big: false });
    g.days.push(Math.floor(l.dep_local / time.DAY));
    if (l.ground_min != null) g.gaps.push(l.ground_min);
    g.short = g.short || !!l.turn?.short;
    g.tight = g.tight || !!l.turn?.tight;
    g.pos = g.pos && l.position_ok;
    g.big = g.big || (target != null && l.ground_min != null && l.ground_min >= target);
  }
  return [...m.values()].map((g) => {
    const dep = time.mod(g.l.dep_local, time.DAY);
    return {
      no: g.no, from: g.l.origin, to: g.l.dest, days: g.days, dep, arr: time.mod(g.l.arr_local, time.DAY),
      arrNextDay: Math.floor(g.l.arr_local / time.DAY) !== Math.floor(g.l.dep_local / time.DAY), block: g.l.block_min, gaps: g.gaps,
      pill: !g.pos ? { cls: "bad" as const, text: "next leg starts elsewhere" } : g.short ? { cls: "bad" as const, text: "short turn" }
        : g.tight ? { cls: "warn" as const, text: "tight turn" } : g.big ? { cls: "ok" as const, text: "gap" } : null,
    };
  }).sort((x, y) => x.dep - y.dep || String(x.no).localeCompare(String(y.no)));
}
/** The ground time to the next leg, as one time or a range. */
export const gapWords = (gaps: readonly number[]): string =>
  !gaps.length ? "" : Math.min(...gaps) === Math.max(...gaps) ? hhmm(Math.min(...gaps)) : `${hhmm(Math.min(...gaps))} – ${hhmm(Math.max(...gaps))}`;

/** The aircraft pop-up's flights (the old tailModal): one line per flight number, the first of its legs, by departure. */
export function popupFlights(rules: Rules, week: AircraftWeek | null): { no: number | null; from: string; to: string; dep: number; arr: number; block: number; short: boolean }[] {
  const by = new Map<string, WeekLeg>();
  for (const l of week?.legs ?? []) {
    const k = String(legNumber(rules, l));
    if (!by.has(k)) by.set(k, l);
  }
  return [...by.values()].map((l) => ({ no: legNumber(rules, l), from: l.origin, to: l.dest, dep: time.mod(l.dep_local, time.DAY), arr: time.mod(l.arr_local, time.DAY),
    block: l.block_min, short: !!l.turn?.short }))
    .map((x, i) => ({ x, i })).sort((p, q) => p.x.dep - q.x.dep || p.i - q.i).map((p) => p.x);
}
/** A block time in the pop-up: "2:05". */
export const blockClock = (m: number): string => (m ? `${Math.floor(m / 60)}:${pad(m % 60)}` : "");

// ---------- deliveries (the old deliveryRows): every aircraft with a delivery, on order, arrived or flying
export interface DeliveryRow {
  a: TailAircraft;
  airline: TailAirline | undefined;
  type: string;
  config: string;
  /** Its arrival in the game, ms, or NaN. */
  at: number;
  due: string;
  hrs: number | null;
  base: string;
  plan: string;
  status: Exclude<DeliveryStatus, "">;
  card: PlanCardRow | undefined;
}
/** The aircraft flying a rotation: each rotation's outbound's, else its return's (the old freq's tail). */
export function flyingIds(rules: Rules): Set<number> {
  const byRot = new Map<number, { l1?: number | null; l2?: number | null }>();
  for (const l of rules.legs) {
    if (l.rotation_id == null) continue;
    const r = byRot.get(l.rotation_id) ?? {};
    if ((l.leg_no ?? 1) === 1) r.l1 = l.aircraft_id;
    else r.l2 = l.aircraft_id;
    byRot.set(l.rotation_id, r);
  }
  return new Set([...byRot.values()].map((r) => r.l1 ?? r.l2).filter((x): x is number => x != null));
}
const RANK = { unscheduled: 0, "on order": 1, flying: 2 } as const;
export function deliveryRows(aircraft: readonly TailAircraft[], airlines: readonly TailAirline[], rules: Rules, configs: ReadonlyMap<number, ConfigRow>,
  cards: readonly PlanCardRow[], now: number, today: string): DeliveryRow[] {
  const flying = flyingIds(rules);
  const cardOf = new Map(cards.map((c) => [c.aircraft_id, c]));
  return aircraft.filter((a) => a.delivery_at && a.status !== "retired")
    .sort((a, b) => (extraIndex(a, "deliveries_index") ?? 1e9) - (extraIndex(b, "deliveries_index") ?? 1e9) || a.id - b.id)
    .map((a): DeliveryRow => {
      // to the minute, as the old planner's documents kept delivery times
      const at = toMinute(String(a.delivery_at));
      const ok = Number.isFinite(at);
      const due = ok ? new Date(at).toISOString().slice(0, 10) : "";
      const arrived = ok ? at <= now : !!due && due <= today;
      return {
        a, airline: airlines.find((x) => x.id === a.airline_id), type: typeName(rules, a.aircraft_type_id), config: configCode(configs, a.order_config_id),
        at, due, hrs: ok ? (at - now) / 36e5 : null, base: a.order_base_code ?? "", plan: String(a.order_note ?? "").replace(/^lands [^·]+· /, ""),
        status: flying.has(a.id) ? "flying" : arrived ? "unscheduled" : "on order", card: cardOf.get(a.id),
      };
    })
    .map((r, i) => ({ r, i })).sort((x, y) => RANK[x.r.status] - RANK[y.r.status] || (x.r.due < y.r.due ? -1 : x.r.due > y.r.due ? 1 : 0) || x.i - y.i)
    .map((x) => x.r);
}
/** The board's rows for the airline and the Tails filters (base and type), and its own status filter (open by default). */
export function shownDeliveries(rows: readonly DeliveryRow[], airlineId: number | undefined, f: Pick<Filters, "base" | "type" | "del">): DeliveryRow[] {
  return rows.filter((r) => r.a.airline_id === airlineId && (!f.base || r.base === f.base) && (!f.type || norm(r.type) === norm(f.type))
    && (f.del ? r.status === f.del : r.status !== "flying"));
}
/** "in 5 h" or "in 3 days" after a delivery still to come. */
export const comingIn = (hrs: number | null): string => (hrs != null && hrs > 0 ? (hrs < 24 ? `in ${Math.ceil(hrs)} h` : `in ${Math.ceil(hrs / 24)} days`) : "");

// ---------- a plan card, as the old planner shows it: its legs in local time
export interface CardLeg {
  row: PlanLegRow;
  no: string;
  from: string;
  to: string;
  /** Local "HH:MM" at the origin, and at the destination ("" without a block). */
  dep: string;
  arr: string;
  block: string;
  svc: string;
  /** The local weekdays it leaves on at the origin, "1234567" for every day. */
  days: string;
}
/** The rules with airports the start doesn't carry (a plan card's new destination), from the tables. */
export function withAirports(rules: Rules, airports: readonly AirportInfo[]): Rules {
  const have = new Set(rules.input.airports.map((a) => a.code));
  const extra: AirportRow[] = airports.filter((a) => !have.has(a.code)).map((a) => ({
    code: a.code, city: a.city, country_code: a.country_code, lat: a.lat, lon: a.lon, utc_offset: a.correction ?? a.utc_offset, utc_offset_override: a.correction, mct_min: null,
  }));
  return extra.length ? buildRules({ ...rules.input, airports: [...rules.input.airports, ...extra] }) : rules;
}
export function cardLegs(rules: Rules, legs: readonly PlanLegRow[]): CardLeg[] {
  return [...legs].sort((a, b) => a.position - b.position).map((l) => {
    const dep = l.dep_utc_min == null ? null : time.toLocal(rules, l.origin_code, l.dep_utc_min, time.DAY);
    const arr = l.dep_utc_min == null || l.block_min == null ? null : time.toLocal(rules, l.dest_code, l.dep_utc_min + l.block_min, time.DAY);
    const days = l.dep_utc_min == null ? "1234567" : time.localDays(rules, l.origin_code, l.days_utc?.length ? l.days_utc : [1, 2, 3, 4, 5, 6, 7], l.dep_utc_min).join("");
    return {
      row: l, no: l.flight_no == null ? "" : String(l.flight_no), from: l.origin_code, to: l.dest_code, dep: dep == null ? "" : H(dep), arr: arr == null ? "" : H(arr),
      block: l.block_min == null ? "" : `${Math.floor(l.block_min / 60)}:${pad(l.block_min % 60)}`, svc: l.service_code ?? "", days,
    };
  });
}

// ---------- the plan card's service check (#18 build pull request 10, spec docs/specs/2026-10-14-review.md part 2): each
// leg's service code against the one its route's distance calls for (the library's service.checkLegs). The start carries
// only the flown routes, so the airline's own routes are laid in first, as filing takes a leg's distance from them.
/** The rules with an airline's routes the start doesn't carry (a plan card's new route), with any distance override. */
export function withRoutes(rules: Rules, routes: readonly RouteRow[]): Rules {
  const have = new Set(rules.input.routes.map((r) => r.id));
  const extra = routes.filter((r) => !have.has(r.id) && !r.removed).map((r) => ({
    id: r.id, airline_id: r.airline_id, hub_code: r.hub_code, dest_code: r.dest_code, distance_km: r.distance_override_km ?? r.distance_km,
  }));
  return extra.length ? buildRules({ ...rules.input, routes: [...rules.input.routes, ...extra] }) : rules;
}
/** Each card leg's service issue (the code given against the code wanted), by the leg's row id; empty when all are right. */
export function cardServiceIssues(rules: Rules, airlineId: number, legs: readonly CardLeg[]): Map<number, string> {
  const check = service.checkLegs(rules, airlineId, legs.map((L) => ({ flight_no: L.row.flight_no, origin_code: L.from, dest_code: L.to, service_code: L.row.service_code })));
  const out = new Map<number, string>();
  for (const i of check.issues) {
    const L = legs[i.leg - 1];
    if (L) out.set(L.row.id, service.shortWords(i));
  }
  return out;
}

// ---------- the check before filing (the old checkBeforeFile): each plan-card leg against the game's schedule, with the
// library's game comparison (game.compareCard, the same code the Check screen's Game check uses, #18 build pull request 9)
export const sortDays = game.sortDays;
export const daysLabel = game.daysLabel;
/** A leg's days after its times in the check's table, unless every day. */
export const daysSuffix = (x: string | null | undefined): string => (x && sortDays(x) !== "1234567" ? " " + daysLabel(sortDays(x)) : "");
export type CheckRow = LibCheckRow<CardLeg>;
export type CardCheck = LibCardCheck<CardLeg>;
/** Whether the game flies a card leg at the card's times: its departure, its arrival (when the game gives one) and days. */
export const sameTimes = game.sameTimes;
/** Each leg with the game's flight of the same number and airports, and whether its times and days are the same. */
export const compareCard = (legs: readonly CardLeg[], flights: readonly GameFlight[] | null, err = ""): CardCheck => game.compareCard(legs, flights, err);
/** The check's line above its table. */
export function checkSummary(c: CardCheck): string {
  const n = c.rows.length;
  if (c.miss) return `${c.miss} of ${n} flights aren't in the game's schedule yet${c.diff ? `, and ${c.diff} differ from the plan card` : ""}.`;
  return c.diff ? `${c.diff} of ${n} flights differ from the plan card. The game's times are the real ones.` : "Everything matches.";
}
/** The airline's public schedule in the game: its enterprise page (the old ref.gameLinks, from worlds.game_host and
 *  airlines.game_id). */
export const gameLink = (host: string | null | undefined, gameId: number | null | undefined): string | null =>
  host && gameId != null ? `https://${host}/app/info/enterprises/${gameId}?tab=3` : null;

// ---------- filing (the old filePlan and importFlight)
/** Each outbound with its return: the first leg not yet used, and the first later one flying back with a number one
 *  apart, as filePlan pairs them; a leg with no return stays alone. Indexes into the legs. */
export function pairLegs(legs: readonly { no: string; from: string; to: string }[]): [number, number | null][] {
  const used = new Set<string>();
  const out: [number, number | null][] = [];
  legs.forEach((a, i) => {
    if (used.has(a.no)) return;
    const j = legs.findIndex((x) => !used.has(x.no) && x.no !== a.no && x.from === a.to && x.to === a.from && Math.abs(Number(x.no) - Number(a.no)) === 1);
    used.add(a.no);
    if (j >= 0) used.add((legs[j] as { no: string }).no);
    out.push([i, j >= 0 ? j : null]);
  });
  return out;
}

/** A frequency's id made as the old importFlight makes one: "f", the moment in base 36, three random letters. */
export const fileKey = (nowMs: number, rand: () => number = Math.random): string => "f" + nowMs.toString(36) + (rand().toString(36) + "000").slice(2, 5);

export interface FileFlight { no: string; from: string; to: string; dep: string; arr: string; days: string }
export interface FilingInput {
  worldId: number;
  today: string;
  nowMs: number;
  rand?: () => number;
  rules: Rules;
  aircraft: TailAircraft;
  card: PlanCardRow;
  /** The card's legs in local time, with the game's times in place when filing with them. */
  legs: readonly CardLeg[];
  /** The game's flight for each leg (by its index), when filing with the game's times. */
  game: readonly (GameFlight | null)[] | null;
  /** The cabin its first fit is logged with: the order's own, else order_cabin(); null when there is none. */
  cabin: { code: string; cost: number | null } | null;
  /** Whether a first cabin fit is logged for it already (a cabin row whose note starts with its registration). */
  cabinLogged: boolean;
  /** Its place in the old planner's list of tails: how many aircraft have one. */
  tailsIndex: number;
  /** The airline's bases, its routes (removed ones too), markets and service profiles. */
  bases: readonly string[];
  routes: readonly RouteRow[];
  markets: ReadonlyMap<number, MarketRow>;
  profiles: readonly ServiceProfile[];
  /** Airports a route to add needs (its city, country and position). */
  airports: ReadonlyMap<string, AirportInfo>;
}

const clockMin = (s: string): number | null => time.parseClock(s);

/** Filing as one action: the aircraft in service (status active, its base and cabin, its place in the list of tails), its
 *  first cabin fit in spending_log, each outbound and its return as a rotation with its two legs (a route added where
 *  the airline has none), and, filing with the game's times, the plan card's legs taking them. */
export function filingChanges(x: FilingInput): Change[] {
  const out: Change[] = [];
  const a = x.aircraft;
  const reg = a.registration;
  // the aircraft, as the old planner's tail ({id, airline, type, config: the order's cabin, base: the card's or the order's})
  if (a.status !== "active") {
    const values: Values = { status: "active" };
    const base = x.card.base_code || a.order_base_code || null;
    if ((a.base_code ?? null) !== base) values.base_code = base;
    if ((a.cabin_config_id ?? null) !== (a.order_config_id ?? null)) values.cabin_config_id = a.order_config_id ?? null;
    if (a.retired_on != null) values.retired_on = null;
    for (const k of ["checked_on", "schedule_changed_on", "maintenance_note"] as const) if (a[k] != null) values[k] = null;
    const extra = { ...(isObj(a.extra) ? a.extra : {}) };
    extra.tails_index = x.tailsIndex;
    values.extra = extra;
    out.push({ table: "aircraft", op: "update", key: { id: a.id }, base: a.updated_at, values });
    if (x.cabin && x.cabin.cost && !x.cabinLogged) {
      out.push({ table: "spending_log", op: "insert", values: {
        world_id: x.worldId, airline_id: a.airline_id, spent_on: x.today, amount: Number(x.cabin.cost), kind: "cabin", aircraft_id: a.id,
        note: `${reg} first cabin fit (${x.cabin.code})` } });
    }
  }
  // the flights: as filed with the game's times, the legs take them
  const flights: FileFlight[] = x.legs.map((L, i) => {
    const g = x.game?.[i] ?? null;
    return g ? { no: L.no, from: L.from, to: L.to, dep: g.dep, arr: g.arr || L.arr, days: g.days ? sortDays(g.days) : L.days }
      : { no: L.no, from: L.from, to: L.to, dep: L.dep, arr: L.arr, days: L.days };
  });
  const hubs = new Set(x.bases);
  const live = x.routes.filter((r) => !r.removed);
  const added = new Map<string, string>();   // routes added in this action: hub|dest → its name
  let n = 0;
  for (const [i, j] of pairLegs(flights)) {
    let o = flights[i] as FileFlight, b = j == null ? null : flights[j] as FileFlight;
    if (!hubs.has(o.from) && b && hubs.has(b.from)) [o, b] = [b, o];
    let route = live.find((r) => r.hub_code === o.from && r.dest_code === o.to);
    if (!route && b) {
      const rev = live.find((r) => r.hub_code === o.to && r.dest_code === o.from);
      if (rev) {
        [o, b] = [b, o];
        route = rev;
      }
    }
    n++;
    const rotName = `rotation ${n}`;
    const rot: Change = { table: "rotations", op: "insert", as: rotName, values: {
      world_id: x.worldId, airline_id: a.airline_id, legacy_key: fileKey(x.nowMs, x.rand), launched_on: x.today } };
    let distance: number | null;
    const values = rot.values as Values;
    if (route) {
      const r = routeOf(route, x.markets);
      values.route_id = route.id;
      values.service_code = service.profileFor(x.profiles, a.airline_id, r.dist)?.code || null;
      values.fare_pct = priceFor(r, x.markets);
      distance = r.dist;
    } else {
      // a route the airline doesn't have: added as the old importFlight adds it (city and country from the airport list,
      // the great-circle distance, no market, 3 stars), or a removed one brought back
      const key = `${o.from}|${o.to}`;
      let name = added.get(key);
      const ad = x.airports.get(o.to), ah = x.airports.get(o.from);
      distance = block.greatCircleBetween(ah, ad) ?? 0;
      if (!name) {
        name = `route ${added.size + 1}`;
        added.set(key, name);
        const existing = x.routes.find((r) => r.hub_code === o.from && r.dest_code === o.to) ?? null;
        const ch = addRouteChanges(x.worldId, a.airline_id, o.from, o.to, { city: ad?.city ?? o.to, country: ad?.country_name ?? ad?.country_code ?? null, km: distance, marketId: null },
          existing, false);
        const last = ch[ch.length - 1] as Change;
        if (!existing) last.as = name;
        out.push(...ch);
        if (existing) added.set(key, `id:${existing.id}`);
      }
      const named = added.get(key) as string;
      if (named.startsWith("id:")) values.route_id = Number(named.slice(3));
      else rot.from = { route_id: named };
      values.service_code = service.profileFor(x.profiles, a.airline_id, distance)?.code || null;
      values.fare_pct = null;
    }
    out.push(rot);
    const local: LocalTimes = {
      days: frequency.weekdays(o.days || "1234567"), dep_hub: clockMin(o.dep), arr_dest: clockMin(o.arr),
      dep_dest: b ? clockMin(b.dep) : null, arr_hub: b ? clockMin(b.arr) : null,
    };
    const ends = { airline_id: a.airline_id, hub: o.from, dest: o.to, distance_km: distance, type_id: a.aircraft_type_id };
    const { leg1, leg2 } = frequency.toLegs(x.rules, ends, local);
    const legRow = (k: 1 | 2, s: typeof leg1, no: string): Change => ({
      table: "flight_legs", op: "insert", from: { rotation_id: rotName }, values: {
        world_id: x.worldId, airline_id: a.airline_id, leg_no: k, flight_no: no === "" ? null : Number(no), origin_code: k === 1 ? o.from : o.to,
        dest_code: k === 1 ? o.to : o.from, aircraft_id: a.id, days_utc: s.days_utc, dep_utc_min: s.dep_utc_min, block_min: s.block_min } });
    out.push(legRow(1, leg1, o.no), legRow(2, leg2, b ? b.no : ""));
  }
  // the plan card takes the game's times: each leg's departure, arrival (its block) and days, in UTC
  if (x.game) {
    x.legs.forEach((L, i) => {
      const g = x.game?.[i];
      if (!g) return;
      const dep = clockMin(g.dep);
      if (dep == null) return;
      const days = frequency.weekdays(g.days ? sortDays(g.days) : L.days);
      const u = time.fromLocal(x.rules, L.from, days, dep);
      const values: Values = {};
      if (u.dep_utc_min !== L.row.dep_utc_min) values.dep_utc_min = u.dep_utc_min;
      if (JSON.stringify(u.days_utc) !== JSON.stringify([...(L.row.days_utc ?? [])].sort((p, q) => p - q))) values.days_utc = u.days_utc;
      const arr = g.arr ? clockMin(g.arr) : null;
      if (arr != null) {
        const blk = time.mod(arr - dep - (time.utcOffsetMin(x.rules, L.to) - time.utcOffsetMin(x.rules, L.from)), time.DAY);
        if (blk !== L.row.block_min) values.block_min = blk;
      }
      if (Object.keys(values).length) out.push({ table: "plan_card_legs", op: "update", key: { id: L.row.id }, base: L.row.updated_at, values });
    });
    // a copy of the card's typed legs the old planner's storage keeps (extra.legs, which the old planner shows instead of
    // the leg rows) is out of date once they change: it goes, and the old planner reads the legs from their rows. (The old
    // planner's own save writes the copy afresh instead; the new planner keeps the times and days in the rows only.)
    const changed = x.legs.some((L, i) => { const g = x.game?.[i]; return !!g && !sameTimes(L, g); });
    if (changed && isObj(x.card.extra) && "legs" in x.card.extra) {
      const extra = { ...x.card.extra };
      delete extra.legs;
      out.push({ table: "plan_cards", op: "update", key: { id: x.card.id }, base: x.card.updated_at, values: { extra } });
    }
  }
  return out;
}

// ---------- the other actions on an aircraft
export type TailField = "id" | "type" | "base" | "config" | "maint" | "notes";
export type ChangeAnswer = { changes: Change[] } | { error: string };

/** Add a tail (the old t-add): a new aircraft in service at the end of the list of tails; a registration that's retired
 *  comes back (the old planner's save brought it back the same way). */
export function addTailChanges(worldId: number, airlineId: number, typed: { id: string; type: string; config: string; base: string }, rules: Rules,
  configs: readonly ConfigRow[], aircraft: readonly TailAircraft[], tailsIndex: number): ChangeAnswer {
  const reg = typed.id.trim();
  if (!reg) return { changes: [] };
  const have = aircraft.find((a) => a.registration === reg);
  if (have && have.status !== "retired") return { error: "That tail id exists." };
  const type = [...rules.types.values()].filter((t) => t.name === typed.type).sort((p, q) => p.id - q.id)[0];
  const cfg = configs.filter((c) => c.code === typed.config).sort((p, q) => p.id - q.id)[0];
  const values: Values = {
    airline_id: airlineId, aircraft_type_id: type?.id ?? null, cabin_config_id: cfg?.id ?? null, base_code: typed.base || null, status: "active",
  };
  if (have) {
    return { changes: [{ table: "aircraft", op: "update", key: { id: have.id }, base: have.updated_at, values: {
      ...values, retired_on: null, extra: { ...(isObj(have.extra) ? have.extra : {}), tails_index: tailsIndex } } }] };
  }
  return { changes: [{ table: "aircraft", op: "insert", values: { world_id: worldId, registration: reg, ...values, extra: { tails_index: tailsIndex } } }] };
}

/** One field of an aircraft's page changed (the old data-tk): its one row. */
export function editTailChange(a: TailAircraft, field: TailField, typed: string, ctx: {
  rules: Rules; configs: readonly ConfigRow[]; aircraft: readonly TailAircraft[]; airline: Pick<TailAirline, "is_lcc">;
}): ChangeAnswer {
  const one = (values: Values): ChangeAnswer => ({ changes: [{ table: "aircraft", op: "update", key: { id: a.id }, base: a.updated_at, values }] });
  if (field === "id") {
    const nid = typed.trim().toUpperCase();
    if (!nid || nid === a.registration) return { changes: [] };
    if (ctx.aircraft.some((x) => x.registration === nid)) return { error: "That registration already exists." };
    return one({ registration: nid });
  }
  if (field === "type") {
    const type = [...ctx.rules.types.values()].filter((t) => t.name === typed).sort((p, q) => p.id - q.id)[0];
    const id = type?.id ?? null;
    const values: Values = {};
    if (id !== a.aircraft_type_id) values.aircraft_type_id = id;
    // the cabin follows: kept if the new type has it, else the only one it has, else none
    const ok = configsFor(ctx.rules, ctx.configs, ctx.airline, typed);
    const now = ctx.configs.find((c) => c.id === a.cabin_config_id)?.code ?? "";
    if (!ok.includes(now)) {
      const code = ok.length === 1 ? ok[0] : "";
      const cfg = ctx.configs.filter((c) => c.code === code).sort((p, q) => p.id - q.id)[0];
      if ((cfg?.id ?? null) !== a.cabin_config_id) values.cabin_config_id = cfg?.id ?? null;
    }
    return Object.keys(values).length ? one(values) : { changes: [] };
  }
  if (field === "config") {
    const cfg = ctx.configs.filter((c) => c.code === typed).sort((p, q) => p.id - q.id)[0];
    const id = cfg?.id ?? null;
    return id === a.cabin_config_id ? { changes: [] } : one({ cabin_config_id: id });
  }
  if (field === "base") {
    const v = typed || null;
    return v === a.base_code ? { changes: [] } : one({ base_code: v });
  }
  if (field === "maint") {
    const v = typed === "" ? null : typed;
    return v === a.maintenance_note ? { changes: [] } : one({ maintenance_note: v });
  }
  const extra = { ...(isObj(a.extra) ? a.extra : {}) };
  const tail = { ...(isObj(extra.tail) ? extra.tail : {}) };
  if ((typeof tail.notes === "string" ? tail.notes : "") === typed) return { changes: [] };
  if (typed) tail.notes = typed;
  else delete tail.notes;
  if (Object.keys(tail).length) extra.tail = tail;
  else delete extra.tail;
  return one({ extra });
}

const OLD_LISTS = ["tails_index", "deliveries_index", "tail", "delivery"];
/** Remove an aircraft: retired today, never deleted, and out of the old planner's two lists. */
function retire(a: TailAircraft, today: string): Change {
  const extra = { ...(isObj(a.extra) ? a.extra : {}) };
  for (const k of OLD_LISTS) delete extra[k];
  return { table: "aircraft", op: "update", key: { id: a.id }, base: a.updated_at, values: { status: "retired", retired_on: today, extra } };
}
/** The list's remove (the old data-deltail): refused while it flies a route. */
export function removeTailChanges(a: TailAircraft, flies: boolean, today: string): ChangeAnswer {
  if (flies) return { error: "This tail still flies routes. Reassign them first." };
  return { changes: [retire(a, today)] };
}
/** The page's Delete aircraft… (the old data-tdel): its rotations and their legs go, and it is retired, as one action. */
export function deleteTailChanges(a: TailAircraft, rotations: readonly { id: number; updated_at: string; legs: readonly { id: number; updated_at: string }[] }[],
  today: string): Change[] {
  return [
    ...rotations.flatMap((r) => r.legs.map((l): Change => ({ table: "flight_legs", op: "delete", key: { id: l.id }, base: l.updated_at }))),
    ...rotations.map((r): Change => ({ table: "rotations", op: "delete", key: { id: r.id }, base: r.updated_at })),
    retire(a, today),
  ];
}
/** Mark checked (the old tmcheck): the one-week check done today. */
export const markCheckedChange = (a: TailAircraft, today: string): Change =>
  ({ table: "aircraft", op: "update", key: { id: a.id }, base: a.updated_at, values: { checked_on: today } });
