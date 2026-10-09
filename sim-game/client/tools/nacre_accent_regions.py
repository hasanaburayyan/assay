#!/usr/bin/env python3
"""HOW MANY SEPARATE ACCENT REGIONS A FRAME SHOWS, AND WHERE EACH ONE IS (ASSA-335).

Maren's ruling 1: *"ACCENT marks the one act a screen is for, ONE REGION PER SCREEN."* That is a
claim about contiguous shapes in a picture, so it cannot be checked by reading a theme file or by
counting accent PIXELS -- 1781 px in one button and 1781 px spread over three controls are the same
total and a different screen. This counts the shapes.

Usage:
    nacre_accent_regions.py FRAME.png [FRAME.png ...]
    nacre_accent_regions.py --control DIR        # DIR holds ASSA-315's published before-frames

**THE REPORTED NUMBER IS ACCENT OUTSIDE THE PRIMARY'S BOX, NOT A COMPONENT COUNT, AND ITS OWN
CONTROL IS WHY.** The first version of this script counted 4-connected components and compared them
to ASSA-315's published *"unfocused 1781 px, ONE region ... focused +526 px, a SECOND"*. It refused:
it read **5** regions on the unfocused frame and **11** on the focused one. Neither reading was
wrong. A `StyleBoxFlat` ring has `RADIUS 4` rounded corners, so the host box's outline is four
1-px-wide arcs that never touch -- two 230x1 runs and two 1x20 runs -- and `Play solo`'s own label
punches accent-coloured holes inside letters that are components of their own. **ASSA-315's "one
region" was a pixel total plus a human looking at a shape, and a strict component count is a
different question.** Tuning the tolerance until 11 became 2 would have been fitting the instrument
to the answer.

So the question is asked the way the ruling means it: **is there accent anywhere on this screen
other than the one act it is for?** That is insensitive to corner radii and glyph holes, and it is
the thing a player sees.

`--control` reproduces ASSA-315's spatial claim on their own two frames or exits 2, NO VERDICT:
nothing outside the primary when unfocused, and when focused an outside mass whose bounding box is
exactly their published `x417..656 y408..437`. An instrument that cannot find what somebody measured
by hand is not measuring -- and this one is about to claim a region DISAPPEARED, the direction where
a too-strict colour match flatters me by finding nothing anywhere.

**4-CONNECTIVITY AND NO MINIMUM REGION SIZE** for the component list, which is kept as diagnostics
so the shape of the outside mass is visible rather than just its total. A size floor would be a
tolerance to tune; the control above is what holds the tolerance honest instead.

ACCENT is `Color(0.50, 0.90, 0.55)` in `build_theme.gd` -> (128, 229, 140). The tolerance is for
PNG rounding, not for finding near-greens: a glyph fringe over the accent fill is a different
colour and belongs to neither region.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from nacre_door_contrast import read_png  # noqa: E402  (same directory, same PNG reader)

ACCENT = (128, 229, 140)
TOL = 6

# ASSA-315's published spatial claim, which is what this reproduces: nothing accent outside the
# primary when the host box is unfocused, and a 240x30 outline at exactly this box when it is.
CONTROL_RING_BOX = (417, 656, 408, 437)
CONTROL_RING_MIN_PX = 400


def accent_mask(path, colour=ACCENT, tol=TOL):
    """Every pixel within `tol` of `colour`, as a set of (x, y)."""
    width, height, channels, rows = read_png(path)
    hit = set()
    for y in range(height):
        row = rows[y]
        for x in range(width):
            base = x * channels
            if (abs(row[base] - colour[0]) <= tol
                    and abs(row[base + 1] - colour[1]) <= tol
                    and abs(row[base + 2] - colour[2]) <= tol):
                hit.add((x, y))
    return hit, width, height


def regions(hit):
    """Contiguous 4-connected regions, largest first: (px, x0, x1, y0, y1)."""
    seen = set()
    out = []
    for start in hit:
        if start in seen:
            continue
        # Iterative, because a 1781 px region would recurse 1781 deep.
        stack = [start]
        seen.add(start)
        cells = []
        while stack:
            x, y = stack.pop()
            cells.append((x, y))
            for step in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nxt = (x + step[0], y + step[1])
                if nxt in hit and nxt not in seen:
                    seen.add(nxt)
                    stack.append(nxt)
        xs = [c[0] for c in cells]
        ys = [c[1] for c in cells]
        out.append((len(cells), min(xs), max(xs), min(ys), max(ys)))
    out.sort(reverse=True)
    return out


def describe(path):
    """Report the primary's mass, then everything accent that is NOT in it."""
    hit, width, height = accent_mask(path)
    found = regions(hit)
    if not found:
        print("%s  %dx%d  NO accent pixels at all" % (Path(path).name, width, height))
        return None
    # The primary is the largest mass; its bbox is the one place accent is earned on this screen.
    biggest = found[0]
    px, bx0, bx1, by0, by1 = biggest
    inside = [r for r in found if r[1] >= bx0 and r[2] <= bx1 and r[3] >= by0 and r[4] <= by1]
    outside = [r for r in found if r not in inside]
    out_px = sum(r[0] for r in outside)
    print("%s  %dx%d  %d accent px total" % (Path(path).name, width, height, len(hit)))
    print("    primary  %6d px  x%d..%d y%d..%d  (%dx%d)  in %d piece(s) incl. glyph holes"
          % (px, bx0, bx1, by0, by1, bx1 - bx0 + 1, by1 - by0 + 1, len(inside)))
    if not outside:
        print("    OUTSIDE IT:  0 px -- the accent is spent in one place")
        return {"outside_px": 0, "outside_box": None, "pieces": 0}
    ox0 = min(r[1] for r in outside)
    ox1 = max(r[2] for r in outside)
    oy0 = min(r[3] for r in outside)
    oy1 = max(r[4] for r in outside)
    print("    OUTSIDE IT:  %6d px  x%d..%d y%d..%d  (%dx%d)  in %d piece(s)"
          % (out_px, ox0, ox1, oy0, oy1, ox1 - ox0 + 1, oy1 - oy0 + 1, len(outside)))
    for r in outside:
        print("        %6d px  x%d..%d y%d..%d  (%dx%d)"
              % (r[0], r[1], r[2], r[3], r[4], r[2] - r[1] + 1, r[4] - r[3] + 1))
    return {"outside_px": out_px, "outside_box": (ox0, ox1, oy0, oy1), "pieces": len(outside)}


def control(folder):
    """Reproduce ASSA-315's spatial claim on their own frames, or refuse to be used."""
    bad = []
    unfocused = describe(str(Path(folder) / "01-unfocused.png"))
    focused = describe(str(Path(folder) / "02-focused.png"))
    if unfocused is None or focused is None:
        print("\nNO VERDICT -- ASSA-315's frames are not in %s" % folder)
        return 2
    if unfocused["outside_px"] != 0:
        bad.append("01-unfocused: %d accent px outside the primary; ASSA-315 found the accent in "
                   "ONE place when nothing is focused" % unfocused["outside_px"])
    if focused["outside_px"] < CONTROL_RING_MIN_PX:
        bad.append("02-focused: only %d accent px outside the primary; ASSA-315 measured the host "
                   "box's ring at 526" % focused["outside_px"])
    if focused["outside_box"] != CONTROL_RING_BOX:
        bad.append("02-focused: the outside mass spans x%d..%d y%d..%d; ASSA-315 published "
                   "x%d..%d y%d..%d" % (*focused["outside_box"], *CONTROL_RING_BOX))
    if bad:
        print("\nNO VERDICT -- this instrument does not reproduce ASSA-315's own measurement:")
        for line in bad:
            print("  " + line)
        return 2
    print("\nCONTROL PASSES. On ASSA-315's own frames: nothing accent outside the primary when")
    print("unfocused, and when focused an outside mass at exactly their published x417..656")
    print("y408..437. So an outside mass this script cannot find on a new frame is really absent.")
    return 0


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    if argv[0] == "--control":
        if len(argv) != 2:
            print("--control takes one directory")
            return 2
        return control(argv[1])
    for path in argv:
        describe(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
