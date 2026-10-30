// Today's chart (spec docs/specs/2026-10-30-charts-everywhere.md, part C): Orders as a timeline, a row per airline and
// delivery line: each queued aircraft's arrival until the line runs dry, now, and when its first type is safe to order by
// the cash forecast. The figures are the Orders table's (useAttention's orders: growth.orderQueues and cash_forecast()),
// unchanged; the table stays one tap away.
import type { TimelineRow } from "../../ui/charts";
import { runsDryWords, type OrderRow } from "./model";

const DAY_MS = 86_400_000;
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const dayLabel = (ms: number) => { const d = new Date(ms); return `${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}`; };

/** The orders' timeline: rows in the table's order (airline, then its lines), from a day before now to 14 days on (or the
 *  last arrival, at most 28 days on; later ones sit on the edge, their tips saying when), ticks every other day at
 *  midnight UTC. Marks: "arrive" for each queued aircraft, "dry" for the last (amber when it runs dry within
 *  order_queue_warn_h), "safe" when the line's first type is safe to order. */
export function ordersTimeline(orders: readonly OrderRow[], nowMs: number): { rows: TimelineRow[]; t0: number; t1: number; ticks: { t: number; label: string }[]; now: number } {
  const rows: TimelineRow[] = [];
  let last = nowMs;
  for (const o of orders) {
    for (const q of o.queues ?? []) {
      const who = `${o.airline.code ?? o.airline.name} · ${q.family}`;
      const n = q.arrivals.length;
      const marks: TimelineRow["marks"][number][] = q.arrivals.map((t, i) => ({
        t, kind: i === n - 1 ? (q.warn ? "dry warn" : "dry") : "arrive",
        tip: i === n - 1 ? `${who}: the last of ${n} on order arrives ${runsDryWords(t)} UTC, when the line runs dry` : `${who}: aircraft ${i + 1} of ${n} arrives ${runsDryWords(t)} UTC`,
      }));
      if (q.safe_ms != null) marks.push({ t: q.safe_ms, kind: "safe", tip: `${who}: ${q.safe_now ? "safe to order now" : `safe to order from ${dayLabel(q.safe_ms)}`}` });
      if (!n) marks.push({ t: nowMs, kind: "empty", tip: `${who}: nothing on order, the line stands idle` });
      last = Math.max(last, ...q.arrivals);
      rows.push({ key: `${o.airline.id}|${q.family}`, label: who, marks });
    }
  }
  const t0 = nowMs - DAY_MS, t1 = Math.min(nowMs + 28 * DAY_MS, Math.max(nowMs + 14 * DAY_MS, last + DAY_MS));
  const first = Math.ceil(t0 / DAY_MS) * DAY_MS, ticks: { t: number; label: string }[] = [];
  for (let t = first; t <= t1; t += 2 * DAY_MS) ticks.push({ t, label: dayLabel(t) });
  return { rows, t0, t1, ticks, now: nowMs };
}
