// The airline cards at the foot of Home (the old planner's airline grid, .agrid, and eqCards): one card per airline, with
// its in-game logo (the website's logos.js) and whether it's flying, its bases (hubs, then focus cities dashed; filled
// once a route flies from them), its aircraft, routes, flights and block hours a day, the lowest maintenance among its
// aircraft, short and tight turns or "clean", and "Open fleet ›". Every figure is the planning library's
// (summary.airlineCards), but the lowest maintenance: since 23 Oct (spec
// docs/specs/2026-10-23-game-maintenance-on-tails.md) the game's figure from the latest night's fleet pages for each
// aircraft that has one, the estimate for the rest (figures.ts' lowestMaintenance), and "clean" judged on that figure
// (cardClean). Where the website has a photo of the airline's city (airlines.photo_city, since build pull request 12; the
// old planner kept the list in its code, EQ_HUBPHOTO), it shows in the band at the card's top (from site_public()), with
// the logo on it. "Open fleet ›" opens the airline on Tails (build pull request 7).
// Since 23 Oct (spec docs/specs/2026-10-23-planner-look-home.md) the cards wear Performance's scorecard style: the band,
// then the colour dot and name as the head with the flying pill, then label/value rows that start at the top of the card
// and keep a readable label column, then the pills and "Open fleet ›" as the footer. Since 30 Oct (spec
// docs/specs/2026-10-30-charts-everywhere.md, part C) a row with the airline's profit over its last 14 reports as a
// sparkline (airline_profit(), as Performance's scorecard).
import { useEffect, useState, type CSSProperties } from "react";
import { Link } from "react-router";
import type { AirlineCard, Rules } from "@rules";
import type { GameMaintFigure } from "../tails/model";
import { Pill } from "../../ui/Pill";
import { loadLogos } from "../../ui/siteFiles";
import { cardClean, lowestMaintenance, lowestWords, profitSpark } from "./figures";
import { ChartTip, Spark, sparkLayout } from "../../ui/charts";
import type { ProfitDay } from "../performance/model";
import type { HomeAirline } from "./reads";

export function AirlineCards({ cards, airlines, photos, rules, game, profitOf }: {
  cards: readonly AirlineCard[]; airlines: readonly HomeAirline[]; photos: Record<string, { url: string }> | undefined;
  rules: Rules; game: ReadonlyMap<number, GameMaintFigure> | undefined;
  /** Each airline's reported profit days (airline_profit()), for the 14-day sparkline (since 30 Oct); absent until read. */
  profitOf?: ReadonlyMap<number, readonly ProfitDay[]>;
}) {
  const [logos, setLogos] = useState<Record<string, string> | null>(null);
  useEffect(() => {
    let alive = true;
    loadLogos().then((l) => { if (alive) setLogos(l); }).catch(() => { if (alive) setLogos({}); });
    return () => { alive = false; };
  }, []);
  return (
    <div className="agrid" data-board="airline cards" data-logos={logos ? "ready" : "loading"} data-photos={photos ? "ready" : "loading"}>
      {airlines.map((a) => {
        const c = cards.find((x) => x.airline_id === a.id);
        if (!c) return null;
        const photo = a.photo ? photos?.[a.photo]?.url : undefined;
        const style = { "--lv": a.color || "#8B96A8", ...(photo ? { "--ph": `url("${photo}")` } : {}) } as CSSProperties;
        const m = lowestMaintenance(rules, a.id, game);
        return (
          <div key={a.id} className="acard" style={style} data-acard={a.name}>
            <div className={"acband" + (photo ? " ph" : "")}>
              {logos?.[a.name] ? <img className="alogo" src={logos[a.name]} alt={a.name} style={{ height: 23 }} /> : null}
            </div>
            <div className="fchead">
              <div className="fch ach">
                <i className="lv" style={{ "--lv": a.color || "#8B96A8" } as CSSProperties} /><b>{a.name}</b>
                {c.flying ? <Pill kind="ok">flying</Pill> : <Pill kind="mute">not launched</Pill>}
              </div>
            </div>
            <dl className="wowl acrows">
              <dt>Bases</dt>
              <dd className="acb">
                {c.bases.length ? c.bases.map((b) => (
                  <span key={b.code} className={`hubtag ${b.live ? "on" : ""} ${b.role === "focus" ? "fc" : ""}`} data-hubtag={b.code}
                    title={`${b.role === "focus" ? "focus city" + (b.parent_code ? ", feeds " + b.parent_code : "") + " · " : "hub · "}${b.live ? "flights based here" : "not yet operating as a base"}`}>{b.code}</span>
                )) : <span className="dim">none</span>}
              </dd>
              <dt>Aircraft</dt><dd>{c.aircraft}</dd>
              <dt>Routes</dt><dd>{c.routes}</dd>
              <dt>Flights a day</dt><dd>{Math.round(c.flights_day)}</dd>
              <dt>Block hours a day</dt><dd>{c.block_hours_day.toFixed(0)}</dd>
              {profitOf ? <ProfitRow name={a.name} days={profitOf.get(a.id)} /> : null}
            </dl>
            <div className="ffoot acfoot">
              <div className="acf">
                {m ? <Pill kind={m.level} title={m.from === "game" ? m.title : undefined}>{lowestWords(m)}</Pill> : null}
                {c.short_turns ? <Pill kind="bad">{c.short_turns} short turns</Pill> : null}
                {c.tight_turns ? <Pill kind="warn">{c.tight_turns} tight turns</Pill> : null}
                {cardClean(c, m) ? <Pill kind="ok">clean</Pill> : null}
              </div>
              <Link className="link" to={"/tails" + (a.code ? "?airline=" + encodeURIComponent(a.code) : "")} data-open-fleet={a.name}>Open fleet ›</Link>
            </div>
          </div>
        );
      })}
    </div>
  );
}

/** The card's profit over the last 14 reports, as Performance's scorecard draws it: a bar a report, green or red; opens
 *  full size like every chart (the chart kit). */
function ProfitRow({ name, days }: { name: string; days: readonly ProfitDay[] | undefined }) {
  const p = profitSpark(name, days ?? []);
  return (
    <>
      <dt>Profit, 14 reports</dt>
      <dd className="acspark" data-profit-spark={p.values.length}>
        {p.values.length ? <ChartTip className="chartwrap kmultw acsparkw" label={`${name}: profit a day`}><Spark g={sparkLayout(p.values, "bar")} tip={p.tip} label={p.tip} /></ChartTip>
          : <span className="dim">none reported yet</span>}
      </dd>
    </>
  );
}
