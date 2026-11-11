import { describe, expect, it } from "vitest";
import { LOOK_STORAGE_KEY } from "../../data/config";
import { applyLook, applyPeriod, periodOf, readLook, setLook } from "./look";

function store(initial: Record<string, string> = {}) {
  const m = new Map(Object.entries(initial));
  return {
    m,
    getItem: (k: string) => m.get(k) ?? null,
    setItem: (k: string, v: string) => void m.set(k, v),
    removeItem: (k: string) => void m.delete(k),
  };
}

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

describe("the switch, kept in this browser", () => {
  it("is on only for the exact value glass", () => {
    expect(readLook(store())).toBe(false);
    expect(readLook(store({ [LOOK_STORAGE_KEY]: "glass" }))).toBe(true);
    expect(readLook(store({ [LOOK_STORAGE_KEY]: "GLASS" }))).toBe(false);
    expect(readLook(store({ [LOOK_STORAGE_KEY]: "1" }))).toBe(false);
    expect(readLook({ getItem: () => { throw new Error("blocked"); } })).toBe(false);
    expect(readLook(null)).toBe(false);
  });

  it("writes and removes its key, and storage that throws doesn't stop it", () => {
    const s = store();
    setLook(true, s);
    expect(s.m.get(LOOK_STORAGE_KEY)).toBe("glass");
    setLook(false, s);
    expect(s.m.has(LOOK_STORAGE_KEY)).toBe(false);
    expect(() => setLook(true, { setItem: () => { throw new Error("blocked"); }, removeItem: () => undefined })).not.toThrow();
    setLook(false, s);
  });

  it("sets and removes the attributes on the root", () => {
    const root = { dataset: {} as Record<string, string> } as unknown as HTMLElement;
    applyLook(true, root);
    expect(root.dataset.look).toBe("glass");
    applyLook(false, root);
    expect(root.dataset.look).toBeUndefined();
    applyPeriod("dusk", root);
    expect(root.dataset.period).toBe("dusk");
  });
});
