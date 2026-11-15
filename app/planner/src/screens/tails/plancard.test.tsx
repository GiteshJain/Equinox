// The cleaner plan card (15 Nov, to-do 242, spec docs/specs/2026-11-15-cleaner-plan-card.md): what is on the card
// itself, what folds under its one "More" line (closed by default), and how a problem under it shows on that line. The
// card is rendered to markup (react-dom/server) with a small hand-made card; nothing is saved here.
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { CabinSuggestion } from "@rules";
import { PlanCard } from "./Deliveries";
import { CARD_FACE, CARD_SCHEDULE, cardMore, type CardLeg, type PlanCardRow, type PlanLegRow } from "./model";

const T0 = "2026-11-15T10:00:00.000001+00:00";
const row = (id: number, x: Partial<PlanLegRow> = {}): PlanLegRow => ({
  id, plan_card_id: 7, position: id, flight_no: 100 + id, origin_code: "HUB", dest_code: "DDD", dep_utc_min: 480, block_min: 345, days_utc: [1, 2, 3, 4, 5, 6, 7],
  service_code: "S3", updated_at: T0, ...x,
} as PlanLegRow);
const leg = (id: number, from: string, to: string, x: Partial<CardLeg> = {}): CardLeg => ({
  row: row(id, { origin_code: from, dest_code: to }), no: String(100 + id), from, to, dep: "08:00", arr: "13:45", block: "5:45", svc: "S3", days: "1234567", ...x,
});
const legs = [leg(1, "HUB", "DDD"), leg(2, "DDD", "HUB", { dep: "15:00", arr: "20:45" })];
const card: PlanCardRow = { id: 7, airline_id: 1, aircraft_id: 5, base_code: "HUB", title: "DDD", note: "first of three", config_id: 15, updated_at: T0 };
const sug = (code: string): CabinSuggestion => ({ code, config_id: 15, reason: "3,500–6,500 km is 81% of block time: Leisure Plus", missing: false, differs: false } as CabinSuggestion);

function html(x: Partial<Parameters<typeof PlanCard>[0]> = {}): string {
  return renderToStaticMarkup(<PlanCard reg="N501AW" base="HUB" title="DDD" type="A321neo" config="321-LP" card={card} legs={legs} filed={false} canFile busy={false}
    onFile={() => {}} cabins={["321-LP", "321-LEI"]} cardCabin="321-LP" onCabin={() => {}} stations={new Set(["HUB"])} suggestion={sug("321-LP")}
    fares={new Map([[1, "launch (+0% of the default price)"], [2, "launch (+0% of the default price)"]])} {...x} />);
}
/** The card's markup before its "More" line, and the "More" line's own (its summary and what it folds). */
function parts(h: string): { face: string; summary: string; more: string } {
  const at = h.indexOf("<details");
  const sum = at < 0 ? "" : h.slice(at, h.indexOf("</summary>", at));
  return { face: at < 0 ? h : h.slice(0, at), summary: sum, more: at < 0 ? "" : h.slice(h.indexOf("</summary>", at)) };
}

describe("the cleaner plan card (15 Nov)", () => {
  it("keeps the tail, type, hub, cabin and schedule on the card itself", () => {
    expect(CARD_FACE).toEqual(["tail", "type", "hub", "cabin", "schedule"]);
    expect(CARD_SCHEDULE).toEqual(["Flight", "Route", "Day", "Departs", "Arrives", "Service"]);
    const { face } = parts(html());
    expect(face).toContain("N501AW · HUB");
    expect(face).toContain("A321neo");
    expect(face).toContain('data-card-cabin="321-LP"');
    for (const h of ["Flight", "Route", "Departs", "Arrives", "Service"]) expect(face).toContain(`<th>${h}</th>`);
    expect(face).toContain("<td><b>101</b></td>");
    expect(face).toContain("08:00");
    expect(face).toContain("13:45");
    expect(face).toContain("S3");
    // the Cabin box and File into planner stay on the card
    expect(face).toContain('data-card-cabin-pick="N501AW"');
    expect(face).toContain('data-planfile="N501AW"');
    // a daily card has no Day column; a line's card has one, on the card itself
    expect(face).not.toContain("<th>Day</th>");
    expect(parts(html({ legs: [leg(1, "HUB", "DDD", { days: "1" }), leg(2, "DDD", "HUB", { days: "2" })] })).face).toContain("<th>Day</th>");
  });

  it("folds the title, flight count, note, suggestion, block and fare levels under one closed More line", () => {
    const h = html();
    const { face, summary, more } = parts(h);
    expect(h.match(/<details/g)).toHaveLength(1);
    expect(summary).not.toContain(" open");
    expect(summary).toContain("<b>More</b>");
    for (const x of ["<th>Block</th>", "<th>Fare level</th>", "data-card-fare", "data-card-suggest", "Use the suggestion", "first of three", "data-card-title", "2 flights"]) {
      expect(face).not.toContain(x);
    }
    expect(more).toContain("<th>Block</th>");
    expect(more).toContain("5:45");
    expect(more).toContain('data-card-fare="HUB-DDD"');
    expect(more).toContain('data-card-fare="DDD-HUB"');
    expect(more).toContain('data-card-suggest="321-LP"');
    expect(more).toContain("3,500–6,500 km is 81% of block time");
    expect(more).toContain("first of three");
    expect(more).toContain("2 flights");
    // the suggestion's reason is never on the card itself
    expect(face).not.toContain("Leisure Plus");
  });

  it("says what is under More, in order", () => {
    const m = cardMore({ title: "DDD", flights: 2, onLine: true, note: "x", filed: false, suggestion: sug("321-LP"), shown: "321-LP", block: true, fares: 2 });
    expect(m.items).toEqual(["title", "flights", "line", "note", "suggestion", "block", "fares"]);
    expect(m.words).toBe("plan · flight count · line · note · cabin suggestion · block times · fare levels");
    expect(m).toMatchObject({ problems: [], count: "", level: "" });
    // nothing to fold but what the card has: no note, no line, no fares read yet, filed (no suggestion)
    expect(cardMore({ title: "", flights: 2, onLine: false, note: "", filed: true, suggestion: sug("321-LP"), shown: "321-LEI", block: true, fares: 0 }))
      .toMatchObject({ items: ["flights", "block"], problems: [], count: "" });
  });

  it("counts a problem under More on the More line itself, so a clean card means nothing to fix", () => {
    const m = cardMore({ title: "DDD", flights: 2, onLine: false, note: "", filed: false, suggestion: sug("321-LP"), shown: "321-LEI", block: true, fares: 0 });
    expect(m.problems).toEqual([{ key: "cabin-differs", level: "warn", text: "cabin 321-LEI differs from the suggested 321-LP" }]);
    expect(m).toMatchObject({ count: "1 to check", level: "warn" });
    // no cabin is not a difference: it has its own red mark on the card itself
    expect(cardMore({ title: "", flights: 1, onLine: false, note: "", filed: false, suggestion: sug("321-LP"), shown: "", block: false, fares: 0 }).count).toBe("");
    const { face, summary, more } = parts(html({ config: "321-LEI", cardCabin: "321-LEI" }));
    expect(summary).toContain('data-card-more-count="1"');
    expect(summary).toContain("1 to check");
    expect(summary).toContain('data-card-more="warn"');
    expect(more).toContain('data-card-cabin-differs="yes"');
    expect(face).not.toContain("data-card-cabin-differs");
    // a clean card's More line has no count
    const clean = parts(html());
    expect(clean.summary).toContain('data-card-more="clean"');
    expect(clean.summary).not.toContain("to check");
  });

  it("keeps the red marks on the card itself: a wrong service code, no cabin chosen, a new station", () => {
    const { face } = parts(html({ config: "", cardCabin: "", service: new Map([[1, "S1, wants S3"]]) }));
    expect(face).toMatch(/<span class="pill bad sm" data-service-issue[^>]*>S1, wants S3<\/span>/);
    expect(face).toContain('<span class="pill bad sm" data-card-cabin="">no cabin chosen</span>');
    // DDD: no station there yet for this airline
    expect(face).toContain('data-new-station="DDD"');
  });

  it("shows a filed card as in the planner, with no Cabin box and no suggestion", () => {
    const { face, more } = parts(html({ filed: true, config: "321-LEI" }));
    expect(face).toContain("in the planner");
    expect(face).not.toContain("data-card-cabin-pick");
    expect(more).not.toContain("data-card-suggest");
    expect(more).not.toContain("data-card-cabin-differs");
  });
});
