// Under the header on every screen, as in the old planner (its #terminator and #clocks, renderClocks):
//   - the equinox band: 24 hours of UTC from midnight to midnight, a marker at now, moved each minute. The old planner
//     still draws it but its last style layer hides it (#terminator{display:none}); it's kept the same way here, hidden,
//     so the two look alike (the pull request says so);
//   - the game clocks: one chip per time zone of our bases, west to east, with the local time there, a dot for day or
//     night and the bases' codes. The zones and times are the planning library's (time.clocks), from rules_input().
import { time } from "@rules";
import { useNow } from "../data/clock";
import { useWorld } from "../data/reads";
import { useRules } from "../data/rules";

export function Band() {
  const now = useNow();
  const m = now.getUTCHours() * 60 + now.getUTCMinutes();
  return (
    <div id="terminator" title="Now, in UTC — the band runs from midnight to midnight" data-band>
      <i style={{ left: (m / 1440) * 100 + "%" }} />
    </div>
  );
}

export function Clocks() {
  const now = useNow();
  const world = useWorld();
  const rules = useRules(world.data?.id).data?.rules;
  const zones = rules ? time.clocks(rules, rules.bases.map((b) => b.airport_code), now.toISOString()) : [];
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
