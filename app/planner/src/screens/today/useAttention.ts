// Needs attention's reads and figures, in one place for the two screens that show them (spec
// docs/specs/2026-10-23-attention-on-home.md): Home shows its summary cards, Today each group's full list. Everything
// here was Today's own until 23 Oct and is unchanged: the orders (can order now or from when, the safe types, each
// delivery line), the aircraft to file, needs attention's items (today/attention.ts) without those dismissed, where each
// item is fixed, and dismiss and show again. One set of reads, shared through TanStack Query's cache, so Home and Today
// never work the figures out twice or differently.
import { useMemo, useState } from "react";
import { growth } from "@rules";
import { ourAirlines, type OurAirline } from "../../data/airlines";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import { saver } from "../../data/saving";
import { familyOf } from "../../ui/aircraftNames";
import { dismissKey, withoutDismissed, type AttItem } from "../../ui/attention";
import { toMinute } from "../../ui/dates";
import { useBackups, useCaptureStatus, useDismissals, useGrowth, useHomeAircraft, useJobs, usePlanCards, useTodoItems, useTodos } from "../home/reads";
import { isOpen, statusOf } from "../interline/model";
import { useAgreements } from "../interline/reads";
import { useInterlineRows } from "../interline/useRows";
import { useForecasts, useReviewCards } from "../performance/reads";
import { typeName } from "../tails/model";
import { useBuyTypes } from "../tails/reads";
import { useLatestThreats } from "../competition/reads";
import { useCabinCharges, useFleetChecks, useServiceChecks } from "../systems/reads";
import { homeAttention, type HomeAirline } from "./attention";
import { attentionHref, deliveryLines, lineQueues, orderStatus, safeTypes, toFile, type OrderRow } from "./model";
import { onOrder } from "./onOrder";
import { dismissChanges, showAgainChanges } from "./todos";

const first = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

export { opensAircraft } from "./model";

/** Everything needs attention reads and works out, for Home's cards and Today's sections. */
export function useAttention(now: Date, today: string) {
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const rulesQ = useRules(w);
  const aircraftQ = useHomeAircraft(w);
  const planCardsQ = usePlanCards(w);
  const todosQ = useTodos(w);
  const itemsQ = useTodoItems(w);
  const dismissalsQ = useDismissals(w);
  const backupsQ = useBackups();
  const jobsQ = useJobs();
  const captureQ = useCaptureStatus(w);
  const cardsQ = useReviewCards(w);
  const growthQ = useGrowth(w);
  const interline = useInterlineRows(w);
  const agreementsQ = useAgreements(w);
  const buyQ = useBuyTypes(w);
  const airlines: OurAirline[] = useMemo(() => ourAirlines(airlinesQ.data), [airlinesQ.data]);
  // the orders are for the airlines the captured figures cover (airline_cards(): our active airlines), in our order
  const ordering = useMemo(() => airlines.filter((a) => (cardsQ.data?.airlines ?? []).some((c) => c.airline_id === a.id)), [airlines, cardsQ.data]);
  const forecastsQ = useForecasts(ordering.map((a) => a.id));
  // the rivals' moves the latest world scan showed (competition(), since 21 Oct), for needs attention
  const competition = useLatestThreats(ordering.map((a) => a.id));
  const threats = competition.threats;
  // the cabin charge check (cabin_charges(), since 22 Oct), for needs attention
  const cabinsQ = useCabinCharges(w !== undefined);
  // the fleet checks (fleet_checks(), since 22 Oct), for needs attention's Fleet group
  const fleetQ = useFleetChecks(w);
  // the service check (market_service_checks(), since 30 Oct), for needs attention's Service in the game
  const serviceQ = useServiceChecks(w !== undefined);
  // dismissed here and not yet back from the database (and, on a preview, dismissed here only, as the old planner does)
  const [dismissedHere, setDismissedHere] = useState<ReadonlySet<string>>(new Set());

  const rules = rulesQ.data?.rules;
  // needs attention words airlines as Home did (HomeAirline: the old planner's names)
  const homeAirlines: HomeAirline[] = useMemo(() => airlines.map((a) => ({ id: a.id, name: a.name, code: a.code, color: a.color })), [airlines]);
  const interlineOpen = useMemo(() => {
    if (!interline.rows || !agreementsQ.data) return null;
    const records = new Map(agreementsQ.data.map((a) => [a.airline_id + "|" + a.country_code, a]));
    return interline.rows.filter((r) => isOpen(statusOf(records.get(r.airline_id + "|" + r.cc)))).length;
  }, [interline.rows, agreementsQ.data]);
  const attention = useMemo(() => (rules && todosQ.data ? homeAttention({
    now, today, airlines: homeAirlines, rules, todos: todosQ.data, capture: captureQ.data ?? null, backups: backupsQ.data ?? null,
    jobs: jobsQ.data ?? null, cards: cardsQ.data?.airlines ?? null, growth: growthQ.data ?? null, interlineOpen, threats, cabins: cabinsQ.data ?? null,
    fleet: fleetQ.data ?? null, service: serviceQ.data ?? null,
  }) : null), [now, today, homeAirlines, rules, todosQ.data, captureQ.data, backupsQ.data, jobsQ.data, cardsQ.data, growthQ.data, interlineOpen, threats,
    cabinsQ.data, fleetQ.data, serviceQ.data]);
  const dismissed = useMemo(() => new Set([...(dismissalsQ.data ?? []).map((d) => d.alert_key), ...dismissedHere]), [dismissalsQ.data, dismissedHere]);
  const attShown = useMemo(() => (attention ? withoutDismissed(attention, dismissed) : null), [attention, dismissed]);

  // ---------- orders: can order now or from when, the safe types, and each delivery line
  const orders: OrderRow[] | null = useMemo(() => {
    if (!rules || !cardsQ.data || !buyQ.data || !aircraftQ.data || forecastsQ.some((q) => !q.data)) return null;
    const family = (id: number | null) => familyOf(typeName(rules, id));
    const families = [...new Set(buyQ.data.filter((b) => airlines.some((a) => a.id === b.airline_id)).map((b) => family(b.aircraft_type_id)))].sort();
    const unfiled = aircraftQ.data.filter((a) => a.status === "on_order" || a.status === "delivered");
    return ordering.map((a, i) => {
      const card = cardsQ.data.airlines.find((c) => c.airline_id === a.id);
      const allowed = new Set(buyQ.data.filter((b) => b.airline_id === a.id).map((b) => family(b.aircraft_type_id)));
      const deliveries = unfiled.filter((x) => x.airline_id === a.id && x.delivery_at).map((x) => ({ family: family(x.aircraft_type_id), delivery_ms: toMinute(x.delivery_at as string) }));
      const cells = growth.orderQueues(rules, a.id, families, allowed, deliveries, now.getTime());
      const types = forecastsQ[i]?.data?.types;
      return { airline: a, status: orderStatus(card?.next_order, card?.can_order_now), types: safeTypes(types), lines: deliveryLines(cells, types, (t) => family(t.aircraft_type_id)),
        queues: lineQueues(cells, deliveries, now.getTime(), types, (t) => family(t.aircraft_type_id)) };
    });
  }, [rules, cardsQ.data, buyQ.data, aircraftQ.data, forecastsQ, airlines, ordering, now]);

  // each airline's cash_forecast() types (undefined until read, or for an airline the figures don't cover), for Today's
  // open lines (since 28 Oct): when a line's next aircraft can be ordered
  const forecastOf = useMemo(() => {
    const by = new Map(ordering.map((a, i) => [a.id, forecastsQ[i]?.data?.types] as const));
    return (airlineId: number) => by.get(airlineId);
  }, [ordering, forecastsQ]);

  // ---------- aircraft to file: arrived with a plan card
  const filing = useMemo(() => (rules && aircraftQ.data && planCardsQ.data
    ? toFile(onOrder(aircraftQ.data, rules, new Map(planCardsQ.data.map((p) => [p.aircraft_id, p.title] as const)), homeAirlines, now.getTime()).groups) : null),
  [rules, aircraftQ.data, planCardsQ.data, homeAirlines, now]);

  const hrefOf = (a: AttItem) => attentionHref(a, airlines);
  async function dismiss(a: AttItem) {
    if (w === undefined) return;
    const key = dismissKey(a);
    setDismissedHere((s) => new Set([...s, key]));
    const res = await saver.save(dismissChanges(w, key, today));
    if (res.status === "clash") setDismissedHere((s) => new Set([...s].filter((k) => k !== key)));
  }
  async function showAgain() {
    setDismissedHere(new Set());
    if (dismissalsQ.data?.length) await saver.save(showAgainChanges(dismissalsQ.data));
  }

  const ready = !!(rules && todosQ.data && dismissalsQ.data && backupsQ.data && jobsQ.data && captureQ.data && cardsQ.data && growthQ.data
    && aircraftQ.data && planCardsQ.data && airlinesQ.data && interlineOpen !== null && orders && filing && threats && cabinsQ.data && fleetQ.data
    && serviceQ.data && attShown);
  const loadError = first(world, airlinesQ, rulesQ, aircraftQ, planCardsQ, todosQ, itemsQ, dismissalsQ, backupsQ, jobsQ, captureQ, cardsQ, growthQ,
    buyQ, ...forecastsQ, competition, cabinsQ, fleetQ, serviceQ);

  return {
    w, world, airlines, airlinesQ, rules, rulesQ, todosQ, itemsQ, captureQ, aircraftQ, dismissalsQ,
    orders, forecastOf, filing, attShown, hrefOf, dismiss, showAgain, ready, loadError,
  };
}
