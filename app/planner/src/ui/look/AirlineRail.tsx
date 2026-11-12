// The six airlines as a rail on the left (to-do 225, decision 4; spec docs/specs/2026-11-11-glass-look.md, step 1): since
// step 6 the only way to pick an airline on Routes, Tails, Performance and Competition. Where each button goes and which is lit is rail.ts's. A vertical bar
// from 761 px wide, a row above the screen below that (styles.css).
import { Link, useLocation } from "react-router";
import { useOurAirlines, useWorld } from "../../data/reads";
import { railAllWorks, railCurrent, railTarget, type RailPick } from "./rail";

export function AirlineRail() {
  const loc = useLocation();
  const world = useWorld();
  const airlinesQ = useOurAirlines(world.data?.id);
  const airlines = (airlinesQ.data ?? []).map((a) => ({
    code: a.iata_code ?? "", name: a.planner_name ?? a.public_name ?? a.game_name ?? `Airline ${a.game_id}`,
  })).filter((a) => a.code);
  const first = airlines[0]?.code ?? "";
  const current = railCurrent(loc.pathname, loc.search, first);

  const button = (pick: RailPick, label: string, name: string) => {
    const lit = current === pick;
    const to = railTarget(loc.pathname, loc.search, pick, first);
    const props = { className: "eq-railbtn" + (lit ? " on" : ""), "aria-label": name, "data-rail": pick, title: name };
    if (to == null || lit) {
      const dead = pick === "all" && !railAllWorks(loc.pathname);
      return (
        <span key={pick} {...props} aria-current={lit ? "true" : undefined} aria-disabled={dead ? "true" : undefined}
          title={dead ? `${loc.pathname.startsWith("/routes") ? "Routes" : "Tails"} shows one airline at a time` : name}>{label}</span>
      );
    }
    return <Link key={pick} to={to} {...props}>{label}</Link>;
  };

  return (
    <nav className="eq-rail" aria-label="Airlines" data-rail-current={current}>
      {button("all", "All", "All airlines")}
      {airlines.map((a) => button(a.code, a.code, a.name))}
    </nav>
  );
}
