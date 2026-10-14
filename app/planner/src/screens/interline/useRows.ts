// Interline's rows from the database (model.ts's interlineRows on the start's rules input, the waiting plan cards and the
// setting interline_rules), shared by Interline and by Home's interline line in needs attention (the switch, build pull
// request 13; design §16): the old Home counted the same rows as the old Interline (interlineRows), so both read them here.
import { useMemo } from "react";
import { useOurAirlines } from "../../data/reads";
import { useRules } from "../../data/rules";
import { useAirports } from "../routes/reads";
import { onDeliveries } from "../tails/model";
import { usePlanCards, usePlanLegs, useTailsAircraft } from "../tails/reads";
import { interlineRows, parseRules, type IlAirline, type IlPlan, type IlRotation, type IlRow } from "./model";

export function useInterlineRows(w: number | undefined) {
  const airlinesQ = useOurAirlines(w);
  const rulesQ = useRules(w);
  const aircraftQ = useTailsAircraft(w);
  const cardsQ = usePlanCards(w);
  const legsQ = usePlanLegs(w);

  const rules = rulesQ.data?.rules;
  const airlines: IlAirline[] = useMemo(() => (airlinesQ.data ?? []).map((a) => ({
    id: a.id, code: a.iata_code, name: a.planner_name ?? a.public_name ?? a.game_name ?? `Airline ${a.game_id}`, color: a.livery_color,
  })), [airlinesQ.data]);
  const ilRules = useMemo(() => (rules ? parseRules(rules.input.settings.interline_rules) : null), [rules]);

  // the waiting plan cards: an aircraft not in service, on the deliveries board, with a card; its legs from the card's rows
  const plans: IlPlan[] = useMemo(() => {
    if (!aircraftQ.data || !cardsQ.data || !legsQ.data) return [];
    const ac = new Map(aircraftQ.data.map((a) => [a.id, a]));
    return cardsQ.data.flatMap((c): IlPlan[] => {
      const a = ac.get(c.aircraft_id);
      if (!a || a.status === "active" || !onDeliveries(a)) return [];
      const legs = legsQ.data.filter((l) => l.plan_card_id === c.id).sort((x, y) => x.position - y.position).map((l) => ({ from: l.origin_code, to: l.dest_code }));
      return [{ airline_id: a.airline_id, registration: a.registration, legs }];
    });
  }, [aircraftQ.data, cardsQ.data, legsQ.data]);
  const planCodes = useMemo(() => [...new Set(plans.flatMap((p) => p.legs.flatMap((l) => [l.from, l.to])).filter((x): x is string => !!x))]
    .filter((c) => !rules?.airports.has(c)), [plans, rules]);
  const planAirportsQ = useAirports(w, planCodes);

  const home = useMemo(() => new Set((rules?.bases ?? []).map((b) => rules?.airports.get(b.airport_code)?.country_code).filter((x): x is string => !!x)), [rules]);
  const nameOf = useMemo(() => (code: string) => airlines.find((a) => a.code === code)?.name ?? code, [airlines]);

  const rows: IlRow[] | null = useMemo(() => {
    // the plans are read before the rows are made, so a waiting card's countries are never left out
    if (!rules || !ilRules || !airlinesQ.data || !aircraftQ.data || !cardsQ.data || !legsQ.data || (planCodes.length && !planAirportsQ.data)) return null;
    const rotations: IlRotation[] = [];
    const days = new Map<number, { l1?: number; l2?: number }>();
    for (const l of rules.legs) {
      if (l.rotation_id == null) continue;
      const d = days.get(l.rotation_id) ?? {};
      if ((l.leg_no ?? 1) === 1) d.l1 ??= l.days_utc.length;
      else d.l2 ??= l.days_utc.length;
      days.set(l.rotation_id, d);
    }
    for (const id of [...rules.rotations.keys()].sort((a, b) => a - b)) {
      const rot = rules.rotations.get(id);
      const route = rot ? rules.routes.get(rot.route_id) : undefined;
      if (!route) continue;
      const d = days.get(id) ?? {};
      rotations.push({ airline_id: route.airline_id, hub: route.hub_code, dest: route.dest_code, days: d.l1 ?? d.l2 ?? 0 });
    }
    const planCountry = new Map((planAirportsQ.data ?? []).map((a) => [a.code, a.country_code]));
    return interlineRows({
      airlines, rotations, plans, home, rules: ilRules, nameOf,
      countryOf: (ap) => rules.airports.get(ap)?.country_code ?? planCountry.get(ap) ?? null,
    });
  }, [rules, ilRules, airlinesQ.data, aircraftQ.data, cardsQ.data, legsQ.data, airlines, plans, home, nameOf, planCodes.length, planAirportsQ.data]);

  const error = airlinesQ.error ?? rulesQ.error ?? aircraftQ.error ?? cardsQ.error ?? legsQ.error ?? planAirportsQ.error;
  return { rules, airlines, ilRules, home, nameOf, rows, error };
}
