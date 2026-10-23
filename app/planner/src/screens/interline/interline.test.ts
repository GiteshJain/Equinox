// Interline's rows, filters and edits (spec docs/specs/2026-10-14-interline-photos-reference.md, "Checks": the interline
// rows and filters), on a small world: Test Air (TA) with a base in GB flies to Japan, Indonesia and Canada; Other Air
// (FR, group only) flies to Japan; a waiting plan card of Test Air's goes to Brazil.
import { describe, expect, it } from "vitest";
import {
  agreementChange, airportsOf, answerWords, byAirline, classify, coveredWords, filterSearch, interlineRows, isOpen, parseFilters, parseRules, planOrder, rtWords,
  shownRows, statusCounts, statusOf,
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
const agreement = (x: Partial<AgreementRow>): AgreementRow => ({ id: 9, world_id: 1, airline_id: 1, country_code: "JP", status: null, partner: null, decided_on: null, note: null, updated_at: "t", ...x });

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
    expect(agreementChange(1, 1, "JP", undefined, "status", "requested")).toEqual({ table: "interline_agreements", op: "insert",
      values: { world_id: 1, airline_id: 1, country_code: "JP", status: "to_sign", partner: null, decided_on: null, note: null } });
  });
  it("a partner, a date or a note changes only that column; the same value changes nothing", () => {
    expect(agreementChange(1, 1, "JP", agreement({ status: "to_sign" }), "partner", " ANA (45) ")).toEqual(
      { table: "interline_agreements", op: "update", key: { id: 9 }, base: "t", values: { partner: "ANA (45)" } });
    expect(agreementChange(1, 1, "JP", agreement({ status: "to_sign" }), "date", "2026-10-01")?.values).toEqual({ decided_on: "2026-10-01" });
    expect(agreementChange(1, 1, "JP", agreement({ status: "signed" }), "status", "signed")).toBeNull();
  });
  it("a row left with nothing in it is removed; not contacted with nothing else typed writes nothing", () => {
    expect(agreementChange(1, 1, "JP", agreement({ status: "signed" }), "status", "none")).toEqual({ table: "interline_agreements", op: "delete", key: { id: 9 }, base: "t" });
    expect(agreementChange(1, 1, "JP", undefined, "notes", "  ")).toBeNull();
    expect(agreementChange(1, 1, "JP", agreement({ status: "signed", note: "x" }), "status", "none")?.values).toEqual({ status: null });
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
