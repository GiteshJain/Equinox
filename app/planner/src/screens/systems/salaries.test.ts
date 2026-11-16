// The salary table's words (since 16 Nov; to-do 245, spec docs/specs/2026-11-16-salary-table.md): the board's line, each
// airline's heading, a difference, and Today's one item (only when a position is under or over target; keyed by the
// flagged positions; a position with no staff or no country average makes none).
import { describe, expect, it } from "vitest";
import { airlineReadWords, diffWords, readAtWords, salaryAttention, salaryCountsWords, type SalaryAirline, type SalaryRow, type SalaryTable } from "./salaries";

const row = (position: string, x: Partial<SalaryRow> = {}): SalaryRow => ({
  position, group: "Ground crew", employed: 3, salary: 1000, salary_next: 1050, overview_avg: 1000, country_avg: 1000, target: 1050, diff: 0,
  diff_pct: 0, flag: null, averages_differ: false, raised_to: null, ...x,
});
const counts = (rows: SalaryRow[]) => ({
  positions: rows.length, flagged: rows.filter((r) => r.flag === "under" || r.flag === "over").length, under: rows.filter((r) => r.flag === "under").length,
  over: rows.filter((r) => r.flag === "over").length, no_average: rows.filter((r) => r.flag === "no_average").length, averages_differ: 0,
});
const airline = (code: string, rows: SalaryRow[], x: Partial<SalaryAirline> = {}): SalaryAirline => ({
  airline_id: code.charCodeAt(0), code, name: code, read_at: "2026-11-16T21:34:05.000Z", unattended: false, verdict: "ok",
  note: null, country: { id: 61, name: "India", code: "IN", ok: true }, counts: counts(rows), rows, ...x,
});
const table = (airlines: SalaryAirline[]): SalaryTable => {
  const rows = airlines.flatMap((a) => a.rows);
  const c = counts(rows);
  return { as_of: "2026-11-16T22:00:00.000Z", flag_pct: 1, above_pct: 5,
    counts: { flagged: c.flagged, under: c.under, over: c.over, no_average: c.no_average,
              airlines_flagged: airlines.filter((a) => a.rows.some((r) => r.flag === "under" || r.flag === "over")).length,
              not_read: airlines.filter((a) => !a.read_at).length }, airlines };
};

describe("the salary table's words", () => {
  it("a difference, signed, in AS$ and per cent of the target", () => {
    expect(diffWords({ diff: 11, diff_pct: 1.05 })).toBe("+11 (+1.05%)");
    expect(diffWords({ diff: -11, diff_pct: -1.05 })).toBe("−11 (−1.05%)");
    expect(diffWords({ diff: 0, diff_pct: 0 })).toBe("0 (0.00%)");
    expect(diffWords({ diff: 1200, diff_pct: 57.1 })).toBe("+1,200 (+57.1%)");
    expect(diffWords({ diff: null, diff_pct: null })).toBe("—");
  });
  it("when it was read, in UTC", () => {
    expect(readAtWords("2026-11-16T21:34:05.000Z")).toBe("16 Nov, 21:34 UTC");
    expect(readAtWords(null)).toBe("not read yet");
  });
  it("an airline's heading: when, by which capture, the country, and its flags", () => {
    expect(airlineReadWords(airline("KF", [row("Pursers", { flag: "over", diff: 11, diff_pct: 1.05 })], { unattended: true })))
      .toBe("read 16 Nov, 21:34 UTC by the unattended capture · India (IN) · 1 off target");
    expect(airlineReadWords(airline("KF", [row("Pursers")]))).toBe("read 16 Nov, 21:34 UTC · India (IN) · all within target");
    expect(airlineReadWords(airline("MU", [], { read_at: null }))).toBe("not read yet: the next capture reads it");
  });
  it("the board's line", () => {
    const t = table([airline("KF", [row("Pursers", { flag: "over" }), row("Ramp agents", { flag: "under" }), row("B737", { flag: "no_average" })]),
      airline("MH", [row("Pursers", { flag: "under" })]), airline("VS", [], { read_at: null })]);
    expect(salaryCountsWords(t)).toBe("3 positions more than 1% off target in 2 airlines · 1 with no country average · 1 airline not read yet");
    expect(salaryCountsWords(table([airline("KF", [row("Pursers")])]))).toBe("every position with staff within 1% of its target");
    expect(salaryCountsWords(table([airline("KF", [], { read_at: null })]))).toBe("no salaries read yet: the next capture reads them");
  });
});

describe("Today's one item", () => {
  it("one warn item linking to Systems, keyed by the flagged positions", () => {
    const t = table([airline("KF", [row("Ramp agents", { flag: "under" }), row("Pursers", { flag: "over" })]), airline("MH", [row("Pursers", { flag: "under" })])]);
    expect(salaryAttention(t)).toEqual({
      key: "salary|KF:Pursers:over,KF:Ramp agents:under,MH:Pursers:under", cls: "warn", screen: "systems",
      text: "Salaries: 3 positions more than 1% off target in 2 airlines",
    });
    expect(salaryAttention(table([airline("KF", [row("Pursers", { flag: "over" })])]))?.text).toBe("Salaries: 1 position more than 1% off target in 1 airline");
  });
  it("none when nothing is under or over: no staff, no country average and within target make no item", () => {
    expect(salaryAttention(table([airline("KF", [row("Logistics", { employed: 0 }), row("B737", { flag: "no_average" }), row("Pursers")])]))).toBeNull();
    expect(salaryAttention(null)).toBeNull();
  });
});
