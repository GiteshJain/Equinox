// An aircraft's page, as the old planner's renderTailDetail draws it: its header (type, cabin, legs a week, block hours a
// day, gap target and minimum turn, gaps at the target, maintenance), the fields that change it, each saving on its own
// as one action (registration, type, base, cabin, the maintenance gap, notes), Delete aircraft…, every issue (the old
// tailIssues, which the spec asks for here too), the week strip in the base's local time and its legs by flight number
// with the ground time to the next and the turn or gap. Every figure is the planning library's (model.ts words them).
import { useState, type FocusEvent, type KeyboardEvent } from "react";
import type { Rules } from "@rules";
import { ConfirmPanel } from "../../ui/Confirm";
import {
  daysText, gapWords, H, headerWords, hhmm, issueWords, legGroups, maintPill, shownPill, tailNotes, weekStrip, DAYS, type ConfigRow, type ShownIssue, type ShownMaint,
  type TailAircraft, type TailFigures, type TailField,
} from "./model";

/** The maintenance pill: the planner's estimate (≈), or, given a shown figure (Tails' board, since 23 Oct), that one:
 *  the game's for an aircraft on the latest fleet pages. */
export function MaintPill({ fig, shown }: { fig: TailFigures; shown?: ShownMaint | null }) {
  const p = shown !== undefined ? shownPill(shown) : maintPill(fig.maint);
  if (!p) return <span className="dim">—</span>;
  return <span className={`pill ${p.cls}`} title={p.title} data-maint={shown?.from ?? "estimate"}>{p.text}</span>;
}

export function Issues({ issues }: { issues: readonly ShownIssue[] }) {
  return (
    <div className="ckb" data-figure="tails: issues">
      {issues.length ? issues.map((i, k) => <span key={k} className="pill bad" data-issue={i.kind}>{issueWords(i)}</span>)
        : <span className="pill ok">schedule clean — no short turns, maintenance and night bans fine</span>}
    </div>
  );
}

/** A box's choices, as the old planner's opt(): "—" first, then the list (a value outside it shows as "—", as there). */
function Opts({ list, empty }: { list: readonly string[]; empty: string }) {
  return (
    <>
      <option value="">{empty}</option>
      {list.map((v) => <option key={v} value={v}>{v}</option>)}
    </>
  );
}

export interface AircraftPageProps {
  rules: Rules;
  a: TailAircraft;
  configs: ReadonlyMap<number, ConfigRow>;
  fig: TailFigures;
  /** The maintenance shown in the header: the game's for an aircraft on the latest fleet pages, else the estimate. */
  maint: ShownMaint | null;
  issues: readonly ShownIssue[];
  types: readonly string[];
  bases: readonly string[];
  configsFor: (type: string) => string[];
  /** How many round trips it flies (Delete aircraft… names them). */
  roundTrips: number;
  busy: boolean;
  onBack: () => void;
  onEdit: (field: TailField, value: string) => void;
  onDelete: () => void;
}

export function AircraftPage(p: AircraftPageProps) {
  const { rules, a, fig } = p;
  const [asking, setAsking] = useState(false);
  const type = p.rules.types.get(a.aircraft_type_id ?? -1)?.name ?? "";
  const config = a.cabin_config_id == null ? "" : p.configs.get(a.cabin_config_id)?.code ?? "";
  const strip = weekStrip(rules, a, fig.week);
  const groups = legGroups(rules, a, fig.week);
  const text = (k: TailField, label: string, value: string, wide = false) => {
    const done = (e: FocusEvent<HTMLInputElement>) => { if (e.currentTarget.value !== value) p.onEdit(k, e.currentTarget.value); };
    const enter = (e: KeyboardEvent<HTMLInputElement>) => { if (e.key === "Enter") e.currentTarget.blur(); };
    return (
      <label className={wide ? "wide" : undefined}>{label}
        <input key={value} data-tk={k} defaultValue={value} spellCheck={k === "id" ? false : undefined} onBlur={done} onKeyDown={enter} disabled={p.busy} />
      </label>
    );
  };
  const select = (k: TailField, label: string, value: string, list: readonly string[]) => (
    <label>{label}
      <select key={value} data-tk={k} defaultValue={list.includes(value) ? value : ""} onChange={(e) => p.onEdit(k, e.currentTarget.value)} disabled={p.busy}>
        <Opts list={list} empty="—" />
      </select>
    </label>
  );
  return (
    <div data-tail-page={a.registration}>
      <div className="dhead">
        <button type="button" className="back" id="back-tail" onClick={p.onBack}>‹ Tails</button>
        <h2>{a.registration}</h2>
        <div className="dsub" data-figure="tails: aircraft">{headerWords(rules, a, p.configs, fig)} <MaintPill fig={fig} shown={p.maint} /></div>
        <div className="fg">
          {text("id", "Registration", a.registration)}
          {select("type", "Type", type, p.types)}
          {select("base", "Base", a.base_code ?? "", p.bases)}
          {select("config", "Config", config, p.configsFor(type))}
          {text("maint", "Maintenance gap — where / when", a.maintenance_note ?? "", true)}
          {text("notes", "Notes", tailNotes(a), true)}
          <button type="button" className="secondary danger" data-tdel={a.registration} disabled={p.busy} onClick={() => setAsking(true)}>Delete aircraft…</button>
        </div>
        {asking ? (
          <ConfirmPanel question={p.roundTrips ? `Delete ${a.registration} and its ${p.roundTrips} round trip${p.roundTrips === 1 ? "" : "s"}?` : `Delete ${a.registration}?`}
            yes="Delete" busy={p.busy} onNo={() => setAsking(false)} onYes={() => { setAsking(false); p.onDelete(); }}>
            <div className="dim">It is retired, never deleted: its history stays.</div>
          </ConfirmPanel>
        ) : null}
      </div>
      <Issues issues={p.issues} />
      <div className="week" data-figure="tails: week">
        <div className="wk-axis">{[0, 6, 12, 18].map((x) => <span key={x} style={{ left: `${x / 24 * 100}%` }}>{String(x).padStart(2, "0")}:00</span>)}</div>
        {DAYS.map((d, i) => (
          <div className="wk-row" key={d}>
            <span className="wk-day">{d}</span>
            <div className="wk-bar">
              {strip.bars.filter((b) => b.day === i).map((b, k) => (
                <span key={k} className={"leg" + (b.bad ? " bad" : "")} style={{ left: `${b.left}%`, width: `${b.width}%` }} title={b.title}>{b.text}</span>
              ))}
            </div>
          </div>
        ))}
      </div>
      <div className="note">Bars in {strip.base || "base"} local time. Red = short turn or aircraft not where the next leg starts.</div>
      <div className="tblwrap">
        <table className="tbl" data-figure="tails: legs">
          <tbody>
            <tr><th>Flight</th><th>Leg</th><th>Days</th><th>Dep</th><th>Arr</th><th>Duration</th><th>Ground to next</th><th></th></tr>
            {groups.map((g, i) => (
              <tr key={i} data-leg-group>
                <td><b>{g.no ?? "—"}</b></td>
                <td>{g.from}–{g.to}</td>
                <td>{daysText(g.days)}</td>
                <td>{H(g.dep)}</td>
                <td>{H(g.arr)}{g.arrNextDay ? " +1" : ""}</td>
                <td>{hhmm(g.block)}</td>
                <td>{gapWords(g.gaps)}</td>
                <td>{g.pill ? <span className={`pill ${g.pill.cls}`}>{g.pill.text}</span> : null}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {!fig.week?.legs.length ? <div className="empty">No flights yet. Assign this tail on a route.</div> : null}
    </div>
  );
}
