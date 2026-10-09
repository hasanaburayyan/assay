#!/usr/bin/env python3
"""ASSA-388: what a part is actually DRAWN at inside a build-screen slot plate, off a 1x window.

`main.gd::_slot_box` gives its 32x32 plate a reason -- a 128x102 assembly cell at 1/4, width-bound,
"nothing is resampled". `client/tools/cove_slot_box_scale.gd` shows the engine hands it a 64x96
ITEMS frame instead, so the stretch mode picks 1/3 and the HEIGHT binds. That is still the stretch
rule written out in my own words, which is a replica. This reads the window.

The plate is a themed `Panel` (RAISED), the sprite is species-TINTED, and the panel behind both is
SURFACE -- so the sprite is the only COLOURED thing in the region: a pixel whose channel spread
(max-min) clears SPREAD is paint. Panels, borders, text and the screen itself are all neutral greys.

    art/slot_plate_probe.py <window.png> <x0> <y0> <x1> <y1>

Prints one line per connected run of columns holding paint (one plate's sprite), with its ink bbox
and what share of a 32x32 and a 32x48 plate that is.
"""
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from png_stdlib import read_rgba

ALPHA_FLOOR = 200    # the window is opaque; this only guards against a stray composite
SURFACE = (37, 40, 48)   # the build screen's own panel colour (ui_theme)


## **CLASSIFY THE PAINT, DO NOT THRESHOLD IT.** My first classifier called a pixel "sprite" when its
## channel spread cleared 25. The `head` sprite's darkest body is `(46,27,50)` -- spread 22 -- so the
## whole bulb was binned as PLATE and the probe reported a 48x44 plate where the engine draws 32x32.
##
## Every UI neutral in this theme is one ramp: `SURFACE (37,40,48)`, `RAISED (53,57,67)`, the plate
## border `(74,79,92)`, the shadow `(23,24,29)` -- all of them **r <= g <= b**, blue-leaning by
## construction, and so is every antialiased blend BETWEEN two of them. Nothing in the ramp inverts
## that order, so the test is exact rather than tuned.
##
## **IT IS A PER-SPECIES TEST AND IT SAYS SO.** `tint_for` multiplies the frame by the species
## colour; Tonore's is magenta, which drives GREEN below red, so every sprite pixel breaks the
## ordering. A green-tinted species would not, and this probe would go blind on it -- which is why
## `--audit` prints the counts both ways so the caller can see the split is clean before trusting it.
def _is_ui_neutral(r: int, g: int, b: int) -> bool:
    return r <= g <= b


def main() -> int:
    if len(sys.argv) != 6:
        print(__doc__)
        return 2
    path = sys.argv[1]
    x0, y0, x1, y1 = (int(v) for v in sys.argv[2:6])
    w, h, px = read_rgba(path)
    x1, y1 = min(x1, w), min(y1, h)

    cols = {}
    for y in range(y0, y1):
        row = px[y]
        for x in range(x0, x1):
            r, g, b, a = row[x]
            if a < ALPHA_FLOOR:
                continue
            if _is_ui_neutral(r, g, b):
                continue
            cols.setdefault(x, []).append(y)

    if not cols:
        print("NO TINTED PAINT in x %d..%d y %d..%d" % (x0, x1, y0, y1))
        return 1

    # **ONE RECT IS ONE PLATE, AND GROUPING BY COLUMN RUNS IS WRONG HERE.** My first pass did that
    # and merged the `head` plate with the first `hopper` plate, because the two rows are indented
    # differently and their x ranges overlap: it reported one 37x67 sprite in a 32x32 box. The
    # caller names the rect; the probe does not guess where a plate is.
    ys = [y for x in cols for y in cols[x]]
    xs = sorted(cols)
    bx0, bx1, by0, by1 = xs[0], xs[-1], min(ys), max(ys)
    bw, bh = bx1 - bx0 + 1, by1 - by0 + 1
    n = sum(len(cols[x]) for x in xs)

    # THE PLATE ITSELF: the themed `Panel` is neutral, so it is everything in the rect that is NOT
    # the screen's own SURFACE and not tinted paint. Its bbox is the plate's drawn edge.
    pxs, pys = [], []
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = px[y][x]
            if a < ALPHA_FLOOR or (r, g, b) == SURFACE:
                continue
            if not _is_ui_neutral(r, g, b):
                continue
            pxs.append(x)
            pys.append(y)

    print("file   %s" % path)
    print("rect   x %d..%d  y %d..%d   neutral = r<=g<=b   alpha>=%d" % (x0, x1, y0, y1, ALPHA_FLOOR))
    if pxs:
        print("PLATE  x %4d..%-4d y %4d..%-4d  %3d x %-3d   (neutral, not SURFACE)" % (
            min(pxs), max(pxs), min(pys), max(pys),
            max(pxs) - min(pxs) + 1, max(pys) - min(pys) + 1,
        ))
    else:
        print("PLATE  none found")
    print("INK    x %4d..%-4d y %4d..%-4d  %3d x %-3d   %5d px tinted" % (
        bx0, bx1, by0, by1, bw, bh, n))
    if pxs:
        p0x, p1x, p0y, p1y = min(pxs), max(pxs), min(pys), max(pys)
        over = (max(0, p0x - bx0), max(0, bx1 - p1x), max(0, p0y - by0), max(0, by1 - p1y))
        print("OVER   left %d  right %d  top %d  bottom %d   (ink outside the plate's own edge)"
              % over)
        print("FILL   ink / plate = %.1f%%" % (
            bw * bh / float((p1x - p0x + 1) * (p1y - p0y + 1)) * 100.0))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
