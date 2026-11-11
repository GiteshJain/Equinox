import { describe, expect, it } from "vitest";
import { railAllWorks, railCurrent, railTarget } from "./rail";

describe("the airline rail (decision 4, option A)", () => {
  it("picks the airline on Performance and Competition, All their group page", () => {
    expect(railTarget("/performance", "", "VS", "PA")).toBe("/performance/VS");
    expect(railTarget("/performance/FR/AMS-BCN", "", "VS", "PA")).toBe("/performance/VS");
    expect(railTarget("/performance/FR", "", "all", "PA")).toBe("/performance");
    expect(railTarget("/competition/FR", "", "MH", "PA")).toBe("/competition/MH");
    expect(railTarget("/competition", "", "all", "PA")).toBe("/competition");
    expect(railCurrent("/performance/FR/AMS-BCN", "", "PA")).toBe("FR");
    expect(railCurrent("/performance", "", "PA")).toBe("all");
    expect(railCurrent("/competition/MU", "", "PA")).toBe("MU");
  });

  it("picks the airline on Routes, keeping its filters but not the pair or the aircraft pop-up", () => {
    expect(railTarget("/routes/PA/JFK-ORD", "?trunk=1&aircraft=N001AW", "KF", "PA")).toBe("/routes/KF?trunk=1");
    expect(railTarget("/routes", "?airline=VS", "KF", "PA")).toBe("/routes/KF");
    expect(railTarget("/routes/PA", "", "all", "PA")).toBeNull();
    expect(railCurrent("/routes/KF/DEL-BOM", "", "PA")).toBe("KF");
    expect(railCurrent("/routes", "?airline=VS", "PA")).toBe("VS");
    expect(railCurrent("/routes", "", "PA")).toBe("PA");
  });

  it("picks the airline on Tails by its filter, none for the first airline", () => {
    expect(railTarget("/tails", "?airline=VS&base=LGW", "KF", "PA")).toBe("/tails?airline=KF");
    expect(railTarget("/tails/G-AAGJ", "", "PA", "PA")).toBe("/tails");
    expect(railTarget("/tails", "", "all", "PA")).toBeNull();
    expect(railCurrent("/tails", "?airline=MH", "PA")).toBe("MH");
    expect(railCurrent("/tails", "", "PA")).toBe("PA");
  });

  it("lights All on the other screens, and an airline opens its Performance page", () => {
    for (const p of ["/", "/today", "/interline", "/photos", "/reference/markets", "/systems"]) {
      expect(railCurrent(p, "", "PA")).toBe("all");
      expect(railTarget(p, "", "FR", "PA")).toBe("/performance/FR");
      expect(railTarget(p, "", "all", "PA")).toBeNull();
      expect(railAllWorks(p)).toBe(true);
    }
    expect(railAllWorks("/routes/PA")).toBe(false);
    expect(railAllWorks("/tails")).toBe(false);
    expect(railAllWorks("/performance")).toBe(true);
  });
});
