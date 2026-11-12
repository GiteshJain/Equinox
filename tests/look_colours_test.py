#!/usr/bin/env python3
"""Typed-in colours don't grow (to-do 225, spec docs/specs/2026-11-11-glass-look.md, step 1, check 3).

Counts the colour values typed in directly (hex #rgb, #rgba, #rrggbb, #rrggbbaa, and rgb()/rgba() with numbers) in the
planner's stylesheet, outside its :root blocks of named colours, and in the planner's code (app/planner/src, .ts and
.tsx, not the tests). Fails when either count is over its ceiling below. Each step of the glass look replaces its
screens' typed-in colours with named ones and lowers the ceilings to its new counts, saying both in its pull request;
step 6 ends at 0 in the stylesheet and only the globe's in the code.

Run from the repository root: python3 tests/look_colours_test.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHEET = ROOT / "app/planner/src/ui/styles.css"
CODE = ROOT / "app/planner/src"

# The ceilings, with the date each was set. Started at a0be3d4 (11 Nov): 412 in the stylesheet (the spec says 413: it counted
# one inside a comment), 113 in the code.
CEILING_SHEET = 152   # 12 Nov, glass look step 5 (Photos, Reference and Systems; Competition and Interline: 170, Performance: 174, Routes and the route story: 227, step 2: 316, step 1: 350)
CEILING_CODE = 47     # 12 Nov, glass look step 5 (Systems' charts through the kit: TONE, SYS; Competition: 56, Performance: 65, Routes: 101, step 2: 104, step 1: 113)

COLOUR = re.compile(r"#[0-9a-fA-F]{8}\b|#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3,4}\b|rgba?\(\s*[0-9][^)]*\)")


def strip_comments(css):
    return re.sub(r"/\*.*?\*/", "", css, flags=re.S)


def sheet_count(css):
    """Colours in the stylesheet outside any rule whose selector starts with :root (the named colours' blocks)."""
    css = strip_comments(css)
    # drop data: URLs (their colours are %23-encoded anyway, but be sure)
    css = re.sub(r"url\((['\"]?)data:.*?\1\)", "url()", css, flags=re.S)
    out, i = [], 0
    for m in re.finditer(r":root[^{]*\{[^{}]*\}", css):
        out.append(css[i:m.start()])
        i = m.end()
    out.append(css[i:])
    return len(COLOUR.findall("".join(out)))


def code_count(src):
    n, files = 0, 0
    for p in sorted(src.rglob("*.ts*")):
        if p.suffix not in (".ts", ".tsx") or ".test." in p.name:
            continue
        k = len(COLOUR.findall(p.read_text(encoding="utf-8")))
        if k:
            n += k
            files += 1
    return n, files


def selftest():
    css = ":root{--a:#fff;--b:rgba(1,2,3,.5)}\n@media (x){:root{--c:#000}}\n/* #abc */\n.x{color:#123456;background:url(\"data:image/svg+xml,%23fff\")}\n:root[data-look=\"glass\"]{--a:#000}\n.y{fill:rgb(1, 2, 3)}"
    assert sheet_count(css) == 2, sheet_count(css)
    assert len(COLOUR.findall("#eqhero #f-q #rev-expall #fade")) == 1   # #fade is hex; ids rarely are
    return True


def main():
    selftest()
    sheet = sheet_count(SHEET.read_text(encoding="utf-8"))
    code, files = code_count(CODE)
    problems = []
    if sheet > CEILING_SHEET:
        problems.append(f"the stylesheet has {sheet} typed-in colours, over its ceiling of {CEILING_SHEET}: use a named colour")
    if code > CEILING_CODE:
        problems.append(f"the planner's code has {code} typed-in colours ({files} files), over its ceiling of {CEILING_CODE}: use a named colour")
    print(f"typed-in colours: stylesheet {sheet} (ceiling {CEILING_SHEET}), code {code} in {files} files (ceiling {CEILING_CODE})")
    if sheet < CEILING_SHEET or code < CEILING_CODE:
        print("  (under the ceiling: lower it to the new count in this pull request)")
    for p in problems:
        print("FAIL  " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
