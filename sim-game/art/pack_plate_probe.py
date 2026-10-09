#!/usr/bin/env python3
"""ASSA-376: where a pack-row icon's art sits inside its 32x48 plate, off a 1x window.

The fit (`rig.Asset(fill="top")` + `build.py::fit_to_frame`) crops each items frame to its paint and
scales that into the 64x96 box with the TOP edge at y=0 and the slack at the BOTTOM. On a pack row
the frame is drawn into a 32x48 plate at an exact 1/2, so the promise is checkable in the window:
**after the fit a row's art must start at the plate's own top edge.**

**THE CLASSIFIER IS THE PLATE'S OWN COLOUR, NOT A THRESHOLD AND NOT THE UI RAMP.** `pack_icon_plate()`
is the ground sheet's median -- an olive, which breaks the `r <= g <= b` ordering the build screen's
neutrals obey, so the slot-plate probe's test is the wrong one here. The painter writes ONE exact
colour for the plate, so the plate is its modal colour and the art is everything else. Exact match,
with an explicit tolerance for the rounded corners' antialiasing, and the tolerance is printed so a
reader can see the verdict does not depend on it.

    art/pack_plate_probe.py <window.png> <x0> <y0> <x1> <y1> [tolerance]

Prints the plate colour it found, the art's bbox inside the rect, and the GAP on each side.
"""
import sys
import collections

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from png_stdlib import read_rgba


def main() -> int:
    if len(sys.argv) not in (6, 7):
        print(__doc__)
        return 2
    path = sys.argv[1]
    x0, y0, x1, y1 = (int(v) for v in sys.argv[2:6])
    tol = int(sys.argv[6]) if len(sys.argv) == 7 else 8
    w, h, px = read_rgba(path)
    x1, y1 = min(x1, w), min(y1, h)

    counts = collections.Counter()
    for y in range(y0, y1):
        for x in range(x0, x1):
            counts[px[y][x][:3]] += 1
    plate, n_plate = counts.most_common(1)[0]

    xs, ys = [], []
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[y][x][:3]
            if abs(r - plate[0]) <= tol and abs(g - plate[1]) <= tol and abs(b - plate[2]) <= tol:
                continue
            xs.append(x)
            ys.append(y)

    print("file   %s" % path)
    print("rect   x %d..%d  y %d..%d  (%d x %d)   tolerance %d" % (
        x0, x1 - 1, y0, y1 - 1, x1 - x0, y1 - y0, tol))
    print("plate  %s, %d of %d px in the rect" % (str(plate), n_plate, (x1 - x0) * (y1 - y0)))
    if not xs:
        print("ART    none: every pixel in the rect is the plate")
        return 1
    ax0, ax1, ay0, ay1 = min(xs), max(xs), min(ys), max(ys)
    print("ART    x %d..%d  y %d..%d   %d x %d   %d px" % (
        ax0, ax1, ay0, ay1, ax1 - ax0 + 1, ay1 - ay0 + 1, len(xs)))
    print("GAP    top %d   bottom %d   left %d   right %d" % (
        ay0 - y0, (y1 - 1) - ay1, ax0 - x0, (x1 - 1) - ax1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
