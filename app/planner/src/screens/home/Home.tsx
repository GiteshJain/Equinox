// Home (decision #18, build pull request 5; spec docs/specs/2026-10-13-home.md, and the Building chat's review): the
// network at a glance, as the old planner's Home shows it, from the same data, with the same figures and look. Above the
// page, the operations hero (the globe, aircraft in the air and four tiles), which on the old Home stands in for the page
// heading and the key-figure row (that row stays in the page, hidden, as there); then the network map, aircraft on order
// and the airline cards. Needs attention, Coming up and the to-do board moved to Today on 20 Oct (spec
// docs/specs/2026-10-20-today-performance-systems.md), and File into planner with them, so each thing lives in one place.
// Every figure comes from its one home (decision #19): the planning library on rules_input(world, 'flown') for the key
// figures, the hero, positions and the airline cards; the database's captured figures for the group's average load and
// the loads per route; the tables for the rest. Home only words and arranges them. It moves on with the clock each
// minute.
import { useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router";
import { positions, summary } from "@rules";
import { useNow } from "../../data/clock";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import { AirlineMark } from "../../ui/AirlineMark";
import { Board } from "../../ui/Board";
import { niceDate, untilText } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { Pill } from "../../ui/Pill";
import { RoutePopup } from "../routes/RoutePopup";
import { itemRoute } from "../screens";
import { AircraftPopup } from "../tails/AircraftPopup";
import type { HomeAirline } from "./reads";
import { AirlineCards } from "./AirlineCards";
import { greeting, heroFigures, keyFigureTiles } from "./figures";
import { Hero } from "./Hero";
import type { HeroPlane, HeroRoute, LatLon } from "./heroScene";
import { NetworkMap } from "./NetworkMap";
import { familyWords, onOrder } from "./onOrder";
import { useAirlineCards, useHomeAircraft, usePlanCards, useSitePhotos } from "./reads";

const first = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

export function Home() {
  const now = useNow();
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const rulesQ = useRules(w);
  const aircraftQ = useHomeAircraft(w);
  const planCardsQ = usePlanCards(w);
  const cardsQ = useAirlineCards(w);
  const photosQ = useSitePhotos();
  // the route pop-up a click on the map's route opens (Routes' RoutePopup, build pull request 6)
  const [popup, setPopup] = useState<number | null>(null);
  // the aircraft pop-up (Tails' AircraftPopup, build pull request 7), kept in the address (/planner/?aircraft=N001AW) so a
  // link or the back button reopens it
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
  const ready = !!(rules && cardsQ.data && aircraftQ.data && planCardsQ.data && airlinesQ.data);

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

  const loadError = first(world, airlinesQ, rulesQ, aircraftQ, planCardsQ, cardsQ);
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
          ? <OnOrderBoard data={onOrder(aircraftQ.data, rules, new Map(planCardsQ.data.map((p) => [p.aircraft_id, p.title] as const)), airlines, now.getTime())} now={now.getTime()} />
          : null}

        {cards ? <AirlineCards cards={cards} airlines={airlines} photos={photosQ.data} /> : null}
      </main>
    </>
  );
}

/** Aircraft on order, by airline: an arrived one with a plan card is filed from Today (its File into planner moved there
 *  on 20 Oct). */
function OnOrderBoard({ data, now }: { data: ReturnType<typeof onOrder>; now: number }) {
  if (!data.count) return null;
  return (
    <Board title="Aircraft on order" className="oob" figure="home: aircraft on order"
      note={`${data.count} aircraft · one that has arrived with a plan card is filed from Today`}>
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
                      <td className="n ooact">{r.hasCard ? (r.arrived ? <Link className="link" to={itemRoute("today", { hash: "to-file" })}>to file on Today</Link> : null)
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
