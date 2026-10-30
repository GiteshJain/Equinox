// Orders as a timeline (spec docs/specs/2026-10-30-charts-everywhere.md, part C; charts.ts), drawn with the chart kit;
// Today.tsx puts the table behind it ("show as table").
import { ChartFrame, Timeline, timelineLayout } from "../../ui/charts";
import { ordersTimeline } from "./charts";
import type { OrderRow } from "./model";

export function OrdersChart({ orders, now }: { orders: readonly OrderRow[]; now: number }) {
  const t = ordersTimeline(orders, now);
  return (
    <ChartFrame title="Delivery lines" note="each line's aircraft on order until it runs dry, and when its first type is safe to order · the dashed line is now (UTC)"
      legend={[{ label: "an aircraft arrives", color: "#0E1630" }, { label: "the last: runs dry", color: "#4B3BA8" }, { label: "runs dry soon", color: "#E39B21" },
        { label: "safe to order", color: "#1A7F55" }, { label: "nothing on order", color: "#9AA4C4" }]}
      figure="today: orders chart" empty={t.rows.length ? null : "No delivery lines yet."}>
      <Timeline layout={(W) => timelineLayout(t.rows, { t0: t.t0, t1: t.t1, ticks: t.ticks, now: t.now, W, L: 150 })} label="delivery lines" figure="today: orders timeline" />
    </ChartFrame>
  );
}
