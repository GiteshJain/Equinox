// The Systems board at the top of Systems (decision #23; at the top of Check until 20 Oct): one line each with a green, amber or red mark and when. Always
// open (it doesn't fold): one look says whether everything worked. Its marks and words are systems.ts's. Since 22 Oct
// (spec docs/specs/2026-10-22-planner-look-systems.md) its answer is the screen's title (Systems.tsx); here the lines are
// tiles, red first, then amber, then green, and each airline's evening capture is one row of a table. Every line keeps
// its data-sys and data-mark. Since 30 Oct (spec docs/specs/2026-10-30-charts-everywhere.md, part C) the capture table has
// each airline's verdicts over the last 14 nights under it, and the usage figures are gauges under the tiles too.
import { MARK_TILE_WORDS, captureVerdict, worstFirst, type Mark, type SysCapture, type SysLine, type SystemStatus } from "./systems";
import type { CaptureAt } from "./charts";
import { CaptureHistory, UsageGauges } from "./SystemsCharts";

const MARK_WORDS: Record<Mark, string> = { ok: "green", warn: "amber", bad: "red" };
const Dot = ({ mark }: { mark: Mark }) => <span className={"sysmark " + mark} role="img" aria-label={MARK_WORDS[mark]} title={MARK_WORDS[mark]} />;

export function SystemsBoard({ lines, captures, now, usage, history }: {
  lines: readonly SysLine[]; captures: readonly SysCapture[]; now: Date;
  /** Since 30 Oct (spec docs/specs/2026-10-30-charts-everywhere.md, part C): the usage figures for their gauges, and the
   *  capture history for the last 14 nights (SystemsCharts.tsx). */
  usage?: SystemStatus["usage"]; history?: { today: string; answers: CaptureAt[][] } | undefined;
}) {
  const capKey = (c: SysCapture) => `capture|${c.airline_id}`;
  const byKey = new Map(captures.map((c) => [capKey(c), c]));
  const capLines = lines.filter((l) => byKey.has(l.key));
  const tiles = worstFirst(lines.filter((l) => !byKey.has(l.key)));
  return (
    <section className="board sysboard" id="systems" data-figure="systems: board" aria-label="The Systems board">
      <ul className="systiles">
        {tiles.map((l) => (
          <li key={l.key} className={"sysline systile " + l.mark} data-sys={l.key} data-mark={l.mark}>
            <span className={"sysst " + l.mark}><Dot mark={l.mark} />{MARK_TILE_WORDS[l.mark]}</span>
            <span className="syslabel">{l.label}</span>
            <span className="systext">{l.text}</span>
            {l.when ? <span className="syswhen">{l.when}</span> : null}
          </li>
        ))}
      </ul>
      {capLines.length ? (
        <div className="syscapwrap">
          <h3 className="tph">Evening capture <span className="note">each airline's latest page and its verdict (UTC)</span></h3>
          <table className="tbl syscap">
            <thead><tr><th>Airline</th><th>Latest page</th><th>Verdict</th></tr></thead>
            <tbody>
              {capLines.map((l) => {
                const c = byKey.get(l.key) as SysCapture;
                const v = captureVerdict(c, now);
                return (
                  <tr key={l.key} className={"sysline " + l.mark} data-sys={l.key} data-mark={l.mark}>
                    <td className="sysname"><Dot mark={l.mark} /><span className="syslabel">{c.name ?? c.code ?? "airline " + c.airline_id}</span></td>
                    <td className={l.when ? "syswhen" : "dim"}>{l.when ?? "—"}</td>
                    <td className="systext"><span className={"pill sm " + v.cls}>{v.word}</span>{v.detail ? <span className="sysdet"> {v.detail}</span> : null}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          <CaptureHistory history={history} />
        </div>
      ) : null}
      {usage?.length ? <UsageGauges usage={usage} /> : null}
    </section>
  );
}
