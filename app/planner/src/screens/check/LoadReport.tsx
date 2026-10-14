// Check → Daily load report (the old renderReview's report): one day at a time (‹ ›, the day in the address), every
// departure of the day by airline (the library's loadReport.flightsOn) with its captured loads by class (game_loads), and
// the day's summary: from the captured loads, else from loads typed by hand once the day was marked complete.
import { useEffect, useState } from "react";
import type { DayFlight } from "@rules";
import { AirlineMark } from "../../ui/AirlineMark";
import { niceDate } from "../../ui/dates";
import { loadLogos } from "../../ui/siteFiles";
import { airlineDay, capLine, pctWords, summaryWords, type CheckAirline, type DaySummary } from "./model";
import type { CapturedLoad } from "./reads";

export function LoadReport({ day, flights, summary, airlines, loadOf, onDay, loading }: {
  day: string;
  flights: readonly DayFlight[];
  summary: DaySummary;
  airlines: readonly CheckAirline[];
  loadOf: (f: DayFlight) => CapturedLoad | undefined;
  onDay: (n: number) => void;
  /** The day's loads are still being read. */
  loading: boolean;
}) {
  const [logos, setLogos] = useState<Record<string, string> | null>(null);
  useEffect(() => {
    let alive = true;
    loadLogos().then((l) => { if (alive) setLogos(l); }).catch(() => { if (alive) setLogos({}); });
    return () => { alive = false; };
  }, []);
  const byAl = airlines.map((a) => ({ a, list: flights.filter((f) => f.airline_id === a.id) })).filter((x) => x.list.length);
  return (
    <>
      <div className="toolbar" data-figure="check: load report summary">
        <button type="button" className="secondary" data-lfday="-1" onClick={() => onDay(-1)} aria-label="The day before">‹</button>
        <b style={{ minWidth: 120, textAlign: "center" }} data-lfdate={day}>{niceDate(day)}</b>
        <button type="button" className="secondary" data-lfday="1" onClick={() => onDay(1)} aria-label="The day after">›</button>
        <span className="count">{loading ? "Loading…" : summary.kind === "captured"
          ? <>{summary.departures} departures · {summary.captured} captured · economy {pctWords(summary.economy)} · business {pctWords(summary.business)} · cargo {pctWords(summary.cargo)} · <b>{summary.soldOut}</b> sold out · {summary.under85} under 85%</>
          : summaryWords(summary)}</span>
      </div>
      {!byAl.length ? <div className="empty">No flights scheduled that day.</div> : null}
      {byAl.map(({ a, list }) => {
        const s = airlineDay(list, loadOf);
        return (
          <div className="qcard" key={a.id} data-airline={a.code ?? ""}>
            <div className="qh">
              {logos?.[a.name] ? <img className="alogo" src={logos[a.name]} alt={a.name} style={{ height: 18 }} /> : <><AirlineMark color={a.color} /><b>{a.name}</b></>}
              <span className="dim">
                {s.departures} departure{s.departures === 1 ? "" : "s"}
                {s.captured ? <> · <b>{s.captured} captured</b> · economy {pctWords(s.economy)} · {s.soldOut} sold out</> : null}
                {s.firstWeek ? ` · ${s.firstWeek} in their first week` : null}
              </span>
              <details className="qfl">
                <summary>flights{s.captured ? " with loads by class" : ""}</summary>
                <div className="qlist">
                  {list.map((f, i) => {
                    const c = capLine(loadOf(f));
                    return (
                      <span key={i} className={f.leeway ? "dim" : undefined}>
                        <b>{f.no}</b> {f.from}–{f.to} {f.dep}{c ? <> <span className={"capl" + (c.low ? " low" : "")}>{c.text}</span></> : null}
                      </span>
                    );
                  })}
                </div>
              </details>
            </div>
          </div>
        );
      })}
    </>
  );
}
