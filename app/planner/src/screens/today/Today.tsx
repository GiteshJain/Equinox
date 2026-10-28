// Today (spec docs/specs/2026-10-20-today-performance-systems.md): "what do I do now?", the evening after a capture or
// whenever one lands. The answer at the top (All clear when nothing is waiting: no order possible, nothing to file, no
// attention items, no Game check differences) with the capture in one line (capture_status(), a link to Systems), then
// every board open, the most important first:
//   - Orders: for each airline, whether it can order now or from when (airline_cards()), the types that are safe
//     (cash_forecast()) and each delivery line with when it runs dry (the library's growth.orderQueues; Check → Growth's
//     can order and order queues until 20 Oct);
//   - Aircraft to file: arrived with a plan card, with File into planner, which files it on Tails (Home's until 20 Oct);
//   - Needs attention, moved whole from Home, with dismiss and show again (attention.ts);
//   - Game check, moved from Check (GameCheck.tsx, game.ts);
//   - the to-do board and Coming up, moved from Home.
// Since 28 Oct (spec docs/specs/2026-10-27-long-haul-lines.md §5) Orders also lists each open 7-day line: how many of its
// places are ordered and arrived (Tails' slots, from plan_lines and the plan cards), when its next aircraft can be ordered
// by the cash forecast, and a link to the line on Tails. It adds nothing to the answer's count: an airline that can
// order is counted there already.
// Address: /planner/today, the aircraft pop-up (?aircraft=REG, Tails' AircraftPopup, as Home's needs attention opened it).
// An old load-report address (/planner/check?day=…, which web/_redirects sends here) goes on to Performance's Flights by
// day with its day. Every action is one planner_save() call.
// Since 22 Oct (spec docs/specs/2026-10-22-planner-look-today.md) laid out as the approved mockup: the answer is the
// page's title with the capture as a pill beside it; the things waiting as big cards (until 23 Oct); Orders as
// one table, a column per delivery line (one compact row per airline on a phone); then Aircraft to file and each group
// of needs attention as count tiles (countTiles), each opening its list below them; Game check and the to-dos as before.
// The one-week checks (needs attention's group and Coming up's) went on 22 Oct (spec
// docs/specs/2026-10-22-remove-aircraft-checks.md). Since 22 Oct (spec docs/specs/2026-10-22-fleet-capture.md §3) needs
// attention has a Fleet group from fleet_checks() (the game's figures on the latest night's fleet pages), and the game's
// maintenance under the limit is its own card, the most urgent after order now.
// Since 23 Oct (spec docs/specs/2026-10-23-attention-on-home.md) the summary cards are Home's, not Today's: Today keeps
// every group's full list as its own section with a stable anchor (#to-file, #att-<kind>: model.ts's attentionAnchor),
// which Home's buttons open (the list open, scrolled to it), still with dismiss and show again. The answer's count is
// what's left on Today, a thing per section with something in it. The orders, the aircraft to file and needs
// attention's reads and figures are in useAttention.ts, shared with Home.
import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useLocation, useNavigate, useSearchParams } from "react-router";
import { game } from "@rules";
import type { OurAirline } from "../../data/airlines";
import { useNow } from "../../data/clock";
import { queryClient } from "../../data/query";
import type { Change } from "../../data/save";
import { saver } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { AttentionItems } from "../../ui/AttentionList";
import { groupAttention, type AttItem } from "../../ui/attention";
import { Board } from "../../ui/Board";
import { niceDate, todayAt, untilText } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { itemRoute, movedTo } from "../screens";
import { AircraftPopup } from "../tails/AircraftPopup";
import { flyingIds, gameLink, lineSize, typeName, type TailAircraft } from "../tails/model";
import { readAirlineRoutes, readGameSchedule, readMarkets, readProfiles, useGameHost, usePlanCards as useLineCards, usePlanLines, useTailsAircraft } from "../tails/reads";
import { readAirports } from "../routes/reads";
import { ComingUp } from "./ComingUp";
import { comingUp } from "./comingUp";
import { checkedAtWords, fixChanges, fixRotations, importChanges, noLinkWords, type GameResult } from "./game";
import { GameLines, GameModal, type GameLine, type TailChoice } from "./GameCheck";
import { attentionAnchor, captureLine, countTiles, lineCell, lineColumns, openLines, tileForHash, waitingWords } from "./model";
import { readLegs } from "./reads";
import { TodoBoard } from "./TodoBoard";
import { todoViews } from "./todos";
import { opensAircraft, useAttention } from "./useAttention";

const first = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

export function Today() {
  const loc = useLocation();
  const navigate = useNavigate();
  const [search, setSearch] = useSearchParams();
  const now = useNow();
  const today = todayAt(now);
  // the orders, the aircraft to file and needs attention, read and worked out once for Home and Today (useAttention.ts)
  const att = useAttention(now, today);
  const { w, airlines, airlinesQ, rules, todosQ, itemsQ, captureQ, orders, forecastOf, filing, attShown, hrefOf } = att;
  // Today's own reads beyond those: the game check's aircraft and the game's address; and (since 28 Oct) the 7-day lines
  // and the plan cards with their line and offset, Tails' own reads, for the open lines
  const tailsQ = useTailsAircraft(w);
  const hostQ = useGameHost(w);
  const linesQ = usePlanLines(w);
  const lineCardsQ = useLineCards(w);
  const [busy, setBusy] = useState(false);
  const [gc, setGc] = useState<{ running: boolean; at: Date | null; res: ReadonlyMap<number, GameResult> }>({ running: false, at: null, res: new Map() });
  const [gcOpen, setGcOpen] = useState<number | null>(null);
  // the count tile whose list is open below the tiles (one at a time). Since 23 Oct (spec
  // docs/specs/2026-10-23-attention-on-home.md) Home's needs attention cards open a group's section by its anchor
  // (/planner/today#att-route), as the old "to file on Today" opened Aircraft to file (#to-file)
  const [tile, setTile] = useState<string | null>(() => tileForHash(loc.hash));
  // the airlines whose delivery lines are open on a phone (the table's compact rows)
  const [openRows, setOpenRows] = useState<ReadonlySet<number>>(new Set());
  const tailPopup = search.get("aircraft");
  const setTailPopup = (reg: string | null) => setSearch((s) => {
    const n = new URLSearchParams(s);
    if (reg) n.set("aircraft", reg);
    else n.delete("aircraft");
    return n;
  });

  // an old load-report's day (/planner/check?day=…, sent here by web/_redirects) opens Performance's Flights by day
  const moved = movedTo(loc.pathname, loc.search);
  useEffect(() => { if (moved) navigate(moved, { replace: true }); }, [moved, navigate]);

  const todos = useMemo(() => (todosQ.data && itemsQ.data ? todoViews(todosQ.data, itemsQ.data) : null), [todosQ.data, itemsQ.data]);

  // ---------- Game check (Check's until 20 Oct)
  const all = useMemo(() => tailsQ.data ?? [], [tailsQ.data]);
  const tailList = useMemo(() => all.filter((a) => a.status === "active").sort((a, b) => a.id - b.id), [all]);
  const linkOf = (a: OurAirline) => gameLink(hostQ.data, a.game_id);
  const gameLines: GameLine[] = useMemo(() => {
    if (!rules) return [];
    const out: GameLine[] = [];
    for (const a of airlines) {
      if (!gameLink(hostQ.data, a.game_id)) continue;
      const x = gc.res.get(a.id);
      if (!x) continue;
      if ("error" in x) { out.push({ airline: a, error: x.error }); continue; }
      out.push({ airline: a, cmp: game.compare(rules, a.id, x.flights), cands: game.importCandidates(rules, a.id, x.flights) });
    }
    return out;
  }, [rules, airlines, hostQ.data, gc.res]);
  // ---------- each open 7-day line (since 28 Oct)
  const lines = useMemo(() => (rules && linesQ.data && lineCardsQ.data && tailsQ.data ? openLines({
    airlines, lines: linesQ.data, cards: lineCardsQ.data, aircraft: tailsQ.data, flying: flyingIds(rules), now: now.getTime(),
    sizeOf: (id) => lineSize(rules, id), typeOf: (id) => typeName(rules, id), forecastOf,
  }) : null), [rules, linesQ.data, lineCardsQ.data, tailsQ.data, airlines, now, forecastOf]);
  const differences = gameLines.reduce((n, l) => n + (l.cmp?.issues.length ?? 0), 0);

  async function save(changes: Change[], rulesToo = false) {
    if (!changes.length) return;
    setBusy(true);
    try {
      const res = await saver.save(changes);
      if (res.status === "saved" && rulesToo) void queryClient.invalidateQueries({ queryKey: ["rules"] });
      return res;
    } finally {
      setBusy(false);
    }
  }
  async function runCheck() {
    setGc({ running: true, at: null, res: new Map() });
    const res = new Map<number, GameResult>();
    await Promise.all(airlines.map(async (a) => {
      const link = linkOf(a);
      if (!link) return;
      const r = await readGameSchedule(link);
      res.set(a.id, "flights" in r ? { flights: r.flights } : { error: r.error });
    }));
    setGc({ running: false, at: new Date(), res });
  }
  async function fix(airlineId: number, issues: Parameters<typeof fixRotations>[2]) {
    if (!rules) return;
    const rots = fixRotations(rules, airlineId, issues);
    const legs = await readLegs(rots);
    await save(fixChanges(rules, airlineId, issues, legs), true);
  }
  async function add(airlineId: number, line: GameLine, index: number, choice: TailChoice) {
    const cand = line.cands?.[index];
    if (!rules || !cand || w === undefined) return;
    const mine = tailList.filter((a) => a.airline_id === airlineId);
    const tail = choice.isNew ? { registration: choice.registration, acquired: choice.acquired } : { aircraft: mine.find((a) => a.registration === choice.registration) as TailAircraft };
    if (!choice.isNew && !("aircraft" in tail && tail.aircraft)) return;
    const codes = [...new Set([cand.a.from, cand.a.to, ...(cand.b ? [cand.b.from, cand.b.to] : [])])];
    const [routes, markets, profiles, airports] = await Promise.all([readAirlineRoutes(airlineId), readMarkets(w), readProfiles(w), readAirports(w, codes)]);
    await save(importChanges({
      worldId: w, today, nowMs: Date.now(), rules, airlineId, cand, tail, aircraft: all, tails: mine,
      bases: rules.bases.filter((b) => b.airline_id === airlineId).map((b) => b.airport_code), routes, markets: new Map(markets.map((m) => [m.id, m])), profiles,
      airports: new Map(airports.map((x) => [x.code, x])),
    }), true);
  }
  const missingLinks = airlines.filter((a) => !linkOf(a)).map((a) => a.name);
  const openLine = gcOpen == null ? undefined : gameLines.find((x) => x.airline.id === gcOpen);

  const ready = !!(att.ready && todos && tailsQ.data && hostQ.isSuccess && lines);
  const loadError = att.loadError ?? first(tailsQ, hostQ, linesQ, lineCardsQ);
  const cap = captureQ.data && airlinesQ.data ? captureLine(airlines, captureQ.data, now) : null;
  const groups = attShown ? groupAttention(attShown.shown) : [];
  // the answer counts what's left on Today, a thing per section with something in it (since 23 Oct): Orders when an
  // airline can order, Aircraft to file, each group of needs attention (Can order counted once, with Orders) and Game check
  const waiting = ready && orders && filing && attShown ? waitingWords({
    canOrder: orders.filter((o) => o.status.kind === "now").map((o) => o.airline.name), toFile: filing.length,
    attention: groups.filter((g) => g.kind !== "order").map((g) => ({ label: g.label, count: g.items.length })), game: differences,
  }) : null;

  const tiles = attShown && filing ? countTiles(filing.length, attShown.shown) : null;
  const columns = orders ? lineColumns(orders) : [];
  const openAircraft = (a: AttItem) => { if (!opensAircraft(a) || !a.tail) return false; setTailPopup(a.tail); return true; };
  // arriving at a section's anchor (Home's buttons: a group's See all, #att-<kind>; a to-do, #todo; Game check,
  // #game-check): scroll to it once everything is read and, for a group, its list is open
  const arrived = useRef(false);
  useEffect(() => {
    if (!ready || arrived.current) return;
    arrived.current = true;
    const id = loc.hash.slice(1);
    if (id) requestAnimationFrame(() => document.getElementById(id)?.scrollIntoView({ block: "start" }));
  }, [ready, loc.hash]);

  return (
    <main className="view review today" data-screen="today" data-today-ready={ready ? "yes" : "no"} data-today-view={loc.pathname + loc.search}>
      <div className={"vh todayvh" + (waiting?.clear ? " clear" : "")} data-figure="today: answer" data-all-clear={waiting ? (waiting.clear ? "yes" : "no") : ""}>
        <p className="vk">Every day</p>
        <div className="todayttl">
          <h1 className="ansh">{waiting ? waiting.title : "Today"}</h1>
          {cap ? (
            <div className="capline" data-figure="today: capture" data-capture-state={cap.state} data-mark={cap.mark}>
              <span className={"sysmark " + cap.mark} role="img" aria-label={cap.mark === "ok" ? "green" : cap.mark === "warn" ? "amber" : "red"} />
              <span className="captext">{cap.text}</span> <Link className="link" to={itemRoute("systems")}>Systems ›</Link>
            </div>
          ) : null}
        </div>
        <p className="ansp">{waiting ? (waiting.clear ? "What to do now: the capture, orders, aircraft to file, what needs attention, the game check and the to-dos."
          : waiting.parts.join(" · ")) : "Loading…"}</p>
      </div>
      {loadError ? <ErrorBox error={loadError} /> : null}

      {waiting?.clear ? (
        <section className="waitgrid" aria-label="All clear">
          <div className="wcard clear" data-wait-card="clear">
            <span className="wkind">All clear</span>
            <h2 className="wh">{waiting.parts[0]}</h2>
          </div>
        </section>
      ) : null}

      <Board title="Orders" figure="today: orders" id="orders" className="ordboard"
        note="Safe means the cushion stays in hand at the cash forecast's lowest point. Each line: when its first type is safe, what's on order and when it runs dry (UTC).">
        {!orders ? <div className="loading">Loading…</div> : (
          <div className="ordwrap">
            <table className="tbl ordtbl">
              <thead><tr><th>Airline</th>{columns.map((f) => <th key={f}>{f}</th>)}<th className="ordx"><span className="sr">Cash and safe types</span></th></tr></thead>
              <tbody>
                {orders.map((o) => {
                  const open = openRows.has(o.airline.id);
                  return (
                    <tr className={"ordcard" + (o.status.kind === "now" ? " now" : "") + (open ? " open" : "")} key={o.airline.id} data-orders={o.airline.code ?? ""}>
                      <td className="ordh">
                        <button type="button" className="ordtap" aria-expanded={open}
                          onClick={() => setOpenRows((s) => { const n = new Set(s); if (n.has(o.airline.id)) n.delete(o.airline.id); else n.add(o.airline.id); return n; })}>
                          <AirlineMark color={o.airline.color} size={10} /><b>{o.airline.name}</b>
                          {o.status.kind === "now" ? <span className="pill warn" data-can-order>{o.status.text}</span> : <span className="dim ordst">{o.status.text}</span>}
                          <span className="chev" aria-hidden="true" />
                        </button>
                      </td>
                      {columns.map((f) => {
                        const l = o.lines.find((x) => x.family === f);
                        if (!l) return <td key={f} className="ordc none"><span className="ordfam">{f}</span><span className="dim">—</span></td>;
                        const c = lineCell(l);
                        return (
                          <td key={f} className={"ordc" + (c.warn ? " warn" : "")} data-order-line={l.family}>
                            <span className="ordfam">{f}</span>
                            {c.safe ? (c.safe.now ? <span className="pill now">{c.safe.text}</span> : <span className="ordsafe">{c.safe.text}</span>) : null}
                            <span className={c.dry ? "ordq" : "ordq dim"}>{c.onOrder}</span>
                            {c.dry ? <span className="orddry dim">runs dry {c.dry}{c.soon ? <> · <span className="pill warn sm">{c.soon}</span></> : null}</span> : null}
                          </td>
                        );
                      })}
                      <td className="ordx">
                        {o.airline.code ? <Link className="link" to={itemRoute("performance", { airline: o.airline.code })}>Cash, next 14 days ›</Link> : null}
                        {o.types.length ? (
                          <details className="ordall" data-all-safe={o.airline.code ?? ""}>
                            <summary>all safe types</summary>
                            <div className="ordtypes"><span className="dim">Safe</span> {o.types.map((g, i) => (
                              <span key={g.when}>{i ? <span className="dim"> · </span> : null}{g.now ? <b>{g.when}: {g.names.join(", ")}</b> : <span className="dim">{g.when}: {g.names.join(", ")}</span>}</span>
                            ))}</div>
                          </details>
                        ) : null}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
            {lines?.length ? (
              <div className="ordlines" data-figure="today: open lines">
                <h4 className="ordlh">Lines <span className="note">7 aircraft of one type, each a day apart · next by the cash forecast, the type with its order cabin</span></h4>
                <ul>
                  {lines.map((l) => (
                    <li key={l.key} data-open-line={l.lineId} data-line-ordered={l.ordered} data-line-arrived={l.arrived}>
                      <AirlineMark color={l.airline.color} size={10} />
                      <b>{l.heading}</b>
                      <span className="dim">{l.type}</span>
                      {l.next?.now ? <span className="pill now">{l.nextText}</span> : <span className={l.next ? "ordsafe" : "dim"}>{l.nextText}</span>}
                      <Link className="link" to={l.href} data-line-link>{l.name} on Tails ›</Link>
                    </li>
                  ))}
                </ul>
              </div>
            ) : null}
          </div>
        )}
      </Board>

      <section className="board todaycounts" id="attention" aria-labelledby="att-h">
        <h3 className="rh" id="att-h">
          <span className="rht">Needs attention</span>
          <span className="note">{attShown ? (attShown.shown.length ? `${attShown.shown.length} item${attShown.shown.length === 1 ? "" : "s"}, and the aircraft to file · tap a tile to see its list` : "nothing right now") : ""}</span>
        </h3>
        {!tiles || !attShown || !ready ? <div className="loading">Loading…</div> : (
          <>
            <div className="tiles" role="group" aria-label="Aircraft to file and needs attention">
              {tiles.map((t) => (
                <button type="button" key={t.key} className={"tile " + t.cls + (tile === t.key ? " on" : "")} aria-expanded={tile === t.key}
                  aria-controls={attentionAnchor(t.key)} data-att-tile={t.key} onClick={() => setTile((k) => (k === t.key ? null : t.key))}>
                  <b className="tn">{t.count}</b>
                  <span className="tname">{t.name}</span>
                  <span className="tline">{t.line}</span>
                </button>
              ))}
            </div>
            {attShown.hidden ? (
              <div className="dim hiddenline" data-dismissed={attShown.hidden}>
                {attShown.hidden} dismissed · <button type="button" className="link" onClick={() => void att.showAgain()} data-show-again>show again</button>
              </div>
            ) : null}

            <section className="tilepanel" id={attentionAnchor("to-file")} data-figure="today: aircraft to file" hidden={tile !== "to-file"} aria-label="Aircraft to file">
              <h4 className="tph">Aircraft to file <span className="note">arrived in the game with a plan card · File into planner checks the card against the game's schedule, on Tails</span></h4>
              {filing && filing.length ? (
                <div className="tblwrap">
                  <table className="tbl gtbl">
                    <thead><tr><th>Aircraft</th><th>Airline</th><th>Type</th><th>Arrived (UTC)</th><th>Base</th><th>Plan</th><th></th></tr></thead>
                    <tbody>
                      {filing.map((r) => {
                        const at = Number.isFinite(r.at) ? new Date(r.at).toISOString() : "";
                        return (
                          <tr key={r.registration} data-to-file={r.registration}>
                            <td><b>{r.registration}</b></td>
                            <td><AirlineMark color={r.airline.color} />{r.airline.name}</td>
                            <td>{r.type}{r.config ? <> <span className="dim">{r.config}</span></> : null}</td>
                            <td>{niceDate(at.slice(0, 10))} {at.slice(11, 16)} <span className="dim">{untilText(r.at, now.getTime())}</span></td>
                            <td>{r.base}</td>
                            <td className="dim">{r.plan}</td>
                            <td className="n"><Link className="primary sm" to={r.href} data-file-into-planner>File into planner</Link></td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              ) : <div className="dim">Nothing to file.</div>}
            </section>

            <div className="tilepanels" data-figure="today: needs attention">
              {groups.map((g) => (
                <section className="tilepanel" key={g.kind} id={attentionAnchor(g.kind)} data-att-group={g.kind} hidden={tile !== g.kind} aria-label={g.label}>
                  <h4 className="tph">{g.label} <span className="note">{g.items.length} item{g.items.length === 1 ? "" : "s"}</span></h4>
                  <AttentionItems items={g.items} hrefOf={hrefOf} onDismiss={(a) => void att.dismiss(a)} onOpen={openAircraft} />
                </section>
              ))}
              {!attShown.shown.length ? <div className="dim">Every aircraft is inside its maintenance, turn and night-ban rules.</div> : null}
            </div>
          </>
        )}
      </section>

      <Board title="Game check" figure="today: game check" board="Game check" id="game-check" note="compares the planner with each airline's live schedule in the game">
        <div className="toolbar">
          <button type="button" className="primary sm" id="gcheck" disabled={gc.running || !rules} onClick={() => void runCheck()}>{gc.running ? "Checking…" : "Check against the game"}</button>
          <span className="count">{gc.at ? checkedAtWords(gc.at) : ""}{noLinkWords(missingLinks)}</span>
        </div>
        <GameLines lines={gameLines} busy={busy} onOpen={setGcOpen}
          onFixAll={(id) => { const l = gameLines.find((x) => x.airline.id === id); if (l?.cmp) void fix(id, l.cmp.issues.filter((i) => i.fix)); }} />
      </Board>

      <div className="hgrid">
        <TodoBoard worldId={w} todos={todos} today={today} now={now} />
        <ComingUp events={todosQ.data ? comingUp(todosQ.data, today) : null} today={today} />
      </div>

      {openLine?.cmp && rules ? (
        <GameModal line={openLine} busy={busy} tails={tailList.filter((a) => a.airline_id === openLine.airline.id).map((a) => a.registration)} onClose={() => setGcOpen(null)}
          onFix={(k) => { const i = openLine.cmp?.issues[k]; if (i) void fix(openLine.airline.id, [i]); }}
          onFixAll={() => void fix(openLine.airline.id, (openLine.cmp?.issues ?? []).filter((i) => i.fix))}
          onAdd={(i, choice) => void add(openLine.airline.id, openLine, i, choice)} />
      ) : null}
      {tailPopup && rules ? <AircraftPopup registration={tailPopup} rules={rules} onClose={() => setTailPopup(null)} /> : null}
    </main>
  );
}
