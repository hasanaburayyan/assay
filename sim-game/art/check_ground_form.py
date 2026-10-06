#!/usr/bin/env python3
"""THE GROUND HAS STRUCTURE LARGER THAN A TILE, AND NOTHING ELSE HERE CAN SEE THAT (ASSA-150)

    art/check_ground_form.py              # the guard, on the shipped sheet
    art/check_ground_form.py <sheet.png>  # judge any ground sheet, e.g. the one before the mottle:
                                          #   git show <sha>:sim-game/client/assets/sprites/ground.png > /tmp/old.png
                                          #   art/check_ground_form.py /tmp/old.png   -> FAIL, as it must

WHAT THIS DEFENDS. `ground.py`'s first three layers are drawn inside the per-cell loop, so whatever
they do they do inside 32 px; the field they add up to was measured as white noise above half a
tile -- cell means one tile apart correlated -0.097 and +0.062, and the structure function was flat
from 48 px to 256. The fourth layer, the MOTTLE, is the only one whose features cross a tile. It is
eight domes drawn once over the whole field, and **every quantity the other checks measure is blind
to it**: the palette is unchanged, the tone budget is unchanged, coverage is unchanged, no row is
added. `check_ground_block`, `check_scatter`, `check_species_tints` and `check_headroom` would all
stay green if someone set `MOTTLE_BLOBS = 0` and handed the board back a field with no form in it.

THE MEASURE IS THE CORRELATION BETWEEN NEIGHBOURING CELLS, because that is what "a feature bigger
than a tile" means: two tiles side by side have to know something about each other. The cells are
laid back out as the field -- `v[cy * BLOCK + cx]`, which is `ground.py`'s own comment and
`scene_view.gd`'s `posmod(y, h) * w + posmod(x, w)` -- and the correlation is taken on the torus,
because the field wraps.

THE FLOOR IS 0.20 AND IT IS NOT THE MEASUREMENT. The shipped field measures +0.357 / +0.322 and the
pre-mottle one -0.097 / +0.062, so anything between separates them; with 64 cells the standard
error on r is about 0.125, so a floor set AT the measurement would go red on an honest re-render
that happened to roll a quieter layout. 0.20 sits about one standard error under what ships and
about two over what it replaced.

EXIT CODES
  0 PASS       -- the ground still has form above a tile.
  1 FAIL       -- neighbouring tiles have stopped knowing about each other.
  2 NO VERDICT -- sheet unreadable or a control did not hold. Never a pass.
"""
import json, os, sys

ART = os.path.dirname(os.path.abspath(__file__))
SPRITES = os.path.join(os.path.dirname(ART), "client", "assets", "sprites")
FLOOR = 0.20
LUM = (0.2126, 0.7152, 0.0722)


class CannotCheck(Exception):
    pass


def cell_means(sheet):
    """Per-cell mean luminance, laid out as the field: (bw, bh, {(cx, cy): mean})."""
    sys.path.insert(0, ART)
    from png_stdlib import read_rgba
    man_path = os.path.join(SPRITES, "manifest.json")
    if not os.path.exists(man_path):
        raise CannotCheck("no manifest at %s -- run art/build.py" % man_path)
    man = json.load(open(man_path)).get("ground")
    if not man:
        raise CannotCheck("the manifest describes no `ground` asset.")
    block = man.get("block")
    if not block:
        raise CannotCheck("`ground` has no `block` in the manifest: the cells are not placed by "
                          "position, so 'neighbouring cell' has no meaning and this check cannot "
                          "ask its question.")
    bw, bh = block
    fw, fh = man["frame_px"]
    rows = [r["name"] for r in man["rows"]]
    if len(rows) < bw * bh:
        raise CannotCheck("manifest names %d rows for a %dx%d block" % (len(rows), bw, bh))
    if not os.path.exists(sheet):
        raise CannotCheck("no sheet at %s" % sheet)
    _w, _h, px = read_rgba(sheet)
    means = {}
    for cy in range(bh):
        for cx in range(bw):
            i = cy * bw + cx
            tot = 0.0
            for y in range(i * fh, (i + 1) * fh):
                line = px[y]
                for x in range(fw):
                    p = line[x]
                    tot += LUM[0] * p[0] + LUM[1] * p[1] + LUM[2] * p[2]
            means[(cx, cy)] = tot / (fw * fh)
    return bw, bh, means


def correlation(bw, bh, means, lag=1):
    """Pearson r between a cell's mean and its neighbour `lag` tiles away, wrapped, per axis."""
    out = []
    for pairs in ([(means[(cx, cy)], means[((cx + lag) % bw, cy)])
                   for cy in range(bh) for cx in range(bw)],
                  [(means[(cx, cy)], means[(cx, (cy + lag) % bh)])
                   for cy in range(bh) for cx in range(bw)]):
        n = len(pairs)
        ax = sum(a for a, _ in pairs) / n
        ay = sum(b for _, b in pairs) / n
        sxy = sum((a - ax) * (b - ay) for a, b in pairs)
        sxx = sum((a - ax) ** 2 for a, _ in pairs)
        syy = sum((b - ay) ** 2 for _, b in pairs)
        out.append(None if sxx == 0 or syy == 0 else sxy / (sxx * syy) ** 0.5)
    return out


def judge(rh, rv):
    """[(axis, r)] for the axes that have lost their form. One judge for the real run and the
    control, so the control cannot pass by taking another path to the verdict."""
    bad = []
    for axis, r in (("horizontal", rh), ("vertical", rv)):
        if r is None or r < FLOOR:
            bad.append((axis, r))
    return bad


def main(argv):
    sheet = argv[0] if argv else os.path.join(SPRITES, "ground.png")
    bw, bh, means = cell_means(sheet)

    # CONTROL 1, WIRING: lag 0 is a cell against itself and must be exactly 1. If the cells are not
    # being cut apart and laid out as the field, nothing below means anything.
    z = correlation(bw, bh, means, lag=0)
    if z[0] is None or z[1] is None or min(z) < 0.999:
        raise CannotCheck("lag 0 is %s, not 1: the sheet is not being laid out as the field, so "
                          "'neighbouring cell' is not what this measured." % (z,))
    if len(set(round(v, 4) for v in means.values())) < 4:
        raise CannotCheck("the cells are nearly all one value -- a blank sheet would pass every "
                          "test in this file.")

    rh, rv = correlation(bw, bh, means, lag=1)

    if "--record" in argv:
        print("measured: horizontal %.3f  vertical %.3f  (FLOOR is %.2f)" % (rh, rv, FLOOR))
        return 0

    # CONTROL 2, IT CAN FAIL: the defect itself, not a nudge. Re-deal the same cell means to
    # different places -- the field a per-cell layer with no mottle produces, where every cell is
    # drawn independently -- and the judge must call it a failure. A fixed shuffle, no RNG: a
    # control whose answer moved between runs would be worse than no control.
    order = sorted(means, key=lambda k: (means[k], k))
    dealt = {k: means[order[(i * 37 + 11) % len(order)]] for i, k in enumerate(sorted(means))}
    drh, drv = correlation(bw, bh, dealt, lag=1)
    if not judge(drh, drv):
        raise CannotCheck("the can-fail control did not fail: the same cell means re-dealt to "
                          "different places measured %.3f / %.3f and this check passed them. The "
                          "guard is not wired to the verdict." % (drh, drv))

    bad = judge(rh, rv)
    print("STRUCTURE ABOVE A TILE -- correlation between neighbouring cell means, wrapped,\n"
          "on %s (%dx%d cells).\n" % (os.path.basename(sheet), bw, bh))
    print("%-14s %10s %10s" % ("", "measured", "floor"))
    print("%-14s %10.3f %10.2f" % ("horizontal", rh, FLOOR))
    print("%-14s %10.3f %10.2f" % ("vertical", rv, FLOOR))

    if bad:
        print("\n%d AXIS/AXES HAVE NO FORM ABOVE A TILE:" % len(bad))
        for axis, r in bad:
            print("  %-12s r = %s against a floor of %.2f"
                  % (axis, "undefined" if r is None else "%.3f" % r, FLOOR))
        print("\nASSA-150: the first three layers in `ground.py` are drawn per CELL, so they cannot\n"
              "make a feature bigger than a tile however they are arranged. The MOTTLE is the one\n"
              "that can -- look at `MOTTLE_BLOBS`, `MOTTLE_R` and `MOTTLE_STEP` before anything\n"
              "else. If this went red on purpose, say in the commit message what replaced it, and\n"
              "look at a field at 32 px before believing any number here, including this one.")
        print("\nVERDICT: FAIL (exit 1).")
        return 1
    print("\nVERDICT: PASS (exit 0). Two tiles side by side still know something about each\n"
          "other, and both controls held.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except CannotCheck as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n%s" % why)
        sys.exit(2)
