// The game clocks, in the panel the top bar's clock button opens (since 22 Oct, spec
// docs/specs/2026-10-22-planner-look-foundation.md; before, a row under the header on every screen): one chip per time
// zone of our bases, west to east, with the local time there, a dot for day or night and the bases' codes. The zones and
// times are the planning library's (time.clocks), from rules_input(); stations (since 22 Oct) are no bases and get none.
// The hidden equinox band went with the move.
import { banks, time } from "@rules";
import { useNow } from "../data/clock";
import { useWorld } from "../data/reads";
import { useRules } from "../data/rules";

export function Clocks() {
  const now = useNow();
  const world = useWorld();
  const rules = useRules(world.data?.id).data?.rules;
  const zones = rules ? time.clocks(rules, rules.bases.filter((b) => !banks.isStation(b)).map((b) => b.airport_code), now.toISOString()) : [];
  return (
    <div id="clocks" aria-label="Game time at the hubs" data-clocks={rules ? "ready" : "loading"}>
      {zones.map((z) => (
        <div key={z.offset_h} className={"zc " + (z.day ? "day" : "nite")} data-zone={z.label}>
          <div className="zt">{time.clock(z.local_min)}<span className="zo">{z.label}</span></div>
          <div className="zh">{z.codes.join(" ")}</div>
        </div>
      ))}
    </div>
  );
}
