// Home, until it's rebuilt (build pull request 5): the old planner's link, and the proof that reading works (spec §3):
// the world's airlines from airlines, in their position order, and the time of the latest change in change_log.
import { useLatestChange, useOurAirlines, useWorld } from "../../data/reads";
import { formatMoment, useTimeMode } from "../../data/timeMode";
import { ErrorBox } from "../../ui/ErrorBox";
import { NotBuilt } from "../../ui/NotBuilt";
import { screen } from "../screens";

export function Home() {
  const world = useWorld();
  const airlines = useOurAirlines(world.data?.id);
  const latest = useLatestChange();
  const [mode] = useTimeMode();
  return (
    <NotBuilt screen={screen("home")}>
      <section className="panel" aria-labelledby="home-airlines">
        <h2 id="home-airlines">Our airlines{world.data ? ` in ${world.data.name}` : ""}</h2>
        {world.error ? <ErrorBox error={world.error} />
          : airlines.error ? <ErrorBox error={airlines.error} />
          : !airlines.data ? <div className="loading">Loading…</div>
          : airlines.data.length === 0 ? <p className="dim">No airlines in this world yet.</p>
          : (
            <ul className="airlines" data-airlines>
              {airlines.data.map((a) => (
                <li key={a.id} data-airline={a.game_id} data-color={a.livery_color ?? ""}>
                  <span className="lv" style={{ background: a.livery_color ?? "var(--faint)" }}></span>
                  <span className="nm">{a.public_name ?? a.planner_name ?? a.game_name ?? `Airline ${a.game_id}`}</span>
                  {a.active ? null : <span className="dim">(not active)</span>}
                </li>
              ))}
            </ul>
          )}
      </section>
      <section className="panel" aria-labelledby="home-latest">
        <h2 id="home-latest">Latest change</h2>
        {latest.error ? <ErrorBox error={latest.error} />
          : latest.isPending ? <div className="loading">Loading…</div>
          : latest.data ? <p data-latest-change={latest.data}>{formatMoment(latest.data, mode)}</p>
          : <p className="dim" data-latest-change="">No changes logged yet.</p>}
      </section>
    </NotBuilt>
  );
}
