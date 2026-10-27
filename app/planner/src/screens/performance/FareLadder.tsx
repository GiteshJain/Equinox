// Performance → the fare ladder (manual §5, since 21 Oct; spec docs/specs/2026-10-21-fare-ladder.md §3): for each airline,
// this Saturday's moves in one line and how many changes to make in the game, the game actions (Ticket price adjustment,
// baseline default price), numbered, each copyable, Put on the fare plan (one planner_save() call: model.ts's
// ladderPlanChanges), and the routes table (route, cabin, level with its steps above launch, the sold-out share, the move
// and its reason), sortable; the actions and the routes each cut to 10 rows with "show all" as the growth lists are. Since
// 21 Oct (spec docs/specs/2026-10-21-fare-actions-by-route.md) the actions are route by route only, never a whole base:
// each direction its own action, naming the classes it changes. Since 21 Oct (spec
// docs/specs/2026-10-21-frequencies-and-fares.md §3) the changes that set a route back to its level (its captured fares
// don't match it) come first, in their own short list ("3 routes off their level"), each with why; the heading counts
// them with the moves. Every level, move and action is fare_ladder()'s. Colour only for action: a step down in amber, a
// step up plain. The moves never appear on Today or in Needs attention. Since 22 Oct (spec
// docs/specs/2026-10-22-planner-look-performance.md §3) one card per airline: its moves as three counts, the changes to
// make, Put on the fare plan and See the changes, which opens the lists below the card. Since 23 Oct (spec
// docs/specs/2026-10-23-fare-ladder-under-launch.md §4) the card also counts the week's jumps under launch and the
// cut-or-keep decisions ("2 jumps, 1 decision"), the routes table words a jump and the hold after a jump, and a row that
// is a decision for Gitesh shows "cut or keep?" beside its reason (since 26 Oct, spec
// docs/specs/2026-10-26-under-launch-by-loads.md, judged by loads: no revert). Nothing goes to Today's Needs attention.
// Since 26 Oct (spec docs/specs/2026-10-26-fare-ladder-per-direction.md §3) each direction of each cabin has its own level:
// the routes table has a row per direction and cabin, its route shown as "EDI → FRA" (the airports that way round, linking
// to the route's page), with its own sold out, Load (that direction's average load over the 7 days), level, move and why;
// the counts, the game actions (one per direction) and Put on the fare plan (with each row's direction) follow.
// Since 26 Oct (spec docs/specs/2026-10-26-fare-ladder-one-airline.md) the board is on each airline's page, for that
// airline only, under its scorecard (the group page has a link to each): all six at once timed out together.
import { useState } from "react";
import { Link } from "react-router";
import type { OurAirline } from "../../data/airlines";
import { AirlineMark } from "../../ui/AirlineMark";
import { niceDate } from "../../ui/dates";
import { showMessage } from "../../ui/messages";
import { itemRoute } from "../screens";
import {
  LADDER_SORTS, changesWords, decideWords, directionWords, ladderKey, ladderRows, levelWords, listCut, loadWords, moveWords, offLevelWords, planButton,
  plannedWords, soldWords, splitActions, underLaunchLine,
  type LadderAction, type LadderAnswer, type LadderSort,
} from "./model";

/** The board: one card per airline given (since 26 Oct the airline page's one), in the airlines' order, in a two-column grid (one on a phone). Since 22 Oct (spec
 *  docs/specs/2026-10-22-planner-look-performance.md §3) each card shows only its moves as three counts, how many
 *  changes to make in the game and its two actions; **See the changes** opens the long lists (the set-back changes,
 *  the game actions, the routes table with its sorts) right below the card's row. */
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
      <div className="flgrid">
        {shown.map((a) => <Airline key={a.id} airline={a} ladder={ladders.get(a.id) as LadderAnswer} busy={busy} onPlan={() => onPlan(a, ladders.get(a.id) as LadderAnswer)} />)}
      </div>
      {notes.length ? <div className="note flnotes">{notes.join(" ")}</div> : null}
    </div>
  );
}

/** One airline's card and, once opened, its changes beneath (both inside one section with no box of its own, so each
 *  is a cell of the grid: the opened part takes the whole row under the card's). */
function Airline({ airline, ladder, busy, onPlan }: { airline: OurAirline; ladder: LadderAnswer; busy: boolean; onPlan: () => void }) {
  const [sort, setSort] = useState<LadderSort>("move");
  const [open, setOpen] = useState(false);
  const [seen, setSeen] = useState(false);
  const code = airline.code ?? String(airline.id);
  const rows = ladderRows(ladder.routes, sort);
  const cut = listCut(rows, open);
  const btn = planButton(ladder);
  const { fixes, moves } = splitActions(ladder.actions);
  const m = ladder.moves;
  const ul = underLaunchLine(m);
  const panel = `ladder-${code}`;
  return (
    <section className="flair" data-ladder={code}>
      <div className={"flcard" + (seen ? " on" : "")}>
        <h3 className="flh"><AirlineMark color={airline.color} />{airline.name}</h3>
        <div className="flmoves" data-ladder-moves={code}>
          <span className="flc"><b>{m.up}</b> up</span><span className="sr">, </span>
          <span className="flc"><b>{m.hold}</b> hold</span><span className="sr">, </span>
          <span className={"flc" + (m.down ? " down" : "")}><b>{m.down}</b> down</span>
        </div>
        {ul ? <div className="flchg" data-ladder-under={code}><span className="sr">· </span>{ul}</div> : null}
        <div className="flchg" data-ladder-changes={code}><span className="sr">· </span>{changesWords(ladder.actions.length)}</div>
        <div className="fltools">
          <button type="button" className="primary sm" data-ladder-plan={code} disabled={busy || !btn.enabled} onClick={onPlan}>{btn.text}</button>
          <button type="button" className="secondary sm" data-ladder-open={code} aria-expanded={seen} aria-controls={panel} onClick={() => setSeen(!seen)}>
            {seen ? "Hide the changes" : "See the changes"}</button>
        </div>
        {btn.note ? <div className="dim flnote">{btn.note}</div> : null}
      </div>
      {seen ? (
        <div className="flpanel" id={panel} data-ladder-panel={code}>
          <h4 className="tph"><AirlineMark color={airline.color} />{airline.name}: the changes</h4>
          <Fixes code={code} fixes={fixes} />
          <Actions code={code} actions={moves} fixesFirst={fixes.length > 0} />
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
                      <tr><th>Route</th><th>Cabin</th><th>Level</th><th className="num">Sold out</th><th className="num">Load</th><th>Move</th><th>Why</th></tr>
                      {cut.shown.map((r) => {
                        const mv = moveWords(r), p = plannedWords(r, (d) => niceDate(d)), dk = decideWords(r);
                        return (
                          <tr key={ladderKey(r)} data-ladder-row={`${r.from}-${r.to} ${r.cabin}`} data-move={r.move} data-direction={r.direction}
                            data-ladder-kind={r.ladder_kind ?? r.move}>
                            <td><Link className="link" to={itemRoute("routes", { airline: airline.code, hub: r.hub, dest: r.dest })}><b>{directionWords(r)}</b></Link></td>
                            <td>{r.cabin}</td>
                            <td>{levelWords(r.level, r.steps)}{r.index_matches === false && r.fare_index != null
                              ? <> <span className="dim" data-ladder-index={`${r.from}-${r.to} ${r.cabin}`}
                                  title="each flight of the latest captured day in this direction against its fare on 21 Oct (or its first, launched later), times the launch level: a flight more than a point off the level">· index {Math.round(r.fare_index)}{r.fix ? " · set back" : ""}</span></> : null}</td>
                            <td className="num">{soldWords(r)}</td>
                            <td className="num" data-ladder-load={`${r.from}-${r.to} ${r.cabin}`}>{loadWords(r)}</td>
                            <td><span className={mv.kind === "down" ? "pill warn sm" : mv.kind === "up" ? "flup" : "dim"}>{mv.text}</span>{p ? <> <span className="dim">· {p}</span></> : null}</td>
                            <td className="dim">{dk ? <><span className="pill warn sm" data-ladder-decide={`${r.from}-${r.to} ${r.cabin}`}>{dk}</span> </> : null}{r.reason}</td>
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
        </div>
      ) : null}
    </section>
  );
}

/** Copies an action's words, or shows them where the browser won't copy. */
function copyAction(a: LadderAction) {
  const done = () => showMessage(`Copied: ${a.text}`);
  try {
    const p = navigator.clipboard?.writeText(a.text);
    if (p) void p.then(done, () => showMessage(a.text));
    else showMessage(a.text);
  } catch {
    showMessage(a.text);
  }
}

/** The set-back changes (since 21 Oct): directions whose captured fares don't match their level (since 26 Oct each
 *  direction its own level), each its own change at its level, numbered as fare_ladder() numbers them (first), each with why and a copy button; cut to
 *  10 as the other lists. Nothing when every route is at its level. */
function Fixes({ code, fixes }: { code: string; fixes: readonly LadderAction[] }) {
  const [open, setOpen] = useState(false);
  if (!fixes.length) return null;
  const cut = listCut(fixes, open);
  return (
    <div className="flacts flfix" data-ladder-fixes={code} data-list={`fixes ${code}`} data-list-rows={fixes.length} data-list-shown={cut.shown.length}>
      <div><b data-ladder-off={code}>{offLevelWords(fixes)}</b> <span className="dim">· set back first: the captured fares don't match the level (a flight the game priced
        otherwise, or a change not made). Ticket price adjustment, default price, each direction on its own.</span></div>
      <ol>
        {cut.shown.map((a) => (
          <li key={a.n} value={a.n} data-action={a.n} data-route={a.route} data-way={`${a.from}>${a.to}`} data-classes={a.classes.join(" ")} data-fix="yes">
            <span className="fltext">{a.text}</span> <span className="dim">· {a.reason ?? "off its level"}</span>{" "}
            <button type="button" className="link sm" data-copy-action={a.n} onClick={() => copyAction(a)}>copy</button>
          </li>
        ))}
      </ol>
      {cut.button ? <button type="button" className="link gmore" data-list-more={`fixes ${code}`} aria-expanded={open} onClick={() => setOpen(!open)}>{cut.button}</button> : null}
    </div>
  );
}

/** The game actions, numbered, each with its own copy button; the first 10 with "show all N", as the routes table (on the
 *  copy of 20 Oct an airline had 50 to 76, and the screen ran to 15,660 px with them all open). Route by route only, each
 *  direction its own action, its text naming the classes to tick ("economy and business" when both move together). The
 *  set-back changes are in their own list above (fixesFirst). */
function Actions({ code, actions, fixesFirst = false }: { code: string; actions: readonly LadderAction[]; fixesFirst?: boolean }) {
  const [open, setOpen] = useState(false);
  if (!actions.length) return <div className="dim flnone">{fixesFirst ? "No moves to make in the game this Saturday." : "No changes to make in the game this Saturday."}</div>;
  const cut = listCut(actions, open);
  return (
    <div className="flacts" data-ladder-actions={code} data-list={`actions ${code}`} data-list-rows={actions.length} data-list-shown={cut.shown.length}>
      <div className="dim">In the game, Ticket price adjustment with the calculation baseline default price, route by route: each direction on its own, with the classes named ticked.</div>
      <ol>
        {cut.shown.map((a) => (
          <li key={a.n} value={a.n} data-action={a.n} data-route={a.route} data-classes={a.classes.join(" ")}>
            <span className="fltext">{a.text}</span>{" "}
            <button type="button" className="link sm" data-copy-action={a.n} onClick={() => copyAction(a)}>copy</button>
          </li>
        ))}
      </ol>
      {cut.button ? <button type="button" className="link gmore" data-list-more={`actions ${code}`} aria-expanded={open} onClick={() => setOpen(!open)}>{cut.button}</button> : null}
    </div>
  );
}
