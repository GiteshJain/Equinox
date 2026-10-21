// The Systems board at the top of Systems (decision #23, at the top of Check until 20 Oct; spec docs/specs/2026-10-14-capture-checks-and-systems.md part 2):
// one line each, with a green, amber or red mark and when: the evening capture (each airline, with #21's verdict), the
// daily snapshot, the nightly backup, the monthly archive, the clean-ups, the world scan, the planner's own build, and the
// usage the database can measure against its triggers. The figures come from system_status() (one staff call, read only)
// and the build's stamp; this file only marks and words them, so the unit tests can try every limit. The limits are
// Home's (manual §7): capture 26 and 48 hours, backup and snapshot 30 hours (red at 54, as Home), the archive by the 3rd,
// a job whose last run failed; the world scan amber over 8 days and red over 15, and amber when a scan stopped part-way
// with none finished after it (22 Oct); usage amber from 70% and red at the trigger. Home keeps flagging problems; the
// board is where "all good" shows.
import type { BuildStamp } from "../../data/build";
import { ARCHIVE_BY_DAY, BACKUP_BAD_H, BACKUP_LATE_H, CAPTURE_BAD_H, CAPTURE_LATE_H, SCHEDULER_LATE_H, SNAPSHOT_BAD_H, SNAPSHOT_LATE_H } from "../today/attention";

export type Mark = "ok" | "warn" | "bad";

/** The world scan's age, in days: amber over 8, red over 15. */
export const SCAN_LATE_D = 8;
export const SCAN_BAD_D = 15;
/** Usage: amber from this share of its trigger, red at the trigger. */
export const USAGE_WARN_SHARE = 0.7;
/** A daily job not run for this long is late (Home's 30 hours), and red from Home's 54. */
export const JOB_LATE_H = SCHEDULER_LATE_H;
export const JOB_BAD_H = SNAPSHOT_BAD_H;

export type Verdict = "ok" | "short" | "broken";

export interface SysCapture {
  airline_id: number;
  code: string | null;
  name: string | null;
  last_at: string | null;
  verdict: Verdict | null;
  verdict_words: string | null;
  verdict_at: string | null;
  missing: string[];
}
export interface SysJob { at: string | null; status: string | null; note: string | null }
export interface SystemStatus {
  as_of: string;
  capture: SysCapture[];
  snapshot: {
    day?: string | null;
    source?: string | null;
    complete?: boolean | null;
    taken_at?: string | null;
    last_run?: { job: string; status: string; at: string; note: string | null } | null;
    fallback_at?: string | null;
  };
  backup: {
    last: { ran_at: string; ok: boolean | null; kind: string | null; note: string | null } | null;
    last_good: { ran_at: string; bytes: number | null; tables: number | null; rows: number | null; files: number | null } | null;
  };
  archive: {
    last_at: string | null;
    month: string;
    runs_this_month: number;
    ok_this_month: number;
    rows_this_month: number;
    failed: { table: string | null; month: string | null; at: string; note: string | null }[];
  } | null;
  cleanup: SysJob | null;
  scan: { taken_at: string; week: string | null; status: string | null } | null;
  /** A scan that stopped part-way since the latest finished one (since 22 Oct, spec docs/specs/2026-10-21-tidy-ups.md
   *  §1): marked stopped when the next scan started, or left unfinished over an hour; null when there's none. */
  scan_stopped?: ScanStopped | null;
  usage: { key: string; label: string; bytes: number; trigger_bytes: number }[];
}
/** A stopped scan as system_status() gives it: how far it got against the finished scan before it (private.scan_progress()). */
export interface ScanStopped {
  id: number;
  taken_at: string;
  status: string | null;
  note: string | null;
  airlines: number;
  airports: number;
  airlines_expected: number | null;
  airports_expected: number | null;
}

/** One line of the board. */
export interface SysLine {
  key: string;
  /** What it is: "Evening capture · Pan Am", "Nightly backup" ... */
  label: string;
  mark: Mark;
  /** When, in words ("15 Oct 00:11 UTC"), or null when nothing is recorded. */
  when: string | null;
  text: string;
}

const H = 3_600_000;
const RANK: Record<Mark, number> = { ok: 0, warn: 1, bad: 2 };
/** The worse of two marks. */
export const worse = (a: Mark, b: Mark): Mark => (RANK[b] > RANK[a] ? b : a);
/** Hours from a moment to now, or null without one. */
export const hoursSince = (at: string | null | undefined, now: Date): number | null => (at ? (now.getTime() - Date.parse(at)) / H : null);
/** A mark by age: amber past late, red past bad (both in hours, as Home's thresholds: over the limit, not at it). */
export function ageMark(hours: number | null, late: number, bad: number): Mark {
  if (hours == null) return "bad";
  return hours > bad ? "bad" : hours > late ? "warn" : "ok";
}
/** A usage mark: amber from 70% of the trigger, red at it. */
export function usageMark(bytes: number, trigger: number): Mark {
  if (!(trigger > 0)) return "ok";
  return bytes >= trigger ? "bad" : bytes >= USAGE_WARN_SHARE * trigger ? "warn" : "ok";
}
/** A size in words: 44.1 MB, 114 KB, 512 B (1,024 to the next). */
export function sizeWords(bytes: number): string {
  if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  if (bytes >= 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${Math.round(bytes)} B`;
}
/** A moment as the board writes it: "15 Oct 00:11 UTC". */
export function whenWords(at: string | null | undefined): string | null {
  if (!at) return null;
  const d = new Date(at);
  if (Number.isNaN(d.getTime())) return null;
  const mon = d.toLocaleString("en-GB", { month: "short", timeZone: "UTC" });
  return `${d.getUTCDate()} ${mon} ${d.toISOString().slice(11, 16)} UTC`;
}
/** An age in words: "40 minutes ago", "5 hours ago", "3 days ago". */
export function agoWords(hours: number | null): string {
  if (hours == null) return "never";
  if (hours < 1) return `${Math.max(0, Math.round(hours * 60))} minutes ago`;
  if (hours < 48) return `${Math.round(hours)} hours ago`;
  return `${Math.round(hours / 24)} days ago`;
}
const dayWords = (day: string | null | undefined): string => {
  if (!day) return "";
  const d = new Date(day + "T00:00:00Z");
  return Number.isNaN(d.getTime()) ? day : `${d.getUTCDate()} ${d.toLocaleString("en-GB", { month: "short", timeZone: "UTC" })}`;
};

/** An airline's evening capture: when, and the verdict on its pages (#21). */
export function captureLine(c: SysCapture, now: Date): SysLine {
  const h = hoursSince(c.last_at, now);
  let mark = ageMark(h, CAPTURE_LATE_H, CAPTURE_BAD_H);
  if (c.verdict === "broken") mark = worse(mark, "bad");
  else if (c.verdict === "short") mark = worse(mark, "warn");
  const words = c.last_at == null ? "no capture in the database's 14 days"
    : c.verdict == null ? "not checked (captured before the page checks)"
    : c.verdict_words || (c.verdict === "ok" ? "all good" : c.verdict);
  const late = h != null && h > CAPTURE_LATE_H ? ` · ${agoWords(h)}: press Capture all airlines in the game` : "";
  return { key: `capture|${c.airline_id}`, label: `Evening capture · ${c.name ?? c.code ?? "airline " + c.airline_id}`, mark, when: whenWords(c.last_at), text: words + late };
}

/** The daily snapshot: taken by the capture (green), or by the 10:00 UTC fallback and so incomplete (amber). */
export function snapshotLine(s: SystemStatus["snapshot"], now: Date): SysLine {
  const h = hoursSince(s.taken_at, now);
  let mark = ageMark(h, SNAPSHOT_LATE_H, SNAPSHOT_BAD_H);
  const fallback = !!s.source && s.source !== "capture";
  if (fallback || s.complete === false) mark = worse(mark, "warn");
  if (s.last_run?.status === "failed") mark = "bad";
  const fb = hoursSince(s.fallback_at, now);
  const parts = [
    s.day ? `${dayWords(s.day)}, ${s.source === "capture" ? "taken by the capture" : s.source === "fallback" ? "taken by the 10:00 UTC fallback, so incomplete" : `source ${s.source ?? "unknown"}`}`
      : "none taken yet",
  ];
  if (s.last_run?.status === "failed") parts.push(`the last run failed: ${s.last_run.note ?? "no note"}`);
  if (fb == null || fb > SCHEDULER_LATE_H) {
    mark = worse(mark, "warn");
    parts.push(fb == null ? "the 10:00 UTC job has never run" : `the 10:00 UTC job last ran ${agoWords(fb)}: the database's scheduler may have stopped`);
  }
  return { key: "snapshot", label: "Daily snapshot", mark, when: whenWords(s.taken_at), text: parts.join(" · ") };
}

/** The nightly backup: the last good copy (its restore check passed), its size, and whether the last run failed. */
export function backupLine(b: SystemStatus["backup"], now: Date): SysLine {
  const good = b.last_good;
  const h = hoursSince(good?.ran_at, now);
  let mark: Mark = !b.last && !good ? "warn" : ageMark(h, BACKUP_LATE_H, BACKUP_BAD_H);
  const parts: string[] = [];
  if (good) {
    parts.push(`last good copy ${agoWords(h)}, restore check passed`);
    if (good.bytes != null) parts.push(sizeWords(Number(good.bytes)));
    if (good.tables != null) parts.push(`${good.tables} tables, ${Number(good.rows ?? 0).toLocaleString("en-US")} rows`);
  } else {
    parts.push(b.last ? "no good copy yet" : "no copy yet");
  }
  if (b.last && b.last.ok === false) {
    mark = "bad";
    parts.push(`the last run failed (${whenWords(b.last.ran_at)}): ${String(b.last.note ?? "no note").slice(-160)}`);
  }
  return { key: "backup", label: "Nightly backup", mark, when: whenWords(good?.ran_at ?? b.last?.ran_at), text: parts.join(" · ") };
}

/** The monthly archive: this month's state, due by the 3rd; red when a table and month's last run failed. */
export function archiveLine(a: SystemStatus["archive"], now: Date): SysLine {
  const day = now.getUTCDate();
  const next = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + (a && a.runs_this_month > 0 ? 1 : 0), ARCHIVE_BY_DAY));
  const due = `due by ${next.getUTCDate()} ${next.toLocaleString("en-GB", { month: "short", timeZone: "UTC" })}`;
  let mark: Mark = "ok";
  let text: string;
  if (a && a.runs_this_month > 0) {
    text = `ran this month: ${a.ok_this_month} of ${a.runs_this_month} table-months, ${Number(a.rows_this_month).toLocaleString("en-US")} rows moved · next ${due}`;
  } else {
    text = `hasn't run this month · ${due}` + (a?.last_at ? ` · last ran ${whenWords(a.last_at)}` : " · never run");
    if (day >= ARCHIVE_BY_DAY) mark = "warn";
  }
  if (a && a.failed.length) {
    mark = "bad";
    text = a.failed.map((f) => `${f.table ?? "?"} ${String(f.month ?? "").slice(0, 7)} failed: ${f.note ?? "no note"}`).join(" · ") + " · " + text;
  }
  return { key: "archive", label: "Monthly archive", mark, when: whenWords(a?.last_at), text };
}

/** The clean-ups (10:20 UTC): the last run, red when it failed, late as a daily job. */
export function cleanupLine(c: SysJob | null, now: Date): SysLine {
  const h = hoursSince(c?.at, now);
  let mark = ageMark(h, JOB_LATE_H, JOB_BAD_H);
  if (c?.status === "failed") mark = "bad";
  const text = !c ? "never run" : `${c.status === "failed" ? "failed" : "ran"} ${agoWords(h)}${c.note ? ": " + c.note : ""}`;
  return { key: "cleanup", label: "Clean-ups (10:20 UTC)", mark, when: whenWords(c?.at), text };
}

/** How often the evening capture scans the world, from settings.scan_every_days: "every evening", "every 3 capture days". */
export function scanEveryWords(everyDays: number | null | undefined): string {
  const n = everyDays == null || !Number.isFinite(Number(everyDays)) ? null : Number(everyDays);
  if (n == null) return "when one is due (scan_every_days)";
  return n <= 1 ? "every evening (scan_every_days 1)" : `every ${n} capture days (scan_every_days ${n})`;
}

/** A stopped scan in words: "the scan of 21 Oct stopped after 812 of 1,040 airlines" (of the finished scan before it), or
 *  "stopped after 812 airlines" when there was none to compare with. */
export function stoppedWords(x: ScanStopped): string {
  const n = (v: number) => Number(v).toLocaleString("en-US");
  const of = x.airlines_expected != null ? ` of ${n(x.airlines_expected)}` : "";
  return `the scan of ${dayWords(String(x.taken_at).slice(0, 10))} stopped after ${n(x.airlines)}${of} airline${x.airlines_expected == null && Number(x.airlines) === 1 ? "" : "s"}`;
}

/** The world scan's age: amber over 8 days, red over 15. Since 21 Oct it runs with the evening capture when one is due
 *  (settings.scan_every_days; spec docs/specs/2026-10-21-competition-analysis.md §3), not at the Saturday review. Since
 *  22 Oct (spec docs/specs/2026-10-21-tidy-ups.md §1) a scan that stopped part-way, with no finished scan after it, says
 *  so in amber, not red: the next capture scans again. */
export function scanLine(s: SystemStatus["scan"], now: Date, everyDays?: number | null, stopped?: ScanStopped | null): SysLine {
  const h = hoursSince(s?.taken_at, now);
  const d = h == null ? null : h / 24;
  const age: Mark = d == null || d > SCAN_BAD_D ? "bad" : d > SCAN_LATE_D ? "warn" : "ok";
  const runs = `runs with the evening capture ${scanEveryWords(everyDays)}`;
  const stop = stopped ? ` · ${stoppedWords(stopped)}; the next capture scans again` : "";
  const text = !s ? `no world scan yet${stop} · ${runs}` : `${agoWords(h)}${s.week ? ` (week ${s.week})` : ""}${stop} · ${runs}`
    + (age === "ok" ? "" : "; capture again while it's due, or gscan.py by hand");
  return { key: "scan", label: "World scan", mark: stopped ? worse(age, "warn") : age, when: whenWords(s?.taken_at), text };
}

/** The planner's own build: when and from which change (after a merge, a time that hasn't moved means the deploy failed). */
export function buildLine(b: BuildStamp | null): SysLine {
  if (!b) return { key: "build", label: "Planner build", mark: "warn", when: null, text: "this planner carries no build stamp (built without vite.config.ts's stamp)" };
  const change = b.commit ? b.commit.slice(0, 7) + (b.subject ? ` · ${b.subject}` : "") : "change unknown";
  return { key: "build", label: "Planner build", mark: "ok", when: whenWords(b.at),
    text: `built from ${change} · after a merge this time moves within minutes; if it doesn't, Cloudflare's build failed` };
}

/** A usage figure against its trigger. */
export function usageLine(u: SystemStatus["usage"][number]): SysLine {
  const bytes = Number(u.bytes), trigger = Number(u.trigger_bytes);
  const pct = trigger > 0 ? Math.round((bytes / trigger) * 100) : 0;
  return { key: "usage|" + u.key, label: u.label, mark: usageMark(bytes, trigger), when: null,
    text: `${sizeWords(bytes)} of ${sizeWords(trigger)} (${pct}%)${bytes >= trigger ? " · the trigger is reached: a brief at the next weekly review" : ""}` };
}

/** Every line of the board, in its order (the scan's with how often the capture takes one, scan_every_days). */
export function systemLines(s: SystemStatus, build: BuildStamp | null, now: Date, scanEveryDays?: number | null): SysLine[] {
  return [
    ...s.capture.map((c) => captureLine(c, now)),
    snapshotLine(s.snapshot ?? {}, now),
    backupLine(s.backup ?? { last: null, last_good: null }, now),
    archiveLine(s.archive, now),
    cleanupLine(s.cleanup, now),
    scanLine(s.scan, now, scanEveryDays, s.scan_stopped),
    buildLine(build),
    ...(s.usage ?? []).map(usageLine),
  ];
}

/** The board's own line: how many lines are green, amber and red. */
export function boardSummary(lines: readonly SysLine[]): { mark: Mark; text: string } {
  const n = (m: Mark) => lines.filter((l) => l.mark === m).length;
  const mark = lines.reduce<Mark>((m, l) => worse(m, l.mark), "ok");
  return { mark, text: mark === "ok" ? "all good" : [n("bad") ? `${n("bad")} red` : "", n("warn") ? `${n("warn")} amber` : ""].filter(Boolean).join(", ") };
}
