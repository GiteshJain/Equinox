// Interline's rows and words (the old planner's interlineRows, ilClass and renderInterline; spec
// docs/specs/2026-10-14-interline-photos-reference.md). Plain data in, plain data out, so the unit tests can run it.
// - The rules are the setting interline_rules (manual §6; the old IL_YES, EUROPE_ZONE, IL_RIVAL, IL_COVER and IL_PARTNERS,
//   given a home by migration 20261014180000): a country with a group base is never an interline country, nor one in the
//   Europe zone, nor any for an airline that signs only inside the group (Ryanair), nor a hub rival's, nor one another of
//   our airlines covers; of the rest, the countries with a real domestic network or a regional gateway are.
// - One row per airline and interline country it flies into (its rotations, in id order: each route's destination, then its
//   hub) or has planned (the plan cards of its aircraft not yet in service, in the old planner's order of their
//   registrations), with the airports and the round trips a day there; airlines in their order, most round trips first.
// - Each row's record is its interline_agreements row; an edit writes that row as the old planner's adapter does (to_sign
//   for the old "requested", a row with nothing in it removed).
import type { Json } from "../../db/types";
import type { Change } from "../../data/save";

export type IlKind = "base" | "europe" | "group" | "rival" | "covered" | "interline" | "nonet";
export interface IlRules {
  /** The interline countries and why: domestic or gateway. */
  countries: Record<string, string>;
  europe_zone: string[];
  rivals: string[];
  /** The countries each of our airlines covers, by airline code. */
  covered: Record<string, string[]>;
  /** Airlines that sign with no one outside the group, by code. */
  group_only: string[];
  /** The partners in the game, by country: name and the game's enterprise id. */
  partners: Record<string, { name: string; game_id: number }[]>;
}
export interface IlAirline { id: number; code: string | null; name: string; color: string | null }

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const strs = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);

/** The setting interline_rules as the screen uses it, or null when the settings have none. */
export function parseRules(v: Json | undefined): IlRules | null {
  if (!isObj(v) || !isObj(v.countries)) return null;
  const covered: Record<string, string[]> = {};
  for (const [k, x] of Object.entries(isObj(v.covered) ? v.covered : {})) covered[k] = strs(x);
  const partners: IlRules["partners"] = {};
  for (const [k, x] of Object.entries(isObj(v.partners) ? v.partners : {})) {
    partners[k] = (Array.isArray(x) ? (x as unknown[]) : []).filter(isObj).map((q) => ({ name: String(q.name ?? ""), game_id: Number(q.game_id) }));
  }
  return {
    countries: Object.fromEntries(Object.entries(v.countries).filter(([, w]) => typeof w === "string")) as Record<string, string>,
    europe_zone: strs(v.europe_zone), rivals: strs(v.rivals), covered, group_only: strs(v.group_only), partners,
  };
}

/** How the group treats a country for an airline (the old ilClass): only "interline" countries get rows. */
export function classify(cc: string, airline: Pick<IlAirline, "code" | "name"> | null, rules: IlRules, home: ReadonlySet<string>,
  nameOf: (code: string) => string): { kind: IlKind; label: string } {
  if (home.has(cc)) return { kind: "base", label: "group base country" };
  if (rules.europe_zone.includes(cc)) return { kind: "europe", label: "Europe zone" };
  if (airline?.code && rules.group_only.includes(airline.code)) return { kind: "group", label: `${airline.name}: group only` };
  if (rules.rivals.includes(cc)) return { kind: "rival", label: "hub rival" };
  const by = Object.entries(rules.covered).find(([, list]) => list.includes(cc));
  if (by) return { kind: "covered", label: "covered by " + nameOf(by[0]) };
  if (rules.countries[cc]) return { kind: "interline", label: "interline · " + rules.countries[cc] };
  return { kind: "nonet", label: "no network" };
}

export interface IlRow {
  airline_id: number;
  cc: string;
  /** The airports there, with round trips a day, in the order first met. */
  airports: Map<string, number>;
  rt_day: number;
  /** Only on plan cards so far. */
  planned: boolean;
}

/** A rotation as the rows need it: its airline, its route's two ends and its outbound's days a week. */
export interface IlRotation { airline_id: number; hub: string; dest: string; days: number }
/** A waiting plan card's legs (its aircraft not yet in service), with the aircraft's airline. */
export interface IlPlan { airline_id: number; registration: string; legs: readonly { from: string | null; to: string | null }[] }

/** The old planner's order of plan cards: its storage kept them under their registrations as JSON keys, which come back
 *  shortest first, then by their characters. */
export const planOrder = (a: string, b: string) => a.length - b.length || (a < b ? -1 : a > b ? 1 : 0);

/** The rows (the old interlineRows), airlines in their order, most round trips first. */
export function interlineRows(x: {
  airlines: readonly IlAirline[]; rotations: readonly IlRotation[]; plans: readonly IlPlan[];
  countryOf: (airport: string) => string | null | undefined; home: ReadonlySet<string>; rules: IlRules; nameOf: (code: string) => string;
}): IlRow[] {
  const rows = new Map<string, IlRow>();
  const byId = new Map(x.airlines.map((a) => [a.id, a]));
  const add = (airlineId: number, ap: string | null, rtDay: number, planned: boolean) => {
    if (!ap) return;
    const cc = x.countryOf(ap);
    const al = byId.get(airlineId);
    if (!cc || !al || classify(cc, al, x.rules, x.home, x.nameOf).kind !== "interline") return;
    const k = airlineId + "|" + cc;
    const r = rows.get(k) ?? { airline_id: airlineId, cc, airports: new Map<string, number>(), rt_day: 0, planned: true };
    rows.set(k, r);
    r.airports.set(ap, (r.airports.get(ap) ?? 0) + rtDay);
    r.rt_day += rtDay;
    if (!planned) r.planned = false;
  };
  for (const f of x.rotations) for (const ap of [f.dest, f.hub]) add(f.airline_id, ap, f.days / 7, false);
  for (const p of [...x.plans].sort((a, b) => planOrder(a.registration, b.registration))) {
    for (const L of p.legs) for (const ap of [L.from, L.to]) add(p.airline_id, ap, 0, true);
  }
  const order = (id: number) => { const i = x.airlines.findIndex((a) => a.id === id); return i < 0 ? x.airlines.length : i; };
  return [...rows.values()].sort((a, b) => order(a.airline_id) - order(b.airline_id) || b.rt_day - a.rt_day);
}

/** A row's airports, most round trips first (the first met first on a tie). */
export const airportsOf = (r: IlRow): string[] => [...r.airports].map((e, i) => ({ e, i })).sort((a, b) => b.e[1] - a.e[1] || a.i - b.i).map((v) => v.e[0]);
/** Round trips a day as the old table wrote them: whole, else one decimal. */
export const rtWords = (n: number): string => (n % 1 ? n.toFixed(1) : String(n));

// ---------- the agreements
export type IlStatus = "none" | "requested" | "signed" | "declined" | "nopartner";
export const IL_STATUS: readonly IlStatus[] = ["none", "requested", "signed", "declined", "nopartner"];
export const STATUS_WORDS: Record<IlStatus, string> = {
  none: "not contacted", requested: "requested", signed: "signed", declined: "declined", nopartner: "no partner in Gander yet",
};
/** An interline_agreements row as read. */
export interface AgreementRow {
  id: number; world_id: number; airline_id: number; country_code: string; status: string | null; partner: string | null;
  decided_on: string | null; note: string | null; updated_at: string;
}
export const AGREEMENT_COLUMNS = "id, world_id, airline_id, country_code, status, partner, decided_on, note, updated_at";

/** The row's status as the old screen showed it (to_sign is the old "requested"; none when there's no row or no status). */
export function statusOf(a: AgreementRow | undefined): IlStatus {
  const s = a?.status;
  if (!s) return "none";
  return s === "to_sign" ? "requested" : (IL_STATUS as readonly string[]).includes(s) ? (s as IlStatus) : "requested";
}
/** Still to sign: not signed, declined or without a partner in the game. */
export const isOpen = (s: IlStatus) => !["signed", "declined", "nopartner"].includes(s);

export type IlField = "status" | "partner" | "date" | "notes";
const COLUMN: Record<IlField, keyof AgreementRow> = { status: "status", partner: "partner", date: "decided_on", notes: "note" };

/** The change one edit makes (the old change handler and the adapter's interline step): a value typed (none or empty takes
 *  it out) on the airline–country's row; a row left with nothing in it is removed; none when nothing changes. */
export function agreementChange(worldId: number, airlineId: number, cc: string, row: AgreementRow | undefined, field: IlField, typed: string): Change | null {
  const v = typed.trim();
  const keep = v && v !== "none" ? v : null;
  const db = field === "status" && keep ? (["signed", "declined", "nopartner"].includes(keep) ? keep : "to_sign") : keep;
  const col = COLUMN[field];
  const now = { status: row?.status ?? null, partner: row?.partner ?? null, decided_on: row?.decided_on ?? null, note: row?.note ?? null };
  const next = { ...now, [col]: db };
  if (!next.status && !next.partner && !next.decided_on && !next.note) {
    return row ? { table: "interline_agreements", op: "delete", key: { id: row.id }, base: row.updated_at } : null;
  }
  if (row) {
    if ((now as Record<string, unknown>)[col] === db) return null;
    return { table: "interline_agreements", op: "update", key: { id: row.id }, base: row.updated_at, values: { [col]: db } };
  }
  return { table: "interline_agreements", op: "insert", values: { world_id: worldId, airline_id: airlineId, country_code: cc, ...next } };
}

// ---------- the filters, in the address (?airline=KF&status=open)
export type StatusFilter = "" | "open" | "signed" | "declined";
export interface IlFilters { airline: string; status: StatusFilter }
export function parseFilters(search: string): IlFilters {
  const q = new URLSearchParams(search);
  const s = q.get("status") ?? "";
  return { airline: (q.get("airline") ?? "").toUpperCase(), status: (["open", "signed", "declined"].includes(s) ? s : "") as StatusFilter };
}
export function filterSearch(f: IlFilters): string {
  const q = new URLSearchParams();
  if (f.airline) q.set("airline", f.airline);
  if (f.status) q.set("status", f.status);
  const s = q.toString();
  return s ? "?" + s : "";
}
/** The rows the filters show (the old ilf: an airline, and still to sign, signed or declined). */
export function shownRows(rows: readonly IlRow[], f: IlFilters, codeOf: (id: number) => string | null, status: (r: IlRow) => IlStatus): IlRow[] {
  return rows.filter((r) => {
    if (f.airline && codeOf(r.airline_id) !== f.airline) return false;
    const st = status(r);
    if (f.status === "open") return isOpen(st);
    if (f.status) return st === f.status;
    return true;
  });
}

/** The footnote's covered countries (the old kinds), as "Pan American — Canada, Mexico · …", over every country but the
 *  unknown one, in the countries' order. */
export function coveredWords(countries: readonly { code: string; name: string }[], rules: IlRules, home: ReadonlySet<string>, nameOf: (code: string) => string): string {
  const kinds = new Map<string, string[]>();
  for (const c of countries) {
    if (c.code === "--") continue;
    const k = classify(c.code, null, rules, home, nameOf);
    if (k.kind !== "covered") continue;
    kinds.set(k.label, [...(kinds.get(k.label) ?? []), c.name || c.code]);
  }
  return [...kinds].map(([k, v]) => `${k.replace("covered by ", "")} — ${v.join(", ")}`).join(" · ");
}
