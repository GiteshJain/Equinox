// What Today reads beyond the earlier screens' own (spec docs/specs/2026-10-20-today-performance-systems.md): Home's
// reads (aircraft on order, plan cards, launch days, to-dos and their steps, dismissals, the backups, the jobs,
// capture_status(), airline_cards() and growth_signals()), Interline's rows and agreements (needs attention's interline
// line), Tails' (the types each airline may have, the game's address, every aircraft, filing's reads), Routes' markets
// and Performance's cash_forecast() for each airline. Read fresh when saving: the legs a fix from the game changes.
import { supabase } from "../../data/supabase";

const fail = (what: string, message: string): never => {
  throw new Error(`Couldn't read ${what}: ${message}`);
};

export interface LegNow { id: number; rotation_id: number; leg_no: number; days_utc: number[]; dep_utc_min: number | null; block_min: number | null; updated_at: string }

/** The legs of some rotations as they are now, with their updated_at (a fix from the game changes them). */
export async function readLegs(rotationIds: readonly number[]): Promise<LegNow[]> {
  if (!rotationIds.length) return [];
  const { data, error } = await supabase.from("flight_legs").select("id, rotation_id, leg_no, days_utc, dep_utc_min, block_min, updated_at")
    .in("rotation_id", [...rotationIds]).order("rotation_id").order("leg_no");
  if (error) return fail("the flight legs", error.message);
  return data as unknown as LegNow[];
}
