// The Tails list as bars (spec docs/specs/2026-10-30-charts-everywhere.md, part C; charts.ts), drawn with the chart kit, a
// chart per base; tap a bar for the aircraft. Tails.tsx puts the table behind it ("show as table").
import { ChartFrame, HBars, Legend, hbarLayout } from "../../ui/charts";
import { blockBars, blockMarks } from "./charts";
import type { TailRow } from "./model";

export function TailsChart({ rows, target, onPick }: { rows: readonly TailRow[]; target: number; onPick: (registration: string) => void }) {
  const groups = blockBars(rows);
  const marks = blockMarks(target);
  return (
    <div className="tchart" data-figure="tails: chart">
      <div className="note tchartn">Block hours a day, each aircraft · the dashed lines are {marks.map((m) => m.label).join(" and ")} · coloured by maintenance · tap a bar for the aircraft</div>
      <Legend items={[{ label: "maintenance fine", color: "#1A7F55" }, { label: "little headroom", color: "#E39B21" }, { label: "under the minimum", color: "#B4234B" },
        { label: "no figure", color: "#9AA4C4" }]} />
      {!groups.length ? <div className="dim kce">No tails match. Clear a filter.</div> : null}
      {groups.map((g) => (
        <ChartFrame key={g.base} title={g.base} note={`${g.items.length} aircraft`} figure="tails: base chart">
          <HBars layout={(W) => hbarLayout(g.items, { fmt: (v) => `${v} h`, marks, W, L: 84, R: 40, row: 20 })} label={`${g.base}: block hours a day`}
            figure="tails: block hours" onPick={onPick} />
        </ChartFrame>
      ))}
    </div>
  );
}
