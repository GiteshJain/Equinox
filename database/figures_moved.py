"""Which captured figures a pull request's database changes move, on the rehearsal's copy (spec
docs/specs/2026-10-15-small-fixes.md §1: "say which figures move and by how much on last night's copy").

Usage (database/rehearse.sh runs it after the database tests, with FIGURES_DIR set):
  psql "$DB" -X -At -f database/figures_moved.sql | python3 database/figures_moved.py --out <dir>/figures_moved.md

Reads one JSON document, {"as_of", "before", "after", "payments_named"}: before and after each hold figures
(private.fig_export() at one moment) and money (the flight-money views and the last two weeks of daily history per
airline), saved before the changes (database/tests/before/figures_before.sql) and worked out again after them;
payments_named lists the payments whose kind the changes changed. Writes every value that moved, with its value before
and after and the change, and those payments, to --out (the run's figures-moved artifact, kept a few days and never
committed: it holds live figures). Prints only how many moved and where (section and airline), never a figure, since
the log is posted on the pull request.
"""
import json, pathlib, sys

# fields that name a list's item, so items are matched by what they are, not by where they stand in the list
ID_KEYS = ("airline_id", "airline", "code", "route_id", "route", "hub", "dest", "registration", "type", "date", "day", "id", "key")


def ident(item):
    if not isinstance(item, dict):
        return None
    parts = [f"{k}={item[k]}" for k in ID_KEYS if isinstance(item.get(k), (str, int)) and not isinstance(item.get(k), bool)]
    return ", ".join(parts) or None


def walk(path, b, a, out):
    if isinstance(b, dict) and isinstance(a, dict):
        for k in list(b) + [k for k in a if k not in b]:
            walk(path + [k], b.get(k, MISSING), a.get(k, MISSING), out)
    elif isinstance(b, list) and isinstance(a, list):
        ib, ia = [ident(x) for x in b], [ident(x) for x in a]
        if all(ib) and all(ia) and len(set(ib)) == len(ib) and len(set(ia)) == len(ia):
            mb, ma = dict(zip(ib, b)), dict(zip(ia, a))
            for k in ib + [k for k in ia if k not in mb]:
                walk(path + [f"[{k}]"], mb.get(k, MISSING), ma.get(k, MISSING), out)
        elif all(not isinstance(x, (dict, list)) for x in b + a):
            if b != a:
                out.append((path, b, a))
        else:
            for i in range(max(len(b), len(a))):
                walk(path + [f"[{i}]"], b[i] if i < len(b) else MISSING, a[i] if i < len(a) else MISSING, out)
    elif b != a:
        out.append((path, b, a))


MISSING = object()


def show(v):
    if v is MISSING:
        return "(none)"
    if isinstance(v, float):
        return f"{v:.6g}"
    if isinstance(v, (dict, list)):
        s = json.dumps(v)
        return s if len(s) <= 80 else s[:77] + "..."
    return str(v)


def change(b, a):
    if isinstance(b, (int, float)) and isinstance(a, (int, float)) and not isinstance(b, bool) and not isinstance(a, bool):
        return f"{a - b:+.6g}"
    return ""


def main():
    out_path = None
    if "--out" in sys.argv:
        out_path = pathlib.Path(sys.argv[sys.argv.index("--out") + 1])
    doc = json.load(sys.stdin)
    before, after, as_of = doc.get("before"), doc.get("after"), doc.get("as_of")
    names = {}
    for a in ((after or {}).get("figures") or {}).get("airlines") or []:
        names[str(a.get("airline_id"))] = a.get("code") or a.get("name") or str(a.get("airline_id"))
    moved = []
    walk([], before, after, moved)
    moved = [m for m in moved if m[0] and m[0][-1] != "as_of"]

    def label(path):
        s = ""
        for p in path:
            if p.startswith("["):
                parts = p[1:-1].split(", ")
                al = next((x[11:] for x in parts if x.startswith("airline_id=") and x[11:] in names), None)
                if al:   # an airline by its code, without its id and code again
                    parts = [names[al]] + [x for x in parts if not x.startswith(("airline_id=", "code="))]
                s += f"[{', '.join(parts)}]"
            else:
                s += ("." if s else "") + p
        return s

    def where(path):   # the section and, inside the airlines' list, the airline: counts only, for the log
        pre, p = (path[0] + ".", path[1:]) if path[0] in ("figures", "money") and len(path) > 1 else ("", path)
        if p[0] == "airlines" and len(p) > 2:
            return pre + f"{label(p[:2])}.{p[2]}"
        return pre + p[0]

    counts = {}
    for p, _, _ in moved:
        counts[where(p)] = counts.get(where(p), 0) + 1
    lines = [f"# Figures moved by the changes, on the rehearsal's copy", "",
             f"Every captured figure (`private.fig_export()`) as of {as_of} (the copy's latest capture plus an hour), "
             "before the pull request's database changes and after them, in millions of AS$ as the figures give them; and the "
             "flight-money views (`game_flight_pnl` summed per airline, `game_ops_recent`) and the last two weeks of daily history "
             "(`airline_days`), in AS$ (`money`).", ""]
    named = doc.get("payments_named") or []
    if named:
        lines += ["Payments whose kind the changes changed, per airline (AS$; `ops_window_from` is where each airline's 24 hours "
                  "of `game_ops_recent` start):", "",
                  "| " + " | ".join(named[0].keys()) + " |", "|" + "---|" * len(named[0])]
        lines += ["| " + " | ".join(show(v) for v in x.values()) + " |" for x in named]
        lines.append("")
    if not moved:
        lines.append("Nothing moved.")
    else:
        lines += [f"{len(moved)} values moved.", "", "| Where | Count |", "|---|---|"]
        lines += [f"| `{k}` | {v} |" for k, v in sorted(counts.items())]
        lines += ["", "| Figure | Before | After | Change |", "|---|---|---|---|"]
        lines += [f"| `{label(p)}` | {show(b)} | {show(a)} | {change(b, a)} |" for p, b, a in moved]
    if out_path:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text("\n".join(lines) + "\n")
    if not moved:
        print(f"ok    no captured figure moved (as of {as_of})")
    else:
        print(f"      {len(moved)} values moved (as of {as_of}), by where: "
              + "; ".join(f"{k} {v}" for k, v in sorted(counts.items()))
              + ". Before and after are in the run's figures-moved artifact, never in this log.")


if __name__ == "__main__":
    main()
