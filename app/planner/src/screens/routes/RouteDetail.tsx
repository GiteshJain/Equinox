// A route, as the old planner's renderRouteDetail draws it: its header (stars, airline, market, distance, the two UTC
// offsets; the estimated block, its layout, its service profile, the hub's banks), edit route and remove route; the next
// free numbers when it isn't flown, its loads when it is; each frequency; and Add frequency. Every action is one
// planner_save() call; the questions are asked in the page. Since 21 Oct (spec docs/specs/2026-10-21-cabins-new-rule.md
// §2) the header shows the layout the route calls for (since 26 Oct its distance's range, manual §5) where it showed the
// market's aircraft, cabin and fares, and the block is estimated on the airline's most-flown type. Since 22 Oct (spec
// docs/specs/2026-10-21-route-page.md §3) a flown route links to its route page on Performance. Since the new look (22 Oct,
// spec docs/specs/2026-10-22-planner-look-routes.md §5): the route's name ("New York → Atlanta") with its codes, a muted
// line (airline, distance, stars, market), the figures as big numbers, then the frequencies, the loads and "The route's
// story ›".
import { useState, type FocusEvent, type KeyboardEvent } from "react";
import { Link } from "react-router";
import { block, findType, game, type FrequencyChecks, type Rules } from "@rules";
import { ConfirmPanel } from "../../ui/Confirm";
import { showMessage } from "../../ui/messages";
import { itemRoute } from "../screens";
import { Frequency } from "./Frequency";
import {
  bankWords, disp, hhmm, layoutWords, loadAverage, loadClass, moveWords, nextPair, nextPairWords, parseOffset, perDay, priceFor, routeName, serviceFor, summaryOf,
  type AircraftRow, type Airline, type AirportInfo, type Freq, type FreqField, type Load, type MarketRow, type Mode, type OffsetMove, type Route, type RouteField,
} from "./model";
import { LoadSummary, Stars } from "./parts";
import type { ServiceRow } from "./reads";

export interface DetailProps {
  route: Route;
  airline: Airline;
  airlines: readonly Airline[];
  freqs: readonly Freq[];
  checks: ReadonlyMap<number, FrequencyChecks>;
  rules: Rules;
  mode: Mode;
  routeLoad: Load | undefined;
  flightLoad: (no: number | null) => Load | undefined;
  airlineMarkets: readonly MarketRow[];
  profiles: readonly ServiceRow[];
  tails: readonly AircraftRow[];
  airports: ReadonlyMap<string, AirportInfo>;
  busy: boolean;
  onBack: () => void;
  onFrequency: (f: Freq, field: FreqField, value: string) => void;
  onDeleteFrequency: (f: Freq) => void;
  onAddFrequency: () => void;
  onEdit: (field: RouteField, value: string) => void;
  onRemove: () => void;
  /** Opens a frequency's aircraft in its pop-up. */
  onOpenTail?: (registration: string) => void;
  /** An offset typed: what it would move, worked out from the copy's legs, to ask about first. */
  onOffset: (code: string, typed: string) => Promise<{ question: string; moves: OffsetMove[]; apply: () => Promise<void> } | null>;
}

/** An offset's box: the airport's hours from UTC (the world's correction, else the game's, else 0, as the old utcOf). */
function OffsetInput({ code, value, style, onOffset, className }: { code: string; value: string; style?: React.CSSProperties; className?: string; onOffset: (code: string, typed: string) => void }) {
  const done = (e: FocusEvent<HTMLInputElement>) => { if (e.currentTarget.value !== value) onOffset(code, e.currentTarget.value); };
  const enter = (e: KeyboardEvent<HTMLInputElement>) => { if (e.key === "Enter") e.currentTarget.blur(); };
  return <input key={value} data-utc={code} defaultValue={value} className={className} style={style} title={`${code} hours from UTC`} onBlur={done} onKeyDown={enter} />;
}

export function RouteDetail(p: DetailProps) {
  const r = p.route, rules = p.rules;
  const [editing, setEditing] = useState(false);
  const [removing, setRemoving] = useState(false);
  const [offset, setOffset] = useState<{ code: string; question: string; moves: OffsetMove[]; apply: () => Promise<void> } | null>(null);
  // the estimate on the airline's most-flown type (the market's aircraft until 21 Oct)
  const type = findType(rules, game.mostFlownType(rules, r.airline_id));
  const est = type && type.cruise_kmh && r.dist != null ? block.estimateBlock(rules, r.dist, type, r.airline_id) : null;
  const base = rules.bases.find((b) => b.airport_code === r.hub && b.airline_id === r.airline_id);
  const offH = (code: string) => {
    const a = p.airports.get(code);
    const h = a ? a.correction ?? a.utc_offset : rules.airports.get(code)?.utc_offset;
    return h == null ? 0 : Number(h);
  };
  const offMin = (code: string) => Math.round(offH(code) * 60);
  const z = p.mode === "utc" ? "Z" : "";
  const nx = nextPair(rules, r);
  const svc = serviceFor(p.profiles, r);
  const sm = summaryOf(p.freqs);
  const codeOf = (id: number | null) => p.airlines.find((a) => a.id === id)?.code ?? null;
  const askOffset = async (code: string, typed: string) => {
    const v = parseOffset(typed);
    if (v === "bad") { showMessage(`An offset is hours from UTC, such as 5.5 or -5 (${typed} isn't)`); return; }
    const q = await p.onOffset(code, typed);
    if (q) setOffset({ code, ...q });
  };
  const margin = (() => { const s = rules.input.settings.turn_margin_min; return typeof s === "number" ? s : Number(s ?? 0); })();
  const maxWait = (() => { const s = rules.input.settings.connection_max_wait_h; return typeof s === "number" ? s : Number(s ?? 8); })();
  const connectionNote = (code: string) => {
    const m = rules.airports.get(code)?.mct_min;
    return `Connections from ${hhmm(m == null ? 90 : Number(m))} (minimum connection) up to ${maxWait} h`;
  };
  const isBase = (code: string) => rules.bases.some((b) => b.airport_code === code);
  const tails = p.tails.map((t) => t.registration);
  const marketNames = p.airlineMarkets.map((m) => m.name);
  const edit = (field: RouteField) => (e: FocusEvent<HTMLInputElement> | React.ChangeEvent<HTMLSelectElement>) => p.onEdit(field, e.currentTarget.value);
  const enter = (e: KeyboardEvent<HTMLInputElement>) => { if (e.key === "Enter") e.currentTarget.blur(); };

  return (
    <div data-route-detail={`${r.hub}-${r.dest}`}>
      <div className="dhead" data-figure="routes: header">
        <button type="button" className="back" id="back-route" onClick={p.onBack}>← Routes</button>
        <h2 className="rdh">{routeName(p.airports.get(r.hub)?.city, r.hub, r.city || p.airports.get(r.dest)?.city, r.dest)} <span className="rcodes">{r.hub}–{r.dest}</span></h2>
        <div className="dsub" data-dsub="1">
          {p.airline.name} · {(r.dist ?? 0).toLocaleString()} km · <Stars n={r.stars} title={`demand ${r.stars}/5`} />{r.market ? ` · ${r.market}` : ""}
        </div>
        <div className="rfigs" data-figure="routes: figures">
          <div className="rfig" data-fig="block"><span className="rfl">Est. block</span><b>{est ? hhmm(est) : "—"}</b><span className="rfs">on {type?.name ?? "?"}</span></div>
          <div className="rfig" data-fig="a day"><span className="rfl">A day</span><b>{sm.count ? perDay(sm.rtDay) : "—"}</b>
            <span className="rfs">{sm.count ? `round trip${sm.rtDay === 1 ? "" : "s"} · ${sm.count} frequenc${sm.count === 1 ? "y" : "ies"}` : "not flown yet"}</span></div>
          <div className="rfig" data-fig="load"><span className="rfl">Load, 7 days</span>
            {p.routeLoad ? <><b className={"lf " + loadClass(loadAverage(p.routeLoad))}>≈{Math.round(loadAverage(p.routeLoad))}%</b>
              <span className="rfs">{p.routeLoad.departures} departure{p.routeLoad.departures === 1 ? "" : "s"}</span></>
              : <><b>—</b><span className="rfs">no reports yet</span></>}
          </div>
        </div>
        <div className="dsub" data-dsub="2">
          <span data-route-layout>{layoutWords(rules, r)}</span> · service {svc}
          {" · " + bankWords(base, (b) => disp(Number(b.slice(0, 2)) * 60 + Number(b.slice(3, 5)), offMin(r.hub), p.mode)) + (base && base.role !== "station" ? z : "")}
        </div>
        <div className="dsub" data-dsub="3">
          UTC offsets{" "}
          <OffsetInput code={r.hub} value={String(offH(r.hub))} className="tiny" onOffset={(c, t) => void askOffset(c, t)} /> {r.hub}{" "}
          <OffsetInput code={r.dest} value={String(offH(r.dest))} className="tiny" onOffset={(c, t) => void askOffset(c, t)} /> {r.dest}
        </div>
        <div className="racts">
          <button type="button" className="link" id="edit-route" aria-expanded={editing} onClick={() => setEditing((x) => !x)}>{editing ? "done" : "edit route"}</button>
          <button type="button" className="link" id="rm-route" disabled={p.busy}
            onClick={() => { if (p.freqs.length) showMessage("Remove its frequencies first."); else setRemoving(true); }}>remove route</button>
        </div>
        {editing ? (
          <div className="fg edit-route">
            <label>Demand stars<select key={r.stars} data-rk="stars" defaultValue={String(r.stars)} onChange={edit("stars")} disabled={p.busy}>
              {["5", "4", "3", "2", "1"].map((s) => <option key={s} value={s}>{s}</option>)}</select></label>
            <label>Market<select key={r.market} data-rk="market" defaultValue={r.market} onChange={edit("market")} disabled={p.busy}>
              <option value="">—</option>{(r.market && !marketNames.includes(r.market) ? [...marketNames, r.market] : marketNames).map((m) => <option key={m} value={m}>{m}</option>)}</select></label>
            <label>Distance km<input key={String(r.dist)} data-rk="dist" defaultValue={r.dist == null ? "" : String(r.dist)}
              onBlur={(e) => { if (e.currentTarget.value !== (r.dist == null ? "" : String(r.dist))) edit("dist")(e); }} onKeyDown={enter} disabled={p.busy} /></label>
            <label>City<input key={r.city} data-rk="city" defaultValue={r.city} onBlur={(e) => { if (e.currentTarget.value !== r.city) edit("city")(e); }} onKeyDown={enter} disabled={p.busy} /></label>
            <label>UTC {r.hub}<OffsetInput code={r.hub} value={String(offH(r.hub))} style={{ width: 70 }} onOffset={(c, t) => void askOffset(c, t)} /></label>
            <label>UTC {r.dest}<OffsetInput code={r.dest} value={String(offH(r.dest))} style={{ width: 70 }} onOffset={(c, t) => void askOffset(c, t)} /></label>
          </div>
        ) : null}
      </div>
      {offset ? (
        <ConfirmPanel question={offset.question} yes="Change it" busy={p.busy}
          onYes={() => { const o = offset; setOffset(null); void o.apply(); }} onNo={() => setOffset(null)}>
          {offset.moves.length ? (
            <ul data-offset-moves>
              {offset.moves.map((m, i) => <li key={i}>{moveWords(m, codeOf(m.airline_id))}</li>)}
            </ul>
          ) : <div className="dim">No flight touches {offset.code}, so nothing moves.</div>}
        </ConfirmPanel>
      ) : null}
      {removing ? (
        <ConfirmPanel question="Remove this route from the list? You can restore it from Reference." yes="Remove" busy={p.busy}
          onYes={() => { setRemoving(false); p.onRemove(); }} onNo={() => setRemoving(false)} />
      ) : null}
      {!p.freqs.length ? (
        <div className="empty" data-figure="routes: next numbers">
          Not flown yet. Next free numbers at {r.hub}: {nextPairWords(nx)}.
        </div>
      ) : <h3 className="rsh">Frequencies</h3>}
      {p.freqs.map((f) => (
        <Frequency key={f.rot.id} f={f} route={r} checks={p.checks.get(f.rot.id) ?? null} mode={p.mode} flightLoad={p.flightLoad} airlines={p.airlines}
          tails={tails} services={p.profiles.map((s) => s.code)} serviceDefault={svc} priceDefault={priceFor(rules, r)} connectionNote={connectionNote}
          isBase={isBase} turnMargin={margin} busy={p.busy} onChange={(field, value) => p.onFrequency(f, field, value)} onDelete={() => p.onDeleteFrequency(f)}
          onOpenTail={p.onOpenTail} />
      ))}
      <button type="button" className="primary" id="add-freq" onClick={p.onAddFrequency} disabled={p.busy}>Add frequency</button>
      {p.freqs.length ? <LoadSummary a={p.routeLoad} /> : null}
      {p.freqs.length && p.airline.code ? (
        <Link className="rstory" to={itemRoute("performance", { airline: p.airline.code, hub: r.hub, dest: r.dest })} data-route-page-link
          title="its story since launch, on Performance">The route's story ›</Link>
      ) : null}
    </div>
  );
}
