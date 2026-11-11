#!/usr/bin/env python3
"""Draws the planner's three glass-look backdrops (to-do 225, spec docs/specs/2026-11-11-glass-look.md, step 1).

Day, Dusk and Night skies, drawn from nothing but gradients, soft cloud and stars, in the planner's own colours (night
#0A1230, violet #4B3BA8, rose #E86A92, amber #F6B44B) and in the drawn style of the mock-up "Planner glass look".
No photographs, no downloaded images. The same files every run (fixed seeds), so a redraw only changes what the code
changes. Day must look like day: never darken it to make the contrast check pass (Gitesh, 11 Nov).

Run from the repository root:  python3 scripts/look/draw_backdrops.py
Writes app/planner/src/ui/look/backdrop-{day,dusk,night}.jpg (1920 x 1200, JPEG) and prints each file's size.
Needs Pillow and NumPy (both installed with matplotlib, which the checks already pin).
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

W, H = 1920, 1200
OUT = Path(__file__).resolve().parents[2] / "app/planner/src/ui/look"
QUALITY = 78


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)


def vertical(stops):
    """A sky from top (0) to bottom (1): stops is [(position, colour), ...]."""
    y = np.linspace(0, 1, H)
    out = np.zeros((H, 3))
    pos = [p for p, _ in stops]
    cols = [hexrgb(c) for _, c in stops]
    for k in range(3):
        out[:, k] = np.interp(y, pos, [c[k] for c in cols])
    return np.repeat(out[:, None, :], W, axis=1)


def glow(img, cx, cy, rx, ry, colour, strength):
    """A soft round light (the sun's glow, a lit patch of sky)."""
    yy, xx = np.mgrid[0:H, 0:W]
    d = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2
    a = strength * np.exp(-d)
    return img * (1 - a[..., None]) + hexrgb(colour) * a[..., None]


def clouds(seed, count, band, size, colour, opacity, blur):
    """Soft cloud: many overlapping ellipses in a band of the sky, blurred into banks. Returns (colour layer, alpha)."""
    rng = np.random.default_rng(seed)
    mask = Image.new("L", (W, H), 0)
    from PIL import ImageDraw
    d = ImageDraw.Draw(mask)
    for _ in range(count):
        cx = rng.uniform(-0.1, 1.1) * W
        cy = rng.uniform(*band) * H
        rx = rng.uniform(0.5, 1.0) * size
        ry = rx * rng.uniform(0.25, 0.45)
        shade = int(rng.uniform(120, 255))
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=shade)
    mask = mask.filter(ImageFilter.GaussianBlur(blur))
    a = np.asarray(mask, dtype=np.float64) / 255 * opacity
    return hexrgb(colour), a


def lay(img, layer):
    colour, a = layer
    return img * (1 - a[..., None]) + colour * a[..., None]


def stars(img, seed, count):
    rng = np.random.default_rng(seed)
    out = img.copy()
    for _ in range(count):
        x, y = int(rng.uniform(0, W)), int(rng.uniform(0, H * 0.75))
        b = rng.uniform(0.25, 0.9) * (1 - y / (H * 0.9))
        r = 1 if rng.random() < 0.85 else 2
        out[max(0, y - r + 1):y + r, max(0, x - r + 1):x + r] = out[max(0, y - r + 1):y + r, max(0, x - r + 1):x + r] * (1 - b) + 255 * b
    return out


def grain(img, seed, amount=1.6):
    """A touch of grain, so the gradients don't band on a good screen."""
    rng = np.random.default_rng(seed)
    return img + rng.normal(0, amount, img.shape)


def save(img, name):
    path = OUT / f"backdrop-{name}.jpg"
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").save(path, "JPEG", quality=QUALITY, optimize=True, progressive=True)
    return path


def day():
    img = vertical([(0, "#2F6FC4"), (0.45, "#6FA6E3"), (0.8, "#B9D6F2"), (1, "#E4EEF8")])
    img = glow(img, W * 0.78, H * 0.12, W * 0.35, H * 0.35, "#FFF6E0", 0.35)
    img = lay(img, clouds(11, 60, (0.55, 0.95), 260, "#FFFFFF", 0.85, 38))
    img = lay(img, clouds(12, 18, (0.15, 0.4), 200, "#F4F8FD", 0.45, 46))
    return grain(img, 1)


def dusk():
    img = vertical([(0, "#0A1230"), (0.3, "#2A2470"), (0.55, "#4B3BA8"), (0.75, "#E86A92"), (0.92, "#F6B44B"), (1, "#F9C978")])
    img = glow(img, W * 0.3, H * 0.95, W * 0.4, H * 0.22, "#FFD08A", 0.55)
    img = lay(img, clouds(21, 40, (0.6, 0.85), 280, "#7A3E8C", 0.55, 34))
    img = stars(img, 22, 60)
    return grain(img, 2)


def night():
    img = vertical([(0, "#050A1E"), (0.6, "#0E1640"), (1, "#1B2559")])
    img = glow(img, W * 0.7, H * 0.85, W * 0.5, H * 0.3, "#4B3BA8", 0.35)
    img = lay(img, clouds(31, 30, (0.7, 0.95), 300, "#1F2A66", 0.5, 40))
    img = stars(img, 32, 420)
    return grain(img, 3)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name, draw in (("day", day), ("dusk", dusk), ("night", night)):
        p = save(draw(), name)
        print(f"{p.relative_to(OUT.parents[4])}: {p.stat().st_size:,} bytes")
