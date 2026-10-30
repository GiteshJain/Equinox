// Systems' charts (spec docs/specs/2026-10-30-charts-everywhere.md, part C; charts.ts), drawn with the chart kit: the usage
// figures as gauges against their triggers, and each airline's capture verdicts over the last 14 nights. The board's
// tiles and the capture table stay; Manual entry and Cabin charges stay tables.
import { ChartFrame, ChartTip, Gauge, HeatStrip, heatLayout } from "../../ui/charts";
import { usageGauges, verdictFill, verdictHistory, type CaptureAt } from "./charts";
import type { SystemStatus } from "./systems";

export function UsageGauges({ usage }: { usage: SystemStatus["usage"] }) {
  const gs = usageGauges(usage);
  if (!gs.length) return null;
  return (
    <ChartFrame title="Usage against the triggers" note="each figure's share of its trigger · amber from 70%, red at it (a brief at the next weekly review)" figure="systems: usage gauges">
      <ChartTip className="chartwrap kmultw" label="usage against the triggers">
        <div className="kgauges">
          {gs.map((x) => <Gauge key={x.key} g={x.g} figure={"systems: usage " + x.key} label={<><b>{x.label}</b><br />{x.words}</>} />)}
        </div>
      </ChartTip>
    </ChartFrame>
  );
}

export function CaptureHistory({ history }: { history: { today: string; answers: CaptureAt[][] } | undefined }) {
  const h = history ? verdictHistory(history.answers, history.today) : null;
  return (
    <ChartFrame title="The last 14 nights" note="each airline's capture verdict each night (UTC capture days)"
      legend={[{ label: "all good", color: "#1A7F55" }, { label: "short", color: "#E39B21" }, { label: "broken", color: "#B4234B" }, { label: "not checked", color: "#9AA4C4" }, { label: "no capture", color: "#ECEFF4" }]}
      figure="systems: capture history" empty={!h ? "Reading the last 14 nights…" : h.rows.length ? null : "No airline captured yet."}>
      {h ? <HeatStrip layout={(W) => heatLayout(h.rows, h.cols, { W, L: 44, row: 22, fill: verdictFill, every: W < 520 ? 3 : 1 })} label="capture verdicts, last 14 nights" figure="systems: capture nights" /> : null}
    </ChartFrame>
  );
}
