// Competition's charts (spec docs/specs/2026-10-30-charts-everywhere.md, part B), drawn with the chart kit
// (src/ui/charts) from competition()'s figures, unchanged: each market's share as a donut, the threats as a timeline by
// scan day, the openings as a scatter (stars against rivals' departures a week, sized by distance, coloured by variant
// family, hubs-first allowed ringed), each rival's fleet and orders by type, and the order books against the flag.
import { SERIES, TONE, type DonutPart, type HBarItem, type SizedPoint, type StackRow, type StackSeries, type TimelineRow } from "../../ui/charts";
import { dayWords, kmWords, n0, pctWords, shareBar, starsWords, variantWords, type Fleet, type Market, type Opening, type OrderFlag, type Threat } from "./model";

const DAY_MS = 86_400_000;
/** Our share's colour in every Competition chart. */
export const OURS = TONE.violet;
/** The rivals' colours in a market, in their order (the rest last, grey). */
const RIVALS = SERIES.slice(1);

/** A market's donut: ours (in the airline's colour), each top rival and the other rivals, by departures a week (shareBar's
 *  parts, the same order). */
export function marketDonut(m: Market, ours: string = OURS): (DonutPart & { pct: number })[] {
  const parts = shareBar(m);
  return parts.map((p, i) => ({
    key: p.ours ? "ours" : p.label === "others" && i === parts.length - 1 ? "others" : `r${i}`,
    label: p.label, value: Math.round(p.pct * m.total) / 100, pct: p.pct,
    color: p.ours ? ours : p.label === "others" && i === parts.length - 1 ? "#C9CEDB" : (RIVALS[(i - 1) % RIVALS.length] as string),
  }));
}

/** The threats as a timeline: a row per rival on an airline's page, per our airline on the group's (`by`), each threat a
 *  mark on its scan day, linking to its route's page; t0 a day before the first, t1 a day after the last (or today). */
export function threatTimeline<T extends Threat & { al?: { code: string | null; name: string } }>(items: readonly T[], by: "rival" | "airline",
  routeHref: (t: T) => string | null, today?: string): { rows: TimelineRow[]; t0: number; t1: number; ticks: { t: number; label: string }[] } | null {
  if (!items.length) return null;
  const day = (t: T) => Date.parse(t.on.slice(0, 10) + "T00:00:00Z");
  const keyOf = (t: T) => (by === "rival" ? String(t.rival_id) : t.al?.code ?? "?");
  const order: string[] = [];
  const rows = new Map<string, TimelineRow & { marks: TimelineRow["marks"][number][] }>();
  for (const t of items) {
    const k = keyOf(t);
    if (!rows.has(k)) { order.push(k); rows.set(k, { key: k, label: by === "rival" ? t.rival : t.al?.code ?? "?", marks: [] }); }
    const href = routeHref(t);
    rows.get(k)!.marks.push({ t: day(t), kind: t.kind, tip: `${dayWords(t.on)} · ${by === "airline" && t.al?.code ? t.al.code + " · " : ""}${t.words}`, ...(href ? { href } : {}) });
  }
  const days = [...new Set(items.map(day))].sort((a, b) => a - b);
  const last = Math.max(days[days.length - 1] as number, today ? Date.parse(today + "T00:00:00Z") : 0);
  return {
    rows: order.map((k) => rows.get(k)!),
    t0: (days[0] as number) - DAY_MS, t1: last + DAY_MS,
    ticks: days.map((t) => ({ t, label: dayWords(new Date(t).toISOString()) })),
  };
}

/** A variant's family: its type up to the model number ("A320neo SHARP" → "A320", "737-9 HGW" → "737", "E195-E2" →
 *  "E195"), or "other" with none. */
export function variantFamily(type: string | null | undefined): string {
  const m = /^([A-Za-z]*\d{2,3})/.exec(String(type ?? "").trim());
  return m ? (m[1] as string).toUpperCase() : "other";
}
/** The openings as sized points: x the rivals' departures a week, y the stars (nudged a little apart by rank, so equal
 *  stars don't sit on one another), size the distance, colour the variant family (the five commonest named, the rest
 *  grey), ringed when hubs first allows it. */
export function openingPoints(openings: readonly Opening[]): { points: SizedPoint[]; families: { label: string; color: string }[] } {
  const count = new Map<string, number>();
  for (const o of openings) { const f = variantFamily(o.variant.type); count.set(f, (count.get(f) ?? 0) + 1); }
  const named = [...count.entries()].filter(([f]) => f !== "other").sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).slice(0, 5).map(([f]) => f);
  const colorOf = (f: string) => { const i = named.indexOf(f); return i < 0 ? "#9AA4C4" : (SERIES[i] as string); };
  const families = named.map((f) => ({ label: f, color: colorOf(f) }));
  if ([...count.keys()].some((f) => !named.includes(f))) families.push({ label: "other", color: "#9AA4C4" });
  return {
    families,
    points: openings.map((o) => ({
      key: String(o.route_id), x: o.rivals_weekly, y: (o.stars ?? 0) + (((o.rank % 5) - 2) * 0.06), size: o.distance_km ?? 0,
      color: colorOf(variantFamily(o.variant.type)), ring: o.allowed,
      tip: `#${o.rank} ${o.route} · ${starsWords(o.stars)} · ${kmWords(o.distance_km)} · rivals ${n0(o.rivals_weekly)} a week · ${variantWords(o.variant)} · ${o.allowed ? "hubs first allows it" : `not yet: ${o.reason ?? "hubs first"}`}`,
    })),
  };
}

/** A rival's fleet by type: a bar per type of its aircraft, then those on order. */
export const FLEET_SERIES: StackSeries[] = [{ key: "fleet", label: "in its fleet", color: TONE.ink }, { key: "order", label: "on order", color: "#E39B21" }];
export function fleetRows(f: Fleet | null | undefined): StackRow[] {
  return (f?.types ?? []).map((t) => ({
    key: t.type, label: t.type, parts: { fleet: t.overall ?? 0, order: t.on_order ?? 0 },
    tip: (s, n) => `${t.type}: ${n0(n)} ${s.key === "fleet" ? "in its fleet" : "on order"}`,
  }));
}

/** The order books as bars: each rival's aircraft on order as a share of its fleet (a starting rival, with no flights yet,
 *  drawn full and said so), coloured by whether it meets our airlines; the flag's threshold is the reference line. `short`
 *  (a narrow chart) writes the share alone. */
export function orderBookBars(books: readonly (OrderFlag & { meets_codes: string[] })[], flagPct: number, short = false): { items: HBarItem[]; ref: { value: number; label: string }; max: number } {
  const shares = books.map((f) => f.share).filter((v): v is number => v != null);
  const max = Math.max(flagPct, ...shares, 1);
  return {
    max,
    ref: { value: flagPct, label: `flag ${flagPct}%` },
    items: books.map((f) => ({
      key: String(f.airline_id), label: f.name,
      value: f.kind === "starting" || f.share == null ? max : f.share,
      text: f.kind === "starting" || f.share == null ? (short ? `${n0(f.on_order)}, starting` : `${n0(f.on_order)} on order, no flights yet`)
        : short ? pctWords(f.share) : `${pctWords(f.share)} · ${n0(f.on_order)} of ${n0(f.fleet)}`,
      color: f.meets ? TONE.bad : TONE.mute,
      tip: `${f.name}: ${f.words}${f.meets ? ` · meets ${f.meets_codes.join(", ")}` : " · meets none of our airlines"}`,
    })),
  };
}
