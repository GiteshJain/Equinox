// A board: a titled panel, as the old planner's (<div class="board"><h3 class="rh">Title <span class="note">…</span></h3>).
import { useId, type ReactNode } from "react";

export function Board({ title, note, className, children, figure, id }: {
  title: ReactNode;
  note?: ReactNode;
  className?: string;
  /** The saved answers' name for the board's figures (tests/fixtures/planner_numbers.expected.json), for the checks. */
  figure?: string;
  id?: string;
  children?: ReactNode;
}) {
  const h = useId();
  return (
    <section className={"board" + (className ? " " + className : "")} aria-labelledby={h} data-figure={figure} id={id}>
      <h3 className="rh" id={h}>
        <span className="rht">{title}</span>
        {note != null && note !== "" ? <span className="note">{note}</span> : null}
      </h3>
      {children}
    </section>
  );
}
