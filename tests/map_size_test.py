"""The map stays slim (to-do 209, agreed by Gitesh on 11 Nov in the Audit chat, the reading load, option C).

Every Building chat and every build helper reads the map, `docs/architecture.md`, before it starts. On 11 Nov it was
155,000 characters, 98,000 of them the parts table. Each part's detail now lives in its own file under `docs/map/`,
and this check keeps the map from growing back:
- the whole map at most MAP_MAX characters;
- each row of the parts table at most ROW_MAX characters (a few lines and a link; the detail goes in the part's file);
- every `map/<part>.md` link in the map points at a file that exists, and every file in `docs/map/` is linked;
- the map still has "Which call answers which question", which the rehearsal's guide test reads
  (`tests/briefing_copy_test.py`).

If this fails, move the new detail into the part's own file (`docs/map/<part>.md`) instead of raising the limits.

Usage: python3 tests/map_size_test.py
"""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAP = ROOT / "docs" / "architecture.md"
PARTS = ROOT / "docs" / "map"
MAP_MAX = 70_000
ROW_MAX = 1_200

failed = False


def check(ok, what):
    global failed
    print(("ok    " if ok else "FAIL  ") + what)
    failed |= not ok


text = MAP.read_text()
check(len(text) <= MAP_MAX, f"the map is {len(text):,} characters (at most {MAP_MAX:,})")

table = re.search(r"(?ms)^## The parts\n(.*?)(?=^## )", text)
check(table is not None, "the map has its parts table (## The parts)")
rows = [l for l in (table.group(1).splitlines() if table else []) if l.startswith("| **")]
check(len(rows) > 0, f"the parts table has {len(rows)} rows")
for row in rows:
    name = row.split("|")[1].strip().strip("*")
    check(len(row) <= ROW_MAX, f"{name}: its row is {len(row):,} characters (at most {ROW_MAX:,})")

linked = set(re.findall(r"\]\(map/([a-z0-9-]+\.md)\)", text))
files = {p.name for p in PARTS.glob("*.md")}
for name in sorted(linked):
    check(name in files, f"map/{name} is linked from the map and exists")
for name in sorted(files - linked):
    check(False, f"docs/map/{name} is linked from the map")

check(re.search(r"(?m)^## Which call answers which question$", text) is not None,
      "the map keeps \"Which call answers which question\" (the rehearsal's guide test reads it)")

sys.exit(1 if failed else 0)
