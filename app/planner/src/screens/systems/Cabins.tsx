// Systems → Cabins (Check's until 20 Oct; the old cabinsBoard): each aircraft's cabin against what its markets want (the library's cabins.fit),
// with "Refitted to …" (the aircraft takes the layout and the refit's cost, cabin_refit_cost, is logged as a loss), "Keep as
// is" (until its routes call for a different cabin), and the ones kept, each with "Show again".
import type { CabinFit } from "@rules";
import { AirlineMark } from "../../ui/AirlineMark";
import { niceDate } from "../../ui/dates";
import type { OurAirline } from "../../data/airlines";
import { costWords, haveWords, keepKey, mixWords } from "./model";

export function CabinsList({ list, airlines, cost, sharePct, busy, onRefit, onKeep, onUndo, onAircraft }: {
  list: readonly CabinFit[];
  airlines: readonly OurAirline[];
  cost: number;
  sharePct: number;
  busy: boolean;
  onRefit: (x: CabinFit) => void;
  onKeep: (x: CabinFit) => void;
  onUndo: (x: CabinFit) => void;
  onAircraft: (registration: string) => void;
}) {
  const color = (id: number) => airlines.find((a) => a.id === id)?.color;
  const open = list.filter((x) => !x.kept), kept = list.filter((x) => x.kept);
  const strong = open.filter((x) => x.strong);
  const hidden = kept.length ? (
    <details className="gsub">
      <summary className="dim">{kept.length} kept as is</summary>
      <div className="tblwrap">
        <table className="tbl">
          <tbody>
            <tr><th>Aircraft</th><th>Cabin</th><th>Its markets want</th><th>Kept since</th><th></th></tr>
            {kept.map((x) => (
              <tr key={keepKey(x)}>
                <td><AirlineMark color={color(x.airline_id)} /><b>{x.registration}</b></td>
                <td>{haveWords(x)}</td>
                <td>{x.want} <span className="dim">{x.share}%</span></td>
                <td className="dim">{niceDate(x.kept_on)}</td>
                <td className="n"><button type="button" className="link" data-cabundo={keepKey(x)} disabled={busy} onClick={() => onUndo(x)}>Show again</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </details>
  ) : null;
  if (!open.length) {
    return <><div className="empty">{list.length ? "Nothing left to decide — the rest are kept as they are." : "Every aircraft's cabin matches the markets it flies."}</div>{hidden}</>;
  }
  return (
    <>
      <div className="tblwrap">
        <table className="tbl">
          <tbody>
            <tr><th>Aircraft</th><th>Cabin now</th><th>Its markets want</th><th>Share of its flying</th><th>All its markets</th><th></th></tr>
            {open.map((x) => (
              <tr key={keepKey(x)} data-cabin={x.registration}>
                <td><AirlineMark color={color(x.airline_id)} /><button type="button" className="link" data-tailm={x.registration} onClick={() => onAircraft(x.registration)}><b>{x.registration}</b></button></td>
                <td>{haveWords(x)} <span className="dim">{x.have_code}</span></td>
                <td><b>{x.want}</b></td>
                <td>{x.strong ? <span className="pill warn sm">{x.share}%</span> : <span className="dim">{x.share}%</span>}</td>
                <td className="dim">{mixWords(x)}</td>
                <td className="n ooact">
                  {x.target
                    ? <button type="button" className="primary sm" data-refit={`${x.registration}|${x.target.code}`} disabled={busy} onClick={() => onRefit(x)}
                      title={`Log a refit to ${x.target.code} done in the game: changes the aircraft's cabin here and counts ${costWords(cost)} as a loss against that day's profit`}>Refitted to {x.target.code}</button>
                    : <span className="dim">no {x.want} cabin for this type</span>}{" "}
                  <button type="button" className="secondary sm" data-cabkeep={keepKey(x)} disabled={busy} onClick={() => onKeep(x)}
                    title="Leave this cabin as it is; it only comes back if the aircraft's routes start calling for a different cabin">Keep as is</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="note">{strong.length} aircraft fly {sharePct}%+ of their time in markets that want a different cabin — those are the refits that pay. Mixed days are better left as they are: "Keep as is" takes them off the list.</div>
      {hidden}
    </>
  );
}
