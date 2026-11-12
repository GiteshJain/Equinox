#!/usr/bin/env python3
"""Every colour is a named one (to-do 225, spec docs/specs/2026-11-11-glass-look.md, step 1, check 3; final since step 6).

Counts the colour values typed in directly (hex #rgb, #rgba, #rrggbb, #rrggbbaa, and rgb()/rgba() with numbers) in the
planner's stylesheet, outside its :root blocks of named colours, and in the planner's code (app/planner/src, .ts and
.tsx, not the tests). The glass look's steps lowered the ceilings step by step; since step 6 (glass for everyone, 12 Nov)
the stylesheet has none outside its named colours, and the code only the globe's and the network map's (CODE_ALLOWED
below: canvas, WebGL and SVG attributes can't read a named colour). Fails when either count is over its ceiling, or when
a typed-in colour is anywhere else in the code.

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
CEILING_SHEET = 0     # 12 Nov, glass look step 6, final (step 5: 152, step 4: 170, Performance: 174, Routes: 227, step 2: 316, step 1: 350)
CEILING_CODE = 11     # 12 Nov, glass look step 6, final: the globe's and the network map's only (step 5: 47, step 4: 56, Performance: 65, Routes: 101, step 2: 104, step 1: 113)

# The only files of the planner's code that may type a colour in: the globe on Home (a canvas glow and a WebGL material)
# and the network map's (its load colours and two others, as SVG attributes).
CODE_ALLOWED = ("screens/home/heroScene.ts", "screens/home/map.ts")

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
    """(colours, files with any, files outside CODE_ALLOWED with any)."""
    n, files, stray = 0, 0, []
    for p in sorted(src.rglob("*.ts*")):
        if p.suffix not in (".ts", ".tsx") or ".test." in p.name:
            continue
        k = len(COLOUR.findall(p.read_text(encoding="utf-8")))
        if k:
            n += k
            files += 1
            rel = p.relative_to(src).as_posix()
            if rel not in CODE_ALLOWED:
                stray.append(f"{rel} ({k})")
    return n, files, stray


def selftest():
    css = ":root{--a:#fff;--b:rgba(1,2,3,.5)}\n@media (x){:root{--c:#000}}\n/* #abc */\n.x{color:#123456;background:url(\"data:image/svg+xml,%23fff\")}\n:root[data-look=\"glass\"]{--a:#000}\n.y{fill:rgb(1, 2, 3)}"
    assert sheet_count(css) == 2, sheet_count(css)
    assert len(COLOUR.findall("#eqhero #f-q #rev-expall #fade")) == 1   # #fade is hex; ids rarely are
    return True


def main():
    selftest()
    sheet = sheet_count(SHEET.read_text(encoding="utf-8"))
    code, files, stray = code_count(CODE)
    problems = []
    if sheet > CEILING_SHEET:
        problems.append(f"the stylesheet has {sheet} typed-in colours, over its ceiling of {CEILING_SHEET}: use a named colour")
    if code > CEILING_CODE:
        problems.append(f"the planner's code has {code} typed-in colours ({files} files), over its ceiling of {CEILING_CODE}: use a named colour")
    if stray:
        problems.append("typed-in colours outside the globe's and the network map's files: " + ", ".join(stray) + ": use a named colour")
    print(f"typed-in colours: stylesheet {sheet} (ceiling {CEILING_SHEET}), code {code} in {files} files (ceiling {CEILING_CODE})")
    if sheet < CEILING_SHEET or code < CEILING_CODE:
        print("  (under the ceiling: lower it to the new count in this pull request)")
    for p in problems:
        print("FAIL  " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
