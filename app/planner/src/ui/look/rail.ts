// The airline rail's addresses (to-do 225, decision 4, option A; spec docs/specs/2026-11-11-glass-look.md, step 1).
// On the screens that show one airline at a time the rail picks the airline: Performance (/performance/<code>, "All" its
// group page), Competition (/competition/<code>, the same), Routes (/routes/<code>) and Tails (?airline=<code>, none for
// the first airline, as Tails' own buttons do); Routes and Tails have no all-airline view, so "All" is shown there but
// not clickable. On every other screen (Home, Today, Interline, Photos, Systems, and Reference: the spec's question 1,
// settled 12 Nov as Home, since Reference shows all six airlines at once) "All" is lit and an airline opens its
// Performance page. Addresses are the router's own (without /planner).

export type RailPick = string | "all";

/** Which screen an address inside the router belongs to, as far as the rail cares. */
function kindOf(pathname: string): "performance" | "competition" | "routes" | "tails" | "other" {
  const first = pathname.split("/").filter(Boolean)[0] ?? "";
  return first === "performance" || first === "competition" || first === "routes" || first === "tails" ? first : "other";
}

function segment(pathname: string, i: number): string {
  return decodeURIComponent(pathname.split("/").filter(Boolean)[i] ?? "");
}

/** The address the rail's button goes to, or null when it does nothing there ("All" on Routes and Tails). */
export function railTarget(pathname: string, search: string, pick: RailPick, firstCode: string): string | null {
  const kind = kindOf(pathname);
  const code = pick === "all" ? null : encodeURIComponent(pick);
  if (kind === "performance" || kind === "competition") return code ? `/${kind}/${code}` : `/${kind}`;
  if (kind === "routes") {
    if (!code) return null;
    const q = new URLSearchParams(search);
    q.delete("airline");
    q.delete("aircraft");
    const s = q.toString();
    return `/routes/${code}` + (s ? "?" + s : "");
  }
  if (kind === "tails") {
    if (!code) return null;
    return pick === firstCode ? "/tails" : `/tails?airline=${code}`;
  }
  return code ? `/performance/${code}` : null;
}

/** Which button is lit: the airline the screen shows, or "all". */
export function railCurrent(pathname: string, search: string, firstCode: string): RailPick {
  const kind = kindOf(pathname);
  if (kind === "performance" || kind === "competition") return segment(pathname, 1) || "all";
  if (kind === "routes") return segment(pathname, 1) || new URLSearchParams(search).get("airline") || firstCode || "all";
  if (kind === "tails") return new URLSearchParams(search).get("airline") || firstCode || "all";
  return "all";
}

/** Whether "All" can be clicked here (not on Routes and Tails, which always show one airline). */
export function railAllWorks(pathname: string): boolean {
  const kind = kindOf(pathname);
  return kind !== "routes" && kind !== "tails";
}
