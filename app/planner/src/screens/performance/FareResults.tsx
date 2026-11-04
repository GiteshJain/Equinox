// Performance → Fare results (since 3 Nov; spec docs/specs/2026-11-03-fare-results.md §2): what the fare ladder has done
// to each direction it repriced, from fare_results(). On each airline's page, a row of its own directly under the fare
// ladder (#fare-results), closed on arrival like the other rows, its title line the answer ("Fares up on 214 directions:
// profit a flight +9% (the rest +1%), about +1.4M a week"). Open: a filter row (All · Load fell · At cap · Frequency
// changed) with a search box like Route profit's, a dot per direction (economy level now across, profit a flight change
// up, the rest of the airline as a line; a dot opens its route page) and the table: route (opening the route page, its
// direction beside it as on the Fare plan table), the levels now, the moves, economy fare, economy load and profit a
// flight before → now, profit a week gained and the flags as small pills. A direction seen too recently has its change
// greyed. Every figure is fare_results()'s; the words are model.ts's.
import { useState } from "react";
import { Link } from "react-router";
import { niceDate } from "../../ui/dates";
import { itemRoute } from "../screens";
import { FareResultsChart } from "./PerfCharts";
import {
  FARE_RESULT_FILTERS, fareFareWords, fareFlagWords, fareLevelWords, fareLoadWords, fareMovesWords, fareProfitWords, fareResultCounts, fareResultsShown, fareWeekWords,
  type FareResultFilter, type FareResultsAnswer,
} from "./model";

export function FareResultsBody({ code, airline, answer, city, onRoute }: {
  code: string | null;
  airline: string;
  answer: FareResultsAnswer;
  city: (code: string) => string;
  onRoute: (hub: string, dest: string) => void;
}) {
  const [filter, setFilter] = useState<FareResultFilter>("all");
  const [q, setQ] = useState("");
  if (!answer.routes.length) {
    return <div className="dim" data-fare-results-none>No fare changes of {airline}'s seen in the game yet. Once a capture sees a fare ladder change, its direction shows here with its loads and profit a flight before and after.</div>;
  }
  const counts = fareResultCounts(answer.routes);
  const shown = fareResultsShown(answer.routes, filter, q, city);
  return (
    <div data-figure="performance: fare results">
      <div className="rpf frf">
        <span className="rpl">Show</span>
        {FARE_RESULT_FILTERS.map(([k, l]) => (
          <button type="button" key={k} className={"mf" + (filter === k ? " on" : "")} data-fare-filter={k} aria-pressed={filter === k} onClick={() => setFilter(k)}>{l} {counts[k]}</button>
        ))}
        <input id="fr-q" className="rpq" placeholder="Filter routes, e.g. JFK or Paris" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Filter the fare results" />
      </div>
      <FareResultsChart rows={shown} baselinePct={answer.totals?.baseline_profit_per_flight_pct ?? null} onPick={onRoute} />
      <div className="tscroll">
        <table className="tbl rptbl frtbl" data-figure="performance: fare results table" data-rows={shown.length}>
          <tbody>
            <tr><th>Route</th><th className="num">Economy level</th><th className="num">Business level</th><th>Moves</th><th className="num">Economy fare</th>
              <th className="num">Economy load</th><th className="num">Profit a flight</th><th className="num">Profit a week</th><th>Flags</th></tr>
            {shown.map((r) => {
              const soon = r.flags.includes("too_soon");
              return (
                <tr key={`${r.from}-${r.to}`} data-fare-result={`${r.from}-${r.to}`} data-direction={r.direction}>
                  <td><Link className="link" to={itemRoute("performance", { airline: code, hub: r.hub, dest: r.dest })} data-route-link title="its route page: the story since launch">
                    <b>{r.hub}–{r.dest}</b></Link> <span className="dim" data-fare-result-dir={r.direction}>{r.direction}</span></td>
                  <td className="num">{fareLevelWords(r.economy_level)}</td>
                  <td className="num">{fareLevelWords(r.business_level)}</td>
                  <td className="dim" title={`first seen in the game ${niceDate(r.moves.first_seen)}`}>{fareMovesWords(r, (d) => niceDate(d))}</td>
                  <td className={"num" + (soon ? " dim" : "")}>{fareFareWords(r)}</td>
                  <td className={"num" + (soon ? " dim" : "")}>{fareLoadWords(r)}</td>
                  <td className={"num" + (soon ? " dim" : "")}>{fareProfitWords(r)}</td>
                  <td className={"num" + (soon ? " dim" : r.profit_week != null && r.profit_week < 0 ? " neg" : "")}><b>{fareWeekWords(r)}</b></td>
                  <td>{r.flags.map((f) => { const w = fareFlagWords(f); return <span key={f} className={`pill ${w.cls} sm`} data-fare-flag={f}>{w.text}</span>; })}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {shown.length ? null : <div className="dim">No direction with that flag.</div>}
      {answer.notes.length ? <div className="note frnotes">{answer.notes.join(" ")}</div> : null}
    </div>
  );
}
