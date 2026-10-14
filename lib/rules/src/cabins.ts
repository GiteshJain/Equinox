// cabins: each aircraft's cabin against what its markets want, the Check screen's Cabins board (#18 build pull request 9,
// spec docs/specs/2026-10-13-check.md; manual §5: the cabin follows the market default, whatever the aircraft).
//   - Each leg an aircraft flies in the week wants a cabin: its route's own choice (routes.cabin_choice) or else its
//     market's default cabin layout's cabin. The aircraft's block minutes are added up by the cabin they want.
//   - The cabin most of its flying wants is compared with the cabin it has; where they differ it's listed, with that
//     cabin's share of its flying, every cabin's share, and the layout of its type with that cabin, if there is one.
//   - A refit pays where the share is at least cabin_refit_share_pct (the setting); its cost is cabin_refit_cost.
//   - "Keep as is" lasts until the aircraft's routes call for a different cabin: a keep names the cabin they called for
//     (aircraft_cabin_keeps), so it no longer counts once they call for another.
// The old code it follows: the old planner's cabinFit and cabinsBoard (its 0.2M and 70% are settings here). The aircraft,
// their order and the tables' rows the rule needs are the caller's; the legs are the library's (aircraftWeek).
import { forAircraft as weekOf } from "./aircraftWeek.js";
import { timedLegs } from "./block.js";
import { settingNumber } from "./input.js";
import type { Rules, TimedLeg } from "./types.js";

/** What the rule needs from the tables. */
export interface CabinFacts {
  /** The aircraft to look at, in the order to list them (the old planner's list of tails), with the cabin each has. */
  aircraft: readonly { id: number; cabin_config_id: number | null }[];
  /** Every cabin layout: its code, its type and its cabin. */
  configs: readonly { id: number; code: string; aircraft_type_id: number | null; cabin: string | null }[];
  /** Each route's own cabin choice, where it has one. */
  routes: readonly { id: number; cabin_choice: string | null }[];
  /** Each market's default cabin layout. */
  markets: readonly { id: number; default_config_id: number | null }[];
  /** The "keep as is" decisions: the aircraft, the cabin its routes called for, and the day. */
  keeps: readonly { aircraft_id: number; cabin: string; decided_on: string | null }[];
}

export interface CabinFit {
  aircraft_id: number;
  registration: string;
  airline_id: number;
  /** The cabin it has (its layout's cabin), "" when its layout has none or it has no layout. */
  have: string;
  /** Its layout's code, "" without one. */
  have_code: string;
  /** The cabin most of its flying wants. */
  want: string;
  /** That cabin's share of its block minutes, a whole percent. */
  share: number;
  /** Every cabin its flying wants with its share, most first. */
  mix: { cabin: string; pct: number }[];
  /** The layout of its type with the cabin wanted (the first in the layouts' order), or null when its type has none. */
  target: { id: number; code: string } | null;
  /** At least cabin_refit_share_pct of its flying wants the other cabin: a refit that pays. */
  strong: boolean;
  /** When it was kept as is for this cabin, or null: still to decide. */
  kept_on: string | null;
  kept: boolean;
}

const upper = (s: string | null | undefined) => String(s ?? "").toUpperCase();

/** Every aircraft whose cabin differs from what most of its flying wants, by share (most first; the aircraft's order for
 *  a tie). Aircraft that don't fly, or whose routes want no cabin, aren't listed. */
export function fit(rules: Rules, facts: CabinFacts, legs: readonly TimedLeg[] = timedLegs(rules)): CabinFit[] {
  const configs = new Map(facts.configs.map((c) => [c.id, c]));
  const choice = new Map(facts.routes.map((r) => [r.id, r.cabin_choice]));
  const marketConfig = new Map(facts.markets.map((m) => [m.id, m.default_config_id]));
  const keeps = new Map(facts.keeps.map((k) => [`${k.aircraft_id}|${k.cabin}`, k]));
  const wantOf = (routeId: number | null): string | null => {
    if (routeId == null) return null;
    const route = rules.routes.get(routeId);
    if (!route) return null;
    const own = choice.get(routeId);
    if (own) return own;
    const cfgId = route.market_id == null ? null : marketConfig.get(route.market_id) ?? null;
    return (cfgId == null ? null : configs.get(cfgId)?.cabin) || null;
  };
  const out: CabinFit[] = [];
  for (const f of facts.aircraft) {
    const a = rules.aircraft.get(f.id);
    if (!a) continue;
    const week = weekOf(rules, a, legs);
    if (!week || !week.legs.length) continue;
    const w = new Map<string, number>();
    let tot = 0;
    for (const l of week.legs) {
      const want = wantOf(l.route_id);
      if (!want) continue;
      w.set(want, (w.get(want) ?? 0) + l.block_min);
      tot += l.block_min;
    }
    if (!tot) continue;
    const sorted = [...w].map((x, i) => ({ x, i })).sort((p, q) => q.x[1] - p.x[1] || p.i - q.i).map((v) => v.x);
    const [dom, mins] = sorted[0] as [string, number];
    const own = f.cabin_config_id == null ? undefined : configs.get(f.cabin_config_id);
    const have = own?.cabin ?? "";
    if (have === dom) continue;
    const typeName = a.aircraft_type_id == null ? "" : rules.types.get(a.aircraft_type_id)?.name ?? "";
    const target = facts.configs.find((c) => upper(c.aircraft_type_id == null ? "" : rules.types.get(c.aircraft_type_id)?.name) === upper(typeName) && c.cabin === dom) ?? null;
    const share = Math.round(mins / tot * 100);
    const keep = keeps.get(`${a.id}|${dom}`);
    out.push({
      aircraft_id: a.id, registration: a.registration, airline_id: a.airline_id, have, have_code: own?.code ?? "", want: dom, share,
      mix: sorted.map(([cabin, v]) => ({ cabin, pct: Math.round(v / tot * 100) })),
      target: target ? { id: target.id, code: target.code } : null,
      strong: share >= settingNumber(rules, "cabin_refit_share_pct", a.airline_id),
      kept_on: keep ? keep.decided_on : null, kept: !!keep,
    });
  }
  return out.map((x, i) => ({ x, i })).sort((p, q) => q.x.share - p.x.share || p.i - q.i).map((v) => v.x);
}

/** A refit's cost (AS$) for an airline: cabin_refit_cost. */
export const refitCost = (rules: Rules, airlineId?: number | null): number => settingNumber(rules, "cabin_refit_cost", airlineId);
