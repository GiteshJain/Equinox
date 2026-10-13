// The airline cards at the foot of Home (the old planner's airline grid, .agrid, and eqCards): one card per airline in
// its colour, with its in-game logo (the website's logos.js) and whether it's flying, its bases (hubs, then focus cities
// dashed; filled once a route flies from them), its aircraft, routes, flights and block hours a day, the lowest
// maintenance among its aircraft, short and tight turns or "clean", and "Open fleet ›". Every figure is the planning
// library's (summary.airlineCards). Where the website has a photo of the airline's home city, the card shows it behind
// (the old planner's hub-city photos, from site_public()). "Open fleet ›" opens the airline on Tails (build pull request 7).
import { useEffect, useState, type CSSProperties } from "react";
import { Link } from "react-router";
import type { AirlineCard } from "@rules";
import { Pill } from "../../ui/Pill";
import { loadLogos } from "../../ui/siteFiles";
import type { HomeAirline } from "./attention";

/** The city whose photo each airline's card shows (the old planner's EQ_HUBPHOTO, by planner name). */
export const HUB_PHOTO: Record<string, string> = {
  "Pan American": "New York", "Virgin Atlantic": "London", "Ryanair": "Paris", "Kingfisher": "Delhi", "China Eastern": "Shanghai",
  "Malaysia Airlines": "Kuala Lumpur",
};

export function AirlineCards({ cards, airlines, photos }: {
  cards: readonly AirlineCard[]; airlines: readonly HomeAirline[]; photos: Record<string, { url: string }> | undefined;
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
        const photo = photos?.[HUB_PHOTO[a.name] ?? ""]?.url;
        const style = { "--lv": a.color || "#8B96A8", ...(photo ? { "--ph": `url("${photo}")` } : {}) } as CSSProperties;
        const m = c.lowest_maintenance;
        return (
          <div key={a.id} className={"acard" + (photo ? " eqphoto" : "")} style={style} data-acard={a.name}>
            <div className="ach">
              {logos?.[a.name] ? <img className="alogo" src={logos[a.name]} alt={a.name} style={{ height: 23 }} />
                : <><i className="lv" style={{ "--lv": a.color || "#8B96A8" } as CSSProperties} /><b>{a.name}</b></>}
              {c.flying ? <Pill kind="ok">flying</Pill> : <Pill kind="mute">not launched</Pill>}
            </div>
            <div className="acb">
              {c.bases.map((b) => (
                <span key={b.code} className={`hubtag ${b.live ? "on" : ""} ${b.role === "focus" ? "fc" : ""}`} data-hubtag={b.code}
                  title={`${b.role === "focus" ? "focus city" + (b.parent_code ? ", feeds " + b.parent_code : "") + " · " : "hub · "}${b.live ? "flights based here" : "not yet operating as a base"}`}>{b.code}</span>
              ))}
            </div>
            <div className="acs">
              <span><b>{c.aircraft}</b> aircraft</span><span><b>{c.routes}</b> routes</span>
              <span><b>{Math.round(c.flights_day)}</b> flights/day</span><span><b>{c.block_hours_day.toFixed(0)}</b> block h/day</span>
            </div>
            <div className="acf">
              {m ? <Pill kind={m.level}>lowest maintenance ≈{m.pct}%</Pill> : null}
              {c.short_turns ? <Pill kind="bad">{c.short_turns} short turns</Pill> : null}
              {c.tight_turns ? <Pill kind="warn">{c.tight_turns} tight turns</Pill> : null}
              {c.clean ? <Pill kind="ok">clean</Pill> : null}
            </div>
            <Link className="link" to={"/tails" + (a.code ? "?airline=" + encodeURIComponent(a.code) : "")} data-open-fleet={a.name}>Open fleet ›</Link>
          </div>
        );
      })}
    </div>
  );
}
