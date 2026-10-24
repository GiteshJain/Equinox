import { describe, expect, it } from "vitest";
import { FIGURES_STALE_MS, STALE_MS, queryClient, tableKey } from "./query";

// 24 Oct: the captured figures stay fresh 15 minutes (they change only with a capture); tables and the capture's and
// the systems' state stay at a minute.
const stale = (key: readonly unknown[]) => queryClient.defaultQueryOptions({ queryKey: key }).staleTime;

describe("how long reads stay fresh", () => {
  it("keeps the captured figures 15 minutes", () => {
    expect(FIGURES_STALE_MS).toBe(15 * 60_000);
    expect(stale(["figures", "competition", 1])).toBe(FIGURES_STALE_MS);
    expect(stale(["figures", "route_loads", "routes and flights", 1])).toBe(FIGURES_STALE_MS);
    expect(stale(tableKey("fare_plan", "ladder", 1))).toBe(FIGURES_STALE_MS);
  });
  it("keeps tables, the capture's state and the systems' state at a minute", () => {
    expect(stale(tableKey("routes", 1))).toBe(STALE_MS);
    expect(stale(tableKey("fare_plan", 1))).toBe(STALE_MS);
    expect(stale(["figures", "capture_status", 1])).toBe(STALE_MS);
    expect(stale(["figures", "capture_status", "check", 1])).toBe(STALE_MS);
    expect(stale(["figures", "system_status", 1])).toBe(STALE_MS);
  });
});
