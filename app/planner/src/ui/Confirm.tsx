// A question asked in the page, never in a browser dialog: the words and two buttons, the first doing it.
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
