// Needs attention (moved from Home to Today on 20 Oct, spec docs/specs/2026-10-20-today-performance-systems.md): its items,
// in the order the old planner's renderHome pushes them, with its words and keys; each links to where it's fixed now
// (the capture, the backup and the jobs to Systems, routes to fix and can order to Performance, a
// to-do to Today's board). Every figure comes from its one home (decision #19, spec §2): maintenance, turns and positions, night
// bans, flight numbers used twice and the airport caps (airport_cap_warning_pct) from the planning library; the capture
// from capture_status() (when, and since #21 each airline's latest verdict: a short or broken page the same night); the backups and the jobs from backup_runs and job_runs; routes to fix from growth_signals()
// (or, with no profit captured, the routes its load patterns mark cut, as the old Home fell back); can order from
// airline_cards(); the interline line from Interline's rows (the setting interline_rules, build pull request 13) and
// interline_agreements; to-dos from the table; and since 21 Oct (spec docs/specs/2026-10-21-competition-analysis.md §3)
// the rivals' moves the latest world scan showed on our routes, from competition() (each airline's threats with latest
// true), linking to Competition: they aren't fare moves, so the fare ladder's rule doesn't keep them off; and since 22 Oct
// (spec docs/specs/2026-10-21-tidy-ups.md §3) one item when a cabin charge doesn't match the first fit we logged, from
// cabin_charges(), linking to Systems' Cabin charges; and since 22 Oct (spec docs/specs/2026-10-22-fleet-capture.md §3)
// the Fleet group, one item per problem fleet_checks() finds on the latest night's fleet pages (the game's maintenance under
// maintenance_min_pct, no pilots, seats against the planner's cabin, an aircraft in one and not the other), worst first;
// since 23 Oct the estimate's "maintenance ≈P%" item only for an aircraft without the game's figure; and since 30 Oct
// (spec docs/specs/2026-10-30-market-pages-planner.md §3) the group Service in the game, one item per mismatch the
// service check (market_service_checks()) finds on the latest market read, worst first (the game against the distance's
// code, then against the planner's), each linking to the route's page.
// This file only words them. Monthly checks have none since 8 Oct, as
// in the old planner, and the one-week checks went on 22 Oct (spec docs/specs/2026-10-22-remove-aircraft-checks.md).
import { aircraftWeek, block, maintenance, schedule, type Rules } from "@rules";
import type { AttItem } from "../../ui/attention";
import { shortType } from "../../ui/aircraftNames";
import { niceDate, utcClock, utcDay } from "../../ui/dates";
import type { AirlineCard, BackupRun, CaptureRead, FixRoute, GrowthRead, HomeAirline, JobRun, JobsRead, TodoRow } from "../home/reads";
import { threatItemWords, threatKey, type ThreatItem } from "../competition/model";
import type { ServiceChecks, ServiceMismatch } from "../performance/model";
import { cabinAttention, fleetAttention, gameMaintenance, type CabinCharges, type FleetChecks } from "../systems/model";

/** One of our airlines as Home names it (home/reads.ts): needs attention words and keys it by the old planner's name. */
export type { HomeAirline };

export interface AttentionInput {
  now: Date;
  today: string;
  airlines: readonly HomeAirline[];
  rules: Rules;
  todos: readonly TodoRow[];
  /** Each null until read, as the old planner shows nothing of a part it hasn't read. */
  capture: CaptureRead | null;
  backups: readonly BackupRun[] | null;
  jobs: JobsRead | null;
  cards: readonly AirlineCard[] | null;
  growth: GrowthRead | null;
  /** How many airline–country pairs Interline lists without an agreement (not signed, declined or without a partner),
   *  or null until read. */
  interlineOpen: number | null;
  /** The rivals' moves the latest world scan showed on our routes (competition(), latestThreats()), or null until read. */
  threats?: readonly ThreatItem[] | null;
  /** The cabin charge check (cabin_charges(), since 22 Oct), or null until read. */
  cabins?: CabinCharges | null;
  /** The fleet checks (fleet_checks(), since 22 Oct), or null until read. */
  fleet?: FleetChecks | null;
  /** The service check (market_service_checks(), since 30 Oct), or null until read. */
  service?: ServiceChecks | null;
  /** For the tests only: the language dates and numbers are written in (the device's own otherwise). */
  locale?: string;
}

// The old planner's thresholds for the capture, the backup and the jobs (manual §7), in hours.
export const CAPTURE_LATE_H = 26;
export const CAPTURE_BAD_H = 48;
export const BACKUP_LATE_H = 30;
export const BACKUP_BAD_H = 54;
export const SNAPSHOT_LATE_H = 30;
export const SNAPSHOT_BAD_H = 54;
export const SCHEDULER_LATE_H = 30;
/** The day of the month by which the archive should have run. */
export const ARCHIVE_BY_DAY = 3;
/** A route-profit mark as the old planner words it (RP_SIG). */
export const MARK_WORDS: Record<FixRoute["mark"], string> = { losing: "losing money", fix: "fix or reduce" };

const JOB_NAME: Record<string, string> = {
  snapshot: "Daily snapshot", snapshot_fallback: "10:00 UTC snapshot job", cleanup: "Clean-up (10:20 UTC)", archive: "Monthly archive",
};

/** Needs attention's words for an airline's capture judged short or broken (#21): what came in short, from the database's
 *  words ("short: loads 12 of 78 flights"), and what to do; null when it is all good or wasn't judged. */
export function verdictItemWords(airline: string, verdict: string | null | undefined, words: string | null | undefined): string | null {
  if (verdict !== "short" && verdict !== "broken") return null;
  const what = String(words ?? "").replace(/^(short|broken):\s*/, "") || "a page";
  return `${airline}'s capture came in ${verdict}: ${what}. Capture that airline again in the game (Systems has each page)`;
}

/** A route as the old planner keys it: "Pan American|JFK|ORD". */
export function routeKey(rules: Rules, airlines: readonly HomeAirline[], routeId: number | null | undefined): string | undefined {
  const r = routeId == null ? undefined : rules.routes.get(routeId);
  if (!r) return undefined;
  return `${airlines.find((a) => a.id === r.airline_id)?.name ?? ""}|${r.hub_code}|${r.dest_code}`;
}

const km = (v: number | null): string => (v == null ? "its distance" : `its ${Math.round(v).toLocaleString("en-US")} km`);
/** A service mismatch in words (since 30 Oct): "DUB→AMS (FR): S1 in the game, its 750 km calls for R" (and "; the planner
 *  has S2" when that differs too), or "MAD→BCN (FR): R in the game, the planner has S1". */
export function serviceItemWords(m: Pick<ServiceMismatch, "from" | "to" | "code" | "game_code" | "distance_code" | "distance_km" | "planner_codes" | "kind" | "off_planner">): string {
  const head = `${m.from}→${m.to}${m.code ? ` (${m.code})` : ""}: ${m.game_code ?? "no service"} in the game`;
  const planner = m.planner_codes.length ? `the planner has ${m.planner_codes.join(", ")}` : "the planner has no flight that way";
  return m.kind === "distance"
    ? `${head}, ${km(m.distance_km)} calls for ${m.distance_code}${m.off_planner ? `; ${planner}` : ""}`
    : `${head}, ${planner}`;
}

/** Needs attention's Service in the game (since 30 Oct): one item per mismatch, in the check's order (the game against the
 *  distance's code first), each linking to the route's page on Performance; its key names the pair, direction and the
 *  game's code, so it comes back if the next read finds it set differently again. */
export function serviceAttention(c: ServiceChecks | null | undefined, airlines: readonly HomeAirline[]): AttItem[] {
  return (c?.mismatches ?? []).map((m) => {
    const name = airlines.find((a) => a.id === m.airline_id)?.name ?? m.airline ?? "";
    return { key: `service|${m.code ?? m.airline_id}|${m.from}-${m.to}|${m.game_code ?? "none"}`, cls: "warn" as const, screen: "performance" as const,
      route: `${name}|${m.hub}|${m.dest}`, text: serviceItemWords(m) };
  });
}

export function homeAttention(x: AttentionInput): AttItem[] {
  const { rules, airlines, today, locale } = x;
  const now = x.now.getTime();
  const name = (id: number) => airlines.find((a) => a.id === id)?.name ?? "";
  const items: AttItem[] = [];

  // each aircraft in service: its maintenance, then its short turns and wrong positions
  const legs = block.timedLegs(rules);
  const inGame = gameMaintenance(x.fleet);
  for (const a of rules.aircraft.values()) {
    if (a.status !== "active") continue;
    const week = aircraftWeek.forAircraft(rules, a, legs);
    // since 23 Oct (as Tails and Home's airline cards, spec docs/specs/2026-10-23-game-maintenance-on-tails.md) an
    // aircraft on the latest night's fleet pages is judged on the game's figure, not the estimate: under the minimum the
    // Fleet group lists it already (fleet|maintenance), at or above it there is nothing to say, so no item here either
    // way. The estimate, with its ≈, only for an aircraft the fleet pages don't have a figure for.
    const m = week && !inGame.has(a.id) ? maintenance.forAircraft(rules, a, legs, week) : null;
    if (m && m.ratio !== null && m.level !== "ok") {
      items.push({ key: "maint|" + a.registration, cls: m.level, screen: "tails", tail: a.registration,
        text: `${a.registration} maintenance ≈${Math.round(m.ratio * 100)}% — ${m.level === "bad" ? "condition will fall" : "little headroom"}` });
    }
    const bad = week ? week.legs.filter((l) => l.turn?.short || !l.position_ok).length : 0;
    if (bad) items.push({ cls: "bad", screen: "tails", tail: a.registration, text: `${a.registration}: ${bad} leg${bad > 1 ? "s" : ""} with a short turn or wrong position` });
  }

  // the fleet as the game showed it on the latest night (since 22 Oct): the game's maintenance and crew first, then the
  // cabins and the aircraft in one of the game and the planner only
  items.push(...fleetAttention(x.fleet));

  // night bans: each rotation with a departure or arrival inside one
  const legOf = new Map(legs.map((l) => [l.id, l]));
  const banned = new Set(schedule.nightBanHits(rules, legs).map((h) => legOf.get(h.leg_id)?.rotation_id));
  for (const r of rules.rotations.values()) {
    const route = rules.routes.get(r.route_id);
    if (!banned.has(r.id) || !route) continue;
    const out = rules.legs.find((l) => l.rotation_id === r.id && l.leg_no === 1);
    items.push({ cls: "bad", screen: "routes", route: routeKey(rules, airlines, r.route_id),
      text: `${route.hub_code}–${route.dest_code} (${out?.flight_no || "?"}) lands or leaves inside a night ban` });
  }

  // flight numbers used twice on the same days
  for (const c of schedule.flightNumberClashes(rules, legs)) {
    const a = legOf.get(c.leg_ids[0]), b = legOf.get(c.leg_ids[1]);
    if (!a || !b) continue;
    items.push({ cls: "bad", screen: "routes", route: routeKey(rules, airlines, b.route_id),
      text: `${name(c.airline_id).split(" ")[0]} ${c.flight_no} is used twice (${a.origin}–${a.dest} and ${b.origin}–${b.dest}) on the same days` });
  }

  // departures a week per airport, from airport_cap_warning_pct of the game's cap, bad at the cap
  for (const d of schedule.airportCapWarnings(rules, legs)) {
    items.push({ cls: d.level, screen: "routes",
      text: `${d.airport}: ${d.departures_week.toLocaleString(locale)} departures a week — the cap is ${d.cap.toLocaleString(locale)} per airport` });
  }

  // interline: the airline–country pairs Interline lists that have no agreement yet (the old Home's line, with no key)
  const il = x.interlineOpen ?? 0;
  if (il) items.push({ cls: "mute", screen: "interline", text: `Interline: ${il} airline–country pair${il === 1 ? "" : "s"} without an agreement` });

  // routes to fix or reduce, airline by airline, the most profitable a week first (route_profit()'s order); with no
  // profit captured, the routes the load patterns say to reduce instead (the old Home's fallback)
  const pos = (id: number) => { const i = airlines.findIndex((a) => a.id === id); return i < 0 ? airlines.length : i; };
  const val = (v: number | null) => (v == null ? -Infinity : Number(v));
  if (x.growth?.profit_captured) {
    const fix: FixRoute[] = [...x.growth.fix_or_reduce].sort((a, b) => pos(a.airline_id) - pos(b.airline_id)
      || val(b.profit_week) - val(a.profit_week) || val(b.profit_per_flight) - val(a.profit_per_flight));
    for (const r of fix) {
      const key = `${name(r.airline_id)}|${r.hub}|${r.dest}`;
      items.push({ key: "route|" + key, cls: r.mark === "losing" ? "bad" : "warn", screen: "performance", route: key,
        text: `${r.hub}–${r.dest}: ${MARK_WORDS[r.mark] ?? r.mark} — ${r.why}` });
    }
  } else if (x.growth) {
    for (const p of x.growth.load_patterns) {
      if (p.mark !== "cut") continue;
      const key = `${name(p.airline_id)}|${p.hub}|${p.dest}`;
      items.push({ key: "route|" + key, cls: "warn", screen: "routes", route: key, text: `${p.hub}–${p.dest}: loads say reduce — ${p.why}` });
    }
  }

  // the rivals' moves the latest world scan showed on our routes (since 21 Oct): "Air China started on PVG–CAN, 14 a week",
  // each linking to its airline's Competition page
  for (const t of x.threats ?? []) items.push({ key: threatKey(t), cls: "warn", screen: "competition", text: threatItemWords(t.threat) });

  // the capture: an airline not captured for over a day
  if (x.capture) {
    const late = x.capture.last.map((c) => ({ name: name(c.airline_id), h: c.at ? (now - Date.parse(c.at)) / 36e5 : null }))
      .filter((c) => c.h == null || c.h > CAPTURE_LATE_H);
    if (late.length) {
      const worst = Math.max(...late.map((c) => c.h ?? 99));
      items.push({ key: "capture|" + today, cls: worst > CAPTURE_BAD_H ? "bad" : "warn", screen: "systems",
        text: late.length === x.capture.last.length
          ? `No capture for ${worst >= 99 ? "over 2 days" : Math.round(worst) + " hours"}: open the game and press Capture all airlines`
          : `Not captured for over a day: ${late.map((c) => c.name).join(", ")}. Press Capture all airlines in the game` });
    }
    // a page judged short or broken (#21), the same night: one line per airline whose latest capture isn't all good
    // (older than a day, the line above says so instead)
    for (const v of x.capture.verdicts ?? []) {
      const words = verdictItemWords(name(v.airline_id), v.verdict, v.words);
      if (!words || (now - Date.parse(v.at)) / 36e5 > CAPTURE_LATE_H) continue;
      items.push({ key: `capture|verdict|${name(v.airline_id)}|${v.at}`, cls: v.verdict === "broken" ? "bad" : "warn", screen: "systems", text: words });
    }
  }

  // the service check (since 30 Oct): each pair and direction whose service profile in the game differs
  items.push(...serviceAttention(x.service, airlines));

  // the cabin charge check (since 22 Oct, spec docs/specs/2026-10-21-tidy-ups.md §3): one item when any first fit doesn't
  // match the game's charge, linking to Systems' Cabin charges board
  const cab = cabinAttention(x.cabins);
  if (cab) items.push({ key: cab.key, cls: "warn", screen: "systems", text: cab.text });

  // the backup: no good copy for 30 hours, or the last run failed
  if (x.backups) {
    const B = x.backups.filter((b) => b.kind !== "test"), good = B.find((b) => b.ok);
    const hrs = good ? (now - Date.parse(good.ran_at)) / 36e5 : null;
    const first = B[0];
    if (hrs == null || hrs > BACKUP_LATE_H) {
      items.push({ key: "backup|" + today, screen: "systems",
        cls: hrs == null && !B.length ? "mute" : hrs == null || hrs > BACKUP_BAD_H ? "bad" : "warn",
        text: hrs != null ? `Backup: last good copy ${Math.round(hrs)} hours ago${first && !first.ok ? " (the last run failed)" : ""}`
          : B.length ? "Backup: no good copy yet (the last run failed)" : "Backup: no copy yet; the first runs tonight" });
    } else if (first && !first.ok) {
      const n = String(first.note || "no note");
      items.push({ key: "backup|failed|" + first.ran_at, cls: "bad", screen: "systems",
        text: `Backup: the last run failed (${niceDate(utcDay(first.ran_at), locale)} ${utcClock(first.ran_at)} UTC): ${n.length > 160 ? "…" + n.slice(-160) : n}` });
    }
  }

  // the jobs: a late snapshot, the 10:00 UTC job not run, the month's archive not run by the 3rd, a job whose last run failed
  if (x.jobs) {
    const J = x.jobs.runs, ago = (t: string) => (now - Date.parse(t)) / 36e5;
    const when = (t: string) => `${niceDate(utcDay(t), locale)} ${utcClock(t)} UTC`;
    const m0 = x.now.toISOString().slice(0, 7) + "-01T00:00:00Z";
    const snap = J.find((j) => (j.job === "snapshot" || j.job === "snapshot_fallback") && (j.status === "ok" || j.status === "incomplete"));
    const fb = J.find((j) => j.job === "snapshot_fallback");
    if (snap && ago(snap.started_at) > SNAPSHOT_LATE_H) {
      items.push({ key: "jobs|snapshot|" + today, cls: ago(snap.started_at) > SNAPSHOT_BAD_H ? "bad" : "warn", screen: "systems",
        text: `Daily snapshot: the last was ${Math.round(ago(snap.started_at))} hours ago (the evening's capture takes it; the 10:00 UTC job when the capture didn't)` });
    }
    if (fb && ago(fb.started_at) > SCHEDULER_LATE_H) {
      items.push({ key: "jobs|scheduler|" + today, cls: "warn", screen: "systems",
        text: `Nightly jobs: the 10:00 UTC job last ran ${Math.round(ago(fb.started_at))} hours ago; the database's scheduler may have stopped (restart it from Supabase's settings)` });
    }
    const arch = x.jobs.archiveLast;
    if (x.now.getUTCDate() >= ARCHIVE_BY_DAY && arch && Date.parse(arch.started_at) < Date.parse(m0)) {
      items.push({ key: "jobs|archive|" + m0.slice(0, 7), cls: "warn", screen: "systems",
        text: `Monthly archive: hasn't run this month (the nightly backup runs it from the 1st; last ran ${when(arch.started_at)})` });
    }
    const last = new Map<string, JobRun>();   // each job's last run; the archive's per table and month
    for (const j of J) {
      const k = j.job === "archive" ? `archive|${j.details?.table ?? ""}|${j.for_month ?? ""}` : j.job;
      if (j.status !== "running" && !last.has(k)) last.set(k, j);
    }
    for (const j of last.values()) {
      if (j.status !== "failed") continue;
      const table = j.job === "archive" && j.details?.table ? ` (${j.details.table} ${String(j.for_month ?? "").slice(0, 7)})` : "";
      items.push({ key: `jobs|failed|${j.job}|${j.started_at}`, cls: "bad", screen: "systems",
        text: `${JOB_NAME[j.job] ?? j.job}${table}: the last run failed (${when(j.started_at)}): ${String(j.note || "no note").slice(0, 200)}` });
    }
  }

  // can order now (the cash forecast's, through airline_cards())
  for (const a of airlines) {
    const types = (x.cards?.find((c) => c.airline_id === a.id)?.can_order_now ?? []).map(shortType);
    if (types.length) items.push({ key: `order|${a.name}|${today}`, cls: "ok", screen: "performance", text: `${a.name} can safely order: ${types.join(", ")}` });
  }

  // to-dos due today or overdue
  for (const t of x.todos) {
    if (t.done || !t.due_on || t.due_on > today) continue;
    items.push({ key: "todo|" + (t.legacy_key ?? String(t.id)), cls: t.due_on < today ? "bad" : "warn", screen: "today",
      text: `To-do${t.due_on < today ? " (overdue)" : ""}: ${t.title}` });
  }
  return items;
}
