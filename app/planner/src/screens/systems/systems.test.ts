// The Systems board's marks at each limit (decision #23, spec part 2 and "Checks"): the capture at 26 and 48 hours and
// with #21's verdicts, the snapshot and backup at 30 hours (red at 54, as Home), the archive by the 3rd, a failed run,
// the world scan at 8 and 15 days (and amber for a scan that stopped part-way, 22 Oct), usage at 70% and at the trigger,
// and the planner's build stamp.
import { describe, expect, it } from "vitest";
import {
  ageMark, archiveLine, backupLine, boardSummary, buildLine, captureLine, cleanupLine, scanEveryWords, scanLine, sizeWords, snapshotLine, stoppedWords, systemLines,
  usageLine, usageMark, type ScanStopped, type SysCapture, type SystemStatus,
} from "./systems";

const now = new Date("2026-10-15T12:00:00Z");
const ago = (h: number) => new Date(now.getTime() - h * 3_600_000).toISOString();
const cap = (x: Partial<SysCapture> = {}): SysCapture => ({
  airline_id: 1, code: "PA", name: "Pan Am", last_at: ago(1), verdict: "ok", verdict_words: "all good", verdict_at: ago(1), missing: [], ...x,
});

describe("marks by age and usage", () => {
  it("over a limit, not at it", () => {
    expect([ageMark(26, 26, 48), ageMark(26.01, 26, 48), ageMark(48, 26, 48), ageMark(48.01, 26, 48), ageMark(null, 26, 48)])
      .toEqual(["ok", "warn", "warn", "bad", "bad"]);
  });
  it("usage: amber from 70% of the trigger, red at it", () => {
    expect([usageMark(69, 100), usageMark(70, 100), usageMark(99, 100), usageMark(100, 100), usageMark(5, 0)]).toEqual(["ok", "warn", "warn", "bad", "ok"]);
  });
  it("sizes in words", () => {
    expect([sizeWords(512), sizeWords(116_736), sizeWords(46_242_201)]).toEqual(["512 B", "114 KB", "44.1 MB"]);
  });
});

describe("the evening capture, each airline (#21's verdict)", () => {
  it("at 26 and 48 hours, as Home", () => {
    expect(captureLine(cap({ last_at: ago(26) }), now).mark).toBe("ok");
    expect(captureLine(cap({ last_at: ago(26.5) }), now).mark).toBe("warn");
    expect(captureLine(cap({ last_at: ago(48.5) }), now).mark).toBe("bad");
    expect(captureLine(cap({ last_at: null, verdict: null }), now)).toMatchObject({ mark: "bad", when: null, text: "no capture in the database's 14 days" });
  });
  it("the verdict: all good, short (amber), broken (red), not checked", () => {
    expect(captureLine(cap(), now)).toMatchObject({ key: "capture|1", label: "Evening capture · Pan Am", mark: "ok", when: "15 Oct 11:00 UTC", text: "all good" });
    expect(captureLine(cap({ verdict: "short", verdict_words: "short: loads 12 of 78 flights" }), now))
      .toMatchObject({ mark: "warn", text: "short: loads 12 of 78 flights" });
    expect(captureLine(cap({ verdict: "broken", verdict_words: "broken: balance sheet without the cash account (2800)" }), now).mark).toBe("bad");
    expect(captureLine(cap({ verdict: null, verdict_words: null }), now)).toMatchObject({ mark: "ok", text: "not checked (captured before the page checks)" });
    // short and late: the worse
    expect(captureLine(cap({ last_at: ago(30), verdict: "short", verdict_words: "short: x" }), now))
      .toMatchObject({ mark: "warn", text: "short: x · 30 hours ago: press Capture all airlines in the game" });
    expect(captureLine(cap({ last_at: ago(50), verdict: "short", verdict_words: "short: x" }), now).mark).toBe("bad");
  });
});

describe("the jobs", () => {
  const snap = (x: Partial<SystemStatus["snapshot"]> = {}): SystemStatus["snapshot"] => ({
    day: "2026-10-14", source: "capture", complete: true, taken_at: ago(12), last_run: { job: "snapshot_fallback", status: "ok", at: ago(2), note: null }, fallback_at: ago(2), ...x,
  });
  it("the snapshot: taken by the capture, by the fallback (incomplete), late at 30 and 54 hours, a failed run, the scheduler stopped", () => {
    expect(snapshotLine(snap(), now)).toMatchObject({ mark: "ok", text: "14 Oct, taken by the capture" });
    expect(snapshotLine(snap({ source: "fallback", complete: false }), now)).toMatchObject({ mark: "warn", text: "14 Oct, taken by the 10:00 UTC fallback, so incomplete" });
    expect(snapshotLine(snap({ taken_at: ago(30) }), now).mark).toBe("ok");
    expect(snapshotLine(snap({ taken_at: ago(31) }), now).mark).toBe("warn");
    expect(snapshotLine(snap({ taken_at: ago(55) }), now).mark).toBe("bad");
    expect(snapshotLine(snap({ last_run: { job: "snapshot", status: "failed", at: ago(1), note: "boom" } }), now)).toMatchObject({ mark: "bad" });
    expect(snapshotLine(snap({ fallback_at: ago(31) }), now)).toMatchObject({ mark: "warn" });
    expect(snapshotLine(snap({ fallback_at: ago(31) }), now).text).toContain("the 10:00 UTC job last ran 31 hours ago");
  });
  it("the backup: the last good copy at 30 and 54 hours, its size, a failed last run, none yet", () => {
    const good = (h: number) => ({ ran_at: ago(h), bytes: 120 * 1024 * 1024, tables: 60, rows: 210_000, files: 90 });
    expect(backupLine({ last: { ran_at: ago(5), ok: true, kind: "nightly", note: null }, last_good: good(5) }, now))
      .toMatchObject({ mark: "ok", text: "last good copy 5 hours ago, restore check passed · 120.0 MB · 60 tables, 210,000 rows" });
    expect(backupLine({ last: { ran_at: ago(30), ok: true, kind: "nightly", note: null }, last_good: good(30) }, now).mark).toBe("ok");
    expect(backupLine({ last: { ran_at: ago(31), ok: true, kind: "nightly", note: null }, last_good: good(31) }, now).mark).toBe("warn");
    expect(backupLine({ last: { ran_at: ago(55), ok: true, kind: "nightly", note: null }, last_good: good(55) }, now).mark).toBe("bad");
    expect(backupLine({ last: { ran_at: ago(2), ok: false, kind: "nightly", note: "upload failed" }, last_good: good(26) }, now).mark).toBe("bad");
    expect(backupLine({ last: null, last_good: null }, now)).toMatchObject({ mark: "warn", text: "no copy yet" });
  });
  it("the archive: by the 3rd; ran this month; a table and month that failed", () => {
    const none = { last_at: "2026-09-02T07:30:00Z", month: "2026-10-01", runs_this_month: 0, ok_this_month: 0, rows_this_month: 0, failed: [] };
    expect(archiveLine(none, new Date("2026-10-02T12:00:00Z"))).toMatchObject({ mark: "ok" });
    expect(archiveLine(none, new Date("2026-10-03T00:00:00Z"))).toMatchObject({ mark: "warn" });
    expect(archiveLine(none, new Date("2026-10-03T00:00:00Z")).text).toContain("hasn't run this month · due by 3 Oct");
    const ran = { ...none, last_at: ago(80), runs_this_month: 4, ok_this_month: 4, rows_this_month: 12_345 };
    expect(archiveLine(ran, now)).toMatchObject({ mark: "ok", text: "ran this month: 4 of 4 table-months, 12,345 rows moved · next due by 3 Nov" });
    expect(archiveLine({ ...ran, failed: [{ table: "game_flights", month: "2026-09-01", at: ago(80), note: "checksum" }] }, now).mark).toBe("bad");
    expect(archiveLine(null, new Date("2026-10-05T00:00:00Z")).mark).toBe("warn");
  });
  it("the clean-ups: late as a daily job, red when the last run failed", () => {
    expect(cleanupLine({ at: ago(2), status: "ok", note: "raw pages: 30 deleted" }, now)).toMatchObject({ mark: "ok", text: "ran 2 hours ago: raw pages: 30 deleted" });
    expect(cleanupLine({ at: ago(30), status: "ok", note: null }, now).mark).toBe("ok");
    expect(cleanupLine({ at: ago(31), status: "ok", note: null }, now).mark).toBe("warn");
    expect(cleanupLine({ at: ago(55), status: "ok", note: null }, now).mark).toBe("bad");
    expect(cleanupLine({ at: ago(2), status: "failed", note: "3 statement lines" }, now).mark).toBe("bad");
    expect(cleanupLine(null, now)).toMatchObject({ mark: "bad", text: "never run" });
  });
  it("the world scan: amber over 8 days, red over 15", () => {
    const scan = (d: number) => ({ taken_at: ago(d * 24), week: "41", status: "done" });
    expect([scanLine(scan(8), now).mark, scanLine(scan(8.1), now).mark, scanLine(scan(15), now).mark, scanLine(scan(15.1), now).mark, scanLine(null, now).mark])
      .toEqual(["ok", "warn", "warn", "bad", "bad"]);
  });
  it("the world scan runs with the evening capture (scan_every_days), not at the Saturday review (21 Oct)", () => {
    const scan = (d: number) => ({ taken_at: ago(d * 24), week: "43", status: "done" });
    expect(scanLine(scan(0.5), now, 1).text).toMatch(/ · runs with the evening capture every evening \(scan_every_days 1\)$/);
    expect(scanLine(scan(9), now, 3).text).toMatch(/runs with the evening capture every 3 capture days \(scan_every_days 3\); capture again while it's due, or gscan\.py by hand$/);
    expect(scanLine(null, now).text).toBe("no world scan yet · runs with the evening capture when one is due (scan_every_days)");
    expect(scanEveryWords(2)).toBe("every 2 capture days (scan_every_days 2)");
    for (const x of [scanLine(scan(1), now, 1), scanLine(scan(20), now, 1), scanLine(null, now)]) expect(x.text).not.toMatch(/Saturday/);
  });
  it("a scan that stopped part-way, with none finished after it: amber, not red, saying how far it got (22 Oct)", () => {
    const scan = (d: number) => ({ taken_at: ago(d * 24), week: "43", status: "done" });
    const stopped = (x: Partial<ScanStopped> = {}): ScanStopped => ({
      id: 9, taken_at: "2026-10-14T01:10:00.000Z", status: "stopped", note: "stopped part-way…", airlines: 812, airports: 0,
      airlines_expected: 1040, airports_expected: 97, ...x,
    });
    expect(stoppedWords(stopped())).toBe("the scan of 14 Oct stopped after 812 of 1,040 airlines");
    expect(stoppedWords(stopped({ airlines_expected: null, airlines: 1 }))).toBe("the scan of 14 Oct stopped after 1 airline");
    const l = scanLine(scan(2), now, 1, stopped());
    expect(l.mark).toBe("warn");
    expect(l.text).toBe("2 days ago (week 43) · the scan of 14 Oct stopped after 812 of 1,040 airlines; the next capture scans again · runs with the evening capture every evening (scan_every_days 1)");
    // red stays red by age; with no stop, as before
    expect(scanLine(scan(16), now, 1, stopped()).mark).toBe("bad");
    expect(scanLine(scan(2), now, 1, null).mark).toBe("ok");
    expect(scanLine(null, now, 1, stopped()).text).toMatch(/^no world scan yet · the scan of 14 Oct stopped after 812 of 1,040 airlines; the next capture scans again · /);
    // system_status()'s scan_stopped reaches the line
    const s: SystemStatus = {
      as_of: now.toISOString(), capture: [], snapshot: {}, backup: { last: null, last_good: null }, archive: null, cleanup: null,
      scan: scan(1), scan_stopped: stopped(), usage: [],
    };
    expect(systemLines(s, null, now, 1).find((x) => x.key === "scan")?.mark).toBe("warn");
  });
});

describe("the planner's build and the usage", () => {
  it("the build: when and from which change; without a stamp, amber", () => {
    expect(buildLine({ at: "2026-10-15T09:05:00Z", commit: "5c947c8d0e", subject: "Capture checks" }))
      .toMatchObject({ mark: "ok", when: "15 Oct 09:05 UTC", text: "built from 5c947c8 · Capture checks · after a merge this time moves within minutes; if it doesn't, Cloudflare's build failed" });
    expect(buildLine(null).mark).toBe("warn");
  });
  it("usage against its trigger", () => {
    expect(usageLine({ key: "database", label: "Database size", bytes: 44 * 1024 * 1024, trigger_bytes: 350 * 1024 * 1024 }))
      .toMatchObject({ key: "usage|database", mark: "ok", text: "44.0 MB of 350.0 MB (13%)" });
    expect(usageLine({ key: "site_public", label: "The website's data", bytes: 360 * 1024, trigger_bytes: 500 * 1024 }).mark).toBe("warn");
    expect(usageLine({ key: "report_pdfs", label: "Report PDFs", bytes: 50 * 1024 * 1024, trigger_bytes: 50 * 1024 * 1024 }).mark).toBe("bad");
  });
  it("every line in order, each marked, and the board's summary", () => {
    const s: SystemStatus = {
      as_of: now.toISOString(), capture: [cap(), cap({ airline_id: 2, name: "Kingfisher", verdict: "short", verdict_words: "short: loads 1 of 9 flights" })],
      snapshot: { day: "2026-10-14", source: "capture", complete: true, taken_at: ago(12), last_run: null, fallback_at: ago(2) },
      backup: { last: { ran_at: ago(5), ok: true, kind: "nightly", note: null }, last_good: { ran_at: ago(5), bytes: 1, tables: 1, rows: 1, files: 1 } },
      archive: { last_at: ago(80), month: "2026-10-01", runs_this_month: 1, ok_this_month: 1, rows_this_month: 1, failed: [] },
      cleanup: { at: ago(2), status: "ok", note: null }, scan: { taken_at: ago(24), week: "41", status: "done" },
      usage: [{ key: "database", label: "Database size", bytes: 1, trigger_bytes: 10 }],
    };
    const lines = systemLines(s, { at: ago(3), commit: "abc1234", subject: "" }, now);
    expect(lines.map((l) => [l.key, l.mark])).toEqual([
      ["capture|1", "ok"], ["capture|2", "warn"], ["snapshot", "ok"], ["backup", "ok"], ["archive", "ok"], ["cleanup", "ok"], ["scan", "ok"], ["build", "ok"], ["usage|database", "ok"],
    ]);
    expect(boardSummary(lines)).toEqual({ mark: "warn", text: "1 amber" });
    expect(boardSummary(lines.filter((l) => l.mark === "ok"))).toEqual({ mark: "ok", text: "all good" });
  });
});
