// Reference → Data's exports (design §14, choice 2: import and clear go, export stays): the planner's tables as JSON, and
// the flights as CSV, one line per leg with the old planner's columns (flightsCsv): flight number, airline, from, to, the
// days and local times at the hub, the day it lands, the block, the aircraft, its type and layout, seats, service, price,
// the typed loads and the bank, and since 21 Oct the layout its route calls for (Layout: the route's own cabin choice,
// else its market's layout; spec docs/specs/2026-10-21-cabins-new-rule.md §2). A new frequency's price is the airline's
// launch fare (the market's fare until 21 Oct). Both are read fresh when asked, and handed to the browser as a file to
// save.
import type { Rules } from "@rules";
import { supabase } from "../../data/supabase";
import { PLANNER_TABLES } from "../../data/save";
import {
  LEG_COLUMNS, MARKET_ROW_COLUMNS, ROTATION_COLUMNS, ROUTE_COLUMNS, freqOf, hhmm as dur, priceFor, routeOf, serviceFor,
  type AircraftRow, type LegRow, type MarketRow, type RotationRow, type RouteRow,
} from "../routes/model";
import { CSV_HEAD, csvBanks, csvLine } from "./model";

const fail = (what: string, message: string): never => {
  throw new Error(`Couldn't read ${what}: ${message}`);
};
async function all<T>(what: string, table: string, cols: string, worldId: number, extra?: (q: never) => unknown): Promise<T[]> {
  const out: T[] = [];
  for (let from = 0; ; from += 1000) {
    let q = supabase.from(table as never).select(cols).eq("world_id", worldId).order("id" as never).range(from, from + 999) as unknown;
    if (extra) q = extra(q as never);
    const { data, error } = await (q as PromiseLike<{ data: T[] | null; error: { message: string } | null }>);
    if (error) return fail(what, error.message);
    out.push(...(data ?? []));
    if ((data ?? []).length < 1000) return out;
  }
}

const H = (m: number | null | undefined) => (m == null ? "" : `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`);

/** The flights as the old Export flights (CSV) gave them: each rotation's outbound, then its return. */
export async function flightsCsv(rules: Rules, worldId: number, names: ReadonlyMap<number, string>): Promise<string> {
  const [rotations, legs, aircraft, markets, configs, profiles] = await Promise.all([
    all<RotationRow>("the frequencies", "rotations", ROTATION_COLUMNS, worldId),
    all<LegRow>("the flights", "flight_legs", LEG_COLUMNS, worldId),
    all<AircraftRow & { cabin_config_id: number | null }>("the aircraft", "aircraft", "id, registration, airline_id, aircraft_type_id, cabin_config_id, status, schedule_changed_on, updated_at", worldId),
    all<MarketRow>("the markets", "markets", MARKET_ROW_COLUMNS, worldId),
    all<{ id: number; code: string; seats: number | null }>("the cabin layouts", "cabin_configs", "id, code, seats", worldId),
    all<{ id: number; code: string; airline_id: number | null; up_to_km: number | null }>("the service profiles", "service_profiles", "id, code, airline_id, up_to_km", worldId),
  ]);
  const routeIds = [...new Set(rotations.map((r) => r.route_id))];
  const routes: RouteRow[] = [];
  for (let i = 0; i < routeIds.length; i += 300) {
    const { data, error } = await supabase.from("routes").select(ROUTE_COLUMNS).in("id", routeIds.slice(i, i + 300));
    if (error) return fail("the routes", error.message);
    routes.push(...(data as unknown as RouteRow[]));
  }
  const mk = new Map(markets.map((m) => [m.id, m]));
  const byRoute = new Map(routes.map((r) => [r.id, routeOf(r, mk)]));
  const ac = new Map(aircraft.map((a) => [a.id, a]));
  const cfg = new Map(configs.map((c) => [c.id, c]));
  const lines = [csvLine(CSV_HEAD)];
  for (const rot of rotations) {
    const route = byRoute.get(rot.route_id);
    if (!route) continue;
    const f = freqOf(rules, route, rot, legs, ac);
    const a = f.aircraft as (AircraftRow & { cabin_config_id: number | null }) | undefined;
    const typeId = f.ends.type_id;
    const type = typeId == null ? undefined : rules.types.get(typeId);
    const config = a?.cabin_config_id == null ? undefined : cfg.get(a.cabin_config_id);
    const seats = config ? config.seats : type ? type.seats_max ?? null : null;
    const service = rot.service_code || serviceFor(profiles.map((p) => ({ ...p, up_to_km: p.up_to_km })), route);
    const price = (rot.fare_pct != null && Number(rot.fare_pct)) || priceFor(rules, route);
    const extra = rot.extra && typeof rot.extra === "object" && !Array.isArray(rot.extra) ? rot.extra : {};
    const days = f.local.days.join("");
    const name = names.get(route.airline_id) ?? "";
    const reg = a?.registration ?? "";
    const common = [reg, type?.name ?? "", config?.code ?? "", seats, service, price] as const;
    const out = f.view.out, back = f.view.back;
    const [waveOut, waveBack] = csvBanks(f.wave);
    // the layout the route calls for (since 21 Oct): its own cabin choice, else its market's
    const layout = route.row.cabin_choice || route.layout;
    if (out) lines.push(csvLine([f.noOut, name, route.hub, route.dest, days, H(out.dep), H(out.arr), out.arr_day, dur(out.block), ...common,
      String(extra.slfOut ?? ""), waveOut, layout]));
    if (back) lines.push(csvLine([f.noBack, name, route.dest, route.hub, days, H(back.dep), H(back.arr), back.arr_day, dur(back.block), ...common,
      String(extra.slfBack ?? ""), waveBack, layout]));
  }
  return lines.join("\n");
}

/** Every planner table's rows for the world (the 33 planner_save() writes; the shared ones whole), as one JSON document. */
export async function tablesJson(worldId: number): Promise<string> {
  const out: Record<string, unknown[]> = {};
  for (const t of PLANNER_TABLES) {
    const shared = t === "countries" || t === "airports";
    const rows: unknown[] = [];
    for (let from = 0; ; from += 1000) {
      let q = supabase.from(t).select("*").range(from, from + 999);
      if (!shared) q = t === "worlds" ? q.eq("id" as never, worldId as never) : q.eq("world_id" as never, worldId as never);
      const { data, error } = await q;
      if (error) return fail(t, error.message);
      rows.push(...(data ?? []));
      if ((data ?? []).length < 1000) break;
    }
    out[t] = rows;
  }
  return JSON.stringify({ world_id: worldId, exported_at: new Date().toISOString(), tables: out }, null, 1);
}

/** Hands a text to the browser as a file to save. */
export function download(text: string, filename: string, type: string) {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
