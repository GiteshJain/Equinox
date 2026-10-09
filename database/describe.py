"""Makes the table guide, docs/data.md, from the database's own descriptions (decision #10).

Usage:
  psql "$DB" -X -At -f database/describe.sql | python3 database/describe.py           writes docs/data.md
  psql "$DB" -X -At -f database/describe.sql | python3 database/describe.py --check   fails if anything has no
      description, or if docs/data.md doesn't match the database
Run by the database rehearsal (#8) on every pull request that changes the database.
"""
import difflib, json, pathlib, sys

GUIDE = pathlib.Path(__file__).resolve().parent.parent / "docs" / "data.md"
NEVER_BACKED_UP = {"ingest_secret", "capture_keys", "report_access"}   # equinox-backups scripts/config.sh


def render(d):
    rel, fns = d["relations"], d["functions"]
    out = ["# The database, table by table", "",
           "Generated from the database's own descriptions by `database/describe.py`. Don't edit by hand: change the",
           "description in a migration (`comment on table ...`), and the database rehearsal regenerates and checks this",
           "file. How the parts fit together: `docs/architecture.md`.", "",
           f"{sum(r['kind'] == 'table' for r in rel)} tables, {sum(r['kind'] == 'view' for r in rel)} views and "
           f"{len(fns)} functions, all in Supabase's `public` schema. Website photos and logos are files in the "
           "`site-photos` storage bucket, not tables.", "", "## Contents", ""]
    for r in rel:
        out.append(f"- [`{r['name']}`](#{r['name'].replace('_', '-')}) ({r['kind']}): {(r['description'] or '').split('. ')[0].rstrip('.')}")
    out += ["- [Functions](#functions)", ""]
    for r in rel:
        out += [f"## {r['name']}", "", f"*{r['kind'].capitalize()}.* {r['description'] or '**No description.**'}", ""]
        if r["name"] in NEVER_BACKED_UP:
            out += ["Never leaves the database: left out of the nightly backup on purpose.", ""]
        out += ["| Column | Type | Notes |", "|---|---|---|"]
        out += [f"| `{c['name']}` | {c['type']} | {c['description'] or ''} |" for c in r["columns"] or []]
        out.append("")
        if r["kind"] == "table":
            pol = r["policies"] or []
            out.append("**Access:** " + ("; ".join(pol) if pol else "no policies, so only the database's own functions and "
                                          "the server can read or write it") + ".")
            out.append("")
        if r["triggers"]:
            out += ["**Triggers:** " + ", ".join(sorted(r["triggers"])) + ".", ""]
    out += ["## Functions", "",
            "*Runs as owner* means the function can do what its caller couldn't do directly, so it checks permission itself.",
            "", "| Function | Returns | Who can call it | What it does |", "|---|---|---|---|"]
    for f in fns:
        who = ", ".join(sorted(f["callable_by"] or [])) or "internal only"
        out.append(f"| `{f['name']}({f['args']})` | {f['returns']} | {who}{' · runs as owner' if f['definer'] else ''} | "
                   f"{f['description'] or '**No description.**'} |")
    return "\n".join(out) + "\n"


def main():
    d = json.loads(sys.stdin.read())
    missing = [f"{r['kind']} {r['name']}" for r in d["relations"] if not r["description"]]
    missing += [f"function {f['name']}({f['args']})" for f in d["functions"] if not f["description"]]
    text = render(d)
    if "--check" not in sys.argv:
        GUIDE.write_text(text)
        print(f"wrote {GUIDE.relative_to(GUIDE.parent.parent)} ({len(d['relations'])} tables and views, {len(d['functions'])} functions)")
    ok = True
    if missing:
        ok = False
        print("FAIL  no description for: " + ", ".join(missing))
        print("      add one in the migration: comment on table|view|function ... is '...';")
    if "--check" in sys.argv:
        have = GUIDE.read_text() if GUIDE.exists() else ""
        if have != text:
            ok = False
            diff = list(difflib.unified_diff(have.splitlines(), text.splitlines(), "docs/data.md (committed)", "the database", lineterm="", n=0))
            print("FAIL  docs/data.md doesn't match the database; regenerate it with database/describe.py")
            print("\n".join("      " + x for x in diff[:30]))
        elif not missing:
            print(f"ok    every table, view and function is described, and docs/data.md matches ({len(d['relations'])} + {len(d['functions'])})")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
