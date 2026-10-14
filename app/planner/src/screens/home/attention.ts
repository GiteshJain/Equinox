// Home's needs-attention items, in the order the old planner's renderHome pushes them, with its words, keys and links.
// Every figure comes from its one home (decision #19, spec §2): one-week checks, maintenance, turns and positions, night
// bans, flight numbers used twice and the airport caps (airport_cap_warning_pct) from the planning library; the capture
// from capture_status(); the backups and the jobs from backup_runs and job_runs; routes to fix from growth_signals()
// (or, with no profit captured, the routes its load patterns mark cut, as the old Home fell back); can order from
// airline_cards(); to-dos from the table. This file only words them. Interline isn't listed yet:
// its rule (the old planner's list of interline countries) has no home outside the old planner's code (the pull
// request says so); monthly checks have none since 8 Oct, as in the old planner.
import { aircraftWeek, block, maintenance, schedule, type OneWeekCheck, type Rules } from "@rules";
import type { AttItem } from "../../ui/attention";
import { shortType } from "../../ui/aircraftNames";
import { niceDate, utcClock, utcDay } from "../../ui/dates";
import type { AirlineCard, BackupRun, CaptureRead, FixRoute, GrowthRead, JobRun, JobsRead, TodoRow } from "./reads";

/** One of our airlines as Home names it: the old planner's name (Pan American), so its words and keys are the old ones. */
export interface HomeAirline {
  id: number;
  name: string;
  code: string | null;
  color: string | null;
  /** The city whose photo the airline's card shows (airlines.photo_city). */
  photo?: string | null;
}

export interface AttentionInput {
  now: Date;
  today: string;
  airlines: readonly HomeAirline[];
  rules: Rules;
  checks: readonly OneWeekCheck[];
  todos: readonly TodoRow[];
  /** Each null until read, as the old planner shows nothing of a part it hasn't read. */
  capture: CaptureRead | null;
  backups: readonly BackupRun[] | null;
  jobs: JobsRead | null;
  cards: readonly AirlineCard[] | null;
  growth: GrowthRead | null;
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

/** A route as the old planner keys it: "Pan American|JFK|ORD". */
export function routeKey(rules: Rules, airlines: readonly HomeAirline[], routeId: number | null | undefined): string | undefined {
  const r = routeId == null ? undefined : rules.routes.get(routeId);
  if (!r) return undefined;
  return `${airlines.find((a) => a.id === r.airline_id)?.name ?? ""}|${r.hub_code}|${r.dest_code}`;
}

export function homeAttention(x: AttentionInput): AttItem[] {
  const { rules, airlines, today, locale } = x;
  const now = x.now.getTime();
  const name = (id: number) => airlines.find((a) => a.id === id)?.name ?? "";
  const items: AttItem[] = [];

  // one-week checks due
  for (const c of x.checks) if (c.status === "due") items.push({ cls: "warn", text: `${c.registration} is due its one-week check`, screen: "check" });

  // each aircraft in service: its maintenance, then its short turns and wrong positions
  const legs = block.timedLegs(rules);
  for (const a of rules.aircraft.values()) {
    if (a.status !== "active") continue;
    const week = aircraftWeek.forAircraft(rules, a, legs);
    const m = week ? maintenance.forAircraft(rules, a, legs, week) : null;
    if (m && m.ratio !== null && m.level !== "ok") {
      items.push({ key: "maint|" + a.registration, cls: m.level, screen: "tails", tail: a.registration,
        text: `${a.registration} maintenance ≈${Math.round(m.ratio * 100)}% — ${m.level === "bad" ? "condition will fall" : "little headroom"}` });
    }
    const bad = week ? week.legs.filter((l) => l.turn?.short || !l.position_ok).length : 0;
    if (bad) items.push({ cls: "bad", screen: "tails", tail: a.registration, text: `${a.registration}: ${bad} leg${bad > 1 ? "s" : ""} with a short turn or wrong position` });
  }

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

  // routes to fix or reduce, airline by airline, the most profitable a week first (route_profit()'s order); with no
  // profit captured, the routes the load patterns say to reduce instead (the old Home's fallback)
  const pos = (id: number) => { const i = airlines.findIndex((a) => a.id === id); return i < 0 ? airlines.length : i; };
  const val = (v: number | null) => (v == null ? -Infinity : Number(v));
  if (x.growth?.profit_captured) {
    const fix: FixRoute[] = [...x.growth.fix_or_reduce].sort((a, b) => pos(a.airline_id) - pos(b.airline_id)
      || val(b.profit_week) - val(a.profit_week) || val(b.profit_per_flight) - val(a.profit_per_flight));
    for (const r of fix) {
      const key = `${name(r.airline_id)}|${r.hub}|${r.dest}`;
      items.push({ key: "route|" + key, cls: r.mark === "losing" ? "bad" : "warn", screen: "review", route: key,
        text: `${r.hub}–${r.dest}: ${MARK_WORDS[r.mark] ?? r.mark} — ${r.why}` });
    }
  } else if (x.growth) {
    for (const p of x.growth.load_patterns) {
      if (p.mark !== "cut") continue;
      const key = `${name(p.airline_id)}|${p.hub}|${p.dest}`;
      items.push({ key: "route|" + key, cls: "warn", screen: "routes", route: key, text: `${p.hub}–${p.dest}: loads say reduce — ${p.why}` });
    }
  }

  // the capture: an airline not captured for over a day
  if (x.capture) {
    const late = x.capture.last.map((c) => ({ name: name(c.airline_id), h: c.at ? (now - Date.parse(c.at)) / 36e5 : null }))
      .filter((c) => c.h == null || c.h > CAPTURE_LATE_H);
    if (late.length) {
      const worst = Math.max(...late.map((c) => c.h ?? 99));
      items.push({ key: "capture|" + today, cls: worst > CAPTURE_BAD_H ? "bad" : "warn", screen: "check",
        text: late.length === x.capture.last.length
          ? `No capture for ${worst >= 99 ? "over 2 days" : Math.round(worst) + " hours"}: open the game and press Capture all airlines`
          : `Not captured for over a day: ${late.map((c) => c.name).join(", ")}. Press Capture all airlines in the game` });
    }
  }

  // the backup: no good copy for 30 hours, or the last run failed
  if (x.backups) {
    const B = x.backups.filter((b) => b.kind !== "test"), good = B.find((b) => b.ok);
    const hrs = good ? (now - Date.parse(good.ran_at)) / 36e5 : null;
    const first = B[0];
    if (hrs == null || hrs > BACKUP_LATE_H) {
      items.push({ key: "backup|" + today, screen: "check",
        cls: hrs == null && !B.length ? "mute" : hrs == null || hrs > BACKUP_BAD_H ? "bad" : "warn",
        text: hrs != null ? `Backup: last good copy ${Math.round(hrs)} hours ago${first && !first.ok ? " (the last run failed)" : ""}`
          : B.length ? "Backup: no good copy yet (the last run failed)" : "Backup: no copy yet; the first runs tonight" });
    } else if (first && !first.ok) {
      const n = String(first.note || "no note");
      items.push({ key: "backup|failed|" + first.ran_at, cls: "bad", screen: "check",
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
      items.push({ key: "jobs|snapshot|" + today, cls: ago(snap.started_at) > SNAPSHOT_BAD_H ? "bad" : "warn", screen: "check",
        text: `Daily snapshot: the last was ${Math.round(ago(snap.started_at))} hours ago (the evening's capture takes it; the 10:00 UTC job when the capture didn't)` });
    }
    if (fb && ago(fb.started_at) > SCHEDULER_LATE_H) {
      items.push({ key: "jobs|scheduler|" + today, cls: "warn", screen: "check",
        text: `Nightly jobs: the 10:00 UTC job last ran ${Math.round(ago(fb.started_at))} hours ago; the database's scheduler may have stopped (restart it from Supabase's settings)` });
    }
    const arch = x.jobs.archiveLast;
    if (x.now.getUTCDate() >= ARCHIVE_BY_DAY && arch && Date.parse(arch.started_at) < Date.parse(m0)) {
      items.push({ key: "jobs|archive|" + m0.slice(0, 7), cls: "warn", screen: "check",
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
      items.push({ key: `jobs|failed|${j.job}|${j.started_at}`, cls: "bad", screen: "check",
        text: `${JOB_NAME[j.job] ?? j.job}${table}: the last run failed (${when(j.started_at)}): ${String(j.note || "no note").slice(0, 200)}` });
    }
  }

  // can order now (the cash forecast's, through airline_cards())
  for (const a of airlines) {
    const types = (x.cards?.find((c) => c.airline_id === a.id)?.can_order_now ?? []).map(shortType);
    if (types.length) items.push({ key: `order|${a.name}|${today}`, cls: "ok", screen: "review", text: `${a.name} can safely order: ${types.join(", ")}` });
  }

  // to-dos due today or overdue
  for (const t of x.todos) {
    if (t.done || !t.due_on || t.due_on > today) continue;
    items.push({ key: "todo|" + (t.legacy_key ?? String(t.id)), cls: t.due_on < today ? "bad" : "warn", screen: "home",
      text: `To-do${t.due_on < today ? " (overdue)" : ""}: ${t.title}` });
  }
  return items;
}
