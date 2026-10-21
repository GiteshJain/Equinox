// Performance → Growth signals and Main hubs towards 750 (Check → Growth until 20 Oct, the old growthBoard): the growth
// lists from the capture (growth_signals(): ready for another flight, raise fares, fix or reduce, aircraft losing money
// after their lease; from the load reports and load patterns when no profit was captured), and one bar per main hub
// towards its weekly target (hub_progress()) with hub readiness (how many cities feed each bank, the library's
// growth.hubReadiness) folded into its line. Can order and the order queues moved to Today; the order rotation's next
// move and its Log an order as went (spec decision 2). The planning parts are the library's (growth, the suggested
// aircraft size after a route too, growth.suggestedSize); the captured figures the database's.
import { Link } from "react-router";
import type { GrowthRoute, ReadinessRow, Rules } from "@rules";
import type { OurAirline } from "../../data/airlines";
import { AirlineMark } from "../../ui/AirlineMark";
import { loadClass, loadTip, type Load } from "../routes/model";
import { itemRoute } from "../screens";
import { H, hubRows, kWords, pctWords, perDayWords, readinessOf, weekWords } from "./growth";
import type { GrowthRead, HubProgressAirline, Pattern, SignalAircraft, SignalRoute } from "./reads";

export interface ReadyRow { route: GrowthRoute & { airline_id: number; round_trips_day: number }; load: Load & { average: number }; flyingOn: string; size: string | null }

const routeLink = (code: string | null | undefined, hub: string, dest: string) => (
  <Link className="link" to={itemRoute("routes", { airline: code, hub, dest })}><b>{hub}–{dest}</b></Link>
);

function Table<T>({ rows, cols }: { rows: readonly T[]; cols: readonly [string, (r: T) => React.ReactNode, boolean?][] }) {
  return (
    <div className="tscroll">
      <table className="tbl gtbl">
        <tbody>
          <tr>{cols.map((c, i) => <th key={i} className={c[2] ? "num" : undefined}>{c[0]}</th>)}</tr>
          {rows.map((r, i) => <tr key={i}>{cols.map((c, j) => <td key={j} className={c[2] ? "num" : undefined}>{c[1](r)}</td>)}</tr>)}
        </tbody>
      </table>
    </div>
  );
}

/** The growth lists: from the capture, or from the load reports and patterns when no profit was captured. */
export function GrowthSignals({ rules, signals, ready, airlines }: { rules: Rules; signals: GrowthRead; ready: readonly ReadyRow[]; airlines: readonly OurAirline[] }) {
  return (
    <div data-figure="performance: growth lists">
      {signals.profit_captured ? <Signals rules={rules} s={signals} airlines={airlines} /> : <FromLoads ready={ready} patterns={signals.load_patterns} airlines={airlines} rules={rules} />}
    </div>
  );
}

/** Main hubs towards their weekly target: one bar per hub, the plan cards not yet filed lighter, and each airline's hub
 *  readiness (the cities feeding each bank) folded into its line. */
export function MainHubs({ progress, readiness, airlines }: { progress: readonly HubProgressAirline[]; readiness: readonly ReadinessRow[]; airlines: readonly OurAirline[] }) {
  const al = (id: number) => airlines.find((a) => a.id === id);
  const hubs = hubRows(progress, (id) => al(id)?.name ?? "");
  const shown = new Set(hubs.map((h) => h.airline_id));
  // airlines whose banks are counted but with no main hub towards the target (exempt, or none yet) keep their readiness
  const others = airlines.filter((a) => !shown.has(a.id) && readiness.some((r) => r.airline_id === a.id));
  const fold = (airlineId: number) => {
    const r = readinessOf(readiness, airlineId);
    if (!r.rows.length) return null;
    return (
      <details className="gsub hpready" data-readiness={al(airlineId)?.code ?? ""}>
        <summary className="dim">Hub readiness: {r.line}</summary>
        <div className="tscroll">
          <table className="tbl" data-figure="performance: hub readiness">
            <tbody>
              <tr><th>Hub</th><th>Bank</th><th>Cities flying</th><th>With planned</th><th>Regions (with planned)</th></tr>
              {r.rows.map((x) => (
                <tr key={`${x.base_id}|${x.bank}`}>
                  <td><b>{x.airport}</b></td>
                  <td>B{x.bank} · {H(x.dep)}</td>
                  <td>{x.flying}</td>
                  <td><b>{x.with_planned}</b></td>
                  <td className="dim">{x.regions.map((c) => `${c.region} ${c.cities}`).join(" · ")}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>
    );
  };
  return (
    <div className="hubprog" data-figure="performance: main hubs">
      {hubs.map((x) => (
        <div className="hpline" key={x.airline_id} data-hub={x.hub}>
          <div className="hp">
            <span className="hpn"><AirlineMark color={al(x.airline_id)?.color} /><b>{x.hub}</b> <span className="dim">{x.name}</span></span>
            <div className="hpbar"><i style={{ width: x.width }} /><i className="pend" style={{ width: x.pend }} /></div>
            <span className="hpv"><b>{x.departures}</b>{x.planned ? <> <span className="dim">+{x.planned}</span></> : null} / {x.target} <span className="dim">{x.pct}%</span></span>
          </div>
          {fold(x.airline_id)}
        </div>
      ))}
      {others.map((a) => (
        <div className="hpline" key={a.id}>
          <div className="hpn"><AirlineMark color={a.color} /><b>{a.name}</b> <span className="dim">no main hub towards the target</span></div>
          {fold(a.id)}
        </div>
      ))}
      {!hubs.length && !others.length ? <div className="dim">No main hub yet.</div> : null}
    </div>
  );
}

/** The growth lists from the capture (the old capSignalsHtml). */
function Signals({ rules, s, airlines }: { rules: Rules; s: GrowthRead; airlines: readonly OurAirline[] }) {
  const al = (id: number) => airlines.find((a) => a.id === id);
  const AL: [string, (r: { airline_id: number }) => React.ReactNode] = ["Airline", (r) => <><AirlineMark color={al(r.airline_id)?.color} />{al(r.airline_id)?.name ?? ""}</>];
  const rl = (r: SignalRoute) => routeLink(al(r.airline_id)?.code, r.hub, r.dest);
  const setting = (k: string) => String(rules.input.settings[k] ?? "?");
  return (
    <>
      <h4 className="gh">Ready for another flight <span className="note">sold out on most captured departures in the last {s.days} days, and profit an aircraft hour (block time, turnaround and turn margin) at or above the airline's middle route · {s.ready_for_another_flight.length}</span></h4>
      {s.ready_for_another_flight.length ? <Table rows={s.ready_for_another_flight} cols={[["Route", rl], AL, ["Departures", (r) => r.flights, true], ["Sold out", (r) => `${r.sold_out}/${r.with_loads}`, true],
        ["An aircraft hour", (r) => (r.profit_per_aircraft_hour == null ? "—" : kWords(r.profit_per_aircraft_hour)), true],
        ["Profit a flight", (r) => kWords(r.profit_per_flight ?? 0), true], ["A week", (r) => weekWords(r.profit_week ?? 0), true]]} />
        : <div className="dim">Nothing yet. A route needs at least {setting("growth_sold_out_min_departures")} captured departures, most of them sold out.</div>}
      <h4 className="gh">Raise fares <span className="note">sold out, but less profit an aircraft hour than the airline's middle route: a higher fare earns more from the same seats · {s.raise_fares.length}</span></h4>
      {s.raise_fares.length ? <Table rows={s.raise_fares} cols={[["Route", rl], AL, ["Departures", (r) => r.flights, true], ["Sold out", (r) => `${r.sold_out}/${r.with_loads}`, true],
        ["An aircraft hour", (r) => (r.profit_per_aircraft_hour == null ? "—" : kWords(r.profit_per_aircraft_hour)), true],
        ["Profit a flight", (r) => kWords(r.profit_per_flight ?? 0), true], ["Economy fare", (r) => (r.economy_fare == null ? "—" : Math.round(r.economy_fare)), true]]} />
        : <div className="dim">Nothing yet.</div>}
      <h4 className="gh">Fix or reduce <span className="note">losing money, economy under {setting("growth_fix_economy_pct")}%, or bottom-quarter profit on a thin margin · {s.fix_or_reduce.length}</span></h4>
      {s.fix_or_reduce.length ? <Table rows={s.fix_or_reduce} cols={[["Route", rl], AL, ["Economy", (r) => pctWords(r.economy), true], ["Profit a flight", (r) => kWords(r.profit_per_flight ?? 0), true],
        ["Why", (r) => r.why]]} />
        : <div className="dim">Nothing to fix.</div>}
      <h4 className="gh">Aircraft losing money after their lease <span className="note">flight profit a day below the lease · {s.aircraft_losing_after_lease.length}</span></h4>
      {s.aircraft_losing_after_lease.length ? <Table<SignalAircraft> rows={s.aircraft_losing_after_lease} cols={[["Aircraft", (r) => <b>{r.registration}</b>], AL, ["Type", (r) => r.type],
        ["After lease a day", (r) => kWords(r.net_day ?? 0), true], ["Routes", (r) => r.routes.join(", ")]]} />
        : <div className="dim">Every aircraft covers its lease.</div>}
      <div className="note">From the nightly capture, last {s.days} days. The full picture for each airline, with charts, is on its own page: tap its scorecard.</div>
    </>
  );
}

/** Without any profit captured: ready for another flight from the load reports, and the routes to reduce from the load
 *  patterns (the old growthBoard's own lists). */
function FromLoads({ rules, ready, patterns, airlines }: { rules: Rules; ready: readonly ReadyRow[]; patterns: readonly Pattern[]; airlines: readonly OurAirline[] }) {
  const al = (id: number) => airlines.find((a) => a.id === id);
  const byAl = airlines.map((a) => ({ a, list: ready.filter((x) => x.route.airline_id === a.id) })).filter((x) => x.list.length);
  const cut = patterns.filter((x) => x.mark === "cut");
  const minDays = Number(rules.input.settings.growth_ready_min_days);
  const window = Number(rules.input.settings.load_window_days);
  return (
    <>
      <h4 className="gh">Ready for another flight <span className="note">95%+ on every departure over at least {minDays} reported days · highest demand first · {ready.length} route{ready.length === 1 ? "" : "s"}</span></h4>
      {!ready.length ? <div className="dim">Nothing yet. A route qualifies after about {minDays} saved daily reports with every departure at 95%+.</div> : (
        <>
          <div className="gsum">{byAl.map((x) => <span className="gchip" key={x.a.id}><AirlineMark color={x.a.color} />{x.a.name} <b>{x.list.length}</b></span>)}</div>
          {byAl.map((x) => (
            <details className="gsec" key={x.a.id}>
              <summary><AirlineMark color={x.a.color} /><b>{x.a.name}</b> <span className="dim">{x.list.length} route{x.list.length === 1 ? "" : "s"} ready · top: {x.list.slice(0, 3).map((r) => r.route.hub + "–" + r.route.dest).join(", ")}</span></summary>
              <div className="tscroll">
                <table className="tbl gtbl">
                  <tbody>
                    <tr><th>Route</th><th>Demand</th><th>Flights a day</th><th>Loads (7 days)</th><th>Flying on</th><th>Add</th></tr>
                    {x.list.map((r) => (
                      <tr key={r.route.id}>
                        <td>{routeLink(x.a.code, r.route.hub, r.route.dest)}</td>
                        <td><span className="stars">{"★".repeat(Math.max(0, r.route.stars))}</span></td>
                        <td>{perDayWords(r.route.round_trips_day)}</td>
                        <td><span className={`pill ${loadClass(r.load.average)} lfc`} title={loadTip(r.load)}>≈{Math.round(r.load.average)}%</span> <span className="dim">{r.load.days} days</span></td>
                        <td className="dim">{r.flyingOn || "—"}</td>
                        <td><b>{r.size ?? ""}</b></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </details>
          ))}
        </>
      )}
      <h4 className="gh">Reduce <span className="note">under 85% on most departures over the last {window} days</span></h4>
      {cut.length ? (
        <div className="tscroll">
          <table className="tbl">
            <tbody>
              <tr><th>Route</th><th>Airline</th><th>Departures seen</th><th>Under 85%</th></tr>
              {cut.map((x) => (
                <tr key={x.route_id}><td>{routeLink(al(x.airline_id)?.code, x.hub, x.dest)}</td><td><AirlineMark color={al(x.airline_id)?.color} />{al(x.airline_id)?.name ?? ""}</td>
                  <td>{x.departures}</td><td>{x.under_85 + x.under_70}</td></tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : <div className="dim">No route is clearly under-performing yet.</div>}
    </>
  );
}
