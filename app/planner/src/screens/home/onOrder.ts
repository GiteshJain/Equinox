// Aircraft on order: every aircraft not yet in service (on order, or arrived and not yet filed into the planner), by
// airline in their order, soonest first, as the old planner's onOrderBoard shows them.
import type { Rules } from "@rules";
import { familyOf, shortType } from "../../ui/aircraftNames";
import { toMinute } from "../../ui/dates";
import type { HomeAirline } from "./reads";
import type { AircraftRow } from "./reads";

export interface OnOrderRow {
  id: number;
  registration: string;
  /** Its type, as the old planner shortens it (A321neo), and its cabin layout as ordered. */
  type: string;
  config: string;
  family: string;
  /** When it arrives (or arrived) in the game, to the minute, milliseconds since 1970 (NaN when unknown). */
  at: number;
  arrived: boolean;
  base: string;
  /** The plan noted with the order, without its base in front ("LGW · LIS + IST" → "LIS + IST"). */
  plan: string;
  hasCard: boolean;
}

export interface OnOrderGroup {
  airline: HomeAirline;
  rows: OnOrderRow[];
  /** How many arrived and wait to be filed. */
  arrived: number;
  /** Each family and how many, in the order they first come. */
  families: [string, number][];
}

export function onOrder(aircraft: readonly AircraftRow[], rules: Rules, withCard: ReadonlySet<number>, airlines: readonly HomeAirline[], now: number):
  { count: number; groups: OnOrderGroup[] } {
  const rows = aircraft
    .filter((a) => a.status === "on_order" || a.status === "delivered")
    .map((a) => {
      const typeName = a.aircraft_type_id == null ? "" : rules.types.get(a.aircraft_type_id)?.name ?? "";
      const at = a.delivery_at ? toMinute(a.delivery_at) : NaN;
      return {
        airline_id: a.airline_id,
        row: {
          id: a.id, registration: a.registration, type: shortType(typeName), family: familyOf(typeName),
          config: a.order_config_id == null ? "" : rules.configs.get(a.order_config_id)?.code ?? "",
          at, arrived: Number.isFinite(at) && at <= now, base: a.order_base_code ?? "",
          plan: String(a.order_note ?? "").replace(/^[A-Z]{3} · /, ""), hasCard: withCard.has(a.id),
        } satisfies OnOrderRow,
      };
    })
    .sort((x, y) => (Number.isFinite(x.row.at) ? x.row.at : Infinity) - (Number.isFinite(y.row.at) ? y.row.at : Infinity) || x.row.id - y.row.id);
  const groups: OnOrderGroup[] = [];
  for (const airline of airlines) {
    const mine = rows.filter((r) => r.airline_id === airline.id).map((r) => r.row);
    if (!mine.length) continue;
    const fam = new Map<string, number>();
    for (const r of mine) fam.set(r.family, (fam.get(r.family) ?? 0) + 1);
    groups.push({ airline, rows: mine, arrived: mine.filter((r) => r.arrived).length, families: [...fam.entries()] });
  }
  return { count: groups.reduce((n, g) => n + g.rows.length, 0), groups };
}

/** A family as the summary words it ("5 A320-family"). */
export const familyWords = ([f, n]: [string, number]) => `${n} ${f === "A320 family" ? "A320-family" : f}`;
