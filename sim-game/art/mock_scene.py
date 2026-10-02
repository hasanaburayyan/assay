#!/usr/bin/env -S uv run --quiet --with pillow python
"""Compose a fake game view from the packed sheets, to check that the assets
fit together the way the client will draw them. Writes
assets/sprites/mock_scene.png (2x authoring size on top, 1x game size below).

Usage: art/mock_scene.py

THE MACHINES IN THIS SCENE ARE ASSEMBLED FROM PARTS, and that is the one thing
about this file worth reading. It used to drop in `drill.py`'s sprite: a single
2x2 drawing of a whole drill, rendered in the first batch of assets, before
parts existed. Nothing in the game can be that any more. A planted machine in
sim is an `Assembly { frame, mounted }` -- the player chooses the parts -- and
rig.py rule 2 says a machine is DRAWN by overlaying whole part sprites at one
frame position. A picture of the game containing a machine the game cannot
build is worse than no picture, because this is the artefact people look at
when they ask what Assay looks like.

So the three machines here are `frame + head` (no hopper), `frame + hopper +
head`, and `frame + 2 hoppers + head`, at grades C, B and A, by the same rule
`art/assemble.py` checks. Two things fall out of that which a contact sheet of
single parts cannot show, and both are the point of this file:
  - GRADE READS ACROSS A SCENE. Dulled, as drawn, and blown out to neutral at
    A, on three machines at once, on real ground, beside tinted deposits.
  - THE GRADE-A MACHINE LOSES ITS HOPPERS. The chassis blows out to the same
    VALUE as the steel hopper bodies, so the A drill is one pale mass where
    the C and B ones have two parts. That is ASSA-28, and it is much more
    obvious here than on the assembly sheet.

`drill.py` is deliberately NOT drawn here any more. It is still rendered and
still measured by loudness.py; whether it is retired, or kept as the look of
some future fixed machine, is the Director's call and not this file's.
"""
import json, os, random, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from species_tints import SPECIES_TINTS
from part_layout import PART_REPEAT_OFFSET

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


def assemble(parts, grade):
    """rig.py rule 2 and rule 5, executed: whole part frames stacked at one
    position, with the nth repeat of a kind stepped by n * PART_REPEAT_OFFSET.

    The same operation `art/assemble.py` checks, deliberately written out again
    rather than imported: that file is a CHECK and imports Blender-free module
    `part_layout` for the offset, but it also owns red levers that rewrite the
    offset from the environment. A scene drawn through a check's red lever
    would be a scene that quietly lies when someone runs the lever.

    `parts` is in `Assembly::parts()` order -- frame first, then mounted.
    """
    sizes = {tuple(man[p]["frame_px"]) for p in parts}
    if len(sizes) != 1:
        raise SystemExit("parts %s do not share one frame rectangle %s; rule 2"
                         " cannot overlay them." % (list(parts), sizes))
    w, h = sizes.pop()
    out = Image.new("RGBA", (w, h))
    seen = {}
    for p in parts:
        n = seen.get(p, 0)
        seen[p] = n + 1
        src = frame(p, grade)
        if n == 0:
            out.alpha_composite(src)
            continue
        dx, dy = PART_REPEAT_OFFSET[0] * n, PART_REPEAT_OFFSET[1] * n
        layer = Image.new("RGBA", (w, h))
        layer.alpha_composite(src)
        out.alpha_composite(layer.transform((w, h), Image.AFFINE,
                                            (1, 0, -dx, 0, 1, -dy)))
    return out


def blit_machine(img, parts, grade, tx, ty):
    """A planted machine, anchored like any other sprite.

    FOOTPRINT, HONESTLY: `sim/src/building.rs` gives `BuildingKind::Machine`
    a footprint of (1, 1) -- "so a drill sits on the deposit tile it works" --
    while the part frame is 2 tiles wide. The sprite therefore OVERHANGS its
    occupied tile, the way a tall sprite overhangs in any tile game, and the
    anchor is what reconciles them. That is drawn here rather than hidden
    because it is a real question for whoever builds the renderer: an
    overhanging machine can cover the deposit tile next door, and nothing has
    ruled on whether that is acceptable. See ASSA-30.
    """
    ax, ay = man[parts[0]]["anchor_px"]
    img.alpha_composite(assemble(parts, grade), (tx * T - ax, ty * T - ay))


img = Image.new("RGBA", (W * T, H * T))
# ground
for y in range(H):
    for x in range(W):
        blit(img, "ground", f"v{random.randrange(4)}", x, y)
# Deposits, drawn the way the client will: EVERY TILE INSIDE `contains()` IS
# THE SAME TILE. There is no border variant - the sim's `amount` is one number
# for the whole patch, so a sparser rim would be a visible mark for a
# difference that does not exist (Maren, ASSA-20). The hard edge is the point:
# it is exactly where mining and placing stop working. Variation comes from
# v0/v1, which move rocks without claiming anything about quantity.
#
# A deposit is a SPECIES INDEX plus a GRADE (C/B/A, the sim's own purity
# bands), not a named ore: the art is one neutral rock set and the index picks
# the tint. Three different species here so the sheet answers "can I tell
# these apart on a map" and not just "does the tile look nice".
deposits = [(0, 4, 4, 3, "A"), (1, 11, 5, 2, "B"), (4, 10, 1, 1, "C")]
for species, cx, cy, r, grade in deposits:
    inside = lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= r * r
    for y in range(H):
        for x in range(W):
            if not inside(x, y): continue
            row = f"{grade}_full_v{random.randrange(2)}"
            blit(img, "ore", row, x, y, tint=SPECIES_TINTS[species])
blit(img, "ore", "depleted_full", 1, 7, tint=SPECIES_TINTS[2])
# PLANTED MACHINES, assembled from parts. Three different builds at three
# different grades on purpose: the question this scene answers is not "does a
# drill look nice", it is "can I tell a player's machines apart, and tell how
# good they are, at the size the game draws them".
machines = [(("frame", "hopper", "head"), "B", 3, 3),
            (("frame", "hopper", "hopper", "head"), "A", 10, 4),
            (("frame", "head"), "C", 11, 6)]
for parts, grade, x, y in sorted(machines, key=lambda m: m[3]):
    blit_machine(img, parts, grade, x, y)
# the rest, sorted by their bottom edge so nearer things draw on top
ents = [("spawn", "pad", 6, 1, 0),
        ("player", "walk_SE", 8, 5, 3), ("player", "idle_S", 5, 7, 0)]
for asset, row, x, y, f in sorted(ents, key=lambda e: e[3] + man[e[0]]["tiles"][1]):
    blit(img, asset, row, x, y, f)

out = Image.new("RGBA", (W * T, H * T + H * T // 2 + 8), (30, 32, 30, 255))
out.alpha_composite(img, (0, 0))
out.alpha_composite(img.resize((W * T // 2, H * T // 2), Image.LANCZOS), (0, H * T + 8))
out.save(os.path.join(SPR, "mock_scene.png"))
print("wrote assets/sprites/mock_scene.png")
