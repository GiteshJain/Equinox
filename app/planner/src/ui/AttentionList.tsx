// The needs-attention list: one group's items (Today's count tiles open a group's list, since 22 Oct, spec
// docs/specs/2026-10-22-planner-look-today.md §4). Each item links to where it's fixed and has × to dismiss it.
import { Link } from "react-router";
import { attKind, dismissKey, type AttItem } from "./attention";

type Open = (a: AttItem) => boolean;

function Item({ a, href, onDismiss, onOpen, busy }: { a: AttItem; href: string; onDismiss: (a: AttItem) => void; onOpen?: Open; busy: boolean }) {
  const key = dismissKey(a);
  return (
    <li className={a.cls} data-att-item data-att-kind={attKind(a)} data-att-key={key} data-cls={a.cls} data-screen={a.screen}
      data-tail={a.tail ?? ""} data-route={a.route ?? ""}>
      <Link className="link" to={href} onClick={(e) => { if (onOpen?.(a)) e.preventDefault(); }}>{a.text}</Link>
      <button type="button" className="dismiss" title="Dismiss" aria-label={"Dismiss: " + a.text} disabled={busy}
        onClick={() => onDismiss(a)}>×</button>
    </li>
  );
}

/** One group's items as a flat list, as Today's count tiles open them (since 22 Oct). */
export function AttentionItems({ items, hrefOf, onDismiss, onOpen, busy = false }: {
  items: readonly AttItem[];
  hrefOf: (a: AttItem) => string;
  onDismiss: (a: AttItem) => void;
  onOpen?: Open;
  busy?: boolean;
}) {
  return (
    <ul className="att">
      {items.map((a, i) => <Item key={`${i}|${dismissKey(a)}`} a={a} href={hrefOf(a)} onDismiss={onDismiss} onOpen={onOpen} busy={busy} />)}
    </ul>
  );
}
