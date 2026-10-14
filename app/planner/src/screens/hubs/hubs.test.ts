// Hubs' addresses and words (spec docs/specs/2026-10-13-hubs.md): where the address points, and how the screen writes the
// library's figures, as the old Hubs wrote them. The figures themselves are the library's, with their own cases
// (lib/rules/cases/hubs.json); these run the screen on that file's small world.
import { readFileSync } from "node:fs";
import { createElement } from "react";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { buildRules, hubs, type RulesInput } from "@rules";
import { itemRoute } from "../screens";
import { Connections, DayBoard, FlightList, WeekBoard } from "./Hubs";
import {
  capWords, cellClass, connectionsNote, countWords, exampleWords, focusWords, nextWords, parsePlace, placePath, regionWords, rowLabel,
} from "./model";

const read = (f: string) => JSON.parse(readFileSync(new URL(`../../../../../lib/rules/cases/${f}`, import.meta.url), "utf8")) as { input: RulesInput };
const input: RulesInput = { ...read("_base.json").input, ...read("hubs.json").input };
const rules = buildRules(input);

describe("Hubs' addresses", () => {
  it("names the airport and the day, Monday and the first board where it names none", () => {
    expect(parsePlace("", "")).toEqual({ code: null, day: 0 });
    expect(parsePlace("JFK", "?day=3")).toEqual({ code: "JFK", day: 3 });
    expect(parsePlace("del/", "?day=6")).toEqual({ code: "DEL", day: 6 });
    expect(parsePlace("JFK", "?day=7")).toEqual({ code: "JFK", day: 0 });
    expect(parsePlace("JFK", "?day=x")).toEqual({ code: "JFK", day: 0 });
  });

  it("a board's link reopens the same airport and day", () => {
    expect(placePath("JFK", 0)).toBe("/hubs/JFK");
    expect(placePath("JFK", 2)).toBe("/hubs/JFK?day=2");
    expect(itemRoute("hubs", { hub: "KUL", day: 5 })).toBe("/hubs/KUL?day=5");
    expect(itemRoute("hubs")).toBe("/hubs");
    const p = placePath("PVG", 4);
    expect(parsePlace(p.split("/")[2]?.split("?")[0] ?? "", p.slice(p.indexOf("?")))).toEqual({ code: "PVG", day: 4 });
  });
});

describe("Hubs' words", () => {
  const mon = hubs.board(rules, "HUB", 0);
  const foc = hubs.board(rules, "FOC", 0);
  const table = hubs.connectionsTable(rules, "HUB");

  it("the count line: today's departures and arrivals, departures a week against the cap, the next free pair", () => {
    expect(countWords(mon) + capWords(mon, "en-US") + nextWords(mon))
      .toBe("8 departures · 4 arrivals today · 50 departures/week of 5,000 cap · next free 1015 / 1016 (last used 1013)");
    expect(capWords({ ...mon, over_cap: true })).toBe("");
    expect(nextWords({ ...mon, next_pair: null })).toBe("");
  });

  it("a focus city's note names its hub", () => {
    expect(focusWords(foc)).toBe("FOC is a focus city feeding HUB: it has no banks of its own, so its flights are timed to HUB's banks. "
      + "Check the connections on HUB's board.");
    expect(focusWords({ ...foc, base: { ...foc.base!, parent_code: null } })).toContain("timed to its hub's banks. Check the connections on the hub's board.");
  });

  it("the week grid's cells: a bank's departure window, its arrival window, the hour's first slot", () => {
    expect(cellClass(mon, 24)).toBe("wdep hr");
    expect(cellClass(mon, 17)).toBe("warr");
    expect(cellClass(mon, 1)).toBe("");
    expect(cellClass(foc, 24)).toBe(" hr");
  });

  it("the connections table: each row's name, the regions, the tightest examples and the note", () => {
    expect(table.rows.map((r) => rowLabel(table, r))).toEqual(["Bank 1 · 06:00", "Bank 2 · 14:00", "Outside the banks"]);
    expect(rowLabel({ banked: false }, { n: 0, dep_local_min: null })).toBe("All connections");
    expect(regionWords(table.rows[1]!.arriving_regions)).toBe("Europe 3 · North America 1");
    expect(regionWords(table.rows[2]!.leaving_regions)).toBe("South Asia 2 · Europe 2 · North America 1");
    expect(exampleWords(table.rows[1]!)).toBe("AAA→BBB 1:00, FOC→NBN 2:59, FOC→BBB 3:00, AAA→NBN 3:29, FOC→AAA 3:45, BBB→NBN 5:44, AAA→CCC 6:00, AAA→DDD 6:01 …");
    expect(connectionsNote(rules, table)).toBe("flights that are flying now, all two airlines · connection time from the airport's MCT up to 8 h · 14 city pairs linked");
  });
});

describe("Hubs' boards", () => {
  const html = (el: Parameters<typeof renderToString>[0]) => renderToString(el);
  const tue = hubs.board(rules, "HUB", 1);

  it("every figure is marked for the checks", () => {
    const out = html(createElement("div", null, createElement(DayBoard, { b: tue }), createElement(WeekBoard, { b: tue }), createElement(FlightList, { b: tue }),
      createElement(Connections, { rules, t: hubs.connectionsTable(rules, "HUB") })));
    for (const f of ["hubs: day strip", "hubs: hours", "hubs: week", "hubs: flights", "hubs: connections"]) expect(out).toContain(`data-figure="${f}"`);
  });

  it("the flight list: an arrival named with the bank it can next make within the connection rules, else outside the banks; a flight of an airline with no base here with none, off wave in red", () => {
    const out = html(createElement(FlightList, { b: tue }));
    expect(out).toContain("<td>05:30</td><td>↘</td><td><b>1006</b></td><td>CCC</td><td>T-001</td><td><span class=\"pill bad\">outside the banks</span></td>");
    expect(out).toContain("<td>06:00</td><td>↘</td><td><b>1004</b></td><td>BBB</td><td>T-002</td><td><span class=\"pill ok\">bank 2</span></td>");
    expect(out).toContain("<td>08:15</td><td>↘</td><td><b>3001</b></td><td>AAA</td><td>O-001</td><td></td>");
    expect(out).toContain("<td>11:44</td><td>↗</td><td><b>1009</b></td><td>NBN</td><td>T-002</td><td><span class=\"pill bad\">off wave</span></td>");
  });

  it("the strip: each bank's windows, and a tick per flight (red off wave)", () => {
    const out = html(createElement(DayBoard, { b: tue }));
    expect(out.match(/class="win dep"/g)).toHaveLength(3);
    expect(out.match(/class="tick /g)).toHaveLength(tue.flights.length);
    expect(out).toContain("title=\"bank 1 departures\">B1</span>");
    expect(out.match(/class="tick dep off"/g)).toHaveLength(tue.flights.filter((x) => x.kind === "dep" && x.bank === 0).length);
  });

  it("the week grid: a row a day, Tuesday marked, the totals", () => {
    const out = html(createElement(WeekBoard, { b: tue }));
    expect(out.match(/<tr class="cur">/g)).toHaveLength(1);
    expect(out).toContain("<td class=\"sum\"><b>7↗ 5↘</b></td>");
  });

  it("a day with nothing says so, and an airport with no arrivals or no departures has no table", () => {
    const empty = { ...tue, flights: [] };
    expect(html(createElement(FlightList, { b: empty }))).toContain("Nothing scheduled at <!-- -->HUB<!-- --> on <!-- -->Tue<!-- -->.");
    const none = { ...hubs.connectionsTable(rules, "HUB"), arrivals: 0 };
    const out = html(createElement(Connections, { rules, t: none }));
    expect(out).toContain("No flights both arriving and leaving here yet.");
    expect(out).not.toContain("<table");
  });
});
