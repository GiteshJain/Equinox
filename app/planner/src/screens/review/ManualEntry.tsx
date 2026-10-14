// Review's Manual entry (the old cashEntryHtml, the nightly log, manualLoadsHtml, parseLoadPaste and lfPastePreview, and
// their reviewClick handlers): only needed when a night's capture failed.
//   - Cash and fixed costs for today, one pair of boxes per airline, saved as one planner_save() action that writes the
//     cash_entries rows the old planner's adapter writes (model.ts's cashChanges);
//   - the nightly log: each reported day's cash and fixed costs per airline (cash_log());
//   - loads by hand for a day, typed (each airline's flights under 95%) or pasted from the game's load table and read,
//     with days marked complete: one planner_save() action writing the load_entries and load_days rows the old planner's
//     save_loads() wrote (model.ts's loadsChanges), from the days as they stand when it's saved (loads_by_day(), read
//     again then). Since the clean-up (build pull request 14); until then through save_loads(). A preview sends nothing.
import { useMemo, useState } from "react";
import { loadReport, type Rules } from "@rules";
import { queryClient, tableKey } from "../../data/query";
import type { Change, SaveResult } from "../../data/save";
import { AirlineMark } from "../../ui/AirlineMark";
import { addDays, niceDate } from "../../ui/dates";
import { showMessage } from "../../ui/messages";
import {
  boxValue, cashChanges, dayStatus, firstWord, loadsChanges, nightlyLog, parseLoadPaste, pasteSaves, pastePill, typedLoads, typedSave, underList, type CashLog,
  type DayPatch, type PastedLoad,
} from "./model";
import { readLoadsDays, useLoadsDay } from "./reads";
import type { ReviewAirline } from "./Review";

/** Saves loads by hand as one planner_save() action: each day's rows (loadsChanges) from the days as they stand now, read
 *  again from loads_by_day(). True when it was saved (or there was nothing to change). */
async function saveLoads(worldId: number, days: Record<string, DayPatch>, airlines: ReadonlyMap<string, number>,
  onSave: (changes: Change[]) => Promise<SaveResult | undefined>): Promise<boolean> {
  const dates = Object.keys(days).sort();
  if (!dates.length) return true;
  let now: Record<string, Awaited<ReturnType<typeof readLoadsDays>>[string]>;
  try {
    now = await readLoadsDays(worldId, dates[0] as string, dates[dates.length - 1] as string);
  } catch (e) {
    showMessage(e instanceof Error ? e.message : String(e));
    return false;
  }
  const at = new Date().toISOString();
  const changes = dates.flatMap((d) => loadsChanges(worldId, d, now[d] ?? null, days[d] as DayPatch, airlines, at));
  if (!changes.length) return true;
  const res = await onSave(changes);
  void queryClient.invalidateQueries({ queryKey: tableKey("load_entries") });
  void queryClient.invalidateQueries({ queryKey: tableKey("load_days") });
  return res?.status === "saved";
}

export function ManualEntry({ worldId, rules, log, airlines, busy, now, onSave }: {
  worldId: number | undefined;
  rules: Rules;
  log: CashLog;
  airlines: readonly ReviewAirline[];
  busy: boolean;
  now: Date;
  onSave: (changes: Change[]) => Promise<SaveResult | undefined>;
}) {
  const colorOf = (id: number) => airlines.find((a) => a.id === id)?.color ?? null;
  const rows = nightlyLog(log);
  return (
    <>
      <CashBoxes key={log.today + JSON.stringify(log.airlines.map((a) => a.today))} worldId={worldId} log={log} colorOf={colorOf} busy={busy} onSave={onSave} />
      <details className="gsub">
        <summary className="dim">Nightly log (cash / fixed costs, 7 days)</summary>
        {rows.length ? (
          <div className="tscroll">
            <table className="tbl flog" data-figure="review: nightly log">
              <tbody>
                <tr><th>Date</th>{log.airlines.map((a) => <th key={a.airline_id}><AirlineMark color={colorOf(a.airline_id)} />{firstWord(a.name)}</th>)}</tr>
                {rows.map((r) => (
                  <tr key={r.day}>
                    <td><b>{niceDate(r.day)}</b></td>
                    {r.cells.map((c, i) => <td key={i}>{c ? <>{c.cash}{c.fixed != null ? <> <span className="dim">/ {c.fixed}</span></> : null}</> : <span className="dim">—</span>}</td>)}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : <div className="dim">Nothing reported yet.</div>}
      </details>
      <LoadsByHand worldId={worldId} rules={rules} airlines={airlines} now={now} onSave={onSave} />
    </>
  );
}

/** Cash and fixed costs for today, millions AS$, one pair of boxes per airline. */
function CashBoxes({ worldId, log, colorOf, busy, onSave }: {
  worldId: number | undefined;
  log: CashLog;
  colorOf: (id: number) => string | null;
  busy: boolean;
  onSave: (changes: Change[]) => Promise<SaveResult | undefined>;
}) {
  const [typed, setTyped] = useState<Record<number, { cash: string; fixed: string }>>(() =>
    Object.fromEntries(log.airlines.map((a) => [a.airline_id, { cash: boxValue(a.today.shown_cash), fixed: boxValue(a.today.shown_fixed) }])));
  const set = (id: number, k: "cash" | "fixed", v: string) => setTyped((t) => ({ ...t, [id]: { ...(t[id] ?? { cash: "", fixed: "" }), [k]: v } }));
  const save = () => {
    if (worldId === undefined) return;
    const changes = cashChanges(worldId, log.airlines.map((a) => ({ airline_id: a.airline_id, today: a.today, cash: typed[a.airline_id]?.cash ?? "", fixed: typed[a.airline_id]?.fixed ?? "" })),
      new Date().toISOString());
    if (!changes.length) { showMessage("Nothing changed: the figures are the ones the planner already holds."); return; }
    void onSave(changes);
  };
  return (
    <div className="cashrow">
      <b>Cash and fixed costs today</b> <span className="dim">({niceDate(log.today)}, millions AS$ · cash, then fixed costs due in the next 7 days, from each airline's finance page)</span>
      <div className="cashin">
        {log.airlines.map((a) => (
          <div className="cashal" key={a.airline_id}>
            <AirlineMark color={colorOf(a.airline_id)} /><b>{firstWord(a.name)}</b>
            <label>cash<input type="number" step="0.01" data-cash={a.code ?? a.name} value={typed[a.airline_id]?.cash ?? ""} placeholder="0.00"
              onChange={(e) => set(a.airline_id, "cash", e.target.value)} /></label>
            <label>fixed, 7 days<input type="number" step="0.01" data-fixed={a.code ?? a.name} value={typed[a.airline_id]?.fixed ?? ""} placeholder="0.00"
              onChange={(e) => set(a.airline_id, "fixed", e.target.value)} /></label>
          </div>
        ))}
        <button type="button" className="secondary sm" id="cashsave" disabled={busy} onClick={save}>Save</button>
      </div>
    </div>
  );
}

/** Loads by hand for one day: each airline's flights under 95% typed, or the game's load table pasted and read. */
function LoadsByHand({ worldId, rules, airlines, now, onSave }: {
  worldId: number | undefined; rules: Rules; airlines: readonly ReviewAirline[]; now: Date; onSave: (changes: Change[]) => Promise<SaveResult | undefined>;
}) {
  const utcToday = now.toISOString().slice(0, 10);
  const [open, setOpen] = useState(false);
  const [date, setDate] = useState(utcToday);
  const [boxes, setBoxes] = useState<{ date: string; v: Record<string, string> }>({ date: "", v: {} });
  const [pasteOpen, setPasteOpen] = useState(false);
  const [pasteText, setPasteText] = useState("");
  const [parsed, setParsed] = useState<PastedLoad[] | null>(null);
  const [marks, setMarks] = useState<Record<string, boolean>>({});
  const [saving, setSaving] = useState(false);
  const dayQ = useLoadsDay(worldId, date);
  const day = dayQ.data ?? null;
  const nameOf = (id: number) => airlines.find((a) => a.id === id)?.name ?? "";
  const flightsOf = (d: string) => loadReport.flightsOn(rules, d, []).map((f) => ({ ...f, key: nameOf(f.airline_id) + "|" + f.no, airline: nameOf(f.airline_id) }));
  const flights = useMemo(() => flightsOf(date), [rules, date, airlines]); // eslint-disable-line react-hooks/exhaustive-deps
  const flying = airlines.filter((a) => flights.some((f) => f.airline === a.name));
  const codes = useMemo(() => new Map(airlines.filter((a) => a.code).map((a) => [a.code as string, a.name])), [airlines]);
  const ids = useMemo(() => new Map(airlines.map((a) => [a.name, a.id])), [airlines]);
  // the boxes start from the day as the planner holds it; what's typed is kept until the day moves
  const boxOf = (name: string) => (boxes.date === date && name in boxes.v ? boxes.v[name] ?? "" : underList(day, name));
  const setBox = (name: string, v: string) => setBoxes((b) => ({ date, v: { ...(b.date === date ? b.v : {}), [name]: v } }));
  const move = (n: number) => { setDate((d) => addDays(d, n)); setBoxes({ date: "", v: {} }); };

  async function saveTyped() {
    const valid = new Set(flights.map((f) => f.key));
    const { f, unknown } = typedLoads(flying.map((a) => ({ airline: a.name, text: boxOf(a.name) })), valid);
    if (worldId === undefined) return;
    setSaving(true);
    try {
      const ok = await saveLoads(worldId, typedSave(date, f, Date.now()), ids, onSave);
      if (unknown.length) showMessage("Saved, but these flight numbers don't operate that day in the planner, so they won't count: " + unknown.join(", "));
      if (ok) setBoxes({ date: "", v: {} });
    } finally {
      setSaving(false);
    }
  }
  async function savePaste() {
    if (!parsed?.length || worldId === undefined) return;
    const dates = [...new Set(parsed.map((x) => x.date))].sort();
    const marked = dates.filter((d) => marks[d] ?? d === utcToday);
    setSaving(true);
    try {
      if (await saveLoads(worldId, pasteSaves(parsed, marked, Date.now()), ids, onSave)) {
        setParsed(null);
        setPasteText("");
        setMarks({});
      }
    } finally {
      setSaving(false);
    }
  }
  const pasteDates = parsed ? [...new Set(parsed.map((x) => x.date))].sort() : [];
  const known = new Map(pasteDates.map((d) => [d, new Set(flightsOf(d).map((f) => f.key))]));

  return (
    <details className="gsub" open={open || !!pasteText || !!parsed} onToggle={(e) => setOpen((e.target as HTMLDetailsElement).open)} data-loads-by-hand={date}>
      <summary className="dim" data-det="lfman">Loads by hand</summary>
      <div className="toolbar">
        <button type="button" className="secondary" data-lfday="-1" onClick={() => move(-1)}>‹</button>
        <b style={{ minWidth: 120, textAlign: "center" }}>{niceDate(date)}</b>
        <button type="button" className="secondary" data-lfday="1" onClick={() => move(1)}>›</button>
        <span className="count">{dayQ.isFetching && !dayQ.data ? "" : dayStatus(day)}</span>
      </div>
      <div className="qman-grid">
        {flying.map((a) => (
          <label className="qone" key={a.id}><span><AirlineMark color={a.color} />{a.name}: flights under 95%, flight then load</span>
            <input data-q={`${a.code ?? a.name}|x`} value={boxOf(a.name)} placeholder="1001 93, 1005 88, 1051 61" onChange={(e) => setBox(a.name, e.target.value)} />
          </label>
        ))}
      </div>
      <details className="lfpaste" open={pasteOpen || !!pasteText} onToggle={(e) => setPasteOpen((e.target as HTMLDetailsElement).open)}>
        <summary><b>Paste from the game</b> <span className="dim">— copy the load monitoring table (−24h until now) and paste it here</span></summary>
        <textarea id="lfpaste-in" rows={5} placeholder={"KF 1008\tVT-AAE\tAMS\t28.09. 02:45 LT\tDEL\t…"} value={pasteText} onChange={(e) => setPasteText(e.target.value)} />
        <div className="toolbar">
          <button type="button" className="secondary" id="lfpaste-read" onClick={() => setParsed(parseLoadPaste(pasteText, codes, utcToday))}>Read paste</button>
          {parsed ? <button type="button" className="link" id="lfpaste-clear" onClick={() => { setParsed(null); setPasteText(""); setMarks({}); }}>clear</button> : null}
        </div>
      </details>
      {parsed ? (
        <div className="mback" data-paste-preview onClick={(e) => { if (e.target === e.currentTarget) setParsed(null); }}>
          <div className="modal" role="dialog" aria-modal="true" aria-label="Load report">
            <div className="mhead"><div><b>Load report</b> <span className="dim">· check the flights before saving</span></div>
              <button type="button" className="mx" aria-label="Close" onClick={() => setParsed(null)}>×</button></div>
            <div className="mbody">
              {!parsed.length ? <div className="dim">Nothing recognised. Paste the whole table, including the flight codes (e.g. KF 1008).</div> : (
                <>
                  <div className="tscroll">
                    <table className="tbl" data-figure="review: paste preview">
                      <tbody>
                        <tr><th>Flight</th><th>Route</th><th>Departs (local)</th><th>Load</th><th></th></tr>
                        {parsed.map((x, i) => (
                          <tr key={i}>
                            <td><b>{firstWord(x.airline)} {x.no}</b> <span className="dim">{x.tail}</span></td>
                            <td>{x.from}–{x.to}</td>
                            <td>{niceDate(x.date)} {x.dep}</td>
                            <td><span className={"pill " + pastePill(x.pct)}>{x.pct}%</span> <span className="dim">{x.pax}/{x.seats}</span></td>
                            <td>{known.get(x.date)?.has(x.key) ? "" : <span className="pill mute" title="no planner flight with this number departs that day">not in planner</span>}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  <div className="qfoot">
                    {pasteDates.map((d) => (
                      <label className="check" key={d}><input type="checkbox" data-lfmark={d} checked={marks[d] ?? d === utcToday}
                        onChange={(e) => setMarks((m) => ({ ...m, [d]: e.target.checked }))} /> mark {niceDate(d)} complete</label>
                    ))}{" "}
                    <button type="button" className="primary" id="lfpaste-save" disabled={saving} onClick={() => void savePaste()}>Save {parsed.length} load{parsed.length === 1 ? "" : "s"}</button>
                    <span className="note">Loads are combined economy + business + first, without cargo. Tick a day only once every airline's flights for it are in; unlisted flights on a complete day count as 95%+.</span>
                  </div>
                </>
              )}
            </div>
            <div className="mfoot"><span className="dim">Close discards this paste; the text stays in the box.</span>
              <button type="button" className="secondary" onClick={() => setParsed(null)}>Close</button></div>
          </div>
        </div>
      ) : null}
      <div className="qfoot">
        <button type="button" className="primary" id="lfsave" disabled={saving || (!dayQ.data && dayQ.isFetching)} onClick={() => void saveTyped()}>
          {day?.done ? "Update report" : "Save report for " + niceDate(date)}
        </button>
        <span className="note">Type the flight number, then its load, pairs separated by commas (an airline prefix like AW is fine).</span>
      </div>
    </details>
  );
}
