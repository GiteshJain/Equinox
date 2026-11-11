#!/usr/bin/env python3
"""Text against the glass (to-do 225, decision 2; spec docs/specs/2026-11-11-glass-look.md, step 1, check 2).

For each period's picture (app/planner/src/ui/look/backdrop-<period>.jpg), scaled to cover the window as the page does
(1280 x 900 and 380 x 800), the brightest point behind the glass: for the blurred surfaces (cards and bars) the picture
blurred and saturated as the glass does it (blur 24 px, saturate 150%), for the panels (tables and charts, no blur) the
picture as it is. Over that point, each glass surface of that period from styles.css's :root[data-look="glass"] blocks,
and on it every text colour at 4.5:1 or more (the text, the lesser text, links, each status pill's text over its fill,
a field's text, the header's buttons, the page you're on) and every chart colour at 3:1 or more on the panel the charts
sit on (question 3's default). It names any pair that fails, with its ratio, picture and surface, and prints question
3's figures: the chart colours on the card glass by day, which the spec doesn't require.

Never darken a picture to make this pass: Day must look like day (Gitesh, 11 Nov).

Run from the repository root: python3 tests/glass_contrast_test.py   (needs Pillow and NumPy, installed with matplotlib)
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SHEET = ROOT / "app/planner/src/ui/styles.css"
LOOK = ROOT / "app/planner/src/ui/look"
PERIODS = ("day", "dusk", "night")
WINDOWS = ((1280, 900), (380, 800))
TEXT_MIN, MARK_MIN = 4.5, 3.0
CHARTS = ("--chart-1", "--chart-2", "--chart-5", "--chart-6", "--chart-ok", "--chart-warn", "--chart-bad", "--chart-mute", "--chart-ink")


def block(css, selector):
    i = css.find(selector + "{")
    if i < 0:
        raise SystemExit(f"FAIL  styles.css has no {selector} block")
    body = css[i + len(selector) + 1:css.index("}", i)]
    return dict((k, v.strip()) for k, v in re.findall(r"(--[a-z0-9-]+):\s*([^;]+);", body))


def rgba(v):
    v = v.strip()
    if v.startswith("#"):
        h = v[1:]
        if len(h) in (3, 4):
            h = "".join(c * 2 for c in h)
        a = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
        return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=float), a
    m = re.fullmatch(r"rgba?\(([^)]*)\)", v)
    if not m:
        raise ValueError(f"not a colour: {v}")
    n = [float(x) for x in re.split(r"[ ,/]+", m.group(1).strip()) if x]
    return np.array(n[:3]), (n[3] if len(n) == 4 else 1.0)


def over(colour, under):
    c, a = rgba(colour) if isinstance(colour, str) else colour
    return c * a + under * (1 - a)


def lum(rgb):
    c = np.asarray(rgb, dtype=float) / 255
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return float(0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2])


def ratio(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def saturate(img, s=1.5):
    """CSS saturate(), the Filter Effects matrix."""
    m = np.array([
        [0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s],
        [0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s],
        [0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s],
    ])
    return np.clip(img @ m.T, 0, 255)


def brightest(arr):
    lin = np.where(arr / 255 <= 0.04045, arr / 255 / 12.92, ((arr / 255 + 0.055) / 1.055) ** 2.4)
    y = lin @ np.array([0.2126, 0.7152, 0.0722])
    i = np.unravel_index(np.argmax(y), y.shape)
    return arr[i]


def behind(path, w, h):
    """The brightest point behind blurred glass and behind a panel, for the picture covering a w x h window."""
    im = Image.open(path).convert("RGB")
    s = max(w / im.width, h / im.height)
    im = im.resize((max(w, round(im.width * s)), max(h, round(im.height * s))), Image.LANCZOS)
    left, top = (im.width - w) // 2, (im.height - h) // 2
    im = im.crop((left, top, left + w, top + h))
    sharp = np.asarray(im, dtype=float)
    soft = saturate(np.asarray(im.filter(ImageFilter.GaussianBlur(24)), dtype=float))
    return brightest(soft), brightest(sharp)


def main():
    css = SHEET.read_text(encoding="utf-8")
    base = block(css, ':root[data-look="glass"]')
    day = {**base, **block(css, ':root[data-look="glass"][data-period="day"]')}
    problems, lines, q3 = [], [], []
    for period in PERIODS:
        t = day if period == "day" else base
        pic = LOOK / f"backdrop-{period}.jpg"
        if not pic.exists():
            problems.append(f"{period}: no picture {pic.relative_to(ROOT)}")
            continue
        for w, h in WINDOWS:
            soft, sharp = behind(pic, w, h)
            where = f"{period} at {w} px (brightest blurred {tuple(int(x) for x in soft)}, sharp {tuple(int(x) for x in sharp)})"
            surfaces = {
                "card": over(t["--card-bg"], soft),
                "bar": over(t["--bar-bg"], soft),
                "panel": over(t["--panel-bg"], sharp),
            }
            surfaces["header button"] = over(t["--sel-bg"], surfaces["bar"])
            surfaces["field on a card"] = over(t["--field-bg"], surfaces["card"])
            worst = {}
            for sname, s in surfaces.items():
                checks = [("text", t["--text"]), ("lesser text", t["--text-2"]), ("faintest text", t["--text-3"]), ("link", t["--link"])]
                for name, colour in checks:
                    r = ratio(over(colour, s), s)
                    worst[(sname, name)] = r
                    if r < TEXT_MIN:
                        problems.append(f"{where}: {name} on the {sname} {r:.2f}:1, under {TEXT_MIN}")
                if sname in ("card", "panel", "bar"):
                    for kind in ("ok", "warn", "bad", "mute"):
                        pill = over(t[f"--{kind}-fill"], s)
                        r = ratio(over(t[f"--{kind}-text"], pill), pill)
                        worst[(sname, f"{kind} pill")] = r
                        if r < TEXT_MIN:
                            problems.append(f"{where}: the {kind} pill's text on the {sname} {r:.2f}:1, under {TEXT_MIN}")
            r = ratio(rgba(t["--on-text"])[0], over(t["--on-bg"], surfaces["bar"]))
            if r < TEXT_MIN:
                problems.append(f"{where}: the page you're on {r:.2f}:1, under {TEXT_MIN}")
            for c in CHARTS:
                r = ratio(over(t[c], surfaces["panel"]), surfaces["panel"])
                worst[("panel", c)] = r
                if r < MARK_MIN:
                    problems.append(f"{where}: {c} on the panel {r:.2f}:1, under {MARK_MIN}")
                r = ratio(over(t[c], surfaces["card"]), surfaces["card"])
                worst[("card", c)] = r
                if period == "day":
                    q3.append((w, c, r))
            low = min(worst.items(), key=lambda kv: kv[1])
            lines.append(f"{where}: card text {worst[('card', 'text')]:.1f}, labels {worst[('card', 'lesser text')]:.1f}, "
                         f"pills {min(v for k, v in worst.items() if k[0] == 'card' and k[1].endswith('pill')):.1f}; "
                         f"panel charts {min(v for k, v in worst.items() if k[0] == 'panel' and k[1].startswith('--chart')):.1f}; "
                         f"lowest {low[0][1]} on the {low[0][0]} {low[1]:.2f}")
    for line in lines:
        print(line)
    if q3:
        print("question 3, the chart colours on the card glass by day (not required): " + "; ".join(
            f"{w} px " + ", ".join(f"{c[8:]} {r:.2f}" for ww, c, r in q3 if ww == w) for w in sorted({x[0] for x in q3})))
    for p in problems:
        print("FAIL  " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
