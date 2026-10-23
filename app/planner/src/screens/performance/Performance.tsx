// Performance (spec docs/specs/2026-10-20-today-performance-systems.md): "how are we doing, and why?". Review's screen
// until 20 Oct (decision #18, build pull request 10, spec docs/specs/2026-10-14-review.md), with Check's growth boards and
// daily load report; every money figure from the database's figures (design §8). Its boards are open on arrival, the
// most important first (Collapse all and Expand all fold them).
//   - The group (/planner/performance): the scorecards, one per airline (Review's cards, airline_cards(), with each
//     airline's sparkline from airline_profit(), and the fleet, flights a day and average load against the same day last
//     week from the daily history, airline_days, with an arrow); tap one to open the airline. Then the fare ladder (since 21
//     Oct, spec docs/specs/2026-10-21-fare-ladder.md: fare_ladder() for each airline, FareLadder.tsx), the group today (each
//     airline's flight profit, leases and week-end closing, net; no group totals, manual §5), the growth signals (ready
//     for another flight, raise fares, fix or reduce, aircraft losing money after their lease: growth_signals()), the
//     main hubs towards 750 (hub_progress(), with hub readiness, the library's growth.hubReadiness, folded into each line)
//     and Flights by day (Check's daily load report, renamed; its day in the address, ?day=).
//   - The airline (/planner/performance/<code>): its scorecard, then Review's page: the profit chart for the last 14
//     intervals with its average and the table of reported days (airline_profit()), Cash, next 14 days (cash_forecast()),
//     Route profit with its aircraft and fare changes (route_profit(), aircraft_profit(), fare_changes(); since 21 Oct each
//     route's fare index from fare_ladder() and its 14-day load sparkline from route_days) and the Fare plan
//     (fare_plan_status()). Each route's name in the route profit table opens its route page; the table's search box
//     filters it to a route (what /performance/PA/JFK-ORD did until 22 Oct).
//   - A route (/planner/performance/<code>/<route>, since 22 Oct, spec docs/specs/2026-10-21-route-page.md): the route
//     page, its story since launch (RoutePage.tsx, route_story()).
// Since 22 Oct (spec docs/specs/2026-10-22-planner-look-performance.md) in the style of the new Today, Routes and Systems:
// the group page's title is the answer (how many airlines are in profit, never a group total), the scorecards tidy,
// the fare ladder one card per airline, and the other boards rows that open, all closed on arrival; an airline's page
// has its name as the title with four big numbers and the airline switch under it, its boards rows that open with
// Route profit open on arrival (Aircraft and Fare changes rows of their own).
// Manual entry moved to Systems. The saves here, + fare plan, remove and Put on the fare plan (the fare ladder), are one
// planner_save() call each.
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
import { BarChart, CostChart, ForecastChart, GroupChart, LoadSpark, Scatter, Spark, TailChart } from "./Charts";
import { FareLadderBoard } from "./FareLadder";
import { daySummary, loadKey, loadsByFlight, moveDay, parseDay, utcToday } from "./flights";
import { FlightsByDay } from "./FlightsByDay";
import { GrowthSignals, MainHubs, type ReadyRow } from "./Growth";
import { RoutePage } from "./RoutePage";
import {
  BOARDS, GROUP_BOARDS, foldsFor, foldsOnArrival, type FoldState, MARKS, MARK_ORDER, PERIODS, SORTS, aircraftRowWords, barTip, capturedLine, cardWords, cashRowWords, changesRowWords, chartIntervals,
  farePlanAdd, farePlanDrop, fcDay, fcWhat, groupTodayWords, growthWords, historyFrom, hubsWords, indexWords, kk, ladderLine, ladderPlanChanges, loads14, markCounts, ms,
  offersFarePlan, pc, planRowWords, planWords, profitAnswer, profitRowWords, routeRowWords, routeSearchText, safeWords, sg, shownRoutes, weekOnWeek, weekWords, type AircraftRow,
  type BoardKey, type Card, type CardWords, type FareChange, type FarePlanAnswer, type Forecast, type GroupBoardKey, type LadderAnswer, type Mark, type ProfitAnswer, type RouteDayRow,
  type RouteProfitAnswer, type RouteSort, type WeekKey, type WeekOnWeek,
} from "./model";
import {
  refreshFigures, useAircraftProfit, useAirlineDays, useDayLoads, useFareChanges, useFareLadder, useFareLadders, useFarePlan, useForecast, useGrowthSignals, useHandLoads,
  useHubProgress, useProfits, useReviewCards, useRouteDays, useRouteProfit,
} from "./reads";

/** The fare ladder's line under its heading. */
const LADDER_NOTE = "each route and cabin's level against the game's default price, and this Saturday's move from the week's captured flights: up a step when every flight sold out, hold at 90–99%, down under 90%; a cabin that doesn't fill at launch may jump under it, judged on revenue a flight (manual §5) · make the moves in the game with Ticket price adjustment, put them on the fare plan, and the next capture ticks each off";
/** Each row's one-line note; the board's full words (NOTES) lead it once open. */
const SHORT: Record<BoardKey | GroupBoardKey, string> = {
  "The group today": "Each airline's flight profit against its leases, a day",
  "Growth signals": "Where each airline should grow next, and what to trim",
  "Main hubs": "Each main hub towards its weekly target",
  "Flights by day": "Every flight of a day, with its loads",
  "Profit": "Profit for each day between reports",
  "Cash, next 14 days": "Cash in hand day by day, and what's safe to order",
  "Route profit": "Each route's profit, loads and fares",
  "Aircraft": "Each aircraft's profit a day, less its lease",
  "Fare changes": "Fares changed in the game, with the load before and after",
  "Fare plan": "Fare changes to make in the game",
};
const NOTES: Record<BoardKey | GroupBoardKey, string> = {
  "The group today": "from last night's capture · flight profit is before leases; leases and the week-end closing are this week's scheduled payments, per day",
  "Growth signals": "where each airline should grow next, and what to trim · from the nightly capture",
  "Main hubs": "",
  "Flights by day": "every flight flown, from the nightly capture, with loads by class · if a capture failed, enter loads in Systems under Manual entry",
  "Profit": "profit for each day between reports = change in cash + order payments that day · cash moves on payment days, so read the average",
  "Cash, next 14 days": "",
  "Route profit": "each captured flight's income minus its flight costs (fuel, handling, on-board, landing and air-traffic fees, maintenance), from the bank statement, matched to its loads and fares · before leases and the week-end closing",
  "Aircraft": "flight profit a day (its average flight × its scheduled flights) less its lease",
  "Fare changes": "spotted in the captured economy fares, with the load the day before and after",
  "Fare plan": "fare changes to make in the game · each is spotted in the next capture, with the economy load before and after",
};

const firstError = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

/** Performance: the group, an airline's page, or (with a route after the airline, since 22 Oct) the route page. */
export function Performance() {
  const params = useParams();
  const [code, routeKey] = (params["*"] ?? "").split("/").filter(Boolean);
  if (code && routeKey) return <RoutePage key={`${code}/${routeKey}`} code={code} routeKey={routeKey} />;
  return <PerformanceScreen />;
}

function PerformanceScreen() {
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

  const [code] = (params["*"] ?? "").split("/").filter(Boolean);
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
  const ladderQ = useFareLadder(selId);
  const routeDaysQ = useRouteDays(selId, moveDay(utcDay, -13), utcDay);

  // ---------- the group's boards
  const group = !isAirline ? w : undefined;
  const laddersQ = useFareLadders(group !== undefined ? cards.map((c) => c.airline_id) : []);
  const ladders = new Map<number, LadderAnswer>();
  laddersQ.forEach((q, i) => { const c = cards[i]; if (c && q.data) ladders.set(c.airline_id, q.data); });
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
  // every row closed on arrival but the airline's Route profit, and Flights by day when the address names a day; each page
  // (the group, each airline) arrives that way whatever the page before had open (foldsFor)
  const foldView = "/performance" + (code ? "/" + code : "");
  const [foldState, setFoldState] = useState<FoldState>(() => foldsOnArrival(foldView, loc.search));
  const folded = foldsFor(foldState, foldView, loc.search);
  const setFolded = (next: ReadonlySet<BoardKey | GroupBoardKey>) => setFoldState({ view: foldView, folded: next });
  const [busy, setBusy] = useState(false);
  const toggle = (k: BoardKey | GroupBoardKey) => { const n = new Set(folded); if (n.has(k)) n.delete(k); else n.add(k); setFolded(n); };

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
  const airlineReady = !!(sel && selProfit && forecastQ.data && routeQ.data && !routeQ.isFetching && aircraftQ.data && !aircraftQ.isFetching && changesQ.data && planQ.data
    && ladderQ.data && routeDaysQ.data);
  const groupReady = !!(signalsQ.data && progressQ.data && growthParts && (!cardCodes.length || airportsQ.data) && launchesQ.data && dayReady
    && laddersQ.every((q) => q.data && !q.isFetching));
  const ready = common && (isAirline ? airlineReady : groupReady);
  const loadError = firstError(world, airlinesQ, rulesQ, cardsQ, daysQ, ...profitsQ,
    ...(isAirline ? [forecastQ, routeQ, aircraftQ, changesQ, planQ, ladderQ, routeDaysQ]
      : [...laddersQ, signalsQ, progressQ, routesQ, loadsQ, marketsQ, tailsQ, planCardsQ, planLegsQ, launchesQ, airportsQ, dayLoadsQ, handQ]));
  const board = (k: BoardKey | GroupBoardKey, children: ReactNode, opts: { title?: ReactNode; lead?: ReactNode; figure?: string; aside?: ReactNode } = {}) => (
    <FoldBoard key={k} k={k} title={<span className="fbname">{opts.title ?? k}</span>} note={SHORT[k]} aside={opts.aside} folded={folded.has(k)} onToggle={() => toggle(k)}
      figure={opts.figure}>{(opts.lead ?? NOTES[k]) ? <div className="note fblead">{opts.lead ?? NOTES[k]}</div> : null}{children}</FoldBoard>
  );
  const rows = (children: ReactNode) => (
    <section className="sysrows perfrows" aria-labelledby="perfrows-h">
      <div className="sysrowsh">
        <h2 className="tph" id="perfrows-h">The details</h2>
        <FoldTools onCollapse={() => setFolded(new Set(allFolds))} onExpand={() => setFolded(new Set())} hint="" />
      </div>
      {children}
    </section>
  );
  const cushion = (fc: Forecast | undefined) => (fc?.cushion != null ? fc.cushion : rules && selId != null ? Number(setting(rules, "order_cushion", selId) ?? 0) / 1_000_000 : 0);
  const view = "/performance" + (code ? "/" + code : "");
  const target = (progressQ.data ?? []).find((x) => !x.exempt && x.main_hub)?.target ?? progressQ.data?.[0]?.target ?? 750;
  const exempt = (progressQ.data ?? []).filter((x) => x.exempt).map((x) => named.get(x.airline_id)).filter(Boolean);
  const card = (c: Card) => (
    <Scorecard key={c.airline_id} c={c} color={colorOf(c.airline_id)} days={profitOf.get(c.airline_id)?.days ?? []} wow={wowOf.get(c.airline_id)}
      onPick={() => navigate(itemRoute("performance", { airline: c.code ?? String(c.airline_id) }))} />
  );
  // each row's count or state
  const signals = signalsQ.data;
  const growthAside = signals ? growthWords({ profit_captured: signals.profit_captured, ready: signals.profit_captured ? signals.ready_for_another_flight.length : growthParts?.ready.length ?? 0,
    raise: signals.raise_fares.length, fix: signals.fix_or_reduce.length, aircraft: signals.aircraft_losing_after_lease.length }) : null;
  const daysAside = !dayReady ? "Loading…" : `${niceDate(day)} · ${summary.departures} departure${summary.departures === 1 ? "" : "s"}`
    + (summary.kind === "captured" ? ` · ${summary.soldOut} sold out` : summary.kind === "hand" ? " · by hand" : "");
  const cashAside = forecastQ.data ? cashRowWords(forecastQ.data, cushion(forecastQ.data)) : null;
  const tailsAside = aircraftQ.data ? aircraftRowWords(aircraftQ.data) : null;

  return (
    <main className="view finance performance" data-screen="performance" data-performance-ready={ready ? "yes" : "no"} data-performance-view={view}
      data-airline={sel?.code ?? ""} data-day={isAirline ? "" : day}>
      {sel ? (
        <div className="vh perfvh perfal">
          <p className="vk">Performance</p>
          <div className="perfttl">
            <h1 data-perf-name={sel.code ?? ""}><AirlineMark color={colorOf(sel.airline_id)} size={18} />{sel.name}</h1>
            <Link className="link perfback" to="/performance" data-back>‹ All airlines</Link>
          </div>
          <div className="seg rseg perfseg" role="group" aria-label="Airline" data-airlines>
            {cards.map((c) => (
              <button type="button" key={c.airline_id} className={c.airline_id === selId ? "on" : ""} aria-pressed={c.airline_id === selId} data-al={c.code ?? ""}
                onClick={() => navigate(itemRoute("performance", { airline: c.code ?? String(c.airline_id) }))}>
                <AirlineMark color={colorOf(c.airline_id)} />{c.code ?? c.name}
              </button>
            ))}
          </div>
          <HeadFigures c={sel} wow={wowOf.get(sel.airline_id)} />
        </div>
      ) : (
        <div className="vh todayvh perfvh">
          <p className="vk">{isAirline ? "Performance" : "Results"}</p>
          <div className="todayttl">
            <h1 className="ansh" data-perf-answer>{!isAirline && cardsQ.data ? profitAnswer(cards) : "Performance"}</h1>
          </div>
          <p className="ansp">How each airline is doing, and why: the scorecards against last week, this Saturday's fare ladder, the growth signals, the main hubs and the flights by day.</p>
        </div>
      )}
      {loadError ? <ErrorBox error={loadError} /> : null}
      {!ready && !loadError ? <div className="empty">Loading…</div> : null}
      {isAirline && cardsQ.data && !sel ? <div className="empty">There's no airline {code} in the planner. <Link className="link" to="/performance">All airlines</Link></div> : null}
      {cardsQ.data && rules ? (sel ? rows(
        <>
          {selProfit ? board("Profit", <ProfitBody p={selProfit} />, {
            title: <>{sel.name}: profit</>, figure: `performance ${sel.name}: profit`, aside: profitRowWords(selProfit) }) : null}
          {forecastQ.data ? board("Cash, next 14 days", <ForecastBody fc={forecastQ.data} cushion={cushion(forecastQ.data)} airline={sel.name} />, {
            lead: `captured cash + flight profit from the last day's bank statement − every scheduled lease payment and week-end closing (repeated weekly beyond what the game lists) · an order is "safe" when ${cushion(forecastQ.data).toFixed(1)}M stays in hand at the lowest point afterwards, counting its own weekly lease from 7 days after it arrives (taken as the day it's ordered)`,
            figure: `performance ${sel.name}: Cash, next 14 days`,
            aside: cashAside ? (cashAside.low ? <span className="pill warn sm">{cashAside.text}</span> : cashAside.text) : null }) : null}
          {routeQ.data && changesQ.data && planQ.data ? board("Route profit", (
            <RouteProfitBody key={sel.airline_id} airline={sel} r={routeQ.data} plan={planQ.data}
              ladder={ladderQ.data} routeDays={routeDaysQ.data ?? []} today={utcDay}
              days={days} onDays={setDays} busy={busy}
              city={(c) => rules.airports.get(c)?.city ?? ""} soldOutMin={String(setting(rules, "growth_sold_out_min_departures", sel.airline_id) ?? "")}
              raisePct={Number(setting(rules, "fare_plan_raise_pct", sel.airline_id) ?? NaN)}
              onAdd={(row) => {
                const pct = Number(setting(rules, "fare_plan_raise_pct", sel.airline_id));
                const fare = planQ.data.fares.find((f) => f.route_id === row.route_id)?.fare;
                const ch = row.route_id != null && w !== undefined ? farePlanAdd({ worldId: w, airlineId: sel.airline_id, routeId: row.route_id, fare, pct, today, nowMs: Date.now() }) : null;
                if (!ch) { showMessage("No captured fare for this route yet."); return; }
                void save([ch]).then((res) => { if (res?.status === "saved") showMessage(`${row.hub}–${row.dest}: +${pct}% economy added to the fare plan.`); });
              }} />
          ), { figure: `performance ${sel.name}: Route profit`, aside: routeRowWords(routeQ.data) }) : null}
          {aircraftQ.data ? board("Aircraft", <AircraftBody aircraft={aircraftQ.data} />, {
            figure: `performance ${sel.name}: Aircraft`,
            aside: tailsAside ? <>{tailsAside.text}{tailsAside.losing ? <span className="pill warn sm">{tailsAside.losing} losing after its lease</span> : null}</> : null }) : null}
          {changesQ.data ? board("Fare changes", <FareChangesBody changes={changesQ.data} />, { figure: `performance ${sel.name}: Fare changes`, aside: changesRowWords(changesQ.data.length) }) : null}
          {planQ.data ? board("Fare plan", <FarePlanBody airline={sel.name} plan={planQ.data} busy={busy} onDrop={(p) => void save([farePlanDrop(p)])} />,
            { figure: `performance ${sel.name}: Fare plan`, aside: planRowWords(planQ.data.plan.length) }) : null}
        </>
      ) : !isAirline ? (
        <>
          <div className="fgrid" data-figure="performance: scorecards">{cards.map((c) => card(c))}</div>
          <section className="perfsec" data-board="Fare ladder" data-figure="performance: fare ladder board" aria-labelledby="perf-ladder-h">
            <h2 className="perfh" id="perf-ladder-h">The fare ladder</h2>
            <p className="note perflead">{LADDER_NOTE}</p>
            <FareLadderBoard airlines={airlines} ladders={ladders} busy={busy} onPlan={(a, ladder) => {
              const ch = w !== undefined ? ladderPlanChanges({ worldId: w, airlineId: a.id, routes: ladder.routes, utcDay, nowMs: Date.now() }) : [];
              if (!ch.length) { showMessage(`Nothing of ${a.name}'s to put on the fare plan.`); return; }
              void save(ch).then((res) => { if (res?.status === "saved") showMessage(`${a.name}: ${ch.length} on the fare plan (${ladderLine(ladder.moves)}). Make them in the game; the next capture ticks each off.`); });
            }} />
          </section>
          {rows(<>
            {cardsQ.data.group_today_shown ? board("The group today", <GroupChart rows={groupRows} />, { figure: "performance: the group today", aside: groupTodayWords(groupRows) }) : null}
            {signalsQ.data && growthParts ? board("Growth signals", <GrowthSignals rules={rules} signals={signalsQ.data} ready={growthParts.ready} airlines={airlines} />,
              { figure: "performance: growth signals", aside: growthAside }) : null}
            {progressQ.data && growthParts ? board("Main hubs", <MainHubs progress={progressQ.data} readiness={growthParts.readiness} airlines={airlines} />, {
              title: `Main hubs towards ${target}`, figure: "performance: main hubs board", aside: hubsWords(progressQ.data),
              lead: `hubs first: each main hub reaches ${target} departures a week before another opens, unless the new one is contested${exempt.length ? ` (${exempt.join(", ")} exempt)` : ""} · lighter bar = plan cards not yet filed · open a line for its hub readiness: how many cities feed each bank`,
            }) : null}
            {board("Flights by day", <FlightsByDay day={day} flights={flights} summary={summary} airlines={airlines} loadOf={loadOfFlight} onDay={goDay} loading={!dayReady} />,
              { figure: "performance: flights by day", aside: daysAside })}
          </>)}
        </>
      ) : null) : null}
    </main>
  );
}

/** A scorecard: Review's card, with the fleet, flights a day and average load against the same day last week from the
 *  daily history (airline_days), each with an arrow. One change a line: with the arrows, the card's own "+N this week"
 *  (counted from the schedule, so it can differ) is left out; without a day a week ago it stays. Tap it to open the
 *  airline. Since 22 Oct its head is the big profit figure and the name line, the rows two tidy columns (the label, then
 *  the value with its change in one cell) and "Next order" its footer with its pill. */
function Scorecard({ c, color, days, wow, onPick }: { c: Card; color: string | null; days: ProfitAnswer["days"]; wow: WeekOnWeek | undefined; onPick: () => void }) {
  const x = cardWords(c);
  const vs = (k: WeekKey) => {
    const ch = wow?.changes[k];
    return <span className={"wow" + (ch?.arrow ? " " + ch.arrow : "")} data-wow={k} title={wow?.weekAgo ? `against ${niceDate(wow.weekAgo)}` : undefined}>{wow?.compared && ch ? ch.text : ""}</span>;
  };
  return (
    <button type="button" className="fcard" data-final={c.code ?? ""} data-figure={`performance ${c.name}: card`} onClick={onPick}>
      <div className="fchead">
        <div className="fch"><AirlineMark color={color} /><b>{c.name}</b><Spark days={days} /></div>
        <div className={"fbig" + (x.bigNeg ? " neg" : "")}>{x.big}{c.profit_day != null ? <span className="fu"> a day</span> : null}</div>
        <div className="fsub">{x.sub}</div>
      </div>
      <dl className="wowl">
        <dt>Per aircraft</dt><dd>{x.perAircraft}</dd>
        <dt>Return on fleet</dt><dd>{x.returnOnFleet}</dd>
        <dt>An aircraft pays back in</dt><dd>{x.payback}</dd>
        <dt>Funds a new aircraft every</dt><dd>{x.fundsEvery}</dd>
        <dt>Fleet</dt><dd><span>{x.fleet}{x.fleetAdded && !wow?.compared ? <> <span className="pos">{x.fleetAdded}</span></> : null}{x.onOrder}</span>{vs("fleet")}</dd>
        <dt>Flights a day</dt><dd><span>{x.flights}{x.flightsAdded && !wow?.compared ? <> <span className="pos">{x.flightsAdded}</span></> : null}</span>{vs("flights")}</dd>
        <dt>Average load, 7 days</dt><dd><span>{x.load}</span>{vs("load")}</dd>
      </dl>
      <div className="fwow dim" data-wow-day={wow?.weekAgo ?? ""}>
        {!wow || !wow.day ? "no daily history yet" : wow.compared ? `▲▼ against ${niceDate(wow.weekAgo)}, from the daily history` : `no day a week ago (${niceDate(wow.weekAgo)}) to compare`}
      </div>
      <div className="ffoot"><span className="ffl">Next order</span><NextOrder x={x} /></div>
    </button>
  );
}

function NextOrder({ x }: { x: CardWords }) {
  return (
    <span className="ffn" data-figure="performance: next order per airline">
      {x.next.kind === "pill" ? <span className="pill warn sm">{x.next.text}</span> : x.next.kind === "dim" ? <span className="dim">{x.next.text}</span> : x.next.text}
    </span>
  );
}

/** An airline page's head (22 Oct): its scorecard's figures as four big numbers (profit a day, per aircraft, return on
 *  fleet, next order), each with its line, and the card's other figures in one line under them, with their changes. */
function HeadFigures({ c, wow }: { c: Card; wow: WeekOnWeek | undefined }) {
  const x = cardWords(c);
  const vs = (k: WeekKey) => {
    const ch = wow?.changes[k];
    return wow?.compared && ch?.text ? <> <span className={"wow" + (ch.arrow ? " " + ch.arrow : "")} data-wow={k}>{ch.text}</span></> : null;
  };
  return (
    <div className="perfhead" data-figure="performance: scorecards">
      <div className="rfigs pfigs" data-final={c.code ?? ""} data-figure={`performance ${c.name}: card`}>
        <div className="rfig"><span className="rfl">Profit a day</span><b className={x.bigNeg ? "neg" : ""}>{x.big}</b><span className="rfs">{x.sub}</span></div>
        <div className="rfig"><span className="rfl">Per aircraft</span><b>{c.per_aircraft_day == null ? "—" : kk(c.per_aircraft_day)}</b><span className="rfs">a day · pays back in {x.payback}</span></div>
        <div className="rfig"><span className="rfl">Return on fleet</span><b>{x.returnOnFleet.replace(" a week", "")}</b><span className="rfs">a week · funds a new aircraft every {x.fundsEvery}</span></div>
        <div className="rfig pnext"><span className="rfl">Next order</span><b className="pnb"><NextOrder x={x} /></b></div>
      </div>
      <p className="perfline">
        <span>Fleet {x.fleet}{x.fleetAdded && !wow?.compared ? <> <span className="pos">{x.fleetAdded}</span></> : null}{x.onOrder}{vs("fleet")}</span>
        <span>{x.flights} flights a day{x.flightsAdded && !wow?.compared ? <> <span className="pos">{x.flightsAdded}</span></> : null}{vs("flights")}</span>
        <span>average load {x.load}, 7 days{vs("load")}</span>
        <span className="dim" data-wow-day={wow?.weekAgo ?? ""}>{!wow || !wow.day ? "no daily history yet" : wow.compared ? `▲▼ against ${niceDate(wow.weekAgo)}` : `no day a week ago (${niceDate(wow.weekAgo)}) to compare`}</span>
      </p>
    </div>
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

/** Route profit for the period picked (its aircraft and fare changes are rows of their own since 22 Oct); each route with its fare index (the fare
 *  ladder's economy row) and its 14-day load sparkline (route_days) since 21 Oct; each route's name opens its route page
 *  since 22 Oct (the search box filters the table to a route). */
function RouteProfitBody({ airline, r, plan, ladder, routeDays, today, days, onDays, busy, city, soldOutMin, raisePct, onAdd }: {
  airline: Card;
  r: RouteProfitAnswer;
  plan: FarePlanAnswer;
  ladder: LadderAnswer | undefined;
  routeDays: readonly RouteDayRow[];
  today: string;
  days: number;
  onDays: (d: number) => void;
  busy: boolean;
  city: (code: string) => string;
  soldOutMin: string;
  raisePct: number;
  onAdd: (row: RouteProfitAnswer["routes"][number]) => void;
}) {
  const [mark, setMark] = useState<Mark | "">("");
  const [sort, setSort] = useState<RouteSort>("pwk");
  const [q, setQ] = useState("");
  if (!r.flights) return <div className="dim">Fills in once {airline.name}'s bank statement has been captured.</div>;
  const cnt = markCounts(r.routes);
  const shown = shownRoutes(r.routes, mark, sort);
  const query = q.trim().toLowerCase();
  const k = (v: number) => (v >= 0 ? "+" : "−") + Math.round(Math.abs(v) * 1000) + "k";
  const indexOf = (x: { route_id: number | null; hub: string; dest: string }) => indexWords(ladder?.routes.find((l) => l.cabin === "economy"
    && (x.route_id != null ? l.route_id === x.route_id : (l.hub === x.hub && l.dest === x.dest) || (l.hub === x.dest && l.dest === x.hub))));
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
        <div className="rpc rpscatter"><div className="rpct">Load against profit <span className="dim">· bubble size = flights a week · colour = signal</span></div><Scatter routes={r.routes} /></div>
        <div className="rpc rpcost"><div className="rpct">An average flight <span className="dim">· income and where it goes</span></div><CostChart avg={r.average_flight} /></div>
      </div>
      <div className="tscroll">
        <table className="tbl rptbl" id="rp-table" data-figure="performance: route profit table">
          <tbody>
            <tr><th>Route</th><th className="num">Flights</th><th className="num">Profit a flight</th><th className="num">Margin</th><th className="num">A week</th><th className="num">Economy</th><th className="num">Sold out</th><th className="num">Business</th><th className="num">Cargo</th><th className="num">Economy fare</th><th className="num" title="the latest captured economy fare against the first, times the launch level (the fare ladder)">Fare index</th><th>14 days</th><th>Signal</th></tr>
            {shown.map((x) => {
              const txt = routeSearchText(x, city);
              return (
                <tr key={`${x.hub}-${x.dest}`} data-rprow={txt} style={query && !txt.includes(query) ? { display: "none" } : undefined}>
                  <td><Link className="link" to={itemRoute("performance", { airline: airline.code, hub: x.hub, dest: x.dest })} data-route-link title="its route page: the story since launch"><b>{x.hub}–{x.dest}</b></Link></td>
                  <td className="num">{x.flights}</td>
                  <td className={"num" + (x.profit_per_flight < 0 ? " neg" : "")}>{k(x.profit_per_flight)}</td>
                  <td className="num">{x.margin == null ? "—" : Math.round(x.margin * 100) + "%"}</td>
                  <td className="num">{weekWords(x)}</td>
                  <td className="num">{pc(x.economy)}</td>
                  <td className="num">{x.with_loads ? x.sold_out + "/" + x.with_loads : "—"}</td>
                  <td className="num">{pc(x.business)}</td>
                  <td className="num">{pc(x.cargo)}</td>
                  <td className="num">{x.economy_fare == null ? "—" : Math.round(x.economy_fare)}</td>
                  {(() => { const ix = indexOf(x); return <td className="num" data-fare-index={ix.text} title={ix.flag ? `the fare ladder records ${ix.flag}: the captured fares don't match it` : undefined}>{ix.text}{ix.flag ? <span className="dim"> · {ix.flag}</span> : null}</td>; })()}
                  <td><LoadSpark values={loads14(routeDays, x, today)} /></td>
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
    </>
  );
}

/** Each aircraft's profit a day after its lease (a row of its own since 22 Oct, for the period Route profit picks). */
function AircraftBody({ aircraft }: { aircraft: AircraftRow[] }) {
  const [tailsOpen, setTailsOpen] = useState(false);
  const k = (v: number) => (v >= 0 ? "+" : "−") + Math.round(Math.abs(v) * 1000) + "k";
  if (!aircraft.length) return <div className="dim">No aircraft with captured flights in the period.</div>;
  return (
    <>
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
  );
}

/** The fare changes spotted in the captured economy fares, the latest 12 (a row of its own since 22 Oct). */
function FareChangesBody({ changes }: { changes: FareChange[] }) {
  if (!changes.length) return <div className="dim">None yet. Change a fare in the game and it appears here after the next capture, with the load before and after.</div>;
  return (
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
