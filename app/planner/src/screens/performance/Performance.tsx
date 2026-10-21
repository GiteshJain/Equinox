// Performance (spec docs/specs/2026-10-20-today-performance-systems.md): "how are we doing, and why?". Review's screen
// until 20 Oct (decision #18, build pull request 10, spec docs/specs/2026-10-14-review.md), with Check's growth boards and
// daily load report; every money figure from the database's figures (design §8). Its boards are open on arrival, the
// most important first (Collapse all and Expand all fold them).
//   - The group (/planner/performance): the scorecards, one per airline (Review's cards, airline_cards(), with each
//     airline's sparkline from airline_profit(), and the fleet, flights a day and average load against the same day last
//     week from the daily history, airline_days, with an arrow); tap one to open the airline. Then the group today (each
//     airline's flight profit, leases and week-end closing, net; no group totals, manual §5), the growth signals (ready
//     for another flight, raise fares, fix or reduce, aircraft losing money after their lease: growth_signals()), the
//     main hubs towards 750 (hub_progress(), with hub readiness, the library's growth.hubReadiness, folded into each line)
//     and Flights by day (Check's daily load report, renamed; its day in the address, ?day=).
//   - The airline (/planner/performance/<code>): its scorecard, then Review's page: the profit chart for the last 14
//     intervals with its average and the table of reported days (airline_profit()), Cash, next 14 days (cash_forecast()),
//     Route profit with its aircraft and fare changes (route_profit(), aircraft_profit(), fare_changes()) and the Fare
//     plan (fare_plan_status()). With a route after it (/performance/PA/JFK-ORD, from Today's needs attention) the route
//     profit table opens filtered to that route.
// Manual entry moved to Systems. The saves here, + fare plan and remove, are one planner_save() call each.
import { useMemo, useState, type ReactNode } from "react";
import { Link, useLocation, useNavigate, useParams } from "react-router";
import { game, growth, loadReport, setting } from "@rules";
import { ourAirlines, type OurAirline } from "../../data/airlines";
import { useNow } from "../../data/clock";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import type { Change } from "../../data/save";
import { saver } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { shortType } from "../../ui/aircraftNames";
import { niceDate, todayAt } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { FoldBoard, FoldTools } from "../../ui/FoldBoard";
import { showMessage } from "../../ui/messages";
import { routeOf } from "../routes/model";
import { useAirports, useAllRoutes, useLoads, useMarkets } from "../routes/reads";
import { itemRoute } from "../screens";
import { rulesLegs, typeName, type PlanLegRow } from "../tails/model";
import { useLaunches, usePlanCards, usePlanLegs, useTailsAircraft } from "../tails/reads";
import { BarChart, CostChart, ForecastChart, GroupChart, Scatter, Spark, TailChart } from "./Charts";
import { daySummary, loadKey, loadsByFlight, moveDay, parseDay, utcToday } from "./flights";
import { FlightsByDay } from "./FlightsByDay";
import { GrowthSignals, MainHubs, type ReadyRow } from "./Growth";
import {
  BOARDS, GROUP_BOARDS, MARKS, MARK_ORDER, PERIODS, SORTS, barTip, capturedLine, cardWords, chartIntervals, farePlanAdd, farePlanDrop, fcDay, fcWhat, historyFrom, kk, markCounts, ms,
  offersFarePlan, pc, planWords, routeSearchText, safeWords, sg, shownRoutes, weekOnWeek, weekWords, type AircraftRow, type BoardKey, type Card, type FareChange, type FarePlanAnswer,
  type Forecast, type GroupBoardKey, type Mark, type ProfitAnswer, type RouteProfitAnswer, type RouteSort, type WeekKey, type WeekOnWeek,
} from "./model";
import {
  refreshFigures, useAircraftProfit, useAirlineDays, useDayLoads, useFareChanges, useFarePlan, useForecast, useGrowthSignals, useHandLoads, useHubProgress, useProfits,
  useReviewCards, useRouteProfit,
} from "./reads";

const NOTES: Record<BoardKey | GroupBoardKey, string> = {
  "The group today": "from last night's capture · flight profit is before leases; leases and the week-end closing are this week's scheduled payments, per day",
  "Growth signals": "where each airline should grow next, and what to trim · from the nightly capture",
  "Main hubs": "",
  "Flights by day": "every flight flown, from the nightly capture, with loads by class · if a capture failed, enter loads in Systems under Manual entry",
  "Profit": "profit for each day between reports = change in cash + order payments that day · cash moves on payment days, so read the average",
  "Cash, next 14 days": "",
  "Route profit": "each captured flight's income minus its flight costs (fuel, handling, on-board, landing and air-traffic fees, maintenance), from the bank statement, matched to its loads and fares · before leases and the week-end closing",
  "Fare plan": "fare changes to make in the game · each is spotted in the next capture, with the economy load before and after",
};

const firstError = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

export function Performance() {
  const params = useParams();
  const loc = useLocation();
  const navigate = useNavigate();
  const now = useNow();
  const today = todayAt(now);
  const utcDay = utcToday(now);
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const rulesQ = useRules(w);
  const cardsQ = useReviewCards(w);
  const daysQ = useAirlineDays(w, historyFrom(utcDay), utcDay);
  const airlines: OurAirline[] = useMemo(() => ourAirlines(airlinesQ.data), [airlinesQ.data]);
  // each airline by its planner name, as the old Review names it (the captured figures give the public name)
  const named = useMemo(() => new Map(airlines.map((a) => [a.id, a.name])), [airlines]);
  const cards = useMemo(() => (cardsQ.data?.airlines ?? []).map((c) => ({ ...c, name: named.get(c.airline_id) ?? c.name })), [cardsQ.data, named]);
  const groupRows = useMemo(() => (cardsQ.data?.group_today ?? []).map((r) => ({ ...r, name: named.get(r.airline_id) ?? r.name })), [cardsQ.data, named]);
  const profitsQ = useProfits(cards.map((c) => c.airline_id));
  const profitOf = new Map<number, ProfitAnswer>();
  profitsQ.forEach((q, i) => { const c = cards[i]; if (c && q.data) profitOf.set(c.airline_id, q.data); });
  const wowOf = useMemo(() => new Map(cards.map((c) => [c.airline_id, weekOnWeek(daysQ.data ?? [], c.airline_id, utcDay)])), [cards, daysQ.data, utcDay]);

  const [code, routeKey] = (params["*"] ?? "").split("/").filter(Boolean);
  const colorOf = (id: number) => airlines.find((a) => a.id === id)?.color ?? null;
  const sel = code ? cards.find((c) => c.code === code) : undefined;
  const selId = sel?.airline_id;
  const isAirline = !!code;

  // ---------- the airline's page
  const forecastQ = useForecast(selId);
  const [days, setDays] = useState(7);
  const routeQ = useRouteProfit(selId, days);
  const aircraftQ = useAircraftProfit(selId, days);
  const changesQ = useFareChanges(selId);
  const planQ = useFarePlan(selId);

  // ---------- the group's boards
  const group = !isAirline ? w : undefined;
  const signalsQ = useGrowthSignals(group);
  const progressQ = useHubProgress(group);
  const routesQ = useAllRoutes(group);
  const loadsQ = useLoads(group);
  const marketsQ = useMarkets(group);
  const tailsQ = useTailsAircraft(group);
  const planCardsQ = usePlanCards(group);
  const planLegsQ = usePlanLegs(group);
  const launchesQ = useLaunches(group);
  const cardCodes = useMemo(() => [...new Set((planLegsQ.data ?? []).flatMap((l) => [l.origin_code, l.dest_code]))], [planLegsQ.data]);
  const airportsQ = useAirports(group, cardCodes);
  const day = parseDay(loc.search, utcDay);
  // the old planner held the last 9 days of captured loads (game_loads since utcDay(-9)); older days show none, as there
  const captured = Math.round((Date.parse(utcDay) - Date.parse(day)) / 86_400_000) <= 9;
  const dayLoadsQ = useDayLoads(group, day, captured);
  const handQ = useHandLoads(group, day);

  const allFolds: readonly (BoardKey | GroupBoardKey)[] = [...GROUP_BOARDS, ...BOARDS];
  const [folded, setFolded] = useState<ReadonlySet<BoardKey | GroupBoardKey>>(() => new Set());
  const [busy, setBusy] = useState(false);
  const toggle = (k: BoardKey | GroupBoardKey) => setFolded((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });

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

  // the growth lists from the load reports (shown when no profit was captured) and the hubs' readiness
  const growthParts = useMemo(() => {
    if (isAirline || !rules || !routesQ.data || !loadsQ.data || !marketsQ.data || !tailsQ.data || !planCardsQ.data || !planLegsQ.data) return null;
    const markets = new Map(marketsQ.data.map((m) => [m.id, m]));
    const routes = routesQ.data.map((r) => routeOf(r, markets));
    const loads = loadsQ.data.routes.map((x) => ({ ...x, departures: Number(x.departures), full: Number(x.full), days: Number(x.days) }));
    const typesOn = new Map<number, string[]>();
    for (const f of game.frequencies(rules, null)) {
      const ac = f.leg1?.aircraft_id ?? f.leg2?.aircraft_id ?? null;
      const t = ac == null ? "" : shortType(typeName(rules, rules.aircraft.get(ac)?.aircraft_type_id));
      if (t && !(typesOn.get(f.route_id) ?? []).includes(t)) typesOn.set(f.route_id, [...(typesOn.get(f.route_id) ?? []), t]);
    }
    const loadOf = new Map(loadsQ.data.routes.map((x) => [x.route_id, x]));
    const ready: ReadyRow[] = growth.readyFromLoads(rules, routes.map((r) => ({ id: r.id, airline_id: r.airline_id, hub: r.hub, dest: r.dest, stars: r.stars, dist: r.dist })), loads)
      .map((r) => ({ route: r, load: loadOf.get(r.id) as ReadyRow["load"], flyingOn: (typesOn.get(r.id) ?? []).join(", "),
        size: growth.suggestedSize(rules, r.airline_id, "freq", r) }));
    // the plan cards of aircraft not yet in service feed the banks they're planned into
    const statusOf = new Map(tailsQ.data.map((a) => [a.id, a.status]));
    const cardOf = new Map(planCardsQ.data.map((c) => [c.id, c.aircraft_id]));
    const legsOf = new Map<number, PlanLegRow[]>();
    for (const l of planLegsQ.data) {
      const a = cardOf.get(l.plan_card_id);
      if (a != null) legsOf.set(a, [...(legsOf.get(a) ?? []), l]);
    }
    const planned = [...legsOf].filter(([id]) => statusOf.get(id) !== "active")
      .flatMap(([, ls]) => ls.map((l) => ({ from: l.origin_code, to: l.dest_code, dep_utc_min: l.dep_utc_min, block_min: l.block_min })));
    const regions = new Map((airportsQ.data ?? []).map((x) => [x.code, x.region ?? null]));
    return { ready, readiness: growth.hubReadiness(rules, planned, regions, rulesLegs(rules)) };
  }, [isAirline, rules, routesQ.data, loadsQ.data, marketsQ.data, tailsQ.data, planCardsQ.data, planLegsQ.data, airportsQ.data]);

  // Flights by day
  const flights = useMemo(() => (rules && launchesQ.data ? loadReport.flightsOn(rules, day, launchesQ.data) : []), [rules, launchesQ.data, day]);
  const loadsMap = useMemo(() => loadsByFlight(captured ? dayLoadsQ.data ?? [] : [], day), [captured, dayLoadsQ.data, day]);
  const loadOfFlight = (f: { airline_id: number; no: number }) => loadsMap.get(loadKey(airlines.find((a) => a.id === f.airline_id)?.name ?? "", f.no));
  const summary = daySummary(flights, loadOfFlight, handQ.data);
  const goDay = (n: number) => {
    const d = moveDay(day, n);
    const s = new URLSearchParams(loc.search);
    if (d === utcDay) s.delete("day");
    else s.set("day", d);
    const q = s.toString();
    navigate("/performance" + (q ? "?" + q : ""));
  };
  const dayReady = (!captured || !!dayLoadsQ.data) && !!handQ.data && !dayLoadsQ.isFetching && !handQ.isFetching;

  const selProfit = selId != null ? profitOf.get(selId) : undefined;
  const common = !!(cardsQ.data && airlinesQ.data && rules && profitsQ.every((q) => q.data) && daysQ.data);
  const airlineReady = !!(sel && selProfit && forecastQ.data && routeQ.data && !routeQ.isFetching && aircraftQ.data && !aircraftQ.isFetching && changesQ.data && planQ.data);
  const groupReady = !!(signalsQ.data && progressQ.data && growthParts && (!cardCodes.length || airportsQ.data) && launchesQ.data && dayReady);
  const ready = common && (isAirline ? airlineReady : groupReady);
  const loadError = firstError(world, airlinesQ, rulesQ, cardsQ, daysQ, ...profitsQ,
    ...(isAirline ? [forecastQ, routeQ, aircraftQ, changesQ, planQ] : [signalsQ, progressQ, routesQ, loadsQ, marketsQ, tailsQ, planCardsQ, planLegsQ, launchesQ, airportsQ, dayLoadsQ, handQ]));
  const board = (k: BoardKey | GroupBoardKey, children: ReactNode, opts: { title?: ReactNode; note?: ReactNode; figure?: string } = {}) => (
    <FoldBoard key={k} k={k} title={opts.title} note={opts.note ?? NOTES[k]} folded={folded.has(k)} onToggle={() => toggle(k)} figure={opts.figure}>{children}</FoldBoard>
  );
  const cushion = (fc: Forecast | undefined) => (fc?.cushion != null ? fc.cushion : rules && selId != null ? Number(setting(rules, "order_cushion", selId) ?? 0) / 1_000_000 : 0);
  const view = "/performance" + (code ? "/" + code : "") + (routeKey ? "/" + routeKey : "");
  const target = (progressQ.data ?? []).find((x) => !x.exempt && x.main_hub)?.target ?? progressQ.data?.[0]?.target ?? 750;
  const exempt = (progressQ.data ?? []).filter((x) => x.exempt).map((x) => named.get(x.airline_id)).filter(Boolean);
  const card = (c: Card, on: boolean) => (
    <Scorecard key={c.airline_id} c={c} on={on} color={colorOf(c.airline_id)} days={profitOf.get(c.airline_id)?.days ?? []} wow={wowOf.get(c.airline_id)}
      onPick={() => navigate(itemRoute("performance", { airline: c.code ?? String(c.airline_id) }))} />
  );

  return (
    <main className="view finance performance" data-screen="performance" data-performance-ready={ready ? "yes" : "no"} data-performance-view={view}
      data-airline={sel?.code ?? ""} data-day={isAirline ? "" : day}>
      <div className="vh">
        <h1>{sel ? <>{sel.name}</> : "Performance"}</h1>
        <p>{sel ? "How it's doing, and why: profit, cash for the next 14 days, route profit, aircraft, fare changes and the fare plan."
          : "How each airline is doing, and why: the scorecards against last week, the growth signals, the main hubs and the flights by day."}</p>
      </div>
      {loadError ? <ErrorBox error={loadError} /> : null}
      {!ready && !loadError ? <div className="empty">Loading…</div> : null}
      {isAirline && cardsQ.data && !sel ? <div className="empty">There's no airline {code} in the planner. <Link className="link" to="/performance">All airlines</Link></div> : null}
      {cardsQ.data && rules ? (sel ? (
        <>
          <div className="perfnav" data-airlines>
            <Link className="link" to="/performance" data-back>‹ All airlines</Link>
            <span className="mleg">
              {cards.map((c) => (
                <Link key={c.airline_id} className={"mf" + (c.airline_id === selId ? " on" : "")} to={itemRoute("performance", { airline: c.code ?? String(c.airline_id) })} data-al={c.code ?? ""}>
                  <AirlineMark color={colorOf(c.airline_id)} />{c.code ?? c.name}
                </Link>
              ))}
            </span>
          </div>
          <div className="fgrid one" data-figure="performance: scorecards">{card(sel, true)}</div>
          <FoldTools onCollapse={() => setFolded(new Set(allFolds))} onExpand={() => setFolded(new Set())} />
          {selProfit ? board("Profit", <ProfitBody p={selProfit} />, {
            title: <><AirlineMark color={colorOf(sel.airline_id)} />{sel.name}: profit</>, figure: `performance ${sel.name}: profit` }) : null}
          {forecastQ.data ? board("Cash, next 14 days", <ForecastBody fc={forecastQ.data} cushion={cushion(forecastQ.data)} airline={sel.name} />, {
            note: `captured cash + flight profit from the last day's bank statement − every scheduled lease payment and week-end closing (repeated weekly beyond what the game lists) · an order is "safe" when ${cushion(forecastQ.data).toFixed(1)}M stays in hand at the lowest point afterwards, counting its own weekly lease from 7 days after it arrives (taken as the day it's ordered)`,
            figure: `performance ${sel.name}: Cash, next 14 days` }) : null}
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
          ), { figure: `performance ${sel.name}: Route profit` }) : null}
          {planQ.data ? board("Fare plan", <FarePlanBody airline={sel.name} plan={planQ.data} busy={busy} onDrop={(p) => void save([farePlanDrop(p)])} />,
            { figure: `performance ${sel.name}: Fare plan` }) : null}
        </>
      ) : !isAirline ? (
        <>
          <div className="fgrid" data-figure="performance: scorecards">{cards.map((c) => card(c, false))}</div>
          <FoldTools onCollapse={() => setFolded(new Set(allFolds))} onExpand={() => setFolded(new Set())} />
          {cardsQ.data.group_today_shown ? board("The group today", <GroupChart rows={groupRows} />, { figure: "performance: the group today" }) : null}
          {signalsQ.data && growthParts ? board("Growth signals", <GrowthSignals rules={rules} signals={signalsQ.data} ready={growthParts.ready} airlines={airlines} />,
            { figure: "performance: growth signals" }) : null}
          {progressQ.data && growthParts ? board("Main hubs", <MainHubs progress={progressQ.data} readiness={growthParts.readiness} airlines={airlines} />, {
            title: `Main hubs towards ${target}`, figure: "performance: main hubs board",
            note: `hubs first: each main hub reaches ${target} departures a week before another opens, unless the new one is contested${exempt.length ? ` (${exempt.join(", ")} exempt)` : ""} · lighter bar = plan cards not yet filed · open a line for its hub readiness: how many cities feed each bank`,
          }) : null}
          {board("Flights by day", <FlightsByDay day={day} flights={flights} summary={summary} airlines={airlines} loadOf={loadOfFlight} onDay={goDay} loading={!dayReady} />,
            { figure: "performance: flights by day" })}
        </>
      ) : null) : null}
    </main>
  );
}

/** A scorecard: Review's card, with the fleet, flights a day and average load against the same day last week from the
 *  daily history (airline_days), each with an arrow. One change a line: with the arrows, the card's own "+N this week"
 *  (counted from the schedule, so it can differ) is left out; without a day a week ago it stays. Tap it to open the airline. */
function Scorecard({ c, on, color, days, wow, onPick }: { c: Card; on: boolean; color: string | null; days: ProfitAnswer["days"]; wow: WeekOnWeek | undefined; onPick: () => void }) {
  const x = cardWords(c);
  const vs = (k: WeekKey) => {
    const ch = wow?.changes[k];
    return <dd className={"wow" + (ch?.arrow ? " " + ch.arrow : "")} data-wow={k} title={wow?.weekAgo ? `against ${niceDate(wow.weekAgo)}` : undefined}>{wow?.compared && ch ? ch.text : ""}</dd>;
  };
  const none = <dd className="wow" />;
  return (
    <button type="button" className={"fcard" + (on ? " on" : "")} data-final={c.code ?? ""} data-figure={`performance ${c.name}: card`} onClick={onPick}>
      <div className="fch"><AirlineMark color={color} /><b>{c.name}</b><Spark days={days} /></div>
      <div className={"fbig" + (x.bigNeg ? " neg" : "")}>{x.big}{c.profit_day != null ? <span className="fu"> a day</span> : null}</div>
      <div className="fsub">{x.sub}</div>
      <dl className="wowl">
        <dt>Per aircraft</dt><dd>{x.perAircraft}</dd>{none}
        <dt>Return on fleet</dt><dd>{x.returnOnFleet}</dd>{none}
        <dt>An aircraft pays back in</dt><dd>{x.payback}</dd>{none}
        <dt>Funds a new aircraft every</dt><dd>{x.fundsEvery}</dd>{none}
        <dt>Fleet</dt><dd>{x.fleet}{x.fleetAdded && !wow?.compared ? <> <span className="pos">{x.fleetAdded}</span></> : null}{x.onOrder}</dd>{vs("fleet")}
        <dt>Flights a day</dt><dd>{x.flights}{x.flightsAdded && !wow?.compared ? <> <span className="pos">{x.flightsAdded}</span></> : null}</dd>{vs("flights")}
        <dt>Average load, 7 days</dt><dd>{x.load}</dd>{vs("load")}
        <dt>Next order</dt><dd data-figure="performance: next order per airline">
          {x.next.kind === "pill" ? <span className="pill warn sm">{x.next.text}</span> : x.next.kind === "dim" ? <span className="dim">{x.next.text}</span> : x.next.text}
        </dd>{none}
      </dl>
      <div className="fwow dim" data-wow-day={wow?.weekAgo ?? ""}>
        {!wow || !wow.day ? "no daily history yet" : wow.compared ? `▲▼ against ${niceDate(wow.weekAgo)}, from the daily history` : `no day a week ago (${niceDate(wow.weekAgo)}) to compare`}
      </div>
    </button>
  );
}

/** The profit chart (the last 14 intervals, with the 7-day average) and the table of reported days, newest first. */
function ProfitBody({ p }: { p: ProfitAnswer }) {
  const iv = p.days;
  return (
    <>
      <BarChart pts={chartIntervals(iv).map((x) => ({ x: x.date, y: x.profit_day, tip: barTip(x, (d) => niceDate(d)) }))} avg={p.profit_day} figure="performance: profit chart" />
      {iv.length ? (
        <div className="tscroll">
          <table className="tbl ftbl" data-figure="performance: profit by day">
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
      <div className="fcfacts" data-figure="performance: forecast facts">
        <span>Cash at capture <b>{(fc.cash ?? 0).toFixed(2)}M</b> <span className="dim">({fcDay(t0)} {new Date(t0).toISOString().slice(11, 16)} UTC)</span></span>
        <span>Flight profit <b>{ops >= 0 ? "+" : "−"}{Math.abs(ops).toFixed(2)}M a day</b> <span className="dim">before leases · {Math.round((fc.profit_per_flight ?? 0) * 1000)}k a flight × {(fc.flights_per_day ?? 0).toFixed(0)} flights</span></span>
        <span>Payments, next 7 days <b>{(fc.payments_next_7_days ?? 0).toFixed(2)}M</b></span>
        {low ? <span>Lowest point <b className={low.balance < cushion ? "neg" : ""}>{low.balance.toFixed(2)}M</b> on {fcDay(low.at)}{low.payment ? `, after ${fcWhat(low.payment.what)}` : ""}</span> : null}
      </div>
      <div className="fcsafe" data-figure="performance: safe to order">
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
        <table className="tbl rptbl" id="rp-table" data-figure="performance: route profit table">
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
              <table className="tbl rptbl" data-figure="performance: aircraft table">
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
          <table className="tbl rptbl" data-figure="performance: fare changes">
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
      <table className="tbl rptbl" data-figure="performance: fare plan table">
        <tbody>
          <tr><th>Route</th><th>Class</th><th className="num">Change</th><th className="num">Fare then → target</th><th className="num">Fare now</th><th>Status</th><th className="num">Load before → after</th><th>Why</th><th></th></tr>
          {plan.plan.map((p) => {
            const x = planWords(p, (d) => niceDate(d));
            return (
              <tr key={p.id} data-fareplan={p.id}>
                <td><b>{x.route}</b></td><td>{x.cls}</td><td className="num">{x.change}</td><td className="num">{x.fares}</td><td className="num">{x.now}</td>
                <td><span className={x.status.kind === "ok" ? "dim" : `pill ${x.status.kind} sm`}>{x.status.text}</span></td><td className="num">{x.loads}</td><td className="dim">{x.why}</td>
                <td><button type="button" className="link" data-faredel={p.id} disabled={busy} title="Remove from the plan" onClick={() => onDrop(p)}>remove</button></td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
