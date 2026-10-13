// Aircraft types as the old planner names them on screen (web/planner/index.html: SHORT_TYPE and familyOf). Display
// names only, no rule: the types themselves and their figures come from aircraft_types.

const SHORT_TYPE: Readonly<Record<string, string>> = {
  "A320NEO LIGHT": "A320neo", "A321 NEO LIGHT": "A321neo", "E195-E2": "E195", "A321XLR": "XLR", "A350-900ULR": "A350",
};

/** "A321 NEO LIGHT" → "A321neo"; a type without a short name keeps its own. */
export function shortType(name: string | null | undefined): string {
  const n = String(name ?? "");
  return SHORT_TYPE[n.toUpperCase()] ?? n;
}

/** The family a type belongs to, as Home's Aircraft on order counts them: "A320 family", "A350", "E195". */
export function familyOf(name: string | null | undefined): string {
  const t = String(name ?? "").toUpperCase();
  return /A3(19|20|21)|XLR/.test(t) ? "A320 family" : /A350/.test(t) ? "A350" : /E19/.test(t) ? "E195" : t || "?";
}
