// Home (decision #18, build pull request 5; spec docs/specs/2026-10-13-home.md, and the Building chat's review): the
// network at a glance, as the old planner's Home shows it, from the same data, with the same figures and look. Above the
// page, the operations hero (the globe, aircraft in the air and four tiles), which on the old Home stands in for the page
// heading and the key-figure row (that row stays in the page, hidden, as there); then needs attention's summary cards,
// the network map and the airline cards. Needs attention, Coming up and the to-do board moved to Today on 20 Oct (spec
// docs/specs/2026-10-20-today-performance-systems.md), and File into planner with them, so each thing lives in one place.
// Since 23 Oct (spec docs/specs/2026-10-23-attention-on-home.md) needs attention's summary cards are here, not on Today:
// one per thing waiting, exactly as Today showed them (today/model.ts's waitingCards, on the reads and figures Today
// uses, today/useAttention.ts), each See all opening its group's section on Today (/planner/today#att-<kind>); with
// nothing waiting, one line says so. Aircraft on order went the same day: Today's Orders and delivery lines show it.
// Every figure comes from its one home (decision #19): the planning library on rules_input(world, 'flown') for the key
// figures, the hero, positions and the airline cards; the database's captured figures for the group's average load and
// the loads per route; the tables for the rest. Home only words and arranges them. It moves on with the clock each
// minute.
// Since 23 Oct (spec docs/specs/2026-10-23-planner-look-home.md, the new look's step 8) Home wears the style of Today and
// Performance: the hero on the foundation's tokens, needs attention's cards as Today's were (.waitgrid, .wcard), the map
// in a card with a one-line heading and its airline legend as pills, and the airline cards as Performance's scorecards
// (AirlineCards.tsx). Nothing it shows, reads or links to changed.
import { useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router";
import { positions, summary } from "@rules";
import { useNow } from "../../data/clock";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import type { AttItem } from "../../ui/attention";
import { todayAt } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { RoutePopup } from "../routes/RoutePopup";
import { screen } from "../screens";
import { gameMaintenance } from "../systems/model";
import { useFleetChecks } from "../systems/reads";
import { AircraftPopup } from "../tails/AircraftPopup";
import type { HomeAirline } from "./reads";
import { AirlineCards } from "./AirlineCards";
import { greeting, heroFigures, keyFigureTiles } from "./figures";
import { Hero } from "./Hero";
import type { HeroPlane, HeroRoute, LatLon } from "./heroScene";
import { NetworkMap } from "./NetworkMap";
import { useAirlineCards, useHomeAircraft, useSitePhotos } from "./reads";
import { waitingCards, type WaitCard } from "../today/model";
import { opensAircraft, useAttention } from "../today/useAttention";

const first = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

export function Home() {
  const now = useNow();
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const rulesQ = useRules(w);
  const aircraftQ = useHomeAircraft(w);
  const cardsQ = useAirlineCards(w);
  const photosQ = useSitePhotos();
  // the game's maintenance from the latest night's fleet pages (fleet_checks(), the read Tails and its pop-up share): the
  // airline cards' lowest maintenance uses it where it has a figure (since 23 Oct); until it's read, the estimate
  const fleetQ = useFleetChecks(w);
  const gameMaint = useMemo(() => (fleetQ.data ? gameMaintenance(fleetQ.data) : undefined), [fleetQ.data]);
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
  // needs attention's summary cards (Today's until 23 Oct): the same reads and figures as Today's sections
  const today = todayAt(now);
  const att = useAttention(now, today);
  const waiting: WaitCard[] | null = att.ready && att.orders && att.filing && att.attShown && att.todosQ.data ? waitingCards({
    orders: att.orders, toFile: att.filing, attention: att.attShown.shown, todos: att.todosQ.data, game: 0, today, hrefOf: att.hrefOf,
    screenName: (a) => screen(a.screen).name,
  }) : null;
  const openAircraft = (a: AttItem) => { if (!opensAircraft(a) || !a.tail) return false; setTailPopup(a.tail); return true; };
  const ready = !!(rules && cardsQ.data && aircraftQ.data && airlinesQ.data && waiting);

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

  const loadError = first(world, airlinesQ, rulesQ, aircraftQ, cardsQ) ?? att.loadError;
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

        <AttentionCards cards={waiting} onOpen={openAircraft} />

        <NetworkMap rules={rules} airlines={airlines} now={now} worldId={w} aircraft={aircraftQ.data} onOpenRoute={setPopup} />
        {popup != null && rules ? <RoutePopup routeId={popup} rules={rules} airlines={airlines} onClose={() => setPopup(null)} /> : null}
        {tailPopup && rules ? <AircraftPopup registration={tailPopup} rules={rules} onClose={() => setTailPopup(null)} /> : null}

        {cards && rules ? <AirlineCards cards={cards} airlines={airlines} photos={photosQ.data} rules={rules} game={gameMaint} /> : null}
      </main>
    </>
  );
}

/** Needs attention's summary cards (Today's until 23 Oct, spec docs/specs/2026-10-23-attention-on-home.md): one per
 *  thing waiting, the most urgent first, each with its button (where it's fixed, or See all, which opens its group's
 *  section on Today); with nothing waiting, one line says so, as Today's did. Home doesn't run the game check, so its
 *  differences are Today's alone. */
function AttentionCards({ cards, onOpen }: { cards: readonly WaitCard[] | null; onOpen: (a: AttItem) => boolean }) {
  if (!cards) return <section className="waitgrid homeatt" aria-label="Needs attention" data-figure="home: needs attention cards"><div className="loading">Loading…</div></section>;
  if (!cards.length) {
    return (
      <section className="waitgrid homeatt" aria-label="All clear" data-figure="home: needs attention cards">
        <div className="wcard clear" data-wait-card="clear">
          <span className="wkind">All clear</span>
          <h2 className="wh">Nothing to order or file, and nothing needs attention.</h2>
        </div>
      </section>
    );
  }
  return (
    <section className="waitgrid homeatt" aria-label="Needs attention" data-figure="home: needs attention cards">
      {cards.map((c) => (
        <div className={"wcard " + c.kind + (c.urgent ? " urgent" : "")} key={c.key} data-wait-card={c.kind}>
          <span className="wkind">{c.label}</span>
          <h2 className="wh">{c.heading}</h2>
          {c.detail ? <p className="wd">{c.detail}</p> : null}
          <div className="wact">
            {c.action.href ? (
              <Link className={"primary" + (c.urgent ? " now" : "")} to={c.action.href} data-wait-href={c.action.href}
                onClick={(e) => { if (c.action.item && onOpen(c.action.item)) e.preventDefault(); }}>{c.action.text}</Link>
            ) : null}
          </div>
        </div>
      ))}
    </section>
  );
}
