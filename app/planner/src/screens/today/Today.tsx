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
// Address: /planner/today, the aircraft pop-up (?aircraft=REG, Tails' AircraftPopup, as Home's needs attention opened it).
// An old load-report address (/planner/check?day=…, which web/_redirects sends here) goes on to Performance's Flights by
// day with its day. Every action is one planner_save() call.
import { useEffect, useMemo, useState } from "react";
import { Link, useLocation, useNavigate, useSearchParams } from "react-router";
import { checks as checkRules, game, growth } from "@rules";
import { ourAirlines, type OurAirline } from "../../data/airlines";
import { useNow } from "../../data/clock";
import { queryClient } from "../../data/query";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import type { Change } from "../../data/save";
import { saver } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { AttentionList } from "../../ui/AttentionList";
import { familyOf } from "../../ui/aircraftNames";
import { dismissKey, withoutDismissed, type AttItem } from "../../ui/attention";
import { Board } from "../../ui/Board";
import { niceDate, toMinute, todayAt, untilText } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { onOrder } from "../home/onOrder";
import { useBackups, useCaptureStatus, useDismissals, useGrowth, useHomeAircraft, useJobs, usePlanCards, useRotations, useTodoItems, useTodos } from "../home/reads";
import { isOpen, statusOf } from "../interline/model";
import { useAgreements } from "../interline/reads";
import { useInterlineRows } from "../interline/useRows";
import { useForecasts, useReviewCards } from "../performance/reads";
import { readAirports } from "../routes/reads";
import { itemRoute, movedTo } from "../screens";
import { AircraftPopup } from "../tails/AircraftPopup";
import { gameLink, typeName, type TailAircraft } from "../tails/model";
import { readAirlineRoutes, readGameSchedule, readMarkets, readProfiles, useBuyTypes, useGameHost, useTailsAircraft } from "../tails/reads";
import { useLatestThreats } from "../competition/reads";
import { useCabinCharges } from "../systems/reads";
import { homeAttention, type HomeAirline } from "./attention";
import { ComingUp } from "./ComingUp";
import { comingUp, upFilters } from "./comingUp";
import { checkedAtWords, fixChanges, fixRotations, importChanges, noLinkWords, type GameResult } from "./game";
import { GameLines, GameModal, type GameLine, type TailChoice } from "./GameCheck";
import { captureLine, deliveryLines, orderStatus, safeTypes, toFile, waitingWords, type OrderRow } from "./model";
import { readLegs } from "./reads";
import { TodoBoard } from "./TodoBoard";
import { dismissChanges, showAgainChanges, todoViews } from "./todos";

const first = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

export function Today() {
  const loc = useLocation();
  const navigate = useNavigate();
  const [search, setSearch] = useSearchParams();
  const now = useNow();
  const today = todayAt(now);
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const rulesQ = useRules(w);
  const aircraftQ = useHomeAircraft(w);
  const rotationsQ = useRotations(w);
  const planCardsQ = usePlanCards(w);
  const todosQ = useTodos(w);
  const itemsQ = useTodoItems(w);
  const dismissalsQ = useDismissals(w);
  const backupsQ = useBackups();
  const jobsQ = useJobs();
  const captureQ = useCaptureStatus(w);
  const cardsQ = useReviewCards(w);
  const growthQ = useGrowth(w);
  const interline = useInterlineRows(w);
  const agreementsQ = useAgreements(w);
  const buyQ = useBuyTypes(w);
  const tailsQ = useTailsAircraft(w);
  const hostQ = useGameHost(w);
  const airlines: OurAirline[] = useMemo(() => ourAirlines(airlinesQ.data), [airlinesQ.data]);
  // the orders are for the airlines the captured figures cover (airline_cards(): our active airlines), in our order
  const ordering = useMemo(() => airlines.filter((a) => (cardsQ.data?.airlines ?? []).some((c) => c.airline_id === a.id)), [airlines, cardsQ.data]);
  const forecastsQ = useForecasts(ordering.map((a) => a.id));
  // the rivals' moves the latest world scan showed (competition(), since 21 Oct), for needs attention
  const competition = useLatestThreats(ordering.map((a) => a.id));
  const threats = competition.threats;
  // the cabin charge check (cabin_charges(), since 22 Oct), for needs attention
  const cabinsQ = useCabinCharges(w !== undefined);
  // dismissed here and not yet back from the database (and, on a preview, dismissed here only, as the old planner does)
  const [dismissedHere, setDismissedHere] = useState<ReadonlySet<string>>(new Set());
  const [busy, setBusy] = useState(false);
  const [gc, setGc] = useState<{ running: boolean; at: Date | null; res: ReadonlyMap<number, GameResult> }>({ running: false, at: null, res: new Map() });
  const [gcOpen, setGcOpen] = useState<number | null>(null);
  const tailPopup = search.get("aircraft");
  const setTailPopup = (reg: string | null) => setSearch((s) => {
    const n = new URLSearchParams(s);
    if (reg) n.set("aircraft", reg);
    else n.delete("aircraft");
    return n;
  });

  // an old load report's day (/planner/check?day=…, sent here by web/_redirects) opens Performance's Flights by day
  const moved = movedTo(loc.pathname, loc.search);
  useEffect(() => { if (moved) navigate(moved, { replace: true }); }, [moved, navigate]);

  const rules = rulesQ.data?.rules;
  // needs attention words airlines as Home did (HomeAirline: the old planner's names)
  const homeAirlines: HomeAirline[] = useMemo(() => airlines.map((a) => ({ id: a.id, name: a.name, code: a.code, color: a.color })), [airlines]);
  const checks = useMemo(() => (rules && aircraftQ.data && rotationsQ.data
    ? checkRules.oneWeek(rules, { aircraft: aircraftQ.data, rotations: rotationsQ.data }, today) : null), [rules, aircraftQ.data, rotationsQ.data, today]);
  const todos = useMemo(() => (todosQ.data && itemsQ.data ? todoViews(todosQ.data, itemsQ.data) : null), [todosQ.data, itemsQ.data]);
  const interlineOpen = useMemo(() => {
    if (!interline.rows || !agreementsQ.data) return null;
    const records = new Map(agreementsQ.data.map((a) => [a.airline_id + "|" + a.country_code, a]));
    return interline.rows.filter((r) => isOpen(statusOf(records.get(r.airline_id + "|" + r.cc)))).length;
  }, [interline.rows, agreementsQ.data]);
  const attention = useMemo(() => (rules && checks && todosQ.data ? homeAttention({
    now, today, airlines: homeAirlines, rules, checks, todos: todosQ.data, capture: captureQ.data ?? null, backups: backupsQ.data ?? null,
    jobs: jobsQ.data ?? null, cards: cardsQ.data?.airlines ?? null, growth: growthQ.data ?? null, interlineOpen, threats, cabins: cabinsQ.data ?? null,
  }) : null), [now, today, homeAirlines, rules, checks, todosQ.data, captureQ.data, backupsQ.data, jobsQ.data, cardsQ.data, growthQ.data, interlineOpen, threats,
    cabinsQ.data]);
  const dismissed = useMemo(() => new Set([...(dismissalsQ.data ?? []).map((d) => d.alert_key), ...dismissedHere]), [dismissalsQ.data, dismissedHere]);
  const attShown = useMemo(() => (attention ? withoutDismissed(attention, dismissed) : null), [attention, dismissed]);

  // ---------- orders: can order now or from when, the safe types, and each delivery line
  const orders: OrderRow[] | null = useMemo(() => {
    if (!rules || !cardsQ.data || !buyQ.data || !aircraftQ.data || forecastsQ.some((q) => !q.data)) return null;
    const family = (id: number | null) => familyOf(typeName(rules, id));
    const families = [...new Set(buyQ.data.filter((b) => airlines.some((a) => a.id === b.airline_id)).map((b) => family(b.aircraft_type_id)))].sort();
    const unfiled = aircraftQ.data.filter((a) => a.status === "on_order" || a.status === "delivered");
    return ordering.map((a, i) => {
      const card = cardsQ.data.airlines.find((c) => c.airline_id === a.id);
      const allowed = new Set(buyQ.data.filter((b) => b.airline_id === a.id).map((b) => family(b.aircraft_type_id)));
      const cells = growth.orderQueues(rules, a.id, families, allowed,
        unfiled.filter((x) => x.airline_id === a.id && x.delivery_at).map((x) => ({ family: family(x.aircraft_type_id), delivery_ms: toMinute(x.delivery_at as string) })), now.getTime());
      const types = forecastsQ[i]?.data?.types;
      return { airline: a, status: orderStatus(card?.next_order, card?.can_order_now), types: safeTypes(types), lines: deliveryLines(cells, types, (t) => family(t.aircraft_type_id)) };
    });
  }, [rules, cardsQ.data, buyQ.data, aircraftQ.data, forecastsQ, airlines, ordering, now]);

  // ---------- aircraft to file: arrived with a plan card
  const filing = useMemo(() => (rules && aircraftQ.data && planCardsQ.data
    ? toFile(onOrder(aircraftQ.data, rules, new Map(planCardsQ.data.map((p) => [p.aircraft_id, p.title] as const)), homeAirlines, now.getTime()).groups) : null),
  [rules, aircraftQ.data, planCardsQ.data, homeAirlines, now]);

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
    const tail = choice.isNew ? { registration: choice.registration } : { aircraft: mine.find((a) => a.registration === choice.registration) as TailAircraft };
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

  // ---------- needs attention: where each item is fixed, dismiss and show again
  const hrefOf = (a: AttItem) => {
    if (a.screen === "today") return itemRoute("today", { hash: "todo" });
    if (a.tail) return itemRoute(a.screen, { tail: a.tail });
    if (a.route) {
      const [al = "", hub = "", dest = ""] = a.route.split("|");
      return itemRoute(a.screen, { airline: airlines.find((x) => x.name === al)?.code, hub, dest });
    }
    // can order: the airline's page on Performance, with its cash for the next 14 days
    if (a.screen === "performance" && a.key?.startsWith("order|")) return itemRoute("performance", { airline: airlines.find((x) => x.name === a.key?.split("|")[1])?.code });
    // a rival's move: the airline's Competition page (its key: threat|<code>|<pair>|<rival>|<day>)
    if (a.screen === "competition" && a.key?.startsWith("threat|")) return itemRoute("competition", { airline: a.key.split("|")[1] });
    // a cabin charge that doesn't match: Systems' Cabin charges board, open on arrival
    if (a.screen === "systems" && a.key?.startsWith("cabin|")) return itemRoute("systems", { hash: "cabin-charges" });
    return itemRoute(a.screen);
  };
  async function dismiss(a: AttItem) {
    if (w === undefined) return;
    const key = dismissKey(a);
    setDismissedHere((s) => new Set([...s, key]));
    const res = await saver.save(dismissChanges(w, key, today));
    if (res.status === "clash") setDismissedHere((s) => new Set([...s].filter((k) => k !== key)));
  }
  async function showAgain() {
    setDismissedHere(new Set());
    if (dismissalsQ.data?.length) await saver.save(showAgainChanges(dismissalsQ.data));
  }

  const ready = !!(rules && checks && todos && dismissalsQ.data && backupsQ.data && jobsQ.data && captureQ.data && cardsQ.data && growthQ.data
    && aircraftQ.data && planCardsQ.data && airlinesQ.data && interlineOpen !== null && orders && filing && tailsQ.data && hostQ.isSuccess && threats
    && cabinsQ.data);
  const loadError = first(world, airlinesQ, rulesQ, aircraftQ, rotationsQ, planCardsQ, todosQ, itemsQ, dismissalsQ, backupsQ, jobsQ, captureQ, cardsQ, growthQ,
    buyQ, tailsQ, hostQ, ...forecastsQ, competition, cabinsQ);
  const cap = captureQ.data && airlinesQ.data ? captureLine(airlines, captureQ.data, now) : null;
  const waiting = ready && orders && filing && attShown ? waitingWords({
    canOrder: orders.filter((o) => o.status.kind === "now").map((o) => o.airline.name), toFile: filing.length, attention: attShown.shown.length, game: differences,
  }) : null;

  return (
    <main className="view review today" data-screen="today" data-today-ready={ready ? "yes" : "no"} data-today-view={loc.pathname + loc.search}>
      <div className="vh"><p className="vk">Every day</p><h1>Today</h1><p>What to do now: the capture, orders, aircraft to file, what needs attention, the game check and the to-dos.</p></div>
      {loadError ? <ErrorBox error={loadError} /> : null}

      <section className={"board todayans" + (waiting?.clear ? " clear" : "")} data-figure="today: answer" data-all-clear={waiting ? (waiting.clear ? "yes" : "no") : ""}>
        {waiting ? (
          <>
            <h2 className="ansh">{waiting.title}</h2>
            <p className="ansp">{waiting.parts.join(" · ")}</p>
          </>
        ) : <div className="loading">Loading…</div>}
        {cap ? (
          <div className="capline" data-figure="today: capture" data-capture-state={cap.state} data-mark={cap.mark}>
            <span className={"sysmark " + cap.mark} role="img" aria-label={cap.mark === "ok" ? "green" : cap.mark === "warn" ? "amber" : "red"} />
            <span className="captext">{cap.text}</span> <Link className="link" to={itemRoute("systems")}>Systems ›</Link>
          </div>
        ) : null}
      </section>

      <Board title="Orders" figure="today: orders" id="orders"
        note="from the cash forecast: an order is safe when the cushion stays in hand at its lowest point · each delivery line: when its first type is safe, what's on order and when it runs dry (UTC)">
        {!orders ? <div className="loading">Loading…</div> : (
          <div className="ordgrid">
            {orders.map((o) => (
              <div className="ordcard" key={o.airline.id} data-orders={o.airline.code ?? ""}>
                <div className="ordh">
                  <AirlineMark color={o.airline.color} /><b>{o.airline.name}</b>
                  {o.status.kind === "now" ? <span className="pill warn" data-can-order>{o.status.text}</span> : <span className="dim">{o.status.text}</span>}
                </div>
                {o.lines.length ? (
                  <ul className="ordlines">
                    {o.lines.map((l) => (
                      <li key={l.family} data-order-line={l.family}>
                        <b>{l.family}</b> —{" "}
                        {l.safe ? <>{l.safe.now ? <b>{l.safe.text}</b> : <span>{l.safe.text}</span>} <span className="dim">·</span> </> : null}
                        <span className={l.text.startsWith("empty") ? "dim" : undefined}>{l.text}</span>{l.soon ? <> <span className="pill warn sm">{l.soon}</span></> : null}
                      </li>
                    ))}
                  </ul>
                ) : null}
                {o.types.length ? (
                  <details className="ordall" data-all-safe={o.airline.code ?? ""}>
                    <summary>all safe types</summary>
                    <div className="ordtypes"><span className="dim">Safe</span> {o.types.map((g, i) => (
                      <span key={g.when}>{i ? <span className="dim"> · </span> : null}{g.now ? <b>{g.when}: {g.names.join(", ")}</b> : <span className="dim">{g.when}: {g.names.join(", ")}</span>}</span>
                    ))}</div>
                  </details>
                ) : null}
                {o.airline.code ? <Link className="link" to={itemRoute("performance", { airline: o.airline.code })}>Cash, next 14 days ›</Link> : null}
              </div>
            ))}
          </div>
        )}
      </Board>

      <Board title="Aircraft to file" figure="today: aircraft to file" id="to-file"
        note="arrived in the game with a plan card · File into planner checks the card against the game's schedule, on Tails">
        {!filing ? <div className="loading">Loading…</div> : filing.length ? (
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
      </Board>

      <Board title="Needs attention" figure="today: needs attention" id="attention"
        note={attShown ? (attShown.shown.length ? `${attShown.shown.length} item${attShown.shown.length === 1 ? "" : "s"}` : "nothing right now") : ""}>
        {!attShown || !ready ? <div className="loading">Loading…</div> : (
          <>
            {attShown.hidden ? (
              <div className="dim hiddenline" data-dismissed={attShown.hidden}>
                {attShown.hidden} dismissed · <button type="button" className="link" onClick={() => void showAgain()} data-show-again>show again</button>
              </div>
            ) : null}
            {attShown.shown.length ? <AttentionList items={attShown.shown} hrefOf={hrefOf} onDismiss={(a) => void dismiss(a)}
              onOpen={(a) => { if (!a.tail || a.route || a.screen !== "tails") return false; setTailPopup(a.tail); return true; }} />
              : <div className="dim">Every aircraft is inside its maintenance, turn and night-ban rules, and no checks are due.</div>}
          </>
        )}
      </Board>

      <Board title="Game check" figure="today: game check" board="Game check" note="compares the planner with each airline's live schedule in the game">
        <div className="toolbar">
          <button type="button" className="primary sm" id="gcheck" disabled={gc.running || !rules} onClick={() => void runCheck()}>{gc.running ? "Checking…" : "Check against the game"}</button>
          <span className="count">{gc.at ? checkedAtWords(gc.at) : ""}{noLinkWords(missingLinks)}</span>
        </div>
        <GameLines lines={gameLines} busy={busy} onOpen={setGcOpen}
          onFixAll={(id) => { const l = gameLines.find((x) => x.airline.id === id); if (l?.cmp) void fix(id, l.cmp.issues.filter((i) => i.fix)); }} />
      </Board>

      <div className="hgrid">
        <TodoBoard worldId={w} todos={todos} today={today} now={now} />
        <ComingUp events={checks && todosQ.data ? comingUp(checks, todosQ.data, today) : null} today={today} filters={upFilters(rules, airlines.map((a) => a.id))} />
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
