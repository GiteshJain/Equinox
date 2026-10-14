// Check (decision #18, build pull request 9; spec docs/specs/2026-10-13-check.md): the daily look at how the network is
// doing, as the old planner's Check (its renderReview), from the same data, with the same figures and look. Its boards, in
// the old order, each folding open and shut by its title (all folded on arrival, with Collapse all and Expand all):
//   - Capture: what the capture collected for each airline and when (capture_status()), with Reload, and the backup;
//   - Growth (Growth.tsx): who can order now, main hubs' progress, each airline's next move, the growth lists, the order
//     queues and the hubs' readiness;
//   - Aircraft checks: the one-week checks due (the library's checks.oneWeek), with each aircraft's issues and its routes'
//     load patterns, the ones coming up by date and how many are done; Mark checked (Gitesh's own, manual §1);
//   - Cabins (Cabins.tsx): each aircraft's cabin against its markets (cabins.fit), Refitted to, Keep as is, Show again;
//   - Game check (GameCheck.tsx): Check against the game, the differences, fix one or all, add a flight;
//   - Daily load report (LoadReport.tsx): a day at a time, every departure with its loads by class.
// Address: /planner/next/check, the report's day in it (?day=YYYY-MM-DD; today, UTC, without), and the aircraft pop-up
// (?aircraft=REG, Tails' AircraftPopup, as the old planner opened it from here). Every action is one planner_save() call.
import { useMemo, useState, type ReactNode } from "react";
import { useLocation, useNavigate, useSearchParams } from "react-router";
import { cabins, checks, game, growth, loadReport, tails, type CabinFit, type GameIssue, type Move } from "@rules";
import { useNow } from "../../data/clock";
import { queryClient } from "../../data/query";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import type { Change } from "../../data/save";
import { saver } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { familyOf, shortType } from "../../ui/aircraftNames";
import { dayDiff, niceDate, toMinute, todayAt } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { useAirlineCards } from "../home/reads";
import { routeOf } from "../routes/model";
import { readAirports, useAirports, useLoads, useMarkets } from "../routes/reads";
import { AircraftPopup } from "../tails/AircraftPopup";
import { extraIndex, figuresOf, gameLink, issueWords, markCheckedChange, rulesLegs, typeName, type PlanLegRow, type TailAircraft } from "../tails/model";
import {
  readAirlineRoutes, readGameSchedule, readMarkets, readProfiles, tailsCount, useBuyTypes, useConfigs, useGameHost, useLaunches, usePlanCards, usePlanLegs, useTailsAircraft,
} from "../tails/reads";
import { CabinsList } from "./Cabins";
import { GameLines, GameModal, type GameLine, type TailChoice } from "./GameCheck";
import { GrowthBoard, type NextMoveRow, type QueueRow, type ReadyRow } from "./Growth";
import { LoadReport } from "./LoadReport";
import {
  BOARDS, CAPTURE_KINDS, backupWords, captureCell, captureStatus, checkedAtWords, costWords, daySummary, fixChanges, fixRotations, importChanges, keepChange,
  loadKey, loadsByFlight, logMoveChange, moveDay, noLinkWords, parseDay, patternPill, patternRanks, refitChanges, refitCost, undoKeepChange, upcomingByDay, utcToday,
  type BoardKey, type CheckAirline, type GameResult,
} from "./model";
import {
  readLegs, useAllRoutes, useBackupLine, useCabinKeeps, useCapture, useDayLoads, useGrowthLog, useGrowthSignals, useHandLoads, useHubProgress,
} from "./reads";

const NOTES: Record<BoardKey, string> = {
  "Capture": "what the one-click capture collected from the game, per airline · times in UTC · cash and fixed costs go straight into Review",
  "Growth": "what each airline can afford, where the next aircraft should go, what to trim, and when each order queue runs dry",
  "Aircraft checks": "one check, a week after an aircraft is scheduled · once marked checked it only comes back when that aircraft's schedule changes",
  "Cabins": "",
  "Game check": "compares the planner with each airline's live schedule in the game",
  "Daily load report": "every flight flown, from the nightly capture, with loads by class · if a capture failed, enter loads on the Review tab under Manual entry",
};
const FIGURE: Record<BoardKey, string> = {
  "Capture": "check: capture", "Growth": "check: growth", "Aircraft checks": "check: aircraft checks", "Cabins": "check: cabins", "Game check": "check: game check",
  "Daily load report": "check: load report",
};

/** A board that folds open and shut by its title, as the old Check's (decorateBoards): folded, only the title shows. */
function FoldBoard({ k, note, folded, onToggle, children }: { k: BoardKey; note: ReactNode; folded: boolean; onToggle: () => void; children: ReactNode }) {
  return (
    <section className={"board" + (folded ? " rcol" : "")} data-figure={FIGURE[k]} data-board={k}>
      <h3 className="rh rch" data-rkey={k} tabIndex={0} aria-expanded={!folded}
        onClick={(e) => { if (!(e.target as HTMLElement).closest("button, input, select, a, label")) onToggle(); }}
        onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onToggle(); } }}>
        <span className="chev" aria-hidden="true" />{k} <span className="note">{note}</span>
      </h3>
      {children}
    </section>
  );
}

const firstError = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

export function Check() {
  const loc = useLocation();
  const navigate = useNavigate();
  const [search, setSearch] = useSearchParams();
  const now = useNow();
  const today = todayAt(now);
  const utcDay = utcToday(now);
  const day = parseDay(loc.search, utcDay);
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const rulesQ = useRules(w);
  const aircraftQ = useTailsAircraft(w);
  const configsQ = useConfigs(w);
  const launchesQ = useLaunches(w);
  const cardsQ = usePlanCards(w);
  const planLegsQ = usePlanLegs(w);
  const buyQ = useBuyTypes(w);
  const hostQ = useGameHost(w);
  const marketsQ = useMarkets(w);
  const routesQ = useAllRoutes(w);
  const logQ = useGrowthLog(w);
  const keepsQ = useCabinKeeps(w);
  const captureQ = useCapture(w);
  const backupsQ = useBackupLine();
  const figCardsQ = useAirlineCards(w);
  const signalsQ = useGrowthSignals(w);
  const progressQ = useHubProgress(w);
  const loadsQ = useLoads(w);
  // the old planner held the last 9 days of captured loads (game_loads since utcDay(-9)); older days show none, as there
  const captured = dayDiff(day, utcDay) <= 9;
  const dayLoadsQ = useDayLoads(w, day, captured);
  const handQ = useHandLoads(w, day);
  const cardCodes = useMemo(() => [...new Set((planLegsQ.data ?? []).flatMap((l) => [l.origin_code, l.dest_code]))], [planLegsQ.data]);
  const airportsQ = useAirports(w, cardCodes);
  const [folded, setFolded] = useState<ReadonlySet<BoardKey>>(() => new Set(BOARDS));
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

  const rules = rulesQ.data?.rules;
  const airlines: CheckAirline[] = useMemo(() => (airlinesQ.data ?? []).map((a) => ({
    id: a.id, code: a.iata_code, name: a.planner_name ?? a.public_name ?? a.game_name ?? `Airline ${a.game_id}`, color: a.livery_color, game_id: a.game_id,
  })), [airlinesQ.data]);
  const airline = (id: number) => airlines.find((a) => a.id === id);
  const all = useMemo(() => aircraftQ.data ?? [], [aircraftQ.data]);
  const byId = useMemo(() => new Map(all.map((a) => [a.id, a])), [all]);
  const marketTypes = useMemo(() => new Map((marketsQ.data ?? []).map((m) => [m.id, m.default_type_id])), [marketsQ.data]);
  // the old planner's list of tails, every airline's, in its order (aircraft.extra.tails_index)
  const tailList = useMemo(() => all.filter((a) => a.status === "active" && extraIndex(a, "tails_index") != null)
    .sort((a, b) => (extraIndex(a, "tails_index") ?? 0) - (extraIndex(b, "tails_index") ?? 0) || a.id - b.id), [all]);
  const unfiled = useMemo(() => all.filter((a) => a.status === "on_order" || a.status === "delivered"), [all]);
  const legsOfAircraft = useMemo(() => {
    const cardOf = new Map((cardsQ.data ?? []).map((c) => [c.id, c.aircraft_id]));
    const by = new Map<number, PlanLegRow[]>();
    for (const l of planLegsQ.data ?? []) {
      const a = cardOf.get(l.plan_card_id);
      if (a != null) by.set(a, [...(by.get(a) ?? []), l]);
    }
    return by;
  }, [cardsQ.data, planLegsQ.data]);

  // ---------- saving: one action each; the start's rules are read again after one that changes the schedule or a cabin
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

  // ---------- Growth
  const growthParts = useMemo(() => {
    if (!rules || !routesQ.data || !logQ.data || !loadsQ.data || !marketsQ.data || !buyQ.data) return null;
    const markets = new Map(marketsQ.data.map((m) => [m.id, m]));
    const routes = routesQ.data.map((r) => routeOf(r, markets));
    const loads = loadsQ.data.routes.map((x) => ({ ...x, departures: Number(x.departures), full: Number(x.full), days: Number(x.days) }));
    const canOrder = new Map((figCardsQ.data?.airlines ?? []).map((c) => [c.airline_id, c.can_order_now ?? []]));
    const moves: NextMoveRow[] = airlines.map((a) => {
      const mine = unfiled.filter((x) => x.airline_id === a.id);
      const c = growth.moveCandidates(rules, a.id, {
        routes: routes.filter((r) => r.airline_id === a.id).map((r) => ({ id: r.id, hub: r.hub, dest: r.dest, stars: r.stars, dist: r.dist })),
        planned: mine.flatMap((x) => (legsOfAircraft.get(x.id) ?? []).map((l) => ({ from: l.origin_code, to: l.dest_code }))),
        orderBases: mine.map((x) => x.order_base_code), loads,
      });
      const move = growth.shownMove(growth.nextMove(logQ.data, a.id), c);
      return { airline: a, last: growth.lastMove(logQ.data, a.id), move, options: c[move].map((r) => ({ ...r, code: a.code })), canOrder: !!(canOrder.get(a.id) ?? []).length };
    });
    // the routes ready from the load reports alone, with the types flying them (shown when no profit was captured)
    const typesOn = new Map<number, string[]>();
    for (const f of game.frequencies(rules, null)) {
      const ac = f.leg1?.aircraft_id ?? f.leg2?.aircraft_id ?? null;
      const t = ac == null ? "" : shortType(typeName(rules, rules.aircraft.get(ac)?.aircraft_type_id));
      if (t && !(typesOn.get(f.route_id) ?? []).includes(t)) typesOn.set(f.route_id, [...(typesOn.get(f.route_id) ?? []), t]);
    }
    const loadOf = new Map(loadsQ.data.routes.map((x) => [x.route_id, x]));
    const ready: ReadyRow[] = growth.readyFromLoads(rules, routes.map((r) => ({ id: r.id, airline_id: r.airline_id, hub: r.hub, dest: r.dest, stars: r.stars, dist: r.dist })), loads)
      .map((r) => ({ route: r, load: loadOf.get(r.id) as ReadyRow["load"], flyingOn: (typesOn.get(r.id) ?? []).join(", ") }));
    // the order queues by family: the families any of our airlines may have, in name order
    const typeFamily = (id: number | null) => familyOf(typeName(rules, id));
    const families = [...new Set(buyQ.data.filter((b) => airlines.some((a) => a.id === b.airline_id)).map((b) => typeFamily(b.aircraft_type_id)))].sort();
    const queues: QueueRow[] = airlines.map((a) => ({
      airline: a,
      cells: growth.orderQueues(rules, a.id, families, new Set(buyQ.data.filter((b) => b.airline_id === a.id).map((b) => typeFamily(b.aircraft_type_id))),
        unfiled.filter((x) => x.airline_id === a.id && x.delivery_at).map((x) => ({ family: typeFamily(x.aircraft_type_id), delivery_ms: toMinute(x.delivery_at as string) })), now.getTime()),
    }));
    const planned = [...legsOfAircraft].filter(([id]) => byId.get(id)?.status !== "active")
      .flatMap(([, ls]) => ls.map((l) => ({ from: l.origin_code, to: l.dest_code, dep_utc_min: l.dep_utc_min, block_min: l.block_min })));
    const countries = new Map((airportsQ.data ?? []).map((x) => [x.code, x.country_code]));
    return { canOrder, moves, ready, families, queues, readiness: growth.hubReadiness(rules, planned, countries, rulesLegs(rules)) };
  }, [rules, routesQ.data, logQ.data, loadsQ.data, marketsQ.data, buyQ.data, figCardsQ.data, airlines, unfiled, legsOfAircraft, byId, airportsQ.data, now]);

  // ---------- Aircraft checks
  const checkList = useMemo(() => (rules && aircraftQ.data && launchesQ.data
    ? checks.oneWeek(rules, { aircraft: aircraftQ.data, rotations: launchesQ.data }, today) : null), [rules, aircraftQ.data, launchesQ.data, today]);
  const ranks = useMemo(() => {
    if (!rules) return new Map<number, number>();
    return patternRanks(rules, today, Number(rules.input.settings.load_window_days) || 0);
  }, [rules, today]);
  const freqs = useMemo(() => (rules ? game.frequencies(rules, null) : []), [rules]);

  // ---------- Cabins
  const cabinList = useMemo(() => (rules && configsQ.data && routesQ.data && marketsQ.data && keepsQ.data
    ? cabins.fit(rules, {
      aircraft: tailList.map((a) => ({ id: a.id, cabin_config_id: a.cabin_config_id })), configs: configsQ.data,
      routes: routesQ.data.map((r) => ({ id: r.id, cabin_choice: r.cabin_choice })), markets: marketsQ.data, keeps: keepsQ.data,
    }, rulesLegs(rules)) : null), [rules, configsQ.data, routesQ.data, marketsQ.data, keepsQ.data, tailList]);

  // ---------- Game check
  const linkOf = (a: CheckAirline) => gameLink(hostQ.data, a.game_id);
  const gameLines: GameLine[] = useMemo(() => {
    if (!rules) return [];
    const out: GameLine[] = [];
    for (const a of airlines) {
      if (!gameLink(hostQ.data, a.game_id)) continue;
      const x = gc.res.get(a.id);
      if (!x) continue;
      if ("error" in x) { out.push({ airline: a, error: x.error }); continue; }
      out.push({ airline: a, cmp: game.compare(rules, a.id, x.flights, marketTypes), cands: game.importCandidates(rules, a.id, x.flights) });
    }
    return out;
  }, [rules, airlines, hostQ.data, gc.res, marketTypes]);
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
  async function fix(airlineId: number, issues: readonly GameIssue[]) {
    if (!rules) return;
    const rots = fixRotations(rules, airlineId, issues, marketTypes);
    const legs = await readLegs(rots);
    await save(fixChanges(rules, airlineId, issues, legs, marketTypes), true);
  }
  async function add(airlineId: number, line: GameLine, index: number, choice: TailChoice) {
    const cand = line.cands?.[index];
    if (!rules || !cand || w === undefined) return;
    const mine = tailList.filter((a) => a.airline_id === airlineId);
    const tail = choice.isNew ? { registration: choice.registration } : { aircraft: mine.find((a) => a.registration === choice.registration) as TailAircraft };
    if (!choice.isNew && !("aircraft" in tail && tail.aircraft)) return;
    const codes = [...new Set([cand.a.from, cand.a.to, ...(cand.b ? [cand.b.from, cand.b.to] : [])])];
    const [routes, markets, profiles, count, airports] = await Promise.all([readAirlineRoutes(airlineId), readMarkets(w), readProfiles(w), tailsCount(w), readAirports(w, codes)]);
    await save(importChanges({
      worldId: w, today, nowMs: Date.now(), rules, airlineId, cand, tail, aircraft: all, tails: mine, tailsIndex: count,
      bases: rules.bases.filter((b) => b.airline_id === airlineId).map((b) => b.airport_code), routes, markets: new Map(markets.map((m) => [m.id, m])), profiles,
      airports: new Map(airports.map((x) => [x.code, x])),
    }), true);
  }

  // ---------- the daily load report
  const flights = useMemo(() => (rules && launchesQ.data ? loadReport.flightsOn(rules, day, launchesQ.data) : []), [rules, launchesQ.data, day]);
  const loadsMap = useMemo(() => loadsByFlight(captured ? dayLoadsQ.data ?? [] : [], day), [captured, dayLoadsQ.data, day]);
  const loadOf = (f: { airline_id: number; no: number }) => loadsMap.get(loadKey(airline(f.airline_id)?.name ?? "", f.no));
  const summary = daySummary(flights, loadOf, handQ.data);
  const goDay = (n: number) => {
    const d = moveDay(day, n);
    const s = new URLSearchParams(loc.search);
    if (d === utcDay) s.delete("day");
    else s.set("day", d);
    const q = s.toString();
    navigate("/check" + (q ? "?" + q : ""));
  };

  // everything but the report's day, which loads on its own as the day moves (the boards stay while it does)
  const ready = !!(rules && aircraftQ.data && configsQ.data && launchesQ.data && cardsQ.data && planLegsQ.data && buyQ.isSuccess && hostQ.isSuccess && marketsQ.data
    && routesQ.data && logQ.data && keepsQ.data && captureQ.data && backupsQ.isSuccess && figCardsQ.data && signalsQ.data && progressQ.data && loadsQ.data
    && (!cardCodes.length || airportsQ.data) && airlinesQ.data && growthParts && cabinList && checkList);
  const dayReady = (!captured || !!dayLoadsQ.data) && !!handQ.data && !dayLoadsQ.isFetching && !handQ.isFetching;
  const loadError = firstError(world, airlinesQ, rulesQ, aircraftQ, configsQ, launchesQ, cardsQ, planLegsQ, buyQ, hostQ, marketsQ, routesQ, logQ, keepsQ, signalsQ,
    progressQ, loadsQ, dayLoadsQ, handQ, airportsQ, figCardsQ);
  const toggle = (k: BoardKey) => setFolded((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const board = (k: BoardKey, children: ReactNode, note: ReactNode = NOTES[k]) => (
    <FoldBoard key={k} k={k} note={note} folded={folded.has(k)} onToggle={() => toggle(k)}>{children}</FoldBoard>
  );
  const sharePct = rules ? Number(rules.input.settings.cabin_refit_share_pct) : 0;
  const worldCost = rules ? Number(rules.input.settings.cabin_refit_cost) : 0;
  const missingLinks = airlines.filter((a) => !linkOf(a)).map((a) => a.name);
  const openLine = gcOpen == null ? undefined : gameLines.find((x) => x.airline.id === gcOpen);
  const backup = backupWords(backupsQ.data, (d) => niceDate(d));

  return (
    <main className="view review" data-screen="check" data-check-ready={ready && dayReady ? "yes" : "no"} data-check-view={loc.pathname + loc.search} data-day={day}>
      <div className="vh"><h1>Check</h1><p>Last night's capture, aircraft checks, growth signals, Game check and the daily load report.</p></div>
      {loadError ? <ErrorBox error={loadError} /> : null}
      {!ready && !loadError ? <div className="empty">Loading…</div> : null}
      <div className="revtools">
        <button type="button" className="link" id="rev-colall" onClick={() => setFolded(new Set(BOARDS))}>Collapse all</button><span className="dim">·</span>
        <button type="button" className="link" id="rev-expall" onClick={() => setFolded(new Set())}>Expand all</button>
        <span className="dim">· click a board's title to open or fold it · everything folds again when you leave this tab</span>
      </div>
      {ready && rules && growthParts && checkList && cabinList ? (
        <>
          {board("Capture", <>
            <div className="toolbar">
              <button type="button" className="secondary" id="cap-reload" disabled={captureQ.isFetching}
                onClick={() => { void captureQ.refetch(); void backupsQ.refetch(); void dayLoadsQ.refetch(); }}>{captureQ.isFetching ? "Loading…" : "Reload"}</button>
              <span className="count">{captureQ.dataUpdatedAt ? "checked at " + new Date(captureQ.dataUpdatedAt).toISOString().slice(11, 16) + " UTC" : "not checked yet"}</span>
              {captureQ.error ? <> <span className="pill bad">{captureQ.error instanceof Error ? captureQ.error.message : String(captureQ.error)}</span></> : null}
            </div>
            <div className="tblwrap">
              <table className="tbl" data-figure="check: capture table">
                <tbody>
                  <tr><th>Airline</th>{CAPTURE_KINDS.map((k) => <th key={k[0]}>{k[1]}</th>)}<th className="num">Flights, {niceDate(captureQ.data?.today)}</th><th className="num">{niceDate(captureQ.data?.yesterday)}</th><th>Today</th></tr>
                  {(captureQ.data?.airlines ?? []).map((x) => {
                    const st = captureStatus(x);
                    return (
                      <tr key={x.airline_id}>
                        <td><AirlineMark color={airline(x.airline_id)?.color} /><b>{airline(x.airline_id)?.name ?? x.name}</b></td>
                        {CAPTURE_KINDS.map(([k]) => { const c = captureCell(x.pages?.[k]); return <td key={k}>{c.dim ? <span className="dim">{c.text}</span> : c.text}</td>; })}
                        <td className="num">{x.flights_today || "—"}</td>
                        <td className="num">{x.flights_yesterday || "—"}</td>
                        <td><span className={"pill " + st.cls}>{st.text}</span></td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <div className="note">Flights are counted by their departure date (local time), as the game lists them.</div>
            {backup ? <div className="note">{backup.ok === false ? <><span className="pill bad sm">Backup failed</span> {backup.text}</> : backup.text}</div> : null}
          </>)}
          {board("Growth", <GrowthBoard rules={rules} airlines={airlines} canOrder={growthParts.canOrder} progress={progressQ.data ?? []} moves={growthParts.moves}
            signals={signalsQ.data as NonNullable<typeof signalsQ.data>} ready={growthParts.ready} queues={growthParts.queues} families={growthParts.families}
            readiness={growthParts.readiness} busy={busy} onLog={(id, m: Move) => { if (w !== undefined) void save([logMoveChange(w, id, m, today)]); }} />)}
          {board("Aircraft checks", <ChecksBody list={checkList} today={today} rules={rules} byId={byId} airline={airline} freqs={freqs} ranks={ranks}
            patterns={signalsQ.data?.load_patterns ?? []} busy={busy} onAircraft={setTailPopup}
            onCheck={(a) => void save([markCheckedChange(a, today)])} />)}
          {board("Cabins", <CabinsList list={cabinList} airlines={airlines} cost={worldCost} sharePct={sharePct} busy={busy} onAircraft={setTailPopup}
            onRefit={(x: CabinFit) => { const a = byId.get(x.aircraft_id); if (a && x.target && w !== undefined) void save(refitChanges(w, a, x.target, refitCost(rules, a.airline_id), today), true); }}
            onKeep={(x) => { if (w !== undefined) void save([keepChange(w, x.aircraft_id, x.want, today)]); }}
            onUndo={(x) => { const k = keepsQ.data?.find((r) => r.aircraft_id === x.aircraft_id && r.cabin === x.want); if (k) void save([undoKeepChange(k)]); }} />,
          `each aircraft's cabin against the default cabin of the markets it flies most · a refit costs about ${costWords(worldCost)} with no time out of service · only worth it where most of the flying is in the other cabin's markets`)}
          {board("Game check", <>
            <div className="toolbar">
              <button type="button" className="primary sm" id="gcheck" disabled={gc.running} onClick={() => void runCheck()}>{gc.running ? "Checking…" : "Check against the game"}</button>
              <span className="count">{gc.at ? checkedAtWords(gc.at) : ""}{noLinkWords(missingLinks)}</span>
            </div>
            <GameLines lines={gameLines} busy={busy} onOpen={setGcOpen}
              onFixAll={(id) => { const l = gameLines.find((x) => x.airline.id === id); if (l?.cmp) void fix(id, l.cmp.issues.filter((i) => i.fix)); }} />
          </>)}
          {board("Daily load report", <LoadReport day={day} flights={flights} summary={summary} airlines={airlines} loadOf={loadOf} onDay={goDay} loading={!dayReady} />)}
        </>
      ) : null}
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

/** The aircraft checks (the old renderReview's checks): each one due with its aircraft's issues and its routes' load
 *  patterns, the ones coming up by day, and how many are done. */
function ChecksBody({ list, today, rules, byId, airline, freqs, ranks, patterns, busy, onAircraft, onCheck }: {
  list: ReturnType<typeof checks.oneWeek>;
  today: string;
  rules: NonNullable<ReturnType<typeof useRules>["data"]>["rules"];
  byId: ReadonlyMap<number, TailAircraft>;
  airline: (id: number) => CheckAirline | undefined;
  freqs: ReturnType<typeof game.frequencies>;
  ranks: ReadonlyMap<number, number>;
  patterns: NonNullable<ReturnType<typeof useGrowthSignals>["data"]>["load_patterns"];
  busy: boolean;
  onAircraft: (registration: string) => void;
  onCheck: (a: TailAircraft) => void;
}) {
  const due = list.filter((c) => c.status === "due"), up = list.filter((c) => c.status === "upcoming"), doneN = list.filter((c) => c.status === "done").length;
  const legs = rulesLegs(rules);
  return (
    <>
      {!list.length ? <div className="dim">No launch dates yet. Set "Launched" on a frequency (new frequencies get today automatically) and its aircraft will come up here a week later.</div> : null}
      {due.map((c) => {
        const a = byId.get(c.aircraft_id);
        if (!a) return null;
        const al = airline(a.airline_id);
        const fig = figuresOf(rules, a.id, legs);
        const iss = fig.week ? tails.issues(rules, a.id, legs, fig.week, fig.maint) : [];
        const mine = freqs.filter((f) => (f.leg1?.aircraft_id ?? f.leg2?.aircraft_id ?? null) === a.id);
        const dests = [...new Set(mine.map((f) => f.dest))];
        const routes = new Set(mine.map((f) => f.route_id));
        const lf = patterns.filter((p) => routes.has(p.route_id))
          .map((p, i) => ({ p, i })).sort((x, y) => (ranks.get(x.p.route_id) ?? 1e9) - (ranks.get(y.p.route_id) ?? 1e9) || x.i - y.i).map((v) => v.p);
        const base = a.base_code ?? "";
        const hub = rules.bases.find((b) => b.airport_code === base && b.airline_id === a.airline_id);
        return (
          <div className="ck due" key={a.id} data-check={a.registration}>
            <div className="ckh">
              <button type="button" className="link" data-tailm={a.registration} onClick={() => onAircraft(a.registration)}><b>{a.registration}</b></button>{" "}
              {base ? <span className="hubtag on" style={{ "--lv": al?.color ?? "#8B96A8" } as React.CSSProperties} title={hub && hub.role === "focus" ? "focus city" : "hub"}>{base}</span> : null}{" "}
              <span className="dim">{al?.name ?? ""} · {typeName(rules, a.aircraft_type_id)} · flies {dests.join(", ") || "—"} · last scheduled {niceDate(c.last)} · check due {niceDate(c.due)}</span>
              <button type="button" className="primary sm" data-checked={a.registration} disabled={busy} onClick={() => onCheck(a)}>Mark checked</button>
            </div>
            <div className="ckb">
              {iss.length ? iss.map((x, k) => <span key={k} className="pill bad">{issueWords(x)}</span>)
                : <span className="pill ok">schedule clean — {fig.blockDay.toFixed(1)} h a day, no short turns</span>}
              {lf.map((p) => { const x = patternPill(p); return <span key={p.route_id} className={"pill " + x.cls}>{x.text}</span>; })}
            </div>
            <div className="note">In the game: loads on each route, the maintenance ratio, and that every leg flew on time.</div>
          </div>
        );
      })}
      {up.length ? (
        <div className="tblwrap">
          <table className="tbl" style={{ marginTop: 4 }} data-figure="check: checks coming up">
            <tbody>
              <tr><th style={{ width: 170 }}>Due</th><th>Aircraft</th></tr>
              {upcomingByDay(up).map(([d, regs]) => {
                const n = dayDiff(today, d);
                return <tr key={d}><td><b>{niceDate(d)}</b> <span className="dim">in {n} day{n === 1 ? "" : "s"}</span></td><td>{regs.join(", ")}</td></tr>;
              })}
            </tbody>
          </table>
        </div>
      ) : null}
      {doneN ? <div className="dim">{doneN} aircraft checked since their schedule last changed.</div> : null}
    </>
  );
}