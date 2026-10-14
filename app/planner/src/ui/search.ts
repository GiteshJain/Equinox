// The header's search (the old planner's searchAll; spec docs/specs/2026-10-14-interline-photos-reference.md, part 2):
// flights, aircraft, airports and routes, as the old one found them, with each result opening its new screen. Plain data
// in, plain data out, so the unit tests can run it.
//   - a flight number, with or without the airline's code in front ("1008", "KF 1008", "KF1008"): every flight of ours
//     whose number starts with it (each rotation's outbound and return), and every planned flight on a plan card of an
//     aircraft not yet in service;
//   - a registration (any part of it, dashes ignored): the aircraft in service, and those on order;
//   - two airport codes ("DEL BOM", "DEL-BOM"): the routes between them, either way, first;
//   - an airport code, or the start of a city's name (three letters or more): each airline's routes there.
// At most 14 results; a query shorter than two letters finds nothing.
import { niceDate } from "./dates";

export interface SearchData {
  airlines: readonly { id: number; name: string; code: string | null }[];
  /** Each rotation (in id order) with its route's ends and its two flight numbers as the old planner showed them. */
  freqs: readonly { airline_id: number; hub: string; dest: string; noOut: number | null; noBack: number | null }[];
  /** The aircraft in service, in the old planner's list order, with their type's name. */
  tails: readonly { registration: string; airline_id: number; type: string }[];
  /** The aircraft on order (in the old list of deliveries, not in service), with the plan noted and its card's flights. */
  deliveries: readonly { registration: string; airline_id: number; plan: string; delivery_at: string | null; legs: readonly { no: number | string | null; from: string; to: string }[] | null }[];
  /** Every route that isn't removed, in the planner's order. */
  routes: readonly { airline_id: number; hub: string; dest: string }[];
  /** Each airport's city as the route research gives it. */
  cities: ReadonlyMap<string, string | null>;
}
export type HitKind = "Flight" | "Aircraft" | "On order" | "Planned" | "Route" | "Airport";
export interface Hit { kind: HitKind; label: string; to: string }

/** The airline's part of a flight's words, as the old planner shortened it: its first word ("Pan" for Pan American). */
const first = (name: string) => name.split(" ")[0] ?? name;
const enc = encodeURIComponent;

export function searchAll(query: string, d: SearchData): Hit[] {
  const q = query.trim().toUpperCase();
  if (q.length < 2) return [];
  const res: Hit[] = [];
  const al = new Map(d.airlines.map((a) => [a.id, a]));
  const name = (id: number) => al.get(id)?.name ?? "";
  const code = (id: number) => al.get(id)?.code ?? "";
  // an airline's code in front of a number is left out ("KF 1008" finds 1008)
  const num = q.replace(/^[A-Z]{2}\s*/, "");
  const digits = /^\d{1,4}$/.test(num);
  if (digits) {
    for (const f of d.freqs) {
      for (const [no, a, b] of [[f.noOut, f.hub, f.dest], [f.noBack, f.dest, f.hub]] as const) {
        if (no && String(no).startsWith(num)) {
          res.push({ kind: "Flight", label: `${first(name(f.airline_id))} ${no} · ${a}–${b}`, to: `/routes/${enc(code(f.airline_id))}/${enc(f.hub + "-" + f.dest)}` });
        }
      }
    }
  }
  const bare = q.replace("-", "");
  for (const t of d.tails) {
    if (t.registration.toUpperCase().replace("-", "").includes(bare)) {
      res.push({ kind: "Aircraft", label: `${t.registration} · ${name(t.airline_id)} · ${t.type}`, to: `/tails/${enc(t.registration)}` });
    }
  }
  const filed = new Set(d.tails.map((t) => t.registration));
  for (const x of d.deliveries) {
    if (filed.has(x.registration)) continue;
    const card = `/tails?airline=${enc(code(x.airline_id))}&card=${enc(x.registration)}`;
    if (x.registration.toUpperCase().replace("-", "").includes(bare)) {
      const at = String(x.delivery_at ?? "");
      res.push({ kind: "On order", label: `${x.registration} · ${name(x.airline_id)} · ${x.plan} · ${niceDate(at.slice(0, 10))} ${at.slice(11, 16)} UTC`, to: card });
    }
    if (x.legs && digits) {
      for (const L of x.legs) {
        if (String(L.no).startsWith(num)) res.push({ kind: "Planned", label: `${first(name(x.airline_id))} ${L.no} · ${L.from}–${L.to} · ${x.registration}`, to: card });
      }
    }
  }
  const flying = new Set(d.freqs.map((f) => `${f.airline_id}|${f.hub}|${f.dest}`));
  const pair = /^([A-Z]{3})[\s\-–]*([A-Z]{3})$/.exec(q);
  if (pair) {
    const [, a, b] = pair;
    for (const r of d.routes) {
      if ((r.hub === a && r.dest === b) || (r.hub === b && r.dest === a)) {
        res.unshift({ kind: "Route", label: `${r.hub}–${r.dest} · ${name(r.airline_id)}${flying.has(`${r.airline_id}|${r.hub}|${r.dest}`) ? " · flying" : ""}`,
          to: `/routes/${enc(code(r.airline_id))}/${enc(r.hub + "-" + r.dest)}` });
      }
    }
  }
  if (/^[A-Z]{3}$/.test(q) || q.length >= 3) {
    const seen = new Set<string>();
    let counts: Map<string, number> | null = null;
    for (const r of d.routes) {
      for (const ap of [r.hub, r.dest]) {
        const city = d.cities.get(ap) ?? "";
        if ((ap === q || (q.length >= 3 && city.toUpperCase().startsWith(q))) && !seen.has(ap + "|" + r.airline_id)) {
          seen.add(ap + "|" + r.airline_id);
          if (!counts) {
            counts = new Map();
            for (const x of d.routes) for (const c of new Set([x.hub, x.dest])) counts.set(c + "|" + x.airline_id, (counts.get(c + "|" + x.airline_id) ?? 0) + 1);
          }
          const n = counts.get(ap + "|" + r.airline_id) ?? 0;
          res.push({ kind: "Airport", label: `${ap} ${city} · ${name(r.airline_id)} · ${n} route${n === 1 ? "" : "s"}`, to: `/routes?airline=${enc(code(r.airline_id))}&q=${enc(ap)}` });
        }
      }
    }
  }
  return res.slice(0, 14);
}
