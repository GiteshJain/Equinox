// Interline (decision #18, build pull request 12; spec docs/specs/2026-10-14-interline-photos-reference.md): which foreign
// countries each airline flies into or has planned, and whether it has an interline agreement there, as the old planner's
// Interline (renderInterline), from the same data, with the same words:
//   - the agreements: one row per airline and interline country, with the airports, round trips a day (or "planned"), the
//     status, the partner in the game, since when and notes, each saved as you change it (one planner_save() call, the
//     interline_agreements row the old planner's adapter writes); the airline and status filters, in the address
//     (/planner/interline?airline=KF&status=open);
//   - the interline countries, why each is one, the partners in the game there and our airlines flying or planned there;
//     what to do when another airline asks, and the countries each of our airlines covers.
// Since 23 Oct (spec docs/specs/2026-10-23-planner-look-interline.md) answer-first, as the new Today and Systems: the
// answer is the title ("5 agreements to set up", or "All agreements in place") with the airline and status filters as
// pills beside it; count tiles by status, each applying the status filter (?status=none, requested, signed, declined,
// nopartner, or open for still to sign); the agreements as one table grouped by airline under its colour dot, each row on
// a phone a compact card (country, airline, status pill) that opens to its fields; and the interline countries, what to
// do when another airline asks and the countries each airline covers as rows that open (FoldBoard), closed on arrival.
// The rows and rules are model.ts's, on the start's rules input (rotations, routes, bases, the flown airports' countries),
// the waiting plan cards and the setting interline_rules (manual §6), made in useRows.ts, which Home's interline line shares.
import { useEffect, useMemo, useState, type CSSProperties, type KeyboardEvent } from "react";
import { useLocation, useNavigate } from "react-router";
import { useWorld } from "../../data/reads";
import { saver } from "../../data/saving";
import { AirlineMark } from "../../ui/AirlineMark";
import { ErrorBox } from "../../ui/ErrorBox";
import { FoldBoard, FoldTools } from "../../ui/FoldBoard";
import { loadLogos } from "../../ui/siteFiles";
import { useGameHost } from "../tails/reads";
import {
  IL_STATUS, STATUS_WORDS, agreementChange, airportsOf, answerWords, byAirline, coveredWords, filterSearch, isOpen, parseFilters, type parseRules,
  rtWords, shownRows, statusCounts, statusOf, type AgreementRow, type IlAirline, type IlField, type IlRow, type IlStatus, type StatusFilter,
} from "./model";
import { useAgreements, useCountries } from "./reads";
import { useInterlineRows } from "./useRows";

const STATUS_CHIPS: readonly [StatusFilter, string][] = [["", "All"], ["open", "Still to sign"], ["signed", "Signed"], ["declined", "Declined"]];
/** The count tiles: still to sign, then each status; each applies its status filter. */
const TILES: readonly { k: Exclude<StatusFilter, "">; name: string; line: string }[] = [
  { k: "open", name: "Still to sign", line: "not contacted or requested" },
  { k: "none", name: "Not contacted", line: "nobody asked yet" },
  { k: "requested", name: "Requested", line: "waiting for an answer" },
  { k: "signed", name: "Signed", line: "agreement in place" },
  { k: "declined", name: "Declined", line: "no agreement, by choice" },
  { k: "nopartner", name: "No partner in Gander yet", line: "no airline there to sign with" },
];
/** Each status's pill (the phone card's), in the status colours. */
const STATUS_PILL: Record<IlStatus, string> = { none: "warn", requested: "mute", signed: "ok", declined: "mute", nopartner: "mute" };
/** The rows that open under the table. */
const FOLDS = ["The interline countries", "When another airline asks", "Countries our airlines cover"] as const;
type FoldKey = (typeof FOLDS)[number];

export function Interline() {
  const loc = useLocation();
  const navigate = useNavigate();
  const filters = useMemo(() => parseFilters(loc.search), [loc.search]);
  const world = useWorld();
  const w = world.data?.id;
  const { rules, airlines, ilRules, home, nameOf, rows, error: rowsError } = useInterlineRows(w);
  const countriesQ = useCountries();
  const agreementsQ = useAgreements(w);
  const hostQ = useGameHost(w);
  const [logos, setLogos] = useState<Record<string, string> | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let alive = true;
    loadLogos().then((l) => { if (alive) setLogos(l); }).catch(() => { if (alive) setLogos({}); });
    return () => { alive = false; };
  }, []);

  // the rows (the airlines, the rules and the waiting plan cards they're made from) are useRows.ts's, as Home counts them
  const names = useMemo(() => new Map((countriesQ.data ?? []).map((c) => [c.code, c.name])), [countriesQ.data]);
  const ctryName = (cc: string) => names.get(cc) || cc;

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

  const loadError = world.error ?? rowsError ?? countriesQ.error ?? agreementsQ.error ?? hostQ.error;
  const ready = !!(rows && countriesQ.data && agreementsQ.data && logos && hostQ.isFetched);
  const host = hostQ.data;
  // the answer: every pair still to sign, whatever the filters show
  const openAll = ready && rows ? rows.filter((r) => isOpen(statusOf(rec(r)))).length : null;
  return (
    <main className="view interline" data-screen="interline" data-interline-ready={ready ? "yes" : "no"} data-interline-view={loc.search}>
      <div className="vh todayvh ilvh">
        <p className="vk">Agreements</p>
        <div className="todayttl">
          <h1 className="ansh" data-il-answer={openAll ?? ""}>{openAll != null ? answerWords(openAll) : "Interline"}</h1>
          {ready && rows ? <Filters rows={rows} filters={filters} al={al} onFilter={setFilters} /> : null}
        </div>
        <p className="ansp">Which foreign countries each airline flies into, and whether it has an interline agreement there.</p>
      </div>
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

/** The airline and status filters, as pills beside the title (kept in the address). */
function Filters({ rows, filters, al, onFilter }: {
  rows: readonly IlRow[]; filters: ReturnType<typeof parseFilters>; al: (id: number) => IlAirline | undefined;
  onFilter: (f: Partial<ReturnType<typeof parseFilters>>) => void;
}) {
  const ilAls = [...new Set(rows.map((r) => r.airline_id))];
  return (
    <div className="chips ilchips" data-chips="interline">
      <span className="ilchipset">
        <span className="chiplbl">Airline</span>
        <button type="button" className={"chip" + (!filters.airline ? " on" : "")} data-ilf="al" data-v="" onClick={() => onFilter({ airline: "" })}>All</button>
        {ilAls.map((id) => {
          const a = al(id);
          const code = a?.code ?? "";
          return <button type="button" key={id} className={"chip" + (filters.airline && filters.airline === code ? " on" : "")} data-ilf="al" data-v={code}
            onClick={() => onFilter({ airline: code })}><AirlineMark color={a?.color} />{a?.name ?? ""}</button>;
        })}
      </span>
      <span className="ilchipset">
        <span className="chiplbl">Status</span>
        {STATUS_CHIPS.map(([k, l]) => (
          <button type="button" key={l} className={"chip" + (filters.status === k ? " on" : "")} data-ilf="status" data-v={k} onClick={() => onFilter({ status: k })}>{l}</button>
        ))}
      </span>
    </div>
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
  const [openRows, setOpenRows] = useState<ReadonlySet<string>>(() => new Set());
  const [folded, setFolded] = useState<ReadonlySet<FoldKey>>(() => new Set(FOLDS));
  const status = (r: IlRow) => statusOf(p.rec(r));
  const open = rows.filter((r) => isOpen(status(r))).length;
  const shown = shownRows(rows, filters, p.codeOf, status);
  // the tiles count the rows of the airline picked (all when none is), so each tile's number is what it shows
  const forAirline = shownRows(rows, { airline: filters.airline, status: "" }, p.codeOf, status);
  const counts = statusCounts(forAirline, status);
  const tileCount = (k: Exclude<StatusFilter, "">) => (k === "open" ? counts.none + counts.requested : counts[k]);
  const tileCls = (k: Exclude<StatusFilter, "">, n: number) => (k === "open" || k === "none" ? (n ? "warn" : "ok") : k === "signed" && n ? "ok" : "");
  const yes = Object.entries(p.rules.countries).sort((a, b) => p.ctryName(a[0]).localeCompare(p.ctryName(b[0])));
  const mark = (id: number) => <AirlineMark color={p.al(id)?.color} />;
  const enter = (e: KeyboardEvent<HTMLInputElement>) => { if (e.key === "Enter") e.currentTarget.blur(); };
  const toggleRow = (k: string) => setOpenRows((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const toggle = (k: FoldKey) => setFolded((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const covered = coveredWords(p.countries, p.rules, p.home, p.nameOf);
  const coveredBy = covered ? covered.split(" · ").length : 0;
  const pickedName = filters.airline ? p.airlines.find((a) => a.code === filters.airline)?.name ?? filters.airline : null;
  return (
    <>
      <section className="board ilcounts" aria-labelledby="il-counts-h">
        <h3 className="rh" id="il-counts-h">
          <span className="rht">By status</span>
          <span className="note">{forAirline.length} airline–country pair{forAirline.length === 1 ? "" : "s"}{pickedName ? ` for ${pickedName}` : ""} · tap a tile to show only those</span>
        </h3>
        <div className="tiles iltiles" role="group" aria-label="Agreements by status">
          {TILES.map((t) => {
            const n = tileCount(t.k);
            const on = filters.status === t.k;
            return (
              <button type="button" key={t.k} className={"tile " + tileCls(t.k, n) + (on ? " on" : "")} aria-pressed={on} data-il-tile={t.k} data-count={n}
                onClick={() => p.onFilter({ status: on ? "" : t.k })}>
                <b className="tn">{n}</b>
                <span className="tname">{t.name}</span>
                <span className="tline">{t.line}</span>
              </button>
            );
          })}
        </div>
      </section>

      <section className="board ilboard" data-figure="interline: agreements">
        <h3 className="rh">Interline agreements <span className="note">{rows.length} airline–country pairs · {open} still to sign · each airline signs its own · the group's airlines already interline with each other</span></h3>
        {!rows.length ? <div className="dim">None of our airlines flies to an interline country yet.</div> : null}
        {rows.length && !shown.length ? <div className="dim">No agreement matches these filters.</div> : null}
        {shown.length ? (
          <div className="tblwrap">
            <table className="tbl il">
              <thead><tr><th>Country</th><th>Airports we fly there</th><th>Round trips/day</th><th>Status</th><th>Partner in the game</th><th>Since</th><th>Notes</th></tr></thead>
              {byAirline(shown).map((g) => {
                const a = p.al(g.airline_id);
                const logo = a ? p.logos[a.name] : undefined;
                const gOpen = g.rows.filter((r) => isOpen(status(r))).length;
                return (
                  <tbody key={g.airline_id} data-il-airline={a?.code ?? g.airline_id}>
                    <tr className="ilgrp">
                      <th colSpan={7} scope="colgroup">
                        <span className="ilgname">{mark(g.airline_id)}{logo ? <img className="alogo" src={logo} alt={a?.name ?? ""} style={{ height: 16 } as CSSProperties} /> : <b>{a?.name ?? ""}</b>}</span>
                        <span className="ilgnote">{g.rows.length} countr{g.rows.length === 1 ? "y" : "ies"}{gOpen ? ` · ${gOpen} still to sign` : " · all settled"}</span>
                      </th>
                    </tr>
                    {g.rows.map((r) => {
                      const v = p.rec(r);
                      const st = status(r);
                      const k = `${p.codeOf(r.airline_id) ?? r.airline_id}|${r.cc}`;
                      const isOpenRow = openRows.has(k);
                      return (
                        <tr key={k} className={st} data-il-row={k} data-open={isOpenRow ? "yes" : "no"}>
                          <td className="ilh">
                            <button type="button" className="iltap" aria-expanded={isOpenRow} onClick={() => toggleRow(k)}>
                              <b className="ilcty">{p.ctryName(r.cc)}</b>
                              <span className="ilal">{mark(r.airline_id)}{a?.name ?? ""}</span>
                              <span className={"pill sm ilst " + STATUS_PILL[st]}>{STATUS_WORDS[st]}</span>
                              <span className="chev" aria-hidden="true" />
                            </button>
                          </td>
                          <td data-l="Airports we fly there">{airportsOf(r).map((ap, i) => <span key={ap}>{i ? " " : null}<span className="hubtag">{ap}</span></span>)}</td>
                          <td data-l="Round trips/day">{r.planned ? <span className="dim">planned</span> : rtWords(r.rt_day)}</td>
                          <td data-l="Status">
                            <select data-il={k} data-ilk="status" value={st} disabled={p.busy} onChange={(e) => p.onEdit(r, "status", e.currentTarget.value)}>
                              {IL_STATUS.map((s) => <option key={s} value={s}>{STATUS_WORDS[s]}</option>)}
                            </select>
                          </td>
                          <td data-l="Partner in the game"><input key={`p|${v?.partner ?? ""}`} data-il={k} data-ilk="partner" defaultValue={v?.partner ?? ""} placeholder="airline name"
                            onBlur={(e) => { if (e.currentTarget.value !== (v?.partner ?? "")) p.onEdit(r, "partner", e.currentTarget.value); }} onKeyDown={enter} /></td>
                          <td data-l="Since"><input key={`d|${v?.decided_on ?? ""}`} type="date" data-il={k} data-ilk="date" defaultValue={v?.decided_on ?? ""}
                            onBlur={(e) => { if (e.currentTarget.value !== (v?.decided_on ?? "")) p.onEdit(r, "date", e.currentTarget.value); }} onKeyDown={enter} /></td>
                          <td data-l="Notes"><input key={`n|${v?.note ?? ""}`} data-il={k} data-ilk="notes" defaultValue={v?.note ?? ""}
                            onBlur={(e) => { if (e.currentTarget.value !== (v?.note ?? "")) p.onEdit(r, "notes", e.currentTarget.value); }} onKeyDown={enter} /></td>
                        </tr>
                      );
                    })}
                  </tbody>
                );
              })}
            </table>
          </div>
        ) : null}
        <div className="note">Rows come from the flights in the planner and the plan cards not yet filed: a country appears for an airline once that airline flies there or has it planned. Only the {yes.length} interline countries get rows; everything else is covered by one of our airlines, a hub rival, a group-base country, the Europe zone, or has no network worth a partner.</div>
      </section>

      <section className="sysrows ilrows" aria-labelledby="ilrows-h">
        <div className="sysrowsh">
          <h2 className="tph" id="ilrows-h">The rules</h2>
          <FoldTools onCollapse={() => setFolded(new Set(FOLDS))} onExpand={() => setFolded(new Set())} hint="" />
        </div>
        <FoldBoard k="The interline countries" title={<span className="fbname">The interline countries</span>}
          note="Real domestic network or regional gateway, the partners in Gander, our airlines there" aside={<span>{yes.length} countries</span>}
          folded={folded.has("The interline countries")} onToggle={() => toggle("The interline countries")}>
          <div className="note fblead">The {yes.length} interline countries · real domestic network or regional gateway · each airline that flies there signs its own partner · partners that exist in Gander</div>
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
        </FoldBoard>
        <FoldBoard k="When another airline asks" title={<span className="fbname">When another airline asks</span>}
          note="Who to accept and who to decline" aside={<span>manual §6</span>}
          folded={folded.has("When another airline asks")} onToggle={() => toggle("When another airline asks")}>
          <div className="note ilguide" data-il-guide>If another airline asks to interline: accept if it's based in an interline country, flies to an airport that airline serves, and mostly goes where we don't. In a country covered by one of our airlines, accept only small regionals flying to cities our airline doesn't reach. Decline carriers from group-base countries, the Europe zone and the hub rivals (Gulf, Türkiye, Singapore, Hong Kong, South Korea). Ryanair signs with no one outside the group.</div>
        </FoldBoard>
        <FoldBoard k="Countries our airlines cover" title={<span className="fbname">Countries our airlines cover</span>}
          note="Countries one of our airlines covers, so no outside partner there" aside={<span>{coveredBy} airline{coveredBy === 1 ? "" : "s"}</span>}
          folded={folded.has("Countries our airlines cover")} onToggle={() => toggle("Countries our airlines cover")}>
          <div className="note ilcovered" data-il-covered>Covered: {covered}.</div>
        </FoldBoard>
      </section>
    </>
  );
}
