// Tails (decision #18, build pull request 7; spec docs/specs/2026-10-13-tails.md): every aircraft, what it flies each week
// and how hard it works, as the old planner's Tails, from the same data, with the same figures and look:
//   - the list, one airline at a time: filters for base, type and Flying / No flights / Needs a look; each aircraft's legs
//     a week, block hours a day, maintenance (with the hours on hover) and routes; Add a tail; remove;
//   - an aircraft (AircraftPage.tsx): its header, the fields that change it, its week and every issue;
//   - the deliveries board (Deliveries.tsx): aircraft on order, arrived or flying, each with its plan card, and filing an
//     arrived one into the planner after checking it against the game (Filing.tsx).
// Addresses: /planner/next/tails (filters in the address: ?airline=PA&base=JFK&type=...&status=warn&del=on+order&card=REG)
// and /planner/next/tails/<registration>. Home's "File into planner" opens ?file=<registration>, which starts filing at
// once, as the old Home's button did. Each action is one planner_save() call; the start's rules are read again after it.
import { useEffect, useMemo, useRef, useState } from "react";
import { useLocation, useNavigate, useParams } from "react-router";
import { tails as tailRules, type TailIssue } from "@rules";
import { useNow } from "../../data/clock";
import { queryClient } from "../../data/query";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import type { Change } from "../../data/save";
import { saver } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { ConfirmPanel } from "../../ui/Confirm";
import { todayAt } from "../../ui/dates";
import { ErrorBox } from "../../ui/ErrorBox";
import { showMessage } from "../../ui/messages";
import { useAirlineRoutes, useAirports } from "../routes/reads";
import { AircraftPage, MaintPill } from "./AircraftPage";
import { Deliveries } from "./Deliveries";
import { FileCheckModal, useFiling } from "./Filing";
import {
  addTailChanges, basesOf, cardLegs, cardServiceIssues, chips, configsFor, deleteTailChanges, deliveryRows, editTailChange, filtersQuery, flyingIds, parseFilters, removeTailChanges,
  rulesLegs, shownDeliveries, tailRows, tailsOf, typesFor, withAirports, withRoutes, extraIndex, type CardLeg, type DeliveryRow, type Filters, type PlanCardRow, type PlanLegRow,
  type TailAircraft, type TailAirline, type TailField,
} from "./model";
import {
  readRotationsWithLegs, tailsCount, useBuyTypes, useConfigs, useGameHost, useLaunches, useLowCost, usePlanCards, usePlanLegs, useTailsAircraft,
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
  const launchesQ = useLaunches(w);
  const hostQ = useGameHost(w);
  const [busy, setBusy] = useState(false);
  const [removing, setRemoving] = useState<TailAircraft | null>(null);

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
  const cardCodes = useMemo(() => [...new Set((planLegsQ.data ?? []).flatMap((l) => [l.origin_code, l.dest_code]))], [planLegsQ.data]);
  const airportsQ = useAirports(w, cardCodes);
  const rules = useMemo(() => (startRules ? withAirports(startRules, airportsQ.data ?? []) : undefined), [startRules, airportsQ.data]);

  const mine = useMemo(() => tailsOf(all, airline?.id), [all, airline]);
  const rows = useMemo(() => (rules ? tailRows(mine, filters, rules, configs) : []), [mine, filters, rules, configs]);
  const chipLists = useMemo(() => (rules ? chips(mine, rules) : { bases: [], types: [] }), [mine, rules]);
  const flying = useMemo(() => (rules ? flyingIds(rules) : new Set<number>()), [rules]);
  const deliveries = useMemo(() => (rules && cardsQ.data ? deliveryRows(all, airlines, rules, configs, cardsQ.data, now.getTime(), today) : []),
    [all, airlines, rules, configs, cardsQ.data, now, today]);
  const shown = useMemo(() => shownDeliveries(deliveries, airline?.id, filters), [deliveries, airline, filters]);
  // the plan card's service check: the airline's routes laid in, as filing takes a leg's distance from them
  const routesQ = useAirlineRoutes(w, airline?.id);
  const serviceRules = useMemo(() => (rules && routesQ.data ? withRoutes(rules, routesQ.data) : rules), [rules, routesQ.data]);
  const serviceOf = useMemo(() => (card: PlanCardRow, legs: readonly CardLeg[]) => (serviceRules ? cardServiceIssues(serviceRules, card.airline_id, legs) : new Map<number, string>()),
    [serviceRules]);
  const legsOf = useMemo(() => {
    const by = new Map<number, PlanLegRow[]>();
    for (const l of planLegsQ.data ?? []) by.set(l.plan_card_id, [...(by.get(l.plan_card_id) ?? []), l]);
    return (card: PlanCardRow) => (rules ? cardLegs(rules, by.get(card.id) ?? []) : []);
  }, [planLegsQ.data, rules]);

  const fig = useMemo(() => (rules && open ? tailRows([open], { base: "", type: "", status: "" }, rules, configs)[0]?.fig : undefined), [rules, open, configs]);
  const issues: TailIssue[] = useMemo(() => (rules && open && fig?.week ? tailRules.issues(rules, open.id, rulesLegs(rules), fig.week, fig.maint) : []), [rules, open, fig]);
  const roundTrips = useMemo(() => {
    if (!rules || !open) return [];
    const ids = new Set<number>();
    for (const l of rules.legs) if (l.rotation_id != null && l.aircraft_id === open.id) ids.add(l.rotation_id);
    return [...ids];
  }, [rules, open]);

  const ready = !!(rules && aircraftQ.data && configsQ.data && buyQ.data && cardsQ.data && planLegsQ.data && launchesQ.data && airlinesQ.data && lowCostQ.data
    && (!cardCodes.length || airportsQ.data));
  const loadError = firstError(world, airlinesQ, lowCostQ, rulesQ, aircraftQ, configsQ, buyQ, cardsQ, planLegsQ, launchesQ, airportsQ);

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
  const [form, setForm] = useState({ id: "", type: "", config: "", base: "" });
  const typeList = rules && airline && buyQ.data ? typesFor(rules, buyQ.data, airline.id) : [];
  const cfgList = (type?: string) => (rules && airline && configsQ.data ? configsFor(rules, configsQ.data, airline, type) : []);
  const baseList = rules && airline ? basesOf(rules, airline.id) : [];
  async function addTail() {
    if (!airline || !rules || w === undefined) return;
    // its place at the end of the old planner's list of tails, counted fresh
    const count = await tailsCount(w).catch(() => all.filter((a) => extraIndex(a, "tails_index") != null).length);
    const res = addTailChanges(w, airline.id, form, rules, configsQ.data ?? [], all, count);
    if ("error" in res) { showMessage(res.error); return; }
    if (!res.changes.length) return;
    const x = await save(res.changes);
    if (x.status === "saved") {
      const r = form.id.trim();
      setForm({ id: "", type: "", config: "", base: "" });
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
      <div className="vh"><h1>Tails</h1><p>Every aircraft — what it flies each week and how hard it works.</p></div>
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
          <table className="tbl tlist" data-figure="tails: list">
            <tbody>
              <tr><th>Tail</th><th>Type</th><th>Config</th><th>Base</th><th>Legs/wk</th><th>Block h/day</th><th>Maint.</th><th>Routes</th><th></th></tr>
              {rows.map((r) => (
                <tr key={r.a.id} className={open?.id === r.a.id ? "sel" : ""} data-tail={r.a.registration} role="link" tabIndex={0} onClick={(e) => { if (!(e.target as HTMLElement).closest("button")) toTail(r.a.registration); }}
                  onKeyDown={(e) => { if (e.key === "Enter") toTail(r.a.registration); }}>
                  <td data-l="Tail"><b>{r.a.registration}</b>{r.fig.marked ? <> <span className="dot bad" /></> : null}</td>
                  <td data-l="Type">{r.type}</td>
                  <td data-l="Config">{r.config}</td>
                  <td data-l="Base">{r.base}</td>
                  <td data-l="Legs/wk">{r.fig.legsWk}</td>
                  <td data-l="Block h/day">{r.fig.blockDay.toFixed(1)}</td>
                  <td data-l="Maint."><MaintPill fig={r.fig} /></td>
                  <td data-l="Routes">{r.fig.routes}</td>
                  <td><button type="button" className="link" data-deltail={r.a.registration} disabled={busy} onClick={() => onRemove(r.a)}>remove</button></td>
                </tr>
              ))}
            </tbody>
          </table>
          {!rows.length ? <div className="empty">{ready ? "No tails match. Clear a filter." : "Loading…"}</div> : null}
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
            <button type="button" className="primary" id="t-add" disabled={busy} onClick={() => void addTail()}>Add</button>
          </div>
        </div>
        <div className="detail" id="detail">
          {open && rules && fig && airline ? (
            <AircraftPage rules={rules} a={open} configs={configs} fig={fig} issues={issues} types={typeList} bases={baseList}
              configsFor={(t) => cfgList(t || undefined)} roundTrips={roundTrips.length} busy={busy}
              onBack={() => navigate("/tails" + filtersQuery({ ...listFilters(filters), card: "", file: "" }))} onEdit={onEdit} onDelete={() => void onDelete()} />
          ) : reg && ready ? (
            <div className="empty" data-no-tail>No aircraft {reg} in service: it may have been removed, or not filed yet.</div>
          ) : reg ? <div className="empty">Loading…</div> : <div className="empty">Pick a tail to see its week.</div>}
        </div>
      </div>
      <Deliveries all={deliveries} shown={shown} airline={airline} filters={filters} open={filters.card} legsOf={legsOf} serviceOf={serviceOf}
        filed={(id) => flying.has(id)} busy={busy || filing.filing} now={now.getTime()}
        onStatus={(s) => keep({ ...filters, del: s })} onCard={(r) => keep({ ...filters, card: filters.card === r ? "" : r })} onFile={onFileDelivery} />
      {filing.state ? <FileCheckModal state={filing.state} busy={busy || filing.filing} onFile={(g) => void filing.file(g)} onClose={filing.close} /> : null}
    </main>
  );
}
