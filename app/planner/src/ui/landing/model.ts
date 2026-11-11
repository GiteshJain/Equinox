// The landing page's decisions and words (since 11 Nov; to-do 223, spec docs/specs/2026-11-11-stored-figures.md §2): one
// full-window page shown instead of the screens while a capture runs, while its figures are worked out, and while the
// planner loads the stored set and the tables it opens with. Pure: every moment it compares is the database's
// (planner_figures_status()'s `at` and its times), so the browser's clock never decides. Its look is Landing.tsx alone, so
// a restyle (the glass look, to-do 225) touches nothing here.

/** planner_figures_status()'s answer (migration 20261111020000_stored_figures.sql), the parts the planner reads. */
export interface FiguresStatus {
  at: string;
  generation: number;
  ready_at?: string | null;
  set_as_of?: string | null;
  capture: {
    running: boolean;
    what: "capture" | "world scan" | "market pages" | null;
    since?: string | null;
    stage_since?: string | null;
    last_page_at?: string | null;
    capture?: { airlines_done?: number | null; airlines_total?: number | null; airline?: string | null } | null;
    scan?: { airlines?: number | null; airlines_expected?: number | null } | null;
    market?: { pages_read?: number | null; pages_expected?: number | null } | null;
  };
  refresh: { due: boolean; reason: string | null; waiting_until?: string | null; running: boolean; running_since?: string | null };
  last_error?: string | null;
  last_error_at?: string | null;
  landing_max_min?: number | string | null;
}

/** Where the planner stands, everything the decision needs. */
export interface LandingInput {
  /** The latest status answer, or null before the first. */
  status: FiguresStatus | null;
  /** Status calls that failed in a row since the last answer. */
  failures: number;
  /** The last failure's message. */
  statusError?: string | null;
  /** The set in memory: its generation (0: none) and the capture it was worked out from; null before the first load ends. */
  loaded: { generation: number; captureAt: string | null } | null;
  /** The opening's reads, done of all; null once they have all come back. */
  opening: { done: number; total: number } | null;
  /** A newer set being loaded, done of all (its pages): null when none is. */
  reloading: { done: number; total: number } | null;
  /** Why the last read of a stored set failed (null when it went through): a newer set that can't be read never holds the
   *  planner. */
  loadError?: string | null;
  /** The last status `at` that said a capture was running, this session. */
  sawRunningAt: string | null;
  /** Whether the landing page was showing at the last decision (a new set loaded after a capture keeps it until it's in). */
  showing: boolean;
  /** A moment in the planner's time mode, for the line ("09:30 UTC"). */
  time: (iso: string) => string;
}

export type Decision =
  | { show: true; line: string; detail: string | null }
  | { show: false; note: string | null };

/** The status's three failed calls in a row: past that, the planner opens on what it has. */
export const MAX_STATUS_FAILURES = 3;
/** No new set this long after a capture ends: the planner opens on the last one. */
export const AFTER_CAPTURE_MIN = 10;
/** settings.figures_landing_max_min's default (the status gives the world's). */
export const LANDING_MAX_MIN = 30;
/** How often the status is asked: every 30 s; after a failure while the landing page shows, again in 5 s, so three failures
 *  in a row open the planner in seconds rather than a minute and a half. */
export const POLL_MS = 30_000;
export const RETRY_MS = 5_000;

const minutes = (from: string | null | undefined, to: string): number => {
  const a = from ? Date.parse(from) : NaN, b = Date.parse(to);
  return Number.isFinite(a) && Number.isFinite(b) ? (b - a) / 60_000 : Infinity;
};
const later = (a: string | null | undefined, b: string | null | undefined): string | null => {
  if (!a) return b ?? null;
  if (!b) return a;
  return Date.parse(b) > Date.parse(a) ? b : a;
};
const n = (v: unknown): number | null => (v == null || v === "" || !Number.isFinite(Number(v)) ? null : Number(v));
const of = (a: number | null, b: number | null) => (a != null && b != null ? `${a.toLocaleString("en-US")} of ${b.toLocaleString("en-US")}` : a != null ? a.toLocaleString("en-US") : null);

/** The line a capture shows while it runs: "Capture running · Ryanair (3 of 6)", "World scan · 120 of 163 airlines",
 *  "Market pages · 340 of 686". */
export function captureLine(c: FiguresStatus["capture"]): string {
  if (c.what === "market pages") {
    const p = of(n(c.market?.pages_read), n(c.market?.pages_expected));
    return "Market pages" + (p ? " · " + p : "");
  }
  if (c.what === "world scan") {
    const p = of(n(c.scan?.airlines), n(c.scan?.airlines_expected));
    return "World scan" + (p ? ` · ${p} airlines` : "");
  }
  const done = n(c.capture?.airlines_done), total = n(c.capture?.airlines_total), name = c.capture?.airline;
  const count = done != null && total != null ? `${done} of ${total}` : null;
  return "Capture running" + (name ? ` · ${name}${count ? ` (${count})` : ""}` : count ? ` · ${count}` : "");
}

/** Whether the status says a new set is being worked out after a capture, scan or market run (a save alone, or the very
 *  first set, never holds the planner). */
export const dueAfterCapture = (s: FiguresStatus): boolean =>
  s.refresh.due && !!s.refresh.reason && s.refresh.reason !== "planner saves" && s.refresh.reason !== "first set";

/** When the capture ended as far as the planner can tell: its last page, or later the last status this session that saw it
 *  running (the world scan and market pages come after the pages). */
export const captureEnded = (s: FiguresStatus, sawRunningAt: string | null): string | null => later(s.capture.last_page_at, sawRunningAt);

/** What holds the planner on the landing page now, by the status alone: the capture's line, the figures being worked out,
 *  or nothing; with why, when a limit has passed. */
function blocker(s: FiguresStatus, sawRunningAt: string | null): { line: string } | { why: string } | null {
  const max = n(s.landing_max_min) ?? LANDING_MAX_MIN;
  if (s.capture.running) {
    if (minutes(s.capture.since, s.at) < max) return { line: captureLine(s.capture) };
    return { why: `the capture has been running for over ${max} minutes` };
  }
  if (dueAfterCapture(s)) {
    if (minutes(captureEnded(s, sawRunningAt), s.at) < AFTER_CAPTURE_MIN) return { line: "Working out the figures…" };
    return { why: `they still weren't worked out ${AFTER_CAPTURE_MIN} minutes after the capture ended` + (s.last_error ? ` (${s.last_error})` : "") };
  }
  return null;
}

/** The line at the top of every screen when the planner opened on older figures: "Figures from the 09:30 UTC capture: the
 *  new ones aren't ready because …". */
function staleNote(x: LandingInput, why: string): string {
  const has = x.loaded && x.loaded.generation > 0;
  if (!has) return `The stored figures aren't ready because ${why}: the figures are worked out as each screen asks.`;
  const cap = x.loaded?.captureAt ? `the ${x.time(x.loaded.captureAt)} capture` : "the previous capture";
  return `Figures from ${cap}: the new ones aren't ready because ${why}.`;
}

/** Show the landing page, and which line; or open the screens, with the line at their top when a limit has passed. */
export function decide(x: LandingInput): Decision {
  const loading = x.opening ?? (x.showing ? x.reloading : null);
  const loadLine = (p: { done: number; total: number }) => ({ show: true as const, line: `Loading… ${p.done} of ${p.total}`, detail: null });

  if (!x.status) {
    if (x.failures >= MAX_STATUS_FAILURES) {
      if (x.opening) return loadLine(x.opening);
      return { show: false, note: staleNote(x, `the planner can't read where they stand${x.statusError ? ` (${x.statusError})` : ""}`) };
    }
    return x.opening ? loadLine(x.opening) : { show: true, line: "Loading…", detail: null };
  }
  // a status that failed three times since its last answer: open on what is loaded
  const b = x.failures >= MAX_STATUS_FAILURES ? { why: `the planner can't read where they stand${x.statusError ? ` (${x.statusError})` : ""}` } : blocker(x.status, x.sawRunningAt);
  if (b && "line" in b) {
    const detail = loading ? `Loading… ${loading.done} of ${loading.total}` : null;
    return { show: true, line: b.line, detail };
  }
  if (loading) return loadLine(loading);
  // a new set stored after a capture: kept until it has loaded, unless it can't be read
  const newer = !!x.loaded && x.status.generation > x.loaded.generation;
  if (newer && x.loadError) return { show: false, note: staleNote(x, `they couldn't be loaded (${x.loadError})`) };
  if (x.showing && newer) return { show: true, line: "Loading the new figures…", detail: null };
  return { show: false, note: b ? staleNote(x, b.why) : null };
}

/** How long until the status is asked again (setTimeout after each answer, never while one is unanswered). */
export const nextPollMs = (failures: number, showing: boolean): number => (failures > 0 && showing ? RETRY_MS : POLL_MS);

/** The last status `at` that saw a capture running: moved on by each answer that says one is. */
export const sawRunning = (prev: string | null, s: FiguresStatus): string | null => (s.capture.running ? later(prev, s.at) : prev);

/** Whether the planner should load the set again: the status names a generation other than the one in memory (and none is
 *  loading). */
export const needsLoad = (s: FiguresStatus | null, loadedGeneration: number | null, loading: boolean): boolean =>
  !!s && !loading && loadedGeneration !== null && s.generation !== loadedGeneration;
