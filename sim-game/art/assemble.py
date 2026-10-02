#!/usr/bin/env -S uv run --quiet --with pillow python
"""Assemble the demo's machines out of part sprites and judge them at 1x.

    art/assemble.py

Writes assets/sprites/assembled.png: every machine the minimal demo defines,
built the way the client must build it, at the size the player sees.

WHY THIS EXISTS
  rig.py rule 2 says a machine is drawn by stacking whole part sprites at the
  same frame position, never by rendering a per-machine sprite. Every other
  decision in the part set follows from it - one frame size, one join height,
  one anchor, parts meeting at the origin. It was a COMMENT. A comment is not
  a check: twice this week I have written down what a thing does and then
  cited my own sentence as evidence that it did it. So this composites the
  real packed sheets and reports numbers.

WHAT IT CHECKS
  1. A pick (head + handle) and a drill (head + planted frame) both assemble
     from one path, differing only by which frame part goes in. Demo point 6.
  2. Hoppers are COUNTABLE. The demo says a second hopper raises capacity
     with no new recipe (point 5) and that hoppers raise the drill's buffer
     (point 9), so a player has to be able to see that a drill has two. Two
     sprites stacked at one position would make hopper #2 invisible, and no
     amount of sim correctness fixes a machine you cannot read.
  3. The grade ladder survives assembly: a C machine and an A machine still
     differ once the parts are overlaid and shrunk to 1x.
  Each is printed as a measurement, and the sheet is there to look at.

The draw order is frame, then hopper(s), then head: the frame is the body and
the thing behind, the head is the working end and must never be occluded, and
hoppers ride on the frame between the two.

STATUS: THIS EXITS NONZERO TODAY, ON PURPOSE. Check 2 fails - a second hopper
is invisible - and that is an open design question for the Director and the
Lead, not a bug in a sprite I should quietly paint around. CI never runs the
art scripts (they need Blender and Pillow), so a red check here breaks no
build; it is the honest record of a known hole, and it goes green by itself
the day repeated parts are given a position rule. Checks 1 and 3 pass.
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPR = os.path.join(ROOT, "assets", "sprites")
TILE = 64                       # authoring size; the game shows 32 at 1x
GAME = 32

man = json.load(open(os.path.join(SPR, "manifest.json")))
sheets = {}


def frame_of(asset, row, f=0):
    """One frame of a packed sheet, by row NAME - never by index. A row order
    is a packing detail; a name is a promise."""
    if asset not in sheets:
        sheets[asset] = Image.open(os.path.join(SPR, man[asset]["sheet"])).convert("RGBA")
    m = man[asset]
    fw, fh = m["frame_px"]
    names = [r["name"] for r in m["rows"]]
    if row not in names:
        raise SystemExit("%s has no row %r (has %s)" % (asset, row, names))
    y = names.index(row)
    return sheets[asset].crop((f * fw, y * fh, (f + 1) * fw, (y + 1) * fh))


def assemble(parts, grade):
    """Stack whole part frames at one position. This is rule 2, executed.

    Every part must agree on frame size and anchor or the stack is meaningless,
    so that is asserted here rather than assumed: it is the invariant the whole
    part set is built on and the cheapest possible place to catch it breaking.
    """
    sizes = {tuple(man[p]["frame_px"]) for p in parts}
    anchors = {tuple(man[p]["anchor_px"]) for p in parts}
    if len(sizes) != 1 or len(anchors) != 1:
        raise SystemExit(
            "parts %s do not share one frame rectangle (sizes %s, anchors %s) -\n"
            "    they cannot be overlaid, which breaks rig.py rule 2."
            % (list(parts), sizes, anchors))
    w, h = sizes.pop()
    out = Image.new("RGBA", (w, h))
    for p in parts:
        out.alpha_composite(frame_of(p, grade))
    return out


def at_1x(img):
    """The game draws a 2x1-tile part at 32px per tile. Judge there."""
    k = GAME / float(TILE)
    return img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)


def differs(a, b):
    """Opaque-pixel difference between two 1x renders: how many pixels changed
    and by how much at the worst. 'They look different' is not a measurement."""
    pa, pb = a.convert("RGBA").load(), b.convert("RGBA").load()
    n, worst = 0, 0
    for y in range(a.height):
        for x in range(a.width):
            ca, cb = pa[x, y], pb[x, y]
            d = max(abs(ca[i] - cb[i]) for i in range(4))
            if d > 8:
                n += 1
                worst = max(worst, d)
    return n, worst


def footprint(img):
    """Count of solid pixels. Stacking a sprite on itself cannot grow this, so
    it is the measure that cannot be fooled by alpha."""
    px = img.convert("RGBA").load()
    return sum(1 for y in range(img.height) for x in range(img.width)
               if px[x, y][3] > 128)


# The machines the minimal demo defines (2026-10-01-minimal-demo-loop.md).
# A pick is a head on a HANDLE, which is the held frame; a drill is a head on
# a planted FRAME with optional hoppers. One assembly path, different parts.
MACHINES = [
    ("pick",          ("handle", "head")),
    ("drill",         ("frame", "head")),
    ("drill+hopper",  ("frame", "hopper", "head")),
    ("drill+2hopper", ("frame", "hopper", "hopper", "head")),
]


def main():
    shots = []
    for name, parts in MACHINES:
        for g in ("C", "A"):
            shots.append((("%s %s" % (name, g)), assemble(parts, g)))

    ok = True

    # 1. CAN YOU COUNT THE HOPPERS?
    #
    # The naive test - "do any pixels differ between one hopper and two" -
    # passes, and it is worthless. I ran it and it reported 486 differing
    # pixels with a worst channel of 254, which sounds decisive. Compositing a
    # sprite ONTO ITSELF cannot add anything to the picture; what it does is
    # push the part-transparent pixels of an antialiased edge and an outline
    # further toward opaque. So the number was real, the pixels did change, and
    # the answer to the question I actually had was still no. My own pixel
    # scripts lie to me in exactly this way, so this measures two things that
    # cannot be fooled:
    #   - the SOLID FOOTPRINT, which stacking a sprite on itself cannot grow;
    #   - adding the second hopper against the CONTROL of adding the first.
    # If the first hopper changes the machine a lot and the second changes it
    # by an edge-alpha rounding error, the machine is not countable.
    zero = at_1x(assemble(("frame", "head"), "A"))
    one = at_1x(assemble(("frame", "hopper", "head"), "A"))
    two = at_1x(assemble(("frame", "hopper", "hopper", "head"), "A"))
    f0, f1, f2 = footprint(zero), footprint(one), footprint(two)
    g1, g2 = f1 - f0, f2 - f1
    d01, _ = differs(zero, one)
    d12, _ = differs(one, two)
    print("hopper count at 1x: footprint %d -> %d -> %d px for 0 -> 1 -> 2 hoppers" % (f0, f1, f2))
    print("                    new shape: +%d px for the 1st hopper, +%d px for the 2nd (%.0f%%)"
          % (g1, g2, 100.0 * g2 / g1 if g1 else 0))
    print("                    pixels touched: %d for the 1st, %d for the 2nd" % (d01, d12))
    # The verdict is FOOTPRINT GROWTH, not pixels touched. Pixels touched says
    # 486 for the second hopper, which looks like a lot until you notice a
    # sprite composited onto itself touches every antialiased pixel it owns.
    if g2 < g1 * 0.25:
        ok = False
        print("  FAIL: THE SECOND HOPPER IS INVISIBLE. The first hopper adds %d px\n"
              "  of new shape; the second adds %d. That is edge alpha hardening,\n"
              "  not a part. The demo says a second hopper raises the buffer with\n"
              "  no new recipe (point 5) and that hoppers raise the cap (point 9),\n"
              "  so a player has to be able to SEE two. Stacking identical frames\n"
              "  at one position cannot express a COUNT. This wants a design\n"
              "  answer - offset each repeated part along the frame, or cap the\n"
              "  visible hoppers and put the number in UI - not a sprite tweak."
              % (g1, g2))

    # 2. Does the grade ladder survive assembly?
    for name, parts in MACHINES:
        n, worst = differs(at_1x(assemble(parts, "C")), at_1x(assemble(parts, "A")))
        print("grade C vs A on %-14s %4d px differ (worst channel %d)" % (name + ":", n, worst))
        if n == 0:
            ok = False
            print("  FAIL: %s renders identically at C and A." % name)

    # the sheet: 2x authoring on top so you can see what it is made of, and the
    # true 1x row below, which is the verdict.
    pad = 6
    cw = max(im.width for _, im in shots)
    ch = max(im.height for _, im in shots)
    sheet = Image.new("RGBA", (pad + len(shots) * (cw + pad), ch + pad * 3 + round(ch * GAME / TILE)),
                      (30, 32, 30, 255))
    for i, (_, im) in enumerate(shots):
        sheet.alpha_composite(im, (pad + i * (cw + pad), pad))
        small = at_1x(im)
        sheet.alpha_composite(small, (pad + i * (cw + pad), ch + pad * 2))
    sheet.save(os.path.join(SPR, "assembled.png"))
    print("wrote assets/sprites/assembled.png  (%d machines, top row authoring size, bottom row true 1x)"
          % len(shots))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
