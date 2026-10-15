// The aircraft pop-up (the old planner's tailModal), opened from Home's needs attention (an aircraft's maintenance, turns
// and positions), the Check screen and, since build pull request 12, a frequency's aircraft on Routes: the aircraft's base, block hours a day, legs a week, maintenance and
// its one-week check; every issue, or "schedule clean"; its flights, one line per number; Mark checked and Open in Tails.
// The check line and Mark checked show only while the checks are on for its airline (aircraft_check_after_days above 0,
// the library's checks.on; manual §1 has none since 15 Oct). Every figure is the planning library's on the start's rules.
import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router";
import { checks, tails, type Rules } from "@rules";
import { useNow } from "../../data/clock";
import { useOurAirlines, useWorld } from "../../data/reads";
import { saver } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { niceDate, todayAt } from "../../ui/dates";
import { itemRoute } from "../screens";
import { Issues, MaintPill } from "./AircraftPage";
import { blockClock, configCode, figuresOf, H, markCheckedChange, popupFlights, rulesLegs, typeName } from "./model";
import { useConfigs, useLaunches, useTailsAircraft } from "./reads";

export function AircraftPopup({ registration, rules, onClose }: { registration: string; rules: Rules; onClose: () => void }) {
  const navigate = useNavigate();
  const now = useNow();
  const today = todayAt(now);
  const w = useWorld().data?.id;
  const airlinesQ = useOurAirlines(w);
  const aircraftQ = useTailsAircraft(w);
  const configsQ = useConfigs(w);
  const launchesQ = useLaunches(w);
  const [busy, setBusy] = useState(false);
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
  const issues = useMemo(() => (a && fig?.week ? tails.issues(rules, a.id, rulesLegs(rules), fig.week, fig.maint) : []), [rules, a, fig]);
  const check = useMemo(() => (aircraftQ.data && launchesQ.data && a
    ? checks.oneWeek(rules, { aircraft: aircraftQ.data, rotations: launchesQ.data }, today).find((c) => c.aircraft_id === a.id) ?? null : null),
  [rules, aircraftQ.data, launchesQ.data, a, today]);
  if (!aircraftQ.data || !configsQ.data) return null;
  if (!a || !fig) return null;
  const airline = (airlinesQ.data ?? []).find((x) => x.id === a.airline_id);
  const name = airline ? airline.planner_name ?? airline.public_name ?? airline.game_name ?? "" : "";
  const type = typeName(rules, a.aircraft_type_id), config = configCode(configs, a.cabin_config_id);
  const flights = popupFlights(rules, fig.week);
  const mark = async () => {
    setBusy(true);
    try { await saver.save([markCheckedChange(a, today)]); } finally { setBusy(false); }
  };
  const open = () => { onClose(); navigate(itemRoute("tails", { tail: a.registration })); };

  return (
    <div className="mback" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }} data-aircraft-popup={a.registration}
      data-popup-ready={launchesQ.data && airlinesQ.data ? "yes" : "no"}>
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
            {checks.on(rules, a.airline_id) ? <div><span className="dim">Check</span><b>{check ? (check.status === "done" ? <span className="pill ok">checked</span>
              : <span className={"pill " + (check.status === "due" ? "warn" : "mute")}>due {niceDate(check.due)}</span>) : <span className="dim">—</span>}</b></div> : null}
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
          {check && check.status !== "done" ? <button type="button" className="primary" data-tmcheck={a.registration} disabled={busy} onClick={() => void mark()}>Mark checked</button> : null}
          <button type="button" className="secondary" data-opentail={a.registration} onClick={open}>Open in Tails</button>
          <button type="button" className="secondary" onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  );
}
