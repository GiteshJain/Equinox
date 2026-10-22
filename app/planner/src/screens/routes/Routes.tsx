// Routes (decision #18, build pull request 6; spec docs/specs/2026-10-13-routes.md): where flights are planned. The old
// planner's Routes, from the same data, with the same figures and look:
//   - the list, one airline at a time: search by destination; filters for bases (with trunks when a focus city is
//     picked), demand stars, markets, distance and active only; sorts by stars, distance, destination or load; each
//     row's stars, distance, market, frequencies and 7-day load; Add route; Remove unflown routes shown;
//   - a route (RouteDetail.tsx) and its frequencies (Frequency.tsx), with every check from the planning library.
// Addresses: /planner/routes (the list, its filters in the address so a link reopens them) and
// /planner/routes/<airline code>/<hub>-<destination> (a route). Each action is one planner_save() call; the start's
// rules are read again after each, since the schedule changed. Every rule is the library's (lib/rules); model.ts joins
// the tables to it and words what it answers.
import { useMemo, useState, type KeyboardEvent } from "react";
import { useLocation, useNavigate, useParams } from "react-router";
import { block, frequency, game, type FrequencyChecks } from "@rules";
import { useNow } from "../../data/clock";
import { queryClient } from "../../data/query";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import type { Change } from "../../data/save";
import { saver } from "../../data/saving";
import { useTimeMode } from "../../data/timeMode";
import { AirlineMark } from "../../ui/AirlineMark";
import { ConfirmPanel } from "../../ui/Confirm";
import { todayAt } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { showMessage } from "../../ui/messages";
import { Pill } from "../../ui/Pill";
import {
  SORTS, addFrequencyChanges, addRouteChanges, changeFrequency, deleteFrequencyChanges, editRouteChange, filtersQuery, freqOf, isTrunk, listRows,
  liveRules, marketChips, newLegacyKey, nextPair, offsetChanges, parseFilters, parseOffset, perDay, priceFor, removeRoutesChanges, routeOf, serviceFor,
  summaryOf, tailsWords, type AircraftRow, type Airline, type Filters, type Freq, type FreqField, type Load, type Route, type RouteField,
} from "./model";
import { LoadChip, Stars } from "./parts";
import {
  legsAt, readAirports, routeByAirports, useAirlineLegs, useAirlineRotations, useAirlineRoutes, useAirports, useLoads, useMarkets, useRoutesAircraft,
  useServiceProfiles,
} from "./reads";
import { RouteDetail } from "./RouteDetail";
import { AircraftPopup } from "../tails/AircraftPopup";

const firstError = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

export function Routes() {
  const params = useParams();
  const loc = useLocation();
  const navigate = useNavigate();
  const filters = useMemo(() => parseFilters(loc.search), [loc.search]);
  // the aircraft pop-up a frequency's aircraft opens (Tails' AircraftPopup, as from Home), kept in the address
  // (/planner/routes/PA/JFK-ORD?aircraft=N001AW) so a link or the back button reopens it
  const tailPopup = new URLSearchParams(loc.search).get("aircraft");
  const setTailPopup = (reg: string | null) => {
    const n = new URLSearchParams(loc.search);
    if (reg) n.set("aircraft", reg);
    else n.delete("aircraft");
    const q = n.toString();
    navigate({ pathname: loc.pathname.replace(/^\/planner\/next/, "") || "/", search: q ? "?" + q : "" });
  };
  const [codePart = "", pairPart = ""] = (params["*"] ?? "").split("/").map(decodeURIComponent);
  const [hubCode = "", destCode = ""] = pairPart.split("-");
  const now = useNow();
  const today = todayAt(now);
  const [mode] = useTimeMode();
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const airlines: Airline[] = useMemo(() => (airlinesQ.data ?? []).map((a) => ({
    id: a.id, code: a.iata_code, name: a.planner_name ?? a.public_name ?? a.game_name ?? `Airline ${a.game_id}`, color: a.livery_color,
  })), [airlinesQ.data]);
  const airline = airlines.find((a) => a.code === (codePart || filters.airline)) ?? (codePart || filters.airline ? undefined : airlines[0]);
  const rulesQ = useRules(w);
  const routesQ = useAirlineRoutes(w, airline?.id);
  const marketsQ = useMarkets(w);
  const profilesQ = useServiceProfiles(w);
  const aircraftQ = useRoutesAircraft(w);
  const rotationsQ = useAirlineRotations(w, airline?.id);
  const legsQ = useAirlineLegs(w, airline?.id);
  const loadsQ = useLoads(w);
  const [busy, setBusy] = useState(false);
  const [adding, setAdding] = useState(false);
  const [removingShown, setRemovingShown] = useState(false);

  const markets = useMemo(() => new Map((marketsQ.data ?? []).map((m) => [m.id, m])), [marketsQ.data]);
  const routes = useMemo(() => (routesQ.data ?? []).map((r) => routeOf(r, markets)), [routesQ.data, markets]);
  const route = codePart ? routes.find((r) => r.hub === hubCode && r.dest === destCode) : undefined;
  const airportsQ = useAirports(w, route ? [route.hub, route.dest] : []);
  const airports = useMemo(() => new Map((airportsQ.data ?? []).map((a) => [a.code, a])), [airportsQ.data]);
  const rules = rulesQ.data?.rules;
  const live = useMemo(() => (rules && airline && routesQ.data && rotationsQ.data && legsQ.data
    ? liveRules(rules, airline.id, routes, rotationsQ.data, legsQ.data, airportsQ.data ?? []) : null),
  [rules, airline, routes, routesQ.data, rotationsQ.data, legsQ.data, airportsQ.data]);
  const aircraft = useMemo(() => new Map((aircraftQ.data ?? []).map((a) => [a.id, a])), [aircraftQ.data]);
  const byRegistration = useMemo(() => new Map((aircraftQ.data ?? []).map((a) => [a.registration, a])), [aircraftQ.data]);
  // the airline's tails, in the order they were added (id; the old planner's list order went with the clean-up)
  const tails = useMemo(() => (aircraftQ.data ?? []).filter((a) => a.airline_id === airline?.id && a.status === "active")
    .sort((a, b) => a.id - b.id), [aircraftQ.data, airline]);

  // every route's frequencies, as the library sees them, and the figures the list shows
  const freqsByRoute = useMemo(() => {
    const out = new Map<number, Freq[]>();
    if (!live || !rotationsQ.data || !legsQ.data) return out;
    const byId = new Map(routes.map((r) => [r.id, r]));
    for (const rot of rotationsQ.data) {
      const r = byId.get(rot.route_id);
      if (!r) continue;
      out.set(r.id, [...(out.get(r.id) ?? []), freqOf(live, r, rot, legsQ.data, aircraft)]);
    }
    return out;
  }, [live, rotationsQ.data, legsQ.data, routes, aircraft]);
  const summaries = useMemo(() => new Map([...freqsByRoute.entries()].map(([id, fs]) => [id, summaryOf(fs)])), [freqsByRoute]);
  const routeLoads = useMemo(() => new Map<number, Load>((loadsQ.data?.routes ?? []).map((l) => [l.route_id, l])), [loadsQ.data]);
  const flightLoads = useMemo(() => new Map<string, Load>((loadsQ.data?.flights ?? []).map((l) => [`${l.airline_id}|${l.flight_no}`, l])), [loadsQ.data]);
  const bases = useMemo(() => (live && airline ? live.bases.filter((b) => b.airline_id === airline.id) : []), [live, airline]);
  const ctx = useMemo(() => ({
    focus: bases.filter((b) => b.role === "focus").map((b) => b.airport_code), hubs: bases.filter((b) => b.role !== "focus").map((b) => b.airport_code),
    summaries, loads: routeLoads,
  }), [bases, summaries, routeLoads]);
  // the bases picked: the address's, else the open route's hub, else the airline's first base (the old planner's ui.hubs)
  const pickedKey = (filters.bases ?? [route?.hub ?? bases[0]?.airport_code].filter((x): x is string => !!x)).join(",");
  const picked = useMemo(() => (pickedKey ? pickedKey.split(",") : []), [pickedKey]);
  const rows = useMemo(() => listRows(routes, filters, picked, ctx), [routes, filters, picked, ctx]);
  const activeCount = rows.filter((x) => x.summary.count).length;
  const removable = rows.filter((x) => !x.summary.count);

  // the open route's frequencies and every check on them, against the whole schedule
  const routeFreqs = route ? freqsByRoute.get(route.id) ?? [] : [];
  const checks = useMemo(() => {
    const m = new Map<number, FrequencyChecks>();
    if (!live || !route) return m;
    const timed = block.timedLegs(live);
    for (const f of freqsByRoute.get(route.id) ?? []) m.set(f.rot.id, frequency.checks(live, f.rot.id, timed));
    return m;
  }, [live, route, freqsByRoute]);

  const ready = !!(live && routesQ.data && marketsQ.data && profilesQ.data && aircraftQ.data && loadsQ.data && (!route || airportsQ.data));
  const loadError = firstError(world, airlinesQ, rulesQ, routesQ, marketsQ, profilesQ, aircraftQ, rotationsQ, legsQ, loadsQ, airportsQ);

  // ---------- addresses
  const listHref = (f: Filters) => "/routes" + filtersQuery(f);
  const here = (f: Filters) => (codePart ? loc.pathname.replace(/^.*?\/routes/, "/routes") : "/routes") + filtersQuery(codePart ? { ...f, airline: null } : f);
  const routeHref = (r: Route) => `/routes/${encodeURIComponent(airline?.code ?? "")}/${encodeURIComponent(r.hub + "-" + r.dest)}`
    + filtersQuery({ ...filters, airline: null, bases: filters.bases ?? picked });
  const toList = (f: Filters) => navigate(listHref({ ...f, airline: airline && airline !== airlines[0] ? airline.code : f.airline }));
  const keep = (f: Filters, replace = false) => navigate(here(f), { replace });

  // ---------- saving: one action each; the start's rules are read again after it, since the schedule changed
  async function save(changes: Change[]) {
    if (!changes.length) return { status: "saved" as const };
    setBusy(true);
    try {
      const res = await saver.save(changes);
      if (res.status === "saved") void queryClient.invalidateQueries({ queryKey: ["rules"] });
      return res;
    } finally {
      setBusy(false);
    }
  }
  const onFrequency = (f: Freq, field: FreqField, value: string) => {
    if (!live || !route) return;
    const res = changeFrequency(live, f, field, value, { mode, today, aircraft, byRegistration, route });
    if ("error" in res) { showMessage(res.error); return; }
    void save(res.changes);
  };
  const onAddFrequency = () => {
    if (!live || !route || w === undefined) return;
    const nx = nextPair(live, route);
    void save(addFrequencyChanges(w, route, nx, serviceFor(profilesQ.data ?? [], route), priceFor(live, route), today, newLegacyKey()));
  };
  const onEdit = (field: RouteField, value: string) => {
    if (!route) return;
    const res = editRouteChange(route, field, value, marketsQ.data ?? []);
    if ("error" in res) { showMessage(res.error); return; }
    void save(res.changes);
  };
  const onRemove = async () => {
    if (!route) return;
    const res = await save(removeRoutesChanges([route], `removed in Routes on ${today}`));
    if (res.status === "saved") toList(filters);
  };
  // an offset typed: every leg touching the airport, read fresh with its updated_at, re-timed to keep its local times
  const onOffset = async (code: string, typed: string) => {
    if (!live || w === undefined) return null;
    const v = parseOffset(typed);
    if (v === "bad") return null;
    const [info] = (airportsQ.data ?? []).filter((a) => a.code === code);
    const a = info ?? (await readAirports(w, [code]))[0];
    if (!a) { showMessage(`No airport ${code}`); return null; }
    const before = a.correction ?? a.utc_offset ?? 0;
    const hours = v ?? a.utc_offset ?? 0;
    if (v === a.correction && hours === before) return null;
    const { legs, planLegs } = await legsAt(w, code);
    const rots = [...new Set(legs.map((l) => l.rotation_id))].map((id) => {
      const l1 = legs.find((l) => l.rotation_id === id && l.leg_no === 1), l2 = legs.find((l) => l.rotation_id === id && l.leg_no === 2);
      const rot = live.rotations.get(id), rr = rot ? live.routes.get(rot.route_id) : undefined;
      const ac = l1?.aircraft_id ?? l2?.aircraft_id;
      const type = ac == null ? undefined : live.aircraft.get(ac)?.aircraft_type_id ?? undefined;
      const airlineId = (l1 ?? l2)?.airline_id ?? 0;
      // with no aircraft, the airline's most-flown type (its market's aircraft until 21 Oct)
      return {
        rotation_id: id, leg1: l1, leg2: l2,
        ends: { airline_id: airlineId, hub: l1?.origin_code ?? l2?.dest_code ?? "", dest: l1?.dest_code ?? l2?.origin_code ?? "",
          distance_km: rr?.distance_km ?? null, type_id: type ?? game.mostFlownType(live, airlineId) },
      };
    });
    const plan = offsetChanges(live, w, a, v, { rotations: rots, planLegs });
    const n = plan.moves.length;
    const word = (h: number) => String(h);
    return {
      question: `Change ${code}'s UTC offset from ${word(before)} to ${word(hours)}${v == null ? " (the game's)" : ""}? The planner keeps local times there, so ${n ? `${n} leg${n === 1 ? "" : "s"} move${n === 1 ? "s" : ""} in UTC` : "nothing moves"}.`,
      moves: plan.moves,
      apply: async () => {
        const res = await save(plan.changes);
        if (res.status === "saved") void queryClient.invalidateQueries({ queryKey: ["table", "world_airports"] });
      },
    };
  };

  // ---------- Add route (the old r-add)
  const [form, setForm] = useState({ hub: "", dest: "", city: "", km: "", market: "" });
  async function addRoute() {
    if (!airline || w === undefined || !live) return;
    const hub = form.hub || picked[0] || bases[0]?.airport_code || "", dest = form.dest.trim().toUpperCase();
    if (!hub || !dest) return;
    if (routes.some((r) => r.hub === hub && r.dest === dest)) { showMessage("That route is already in the list."); return; }
    const [ah, ad] = await Promise.all([readAirports(w, [hub]), readAirports(w, [dest])]);
    const typedKm = Number(form.km) || null;
    const km = typedKm ?? block.greatCircleBetween(ah[0], ad[0]);
    if (!km) { showMessage("Distance needed — this airport isn't in the list, type the km."); return; }
    const existing = await routeByAirports(airline.id, hub, dest);
    const mkt = (marketsQ.data ?? []).find((m) => m.airline_id === airline.id && m.name === form.market);
    const res = await save(addRouteChanges(w, airline.id, hub, dest, {
      city: form.city.trim() || ad[0]?.city || dest, country: ad[0]?.country_name ?? ad[0]?.country_code ?? null, km, marketId: mkt?.id ?? null,
    }, existing, !ad[0]));
    if (res.status === "saved") {
      setAdding(false);
      setForm({ hub: "", dest: "", city: "", km: "", market: "" });
      navigate(`/routes/${encodeURIComponent(airline.code ?? "")}/${encodeURIComponent(hub + "-" + dest)}` + filtersQuery({ ...filters, airline: null, bases: filters.bases ?? picked }));
    }
  }

  const toggle = <T,>(list: readonly T[], v: T) => (list.includes(v) ? list.filter((x) => x !== v) : [...list, v]);
  const km = (k: "kmFrom" | "kmTo") => ({
    defaultValue: filters[k], key: filters[k],
    onBlur: (e: React.FocusEvent<HTMLInputElement>) => { if (e.currentTarget.value !== filters[k]) keep({ ...filters, [k]: e.currentTarget.value }); },
    onKeyDown: (e: KeyboardEvent<HTMLInputElement>) => { if (e.key === "Enter") e.currentTarget.blur(); },
  });
  const airlineMarkets = (marketsQ.data ?? []).filter((m) => m.airline_id === airline?.id);
  const focusPicked = picked.some((c) => ctx.focus.includes(c));

  return (
    <main className={"view routes" + (route || codePart ? " has-detail" : "")} data-screen="routes" data-routes-ready={ready ? "yes" : "no"}
      data-routes-airline={airline?.code ?? ""} data-route-open={route ? `${route.hub}-${route.dest}` : ""} data-routes-view={loc.pathname + loc.search}>
      <div className="vh"><p className="vk">The network</p><h1>Routes</h1><p>Every route in the network. Pick one to schedule its flights.</p></div>
      {loadError ? <ErrorBox error={loadError} /> : null}
      {airlinesQ.data && !airline ? <ErrorBox error={`There's no airline ${codePart || filters.airline} among ours.`} /> : null}
      <div className="toolbar">
        <div className="seg">
          {airlines.map((a) => (
            <button type="button" key={a.id} data-al={a.code ?? ""} className={a.id === airline?.id ? "on" : ""}
              onClick={() => navigate(listHref({ ...filters, airline: a === airlines[0] ? null : a.code, bases: null, markets: [] }))}>
              <AirlineMark color={a.color} />{a.name}
            </button>
          ))}
        </div>
        <input id="f-q" placeholder="Search destination" value={filters.q} onChange={(e) => keep({ ...filters, q: e.currentTarget.value }, true)} />
        <label className="check"><input type="checkbox" id="f-active" checked={filters.active} onChange={(e) => keep({ ...filters, active: e.currentTarget.checked })} /> Active only</label>
        <select id="f-sort" value={filters.sort} onChange={(e) => keep({ ...filters, sort: e.currentTarget.value as Filters["sort"] })}>
          {SORTS.map(([s, l]) => <option key={s} value={s}>{l}</option>)}
        </select>
        <input id="f-dmin" type="number" placeholder="km from" style={{ width: 86 }} {...km("kmFrom")} />
        <input id="f-dmax" type="number" placeholder="km to" style={{ width: 86 }} {...km("kmTo")} />
        <button type="button" className="secondary" id="add-route-btn" onClick={() => setAdding((x) => !x)}>Add route</button>
        {removable.length && !filters.active ? (
          <button type="button" className="danger" id="rm-filtered" disabled={busy} onClick={() => setRemovingShown(true)}>
            Remove {removable.length} unflown route{removable.length > 1 ? "s" : ""} shown
          </button>
        ) : null}
        <span className="count" data-figure="routes: count">{rows.length} routes · {activeCount} active</span>
      </div>
      {removingShown ? (
        <ConfirmPanel question={`Remove ${removable.length} unflown routes from the list? You can restore them from Reference.`} yes="Remove" busy={busy}
          onNo={() => setRemovingShown(false)}
          onYes={() => { setRemovingShown(false); void save(removeRoutesChanges(removable.map((x) => x.route), `removed with the unflown routes shown on ${today}`)).then((res) => { if (res.status === "saved" && route && removable.some((x) => x.route.id === route.id)) toList(filters); }); }} />
      ) : null}
      <div className="chips" data-chips="bases">
        <span className="chiplbl">Bases</span>
        <button type="button" className={"chip" + (!picked.length ? " on" : "")} data-hubchip="" onClick={() => toList({ ...filters, bases: [] })}>All</button>
        {bases.map((b) => {
          const fc = b.role === "focus";
          return (
            <button type="button" key={b.id} className={"chip" + (picked.includes(b.airport_code) ? " on" : "") + (fc ? " fcchip" : "")} data-hubchip={b.airport_code}
              title={fc ? "focus city" + (b.parent_code ? ", feeds " + b.parent_code : "") : "hub"}
              onClick={() => toList({ ...filters, bases: toggle(picked, b.airport_code) })}>
              {b.airport_code}{fc ? <span className="fctag">focus</span> : null}
            </button>
          );
        })}
        {focusPicked && ctx.hubs.length ? <>
          <button type="button" className={"chip" + (filters.trunks ? "" : " on")} data-trunkonly="0" onClick={() => toList({ ...filters, bases: picked, trunks: false })}>All routes</button>
          <button type="button" className={"chip" + (filters.trunks ? " on" : "")} data-trunkonly="1" title="only routes between the focus city and this airline's hubs"
            onClick={() => toList({ ...filters, bases: picked, trunks: true })}>Trunks only</button>
        </> : null}
      </div>
      <div className="chips" data-chips="stars">
        <span className="chiplbl">Demand</span>
        <button type="button" className={"chip" + (!filters.stars.length ? " on" : "")} data-starchip="" onClick={() => toList({ ...filters, bases: picked, stars: [] })}>All</button>
        {[5, 4, 3, 2, 1].map((n) => (
          <button type="button" key={n} className={"chip" + (filters.stars.includes(n) ? " on" : "")} data-starchip={n}
            onClick={() => toList({ ...filters, bases: picked, stars: toggle(filters.stars, n) })}>{"★".repeat(n)}</button>
        ))}
      </div>
      <div className="chips" data-chips="markets">
        <span className="chiplbl">Markets</span>
        <button type="button" className={"chip" + (!filters.markets.length ? " on" : "")} data-mkchip="" onClick={() => toList({ ...filters, bases: picked, markets: [] })}>All</button>
        {marketChips(routes).map((m) => (
          <button type="button" key={m} className={"chip" + (filters.markets.includes(m) ? " on" : "")} data-mkchip={m}
            onClick={() => toList({ ...filters, bases: picked, markets: toggle(filters.markets, m) })}>{m}</button>
        ))}
      </div>
      {adding && airline ? (
        <div className="addform" data-add-route>
          <b>New route for {airline.name}</b>
          <select id="r-hub" value={form.hub || picked[0] || ""} onChange={(e) => setForm({ ...form, hub: e.currentTarget.value })}>
            <option value="">Hub</option>{bases.map((b) => <option key={b.id} value={b.airport_code}>{b.airport_code}</option>)}
          </select>
          <input id="r-dest" placeholder="Dest code" maxLength={3} style={{ width: 90 }} value={form.dest} onChange={(e) => setForm({ ...form, dest: e.currentTarget.value })} />
          <input id="r-city" placeholder="City (auto if known)" style={{ width: 150 }} value={form.city} onChange={(e) => setForm({ ...form, city: e.currentTarget.value })} />
          <input id="r-dist" placeholder="km (auto if known)" style={{ width: 120 }} value={form.km} onChange={(e) => setForm({ ...form, km: e.currentTarget.value })} />
          <select id="r-market" value={form.market} onChange={(e) => setForm({ ...form, market: e.currentTarget.value })}>
            <option value="">Market</option>{airlineMarkets.map((m) => <option key={m.id} value={m.name}>{m.name}</option>)}
          </select>
          <button type="button" className="primary" id="r-add" disabled={busy} onClick={() => void addRoute()}>Add</button>
          <button type="button" className="link" id="r-cancel" onClick={() => setAdding(false)}>cancel</button>
        </div>
      ) : null}
      <div className="split">
        <div className="list" id="routelist" data-figure="routes: list">
          {!rows.length ? <div className="empty">{ready ? "No routes match. Clear a filter." : "Loading…"}</div> : null}
          {rows.map(({ route: r, summary: s }) => (
            <div key={r.id} className={"row" + (route?.id === r.id ? " sel" : "")} data-route-row={`${r.hub}-${r.dest}`} role="link" tabIndex={0}
              onClick={() => navigate(routeHref(r))} onKeyDown={(e) => { if (e.key === "Enter") navigate(routeHref(r)); }}>
              <div className="rk"><b>{r.hub}–{r.dest}</b> <span className="city">{r.city}</span></div>
              <div className="rm">
                {isTrunk(r, ctx) ? <><span className="pill trunk" title="trunk route between a focus city and a hub">trunk</span>{" "}</> : null}
                <Stars n={r.stars} title={`demand ${r.stars}/5`} /> {r.market} · {(r.dist ?? 0).toLocaleString()} km
              </div>
              <div className="rs">
                {s.count ? <>
                  <LoadChip a={routeLoads.get(r.id)} small />
                  <Pill kind={s.allOk === false ? "bad" : "ok"}>{perDay(s.rtDay)}×/day</Pill>
                  <span className="meta">{tailsWords(s.tails)} · {s.numbers}</span>
                </> : <span className="meta dim">not flown</span>}
              </div>
            </div>
          ))}
        </div>
        <div className="detail" id="detail">
          {route && airline && live ? (
            <RouteDetail route={route} airline={airline} airlines={airlines} freqs={routeFreqs} checks={checks} rules={live} mode={mode}
              routeLoad={routeLoads.get(route.id)} flightLoad={(no) => (no == null ? undefined : flightLoads.get(`${route.airline_id}|${no}`))}
              airlineMarkets={airlineMarkets} profiles={profilesQ.data ?? []} tails={tails as AircraftRow[]} airports={airports} busy={busy}
              onBack={() => toList({ ...filters, bases: filters.bases ?? picked })} onFrequency={onFrequency}
              onDeleteFrequency={(f) => void save(deleteFrequencyChanges(f, today))} onAddFrequency={onAddFrequency} onEdit={onEdit}
              onRemove={() => void onRemove()} onOffset={onOffset} onOpenTail={(reg) => setTailPopup(reg)} />
          ) : codePart && ready ? (
            <div className="empty" data-no-route>No route {hubCode}–{destCode} for {airline?.name ?? codePart}: it may have been removed (Reference restores it).</div>
          ) : codePart ? <div className="empty">Loading…</div> : <div className="empty">Pick a route to add frequencies.</div>}
        </div>
      </div>
      {tailPopup && rules ? <AircraftPopup registration={tailPopup} rules={rules} onClose={() => setTailPopup(null)} /> : null}
    </main>
  );
}
