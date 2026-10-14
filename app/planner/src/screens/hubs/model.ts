// Hubs' addresses and words (#18 build pull request 8; spec docs/specs/2026-10-13-hubs.md). Every figure is the planning
// library's (hubs.board and hubs.connectionsTable in lib/rules): this file only says where the screen is and writes the
// figures as the old Hubs wrote them (renderHub, hubConnections in web/planner/index.html).
import { banks, time, type RegionCount, type HubBoard, type HubConnectionRow, type HubConnections, type Rules } from "@rules";
import { itemRoute } from "../screens";

export const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** A local minute as "HH:MM" (the old H and H2). */
export const H = (m: number): string => time.clock(m);
/** A connection time as the old planner wrote one: "1:05". */
export const hhmm = (m: number): string => banks.duration(m);
const pad = (n: number) => String(n).padStart(2, "0");
export const hourLabel = (h: number): string => pad(h);

export interface Place {
  /** The airport named in the address, or null for the first board. */
  code: string | null;
  /** 0 = Monday to 6 = Sunday; Monday when the address names none, as the old Hubs opened. */
  day: number;
}

/** Where the address points: /planner/next/hubs/<airport>?day=<0-6>. The router gives the part after /hubs/. */
export function parsePlace(rest: string, search: string): Place {
  const code = decodeURIComponent(rest.split("/")[0] ?? "").trim().toUpperCase();
  const d = Number(new URLSearchParams(search).get("day"));
  return { code: code || null, day: Number.isInteger(d) && d >= 0 && d <= 6 ? d : 0 };
}

/** The address of one airport's board on one day, inside the planner's router, so a link reopens it. */
export const placePath = (code: string, day: number): string => itemRoute("hubs", { hub: code, day });

/** The count line's words before the cap: "23 departures · 23 arrivals today · 160 departures/week". */
export function countWords(b: HubBoard): string {
  return `${b.departures_today} departures · ${b.arrivals_today} arrivals today · ${b.departures_week} departures/week`;
}

/** After the cap (or the over-cap pill): " of 5,000 cap" when under it. */
export const capWords = (b: HubBoard, locale?: string): string => (b.over_cap ? "" : ` of ${b.cap.toLocaleString(locale)} cap`);

/** The next free pair: " · next free 1057 / 1058 (last used 1056)", or nothing without a block of numbers. */
export function nextWords(b: HubBoard): string {
  const nx = b.next_pair;
  if (!nx) return "";
  return ` · next free ${nx.out} / ${nx.back}${nx.highest ? ` (last used ${nx.highest})` : ""}`;
}

/** A focus city's note: it has no banks of its own and is timed to its hub's. */
export function focusWords(b: HubBoard): string {
  const p = b.base?.parent_code ?? null;
  return `${b.airport} is a focus city${p ? " feeding " + p : ""}: it has no banks of its own, so its flights are timed to ${p ? p + "'s" : "its hub's"} banks. `
    + `Check the connections on ${p ? p + "'s" : "the hub's"} board.`;
}

/** A share of the strip (or the hour's bar): the old planner's percentages, as CSS. */
export const pct = (part: number, whole: number): string => `${(part / whole) * 100}%`;
/** The width of a window that may wrap past midnight. */
export const span = (from: number, to: number): number => ((to - from) % 1440 + 1440) % 1440;

/** A week-grid cell's shade of the airline violet, as the old planner's --k (two decimals). */
export const shade = (n: number, max: number): string => (n / max).toFixed(2);

/** A week-grid cell's classes: the bank window it sits in, and the hour's first slot. */
export function cellClass(b: HubBoard, i: number): string {
  const s = b.slots[i];
  return (s === "dep" ? "wdep" : s === "arr" ? "warr" : "") + (i % 4 === 0 ? " hr" : "");
}

/** A connections row's name: "Bank 1 · 06:45", "Outside the banks", or "All connections" where there are no banks. */
export function rowLabel(t: Pick<HubConnections, "banked">, r: Pick<HubConnectionRow, "n" | "dep_local_min">): string {
  if (r.n && r.dep_local_min != null) return `Bank ${r.n} · ${H(r.dep_local_min)}`;
  return t.banked ? "Outside the banks" : "All connections";
}

/** The flights by region: "South Asia 6 · North America 3". */
export const regionWords = (list: readonly RegionCount[]): string => list.map((c) => `${c.region} ${c.flights}`).join(" · ");

/** A row's examples, tightest first: "CUN→ORD 2:01, ... …". */
export function exampleWords(r: Pick<HubConnectionRow, "examples" | "more">): string {
  return r.examples.map((e) => `${e.from}→${e.to} ${hhmm(e.gap_min)}`).join(", ") + (r.more ? " …" : "");
}

const NUMBER_WORDS = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"];

/** How many of our airlines the connections cover, in words ("all six airlines"), from the input's airlines. */
export function airlinesWords(rules: Rules): string {
  const n = [...rules.airlines.values()].filter((a) => a.ours).length;
  return `all ${NUMBER_WORDS[n] ?? String(n)} airlines`;
}

/** The connections board's note. */
export function connectionsNote(rules: Rules, t: HubConnections): string {
  return `flights that are flying now, ${airlinesWords(rules)} · connection time from the airport's MCT up to ${t.max_wait_h} h · ${t.pairs.length} city pairs linked`;
}
