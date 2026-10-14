// The header's search box (the old planner's #gsearch and renderSearch): flights, aircraft, airports and routes as you type,
// "/" to jump to it, Enter for the first result, Escape to close; a result opens its new screen. What it searches is read
// the first time the box is used: the start's rules input (flights, the airlines), the aircraft and plan cards, and every
// route with the airports' cities (read a thousand at a time). The finding is search.ts's.
import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useNavigate } from "react-router";
import { useOurAirlines, useWorld } from "../data/reads";
import { useRules } from "../data/rules";
import { supabase } from "../data/supabase";
import type { Json } from "../db/types";
import { searchAll, type Hit, type SearchData } from "./search";

type Page<T> = PromiseLike<{ data: T[] | null; error: { message: string } | null }>;
async function every<T>(what: string, page: (from: number, to: number) => Page<T>): Promise<T[]> {
  const out: T[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await page(from, from + 999);
    if (error) throw new Error(`Couldn't read ${what}: ${error.message}`);
    out.push(...(data ?? []));
    if ((data ?? []).length < 1000) return out;
  }
}
const idx = (extra: Json | null | undefined, k: string): number | null => {
  const v = extra && typeof extra === "object" && !Array.isArray(extra) ? extra[k] : null;
  return typeof v === "number" ? v : v == null ? null : Number(v);
};

/** What the search looks through that the start's rules don't carry, read once the box is used. */
function useSearchTables(worldId: number | undefined, enabled: boolean) {
  return useQuery({
    queryKey: ["table", "routes", "search", worldId],
    enabled: enabled && worldId !== undefined,
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const w = worldId ?? 0;
      const [routes, cities, aircraft, cards, legs] = await Promise.all([
        every<{ airline_id: number; hub_code: string; dest_code: string }>("the routes", (a, b) => supabase.from("routes").select("airline_id, hub_code, dest_code")
          .eq("world_id", w).eq("removed", false).order("id").range(a, b)),
        every<{ code: string; city: string | null }>("the airports", (a, b) => supabase.from("airports").select("code, city").order("code").range(a, b)),
        every<{ id: number; registration: string; airline_id: number; aircraft_type_id: number | null; delivery_at: string | null; order_note: string | null; extra: Json }>(
          "the aircraft", (a, b) => supabase.from("aircraft").select("id, registration, airline_id, aircraft_type_id, delivery_at, order_note, extra").eq("world_id", w).order("id").range(a, b)),
        every<{ id: number; aircraft_id: number; extra: Json }>("the plan cards", (a, b) => supabase.from("plan_cards").select("id, aircraft_id, extra").eq("world_id", w).order("id").range(a, b)),
        every<{ plan_card_id: number; position: number; flight_no: number | null; origin_code: string | null; dest_code: string | null }>("the plan cards' flights",
          (a, b) => supabase.from("plan_card_legs").select("plan_card_id, position, flight_no, origin_code, dest_code").eq("world_id", w).order("plan_card_id").order("position").range(a, b)),
      ]);
      return { routes, cities, aircraft, cards, legs };
    },
  });
}

export function Search() {
  const navigate = useNavigate();
  const box = useRef<HTMLInputElement>(null);
  const [q, setQ] = useState("");
  const [used, setUsed] = useState(false);
  const [shown, setShown] = useState(false);
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const rulesQ = useRules(w);
  const tablesQ = useSearchTables(w, used);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tag = (document.activeElement?.tagName ?? "").toUpperCase();
      if (e.key === "/" && tag !== "INPUT" && tag !== "TEXTAREA" && tag !== "SELECT") {
        e.preventDefault();
        box.current?.focus();
      }
      if (e.key === "Escape") setShown(false);
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, []);

  const data: SearchData | null = useMemo(() => {
    const rules = rulesQ.data?.rules, t = tablesQ.data;
    if (!rules || !t || !airlinesQ.data) return null;
    const airlines = airlinesQ.data.map((a) => ({ id: a.id, name: a.planner_name ?? a.public_name ?? a.game_name ?? "", code: a.iata_code }));
    const byRot = new Map<number, { l1?: number | null; l2?: number | null }>();
    for (const l of rules.legs) {
      if (l.rotation_id == null) continue;
      const x = byRot.get(l.rotation_id) ?? {};
      if ((l.leg_no ?? 1) === 1) x.l1 ??= l.flight_no; else x.l2 ??= l.flight_no;
      byRot.set(l.rotation_id, x);
    }
    const freqs = [...rules.rotations.values()].sort((a, b) => a.id - b.id).flatMap((r) => {
      const route = rules.routes.get(r.route_id);
      if (!route) return [];
      const x = byRot.get(r.id) ?? {};
      const out = x.l1 ?? null;
      return [{ airline_id: route.airline_id, hub: route.hub_code, dest: route.dest_code, noOut: out, noBack: x.l2 ?? (out ? out - 1 : null) }];
    });
    const typeName = (id: number | null) => (id == null ? "" : rules.types.get(id)?.name ?? "");
    const tails = t.aircraft.filter((a) => idx(a.extra, "tails_index") != null).sort((a, b) => (idx(a.extra, "tails_index") ?? 0) - (idx(b.extra, "tails_index") ?? 0) || a.id - b.id)
      .map((a) => ({ registration: a.registration, airline_id: a.airline_id, type: typeName(a.aircraft_type_id) }));
    const cardOf = new Map(t.cards.map((c) => [c.aircraft_id, c]));
    const deliveries = t.aircraft.filter((a) => idx(a.extra, "deliveries_index") != null)
      .sort((a, b) => (idx(a.extra, "deliveries_index") ?? 0) - (idx(b.extra, "deliveries_index") ?? 0) || a.id - b.id)
      .map((a) => {
        const c = cardOf.get(a.id);
        const kept = c?.extra && typeof c.extra === "object" && !Array.isArray(c.extra) ? c.extra.legs : null;
        const legs = !c ? null : Array.isArray(kept)
          ? kept.map((l) => (l && typeof l === "object" && !Array.isArray(l) ? { no: (l.no ?? null) as number | string | null, from: String(l.from ?? ""), to: String(l.to ?? "") } : { no: null, from: "", to: "" }))
          : t.legs.filter((l) => l.plan_card_id === c.id).map((l) => ({ no: l.flight_no, from: l.origin_code ?? "", to: l.dest_code ?? "" }));
        const delivery_at = a.delivery_at ? new Date(a.delivery_at).toISOString().slice(0, 16) + "Z" : null;
        return { registration: a.registration, airline_id: a.airline_id, plan: a.order_note ?? "", delivery_at, legs };
      });
    return {
      airlines, freqs, tails, deliveries, routes: t.routes.map((r) => ({ airline_id: r.airline_id, hub: r.hub_code, dest: r.dest_code })),
      cities: new Map(t.cities.map((c) => [c.code, c.city])),
    };
  }, [rulesQ.data, tablesQ.data, airlinesQ.data]);
  const hits: Hit[] = useMemo(() => (data ? searchAll(q, data) : []), [q, data]);
  const go = (h: Hit) => {
    setQ("");
    setShown(false);
    navigate(h.to);
  };
  const open = shown && q.trim().length >= 2;
  return (
    <div className="gs" data-search-ready={data ? "yes" : used ? "loading" : "no"}>
      <input id="gsearch" ref={box} placeholder="Search flights, aircraft, airports  /" autoComplete="off" value={q} aria-label="Search flights, aircraft, airports"
        onFocus={() => { setUsed(true); setShown(true); }}
        onChange={(e) => { setQ(e.currentTarget.value); setShown(true); }}
        onKeyDown={(e) => { if (e.key === "Enter" && hits[0]) go(hits[0]); }} />
      <div id="gsr" style={{ display: open ? "block" : "none" }}>
        {open && !data ? <div className="gse">Searching…</div>
          : hits.length ? hits.map((h, i) => <button type="button" className="gsi" data-gsi={i} key={i} onMouseDown={(e) => e.preventDefault()} onClick={() => go(h)}><span className="gsk">{h.kind}</span>{h.label}</button>)
          : open ? <div className="gse">Nothing found</div> : null}
      </div>
    </div>
  );
}
