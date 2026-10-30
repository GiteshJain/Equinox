// Tails (decision #18, build pull request 7; spec docs/specs/2026-10-13-tails.md): every aircraft, what it flies each week
// and how hard it works, as the old planner's Tails, from the same data, with the same figures and look:
//   - the list, one airline at a time: filters for base, type and Flying / No flights / Needs a look; each aircraft's legs
//     a week, block hours a day, maintenance (with the hours on hover) and routes; Add a tail; remove;
//   - an aircraft (AircraftPage.tsx): its header, the fields that change it, its week and every issue;
//   - the deliveries board (Deliveries.tsx): aircraft on order, arrived or flying, each with its plan card (since 21 Oct
//     with the cabin its routes call for and Use the suggestion, and the fare level of each route it flies, from
//     fare_ladder() for the card's airline, read while a card is open), and filing an arrived one into the planner after
//     checking it against the game (Filing.tsx); since 28 Oct the airline's 7-day lines over it (Lines.tsx: each line's
//     slots, its check across the cards and Write the next card, spec docs/specs/2026-10-27-long-haul-lines.md §2).
// Since 23 Oct (spec docs/specs/2026-10-23-planner-look-tails.md) in the new look, as Today, Routes, Systems and
// Performance: the answer is the title ("N aircraft need a look", from the Needs a look filter's count over the airline's
// fleet, or "All N aircraft flying well") with the fleet's size and block hours a day as a muted pill; count tiles for
// Flying, No flights and Needs a look, each applying its filter (tap again to clear), and Deliveries (on order, arrived,
// to file) taking you to the board; the list as one table (registration and base, type, cabin, legs, block hours,
// maintenance, routes cut short with the full list on hover), on a phone compact rows (registration and base, block
// hours, maintenance) that open to the rest; the deliveries as rows that open their plan card. Nothing it reads, works
// out or saves changed.
// Addresses: /planner/tails (filters in the address: ?airline=PA&base=JFK&type=...&status=warn&del=on+order&card=REG)
// and /planner/tails/<registration>. Home's "File into planner" opens ?file=<registration>, which starts filing at
// once, as the old Home's button did. Each action is one planner_save() call; the start's rules are read again after it.
// Since 30 Oct (spec docs/specs/2026-10-30-charts-everywhere.md, part C) the list opens as bars (TailsChart.tsx): block hours
// a day per aircraft against the 10- and 12-hour marks, coloured by maintenance, a chart per base; tap a bar for the
// aircraft. The table (with remove and the rows that unfold) stays one tap away ("show as table"); Add a tail stays under
// both. The aircraft page's legs stay a table.
import { useEffect, useMemo, useRef, useState } from "react";
import { useLocation, useNavigate, useParams } from "react-router";
import { settingNumber, tails as tailRules } from "@rules";
import { useNow } from "../../data/clock";
import { queryClient } from "../../data/query";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import type { Change } from "../../data/save";
import { saver } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { ChartOrTable } from "../../ui/charts";
import { ConfirmPanel } from "../../ui/Confirm";
import { todayAt } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { showMessage } from "../../ui/messages";
import { useFareLadder } from "../performance/reads";
import { gameMaintenance } from "../systems/model";
import { useFleetChecks } from "../systems/reads";
import { useAirlineRoutes, useAirports, useMarkets } from "../routes/reads";
import { AircraftPage, MaintPill } from "./AircraftPage";
import { Deliveries } from "./Deliveries";
import { TailsChart } from "./TailsChart";
import type { LineView } from "./Lines";
import { FileCheckModal, useFiling } from "./Filing";
import {
  addTailChanges, basesOf, deliveryCounts, routeNames, routesCell, tailCounts, tailsAnswer, cardCabin, cardCabinChange, cardFareLevels, fareCells, stationsOf, cardLegs, cardServiceIssues, chips, configsFor, deleteTailChanges, deliveryRows, editTailChange, filtersQuery, flyingIds, parseFilters, removeDeliveryChanges, removeTailChanges,
  issuesShown, lineCandidates, lineCardChanges, typeName, lineCheck, lineSize, lineSlots, nextFreeOffset, rulesLegs, shownDeliveries, tailRows, tailsOf, typesFor, withAirports, withRoutes, type CardLeg, type DeliveryRow, type ShownIssue, type Filters, type PlanCardRow, type PlanLegRow,
  type TailAircraft, type TailAirline, type TailField,
} from "./model";
import {
  readRotationsWithLegs, removalFacts, useBuyTypes, useConfigs, useGameHost, useLowCost, usePlanCards, usePlanLegs, usePlanLineLegs, usePlanLines, useTailsAircraft,
} from "./reads";

const firstError = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;
const STATUS: readonly [Filters["status"], string][] = [["", "All"], ["flying", "Flying"], ["idle", "No flights"], ["warn", "Needs a look"]];

export function Tails() {
  const params = useParams();
  const loc = useLocation();
  const navigate = useNavigate();
  const filters = useMemo(() => parseFilters(loc.search), [loc.search]);
  const reg = decodeURIComponent((params["*"] ?? "").split("/")[0] ?? "");
  const now = useNow();
  const today = todayAt(now);
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const lowCostQ = useLowCost(w);
  const rulesQ = useRules(w);
  const aircraftQ = useTailsAircraft(w);
  const configsQ = useConfigs(w);
  const buyQ = useBuyTypes(w);
  const cardsQ = usePlanCards(w);
  const planLegsQ = usePlanLegs(w);
  // the 7-day lines and their legs (since 28 Oct; spec docs/specs/2026-10-27-long-haul-lines.md §2)
  const linesQ = usePlanLines(w);
  const lineLegsQ = usePlanLineLegs(w);
  const hostQ = useGameHost(w);
  // the game's maintenance from the latest night's fleet pages (fleet_checks(), the read the pop-up shares): the board
  // and the issues show it for an aircraft the game flies (since 23 Oct); until it's read, or if it can't be, the estimate
  const fleetQ = useFleetChecks(w);
  const gameMaint = useMemo(() => gameMaintenance(fleetQ.data), [fleetQ.data]);
  const [busy, setBusy] = useState(false);
  const [removing, setRemoving] = useState<TailAircraft | null>(null);
  // on a phone, the list's row opened to show the rest of its figures (registration of the row)
  const [unfolded, setUnfolded] = useState("");

  const airlines: TailAirline[] = useMemo(() => (airlinesQ.data ?? []).map((a) => ({
    id: a.id, code: a.iata_code, name: a.planner_name ?? a.public_name ?? a.game_name ?? `Airline ${a.game_id}`, color: a.livery_color,
    is_lcc: !!(lowCostQ.data ?? []).find((x) => x.id === a.id)?.is_lcc, game_id: a.game_id,
  })), [airlinesQ.data, lowCostQ.data]);
  const all = useMemo(() => aircraftQ.data ?? [], [aircraftQ.data]);
  const open = reg ? all.find((a) => a.registration === reg && a.status === "active") : undefined;
  const airline = (open ? airlines.find((a) => a.id === open.airline_id) : undefined)
    ?? airlines.find((a) => a.code === filters.airline) ?? (filters.airline ? undefined : airlines[0]);
  const startRules = rulesQ.data?.rules;
  const configs = useMemo(() => new Map((configsQ.data ?? []).map((c) => [c.id, c])), [configsQ.data]);
  // the plan cards' airports, which the start may not carry (a new destination), for their local times
  const cardCodes = useMemo(() => [...new Set([...(planLegsQ.data ?? []), ...(lineLegsQ.data ?? [])].flatMap((l) => [l.origin_code, l.dest_code]))], [planLegsQ.data, lineLegsQ.data]);
  const airportsQ = useAirports(w, cardCodes);
  const rules = useMemo(() => (startRules ? withAirports(startRules, airportsQ.data ?? []) : undefined), [startRules, airportsQ.data]);

  const mine = useMemo(() => tailsOf(all, airline?.id), [all, airline]);
  const rows = useMemo(() => (rules ? tailRows(mine, filters, rules, configs, gameMaint) : []), [mine, filters, rules, configs, gameMaint]);
  // the answer and the count tiles (the look, 23 Oct): the title from the airline's whole fleet, the tiles from the base
  // and type picked, so each tile's count is what its filter shows
  const whole = useMemo(() => (rules ? tailCounts(tailRows(mine, { base: "", type: "", status: "" }, rules, configs, gameMaint)) : null), [mine, rules, configs, gameMaint]);
  const counts = useMemo(() => (rules ? tailCounts(tailRows(mine, { ...filters, status: "" }, rules, configs, gameMaint)) : null), [mine, filters, rules, configs, gameMaint]);
  const answer = whole ? tailsAnswer(whole) : null;
  const chipLists = useMemo(() => (rules ? chips(mine, rules) : { bases: [], types: [] }), [mine, rules]);
  const flying = useMemo(() => (rules ? flyingIds(rules) : new Set<number>()), [rules]);
  const stations = useMemo(() => (rules && airline ? stationsOf(rules, airline.id) : undefined), [rules, airline]);
  const deliveries = useMemo(() => (rules && cardsQ.data ? deliveryRows(all, airlines, rules, configs, cardsQ.data, now.getTime(), today) : []),
    [all, airlines, rules, configs, cardsQ.data, now, today]);
  const shown = useMemo(() => shownDeliveries(deliveries, airline?.id, filters), [deliveries, airline, filters]);
  const delCounts = useMemo(() => deliveryCounts(shownDeliveries(deliveries, airline?.id, { ...filters, del: "" })), [deliveries, airline, filters]);
  // the plan card's service check and its cabin (21 Oct): the airline's routes laid in, as filing takes a leg's distance
  // from them, with their markets' layouts and their own cabin choices
  const routesQ = useAirlineRoutes(w, airline?.id);
  const marketsQ = useMarkets(w);
  const serviceRules = useMemo(() => (rules && routesQ.data ? withRoutes(rules, routesQ.data, marketsQ.data ?? []) : rules), [rules, routesQ.data, marketsQ.data]);
  const serviceOf = useMemo(() => (card: PlanCardRow, legs: readonly CardLeg[]) => (serviceRules ? cardServiceIssues(serviceRules, card.airline_id, legs) : new Map<number, string>()),
    [serviceRules]);
  const legsByCard = useMemo(() => {
    const by = new Map<number, PlanLegRow[]>();
    for (const l of planLegsQ.data ?? []) by.set(l.plan_card_id, [...(by.get(l.plan_card_id) ?? []), l]);
    return by;
  }, [planLegsQ.data]);
  const legsOf = useMemo(() => (card: PlanCardRow) => (rules ? cardLegs(rules, legsByCard.get(card.id) ?? []) : []), [legsByCard, rules]);
  // the cabin the card's routes call for (manual §5; the library's card.cabinFor)
  const suggestionOf = useMemo(() => (r: DeliveryRow) => (serviceRules && r.card ? cardCabin(serviceRules, r.card, legsByCard.get(r.card.id) ?? []) : null),
    [serviceRules, legsByCard]);
  // the fare level of each route the open card flies (manual §5, since 21 Oct; the library's card.cardFares), from
  // fare_ladder() for the airline, read only while a card is open
  const ladderQ = useFareLadder(filters.card && airline ? airline.id : undefined);
  const faresOf = useMemo(() => (card: PlanCardRow, legs: readonly CardLeg[]) =>
    (serviceRules ? fareCells(legs, cardFareLevels(serviceRules, card, legsByCard.get(card.id) ?? [], ladderQ.data)) : new Map<number, string>()),
  [serviceRules, legsByCard, ladderQ.data]);

  // the airline's lines: each with its slots, its check across the cards that exist, the next free offset and the aircraft
  // that can take it (on order, of the line's type, without a card)
  const lineViews: LineView[] = useMemo(() => {
    if (!rules || !airline || !cardsQ.data) return [];
    const size = lineSize(rules, airline.id);
    return (linesQ.data ?? []).filter((l) => l.airline_id === airline.id).map((line): LineView => {
      const slots = lineSlots(line, cardsQ.data ?? [], all, flying, now.getTime(), size);
      return {
        line, type: typeName(rules, line.aircraft_type_id), legs: (lineLegsQ.data ?? []).filter((x) => x.line_id === line.id).length, slots,
        check: lineCheck(rules, line, slots, (id) => legsByCard.get(id) ?? []), next: nextFreeOffset(slots), candidates: lineCandidates(line, all, cardsQ.data ?? []),
      };
    });
  }, [rules, airline, cardsQ.data, linesQ.data, lineLegsQ.data, all, flying, now, legsByCard]);

  const openRow = useMemo(() => (rules && open ? tailRows([open], { base: "", type: "", status: "" }, rules, configs, gameMaint)[0] : undefined), [rules, open, configs, gameMaint]);
  const fig = openRow?.fig;
  const issues: ShownIssue[] = useMemo(() => (rules && open && fig?.week
    ? issuesShown(tailRules.issues(rules, open.id, rulesLegs(rules), fig.week, fig.maint), openRow?.maint ?? null) : []), [rules, open, fig, openRow]);
  const roundTrips = useMemo(() => {
    if (!rules || !open) return [];
    const ids = new Set<number>();
    for (const l of rules.legs) if (l.rotation_id != null && l.aircraft_id === open.id) ids.add(l.rotation_id);
    return [...ids];
  }, [rules, open]);

  const ready = !!(rules && aircraftQ.data && configsQ.data && buyQ.data && cardsQ.data && planLegsQ.data && linesQ.data && lineLegsQ.data && airlinesQ.data && lowCostQ.data
    && (!cardCodes.length || airportsQ.data));
  const loadError = firstError(world, airlinesQ, lowCostQ, rulesQ, aircraftQ, configsQ, buyQ, cardsQ, planLegsQ, linesQ, lineLegsQ, airportsQ);

  // ---------- addresses
  const here = (f: Filters, path = reg ? `/tails/${encodeURIComponent(reg)}` : "/tails") => path + filtersQuery(f);
  const keep = (f: Filters, replace = false) => navigate(here(f), { replace });
  const listFilters = (f: Filters) => ({ ...f, airline: airline && airline !== airlines[0] ? airline.code : f.airline });
  const toTail = (r: string) => navigate(`/tails/${encodeURIComponent(r)}` + filtersQuery({ ...filters, airline: null, card: "", file: "" }));

  // ---------- saving: one action each; the start's rules are read again after it, since the fleet or schedule changed
  async function save(changes: Change[]) {
    if (!changes.length) return { status: "saved" as const };
    setBusy(true);
    try {
      const res = await saver.save(changes);
      if (res.status === "saved") void queryClient.invalidateQueries({ queryKey: ["rules"] });
      return res;
    } finally {
      setBusy(false);
    }
  }
  // a plan card's cabin (since 18 Oct): one action on the card; filing fits it
  async function onCardCabin(r: DeliveryRow, code: string) {
    if (!r.card) return;
    const cfg = code ? (configsQ.data ?? []).find((c) => c.code === code) : undefined;
    await save(cardCabinChange(r.card, cfg?.id ?? null));
  }
  // a line's next card (since 28 Oct): the aircraft picked, at the next free offset, its legs from the line; one action
  async function onWriteLine(v: LineView, a: TailAircraft) {
    if (w === undefined || v.next == null) return;
    const res = lineCardChanges({ worldId: w, line: v.line, legs: (lineLegsQ.data ?? []).filter((x) => x.line_id === v.line.id), aircraft: a, offset: v.next, size: v.slots.length });
    if ("error" in res) { showMessage(res.error); return; }
    const x = await save(res.changes);
    if (x.status === "saved") showMessage(`${a.registration} has its card on ${v.line.name}: day ${v.next + 1} of ${v.slots.length}.`);
  }
  // remove a delivery (the old data-deldel): what the old adapter looked at, read now, then one action
  async function onRemoveDelivery(r: DeliveryRow) {
    if (w === undefined) return;
    try {
      const facts = await removalFacts(w, r.a.id);
      await save(removeDeliveryChanges(r.a, facts, today));
      if (filters.card === r.a.registration) keep({ ...filters, card: "" }, true);
    } catch (e) {
      showMessage(e instanceof Error ? e.message : String(e));
    }
  }
  const filing = useFiling({
    worldId: w, rules, airlines, host: hostQ.data, configs, today, save,
    onFiled: (r, words) => { showMessage(words); toTail(r); },
  });
  // Home's "File into planner": start filing once everything is read, and keep the card open on the board
  const started = useRef("");
  useEffect(() => {
    if (!filters.file || !ready || started.current === filters.file) return;
    started.current = filters.file;
    const a = all.find((x) => x.registration === filters.file);
    navigate(here({ ...listFilters(filters), card: filters.file, file: "" }, "/tails"), { replace: true });
    if (a) void filing.start(a);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filters.file, ready]);

  // a line's address from Today's Orders (/tails?airline=PA#line-12, since 28 Oct): scroll to it once everything is read
  const atLine = useRef("");
  useEffect(() => {
    const id = loc.hash.slice(1);
    if (!ready || !id.startsWith("line-") || atLine.current === id) return;
    atLine.current = id;
    requestAnimationFrame(() => document.getElementById(id)?.scrollIntoView({ block: "start" }));
  }, [ready, loc.hash]);

  const onEdit = (field: TailField, value: string) => {
    if (!open || !rules || !airline) return;
    const res = editTailChange(open, field, value, { rules, configs: configsQ.data ?? [], aircraft: all, airline });
    if ("error" in res) { showMessage(res.error); return; }
    void save(res.changes).then((x) => { if (x.status === "saved" && field === "id") toTail(value.trim().toUpperCase()); });
  };
  const onDelete = async () => {
    if (!open || !rules) return;
    // its rotations and their legs, read fresh with their updated_at
    const rots = await readRotationsWithLegs(roundTrips);
    const res = await save(deleteTailChanges(open, rots, today));
    if (res.status === "saved") navigate("/tails" + filtersQuery({ ...listFilters(filters), card: "", file: "" }));
  };

  // ---------- Add a tail (the old t-add)
  const [form, setForm] = useState({ id: "", type: "", config: "", base: "", acquired: "" });
  const typeList = rules && airline && buyQ.data ? typesFor(rules, buyQ.data, airline.id) : [];
  const cfgList = (type?: string) => (rules && airline && configsQ.data ? configsFor(rules, configsQ.data, airline, type) : []);
  const baseList = rules && airline ? basesOf(rules, airline.id) : [];
  async function addTail() {
    if (!airline || !rules || w === undefined) return;
    const res = addTailChanges(w, airline.id, form, rules, configsQ.data ?? [], all);
    if ("error" in res) { showMessage(res.error); return; }
    if (!res.changes.length) return;
    const x = await save(res.changes);
    if (x.status === "saved") {
      const r = form.id.trim();
      setForm({ id: "", type: "", config: "", base: "", acquired: "" });
      toTail(r);
    }
  }
  const onRemove = (a: TailAircraft) => {
    const res = removeTailChanges(a, flying.has(a.id), today);
    if ("error" in res) { showMessage(res.error); return; }
    setRemoving(a);
  };

  const onFileDelivery = (r: DeliveryRow) => void filing.start(r.a);

  return (
    <main className={"view tails" + (open || reg ? " has-detail" : "")} data-screen="tails" data-tails-ready={ready ? "yes" : "no"}
      data-tails-airline={airline?.code ?? ""} data-tail-open={open?.registration ?? ""} data-tails-view={loc.pathname + loc.search}>
      <div className="vh todayvh tailsvh" data-figure="tails: answer">
        <p className="vk">The network</p>
        <div className="todayttl">
          <h1 className="ansh" data-tails-answer={whole ? (whole.warn ? "look" : "well") : ""}>{answer && ready ? answer.title : "Tails"}</h1>
          {answer && ready ? <span className="pill mute tailspill">{answer.pill}</span> : null}
        </div>
        <p className="ansp">Every aircraft{airline ? ` of ${airline.name}` : ""}: what it flies each week and how hard it works.</p>
      </div>
      {loadError ? <ErrorBox error={loadError} /> : null}
      {airlinesQ.data && !airline ? <ErrorBox error={`There's no airline ${filters.airline} among ours.`} /> : null}
      <div className="toolbar">
        <div className="seg">
          {airlines.map((a) => (
            <button type="button" key={a.id} data-al={a.code ?? ""} className={a.id === airline?.id ? "on" : ""}
              onClick={() => navigate("/tails" + filtersQuery({ airline: a === airlines[0] ? null : a.code, base: "", type: "", status: "", del: "", card: "", file: "" }))}>
              <AirlineMark color={a.color} />{a.name}
            </button>
          ))}
        </div>
        <span className="count" data-figure="tails: count">{mine.length} tails</span>
      </div>
      {counts && ready ? (
        <div className="tiles tailtiles" role="group" aria-label="Flying, no flights, needs a look and deliveries">
          {([["flying", counts.flying, "Flying", "fly at least one leg a week", "ok"], ["idle", counts.idle, "No flights", "nothing scheduled yet", ""],
            ["warn", counts.warn, "Needs a look", "short turn, a leg elsewhere or maintenance", counts.warn ? "bad" : "ok"]] as const).map(([k, n, name, line, cls]) => (
            <button type="button" key={k} className={"tile " + cls + (filters.status === k ? " on" : "")} aria-pressed={filters.status === k} data-tails-tile={k}
              onClick={() => keep({ ...filters, status: filters.status === k ? "" : k })}>
              <b className="tn">{n}</b><span className="tname">{name}</span><span className="tline">{line}</span>
            </button>
          ))}
          <button type="button" className={"tile" + (delCounts.toFile ? " warn" : "")} data-tails-tile="deliveries"
            onClick={() => { keep({ ...filters, del: "" }); requestAnimationFrame(() => document.getElementById("deliveries")?.scrollIntoView({ behavior: "smooth", block: "start" })); }}>
            <b className="tn">{delCounts.onOrder + delCounts.arrived}</b><span className="tname">Deliveries</span>
            <span className="tline">{delCounts.onOrder} on order · {delCounts.arrived} arrived · {delCounts.toFile} to file</span>
          </button>
        </div>
      ) : null}
      <div className="chips" data-chips="tails">
        <span className="chiplbl">Base</span>
        <button type="button" className={"chip" + (!filters.base ? " on" : "")} data-tf="base" data-v="" onClick={() => keep({ ...filters, base: "" })}>All</button>
        {chipLists.bases.map((b) => <button type="button" key={b} className={"chip" + (filters.base === b ? " on" : "")} data-tf="base" data-v={b} onClick={() => keep({ ...filters, base: b })}>{b}</button>)}
        <span className="chiplbl" style={{ marginLeft: 14 }}>Type</span>
        <button type="button" className={"chip" + (!filters.type ? " on" : "")} data-tf="type" data-v="" onClick={() => keep({ ...filters, type: "" })}>All</button>
        {chipLists.types.map((t) => <button type="button" key={t} className={"chip" + (filters.type === t ? " on" : "")} data-tf="type" data-v={t} onClick={() => keep({ ...filters, type: t })}>{t}</button>)}
        <span className="chiplbl" style={{ marginLeft: 14 }}>Status</span>
        {STATUS.map(([k, l]) => <button type="button" key={l} className={"chip" + (filters.status === k ? " on" : "")} data-tf="status" data-v={k} onClick={() => keep({ ...filters, status: k })}>{l}</button>)}
      </div>
      {removing ? (
        <ConfirmPanel question={`Remove ${removing.registration}?`} yes="Remove" busy={busy} onNo={() => setRemoving(null)}
          onYes={() => { const a = removing; setRemoving(null); const res = removeTailChanges(a, flying.has(a.id), today); if ("changes" in res) void save(res.changes).then((x) => { if (x.status === "saved" && open?.id === a.id) navigate("/tails" + filtersQuery({ ...listFilters(filters), card: "", file: "" })); }); }}>
          <div className="dim">It is retired, never deleted: its history stays.</div>
        </ConfirmPanel>
      ) : null}
      <div className="split">
        <div className="list" id="taillist">
          <ChartOrTable k="tails-list" chart={rules && airline ? <TailsChart rows={rows} target={settingNumber(rules, "aircraft_block_target_h", airline.id)} onPick={toTail} /> : null} table={<>
          <table className="tbl tlist" data-figure="tails: list">
            <tbody>
              <tr><th>Tail</th><th>Type</th><th>Cabin</th><th className="num">Legs/wk</th><th className="num">Block h/day</th><th>Maint.</th><th>Routes</th><th></th></tr>
              {rows.map((r) => {
                const names = rules ? routeNames(rules, r.fig.week) : [];
                const rc = routesCell(r.fig.routes, names);
                const unf = unfolded === r.a.registration;
                return (
                  <tr key={r.a.id} className={(open?.id === r.a.id ? "sel" : "") + (unf ? " unf" : "")} data-tail={r.a.registration} role="link" tabIndex={0}
                    onClick={(e) => { if (!(e.target as HTMLElement).closest("button")) toTail(r.a.registration); }}
                    onKeyDown={(e) => { if (e.key === "Enter" && e.target === e.currentTarget) toTail(r.a.registration); }}>
                    <td data-l="Tail" className="treg"><b>{r.a.registration}</b>{r.fig.marked ? <> <span className="dot bad" role="img" aria-label="short turn or a leg elsewhere" /></> : null}
                      <span className="tbase" data-l="Base">{r.base || "—"}</span></td>
                    <td data-l="Type" className="tx">{r.type}</td>
                    <td data-l="Cabin" className="tx">{r.config || <span className="dim">—</span>}</td>
                    <td data-l="Legs/wk" className="num tx">{r.fig.legsWk}</td>
                    <td data-l="Block h/day" className="num tblk">{r.fig.blockDay.toFixed(1)}</td>
                    <td data-l="Maint." className="tmnt"><MaintPill fig={r.fig} shown={r.maint} /></td>
                    <td data-l="Routes" className="tx troutes" data-routes={rc.kind} title={rc.kind === "names" ? rc.text : undefined}>
                      {rc.kind === "none" ? <span className="dim">—</span> : <span className={rc.kind === "names" ? "trl" : "trn"}>{rc.text}</span>}</td>
                    <td className="tact"><button type="button" className="link tunf" aria-expanded={unf} aria-label={unf ? `Fold ${r.a.registration}` : `More about ${r.a.registration}`}
                      onClick={() => setUnfolded(unf ? "" : r.a.registration)}><span className="chev" /></button>
                      <button type="button" className="link" data-deltail={r.a.registration} disabled={busy} onClick={() => onRemove(r.a)}>remove</button></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          {!rows.length ? <div className="empty">{ready ? "No tails match. Clear a filter." : "Loading…"}</div> : null}
          </>} />
          <div className="addform" data-add-tail>
            <b>Add a tail</b>
            <input id="t-id" placeholder="Registration e.g. N015AW" value={form.id} onChange={(e) => setForm({ ...form, id: e.currentTarget.value })} />
            <select id="t-type" value={form.type} onChange={(e) => {
              const type = e.currentTarget.value, list = cfgList(type);
              setForm({ ...form, type, config: list.length === 1 ? list[0] ?? "" : "" });
            }}>
              <option value="">Type</option>{typeList.map((t) => <option key={t} value={t}>{t}</option>)}
            </select>
            <select id="t-cfg" value={form.config} onChange={(e) => setForm({ ...form, config: e.currentTarget.value })}>
              <option value="">Config</option>{cfgList(form.type || undefined).map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
            <select id="t-base" value={form.base} onChange={(e) => setForm({ ...form, base: e.currentTarget.value })}>
              <option value="">Base</option>{baseList.map((b) => <option key={b} value={b}>{b}</option>)}
            </select>
            <select id="t-acq" value={form.acquired} onChange={(e) => setForm({ ...form, acquired: e.currentTarget.value })}
              title="how it came: new from the factory (replaced at 3 years) or used from the market (at 10)">
              <option value="">New or used</option><option value="new">new</option><option value="used">used</option>
            </select>
            <button type="button" className="primary" id="t-add" disabled={busy} onClick={() => void addTail()}>Add</button>
          </div>
        </div>
        <div className="detail" id="detail">
          {open && rules && fig && airline ? (
            <AircraftPage rules={rules} a={open} configs={configs} fig={fig} maint={openRow?.maint ?? null} issues={issues} types={typeList} bases={baseList}
              configsFor={(t) => cfgList(t || undefined)} roundTrips={roundTrips.length} busy={busy}
              onBack={() => navigate("/tails" + filtersQuery({ ...listFilters(filters), card: "", file: "" }))} onEdit={onEdit} onDelete={() => void onDelete()} />
          ) : reg && ready ? (
            <div className="empty" data-no-tail>No aircraft {reg} in service: it may have been removed, or not filed yet.</div>
          ) : reg ? <div className="empty">Loading…</div> : <div className="empty">Pick a tail to see its week.</div>}
        </div>
      </div>
      <Deliveries all={deliveries} shown={shown} airline={airline} filters={filters} open={filters.card} legsOf={legsOf} serviceOf={serviceOf}
        filed={(id) => flying.has(id)} busy={busy || filing.filing} now={now.getTime()}
        onStatus={(s) => keep({ ...filters, del: s })} onCard={(r) => keep({ ...filters, card: filters.card === r ? "" : r })} onFile={onFileDelivery}
        onRemove={(r) => void onRemoveDelivery(r)}
        cabinsFor={(r) => cfgList(r.type)} cabinCode={(c) => (c.config_id == null ? "" : configs.get(c.config_id)?.code ?? "")}
        onCabin={(r, code) => void onCardCabin(r, code)} stations={stations} suggestionOf={suggestionOf} faresOf={faresOf}
        lines={lineViews} onWriteLine={(v, a) => void onWriteLine(v, a)} />
      {filing.state ? <FileCheckModal state={filing.state} busy={busy || filing.filing} onFile={(g) => void filing.file(g)} onClose={filing.close} /> : null}
    </main>
  );
}
