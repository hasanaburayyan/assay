#!/usr/bin/env python3
"""ASSA-361: WHAT IS LEFT OF THE SELECTION MARK ONCE THE BODY IS DRAWN IN FRONT OF IT.

Maren's boxes 1, 2 and 5 on the same pixels of a before frame and an after frame, at 1x.

**WHY THIS IS NOT A COLOUR MATCH, WHICH IS THE WHOLE POINT OF THE FILE.** My first pass found the
mark by looking for `HOVER` (242,242,242) within 4 and reported `mark+halo 20 px` on the fixed
frame -- the ring had all but vanished. It had not. A player's sprite carries a **semi-transparent
contact shadow** the width of its tile, so drawing the body after the mark does not erase the bars
it covers, it DIMS them: 242 -> 205..225. A detector that knows one colour reads a dimmed ring as
no ring, and the cheap repair -- widen the tolerance until 205 counts -- would let the tolerance
answer the question instead of the picture.

So the ring is located ONCE, in the BEFORE frame where nothing dims it, by exact `HOVER`; its four
bars and their keyline are derived from that box; and both frames are then read AT THOSE SAME
PIXELS (Maren's box 8). Each is classified:

    ink    the body is in front of it           -- box 1 wants exactly this where the body was eaten
    mark   still the mark: bright and neutral   -- box 2 wants one per row and per column
    other  neither                              -- ground showing through, or something unexpected

CONTROL: pass a frame whose body stands clear of the ring (the 2x2 shot). Every bar pixel there
must read `mark` in BOTH frames, or the classifier is wrong rather than the picture.

Usage:
    python3 -I tools/nacre_mark_behind_body.py <before.png> <after.png> [label]
"""
import sys

sys.path.insert(0, "tools")
from nacre_door_contrast import read_png  # noqa: E402

HOVER = (242, 242, 242)
# The world view inside the 1280x720 window, so `HOVER` text in the HUD column is never the ring.
WORLD = (24, 24, 935, 695)


def px(rows, ch, x, y):
    return tuple(int(v) for v in rows[y][x * ch:x * ch + 3])


def ring_box(rows, ch):
    """The ring's outer box, from the one frame where the mark is painted over everything."""
    found = [(x, y)
             for y in range(WORLD[1], WORLD[3] + 1)
             for x in range(WORLD[0], WORLD[2] + 1)
             if all(abs(c - HOVER[i]) <= 4 for i, c in enumerate(px(rows, ch, x, y)))]
    if not found:
        raise SystemExit("no HOVER pixels in the world view of the before frame")
    xs = [p[0] for p in found]
    ys = [p[1] for p in found]
    return min(xs), min(ys), max(xs), max(ys)


def bars(box, thick=2):
    x0, y0, x1, y1 = box
    return [(x0, y0, x1, y0 + thick - 1), (x0, y1 - thick + 1, x1, y1),
            (x0, y0, x0 + thick - 1, y1), (x1 - thick + 1, y0, x1, y1)]


def spread(rects, grow=0):
    seen = set()
    for x0, y0, x1, y1 in rects:
        for y in range(y0 - grow, y1 + grow + 1):
            for x in range(x0 - grow, x1 + grow + 1):
                seen.add((x, y))
    return seen


def classify(c):
    r, g, b = c
    if r > 200 and 110 < g < 190 and b < 90:
        return "ink"
    if 150 < r < 220 and g > 220 and b > 230:
        return "ink"
    # NEUTRAL AND BRIGHT. The mark is painted 242 grey, and a contact shadow is a neutral darkener,
    # so a dimmed bar stays on the grey diagonal. Ground never is: the floor under this ring reads
    # (77,43,73) and the grass around it is green, both far off it.
    if max(c) - min(c) <= 12 and sum(c) / 3.0 >= 150:
        return "mark"
    return "other"


def report(path, bar_px, halo_px, label):
    w, h, ch, rows = read_png(path)
    counts = {"bar": {}, "halo": {}}
    dimmest = None
    for name, group in (("bar", bar_px), ("halo", halo_px)):
        for x, y in group:
            c = px(rows, ch, x, y)
            kind = classify(c)
            counts[name][kind] = counts[name].get(kind, 0) + 1
            if name == "bar" and kind == "mark":
                lum = sum(c) / 3.0
                if dimmest is None or lum < dimmest[0]:
                    dimmest = (lum, x, y)
    gone_rows, gone_cols = [], []
    by_row, by_col = {}, {}
    for x, y in bar_px:
        by_row.setdefault(y, []).append(x)
        by_col.setdefault(x, []).append(y)
    for y, xs in sorted(by_row.items()):
        if not any(classify(px(rows, ch, x, y)) == "mark" for x in xs):
            gone_rows.append(y)
    for x, ys in sorted(by_col.items()):
        if not any(classify(px(rows, ch, x, y)) == "mark" for y in ys):
            gone_cols.append(x)
    print("%-8s %s" % (label, path.rsplit("/", 2)[-1]))
    for name in ("bar", "halo"):
        total = sum(counts[name].values())
        parts = "  ".join("%s %d" % (k, v) for k, v in sorted(counts[name].items()))
        print("    %-5s %4d px   %s" % (name, total, parts))
    print("    rows with no mark left: %d of %d  %s"
          % (len(gone_rows), len(by_row), gone_rows if gone_rows else ""))
    print("    cols with no mark left: %d of %d  %s"
          % (len(gone_cols), len(by_col), gone_cols if gone_cols else ""))
    if dimmest:
        print("    dimmest surviving bar pixel: %.0f of 255 at (%d, %d), painted at 242"
              % dimmest)
    print()


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        raise SystemExit(2)
    _w, _h, _ch, before_rows = read_png(args[0])
    box = ring_box(before_rows, _ch)
    print("ring located in the BEFORE frame: x%d..%d y%d..%d  %dx%d\n"
          % (box[0], box[2], box[1], box[3], box[2] - box[0] + 1, box[3] - box[1] + 1))
    bar_rects = bars(box)
    bar_px = spread(bar_rects)
    halo_px = spread(bar_rects, 1) - bar_px
    label = args[2] if len(args) > 2 else ""
    report(args[0], bar_px, halo_px, "BEFORE " + label)
    report(args[1], bar_px, halo_px, "AFTER  " + label)
