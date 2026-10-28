// The deliveries board (the old planner's renderDeliveries) and a plan card (planCard): every aircraft with a delivery,
// on order, arrived and not yet scheduled, or flying, for the airline and the Tails filters above (base and type), with
// its own status filter (open by default); each with its plan card (title, base, legs with their numbers, route, local
// times, block and service), and File into planner once it has arrived. Filing itself is Filing.tsx. A leg whose service
// code isn't the one its route's distance calls for (or has none) shows it as an issue on the leg ("S1, wants S3"; the
// plan card's service check, #18 build pull request 10). The card carries its cabin (since 18 Oct), chosen with its routes:
// it shows beside the type ("no cabin chosen" when neither the card nor the order names one), and until the aircraft is
// filed the card's Cabin box sets it; filing fits that cabin and logs its first fit at its price. Since 18 Oct a card opens
// in its own window over the board (the rest of the screen dimmed, as the old planner's did), and an airport where the
// airline has no station yet (stationsOf(): none of its active flights touch it; since 22 Oct its bases and point-to-point
// stations don't count on their own) is highlighted on the card. Since 21 Oct
// (spec docs/specs/2026-10-21-cabins-new-rule.md §3) the card says which cabin the rule calls for beside its Cabin box
// ("suggested: 321-LP", with the reason; the library's card.cabinFor), Use the suggestion sets it (the card-cabin save),
// and a cabin that differs from it shows in amber. Since 21 Oct too (manual §5; spec
// docs/specs/2026-10-21-frequencies-and-fares.md §2) its Fare column gives the fare level of each route it flies, once per
// route on the route's first leg ("economy +10%, business +5% of the default price", "launch (+0% of the default price)"
// for a route not flown yet; the library's card.cardFares on fare_ladder()), so a new flight is priced like its route.
// Since 23 Oct (spec docs/specs/2026-10-23-planner-look-tails.md) restyled: a row with a plan card opens it when tapped
// (card stays too), the card's head carries the type, cabin and flight count as pills, its legs table and the footer
// (Cabin box, the suggestion with Use the suggestion, File into planner) are spaced as the other screens'; on a phone
// each delivery is a block. Every field, check, the station highlight and every save are as before. Since 28 Oct (spec
// docs/specs/2026-10-27-long-haul-lines.md §2) the board shows the airline's 7-day lines over the deliveries (Lines.tsx:
// each line's slots, its check and Write the next card), and a card on a line says which line, its offset and its slot's
// state, with each leg's local weekdays (a line's card flies each leg on one day).
import { useEffect } from "react";
import type { CabinSuggestion } from "@rules";
import { AirlineMark } from "../../ui/AirlineMark";
import { niceDate } from "../../ui/dates";
import { CardLine, Lines, type LineView } from "./Lines";
import { cabinDiffers, comingIn, daysLabel, suggestionWords, type CardLeg, type DeliveryRow, type DeliveryStatus, type PlanCardRow, type TailAircraft, type TailAirline } from "./model";

const STATUS: readonly [DeliveryStatus, string][] = [["", "Open"], ["on order", "On order"], ["unscheduled", "Arrived"], ["flying", "Flying"]];
const pad = (n: number) => String(n).padStart(2, "0");

/** An airport code, highlighted when the airline has no station there yet. */
function Stn({ code, stations }: { code: string; stations?: ReadonlySet<string> }) {
  return stations && !stations.has(code) ? <span className="newstn" data-new-station={code} title="no station here yet for this airline">{code}</span> : <>{code}</>;
}

/** A card's title ("BTV + CHS + SAV"), each airport code in it highlighted when the airline has no station there yet. */
function StnText({ text, stations }: { text: string; stations?: ReadonlySet<string> }) {
  if (!stations) return <>{text}</>;
  return <>{text.split(/\b([A-Z]{3})\b/).map((part, i) => (i % 2 ? <Stn key={i} code={part} stations={stations} /> : part))}</>;
}

export function PlanCard({ reg, base, title, type, config, card, legs, service, fares, filed, canFile, busy, onFile, cabins, cardCabin, onCabin, stations, suggestion, line }: {
  reg: string; base: string; title: string; type: string; config: string; card: PlanCardRow; legs: readonly CardLeg[]; filed: boolean; canFile: boolean; busy: boolean;
  /** Each leg's service issue, by its row id. */
  service?: ReadonlyMap<number, string>;
  /** Each route's fare level, on the first of its legs (by the leg's row id); none until fare_ladder() is read. */
  fares?: ReadonlyMap<number, string>;
  onFile: () => void;
  /** The cabins the card may choose from (the airline's for the type), the card's own (its code, "" for none), and choosing one. */
  cabins?: readonly string[];
  cardCabin?: string;
  onCabin?: (code: string) => void;
  /** The airports where the airline has a station; the others are highlighted. */
  stations?: ReadonlySet<string>;
  /** The cabin the rule calls for (the library's card.cabinFor), when it can be worked out. */
  suggestion?: CabinSuggestion | null;
  /** The line the card flies (since 28 Oct), when it is on one. */
  line?: LineView;
}) {
  // a line's card flies each leg on its own weekday: the legs show their local days (since 28 Oct)
  const byDay = legs.some((l) => l.days !== "1234567");
  const sw = filed ? null : suggestionWords(suggestion ?? null);
  const differs = !filed && cabinDiffers(suggestion ?? null, config);
  return (
    <div className="pcard" data-plan-card={reg}>
      <div className="pch"><b>{reg} · {card.base_code || base} — <StnText text={card.title || title} stations={stations} /></b><span className="pchtags"><span className="pill mute sm">{type}</span> {config
        ? <span className={differs ? "pill warn sm" : undefined} data-card-cabin={config} data-card-cabin-differs={differs ? "yes" : undefined}
          title={differs && suggestion?.code ? `the rule calls for ${suggestion.code}` : undefined}>{config}</span>
        : <span className="pill warn sm" data-card-cabin="">no cabin chosen</span>}{legs.length ? <> <span className="pill mute sm">{legs.length} flight{legs.length === 1 ? "" : "s"}</span></> : null}</span></div>
      <CardLine v={line} offset={card.line_day_offset} />
      <div className="tblwrap">
        <table className="tbl pt">
          <tbody>
            <tr><th>Flight</th><th>Route</th>{byDay ? <th>Day</th> : null}<th>Departs</th><th>Arrives</th><th>Block</th><th>Service</th>{fares?.size ? <th>Fare level</th> : null}</tr>
            {legs.map((l) => {
              const issue = service?.get(l.row.id), fare = fares?.get(l.row.id);
              return (
                <tr key={l.row.id} data-card-leg><td><b>{l.no}</b></td><td><Stn code={l.from} stations={stations} />–<Stn code={l.to} stations={stations} /></td>{byDay ? <td data-card-leg-days={l.days}>{daysLabel(l.days)}</td> : null}<td>{l.dep}</td><td>{l.arr}</td><td>{l.block}</td>
                  <td>{l.svc}{issue ? <> <span className="pill bad sm" data-service-issue title="the service code its route's distance calls for">{issue}</span></> : null}</td>
                  {fares?.size ? <td className="dim" data-card-fare={fare ? `${l.from}-${l.to}` : undefined}
                    title={fare ? "set each new flight's fare to this in the game: Ticket price adjustment, default price" : undefined}>{fare ?? ""}</td> : null}</tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <div className="pfoot">
        {!filed && onCabin && cabins?.length ? (
          <label className="dim pcab">Cabin{" "}
            <select data-card-cabin-pick={reg} value={cardCabin ?? ""} disabled={busy} onChange={(e) => onCabin(e.target.value)}>
              <option value="">{cardCabin ? "none" : "choose…"}</option>
              {cabins.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>{" "}
          </label>
        ) : null}
        {sw && suggestion?.code ? (
          <span className="cabsug" data-card-suggest={suggestion.code}>
            <b>{sw.text}</b> <span className="dim">{sw.reason}</span>
            {onCabin && cardCabin !== suggestion.code ? <>{" "}
              <button type="button" className="secondary sm" data-card-suggest-use={reg} disabled={busy} onClick={() => onCabin(suggestion.code ?? "")}>Use the suggestion</button></> : null}
          </span>
        ) : null}
        {card.note ? <span className="pnote">{card.note}</span> : null}
        {filed ? <> <span className="pill ok">in the planner</span></>
          : canFile ? <> <button type="button" className="primary sm" data-planfile={reg} disabled={busy} onClick={onFile}>File into planner</button></> : null}
      </div>
    </div>
  );
}

export function Deliveries({ all, shown, airline, filters, open, legsOf, serviceOf, filed, busy, now, onStatus, onCard, onFile, onRemove, cabinsFor, cabinCode, onCabin, stations,
  suggestionOf, faresOf, lines = [], onWriteLine }: {
  all: readonly DeliveryRow[];
  shown: readonly DeliveryRow[];
  airline: TailAirline | undefined;
  filters: { base: string; type: string; del: DeliveryStatus };
  open: string;
  legsOf: (card: PlanCardRow) => CardLeg[];
  /** Each leg's service issue on a card, by the leg's row id. */
  serviceOf?: (card: PlanCardRow, legs: readonly CardLeg[]) => ReadonlyMap<number, string>;
  filed: (aircraftId: number) => boolean;
  busy: boolean;
  now: number;
  onStatus: (s: DeliveryStatus) => void;
  onCard: (reg: string) => void;
  onFile: (r: DeliveryRow) => void;
  /** remove (the old data-deldel): the aircraft leaves the list of deliveries. */
  onRemove: (r: DeliveryRow) => void;
  /** The cabins a card may choose (the airline's for its type), a card's own cabin's code, and choosing one ("" clears it). */
  cabinsFor?: (r: DeliveryRow) => readonly string[];
  cabinCode?: (card: PlanCardRow) => string;
  onCabin?: (r: DeliveryRow, code: string) => void;
  /** The airports where the airline has a station. */
  stations?: ReadonlySet<string>;
  /** The cabin the rule calls for on a card (the library's card.cabinFor), or null. */
  suggestionOf?: (r: DeliveryRow) => CabinSuggestion | null;
  /** Each route's fare level on a card, on the first of its legs (by the leg's row id). */
  faresOf?: (card: PlanCardRow, legs: readonly CardLeg[]) => ReadonlyMap<number, string>;
  /** The airline's 7-day lines (since 28 Oct), with their slots and check, and writing a line's next card. */
  lines?: readonly LineView[];
  onWriteLine?: (v: LineView, a: TailAircraft) => void;
}) {
  const shownCard = shown.find((r) => r.a.registration === open && r.card);
  // Escape closes an open card
  useEffect(() => {
    if (!shownCard) return;
    const k = (e: KeyboardEvent) => { if (e.key === "Escape") onCard(shownCard.a.registration); };
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, [shownCard, onCard]);
  const openCount = all.filter((r) => r.status !== "flying").length;
  const head = (
    <h3 className="rh">Deliveries <span className="note">{openCount} aircraft on order or waiting to be scheduled · tap one to open its plan card · flying aircraft drop off this list on their own (the Flying filter shows them) · Claude fills this from your delivery reports</span></h3>
  );
  const lineBoard = lines.length ? <Lines views={lines} busy={busy} open={open} onCard={onCard} onWrite={(v, a) => onWriteLine?.(v, a)} /> : null;
  if (!all.some((r) => r.a.airline_id === airline?.id)) {
    return (
      <div className="board tdel" id="deliveries" data-figure="tails: deliveries">
        {head}
        {lineBoard}
        <div className="dim">Nothing on order for {airline?.name ?? ""}. Send a delivery report and each aircraft appears here with its date, base and plan card.</div>
      </div>
    );
  }
  return (
    <div className="board tdel" id="deliveries" data-figure="tails: deliveries">
      {head}
      <div className="chips" data-chips="deliveries">
        <span className="chiplbl">Status</span>
        {STATUS.map(([k, l]) => <button type="button" key={l} className={"chip" + (filters.del === k ? " on" : "")} data-df="status" data-v={k} onClick={() => onStatus(k)}>{l}</button>)}
        <span className="dim" style={{ marginLeft: 12 }}>showing {airline?.name ?? ""}{filters.base ? " · " + filters.base : ""}{filters.type ? " · " + filters.type : ""}</span>
      </div>
      {lineBoard}
      <div className="tblwrap">
        <table className="tbl deltbl">
          <tbody>
            <tr><th>Reg</th><th>Airline</th><th>Type · config</th><th>Delivery</th><th>Base</th><th>Plan card</th><th>Status</th><th></th></tr>
            {!shown.length ? (
              <tr><td colSpan={8} className="dim">No {filters.del === "flying" ? "flying" : "open"} deliveries for {airline?.name ?? ""}{filters.base || filters.type ? " with those filters" : ""}.</td></tr>
            ) : null}
            {shown.map((r) => {
              const at = Number.isFinite(r.at) ? new Date(r.at) : null;
              return [
                <tr key={r.a.id} data-delivery={r.a.registration} className={(r.card ? "dopen" : "") + (open === r.a.registration ? " sel" : "")}
                  onClick={r.card ? (e) => { if (!(e.target as HTMLElement).closest("button")) onCard(r.a.registration); } : undefined}>
                  <td className="dreg"><b>{r.a.registration}</b></td>
                  <td className="dal"><AirlineMark color={r.airline?.color} /> {r.airline?.name ?? ""}</td>
                  <td className="dty">{r.type} {r.config ? "· " + r.config : ""}</td>
                  <td className="dwhen">{at ? <>{niceDate(r.due)} <span className="dim">{pad(at.getUTCHours())}:{pad(at.getUTCMinutes())} UTC</span></> : r.due ? niceDate(r.due) : "—"}
                    {comingIn(r.hrs) ? <> <span className="dim">· {comingIn(r.hrs)}</span></> : null}</td>
                  <td className="dbase">{r.base}</td>
                  <td className="dim dplan">{r.plan}</td>
                  <td className="dst"><span className={"pill " + (r.status === "unscheduled" ? "bad" : r.status === "flying" ? "ok" : "mute")}>{r.status === "unscheduled" ? "arrived — not scheduled" : r.status}</span></td>
                  <td className="n dact">{r.card ? <><button type="button" className="link" data-plancard={r.a.registration} onClick={() => onCard(r.a.registration)}>{open === r.a.registration ? "hide card" : "card"}</button>{" · "}</> : null}
                    <button type="button" className="link" data-deldel={r.a.registration} disabled={busy} onClick={() => onRemove(r)}>remove</button></td>
                </tr>,
              ];
            })}
          </tbody>
        </table>
      </div>
      {shownCard ? (
        <div className="mback" onClick={(e) => { if (e.target === e.currentTarget) onCard(shownCard.a.registration); }}>
          <div className="modal pcmodal" role="dialog" aria-modal="true" aria-label={`Plan card ${shownCard.a.registration}`}>
            <div className="mhead"><div><AirlineMark color={shownCard.airline?.color} /><b>Plan card · {shownCard.a.registration}</b></div>
              <button type="button" className="mx" aria-label="Close" onClick={() => onCard(shownCard.a.registration)}>×</button></div>
            <div className="mbody">
              <CardRow r={shownCard} legsOf={legsOf} serviceOf={serviceOf} faresOf={faresOf} filed={filed(shownCard.a.id)} canFile={shownCard.status !== "on order" && now > 0} busy={busy}
                onFile={() => onFile(shownCard)} cabins={cabinsFor?.(shownCard)} cardCabin={shownCard.card ? cabinCode?.(shownCard.card) : undefined}
                onCabin={onCabin ? (c) => onCabin(shownCard, c) : undefined} stations={stations} suggestion={suggestionOf?.(shownCard) ?? null}
                line={shownCard.card?.line_id != null ? lines.find((v) => v.line.id === shownCard.card?.line_id) : undefined} />
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

function CardRow({ r, legsOf, serviceOf, faresOf, filed, canFile, busy, onFile, cabins, cardCabin, onCabin, stations, suggestion, line }: {
  r: DeliveryRow; legsOf: (card: PlanCardRow) => CardLeg[]; serviceOf?: (card: PlanCardRow, legs: readonly CardLeg[]) => ReadonlyMap<number, string>;
  faresOf?: (card: PlanCardRow, legs: readonly CardLeg[]) => ReadonlyMap<number, string>;
  filed: boolean; canFile: boolean; busy: boolean; onFile: () => void;
  cabins?: readonly string[]; cardCabin?: string; onCabin?: (code: string) => void; stations?: ReadonlySet<string>; suggestion?: CabinSuggestion | null; line?: LineView;
}) {
  if (!r.card) return null;
  const legs = legsOf(r.card);
  return <PlanCard reg={r.a.registration} base={r.base} title={r.plan} type={r.type} config={r.config} card={r.card} legs={legs} service={serviceOf?.(r.card, legs)}
    fares={faresOf?.(r.card, legs)}
    filed={filed} canFile={canFile} busy={busy} onFile={onFile} cabins={cabins} cardCabin={cardCabin} onCabin={onCabin} stations={stations} suggestion={suggestion} line={line} />;
}
