// The picture behind everything in the glass look (to-do 225, spec docs/specs/2026-11-11-glass-look.md, step 1): a fixed
// layer under the page, shown only under [data-look="glass"] (styles.css). It follows this computer's clock through
// useNow(), so the screen checks' frozen clock decides the period, and moves on each minute.
import { useEffect } from "react";
import { useNow } from "../../data/clock";
import { applyPeriod, periodOf } from "./look";

export function Backdrop() {
  const now = useNow();
  const period = periodOf(now.getHours());
  useEffect(() => applyPeriod(period), [period]);
  return <div className="eq-backdrop" aria-hidden="true" data-backdrop={period} />;
}
