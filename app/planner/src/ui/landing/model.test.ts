import { describe, expect, it } from "vitest";
import {
  captureLine, decide, needsLoad, nextPollMs, POLL_MS, RETRY_MS, sawRunning, type FiguresStatus, type LandingInput,
} from "./model";

const AT = "2026-11-11T09:50:00.000Z";
const mins = (iso: string, m: number) => new Date(Date.parse(iso) + m * 60_000).toISOString();

/** A status at a moment: nothing running and the set up to date, unless told otherwise. */
function status(o: Partial<Omit<FiguresStatus, "capture" | "refresh">> & { capture?: Partial<FiguresStatus["capture"]>; refresh?: Partial<FiguresStatus["refresh"]> } = {}): FiguresStatus {
  return {
    at: AT, generation: 4, landing_max_min: 30, ...o,
    capture: { what: null, last_page_at: mins(AT, -600), ...o.capture, running: o.capture?.running ?? false },
    refresh: { reason: null, ...o.refresh, due: o.refresh?.due ?? false, running: o.refresh?.running ?? false },
  };
}
const input = (o: Partial<LandingInput> = {}): LandingInput => ({
  status: status(), failures: 0, statusError: null, loaded: { generation: 4, captureAt: "2026-11-10T21:30:00.000Z" }, opening: null, reloading: null,
  sawRunningAt: null, showing: false, time: (iso) => iso.slice(11, 16) + " UTC", ...o,
});

describe("the first opening", () => {
  it("shows the landing page with the loading's progress until the set and the tables are in", () => {
    expect(decide(input({ status: null, loaded: null, opening: { done: 0, total: 24 }, showing: true })))
      .toEqual({ show: true, line: "Loading… 0 of 24", detail: null });
    expect(decide(input({ loaded: null, opening: { done: 18, total: 24 }, showing: true })))
      .toEqual({ show: true, line: "Loading… 18 of 24", detail: null });
  });
  it("waits for the first status even when the reads are in", () => {
    expect(decide(input({ status: null, showing: true }))).toEqual({ show: true, line: "Loading…", detail: null });
  });
  it("opens once everything is loaded and nothing is running", () => {
    expect(decide(input({ showing: true }))).toEqual({ show: false, note: null });
  });
  it("with no stored set at all (generation 0, the first set due), opens and reads live", () => {
    const s = status({ generation: 0, refresh: { due: true, reason: "first set" } });
    expect(decide(input({ status: s, loaded: { generation: 0, captureAt: null }, showing: true }))).toEqual({ show: false, note: null });
  });
});

describe("a capture running", () => {
  it("shows its line while it runs: the airlines' pages, the world scan, the market pages", () => {
    const pages = status({ capture: { running: true, what: "capture", since: mins(AT, -3), capture: { airlines_done: 3, airlines_total: 6, airline: "Ryanair" } } });
    expect(decide(input({ status: pages }))).toEqual({ show: true, line: "Capture running · Ryanair (3 of 6)", detail: null });
    const scan = status({ capture: { running: true, what: "world scan", since: mins(AT, -8), scan: { airlines: 120, airlines_expected: 163 } } });
    expect(decide(input({ status: scan }))).toMatchObject({ show: true, line: "World scan · 120 of 163 airlines" });
    const market = status({ capture: { running: true, what: "market pages", since: mins(AT, -15), market: { pages_read: 340, pages_expected: 686 } } });
    expect(decide(input({ status: market }))).toMatchObject({ show: true, line: "Market pages · 340 of 686" });
  });
  it("on opening during a capture, the capture's line with the loading under it", () => {
    const s = status({ capture: { running: true, what: "capture", since: mins(AT, -1), capture: { airlines_done: 1, airlines_total: 6, airline: "Pan Am" } } });
    expect(decide(input({ status: s, opening: { done: 5, total: 24 } }))).toEqual({ show: true, line: "Capture running · Pan Am (1 of 6)", detail: "Loading… 5 of 24" });
  });
  it("past figures_landing_max_min (30) minutes, opens on the last answers with the line saying why", () => {
    const s = status({ capture: { running: true, what: "market pages", since: mins(AT, -31) } });
    expect(decide(input({ status: s, showing: true }))).toEqual({
      show: false, note: "Figures from the 21:30 UTC capture: the new ones aren't ready because the capture has been running for over 30 minutes.",
    });
    // the world's own limit
    const s20 = status({ landing_max_min: 20, capture: { running: true, what: "world scan", since: mins(AT, -21) } });
    expect(decide(input({ status: s20 })).show).toBe(false);
    expect(decide(input({ status: { ...s20, landing_max_min: 30 } })).show).toBe(true);
  });
  it("words a capture with missing counts plainly", () => {
    expect(captureLine({ running: true, what: "capture" })).toBe("Capture running");
    expect(captureLine({ running: true, what: "world scan", scan: { airlines: 12 } })).toBe("World scan · 12 airlines");
    expect(captureLine({ running: true, what: "market pages", market: { pages_read: 1340, pages_expected: 2686 } })).toBe("Market pages · 1,340 of 2,686");
  });
});

describe("after a capture", () => {
  const due = (o: Partial<FiguresStatus["refresh"]> = {}, lastPage = -4) =>
    status({ capture: { running: false, what: null, last_page_at: mins(AT, lastPage) }, refresh: { due: true, reason: "new capture, world scan", ...o } });
  it("works the figures out: the landing page stays until the new set is stored", () => {
    expect(decide(input({ status: due() }))).toEqual({ show: true, line: "Working out the figures…", detail: null });
    expect(decide(input({ status: due({ running: true }) }))).toMatchObject({ show: true, line: "Working out the figures…" });
  });
  it("and until it has loaded", () => {
    const stored = status({ generation: 5 });
    expect(decide(input({ status: stored, showing: true }))).toEqual({ show: true, line: "Loading the new figures…", detail: null });
    expect(decide(input({ status: stored, showing: true, reloading: { done: 0, total: 1 } }))).toEqual({ show: true, line: "Loading… 0 of 1", detail: null });
    expect(decide(input({ status: stored, showing: true, loaded: { generation: 5, captureAt: "2026-11-11T09:46:00.000Z" } }))).toEqual({ show: false, note: null });
  });
  it("a new set that can't be read doesn't hold the planner", () => {
    expect(decide(input({ status: status({ generation: 5 }), showing: true, loadError: "Failed to fetch" }))).toEqual({
      show: false, note: "Figures from the 21:30 UTC capture: the new ones aren't ready because they couldn't be loaded (Failed to fetch).",
    });
  });
  it("a new set from a save alone loads in the background", () => {
    expect(decide(input({ status: status({ generation: 5 }), showing: false, reloading: { done: 0, total: 1 } }))).toEqual({ show: false, note: null });
  });
  it("10 minutes after the capture ended with no new set, opens on the last answers", () => {
    expect(decide(input({ status: due({}, -9.9) })).show).toBe(true);
    expect(decide(input({ status: due({}, -10.5) }))).toEqual({
      show: false, note: "Figures from the 21:30 UTC capture: the new ones aren't ready because they still weren't worked out 10 minutes after the capture ended.",
    });
    // the last error named
    const failing = { ...due({}, -12), last_error: "the refresh failed: timeout" };
    expect(decide(input({ status: failing }))).toMatchObject({ show: false, note: expect.stringContaining("(the refresh failed: timeout)") });
  });
  it("the capture's end is the last status that saw it running, when that's later than its last page (scan, market pages)", () => {
    const s = due({}, -25);
    expect(decide(input({ status: s, sawRunningAt: mins(AT, -2) }))).toMatchObject({ show: true, line: "Working out the figures…" });
    expect(sawRunning(null, status({ capture: { running: true, what: "market pages", since: mins(AT, -20) } }))).toBe(AT);
    expect(sawRunning(mins(AT, -1), status())).toBe(mins(AT, -1));
  });
});

describe("a refresh caused by planner saves", () => {
  it("never shows the landing page", () => {
    const s = status({ refresh: { due: true, reason: "planner saves", waiting_until: mins(AT, 1) } });
    expect(decide(input({ status: s }))).toEqual({ show: false, note: null });
    expect(decide(input({ status: { ...s, refresh: { ...s.refresh, running: true } } }))).toEqual({ show: false, note: null });
  });
});

describe("the status failing", () => {
  it("keeps the landing page through two failures in a row, and opens after the third with the line", () => {
    expect(decide(input({ status: null, failures: 2, statusError: "Failed to fetch", showing: true }))).toEqual({ show: true, line: "Loading…", detail: null });
    expect(decide(input({ status: null, failures: 3, statusError: "Failed to fetch", showing: true }))).toEqual({
      show: false, note: "Figures from the 21:30 UTC capture: the new ones aren't ready because the planner can't read where they stand (Failed to fetch).",
    });
  });
  it("a capture's landing page gives way after three failures too", () => {
    const s = status({ capture: { running: true, what: "capture", since: mins(AT, -2) } });
    expect(decide(input({ status: s, failures: 2 })).show).toBe(true);
    expect(decide(input({ status: s, failures: 3 }))).toMatchObject({ show: false, note: expect.stringContaining("can't read where they stand") });
  });
  it("still finishes the opening's loading first", () => {
    expect(decide(input({ status: null, failures: 3, opening: { done: 3, total: 24 } }))).toMatchObject({ show: true, line: "Loading… 3 of 24" });
  });
  it("with no stored set, the line says the figures are worked out as each screen asks", () => {
    expect(decide(input({ status: null, failures: 3, loaded: { generation: 0, captureAt: null } }))).toEqual({
      show: false, note: "The stored figures aren't ready because the planner can't read where they stand: the figures are worked out as each screen asks.",
    });
  });
  it("asks again in 5 s after a failure while the landing page shows, else every 30 s", () => {
    expect(nextPollMs(0, true)).toBe(POLL_MS);
    expect(nextPollMs(1, true)).toBe(RETRY_MS);
    expect(nextPollMs(2, false)).toBe(POLL_MS);
    expect(POLL_MS).toBe(30_000);
  });
});

describe("loading a new set", () => {
  it("when the status names another generation than the one in memory, and none is loading", () => {
    expect(needsLoad(status({ generation: 5 }), 4, false)).toBe(true);
    expect(needsLoad(status({ generation: 5 }), 4, true)).toBe(false);
    expect(needsLoad(status({ generation: 4 }), 4, false)).toBe(false);
    expect(needsLoad(status({ generation: 1 }), 0, false)).toBe(true);
    // the opening's own read not back yet
    expect(needsLoad(status({ generation: 5 }), null, false)).toBe(false);
    expect(needsLoad(null, 4, false)).toBe(false);
  });
});
