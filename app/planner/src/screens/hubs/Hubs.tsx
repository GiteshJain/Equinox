// Hubs (decision #18, build pull request 8; spec docs/specs/2026-10-13-hubs.md): one airport's day and week, every
// departure and arrival of all our airlines against the hub's bank windows, and which city pairs connect there, as the old
// planner's Hubs, from the same data, with the same figures and look:
//   - the toolbar: every base and focus city, the seven days, and the count line (departures and arrivals that day,
//     departures a week against the airport cap, the next free flight-number pair);
//   - a focus city's note; the day strip with the bank windows and a tick for every flight, and the hourly bars; the week in
//     15-minute slots; the day's flights with their bank; the connections by bank.
// Addresses: /planner/hubs and /planner/hubs/<airport>?day=<0-6>, so a link reopens the same board. It only
// reads: everything comes from the start's rules input (rules_input(world, 'flown')) through the planning library
// (hubs.board, hubs.connectionsTable); model.ts only words it. Times are local at the airport, as the old Hubs showed.
import { useMemo, type CSSProperties } from "react";
import { useLocation, useNavigate, useParams } from "react-router";
import { block, hubs, type HubBoard, type HubConnections, type Rules } from "@rules";
import { useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import { ErrorBox } from "../../ui/ErrorBox";
import {
  DAYS, H, capWords, cellClass, connectionsNote, countWords, exampleWords, focusWords, hourLabel, nextWords, parsePlace, pct,
  placePath, regionWords, rowLabel, shade, span,
} from "./model";

export function Hubs() {
  const params = useParams();
  const loc = useLocation();
  const navigate = useNavigate();
  const place = useMemo(() => parsePlace(params["*"] ?? "", loc.search), [params, loc.search]);
  const world = useWorld();
  const rulesQ = useRules(world.data?.id);
  const rules = rulesQ.data?.rules;
  const codes = useMemo(() => (rules ? hubs.airports(rules) : []), [rules]);
  const code = place.code ?? codes[0] ?? "";
  const known = !!rules && codes.includes(code);
  const legs = useMemo(() => (rules ? block.timedLegs(rules) : []), [rules]);
  const board = useMemo(() => (rules && known ? hubs.board(rules, code, place.day, legs) : null), [rules, known, code, place.day, legs]);
  const table = useMemo(() => (rules && known ? hubs.connectionsTable(rules, code, legs) : null), [rules, known, code, legs]);
  const loadError = world.error ?? rulesQ.error;
  const go = (c: string, d: number) => navigate(placePath(c, d));

  return (
    <main className="view hub" data-screen="hubs" data-hubs-ready={board && table ? "yes" : "no"} data-hubs-view={loc.pathname + loc.search}
      data-hub={known ? code : ""} data-day={place.day}>
      <div className="vh"><h1>Hubs</h1><p>Each base's day: banks, arrivals and departures, and which flights connect.</p></div>
      {loadError ? <ErrorBox error={loadError} /> : null}
      {rules && !known && code ? <ErrorBox error={`${code} isn't one of our bases or focus cities.`} /> : null}
      {rules && !codes.length ? <div className="empty">No bases yet.</div> : null}
      {!rules && !loadError ? <div className="empty">Loading…</div> : null}
      {board && table && rules ? (
        <>
          <div className="toolbar">
            <select id="h-hub" aria-label="Base" value={code} onChange={(e) => go(e.currentTarget.value, place.day)}>
              {codes.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
            <div className="seg" role="group" aria-label="Day">
              {DAYS.map((d, i) => (
                <button type="button" key={d} data-day={i} className={place.day === i ? "on" : ""} aria-pressed={place.day === i} onClick={() => go(code, i)}>{d}</button>
              ))}
            </div>
            <span className="count" data-figure="hubs: count">
              {countWords(board)}
              {board.over_cap ? <> <span className="pill bad">over cap</span></> : capWords(board)}
              {nextWords(board)}
            </span>
          </div>
          {board.focus ? <div className="board note" data-figure="hubs: focus city">{focusWords(board)}</div> : null}
          <DayBoard b={board} />
          <WeekBoard b={board} />
          <FlightList b={board} />
          <Connections rules={rules} t={table} />
        </>
      ) : null}
    </main>
  );
}

/** The day strip (bank windows, a tick for every flight) and the hourly bars, scrolling inside their own box on a phone. */
export function DayBoard({ b }: { b: HubBoard }) {
  return (
    <div className="board">
      <div className="hubscroll">
        <div className="hubday">
          <div className="strip" data-figure="hubs: day strip">
            {b.banks.map((w) => [
              <span key={`a${w.n}`} className="win arr" style={{ left: pct(w.arr_start, 1440), width: pct(span(w.arr_start, w.arr_end), 1440) }} title={`arrivals for bank ${w.n}`} />,
              <span key={`d${w.n}`} className="win dep" style={{ left: pct(w.dep, 1440), width: pct(span(w.dep, w.dep_end), 1440) }} title={`bank ${w.n} departures`}>{`B${w.n}`}</span>,
            ])}
            {b.flights.map((x, i) => (
              <span key={i} className={`tick ${x.kind} ${x.bank === 0 ? "off" : ""}`} style={{ left: pct(x.local_min, 1440) }} title={`${x.kind} ${H(x.local_min)} ${x.other}`} />
            ))}
          </div>
          <div className="hours" data-figure="hubs: hours">
            {b.hours.departures.map((n, i) => (
              <div className="hr" key={i}>
                <div className="bar dep" style={{ height: pct(n, b.max_hour) }} />
                <div className="bar arr" style={{ height: pct(b.hours.arrivals[i] ?? 0, b.max_hour) }} />
                <span>{hourLabel(i)}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
      <div className="legend"><span className="sw dep" />departures <span className="sw arr" />arrivals <span className="sw win" />bank windows — orange = departure window, green = arrival window</div>
    </div>
  );
}

/** The week in 15-minute slots, local time, departures over arrivals, shaded by the bank windows. */
export function WeekBoard({ b }: { b: HubBoard }) {
  return (
    <div className="board" data-figure="hubs: week">
      <b>Week at {b.airport}</b> <span className="note">15-minute slots, local time. Top number departs, bottom number lands. Orange = bank departure window, green = arrival window.</span>
      <div className="wgwrap">
        <table className="wg">
          <tbody>
            <tr><th />{Array.from({ length: 24 }, (_, h) => <th key={h} colSpan={4} className="hh">{hourLabel(h)}</th>)}<th>Σ</th></tr>
            {b.week.map((w, d) => (
              <tr key={d} className={d === b.day ? "cur" : ""}>
                <th>{DAYS[d]}</th>
                {w.departures.map((v, i) => {
                  const a = w.arrivals[i] ?? 0;
                  return (
                    <td key={i} style={{ "--k": shade(v + a, b.max_slot) } as CSSProperties} className={cellClass(b, i)}>
                      <span className="d">{v || ""}</span><span className="a">{a || ""}</span>
                    </td>
                  );
                })}
                <td className="sum"><b>{`${w.departures_total}↗ ${w.arrivals_total}↘`}</b></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

/** The day's flights: time, direction, flight, to or from, aircraft and the bank pill. */
export function FlightList({ b }: { b: HubBoard }) {
  return (
    <>
      <div className="tblwrap hubtbl">
        <table className="tbl" data-figure="hubs: flights">
          <tbody>
            <tr><th>Time</th><th /><th>Flight</th><th>To / from</th><th>Tail</th><th>Wave</th></tr>
            {b.flights.map((x, i) => (
              <tr key={i}>
                <td>{H(x.local_min)}</td>
                <td>{x.kind === "dep" ? "↗" : "↘"}</td>
                <td><b>{x.flight_no || "—"}</b></td>
                <td>{x.other}</td>
                <td>{x.registration ?? ""}</td>
                <td>{x.bank == null ? "" : x.bank ? <span className="pill ok">{`bank ${x.bank}`}</span> : <span className="pill bad">off wave</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {!b.flights.length ? <div className="empty">Nothing scheduled at {b.airport} on {DAYS[b.day]}.</div> : null}
    </>
  );
}

/** Which flights connect at the airport, across all our airlines, by bank and outside the banks. */
export function Connections({ rules, t }: { rules: Rules; t: HubConnections }) {
  return (
    <div className="board" data-figure="hubs: connections">
      <h3 className="rh">Connections at {t.airport} <span className="note">{connectionsNote(rules, t)}</span></h3>
      {!t.arrivals || !t.departures ? <div className="dim">No flights both arriving and leaving here yet.</div> : (
        <>
          <div className="tblwrap">
            <table className="tbl">
              <tbody>
                <tr><th>Wave</th><th>Arriving from</th><th>Leaving to</th><th>City pairs</th><th>Examples</th></tr>
                {t.rows.map((r) => (
                  <tr key={r.n} data-bank={r.n}>
                    <td><b>{rowLabel(t, r)}</b></td>
                    <td>{r.arriving_from.length} <span className="dim">{regionWords(r.arriving_regions)}</span></td>
                    <td>{r.leaving_to.length} <span className="dim">{regionWords(r.leaving_regions)}</span></td>
                    <td><b>{r.city_pairs}</b></td>
                    <td className="dim">{exampleWords(r)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="note">Planned aircraft (plan cards) aren't included until they're filed. A city pair counts once, at its shortest connection.</div>
        </>
      )}
    </div>
  );
}
