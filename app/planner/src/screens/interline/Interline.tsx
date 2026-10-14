// Interline (decision #18, build pull request 12; spec docs/specs/2026-10-14-interline-photos-reference.md): which foreign
// countries each airline flies into or has planned, and whether it has an interline agreement there, as the old planner's
// Interline (renderInterline), from the same data, with the same words and look:
//   - the agreements: one row per airline and interline country, with the airports, round trips a day (or "planned"), the
//     status, the partner in the game, since when and notes, each saved as you change it (one planner_save() call, the
//     interline_agreements row the old planner's adapter writes); the airline and status filters, in the address
//     (/planner/next/interline?airline=KF&status=open);
//   - the interline countries, why each is one, the partners in the game there and our airlines flying or planned there;
//     what to do when another airline asks, and the countries each of our airlines covers.
// The rows and rules are model.ts's, on the start's rules input (rotations, routes, bases, the flown airports' countries),
// the waiting plan cards and the setting interline_rules (manual §6).
import { useEffect, useMemo, useState, type CSSProperties, type KeyboardEvent } from "react";
import { useLocation, useNavigate } from "react-router";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import { saver } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { ErrorBox } from "../../ui/ErrorBox";
import { loadLogos } from "../../ui/siteFiles";
import { useAirports } from "../routes/reads";
import { extraIndex } from "../tails/model";
import { useGameHost, usePlanCards, usePlanLegs, useTailsAircraft } from "../tails/reads";
import {
  IL_STATUS, STATUS_WORDS, agreementChange, airportsOf, coveredWords, filterSearch, interlineRows, isOpen, parseFilters, parseRules,
  rtWords, shownRows, statusOf, type AgreementRow, type IlAirline, type IlField, type IlPlan, type IlRotation, type IlRow, type StatusFilter,
} from "./model";
import { useAgreements, useCountries } from "./reads";

const STATUS_CHIPS: readonly [StatusFilter, string][] = [["", "All"], ["open", "Still to sign"], ["signed", "Signed"], ["declined", "Declined"]];

export function Interline() {
  const loc = useLocation();
  const navigate = useNavigate();
  const filters = useMemo(() => parseFilters(loc.search), [loc.search]);
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const rulesQ = useRules(w);
  const countriesQ = useCountries();
  const agreementsQ = useAgreements(w);
  const aircraftQ = useTailsAircraft(w);
  const cardsQ = usePlanCards(w);
  const legsQ = usePlanLegs(w);
  const hostQ = useGameHost(w);
  const [logos, setLogos] = useState<Record<string, string> | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let alive = true;
    loadLogos().then((l) => { if (alive) setLogos(l); }).catch(() => { if (alive) setLogos({}); });
    return () => { alive = false; };
  }, []);

  const rules = rulesQ.data?.rules;
  const airlines: IlAirline[] = useMemo(() => (airlinesQ.data ?? []).map((a) => ({
    id: a.id, code: a.iata_code, name: a.planner_name ?? a.public_name ?? a.game_name ?? `Airline ${a.game_id}`, color: a.livery_color,
  })), [airlinesQ.data]);
  const ilRules = useMemo(() => (rules ? parseRules(rules.input.settings.interline_rules) : null), [rules]);

  // the waiting plan cards: an aircraft not in service, still in the old planner's deliveries, with a card; its legs as the
  // old planner reads them (a copy kept in the card's extra.legs, else the leg rows)
  const plans: IlPlan[] = useMemo(() => {
    if (!aircraftQ.data || !cardsQ.data || !legsQ.data) return [];
    const ac = new Map(aircraftQ.data.map((a) => [a.id, a]));
    return cardsQ.data.flatMap((c): IlPlan[] => {
      const a = ac.get(c.aircraft_id);
      if (!a || a.status === "active" || a.status === "retired" || extraIndex(a, "deliveries_index") == null) return [];
      const kept = (c.extra && typeof c.extra === "object" && !Array.isArray(c.extra) ? c.extra.legs : null);
      const legs = Array.isArray(kept)
        ? kept.map((l) => (l && typeof l === "object" && !Array.isArray(l) ? { from: typeof l.from === "string" ? l.from : null, to: typeof l.to === "string" ? l.to : null } : { from: null, to: null }))
        : legsQ.data.filter((l) => l.plan_card_id === c.id).sort((x, y) => x.position - y.position).map((l) => ({ from: l.origin_code, to: l.dest_code }));
      return [{ airline_id: a.airline_id, registration: a.registration, legs }];
    });
  }, [aircraftQ.data, cardsQ.data, legsQ.data]);
  const planCodes = useMemo(() => [...new Set(plans.flatMap((p) => p.legs.flatMap((l) => [l.from, l.to])).filter((x): x is string => !!x))]
    .filter((c) => !rules?.airports.has(c)), [plans, rules]);
  const planAirportsQ = useAirports(w, planCodes);

  const names = useMemo(() => new Map((countriesQ.data ?? []).map((c) => [c.code, c.name])), [countriesQ.data]);
  const ctryName = (cc: string) => names.get(cc) || cc;
  const nameOf = (code: string) => airlines.find((a) => a.code === code)?.name ?? code;
  const home = useMemo(() => new Set((rules?.bases ?? []).map((b) => rules?.airports.get(b.airport_code)?.country_code).filter((x): x is string => !!x)), [rules]);

  const rows: IlRow[] | null = useMemo(() => {
    if (!rules || !ilRules || !airlinesQ.data || (planCodes.length && !planAirportsQ.data)) return null;
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
    // nameOf reads airlines, which is in the list
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rules, ilRules, airlinesQ.data, airlines, plans, home, planCodes.length, planAirportsQ.data]);

  const records = useMemo(() => new Map((agreementsQ.data ?? []).map((a) => [a.airline_id + "|" + a.country_code, a])), [agreementsQ.data]);
  const rec = (r: IlRow) => records.get(r.airline_id + "|" + r.cc);
  const codeOf = (id: number) => airlines.find((a) => a.id === id)?.code ?? null;
  const al = (id: number) => airlines.find((a) => a.id === id);

  async function edit(r: IlRow, field: IlField, value: string) {
    if (w === undefined) return;
    const ch = agreementChange(w, r.airline_id, r.cc, rec(r), field, value);
    if (!ch) return;
    setBusy(true);
    try {
      await saver.save([ch]);
    } finally {
      setBusy(false);
    }
  }
  const setFilters = (f: Partial<typeof filters>) => navigate({ search: filterSearch({ ...filters, ...f }) });

  const loadError = world.error ?? airlinesQ.error ?? rulesQ.error ?? countriesQ.error ?? agreementsQ.error ?? aircraftQ.error ?? cardsQ.error
    ?? legsQ.error ?? planAirportsQ.error ?? hostQ.error;
  const ready = !!(rows && countriesQ.data && agreementsQ.data && logos && hostQ.isFetched);
  const host = hostQ.data;
  return (
    <main className="view interline" data-screen="interline" data-interline-ready={ready ? "yes" : "no"} data-interline-view={loc.search}>
      <div className="vh"><h1>Interline</h1><p>Which foreign countries each airline flies into, and whether it has an interline agreement there.</p></div>
      {loadError ? <ErrorBox error={loadError} /> : null}
      {rules && !ilRules ? <ErrorBox error="The interline rules (settings.interline_rules) aren't in the database yet." /> : null}
      {!ready && !loadError ? <div className="empty">Loading…</div> : null}
      {ready && rows && ilRules ? (
        <Agreements rows={rows} filters={filters} rules={ilRules} airlines={airlines} logos={logos ?? {}} host={host ?? null} busy={busy}
          countries={countriesQ.data ?? []} home={home} ctryName={ctryName} nameOf={nameOf} rec={rec} codeOf={codeOf} al={al}
          onFilter={setFilters} onEdit={(r, f, v) => void edit(r, f, v)} />
      ) : null}
    </main>
  );
}

function Agreements(p: {
  rows: readonly IlRow[]; filters: ReturnType<typeof parseFilters>; rules: NonNullable<ReturnType<typeof parseRules>>; airlines: readonly IlAirline[];
  logos: Record<string, string>; host: string | null; busy: boolean; countries: readonly { code: string; name: string }[]; home: ReadonlySet<string>;
  ctryName: (cc: string) => string; nameOf: (code: string) => string; rec: (r: IlRow) => AgreementRow | undefined; codeOf: (id: number) => string | null;
  al: (id: number) => IlAirline | undefined;
  onFilter: (f: Partial<ReturnType<typeof parseFilters>>) => void; onEdit: (r: IlRow, field: IlField, value: string) => void;
}) {
  const { rows, filters } = p;
  const status = (r: IlRow) => statusOf(p.rec(r));
  const open = rows.filter((r) => isOpen(status(r))).length;
  const ilAls = [...new Set(rows.map((r) => r.airline_id))];
  const shown = shownRows(rows, filters, p.codeOf, status);
  const yes = Object.entries(p.rules.countries).sort((a, b) => p.ctryName(a[0]).localeCompare(p.ctryName(b[0])));
  const mark = (id: number) => <AirlineMark color={p.al(id)?.color} />;
  const enter = (e: KeyboardEvent<HTMLInputElement>) => { if (e.key === "Enter") e.currentTarget.blur(); };
  // the airline's logo on its first row shown (the old table's last)
  const firsts = new Set(shown.map((r, i) => (i === 0 || shown[i - 1]?.airline_id !== r.airline_id ? i : -1)).filter((i) => i >= 0));
  return (
    <div className="board" data-figure="interline: agreements">
      <h3 className="rh">Interline agreements <span className="note">{rows.length} airline–country pairs · {open} still to sign · each airline signs its own · the group's airlines already interline with each other</span></h3>
      {!rows.length ? <div className="dim">None of our airlines flies to an interline country yet.</div> : null}
      <div className="chips" data-chips="interline">
        <span className="chiplbl">Airline</span>
        <button type="button" className={"chip" + (!filters.airline ? " on" : "")} data-ilf="al" data-v="" onClick={() => p.onFilter({ airline: "" })}>All</button>
        {ilAls.map((id) => {
          const a = p.al(id);
          const code = a?.code ?? "";
          return <button type="button" key={id} className={"chip" + (filters.airline && filters.airline === code ? " on" : "")} data-ilf="al" data-v={code}
            onClick={() => p.onFilter({ airline: code })}>{mark(id)}{a?.name ?? ""}</button>;
        })}
        <span className="chiplbl" style={{ marginLeft: 14 }}>Status</span>
        {STATUS_CHIPS.map(([k, l]) => (
          <button type="button" key={l} className={"chip" + (filters.status === k ? " on" : "")} data-ilf="status" data-v={k} onClick={() => p.onFilter({ status: k })}>{l}</button>
        ))}
      </div>
      <div className="tblwrap">
        <table className="tbl il">
          <tbody>
            <tr><th>Airline</th><th>Country</th><th>Airports we fly there</th><th>Round trips/day</th><th>Status</th><th>Partner in the game</th><th>Since</th><th>Notes</th></tr>
            {shown.map((r, i) => {
              const v = p.rec(r);
              const st = status(r);
              const k = `${p.codeOf(r.airline_id) ?? r.airline_id}|${r.cc}`;
              const first = firsts.has(i);
              const a = p.al(r.airline_id);
              const logo = a ? p.logos[a.name] : undefined;
              return (
                <tr key={k} className={st} data-il-row={k}>
                  <td>{first ? (logo ? <img className="alogo" src={logo} alt={a?.name ?? ""} style={{ height: 16 } as CSSProperties} />
                    : <>{mark(r.airline_id)}<b>{a?.name ?? ""}</b></>) : null}</td>
                  <td><b>{p.ctryName(r.cc)}</b></td>
                  <td>{airportsOf(r).map((ap, i) => <span key={ap}>{i ? " " : null}<span className="hubtag">{ap}</span></span>)}</td>
                  <td>{r.planned ? <span className="dim">planned</span> : rtWords(r.rt_day)}</td>
                  <td>
                    <select data-il={k} data-ilk="status" value={st} disabled={p.busy} onChange={(e) => p.onEdit(r, "status", e.currentTarget.value)}>
                      {IL_STATUS.map((s) => <option key={s} value={s}>{STATUS_WORDS[s]}</option>)}
                    </select>
                  </td>
                  <td><input key={`p|${v?.partner ?? ""}`} data-il={k} data-ilk="partner" defaultValue={v?.partner ?? ""} placeholder="airline name"
                    onBlur={(e) => { if (e.currentTarget.value !== (v?.partner ?? "")) p.onEdit(r, "partner", e.currentTarget.value); }} onKeyDown={enter} /></td>
                  <td><input key={`d|${v?.decided_on ?? ""}`} type="date" data-il={k} data-ilk="date" defaultValue={v?.decided_on ?? ""}
                    onBlur={(e) => { if (e.currentTarget.value !== (v?.decided_on ?? "")) p.onEdit(r, "date", e.currentTarget.value); }} onKeyDown={enter} /></td>
                  <td><input key={`n|${v?.note ?? ""}`} data-il={k} data-ilk="notes" defaultValue={v?.note ?? ""}
                    onBlur={(e) => { if (e.currentTarget.value !== (v?.note ?? "")) p.onEdit(r, "notes", e.currentTarget.value); }} onKeyDown={enter} /></td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <h3 className="rh" style={{ marginTop: 18 }}>The {yes.length} interline countries <span className="note">real domestic network or regional gateway · each airline that flies there signs its own partner · partners that exist in Gander</span></h3>
      <div className="tblwrap">
        <table className="tbl" data-figure="interline: countries">
          <tbody>
            <tr><th>Country</th><th>Why</th><th>Gander airlines</th><th>Our airlines flying or planned there</th></tr>
            {yes.map(([cc, why]) => {
              const flying = rows.filter((r) => r.cc === cc);
              const partners = p.rules.partners[cc] ?? [];
              return (
                <tr key={cc}>
                  <td><b>{p.ctryName(cc)}</b></td>
                  <td>{why}</td>
                  <td>{partners.length ? partners.map((x, i) => <span key={x.game_id}>{i ? ", " : null}<a href={`https://${p.host ?? "gander.airlinesim.aero"}/app/info/enterprises/${x.game_id}`} target="_blank" rel="noopener">{x.name}</a></span>)
                    : <span className="dim">no airline yet</span>}</td>
                  <td>{flying.length ? flying.map((r, i) => <span key={r.airline_id}>{i ? " · " : null}{mark(r.airline_id)}{(p.al(r.airline_id)?.name ?? "").split(" ")[0]}{r.planned ? <> <span className="dim">(planned)</span></> : null}</span>)
                    : <span className="dim">—</span>}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <div className="note">If another airline asks to interline: accept if it's based in an interline country, flies to an airport that airline serves, and mostly goes where we don't. In a country covered by one of our airlines, accept only small regionals flying to cities our airline doesn't reach. Decline carriers from group-base countries, the Europe zone and the hub rivals (Gulf, Türkiye, Singapore, Hong Kong, South Korea). Ryanair signs with no one outside the group. Covered: {coveredWords(p.countries, p.rules, p.home, p.nameOf)}.</div>
      <div className="note">Rows come from the flights in the planner and the plan cards not yet filed: a country appears for an airline once that airline flies there or has it planned. Only the {yes.length} interline countries get rows; everything else is covered by one of our airlines, a hub rival, a group-base country, the Europe zone, or has no network worth a partner.</div>
    </div>
  );
}
