// Needs attention: the items, their kinds and how they're grouped, exactly as the old planner's Home groups them
// (web/planner/index.html: ATT_KIND, attKind, attGrouped), and the key a dismissal is kept under (dismissals.alert_key),
// the old planner's, so an item dismissed in either planner stays dismissed in both.
import type { ScreenId } from "../screens/screens";

export type AttClass = "bad" | "warn" | "ok" | "mute";

/** One item: its key (when the old planner gives it one), how serious it is, its words, and where it's fixed. */
export interface AttItem {
  key?: string;
  cls: AttClass;
  text: string;
  /** The screen where it's fixed, with the aircraft or route to open there. */
  screen: ScreenId;
  tail?: string;
  /** A route as the old planner keys it: "Pan American|JFK|ORD" (the airline's planner name, hub, destination). */
  route?: string;
}

/** The kinds, in the old planner's order, with their names on screen. */
export const ATT_KIND = {
  capture: "Capture", backup: "Backup", jobs: "Nightly jobs", todo: "To-dos", check: "One-week checks due", maint: "Maintenance",
  turn: "Turns and positions", ban: "Night bans", clash: "Flight numbers used twice", cap: "Airport departure caps", route: "Routes to fix",
  order: "Can order", monthly: "Monthly checks", interline: "Interline",
} as const;
export type AttKind = keyof typeof ATT_KIND | "other";

/** An item's kind: its key's first part, else what its words say (the old attKind). */
export function attKind(a: Pick<AttItem, "key" | "text">): AttKind {
  const k = (a.key ?? "").split("|")[0] ?? "";
  if (k in ATT_KIND) return k as AttKind;
  const t = a.text;
  return /one-week check/.test(t) ? "check" : /check due/.test(t) ? "monthly" : /short turn|wrong position/.test(t) ? "turn"
    : /night ban/.test(t) ? "ban" : /used twice/.test(t) ? "clash" : /the cap is/.test(t) ? "cap" : /nterline/.test(t) ? "interline" : "other";
}

/** The key a dismissal is kept under: the item's key, else its words (the old planner's a.key || a.text). */
export const dismissKey = (a: Pick<AttItem, "key" | "text">): string => a.key || a.text;

export const attLabel = (k: AttKind): string => (k === "other" ? "Other" : ATT_KIND[k]);

const RANK: Record<AttClass, number> = { bad: 0, warn: 1, ok: 2, mute: 3 };

export interface AttGroup {
  kind: AttKind;
  label: string;
  /** The most serious of its items. */
  cls: AttClass;
  items: AttItem[];
}

/** The items grouped by kind: kinds in the order they first appear, then (keeping that order for ties) the most serious
 * first; items in the order given. A kind with one item shows as that item alone (single). */
export function groupAttention(items: readonly AttItem[]): AttGroup[] {
  const order: AttKind[] = [];
  const by = new Map<AttKind, AttItem[]>();
  for (const a of items) {
    const k = attKind(a);
    const list = by.get(k);
    if (list) list.push(a);
    else {
      by.set(k, [a]);
      order.push(k);
    }
  }
  const worst = (k: AttKind) => Math.min(...(by.get(k) ?? []).map((a) => RANK[a.cls] ?? 3));
  return order
    .map((k, i) => ({ k, i }))
    .sort((x, y) => worst(x.k) - worst(y.k) || x.i - y.i)
    .map(({ k }) => {
      const list = by.get(k) ?? [];
      const cls = list.reduce<AttClass>((c, a) => ((RANK[a.cls] ?? 3) < (RANK[c] ?? 3) ? a.cls : c), "mute");
      return { kind: k, label: attLabel(k), cls, items: list };
    });
}

/** The items not dismissed, and how many are. */
export function withoutDismissed(items: readonly AttItem[], dismissed: ReadonlySet<string>): { shown: AttItem[]; hidden: number } {
  const shown = items.filter((a) => !dismissed.has(dismissKey(a)));
  return { shown, hidden: items.length - shown.length };
}
