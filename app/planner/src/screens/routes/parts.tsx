// Routes' small parts, as the old planner draws them: a route's stars, a load's pill (lfChip), the loads over 7 days
// (lfSummary) and a bank-fit pill (wavePill).
import { useState } from "react";
import type { Wave } from "@rules";
import { PREVIEW } from "../../data/preview";
import { queryClient, tableKey } from "../../data/query";
import { showMessage } from "../../ui/messages";
import { PREVIEW_WORDS } from "../photos/model";
import { joinPair } from "./reads";
import { joinWords, loadAverage, loadClass, loadTip, pairTitle, starsText, type Load, type PairMark } from "./model";

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

/** Join this pair (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §1): on an owner's route of a shared pair no one
 *  has joined, the button naming the airline that would join; it calls join_pair() (the database checks the rest: the
 *  first two Saturdays' 6-pair limit, an excluded airline, a joiner already there) and reads the routes again. Look-only
 *  on a preview. */
export function JoinPair({ mark }: { mark: PairMark }) {
  const [busy, setBusy] = useState(false);
  if (!mark.join) return null;
  const join = mark.join;
  async function go() {
    if (PREVIEW) { showMessage(PREVIEW_WORDS); return; }
    setBusy(true);
    try {
      const r = await joinPair(join.ownerRouteId);
      showMessage(`${join.joiner} joined the pair: its route is on its list now (${r.joined} pair${r.joined === 1 ? "" : "s"} joined). Its fares follow this airline's ladder.`);
      void queryClient.invalidateQueries({ queryKey: tableKey("routes") });
      void queryClient.invalidateQueries({ queryKey: ["rules"] });
      void queryClient.invalidateQueries({ queryKey: ["figures"] });
    } catch (e) {
      showMessage(`Couldn't join the pair: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setBusy(false);
    }
  }
  return (
    <button type="button" className="secondary joinpair" data-join-pair={join.ownerRouteId} disabled={busy} onClick={() => void go()}
      title={`${join.joiner} may fly this pair too, at this airline's price (manual §2)`}>{joinWords(mark)}</button>
  );
}

/** A shared pair's pill on a route's row: "shared with KF: 14 a week" or "follows MH: 21 a week". */
export function PairPill({ mark }: { mark: PairMark | undefined }) {
  if (!mark?.text) return null;
  return <span className={"pill shared " + mark.role} data-shared={mark.role} title={pairTitle(mark)}>{mark.text}</span>;
}
