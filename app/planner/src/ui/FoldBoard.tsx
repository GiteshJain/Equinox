// A board that folds open and shut by its title, as the old Check's (decorateBoards): folded, only the title shows.
// Performance (open on arrival) and Systems (folded on arrival) use it since 20 Oct, as Review and Check did. The title's
// text is the board's key (data-rkey); clicks on a button, box or link in the title don't fold.
import type { ReactNode } from "react";

export function FoldBoard({ k, id, title, note, folded, onToggle, figure, children }: {
  k: string;
  /** The board's anchor in the address (#cabin-charges), when a link opens it. */
  id?: string;
  title?: ReactNode;
  note?: ReactNode;
  folded: boolean;
  onToggle: () => void;
  /** The saved answers' name for the board's figures, for the checks. */
  figure?: string;
  children?: ReactNode;
}) {
  return (
    <section id={id} className={"board" + (folded ? " rcol" : "")} data-figure={figure} data-board={k}>
      <h3 className="rh rch" data-rkey={k} tabIndex={0} aria-expanded={!folded}
        onClick={(e) => { if (!(e.target as HTMLElement).closest("button, input, select, a, label")) onToggle(); }}
        onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onToggle(); } }}>
        <span className="chev" aria-hidden="true" />{title ?? k}{note != null && note !== "" ? <> <span className="note">{note}</span></> : null}
      </h3>
      {children}
    </section>
  );
}

/** Collapse all · Expand all, as the old Check's tools. */
export function FoldTools({ onCollapse, onExpand }: { onCollapse: () => void; onExpand: () => void }) {
  return (
    <div className="revtools">
      <button type="button" className="link" id="rev-colall" onClick={onCollapse}>Collapse all</button><span className="dim">·</span>
      <button type="button" className="link" id="rev-expall" onClick={onExpand}>Expand all</button>
      <span className="dim">· click a board's title to open or fold it · everything folds again when you leave this tab</span>
    </div>
  );
}
