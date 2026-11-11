// The landing page's look (since 11 Nov; spec docs/specs/2026-11-11-stored-figures.md §2): the brand, one line saying what
// is happening and, under it, the loading's progress when there is one. Its words and when it shows are model.ts's; a
// restyle (the glass look, to-do 225) changes this file and its styles alone. No way past it but the model's time limits
// (Gitesh, 11 Nov: no "open anyway" link).
export function Landing({ line, detail }: { line: string; detail: string | null }) {
  return (
    <div className="landing" data-landing={line} role="status" aria-live="polite">
      <div className="landing-orb" aria-hidden="true"></div>
      <div className="landing-in">
        <div className="gbrand"><span className="eqwm">equinox<i></i></span></div>
        <p className="landing-line">{line}</p>
        {detail ? <p className="landing-detail">{detail}</p> : null}
      </div>
    </div>
  );
}

/** The line at the top of every screen when the planner opened on the previous capture's figures. */
export function StaleFigures({ note }: { note: string }) {
  return <div className="stalefigs" role="status" data-stale-figures>{note}</div>;
}
