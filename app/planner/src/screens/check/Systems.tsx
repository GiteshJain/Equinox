// The Systems board at the top of Check (decision #23): one line each with a green, amber or red mark and when. Always
// open (it doesn't fold): one look says whether everything worked. Its marks and words are systems.ts's.
import { Board } from "../../ui/Board";
import { boardSummary, type Mark, type SysLine } from "./systems";

const MARK_WORDS: Record<Mark, string> = { ok: "green", warn: "amber", bad: "red" };

export function SystemsBoard({ lines, checkedAt }: { lines: readonly SysLine[]; checkedAt: string | null }) {
  const sum = boardSummary(lines);
  return (
    <Board title="Systems" className="sysboard" figure="check: systems" id="systems"
      note={<><span className={"pill sm " + sum.mark} data-sys-summary={sum.mark}>{sum.text}</span>{checkedAt ? ` · checked at ${checkedAt}` : ""} · the capture, the jobs, the backups, the planner's build and the usage the database can measure</>}>
      <ul className="syslist">
        {lines.map((l) => (
          <li key={l.key} className="sysline" data-sys={l.key} data-mark={l.mark}>
            <span className={"sysmark " + l.mark} role="img" aria-label={MARK_WORDS[l.mark]} title={MARK_WORDS[l.mark]} />
            <span className="syslabel">{l.label}</span>
            {l.when ? <span className="syswhen">{l.when}</span> : null}
            <span className="systext">{l.text}</span>
          </li>
        ))}
      </ul>
    </Board>
  );
}
