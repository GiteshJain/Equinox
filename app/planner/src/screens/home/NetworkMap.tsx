// "The network right now" on Home: the old planner's 2D map (networkMap), ported. Every flying route as a great-circle
// line in its airline's colour (wider the more round trips a day), our bases (hubs larger, focus cities smaller, grey
// until a route flies from them) and the airports the routes reach, with night shaded as it is at this minute. The
// airline buttons show one airline (centring on its busiest base) with its routes coloured by economy load over 7 days
// (route_loads(): 95%+ green, 85 amber, 70 orange, under that red, grey without loads). + and − zoom, ⟲ shows the whole
// world, the wheel zooms where it points, and a zoomed map drags. Planned adds, dashed, the routes on the plan cards of
// aircraft not yet in service. Hovering a line or a dot names it. A route opens on its line in Routes; a planned route
// opens its aircraft in "Aircraft on order" (the old map's pop-ups belong to those screens).
import { useEffect, useMemo, useRef, useState, type CSSProperties, type MouseEvent as RMouseEvent, type PointerEvent as RPointerEvent, type ReactElement } from "react";
import { useNavigate } from "react-router";
import { summary, type Rules } from "@rules";
import { AirlineMark } from "../../ui/AirlineMark";
import { loadWorld } from "../../ui/siteFiles";
import { itemRoute } from "../screens";
import type { HomeAirline } from "./attention";
import {
  MAPH, MAPW, arcWidth, clampView, focusView, gcPath, loadColor, mapPoint, nightPolygon, perDayWords, toMap, zoomView, type LatLon, type MapView,
} from "./map";
import { usePlannedLegs, useRouteLoads, type AircraftRow } from "./reads";

interface Place { code: string; at: LatLon; name: string }

export function NetworkMap({ rules, airlines, now, worldId, aircraft }: {
  rules: Rules | undefined; airlines: readonly HomeAirline[]; now: Date; worldId: number | undefined; aircraft: readonly AircraftRow[] | undefined;
}) {
  const navigate = useNavigate();
  const [only, setOnly] = useState<number | null>(null);
  const [view, setView] = useState<MapView | null>(null);
  const [planned, setPlanned] = useState(false);
  const [world, setWorld] = useState<string | null>(null);
  const loadsQ = useRouteLoads(worldId, only != null);
  const plannedQ = usePlannedLegs(worldId, planned);
  const svgRef = useRef<SVGSVGElement>(null), wrapRef = useRef<HTMLDivElement>(null), tipRef = useRef<HTMLDivElement>(null);
  const viewRef = useRef(view);   // the view for the wheel's listener, which is set up once
  useEffect(() => { viewRef.current = view; }, [view]);

  useEffect(() => {
    let alive = true;
    loadWorld().then((w) => { if (alive) setWorld(w); }).catch(() => { if (alive) setWorld(""); });
    return () => { alive = false; };
  }, []);

  const nameOf = (id: number) => airlines.find((a) => a.id === id)?.name ?? "";
  const colorOf = (id: number) => airlines.find((a) => a.id === id)?.color || "#8B96A8";

  // airports: the rules' (flown routes, legs, bases), and for planned routes the ones their legs use
  const places = useMemo(() => {
    const m = new Map<string, Place>();
    for (const a of rules?.airports.values() ?? []) if (a.lat != null && a.lon != null) m.set(a.code, { code: a.code, at: [Number(a.lat), Number(a.lon)], name: a.city ?? "" });
    for (const a of plannedQ.data?.airports ?? []) if (!m.has(a.code) && a.lat != null && a.lon != null) m.set(a.code, { code: a.code, at: [a.lat, a.lon], name: a.city ?? "" });
    return m;
  }, [rules, plannedQ.data]);

  // each flying route once, in the order of its first rotation, with its round trips a day
  const flying = useMemo(() => {
    if (!rules) return [];
    const trips = new Map(summary.roundTrips(rules).map((t) => [t.route_id, t.round_trips_week]));
    const seen = new Set<number>(), out: { id: number; airline_id: number; hub: string; dest: string; perDay: number }[] = [];
    for (const r of rules.rotations.values()) {
      const route = rules.routes.get(r.route_id);
      if (!route || seen.has(route.id)) continue;
      seen.add(route.id);
      out.push({ id: route.id, airline_id: route.airline_id, hub: route.hub_code, dest: route.dest_code, perDay: (trips.get(route.id) ?? 0) / 7 });
    }
    return out;
  }, [rules]);

  const loads = useMemo(() => (only != null && loadsQ.data ? new Map(loadsQ.data.map((l) => [l.route_id, l])) : null), [only, loadsQ.data]);

  const pick = (id: number | null) => {
    setOnly(id);
    if (id == null || !rules) return setView(null);
    // the airline's busiest base by round trips a week, else its first base
    const deps = new Map<string, number>(), pts: LatLon[] = [];
    for (const r of flying) {
      if (r.airline_id !== id) continue;
      deps.set(r.hub, (deps.get(r.hub) ?? 0) + (r.perDay * 7 || 1));
      for (const c of [r.hub, r.dest]) { const p = places.get(c); if (p) pts.push(p.at); }
    }
    const hub = [...deps.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? rules.bases.find((b) => b.airline_id === id)?.airport_code;
    setView(focusView(hub ? places.get(hub)?.at : undefined, pts));
  };

  // the wheel zooms where it points (a listener that may stop the page scrolling)
  useEffect(() => {
    const s = svgRef.current;
    if (!s) return;
    const wheel = (e: WheelEvent) => {
      e.preventDefault();
      const [px, py] = mapPoint(s.getBoundingClientRect(), viewRef.current, e.clientX, e.clientY);
      setView((v) => zoomView(v, e.deltaY < 0 ? 1.25 : 1 / 1.25, px, py));
    };
    s.addEventListener("wheel", wheel, { passive: false });
    return () => s.removeEventListener("wheel", wheel);
  }, [world]);

  // a press turns into a drag once the pointer moves 5 px, so a click still reaches the route under it
  const drag = useRef<{ x: number; y: number; v: MapView; r: DOMRect; live: boolean; id: number } | null>(null);
  const down = (e: RPointerEvent<SVGSVGElement>) => {
    if (!view || !svgRef.current) return;
    drag.current = { x: e.clientX, y: e.clientY, v: view, r: svgRef.current.getBoundingClientRect(), live: false, id: e.pointerId };
  };
  const moveDrag = (e: RPointerEvent<SVGSVGElement>) => {
    const d = drag.current;
    if (!d) return;
    if (!d.live) {
      if (Math.hypot(e.clientX - d.x, e.clientY - d.y) < 5) return;
      d.live = true;
      try { svgRef.current?.setPointerCapture(d.id); } catch { /* the pointer may be gone */ }
    }
    setView(clampView({ x: d.v.x - (e.clientX - d.x) / d.r.width * d.v.w, y: d.v.y - (e.clientY - d.y) / d.r.height * d.v.h, w: d.v.w, h: d.v.h }));
  };
  const upDrag = () => { setTimeout(() => { drag.current = null; }, 0); };

  // the tip follows the pointer over anything with a data-tip
  const tip = (e: RMouseEvent<HTMLDivElement>) => {
    const t = tipRef.current, wrap = wrapRef.current;
    if (!t || !wrap) return;
    const el = (e.target as Element).closest?.("[data-tip]") as HTMLElement | SVGElement | null;
    if (!el || drag.current?.live) { t.style.display = "none"; return; }
    const r = wrap.getBoundingClientRect();
    t.textContent = el.getAttribute("data-tip");
    t.style.display = "block";
    const x = e.clientX - r.left, y = e.clientY - r.top;
    t.style.left = Math.min(x + 14, r.width - t.offsetWidth - 6) + "px";
    t.style.top = (y + 16 + t.offsetHeight > r.height ? y - t.offsetHeight - 10 : y + 16) + "px";
  };
  const click = (e: RMouseEvent) => {
    if (drag.current?.live) return;
    const el = (e.target as Element).closest?.("[data-route-id], [data-reg]");
    if (!el) return;
    const reg = el.getAttribute("data-reg");
    if (reg) {
      const row = document.querySelector(`[data-oo-row="${CSS.escape(reg)}"]`);
      const det = row?.closest("details");
      if (det) det.open = true;
      row?.scrollIntoView({ block: "center", behavior: "smooth" });
      return;
    }
    const r = flying.find((x) => String(x.id) === el.getAttribute("data-route-id"));
    if (r) navigate(itemRoute("routes", { airline: airlines.find((a) => a.id === r.airline_id)?.code, hub: r.hub, dest: r.dest }));
  };

  const v = view ?? { x: 0, y: 0, w: MAPW, h: MAPH };
  const k = (v.w / MAPW).toFixed(3), kk = Number(k);
  const shown = flying.filter((r) => only == null || r.airline_id === only);
  const aps = new Map<string, number>();
  const arcs: ReactElement[] = [], hits: ReactElement[] = [];
  for (const r of shown) {
    const a = places.get(r.hub), b = places.get(r.dest);
    if (!a || !b) continue;
    const d = gcPath(a.at, b.at), la = loads?.get(r.id);
    arcs.push(<path key={r.id} d={d} stroke={loads ? loadColor(la?.average) : colorOf(r.airline_id)} strokeWidth={arcWidth(r.perDay)} vectorEffect="non-scaling-stroke" data-arc={`${r.hub}-${r.dest}`} />);
    hits.push(<path key={r.id} className="hit" d={d} data-route-id={r.id}
      data-tip={`${r.hub}–${r.dest} · ${nameOf(r.airline_id)} · ${perDayWords(r.perDay)}× a day${la ? ` · loads ≈${Math.round(la.average)}% over ${la.days} days` : ""} · open in Routes`} />);
    for (const c of [r.hub, r.dest]) aps.set(c, (aps.get(c) ?? 0) + 1);
  }
  // planned: the plan cards of aircraft not in service yet, a route only where none flies
  const parcs: ReactElement[] = [];
  if (planned && plannedQ.data && aircraft) {
    const unfiled = new Map(aircraft.filter((a) => a.status !== "active").map((a) => [a.id, a]));
    const flownPairs = new Set(shown.map((r) => [r.hub, r.dest].sort().join("-")));
    const pseen = new Set<string>();
    for (const l of plannedQ.data.legs) {
      const ac = unfiled.get(l.aircraft_id);
      if (!ac || (only != null && ac.airline_id !== only)) continue;
      const key = [l.origin_code, l.dest_code].sort().join("-");
      if (pseen.has(key)) continue;
      pseen.add(key);
      if (flownPairs.has(key)) continue;
      const a = places.get(l.origin_code), b = places.get(l.dest_code);
      if (!a || !b) continue;
      const d = gcPath(a.at, b.at);
      parcs.push(<path key={key} d={d} stroke={colorOf(ac.airline_id)} vectorEffect="non-scaling-stroke" />);
      hits.push(<path key={"p" + key} className="hit" d={d} data-reg={ac.registration}
        data-tip={`${l.origin_code}–${l.dest_code} · ${nameOf(ac.airline_id)} · planned for ${ac.registration} · see it in Aircraft on order`} />);
      for (const c of [l.origin_code, l.dest_code]) if (!aps.has(c)) aps.set(c, 0);
    }
  }
  const baseCodes = new Set((rules?.bases ?? []).map((b) => b.airport_code));
  const dots: ReactElement[] = [];
  for (const h of rules?.bases ?? []) {
    const c = places.get(h.airport_code);
    if (!c) continue;
    const live = aps.has(h.airport_code);
    if (only != null && h.airline_id !== only && !live) continue;
    const [x, y] = toMap(c.at), fcm = h.role === "focus";
    dots.push(
      <g key={"h" + h.id} className={`hub ${live ? "live" : ""} ${fcm ? "focus" : ""}`} data-hub={h.airport_code}>
        <circle cx={x.toFixed(1)} cy={y.toFixed(1)} r={fcm ? (live ? 3 : 2.2) : (live ? 4.5 : 3)} fill={live ? colorOf(h.airline_id) : "#B7C4D8"} />
        <circle className="hitc" cx={x.toFixed(1)} cy={y.toFixed(1)} r="7"
          data-tip={`${h.airport_code} · ${c.name} · ${nameOf(h.airline_id)} ${fcm ? "focus city" : "hub"}${live ? " · " + (aps.get(h.airport_code) ?? 0) + " routes" : " · not flying yet"}`} />
        <text x={x.toFixed(1)} y={y.toFixed(1)} dx="0.72em" dy="0.36em">{h.airport_code}</text>
      </g>,
    );
  }
  const labelDest = only != null && kk < 0.6;
  for (const [code, nr] of aps) {
    if (baseCodes.has(code)) continue;
    const c = places.get(code);
    if (!c) continue;
    const [x, y] = toMap(c.at);
    dots.push(
      <g key={"a" + code} data-ap={code}>
        <circle className={`ap ${only != null ? "on" : ""} ${nr ? "" : "pl"} ${nr >= 3 ? "big" : ""}`} cx={x.toFixed(1)} cy={y.toFixed(1)} r="2" />
        <circle className="hitc" cx={x.toFixed(1)} cy={y.toFixed(1)} r="6"
          data-tip={`${code} · ${c.name} · ${nr ? nr + " route" + (nr === 1 ? "" : "s") + " flying" : "planned only"}`} />
        {labelDest ? <text className="al" x={(x + 4.5 * kk).toFixed(1)} y={(y + 3 * kk).toFixed(1)}>{code}</text> : null}
      </g>,
    );
  }

  const onlyName = only == null ? "" : nameOf(only);
  const loadsState = only == null ? "none" : loadsQ.data ? "ready" : loadsQ.error ? "failed" : "loading";
  return (
    <section className="board mapb" aria-label="The network right now" data-board="network" data-map-airline={onlyName} data-map-loads={loadsState}>
      <div className="maph">
        <h3 className="rh">The network right now <span className="note" data-network-note>
          {onlyName ? onlyName + " · " : ""}{shown.length} routes · day and night as of {now.toISOString().slice(11, 16)}Z
        </span></h3>
        <div className="mleg">
          <button type="button" className={"mf" + (only == null ? " on" : "")} onClick={() => pick(null)}>All</button>
          {airlines.map((a) => (
            <button type="button" key={a.id} className={"mf" + (only === a.id ? " on" : "")} title={a.name} onClick={() => pick(a.id)}>
              <AirlineMark color={a.color} />{a.name}
            </button>
          ))}
        </div>
      </div>
      <div className="mapwrap" ref={wrapRef} onMouseMove={tip} onMouseLeave={() => { if (tipRef.current) tipRef.current.style.display = "none"; }}>
        <div className="mapz">
          <button type="button" title="Zoom in" onClick={() => setView((x) => zoomView(x, 1.6))}>+</button>
          <button type="button" title="Zoom out" onClick={() => setView((x) => zoomView(x, 1 / 1.6))}>−</button>
          <button type="button" title="Whole world" onClick={() => setView(null)}>⟲</button>
        </div>
        <div className="mapopt">
          <button type="button" className={planned ? "on" : ""} title="Show routes planned for aircraft on order" onClick={() => setPlanned((p) => !p)}>Planned</button>
        </div>
        {only != null ? (
          <div className="mapkey">
            <span className="dim">loads, 7 days:</span><span><i style={{ background: "#3FB37F" }} />95%+</span><span><i style={{ background: "#E0B341" }} />85–95</span>
            <span><i style={{ background: "#E8853A" }} />70–85</span><span><i style={{ background: "#E0524B" }} />under 70</span><span><i style={{ background: "#7E8BA3" }} />no data</span>
          </div>
        ) : null}
        <svg ref={svgRef} className="wmap" viewBox={`${v.x.toFixed(1)} ${v.y.toFixed(1)} ${v.w.toFixed(1)} ${v.h.toFixed(1)}`} style={{ "--k": k } as CSSProperties}
          preserveAspectRatio="xMidYMid meet" aria-label="Network map with day and night" data-map={world == null ? "loading" : "ready"}
          onPointerDown={down} onPointerMove={moveDrag} onPointerUp={upDrag} onPointerCancel={upDrag} onClick={click}>
          <defs><filter id="soft" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur stdDeviation="6" /></filter></defs>
          <rect width={MAPW} height={MAPH} className="sea" />{world ? <path d={world} className="land" /> : null}
          <polygon points={nightPolygon(now)} className="night" filter="url(#soft)" />
          <g className="parcs" fill="none" strokeWidth="1" strokeDasharray="3 3" strokeLinecap="round">{parcs}</g>
          <g className="arcs" fill="none" strokeLinecap="round">{arcs}</g><g className="hits">{hits}</g>{dots}
        </svg>
        <div className="maptip" ref={tipRef} />
      </div>
    </section>
  );
}
