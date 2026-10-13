// The deliveries board (the old planner's renderDeliveries) and a plan card (planCard): every aircraft with a delivery,
// on order, arrived and not yet scheduled, or flying, for the airline and the Tails filters above (base and type), with
// its own status filter (open by default); each with its plan card (title, base, legs with their numbers, route, local
// times, block and service), and File into planner once it has arrived. Filing itself is Filing.tsx.
import { AirlineMark } from "../../ui/AirlineMark";
import { niceDate } from "../../ui/dates";
import { comingIn, type CardLeg, type DeliveryRow, type DeliveryStatus, type PlanCardRow, type TailAirline } from "./model";

const STATUS: readonly [DeliveryStatus, string][] = [["", "Open"], ["on order", "On order"], ["unscheduled", "Arrived"], ["flying", "Flying"]];
const pad = (n: number) => String(n).padStart(2, "0");

export function PlanCard({ reg, base, title, type, config, card, legs, filed, canFile, busy, onFile }: {
  reg: string; base: string; title: string; type: string; config: string; card: PlanCardRow; legs: readonly CardLeg[]; filed: boolean; canFile: boolean; busy: boolean;
  onFile: () => void;
}) {
  return (
    <div className="pcard" data-plan-card={reg}>
      <div className="pch"><b>{reg} · {card.base_code || base} — {card.title || title}</b><span>{type}{config ? " · " + config : ""}</span></div>
      <div className="tblwrap">
        <table className="tbl pt">
          <tbody>
            <tr><th>Flight</th><th>Route</th><th>Departs</th><th>Arrives</th><th>Block</th><th>Service</th></tr>
            {legs.map((l) => <tr key={l.row.id} data-card-leg><td><b>{l.no}</b></td><td>{l.from}–{l.to}</td><td>{l.dep}</td><td>{l.arr}</td><td>{l.block}</td><td>{l.svc}</td></tr>)}
          </tbody>
        </table>
      </div>
      <div className="pfoot">
        {card.note ?? ""}
        {filed ? <> <span className="pill ok">in the planner</span></>
          : canFile ? <> <button type="button" className="primary sm" data-planfile={reg} disabled={busy} onClick={onFile}>File into planner</button></> : null}
      </div>
    </div>
  );
}

export function Deliveries({ all, shown, airline, filters, open, legsOf, filed, busy, now, onStatus, onCard, onFile }: {
  all: readonly DeliveryRow[];
  shown: readonly DeliveryRow[];
  airline: TailAirline | undefined;
  filters: { base: string; type: string; del: DeliveryStatus };
  open: string;
  legsOf: (card: PlanCardRow) => CardLeg[];
  filed: (aircraftId: number) => boolean;
  busy: boolean;
  now: number;
  onStatus: (s: DeliveryStatus) => void;
  onCard: (reg: string) => void;
  onFile: (r: DeliveryRow) => void;
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
                  <td className="n">{r.card ? <button type="button" className="link" data-plancard={r.a.registration} onClick={() => onCard(r.a.registration)}>{open === r.a.registration ? "hide card" : "card"}</button> : null}</td>
                </tr>,
                open === r.a.registration && r.card ? (
                  <tr className="planrow" key={r.a.id + "-card"}>
                    <td colSpan={8}>
                      <PlanCard reg={r.a.registration} base={r.base} title={r.plan} type={r.type} config={r.config} card={r.card} legs={r.card ? legsOf(r.card) : []}
                        filed={filed(r.a.id)} canFile={arrived && now > 0} busy={busy} onFile={() => onFile(r)} />
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
