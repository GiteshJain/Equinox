// Competition (spec docs/specs/2026-10-21-competition-analysis.md §3; manual §3, market share first): "who are we up
// against, and where do we open next?". Every figure is competition()'s (the database's), at the screen's moment.
//   - The group (/planner/competition): the scans' dates at the top ("latest scan 17 Oct, compared with 6 Oct"), the
//     group line (our airlines' departures a week against the world's), one card per airline (its share across its
//     markets with its arrow, its threats and its top openings; tap to open it) and every airline's threats.
//   - An airline (/planner/competition/<code>): the scans and the group line on top, then Market share (one card per
//     market: our share with its arrow and the top rivals as a bar), Threats (each with the rival, the pair, the numbers
//     and the day), Openings (the ranked table: rank, pair, stars, distance, rivals, variant and allowed under hubs first,
//     cut to 10 with "show all"; since 22 Oct a 1-star opening on the E195-E2 says "or the E190-E2 if thin" under its
//     variant, spec docs/specs/2026-10-21-tidy-ups.md §2) and Rival profiles (cards).
// Read only: nothing here saves. Phone first: cards stack, the openings table scrolls inside its own box.
import { useMemo, useState } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { ourAirlines, type OurAirline } from "../../data/airlines";
import { useOurAirlines, useWorld } from "../../data/reads";
import { AirlineMark } from "../../ui/AirlineMark";
import { Board } from "../../ui/Board";
import { ErrorBox } from "../../ui/ErrorBox";
import { listCut } from "../performance/model";
import { itemRoute } from "../screens";
import {
  allowedWords, changeWords, dayWords, groupWords, kmWords, n0, openingsLine, otherListsWords, overallShare, pctWords, profileWords, rivalsWords, scansWords, shareBar,
  starsWords, threatNumbers, threatWhen, threatsLine, trunkMonthWords, variantNoteWords, variantWords, type CompetitionAnswer, type Market, type Opening, type Profile, type Threat,
} from "./model";
import { useCompetition, useCompetitions } from "./reads";

const first = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

/** A change with its arrow, quiet when there's nothing to compare. */
function Change({ v, points = false, k }: { v: number | null | undefined; points?: boolean; k?: string }) {
  const c = changeWords(v, points);
  if (!c) return <span className="dim" data-change={k}>no comparison yet</span>;
  return <span className={"cpch " + c.arrow} data-change={k} data-arrow={c.arrow}>{c.text}</span>;
}

export function Competition() {
  const params = useParams();
  const navigate = useNavigate();
  const world = useWorld();
  const w = world.data?.id;
  const airlinesQ = useOurAirlines(w);
  const airlines: OurAirline[] = useMemo(() => ourAirlines((airlinesQ.data ?? []).filter((a) => a.active !== false)), [airlinesQ.data]);
  const [code] = (params["*"] ?? "").split("/").filter(Boolean);
  const sel = code ? airlines.find((a) => a.code === code) : undefined;
  const allQ = useCompetitions(code ? [] : airlines.map((a) => a.id));
  const oneQ = useCompetition(sel?.id);
  const answers = new Map<number, CompetitionAnswer>();
  allQ.forEach((q, i) => { const a = airlines[i]; if (a && q.data) answers.set(a.id, q.data); });

  const isAirline = !!code;
  const ready = !!airlinesQ.data && (isAirline ? !!(oneQ.data && !oneQ.isFetching) : allQ.every((q) => q.data && !q.isFetching));
  const loadError = first(world, airlinesQ, ...(isAirline ? [oneQ] : allQ));
  const top = isAirline ? oneQ.data : answers.get(airlines[0]?.id ?? -1);

  return (
    <main className="view competition" data-screen="competition" data-competition-ready={ready ? "yes" : "no"} data-airline={sel?.code ?? ""}>
      <div className="vh">
        <h1>{sel ? <>{sel.name}: competition</> : "Competition"}</h1>
        <p>{sel ? "Its market share against the rivals, their moves on its routes, the routes to open next and the rivals it meets most, from the world scans."
          : "Who we're up against and where to open next: market share, the rivals' moves, the ranked openings and the rivals' profiles, from the world scans."}</p>
      </div>
      {loadError ? <ErrorBox error={loadError} /> : null}
      {!ready && !loadError ? <div className="empty">Loading…</div> : null}
      {isAirline && airlinesQ.data && !sel ? <div className="empty">There's no airline {code} in the planner. <Link className="link" to="/competition">All airlines</Link></div> : null}
      {isAirline && sel ? (
        <div className="perfnav" data-airlines>
          <Link className="link" to="/competition" data-back>‹ All airlines</Link>
          <span className="mleg">
            {airlines.map((a) => (
              <Link key={a.id} className={"mf" + (a.id === sel.id ? " on" : "")} to={itemRoute("competition", { airline: a.code ?? String(a.id) })} data-al={a.code ?? ""}>
                <AirlineMark color={a.color} />{a.code ?? a.name}
              </Link>
            ))}
          </span>
        </div>
      ) : null}
      {top ? <Top a={top} /> : null}
      {!isAirline && ready ? <Group airlines={airlines} answers={answers} onPick={(a) => navigate(itemRoute("competition", { airline: a.code ?? String(a.id) }))} /> : null}
      {isAirline && sel && oneQ.data ? <AirlinePage airline={sel} a={oneQ.data} /> : null}
    </main>
  );
}

/** The scans' dates and the group line, at the top of both pages. */
function Top({ a }: { a: CompetitionAnswer }) {
  const g = a.group;
  return (
    <div className="cptop" data-figure="competition: scans">
      <div className="cpscans" data-scans>{scansWords(a.scans)}</div>
      <div className="cpgroup" data-figure="competition: group line">
        <b>{groupWords(g)}</b>{g ? <> <Change v={g.share_change} points k="group" />{g.share_before != null ? <span className="dim"> (from {pctWords(g.share_before)})</span> : null}</> : null}
      </div>
    </div>
  );
}

/** The group page: one card per airline, then every airline's threats. */
function Group({ airlines, answers, onPick }: { airlines: readonly OurAirline[]; answers: ReadonlyMap<number, CompetitionAnswer>; onPick: (a: OurAirline) => void }) {
  const threats = airlines.flatMap((al) => (answers.get(al.id)?.threats ?? []).map((t) => ({ al, t })));
  return (
    <>
      <div className="fgrid" data-figure="competition: airlines">
        {airlines.map((al) => {
          const a = answers.get(al.id);
          if (!a) return null;
          const s = overallShare(a.markets);
          return (
            <button type="button" key={al.id} className="fcard cpcard" data-competition-card={al.code ?? ""} onClick={() => onPick(al)}>
              <div className="fch"><AirlineMark color={al.color} /><b>{al.name}</b></div>
              <div className="fbig">{pctWords(s.share)}<span className="fu"> of its markets</span></div>
              <div className="fsub"><Change v={s.change} points k={"share " + (al.code ?? "")} /> · {n0(s.ours)} of {n0(s.total)} departures a week</div>
              <div className={"cpline" + (a.threats.length ? " warn" : " dim")}>{threatsLine(a.threats.length)}</div>
              <div className="cpline dim">{openingsLine(a)}</div>
              {a.openings.length ? (
                <ol className="cptop3">
                  {a.openings.slice(0, 3).map((o) => <li key={o.route_id}><b>{o.route}</b> <span className="dim">{starsWords(o.stars)} · {variantWords(o.variant)}</span></li>)}
                </ol>
              ) : null}
            </button>
          );
        })}
      </div>
      <Board title="Threats" note="rivals who started on, or added a daily flight or more to, one of our city pairs since the scan before · each pauses the route's fares for a week (manual §5)"
        figure="competition: threats" board="Threats">
        {threats.length ? <ThreatList items={threats.map((x) => ({ ...x.t, al: x.al }))} /> : <div className="dim">No rival moves on our routes in the last 7 days.</div>}
      </Board>
    </>
  );
}

/** One airline's page: market share, threats, openings and rival profiles. */
function AirlinePage({ airline, a }: { airline: OurAirline; a: CompetitionAnswer }) {
  const before = dayWords(a.scans.week_before?.taken_at);
  return (
    <>
      <Board title="Market share" figure={`competition ${airline.name}: market share`} board="Market share"
        note={`our departures a week against every rival's on the same city pairs (either way), by market${before ? `, against ${before}` : ""} · our own from the live schedule`}>
        {a.markets.length ? (
          <div className="cpmk" data-figure="competition: markets">
            {a.markets.map((m) => <MarketCard key={m.market_id ?? "none"} m={m} />)}
          </div>
        ) : <div className="dim">No routes on the list yet.</div>}
      </Board>
      <Board title="Threats" figure={`competition ${airline.name}: threats`} board="Threats"
        note="rivals who started on, or added a daily flight or more to, a pair it flies since the scan before · listed for 7 days; the route's fares hold until then (manual §5)">
        {a.threats.length ? <ThreatList items={a.threats} /> : <div className="dim">No rival moves on its routes in the last 7 days.</div>}
      </Board>
      <Board title="Openings" figure={`competition ${airline.name}: openings`} board="Openings"
        note={`the pairs on its list no airline of ours flies, ranked: stars, then rivals' departures a week, then the shorter distance (manual §3) · ${openingsLine(a)}`}>
        {trunkMonthWords(a) ? <div className="cptrunks" data-trunk-month>{trunkMonthWords(a)}</div> : null}
        <Openings code={airline.code ?? String(airline.id)} openings={a.openings} total={a.openings_count} />
      </Board>
      <Board title="Rival profiles" figure={`competition ${airline.name}: rival profiles`} board="Rival profiles"
        note="the rivals who fly most of its city pairs, from the latest scan">
        {a.profiles.length ? (
          <div className="cpmk" data-figure="competition: profiles">
            {a.profiles.map((p) => <ProfileCard key={p.airline_id} p={p} before={before} />)}
          </div>
        ) : <div className="dim">No rival flies its city pairs in the latest scan.</div>}
      </Board>
    </>
  );
}

/** A market's card: our share with its arrow, the top rivals as a bar and a list. */
function MarketCard({ m }: { m: Market }) {
  const bar = shareBar(m);
  return (
    <div className="cpm" data-market={m.name}>
      <div className="cpmh"><b>{m.name}</b> <span className="dim">{m.flown} of {m.pairs} pair{m.pairs === 1 ? "" : "s"} flown</span></div>
      <div className="cpmv"><b className="cpbig">{pctWords(m.share)}</b> <Change v={m.share_change} points k={"market " + m.name} />
        <span className="dim"> · ours {n0(m.ours)} of {n0(m.total)} a week</span></div>
      {bar.length ? (
        <div className="cpbar" role="img" aria-label={bar.map((p) => `${p.label} ${p.pct.toFixed(0)}%`).join(", ")}>
          {bar.map((p, i) => <i key={i} className={p.ours ? "ours" : `r${Math.min(i, 6)}`} style={{ width: `${p.pct}%` }} title={`${p.label} ${p.pct.toFixed(1)}%`} />)}
        </div>
      ) : null}
      {m.top.length ? (
        <ol className="cprv">
          {m.top.map((r) => (
            <li key={r.airline_id}><span className="cpname">{r.name}</span> <span className="num">{n0(r.weekly)}</span> <span className="dim">{pctWords(r.share)}</span>{" "}
              <Change v={r.change} k={"rival " + r.name} /></li>
          ))}
        </ol>
      ) : <div className="dim cpnone">No rival on its pairs.</div>}
    </div>
  );
}

/** The threats: the rival, the pair, the numbers and the day. */
function ThreatList({ items }: { items: readonly (Threat & { al?: OurAirline })[] }) {
  return (
    <ul className="cpthreats">
      {items.map((t) => (
        <li key={`${t.al?.id ?? ""}|${t.pair}|${t.rival_id}`} data-threat={t.route} data-kind={t.kind}>
          {t.al ? <><AirlineMark color={t.al.color} /><Link className="link" to={itemRoute("competition", { airline: t.al.code ?? String(t.al.id) })}>{t.al.code}</Link> · </> : null}
          <b>{t.words}</b> <span className="dim">· {threatNumbers(t)} · {threatWhen(t)}</span>
        </li>
      ))}
    </ul>
  );
}

/** The openings, ranked, cut to 10 with "show all". */
function Openings({ code, openings, total }: { code: string; openings: readonly Opening[]; total: number }) {
  const [open, setOpen] = useState(false);
  if (!openings.length) return <div className="dim">No openings: every pair on its list is flown by one of our airlines, or none is on the list.</div>;
  const cut = listCut(openings, open);
  return (
    <div data-list={`openings ${code}`} data-list-rows={openings.length} data-list-shown={cut.shown.length}>
      <div className="tscroll">
        <table className="tbl gtbl cpopen" data-figure="competition: openings">
          <tbody>
            <tr><th className="num">#</th><th>Pair</th><th>Stars</th><th className="num">Distance</th><th>Rivals a week</th><th>Variant</th><th>Hubs first</th></tr>
            {cut.shown.map((o) => {
              const al = allowedWords(o);
              return (
                <tr key={o.route_id} data-opening={o.route} data-rank={o.rank} data-allowed={o.allowed ? "yes" : "no"} data-trunk={o.trunk ? "yes" : "no"}
                  className={o.allowed ? undefined : "cpno"}>
                  <td className="num">{o.rank}</td>
                  <td><b>{o.route}</b>{o.trunk ? <> <span className="pill mute sm">trunk</span></> : null}{o.city ? <div className="dim cpcity">{o.city}</div> : null}
                    {otherListsWords(o) ? <div className="dim cpcity">{otherListsWords(o)}</div> : null}</td>
                  <td>{starsWords(o.stars)}</td>
                  <td className="num">{kmWords(o.distance_km)}</td>
                  <td><span className="num">{n0(o.rivals_weekly)}</span> <span className="dim">{rivalsWords(o)}</span></td>
                  <td>{variantWords(o.variant)}{variantNoteWords(o) ? <div className="dim cpcity" data-variant-note>{variantNoteWords(o)}</div> : null}</td>
                  <td>{al.ok ? <span title={al.why}>{al.text} <span className="dim">· {al.why}</span></span>
                    : <span className="pill mute sm" title={al.why}>{al.text}</span>}{al.ok ? null : <div className="dim cpwhy">{al.why}</div>}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {cut.button ? <button type="button" className="link gmore" data-list-more={`openings ${code}`} aria-expanded={open} onClick={() => setOpen(!open)}>{cut.button}</button> : null}
      {total > openings.length ? <div className="dim cpmore">The top {openings.length} of {n0(total)}; the Scheduling chat reads the rest with competition()'s p_limit.</div> : null}
    </div>
  );
}

/** A rival's card: its size and growth, the pairs it shares with us, and its biggest airports. */
function ProfileCard({ p, before }: { p: Profile; before: string }) {
  return (
    <div className="cpm" data-profile={p.name}>
      <div className="cpmh"><b>{p.name}</b> <span className="dim">on {p.pairs_shared} of our pair{p.pairs_shared === 1 ? "" : "s"}</span></div>
      <div className="cpmv">{profileWords(p, before)}</div>
      <div className="cpline"><span className="dim">Shared:</span> {p.pairs.slice(0, 6).map((x) => `${x.route} ${x.weekly} (ours ${x.ours})`).join(" · ")}
        {p.pairs.length > 6 ? <span className="dim"> +{p.pairs.length - 6} more</span> : null}</div>
      {p.biggest_airports.length ? <div className="cpline"><span className="dim">Biggest airports:</span> {p.biggest_airports.map((x) => `${x.code} ${n0(x.weekly)}`).join(" · ")}</div> : null}
    </div>
  );
}
