// Routes' small parts, as the old planner draws them: a route's stars, a load's pill (lfChip), the loads over 7 days
// (lfSummary) and a bank-fit pill (wavePill).
import type { Wave } from "@rules";
import { loadAverage, loadClass, loadTip, starsText, type Load } from "./model";

export function Stars({ n, title }: { n: number; title?: string }) {
  const s = starsText(n);
  return <span className="stars" title={title}>{s.on}<span className="off">{s.off}</span></span>;
}

/** A load's pill: "≈97%" and, unless small, how many departures. */
export function LoadChip({ a, small }: { a: Load | null | undefined; small?: boolean }) {
  if (!a) return null;
  const avg = loadAverage(a);
  return (
    <span className={`pill ${loadClass(avg)} lfc`} title={loadTip(a)} data-load>
      ≈{Math.round(avg)}%{small ? null : <> <span className="lfn">{a.departures}</span></>}
    </span>
  );
}

/** A route's loads over the last 7 days: the pill, how many departures on how many days, and the bands as a bar. */
export function LoadSummary({ a }: { a: Load | null | undefined }) {
  if (!a) return <div className="lfs dim" data-figure="routes: loads">No load reports in the last 7 days yet.</div>;
  const seg = (n: number, c: string) => (n ? <i className={c} style={{ flex: n }} /> : null);
  return (
    <div className="lfs" data-figure="routes: loads">
      <div className="lfsh">
        <b>Loads, last 7 days</b> <LoadChip a={a} small />{" "}
        <span className="dim">across {a.departures} departure{a.departures === 1 ? "" : "s"} on {a.days} reported day{a.days === 1 ? "" : "s"}</span>
      </div>
      <div className="lfbar">{seg(a.full, "l0")}{seg(a.under_95, "l95")}{seg(a.under_85, "l85")}{seg(a.under_70, "l70")}</div>
      <div className="lfleg">
        <span><i className="l0" />95%+ {a.full}</span><span><i className="l95" />under 95 {a.under_95}</span>
        <span><i className="l85" />under 85 {a.under_85}</span><span><i className="l70" />under 70 {a.under_70}</span>
      </div>
    </div>
  );
}

/** A bank-fit pill: its level as the pill's class, its words. */
export function WavePill({ w }: { w: Wave | null }) {
  if (!w) return null;
  return <span className={`pill ${w.level}`} data-wave>{w.text}</span>;
}
