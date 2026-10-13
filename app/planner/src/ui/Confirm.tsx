// A question asked in the page, never in a browser dialog: the words and two buttons, the first doing it.
import type { ReactNode } from "react";

export function Confirm({ question, yes, no = "Keep", onYes, onNo }: {
  question: string;
  yes: string;
  no?: string;
  onYes: () => void;
  onNo: () => void;
}) {
  return (
    <span className="confirm" role="alertdialog" aria-label={question} data-confirm>
      <span className="cq">{question}</span>
      <button type="button" className="danger sm" onClick={onYes} data-confirm-yes>{yes}</button>
      <button type="button" className="secondary sm" onClick={onNo} data-confirm-no>{no}</button>
    </span>
  );
}

/** The same question as a block, with what it would do listed under it (Routes: removing routes, an offset change and
 *  the flights it moves). */
export function ConfirmPanel({ question, yes, no = "Keep", onYes, onNo, children, busy = false }: {
  question: string;
  yes: string;
  no?: string;
  onYes: () => void;
  onNo: () => void;
  children?: ReactNode;
  busy?: boolean;
}) {
  return (
    <div className="qpanel" role="alertdialog" aria-label={question} data-confirm>
      <span className="cq">{question}</span>
      {children}
      <div className="qbtn">
        <button type="button" className="danger sm" onClick={onYes} disabled={busy} data-confirm-yes>{yes}</button>
        <button type="button" className="secondary sm" onClick={onNo} disabled={busy} data-confirm-no>{no}</button>
      </div>
    </div>
  );
}
