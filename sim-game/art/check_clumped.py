#!/usr/bin/env python3
"""GRADE-A ORE IS CLUMPED, AND OPEN GROUND BETWEEN CLUMPS IS THE PROOF (ASSA-216)

    art/check_clumped.py              # the guard, on the shipped sheet
    art/check_clumped.py <sheet.png>  # judge any ore sheet, e.g. an old one:
                                      #   git show 0ddbbb9:sim-game/client/assets/sprites/ore.png > /tmp/old.png
                                      #   art/check_clumped.py /tmp/old.png   -> FAIL, as it must

WHAT THIS DEFENDS. Maren's ASSA-216 ruling was arrangement, not value: 19 rocks
spread uniformly over a tile leave holes of one size everywhere, so a deposit
integrates to a flat yellow mass at 1x -- "candy", "confetti", a texture-scale
complaint and not a colour one. The fix gathers the same rocks into clumps that
straddle the tile's joins. Nothing about the fix is visible in any quantity the
other checks measure: the count, the sizes, the colours, the palette and (since
`relax()`) the coverage are all deliberately unchanged, so `check_headroom`,
`check_species_tints` and `species_probe` would all stay green on a revert.

THE MEASURE IS THE GAP, BECAUSE THE GAP IS WHAT A CLUMP MAKES. For every open
pixel of a tile, the distance to the nearest rock, on the TORUS because the tile
is seamless; the number is the mean over open pixels. Scatter 19 rocks evenly
and that mean is small everywhere; gather them and lanes open between the
clumps. On the authored 64 px frames it rose on every grade-A row at once:
3.37 -> 4.15, 4.86 -> 6.40, 3.84 -> 4.64, 3.71 -> 4.81.

GRADE A ONLY, AND I WILL SAY WHY RATHER THAN QUIETLY PICK THE ROWS THAT WON.
This item is about a grade-A deposit; grade A is where the rock is dense enough
for an arrangement to read at all. On the B rows the same statistic moved by
anything from -1% to +42%, so a floor there would either be vacuous or would
fail honest art. This check makes no claim about B, C or depleted.

THE FLOOR IS A MEASUREMENT WITH SLACK, NOT A NUMBER I LIKED: each row's value
as it ships, times 0.90. The slack is generous on purpose and still huge against
the noise -- two independent Blender renders of the same art give this statistic
to **0.00%**, because it reads the alpha silhouette and not the shading.

EXIT CODES
  0 PASS       -- every grade-A row still has its lanes.
  1 FAIL       -- a row's open ground tightened: the clump has been undone,
                  or density was raised until the gaps closed.
  2 NO VERDICT -- sheet unreadable or a control did not hold. Never a pass.
"""
import json, os, sys
from collections import deque

ART = os.path.dirname(os.path.abspath(__file__))
SPRITES = os.path.join(os.path.dirname(ART), "client", "assets", "sprites")
OPAQUE = 200          # same cut as check_headroom: above this is surface
SLACK = 0.90

# MEASURED ON THE SHIPPED SHEET, TIMES SLACK. Mean distance in authored pixels
# from open ground to the nearest rock, per grade-A row.
FLOOR = {
    "A_full_v0": 3.74,
    "A_full_v1": 5.76,
    "A_full_v2": 4.18,
    "A_full_v3": 4.33,
}


class CannotCheck(Exception):
    pass


def lanes(mask, w, h):
    """Mean distance from an open pixel to the nearest solid one, wrapping.

    A breadth-first flood from every solid pixel at once, which is the exact
    4-connected distance transform and needs no library -- these checks run on
    plain `python3` in CI, where there is no pip and no numpy."""
    INF = 1 << 30
    d = [[0 if mask[y][x] else INF for x in range(w)] for y in range(h)]
    q = deque((x, y) for y in range(h) for x in range(w) if mask[y][x])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = (x + dx) % w, (y + dy) % h
            if d[ny][nx] > d[y][x] + 1:
                d[ny][nx] = d[y][x] + 1
                q.append((nx, ny))
    open_px = [d[y][x] for y in range(h) for x in range(w) if not mask[y][x]]
    return (sum(open_px) / len(open_px)) if open_px else None


def rows_of(sheet):
    """(row name, solid mask) for the grade-A rows of an ore sheet."""
    sys.path.insert(0, ART)
    from png_stdlib import read_rgba
    man_path = os.path.join(SPRITES, "manifest.json")
    if not os.path.exists(man_path):
        raise CannotCheck("no manifest at %s -- run art/build.py" % man_path)
    man = json.load(open(man_path)).get("ore")
    if not man:
        raise CannotCheck("the manifest describes no `ore` asset.")
    if not os.path.exists(sheet):
        raise CannotCheck("no sheet at %s" % sheet)
    fw, fh = man["frame_px"]
    _w, _h, px = read_rgba(sheet)
    out = []
    for ri, row in enumerate(man["rows"]):
        if row["name"] not in FLOOR:
            continue
        mask = [[px[ri * fh + y][x][3] > OPAQUE for x in range(fw)] for y in range(fh)]
        out.append((row["name"], mask, fw, fh))
    if len(out) != len(FLOOR):
        raise CannotCheck("found %d of the %d rows this check is about; the sheet "
                          "or the manifest has been renamed under it."
                          % (len(out), len(FLOOR)))
    return out


def judge(measured):
    """[(row, mean)] -> the rows whose lanes have closed. One judge for the real
    run and for the can-fail control, so the control cannot take another path."""
    return [(n, v, FLOOR[n]) for n, v in measured if v < FLOOR[n]]


def main(argv):
    sheet = argv[0] if argv else os.path.join(SPRITES, "ore.png")
    rows = rows_of(sheet)

    # CONTROL 1, WIRING: a row with no rock, or no open ground, measures nothing
    # -- and four identical numbers would mean the sheet is not being cut apart.
    for name, mask, fw, fh in rows:
        solid = sum(sum(1 for v in line if v) for line in mask)
        if solid == 0 or solid == fw * fh:
            raise CannotCheck("%s is all rock or all hole (%d of %d px): this "
                              "statistic says nothing about it." % (name, solid, fw * fh))
    measured = [(n, lanes(m, w, h)) for n, m, w, h in rows]
    if len(set(round(v, 3) for _, v in measured)) < 2:
        raise CannotCheck("every row measured the same -- the rows are not being "
                          "read apart, so none of these numbers mean anything.")

    if "--record" in argv:
        print("FLOOR = {   # measured x %.2f" % SLACK)
        for n, v in measured:
            print("    %-14s %.2f," % ('"%s":' % n, v * SLACK))
        print("}")
        return 0

    # CONTROL 2, IT CAN FAIL -- and the first lever I wrote for it did not, which
    # is the reason this one is a model and not a nudge. Growing the real mask by
    # a pixel all round LOOKS like closing the gaps and barely moves the mean:
    # it deletes every open pixel at distance 1 and takes 1 off the rest, and
    # E[d | d >= 2] - 1 lands back where E[d] was. The control caught my control.
    #
    # So the lever is the defect itself: a REGULAR scatter -- discs on a 5x5 grid
    # at the row's own coverage, which is uniform art of the same density, the
    # exact thing the clump replaced. It must be judged a failure.
    name, mask, fw, fh = rows[0]
    cov = sum(sum(1 for v in line if v) for line in mask) / float(fw * fh)
    import math
    side, flat = 5, [[False] * fw for _ in range(fh)]
    rad = math.sqrt(cov * fw * fh / (side * side * math.pi))
    for gy in range(side):
        for gx in range(side):
            cx, cy = (gx + 0.5) * fw / side, (gy + 0.5) * fh / side
            for y in range(fh):
                for x in range(fw):
                    dx = min(abs(x - cx), fw - abs(x - cx))
                    dy = min(abs(y - cy), fh - abs(y - cy))
                    if dx * dx + dy * dy <= rad * rad:
                        flat[y][x] = True
    if not judge([(name, lanes(flat, fw, fh))]):
        raise CannotCheck("the can-fail control did not fail: a regular 5x5 scatter "
                          "at %s's own coverage (%.1f%%) measured %.2f px of open "
                          "ground and this check passed it. The guard is not wired "
                          "to the verdict." % (name, 100 * cov, lanes(flat, fw, fh)))

    bad = judge(measured)
    print("OPEN GROUND BETWEEN CLUMPS -- mean distance from an open pixel to the\n"
          "nearest rock, wrapping, per grade-A row of %s.\n" % os.path.basename(sheet))
    print("%-14s %10s %10s" % ("row", "mean px", "floor"))
    for n, v in measured:
        print("%-14s %10.2f %10.2f" % (n, v, FLOOR[n]))

    if bad:
        print("\n%d GRADE-A ROW(S) LOST THE LANES BETWEEN THEIR CLUMPS:" % len(bad))
        for n, v, floor in bad:
            print("  %-12s %.2f px of open ground, against a floor of %.2f" % (n, v, floor))
        print("\nASSA-216: the complaint this art answers is that a deposit reads as one\n"
              "flat mass at 1x. The clump in `art/assets/ore.py` (CLUMP_PULL, CLUMP_SEP,\n"
              "CLUMP_EDGES) is what opens the gaps. If this went red on purpose, say in\n"
              "the commit message what replaced it -- and look at a 9x9 field at 32 px\n"
              "before you believe any number here, including this one.")
        print("\nVERDICT: FAIL (exit 1).")
        return 1
    print("\nVERDICT: PASS (exit 0). Grade-A ore still reads as clumps with ground\n"
          "between them, and both controls held.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except CannotCheck as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n%s" % why)
        sys.exit(2)
