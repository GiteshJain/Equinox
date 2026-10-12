// turns: whether a turn fits. The game's turnaround (the type's min_turn_min) plus our margin (turn_margin_min, an
// airline's override where it has one): manual §4, "the game's turnaround plus a 10–15 minute margin". Under the
// game's turnaround is a short turn (the game won't fly it); under the margin a tight one.
// The old code it follows: the old planner's turn checks (shortTurn, tightTurn in legsForTail and computeFreq).
import { RulesError, settingNumber } from "./input.js";
import type { AircraftTypeRow, Rules } from "./types.js";

export interface TurnCheck {
  ground_min: number;
  /** The type's turnaround in the game. */
  min_turn_min: number;
  /** min_turn_min + turn_margin_min: what the manual asks for. */
  need_min: number;
  /** ground ≥ need. */
  ok: boolean;
  /** Under the game's turnaround. */
  short: boolean;
  /** At or over the turnaround but under the margin. */
  tight: boolean;
}

/** The ground time a turn needs on this type: min_turn_min + turn_margin_min. */
export function turnNeed(rules: Rules, type: AircraftTypeRow, airlineId?: number | null): number {
  if (type.min_turn_min == null) throw new RulesError(`aircraft type ${type.name} has no min_turn_min`);
  return type.min_turn_min + settingNumber(rules, "turn_margin_min", airlineId);
}

/** Checks a ground time between two legs on this type. */
export function checkTurn(rules: Rules, type: AircraftTypeRow, groundMin: number, airlineId?: number | null): TurnCheck {
  const need = turnNeed(rules, type, airlineId);
  const min = type.min_turn_min ?? need;
  const short = groundMin < min;
  return { ground_min: groundMin, min_turn_min: min, need_min: need, ok: groundMin >= need, short, tight: !short && groundMin < need };
}
