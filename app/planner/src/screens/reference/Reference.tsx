// Reference (decision #18, build pull request 12; spec docs/specs/2026-10-14-interline-photos-reference.md): every section
// of the old planner's Reference (renderRef and renderRefRaw), folding as the old one does (all folded until opened; the
// open one in the address, /planner/reference/<section>), with the same words and look:
//   hubs, focus cities and banks; constants; aircraft (with each type's order cabin and, since 15 Oct, an airline's own
//   where it differs: spec docs/specs/2026-10-15-last-leftovers.md §1); configs; market defaults; service profiles;
//   removed routes with restore and restore all; night bans; game schedules; time zones; storage; data.
// Every edit is one planner_save() call writing exactly the rows the old planner's adapter wrote for it (model.ts says
// which); a constant is its setting's row (or the departures cap's world rule), and the section says the manual changes
// with it (manual §1). A time zone moves every flight touching the airport in UTC so its local times stay, as Routes'
// offset does (after the page lists what moves and asks). Import and clear went with the tables (design §14, choice 2);
// the exports stay. The bank windows and next free numbers are the planning library's, on the start's rules input.
import { useMemo, useState, type KeyboardEvent, type ReactNode } from "react";
import { useLocation, useNavigate, useParams } from "react-router";
import { banks, schedule, type Rules } from "@rules";
import { queryClient } from "../../data/query";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import type { Change } from "../../data/save";
import { saver, useSaveState } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { ConfirmPanel } from "../../ui/Confirm";
import { ErrorBox } from "../../ui/ErrorBox";
import { showMessage } from "../../ui/messages";
import { legsAt, readAirports } from "../routes/reads";
import { moveWords, offsetChanges, parseOffset, type OffsetMove } from "../routes/model";
import { useGameHost } from "../tails/reads";
import { download, flightsCsv, tablesJson } from "./csv";
import {
  CONSTANTS, SECTIONS, addConfig, addOwnOrder, addService, addType, banSet, banText, bankBoxes, baseChange, basesInOrder, canAddBan, configChange,
  constantChange, constantValue, keyOrder, layoutsOf, marketChange, mctChange, mctHours, orderCabinChange, ownOrderChange, pageId, removeOwnOrder, removeRow,
  removedWords, restoreChange, scheduleLink, sectionOf, serviceChange, typeChange, worldRowChange, type BaseField, type BaseRow, type ConfigField,
  type ConfigRow, type MarketField, type SectionSlug, type ServiceField, type TypeField,
} from "./model";
import {
  stillUsed, useBases, useCities, useConfigs, useCounts, useMarkets, useOwnOrders, useRemoved, useServices, useSettings, useSiteMct, useTypes,
  useWorldAirports, useWorldRules,
} from "./reads";

const H = (m: number) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
const enter = (e: KeyboardEvent<HTMLInputElement>) => { if (e.key === "Enter") e.currentTarget.blur(); };

/** A box that saves when you leave it (or press Enter), as the old planner's change event; it starts again from the value
 *  saved whenever that changes. */
function Box({ value, onSave, ...rest }: { value: string; onSave: (typed: string) => void } & Omit<React.InputHTMLAttributes<HTMLInputElement>, "value" | "defaultValue" | "onBlur">) {
  return <input key={value} defaultValue={value} {...rest} onKeyDown={enter} onBlur={(e) => { if (e.currentTarget.value !== value) onSave(e.currentTarget.value); }} />;
}
function Opt({ list, value, empty }: { list: readonly string[]; value: string; empty?: string }) {
  return <>{empty != null ? <option value="">{empty}</option> : null}{list.map((v, i) => <option key={v + i} value={v}>{v}</option>)}{list.includes(value) || value === "" ? null : <option value={value}>{value}</option>}</>;
}
/** An order-cabin box's choices: none ("—"), then the type's own layouts by code (each layout's id as its value). */
function Layouts({ configs, typeId }: { configs: readonly ConfigRow[]; typeId: number }) {
  return <><option value="">—</option>{layoutsOf(configs, typeId).map((c) => <option key={c.id} value={String(c.id)}>{c.code}</option>)}</>;
}

export function Reference() {
  const params = useParams();
  const loc = useLocation();
  const navigate = useNavigate();
  const addressed = sectionOf(params["*"]);
  const [open, setOpen] = useState<ReadonlySet<SectionSlug>>(() => new Set(addressed ? [addressed] : []));
  const [seen, setSeen] = useState(addressed);
  if (addressed !== seen) {   // a new address opens its section (React's "adjust state while rendering")
    setSeen(addressed);
    if (addressed && !open.has(addressed)) setOpen(new Set([...open, addressed]));
  }
  const toggle = (slug: SectionSlug, now: boolean) => {
    if (now === open.has(slug)) return;
    const n = new Set(open);
    if (now) n.add(slug); else n.delete(slug);
    setOpen(n);
    if (now) navigate("/reference/" + slug, { replace: true });
    else if (addressed === slug) navigate("/reference", { replace: true });
  };

  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const rulesQ = useRules(w);
  const basesQ = useBases(w);
  const waQ = useWorldAirports(w);
  const settingsQ = useSettings(w);
  const wrQ = useWorldRules(w);
  const typesQ = useTypes(w);
  const configsQ = useConfigs(w);
  const marketsQ = useMarkets(w);
  const servicesQ = useServices(w);
  const removedQ = useRemoved(w);
  const ownQ = useOwnOrders(w);
  const siteQ = useSiteMct();
  const countsQ = useCounts(w);
  const hostQ = useGameHost(w);
  const save_ = useSaveState();
  const [busy, setBusy] = useState(false);
  const [mkAl, setMkAl] = useState("");
  const [cfq, setCfq] = useState("");
  const [cfAdd, setCfAdd] = useState({ code: "", val: "" });
  const [utc, setUtc] = useState({ code: "", val: "" });
  const [ownAdd, setOwnAdd] = useState({ airline: "", type: "" });
  const [offset, setOffset] = useState<{ code: string; question: string; moves: OffsetMove[]; apply: () => Promise<void> } | null>(null);

  const rules = rulesQ.data?.rules;
  const airlines = useMemo(() => (airlinesQ.data ?? []).map((a) => ({ id: a.id, code: a.iata_code, game_id: a.game_id, color: a.livery_color,
    name: a.planner_name ?? a.public_name ?? a.game_name ?? `Airline ${a.game_id}` })), [airlinesQ.data]);
  const nameOf = (id: number | null) => (id == null ? "" : airlines.find((a) => a.id === id)?.name ?? "");
  const bases = useMemo(() => basesInOrder(basesQ.data ?? []), [basesQ.data]);
  const wa = useMemo(() => new Map((waQ.data ?? []).map((r) => [r.airport_code, r])), [waQ.data]);
  const bans = useMemo(() => (waQ.data ?? []).filter((r) => r.night_ban_from && r.night_ban_to).sort((a, b) => (a.airport_code < b.airport_code ? -1 : 1)), [waQ.data]);
  const citiesQ = useCities(bans.map((b) => b.airport_code));
  const site = siteQ.data ?? {};
  const types = typesQ.data ?? [];
  const configs = configsQ.data ?? [];

  async function save(changes: (Change | null)[], opts: { rules?: boolean } = {}) {
    const list = changes.filter((c): c is Change => c != null);
    if (!list.length) return;
    setBusy(true);
    try {
      const res = await saver.save(list);
      if (res.status === "saved" && opts.rules !== false) void queryClient.invalidateQueries({ queryKey: ["rules"] });
    } finally {
      setBusy(false);
    }
  }
  const saveOne = (c: Change | null | { error: string }) => {
    if (c && "error" in c) { showMessage(c.error); return; }
    void save([c]);
  };
  async function remove(table: "aircraft_types" | "cabin_configs" | "markets" | "service_profiles", row: { id: number; updated_at: string }, name: string) {
    if (w === undefined) return;
    if (table !== "service_profiles") {
      const used = await stillUsed(w, table, row.id);
      if (used) { showMessage(`${name} is still used by ${used}, so it stays.`); return; }
    }
    await save([removeRow(table, row)]);
  }
  async function askOffset() {
    if (!rules || w === undefined) return;
    const code = utc.code.trim().toUpperCase();
    if (!code) return;
    const v = parseOffset(utc.val);
    if (v === "bad") { showMessage(`An offset is hours from UTC, such as 5.5 or -5 (${utc.val} isn't)`); return; }
    const [a] = await readAirports(w, [code]);
    if (!a) { showMessage(`No airport ${code}`); return; }
    const before = a.correction ?? a.utc_offset ?? 0;
    const hours = v ?? a.utc_offset ?? 0;
    if (v === a.correction && hours === before) return;
    const { legs, planLegs } = await legsAt(w, code);
    const markets = new Map((marketsQ.data ?? []).map((m) => [m.id, m]));
    const rots = [...new Set(legs.map((l) => l.rotation_id))].map((id) => {
      const l1 = legs.find((l) => l.rotation_id === id && l.leg_no === 1), l2 = legs.find((l) => l.rotation_id === id && l.leg_no === 2);
      const rot = rules.rotations.get(id), rr = rot ? rules.routes.get(rot.route_id) : undefined;
      const ac = l1?.aircraft_id ?? l2?.aircraft_id;
      const type = ac == null ? undefined : rules.aircraft.get(ac)?.aircraft_type_id ?? undefined;
      const mk = rr?.market_id == null ? undefined : markets.get(rr.market_id);
      return { rotation_id: id, leg1: l1, leg2: l2,
        ends: { airline_id: (l1 ?? l2)?.airline_id ?? 0, hub: l1?.origin_code ?? l2?.dest_code ?? "", dest: l1?.dest_code ?? l2?.origin_code ?? "",
          distance_km: rr?.distance_km ?? null, type_id: type ?? mk?.default_type_id ?? null } };
    });
    const plan = offsetChanges(rules, w, a, v, { rotations: rots, planLegs });
    const n = plan.moves.length;
    setOffset({
      code, moves: plan.moves,
      question: `Change ${code}'s UTC offset from ${before} to ${hours}${v == null ? " (the game's)" : ""}? The planner keeps local times there, so ${n ? `${n} leg${n === 1 ? "" : "s"} move${n === 1 ? "s" : ""} in UTC` : "nothing moves"}.`,
      apply: async () => { await save(plan.changes); void queryClient.invalidateQueries({ queryKey: ["table", "world_airports"] }); },
    });
  }

  const loadError = world.error ?? airlinesQ.error ?? rulesQ.error ?? basesQ.error ?? waQ.error ?? settingsQ.error ?? wrQ.error ?? typesQ.error ?? configsQ.error
    ?? marketsQ.error ?? servicesQ.error ?? removedQ.error ?? ownQ.error ?? siteQ.error ?? countsQ.error ?? hostQ.error ?? citiesQ.error;
  const ready = !!(rules && airlinesQ.data && basesQ.data && waQ.data && settingsQ.data && wrQ.data && typesQ.data && configsQ.data && marketsQ.data
    && servicesQ.data && removedQ.data && ownQ.data && siteQ.data && countsQ.data && hostQ.isFetched && (!bans.length || citiesQ.data));
  const own = ownQ.data ?? [];
  const isBase = (code: string) => bases.some((b) => b.airport_code === code);
  const removed = (removedQ.data ?? []).map((r) => ({ r, key: `${nameOf(r.airline_id)}|${r.hub_code}|${r.dest_code}` })).sort((a, b) => keyOrder(a.key, b.key));
  const markets = (marketsQ.data ?? []).map((m) => ({ m, key: `${nameOf(m.airline_id)}|${m.name}` })).sort((a, b) => keyOrder(a.key, b.key));
  const overrides = (waQ.data ?? []).filter((r) => r.utc_offset_override != null).sort((a, b) => keyOrder(a.airport_code, b.airport_code));

  const section = (slug: SectionSlug, title: ReactNode, note: ReactNode, body: ReactNode, key = String(title)) => (
    <details className="rsec" data-rsec={key} data-section={slug} key={slug} open={open.has(slug)} onToggle={(e) => toggle(slug, e.currentTarget.open)}>
      <summary><span className="rst">{title}</span>{note ? <span className="note">{note}</span> : null}</summary>
      <div className="rsb">{body}</div>
    </details>
  );

  return (
    <main className="view ref-view" data-screen="reference" data-reference-ready={ready ? "yes" : "no"} data-reference-view={loc.pathname} data-open={[...open].join(" ")}>
      <div className="vh"><h1>Reference</h1><p>Banks, aircraft, configs, markets and time zones.</p></div>
      {loadError ? <ErrorBox error={loadError} /> : null}
      {!ready && !loadError ? <div className="empty">Loading…</div> : null}
      {offset ? (
        <ConfirmPanel question={offset.question} yes="Change it" busy={busy} onYes={() => { const o = offset; setOffset(null); void o.apply(); }} onNo={() => setOffset(null)}>
          {offset.moves.length ? <ul data-offset-moves>{offset.moves.map((m, i) => <li key={i}>{moveWords(m, airlines.find((a) => a.id === m.airline_id)?.code ?? null)}</li>)}</ul>
            : <div className="dim">No flight touches {offset.code}, so nothing moves.</div>}
        </ConfirmPanel>
      ) : null}
      {ready && rules ? (
        <div className="ref">
          {section("hubs", SECTIONS[0][1], "a hub runs banks and connections · a focus city is an aircraft base that serves its own market point-to-point and feeds a hub with trunk flights, so it has no banks of its own · departure times, hub local · MCT in hours · \"last no. used\" = highest flight number already taken in the game, including anything not entered here",
            <HubsTable rules={rules} bases={bases} nameOf={nameOf} wa={wa} busy={busy}
              onField={(b, f, v) => saveOne(baseChange(b, f, v, bases))}
              onMct={(b, v) => w !== undefined && saveOne(mctChange(w, b, v, bases, wa.get(b.airport_code), site))} />)}
          {section("constants", "Constants", null, (
            <>
              <div className="fg" data-figure="reference: constants">
                {CONSTANTS.map(([k, label, key]) => (
                  <label key={k}>{label}<Box data-ref={"consts." + k} value={constantValue(key, settingsQ.data ?? [], wrQ.data ?? [])} disabled={busy}
                    onSave={(v) => saveOne(constantChange(key, v, settingsQ.data ?? [], wrQ.data ?? []))} /></label>
                ))}
              </div>
              <div className="note">These are rule numbers: each is its row in settings (the departures cap in world_rules). Change the operating manual with them (manual §1: rule changes are agreed in chat and the manual updated).</div>
            </>
          ))}
          {section("aircraft", "Aircraft", "block estimates are the block allowance plus the distance at the type's cruise speed (manual §4); nothing is fitted to the times typed · the order cabin is the layout a new order of the type comes with (Tails, the cash forecast)",
            <>
              <div className="tblwrap">
                <table className="tbl edit" data-figure="reference: aircraft">
                  <tbody>
                    <tr><th>Type</th><th>Family</th><th>Max seats</th><th>Cruise km/h (fallback)</th><th>Min turn (min)</th><th>Gap target (h)</th><th>Order cabin</th><th>Learned from your schedule</th><th></th></tr>
                    {types.map((t, i) => (
                      <tr key={t.id}>
                        {([["name", t.name], ["family", t.family_no], ["seats", t.seats_max], ["cruise", t.cruise_kmh], ["minTurn", t.min_turn_min], ["gap", t.gap_target_h]] as [TypeField, unknown][]).map(([f, v]) => (
                          <td key={f}><Box data-ref={`types.${i}.${f}`} value={v == null ? "" : String(v)} disabled={busy} onSave={(x) => saveOne(typeChange(t, f, x))} /></td>
                        ))}
                        <td><select data-ref={`types.${i}.orderCabin`} value={t.order_config_id == null ? "" : String(t.order_config_id)} disabled={busy}
                          onChange={(e) => saveOne(orderCabinChange(t, e.currentTarget.value, configs))}><Layouts configs={configs} typeId={t.id} /></select></td>
                        <td className="dim">{t.cruise_kmh ? `${t.cruise_kmh} km/h + ${constantValue("block_allowance_min", settingsQ.data ?? [], [])} min · the library's estimate` : ""}</td>
                        <td><button type="button" className="link" data-rm={`types.${i}`} disabled={busy} onClick={() => void remove("aircraft_types", t, t.name)}>remove</button></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <button type="button" className="secondary" data-addrow="types" disabled={busy || w === undefined} onClick={() => w !== undefined && void save([addType(w)])}>Add type</button>
              <h4 className="rh" style={{ margin: "18px 0 6px" }}>An airline's own order cabin</h4>
              <div className="note">Where an airline's orders of a type come with another layout than the type's (Ryanair's Standard cabins, as a low-cost airline). Remove one and the airline takes the type's again.</div>
              <div className="tblwrap">
                <table className="tbl edit" data-figure="reference: own order cabins">
                  <tbody>
                    <tr><th>Airline</th><th>Type</th><th>Order cabin</th><th></th></tr>
                    {own.map((o) => {
                      const t = types.find((x) => x.id === o.aircraft_type_id);
                      const key = `${o.airline_id}.${o.aircraft_type_id}`;
                      return (
                        <tr key={key}>
                          <td>{nameOf(o.airline_id) || `Airline ${o.airline_id}`}</td>
                          <td>{t?.name ?? `Type ${o.aircraft_type_id}`}</td>
                          <td><select data-own={key} value={o.order_config_id == null ? "" : String(o.order_config_id)} disabled={busy}
                            onChange={(e) => saveOne(ownOrderChange(o, e.currentTarget.value, configs))}><Layouts configs={configs} typeId={o.aircraft_type_id} /></select></td>
                          <td><button type="button" className="link" data-own-rm={key} disabled={busy} onClick={() => void save([removeOwnOrder(o)])}>remove</button></td>
                        </tr>
                      );
                    })}
                    {own.length ? null : <tr><td colSpan={4} className="dim">None: every airline's orders come with the type's.</td></tr>}
                  </tbody>
                </table>
              </div>
              <div className="fg">
                <label>Airline<select id="own-airline" value={ownAdd.airline} onChange={(e) => setOwnAdd({ ...ownAdd, airline: e.currentTarget.value })}>
                  <option value="">—</option>{airlines.map((a) => <option key={a.id} value={String(a.id)}>{a.name}</option>)}</select></label>
                <label>Type<select id="own-type" value={ownAdd.type} onChange={(e) => setOwnAdd({ ...ownAdd, type: e.currentTarget.value })}>
                  <option value="">—</option>{types.map((t) => <option key={t.id} value={String(t.id)}>{t.name}</option>)}</select></label>
                <button type="button" className="secondary" id="own-add" disabled={busy || w === undefined || !ownAdd.airline || !ownAdd.type} onClick={() => {
                  const t = types.find((x) => String(x.id) === ownAdd.type);
                  if (w === undefined || !t) return;
                  const c = addOwnOrder(w, Number(ownAdd.airline), t, own);
                  if (!c) { showMessage(`${nameOf(Number(ownAdd.airline))} has its own order cabin for ${t.name} already.`); return; }
                  void save([c]);
                  setOwnAdd({ airline: "", type: "" });
                }}>Add</button>
              </div>
            </>)}
          {section("configs", "Configs", "seats follow the config",
            <>
              <div className="tblwrap">
                <table className="tbl edit" data-figure="reference: configs">
                  <tbody>
                    <tr><th>Config</th><th>Type</th><th>Cabin</th><th>Seats</th><th></th></tr>
                    {configs.map((c, i) => {
                      const tn = types.find((t) => t.id === c.aircraft_type_id)?.name ?? "";
                      const field = (f: ConfigField, v: string) => saveOne(configChange(c, f, v, types));
                      return (
                        <tr key={c.id}>
                          <td><Box data-ref={`configs.${i}.code`} value={c.code} disabled={busy} onSave={(v) => field("code", v)} /></td>
                          <td><select data-ref={`configs.${i}.type`} value={tn} disabled={busy} onChange={(e) => field("type", e.currentTarget.value)}><Opt list={types.map((t) => t.name)} value={tn} empty="—" /></select></td>
                          <td><Box data-ref={`configs.${i}.cabin`} value={c.cabin ?? ""} disabled={busy} onSave={(v) => field("cabin", v)} /></td>
                          <td><Box data-ref={`configs.${i}.seats`} value={c.seats == null ? "" : String(c.seats)} disabled={busy} onSave={(v) => field("seats", v)} /></td>
                          <td><button type="button" className="link" data-rm={`configs.${i}`} disabled={busy} onClick={() => void remove("cabin_configs", c, c.code)}>remove</button></td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
              <button type="button" className="secondary" data-addrow="configs" disabled={busy || w === undefined} onClick={() => w !== undefined && void save([addConfig(w)])}>Add config</button>
            </>)}
          {section("markets", "Market defaults", "what a new frequency starts with",
            <>
              <div className="chips" data-chips="markets">
                <span className="chiplbl">Airline</span>
                <button type="button" className={"chip" + (!mkAl ? " on" : "")} data-mkal="" onClick={() => setMkAl("")}>All</button>
                {airlines.map((a) => <button type="button" key={a.id} className={"chip" + (mkAl === a.name ? " on" : "")} data-mkal={a.name} onClick={() => setMkAl(a.name)}><AirlineMark color={a.color} />{a.name}</button>)}
              </div>
              <div className="tblwrap">
                <table className="tbl edit" data-figure="reference: markets">
                  <tbody>
                    <tr><th>Airline</th><th>Market</th><th>Aircraft</th><th>Config</th><th>Price Y</th><th>Price J</th><th></th></tr>
                    {markets.filter((x) => !mkAl || nameOf(x.m.airline_id) === mkAl).map(({ m, key }) => {
                      const tn = types.find((t) => t.id === m.default_type_id)?.name ?? "", cc = configs.find((c) => c.id === m.default_config_id)?.code ?? "";
                      const field = (f: MarketField, v: string) => saveOne(marketChange(m, f, v, types, configs));
                      return (
                        <tr key={m.id}>
                          <td>{nameOf(m.airline_id)}</td><td>{m.name}</td>
                          <td><select data-mk={key + ".aircraft"} value={tn} disabled={busy} onChange={(e) => field("aircraft", e.currentTarget.value)}><Opt list={types.map((t) => t.name)} value={tn} empty="—" /></select></td>
                          <td><select data-mk={key + ".config"} value={cc} disabled={busy} onChange={(e) => field("config", e.currentTarget.value)}><Opt list={configs.map((c) => c.code)} value={cc} empty="—" /></select></td>
                          <td><Box data-mk={key + ".priceY"} value={m.fare_y_pct == null ? "" : String(m.fare_y_pct)} disabled={busy} onSave={(v) => field("priceY", v)} /></td>
                          <td><Box data-mk={key + ".priceJ"} value={m.fare_j_pct == null ? "" : String(m.fare_j_pct)} disabled={busy} onSave={(v) => field("priceJ", v)} /></td>
                          <td><button type="button" className="link" data-rmmk={key} disabled={busy} onClick={() => void remove("markets", m, `${nameOf(m.airline_id)}'s ${m.name}`)}>remove</button></td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </>)}
          {section("services", "Service profiles", "a new frequency starts with the first profile whose \"up to km\" exceeds the route distance; Ryanair uses its own row",
            <>
              <div className="tblwrap">
                <table className="tbl edit" data-figure="reference: services">
                  <tbody>
                    <tr><th>Code</th><th>Airline</th><th>Up to km</th><th>Note</th><th></th></tr>
                    {(servicesQ.data ?? []).map((s, i) => {
                      const al = s.airline_id == null ? "Legacy" : nameOf(s.airline_id);
                      const field = (f: ServiceField, v: string) => saveOne(serviceChange(s, f, v, (n) => airlines.find((a) => a.name === n)?.id ?? null));
                      return (
                        <tr key={s.id}>
                          <td><Box data-ref={`services.${i}.code`} value={s.code} disabled={busy} onSave={(v) => field("code", v)} /></td>
                          <td><select data-ref={`services.${i}.airline`} value={al} disabled={busy} onChange={(e) => field("airline", e.currentTarget.value)}><Opt list={["Legacy", ...airlines.map((a) => a.name)]} value={al} /></select></td>
                          <td><Box data-ref={`services.${i}.upTo`} value={s.up_to_km == null ? "" : String(s.up_to_km)} disabled={busy} onSave={(v) => field("upTo", v)} /></td>
                          <td><Box data-ref={`services.${i}.note`} value={s.note ?? ""} disabled={busy} onSave={(v) => field("note", v)} /></td>
                          <td><button type="button" className="link" data-rm={`services.${i}`} disabled={busy} onClick={() => void remove("service_profiles", s, s.code)}>remove</button></td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
              <button type="button" className="secondary" data-addrow="services" disabled={busy || w === undefined} onClick={() => w !== undefined && void save([addService(w)])}>Add profile</button>
            </>)}
          {removed.length ? section("removed", <>Removed routes <button type="button" className="link" id="restore-all" disabled={busy}
            onClick={(e) => { e.preventDefault(); e.stopPropagation(); void save(removed.map((x) => restoreChange(x.r))); }}>restore all {removed.length}</button></>, null,
            <div className="dim" data-figure="reference: removed routes">
              {removed.map(({ r, key }, i) => <span key={r.id}>{i ? " · " : null}{removedWords(nameOf(r.airline_id), r)} <button type="button" className="link" data-restore={key} disabled={busy}
                onClick={() => void save([restoreChange(r)])}>restore</button></span>)}
            </div>, `Removed routes restore all ${removed.length}`) : null}
          {section("night-bans", "Night bans", "airports that close overnight in the game (read from each airport's page) — flights landing or leaving inside a ban are flagged on their route",
            <>
              <div className="fg"><label>Find<input id="cf-q" value={cfq} placeholder="airport or city" onChange={(e) => setCfq(e.currentTarget.value.trim().toUpperCase())} /></label></div>
              <div className="tblwrap">
                <table className="tbl edit" data-figure="reference: night bans">
                  <tbody>
                    <tr><th style={{ width: 120 }}>Airport</th><th style={{ width: 180 }}>Closed (local)</th><th></th></tr>
                    {bans.filter((b) => !cfq || b.airport_code.includes(cfq) || (citiesQ.data?.get(b.airport_code) ?? "").toUpperCase().includes(cfq)).map((b) => {
                      const set = (typed: string) => {
                        if (w === undefined) return;
                        saveOne(worldRowChange(w, b.airport_code, b, banSet(typed), isBase(b.airport_code), site));
                      };
                      return (
                        <tr key={b.airport_code}>
                          <td><b>{b.airport_code}</b> <span className="dim">{citiesQ.data?.get(b.airport_code) ?? ""}</span></td>
                          <td><Box data-cf={b.airport_code} value={banText(b)} placeholder="00:01-05:59" disabled={busy} onSave={set} /></td>
                          <td><button type="button" className="link" data-cfdel={b.airport_code} disabled={busy} onClick={() => set("")}>remove</button></td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
              <div className="fg">
                <label>Airport<input id="cf-code" maxLength={3} placeholder="e.g. ZRH" value={cfAdd.code} onChange={(e) => setCfAdd({ ...cfAdd, code: e.currentTarget.value })} /></label>
                <label>Closed (local)<input id="cf-val" placeholder="00:01-05:59" value={cfAdd.val} onChange={(e) => setCfAdd({ ...cfAdd, val: e.currentTarget.value })} /></label>
                <button type="button" className="secondary" id="cf-add" disabled={busy} onClick={() => {
                  const code = cfAdd.code.trim().toUpperCase();
                  if (w === undefined || !canAddBan(code, cfAdd.val)) return;
                  saveOne(worldRowChange(w, code, wa.get(code), banSet(cfAdd.val), isBase(code), site));
                  setCfAdd({ code: "", val: "" });
                }}>Add</button>
              </div>
            </>)}
          {section("schedules", "Game schedules", "each airline's public flight-schedule page in the game — used by Check → Game check",
            <div className="tblwrap">
              <table className="tbl edit" data-figure="reference: game schedules">
                <tbody>
                  <tr><th style={{ width: 220 }}>Airline</th><th>Schedule link</th><th style={{ width: 90 }}>Page id</th></tr>
                  {airlines.map((a) => {
                    const link = scheduleLink(hostQ.data ?? null, a.game_id);
                    return (
                      <tr key={a.id}>
                        <td><AirlineMark color={a.color} /> <b>{a.name}</b></td>
                        <td><input data-gl={a.name} value={link} readOnly title="Worked out from the airline's game ID (airlines.game_id)" /></td>
                        <td className="dim">{pageId(link) || "—"}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>)}
          {section("time-zones", "Time zones", "the game runs on standard time all year — no daylight saving — and these offsets match it (verified against the live schedules); override an airport only if the game disagrees",
            <>
              <div className="fg">
                <label>Airport<input id="utc-code" placeholder="e.g. JFK" maxLength={3} value={utc.code} onChange={(e) => setUtc({ ...utc, code: e.currentTarget.value })} /></label>
                <label>UTC offset<input id="utc-val" placeholder="-4" value={utc.val} onChange={(e) => setUtc({ ...utc, val: e.currentTarget.value })} /></label>
                <button type="button" className="secondary" id="utc-set" disabled={busy} onClick={() => void askOffset()}>Set</button>
              </div>
              <div className="dim" data-figure="reference: time zones">{overrides.map((r) => `${r.airport_code} ${Number(r.utc_offset_override)}`).join(" · ") || "No overrides."}</div>
            </>)}
          {section("storage", "Storage", null,
            <div id="diag">
              <div className="dim" data-figure="reference: storage">Cloud store: <b>{save_.label}</b> (each change saves as you make it) · This device: <b>nothing kept</b> (design §14) · {countsQ.data?.freqs ?? 0} frequencies, {countsQ.data?.tails ?? 0} tails, {countsQ.data?.edits ?? 0} route edits, {(marketsQ.data ?? []).length} markets, {(servicesQ.data ?? []).length} service profiles</div>
              <button type="button" className="secondary" id="save-now" onClick={() => void saver.retry()}>Save now</button>
            </div>)}
          {section("data", "Data", null,
            <>
              <div className="fg">
                <button type="button" className="secondary" id="exp" onClick={() => { if (w !== undefined) void tablesJson(w).then((t) => download(t, "equinox-planner-tables.json", "application/json")).catch((e: unknown) => showMessage(String(e))); }}>Export backup (JSON)</button>
                <button type="button" className="secondary" id="expcsv" onClick={() => { if (w !== undefined) void flightsCsv(rules, w, new Map(airlines.map((a) => [a.id, a.name]))).then((t) => download(t, "gander-flights.csv", "text/csv")).catch((e: unknown) => showMessage(String(e))); }}>Export flights (CSV)</button>
              </div>
              <div className="note">The backup is every planner table for the world. Importing a backup and clearing everything went with the tables (design §14, choice 2): the nightly backup and the change log are the safety net.</div>
            </>)}
        </div>
      ) : null}
    </main>
  );
}

function HubsTable({ rules, bases, nameOf, wa, busy, onField, onMct }: {
  rules: Rules; bases: readonly BaseRow[]; nameOf: (id: number) => string; wa: ReadonlyMap<string, { mct_min: number | null }>; busy: boolean;
  onField: (b: BaseRow, f: BaseField, v: string) => void; onMct: (b: BaseRow, v: string) => void;
}) {
  return (
    <div className="tblwrap">
      <table className="tbl edit" data-figure="reference: hubs">
        <tbody>
          <tr><th>Base</th><th>Airline</th><th>Role</th><th>Feeds</th><th>Block</th><th>Last no. used</th><th>Next pair</th><th>MCT</th><th>Bank 1</th><th>Bank 2</th><th>Bank 3</th><th>Bank 4</th><th>Arrival windows</th></tr>
          {bases.map((hb, i) => {
            const rb = rules.bases.find((x) => x.id === hb.id);
            const fc = hb.role === "focus";
            const parents = bases.filter((x) => x.airline_id === hb.airline_id && x.airport_code !== hb.airport_code && x.role !== "focus").map((x) => x.airport_code);
            const parent = bases.find((x) => x.id === hb.parent_base_id)?.airport_code ?? "";
            const nx = rb && rb.flight_no_from != null ? schedule.nextFlightNumbers(rules, rb) : null;
            const wins = rb ? banks.bankWindows(rules, rb) : [];
            const boxes = bankBoxes(hb);
            return (
              <tr key={hb.id} className={fc ? "focusrow" : ""}>
                <td><b>{hb.airport_code}</b></td>
                <td>{nameOf(hb.airline_id)}</td>
                <td><select data-ref={`hubs.${i}.role`} value={fc ? "focus" : "hub"} disabled={busy} onChange={(e) => onField(hb, "role", e.currentTarget.value)}><option value="hub">Hub</option><option value="focus">Focus city</option></select></td>
                <td>{fc ? <select data-ref={`hubs.${i}.parent`} value={parent} disabled={busy} onChange={(e) => onField(hb, "parent", e.currentTarget.value)}><Opt list={parents} value={parent} empty="—" /></select> : <span className="dim">—</span>}</td>
                <td><Box data-ref={`hubs.${i}.block`} value={hb.flight_no_from == null ? "" : String(hb.flight_no_from)} disabled={busy} onSave={(v) => onField(hb, "block", v)} /></td>
                <td><Box data-ref={`hubs.${i}.lastUsed`} value={hb.last_flight_no == null ? "" : String(hb.last_flight_no)} placeholder={nx?.from_schedule ? String(nx.from_schedule) : ""} disabled={busy} onSave={(v) => onField(hb, "lastUsed", v)} /></td>
                <td className="dim">{nx ? `${nx.out} / ${nx.back}` : ""}</td>
                <td><Box data-ref={`hubs.${i}.mct`} value={mctHours(wa.get(hb.airport_code))} disabled={busy} onSave={(v) => onMct(hb, v)} /></td>
                {boxes.map((b, k) => (
                  <td key={k}><Box data-ref={`hubs.${i}.banks.${k}`} value={b} placeholder="hh:mm" disabled={busy || fc} title={fc ? "not used: a focus city times its flights to the banks of the hub it feeds" : undefined}
                    onSave={(v) => onField(hb, `banks.${k}` as BaseField, v)} /></td>
                ))}
                <td className="dim">{fc ? "focus city · times to " + (parent || "its hub") + " banks" : wins.map((x) => `B${x.n} ${H(x.arr_start)}–${H(x.arr_end)}`).join(" · ")}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
