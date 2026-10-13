// Home (decision #18, build pull request 5; spec docs/specs/2026-10-13-home.md): what the old planner's Home shows, from
// the same data, with the same figures: the key figures, the network right now on the globe, aircraft on order, needs
// attention, coming up and the to-do board. Every figure comes from its one home (decision #19): the planning library
// on rules_input(world, 'flown') for the key figures, the aircraft's positions and the schedule checks; the database's
// captured figures for the capture, the average load, can order and routes to fix; the tables for the rest. Home only
// words and arranges them. It moves on with the clock each minute.
import { useMemo, useState } from "react";
import { positions, summary, type Rules } from "@rules";
import { OLD_PLANNER } from "../../data/config";
import { oneWeekChecks, type CheckAircraft } from "../../data/checks";
import { useNow } from "../../data/clock";
import { useOurAirlines, useWorld } from "../../data/reads";
import { saver } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { AttentionList } from "../../ui/AttentionList";
import { dismissKey, withoutDismissed, type AttItem } from "../../ui/attention";
import { Board } from "../../ui/Board";
import { inDays, niceDate, todayAt, untilText } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { Pill } from "../../ui/Pill";
import { itemRoute } from "../screens";
import { homeAttention, type HomeAirline } from "./attention";
import { comingUp, UP_LABEL, type UpEvent } from "./comingUp";
import { keyFigureTiles } from "./figures";
import { Globe } from "./Globe";
import type { GlobePlane, GlobeRoute, LatLon } from "./globeScene";
import { familyWords, onOrder } from "./onOrder";
import {
  useAirlineCards, useBackups, useCaptureStatus, useDismissals, useHomeAircraft, useJobs, usePlanCards, useRotations, useRoutesToFix,
  useRules, useTodoItems, useTodos,
} from "./reads";
import { TodoBoard } from "./TodoBoard";
import { dismissChanges, showAgainChanges, todoViews } from "./todos";

const first = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

export function Home() {
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
  const cardsQ = useAirlineCards(w);
  const fixQ = useRoutesToFix(w);
  // dismissed here and not yet back from the database (and, on a preview, dismissed here only, as the old planner does)
  const [dismissedHere, setDismissedHere] = useState<ReadonlySet<string>>(new Set());

  const airlines: HomeAirline[] = useMemo(() => (airlinesQ.data ?? []).map((a) => ({
    id: a.id, name: a.planner_name ?? a.public_name ?? a.game_name ?? `Airline ${a.game_id}`, code: a.iata_code, color: a.livery_color,
  })), [airlinesQ.data]);
  const rules = rulesQ.data?.rules;
  const figures = useMemo(() => (rules ? summary.keyFigures(rules) : null), [rules]);
  const checks = useMemo(() => (rules && aircraftQ.data && rotationsQ.data ? homeChecks(rules, aircraftQ.data, rotationsQ.data, today) : null),
    [rules, aircraftQ.data, rotationsQ.data, today]);
  const todos = useMemo(() => (todosQ.data && itemsQ.data ? todoViews(todosQ.data, itemsQ.data) : null), [todosQ.data, itemsQ.data]);
  const ready = !!(rules && checks && todos && dismissalsQ.data && backupsQ.data && jobsQ.data && captureQ.data && cardsQ.data && fixQ.data
    && aircraftQ.data && planCardsQ.data && airlinesQ.data);
  const attention = useMemo(() => (rules && checks && todosQ.data ? homeAttention({
    now, today, airlines, rules, checks, todos: todosQ.data, capture: captureQ.data ?? null, backups: backupsQ.data ?? null,
    jobs: jobsQ.data ?? null, cards: cardsQ.data ?? null, routesToFix: fixQ.data ?? null,
  }) : null), [now, today, airlines, rules, checks, todosQ.data, captureQ.data, backupsQ.data, jobsQ.data, cardsQ.data, fixQ.data]);
  const dismissed = useMemo(() => new Set([...(dismissalsQ.data ?? []).map((d) => d.alert_key), ...dismissedHere]), [dismissalsQ.data, dismissedHere]);
  const nameOf = (id: number) => airlines.find((a) => a.id === id)?.name ?? "";

  const hrefOf = (a: AttItem) => {
    if (a.screen === "home") return itemRoute("home", { hash: "todo" });
    if (a.tail) return itemRoute(a.screen, { tail: a.tail });
    if (a.route) {
      const [al = "", hub = "", dest = ""] = a.route.split("|");
      return itemRoute(a.screen, { airline: airlines.find((x) => x.name === al)?.code, hub, dest });
    }
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

  const loadError = first(world, airlinesQ, rulesQ, aircraftQ, rotationsQ, planCardsQ, todosQ, itemsQ, dismissalsQ, backupsQ, jobsQ, captureQ, cardsQ, fixQ);
  return (
    <main className="view home" data-screen="home" data-home-ready={ready ? "yes" : "no"}>
      <div className="vh">
        <h1>Overview</h1>
        <p>The whole network at a glance — where every aircraft is, what needs attention, and what's coming up.</p>
      </div>
      {loadError ? <ErrorBox error={loadError} /> : null}

      <div className="kpis" data-kpis>
        {figures ? keyFigureTiles(figures, cardsQ.data, nameOf).map((t) => (
          <div className="kpi" key={t.label} data-figure="home: key figures" title={t.title}>
            <div className="kv">{t.value}</div><div className="kl">{t.label}</div>
          </div>
        )) : <div className="kpi loading">Loading…</div>}
      </div>

      <Network rules={rules} airlines={airlines} now={now} />

      {aircraftQ.data && rules && planCardsQ.data
        ? <OnOrderBoard data={onOrder(aircraftQ.data, rules, new Set(planCardsQ.data.map((p) => p.aircraft_id)), airlines, now.getTime())} now={now.getTime()} />
        : null}

      <div className="hgrid">
        <Board title="Needs attention" figure="home: needs attention" id="attention"
          note={attention ? (() => { const n = withoutDismissed(attention, dismissed).shown.length; return n ? `${n} item${n === 1 ? "" : "s"}` : "nothing right now"; })() : ""}>
          {!attention || !ready ? <div className="loading">Loading…</div> : (() => {
            const { shown, hidden } = withoutDismissed(attention, dismissed);
            return (
              <>
                {hidden ? (
                  <div className="dim hiddenline" data-dismissed={hidden}>
                    {hidden} dismissed · <button type="button" className="link" onClick={() => void showAgain()} data-show-again>show again</button>
                  </div>
                ) : null}
                {shown.length ? <AttentionList items={shown} hrefOf={hrefOf} onDismiss={(a) => void dismiss(a)} />
                  : <div className="dim">Every aircraft is inside its maintenance, turn and night-ban rules, and no checks are due.</div>}
              </>
            );
          })()}
        </Board>
        <ComingUp events={checks && todosQ.data ? comingUp(checks, todosQ.data, today) : null} today={today} />
      </div>

      <TodoBoard worldId={w} todos={todos} today={today} now={now} />
    </main>
  );
}

/** The one-week checks of our aircraft in service, from each aircraft's rotations' launch days. A rotation belongs to
 * the aircraft its outbound leg flies (else its return's), as the old planner's frequencies did. */
function homeChecks(rules: Rules, aircraft: { id: number; registration: string; status: string; checked_on: string | null; schedule_changed_on: string | null }[],
  rotations: { id: number; launched_on: string | null }[], today: string) {
  const flownBy = new Map<number, number>();
  for (const l of rules.legs) {
    if (l.rotation_id == null || l.aircraft_id == null) continue;
    if (l.leg_no === 1 || !flownBy.has(l.rotation_id)) flownBy.set(l.rotation_id, l.aircraft_id);
  }
  const launches = new Map<number, string[]>();
  for (const r of rotations) {
    const a = flownBy.get(r.id);
    if (a == null || !r.launched_on) continue;
    const list = launches.get(a);
    if (list) list.push(r.launched_on);
    else launches.set(a, [r.launched_on]);
  }
  const inService: CheckAircraft[] = aircraft.filter((a) => a.status === "active");
  return oneWeekChecks(inService, launches, today);
}

function Network({ rules, airlines, now }: { rules: Rules | undefined; airlines: HomeAirline[]; now: Date }) {
  const [only, setOnly] = useState<number | null>(null);
  // each airport's place and each airline's colour, once per read
  const coords = useMemo(() => {
    const m = new Map<string, LatLon>();
    for (const a of rules?.airports.values() ?? []) if (a.lat != null && a.lon != null) m.set(a.code, [Number(a.lat), Number(a.lon)]);
    return m;
  }, [rules]);
  const colors = useMemo(() => new Map(airlines.map((a) => [a.id, a.color ?? "#8B96A8"])), [airlines]);
  const flown = useMemo(() => {
    if (!rules) return [];
    const ids = new Set([...rules.rotations.values()].map((r) => r.route_id));
    return [...rules.routes.values()].filter((r) => ids.has(r.id) && (only == null || r.airline_id === only));
  }, [rules, only]);
  const routes: GlobeRoute[] = useMemo(() => flown.flatMap((r) => {
    const a = coords.get(r.hub_code), b = coords.get(r.dest_code);
    return a && b ? [{ key: String(r.id), a, b, color: colors.get(r.airline_id) ?? "#8B96A8" }] : [];
  }), [flown, coords, colors]);
  const bases: LatLon[] = useMemo(() => (rules?.bases ?? []).filter((b) => only == null || b.airline_id === only)
    .flatMap((b) => { const p = coords.get(b.airport_code); return p ? [p] : []; }), [rules, only, coords]);
  // where each aircraft is at this minute (the planning library's positions); those in the air are drawn
  const planes: GlobePlane[] = useMemo(() => (rules ? positions.positionsAt(rules, now.toISOString()) : [])
    .filter((p) => p.state === "air" && (only == null || p.airline_id === only)).flatMap((p) => {
      const a = p.from ? coords.get(p.from) : undefined, b = p.to ? coords.get(p.to) : undefined;
      return a && b && p.share != null ? [{ a, b, share: p.share }] : [];
    }), [rules, now, only, coords]);
  const onlyName = only == null ? "" : airlines.find((a) => a.id === only)?.name ?? "";
  return (
    <section className="board mapb" aria-label="The network right now" data-board="network">
      <div className="maph">
        <h3 className="rh">The network right now <span className="note" data-network-note>
          {onlyName ? onlyName + " · " : ""}{flown.length} routes · {planes.length} in the air · day and night as of {now.toISOString().slice(11, 16)}Z
        </span></h3>
        <div className="mleg">
          <button type="button" className={"mf" + (only == null ? " on" : "")} onClick={() => setOnly(null)}>All</button>
          {airlines.map((a) => (
            <button type="button" key={a.id} className={"mf" + (only === a.id ? " on" : "")} title={a.name} onClick={() => setOnly(a.id)}>
              <AirlineMark color={a.color} />{a.name}
            </button>
          ))}
        </div>
      </div>
      {rules ? <Globe routes={routes} bases={bases} planes={planes} now={now} /> : <div className="loading">Loading…</div>}
    </section>
  );
}

function OnOrderBoard({ data, now }: { data: ReturnType<typeof onOrder>; now: number }) {
  if (!data.count) return null;
  return (
    <Board title="Aircraft on order" className="oob" figure="home: aircraft on order"
      note={`${data.count} aircraft · "File into planner" appears once one arrives, and opens the old planner for now`}>
      <div className="gsum">
        {data.groups.map((g) => <span className="gchip" key={g.airline.id} data-oo-count={g.airline.name}><AirlineMark color={g.airline.color} />{g.airline.name} <b>{g.rows.length}</b></span>)}
      </div>
      {data.groups.map((g) => {
        const next = g.rows[0], last = g.rows[g.rows.length - 1];
        const day = (ms: number) => (Number.isFinite(ms) ? new Date(ms).toISOString() : "");
        return (
          <details className="gsec" key={g.airline.id} data-oo-airline={g.airline.name}>
            <summary>
              <AirlineMark color={g.airline.color} /><b>{g.airline.name}</b>{" "}
              <span className="dim" data-oo-summary>
                {g.rows.length} on order ({g.families.map(familyWords).join(", ")}) · next {next?.registration} {next ? untilText(next.at, now) : ""} · last {last ? niceDate(day(last.at).slice(0, 10)) : ""}
              </span>
              {g.arrived ? <> <Pill kind="warn" small>{g.arrived} to file</Pill></> : null}
            </summary>
            <div className="tblwrap">
              <table className="tbl gtbl">
                <thead><tr><th>Aircraft</th><th>Type</th><th>Delivers (UTC)</th><th></th><th>Base</th><th>Plan</th><th></th></tr></thead>
                <tbody>
                  {g.rows.map((r) => (
                    <tr key={r.id} data-oo-row={r.registration}>
                      <td><b>{r.registration}</b></td>
                      <td>{r.type}{r.config ? <> <span className="dim">{r.config}</span></> : null}</td>
                      <td>{niceDate(day(r.at).slice(0, 10))} {day(r.at).slice(11, 16)}</td>
                      <td>{r.arrived ? <Pill kind="warn" small>arrived</Pill> : <span className="dim">{untilText(r.at, now)}</span>}</td>
                      <td>{r.base}</td>
                      <td className="dim">{r.plan}</td>
                      <td className="n ooact">{r.hasCard ? (r.arrived ? <a className="primary sm" href={OLD_PLANNER} data-file-into-planner>File into planner</a> : null)
                        : <span className="dim">no plan card</span>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </details>
        );
      })}
    </Board>
  );
}

function ComingUp({ events, today }: { events: UpEvent[] | null; today: string }) {
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
        {([["", "All"], ["check", "One-week checks"], ["todo", "To-dos"]] as const).map(([k, l]) => (
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
