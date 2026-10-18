// Filing an arrived aircraft into the planner from its plan card (the old checkBeforeFile, fileCheckModal, fileFromCheck,
// filePlan and importFlight). The aircraft is already scheduled in the game, so the card is checked first: the airline's
// public schedule is read from the game (/api/game-schedule, with the airline's game link) and each card leg compared
// with the game's flight of the same number. When every leg is the same it files at once; otherwise the check is shown,
// and Gitesh files with the plan card's times or the game's (the card then takes the game's times too). Filing is one
// planner_save() call (model.ts's filingChanges), with every row read fresh first, so the bases are current.
import { useState } from "react";
import type { Rules } from "@rules";
import type { Change } from "../../data/save";
import { AirlineMark } from "../../ui/AirlineMark";
import { readAirports } from "../routes/reads";
import {
  cardLegs, checkSummary, compareCard, daysSuffix, filingCabin, filingChanges, gameLink, withAirports, type CardCheck, type ConfigRow, type TailAircraft, type TailAirline,
} from "./model";
import {
  cabinLogged, readAircraft, readAirlineRoutes, readCard, readCardLegs, readGameSchedule, readMarkets, readProfiles,
} from "./reads";

export interface FileState {
  reg: string;
  airline: TailAirline | undefined;
  running: boolean;
  check?: CardCheck;
  /** What filing needs, read when the check ran. */
  ctx?: { rules: Rules; aircraftId: number; cardId: number };
}

export function FileCheckModal({ state, busy, onFile, onClose }: { state: FileState; busy: boolean; onFile: (useGame: boolean) => void; onClose: () => void }) {
  const title = (
    <div><AirlineMark color={state.airline?.color} /><b>Filing {state.reg}</b> <span className="dim">· checked against the game</span></div>
  );
  const shell = (body: React.ReactNode, foot: React.ReactNode) => (
    <div className="mback" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }} data-file-check={state.reg} data-file-ready={state.running ? "no" : "yes"}>
      <div className="modal" role="dialog" aria-modal="true" aria-label={`Filing ${state.reg}`}>
        <div className="mhead">{title}<button type="button" className="mx" aria-label="Close" onClick={onClose}>×</button></div>
        <div className="mbody">{body}</div>
        <div className="mfoot">{foot}<button type="button" className="secondary" onClick={onClose}>Close</button></div>
      </div>
    </div>
  );
  if (state.running || !state.check) return shell(<div className="dim">Reading {state.airline?.name || "the airline"}'s schedule from the game…</div>, null);
  const c = state.check;
  return shell(
    <>
      {c.err ? <><p><span className="pill bad">Couldn't read the game: {c.err}</span></p><p className="dim">You can still file with the plan card's times and compare later in Check → Game check.</p></> : null}
      {!c.err ? <p data-file-summary>{checkSummary(c)}</p> : null}
      <div className="tblwrap">
        <table className="tbl" data-figure="tails: file check">
          <tbody>
            <tr><th>Flight</th><th>Route</th><th>Plan card</th><th>Game</th><th></th></tr>
            {c.rows.map((r, i) => (
              <tr key={i} data-check-row>
                <td><b>{r.L.no}</b></td>
                <td>{r.L.from}–{r.L.to}</td>
                <td>{r.L.dep}–{r.L.arr}{daysSuffix(r.L.days)}</td>
                <td>{r.g ? `${r.g.dep}–${r.g.arr || "?"}${daysSuffix(r.g.days)}` : <span className="dim">—</span>}</td>
                <td>{!r.g ? <span className={"pill " + (c.err ? "mute" : "warn")}>{c.err ? "unchecked" : "not in the game"}</span>
                  : r.same ? <span className="pill ok">same</span> : <span className="pill warn">different</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>,
    <>
      {c.found ? <button type="button" className="primary" data-filegame={state.reg} disabled={busy} onClick={() => onFile(true)}>File with the game's times</button> : null}
      <button type="button" className="secondary" data-filecard={state.reg} disabled={busy} onClick={() => onFile(false)}>File with the plan card's times</button>
    </>,
  );
}

/** The check and the filing, with the screen's start rules and what it has read. save: the screen's one planner_save()
 *  call (the rules are read again after it). */
export function useFiling(opts: {
  worldId: number | undefined;
  rules: Rules | undefined;
  airlines: readonly TailAirline[];
  host: string | null | undefined;
  configs: ReadonlyMap<number, ConfigRow>;
  today: string;
  save: (changes: Change[]) => Promise<{ status: string }>;
  onFiled: (reg: string, words: string) => void;
}) {
  const [state, setState] = useState<FileState | null>(null);
  const [filing, setFiling] = useState(false);

  async function prepare(a: TailAircraft) {
    const card = await readCard(a.id);
    const legs = card ? await readCardLegs(card.id) : [];
    const codes = [...new Set(legs.flatMap((l) => [l.origin_code, l.dest_code]))];
    const airports = codes.length && opts.worldId !== undefined ? await readAirports(opts.worldId, codes) : [];
    return { card, legs, airports, rules: withAirports(opts.rules as Rules, airports) };
  }

  /** File into planner: check the card against the game, then file at once if every leg is the same. */
  async function start(a: TailAircraft) {
    if (!opts.rules || opts.worldId === undefined) return;
    const airline = opts.airlines.find((x) => x.id === a.airline_id);
    setState({ reg: a.registration, airline, running: true });
    const p = await prepare(a);
    if (!p.card) { setState(null); return; }
    const link = gameLink(opts.host, airline?.game_id);
    const answer = link ? await readGameSchedule(link) : { error: "no game link saved for " + (airline?.name ?? "the airline") };
    const check = compareCard(cardLegs(p.rules, p.legs), "flights" in answer ? answer.flights : null, "error" in answer ? answer.error : "");
    const next: FileState = { reg: a.registration, airline, running: false, check, ctx: { rules: p.rules, aircraftId: a.id, cardId: p.card.id } };
    if (check.allSame) {
      setState(null);
      await file(next, false, `${a.registration} filed: the plan card matches the game exactly.`);
      return;
    }
    setState(next);
  }

  /** Files from the check: with the game's times (the card takes them too) or the plan card's. */
  async function file(st: FileState, useGame: boolean, words?: string) {
    if (!st.check || !st.ctx || opts.worldId === undefined) return;
    setFiling(true);
    try {
      const w = opts.worldId;
      const a = await readAircraft(st.ctx.aircraftId);
      const card = a ? await readCard(a.id) : null;
      if (!a || !card) return;
      // the card's legs again, fresh (their updated_at is the base if the card takes the game's times), in the same order
      const fresh = await readCardLegs(card.id);
      const legs = cardLegs(st.ctx.rules, fresh);
      const game = useGame ? legs.map((L) => st.check?.rows.find((r) => r.L.row.id === L.row.id)?.g ?? null) : null;
      const [routes, markets, profiles, logged] = await Promise.all([
        readAirlineRoutes(a.airline_id), readMarkets(w), readProfiles(w), cabinLogged(w, a.registration),
      ]);
      // its cabin: the plan card's, else the order's, else none (never the type's default: 18 Oct)
      const cabin = filingCabin(card, a, opts.configs);
      const codes = [...new Set(fresh.flatMap((l) => [l.origin_code, l.dest_code]))];
      const airports = codes.length ? await readAirports(w, codes) : [];
      const changes = filingChanges({
        worldId: w, today: opts.today, nowMs: Date.now(), rules: st.ctx.rules, aircraft: a, card, legs, game, cabin, cabinLogged: logged,
        bases: (opts.rules?.bases ?? []).filter((b) => b.airline_id === a.airline_id).map((b) => b.airport_code), routes,
        markets: new Map(markets.map((m) => [m.id, m])), profiles, airports: new Map(airports.map((x) => [x.code, x])),
      });
      const res = await opts.save(changes);
      if (res.status === "preview") setState(null);
      if (res.status === "saved") {
        setState(null);
        const filed = words ?? (useGame ? `${a.registration} filed with the game's times.` : `${a.registration} filed with the plan card's times.`);
        const fit = cabin ? ` Cabin ${cabin.code}${logged ? "" : `, first fit logged at ${Math.round(Number(cabin.cost ?? 0)).toLocaleString("en-US")}`}.`
          : ` No cabin: neither its plan card nor its order names one, so none was set or logged. Set it on Tails (the aircraft's config) once it's chosen.`;
        opts.onFiled(a.registration, filed + fit);
      }
    } finally {
      setFiling(false);
    }
  }

  return { state, filing, start, file: (useGame: boolean) => (state ? file(state, useGame) : Promise.resolve()), close: () => setState(null) };
}
