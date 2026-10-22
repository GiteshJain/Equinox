// One frequency on a route, as the old planner's renderFreq draws it: the outbound and the return (times local or UTC as
// the header says, the other small; block, typed or est; the day markers), each with its flight's loads over 7 days;
// then every check from the library (night bans, a number used twice, bank fit at both ends, the turn at the
// destination; and, as the spec asks, the aircraft's position and the second-daily gap, which the old screen didn't
// show); the connections at both ends; and the form, each field saving on its own as one action. Since the new look
// (spec docs/specs/2026-10-22-planner-look-routes.md §5) it opens with its aircraft, named "N003AW (JFK)", and its numbers.
import { useState, type KeyboardEvent, type FocusEvent } from "react";
import type { FrequencyChecks, ConnectingFlight } from "@rules";
import { AirlineMark } from "../../ui/AirlineMark";
import { Confirm } from "../../ui/Confirm";
import { Pill } from "../../ui/Pill";
import { alt, daysWords, disp, fmt, hhmm, tailName, type Airline, type Freq, type FreqField, type Load, type Mode, type Route } from "./model";
import { LoadChip, WavePill } from "./parts";

export interface FreqProps {
  f: Freq;
  route: Route;
  checks: FrequencyChecks | null;
  mode: Mode;
  /** Each flight's loads, by number. */
  flightLoad: (no: number | null) => Load | undefined;
  airlines: readonly Airline[];
  /** The airline's aircraft in service, in the old planner's tails order. */
  tails: readonly string[];
  services: readonly string[];
  serviceDefault: string;
  priceDefault: number | null;
  /** The airport's minimum connection time and the longest wait, for the connections' note. */
  connectionNote: (code: string) => string;
  /** Whether an airport is any airline's base (the destination's connections show then even when empty). */
  isBase: (code: string) => boolean;
  turnMargin: number;
  onChange: (field: FreqField, value: string) => void;
  onDelete: () => void;
  /** Opens the aircraft's pop-up (Tails' AircraftPopup; build pull request 12). */
  onOpenTail?: (registration: string) => void;
  busy: boolean;
}

/** An input that saves on change (blur or Enter), as the old planner's change events: its value comes from the database. */
function Field({ k, label, value, placeholder, type, wide, onChange, disabled }: {
  k: FreqField; label: string; value: string; placeholder?: string; type?: string; wide?: boolean; disabled?: boolean;
  onChange: (field: FreqField, value: string) => void;
}) {
  const done = (e: FocusEvent<HTMLInputElement>) => { if (e.currentTarget.value !== value) onChange(k, e.currentTarget.value); };
  const enter = (e: KeyboardEvent<HTMLInputElement>) => { if (e.key === "Enter") e.currentTarget.blur(); };
  return (
    <label className={wide ? "wide" : undefined}>{label}
      <input key={value} data-k={k} defaultValue={value} placeholder={placeholder} type={type} onBlur={done} onKeyDown={enter} disabled={disabled}
        maxLength={k === "days" ? 7 : undefined} />
    </label>
  );
}

function Select({ k, label, value, options, empty, onChange, disabled }: {
  k: FreqField; label: string; value: string; options: readonly string[]; empty?: string; disabled?: boolean;
  onChange: (field: FreqField, value: string) => void;
}) {
  const list = value && !options.includes(value) ? [...options, value] : options;
  return (
    <label>{label}
      <select key={value} data-k={k} defaultValue={value} onChange={(e) => onChange(k, e.currentTarget.value)} disabled={disabled}>
        {empty != null ? <option value="">{empty}</option> : null}
        {list.map((o) => <option key={o} value={o}>{o}</option>)}
      </select>
    </label>
  );
}

const SIX = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"];

export function Frequency(p: FreqProps) {
  const { f, route: r, mode } = p;
  const v = f.view, z = mode === "utc" ? "Z" : "";
  const [asking, setAsking] = useState(false);
  const dur = (w: { block: number; est: boolean }) => `${hhmm(w.block)}${w.est ? " est" : ""}`;
  const ch = p.checks;
  const nameOf = (id: number) => p.airlines.find((a) => a.id === id)?.name ?? "";
  const colorOf = (id: number) => p.airlines.find((a) => a.id === id)?.color ?? null;
  const legNo = (id: number) => (id === f.leg1?.id ? f.noOut : id === f.leg2?.id ? f.noBack : null);

  // the connections at both ends (the old connBlock): at the hub the return's arrival onward and the outbound's
  // feeders; at the destination the outbound's arrival onward and the return's feeders
  const conn = (legId: number | undefined) => ch?.connections.find((c) => c.leg_id === legId);
  const out = ch?.legs[0] ?? null, back = ch?.legs[1] ?? null;
  const section = (ap: string, arrLeg: typeof out, depLeg: typeof out, arrLocal: number | null, depLocal: number | null, always: boolean) => {
    const on = arrLeg ? conn(arrLeg.id)?.onward ?? [] : [], fd = depLeg ? conn(depLeg.id)?.feeders ?? [] : [];
    if (!always && !on.length && !fd.length) return null;
    const others = [...new Set([...on, ...fd].filter((x) => x.airline_id !== r.airline_id).map((x) => nameOf(x.airline_id)))];
    const table = (rows: ConnectingFlight[], kind: "on" | "fd") => (
      <div className="tblwrap"><table className="tbl cxt">
        <tbody>
          <tr><th>Flight</th><th>{kind === "on" ? "To" : "From"}</th><th>{kind === "on" ? "Departs" : "Arrives"}</th><th>Connection</th><th>Days</th></tr>
          {rows.map((x) => (
            <tr key={x.leg_id}>
              <td><AirlineMark color={colorOf(x.airline_id)} /><b>{x.flight_no ?? ""}</b></td><td>{kind === "on" ? x.dest : x.origin}</td>
              <td>{fmt(x.local_min)}</td><td>{hhmm(x.gap_min)}</td><td className="dim">{daysWords(x)}</td>
            </tr>
          ))}
        </tbody>
      </table></div>
    );
    const parts = [arrLeg && arrLocal != null ? <span key="a">arrival {fmt(arrLocal)} → <b>{on.length}</b> onward</span> : null,
      depLeg && depLocal != null ? <span key="d">departure {fmt(depLocal)} ← <b>{fd.length}</b> feeding</span> : null].filter(Boolean);
    return (
      <details className="cx" data-cx={ap}>
        <summary>
          <span className="cxap">At {ap}</span> {parts.flatMap((x, i) => (i ? [" · ", x] : [x]))}
          {others.length ? <> <span className="dim">incl. {others.join(", ")}</span></> : null}
        </summary>
        {on.length && arrLocal != null ? <><div className="cxh">Onward from {ap} after the {fmt(arrLocal)} arrival</div>{table(on, "on")}</> : null}
        {fd.length && depLocal != null ? <><div className="cxh">Feeding the {fmt(depLocal)} departure from {ap}</div>{table(fd, "fd")}</> : null}
        {!on.length && !fd.length ? <div className="dim" style={{ padding: "6px 0" }}>Nothing in the group connects here yet.</div> : null}
        <div className="note">{p.connectionNote(ap)}, across all {SIX[p.airlines.length] ?? p.airlines.length} airlines, by day of the week. Local times at {ap}.</div>
      </details>
    );
  };
  const hubSection = section(r.hub, back, out, v.back?.arr ?? null, v.out?.dep ?? null, true);
  const destSection = section(r.dest, out, back, v.out?.arr ?? null, v.back?.dep ?? null, p.isBase(r.dest));

  const turnPill = ch?.turn_dest?.short ? <Pill kind="bad">turn {v.ground_dest} min at {r.dest}</Pill>
    : ch?.turn_dest?.tight ? <Pill kind="warn">turn {v.ground_dest} min at {r.dest} — under the {p.turnMargin}-min margin</Pill>
      : v.ground_dest != null ? <Pill kind="mute">{v.ground_dest} min on the ground at {r.dest}</Pill> : null;
  const label = (x: { origin: string; dest: string }) => `${x.origin}–${x.dest}`;
  const reg = f.aircraft?.registration ?? "";

  return (
    <div className="freq" data-f={f.rot.legacy_key ?? String(f.rot.id)} data-rotation={f.rot.id} data-figure="routes: frequency">
      <div className="fhead">
        {reg ? <b className="ftail">{tailName(reg, r.hub)}</b> : <b className="ftail dim">No aircraft yet</b>}
        <span className="fnos">{f.noOut || "—"} / {f.noBack || "—"}</span>
        <span className="fdays dim">{f.local.days.length === 7 ? "daily" : f.local.days.length ? f.local.days.join("") : "no days yet"}</span>
      </div>
      <div className="fl" data-line="out">
        <span className="no">{f.noOut || "—"}</span>{" "}
        {v.out ? <>
          {r.hub} {disp(v.out.dep, v.offset_hub_min, mode)}{z} → {r.dest} {disp(v.out.arr, v.offset_dest_min, mode)}{z}{v.out.arr_day ? " +" + v.out.arr_day : ""}{" "}
          <span className="blk">{dur(v.out)}</span> <span className="alt">{alt(v.out.dep, v.offset_hub_min, mode)}</span> <span className="alt">{alt(v.out.arr, v.offset_dest_min, mode)}</span>
        </> : "type the outbound departure"}{" "}
        <LoadChip a={p.flightLoad(f.noOut)} />
      </div>
      <div className="fl" data-line="back">
        <span className="no">{f.noBack || "—"}</span>{" "}
        {v.back ? <>
          {r.dest} {disp(v.back.dep, v.offset_dest_min, mode)}{z}{v.back.dep_day ? " +" + v.back.dep_day : ""} → {r.hub} {disp(v.back.arr, v.offset_hub_min, mode)}{z}{v.back.arr_day ? " +" + v.back.arr_day : ""}{" "}
          <span className="blk">{dur(v.back)}</span> <span className="alt">{alt(v.back.dep, v.offset_dest_min, mode)}</span> <span className="alt">{alt(v.back.arr, v.offset_hub_min, mode)}</span>
        </> : "type the return departure"}{" "}
        <LoadChip a={p.flightLoad(f.noBack)} />
      </div>
      {ch && ch.night_bans.length ? (
        <div className="fl" data-line="bans">
          {ch.night_bans.map((b, i) => <Pill key={i} kind="bad">night ban at {b.airport} ({b.ban}) — {b.what} {b.local}</Pill>)}
        </div>
      ) : null}
      {(ch?.flight_numbers ?? []).map((x, i) => (
        <div className="fl" key={"c" + i} data-line="clash"><Pill kind="bad">{x.flight_no} also flies {label(x)} on the same days</Pill></div>
      ))}
      <div className="fl" data-line="fit">
        <WavePill w={f.wave} />{f.waveDest ? <> at {r.dest} <WavePill w={f.waveDest} /></> : null}{turnPill}
      </div>
      {ch && (ch.positions.length || ch.route_gaps.length) ? (
        <div className="fl" data-line="more" data-check="added">
          {ch.positions.map((x, i) => (
            <Pill key={"p" + i} kind="bad">{reg || "the aircraft"} isn't at {x.at} for its next flight after {x.flight_no ?? ""}: it leaves from {x.next_from} ({x.times_week}× a week)</Pill>
          ))}
          {ch.route_gaps.map((x, i) => (
            <Pill key={"g" + i} kind={x.rule === "same_route_gap_min" ? "bad" : "warn"}>
              {legNo(x.leg_id) ?? ""} leaves {hhmm(x.gap_min)} from {x.flight_no ?? "another flight"} on {label(x)} — {x.rule === "same_route_gap_min" ? "the game's gap" : "a second daily"} needs {hhmm(x.need_min)}
            </Pill>
          ))}
        </div>
      ) : null}
      {hubSection || destSection ? <div className="cxw">{hubSection}{destSection}</div> : null}
      <div className="fg">
        <Field k="days" label="Days" value={f.local.days.join("")} placeholder="1234567" onChange={p.onChange} disabled={p.busy} />
        <Select k="tail" label="Tail" value={reg} options={p.tails} empty="—" onChange={p.onChange} disabled={p.busy} />
        {reg && p.onOpenTail ? <button type="button" className="link tailpop" data-tailm={reg} title={`${reg}'s week, maintenance and flights`}
          onClick={() => p.onOpenTail?.(reg)}>{reg} ›</button> : null}
        <Field k="noOut" label="No. out" type="number" value={f.leg1?.flight_no != null ? String(f.leg1.flight_no) : ""} onChange={p.onChange} disabled={p.busy} />
        <Field k="noBack" label="No. back" type="number" value={f.leg2?.flight_no != null ? String(f.leg2.flight_no) : ""}
          placeholder={f.noOut ? String(f.noOut - 1) : ""} onChange={p.onChange} disabled={p.busy} />
        <Field k="depHub" label={`Dep ${r.hub}${z}`} value={disp(f.local.dep_hub, v.offset_hub_min, mode)} placeholder="hh:mm" onChange={p.onChange} disabled={p.busy} />
        <Field k="arrDest" label={`Arr ${r.dest}${z}`} value={disp(f.local.arr_dest, v.offset_dest_min, mode)}
          placeholder={v.out && v.out.est ? disp(v.out.arr, v.offset_dest_min, mode) + " est" : "hh:mm"} onChange={p.onChange} disabled={p.busy} />
        <Field k="depDest" label={`Dep ${r.dest}${z}`} value={disp(f.local.dep_dest, v.offset_dest_min, mode)} placeholder="hh:mm" onChange={p.onChange} disabled={p.busy} />
        <Field k="arrHub" label={`Arr ${r.hub}${z}`} value={disp(f.local.arr_hub, v.offset_hub_min, mode)}
          placeholder={v.back && v.back.est ? disp(v.back.arr, v.offset_hub_min, mode) + " est" : "hh:mm"} onChange={p.onChange} disabled={p.busy} />
        <Select k="service" label="Service" value={f.rot.service_code || p.serviceDefault} options={p.services} onChange={p.onChange} disabled={p.busy} />
        <Field k="price" label="Price %" type="number" value={f.rot.fare_pct != null ? String(Number(f.rot.fare_pct)) : p.priceDefault != null ? String(p.priceDefault) : ""}
          onChange={p.onChange} disabled={p.busy} />
        <Field k="slfOut" label="SLF out" type="number" value={extra(f, "slfOut")} onChange={p.onChange} disabled={p.busy} />
        <Field k="slfBack" label="SLF back" type="number" value={extra(f, "slfBack")} onChange={p.onChange} disabled={p.busy} />
        <Field k="launched" label="Launched" type="date" value={f.rot.launched_on ?? ""} onChange={p.onChange} disabled={p.busy} />
        <Field k="notes" label="Notes" wide value={f.rot.note ?? ""} onChange={p.onChange} disabled={p.busy} />
        {asking ? <Confirm question="Remove this frequency?" yes="Remove" onYes={() => { setAsking(false); p.onDelete(); }} onNo={() => setAsking(false)} />
          : <button type="button" className="danger" data-del={f.rot.id} onClick={() => setAsking(true)} disabled={p.busy}>Remove</button>}
      </div>
    </div>
  );
}

function extra(f: Freq, k: string): string {
  const e = f.rot.extra;
  const x = e && typeof e === "object" && !Array.isArray(e) ? (e as Record<string, unknown>)[k] : undefined;
  return x == null ? "" : String(x);
}
