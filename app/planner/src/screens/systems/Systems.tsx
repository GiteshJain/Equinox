// Systems (spec docs/specs/2026-10-20-today-performance-systems.md): the plumbing, rarely opened. At the top the Systems
// board (decision #23, SystemsBoard.tsx), always open: one line each, green, amber or red, with when, for each airline's
// evening capture (with #21's verdict), the daily snapshot, the nightly backup, the monthly archive, the clean-ups, the
// world scan, the planner's own build and the usage the database can measure (system_status()). Then the boards that fold
// (all folded on arrival, Collapse all and Expand all), each moved here on 20 Oct as it was:
//   - Capture: what the capture collected for each airline and when (capture_status()), with Reload, and the backup's
//     line (Check's);
//   - Manual entry (ManualEntry.tsx): cash and fixed costs, the nightly log, loads by hand (Review's);
//   - Aircraft checks: the one-week checks due (the library's checks.oneWeek), with each aircraft's issues and its routes'
//     load patterns, the ones coming up by date and how many are done; Mark checked. Shown only while the checks are on
//     (aircraft_check_after_days above 0; manual §1 has none since 15 Oct) (Check's).
//   - Cabin charges (since 22 Oct, spec docs/specs/2026-10-21-tidy-ups.md §3): each first cabin fit logged against the
//     game's charge (cabin_charges()), the problems listed with Use the game's amount on a differing one; open on arrival
//     when Today's item sent you (#cabin-charges).
// The Cabins board (each aircraft's cabin against its markets, with Refitted to, Keep as is and Show again; Check's) went
// on 21 Oct (spec docs/specs/2026-10-21-cabins-new-rule.md §1): the cabin is chosen with each order, and the plan card
// suggests it (Tails).
// Since 22 Oct (spec docs/specs/2026-10-22-planner-look-systems.md) short and answer-first, as the new Today: the board's
// answer is the title ("All systems good", or how many need a look) with "checked at" as a small pill beside it; the
// board's lines as tiles, worst first, and each airline's capture as one row of a table (SystemsBoard.tsx); the four
// boards that fold as a short list of large rows, each with a one-line note and its count or state, opening right below.
// Address: /planner/systems, and the aircraft pop-up (?aircraft=REG, Tails' AircraftPopup). Every action is one
// planner_save() call.
import { useMemo, useState, type ReactNode } from "react";
import { useLocation, useSearchParams } from "react-router";
import { checks, game, tails } from "@rules";
import { ourAirlines, type OurAirline } from "../../data/airlines";
import { buildStamp } from "../../data/build";
import { useNow } from "../../data/clock";
import { queryClient } from "../../data/query";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import type { Change } from "../../data/save";
import { saver } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { dayDiff, niceDate, todayAt } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { FoldBoard, FoldTools } from "../../ui/FoldBoard";
import { refreshFigures, useGrowthSignals } from "../performance/reads";
import { AircraftPopup } from "../tails/AircraftPopup";
import { figuresOf, issueWords, markCheckedChange, rulesLegs, typeName, type TailAircraft } from "../tails/model";
import { useLaunches, useTailsAircraft } from "../tails/reads";
import { ManualEntry } from "./ManualEntry";
import {
  BOARDS, CABIN_STATE_WORDS, CAPTURE_KINDS, backupWords, cabinCountsWords, cabinGameWords, cabinLoggedWords, captureCell, captureStatus,
  gameAmountChange, patternPill, patternRanks, shownBoards, signedAsd, upcomingByDay, type BoardKey, type CabinCharges, type CabinProblem,
} from "./model";
import { useBackupLine, useCabinCharges, useCapture, useCashLog, useSystemStatus } from "./reads";
import { SystemsBoard } from "./SystemsBoard";
import { boardSummary, boardTitle, systemLines } from "./systems";

/** Each row's one-line note; the board's full words (NOTES) open with it. */
const SHORT: Record<BoardKey, string> = {
  "Capture": "What the capture collected from the game, per airline",
  "Cabin charges": "Each first cabin fit logged, against the game's charge",
  "Manual entry": "Only needed if a night's capture failed",
  "Aircraft checks": "One check, a week after an aircraft is scheduled",
};
const NOTES: Record<BoardKey, string> = {
  "Capture": "what the one-click capture collected from the game, per airline · times in UTC · cash and fixed costs go straight into Performance",
  "Cabin charges": "each first cabin fit filing logged, against the game's \"Installation of cabin interior\" line on the bank statement",
  "Manual entry": "only needed if a night's capture failed · cash, fixed costs and loads normally come from the capture",
  "Aircraft checks": "one check, a week after an aircraft is scheduled · once marked checked it only comes back when that aircraft's schedule changes",
};
const FIGURE: Record<BoardKey, string> = {
  "Capture": "systems: capture", "Cabin charges": "systems: cabin charges", "Manual entry": "systems: manual entry", "Aircraft checks": "systems: aircraft checks",
};
/** The board Today's cabin charges item opens (/planner/systems#cabin-charges). */
const CABIN_HASH = "#cabin-charges";

const firstError = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

export function Systems() {
  const [search, setSearch] = useSearchParams();
  const loc = useLocation();
  const now = useNow();
  const today = todayAt(now);
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const rulesQ = useRules(w);
  const systemQ = useSystemStatus(w);
  const captureQ = useCapture(w);
  const backupsQ = useBackupLine();
  const logQ = useCashLog(w);
  const aircraftQ = useTailsAircraft(w);
  const launchesQ = useLaunches(w);
  const signalsQ = useGrowthSignals(w);
  const cabinsQ = useCabinCharges(w !== undefined);
  // every board folded on arrival, but Cabin charges open when Today's item sent you here
  const [folded, setFolded] = useState<ReadonlySet<BoardKey>>(() => new Set(BOARDS.filter((k) => !(k === "Cabin charges" && loc.hash === CABIN_HASH))));
  const [busy, setBusy] = useState(false);
  const tailPopup = search.get("aircraft");
  const setTailPopup = (reg: string | null) => setSearch((s) => {
    const n = new URLSearchParams(s);
    if (reg) n.set("aircraft", reg);
    else n.delete("aircraft");
    return n;
  });

  const rules = rulesQ.data?.rules;
  const airlines: OurAirline[] = useMemo(() => ourAirlines(airlinesQ.data), [airlinesQ.data]);
  const airline = (id: number) => airlines.find((a) => a.id === id);
  const all = useMemo(() => aircraftQ.data ?? [], [aircraftQ.data]);
  const byId = useMemo(() => new Map(all.map((a) => [a.id, a])), [all]);

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

  // ---------- Aircraft checks
  const checkList = useMemo(() => (rules && aircraftQ.data && launchesQ.data
    ? checks.oneWeek(rules, { aircraft: aircraftQ.data, rotations: launchesQ.data }, today) : null), [rules, aircraftQ.data, launchesQ.data, today]);
  const ranks = useMemo(() => {
    if (!rules) return new Map<number, number>();
    return patternRanks(rules, today, Number(rules.input.settings.load_window_days) || 0);
  }, [rules, today]);
  const freqs = useMemo(() => (rules ? game.frequencies(rules, null) : []), [rules]);

  const scanEvery = rules ? Number(rules.input.settings.scan_every_days ?? NaN) : NaN;
  const sysLines = useMemo(() => (systemQ.data ? systemLines(systemQ.data, buildStamp(), now, Number.isFinite(scanEvery) ? scanEvery : null) : null),
    [systemQ.data, now, scanEvery]);
  const ready = !!(sysLines && rules && airlinesQ.data && captureQ.data && backupsQ.isSuccess && logQ.data && aircraftQ.data && launchesQ.data
    && signalsQ.data && checkList && cabinsQ.data);
  const loadError = firstError(world, systemQ, airlinesQ, rulesQ, captureQ, logQ, aircraftQ, launchesQ, signalsQ, cabinsQ);
  const toggle = (k: BoardKey) => setFolded((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  // Aircraft checks only while the checks are on (aircraft_check_after_days above 0)
  const shown = rules ? shownBoards(rules, airlines.map((a) => a.id)) : BOARDS;
  const board = (k: BoardKey, children: ReactNode, aside?: ReactNode, id?: string, lead: ReactNode = NOTES[k]) => (shown.includes(k)
    ? <FoldBoard key={k} k={k} id={id} title={<span className="fbname">{k}</span>} note={SHORT[k]} aside={aside} folded={folded.has(k)}
      onToggle={() => toggle(k)} figure={FIGURE[k]}><div className="note fblead">{lead}</div>{children}</FoldBoard> : null);
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
  const dueN = checkList ? checkList.filter((c) => c.status === "due").length : 0;
  const checksAside = !checkList ? null : dueN ? <span className="pill warn sm">{dueN} due</span> : <span>none due</span>;

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
      {ready && rules && checkList && logQ.data ? (
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
          {board("Aircraft checks", <ChecksBody list={checkList} today={today} rules={rules} byId={byId} airline={airline} freqs={freqs} ranks={ranks}
            patterns={signalsQ.data?.load_patterns ?? []} busy={busy} onAircraft={setTailPopup}
            onCheck={(a) => void save([markCheckedChange(a, today)])} />, checksAside)}
        </>
      ) : null}
      </section>
      {tailPopup && rules ? <AircraftPopup registration={tailPopup} rules={rules} onClose={() => setTailPopup(null)} /> : null}
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

/** The aircraft checks (the old renderReview's checks): each one due with its aircraft's issues and its routes' load
 *  patterns, the ones coming up by day, and how many are done. */
function ChecksBody({ list, today, rules, byId, airline, freqs, ranks, patterns, busy, onAircraft, onCheck }: {
  list: ReturnType<typeof checks.oneWeek>;
  today: string;
  rules: NonNullable<ReturnType<typeof useRules>["data"]>["rules"];
  byId: ReadonlyMap<number, TailAircraft>;
  airline: (id: number) => OurAirline | undefined;
  freqs: ReturnType<typeof game.frequencies>;
  ranks: ReadonlyMap<number, number>;
  patterns: NonNullable<ReturnType<typeof useGrowthSignals>["data"]>["load_patterns"];
  busy: boolean;
  onAircraft: (registration: string) => void;
  onCheck: (a: TailAircraft) => void;
}) {
  const due = list.filter((c) => c.status === "due"), up = list.filter((c) => c.status === "upcoming"), doneN = list.filter((c) => c.status === "done").length;
  const legs = rulesLegs(rules);
  return (
    <>
      {!list.length ? <div className="dim">No launch dates yet. Set "Launched" on a frequency (new frequencies get today automatically) and its aircraft will come up here a week later.</div> : null}
      {due.map((c) => {
        const a = byId.get(c.aircraft_id);
        if (!a) return null;
        const al = airline(a.airline_id);
        const fig = figuresOf(rules, a.id, legs);
        const iss = fig.week ? tails.issues(rules, a.id, legs, fig.week, fig.maint) : [];
        const mine = freqs.filter((f) => (f.leg1?.aircraft_id ?? f.leg2?.aircraft_id ?? null) === a.id);
        const dests = [...new Set(mine.map((f) => f.dest))];
        const routes = new Set(mine.map((f) => f.route_id));
        const lf = patterns.filter((p) => routes.has(p.route_id))
          .map((p, i) => ({ p, i })).sort((x, y) => (ranks.get(x.p.route_id) ?? 1e9) - (ranks.get(y.p.route_id) ?? 1e9) || x.i - y.i).map((v) => v.p);
        const base = a.base_code ?? "";
        const hub = rules.bases.find((b) => b.airport_code === base && b.airline_id === a.airline_id);
        return (
          <div className="ck due" key={a.id} data-check={a.registration}>
            <div className="ckh">
              <button type="button" className="link" data-tailm={a.registration} onClick={() => onAircraft(a.registration)}><b>{a.registration}</b></button>{" "}
              {base ? <span className="hubtag on" style={{ "--lv": al?.color ?? "#8B96A8" } as React.CSSProperties} title={hub && hub.role === "focus" ? "focus city" : "hub"}>{base}</span> : null}{" "}
              <span className="dim">{al?.name ?? ""} · {typeName(rules, a.aircraft_type_id)} · flies {dests.join(", ") || "—"} · last scheduled {niceDate(c.last)} · check due {niceDate(c.due)}</span>
              <button type="button" className="primary sm" data-checked={a.registration} disabled={busy} onClick={() => onCheck(a)}>Mark checked</button>
            </div>
            <div className="ckb">
              {iss.length ? iss.map((x, k) => <span key={k} className="pill bad">{issueWords(x)}</span>)
                : <span className="dim">schedule clean — {fig.blockDay.toFixed(1)} h a day, no short turns</span>}
              {lf.map((p) => { const x = patternPill(p); return <span key={p.route_id} className={"pill " + x.cls}>{x.text}</span>; })}
            </div>
            <div className="note">In the game: loads on each route, the maintenance ratio, and that every leg flew on time.</div>
          </div>
        );
      })}
      {up.length ? (
        <div className="tblwrap">
          <table className="tbl" style={{ marginTop: 4 }} data-figure="systems: checks coming up">
            <tbody>
              <tr><th style={{ width: 170 }}>Due</th><th>Aircraft</th></tr>
              {upcomingByDay(up).map(([d, regs]) => {
                const n = dayDiff(today, d);
                return <tr key={d}><td><b>{niceDate(d)}</b> <span className="dim">in {n} day{n === 1 ? "" : "s"}</span></td><td>{regs.join(", ")}</td></tr>;
              })}
            </tbody>
          </table>
        </div>
      ) : null}
      {doneN ? <div className="dim">{doneN} aircraft checked since their schedule last changed.</div> : null}
    </>
  );
}
