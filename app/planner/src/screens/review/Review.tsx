// Review (decision #18, build pull request 10; spec docs/specs/2026-10-14-review.md): each airline's money, as the old
// planner's Review (its nav button "Review" opens its finance view, renderFinance), from the same data, with the same
// figures and look, every money figure from the database's figures (design §8):
//   - the group today: one row per airline (flight profit, leases and the week-end closing, net), without the old board's
//     group totals (manual §5: each airline is its own business);
//   - the airline cards (airline_cards(), with each airline's sparkline from airline_profit()); choosing one opens its page;
//   - the airline page: the profit chart for the last 14 intervals with its average and the table of reported days
//     (airline_profit()), Cash, next 14 days (cash_forecast()), Route profit with its aircraft and fare changes
//     (route_profit(), aircraft_profit(), fare_changes()), the Fare plan (fare_plan_status());
//   - Manual entry (ManualEntry.tsx): cash and fixed costs for today, the nightly log (cash_log()), loads by hand.
// The boards fold by their titles as Check's do (all folded on arrival, Collapse all and Expand all). Address:
// /planner/review (the first airline's page, as the old Review opens) and /planner/review/<airline code>; with a
// route after it (/review/PA/JFK-ORD, from Home's needs attention) the route profit table opens filtered to that route.
import { useMemo, useState, type ReactNode } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { setting } from "@rules";
import { useNow } from "../../data/clock";
import { queryClient } from "../../data/query";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import type { Change } from "../../data/save";
import { saver } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { niceDate, todayAt } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { FoldBoard, FoldTools } from "../../ui/FoldBoard";
import { showMessage } from "../../ui/messages";
import { itemRoute } from "../screens";
import { BarChart, CostChart, ForecastChart, GroupChart, Scatter, Spark, TailChart } from "./Charts";
import { ManualEntry } from "./ManualEntry";
import {
  BOARDS, MARKS, MARK_ORDER, PERIODS, SORTS, barTip, capturedLine, cardWords, chartIntervals, farePlanAdd, farePlanDrop, fcDay, fcWhat, kk, markCounts, ms, offersFarePlan,
  pc, planWords, routeSearchText, safeWords, sg, shownRoutes, weekWords, type AircraftRow, type BoardKey, type Card, type FareChange, type FarePlanAnswer, type Forecast,
  type Mark, type ProfitAnswer, type RouteProfitAnswer, type RouteSort,
} from "./model";
import { useAircraftProfit, useCashLog, useFareChanges, useFarePlan, useForecast, useProfits, useReviewCards, useRouteProfit } from "./reads";

export interface ReviewAirline { id: number; code: string | null; name: string; color: string | null }

const NOTES: Record<BoardKey, string> = {
  "The group today": "from last night's capture · flight profit is before leases; leases and the week-end closing are this week's scheduled payments, per day",
  "Profit": "profit for each day between reports = change in cash + order payments that day · cash moves on payment days, so read the average",
  "Cash, next 14 days": "",
  "Route profit": "each captured flight's income minus its flight costs (fuel, handling, on-board, landing and air-traffic fees, maintenance), from the bank statement, matched to its loads and fares · before leases and the week-end closing",
  "Fare plan": "fare changes to make in the game · each is spotted in the next capture, with the economy load before and after",
  "Manual entry": "only needed if a night's capture failed · cash, fixed costs and loads normally come from the capture",
};

const firstError = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

/** After a save that changes cash or the fare plan, the figures that build on them are read again. */
export function refreshFigures() {
  for (const k of ["airline_cards", "airline_profit", "cash_forecast", "route_profit"]) void queryClient.invalidateQueries({ queryKey: ["figures", k] });
}

export function Review() {
  const params = useParams();
  const navigate = useNavigate();
  const now = useNow();
  const today = todayAt(now);
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const rulesQ = useRules(w);
  const cardsQ = useReviewCards(w);
  const airlines: ReviewAirline[] = useMemo(() => (airlinesQ.data ?? []).map((a) => ({
    id: a.id, code: a.iata_code, name: a.planner_name ?? a.public_name ?? a.game_name ?? `Airline ${a.game_id}`, color: a.livery_color,
  })), [airlinesQ.data]);
  // each airline by its planner name, as the old Review names it (the captured figures give the public name)
  const named = useMemo(() => new Map(airlines.map((a) => [a.id, a.name])), [airlines]);
  const cards = useMemo(() => (cardsQ.data?.airlines ?? []).map((c) => ({ ...c, name: named.get(c.airline_id) ?? c.name })), [cardsQ.data, named]);
  const groupRows = useMemo(() => (cardsQ.data?.group_today ?? []).map((r) => ({ ...r, name: named.get(r.airline_id) ?? r.name })), [cardsQ.data, named]);
  const profitsQ = useProfits(cards.map((c) => c.airline_id));
  const profitOf = new Map<number, ProfitAnswer>();
  profitsQ.forEach((q, i) => { const c = cards[i]; if (c && q.data) profitOf.set(c.airline_id, q.data); });

  const [code, routeKey] = (params["*"] ?? "").split("/").filter(Boolean);
  const colorOf = (id: number) => airlines.find((a) => a.id === id)?.color ?? null;
  const sel = cards.find((c) => c.code === code) ?? cards[0];
  const selId = sel?.airline_id;

  const forecastQ = useForecast(selId);
  const [days, setDays] = useState(7);
  const routeQ = useRouteProfit(selId, days);
  const aircraftQ = useAircraftProfit(selId, days);
  const changesQ = useFareChanges(selId);
  const planQ = useFarePlan(selId);
  const logQ = useCashLog(w);

  const [folded, setFolded] = useState<ReadonlySet<BoardKey>>(() => new Set(BOARDS));
  const [busy, setBusy] = useState(false);
  const toggle = (k: BoardKey) => setFolded((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });

  async function save(changes: Change[]) {
    if (!changes.length) return;
    setBusy(true);
    try {
      const res = await saver.save(changes);
      if (res.status === "saved") refreshFigures();
      return res;
    } finally {
      setBusy(false);
    }
  }

  const rules = rulesQ.data?.rules;
  const selProfit = selId != null ? profitOf.get(selId) : undefined;
  const ready = !!(cardsQ.data && airlinesQ.data && rules && sel && selProfit && profitsQ.every((q) => q.data) && forecastQ.data && routeQ.data && !routeQ.isFetching
    && aircraftQ.data && !aircraftQ.isFetching && changesQ.data && planQ.data && logQ.data);
  const loadError = firstError(world, airlinesQ, rulesQ, cardsQ, ...profitsQ, forecastQ, routeQ, aircraftQ, changesQ, planQ, logQ);
  const board = (k: BoardKey, children: ReactNode, opts: { title?: ReactNode; note?: ReactNode; figure?: string } = {}) => (
    <FoldBoard key={k} k={k} title={opts.title} note={opts.note ?? NOTES[k]} folded={folded.has(k)} onToggle={() => toggle(k)} figure={opts.figure}>{children}</FoldBoard>
  );
  const cushion = (fc: Forecast | undefined) => (fc?.cushion != null ? fc.cushion : rules && selId != null ? Number(setting(rules, "order_cushion", selId) ?? 0) / 1_000_000 : 0);
  const view = "/review" + (code ? "/" + code : "") + (routeKey ? "/" + routeKey : "");

  return (
    <main className="view finance" data-screen="review" data-review-ready={ready ? "yes" : "no"} data-review-view={view} data-airline={sel?.code ?? ""}>
      <div className="vh"><h1>Review</h1><p>How the group and each airline are doing: cash, the 14-day forecast, and profit by route and by aircraft. Manual entry, for a failed capture, is at the bottom.</p></div>
      {loadError ? <ErrorBox error={loadError} /> : null}
      {!ready && !loadError ? <div className="empty">Loading…</div> : null}
      <FoldTools onCollapse={() => setFolded(new Set(BOARDS))} onExpand={() => setFolded(new Set())} />
      {cardsQ.data && rules && sel ? (
        <>
          {cardsQ.data.group_today_shown ? board("The group today", <GroupChart rows={groupRows} />, { figure: "review: the group today" }) : null}
          <div className="fgrid" data-figure="review: cards">
            {cards.map((c) => <AirlineCard key={c.airline_id} c={c} on={c.airline_id === selId} color={colorOf(c.airline_id)} days={profitOf.get(c.airline_id)?.days ?? []}
              onPick={() => navigate("/review/" + encodeURIComponent(c.code ?? String(c.airline_id)))} />)}
          </div>
          {selProfit ? board("Profit", <ProfitBody p={selProfit} />, {
            title: <><AirlineMark color={colorOf(sel.airline_id)} />{sel.name}</>, figure: `review ${sel.name}: profit` }) : null}
          {forecastQ.data ? board("Cash, next 14 days", <ForecastBody fc={forecastQ.data} cushion={cushion(forecastQ.data)} airline={sel.name} />, {
            note: `captured cash + flight profit from the last day's bank statement − every scheduled lease payment and week-end closing (repeated weekly beyond what the game lists) · an order is "safe" when ${cushion(forecastQ.data).toFixed(1)}M stays in hand at the lowest point afterwards, counting its own weekly lease from 7 days after it arrives (taken as the day it's ordered)`,
            figure: `review ${sel.name}: Cash, next 14 days` }) : null}
          {routeQ.data && aircraftQ.data && changesQ.data && planQ.data ? board("Route profit", (
            <RouteProfitBody key={sel.airline_id + "|" + (routeKey ?? "")} airline={sel} r={routeQ.data} aircraft={aircraftQ.data} changes={changesQ.data} plan={planQ.data}
              days={days} onDays={setDays} busy={busy} initialQuery={routeKey ? routeKey.replace("-", " ") : ""}
              city={(c) => rules.airports.get(c)?.city ?? ""} soldOutMin={String(setting(rules, "growth_sold_out_min_departures", sel.airline_id) ?? "")}
              raisePct={Number(setting(rules, "fare_plan_raise_pct", sel.airline_id) ?? NaN)}
              onAdd={(row) => {
                const pct = Number(setting(rules, "fare_plan_raise_pct", sel.airline_id));
                const fare = planQ.data.fares.find((f) => f.route_id === row.route_id)?.fare;
                const ch = row.route_id != null && w !== undefined ? farePlanAdd({ worldId: w, airlineId: sel.airline_id, routeId: row.route_id, fare, pct, today, nowMs: Date.now() }) : null;
                if (!ch) { showMessage("No captured fare for this route yet."); return; }
                void save([ch]).then((res) => { if (res?.status === "saved") showMessage(`${row.hub}–${row.dest}: +${pct}% economy added to the fare plan.`); });
              }} />
          ), { figure: `review ${sel.name}: Route profit` }) : null}
          {planQ.data ? board("Fare plan", <FarePlanBody airline={sel.name} plan={planQ.data} busy={busy} onDrop={(p) => void save([farePlanDrop(p)])} />,
            { figure: `review ${sel.name}: Fare plan` }) : null}
          {logQ.data ? board("Manual entry", <ManualEntry worldId={w} rules={rules} log={{ ...logQ.data, airlines: logQ.data.airlines.map((a) => ({ ...a, name: named.get(a.airline_id) ?? a.name })) }} airlines={airlines} busy={busy} now={now} onSave={save} />,
            { figure: "review: manual entry" }) : null}
        </>
      ) : null}
    </main>
  );
}

function AirlineCard({ c, on, color, days, onPick }: { c: Card; on: boolean; color: string | null; days: ProfitAnswer["days"]; onPick: () => void }) {
  const x = cardWords(c);
  return (
    <button type="button" className={"fcard" + (on ? " on" : "")} data-final={c.code ?? ""} data-figure={`review ${c.name}: card`} onClick={onPick}>
      <div className="fch"><AirlineMark color={color} /><b>{c.name}</b><Spark days={days} /></div>
      <div className={"fbig" + (x.bigNeg ? " neg" : "")}>{x.big}{c.profit_day != null ? <span className="fu"> a day</span> : null}</div>
      <div className="fsub">{x.sub}</div>
      <dl>
        <dt>Per aircraft</dt><dd>{x.perAircraft}</dd>
        <dt>Return on fleet</dt><dd>{x.returnOnFleet}</dd>
        <dt>An aircraft pays back in</dt><dd>{x.payback}</dd>
        <dt>Funds a new aircraft every</dt><dd>{x.fundsEvery}</dd>
        <dt>Fleet</dt><dd>{x.fleet}{x.fleetAdded ? <> <span className="pos">{x.fleetAdded}</span></> : null}{x.onOrder}</dd>
        <dt>Flights a day</dt><dd>{x.flights}{x.flightsAdded ? <> <span className="pos">{x.flightsAdded}</span></> : null}</dd>
        <dt>Average load, 7 days</dt><dd>{x.load}</dd>
        <dt>Next order</dt><dd data-figure="review: next order per airline">
          {x.next.kind === "pill" ? <span className="pill ok sm">{x.next.text}</span> : x.next.kind === "dim" ? <span className="dim">{x.next.text}</span> : x.next.text}
        </dd>
      </dl>
    </button>
  );
}

/** The profit chart (the last 14 intervals, with the 7-day average) and the table of reported days, newest first. */
function ProfitBody({ p }: { p: ProfitAnswer }) {
  const iv = p.days;
  return (
    <>
      <BarChart pts={chartIntervals(iv).map((x) => ({ x: x.date, y: x.profit_day, tip: barTip(x, (d) => niceDate(d)) }))} avg={p.profit_day} figure="review: profit chart" />
      {iv.length ? (
        <div className="tscroll">
          <table className="tbl ftbl" data-figure="review: profit by day">
            <tbody>
              <tr><th>Date</th><th>Cash</th><th>Change</th><th>Order payments</th><th>Profit a day</th><th>Aircraft flying</th><th>Flights</th><th>Average load</th><th>Per aircraft</th></tr>
              {iv.slice().reverse().map((x) => (
                <tr key={x.date}>
                  <td><b>{niceDate(x.date)}</b></td>
                  <td>{x.cash.toFixed(2)}M</td>
                  <td className={x.change < 0 ? "neg" : "pos"}>{sg(x.change)}</td>
                  <td>{x.order_payments ? x.order_payments.toFixed(2) + "M" : <span className="dim">—</span>}</td>
                  <td><b className={x.profit_day < 0 ? "neg" : ""}>{sg(x.profit_day)}</b></td>
                  <td>{x.aircraft}</td>
                  <td>{x.flights}</td>
                  <td>{x.load == null ? <span className="dim">—</span> : "≈" + Math.round(x.load) + "%"}</td>
                  <td>{x.per_aircraft_day != null ? kk(x.per_aircraft_day) : ""}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
    </>
  );
}

/** Cash, next 14 days: what's missing, or the chart, its facts and what's safe to order. */
function ForecastBody({ fc, cushion, airline }: { fc: Forecast; cushion: number; airline: string }) {
  if (fc.status === "no capture") return <div className="dim">Needs a capture for {airline}: balance sheet, events and bank statement.</div>;
  if (fc.status !== "ok") return <div className="dim">Cash {(fc.cash ?? 0).toFixed(2)}M captured. The forecast also needs {fc.missing}.</div>;
  const t0 = ms(fc.cash_at ?? ""), ops = fc.flight_profit_day ?? 0, low = fc.lowest;
  return (
    <>
      <ForecastChart fc={fc} cushion={cushion} airline={airline} />
      <div className="fcfacts" data-figure="review: forecast facts">
        <span>Cash at capture <b>{(fc.cash ?? 0).toFixed(2)}M</b> <span className="dim">({fcDay(t0)} {new Date(t0).toISOString().slice(11, 16)} UTC)</span></span>
        <span>Flight profit <b>{ops >= 0 ? "+" : "−"}{Math.abs(ops).toFixed(2)}M a day</b> <span className="dim">before leases · {Math.round((fc.profit_per_flight ?? 0) * 1000)}k a flight × {(fc.flights_per_day ?? 0).toFixed(0)} flights</span></span>
        <span>Payments, next 7 days <b>{(fc.payments_next_7_days ?? 0).toFixed(2)}M</b></span>
        {low ? <span>Lowest point <b className={low.balance < cushion ? "neg" : ""}>{low.balance.toFixed(2)}M</b> on {fcDay(low.at)}{low.payment ? `, after ${fcWhat(low.payment.what)}` : ""}</span> : null}
      </div>
      <div className="fcsafe" data-figure="review: safe to order">
        <span className="dim">Safe to order:</span>{" "}
        {(fc.types ?? []).map((t, i) => { const s = safeWords(t); return <span key={t.aircraft_type_id}>{i ? " " : ""}<span className={`pill ${s.kind} sm`}>{s.text}</span></span>; })}
      </div>
    </>
  );
}

/** Route profit, its aircraft and the fare changes, for the period picked. */
function RouteProfitBody({ airline, r, aircraft, changes, plan, days, onDays, busy, initialQuery, city, soldOutMin, raisePct, onAdd }: {
  airline: Card;
  r: RouteProfitAnswer;
  aircraft: AircraftRow[];
  changes: FareChange[];
  plan: FarePlanAnswer;
  days: number;
  onDays: (d: number) => void;
  busy: boolean;
  initialQuery: string;
  city: (code: string) => string;
  soldOutMin: string;
  raisePct: number;
  onAdd: (row: RouteProfitAnswer["routes"][number]) => void;
}) {
  const [mark, setMark] = useState<Mark | "">("");
  const [sort, setSort] = useState<RouteSort>("pwk");
  const [q, setQ] = useState(initialQuery);
  const [tailsOpen, setTailsOpen] = useState(false);
  if (!r.flights) return <div className="dim">Fills in once {airline.name}'s bank statement has been captured.</div>;
  const cnt = markCounts(r.routes);
  const shown = shownRoutes(r.routes, mark, sort);
  const query = q.trim().toLowerCase();
  const k = (v: number) => (v >= 0 ? "+" : "−") + Math.round(Math.abs(v) * 1000) + "k";
  return (
    <>
      <div className="rpf">
        <span className="rpl">Period</span>
        {PERIODS.map((d) => <button type="button" key={d} className={"mf" + (days === d ? " on" : "")} data-rpdays={d} onClick={() => onDays(d)}>{d === 1 ? "last day" : d + " days"}</button>)}
        <span className="rpl">Show</span>
        <button type="button" className={"mf" + (!mark ? " on" : "")} data-rpsig="" onClick={() => setMark("")}>All {r.routes.length}</button>
        {MARK_ORDER.filter((x) => cnt[x]).map((x) => (
          <button type="button" key={x} className={"mf" + (mark === x ? " on" : "")} data-rpsig={x} onClick={() => setMark(x)}>
            <i className="sd" style={{ background: MARKS[x].color }} />{MARKS[x].label} {cnt[x]}
          </button>
        ))}
        <span className="rpl">Sort</span>
        {SORTS.map(([x, l]) => <button type="button" key={x} className={"mf" + (sort === x ? " on" : "")} data-rpsort={x} onClick={() => setSort(x)}>{l}</button>)}
        <input id="rp-q" className="rpq" placeholder="Filter routes, e.g. JFK or Paris" value={q} onChange={(e) => setQ(e.target.value)} />
      </div>
      <div className="note" style={{ margin: "4px 0 10px" }}>{capturedLine(r, soldOutMin)}</div>
      <div className="rpcharts">
        <div className="rpc"><div className="rpct">Load against profit <span className="dim">· bubble size = flights a week · colour = signal</span></div><Scatter routes={r.routes} /></div>
        <div className="rpc"><div className="rpct">An average flight <span className="dim">· income and where it goes</span></div><CostChart avg={r.average_flight} /></div>
      </div>
      <div className="tscroll">
        <table className="tbl rptbl" id="rp-table" data-figure="review: route profit table">
          <tbody>
            <tr><th>Route</th><th className="num">Flights</th><th className="num">Profit a flight</th><th className="num">Margin</th><th className="num">A week</th><th className="num">Economy</th><th className="num">Sold out</th><th className="num">Business</th><th className="num">Cargo</th><th className="num">Economy fare</th><th>Signal</th></tr>
            {shown.map((x) => {
              const txt = routeSearchText(x, city);
              return (
                <tr key={`${x.hub}-${x.dest}`} data-rprow={txt} style={query && !txt.includes(query) ? { display: "none" } : undefined}>
                  <td><Link className="link" to={itemRoute("routes", { airline: airline.code, hub: x.hub, dest: x.dest })}><b>{x.hub}–{x.dest}</b></Link></td>
                  <td className="num">{x.flights}</td>
                  <td className={"num" + (x.profit_per_flight < 0 ? " neg" : "")}>{k(x.profit_per_flight)}</td>
                  <td className="num">{x.margin == null ? "—" : Math.round(x.margin * 100) + "%"}</td>
                  <td className="num">{weekWords(x)}</td>
                  <td className="num">{pc(x.economy)}</td>
                  <td className="num">{x.with_loads ? x.sold_out + "/" + x.with_loads : "—"}</td>
                  <td className="num">{pc(x.business)}</td>
                  <td className="num">{pc(x.cargo)}</td>
                  <td className="num">{x.economy_fare == null ? "—" : Math.round(x.economy_fare)}</td>
                  <td>
                    <span className={`pill ${MARKS[x.mark].cls} sm`} title={x.why}>{MARKS[x.mark].label}</span>
                    {offersFarePlan(x, plan.plan) ? <> <button type="button" className="link sm" data-fareadd={`${x.hub}-${x.dest}`} disabled={busy}
                      title={`Plan a ${raisePct}% economy fare rise for this route`} onClick={() => onAdd(x)}>+ fare plan</button></> : null}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {shown.length ? null : <div className="dim">No routes with that signal.</div>}
      {aircraft.length ? (
        <>
          <h4 className="gh">Aircraft <span className="note">flight profit a day (its average flight × its scheduled flights) less its lease</span></h4>
          <TailChart rows={aircraft} />
          <details className="gsub" open={tailsOpen} onToggle={(e) => setTailsOpen((e.target as HTMLDetailsElement).open)}>
            <summary className="dim" data-det="rptails">Aircraft table</summary>
            <div className="tscroll">
              <table className="tbl rptbl" data-figure="review: aircraft table">
                <tbody>
                  <tr><th>Aircraft</th><th>Type</th><th className="num">Flights</th><th className="num">Flight profit a day</th><th className="num">Lease a day</th><th className="num">After lease</th><th>Routes</th></tr>
                  {aircraft.map((t) => (
                    <tr key={t.registration}>
                      <td><b>{t.registration}</b></td>
                      <td className="dim">{t.type}</td>
                      <td className="num">{t.flights}</td>
                      <td className="num">{k(t.flight_profit_day)}</td>
                      <td className="num">{t.lease_day == null ? "—" : k(-t.lease_day)}</td>
                      <td className={"num" + (t.net_day != null && t.net_day < 0 ? " neg" : "")}><b>{t.net_day == null ? "—" : k(t.net_day)}</b></td>
                      <td className="dim">{t.routes.join(", ")}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </details>
        </>
      ) : null}
      <h4 className="gh">Fare changes <span className="note">spotted in the captured economy fares, with the load the day before and after</span></h4>
      {changes.length ? (
        <div className="tscroll">
          <table className="tbl rptbl" data-figure="review: fare changes">
            <tbody>
              <tr><th>Route</th><th>From</th><th className="num">Economy fare</th><th className="num">Load before → after</th></tr>
              {changes.slice(0, 12).map((c, i) => (
                <tr key={i}><td><b>{c.origin}–{c.dest}</b></td><td>{niceDate(c.date)}</td><td className="num">{Math.round(c.fare_before)} → {Math.round(c.fare_after)}</td>
                  <td className="num">{pc(c.economy_before)} → {pc(c.economy_after)}</td></tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : <div className="dim">None yet. Change a fare in the game and it appears here after the next capture, with the load before and after.</div>}
    </>
  );
}

/** The fare plan: each change still planned, whether the captures show it yet, and remove. */
function FarePlanBody({ airline, plan, busy, onDrop }: { airline: string; plan: FarePlanAnswer; busy: boolean; onDrop: (p: FarePlanAnswer["plan"][number]) => void }) {
  if (!plan.plan.length) {
    return <div className="dim">Nothing planned for {airline}. Add a route with “+ fare plan” in the route profit table above (on routes that sell out), or ask Claude to propose changes.</div>;
  }
  return (
    <div className="tscroll">
      <table className="tbl rptbl" data-figure="review: fare plan table">
        <tbody>
          <tr><th>Route</th><th>Class</th><th className="num">Change</th><th className="num">Fare then → target</th><th className="num">Fare now</th><th>Status</th><th className="num">Load before → after</th><th>Why</th><th></th></tr>
          {plan.plan.map((p) => {
            const x = planWords(p, (d) => niceDate(d));
            return (
              <tr key={p.id} data-fareplan={p.id}>
                <td><b>{x.route}</b></td><td>{x.cls}</td><td className="num">{x.change}</td><td className="num">{x.fares}</td><td className="num">{x.now}</td>
                <td><span className={`pill ${x.status.kind} sm`}>{x.status.text}</span></td><td className="num">{x.loads}</td><td className="dim">{x.why}</td>
                <td><button type="button" className="link" data-faredel={p.id} disabled={busy} title="Remove from the plan" onClick={() => onDrop(p)}>remove</button></td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
