import { describe, expect, it } from "vitest";
import { limited, queueState } from "./limit";

const tick = () => new Promise<void>((r) => setTimeout(r, 0));

describe("limited", () => {
  it("never runs more than the limit at once, and runs them all in the order asked", async () => {
    let open = 0, peak = 0;
    const order: number[] = [];
    const gates: Array<() => void> = [];
    const jobs = Array.from({ length: 10 }, (_, i) =>
      limited(async () => {
        open++; peak = Math.max(peak, open); order.push(i);
        await new Promise<void>((go) => gates.push(go));
        open--;
        return i;
      }, 3),
    );
    await tick();
    expect(open).toBe(3);
    expect(queueState().waiting).toBe(7);
    while (gates.length || queueState().running) { gates.shift()?.(); await tick(); }
    expect(await Promise.all(jobs)).toEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(peak).toBe(3);
    expect(order).toEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(queueState()).toEqual({ running: 0, waiting: 0 });
  });

  it("passes a failure to its own caller and still frees its place", async () => {
    const bad = limited(() => Promise.reject(new Error("timeout")), 1);
    const good = limited(() => 7, 1);
    await expect(bad).rejects.toThrow("timeout");
    expect(await good).toBe(7);
    expect(queueState()).toEqual({ running: 0, waiting: 0 });
  });
});
