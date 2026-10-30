// Today's orders as a timeline (spec docs/specs/2026-10-30-charts-everywhere.md, part C): each delivery line's queued
// aircraft (the last when it runs dry, amber when soon), when its first type is safe, now; the figures the table's.
import { describe, expect, it } from "vitest";
import type { QueueCell } from "@rules";
import type { ForecastType } from "../performance/model";
import { ordersTimeline } from "./charts";
import { lineQueues, type OrderRow } from "./model";

const cell = (family: string, x: Partial<QueueCell>): QueueCell => ({ family, in_fleet: true, count: 0, last_ms: null, hours: null, warn: false, ...x });
const ms = (iso: string) => Date.parse(iso);
const type = (id: number, x: Partial<ForecastType>): ForecastType => ({ aircraft_type_id: id, type: "A320neo", price_with_cabin: 1, lease_week: 0.1, lease_seen: true, safe_day: null, safe_from: null, count_today: null, ...x });
const NOW = ms("2026-10-30T12:00:00Z");

describe("each delivery line's queue", () => {
  it("the queued aircraft are the family's last `count` deliveries, in order; safe from the earliest safe type; lines not in the fleet left out", () => {
    const deliveries = [{ family: "A320 family", delivery_ms: ms("2026-10-20T05:00:00Z") }, { family: "A320 family", delivery_ms: ms("2026-11-02T05:00:00Z") },
      { family: "A320 family", delivery_ms: ms("2026-10-31T05:00:00Z") }, { family: "E195", delivery_ms: null }];
    const types = [type(1, { safe_day: 3, safe_from: "2026-11-02T00:00:00Z" }), type(2, { safe_day: 5, safe_from: "2026-11-04T00:00:00Z" }), type(3, { safe_day: 0 })];
    const fam = (t: ForecastType) => (t.aircraft_type_id === 3 ? "E195" : "A320 family");
    const q = lineQueues([cell("A320 family", { count: 2, last_ms: ms("2026-11-02T05:00:00Z"), warn: true }), cell("E195", {}), cell("A350", { in_fleet: false })], deliveries, NOW, types, fam);
    expect(q).toEqual([
      { family: "A320 family", arrivals: [ms("2026-10-31T05:00:00Z"), ms("2026-11-02T05:00:00Z")], safe_ms: ms("2026-11-02T00:00:00Z"), safe_now: false, warn: true },
      { family: "E195", arrivals: [], safe_ms: NOW, safe_now: true, warn: false }]);
    expect(lineQueues([cell("A350", { count: 1 })], [{ family: "A350", delivery_ms: ms("2026-11-01T00:00:00Z") }], NOW)[0]?.safe_ms).toBeNull();
  });
});

describe("the orders' timeline", () => {
  const order = (code: string, queues: OrderRow["queues"]): OrderRow => ({ airline: { id: code.length, code, name: code } as OrderRow["airline"], status: { kind: "none", text: "" }, types: [], lines: [], queues });
  it("a row per airline and line, each aircraft a mark, the last when it runs dry, the safe day, nothing on order at now", () => {
    const t = ordersTimeline([order("PA", [{ family: "A320 family", arrivals: [ms("2026-10-31T05:00:00Z"), ms("2026-11-02T05:00:00Z")], safe_ms: ms("2026-11-02T00:00:00Z"), safe_now: false, warn: true },
      { family: "E195", arrivals: [], safe_ms: NOW, safe_now: true, warn: false }])], NOW);
    expect(t.rows.map((r) => [r.label, r.marks.map((m) => [m.t, m.kind])])).toEqual([
      ["PA · A320 family", [[ms("2026-10-31T05:00:00Z"), "arrive"], [ms("2026-11-02T05:00:00Z"), "dry warn"], [ms("2026-11-02T00:00:00Z"), "safe"]]],
      ["PA · E195", [[NOW, "safe"], [NOW, "empty"]]]]);
    expect(t.rows[0]?.marks.map((m) => m.tip)).toEqual(["PA · A320 family: aircraft 1 of 2 arrives 10-31 05:00 UTC",
      "PA · A320 family: the last of 2 on order arrives 11-02 05:00 UTC, when the line runs dry", "PA · A320 family: safe to order from Nov 2"]);
    // a day before now to 14 days on; ticks every other day at midnight UTC
    expect([t.t0, t.t1, t.now]).toEqual([NOW - 86_400_000, NOW + 14 * 86_400_000, NOW]);
    expect(t.ticks.slice(0, 3).map((x) => x.label)).toEqual(["Oct 30", "Nov 1", "Nov 3"]);
  });
  it("reaches the last arrival, at most 28 days on; no rows without lines", () => {
    const far = ms("2026-12-30T00:00:00Z");
    expect(ordersTimeline([order("PA", [{ family: "A350", arrivals: [ms("2026-11-20T00:00:00Z")], safe_ms: null, safe_now: false, warn: false }])], NOW).t1).toBe(ms("2026-11-21T00:00:00Z"));
    expect(ordersTimeline([order("PA", [{ family: "A350", arrivals: [far], safe_ms: null, safe_now: false, warn: false }])], NOW).t1).toBe(NOW + 28 * 86_400_000);
    expect(ordersTimeline([order("PA", [])], NOW).rows).toEqual([]);
  });
});
