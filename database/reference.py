"""Keeps the database's reference file, database/current/functions.sql, in step with the database (spec
docs/specs/2026-10-15-small-fixes.md §3: it had drifted, four of build pull request 10's functions missing; spec
docs/specs/2026-10-15-last-leftovers.md §4: five more were a version behind or written differently, which a check of the
names alone couldn't see).

Usage (database/rehearse.sh runs it on the copy after the changes):
  psql "$DB" -X -At -f database/reference.sql | python3 database/reference.py --check [--out <file>]
--check fails unless the file lists exactly the database's functions in public and private, each by its schema, name and
arguments, each with the definition the database gives it (pg_get_functiondef(): its arguments, settings and body),
compared ignoring whitespace. Each entry in the file is a line "-- <name>(<arguments>)" (public's without the schema,
private's as "private.<name>"), with the arguments as pg_get_function_identity_arguments() gives them, then the definition
starting "CREATE OR REPLACE FUNCTION <schema>.<name>(" on the next line, up to the ";" line that closes the entry. --out
writes every definition as the database gives it, in the file's format and order (public, then private, each by name): the
run's current-functions artifact, to copy a missing or changed function from. Prints names only.
"""
import json, pathlib, re, sys

FILE = pathlib.Path(__file__).resolve().parent / "current" / "functions.sql"
CREATE = re.compile(r"(?i)^create\s+(?:or\s+replace\s+)?function\s+(?:([a-z_][a-z0-9_]*)\.)?([a-z_][a-z0-9_]*)\s*\(")
HEADER = re.compile(r"^-- (?:([a-z_][a-z0-9_]*)\.)?([a-z_][a-z0-9_]*)\((.*)\)\s*$")


def listed(text):
    """The file's entries as (schema.name(arguments), definition), and the entries whose line above doesn't name them. An
    entry's definition runs from its CREATE line to the next entry's line (or the end), without the closing ";"."""
    lines, found, bad = text.split("\n"), [], []
    for i, line in enumerate(lines):
        m = CREATE.match(line)
        if not m:
            continue
        schema, name = (m.group(1) or "public").lower(), m.group(2).lower()
        h = HEADER.match(lines[i - 1]) if i > 0 else None
        if not h or h.group(2) != name or (h.group(1) or "public") != schema:
            bad.append(f"{schema}.{name} (line {i + 1}: the line above isn't \"-- {'' if schema == 'public' else schema + '.'}{name}(<arguments>)\")")
            continue
        found.append((i, f"{schema}.{name}({h.group(3)})"))
    entries = []
    for k, (i, key) in enumerate(found):
        end = found[k + 1][0] - 1 if k + 1 < len(found) else len(lines)   # the next entry's "-- name(...)" line
        body = "\n".join(lines[i:end]).rstrip()
        if body.endswith(";"):
            body = body[:-1].rstrip()
        entries.append((key, body))
    return entries, bad


def same(a, b):
    """Two definitions the same, ignoring whitespace."""
    return re.sub(r"\s+", "", a or "") == re.sub(r"\s+", "", b or "")


def entry(f):
    head = f["name"] if f["schema"] == "public" else f"{f['schema']}.{f['name']}"
    return f"-- {head}({f['args']})\n{(f['definition'] or '').rstrip(chr(10))}\n\n;\n\n"


def main():
    fns = json.load(sys.stdin)
    if "--out" in sys.argv:
        out = pathlib.Path(sys.argv[sys.argv.index("--out") + 1])
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text("".join(entry(f) for f in fns if f.get("definition")))
    if "--check" not in sys.argv:
        return 0
    copy = {f"{f['schema']}.{f['name']}({f['args']})": f.get("definition") for f in fns}
    entries, bad = listed(FILE.read_text())
    keys = [k for k, _ in entries]
    twice = sorted({k for k in keys if keys.count(k) > 1})
    missing, stale = sorted(set(copy) - set(keys)), sorted(set(keys) - set(copy))
    # a function the file has, whose definition isn't the copy's: a version behind, or written by hand
    differ = sorted({k for k, d in entries if k in copy and copy[k] is not None and not same(d, copy[k])})
    rel = "database/current/functions.sql"
    if not (missing or stale or bad or twice or differ):
        n_pub = sum(1 for f in fns if f["schema"] == "public")
        print(f"ok    {rel} lists the copy's {len(fns)} functions ({n_pub} in public, {len(fns) - n_pub} in private), no more, "
              "each as the copy defines it (ignoring whitespace)")
        return 0
    print(f"FAIL  {rel} doesn't hold the copy's functions as they are after the changes:")
    for label, xs in (("in the copy, missing from the file", missing), ("in the file, not in the copy", stale),
                      ("in the file twice", twice), ("entries without their line", bad),
                      ("defined otherwise in the file than in the copy (a version behind, or written by hand)", differ)):
        if xs:
            print(f"      {label} ({len(xs)}): " + ", ".join(xs))
    print("      add, change or remove their entries (the copy's definitions are in the run's current-functions artifact)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
