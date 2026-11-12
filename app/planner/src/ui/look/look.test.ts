import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { applyPeriod, periodOf } from "./look";

describe("the period by this computer's clock (to-do 225, item 6)", () => {
  it("changes at 05:00, 07:00, 17:00 and 20:00", () => {
    const at = (h: number) => periodOf(h);
    expect([4, 5, 6, 7, 16, 17, 19, 20, 23, 0].map(at)).toEqual(["night", "dusk", "dusk", "day", "day", "dusk", "dusk", "night", "night", "night"]);
    // 04:59, 06:59, 16:59 and 19:59 are still in the hour before the change
    expect(periodOf(new Date(2026, 10, 11, 4, 59).getHours())).toBe("night");
    expect(periodOf(new Date(2026, 10, 11, 6, 59).getHours())).toBe("dusk");
    expect(periodOf(new Date(2026, 10, 11, 16, 59).getHours())).toBe("day");
    expect(periodOf(new Date(2026, 10, 11, 19, 59).getHours())).toBe("dusk");
  });
});

describe("one look for everyone (step 6)", () => {
  it("is on the page from its first byte, with no stored setting", () => {
    const html = readFileSync(new URL("../../../index.html", import.meta.url), "utf8");
    expect(html).toMatch(/<html lang="en" data-look="glass">/);
    const code = ["../../main.tsx", "../../App.tsx", "../Header.tsx", "../../data/config.ts", "./look.ts"]
      .map((f) => readFileSync(new URL(f, import.meta.url), "utf8")).join("\n");
    expect(code).not.toMatch(/localStorage[^\n]*look|LOOK_STORAGE_KEY|lookmode/);
  });

  it("sets the period on the root, and only when it changes", () => {
    const root = { dataset: {} as Record<string, string> } as unknown as HTMLElement;
    applyPeriod("dusk", root);
    expect(root.dataset.period).toBe("dusk");
    applyPeriod("night", root);
    expect(root.dataset.period).toBe("night");
  });
});
