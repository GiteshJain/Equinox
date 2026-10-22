// Systems (spec docs/specs/2026-10-20-today-performance-systems.md): the plumbing, rarely opened. At the top the Systems
// board (decision #23, SystemsBoard.tsx), always open: one line each, green, amber or red, with when, for each airline's
// evening capture (with #21's verdict), the daily snapshot, the nightly backup, the monthly archive, the clean-ups, the
// world scan, the planner's own build and the usage the database can measure (system_status()). Then the boards that fold
// (all folded on arrival, Collapse all and Expand all), each moved here on 20 Oct as it was:
//   - Capture: what the capture collected for each airline and when (capture_status()), with Reload, and the backup's
//     line (Check's);
//   - Manual entry (ManualEntry.tsx): cash and fixed costs, the nightly log, loads by hand (Review's);
//   - Cabin charges (since 22 Oct, spec docs/specs/2026-10-21-tidy-ups.md §3): each first cabin fit logged against the
//     game's charge (cabin_charges()), the problems listed with Use the game's amount on a differing one; open on arrival
//     when Today's item sent you (#cabin-charges).
// The Cabins board (each aircraft's cabin against its markets, with Refitted to, Keep as is and Show again; Check's) went
// on 21 Oct (spec docs/specs/2026-10-21-cabins-new-rule.md §1): the cabin is chosen with each order, and the plan card
// suggests it (Tails). The Aircraft checks board (the one-week checks, with Mark checked and the aircraft pop-up it
// opened) went on 22 Oct (spec docs/specs/2026-10-22-remove-aircraft-checks.md; manual §1 has none since 15 Oct).
// Since 22 Oct (spec docs/specs/2026-10-22-planner-look-systems.md) short and answer-first, as the new Today: the board's
// answer is the title ("All systems good", or how many need a look) with "checked at" as a small pill beside it; the
// board's lines as tiles, worst first, and each airline's capture as one row of a table (SystemsBoard.tsx); the three
// boards that fold as a short list of large rows, each with a one-line note and its count or state, opening right below.
// Address: /planner/systems. Every action is one planner_save() call.
import { useMemo, useState, type ReactNode } from "react";
import { useLocation } from "react-router";
import { ourAirlines, type OurAirline } from "../../data/airlines";
import { buildStamp } from "../../data/build";
import { useNow } from "../../data/clock";
import { queryClient } from "../../data/query";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import type { Change } from "../../data/save";
import { saver } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { niceDate } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { FoldBoard, FoldTools } from "../../ui/FoldBoard";
import { refreshFigures } from "../performance/reads";
import { ManualEntry } from "./ManualEntry";
import {
  BOARDS, CABIN_STATE_WORDS, CAPTURE_KINDS, backupWords, cabinCountsWords, cabinGameWords, cabinLoggedWords, captureCell, captureStatus,
  gameAmountChange, signedAsd, type BoardKey, type CabinCharges, type CabinProblem,
} from "./model";
import { useBackupLine, useCabinCharges, useCapture, useCashLog, useSystemStatus } from "./reads";
import { SystemsBoard } from "./SystemsBoard";
import { boardSummary, boardTitle, systemLines } from "./systems";

/** Each row's one-line note; the board's full words (NOTES) open with it. */
const SHORT: Record<BoardKey, string> = {
  "Capture": "What the capture collected from the game, per airline",
  "Cabin charges": "Each first cabin fit logged, against the game's charge",
  "Manual entry": "Only needed if a night's capture failed",
};
const NOTES: Record<BoardKey, string> = {
  "Capture": "what the one-click capture collected from the game, per airline · times in UTC · cash and fixed costs go straight into Performance",
  "Cabin charges": "each first cabin fit filing logged, against the game's \"Installation of cabin interior\" line on the bank statement",
  "Manual entry": "only needed if a night's capture failed · cash, fixed costs and loads normally come from the capture",
};
const FIGURE: Record<BoardKey, string> = {
  "Capture": "systems: capture", "Cabin charges": "systems: cabin charges", "Manual entry": "systems: manual entry",
};
/** The board Today's cabin charges item opens (/planner/systems#cabin-charges). */
const CABIN_HASH = "#cabin-charges";

const firstError = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

export function Systems() {
  const loc = useLocation();
  const now = useNow();
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const rulesQ = useRules(w);
  const systemQ = useSystemStatus(w);
  const captureQ = useCapture(w);
  const backupsQ = useBackupLine();
  const logQ = useCashLog(w);
  const cabinsQ = useCabinCharges(w !== undefined);
  // every board folded on arrival, but Cabin charges open when Today's item sent you here
  const [folded, setFolded] = useState<ReadonlySet<BoardKey>>(() => new Set(BOARDS.filter((k) => !(k === "Cabin charges" && loc.hash === CABIN_HASH))));
  const [busy, setBusy] = useState(false);

  const rules = rulesQ.data?.rules;
  const airlines: OurAirline[] = useMemo(() => ourAirlines(airlinesQ.data), [airlinesQ.data]);
  const airline = (id: number) => airlines.find((a) => a.id === id);

  // ---------- saving: one action each; the figures that build on cash are read again after it
  async function save(changes: Change[]) {
    if (!changes.length) return;
    setBusy(true);
    try {
      const res = await saver.save(changes);
      if (res.status === "saved") {
        refreshFigures();
        if (changes.some((c) => c.table === "spending_log")) void queryClient.invalidateQueries({ queryKey: ["figures", "cabin_charges"] });
      }
      return res;
    } finally {
      setBusy(false);
    }
  }

  const scanEvery = rules ? Number(rules.input.settings.scan_every_days ?? NaN) : NaN;
  const sysLines = useMemo(() => (systemQ.data ? systemLines(systemQ.data, buildStamp(), now, Number.isFinite(scanEvery) ? scanEvery : null) : null),
    [systemQ.data, now, scanEvery]);
  const ready = !!(sysLines && rules && airlinesQ.data && captureQ.data && backupsQ.isSuccess && logQ.data && cabinsQ.data);
  const loadError = firstError(world, systemQ, airlinesQ, rulesQ, captureQ, logQ, cabinsQ);
  const toggle = (k: BoardKey) => setFolded((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const board = (k: BoardKey, children: ReactNode, aside?: ReactNode, id?: string, lead: ReactNode = NOTES[k]) => (
    <FoldBoard key={k} k={k} id={id} title={<span className="fbname">{k}</span>} note={SHORT[k]} aside={aside} folded={folded.has(k)}
      onToggle={() => toggle(k)} figure={FIGURE[k]}><div className="note fblead">{lead}</div>{children}</FoldBoard>);
  const backup = backupWords(backupsQ.data, (d) => niceDate(d));
  const summary = sysLines ? boardSummary(sysLines) : null;
  const checkedAt = systemQ.dataUpdatedAt ? new Date(systemQ.dataUpdatedAt).toISOString().slice(11, 16) + " UTC" : null;
  // each row's count or state
  const capAirlines = captureQ.data?.airlines ?? [];
  const capShort = capAirlines.filter((x) => captureStatus(x).cls !== "ok").length;
  const capAside = !captureQ.data ? null : <>
    {backup?.ok === false ? <span className="pill bad sm">backup failed</span> : null}
    {capShort ? <span className="pill warn sm">{capShort} of {capAirlines.length} incomplete</span> : <span>all {capAirlines.length} complete</span>}
  </>;
  const cabins = cabinsQ.data;
  const cabinAside = !cabins ? null : cabins.counts.problems
    ? <span className="pill warn sm" data-cabin-problems={cabins.counts.problems}>{cabins.counts.problems} to look at</span>
    : <span>{cabins.check_from ? `${cabins.counts.checked} fit${cabins.counts.checked === 1 ? "" : "s"}, no problems` : "nothing checked"}</span>;

  return (
    <main className="view review systems" data-screen="systems" data-systems-ready={ready ? "yes" : "no"} data-systems-view="/systems">
      <div className="vh todayvh sysvh">
        <p className="vk">The plumbing</p>
        <div className="todayttl">
          <h1 className="ansh" data-sys-summary={summary?.mark ?? ""}>{sysLines ? boardTitle(sysLines) : "Systems"}</h1>
          {checkedAt ? <span className="pill mute syschk">checked at {checkedAt}</span> : null}
        </div>
        <p className="ansp">{summary ? (summary.mark === "ok" ? "Every line is green" : summary.text) + " · " : ""}the capture, the jobs, the backups, the planner's build and the usage the database can measure.</p>
      </div>
      {loadError ? <ErrorBox error={loadError} /> : null}
      {!ready && !loadError ? <div className="empty">Loading…</div> : null}
      {sysLines && systemQ.data ? <SystemsBoard lines={sysLines} captures={systemQ.data.capture} now={now} /> : null}
      <section className="sysrows" aria-labelledby="sysrows-h">
        <div className="sysrowsh">
          <h2 className="tph" id="sysrows-h">The details</h2>
          <FoldTools onCollapse={() => setFolded(new Set(BOARDS))} onExpand={() => setFolded(new Set())} hint="" />
        </div>
      {ready && rules && logQ.data ? (
        <>
          {board("Capture", <>
            <div className="toolbar">
              <button type="button" className="secondary" id="cap-reload" disabled={captureQ.isFetching}
                onClick={() => { void captureQ.refetch(); void systemQ.refetch(); void backupsQ.refetch(); }}>{captureQ.isFetching ? "Loading…" : "Reload"}</button>
              <span className="count">{captureQ.dataUpdatedAt ? "checked at " + new Date(captureQ.dataUpdatedAt).toISOString().slice(11, 16) + " UTC" : "not checked yet"}</span>
              {captureQ.error ? <> <span className="pill bad">{captureQ.error instanceof Error ? captureQ.error.message : String(captureQ.error)}</span></> : null}
            </div>
            <div className="tblwrap">
              <table className="tbl" data-figure="systems: capture table">
                <tbody>
                  <tr><th>Airline</th>{CAPTURE_KINDS.map((k) => <th key={k[0]}>{k[1]}</th>)}<th className="num">Flights, {niceDate(captureQ.data?.today)}</th><th className="num">{niceDate(captureQ.data?.yesterday)}</th><th>Today</th></tr>
                  {(captureQ.data?.airlines ?? []).map((x) => {
                    const st = captureStatus(x);
                    return (
                      <tr key={x.airline_id}>
                        <td><AirlineMark color={airline(x.airline_id)?.color} /><b>{airline(x.airline_id)?.name ?? x.name}</b></td>
                        {CAPTURE_KINDS.map(([k]) => { const c = captureCell(x.pages?.[k]); return <td key={k}>{c.dim ? <span className="dim">{c.text}</span> : c.text}</td>; })}
                        <td className="num">{x.flights_today || "—"}</td>
                        <td className="num">{x.flights_yesterday || "—"}</td>
                        <td>{st.cls === "ok" ? <span className="dim">{st.text}</span> : <span className={"pill " + st.cls}>{st.text}</span>}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <div className="note">Flights are counted by their departure date (local time), as the game lists them.</div>
            {backup ? <div className="note">{backup.ok === false ? <><span className="pill bad sm">Backup failed</span> {backup.text}</> : backup.text}</div> : null}
          </>, capAside)}
          {cabinsQ.data ? board("Cabin charges", <CabinChargesBody c={cabinsQ.data} airline={airline} busy={busy}
            onUse={(p) => void save(gameAmountChange(p))} />, cabinAside, "cabin-charges", <>{cabinCountsWords(cabinsQ.data)} · {NOTES["Cabin charges"]}</>) : null}
          {board("Manual entry", <ManualEntry worldId={w} rules={rules} log={{ ...logQ.data, airlines: logQ.data.airlines.map((a) => ({ ...a, name: airline(a.airline_id)?.name ?? a.name })) }}
            airlines={airlines} busy={busy} now={now} onSave={save} />)}
        </>
      ) : null}
      </section>
    </main>
  );
}

/** Cabin charges (since 22 Oct, spec docs/specs/2026-10-21-tidy-ups.md §3): every first fit that doesn't match the game's
 *  charge, with what we logged and what the game charged; Use the game's amount on a differing one. Matches are counted
 *  in the title, not listed. */
function CabinChargesBody({ c, airline, busy, onUse }: {
  c: CabinCharges;
  airline: (id: number) => OurAirline | undefined;
  busy: boolean;
  onUse: (p: CabinProblem) => void;
}) {
  if (!c.problems.length) {
    return <div className="dim">{c.check_from ? "Every cabin charge the game made matches the first fit we logged." : "Nothing is checked: the world has no cabin_charge_check_from setting."}</div>;
  }
  return (
    <>
      <div className="tblwrap">
        <table className="tbl" data-figure="systems: cabin charges table">
          <tbody>
            <tr><th>Airline</th><th>Aircraft</th><th>State</th><th>We logged</th><th>The game charged</th><th className="num">Difference</th><th></th></tr>
            {c.problems.map((p, i) => {
              const al = airline(p.airline_id);
              const key = `${p.state}:${p.logged?.id ?? "p" + (p.lines[0]?.id ?? i)}`;
              return (
                <tr key={key} data-cabin={p.registration ?? ""} data-cabin-state={p.state}>
                  <td><AirlineMark color={al?.color} /><b>{al?.name ?? p.airline ?? p.code}</b></td>
                  <td><b>{p.registration ?? "—"}</b></td>
                  <td><span className="pill warn sm">{CABIN_STATE_WORDS[p.state]}</span></td>
                  <td>{cabinLoggedWords(p)}</td>
                  <td>{cabinGameWords(p).map((x, k) => <div key={k}>{x}</div>)}</td>
                  <td className="num">{p.difference != null ? signedAsd(p.difference) : "—"}</td>
                  <td className="n">{p.state === "differs" && p.logged ? (
                    <button type="button" className="primary sm" data-cabin-use={p.logged.id} disabled={busy} onClick={() => onUse(p)}>Use the game's amount</button>
                  ) : null}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <div className="note">Not charged yet: no installation line more than {c.wait_days} days after the fit was logged. Not logged: the game charged a cabin for an aircraft with no first fit logged. <b>Use the game's amount</b> changes the logged fit to what the game charged.</div>
    </>
  );
}
