#!/usr/bin/env -S uv run --quiet --with pillow python
"""Compose a fake game view from the packed sheets, to check that the assets
fit together the way the client will draw them. Writes
assets/sprites/mock_scene.png (2x authoring size on top, 1x game size below).

Usage: art/mock_scene.py
"""
import json, os, random, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from species_tints import SPECIES_TINTS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPR = os.path.join(ROOT, "assets", "sprites")
T = 64
W, H = 14, 9
random.seed(3)

man = json.load(open(os.path.join(SPR, "manifest.json")))
sheets = {k: Image.open(os.path.join(SPR, v["sheet"])).convert("RGBA") for k, v in man.items()}


def frame(asset, row, f=0):
    m = man[asset]; fw, fh = m["frame_px"]
    y = [r["name"] for r in m["rows"]].index(row)
    return sheets[asset].crop((f * fw, y * fh, (f + 1) * fw, (y + 1) * fh))


def tinted(im, hexc):
    """Godot `modulate`: per-channel multiply. The ore sprites are
    species-neutral, so this is the step that gives a deposit its identity -
    and doing it here is the point of the mock, because a sheet of untinted
    grey rock does not show what the client will draw."""
    c = [int(hexc[i:i + 2], 16) for i in (1, 3, 5)]
    out = Image.new("RGBA", im.size)
    p, o = im.load(), out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = p[x, y]
            o[x, y] = (r * c[0] // 255, g * c[1] // 255, b * c[2] // 255, a)
    return out


def blit(img, asset, row, tx, ty, f=0, tint=None):
    """Draw a sprite with its footprint's top-left tile at (tx, ty)."""
    ax, ay = man[asset]["anchor_px"]
    fr = frame(asset, row, f)
    if tint:
        fr = tinted(fr, tint)
    img.alpha_composite(fr, (tx * T - ax, ty * T - ay))


img = Image.new("RGBA", (W * T, H * T))
# ground
for y in range(H):
    for x in range(W):
        blit(img, "ground", f"v{random.randrange(4)}", x, y)
# two deposits, drawn the way the client will: a tile is "edge" if any
# 4-neighbour is outside the circle
# A deposit is a SPECIES INDEX plus a GRADE (C/B/A, the sim's own purity
# bands), not a named ore: the art is one
# neutral rock set and the index picks the tint. Three different species here
# so the sheet answers "can I tell these apart on a map" and not just "does
# the tile look nice".
deposits = [(0, 4, 4, 3, "A"), (1, 11, 5, 2, "B"), (4, 10, 1, 1, "C")]
for species, cx, cy, r, grade in deposits:
    inside = lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= r * r
    for y in range(H):
        for x in range(W):
            if not inside(x, y): continue
            edge = not all(inside(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            row = f"{grade}_edge" if edge else f"{grade}_full_v{random.randrange(2)}"
            blit(img, "ore", row, x, y, tint=SPECIES_TINTS[species])
blit(img, "ore", "depleted_full", 1, 7, tint=SPECIES_TINTS[2])
blit(img, "ore", "depleted_edge", 2, 7, tint=SPECIES_TINTS[2])
# entities, sorted by their bottom edge so nearer things draw on top
ents = [("spawn", "pad", 6, 1, 0), ("drill", "work", 3, 3, 2), ("drill", "idle", 10, 4, 0),
        ("player", "walk_SE", 8, 5, 3), ("player", "idle_S", 5, 7, 0)]
for asset, row, x, y, f in sorted(ents, key=lambda e: e[3] + man[e[0]]["tiles"][1]):
    blit(img, asset, row, x, y, f)

out = Image.new("RGBA", (W * T, H * T + H * T // 2 + 8), (30, 32, 30, 255))
out.alpha_composite(img, (0, 0))
out.alpha_composite(img.resize((W * T // 2, H * T // 2), Image.LANCZOS), (0, H * T + 8))
out.save(os.path.join(SPR, "mock_scene.png"))
print("wrote assets/sprites/mock_scene.png")
