// "Figures as of 11 Nov, 15:02 UTC" (since 11 Nov; spec docs/specs/2026-11-11-stored-figures.md §2): the loaded stored
// set's moment, in the planner's local/UTC mode, on Home's header and Performance's pages. Nothing with no stored set (the
// figures are then read live, as each screen asks).
import { useTimeMode } from "../data/timeMode";
import { figuresTime, useFiguresAsOf } from "../data/useStoredFigures";

/** The words, or null with no stored set. */
export function useFiguresAsOfWords(): string | null {
  const asOf = useFiguresAsOf();
  const [mode] = useTimeMode();
  return asOf ? "Figures as of " + figuresTime(asOf, mode) : null;
}

export function FiguresAsOf({ className = "figasof" }: { className?: string }) {
  const asOf = useFiguresAsOf();
  return asOf ? <AsOfWords asOf={asOf} className={className} /> : null;
}

function AsOfWords({ asOf, className }: { asOf: string; className: string }) {
  const [mode] = useTimeMode();
  return <p className={className} data-figures-as-of>{"Figures as of " + figuresTime(asOf, mode)}</p>;
}
