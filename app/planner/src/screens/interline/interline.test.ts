// Interline's rows, filters and edits (spec docs/specs/2026-10-14-interline-photos-reference.md, "Checks": the interline
// rows and filters), on a small world: Test Air (TA) with a base in GB flies to Japan, Indonesia and Canada; Other Air
// (FR, group only) flies to Japan; a waiting plan card of Test Air's goes to Brazil.
import { describe, expect, it } from "vitest";
import {
  agreementChange, airportsOf, answerWords, byAirline, classify, coveredWords, dayWords, daysBetween, daysWords, filterSearch, interlineRows, isOpen, parseFilters,
  parseRules, planOrder, rtWords, shownRows, statusCounts, statusOf, waitDaysOf, waitWords, waitingLine, waitingRows,
  type AgreementRow, type IlRow,
} from "./model";

const rules = parseRules({
  countries: { JP: "domestic", ID: "domestic", BR: "domestic", KE: "gateway" },
  europe_zone: ["GB", "FR"], rivals: ["AE"], covered: { TA: ["CA"] }, group_only: ["FR"],
  partners: { JP: [{ name: "ANA", game_id: 45 }] },
})!;
const airlines = [{ id: 1, code: "TA", name: "Test Air", color: null }, { id: 2, code: "FR", name: "Other Air", color: null }];
const nameOf = (c: string) => airlines.find((a) => a.code === c)?.name ?? c;
const country: Record<string, string> = { LHR: "GB", NRT: "JP", HND: "JP", CGK: "ID", YYZ: "CA", GRU: "BR", DXB: "AE", NBO: "KE" };
const home = new Set(["GB"]);
const rows = interlineRows({
  airlines, home, rules, nameOf, countryOf: (ap) => country[ap],
  rotations: [
    { airline_id: 1, hub: "LHR", dest: "NRT", days: 7 }, { airline_id: 1, hub: "LHR", dest: "HND", days: 3 },
    { airline_id: 1, hub: "LHR", dest: "CGK", days: 14 }, { airline_id: 1, hub: "LHR", dest: "YYZ", days: 7 },
    { airline_id: 2, hub: "LHR", dest: "NRT", days: 7 }, { airline_id: 1, hub: "LHR", dest: "DXB", days: 7 },
  ],
  plans: [{ airline_id: 1, registration: "G-TEST", legs: [{ from: "LHR", to: "GRU" }, { from: "GRU", to: "LHR" }] }],
});
const agreement = (x: Partial<AgreementRow>): AgreementRow => ({ id: 9, world_id: 1, airline_id: 1, country_code: "JP", status: null, partner: null, decided_on: null, requested_on: null, note: null, updated_at: "t", ...x });
/** Today (UTC) for the edits. */
const T = "2026-11-03";

describe("Interline's rows", () => {
  it("a row per airline and interline country it flies to or has planned; the group-only airline, a covered country, a rival and a base country get none", () => {
    expect(rows.map((r) => `${r.airline_id}|${r.cc}`)).toEqual(["1|ID", "1|JP", "1|BR"]);
  });
  it("each row's airports, most round trips first, and its round trips a day; a country only on a plan card is planned", () => {
    const jp = rows.find((r) => r.cc === "JP") as IlRow;
    expect(airportsOf(jp)).toEqual(["NRT", "HND"]);
    expect(rtWords(jp.rt_day)).toBe("1.4");
    expect(rtWords((rows.find((r) => r.cc === "ID") as IlRow).rt_day)).toBe("2");
    expect(rows.find((r) => r.cc === "BR")?.planned).toBe(true);
    expect(jp.planned).toBe(false);
  });
  it("how a country is treated, as the old ilClass words it", () => {
    expect(classify("GB", airlines[0]!, rules, home, nameOf).label).toBe("group base country");
    expect(classify("FR", airlines[0]!, rules, new Set(), nameOf).label).toBe("Europe zone");
    expect(classify("JP", airlines[1]!, rules, home, nameOf).label).toBe("Other Air: group only");
    expect(classify("AE", airlines[0]!, rules, home, nameOf).label).toBe("hub rival");
    expect(classify("CA", airlines[0]!, rules, home, nameOf).label).toBe("covered by Test Air");
    expect(classify("KE", airlines[0]!, rules, home, nameOf).label).toBe("interline · gateway");
    expect(classify("US", airlines[0]!, rules, home, nameOf).label).toBe("no network");
  });
  it("the footnote's covered countries, by name in the countries' order", () => {
    expect(coveredWords([{ code: "--", name: "Unknown" }, { code: "CA", name: "Canada" }, { code: "JP", name: "Japan" }], rules, home, nameOf)).toBe("Test Air — Canada");
  });
  it("plan cards in the old storage's order: shortest registration first, then by its characters", () => {
    expect(["N12", "G-AB", "B-0162", "9M-AAL"].sort(planOrder)).toEqual(["N12", "G-AB", "9M-AAL", "B-0162"]);
  });
});

describe("Interline's filters", () => {
  const status = (r: IlRow) => statusOf(r.cc === "JP" ? agreement({ status: "signed" }) : r.cc === "ID" ? agreement({ status: "to_sign" }) : undefined);
  it("an airline, and still to sign, signed or declined, kept in the address", () => {
    const codeOf = (id: number) => airlines.find((a) => a.id === id)?.code ?? null;
    expect(shownRows(rows, parseFilters("?airline=ta&status=open"), codeOf, status).map((r) => r.cc)).toEqual(["ID", "BR"]);
    expect(shownRows(rows, parseFilters("?status=signed"), codeOf, status).map((r) => r.cc)).toEqual(["JP"]);
    expect(shownRows(rows, parseFilters("?airline=FR"), codeOf, status)).toEqual([]);
    expect(filterSearch({ airline: "TA", status: "open" })).toBe("?airline=TA&status=open");
    expect(parseFilters("?status=nonsense").status).toBe("");
  });
  it("since 23 Oct each status's tile filters by it: not contacted, requested and no partner too", () => {
    const codeOf = (id: number) => airlines.find((a) => a.id === id)?.code ?? null;
    expect(shownRows(rows, parseFilters("?status=none"), codeOf, status).map((r) => r.cc)).toEqual(["BR"]);
    expect(shownRows(rows, parseFilters("?status=requested"), codeOf, status).map((r) => r.cc)).toEqual(["ID"]);
    expect(shownRows(rows, parseFilters("?status=nopartner"), codeOf, status)).toEqual([]);
    expect(filterSearch(parseFilters("?airline=TA&status=nopartner"))).toBe("?airline=TA&status=nopartner");
  });
  it("the old statuses: to_sign is requested, no row is not contacted; signed, declined and no partner are no longer open", () => {
    expect(statusOf(undefined)).toBe("none");
    expect(statusOf(agreement({ status: "to_sign" }))).toBe("requested");
    expect(["none", "requested", "signed", "declined", "nopartner"].map((s) => isOpen(s as never))).toEqual([true, true, false, false, false]);
  });
});

describe("Interline's edits, as the old adapter wrote them", () => {
  it("a status on a pair with no row adds one (requested is to_sign)", () => {
    expect(agreementChange(1, 1, "JP", undefined, "status", "requested", T)).toEqual({ table: "interline_agreements", op: "insert",
      values: { world_id: 1, airline_id: 1, country_code: "JP", status: "to_sign", partner: null, decided_on: null, requested_on: "2026-11-03", note: null } });
  });
  it("a partner, a date or a note changes only that column; the same value changes nothing", () => {
    expect(agreementChange(1, 1, "JP", agreement({ status: "to_sign" }), "partner", " ANA (45) ", T)).toEqual(
      { table: "interline_agreements", op: "update", key: { id: 9 }, base: "t", values: { partner: "ANA (45)" } });
    expect(agreementChange(1, 1, "JP", agreement({ status: "to_sign" }), "date", "2026-10-01", T)?.values).toEqual({ decided_on: "2026-10-01" });
    expect(agreementChange(1, 1, "JP", agreement({ status: "signed" }), "status", "signed", T)).toBeNull();
  });
  it("a row left with nothing in it is removed; not contacted with nothing else typed writes nothing", () => {
    expect(agreementChange(1, 1, "JP", agreement({ status: "signed" }), "status", "none", T)).toEqual({ table: "interline_agreements", op: "delete", key: { id: 9 }, base: "t" });
    expect(agreementChange(1, 1, "JP", undefined, "notes", "  ", T)).toBeNull();
    expect(agreementChange(1, 1, "JP", agreement({ status: "signed", note: "x" }), "status", "none", T)?.values).toEqual({ status: null });
  });
});

describe("the day requested (3 Nov, spec docs/specs/2026-11-03-interline-replies.md)", () => {
  it("a row that becomes to_sign without a day gets today's UTC date in the same change", () => {
    expect(agreementChange(1, 1, "JP", agreement({ partner: "ANA (45)", note: "x" }), "status", "requested", T)).toEqual(
      { table: "interline_agreements", op: "update", key: { id: 9 }, base: "t", values: { status: "to_sign", requested_on: "2026-11-03" } });
    expect(agreementChange(1, 1, "JP", agreement({ status: "declined" }), "status", "requested", T)?.values).toEqual({ status: "to_sign", requested_on: "2026-11-03" });
  });
  it("a day already there stays; any other status leaves the day as it is (history)", () => {
    expect(agreementChange(1, 1, "JP", agreement({ status: "declined", requested_on: "2026-10-20" }), "status", "requested", T)?.values).toEqual({ status: "to_sign" });
    expect(agreementChange(1, 1, "JP", agreement({ status: "to_sign", requested_on: "2026-10-20" }), "status", "signed", T)?.values).toEqual({ status: "signed" });
    expect(agreementChange(1, 1, "JP", undefined, "status", "signed", T)?.values).toMatchObject({ status: "signed", requested_on: null });
    expect(agreementChange(1, 1, "JP", agreement({ status: "to_sign", requested_on: "2026-10-20" }), "partner", "ANA (45)", T)?.values).toEqual({ partner: "ANA (45)" });
  });
  it("the date box changes requested_on only; emptied, it clears it; the day alone doesn't keep a row", () => {
    expect(agreementChange(1, 1, "JP", agreement({ status: "to_sign", requested_on: "2026-11-03" }), "requested", "2026-11-01", T)).toEqual(
      { table: "interline_agreements", op: "update", key: { id: 9 }, base: "t", values: { requested_on: "2026-11-01" } });
    expect(agreementChange(1, 1, "JP", agreement({ status: "to_sign", requested_on: "2026-11-03" }), "requested", "", T)?.values).toEqual({ requested_on: null });
    expect(agreementChange(1, 1, "JP", agreement({ status: "to_sign", requested_on: "2026-11-03" }), "requested", "2026-11-03", T)).toBeNull();
    expect(agreementChange(1, 1, "JP", undefined, "requested", "2026-11-01", T)).toBeNull();
    expect(agreementChange(1, 1, "JP", agreement({ status: "to_sign", requested_on: "2026-11-03" }), "status", "none", T)?.op).toBe("delete");
  });
});

describe("Waiting for a reply (3 Nov, manual §6)", () => {
  const a = (id: number, x: Partial<AgreementRow>) => agreement({ id, status: "to_sign", partner: "P" + id, ...x });
  const all = [
    a(1, { airline_id: 2, country_code: "JP", requested_on: "2026-11-03" }),
    a(2, { airline_id: 1, country_code: "ID", requested_on: "2026-10-20" }),
    a(3, { airline_id: 1, country_code: "BR", requested_on: "2026-11-02" }),
    a(4, { airline_id: 2, country_code: "BR", requested_on: "2026-11-02" }),
    a(5, { airline_id: 1, country_code: "KE", requested_on: null }),
    a(6, { airline_id: 1, country_code: "AU", requested_on: "2026-10-01", status: "signed" }),
    a(7, { airline_id: 1, country_code: "NZ", requested_on: "2026-10-01", partner: null }),
    a(8, { airline_id: 1, country_code: "MX", requested_on: "2026-10-01", partner: "  " }),
  ];
  it("every to_sign row with a partner, oldest first, then the airlines' order and the country; a row without a day last", () => {
    expect(waitingRows(all, "2026-11-03", 14, [1, 2]).map((w) => w.row.id)).toEqual([2, 3, 4, 1, 5]);
    expect(waitingRows(all, "2026-11-03", 14, [2, 1]).map((w) => w.row.id)).toEqual([2, 4, 3, 1, 5]);
  });
  it("days waiting count whole UTC days from the day requested", () => {
    expect(daysBetween("2026-11-02", "2026-11-03")).toBe(1);
    expect(daysBetween("2026-10-20", "2026-11-03")).toBe(14);
    expect(daysBetween("2026-10-25", "2026-11-03")).toBe(9);
    const w = waitingRows(all, "2026-11-03", 14, [1, 2]);
    expect(w.map((x) => x.days)).toEqual([14, 1, 1, 0, null]);
    expect(w.map((x) => daysWords(x.days))).toEqual(["14 days", "1 day", "1 day", "0 days", "no date"]);
  });
  it("the mark at exactly the setting, not a day before; a row without a day is never marked", () => {
    expect(waitingRows([a(1, { requested_on: "2026-10-20" })], "2026-11-03", 14)[0]?.overdue).toBe(true);
    expect(waitingRows([a(1, { requested_on: "2026-10-21" })], "2026-11-03", 14)[0]?.overdue).toBe(false);
    expect(waitingRows([a(1, { requested_on: "2026-10-27" })], "2026-11-03", 7)[0]?.overdue).toBe(true);
    expect(waitingRows([a(1, { requested_on: null })], "2026-11-03", 0)[0]?.overdue).toBe(false);
  });
  it("the words: the day as \"2 Nov\", the wait from the setting (14 is two weeks), and the board's line", () => {
    expect(dayWords("2026-11-02")).toBe("2 Nov");
    expect(dayWords("2026-01-15")).toBe("15 Jan");
    expect(dayWords(null)).toBe("");
    expect(waitWords(14)).toBe("two weeks");
    expect(waitWords(10)).toBe("10 days");
    expect(waitWords(1)).toBe("1 day");
    expect(waitDaysOf(14)).toBe(14);
    expect(waitDaysOf(10)).toBe(10);
    expect(waitDaysOf(undefined)).toBe(14);
    expect(waitDaysOf("x")).toBe(14);
    const w = waitingRows(all, "2026-11-03", 14, [1, 2]);
    expect(waitingLine(w, 14)).toBe("5 requests waiting · 1 with no reply in two weeks");
    expect(waitingLine(w.slice(1, 2), 10)).toBe("1 request waiting · none with no reply in 10 days");
    expect(waitingLine([], 14)).toBe("No requests waiting");
  });
});

describe("Interline's page head and tiles (23 Oct)", () => {
  const status = (r: IlRow) => statusOf(r.cc === "JP" ? agreement({ status: "signed" }) : r.cc === "ID" ? agreement({ status: "to_sign" }) : undefined);
  it("the answer is the title: the agreements still to sign, or all in place", () => {
    expect(answerWords(5)).toBe("5 agreements to set up");
    expect(answerWords(1)).toBe("1 agreement to set up");
    expect(answerWords(0)).toBe("All agreements in place");
  });
  it("a count for every status, none missing", () => {
    expect(statusCounts(rows, status)).toEqual({ none: 1, requested: 1, signed: 1, declined: 0, nopartner: 0 });
  });
  it("the rows in runs of one airline, in their order", () => {
    const g = byAirline([...rows, { airline_id: 2, cc: "JP", airports: new Map(), rt_day: 0, planned: false }]);
    expect(g.map((x) => [x.airline_id, x.rows.map((r) => r.cc)])).toEqual([[1, ["ID", "JP", "BR"]], [2, ["JP"]]]);
  });
});
