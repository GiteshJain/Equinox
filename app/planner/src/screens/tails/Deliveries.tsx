// The deliveries board (the old planner's renderDeliveries) and a plan card (planCard): every aircraft with a delivery,
// on order, arrived and not yet scheduled, or flying, for the airline and the Tails filters above (base and type), with
// its own status filter (open by default); each with its plan card (title, base, legs with their numbers, route, local
// times, block and service), and File into planner once it has arrived. Filing itself is Filing.tsx. A leg whose service
// code isn't the one its route's distance calls for (or has none) shows it as an issue on the leg ("S1, wants S3"; the
// plan card's service check, #18 build pull request 10). The card carries its cabin (since 18 Oct), chosen with its routes:
// it shows beside the type ("no cabin chosen" when neither the card nor the order names one), and until the aircraft is
// filed the card's Cabin box sets it; filing fits that cabin and logs its first fit at its price.
import { AirlineMark } from "../../ui/AirlineMark";
import { niceDate } from "../../ui/dates";
import { comingIn, type CardLeg, type DeliveryRow, type DeliveryStatus, type PlanCardRow, type TailAirline } from "./model";

const STATUS: readonly [DeliveryStatus, string][] = [["", "Open"], ["on order", "On order"], ["unscheduled", "Arrived"], ["flying", "Flying"]];
const pad = (n: number) => String(n).padStart(2, "0");

export function PlanCard({ reg, base, title, type, config, card, legs, service, filed, canFile, busy, onFile, cabins, cardCabin, onCabin }: {
  reg: string; base: string; title: string; type: string; config: string; card: PlanCardRow; legs: readonly CardLeg[]; filed: boolean; canFile: boolean; busy: boolean;
  /** Each leg's service issue, by its row id. */
  service?: ReadonlyMap<number, string>;
  onFile: () => void;
  /** The cabins the card may choose from (the airline's for the type), the card's own (its code, "" for none), and choosing one. */
  cabins?: readonly string[];
  cardCabin?: string;
  onCabin?: (code: string) => void;
}) {
  return (
    <div className="pcard" data-plan-card={reg}>
      <div className="pch"><b>{reg} · {card.base_code || base} — {card.title || title}</b><span>{type} · {config ? <span data-card-cabin={config}>{config}</span> : <span className="pill warn sm" data-card-cabin="">no cabin chosen</span>}</span></div>
      <div className="tblwrap">
        <table className="tbl pt">
          <tbody>
            <tr><th>Flight</th><th>Route</th><th>Departs</th><th>Arrives</th><th>Block</th><th>Service</th></tr>
            {legs.map((l) => {
              const issue = service?.get(l.row.id);
              return (
                <tr key={l.row.id} data-card-leg><td><b>{l.no}</b></td><td>{l.from}–{l.to}</td><td>{l.dep}</td><td>{l.arr}</td><td>{l.block}</td>
                  <td>{l.svc}{issue ? <> <span className="pill bad sm" data-service-issue title="the service code its route's distance calls for">{issue}</span></> : null}</td></tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <div className="pfoot">
        {!filed && onCabin && cabins?.length ? (
          <label className="dim" style={{ marginRight: 10 }}>Cabin{" "}
            <select data-card-cabin-pick={reg} value={cardCabin ?? ""} disabled={busy} onChange={(e) => onCabin(e.target.value)}>
              <option value="">{cardCabin ? "none" : "choose…"}</option>
              {cabins.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>{" "}
          </label>
        ) : null}
        {card.note ?? ""}
        {filed ? <> <span className="pill ok">in the planner</span></>
          : canFile ? <> <button type="button" className="primary sm" data-planfile={reg} disabled={busy} onClick={onFile}>File into planner</button></> : null}
      </div>
    </div>
  );
}

export function Deliveries({ all, shown, airline, filters, open, legsOf, serviceOf, filed, busy, now, onStatus, onCard, onFile, onRemove, cabinsFor, cabinCode, onCabin }: {
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
}) {
  const openCount = all.filter((r) => r.status !== "flying").length;
  const head = (
    <h3 className="rh">Deliveries <span className="note">{openCount} aircraft on order or waiting to be scheduled · flying aircraft drop off this list on their own (the Flying filter shows them) · Claude fills this from your delivery reports</span></h3>
  );
  if (!all.some((r) => r.a.airline_id === airline?.id)) {
    return (
      <div className="board" data-figure="tails: deliveries">
        {head}
        <div className="dim">Nothing on order for {airline?.name ?? ""}. Send a delivery report and each aircraft appears here with its date, base and plan card.</div>
      </div>
    );
  }
  return (
    <div className="board" data-figure="tails: deliveries">
      {head}
      <div className="chips" data-chips="deliveries">
        <span className="chiplbl">Status</span>
        {STATUS.map(([k, l]) => <button type="button" key={l} className={"chip" + (filters.del === k ? " on" : "")} data-df="status" data-v={k} onClick={() => onStatus(k)}>{l}</button>)}
        <span className="dim" style={{ marginLeft: 12 }}>showing {airline?.name ?? ""}{filters.base ? " · " + filters.base : ""}{filters.type ? " · " + filters.type : ""}</span>
      </div>
      <div className="tblwrap">
        <table className="tbl deltbl">
          <tbody>
            <tr><th>Reg</th><th>Airline</th><th>Type · config</th><th>Delivery</th><th>Base</th><th>Plan card</th><th>Status</th><th></th></tr>
            {!shown.length ? (
              <tr><td colSpan={8} className="dim">No {filters.del === "flying" ? "flying" : "open"} deliveries for {airline?.name ?? ""}{filters.base || filters.type ? " with those filters" : ""}.</td></tr>
            ) : null}
            {shown.map((r) => {
              const at = Number.isFinite(r.at) ? new Date(r.at) : null;
              const arrived = r.status !== "on order";
              return [
                <tr key={r.a.id} data-delivery={r.a.registration}>
                  <td><b>{r.a.registration}</b></td>
                  <td><AirlineMark color={r.airline?.color} /> {r.airline?.name ?? ""}</td>
                  <td>{r.type} {r.config ? "· " + r.config : ""}</td>
                  <td>{at ? <>{niceDate(r.due)} <span className="dim">{pad(at.getUTCHours())}:{pad(at.getUTCMinutes())} UTC</span></> : r.due ? niceDate(r.due) : "—"}
                    {comingIn(r.hrs) ? <> <span className="dim">· {comingIn(r.hrs)}</span></> : null}</td>
                  <td>{r.base}</td>
                  <td className="dim">{r.plan}</td>
                  <td><span className={"pill " + (r.status === "unscheduled" ? "bad" : r.status === "flying" ? "ok" : "mute")}>{r.status === "unscheduled" ? "arrived — not scheduled" : r.status}</span></td>
                  <td className="n">{r.card ? <><button type="button" className="link" data-plancard={r.a.registration} onClick={() => onCard(r.a.registration)}>{open === r.a.registration ? "hide card" : "card"}</button>{" · "}</> : null}
                    <button type="button" className="link" data-deldel={r.a.registration} disabled={busy} onClick={() => onRemove(r)}>remove</button></td>
                </tr>,
                open === r.a.registration && r.card ? (
                  <tr className="planrow" key={r.a.id + "-card"}>
                    <td colSpan={8}>
                      <CardRow r={r} legsOf={legsOf} serviceOf={serviceOf} filed={filed(r.a.id)} canFile={arrived && now > 0} busy={busy} onFile={() => onFile(r)}
                        cabins={cabinsFor?.(r)} cardCabin={r.card ? cabinCode?.(r.card) : undefined} onCabin={onCabin ? (c) => onCabin(r, c) : undefined} />
                    </td>
                  </tr>
                ) : null,
              ];
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function CardRow({ r, legsOf, serviceOf, filed, canFile, busy, onFile, cabins, cardCabin, onCabin }: {
  r: DeliveryRow; legsOf: (card: PlanCardRow) => CardLeg[]; serviceOf?: (card: PlanCardRow, legs: readonly CardLeg[]) => ReadonlyMap<number, string>;
  filed: boolean; canFile: boolean; busy: boolean; onFile: () => void;
  cabins?: readonly string[]; cardCabin?: string; onCabin?: (code: string) => void;
}) {
  if (!r.card) return null;
  const legs = legsOf(r.card);
  return <PlanCard reg={r.a.registration} base={r.base} title={r.plan} type={r.type} config={r.config} card={r.card} legs={legs} service={serviceOf?.(r.card, legs)}
    filed={filed} canFile={canFile} busy={busy} onFile={onFile} cabins={cabins} cardCabin={cardCabin} onCabin={onCabin} />;
}
