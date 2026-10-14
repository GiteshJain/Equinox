// Home (decision #18, build pull request 5; spec docs/specs/2026-10-13-home.md, and the Building chat's review): what the
// old planner's Home shows, from the same data, with the same figures and look. Above the page, the operations hero (the
// globe, aircraft in the air and four tiles), which on the old Home stands in for the page heading and the key-figure
// row (that row stays in the page, hidden, as there); then the network map, aircraft on order, needs attention, coming
// up, the to-do board and the airline cards. Every figure comes from its one home (decision #19): the planning library
// on rules_input(world, 'flown') for the key figures, the hero, positions, the airline cards, the one-week checks and
// the schedule checks; the database's captured figures for the capture, the group's average load, can order, routes to
// fix and the loads per route; the tables for the rest. Home only words and arranges them. It moves on with the clock
// each minute.
import { useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router";
import { checks as checkRules, positions, summary } from "@rules";
import { useNow } from "../../data/clock";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import { saver } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { AttentionList } from "../../ui/AttentionList";
import { dismissKey, withoutDismissed, type AttItem } from "../../ui/attention";
import { Board } from "../../ui/Board";
import { inDays, niceDate, todayAt, untilText } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { Pill } from "../../ui/Pill";
import { RoutePopup } from "../routes/RoutePopup";
import { itemRoute } from "../screens";
import { AircraftPopup } from "../tails/AircraftPopup";
import { AirlineCards } from "./AirlineCards";
import { homeAttention, type HomeAirline } from "./attention";
import { comingUp, UP_LABEL, type UpEvent } from "./comingUp";
import { greeting, heroFigures, keyFigureTiles } from "./figures";
import { Hero } from "./Hero";
import type { HeroPlane, HeroRoute, LatLon } from "./heroScene";
import { NetworkMap } from "./NetworkMap";
import { familyWords, onOrder } from "./onOrder";
import {
  useAirlineCards, useBackups, useCaptureStatus, useDismissals, useGrowth, useHomeAircraft, useJobs, usePlanCards, useRotations,
  useSitePhotos, useTodoItems, useTodos,
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
  const growthQ = useGrowth(w);
  const photosQ = useSitePhotos();
  // dismissed here and not yet back from the database (and, on a preview, dismissed here only, as the old planner does)
  const [dismissedHere, setDismissedHere] = useState<ReadonlySet<string>>(new Set());
  // the route pop-up a click on the map's route opens (Routes' RoutePopup, build pull request 6)
  const [popup, setPopup] = useState<number | null>(null);
  // the aircraft pop-up an item about one aircraft opens, as on the old Home (Tails' AircraftPopup, build pull request 7),
  // kept in the address (/planner/next/?aircraft=N001AW) so a link or the back button reopens it
  const [search, setSearch] = useSearchParams();
  const tailPopup = search.get("aircraft");
  const setTailPopup = (reg: string | null) => setSearch((s) => {
    const n = new URLSearchParams(s);
    if (reg) n.set("aircraft", reg);
    else n.delete("aircraft");
    return n;
  });

  const airlines: HomeAirline[] = useMemo(() => (airlinesQ.data ?? []).map((a) => ({
    id: a.id, name: a.planner_name ?? a.public_name ?? a.game_name ?? `Airline ${a.game_id}`, code: a.iata_code, color: a.livery_color,
    photo: a.photo_city,
  })), [airlinesQ.data]);
  const rules = rulesQ.data?.rules;
  const figures = useMemo(() => (rules ? summary.keyFigures(rules) : null), [rules]);
  const cards = useMemo(() => (rules ? summary.airlineCards(rules) : null), [rules]);
  const nowFigures = useMemo(() => (rules ? summary.now(rules, now.toISOString()) : null), [rules, now]);
  const checks = useMemo(() => (rules && aircraftQ.data && rotationsQ.data
    ? checkRules.oneWeek(rules, { aircraft: aircraftQ.data, rotations: rotationsQ.data }, today) : null), [rules, aircraftQ.data, rotationsQ.data, today]);
  const todos = useMemo(() => (todosQ.data && itemsQ.data ? todoViews(todosQ.data, itemsQ.data) : null), [todosQ.data, itemsQ.data]);
  const ready = !!(rules && checks && todos && dismissalsQ.data && backupsQ.data && jobsQ.data && captureQ.data && cardsQ.data && growthQ.data
    && aircraftQ.data && planCardsQ.data && airlinesQ.data);
  const attention = useMemo(() => (rules && checks && todosQ.data ? homeAttention({
    now, today, airlines, rules, checks, todos: todosQ.data, capture: captureQ.data ?? null, backups: backupsQ.data ?? null,
    jobs: jobsQ.data ?? null, cards: cardsQ.data?.airlines ?? null, growth: growthQ.data ?? null,
  }) : null), [now, today, airlines, rules, checks, todosQ.data, captureQ.data, backupsQ.data, jobsQ.data, cardsQ.data, growthQ.data]);
  const dismissed = useMemo(() => new Set([...(dismissalsQ.data ?? []).map((d) => d.alert_key), ...dismissedHere]), [dismissalsQ.data, dismissedHere]);

  // the hero's globe: every flying route, and each aircraft in the air at this minute (the library's positions)
  const coords = useMemo(() => {
    const m = new Map<string, LatLon>();
    for (const a of rules?.airports.values() ?? []) if (a.lat != null && a.lon != null) m.set(a.code, [Number(a.lat), Number(a.lon)]);
    return m;
  }, [rules]);
  const heroRoutes: HeroRoute[] = useMemo(() => {
    if (!rules) return [];
    const ids = new Set([...rules.rotations.values()].map((r) => r.route_id));
    return [...rules.routes.values()].filter((r) => ids.has(r.id)).flatMap((r) => {
      const a = coords.get(r.hub_code), b = coords.get(r.dest_code);
      return a && b ? [{ key: String(r.id), a, b }] : [];
    });
  }, [rules, coords]);
  const planes: HeroPlane[] = useMemo(() => (rules ? positions.positionsAt(rules, now.toISOString()) : [])
    .filter((p) => p.state === "air").flatMap((p) => {
      const a = p.from ? coords.get(p.from) : undefined, b = p.to ? coords.get(p.to) : undefined;
      return a && b && p.share != null ? [{ a, b, share: p.share }] : [];
    }), [rules, now, coords]);

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

  const loadError = first(world, airlinesQ, rulesQ, aircraftQ, rotationsQ, planCardsQ, todosQ, itemsQ, dismissalsQ, backupsQ, jobsQ, captureQ, cardsQ, growthQ);
  return (
    <>
      <Hero figures={nowFigures ? heroFigures(nowFigures, cardsQ.data) : null} hello={greeting(now)} routes={heroRoutes} planes={planes} now={now} />
      <main className="view home eq-enter" data-screen="home" data-home-ready={ready ? "yes" : "no"}>
        {loadError ? <ErrorBox error={loadError} /> : null}

        <div className="kpis" data-kpis>
          {figures ? keyFigureTiles(figures, cardsQ.data).map((t) => (
            <div className="kpi" key={t.label} data-figure="home: key figures">
              <div className="kv">{t.value}</div><div className="kl">{t.label}</div>
            </div>
          )) : null}
        </div>

        <NetworkMap rules={rules} airlines={airlines} now={now} worldId={w} aircraft={aircraftQ.data} onOpenRoute={setPopup} />
        {popup != null && rules ? <RoutePopup routeId={popup} rules={rules} airlines={airlines} onClose={() => setPopup(null)} /> : null}
        {tailPopup && rules ? <AircraftPopup registration={tailPopup} rules={rules} onClose={() => setTailPopup(null)} /> : null}

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
                  {shown.length ? <AttentionList items={shown} hrefOf={hrefOf} onDismiss={(a) => void dismiss(a)}
                    onOpen={(a) => { if (!a.tail || a.route || a.screen !== "tails") return false; setTailPopup(a.tail); return true; }} />
                    : <div className="dim">Every aircraft is inside its maintenance, turn and night-ban rules, and no checks are due.</div>}
                </>
              );
            })()}
          </Board>
          <ComingUp events={checks && todosQ.data ? comingUp(checks, todosQ.data, today) : null} today={today} />
        </div>

        <TodoBoard worldId={w} todos={todos} today={today} now={now} />

        {cards ? <AirlineCards cards={cards} airlines={airlines} photos={photosQ.data} /> : null}
      </main>
    </>
  );
}

function OnOrderBoard({ data, now }: { data: ReturnType<typeof onOrder>; now: number }) {
  if (!data.count) return null;
  return (
    <Board title="Aircraft on order" className="oob" figure="home: aircraft on order"
      note={`${data.count} aircraft · "File into planner" appears once one arrives, and files it on Tails`}>
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
                      <td className="n ooact">{r.hasCard ? (r.arrived ? <Link className="primary sm" to={"/tails?" + new URLSearchParams({ ...(g.airline.code ? { airline: g.airline.code } : {}), file: r.registration }).toString()} data-file-into-planner>File into planner</Link> : null)
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
