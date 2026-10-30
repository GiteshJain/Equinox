// The route page (spec docs/specs/2026-10-21-route-page.md §3), inside Performance at /planner/performance/<code>/<route>
// (/performance/PA/JFK-ORD; the airline's page stays at /performance/<code>): a route's story since launch, so a fare move,
// a new frequency or a rival can be judged by what happened after it. Phone first, by the rules for every screen (spec
// docs/specs/2026-10-20-today-performance-systems.md). Top to bottom: the header (route and city, stars, airline, distance,
// market, the layout its distance calls for (the planning library's, since 26 Oct), launched, departures a week each way, the types, each cabin's fare level and this Saturday's move;
// "‹ <airline>" and "Schedule in Routes"); the last 7 days against the 7 before; then its boards, open on arrival: Since
// launch (one chart), Profit an aircraft hour by week, Events, Rivals on the pair and Connections. Every figure is
// route_story()'s (the database's) but the connections, which are the planning library's on the schedule the planner
// reads (the plan card's rule), and the layout, the library's card.cabinRange on the route's distance (manual §5). Its logic is model.ts's ("the route page"). Read only: nothing here saves.
// Since 30 Oct (spec docs/specs/2026-10-30-market-pages-planner.md §1) ten boards, paired in two columns at 1100 px and
// wider (one column under it): Since launch · Load by direction, Loads by flight · Profit an aircraft hour, Rival fares ·
// Market share, Rivals on the pair · Rivals over time, Events · Connections. Load by direction and the market boards are
// route_story()'s new keys; Loads by flight is route_loads()' flights on the route's flight numbers; the header says the
// service set in the game, amber when the service check (market_service_checks()) finds this route set differently.
// Since 30 Oct (spec docs/specs/2026-10-30-route-story-on-routes.md) the tiles and the boards are RouteStory.tsx's,
// shared with Routes' route detail; this page shows all ten, unchanged.
import { useMemo, useState, type ReactNode } from "react";
import { Link } from "react-router";
import { ourAirlines } from "../../data/airlines";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useLoads } from "../routes/reads";
import { useServiceChecks } from "../systems/reads";
import { useRules } from "../../data/rules";
import { niceDate } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { FoldBoard, FoldTools } from "../../ui/FoldBoard";
import { Stars } from "../routes/parts";
import { itemRoute } from "../screens";
import {
  ROUTE_BOARDS, flightLoads, parseRouteKey, routeConnections, serviceHeader, storyHeader, storyLayout,
  type FlightLoadRow, type RouteBoardKey, type RouteStory, type ServiceChecks,
} from "./model";
import { WeekTiles, useStoryBoards } from "./RouteStory";
import { useRouteAt, useRouteStory } from "./reads";

const firstError = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

const NOTES: Record<RouteBoardKey, string> = {
  "Since launch": "economy and business loads by UTC day, both directions together, from the daily history · the fare level (right) from the fare plan's ladder rows · a dot under a day is an event: point at a day for its figures and events",
  "Profit an aircraft hour": "each week's profit ÷ the block hours flown, the 7 days to the latest captured day and the 12 weeks before · the airline's average isn't drawn: route profit covers only the last few days",
  "Events": "newest first: the schedule's saves (frequencies, aircraft, times), the fare plan, and rivals starting or growing on the pair between world scans",
  "Rivals on the pair": "every other airline flying it either way in the latest world scan, passenger flights only, against the week-before scan, with its one-stop connecting departures beside (never added) · our share at each scan since launch",
  "Connections": "the city pairs its flights connect to at each end, from the minimum connection time up to the longest wait, across all our airlines' schedules (the plan card's rule)",
  "Load by direction": "economy load by UTC day since launch, out from the hub and back to it, from the daily history · each direction's fare level (right) from the fare plan's ladder rows",
  "Loads by flight": "each flight number on the route over the last 7 days (route_loads()): its way, local departure, average economy load, flights and how many were 95% or more",
  "Rival fares": "every airline's fares on the pair from the latest market read, each way · average with lowest–highest, flights seen, economy sold out of finished",
  "Market share": "the game's own share of the pair's passengers this week, each way, from the latest market read, against last week · the scan's departures share for comparison",
  "Rivals over time": "each airline's direct departures a week at every world scan since launch (one a week before the last month) · the pair's seats and price per unit by week from the market reads",
};

export function RoutePage({ code, routeKey }: { code: string; routeKey: string }) {
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const airlines = useMemo(() => ourAirlines(airlinesQ.data), [airlinesQ.data]);
  const airline = airlines.find((a) => a.code === code);
  const key = parseRouteKey(routeKey);
  const routeQ = useRouteAt(airline?.id, key?.hub, key?.dest);
  const storyQ = useRouteStory(routeQ.data?.id ?? undefined);
  const rulesQ = useRules(w);
  const loadsQ = useLoads(w);
  const checksQ = useServiceChecks(w !== undefined);
  const [folded, setFolded] = useState<ReadonlySet<RouteBoardKey>>(() => new Set());
  const toggle = (k: RouteBoardKey) => setFolded((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const s = storyQ.data;
  const rules = rulesQ.data?.rules;
  const conns = useMemo(() => (s && rules ? routeConnections(rules, { id: s.route.id, hub: s.route.hub, dest: s.route.dest }) : null), [s, rules]);
  const flights = useMemo(() => (s && rules && loadsQ.data ? flightLoads(rules, s.route.id, s.route.airline.id, loadsQ.data.flights) : null), [s, rules, loadsQ.data]);

  const noAirline = !!airlinesQ.data && !airline;
  const noRoute = !key || (routeQ.isSuccess && routeQ.data === null);
  const ready = noAirline || noRoute || !!(s && conns && flights && checksQ.data);
  const loadError = firstError(world, airlinesQ, routeQ, storyQ, rulesQ, loadsQ, checksQ);
  const board = (k: RouteBoardKey, children: ReactNode, figure: string, note?: ReactNode) => (
    <FoldBoard key={k} k={k} note={note ?? NOTES[k]} folded={folded.has(k)} onToggle={() => toggle(k)} figure={figure}>{children}</FoldBoard>
  );
  const back = airline ? <Link className="link" to={itemRoute("performance", { airline: code })} data-back>‹ {airline.name}</Link> : null;

  return (
    <main className="view finance performance routepage" data-screen="performance" data-performance-ready={ready ? "yes" : "no"} data-airline={code}
      data-route-page={key ? `${key.hub}-${key.dest}` : routeKey} data-performance-view={`/performance/${code}/${routeKey}`}>
      {loadError ? <ErrorBox error={loadError} /> : null}
      {!ready && !loadError ? <div className="empty">Loading…</div> : null}
      {noAirline ? <div className="empty">There's no airline {code} in the planner. <Link className="link" to="/performance">All airlines</Link></div> : null}
      {!noAirline && noRoute ? (
        <div className="empty">{airline?.name ?? code} has no route {routeKey}. {back}</div>
      ) : null}
      {s && airline && rules ? <RouteStoryView s={{ ...s, route: { ...s.route, airline: { ...s.route.airline, name: airline.name } } }} code={code} back={back} conns={conns} board={board}
        flights={flights} checks={checksQ.data ?? null} color={airline.color}
        layout={storyLayout(rules, s.route)}
        onCollapse={() => setFolded(new Set(ROUTE_BOARDS))} onExpand={() => setFolded(new Set())} /> : null}
    </main>
  );
}

/** The route page below its reads: the header, the week's comparison and the boards (exported for its render test). */
export function RouteStoryView({ s, code, back, conns, board, layout, onCollapse, onExpand, flights = null, checks = null, color = null }: {
  s: RouteStory;
  /** The airline's colour, for our share in the market share donuts. */
  color?: string | null;
  /** Loads by flight's rows (flightLoads()), or null while the loads are read. */
  flights?: readonly FlightLoadRow[] | null;
  /** The service check (market_service_checks()), for the header's service in the game. */
  checks?: ServiceChecks | null;
  /** The layout its distance calls for, in words (storyLayout). */
  layout: string;
  code: string;
  back: ReactNode;
  conns: ReturnType<typeof routeConnections> | null;
  board: (k: RouteBoardKey, children: ReactNode, figure: string, note?: ReactNode) => ReactNode;
  onCollapse: () => void;
  onExpand: () => void;
}) {
  const h = storyHeader(s, (d) => niceDate(d), layout);
  const boards = useStoryBoards(s, { flights, conns, color });
  const svc = serviceHeader(s, checks);
  return (
    <>
      <div className="perfnav" data-route-links>
        {back}
        <Link className="link" to={itemRoute("routes", { airline: code, hub: s.route.hub, dest: s.route.dest })} data-schedule>Schedule in Routes</Link>
      </div>
      <div className="vh rphead" data-figure="performance route: header">
        <p className="vk">Performance · a route</p>
        <h1>{h.title} <span className="city">{h.city}</span></h1>
        <p className="rpline">{s.route.stars != null ? <><Stars n={s.route.stars} />{" "}</> : null}{h.line}
          {svc ? <>{" · "}<span className={"rpsvc" + (svc.off ? " off" : "")} data-service={svc.off ? "off" : "ok"}
            title={svc.off ? "the service check finds this route set differently in the game, the distance or the planner: see Today's needs attention" : undefined}>{svc.text}</span></> : null}</p>
        <p className="rpline">{h.launched} · {h.departures}{h.types ? ` · ${h.types}` : ""}{s.route.removed ? " · removed from the list" : ""}</p>
        {h.fares.length ? <p className="rpline" data-fares>{h.fares.join("; ")}</p> : null}
      </div>
      <WeekTiles s={s} />
      <FoldTools onCollapse={onCollapse} onExpand={onExpand} />
      <div className="rpboards" data-route-boards>
      {ROUTE_BOARDS.map((k) => board(k, boards[k].content, boards[k].figure))}
      </div>
    </>
  );
}
