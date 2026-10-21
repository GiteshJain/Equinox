// Performance → the fare ladder (manual §5, since 21 Oct; spec docs/specs/2026-10-21-fare-ladder.md §3): for each airline,
// this Saturday's moves in one line, the game actions to make (Ticket price adjustment, baseline default price), numbered
// and in order, each copyable, Put on the fare plan (one planner_save() call: model.ts's ladderPlanChanges), and the
// routes table (route, cabin, level with its steps above launch, the sold-out share, the move and its reason), sortable;
// the actions and the routes each cut to 10 rows with "show all" as the growth lists are. Every level, move and action is fare_ladder()'s. Colour
// only for action: a step down in amber, a step up plain. The moves never appear on Today or in Needs attention.
import { useState } from "react";
import { Link } from "react-router";
import type { OurAirline } from "../../data/airlines";
import { AirlineMark } from "../../ui/AirlineMark";
import { niceDate } from "../../ui/dates";
import { showMessage } from "../../ui/messages";
import { itemRoute } from "../screens";
import {
  LADDER_SORTS, ladderLine, ladderRows, levelWords, listCut, moveWords, planButton, plannedWords, soldWords, type LadderAction, type LadderAnswer, type LadderSort,
} from "./model";

/** The board: one section per airline, in the airlines' order. */
export function FareLadderBoard({ airlines, ladders, busy, onPlan }: {
  airlines: readonly OurAirline[];
  ladders: ReadonlyMap<number, LadderAnswer>;
  busy: boolean;
  onPlan: (airline: OurAirline, ladder: LadderAnswer) => void;
}) {
  const shown = airlines.filter((a) => ladders.has(a.id));
  if (!shown.length) return <div className="dim">No routes on the fare ladder yet.</div>;
  const notes = ladders.get(shown[0]?.id ?? -1)?.notes ?? [];
  return (
    <div data-figure="performance: fare ladder">
      {shown.map((a) => <Airline key={a.id} airline={a} ladder={ladders.get(a.id) as LadderAnswer} busy={busy} onPlan={() => onPlan(a, ladders.get(a.id) as LadderAnswer)} />)}
      {notes.length ? <div className="note flnotes">{notes.join(" ")}</div> : null}
    </div>
  );
}

function Airline({ airline, ladder, busy, onPlan }: { airline: OurAirline; ladder: LadderAnswer; busy: boolean; onPlan: () => void }) {
  const [sort, setSort] = useState<LadderSort>("move");
  const [open, setOpen] = useState(false);
  const code = airline.code ?? String(airline.id);
  const rows = ladderRows(ladder.routes, sort);
  const cut = listCut(rows, open);
  const btn = planButton(ladder);
  return (
    <section className="flair" data-ladder={code}>
      <h4 className="gh"><AirlineMark color={airline.color} />{airline.name} <span className="note" data-ladder-moves={code}>{ladderLine(ladder.moves)}</span></h4>
      <div className="fltools">
        <button type="button" className="primary sm" data-ladder-plan={code} disabled={busy || !btn.enabled} onClick={onPlan}>{btn.text}</button>
        {btn.note ? <span className="dim">{btn.note}</span> : null}
      </div>
      <Actions code={code} actions={ladder.actions} />
      {ladder.routes.length ? (
        <>
          <div className="rpf flsort">
            <span className="rpl">Sort</span>
            {LADDER_SORTS.map(([k, l]) => <button type="button" key={k} className={"mf" + (sort === k ? " on" : "")} data-ladder-sort={k} onClick={() => setSort(k)}>{l}</button>)}
          </div>
          <div data-list={`ladder ${code}`} data-list-rows={rows.length} data-list-shown={cut.shown.length}>
            <div className="tscroll">
              <table className="tbl gtbl fltbl" data-figure={`performance ${airline.name}: fare ladder routes`}>
                <tbody>
                  <tr><th>Route</th><th>Cabin</th><th>Level</th><th className="num">Sold out</th><th>Move</th><th>Why</th></tr>
                  {cut.shown.map((r) => {
                    const m = moveWords(r), p = plannedWords(r, (d) => niceDate(d));
                    return (
                      <tr key={`${r.route_id}|${r.cabin}`} data-ladder-row={`${r.hub}-${r.dest} ${r.cabin}`} data-move={r.move}>
                        <td><Link className="link" to={itemRoute("routes", { airline: airline.code, hub: r.hub, dest: r.dest })}><b>{r.hub}–{r.dest}</b></Link></td>
                        <td>{r.cabin}</td>
                        <td>{levelWords(r.level, r.steps)}{r.index_matches === false && r.fare_index != null
                          ? <> <span className="dim" title="the latest captured fare against the first, times the launch level: the level recorded doesn't match it">· index {Math.round(r.fare_index)}</span></> : null}</td>
                        <td className="num">{soldWords(r)}</td>
                        <td><span className={m.kind === "down" ? "pill warn sm" : m.kind === "up" ? "flup" : "dim"}>{m.text}</span>{p ? <> <span className="dim">· {p}</span></> : null}</td>
                        <td className="dim">{r.reason}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            {cut.button ? <button type="button" className="link gmore" data-list-more={`ladder ${code}`} aria-expanded={open} onClick={() => setOpen(!open)}>{cut.button}</button> : null}
          </div>
        </>
      ) : <div className="dim">No routes on the ladder yet: they join once they fly.</div>}
    </section>
  );
}

/** The game actions, numbered and in order, each with its own copy button; the first 10 with "show all N", as the routes
 *  table (on the copy of 20 Oct an airline had 50 to 76, and the screen ran to 15,660 px with them all open). */
function Actions({ code, actions }: { code: string; actions: readonly LadderAction[] }) {
  const [open, setOpen] = useState(false);
  if (!actions.length) return <div className="dim flnone">No changes to make in the game this Saturday.</div>;
  const cut = listCut(actions, open);
  const copy = (a: LadderAction) => {
    const done = () => showMessage(`Copied: ${a.text}`);
    try {
      const p = navigator.clipboard?.writeText(a.text);
      if (p) void p.then(done, () => showMessage(a.text));
      else showMessage(a.text);
    } catch {
      showMessage(a.text);
    }
  };
  return (
    <div className="flacts" data-ladder-actions={code} data-list={`actions ${code}`} data-list-rows={actions.length} data-list-shown={cut.shown.length}>
      <div className="dim">In the game, Ticket price adjustment with the calculation baseline default price, in this order ({actions.length}):</div>
      <ol>
        {cut.shown.map((a) => (
          <li key={a.n} value={a.n} data-action={a.n} data-kind={a.kind}>
            <span className="fltext">{a.text}</span>{a.kind === "base" ? <span className="dim"> · the whole base</span> : null}{" "}
            <button type="button" className="link sm" data-copy-action={a.n} onClick={() => copy(a)}>copy</button>
          </li>
        ))}
      </ol>
      {cut.button ? <button type="button" className="link gmore" data-list-more={`actions ${code}`} aria-expanded={open} onClick={() => setOpen(!open)}>{cut.button}</button> : null}
    </div>
  );
}
