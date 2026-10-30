// Competition (spec docs/specs/2026-10-21-competition-analysis.md §3; manual §3, market share first): "who are we up
// against, and where do we open next?". Every figure is competition()'s (the database's), at the screen's moment.
// Laid out since 23 Oct (spec docs/specs/2026-10-23-planner-look-competition.md) answer-first, as Today, Systems and
// Performance:
//   - The group (/planner/competition): the title is the group's headline, our departures' share of the world's
//     ("4.1% of the world's departures"), with the scans' dates beside it as a small pill ("latest scan 17 Oct, compared
//     with 6 Oct") and the group line under it. Then one tile per airline (three a row, two under 1100 px, one on a
//     phone: its share across its markets with its arrow, its threats and its top opening in one line; tap to open it)
//     and every airline's threats as one table (airline, rival, pair, the numbers, the day and the link to the route's
//     page on Performance), newest first; on a phone each threat is a compact row. Since 23 Oct (spec
//     docs/specs/2026-10-23-rival-fleets.md §5) the board Order books under it: the rivals with a big order book or
//     starting with orders (competition()'s order_flags), biggest share first, each marked with the airlines it meets.
//   - Since 30 Oct (spec docs/specs/2026-10-30-market-pages-planner.md §4) each market card, and each airline's tile on the
//     group page, shows the game's passenger share where its pairs have market reads ("game share 38.0% (pairs read: 2
//     of 3)"), beside the scan's departures share, never replacing it.
//   - An airline (/planner/competition/<code>): the title is its share across its markets with its arrow, the scans'
//     pill beside it, the airline switch (the segmented control Performance uses) under it. Then the sections as rows
//     that open (FoldBoard, as on Systems and Performance), each with its count: Market share (a tile per market: our
//     share with its arrow and the top rivals as a bar and a list), Threats (a table), Openings (open on arrival: the
//     ranked table, rank, pair, stars, distance, rivals, variant and hubs first as a pill, allowed or the reason, cut to
//     10 with "show all") and Rival profiles (cards; since 23 Oct each with its fleet, "99 aircraft, 44
//     on order, +6 on order this week", and its top types). Since 23 Oct (spec docs/specs/2026-10-23-rival-connections.md
//     §4) the rivals' connecting departures sit beside direct, never added: each market card's rivals "160 direct · 14
//     connecting" with the connecting airports, the openings' rivals column "3 direct · 14 connecting", and each rival
//     profile's connecting line.
// Read only: nothing here saves. Phone first: tiles stack, the openings table scrolls inside its own box.
import { useMemo, useState, type ReactNode } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { ourAirlines, type OurAirline } from "../../data/airlines";
import { useOurAirlines, useWorld } from "../../data/reads";
import { AirlineMark } from "../../ui/AirlineMark";
import { ErrorBox } from "../../ui/ErrorBox";
import { FoldBoard, FoldTools } from "../../ui/FoldBoard";
import { listCut } from "../performance/model";
import { itemRoute } from "../screens";
import {
  airlineHeadline, allowedWords, changeWords, gameShareWords, overallGameShare, connectingLine, connectingRivalsWords, dayWords, directConnectingWords, fleetTypesWords, fleetWords, groupHeadline, groupWords, kmWords, marketsRowWords, meetsWords, n0,
  openingsLine, orderBookWords, orderBooks, orderBooksRowWords, otherListsWords, overallShare, pctWords, profileWords, profilesRowWords, rivalsWords, scansWords, shareBar, starsWords, threatMoveWords, threatNumbers, threatWhen, threatsLine,
  threatsNewestFirst, threatsRowWords, topOpeningWords, trunkMonthWords, variantWords, type CompetitionAnswer, type Market, type Opening,
  type Profile, type Threat,
} from "./model";
import { useCompetition, useCompetitions } from "./reads";

const first = (...qs: { error: unknown }[]) => qs.find((q) => q.error)?.error;

/** A change with its arrow, quiet when there's nothing to compare. */
function Change({ v, points = false, k }: { v: number | null | undefined; points?: boolean; k?: string }) {
  const c = changeWords(v, points);
  if (!c) return <span className="dim" data-change={k}>no comparison yet</span>;
  return <span className={"cpch " + c.arrow} data-change={k} data-arrow={c.arrow}>{c.text}</span>;
}

/** An airline page's rows, in order; Openings open on arrival. */
const ROWS = ["Market share", "Threats", "Openings", "Rival profiles"] as const;
type RowKey = (typeof ROWS)[number];
const SHORT: Record<RowKey, string> = {
  "Market share": "Our share of each market, against the rivals",
  "Threats": "Rivals who moved onto its routes since the scan before",
  "Openings": "The routes to open next, ranked",
  "Rival profiles": "The rivals it meets most",
};

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
  const share = isAirline && oneQ.data ? overallShare(oneQ.data.markets) : null;
  const pick = (a: OurAirline) => navigate(itemRoute("competition", { airline: a.code ?? String(a.id) }));

  return (
    <main className="view competition" data-screen="competition" data-competition-ready={ready ? "yes" : "no"} data-airline={sel?.code ?? ""}>
      <div className="vh todayvh cpvh" data-figure={top ? "competition: scans" : undefined}>
        <p className="vk">{sel ? <>Competition · {sel.name}</> : "Results"}</p>
        <div className="todayttl">
          <h1 className="ansh" data-cp-answer>
            {sel && share ? <><AirlineMark color={sel.color} size={18} />{airlineHeadline(share)}{share.change != null ? <>{" "}<Change v={share.change} points k={"share " + (sel.code ?? "")} /></> : null}</>
              : !isAirline && top ? groupHeadline(top.group) : "Competition"}
          </h1>
          {top ? <span className="pill mute cpscans" data-scans>{scansWords(top.scans)}</span> : null}
        </div>
        {top ? <GroupLine a={top} share={share} /> : (
          <p className="ansp">{sel ? "Its market share against the rivals, their moves on its routes, the routes to open next and the rivals it meets most, from the world scans."
            : "Who we're up against and where to open next: market share, the rivals' moves, the ranked openings and the rivals' profiles, from the world scans."}</p>
        )}
        {isAirline && sel ? (
          <>
            <div className="seg rseg perfseg cpseg" role="group" aria-label="Airline" data-airlines>
              {airlines.map((a) => (
                <button type="button" key={a.id} className={a.id === sel.id ? "on" : ""} aria-pressed={a.id === sel.id} data-al={a.code ?? ""} onClick={() => pick(a)}>
                  <AirlineMark color={a.color} />{a.code ?? a.name}
                </button>
              ))}
            </div>
            <Link className="link perfback cpback" to="/competition" data-back>‹ All airlines</Link>
          </>
        ) : null}
      </div>
      {loadError ? <ErrorBox error={loadError} /> : null}
      {!ready && !loadError ? <div className="empty">Loading…</div> : null}
      {isAirline && airlinesQ.data && !sel ? <div className="empty">There's no airline {code} in the planner. <Link className="link" to="/competition">All airlines</Link></div> : null}
      {!isAirline && ready ? <Group airlines={airlines} answers={answers} onPick={pick} /> : null}
      {isAirline && sel && oneQ.data ? <AirlinePage key={sel.id} airline={sel} a={oneQ.data} /> : null}
    </main>
  );
}

/** The group line under the title, on both pages; on an airline's page its own departures against the rivals' first. */
function GroupLine({ a, share }: { a: CompetitionAnswer; share: ReturnType<typeof overallShare> | null }) {
  const g = a.group;
  return (
    <p className="ansp cpgline">
      {share ? <span className="cpown" data-figure="competition: airline line">{n0(share.ours)} of {n0(share.total)} departures a week on its city pairs. </span> : null}
      <span data-figure="competition: group line">
        {groupWords(g)}{g ? <> <Change v={g.share_change} points k="group" />{g.share_before != null ? <span className="dim"> (from {pctWords(g.share_before)})</span> : null}</> : null}
      </span>
    </p>
  );
}

/** The group page: one tile per airline, then every airline's threats as one table, newest first, then the order books. */
function Group({ airlines, answers, onPick }: { airlines: readonly OurAirline[]; answers: ReadonlyMap<number, CompetitionAnswer>; onPick: (a: OurAirline) => void }) {
  const threats = threatsNewestFirst(airlines.flatMap((al) => (answers.get(al.id)?.threats ?? []).map((t) => ({ ...t, al }))));
  const books = orderBooks(airlines.map((al) => answers.get(al.id)));
  return (
    <>
      <div className="fgrid cpgrid" data-figure="competition: airlines">
        {airlines.map((al) => {
          const a = answers.get(al.id);
          if (!a) return null;
          const s = overallShare(a.markets);
          const gs = overallGameShare(a.markets);
          return (
            <button type="button" key={al.id} className="fcard cpcard" data-competition-card={al.code ?? ""} onClick={() => onPick(al)}>
              <div className="fchead">
                <div className="fch"><AirlineMark color={al.color} /><b>{al.name}</b></div>
                <div className="fbig">{pctWords(s.share)}<span className="fu"> of its markets</span></div>
                <div className="fsub"><Change v={s.change} points k={"share " + (al.code ?? "")} /> · {n0(s.ours)} of {n0(s.total)} departures a week</div>
                {gs ? <div className="fsub" data-game-share={gs.share ?? ""}>game share {pctWords(gs.share)} (pairs read: {gs.pairs_read} of {gs.pairs})</div> : null}
              </div>
              <div className="cptile">
                <span className="ffl">Threats</span>
                <span className={"cpline" + (a.threats.length ? " warn" : " dim")}>{threatsLine(a.threats.length)}</span>
              </div>
              <div className="cptile ffoot">
                <span className="ffl">Top opening</span>
                <span className="cpline cptopo" title={openingsLine(a)}>{topOpeningWords(a)}</span>
              </div>
            </button>
          );
        })}
      </div>
      <section className="perfsec cpsec" data-figure="competition: threats" data-board="Threats" aria-labelledby="cp-threats-h">
        <h2 className="perfh" id="cp-threats-h">Threats</h2>
        <p className="note perflead">Rivals who started on, or added a daily flight or more to, one of our city pairs since the scan before · each pauses the route's fares for a week (manual §5) · newest first.</p>
        <div className="cpcardbox">
          {threats.length ? <ThreatTable items={threats} /> : <div className="dim">No rival moves on our routes in the last 7 days.</div>}
        </div>
      </section>
      <section className="perfsec cpsec" data-figure="competition: order books" data-board="Order books" aria-labelledby="cp-books-h">
        <h2 className="perfh" id="cp-books-h">Order books <span className="dim cpcount">{orderBooksRowWords(books.length)}</span></h2>
        <p className="note perflead">Rivals with aircraft on order of a quarter of their fleet or more (at least 5), or on order with no flights yet, from their overview pages in the latest scan · biggest share first · each marked with our airlines it meets on their city pairs or at their bases.</p>
        <div className="cpcardbox">
          {books.length ? (
            <div className="tblwrap">
              <table className="tbl cpbooks">
                <thead><tr><th>Rival</th><th>Order book</th><th>This week</th><th>Meets</th></tr></thead>
                <tbody>
                  {books.map((f) => (
                    <tr key={f.airline_id} data-order-book={f.name} data-kind={f.kind} data-meets={f.meets ? "yes" : "no"} title={f.words}>
                      <td className="cprival"><b>{f.name}</b>{f.kind === "starting" ? <> <span className="pill warn sm">starting</span></> : null}</td>
                      <td className="cpnums">{orderBookWords(f)}</td>
                      <td className="cpday"><Change v={f.on_order_change} k={"orders " + f.name} /></td>
                      <td className="cpal">{f.meets ? <span className="pill warn sm">{meetsWords(f.meets_codes)}</span> : <span className="dim">{meetsWords([])}</span>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : <div className="dim">No rival has a big order book or orders without flights in the latest scan.</div>}
        </div>
      </section>
    </>
  );
}

/** One airline's page: market share, threats, openings and rival profiles, as rows that open; Openings open on arrival. */
function AirlinePage({ airline, a }: { airline: OurAirline; a: CompetitionAnswer }) {
  const before = dayWords(a.scans.week_before?.taken_at);
  const [folded, setFolded] = useState<ReadonlySet<RowKey>>(() => new Set(ROWS.filter((k) => k !== "Openings")));
  const toggle = (k: RowKey) => setFolded((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const row = (k: RowKey, lead: ReactNode, aside: ReactNode, children: ReactNode) => (
    <FoldBoard key={k} k={k} title={<span className="fbname">{k}</span>} note={SHORT[k]} aside={aside} folded={folded.has(k)} onToggle={() => toggle(k)}
      figure={`competition ${airline.name}: ${k.toLowerCase()}`}><div className="note fblead">{lead}</div>{children}</FoldBoard>
  );
  const threatsAside = a.threats.length ? <span className="pill warn sm">{threatsRowWords(a.threats.length)}</span> : threatsRowWords(0);
  return (
    <section className="sysrows perfrows cprows" aria-labelledby="cprows-h">
      <div className="sysrowsh">
        <h2 className="tph" id="cprows-h">The details</h2>
        <FoldTools onCollapse={() => setFolded(new Set(ROWS))} onExpand={() => setFolded(new Set())} hint="" />
      </div>
      {row("Market share", `our departures a week against every rival's on the same city pairs (either way), by market${before ? `, against ${before}` : ""} · our own from the live schedule`,
        marketsRowWords(a.markets.length),
        a.markets.length ? (
          <div className="cpmk" data-figure="competition: markets">
            {a.markets.map((m) => <MarketCard key={m.market_id ?? "none"} m={m} />)}
          </div>
        ) : <div className="dim">No routes on the list yet.</div>)}
      {row("Threats", "rivals who started on, or added a daily flight or more to, a pair it flies since the scan before · listed for 7 days; the route's fares hold until then (manual §5)",
        threatsAside,
        a.threats.length ? <ThreatTable items={threatsNewestFirst(a.threats)} code={airline.code} /> : <div className="dim">No rival moves on its routes in the last 7 days.</div>)}
      {row("Openings", `the pairs on its list no airline of ours flies, ranked: stars, then rivals' departures a week, then the shorter distance (manual §3) · ${openingsLine(a)}`,
        `${n0(a.openings_count)} · ${n0(a.openings_allowed)} allowed`,
        <>
          {trunkMonthWords(a) ? <div className="cptrunks" data-trunk-month>{trunkMonthWords(a)}</div> : null}
          <Openings code={airline.code ?? String(airline.id)} openings={a.openings} total={a.openings_count} />
        </>)}
      {row("Rival profiles", "the rivals who fly most of its city pairs, from the latest scan", profilesRowWords(a.profiles.length),
        a.profiles.length ? (
          <div className="cpmk" data-figure="competition: profiles">
            {a.profiles.map((p) => <ProfileCard key={p.airline_id} p={p} before={before} />)}
          </div>
        ) : <div className="dim">No rival flies its city pairs in the latest scan.</div>)}
    </section>
  );
}

/** A market's tile: our share with its arrow, the top rivals as a bar and a list. */
function MarketCard({ m }: { m: Market }) {
  const bar = shareBar(m);
  return (
    <div className="cpm" data-market={m.name}>
      <div className="cpmh"><b>{m.name}</b> <span className="dim">{m.flown} of {m.pairs} pair{m.pairs === 1 ? "" : "s"} flown</span></div>
      <div className="cpmv"><b className="cpbig">{pctWords(m.share)}</b> <Change v={m.share_change} points k={"market " + m.name} />
        <span className="dim"> · ours {n0(m.ours)} of {n0(m.total)} a week</span></div>
      {gameShareWords(m.game_share) ? (
        <div className="cpline cpgame" data-game-share={m.game_share?.share ?? ""}>
          {gameShareWords(m.game_share)} <Change v={m.game_share?.change ?? null} points k={"game " + m.name} />
          <span className="dim"> · the game's own passenger share, beside the scan's departures share</span>
        </div>
      ) : null}
      {m.connecting_weekly != null ? (
        <div className="cpline cpconn" data-connecting={m.connecting_weekly}>
          <span className="dim">Rivals:</span> {directConnectingWords(m.rivals, m)}
          {connectingLine(m) ? <span className="dim"> · {connectingLine(m)}, never counted in the share</span> : null}
        </div>
      ) : null}
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

/** The threats as one table: the airline (on the group page), the rival, the pair, the numbers, the day and the link to
 *  the route's page on Performance (since 22 Oct, spec docs/specs/2026-10-21-route-page.md §3: a threat is always on a pair
 *  the airline flies). The database's words for each stay on its row (its title). On a phone each is a compact row. */
function ThreatTable({ items, code }: { items: readonly (Threat & { al?: OurAirline })[]; code?: string | null }) {
  const group = items.some((t) => t.al);
  return (
    <div className="tblwrap">
      <table className={"tbl cpthr" + (group ? " cpgrp" : "")}>
        <thead><tr>{group ? <th>Airline</th> : null}<th>Rival</th><th>Pair</th><th>Numbers</th><th>Day</th><th><span className="sr">Route page</span></th></tr></thead>
        <tbody>
          {items.map((t) => {
            const al = t.al?.code ?? code;
            return (
              <tr key={`${t.al?.id ?? ""}|${t.pair}|${t.rival_id}|${t.on}`} data-threat={t.route} data-kind={t.kind} title={t.words}>
                {group ? <td className="cpal">{t.al ? <><AirlineMark color={t.al.color} /><Link className="link" to={itemRoute("competition", { airline: t.al.code ?? String(t.al.id) })}>{t.al.code}</Link></> : null}</td> : null}
                <td className="cprival"><b>{t.rival}</b></td>
                <td className="cppair"><b>{t.route}</b></td>
                <td className="cpnums">{threatMoveWords(t)} <span className="dim">· {threatNumbers(t)}</span></td>
                <td className="cpday">{threatWhen(t)}</td>
                <td className="cplink">{al ? <Link className="link" to={itemRoute("performance", { airline: al, hub: t.hub, dest: t.dest })} data-route-page-link>{t.route} ›</Link> : null}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
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
                  <td>{o.connecting_weekly != null ? <span className="num" data-connecting={o.connecting_weekly}>{directConnectingWords(o.rivals_weekly, o)}</span>
                    : <span className="num">{n0(o.rivals_weekly)}</span>} <span className="dim">{rivalsWords(o)}</span>
                    {connectingRivalsWords(o) ? <div className="dim cpcity">connecting: {connectingRivalsWords(o)}</div> : null}</td>
                  <td>{variantWords(o.variant)}</td>
                  <td className="cphf">{al.ok ? <span className="pill ok sm" title={al.why}>{al.text}{al.why ? ` · ${al.why}` : ""}</span>
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
      {p.fleet !== undefined ? <div className="cpline" data-fleet><span className="dim">Fleet:</span> {fleetWords(p.fleet)}</div> : null}
      {fleetTypesWords(p.fleet) ? <div className="cpline cpcity" data-fleet-types>{fleetTypesWords(p.fleet)}</div> : null}
      {p.connecting_weekly != null ? (
        <div className="cpline" data-connecting={p.connecting_weekly}><span className="dim">On our pairs:</span> {directConnectingWords(p.weekly_on_pairs, p)}
          {connectingLine(p) ? <span className="dim"> · {connectingLine(p)}</span> : null}</div>
      ) : null}
      <div className="cpline"><span className="dim">Shared:</span> {p.pairs.slice(0, 6).map((x) => `${x.route} ${x.weekly} (ours ${x.ours})`).join(" · ")}
        {p.pairs.length > 6 ? <span className="dim"> +{p.pairs.length - 6} more</span> : null}</div>
      {p.biggest_airports.length ? <div className="cpline"><span className="dim">Biggest airports:</span> {p.biggest_airports.map((x) => `${x.code} ${n0(x.weekly)}`).join(" · ")}</div> : null}
    </div>
  );
}
