// Today's logic (spec docs/specs/2026-10-20-today-performance-systems.md): the answer at the top ("what do I do now?",
// All clear when nothing is waiting), the capture in one line, each airline's orders and the aircraft to file. Every
// figure is its one home's (decision #19): the capture's from capture_status(), can order and the safe types from
// airline_cards() and cash_forecast(), the delivery lines from the planning library's growth.orderQueues, the aircraft
// on order from their table. This file only words them, so the unit tests can try each case.
import type { QueueCell } from "@rules";
import type { OurAirline } from "../../data/airlines";
import { shortType } from "../../ui/aircraftNames";
import { fcDay, type ForecastType, type NextOrder } from "../performance/model";
import type { CaptureRead, TodoRow } from "../home/reads";
import type { OnOrderGroup } from "./onOrder";
import { itemRoute } from "../screens";
import { attKind, groupAttention, type AttClass, type AttItem } from "../../ui/attention";
import { niceDate } from "../../ui/dates";
import { CAPTURE_BAD_H, CAPTURE_LATE_H } from "./attention";

export type Mark = "ok" | "warn" | "bad";

// ---------- the answer at the top: All clear, or what's waiting
export interface Waiting {
  /** Our airlines that can safely order now (airline_cards()'s can order). */
  canOrder: readonly string[];
  /** Aircraft that have arrived with a plan card, waiting to be filed. */
  toFile: number;
  /** Needs attention's groups as Today lists them, a section each (those dismissed left out; Can order is counted with
   *  the orders, so it isn't here). Since 23 Oct, spec docs/specs/2026-10-23-attention-on-home.md. */
  attention: readonly { label: string; count: number }[];
  /** Differences Game check found, once it has been run (0 before). */
  game: number;
}

const plural = (n: number, one: string, many = one + "s") => `${n} ${n === 1 ? one : many}`;

/** The answer at the top of Today: All clear when nothing is waiting (no order possible, nothing to file, no attention
 *  items, no Game check differences), else how many things and what. Since 23 Oct each group of needs attention counts
 *  as its own thing, as Today shows each as its own section, so the count matches the sections (until then needs
 *  attention counted once while the cards split it by kind: the 22 Oct handover's title/count mismatch). */
export function waitingWords(w: Waiting): { clear: boolean; title: string; parts: string[] } {
  const groups = w.attention.filter((g) => g.count > 0);
  const parts = [
    ...(w.canOrder.length ? [`${w.canOrder.join(", ")} can order`] : []),
    ...(w.toFile ? [`${plural(w.toFile, "aircraft", "aircraft")} to file`] : []),
    ...groups.map((g) => `${g.count} in ${g.label}`),
    ...(w.game ? [`${plural(w.game, "Game check difference")}`] : []),
  ];
  if (!parts.length) return { clear: true, title: "All clear", parts: ["Nothing to order, file or fix from the game, and nothing needs attention."] };
  const n = parts.length;
  return { clear: false, title: n === 1 ? "One thing waiting" : `${n} things waiting`, parts };
}

// ---------- the capture in one line
export type CaptureState = "complete" | "missing" | "short" | "broken";
export interface CaptureLine { state: CaptureState; mark: Mark; text: string }

const WORDS = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"];
const numberWord = (n: number): string => WORDS[n] ?? String(n);

/** A moment as the line writes it: "17:08 UTC" on the day it is, else "19 Oct 17:08 UTC". */
export function clockWords(at: string, now: Date): string {
  const d = new Date(at);
  const hm = d.toISOString().slice(11, 16) + " UTC";
  if (d.toISOString().slice(0, 10) === now.toISOString().slice(0, 10)) return hm;
  return `${d.getUTCDate()} ${d.toLocaleString("en-GB", { month: "short", timeZone: "UTC" })} ${hm}`;
}

/** The capture in one line, from capture_status() (Home's read: each airline's latest page, and its latest verdict):
 *  complete ("All six airlines captured, all good, 17:08 UTC"), or what's missing (an airline not captured for over a
 *  day, needs attention's 26 hours; red after 48), short (amber) or broken (red). A verdict counts the same night only,
 *  as needs attention counts it; a capture stored before the page checks counts as good. */
export function captureLine(airlines: readonly Pick<OurAirline, "id" | "name">[], cap: CaptureRead, now: Date): CaptureLine {
  const hours = (at: string | null | undefined) => (at ? (now.getTime() - Date.parse(at)) / 3_600_000 : null);
  // the airlines the capture covers (capture_status()'s: our active airlines with a home base), in our order
  const rows = airlines.filter((a) => cap.last.some((x) => x.airline_id === a.id)).map((a) => {
    const at = cap.last.find((x) => x.airline_id === a.id)?.at ?? null;
    const h = hours(at);
    const v = (cap.verdicts ?? []).filter((x) => x.airline_id === a.id && (hours(x.at) ?? Infinity) <= CAPTURE_LATE_H)
      .sort((x, y) => Date.parse(y.at) - Date.parse(x.at))[0];
    return { a, at, h, captured: h != null && h <= CAPTURE_LATE_H, verdict: v?.verdict ?? null, words: String(v?.words ?? "").replace(/^(short|broken):\s*/, "") };
  });
  const missing = rows.filter((r) => !r.captured);
  const short = rows.filter((r) => r.captured && r.verdict === "short");
  const broken = rows.filter((r) => r.captured && r.verdict === "broken");
  const latest = rows.filter((r) => r.captured && r.at).map((r) => r.at as string).sort((x, y) => Date.parse(y) - Date.parse(x))[0];
  const n = rows.length;
  const head = !missing.length
    ? (n === 1 ? `${rows[0]?.a.name} captured` : `All ${numberWord(n)} airlines captured`)
    : missing.length === n ? "No airline captured in the last day" : `${n - missing.length} of ${n} airlines captured`;
  const when = latest ? clockWords(latest, now) : "";
  const state: CaptureState = broken.length ? "broken" : missing.length ? "missing" : short.length ? "short" : "complete";
  if (state === "complete") return { state, mark: "ok", text: `${head}, all good${when ? ", " + when : ""}` };
  const names = (list: typeof rows) => list.map((r) => r.a.name).join(", ");
  const what = (list: typeof rows) => list.map((r) => (r.words ? `${r.a.name} (${r.words})` : r.a.name)).join(", ");
  const parts = [
    head + (when ? ", " + when : ""),
    ...(missing.length && missing.length < n ? [`not captured: ${names(missing)}`] : []),
    ...(missing.length === n ? ["press Capture all airlines in the game"] : []),
    ...(short.length ? [`short: ${what(short)}`] : []),
    ...(broken.length ? [`broken: ${what(broken)}`] : []),
  ];
  const late = missing.some((r) => r.h == null || r.h > CAPTURE_BAD_H);
  return { state, mark: broken.length || late ? "bad" : "warn", text: parts.join(" · ") };
}

// ---------- orders: whether each airline can order now or from when, the types that are safe, and its delivery lines
export interface OrderRow {
  airline: OurAirline;
  /** Can order now (an action: amber), safe from a day, needs a capture, or not within 14 days. */
  status: { kind: "now" | "later" | "needs" | "none"; text: string };
  /** Every type safe to order (cash_forecast()'s), by when: now, then each day from which some are safe; none when it
   *  can't say. Folded under the card ("all safe types") since 21 Oct. */
  types: { when: string; now: boolean; names: string[] }[];
  /** Each delivery line the airline may have, read once: when its first type is safe to order (null when the forecast
   *  has no type of that line), how many are on order and when it runs dry, or empty. */
  lines: { family: string; safe: LineSafe | null; text: string; warn: boolean; soon: string | null }[];
}
/** When a delivery line's first type is safe to order: "safe now", "safe from Wed, Oct 21" or "not safe within 14 days". */
export interface LineSafe { now: boolean; text: string }

/** When an order queue runs dry, in UTC: "10-14 05:53". */
export const runsDryWords = (ms: number): string => new Date(ms).toISOString().slice(5, 16).replace("T", " ");
/** How soon: "now" once past, else "in 12 h". */
export const soonWords = (hours: number): string => (hours < 0 ? "now" : "in " + Math.max(0, Math.round(hours)) + " h");

/** An airline's order status, from its card's next order (airline_cards(), from cash_forecast()). */
export function orderStatus(next: NextOrder | null | undefined, canNow: readonly string[] | null | undefined): OrderRow["status"] {
  if (canNow?.length) return { kind: "now", text: "Can order now" };
  if (!next || next.when === "needs") return { kind: "needs", text: `Needs ${next?.missing || "a capture"}` };
  if (next.when === "now") return { kind: "now", text: "Can order now" };
  if (next.when === "later" && next.safe_from) return { kind: "later", text: `Safe from ${fcDay(next.safe_from)}` };
  return { kind: "none", text: "Not within 14 days" };
}

/** The types that are safe, from cash_forecast()'s types, grouped by when: now first, then each first safe day. Each
 *  short name shows once in its group (the forecast lists a type's variants apart, and several share a short name). A
 *  type that isn't safe within 14 days is left out. */
export function safeTypes(types: readonly ForecastType[] | undefined): OrderRow["types"] {
  const groups = new Map<string, { when: string; now: boolean; day: number; names: string[] }>();
  for (const t of types ?? []) {
    if (t.safe_day == null || (t.safe_day !== 0 && !t.safe_from)) continue;
    const now = t.safe_day === 0, when = now ? "now" : `from ${fcDay(t.safe_from as string)}`;
    let g = groups.get(when);
    if (!g) groups.set(when, (g = { when, now, day: t.safe_day, names: [] }));
    const name = shortType(t.type);
    if (!g.names.includes(name)) g.names.push(name);
  }
  return [...groups.values()].sort((a, b) => a.day - b.day).map(({ when, now, names }) => ({ when, now, names }));
}

/** When a delivery line's first type is safe to order, from cash_forecast()'s types of that line's family (the family
 *  the order queues use): the earliest safe day of any of them, "safe now" or "safe from" that day; "not safe within 14
 *  days" when none is; null when the forecast has no type of the line (no forecast yet, or none of its types). */
export function lineSafe(family: string, types: readonly ForecastType[] | undefined, familyOfType: (t: ForecastType) => string): LineSafe | null {
  const mine = (types ?? []).filter((t) => familyOfType(t) === family);
  if (!mine.length) return null;
  const safe = mine.filter((t) => t.safe_day === 0 || (t.safe_day != null && t.safe_from));
  if (!safe.length) return { now: false, text: "not safe within 14 days" };
  const first = safe.reduce((a, b) => ((b.safe_day as number) < (a.safe_day as number) ? b : a));
  return first.safe_day === 0 ? { now: true, text: "safe now" } : { now: false, text: `safe from ${fcDay(first.safe_from as string)}` };
}

/** Each delivery line the airline may have (the families not in its fleet left out), read once: when its first type is
 *  safe to order (lineSafe), then how many on order and when the last arrives, warned when it runs dry within
 *  order_queue_warn_h; or empty, standing idle. */
export function deliveryLines(cells: readonly QueueCell[], types?: readonly ForecastType[], familyOfType?: (t: ForecastType) => string): OrderRow["lines"] {
  return cells.filter((c) => c.in_fleet).map((c) => {
    const safe = familyOfType ? lineSafe(c.family, types, familyOfType) : null;
    return c.count && c.last_ms != null
      ? { family: c.family, safe, text: `${c.count} on order · runs dry ${runsDryWords(c.last_ms)} UTC`, warn: c.warn, soon: c.warn && c.hours != null ? soonWords(c.hours) : null }
      : { family: c.family, safe, text: "empty: nothing on order", warn: false, soon: null };
  });
}

// ---------- aircraft to file: arrived with a plan card (Home's Aircraft on order, whose File into planner moved here)
export interface FileRow { airline: OnOrderGroup["airline"]; registration: string; type: string; config: string; at: number; base: string; plan: string; href: string }

/** The aircraft that have arrived with a plan card, airline by airline, soonest first, each with its link to file it on
 *  Tails (/tails?airline=PA&file=N123AB). */
export function toFile(groups: readonly OnOrderGroup[]): FileRow[] {
  return groups.flatMap((g) => g.rows.filter((r) => r.arrived && r.hasCard).map((r) => ({
    airline: g.airline, registration: r.registration, type: r.type, config: r.config, at: r.at, base: r.base, plan: r.plan,
    href: "/tails?" + new URLSearchParams({ ...(g.airline.code ? { airline: g.airline.code } : {}), file: r.registration }).toString(),
  })));
}

// ---------- the new look, step 2 (22 Oct, spec docs/specs/2026-10-22-planner-look-today.md): the things waiting as
// cards, the delivery lines as one table, needs attention as count tiles. Only words and order: every figure is the one
// the boards above already show.

/** A delivery line as the orders table's cell says it, in short: when its first type is safe ("Safe now", "Safe from
 *  Wed, Oct 21", "Not safe within 14 days"; none when the forecast can't say), what's on order ("1 on order", "Nothing
 *  on order") and when it runs dry ("10-20 19:14", UTC, with "in 17 h" when that's within order_queue_warn_h). */
export interface LineCell { safe: LineSafe | null; onOrder: string; dry: string | null; soon: string | null; warn: boolean }

const cap1 = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

export function lineCell(l: OrderRow["lines"][number]): LineCell {
  const [count = "", dry = ""] = l.text.split(" · ");
  const empty = l.text.startsWith("empty");
  return {
    safe: l.safe ? { now: l.safe.now, text: cap1(l.safe.text) } : null,
    onOrder: empty ? "Nothing on order" : count,
    dry: empty || !dry ? null : dry.replace(/^runs dry /, "").replace(/ UTC$/, ""),
    soon: l.soon,
    warn: l.warn,
  };
}

/** The table's columns: every delivery line any airline has, narrow-body first, then the E-jets, then the A350 (others
 *  after, by name). */
export function lineColumns(rows: readonly Pick<OrderRow, "lines">[]): string[] {
  const rank = (f: string) => { const i = ["A320 family", "E195", "A350"].indexOf(f); return i < 0 ? 9 : i; };
  return [...new Set(rows.flatMap((r) => r.lines.map((l) => l.family)))].sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
}

/** One thing waiting, as its card says it: the small coloured kind line, the heading in the item's own words, a short
 *  line of detail, and its action: a link, where it's fixed or (since 23 Oct, the cards being Home's) the section on
 *  Today that lists its group. */
export interface WaitCard {
  key: string;
  kind: "order" | "maint" | "due" | "file" | "attention" | "game";
  label: string;
  heading: string;
  detail: string | null;
  /** The single most urgent card: the first airline that can order now, else (since 22 Oct) the Fleet card with the
   *  game's maintenance under the limit. */
  urgent: boolean;
  action: { text: string; href?: string; item?: AttItem };
}

export interface CardsInput {
  orders: readonly OrderRow[];
  toFile: readonly FileRow[];
  /** Needs attention's items, those dismissed left out. */
  attention: readonly AttItem[];
  todos: readonly TodoRow[];
  /** Game check's differences, once it has run. */
  game: number;
  today: string;
  /** Where an attention item is fixed (Today's hrefOf) and its screen's name. */
  hrefOf: (a: AttItem) => string;
  screenName: (a: AttItem) => string;
  locale?: string;
}

/** The cards, one per thing waiting, the most urgent first (Today's until 23 Oct; Home's since, spec
 *  docs/specs/2026-10-23-attention-on-home.md, placed after the hero): each airline that can order now; since 22 Oct (spec
 *  docs/specs/2026-10-22-fleet-capture.md §3) the Fleet card when the game shows an aircraft's maintenance under the
 *  limit, the most urgent kind after order now; each to-do due today or overdue, each aircraft to file, then the rest of
 *  needs attention a card per kind (one item: its words; more: the first item's words and how many more, opening its
 *  tile), and Game check's differences. An order or to-do item of needs attention has its own card already, so it isn't
 *  counted again. */
export function waitingCards(x: CardsInput): WaitCard[] {
  const out: WaitCard[] = [];
  for (const o of x.orders) {
    if (o.status.kind !== "now") continue;
    const now = o.types.find((t) => t.now)?.names ?? [];
    const later = o.types.find((t) => !t.now);
    out.push({
      key: "order|" + o.airline.id, kind: "order", label: "Order now", urgent: false,
      heading: now.length ? `${o.airline.name} can safely order: ${now.join(", ")}` : `${o.airline.name} can order now`,
      detail: later ? `Also safe ${later.when}: ${later.names.join(", ")}` : null,
      action: { text: "Cash, next 14 days", href: o.airline.code ? itemRoute("performance", { airline: o.airline.code }) : undefined },
    });
  }
  // the Fleet group, when the game shows maintenance under the limit: its card next, urgent when nothing can order
  const groups = groupAttention(x.attention.filter((a) => attKind(a) !== "order" && attKind(a) !== "todo"));
  const fleet = groups.find((g) => g.kind === "fleet");
  const maint = !!fleet?.items.some((a) => a.key?.startsWith("fleet|maintenance|"));
  const maintCard = fleet && maint ? attentionCard(fleet, x, "maint", "Fleet · maintenance") : null;
  if (maintCard) out.push(maintCard);
  const first = out[0];
  if (first) first.urgent = true;
  for (const a of x.attention) {
    if (attKind(a) !== "todo") continue;
    const t = x.todos.find((r) => "todo|" + (r.legacy_key ?? String(r.id)) === a.key);
    if (!t?.due_on) continue;
    out.push({
      key: "due|" + t.id, kind: "due", label: (t.due_on < x.today ? "Overdue · due " : "Due ") + (t.due_on === x.today ? "today" : niceDate(t.due_on, x.locale)),
      heading: t.title, detail: null, urgent: false, action: { text: "Open the to-do", href: itemRoute("today", { hash: "todo" }) },
    });
  }
  for (const r of x.toFile) {
    out.push({
      key: "file|" + r.registration, kind: "file", label: "To file", urgent: false,
      heading: `${r.registration} has arrived for ${r.airline.name}`,
      detail: [r.type + (r.config ? " " + r.config : ""), r.base, r.plan].filter(Boolean).join(" · ") || null,
      action: { text: "File into planner", href: r.href },
    });
  }
  for (const g of groups) {
    if (g === fleet && maint) continue;
    const card = attentionCard(g, x, "attention", "Needs attention");
    if (card) out.push(card);
  }
  if (x.game) {
    out.push({ key: "game", kind: "game", label: "Needs attention", heading: plural(x.game, "Game check difference"), detail: "between the planner and the game's schedules",
      urgent: false, action: { text: "Go to Game check", href: itemRoute("today", { hash: "game-check" }) } });
  }
  return out;
}

/** A group of needs attention as its card: one item, its words (opening where it's fixed); more, the first item's words
 *  and how many more, opening its section on Today (/today#att-<kind>, since 23 Oct). */
function attentionCard(g: ReturnType<typeof groupAttention>[number], x: CardsInput, kind: "attention" | "maint", label: string): WaitCard | null {
  const [one] = g.items;
  if (!one) return null;
  return g.items.length === 1
    ? { key: "att|" + g.kind, kind, label, heading: one.text, detail: g.label, urgent: false,
        action: { text: "Open " + x.screenName(one), href: x.hrefOf(one), item: one } }
    : { key: "att|" + g.kind, kind, label, heading: one.text,
        detail: `and ${g.items.length - 1} more in ${g.label}`, urgent: false,
        action: { text: `See all ${g.items.length}`, href: itemRoute("today", { hash: attentionAnchor(g.kind) }) } };
}

/** A count tile: the number, the group's name and one muted line. */
export interface CountTile { key: string; count: number; name: string; line: string; cls: AttClass | "file" }

const SERIOUS: Record<AttClass, string> = { bad: "urgent", warn: "to look at", ok: "to act on", mute: "for information" };

/** The tiles, in order: Aircraft to file, then every group of needs attention (groupAttention's order: the most serious
 *  first). Each tile's line says how serious its items are ("2 urgent · 1 to look at"). */
export function countTiles(toFile: number, attention: readonly AttItem[]): CountTile[] {
  const tiles: CountTile[] = [{ key: "to-file", count: toFile, name: "Aircraft to file", cls: "file",
    line: toFile ? "arrived with a plan card" : "nothing has arrived" }];
  for (const g of groupAttention(attention)) {
    const by = (["bad", "warn", "ok", "mute"] as const).map((c) => [c, g.items.filter((a) => a.cls === c).length] as const).filter(([, n]) => n);
    tiles.push({ key: g.kind, count: g.items.length, name: g.label, cls: g.cls, line: by.map(([c, n]) => `${n} ${SERIOUS[c]}`).join(" · ") });
  }
  return tiles;
}

// ---------- each section's anchor (since 23 Oct, spec docs/specs/2026-10-23-attention-on-home.md): Home's cards open a
// group's section on Today by it. Aircraft to file keeps its own (#to-file, Home's "to file on Today" until 23 Oct); a
// group of needs attention's is att-<kind> (#att-route, #att-fleet), never the bare kind, which for to-dos would be the
// To-do board's #todo.

/** A section's anchor on Today: "to-file", else "att-" and the group's kind. */
export const attentionAnchor = (key: string): string => (key === "to-file" ? "to-file" : "att-" + key);

/** The section an address's anchor opens on Today (the tile's key), or null when it names none. */
export function tileForHash(hash: string): string | null {
  const id = hash.replace(/^#/, "");
  if (id === "to-file") return "to-file";
  return id.startsWith("att-") && id.length > 4 ? id.slice(4) : null;
}

// ---------- where an attention item is fixed (Today's hrefOf until 23 Oct; shared with Home's cards since)
/** Where an attention item is fixed, inside the planner's router (Today's since 20 Oct). */
export function attentionHref(a: AttItem, airlines: readonly Pick<OurAirline, "name" | "code">[]): string {
  if (a.screen === "today") return itemRoute("today", { hash: "todo" });
  if (a.tail) return itemRoute(a.screen, { tail: a.tail });
  if (a.route) {
    const [al = "", hub = "", dest = ""] = a.route.split("|");
    return itemRoute(a.screen, { airline: airlines.find((x) => x.name === al)?.code, hub, dest });
  }
  // can order: the airline's page on Performance, with its cash for the next 14 days
  if (a.screen === "performance" && a.key?.startsWith("order|")) return itemRoute("performance", { airline: airlines.find((x) => x.name === a.key?.split("|")[1])?.code });
  // a rival's move: the airline's Competition page (its key: threat|<code>|<pair>|<rival>|<day>)
  if (a.screen === "competition" && a.key?.startsWith("threat|")) return itemRoute("competition", { airline: a.key.split("|")[1] });
  // a cabin charge that doesn't match: Systems' Cabin charges board, open on arrival
  if (a.screen === "systems" && a.key?.startsWith("cabin|")) return itemRoute("systems", { hash: "cabin-charges" });
  // an aircraft in the game the planner doesn't have: Systems' Fleet board, open on arrival
  if (a.screen === "systems" && a.key?.startsWith("fleet|")) return itemRoute("systems", { hash: "fleet" });
  return itemRoute(a.screen);
}

/** An item about one aircraft (its maintenance, turns or positions) opens its pop-up rather than going to Tails. */
export const opensAircraft = (a: AttItem): boolean => !!a.tail && !a.route && a.screen === "tails";
