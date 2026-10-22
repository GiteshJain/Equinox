// Today → Coming up (Home's until 20 Oct): the next 14 days of to-dos, with the old filter buttons (the one-week checks
// went on 22 Oct, spec docs/specs/2026-10-22-remove-aircraft-checks.md).
import { useState } from "react";
import { Board } from "../../ui/Board";
import { inDays, niceDate } from "../../ui/dates";
import { UP_FILTERS, UP_LABEL, type UpEvent } from "./comingUp";

export function ComingUp({ events, today }: { events: UpEvent[] | null; today: string }) {
  const [kinds, setKinds] = useState<ReadonlySet<UpEvent["type"]>>(new Set());
  const toggle = (k: UpEvent["type"] | "") => setKinds((s) => {
    if (!k) return new Set();
    const n = new Set(s);
    if (n.has(k)) n.delete(k);
    else n.add(k);
    return n;
  });
  const shown = (events ?? []).filter((e) => !kinds.size || kinds.has(e.type));
  return (
    <Board title="Coming up" note="next 14 days" id="coming-up">
      <div className="mleg upf">
        {UP_FILTERS.map(([k, l]) => (
          <button type="button" key={l} className={"mf" + ((k ? kinds.has(k) : !kinds.size) ? " on" : "")} onClick={() => toggle(k)}>{l}</button>
        ))}
      </div>
      {!events ? <div className="loading">Loading…</div> : shown.length ? (
        <div className="tblwrap">
          <table className="tbl" data-board="coming-up">
            <thead><tr><th className="when">When</th><th>What</th></tr></thead>
            <tbody>
              {shown.map((e, i) => (
                <tr key={`${e.date}|${e.type}|${i}`} data-up={e.type}>
                  <td><b>{niceDate(e.date)}</b> <span className="dim">· {inDays(e.date, today)}</span></td>
                  <td><span className={"evt " + e.type}>{UP_LABEL[e.type]}</span> {e.text}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : <div className="dim">Nothing coming up{kinds.size ? " of those kinds" : ""} in the next 14 days.</div>}
    </Board>
  );
}
