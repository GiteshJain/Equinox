// Check → Growth (the old growthBoard): what each airline can order now (airline_cards()), main hubs towards their target
// (hub_progress()), the next move of each airline's order rotation with its best options and the buttons that log an
// order (growth_log), the growth lists from the capture (growth_signals(); from the load reports and load patterns when
// no profit was captured), when each order queue runs dry, and how many cities feed each bank. The planning parts are the
// library's (growth), the suggested aircraft size after each route too (growth.suggestedSize, the setting suggested_size);
// the captured figures the database's.
import { Link } from "react-router";
import { growth, type GrowthRoute, type Move, type QueueCell, type ReadinessRow, type Rules } from "@rules";
import { AirlineMark } from "../../ui/AirlineMark";
import { shortType } from "../../ui/aircraftNames";
import { niceDate } from "../../ui/dates";
import { loadClass, loadTip, type Load } from "../routes/model";
import { itemRoute } from "../screens";
import {
  H, MOVE_BUTTONS, MOVES, hubRows, kWords, movePill, pctWords, perDayWords, runsDryWords, soonWords, spendOrder, weekWords, type CheckAirline,
} from "./model";
import type { GrowthLogRow, GrowthRead, HubProgressAirline, Pattern, SignalAircraft, SignalRoute } from "./reads";

export interface NextMoveRow {
  airline: CheckAirline;
  last: GrowthLogRow | null;
  move: Move;
  options: (GrowthRoute & { code: string | null; size: string | null })[];
  canOrder: boolean;
}
export interface QueueRow { airline: CheckAirline; cells: QueueCell[] }
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

export function GrowthBoard(p: {
  rules: Rules;
  airlines: readonly CheckAirline[];
  canOrder: ReadonlyMap<number, string[]>;
  progress: readonly HubProgressAirline[];
  moves: readonly NextMoveRow[];
  signals: GrowthRead;
  ready: readonly ReadyRow[];
  queues: readonly QueueRow[];
  families: readonly string[];
  readiness: readonly ReadinessRow[];
  busy: boolean;
  onLog: (airlineId: number, move: Move) => void;
}) {
  const al = (id: number) => p.airlines.find((a) => a.id === id);
  const name = (id: number) => al(id)?.name ?? "";
  const mark = (id: number) => <AirlineMark color={al(id)?.color} />;
  const hubs = hubRows(p.progress, name);
  const target = p.progress.find((x) => !x.exempt && x.main_hub)?.target ?? p.progress[0]?.target ?? 0;
  const exempt = p.progress.filter((x) => x.exempt).map((x) => name(x.airline_id)).filter(Boolean);
  const orderable = p.airlines.map((a) => ({ a, now: p.canOrder.get(a.id) ?? [] })).filter((x) => x.now.length);
  return (
    <>
      <div className="gptr" data-figure="check: can order now">
        {orderable.length ? orderable.map((x, i) => <span key={x.a.id}>{i ? " " : null}<span className="pill ok">{x.a.name} can order now: {x.now.map(shortType).join(", ")}</span></span>)
          : <span className="dim">No airline can safely order an aircraft yet.</span>}{" "}
        <Link className="link" to="/review">The cash forecast and order dates are on the Review tab →</Link>
      </div>
      <h4 className="gh">Main hubs towards {target} departures a week <span className="note">hubs first: each main hub reaches {target} before another opens, unless the new one is contested · lighter bar = plan cards not yet filed</span></h4>
      <div className="hubprog" data-figure="check: main hubs">
        {hubs.map((x) => (
          <div className="hp" key={x.airline_id}>
            <span className="hpn">{mark(x.airline_id)}<b>{x.hub}</b> <span className="dim">{x.name}</span></span>
            <div className="hpbar"><i style={{ width: x.width }} /><i className="pend" style={{ width: x.pend }} /></div>
            <span className="hpv"><b>{x.departures}</b>{x.planned ? <> <span className="dim">+{x.planned}</span></> : null} / {x.target} <span className="dim">{x.pct}%</span></span>
          </div>
        ))}
      </div>
      <h4 className="gh">Next move for each airline <span className="note">{spendOrder(target, exempt)} · skip a move that has nothing ready · log each order so the rotation moves on</span></h4>
      <div className="tblwrap">
        <table className="tbl gtbl nmv" data-figure="check: next move">
          <tbody>
            <tr><th>Airline</th><th>Last move</th><th>Next</th><th>Best options for that move</th><th>Money</th><th>Log an order as</th></tr>
            {p.moves.map((r) => (
              <tr key={r.airline.id} data-airline={r.airline.code ?? ""}>
                <td><AirlineMark color={r.airline.color} /><b>{r.airline.name}</b></td>
                <td>{r.last ? <>{MOVES[r.last.move as Move] ?? r.last.move} <span className="dim">{niceDate(r.last.logged_on)}</span></> : <span className="dim">—</span>}</td>
                <td><span className={"pill " + movePill(r.move)}>{MOVES[r.move]}</span></td>
                <td>
                  {r.options.length ? r.options.slice(0, 4).map((x) => (
                    <span className="opt" key={x.id}>
                      <Link className="link" to={itemRoute("routes", { airline: x.code, hub: x.hub, dest: x.dest })}>{x.hub}–{x.dest}</Link>
                      <span className="stars">{"★".repeat(Math.max(0, x.stars))}</span>
                      <span className="sz">{x.size ?? ""}</span>
                    </span>
                  )) : <span className="dim">nothing ready</span>}
                  {r.options.length > 4 ? <> <span className="dim">+{r.options.length - 4} more</span></> : null}
                </td>
                <td>{r.canOrder ? <span className="pill ok sm">can order</span> : <span className="dim">not yet</span>}</td>
                <td className="n">
                  <span className="logseg">
                    {growth.CYCLE.map((m) => (
                      <button type="button" key={m} data-gmove={`${r.airline.code}|${m}`} disabled={p.busy} title={`Log an order for ${r.airline.name} as a ${MOVES[m].toLowerCase()} move`}
                        onClick={() => p.onLog(r.airline.id, m)}>{MOVE_BUTTONS[m]}</button>
                    ))}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div data-figure="check: growth lists">
        {p.signals.profit_captured ? <Signals rules={p.rules} s={p.signals} airlines={p.airlines} /> : <FromLoads ready={p.ready} patterns={p.signals.load_patterns} airlines={p.airlines} rules={p.rules} />}
      </div>
      <h4 className="gh">Order queues <span className="note">each airline delivers one A320-family aircraft every 21 hours, one E195 every 15 hours and one A350 every 30 hours · an empty queue is a delivery line standing idle</span></h4>
      <div className="tblwrap">
        <table className="tbl" data-figure="check: order queues">
          <tbody>
            <tr><th>Airline</th>{p.families.map((f) => <th key={f}>{f}</th>)}</tr>
            {p.queues.map((q) => (
              <tr key={q.airline.id}>
                <td><AirlineMark color={q.airline.color} /><b>{q.airline.name}</b></td>
                {q.cells.map((c) => !c.in_fleet ? <td key={c.family} className="dim">not in fleet</td>
                  : !c.count ? <td key={c.family}><span className="pill mute">empty</span></td>
                  : <td key={c.family}><b>{c.count}</b> on order · runs dry {runsDryWords(c.last_ms as number)} UTC {c.warn ? <span className="pill warn">{soonWords(c.hours as number)}</span> : null}</td>)}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <h4 className="gh">Hub readiness <span className="note">how many cities feed each bank · flying now, plus plan cards not yet filed · Malaysia starts long-haul at about 20 cities into the night bank, from India, China and South-East Asia</span></h4>
      <div className="tblwrap">
        <table className="tbl" data-figure="check: hub readiness">
          <tbody>
            <tr><th>Hub</th><th>Bank</th><th>Cities flying</th><th>With planned</th><th>Regions (with planned)</th></tr>
            {p.readiness.map((r) => (
              <tr key={`${r.base_id}|${r.bank}`}>
                <td>{mark(r.airline_id)}<b>{r.airport}</b></td>
                <td>B{r.bank} · {H(r.dep)}</td>
                <td>{r.flying}</td>
                <td><b>{r.with_planned}</b></td>
                <td className="dim">{r.regions.map((c) => `${c.region} ${c.cities}`).join(" · ")}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

/** The growth lists from the capture (the old capSignalsHtml). */
function Signals({ rules, s, airlines }: { rules: Rules; s: GrowthRead; airlines: readonly CheckAirline[] }) {
  const al = (id: number) => airlines.find((a) => a.id === id);
  const AL: [string, (r: { airline_id: number }) => React.ReactNode] = ["Airline", (r) => <><AirlineMark color={al(r.airline_id)?.color} />{al(r.airline_id)?.name ?? ""}</>];
  const rl = (r: SignalRoute) => routeLink(al(r.airline_id)?.code, r.hub, r.dest);
  const setting = (k: string) => String(rules.input.settings[k] ?? "?");
  return (
    <>
      <h4 className="gh">Ready for another flight <span className="note">sold out on most captured departures in the last {s.days} days, and more profit a flight than the airline's middle route · {s.ready_for_another_flight.length}</span></h4>
      {s.ready_for_another_flight.length ? <Table rows={s.ready_for_another_flight} cols={[["Route", rl], AL, ["Departures", (r) => r.flights, true], ["Sold out", (r) => `${r.sold_out}/${r.with_loads}`, true],
        ["Profit a flight", (r) => kWords(r.profit_per_flight ?? 0), true], ["A week", (r) => weekWords(r.profit_week ?? 0), true]]} />
        : <div className="dim">Nothing yet. A route needs at least {setting("growth_sold_out_min_departures")} captured departures, most of them sold out.</div>}
      <h4 className="gh">Raise fares <span className="note">sold out, but less profit a flight than the airline's middle route: a higher fare earns more from the same seats · {s.raise_fares.length}</span></h4>
      {s.raise_fares.length ? <Table rows={s.raise_fares} cols={[["Route", rl], AL, ["Departures", (r) => r.flights, true], ["Sold out", (r) => `${r.sold_out}/${r.with_loads}`, true],
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
      <div className="note">From the nightly capture, last {s.days} days. The full picture for each airline, with charts, is on the Review tab.</div>
    </>
  );
}

/** Without any profit captured: ready for another flight from the load reports, and the routes to reduce from the load
 *  patterns (the old growthBoard's own lists). */
function FromLoads({ rules, ready, patterns, airlines }: { rules: Rules; ready: readonly ReadyRow[]; patterns: readonly Pattern[]; airlines: readonly CheckAirline[] }) {
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
            </details>
          ))}
        </>
      )}
      <h4 className="gh">Reduce <span className="note">under 85% on most departures over the last {window} days</span></h4>
      {cut.length ? (
        <table className="tbl">
          <tbody>
            <tr><th>Route</th><th>Airline</th><th>Departures seen</th><th>Under 85%</th></tr>
            {cut.map((x) => (
              <tr key={x.route_id}><td>{routeLink(al(x.airline_id)?.code, x.hub, x.dest)}</td><td><AirlineMark color={al(x.airline_id)?.color} />{al(x.airline_id)?.name ?? ""}</td>
                <td>{x.departures}</td><td>{x.under_85 + x.under_70}</td></tr>
            ))}
          </tbody>
        </table>
      ) : <div className="dim">No route is clearly under-performing yet.</div>}
    </>
  );
}
