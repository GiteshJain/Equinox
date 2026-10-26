// Today → Game check (moved from Check on 20 Oct; the old renderGameCheck, gcDetail and gcModal): "Check against the game" reads each airline's public
// schedule (/api/game-schedule, with its game link) and compares it with the planner's flights (the library's game part,
// the same code Tails' check before filing uses). Each airline's line says how many flights are in each and the
// differences; its pop-up lists them, with "Use the game's times" on each one that's only a time or a day change, "Fix all
// from the game", and the game's flights the planner doesn't have, each with an aircraft and "Add to planner".
import { useEffect, useRef, useState } from "react";
import type { GameComparison, ImportCandidate } from "@rules";
import { AirlineMark } from "../../ui/AirlineMark";
import type { OurAirline } from "../../data/airlines";
import { gameSummary } from "./game";

export interface GameLine {
  airline: OurAirline;
  error?: string;
  cmp?: GameComparison;
  cands?: ImportCandidate[];
}

export function GameLines({ lines, busy, onFixAll, onOpen }: {
  lines: readonly GameLine[];
  busy: boolean;
  onFixAll: (airlineId: number) => void;
  onOpen: (airlineId: number) => void;
}) {
  return (
    <>
      {lines.map((x) => {
        if (x.error != null) {
          return (
            <div className="gc" key={x.airline.id} data-gc={x.airline.code ?? ""}>
              <div className="gch"><AirlineMark color={x.airline.color} /><b>{x.airline.name}</b><span className="pill bad">couldn't check</span><span className="dim">{x.error}</span></div>
            </div>
          );
        }
        if (!x.cmp) return null;
        const s = gameSummary(x.cmp, x.cands ?? []);
        return (
          <div className="gc" key={x.airline.id} data-gc={x.airline.code ?? ""}>
            <div className="gch">
              <AirlineMark color={x.airline.color} /><b>{x.airline.name}</b><span className="dim">{s.counts}</span>
              <span className={s.pill.cls === "ok" ? "dim" : "pill " + s.pill.cls}>{s.pill.text}</span>
              {s.fixAll ? <button type="button" className="secondary sm" data-gcfixall={x.airline.code ?? ""} disabled={busy} onClick={() => onFixAll(x.airline.id)}
                title="Set the planner to the game's times for every difference that is only a time or day change">{s.fixAll}</button> : null}
            </div>
            {s.review ? <div className="gcopen"><button type="button" className="primary sm" data-gcopen={x.airline.code ?? ""} onClick={() => onOpen(x.airline.id)}>{s.review}</button></div> : null}
          </div>
        );
      })}
    </>
  );
}

/** The aircraft an added flight goes on: one of the airline's tails, or a registration typed for a new one. */
export type TailChoice = { registration: string; isNew: boolean; acquired?: "new" | "used" };

export function GameModal({ line, tails, busy, onFix, onFixAll, onAdd, onClose }: {
  line: GameLine;
  tails: readonly string[];
  busy: boolean;
  onFix: (issueIndex: number) => void;
  onFixAll: () => void;
  onAdd: (candIndex: number, tail: TailChoice) => void;
  onClose: () => void;
}) {
  const close = useRef(onClose);
  useEffect(() => { close.current = onClose; });
  useEffect(() => {
    document.body.classList.add("mopen");
    const esc = (e: KeyboardEvent) => { if (e.key === "Escape") close.current(); };
    document.addEventListener("keydown", esc);
    return () => { document.body.classList.remove("mopen"); document.removeEventListener("keydown", esc); };
  }, []);
  const [picked, setPicked] = useState<Record<string, string>>({});
  const [typed, setTyped] = useState<Record<string, string>>({});
  // a new tail says how it came (since 26 Oct: an aircraft has no default)
  const [came, setCame] = useState<Record<string, "" | "new" | "used">>({});
  const c = line.cmp;
  if (!c) return null;
  const cands = line.cands ?? [];
  const n = c.issues.length, nf = c.issues.filter((i) => i.fix).length;
  return (
    <div className="mback" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }} data-gc-modal={line.airline.code ?? ""}>
      <div className="modal" role="dialog" aria-modal="true" aria-label={`Game check: ${line.airline.name}`}>
        <div className="mhead">
          <div><AirlineMark color={line.airline.color} /><b>{line.airline.name}</b> <span className="dim">· {c.in_game} flights in the game · {c.in_planner} in the planner</span></div>
          <button type="button" className="mx" aria-label="Close" onClick={onClose}>×</button>
        </div>
        <div className="mbody">
          {n ? (
            <div className="tblwrap">
              <table className="tbl gct" data-figure="today: game differences">
                <tbody>
                  <tr><th style={{ width: 70 }}>Flight</th><th style={{ width: 210 }}>What</th><th>In the game</th><th>In the planner</th><th style={{ width: 150 }}></th></tr>
                  {c.issues.map((i, k) => (
                    <tr key={k}>
                      <td><b>{i.no}</b></td>
                      <td><span className={"pill " + (i.kind === "diff" ? "warn" : "bad")}>{i.text}</span></td>
                      <td>{i.g || <span className="dim">—</span>}</td>
                      <td>{i.p || <span className="dim">—</span>}</td>
                      <td style={{ textAlign: "right" }}>
                        {i.fix ? <button type="button" className="link" data-gcfix={`${line.airline.code ?? ""}|${k}`} disabled={busy} onClick={() => onFix(k)}>Use the game's times</button>
                          : i.kind === "diff" ? <span className="dim">fix by hand</span> : null}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : null}
          {cands.length ? (
            <div className="imp" data-figure="today: game flights to add">
              <b>In the game, not in the planner — add them:</b>
              {cands.map((x, i) => {
                const k = x.a.no;
                const choice = picked[k] ?? tails[0] ?? "__new";
                return (
                  <div className="impr" key={`${x.a.no}|${i}`}>
                    <span><b>{x.a.no}</b> {x.a.from}–{x.a.to} {x.a.dep}{x.b ? <> · <b>{x.b.no}</b> {x.b.from}–{x.b.to} {x.b.dep}</> : null} <span className="dim">{x.a.days === "1234567" ? "daily" : x.a.days}</span></span>
                    <select data-impt={`${line.airline.code ?? ""}|${i}`} value={choice} onChange={(e) => { const v = e.currentTarget.value; setPicked((p) => ({ ...p, [k]: v })); }}>
                      {tails.map((t) => <option key={t} value={t}>{t}</option>)}
                      <option value="__new">new tail…</option>
                    </select>
                    {choice === "__new" ? <input data-impnew={`${line.airline.code ?? ""}|${i}`} placeholder="Registration of the new aircraft" value={typed[k] ?? ""}
                      onChange={(e) => { const v = e.currentTarget.value; setTyped((p) => ({ ...p, [k]: v })); }} /> : null}
                    {choice === "__new" ? <select data-impacq={`${line.airline.code ?? ""}|${i}`} value={came[k] ?? ""} title="how it came: new from the factory or used from the market"
                      onChange={(e) => { const v = e.currentTarget.value as "" | "new" | "used"; setCame((p) => ({ ...p, [k]: v })); }}>
                      <option value="">New or used</option><option value="new">new</option><option value="used">used</option>
                    </select> : null}
                    <button type="button" className="secondary sm" data-imp={`${line.airline.code ?? ""}|${i}`} disabled={busy || (choice === "__new" && (!(typed[k] ?? "").trim() || !came[k]))}
                      onClick={() => onAdd(i, choice === "__new" ? { registration: (typed[k] ?? "").trim().toUpperCase(), isNew: true, acquired: came[k] || undefined } : { registration: choice, isNew: false })}>Add to planner</button>
                  </div>
                );
              })}
            </div>
          ) : null}
          {!n && !cands.length ? <div className="empty">Everything matches the game now.</div> : null}
        </div>
        <div className="mfoot">
          {nf ? <button type="button" className="primary" data-gcfixall={line.airline.code ?? ""} disabled={busy} onClick={onFixAll}>Fix {nf === n ? "all" : nf} from the game</button> : null}
          <button type="button" className="secondary" onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  );
}
