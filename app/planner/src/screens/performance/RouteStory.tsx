// The route's story, shared (spec docs/specs/2026-10-30-route-story-on-routes.md): the last 7 days' tiles and every board of
// Performance's route page, drawn from route_story(), route_loads() and the start's input, so Routes' route detail shows the
// same boards with the same figures (nothing is worked out a second time). Performance's route page (RoutePage.tsx) shows
// all ten in ROUTE_BOARDS' order; Routes (RouteStoryPanel) shows ROUTES_STORY_BOARDS: the tiles, Since launch, Load by
// direction, Rival fares, Market share, Rivals over time, Loads by flight and Profit an aircraft hour, with "Full story ›"
// to the route page. Every board says so when it has no data, as on the route page. Read only: nothing here saves.
import { useMemo, useState, type ReactNode } from "react";
import { Link } from "react-router";
import type { Rules } from "@rules";
import { niceDate } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { itemRoute } from "../screens";
import { Donut, donutLayout } from "../../ui/charts";
import { BarChart, DirChart, HistoryChart, ShareLine, StoryChart, WeeksChart } from "./Charts";
import {
  NO_MARKET_READ, STORY_MIN_DAYS, dirChartLayout, eventWords, shareDonut, flightLoads, historyLayout, listCut, marketShareView, rivalFares, rivalLines,
  shareLine, shareWeeklyNote, storyChartLayout, storyWeekOnWeek, weekBars, weeksLayout,
  type FlightLoadRow, type FlightLoads, type RouteBoardKey, type RouteEnd, type RouteStory,
} from "./model";
import { useRouteStory } from "./reads";

/** A moment's UTC day as words: "Tue, Oct 14". */
export const dayOf = (iso: string): string => niceDate(String(iso).slice(0, 10));

/** The boards Routes' route detail shows, in its order (spec docs/specs/2026-10-30-route-story-on-routes.md): not Events,
 *  Rivals on the pair or Connections, which Routes has already or belong to the route page. */
export const ROUTES_STORY_BOARDS = ["Since launch", "Load by direction", "Rival fares", "Market share", "Rivals over time", "Loads by flight",
  "Profit an aircraft hour"] as const satisfies readonly RouteBoardKey[];

/** The last 7 days against the 7 before, as tiles (the route page's, and Routes' story column's). */
export function WeekTiles({ s }: { s: RouteStory }) {
  const wk = storyWeekOnWeek(s);
  return (
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
  );
}

/** Every board's content and its figure's name, from one story: the route page's ten, of which Routes shows some. */
export function useStoryBoards(s: RouteStory, x: { flights?: readonly FlightLoadRow[] | null; conns?: readonly RouteEnd[] | null; color?: string | null }): Record<RouteBoardKey, { figure: string; content: ReactNode }> {
  const flights = x.flights ?? null, conns = x.conns ?? null, color = x.color ?? undefined;
  const chart = storyChartLayout(s, (d) => niceDate(d));
  const bars = weekBars(s, (d) => niceDate(d));
  const rv = rivalLines(s, dayOf);
  const share = shareLine(s.rivals.shares, dayOf);
  const weeklyNote = shareWeeklyNote(s.rivals.shares, s.rivals.daily_from, dayOf);
  const [eventsOpen, setEventsOpen] = useState(false);
  const ev = listCut(s.events, eventsOpen);
  const dir = dirChartLayout(s, (d) => niceDate(d));
  const fares = rivalFares(s, dayOf);
  const shares = marketShareView(s);
  const hist = historyLayout(s, dayOf);
  const weeks = weeksLayout(s);
  const out = `${s.route.hub} → ${s.route.dest}`, ret = `${s.route.dest} → ${s.route.hub}`;
  const short = (attr: string) => (
    <div className="dim" {...{ [attr]: "" }}>{s.days.length ? `${s.days.length} day${s.days.length === 1 ? "" : "s"} with flights so far` : "No flights in the daily history yet"}: the chart starts once there are {STORY_MIN_DAYS}.</div>
  );
  const noRead = <div className="dim" data-no-market>{NO_MARKET_READ}</div>;
  return {
    "Since launch": { figure: "performance route: since launch board", content: (
      chart ? <StoryChart g={chart} /> : (
              short("data-story-short")
            )
    ) },
    "Load by direction": { figure: "performance route: load by direction board", content: (
      dir ? <DirChart g={dir} out={out} back={ret} /> : short("data-dir-short")
    ) },
    "Loads by flight": { figure: "performance route: loads by flight board", content: (
      flights == null ? <div className="dim">Reading the loads…</div> : flights.length ? (
              <div className="tscroll">
                <table className="tbl rptbl rpflights" data-figure="performance route: loads by flight">
                  <tbody>
                    <tr><th>Flight</th><th>Way</th><th>Departs</th><th>Average load</th><th className="num">Flights</th><th className="num" title="departures at 95% or more">95%+</th></tr>
                    {flights.map((f) => (
                      <tr key={f.flight_no} data-flight={f.flight_no} data-direction={f.direction}>
                        <td>{`${s.route.airline.code ?? ""} ${f.flight_no}`.trim()}</td><td>{`${f.from}→${f.to}`}</td><td>{f.dep_local ?? "—"}</td>
                        <td><span className="rpbar" role="img" aria-label={`${f.average}%`}><i style={{ width: `${Math.max(0, Math.min(100, f.average))}%` }} /></span> {`${f.average}%`}</td>
                        <td className="num">{f.departures}</td><td className="num">{f.full}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : <div className="dim">No flight on it with loads in the last 7 days.</div>
    ) },
    "Profit an aircraft hour": { figure: "performance route: weeks", content: (
      <BarChart pts={bars} avg={null} unit="k" figure="performance route: profit an aircraft hour" empty="No week with block hours yet." />
    ) },
    "Rival fares": { figure: "performance route: rival fares board", content: (
      fares.none ? noRead : (
              <div className="rpfares" data-figure="performance route: rival fares">
                <div className="dim">{`latest market read ${fares.read ?? "—"}`}</div>
                {fares.tables.map((t) => (
                  <div key={t.direction} className="rpfdir" data-fares-direction={t.direction}>
                    <div className="rpendh"><b>{t.label}</b> <span className="dim">{t.read ? `read ${t.read}` : "not read"}</span></div>
                    {t.rows.length ? (
                      <div className="tscroll">
                        <table className="tbl rptbl">
                          <tbody>
                            <tr><th>Airline</th><th className="num">Economy</th><th className="num">Business</th><th className="num">Flights</th><th className="num" title="economy flights sold out of those finished">Sold out</th></tr>
                            {t.rows.map((r) => (
                              <tr key={r.key} className={r.ours ? "ours" : undefined} data-fare-airline={r.name} data-ours={r.ours ? "yes" : undefined}>
                                <td>{r.ours ? <b>{r.name} (ours)</b> : r.name}</td><td className="num">{r.eco}</td><td className="num">{r.bus}</td>
                                <td className="num">{r.flights}</td><td className="num">{r.sold}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    ) : <div className="dim">{t.read ? "No flight on the page." : "This direction wasn't read."}</div>}
                    {t.vs ? <div className="rpvs" data-vs>{t.vs}</div> : null}
                  </div>
                ))}
              </div>
            )
    ) },
    "Market share": { figure: "performance route: market share board", content: (
      (
              <div className="rpmshare" data-figure="performance route: market share">
                {shares.none ? noRead : shares.dirs.map((d) => (
                  <div key={d.direction} className="rpmsd" data-share-direction={d.direction}>
                    <div className="rpendh"><b>{d.label}</b> <span className="dim">{d.week ? `week ${Number(d.week.slice(5))}` : ""}</span></div>
                    <div className="rpmsv"><b>{d.ours == null ? "—" : `${Math.round(d.ours * 10) / 10}%`}</b> <span className="dim">ours</span>{d.change ? <> <span className="wow">{d.change}</span></> : null}
                      {d.before != null ? <span className="dim">{` (from ${Math.round(d.before * 10) / 10}%)`}</span> : null}</div>
                    {(() => {
                      const parts = shareDonut(d, color), dot = new Map(parts.map((p) => [p.label, p.color]));
                      const grey = dot.get("others") ?? "#C9CEDB";
                      return (
                        <div className={"cpdonut" + (parts.length ? "" : " none")} data-share-donut={d.direction}>
                          {parts.length ? <Donut g={donutLayout(parts, { size: 120, ring: 20, fmt: (v) => `${Math.round(v * 10) / 10}% of passengers` })}
                            middle={d.ours == null ? "—" : `${Math.round(d.ours)}%`} label={`${d.label}: the game's passenger share`} figure="performance route: market share donut" /> : null}
                          <ul className="cprv rpmsl">
                            {d.rows.slice(0, 5).map((r) => (
                              <li key={r.name}><i className="cpdot" style={{ background: dot.get(r.name) ?? grey }} />{r.ours ? <b>{r.name}</b> : r.name} <span className="num">{r.share}</span> <span className="dim">{r.change}</span></li>
                            ))}
                          </ul>
                        </div>
                      );
                    })()}
                  </div>
                ))}
                <div className="dim" data-scan-share>{shares.scan}</div>
              </div>
            )
    ) },
    "Rivals on the pair": { figure: "performance route: rivals board", content: (
      (
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
                {weeklyNote ? <div className="dim" data-weekly-note>{weeklyNote}</div> : null}
              </div>
            )
    ) },
    "Rivals over time": { figure: "performance route: rivals over time board", content: (
      (
              <div className="rphist">
                {hist ? <>
                  <HistoryChart g={hist} />
                  <ul className="rphkey">{hist.series.map((x, i) => <li key={x.key} className={"hs " + (x.ours ? "ours" : `r${Math.min(i, 6)}`)}><i />{x.name}</li>)}</ul>
                </> : <div className="dim">No world scan since launch yet.</div>}
                <div className="rpwks">
                  <div className="dim">the pair's seats offered (bars, both ways) and price per unit (line, right) by week, from the market reads</div>
                  {weeks ? <WeeksChart g={weeks} /> : s.market ? <div className="dim">No week with figures yet.</div> : noRead}
                </div>
              </div>
            )
    ) },
    "Events": { figure: "performance route: events", content: (
      s.events.length ? (
              <div data-list="route events" data-list-rows={s.events.length} data-list-shown={ev.shown.length}>
                <ul className="rpevents">
                  {ev.shown.map((e, i) => (
                    <li key={i} data-event-kind={e.kind}><b>{niceDate(e.day)}</b> <span className="dim">·</span> {eventWords(e)}</li>
                  ))}
                </ul>
                {ev.button ? <button type="button" className="link gmore" data-list-more onClick={() => setEventsOpen((x) => !x)}>{ev.button}</button> : null}
              </div>
            ) : <div className="dim">Nothing has happened on it yet.</div>
    ) },
    "Connections": { figure: "performance route: connections board", content: (
      conns ? (
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
            ) : <div className="dim">Reading the schedule…</div>
    ) },
  };
}

/** One board on Routes: open, with its title (Routes' story column doesn't fold). */
function OpenBoard({ k, figure, children }: { k: string; figure: string; children: ReactNode }) {
  return (
    <section className="board rsboard" data-figure={figure} data-board={k}>
      <h3 className="rh" data-rkey={k}>{k}</h3>
      {children}
    </section>
  );
}

/** The story's boards on Routes, below its reads (exported for its render test). */
export function RouteStoryBoards({ s, code, flights, color }: { s: RouteStory; code: string | null; flights: readonly FlightLoadRow[] | null; color?: string | null }) {
  const boards = useStoryBoards(s, { flights, color });
  return (
    <div className="rstoryin" data-route-story={`${s.route.hub}-${s.route.dest}`}>
      <div className="rsth">
        <b>The route's story</b>
        {code ? <Link className="link" data-full-story to={itemRoute("performance", { airline: code, hub: s.route.hub, dest: s.route.dest })}>Full story ›</Link> : null}
      </div>
      <WeekTiles s={s} />
      {ROUTES_STORY_BOARDS.map((k) => <OpenBoard key={k} k={k} figure={boards[k].figure}>{boards[k].content}</OpenBoard>)}
    </div>
  );
}

/** Routes' story column (since 30 Oct): reads route_story() for the open route only, cached as the route page's (the same
 *  query), and its loads by flight from route_loads()' flights Routes reads already. A route not flown yet shows "Not
 *  flown yet" and reads nothing. */
export function RouteStoryPanel({ routeId, flown, code, rules, loads, color }: {
  routeId: number; flown: boolean; code: string | null; rules: Rules;
  /** The airline's colour, for our share in the market share donuts. */
  color?: string | null;
  /** route_loads()' flights, as Routes reads them (undefined while they're read). */
  loads: readonly FlightLoads[] | undefined;
}) {
  const q = useRouteStory(flown ? routeId : undefined);
  const s = q.data;
  const flights = useMemo(() => (s && loads ? flightLoads(rules, s.route.id, s.route.airline.id, loads) : null), [s, rules, loads]);
  if (!flown) return <div className="rstoryin empty" data-route-story-none>Not flown yet.</div>;
  if (q.error) return <ErrorBox error={q.error} />;
  if (!s) return <div className="rstoryin empty">Reading the route's story…</div>;
  return <RouteStoryBoards s={s} code={code} flights={flights} color={color} />;
}
