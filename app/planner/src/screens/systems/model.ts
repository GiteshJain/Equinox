// Systems' logic (spec docs/specs/2026-10-20-today-performance-systems.md): the plumbing, rarely opened. Moved here on
// 20 Oct with their boards: Check's Capture board and the backup's line (decision #18, build pull
// request 9, spec docs/specs/2026-10-13-check.md), and Review's Manual entry (build pull request 10, spec
// docs/specs/2026-10-14-review.md). How each board words what the database's figures and the planning library answer,
// as the old planner's renderReview, cashEntryHtml, manualLoadsHtml and parseLoadPaste word them, and every action as
// the rows of one planner_save() call: cash and fixed costs, loads typed or pasted. The Cabins board (its refit, keep as is and show again) went on 21 Oct (spec
// docs/specs/2026-10-21-cabins-new-rule.md §1). Since 22 Oct the Cabin charges board (spec docs/specs/2026-10-21-tidy-ups.md
// §3): cabin_charges()'s counts and problems, Use the game's amount and Today's one item. The Systems board's own marks
// are systems.ts's. The aircraft checks (the one-week checks and Mark checked) went on 22 Oct (spec
// docs/specs/2026-10-22-remove-aircraft-checks.md). Since 22 Oct also the Fleet board (spec
// docs/specs/2026-10-22-fleet-capture.md §3): fleet_checks()'s latest night, each airline's fleet as the game showed it with
// its problems marked, Today's Fleet items and the game's figures the Tails pop-up shows. No screen code, so the unit
// tests run it.
import type { AttItem } from "../../ui/attention";
import type { Change, Values } from "../../data/save";
import { dayDiff } from "../../ui/dates";
import type { BackupRun, CaptureAirline, CapturePages } from "./reads";

// ---------- the boards that fold under the Systems board, in their order (Fleet and Cabin charges since 22 Oct)
export const BOARDS = ["Capture", "Fleet", "Cabin charges", "Manual entry"] as const;
export type BoardKey = (typeof BOARDS)[number];

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

// ---------- Cabin charges (since 22 Oct, spec docs/specs/2026-10-21-tidy-ups.md §3): each first cabin fit Tails' filing
// logged against the game's "Installation of cabin interior (<reg>)" line, from cabin_charges()
export type CabinState = "differs" | "charged_twice" | "not_charged" | "not_logged";
export interface CabinLine { id: number; paid_at: string; amount: number; descr: string }
export interface CabinProblem {
  state: CabinState;
  airline_id: number;
  code: string | null;
  airline: string | null;
  registration: string | null;
  aircraft_id: number | null;
  /** The spending_log row of the first fit: a change to its amount is made from its updated_at. Null when not logged. */
  logged: { id: number; spent_on: string; amount: number; config: string | null; updated_at: string } | null;
  lines: CabinLine[];
  game_amount: number | null;
  difference: number | null;
}
export interface CabinCharges {
  check_from: string | null;
  wait_days: number;
  counts: { checked: number; matches: number; differs: number; charged_twice: number; not_charged: number; waiting: number; not_logged: number; problems: number };
  problems: CabinProblem[];
}

/** Each state as the board names it. */
export const CABIN_STATE_WORDS: Record<CabinState, string> = {
  differs: "differs", charged_twice: "charged twice", not_charged: "not charged yet", not_logged: "not logged",
};
/** An amount in AS$, whole dollars: "AS$97,000". */
export const asd = (v: number | null | undefined): string => (v == null ? "—" : `AS$${Math.round(Number(v)).toLocaleString("en-US")}`);
/** A difference with its sign: "+AS$2,000", "−AS$500". */
export const signedAsd = (v: number | null | undefined): string =>
  (v == null ? "—" : `${Number(v) < 0 ? "−" : "+"}${asd(Math.abs(Number(v)))}`);
/** A UTC day as the board writes it: "18 Oct". */
const shortDay = (iso: string | null | undefined): string => {
  const d = new Date(String(iso ?? "").slice(0, 10) + "T00:00:00Z");
  return Number.isNaN(d.getTime()) ? "" : `${d.getUTCDate()} ${d.toLocaleString("en-GB", { month: "short", timeZone: "UTC" })}`;
};

/** The board's line: what was checked and how it came out, "since 18 Oct: 14 match · 1 differs · 2 waiting for the game's
 *  charge", or that nothing is checked without the setting. */
export function cabinCountsWords(c: CabinCharges): string {
  if (!c.check_from) return "nothing checked: the world has no cabin_charge_check_from setting";
  const k = c.counts;
  const parts = [
    `${k.matches} match${k.matches === 1 ? "es" : ""}`,
    k.differs ? `${k.differs} differ${k.differs === 1 ? "s" : ""}` : "",
    k.charged_twice ? `${k.charged_twice} charged twice` : "",
    k.not_charged ? `${k.not_charged} not charged yet` : "",
    k.not_logged ? `${k.not_logged} not logged` : "",
    k.waiting ? `${k.waiting} waiting for the game's charge` : "",
  ].filter(Boolean);
  return `first fits since ${shortDay(c.check_from)}: ${parts.join(" · ")}`;
}
/** What we logged for a fit: "18 Oct · AS$97,000 · E195-LEI", or "—" when not logged. */
export function cabinLoggedWords(p: CabinProblem): string {
  return p.logged ? [shortDay(p.logged.spent_on), asd(p.logged.amount), p.logged.config].filter(Boolean).join(" · ") : "—";
}
/** What the game charged: each line "18 Oct 22:04 · AS$99,000", or "—" for none. */
export function cabinGameWords(p: CabinProblem): string[] {
  return p.lines.length ? p.lines.map((l) => `${shortDay(l.paid_at)} ${String(l.paid_at).slice(11, 16)} · ${asd(l.amount)}`) : ["—"];
}
/** Use the game's amount, on a differing fit: its spending_log row's amount set to the game's, one planner_save() change
 *  from the updated_at the figure read it at. Nothing for any other state. */
export function gameAmountChange(p: CabinProblem): Change[] {
  if (p.state !== "differs" || !p.logged || p.game_amount == null) return [];
  return [{ table: "spending_log", op: "update", key: { id: p.logged.id }, base: p.logged.updated_at, values: { amount: Number(p.game_amount) } }];
}
/** Today's needs attention: one item when anything isn't a match, "2 cabin charges don't match what we logged", keyed by
 *  the problems themselves so a new one shows again after a dismissal; null when there's none. */
export function cabinAttention(c: CabinCharges | null | undefined): { key: string; text: string } | null {
  const n = c?.problems.length ?? 0;
  if (!c || !n) return null;
  const keys = c.problems.map((p) => `${p.state}:${p.logged?.id ?? "p" + (p.lines[0]?.id ?? p.registration ?? "")}`).sort();
  return { key: "cabin|" + keys.join(","), text: n === 1 ? "1 cabin charge doesn't match what we logged" : `${n} cabin charges don't match what we logged` };
}

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


// ---------- Fleet (since 22 Oct, spec docs/specs/2026-10-22-fleet-capture.md): the evening capture's fleet pages, each
// aircraft as the game showed it on the latest night, and what needs a look, from fleet_checks()
export type FleetKind = "maintenance" | "crew" | "cabin" | "not_in_planner" | "not_in_game";
export interface FleetProblem {
  kind: FleetKind;
  airline_id: number;
  code: string | null;
  registration: string;
  base: string | null;
  /** The planner's aircraft, or null for one the planner doesn't have. */
  aircraft_id: number | null;
  words: string;
}
export interface FleetAircraft {
  registration: string;
  aircraft_id: number | null;
  base: string | null;
  fleet: string | null;
  type: string | null;
  nickname: string | null;
  from: string | null;
  to: string | null;
  flight: string | null;
  age_years: number | null;
  condition_pct: number | null;
  maintenance_pct: number | null;
  y: number | null;
  c: number | null;
  f: number | null;
  pilots: boolean | null;
  owned: boolean | null;
  contract: string | null;
  captured_at: string;
  problems: FleetKind[];
}
export interface FleetAirline {
  airline_id: number;
  code: string | null;
  name: string | null;
  maintenance_min_pct: number;
  /** The latest run of fleet pages that night: how many read, ok and expected, and whether every one came in ok. */
  pages: { read: number; ok: number; expected: number | null; all_ok: boolean } | null;
  at: string | null;
  aircraft: FleetAircraft[];
}
export interface FleetChecks {
  night: string | null;
  counts: Record<FleetKind | "problems", number>;
  problems: FleetProblem[];
  airlines: FleetAirline[];
}

/** Each kind as the board and Today name it, worst first. */
export const FLEET_KINDS: readonly FleetKind[] = ["maintenance", "crew", "cabin", "not_in_planner", "not_in_game"];
export const FLEET_KIND_WORDS: Record<FleetKind, string> = {
  maintenance: "maintenance", crew: "no pilots", cabin: "cabin", not_in_planner: "not in the planner", not_in_game: "not in the game",
};

/** A night as the board writes it: "22 Oct". */
export const nightWords = (night: string | null | undefined): string => shortDay(night);

/** The board's line: the night it read and how many problems of each kind, "22 Oct: 2 maintenance · 1 no pilots", "22
 *  Oct: nothing to look at", or that no fleet page has come in yet. */
export function fleetCountsWords(f: FleetChecks): string {
  if (!f.night) return "no fleet pages captured yet (Capture all airlines 1.6 reads them each evening)";
  const parts = FLEET_KINDS.filter((k) => f.counts[k]).map((k) => `${f.counts[k]} ${FLEET_KIND_WORDS[k]}`);
  return `the night of ${nightWords(f.night)}: ${parts.length ? parts.join(" · ") : "nothing to look at"}`;
}
/** Where an aircraft is: "ORD → JFK · AW 1003" in the air, "at FRA" on the ground, "—" when the page said nothing. */
export function fleetWhere(a: Pick<FleetAircraft, "from" | "to" | "flight">): string {
  if (a.from && a.to) return `${a.from} → ${a.to}${a.flight ? " · " + a.flight : ""}`;
  return a.from ? `at ${a.from}` : "—";
}
/** A percentage as the game shows it: maintenance with one decimal ("103.8%", "0.0%"), condition whole ("83%"). */
export const pctWords = (v: number | null | undefined, decimals: 0 | 1): string =>
  (v == null || !Number.isFinite(Number(v)) ? "—" : `${Number(v).toFixed(decimals)}%`);
/** The seats as fitted, Y/C/F: "180/15/0". */
export const seatWords = (a: Pick<FleetAircraft, "y" | "c" | "f">): string => [a.y, a.c, a.f].map((x) => (x == null ? "?" : String(x))).join("/");
/** An airline's pages that night in words: "3 of 3 fleet pages ok", "1 of 2 fleet pages ok", or none. */
export function fleetPagesWords(a: Pick<FleetAirline, "pages">): string {
  const p = a.pages;
  if (!p) return "no fleet pages that night";
  return `${p.ok} of ${p.expected ?? p.read} fleet page${(p.expected ?? p.read) === 1 ? "" : "s"} ok`;
}

/** Today's needs attention: one item per problem, worst first as fleet_checks() gives them (maintenance, crew, then the
 *  rest), keyed by its kind, registration and night, so a dismissed problem shows again the next night while it lasts.
 *  An aircraft the planner has opens its pop-up (Tails); one it doesn't opens Systems' Fleet. */
export function fleetAttention(f: FleetChecks | null | undefined): AttItem[] {
  if (!f?.night) return [];
  return f.problems.map((p) => ({
    key: `fleet|${p.kind}|${p.registration}|${f.night}`,
    cls: p.kind === "maintenance" || p.kind === "crew" ? "bad" : "warn",
    text: p.words,
    ...(p.aircraft_id != null ? { screen: "tails" as const, tail: p.registration } : { screen: "systems" as const }),
  }));
}

/** The game's figures for one aircraft on the latest night, for the Tails pop-up beside the planner's own maintenance:
 *  "103.8% maintenance · 83% condition · 22 Oct", or null when the night's fleet pages don't have it. */
export function gameFleetWords(f: FleetChecks | null | undefined, aircraftId: number, registration: string): { text: string; bad: boolean } | null {
  for (const al of f?.airlines ?? []) {
    const a = al.aircraft.find((x) => x.aircraft_id === aircraftId) ?? al.aircraft.find((x) => x.registration === registration.toUpperCase());
    if (!a) continue;
    const bad = a.maintenance_pct != null && Number(a.maintenance_pct) < Number(al.maintenance_min_pct);
    return { text: `${pctWords(a.maintenance_pct, 1)} maintenance · ${pctWords(a.condition_pct, 0)} condition · ${nightWords(f?.night)}`, bad };
  }
  return null;
}
