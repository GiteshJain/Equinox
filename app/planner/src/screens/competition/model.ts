// Competition's logic (spec docs/specs/2026-10-21-competition-analysis.md §3): the words for the scans, the group line,
// each market's share with its arrow and its top rivals as a bar, the threats, the openings table and the rival profiles,
// and Today's threat items. Every figure is competition()'s (the database's, private.fig_competition()): this file only
// words and orders them.

// ---------- competition()'s answer
export interface ScanRef { id: number; taken_at: string }
export interface Scans { latest: ScanRef | null; week_before: ScanRef | null; previous: ScanRef | null }
export interface GroupLine {
  ours: number; world: number; share: number | null;
  ours_before: number | null; world_before: number | null; share_before: number | null;
  ours_change: number | null; world_change: number | null; share_change: number | null;
}
export interface MarketRival { airline_id: number; name: string; weekly: number; weekly_before: number | null; change: number | null; share: number | null }
export interface Market {
  market_id: number | null; name: string; pairs: number; flown: number;
  ours: number; ours_before: number | null; ours_change: number | null;
  rivals: number; rivals_before: number | null; rivals_change: number | null; total: number;
  share: number | null; share_before: number | null; share_change: number | null;
  top: MarketRival[];
}
export interface Threat {
  rival_id: number; rival: string; pair: string; route: string; hub: string; dest: string; kind: "started" | "added";
  then: number; added: number; now: number; ours: number; scan_id: number; on: string; previous_id: number | null; previous_on: string | null;
  until: string; latest: boolean; words: string;
}
export interface Variant {
  type_id: number | null; type: string | null; seats: number | null; range_km: number | null; size: string | null; for_reach: boolean;
  /** False when the airline may not buy it: a November trunk no type of its own reaches takes the world's (manual §4). */
  own?: boolean | null;
}
export interface Opening {
  rank: number; route_id: number; route: string; hub: string; dest: string; pair: string; city: string | null;
  stars: number | null; distance_km: number | null; market_id: number | null;
  rivals_weekly: number; rivals: { airline_id: number; name: string; weekly: number }[];
  variant: Variant; allowed: boolean; allowed_by: string | null; reason: string | null;
  /** A pair between two of our bases, in the trunk month (manual §4: 1 to 30 November): first, shortest first. */
  trunk?: boolean;
  /** Our other airlines with the pair on their own list (one airline per city pair, manual §2, decides). */
  other_lists?: string[];
}
export interface Profile {
  airline_id: number; name: string; pairs_shared: number; weekly_on_pairs: number;
  weekly: number | null; weekly_before: number | null; change: number | null; airports: number | null;
  pairs: { pair: string; route: string; weekly: number; ours: number }[];
  biggest_airports: { code: string; weekly: number }[];
}
export interface CompetitionAnswer {
  airline_id: number; code: string | null; name: string | null; as_of: string; limit: number;
  scans: Scans;
  hubs_first: { main_hub: string | null; departures: number; target: number; exempt: boolean; open: boolean };
  group: GroupLine | null;
  markets: Market[];
  threats: Threat[];
  openings: Opening[];
  openings_count: number; openings_allowed: number; openings_left_out: number; openings_trunks?: number;
  /** November's trunks (manual §4): whether the moment is in the trunk month, and its first and last day. */
  trunk_month?: { on: boolean; from: string | null; to: string | null };
  profiles: Profile[];
  pairs_flown: number; pairs_listed: number;
  notes: string[];
}

// ---------- words
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** A moment's UTC day as the manual writes it: "21 Oct". */
export function dayWords(iso: string | null | undefined): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso ?? ""));
  return m ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1] ?? ""}` : "";
}

/** The scans at the top: "latest scan 17 Oct, compared with 6 Oct", or what's missing. */
export function scansWords(s: Scans | null | undefined): string {
  if (!s?.latest) return "no world scan yet: the evening capture takes one when it's due (Systems)";
  if (!s.week_before) return `latest scan ${dayWords(s.latest.taken_at)}, the only one: nothing to compare with yet`;
  return `latest scan ${dayWords(s.latest.taken_at)}, compared with ${dayWords(s.week_before.taken_at)}`;
}

/** A number with thousands separated, as the manual writes them: 97,960. */
export const n0 = (v: number | null | undefined): string => (v == null ? "—" : Math.round(Number(v)).toLocaleString("en-GB"));
/** A share: "4.1%". */
export const pctWords = (v: number | null | undefined): string => (v == null ? "—" : `${Number(v).toFixed(1)}%`);

export type Arrow = "up" | "down" | "flat";
/** A change with its arrow: points for a share ("▲ 0.2 pts", "= no change"), a count otherwise ("▲ 14", "="); none
 *  without a comparison. */
export function changeWords(change: number | null | undefined, points = false): { arrow: Arrow; text: string } | null {
  if (change == null) return null;
  const v = Number(change);
  const arrow: Arrow = v > 0 ? "up" : v < 0 ? "down" : "flat";
  const mark = arrow === "up" ? "▲" : arrow === "down" ? "▼" : "=";
  const size = points ? `${Math.abs(v).toFixed(1)} pts` : n0(Math.abs(v));
  return { arrow, text: arrow === "flat" ? (points ? "= no change" : "=") : `${mark} ${size}` };
}

/** The group line: "Our airlines: 4,016 of 97,960 departures a week, 4.1% of the world". */
export function groupWords(g: GroupLine | null | undefined): string {
  if (!g) return "no world scan yet";
  return `Our airlines: ${n0(g.ours)} of ${n0(g.world)} departures a week, ${pctWords(g.share)} of the world`;
}

/** A market's bar: our share and each top rival's, in order, the rest of the rivals as "others"; widths in percent. */
export function shareBar(m: Market): { label: string; pct: number; ours: boolean }[] {
  if (!m.total) return [];
  const parts = [{ label: "ours", pct: (m.ours / m.total) * 100, ours: true }];
  let shown = 0;
  for (const r of m.top) {
    parts.push({ label: r.name, pct: (r.weekly / m.total) * 100, ours: false });
    shown += r.weekly;
  }
  const rest = m.rivals - shown;
  if (rest > 0) parts.push({ label: "others", pct: (rest / m.total) * 100, ours: false });
  return parts.filter((p) => p.pct > 0);
}

/** The airline's share across all its markets: its departures and the rivals' added up (a market's pairs are its own). */
export function overallShare(markets: readonly Market[]): { ours: number; total: number; share: number | null; before: number | null; change: number | null } {
  const ours = markets.reduce((s, m) => s + m.ours, 0);
  const total = markets.reduce((s, m) => s + m.total, 0);
  const comparable = markets.every((m) => m.ours_before != null && m.rivals_before != null);
  const oursB = markets.reduce((s, m) => s + (m.ours_before ?? 0), 0);
  const totalB = markets.reduce((s, m) => s + (m.ours_before ?? 0) + (m.rivals_before ?? 0), 0);
  const share = total ? Math.round((ours / total) * 1000) / 10 : null;
  const before = comparable && totalB ? Math.round((oursB / totalB) * 1000) / 10 : null;
  return { ours, total, share, before, change: share != null && before != null ? Math.round((share - before) * 10) / 10 : null };
}

/** A threat's own numbers beside its words (which say the rival's then and now): "ours 14 a week". */
export function threatNumbers(t: Threat): string {
  return `ours ${t.ours} a week`;
}

/** A threat's day and how long it pauses the route on the fare ladder: "17 Oct · fares paused until 24 Oct". */
export function threatWhen(t: Threat): string {
  return `${dayWords(t.on)} · fares paused until ${dayWords(t.until)}`;
}

/** Stars as the manual writes them: "5★". */
export const starsWords = (s: number | null | undefined): string => (s == null ? "—" : `${s}★`);
/** A distance: "1,234 km". */
export const kmWords = (d: number | null | undefined): string => (d == null ? "—" : `${n0(d)} km`);

/** The rivals on an opening: "Air China 14, ANA 7 +2 more", or "none". */
export function rivalsWords(o: Pick<Opening, "rivals">, top = 2): string {
  if (!o.rivals.length) return "none";
  const head = o.rivals.slice(0, top).map((r) => `${r.name} ${r.weekly}`).join(", ");
  return o.rivals.length > top ? `${head} +${o.rivals.length - top} more` : head;
}

/** The variant: "A320neo SHARP", with "for reach" when it's bigger than the city's stars call for, and "not on its
 *  list" for a November trunk that only another airline's type reaches. */
export function variantWords(v: Variant): string {
  return v.type ? `${v.type}${v.for_reach ? " (for reach)" : ""}${v.own === false ? " (not on its list)" : ""}` : "—";
}

/** The trunk month's line over the openings, or nothing outside it: "November's trunks first (1–30 Nov): 4 trunks, shortest
 *  first, hubs first suspended for them (manual §4). Whether each makes sense stays the Scheduling chat's call." */
export function trunkMonthWords(a: Pick<CompetitionAnswer, "trunk_month" | "openings_trunks">): string | null {
  const m = a.trunk_month;
  if (!m?.on) return null;
  const n = a.openings_trunks ?? 0;
  return `November's trunks first (${dayWords(m.from)}–${dayWords(m.to)}): ${n} trunk${n === 1 ? "" : "s"}, shortest first, hubs first suspended for them (manual §4). `
    + "Whether each makes sense stays the Scheduling chat's call.";
}

/** Our other airlines with the pair on their list: "also on VS's list". */
export const otherListsWords = (o: Pick<Opening, "other_lists">): string | null =>
  (o.other_lists?.length ? `also on ${o.other_lists.join(" and ")}'s list` : null);

/** Hubs first in a word or two: "yes", or "no" with why (the database's reason). */
export function allowedWords(o: Pick<Opening, "allowed" | "allowed_by" | "reason">): { ok: boolean; text: string; why: string } {
  return o.allowed ? { ok: true, text: "yes", why: o.allowed_by ?? "" } : { ok: false, text: "not yet", why: o.reason ?? "hubs first" };
}

/** A profile's size line: "6,552 a week (▲ 1,540 since 6 Oct) · 120 airports". */
export function profileWords(p: Profile, before: string): string {
  const ch = changeWords(p.change);
  return `${n0(p.weekly)} a week` + (ch ? ` (${ch.text}${before ? " since " + before : ""})` : "") + (p.airports != null ? ` · ${n0(p.airports)} airports` : "");
}

/** The openings line for a card: "419 openings, 120 allowed under hubs first". */
export function openingsLine(a: Pick<CompetitionAnswer, "openings_count" | "openings_allowed" | "openings_left_out">): string {
  const n = a.openings_count;
  return `${n0(n)} opening${n === 1 ? "" : "s"}, ${n0(a.openings_allowed)} allowed under hubs first`
    + (a.openings_left_out ? ` · ${a.openings_left_out} beyond every type's reach` : "");
}

/** The threats line for a card: "3 threats" or "no threats". */
export const threatsLine = (n: number): string => (n ? `${n} threat${n === 1 ? "" : "s"} in the last 7 days` : "no threats in the last 7 days");

// ---------- Today: the threats from the latest scan in Needs attention
export interface ThreatItem { airline_id: number; code: string | null; threat: Threat }

/** The threats Today lists: those the latest scan showed (each airline's), in the airlines' order, the biggest first. */
export function latestThreats(answers: readonly (CompetitionAnswer | undefined)[]): ThreatItem[] {
  const out: ThreatItem[] = [];
  for (const a of answers) {
    if (!a) continue;
    const mine = a.threats.filter((t) => t.latest).sort((x, y) => y.now - x.now || x.rival.localeCompare(y.rival) || x.route.localeCompare(y.route));
    out.push(...mine.map((t) => ({ airline_id: a.airline_id, code: a.code, threat: t })));
  }
  return out;
}

/** Today's words for a threat: the database's ("Air China started on PVG–CAN, 14 a week"). */
export const threatItemWords = (t: Threat): string => t.words;

/** Today's key for a threat (its dismissal): the airline, the pair, the rival and the scan's day, so a new move shows again. */
export const threatKey = (x: ThreatItem): string => `threat|${x.code ?? x.airline_id}|${x.threat.pair}|${x.threat.rival_id}|${x.threat.on.slice(0, 10)}`;
