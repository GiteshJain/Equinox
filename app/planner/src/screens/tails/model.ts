// The Tails screen's logic (decision #18, build pull request 7; spec docs/specs/2026-10-13-tails.md): the list and its
// filters as the old renderTailsCore, an aircraft's page as renderTailDetail (its week strip, its legs by flight number,
// its issues), the deliveries board as deliveryRows and renderDeliveries, a plan card as planCard, the check against the
// game before filing (checkBeforeFile), and every action as one planner_save() call: add, edit and remove an aircraft,
// and filing (filePlan and importFlight); Mark checked went with the one-week checks on 22 Oct. No screen code, so the
// unit tests run it. Every planning figure is the library's (aircraftWeek, maintenance, tails, frequency, time); this
// file joins the tables' rows to it and words what it answers, as the old planner words it.
import {
  RulesError, aircraftWeek, banks, block, buildRules, card as cardRules, frequency, game, maintenance, service, setting, tails, time, type AircraftWeek, type AirportRow,
  type CabinSuggestion, type CardCheck as LibCardCheck, type CheckRow as LibCheckRow, type FareLadder, type GameFlight as LibGameFlight, type LocalTimes, type Maintenance,
  type NoMaintenance, type RouteFare, type Rules, type ServiceProfile, type TailIssue, type TimedLeg, type WeekLeg,
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
  /** How we got it, new from the factory or used from the game's Aircraft Market (since 22 Oct, manual §3); it decides
   *  the replacement age. Optional so a row made in the planner before it's read again still types. */
  acquired?: string;
}
export const AIRCRAFT_COLUMNS = "id, registration, airline_id, aircraft_type_id, cabin_config_id, base_code, status, ordered_on, delivery_at, "
  + "order_base_code, order_config_id, order_note, checked_on, schedule_changed_on, maintenance_note, retired_on, extra, updated_at, acquired";

/** The pop-up's line on how the aircraft came and when it's replaced (manual §3, replacement by age; spec
 *  docs/specs/2026-10-22-aircraft-age-check.md §2): "came new, replace at 3 years", "came used, replace at 10 years",
 *  the ages from settings.replace_new_years and replace_used_years (an airline's own where it has one); without the
 *  setting, just how it came. */
export function acquiredWords(rules: Rules, a: Pick<TailAircraft, "airline_id" | "acquired">): string {
  const used = a.acquired === "used";
  const n = Number(setting(rules, used ? "replace_used_years" : "replace_new_years", a.airline_id));
  return `came ${used ? "used" : "new"}${Number.isFinite(n) && n > 0 ? `, replace at ${n} years` : ""}`;
}

export interface ConfigRow { id: number; code: string; aircraft_type_id: number | null; cabin: string | null; cost: number | null }
export interface BuyTypeRow { airline_id: number; aircraft_type_id: number }
/** A plan card: its legs are its plan_card_legs rows (the old planner's copy of them in extra.legs went with the clean-up,
 *  build pull request 14). */
/** A plan card. config_id is the cabin chosen with its routes (since 18 Oct): filing fits it and logs its first fit. */
export interface PlanCardRow { id: number; airline_id: number; aircraft_id: number; base_code: string | null; title: string | null; note: string | null; config_id?: number | null; updated_at: string }
export const PLAN_CARD_COLUMNS = "id, airline_id, aircraft_id, base_code, title, note, config_id, updated_at";
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
/** Whether an aircraft is on the deliveries board: it has a delivery and isn't retired (the old planner's list of
 *  deliveries, whose places the clean-up cleared from aircraft.extra, build pull request 14). */
export const onDeliveries = (a: Pick<TailAircraft, "delivery_at" | "status">): boolean => !!a.delivery_at && a.status !== "retired";
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

// ---------- the game's maintenance in place of the estimate (since 23 Oct, spec
// docs/specs/2026-10-23-game-maintenance-on-tails.md): an aircraft on the latest night's fleet pages (fleet_checks()) shows
// and is judged on the game's figure, with no ≈; any other keeps the planner's estimate. Plan cards and what-ifs keep the
// estimate: the game has no figure for a schedule it isn't flying yet.
/** The game's figure for an aircraft (systems' gameMaintenance()): as the game shows it, and the night it was read. */
export interface GameMaintFigure { pct: number; night: string | null }
/** The maintenance a screen shows for an aircraft: the game's or the estimate's, its whole percent and its class. */
export interface ShownMaint { from: "game" | "estimate"; pct: number; level: "ok" | "warn" | "bad"; min_pct: number; target_pct: number; title: string }
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** A night as the fleet board writes it: "22 Oct"; "" without one. */
const nightDay = (night: string | null | undefined): string => {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(night ?? ""));
  return m ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1] ?? ""}` : "";
};
/** The tooltip on the game's figure: "In the game, last night's capture (22 Oct)". */
export const gameMaintTitle = (night: string | null | undefined): string => `In the game, last night's capture${nightDay(night) ? ` (${nightDay(night)})` : ""}`;
/** The estimate's tooltip: the hours behind it. */
const estimateTitle = (m: Maintenance): string =>
  `Estimated maintenance ratio: ${hhmm(Math.round(m.have_min_day))} of usable ground time a day against about ${hhmm(Math.round(m.need_min_day))} needed`;
/** The maintenance shown for an aircraft: the game's when it has one (its class from settings.maintenance_min_pct and
 *  maintenance_target_pct, the airline's own where it has one: bad under the minimum, warn under the target, ok
 *  otherwise), else the estimate's; null when neither has a figure. */
export function shownMaint(rules: Rules, airlineId: number | null, est: Maintenance | NoMaintenance | null | undefined,
  game: GameMaintFigure | null | undefined): ShownMaint | null {
  if (game && Number.isFinite(game.pct)) {
    const min = Number(setting(rules, "maintenance_min_pct", airlineId)), target = Number(setting(rules, "maintenance_target_pct", airlineId));
    if (Number.isFinite(min) && Number.isFinite(target)) {
      return { from: "game", pct: Math.round(game.pct), level: game.pct < min ? "bad" : game.pct < target ? "warn" : "ok", min_pct: min, target_pct: target,
        title: gameMaintTitle(game.night) };
    }
  }
  if (!est || est.ratio == null || !("level" in est)) return null;
  return { from: "estimate", pct: est.pct, level: est.level, min_pct: est.min_pct, target_pct: est.target_pct, title: estimateTitle(est) };
}
/** A shown figure's words: "106%" from the game, "≈106%" for the estimate, "400+" above 400 either way. */
export const shownMaintText = (m: Pick<ShownMaint, "from" | "pct">): string => `${m.from === "game" ? "" : "≈"}${m.pct > 400 ? "400+" : m.pct}%`;
/** The Maint. column's pill for a shown figure. */
export function shownPill(m: ShownMaint | null): { text: string; cls: "ok" | "warn" | "bad"; title: string } | null {
  return m ? { text: shownMaintText(m), cls: m.level, title: m.title } : null;
}
/** An issue as Tails words it: the library's, a maintenance one marked when it is the game's figure (no ≈). */
export type ShownIssue = TailIssue & { game?: boolean };
/** An aircraft's issues with its maintenance judged on the shown figure: the estimate's maintenance issue gives way to
 *  the game's (none when the game's is fine), in the same place (after the short turns). */
export function issuesShown(issues: readonly TailIssue[], m: ShownMaint | null): ShownIssue[] {
  if (!m || m.from !== "game") return [...issues];
  const out: ShownIssue[] = issues.filter((i) => i.kind !== "maintenance");
  if (m.level === "ok") return out;
  const at = out.findIndex((i) => i.kind !== "block_hours" && i.kind !== "short_turns");
  const issue: ShownIssue = { kind: "maintenance", level: m.level, pct: m.pct, min_pct: m.min_pct, target_pct: m.target_pct, game: true };
  out.splice(at < 0 ? out.length : at, 0, issue);
  return out;
}

/** An issue in the old tailIssues' words; the game's maintenance without ≈ (since 23 Oct). */
export function issueWords(i: ShownIssue): string {
  const s = (n: number) => (n > 1 ? "s" : "");
  switch (i.kind) {
    case "block_hours": return `flies ${i.block_hours_day.toFixed(1)} h a day — under the ${i.target_h} h target`;
    case "short_turns": return `${i.count} short turn${s(i.count)} a week`;
    case "maintenance": {
      const p = "game" in i && i.game ? `${i.pct}%` : `≈${i.pct}%`;
      return i.level === "bad" ? `maintenance ${p} — under ${i.min_pct}%, condition will fall` : `maintenance ${p} — little headroom`;
    }
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

/** The airline's tails (status active), in the order they were added (id). The old planner's list order went with its
 *  places in aircraft.extra at the clean-up (build pull request 14). */
export function tailsOf(aircraft: readonly TailAircraft[], airlineId: number | undefined): TailAircraft[] {
  return aircraft.filter((a) => a.airline_id === airlineId && a.status === "active").sort((a, b) => a.id - b.id);
}

/** A row of the list; maint is the Maint. column's figure: the game's for an aircraft on the latest fleet pages, else
 *  the estimate (since 23 Oct). */
export interface TailRow { a: TailAircraft; type: string; config: string; base: string; fig: TailFigures; maint: ShownMaint | null }

/** The list as renderTailsCore shows it: the airline's tails with the base, type and status filters; with the game's
 *  maintenance by aircraft id (systems' gameMaintenance()), each row's Maint. figure is the game's where it has one. */
export function tailRows(mine: readonly TailAircraft[], f: Pick<Filters, "base" | "type" | "status">, rules: Rules, configs: ReadonlyMap<number, ConfigRow>,
  game?: ReadonlyMap<number, GameMaintFigure>): TailRow[] {
  const legs = rulesLegs(rules);
  const out: TailRow[] = [];
  for (const a of mine) {
    const fig = figuresOf(rules, a.id, legs);
    const row = { a, type: typeName(rules, a.aircraft_type_id), config: configCode(configs, a.cabin_config_id), base: a.base_code ?? "", fig,
      maint: shownMaint(rules, a.airline_id, fig.maint, game?.get(a.id)) };
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
/** The airports where an airline has a station (18 Oct): its bases, and every airport its scheduled flights touch. An
 *  airport on a plan card outside this set needs a new station in the game. */
/** The airports where the airline has an active route: every airport its flights touch (legs that fly on at least one day,
 *  on no aircraft or one not retired). Since 22 Oct (Gitesh) its bases no longer count on their own: an airline_bases
 *  row, a point-to-point station especially (role station, manual §2), is a plan, not a station in the game, so a plan
 *  card highlights any airport the airline doesn't fly yet, base or not. */
export function stationsOf(rules: Rules, airlineId: number): Set<string> {
  const s = new Set<string>();
  for (const l of rules.legs) {
    if (l.airline_id !== airlineId || !l.days_utc.length) continue;
    const a = l.aircraft_id == null ? undefined : rules.aircraft.get(l.aircraft_id);
    if (a && a.status === "retired") continue;
    s.add(l.origin_code); s.add(l.dest_code);
  }
  return s;
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
  /** The cabin it will be fitted with: its plan card's, else its order's; "" when neither names one. */
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
  // every aircraft with a delivery that isn't retired, in the order they were added (removing a delivery clears its date)
  return aircraft.filter(onDeliveries).sort((a, b) => a.id - b.id)
    .map((a): DeliveryRow => {
      // to the minute, as the old planner's documents kept delivery times
      const at = toMinute(String(a.delivery_at));
      const ok = Number.isFinite(at);
      const due = ok ? new Date(at).toISOString().slice(0, 10) : "";
      const arrived = ok ? at <= now : !!due && due <= today;
      return {
        a, airline: airlines.find((x) => x.id === a.airline_id), type: typeName(rules, a.aircraft_type_id), config: configCode(configs, cardOf.get(a.id)?.config_id ?? a.order_config_id),
        // the plan card's title (since 19 Oct the card is written with the order, and the order carries no note), else the
        // old order note without its "lands …" part
        at, due, hrs: ok ? (at - now) / 36e5 : null, base: a.order_base_code ?? "",
        plan: cardOf.get(a.id)?.title?.trim() || String(a.order_note ?? "").replace(/^lands [^·]+· /, ""),
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
/** The rules with an airline's routes the start doesn't carry (a plan card's new route), with any distance override, and
 *  since 21 Oct each one's market (any override applied), its market's layout and its own cabin choice, for the plan
 *  card's cabin (markets: name and layout; none given, no market). */
export function withRoutes(rules: Rules, routes: readonly RouteRow[], markets: readonly MarketRow[] = []): Rules {
  const have = new Set(rules.input.routes.map((r) => r.id));
  const byId = new Map(markets.map((m) => [m.id, m]));
  const extra = routes.filter((r) => !have.has(r.id) && !r.removed).map((r) => {
    const marketId = r.market_cleared ? null : r.market_override_id ?? r.market_id;
    const m = marketId == null ? undefined : byId.get(marketId);
    return {
      id: r.id, airline_id: r.airline_id, hub_code: r.hub_code, dest_code: r.dest_code, distance_km: r.distance_override_km ?? r.distance_km,
      market_id: m ? m.id : null, market: m?.name ?? null, market_layout: m?.layout ?? null, cabin_choice: r.cabin_choice ?? null,
    };
  });
  return extra.length ? buildRules({ ...rules.input, routes: [...rules.input.routes, ...extra] }) : rules;
}

// ---------- the plan card's cabin (manual §5; spec docs/specs/2026-10-21-cabins-new-rule.md §3): the library's
// card.cabinFor on the card's legs, with the airline's routes laid in (withRoutes)
/** The cabin the card's routes call for, or null when it can't be worked out (an aircraft without a type, a missing
 *  setting): the suggestion, its reason, and whether the card's own cabin is missing or differs. */
export function cardCabin(rules: Rules, card: Pick<PlanCardRow, "aircraft_id" | "config_id">, legs: readonly PlanLegRow[]): CabinSuggestion | null {
  try {
    return cardRules.cabinFor(rules, {
      aircraft: card.aircraft_id, config_id: card.config_id ?? null,
      legs: [...legs].sort((a, b) => a.position - b.position).map((l) => ({
        flight_no: l.flight_no, origin_code: l.origin_code, dest_code: l.dest_code, days_utc: l.days_utc, dep_utc_min: l.dep_utc_min, block_min: l.block_min,
      })),
    });
  } catch (e) {
    if (e instanceof RulesError) return null;
    throw e;
  }
}
// ---------- the plan card's fares (manual §5, since 21 Oct; spec docs/specs/2026-10-21-frequencies-and-fares.md §2): the
// library's card.cardFares on the card's legs, from fare_ladder()'s answer for the card's airline; nothing is stored on
// the card
/** Each route the card flies with its fare level, once per route in the order of its legs; null when it can't be worked
 *  out (no ladder yet, an aircraft without a type, a missing setting). */
export function cardFareLevels(rules: Rules, card: Pick<PlanCardRow, "aircraft_id" | "config_id">, legs: readonly PlanLegRow[], ladder: FareLadder | null | undefined): RouteFare[] | null {
  if (!ladder) return null;
  try {
    return cardRules.cardFares(rules, {
      aircraft: card.aircraft_id, config_id: card.config_id ?? null,
      legs: [...legs].sort((a, b) => a.position - b.position).map((l) => ({ flight_no: l.flight_no, origin_code: l.origin_code, dest_code: l.dest_code })),
    }, ladder);
  } catch (e) {
    if (e instanceof RulesError) return null;
    throw e;
  }
}
/** The card's Fare column: each route's fare level on the first of its legs on the card (by the leg's row id), so each
 *  route shows once ("economy +10%, business +5% of the default price", "launch (+0% of the default price)"). */
export function fareCells(legs: readonly CardLeg[], fares: readonly RouteFare[] | null): Map<number, string> {
  const out = new Map<number, string>();
  if (!fares) return out;
  const pair = (a: string, b: string) => [a, b].sort().join("|");
  const byPair = new Map(fares.map((f) => [pair(...(f.route.split("–") as [string, string])), f]));
  const done = new Set<string>();
  for (const L of legs) {
    const k = pair(L.from, L.to);
    const f = byPair.get(k);
    if (!f || done.has(k)) continue;
    done.add(k);
    out.set(L.row.id, f.words);
  }
  return out;
}
/** The suggestion beside the card's Cabin box: "suggested: 321-LP", with its reason; null when there's none. */
export function suggestionWords(s: CabinSuggestion | null): { text: string; reason: string } | null {
  return s?.code ? { text: `suggested: ${s.code}`, reason: s.reason } : null;
}
/** Whether a cabin shown on the card (its own, else its order's: a code, "" for none) differs from the suggestion. */
export const cabinDiffers = (s: CabinSuggestion | null, shown: string): boolean => !!s?.code && !!shown && shown !== s.code;
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
  /** The cabin it is fitted with and its first fit logged at (filingCabin(): the card's, else the order's); null when
   *  neither names one, and then the aircraft keeps whatever cabin it has and nothing is logged. */
  cabin: { id?: number; code: string; cost: number | null } | null;
  /** Whether a first cabin fit is logged for it already (a cabin row whose note starts with its registration). */
  cabinLogged: boolean;
  /** The airline's bases, its routes (removed ones too), markets and service profiles. */
  bases: readonly string[];
  routes: readonly RouteRow[];
  markets: ReadonlyMap<number, MarketRow>;
  profiles: readonly ServiceProfile[];
  /** Airports a route to add needs (its city, country and position). */
  airports: ReadonlyMap<string, AirportInfo>;
}

const clockMin = (s: string): number | null => time.parseClock(s);

/** The cabin filing fits and logs (18 Oct): the plan card's, else the order's, else none. Never the airline's default
 *  for the type: the cabin is chosen when the aircraft is planned, and a default would be logged at the wrong price. */
export function filingCabin(card: Pick<PlanCardRow, "config_id"> | null | undefined, a: Pick<TailAircraft, "order_config_id">,
  configs: ReadonlyMap<number, ConfigRow>): { id: number; code: string; cost: number | null; from: "card" | "order" } | null {
  for (const [id, from] of [[card?.config_id, "card"], [a.order_config_id, "order"]] as const) {
    const c = id == null ? undefined : configs.get(id);
    if (c) return { id: c.id, code: c.code, cost: c.cost, from };
  }
  return null;
}
/** Choosing a plan card's cabin (or clearing it): one planner_save() change on the card. */
export function cardCabinChange(card: PlanCardRow, configId: number | null): Change[] {
  return (card.config_id ?? null) === configId ? []
    : [{ table: "plan_cards", op: "update", key: { id: card.id }, base: card.updated_at, values: { config_id: configId } }];
}

/** Filing as one action: the aircraft in service (status active, its base and cabin), its first cabin fit in
 *  spending_log, each outbound and its return as a rotation with its two legs (a route added where the airline has none),
 *  and, filing with the game's times, the plan card's legs taking them. */
export function filingChanges(x: FilingInput): Change[] {
  const out: Change[] = [];
  const a = x.aircraft;
  const reg = a.registration;
  // the aircraft, as the old planner's tail ({id, airline, type, config: the order's cabin, base: the card's or the order's})
  if (a.status !== "active") {
    const values: Values = { status: "active" };
    const base = x.card.base_code || a.order_base_code || null;
    if ((a.base_code ?? null) !== base) values.base_code = base;
    // its cabin: the one chosen for it (the card's, else the order's); with none chosen it keeps what it has
    if (x.cabin?.id != null && a.cabin_config_id !== x.cabin.id) values.cabin_config_id = x.cabin.id;
    if (a.retired_on != null) values.retired_on = null;
    for (const k of ["checked_on", "schedule_changed_on", "maintenance_note"] as const) if (a[k] != null) values[k] = null;
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
      values.fare_pct = priceFor(x.rules, r);
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
  }
  return out;
}

// ---------- the other actions on an aircraft
export type TailField = "id" | "type" | "base" | "config" | "maint" | "notes";
export type ChangeAnswer = { changes: Change[] } | { error: string };

/** Add a tail (the old t-add): a new aircraft in service; a registration that's retired comes back (the old planner's save
 *  brought it back the same way). */
export function addTailChanges(worldId: number, airlineId: number, typed: { id: string; type: string; config: string; base: string }, rules: Rules,
  configs: readonly ConfigRow[], aircraft: readonly TailAircraft[]): ChangeAnswer {
  const reg = typed.id.trim();
  if (!reg) return { changes: [] };
  const have = aircraft.find((a) => a.registration === reg);
  if (have && have.status !== "retired") return { error: "That tail id exists." };
  const type = [...rules.types.values()].filter((t) => t.name === typed.type).sort((p, q) => p.id - q.id)[0];
  const cfg = configs.filter((c) => c.code === typed.config).sort((p, q) => p.id - q.id)[0];
  const values: Values = {
    airline_id: airlineId, aircraft_type_id: type?.id ?? null, cabin_config_id: cfg?.id ?? null, base_code: typed.base || null, status: "active",
  };
  if (have) return { changes: [{ table: "aircraft", op: "update", key: { id: have.id }, base: have.updated_at, values: { ...values, retired_on: null } }] };
  return { changes: [{ table: "aircraft", op: "insert", values: { world_id: worldId, registration: reg, ...values } }] };
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

/** Remove an aircraft: retired today, never deleted. */
function retire(a: TailAircraft, today: string): Change {
  return { table: "aircraft", op: "update", key: { id: a.id }, base: a.updated_at, values: { status: "retired", retired_on: today } };
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
/** What the old adapter looked at when an aircraft left the deliveries (planner_apply_tidy): whether it has money in the
 *  capture or in money spent (then it's retired), and whether anything else points at it (then it stays). */
export interface RemovalFacts { money: boolean; pointedAt: boolean }

/** Remove a delivery (the old data-deldel): the aircraft leaves the deliveries board. In service, its order's fields are
 *  cleared; otherwise it's retired today when the capture or money spent knows it, removed when nothing points at it (no
 *  flights, plan card or kept cabin), and else it keeps its row with its order's fields cleared, so it leaves the board as
 *  it left the old planner's list of deliveries. (Until the clean-up, build pull request 14, the board was that list,
 *  kept as places in aircraft.extra, which this renumbered.) */
export function removeDeliveryChanges(a: TailAircraft, facts: RemovalFacts, today: string): Change[] {
  const key = { id: a.id };
  const order: Values = { ordered_on: null, delivery_at: null, order_base_code: null, order_config_id: null, order_note: null };
  if (a.status === "active") return [{ table: "aircraft", op: "update", key, base: a.updated_at, values: order }];
  if (facts.money) return [{ table: "aircraft", op: "update", key, base: a.updated_at, values: { status: "retired", retired_on: a.retired_on ?? today } }];
  if (!facts.pointedAt) return [{ table: "aircraft", op: "delete", key, base: a.updated_at }];
  return [{ table: "aircraft", op: "update", key, base: a.updated_at, values: order }];
}

