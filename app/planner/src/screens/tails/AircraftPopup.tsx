// The aircraft pop-up (the old planner's tailModal), opened from Home's needs attention (an aircraft's maintenance, turns
// and positions), the Check screen and, since build pull request 12, a frequency's aircraft on Routes: the aircraft's
// base, block hours a day, legs a week and maintenance; every issue, or "schedule clean"; its flights, one line per
// number; Open in Tails. The one-week check's line and Mark checked went on 22 Oct (spec
// docs/specs/2026-10-22-remove-aircraft-checks.md; manual §1 has none since 15 Oct). Every figure is the planning
// library's on the start's rules, but one: since 22 Oct (spec docs/specs/2026-10-22-fleet-capture.md §3) the game's own
// maintenance and condition from the latest night's fleet pages (fleet_checks()) beside the planner's maintenance, so the
// two can be compared; and since 22 Oct (spec docs/specs/2026-10-22-aircraft-age-check.md §2) how it came and when it's
// replaced ("came used, replace at 10 years", manual §3).
import { useEffect, useMemo, useRef } from "react";
import { useNavigate } from "react-router";
import { tails, type Rules } from "@rules";
import { useOurAirlines, useWorld } from "../../data/reads";
import { gameFleetWords, gameMaintenance } from "../systems/model";
import { useFleetChecks } from "../systems/reads";
import { AirlineMark } from "../../ui/AirlineMark";
import { itemRoute } from "../screens";
import { Issues, MaintPill } from "./AircraftPage";
import { acquiredWords, blockClock, configCode, figuresOf, H, issuesShown, popupFlights, rulesLegs, shownMaint, typeName } from "./model";
import { useConfigs, useTailsAircraft } from "./reads";

export function AircraftPopup({ registration, rules, onClose }: { registration: string; rules: Rules; onClose: () => void }) {
  const navigate = useNavigate();
  const w = useWorld().data?.id;
  const airlinesQ = useOurAirlines(w);
  const aircraftQ = useTailsAircraft(w);
  const configsQ = useConfigs(w);
  const fleetQ = useFleetChecks(w);
  const close = useRef(onClose);
  useEffect(() => { close.current = onClose; });
  useEffect(() => {
    document.body.classList.add("mopen");
    const esc = (e: KeyboardEvent) => { if (e.key === "Escape") close.current(); };
    document.addEventListener("keydown", esc);
    return () => { document.body.classList.remove("mopen"); document.removeEventListener("keydown", esc); };
  }, []);

  const a = aircraftQ.data?.find((x) => x.registration === registration && x.status === "active");
  const configs = useMemo(() => new Map((configsQ.data ?? []).map((c) => [c.id, c])), [configsQ.data]);
  const fig = useMemo(() => (a ? figuresOf(rules, a.id, rulesLegs(rules)) : null), [rules, a]);
  // its issues judged on the game's maintenance where the latest fleet pages have it (since 23 Oct), as on Tails
  const gameMaint = useMemo(() => (a ? gameMaintenance(fleetQ.data).get(a.id) : undefined), [fleetQ.data, a]);
  const issues = useMemo(() => (a && fig?.week
    ? issuesShown(tails.issues(rules, a.id, rulesLegs(rules), fig.week, fig.maint), shownMaint(rules, a.airline_id, fig.maint, gameMaint)) : []), [rules, a, fig, gameMaint]);
  if (!aircraftQ.data || !configsQ.data) return null;
  if (!a || !fig) return null;
  const airline = (airlinesQ.data ?? []).find((x) => x.id === a.airline_id);
  const name = airline ? airline.planner_name ?? airline.public_name ?? airline.game_name ?? "" : "";
  const type = typeName(rules, a.aircraft_type_id), config = configCode(configs, a.cabin_config_id);
  const flights = popupFlights(rules, fig.week);
  const game = gameFleetWords(fleetQ.data, a.id, a.registration);
  const open = () => { onClose(); navigate(itemRoute("tails", { tail: a.registration })); };

  return (
    <div className="mback" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }} data-aircraft-popup={a.registration}
      data-popup-ready={airlinesQ.data ? "yes" : "no"}>
      <div className="modal" role="dialog" aria-modal="true" aria-label={`Aircraft ${a.registration}`}>
        <div className="mhead">
          <div><AirlineMark color={airline?.livery_color} /><b>{a.registration}</b> <span className="dim">· {name} · {type}{config ? " · " + config : ""}</span></div>
          <button type="button" className="mx" aria-label="Close" onClick={onClose}>×</button>
        </div>
        <div className="mbody">
          <div className="mstats" data-figure="tails: pop-up">
            <div><span className="dim">Base</span><b>{a.base_code || "—"}</b></div>
            <div><span className="dim">Block a day</span><b>{fig.blockDay.toFixed(1)} h</b></div>
            <div><span className="dim">Legs a week</span><b>{fig.legsWk}</b></div>
            <div><span className="dim">Maintenance</span><b><MaintPill fig={fig} /></b></div>
            <div data-figure="tails: pop-up game"><span className="dim">In the game</span><b>{game ? (game.bad ? <span className="pill bad sm">{game.text}</span> : game.text)
              : <span className="dim">{fleetQ.data ? "not on the latest fleet pages" : fleetQ.error ? "couldn't read" : "…"}</span>}</b></div>
            <div data-figure="tails: pop-up age"><span className="dim">Replacement</span><b>{acquiredWords(rules, a)}</b></div>
          </div>
          <Issues issues={issues} />
          {flights.length ? (
            <div className="tblwrap">
              <table className="tbl">
                <tbody>
                  <tr><th>Flight</th><th>Route</th><th>Departs (local)</th><th>Arrives (local)</th><th>Block</th><th></th></tr>
                  {flights.map((f, i) => (
                    <tr key={i}><td><b>{f.no ?? ""}</b></td><td>{f.from}–{f.to}</td><td>{H(f.dep)}</td><td>{H(f.arr)}</td><td>{blockClock(f.block)}</td>
                      <td>{f.short ? <span className="pill bad sm">short turn</span> : null}</td></tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : <div className="dim">No flights yet.</div>}
        </div>
        <div className="mfoot">
          <button type="button" className="secondary" data-opentail={a.registration} onClick={open}>Open in Tails</button>
          <button type="button" className="secondary" onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  );
}
