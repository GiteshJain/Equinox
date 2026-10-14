// The route pop-up Home's map opens (the old planner's routeModal): the route's distance, demand, flights a day, loads
// over 7 days and its load pattern's signal over the load window, each frequency's numbers, local times as typed, days,
// aircraft and bank fit, its market and city; and Open in Routes. Its frequencies come from the planning library's
// start (rules_input(world, 'flown'), which holds every flown route's), the route itself from the table.
import { useEffect, useMemo, useRef } from "react";
import { useNavigate } from "react-router";
import type { Rules } from "@rules";
import { useWorld } from "../../data/reads";
import { AirlineMark } from "../../ui/AirlineMark";
import { shortType } from "../../ui/aircraftNames";
import { Pill, type PillKind } from "../../ui/Pill";
import { itemRoute } from "../screens";
import { fmt, freqOf, perDay, routeOf, summaryOf, type AircraftRow, type Airline, type LegRow, type RotationRow } from "./model";
import { LoadChip } from "./parts";
import { useLoads, useMarkets, usePatterns, useRouteRow } from "./reads";

const SIG: Record<string, [string, PillKind]> = { cut: ["reduce", "bad"], watch: ["watch", "warn"], add: ["add capacity", "ok"], hold: ["hold", "mute"] };

export function RoutePopup({ routeId, rules, airlines, onClose }: { routeId: number; rules: Rules; airlines: readonly Airline[]; onClose: () => void }) {
  const navigate = useNavigate();
  const w = useWorld().data?.id;
  const rowQ = useRouteRow(routeId);
  const marketsQ = useMarkets(w);
  const loadsQ = useLoads(w);
  const patternsQ = usePatterns(w);
  const close = useRef(onClose);
  useEffect(() => { close.current = onClose; });
  useEffect(() => {
    document.body.classList.add("mopen");
    const esc = (e: KeyboardEvent) => { if (e.key === "Escape") close.current(); };
    document.addEventListener("keydown", esc);
    return () => { document.body.classList.remove("mopen"); document.removeEventListener("keydown", esc); };
  }, []);

  const markets = useMemo(() => new Map((marketsQ.data ?? []).map((m) => [m.id, m])), [marketsQ.data]);
  const route = rowQ.data ? routeOf(rowQ.data, markets) : null;
  const freqs = useMemo(() => {
    if (!route) return [];
    // the route's rotations and legs as the start has them (the pop-up changes nothing, so it needs no updated_at)
    const rots: RotationRow[] = [...rules.rotations.values()].filter((x) => x.route_id === route.id)
      .map((x) => ({ id: x.id, airline_id: x.airline_id, route_id: x.route_id, legacy_key: x.legacy_key ?? null, service_code: null, fare_pct: null, launched_on: null, note: null, extra: {}, updated_at: "" }));
    const ids = new Set(rots.map((x) => x.id));
    const legs: LegRow[] = rules.legs.filter((l) => l.rotation_id != null && ids.has(l.rotation_id)).map((l) => ({
      id: l.id, airline_id: l.airline_id, rotation_id: l.rotation_id as number, leg_no: l.leg_no ?? 1, flight_no: l.flight_no, origin_code: l.origin_code,
      dest_code: l.dest_code, aircraft_id: l.aircraft_id, days_utc: l.days_utc, dep_utc_min: l.dep_utc_min, block_min: l.block_min, updated_at: "" }));
    const aircraft = new Map<number, AircraftRow>([...rules.aircraft.values()].map((a) => [a.id, {
      id: a.id, registration: a.registration, airline_id: a.airline_id, aircraft_type_id: a.aircraft_type_id, status: a.status ?? "", schedule_changed_on: null, updated_at: "" }]));
    return rots.map((x) => freqOf(rules, route, x, legs, aircraft, markets));
  }, [route, rules, markets]);
  if (!route) return null;
  const airline = airlines.find((a) => a.id === route.airline_id);
  const sm = summaryOf(freqs);
  const la = loadsQ.data?.routes.find((x) => x.route_id === route.id);
  const pat = patternsQ.data?.find((x) => x.route_id === route.id);
  const typeName = (id: number | null | undefined) => (id == null ? "" : [...rules.types.values()].find((t) => t.id === id)?.name ?? "");
  const open = () => { onClose(); navigate(itemRoute("routes", { airline: airline?.code, hub: route.hub, dest: route.dest })); };

  return (
    <div className="mback" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }} data-route-popup={`${route.hub}-${route.dest}`}
      data-popup-ready={rowQ.data && marketsQ.data && loadsQ.data && patternsQ.data ? "yes" : "no"}>
      <div className="modal" role="dialog" aria-modal="true" aria-label={`Route ${route.hub}–${route.dest}`}>
        <div className="mhead">
          <div><AirlineMark color={airline?.color} /><b>{route.hub}–{route.dest}</b> <span className="dim">· {airline?.name ?? ""}</span></div>
          <button type="button" className="mx" aria-label="Close" onClick={onClose}>×</button>
        </div>
        <div className="mbody">
          <div className="mstats" data-figure="routes: pop-up">
            <div><span className="dim">Distance</span><b>{route.dist ? route.dist.toLocaleString() + " km" : "—"}</b></div>
            <div><span className="dim">Demand</span><b className="stars">{"★".repeat(route.stars || 0)}</b></div>
            <div><span className="dim">Flights a day</span><b>{perDay(sm.rtDay)}</b></div>
            <div><span className="dim">Loads, 7 days</span><b>{la ? <LoadChip a={la} small /> : <span className="dim">no reports yet</span>}</b></div>
            <div><span className="dim">Signal, 14 days</span><b>{pat && SIG[pat.mark] ? <Pill kind={SIG[pat.mark]?.[1] ?? "mute"}>{SIG[pat.mark]?.[0]}</Pill> : <span className="dim">—</span>}</b></div>
          </div>
          {freqs.length ? (
            <div className="tblwrap">
              <table className="tbl">
                <tbody>
                  <tr><th>Out</th><th>Times</th><th>Back</th><th>Times</th><th>Days</th><th>Aircraft</th><th>Bank fit</th></tr>
                  {freqs.map((f) => {
                    const days = f.local.days.join("");
                    return (
                      <tr key={f.rot.id} data-popup-freq>
                        <td><b>{f.leg1?.flight_no ?? ""}</b> {route.hub}–{route.dest}</td>
                        <td>{fmt(f.local.dep_hub)}–{fmt(f.local.arr_dest)}</td>
                        <td><b>{f.leg2?.flight_no ?? ""}</b> {route.dest}–{route.hub}</td>
                        <td>{fmt(f.local.dep_dest)}–{fmt(f.local.arr_hub)}</td>
                        <td>{days === "1234567" ? "daily" : days}</td>
                        <td>{f.aircraft?.registration ?? ""} <span className="dim">{f.aircraft ? shortType(typeName(f.aircraft.aircraft_type_id)) : ""}</span></td>
                        <td className="dim">{f.wave.text}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          ) : <div className="dim">Not flown yet.</div>}
          <div className="note">{route.market}{route.city ? " · " + route.city : ""}</div>
        </div>
        <div className="mfoot">
          <button type="button" className="primary" onClick={open} data-open-in-routes>Open in Routes</button>
          <button type="button" className="secondary" onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  );
}
