// Competition's charts (spec docs/specs/2026-10-30-charts-everywhere.md, part B), drawn with the chart kit (src/ui/charts)
// from charts.ts's shapes: each market's share as a donut, the threats as a timeline, the openings as a scatter, each
// rival's fleet by type and the order books against the flag. Each has its title or place, its legend, tips and an empty
// state in words; the tables they stand in front of stay one tap away (ChartOrTable, in Competition.tsx).
import { useNavigate } from "react-router";
import {
  ChartFrame, Donut, HBars, Legend, SizedScatter, StackedBars, Timeline, donutLayout, hbarLayout, sizedScatterLayout, stackLayout, timelineLayout,
} from "../../ui/charts";
import { FLEET_SERIES, fleetRows, marketDonut, openingPoints, orderBookBars, threatTimeline } from "./charts";
import { n0, pctWords, type Fleet, type Market, type Opening, type OrderFlag, type Threat } from "./model";

/** A market's share as a donut, our share in the middle; the rivals' list beside it is its legend (colours from here). */
export function MarketDonut({ m, color }: { m: Market; color?: string | null }) {
  const parts = marketDonut(m, color ?? undefined);
  if (!parts.length) return null;
  return <Donut g={donutLayout(parts, { size: 120, ring: 20, fmt: (v) => `${n0(v)} a week` })} middle={pctWords(m.share)} label={`${m.name}: market share`} figure="competition: market donut" />;
}
/** The colour each label has in a market's donut (for its list). */
export const donutColors = (m: Market, color?: string | null): Map<string, string> => new Map(marketDonut(m, color ?? undefined).map((p) => [p.label, p.color]));

/** The threats as a timeline by scan day, each mark a threat; a tap opens its route's page. */
export function ThreatsChart<T extends Threat & { al?: { code: string | null; name: string } }>({ items, by, href, today }: {
  items: readonly T[]; by: "rival" | "airline"; href: (t: T) => string | null; today?: string;
}) {
  const navigate = useNavigate();
  const t = threatTimeline(items, by, href, today);
  return (
    <ChartFrame title="By scan day" note={`each threat on the day its scan saw it, a row per ${by === "rival" ? "rival" : "airline"} · tap one for its route's page`}
      legend={[{ label: "started on a pair", color: "#B4234B" }, { label: "added a daily flight or more", color: "#E39B21" }]}
      figure="competition: threats chart" empty={t ? null : "No rival moves in the last 7 days."}>
      {t ? <Timeline layout={(W) => timelineLayout(t.rows, { t0: t.t0, t1: t.t1, ticks: t.ticks, W, L: by === "rival" ? 140 : 60 })}
        label="threats by scan day" figure="competition: threats timeline" onPick={(h) => navigate(h.replace(/^\/planner/, ""))} /> : null}
    </ChartFrame>
  );
}

/** The openings as a scatter: stars against the rivals' departures a week, sized by distance, coloured by variant family,
 *  ringed where hubs first allows it. The ranked list stays under it. */
export function OpeningsChart({ openings }: { openings: readonly Opening[] }) {
  const o = openingPoints(openings);
  return (
    <ChartFrame title="Stars against rivals" note={`the ${openings.length} openings shown below · size: distance · ringed: hubs first allows it now`}
      legend={o.families} figure="competition: openings chart" empty={openings.length ? null : "No openings."}>
      <SizedScatter layout={(W) => sizedScatterLayout(o.points, { fmtX: (v) => n0(v), fmtY: (v) => `${v}★`, W, y: { lo: 0.5, hi: 5.5, ticks: [1, 2, 3, 4, 5] } })} xLabel="rivals' departures a week" yLabel="stars"
        figure="competition: openings scatter" />
    </ChartFrame>
  );
}

/** A rival's fleet and orders by type. */
export function FleetChart({ f, name }: { f: Fleet | null | undefined; name: string }) {
  const rows = fleetRows(f);
  if (!rows.length) return null;
  return (
    <div className="cpfleet" data-fleet-types>
      <StackedBars layout={(W) => stackLayout(rows, FLEET_SERIES, { W, L: 96, row: 20 })} label={`${name}: fleet by type`} figure="competition: fleet by type" />
      <Legend items={FLEET_SERIES.map((s) => ({ label: s.label, color: s.color }))} />
    </div>
  );
}

/** The order books: each rival's orders as a share of its fleet, the flag's threshold as a line. */
export function OrderBooksChart({ books, flagPct }: { books: readonly (OrderFlag & { meets_codes: string[] })[]; flagPct: number }) {
  return (
    <ChartFrame title="On order against fleet" note={`each rival's aircraft on order as a share of its fleet · the line is the flag, ${flagPct}%`}
      legend={[{ label: "meets our airlines", color: "#B4234B" }, { label: "meets none", color: "#9AA4C4" }]} figure="competition: order books chart"
      empty={books.length ? null : "No rival has a big order book or orders without flights in the latest scan."}>
      <HBars layout={(W) => { const b = orderBookBars(books, flagPct, W < 520); return hbarLayout(b.items, { fmt: (v) => `${Math.round(v)}%`, ref: b.ref, W, L: W < 520 ? 100 : 150, R: W < 520 ? 70 : 150 }); }}
        label="order books against the flag" figure="competition: order books bars" />
    </ChartFrame>
  );
}
