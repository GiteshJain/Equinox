// The deliveries board's lines (since 28 Oct; spec docs/specs/2026-10-27-long-haul-lines.md §2; manual §4, long haul in
// lines): each 7-day line of the airline, with its slots (offset 0 to 6, the aircraft holding each, ordered, arrived,
// filed or empty), the line's check across the cards that exist (the library's card.checkLine: the weekdays still missing
// until all 7 exist, every flight daily, each route both ways, no false flight-number clash), and Write the next card:
// an aircraft of the line's airline and type on order without a card gets one at the next free offset, its legs each line
// leg on its weekday (card.fromLine), as one planner_save() call. A slot's aircraft opens its plan card. Lines are added
// by the Scheduling chat with SQL from optimise-line's answer (scripts/README.md); the board only shows them.
import { useState } from "react";
import { SLOT_WORDS, lineCheckWords, type LineCheck, type LineSlot, type PlanLineRow, type TailAircraft } from "./model";

export interface LineView {
  line: PlanLineRow;
  type: string;
  legs: number;
  slots: LineSlot[];
  check: LineCheck;
  next: number | null;
  candidates: TailAircraft[];
}

const PILL = { ordered: "mute", arrived: "warn", filed: "ok", empty: "" } as const;

export function Lines({ views, busy, open, onCard, onWrite }: {
  views: readonly LineView[];
  busy: boolean;
  /** The registration whose card is open. */
  open: string;
  onCard: (reg: string) => void;
  onWrite: (v: LineView, a: TailAircraft) => void;
}) {
  if (!views.length) return null;
  return (
    <div className="tlines" data-figure="tails: lines">
      <h4 className="tlh">Lines <span className="note">7 aircraft of one type, each a day apart, so every flight flies daily · a card's offset is the day it starts on</span></h4>
      {views.map((v) => <LineBlock key={v.line.id} v={v} busy={busy} open={open} onCard={onCard} onWrite={onWrite} />)}
    </div>
  );
}

function LineBlock({ v, busy, open, onCard, onWrite }: { v: LineView; busy: boolean; open: string; onCard: (reg: string) => void; onWrite: (v: LineView, a: TailAircraft) => void }) {
  const [pick, setPick] = useState("");
  const size = v.slots.length;
  const words = lineCheckWords(v.check, size);
  const held = v.slots.filter((s) => s.state !== "empty").length;
  const chosen = v.candidates.find((a) => a.registration === pick) ?? v.candidates[0];
  return (
    <div className="tline" data-line={v.line.name} data-line-id={v.line.id}>
      <div className="tlhead">
        <b>{v.line.name}</b>
        <span className="pill mute sm">{v.type}</span>
        <span className="pill mute sm" data-line-count={held}>{held} of {size} aircraft</span>
        <span className={"pill sm " + words.level} data-line-check={words.level} title={words.problems.join("\n") || undefined}>{words.text}</span>
        <span className="dim">{v.legs} flights a week each</span>
      </div>
      <div className="tlslots" role="list">
        {v.slots.map((s) => (
          <div key={s.offset} role="listitem" className={"tlslot" + (s.state === "empty" ? " empty" : "") + (s.aircraft && open === s.aircraft.registration ? " sel" : "")}
            data-line-slot={s.offset} data-slot-state={s.state} data-slot-reg={s.aircraft?.registration ?? ""}
            title={s.retired.length ? `before: ${s.retired.join(", ")} (retired)` : undefined}>
            <span className="tlday">Day {s.offset + 1}</span>
            {s.aircraft && s.card ? (
              <button type="button" className="link tlreg" onClick={() => onCard(s.aircraft?.registration ?? "")}>{s.aircraft.registration}</button>
            ) : <span className="dim tlreg">—</span>}
            <span className={"pill sm " + PILL[s.state]}>{SLOT_WORDS[s.state]}</span>
          </div>
        ))}
      </div>
      {words.problems.length ? (
        <ul className="tlprob" data-line-problems>{words.problems.slice(0, 6).map((p, i) => <li key={i}>{p}</li>)}
          {words.problems.length > 6 ? <li className="dim">and {words.problems.length - 6} more</li> : null}</ul>
      ) : null}
      <div className="tlfoot">
        {v.next == null ? <span className="dim">Every place has an aircraft.</span>
          : !v.candidates.length ? <span className="dim">Next card: day {v.next + 1}. No {v.type} of this airline on order without a card.</span>
          : <>
            <label className="dim">Next card, day {v.next + 1}, for{" "}
              <select data-line-pick={v.line.id} value={chosen?.registration ?? ""} disabled={busy} onChange={(e) => setPick(e.target.value)}>
                {v.candidates.map((a) => <option key={a.id} value={a.registration}>{a.registration}</option>)}
              </select>
            </label>{" "}
            <button type="button" className="primary sm" data-line-write={v.line.id} disabled={busy || !chosen} onClick={() => { if (chosen) onWrite(v, chosen); }}>Write the next card</button>
          </>}
      </div>
    </div>
  );
}

/** On a plan card of a line: the line, the card's place on it (offset and day) and its slot's state. */
export function CardLine({ v, offset }: { v: LineView | undefined; offset: number | null | undefined }) {
  if (!v || offset == null) return null;
  const slot = v.slots[offset];
  return (
    <div className="pcline" data-card-line={v.line.name} data-card-offset={offset}>
      <b>Line {v.line.name}</b> · aircraft {offset + 1} of {v.slots.length} (offset {offset}: it flies line day d on weekday d + {offset})
      {slot ? <> · slot <span className={"pill sm " + PILL[slot.state]} data-card-slot={slot.state}>{SLOT_WORDS[slot.state]}</span></> : null}
    </div>
  );
}
