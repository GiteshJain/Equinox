// The route page (spec docs/specs/2026-10-21-route-page.md §3), inside Performance at /planner/performance/<code>/<route>
// (/performance/PA/JFK-ORD; the airline's page stays at /performance/<code>): a route's story since launch, so a fare move,
// a new frequency or a rival can be judged by what happened after it. Phone first, by the rules for every screen (spec
// docs/specs/2026-10-20-today-performance-systems.md). Top to bottom: the header (route and city, stars, airline, distance,
// market, the cabin, launched, departures a week each way, the types, each cabin's fare level and this Saturday's move;
// "‹ <airline>" and "Schedule in Routes"); the last 7 days against the 7 before; then its boards, open on arrival: Since
// launch (one chart), Profit an aircraft hour by week, Events, Rivals on the pair and Connections. Every figure is
// route_story()'s (the database's) but the connections, which are the planning library's on the schedule the planner
// reads (the plan card's rule). Its logic is model.ts's ("the route page"). Read only: nothing here saves.
import { useMemo, useState, type ReactNode } from "react";
import { Link } from "react-router";
import { ourAirlines } from "../../data/airlines";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import { niceDate } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { FoldBoard, FoldTools } from "../../ui/FoldBoard";
import { Stars } from "../routes/parts";
import { itemRoute } from "../screens";
import { BarChart, ShareLine, StoryChart } from "./Charts";
import {
  ROUTE_BOARDS, STORY_MIN_DAYS, eventWords, listCut, parseRouteKey, rivalLines, routeConnections, shareLine, storyChartLayout, storyHeader,
  storyWeekOnWeek, weekBars, type RouteBoardKey, type RouteStory,
} from "./model";
import { useRouteAt, useRouteStory } from "./reads";

const firstError = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;
/** A moment's UTC day as words: "Tue, Oct 14". */
const dayOf = (iso: string): string => niceDate(String(iso).slice(0, 10));

const NOTES: Record<RouteBoardKey, string> = {
  "Since launch": "economy and business loads by UTC day, both directions together, from the daily history · the fare level (right) from the fare plan's ladder rows · a dot under a day is an event: point at a day for its figures and events",
  "Profit an aircraft hour": "each week's profit ÷ the block hours flown, the 7 days to the latest captured day and the 12 weeks before · the airline's average isn't drawn: route profit covers only the last few days",
  "Events": "newest first: the schedule's saves (frequencies, aircraft, times), the fare plan, the cabin, and rivals starting or growing on the pair between world scans",
  "Rivals on the pair": "every other airline flying it either way in the latest world scan, passenger flights only, against the week-before scan, with its one-stop connecting departures beside (never added) · our share at each scan since launch",
  "Connections": "the city pairs its flights connect to at each end, from the minimum connection time up to the longest wait, across all our airlines' schedules (the plan card's rule)",
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
  const [folded, setFolded] = useState<ReadonlySet<RouteBoardKey>>(() => new Set());
  const toggle = (k: RouteBoardKey) => setFolded((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const s = storyQ.data;
  const rules = rulesQ.data?.rules;
  const conns = useMemo(() => (s && rules ? routeConnections(rules, { id: s.route.id, hub: s.route.hub, dest: s.route.dest }) : null), [s, rules]);

  const noAirline = !!airlinesQ.data && !airline;
  const noRoute = !key || (routeQ.isSuccess && routeQ.data === null);
  const ready = noAirline || noRoute || !!(s && conns);
  const loadError = firstError(world, airlinesQ, routeQ, storyQ, rulesQ);
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
      {s && airline ? <RouteStoryView s={{ ...s, route: { ...s.route, airline: { ...s.route.airline, name: airline.name } } }} code={code} back={back} conns={conns} board={board}
        onCollapse={() => setFolded(new Set(ROUTE_BOARDS))} onExpand={() => setFolded(new Set())} /> : null}
    </main>
  );
}

/** The route page below its reads: the header, the week's comparison and the boards (exported for its render test). */
export function RouteStoryView({ s, code, back, conns, board, onCollapse, onExpand }: {
  s: RouteStory;
  code: string;
  back: ReactNode;
  conns: ReturnType<typeof routeConnections> | null;
  board: (k: RouteBoardKey, children: ReactNode, figure: string, note?: ReactNode) => ReactNode;
  onCollapse: () => void;
  onExpand: () => void;
}) {
  const h = storyHeader(s, (d) => niceDate(d));
  const wk = storyWeekOnWeek(s);
  const chart = storyChartLayout(s, (d) => niceDate(d));
  const bars = weekBars(s, (d) => niceDate(d));
  const rv = rivalLines(s, dayOf);
  const share = shareLine(s.rivals.shares, dayOf);
  const [eventsOpen, setEventsOpen] = useState(false);
  const ev = listCut(s.events, eventsOpen);
  return (
    <>
      <div className="perfnav" data-route-links>
        {back}
        <Link className="link" to={itemRoute("routes", { airline: code, hub: s.route.hub, dest: s.route.dest })} data-schedule>Schedule in Routes</Link>
      </div>
      <div className="vh rphead" data-figure="performance route: header">
        <p className="vk">Performance · a route</p>
        <h1>{h.title} <span className="city">{h.city}</span></h1>
        <p className="rpline">{s.route.stars != null ? <><Stars n={s.route.stars} />{" "}</> : null}{h.line}</p>
        <p className="rpline">{h.launched} · {h.departures}{h.types ? ` · ${h.types}` : ""}{s.route.removed ? " · removed from the list" : ""}</p>
        {h.fares.length ? <p className="rpline" data-fares>{h.fares.join("; ")}</p> : null}
      </div>
      <section className="rpweek" data-figure="performance route: last 7 days" data-compared={wk.compared ? "yes" : "no"}>
        <div className="rpweekh dim">
          {wk.from && wk.to ? `The last 7 days (${niceDate(wk.from)} to ${niceDate(wk.to)}) against the 7 before` : "No flights in the last 7 days"}
          {wk.from && !wk.compared ? ": no week before to compare" : ""}{wk.days ? ` (${wk.days})` : ""}
        </div>
        <div className="rpwgrid">
          {wk.rows.map((r) => (
            <div key={r.key} className="rpw" data-wk={r.key}>
              <div className="dim">{r.label}</div>
              <div className="rpwv"><b>{r.now}</b> <span className={"wow" + (r.arrow ? " " + r.arrow : "")}>{r.text}</span></div>
              <div className="dim rpwt">{r.then === "—" ? "" : `was ${r.then}`}</div>
            </div>
          ))}
        </div>
      </section>
      <FoldTools onCollapse={onCollapse} onExpand={onExpand} />
      {board("Since launch", chart ? <StoryChart g={chart} /> : (
        <div className="dim" data-story-short>{s.days.length ? `${s.days.length} day${s.days.length === 1 ? "" : "s"} with flights so far` : "No flights in the daily history yet"}: the chart starts once there are {STORY_MIN_DAYS}.</div>
      ), "performance route: since launch board")}
      {board("Profit an aircraft hour", <BarChart pts={bars} avg={null} unit="k" figure="performance route: profit an aircraft hour" empty="No week with block hours yet." />,
        "performance route: weeks")}
      {board("Events", s.events.length ? (
        <div data-list="route events" data-list-rows={s.events.length} data-list-shown={ev.shown.length}>
          <ul className="rpevents">
            {ev.shown.map((e, i) => (
              <li key={i} data-event-kind={e.kind}><b>{niceDate(e.day)}</b> <span className="dim">·</span> {eventWords(e)}</li>
            ))}
          </ul>
          {ev.button ? <button type="button" className="link gmore" data-list-more onClick={() => setEventsOpen((x) => !x)}>{ev.button}</button> : null}
        </div>
      ) : <div className="dim">Nothing has happened on it yet.</div>, "performance route: events")}
      {board("Rivals on the pair", (
        <div className="rprivals">
          <div className="dim">{rv.scans}</div>
          {rv.none ? <div className="rpnone">{rv.connecting ? "No rival flies this pair or connects on it." : "No rival flies this pair."}</div> : (
            <div className="tscroll">
              <table className="tbl rptbl" data-figure="performance route: rivals">
                <tbody>
                  <tr><th>Rival</th><th className="num">Direct a week</th><th className="num">Change</th>{rv.connecting ? <th className="num">Connecting</th> : null}</tr>
                  {rv.rows.map((r) => (
                    <tr key={r.id} data-rival={r.only ? undefined : r.name} data-connecting-rival={r.only ? r.name : undefined}><td>{r.name}</td><td className="num">{r.weekly}</td>
                      <td className="num">{r.change}{r.before != null && r.change && r.change !== "=" ? <span className="dim">{` from ${r.before}`}</span> : null}</td>
                      {rv.connecting ? <td className="num" data-connecting={r.connecting}>{r.connecting}{r.via ? <span className="dim">{` ${r.via}`}</span> : null}</td> : null}</tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {rv.connectingLine ? <div className="dim" data-connecting-line>{rv.connectingLine}</div> : null}
          <div className="rpours">{rv.ours}</div>
          {share ? <div className="rpshare"><span className="dim">our share at each scan since launch</span><ShareLine s={share} /></div>
            : <div className="dim">{s.rivals.shares.length === 1 ? `one scan since launch: ${s.rivals.shares[0]?.share ?? "—"}%` : "no scan since launch yet"}</div>}
        </div>
      ), "performance route: rivals board")}
      {board("Connections", conns ? (
        <div className="rpconns" data-figure="performance route: connections">
          {conns.map((e) => (
            <div key={e.at} className="rpend" data-end={e.at}>
              <div className="rpendh"><b>{`At ${e.at}`}</b> <span className="dim">{e.pairs ? `${e.pairs} city pair${e.pairs === 1 ? "" : "s"}` : "no connection"}</span></div>
              {e.top.length ? (
                <div className="tscroll">
                  <table className="tbl rptbl">
                    <tbody>
                      <tr><th>City pair</th><th className="num" title={`from ${e.other} on to the city, a week`}>Onward</th><th className="num" title={`from the city on to ${e.other}, a week`}>Feeding</th></tr>
                      {e.top.map((c) => (
                        <tr key={c.city} data-conn={`${e.at}:${c.city}`}><td>{`${e.other}–${c.city}`}</td><td className="num">{c.to || "—"}</td><td className="num">{c.from || "—"}</td></tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : null}
              {e.pairs > e.top.length ? <div className="dim rpmore">{`the top ${e.top.length} of ${e.pairs}, by times a week`}</div> : null}
            </div>
          ))}
        </div>
      ) : <div className="dim">Reading the schedule…</div>, "performance route: connections board")}
    </>
  );
}
