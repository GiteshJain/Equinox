// Systems' logic (spec docs/specs/2026-10-20-today-performance-systems.md): the plumbing, rarely opened. Moved here on
// 20 Oct with their boards: Check's Capture board and the backup's line, its aircraft checks and its cabins (decision #18,
// build pull request 9, spec docs/specs/2026-10-13-check.md), and Review's Manual entry (build pull request 10, spec
// docs/specs/2026-10-14-review.md). How each board words what the database's figures and the planning library answer,
// as the old planner's renderReview, cabinsBoard, cashEntryHtml, manualLoadsHtml and parseLoadPaste word them, and every
// action as the rows of one planner_save() call: mark checked (Tails' markCheckedChange), log a refit, keep a cabin as
// is and show it again, cash and fixed costs, loads typed or pasted. The Systems board's own marks are systems.ts's. No
// screen code, so the unit tests run it.
import { cabins, checks, loadReport, type CabinFit, type Rules } from "@rules";
import type { Change, Values } from "../../data/save";
import { dayDiff } from "../../ui/dates";
import type { TailAircraft } from "../tails/model";
import type { BackupRun, CaptureAirline, CapturePages } from "./reads";

// ---------- the boards that fold under the Systems board, in their order
export const BOARDS = ["Capture", "Manual entry", "Cabins", "Aircraft checks"] as const;
export type BoardKey = (typeof BOARDS)[number];
/** The boards shown: Aircraft checks only while the checks are on for one of our airlines (aircraft_check_after_days
 *  above 0, the library's checks.on; spec docs/specs/2026-10-15-aircraft-checks-off.md). */
export function shownBoards(rules: Rules, airlineIds: readonly number[]): readonly BoardKey[] {
  return airlineIds.some((id) => checks.on(rules, id)) ? BOARDS : BOARDS.filter((k) => k !== "Aircraft checks");
}

// ---------- Capture
/** The capture's five pages, in the old board's order, with its names for them. */
export const CAPTURE_KINDS: readonly (readonly [string, string])[] = [["loads", "Loads"], ["statement", "Statement"], ["events", "Events"], ["pnl", "Income"], ["balance", "Balance"]];
/** A page's cell: today's time, else yesterday's (dim), else a dash. */
export function captureCell(p: CapturePages | undefined): { text: string; dim: boolean } {
  if (p?.today) return { text: p.today.slice(11, 16), dim: false };
  if (p?.yesterday) return { text: "yesterday " + p.yesterday.slice(11, 16), dim: true };
  return { text: "—", dim: true };
}
/** The airline's line for today: complete, missing some pages, or not captured. */
export function captureStatus(a: Pick<CaptureAirline, "missing">): { cls: "ok" | "warn"; text: string } {
  const label = (k: string) => CAPTURE_KINDS.find((x) => x[0] === k)?.[1] ?? k;
  if (a.missing.length === CAPTURE_KINDS.length) return { cls: "warn", text: "not captured" };
  if (a.missing.length) return { cls: "warn", text: "missing " + a.missing.map(label).join(", ") };
  return { cls: "ok", text: "complete" };
}
/** The line under Capture: last night's backup, from the backup job's own report (none when it couldn't be read). */
export function backupWords(runs: readonly BackupRun[] | undefined, niceDate: (d: string) => string): { ok: boolean | null; text: string } | null {
  if (!runs) return null;
  const b = runs.find((x) => x.kind !== "test");
  if (!b) return { ok: null, text: "Backup: no copy yet. The first runs tonight." };
  const when = `${niceDate(String(b.ran_at).slice(0, 10))} ${String(b.ran_at).slice(11, 16)} UTC`;
  return b.ok
    ? { ok: true, text: `Backup: copied ${when} · ${b.tables ?? "?"} tables, ${b.rows != null ? Number(b.rows).toLocaleString("en-US") : "?"} rows, ${b.files ?? "?"} files · restore check passed` }
    : { ok: false, text: `${when} · ${String(b.note ?? "").slice(0, 200)}` };
}

// ---------- Aircraft checks
/** A day n days after (or before) another. */
const moveDay = (day: string, n: number): string => new Date(Date.parse(day + "T00:00:00Z") + n * 86_400_000).toISOString().slice(0, 10);
/** Aircraft by the day their check comes up, in the checks' order. */
export function upcomingByDay(list: readonly { due: string; registration: string }[]): [string, string[]][] {
  const by = new Map<string, string[]>();
  for (const c of list) by.set(c.due, [...(by.get(c.due) ?? []), c.registration]);
  return [...by].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
}
/** The order the old checks listed an aircraft's load-pattern pills in: the routes as the load window's days first show
 *  them, from two days ahead backwards, each day's departures by time (the old patterns() met them in that order). */
export function patternRanks(rules: Rules, today: string, windowDays: number): Map<number, number> {
  const rank = new Map<number, number>();
  for (let i = 1; i <= windowDays; i++) {
    for (const f of loadReport.flightsOn(rules, moveDay(today, 2 - i + 1))) if (!rank.has(f.route_id)) rank.set(f.route_id, rank.size);
  }
  return rank;
}
/** A load pattern's pill on a check: its route, and its share of departures at 95%+. */
export function patternPill(p: { hub: string; dest: string; departures: number; full: number; mark: string }): { cls: string; text: string } {
  return {
    cls: p.mark === "cut" ? "bad" : p.mark === "watch" ? "warn" : p.mark === "add" ? "ok" : "mute",
    text: `${p.hub}–${p.dest}: ${p.departures ? Math.round(p.full / p.departures * 100) : 0}% of departures 95%+`,
  };
}

// ---------- Cabins
/** The cabin it has, as the board shows it: its layout's cabin, else its layout's code, else a dash. */
export const haveWords = (x: Pick<CabinFit, "have" | "have_code">): string => x.have || x.have_code || "—";
export const mixWords = (x: Pick<CabinFit, "mix">): string => x.mix.map((m) => `${m.cabin} ${m.pct}%`).join(" · ");
/** A refit's cost in millions, as the old note writes it ("0.2M"). */
export const costWords = (cost: number): string => `${Number((cost / 1_000_000).toFixed(4))}M`;
/** The kept-as-is key the old planner used: "registration|cabin". */
export const keepKey = (x: Pick<CabinFit, "registration" | "want">): string => `${x.registration}|${x.want}`;
/** Each refit's cost for the airline (cabin_refit_cost). */
export const refitCost = (rules: Rules, airlineId: number): number => cabins.refitCost(rules, airlineId);

/** Log a refit done in the game (the old data-refit): the aircraft takes the layout, and the refit's cost is a loss that
 *  day (spending_log, as the old planner's capex entry "cabin refit REG → CODE" is stored: no aircraft named). */
export function refitChanges(worldId: number, a: Pick<TailAircraft, "id" | "airline_id" | "registration" | "updated_at">, target: { id: number; code: string },
  cost: number, today: string): Change[] {
  return [
    { table: "aircraft", op: "update", key: { id: a.id }, base: a.updated_at, values: { cabin_config_id: target.id } },
    { table: "spending_log", op: "insert", values: {
      world_id: worldId, airline_id: a.airline_id, spent_on: today, amount: cost, kind: "loss", aircraft_id: null, note: `cabin refit ${a.registration} → ${target.code}` } },
  ];
}
/** Keep as is (the old data-cabkeep): the cabin its routes call for, kept from today. */
export const keepChange = (worldId: number, aircraftId: number, cabin: string, today: string): Change =>
  ({ table: "aircraft_cabin_keeps", op: "insert", values: { world_id: worldId, aircraft_id: aircraftId, cabin, decided_on: today } });
/** Show again (the old data-cabundo): the decision goes. */
export const undoKeepChange = (k: { aircraft_id: number; cabin: string; updated_at: string }): Change =>
  ({ table: "aircraft_cabin_keeps", op: "delete", key: { aircraft_id: k.aircraft_id, cabin: k.cabin }, base: k.updated_at });

// ---------- Manual entry (Review's until 20 Oct): cash and fixed costs, the nightly log (cash_log()), loads by hand
export interface CashToday {
  day: string;
  shown_cash: number | null;
  shown_fixed: number | null;
  stored_cash: number | null;
  stored_fixed: number | null;
  captured_cash: number | null;
  captured_fixed: number | null;
  entry: { cash: number | null; fixed_next7: number | null; updated_at: string } | null;
}
export interface CashLogAirline { airline_id: number; code: string | null; name: string; days: { day: string; cash: number; fixed: number | null }[]; today: CashToday }
export interface CashLog { today: string; airlines: CashLogAirline[] }
// ---------- cash and fixed costs for today (cashEntryHtml and its save, as the old planner's adapter writes them)
/** A typed box: the number in it, or null when it's empty or not a number (the old parseFloat, commas dropped). */
export function typedNumber(s: string | null | undefined): number | null {
  const v = parseFloat(String(s ?? "").replace(/,/g, ""));
  return Number.isNaN(v) ? null : v;
}
/** What a box shows to begin with: the figure as the old planner held it, or empty. */
export const boxValue = (v: number | null | undefined): string => (v == null ? "" : String(v));

/** Save cash and fixed costs: for each airline whose figure changed from what the tables hold, a cash_entries row keeps a
 *  figure only where it differs from the capture's (rounded as the planner rounds), in AS$; the row goes once both agree
 *  again (the old planner's planner_apply_money). One action. */
export function cashChanges(worldId: number, rows: readonly { airline_id: number; today: CashToday; cash: string; fixed: string }[], nowIso: string): Change[] {
  const out: Change[] = [];
  const same = (a: number | null | undefined, b: number | null | undefined) => (a ?? null) === (b ?? null);
  const asd = (v: number | null, cap: number | null) => (v != null && v !== cap && Math.abs(v) < 1_000_000 ? Math.round(v * 1_000_000 * 100) / 100 : null);
  for (const r of rows) {
    const t = r.today;
    const stCash = typedNumber(r.cash) ?? t.shown_cash, stFixed = typedNumber(r.fixed) ?? t.shown_fixed;
    if (same(stCash, t.stored_cash) && same(stFixed, t.stored_fixed)) continue;
    const cash = asd(stCash, t.captured_cash), fixed = asd(stFixed, t.captured_fixed);
    const key = { airline_id: r.airline_id, day: t.day };
    if (cash != null || fixed != null) {
      if (!t.entry) {
        out.push({ table: "cash_entries", op: "insert", values: { world_id: worldId, airline_id: r.airline_id, day: t.day, cash, fixed_next7: fixed, entered_at: nowIso } });
      } else if (!same(t.entry.cash, cash) || !same(t.entry.fixed_next7, fixed)) {
        out.push({ table: "cash_entries", op: "update", key, base: t.entry.updated_at, values: { cash, fixed_next7: fixed, entered_at: nowIso } });
      }
    } else if (t.entry) {
      out.push({ table: "cash_entries", op: "delete", key, base: t.entry.updated_at });
    }
  }
  return out;
}

/** The nightly log: every reported day across our airlines, newest first, with each airline's cash and fixed costs. */
export function nightlyLog(log: CashLog): { day: string; cells: ({ cash: string; fixed: string | null } | null)[] }[] {
  const days = [...new Set(log.airlines.flatMap((a) => a.days.map((d) => d.day)))].sort().reverse();
  return days.map((day) => ({
    day,
    cells: log.airlines.map((a) => {
      const p = a.days.find((d) => d.day === day);
      return p ? { cash: p.cash.toFixed(2), fixed: p.fixed != null ? p.fixed.toFixed(2) : null } : null;
    }),
  }));
}
/** An airline's short name, as the old entry boxes and log head it: its first word. */
export const firstWord = (name: string): string => name.split(" ")[0] ?? name;

// ---------- loads by hand (manualLoadsHtml, parseLoadPaste, lfPastePreview), saved through planner_save() into load_entries
// and load_days (since the clean-up, build pull request 14; until then through the old planner's save_loads())
/** A loads day as the planner holds it (loads_by_day()): the flights' economy loads keyed "Airline|number" (captured or
 *  typed, the latest wins), whether it is complete, whether a capture reached it (source "capture"), when it was last saved
 *  by hand (savedAt, ms); and the typed rows behind it, with their updated_at, the base a save changes them from. */
export interface LoadsDay {
  done: boolean;
  f: Record<string, number>;
  source?: string;
  savedAt?: number;
  entries?: { airline_id: number; flight_no: number; eco_pct: number | null; updated_at: string }[];
  flags?: { done: boolean; saved_at_ms: number | null; updated_at: string } | null;
}
/** A day's change as the old planner's save sent it: the whole day's flights (f), or single flights set and cleared, and
 *  the day's flags. */
export interface DayPatch { f?: Record<string, number>; set?: Record<string, number>; del?: string[]; done?: boolean; savedAt?: number }
/** The day after the change, as the old save_loads() merged it: f replaces the day's flights, or set and del change single
 *  ones; done and savedAt as given, else as they were. */
export function mergeDay(got: LoadsDay | null, p: DayPatch): { f: Record<string, number>; done: boolean; savedAt?: number } {
  let f: Record<string, number>;
  if (p.f !== undefined) f = { ...p.f };
  else {
    f = { ...(got?.f ?? {}), ...(p.set ?? {}) };
    for (const k of p.del ?? []) delete f[k];
  }
  const savedAt = p.savedAt !== undefined ? p.savedAt : got?.savedAt;
  return { f, done: p.done !== undefined ? p.done : got?.done ?? false, ...(savedAt !== undefined ? { savedAt } : {}) };
}
/** The rows a day's change writes, as the old save_loads() wrote them (private.loads_mirror_days): a load_entries row for
 *  each flight whose load now differs from the day as it stood (null where it's cleared), and the day's load_days row
 *  when its complete mark or its saved time changed, each stamped as entered now. A row there already is changed from its
 *  updated_at; otherwise it's added. airlines: our airlines' names (the key's first part) to their ids. */
export function loadsChanges(worldId: number, day: string, got: LoadsDay | null, p: DayPatch, airlines: ReadonlyMap<string, number>, nowIso: string): Change[] {
  const v = mergeDay(got, p);
  const gotF = got?.f ?? {};
  const out: Change[] = [];
  for (const k of [...new Set([...Object.keys(gotF), ...Object.keys(v.f)])].sort()) {
    const tv = v.f[k], gv = gotF[k];
    if (tv === gv) continue;
    const [name, no] = [k.slice(0, k.lastIndexOf("|")), Number(k.slice(k.lastIndexOf("|") + 1))];
    const airline = airlines.get(name);
    if (airline === undefined || !Number.isInteger(no) || no < 0 || no > 2000000000) continue;
    const eco = typeof tv === "number" && Number.isFinite(tv) && Math.abs(tv) < 10000 ? tv : null;
    const row = got?.entries?.find((e) => e.airline_id === airline && e.flight_no === no);
    out.push(row
      ? { table: "load_entries", op: "update", key: { airline_id: airline, game_date: day, flight_no: no }, base: row.updated_at, values: { eco_pct: eco, entered_at: nowIso } }
      : { table: "load_entries", op: "insert", values: { world_id: worldId, airline_id: airline, game_date: day, flight_no: no, eco_pct: eco, entered_at: nowIso } });
  }
  if (v.done !== (got?.done ?? false) || v.savedAt !== got?.savedAt) {
    const values: Values = { done: v.done, saved_at_ms: v.savedAt ?? null, entered_at: nowIso };
    out.push(got?.flags
      ? { table: "load_days", op: "update", key: { world_id: worldId, game_date: day }, base: got.flags.updated_at, values }
      : { table: "load_days", op: "insert", values: { world_id: worldId, game_date: day, ...values } });
  }
  return out;
}
/** The day's status after its date. */
export const dayStatus = (d: LoadsDay | null): string => (d?.done ? (d.source === "capture" ? "captured" : "entered by hand") : "nothing yet");
/** An airline's box: its flights under 95%, lowest first, "flight load" pairs. */
export function underList(d: LoadsDay | null, airline: string): string {
  return Object.entries(d?.f ?? {}).filter(([k, v]) => k.startsWith(airline + "|") && +v < 95).sort((x, y) => x[1] - y[1])
    .map(([k, v]) => k.split("|")[1] + " " + v).join(", ");
}

/** The typed boxes read as the old lfsave reads them: number then load, pairs, an airline prefix ("AW") allowed, each load
 *  kept to 0 to 94; flights that don't operate that day are named (they're saved, but won't count). */
export function typedLoads(boxes: readonly { airline: string; text: string }[], valid: ReadonlySet<string>): { f: Record<string, number>; unknown: string[] } {
  const f: Record<string, number> = {}, unknown: string[] = [];
  for (const b of boxes) {
    const toks = (b.text || "").toUpperCase().replace(/[A-Z]{2}\s*(?=\d)/g, "").replace(/%/g, "").split(/[^0-9.]+/).filter(Boolean).map(Number);
    for (let i = 0; i + 1 < toks.length; i += 2) {
      const no = String(Math.round(toks[i] as number)), val = toks[i + 1] as number, key = b.airline + "|" + no;
      if (!valid.has(key)) unknown.push(firstWord(b.airline) + " " + no);
      f[key] = Math.min(94, Math.max(0, Math.round(val)));
    }
  }
  return { f, unknown };
}
/** The typed day's change: that day's flights (replacing them), complete, saved now. */
export const typedSave = (day: string, f: Record<string, number>, nowMs: number): Record<string, DayPatch> => ({ [day]: { f, done: true, savedAt: nowMs } });

export interface PastedLoad { airline: string; no: string; tail: string; from: string; to: string; date: string; dep: string; pax: number; seats: number; pct: number; key: string }
/** The game's load table pasted (parseLoadPaste): each row from its flight code (an airline of ours by its code), tail,
 *  airports, local departure "DD.MM. HH:MM" and each cabin's price then "pax / seats"; the load is economy, business and
 *  first together (no cargo). A date more than 60 days after today is last year's. codes: our airlines' codes → names. */
export function parseLoadPaste(text: string, codes: ReadonlyMap<string, string>, today: string): PastedLoad[] {
  const toks = String(text || "").split(/\t|\r?\n/).map((x) => x.trim()).filter(Boolean);
  const out: PastedLoad[] = [];
  const yNow = +today.slice(0, 4);
  for (let i = 0; i < toks.length; i++) {
    const m = /^([A-Z0-9]{2})\s*(\d{1,4})$/.exec(toks[i] as string);
    const airline = m ? codes.get(m[1] as string) : undefined;
    if (!m || !airline) continue;
    const tail = toks[i + 1] || "", from = toks[i + 2] || "", dm = /^(\d{2})\.(\d{2})\.?\s+(\d{2}):(\d{2})/.exec(toks[i + 3] || ""), to = toks[i + 4] || "";
    if (!dm || !/^[A-Z0-9]{3}$/.test(from) || !/^[A-Z0-9]{3}$/.test(to)) continue;
    let date = `${yNow}-${dm[2]}-${dm[1]}`;
    if (dayDiff(today, date) > 60) date = `${yNow - 1}-${dm[2]}-${dm[1]}`;
    let j = i + 6;
    const cab: ({ pax: number; seats: number } | null)[] = [];
    for (let c = 0; c < 4 && j < toks.length; c++) {
      const price = toks[j++];
      const pax = toks[j++] || "";
      const pm = /^([\d,]+)\s*\/\s*([\d,]+)/.exec(pax);
      cab.push(pm ? { pax: +(pm[1] as string).replace(/,/g, ""), seats: +(pm[2] as string).replace(/,/g, "") } : null);
      if (price === undefined) break;
    }
    const pcs = cab.slice(0, 3).filter((c): c is { pax: number; seats: number } => !!c);
    const pax = pcs.reduce((a, c) => a + c.pax, 0), seats = pcs.reduce((a, c) => a + c.seats, 0);
    if (!seats) continue;
    const no = String(+(m[2] as string));
    out.push({ airline, no, tail, from, to, date, dep: dm[3] + ":" + dm[4], pax, seats, pct: Math.round(pax / seats * 100), key: airline + "|" + no });
    i = j - 1;
  }
  return out;
}
/** A pasted load's pill, as the preview colours it. */
export const pastePill = (pct: number): "ok" | "warn" | "orange" | "bad" => (pct >= 95 ? "ok" : pct >= 85 ? "warn" : pct >= 70 ? "orange" : "bad");
/** The pasted loads saved (lfpaste-save): each day's flights under 95% set and those at 95% or more cleared, and the days
 *  ticked marked complete. */
export function pasteSaves(parsed: readonly PastedLoad[], marked: readonly string[], nowMs: number): Record<string, DayPatch> {
  const send: Record<string, { set: Record<string, number>; del: string[]; done?: boolean; savedAt?: number }> = {};
  const patch = (d: string) => (send[d] ??= { set: {}, del: [] });
  for (const x of parsed) {
    const p = patch(x.date);
    if (x.pct < 95) p.set[x.key] = x.pct;
    else p.del.push(x.key);
  }
  for (const d of marked) Object.assign(patch(d), { done: true, savedAt: nowMs });
  return send;
}

