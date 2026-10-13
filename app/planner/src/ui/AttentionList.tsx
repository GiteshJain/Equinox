// The needs-attention list, grouped as the old planner's Home groups it: a kind with one item shows that item; a kind
// with more opens to its items. Each item links to where it's fixed and has × to dismiss it.
import { Link } from "react-router";
import { attKind, dismissKey, groupAttention, type AttItem } from "./attention";

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

export function AttentionList({ items, hrefOf, onDismiss, onOpen, busy = false }: {
  items: readonly AttItem[];
  hrefOf: (a: AttItem) => string;
  onDismiss: (a: AttItem) => void;
  /** Opens an item in the page instead of following its link (an aircraft's pop-up, as the old Home); true when it did. */
  onOpen?: Open;
  busy?: boolean;
}) {
  const groups = groupAttention(items);
  return (
    <ul className="att">
      {groups.map((g) => (g.items.length === 1 && g.items[0]
        ? <Item key={g.kind} a={g.items[0]} href={hrefOf(g.items[0])} onDismiss={onDismiss} onOpen={onOpen} busy={busy} />
        : (
          <li key={g.kind} className={`${g.cls} attg`} data-att-group={g.kind}>
            <details>
              <summary><b>{g.label}</b> <span className="dim">· {g.items.length}</span></summary>
              <ul className="att sub">
                {g.items.map((a, i) => <Item key={`${i}|${dismissKey(a)}`} a={a} href={hrefOf(a)} onDismiss={onDismiss} onOpen={onOpen} busy={busy} />)}
              </ul>
            </details>
          </li>
        )))}
    </ul>
  );
}
