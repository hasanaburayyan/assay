#!/usr/bin/env python3
"""WHERE IS THE GRID? The judge for the ground's tile seam (ASSA-115 box 2, ASSA-162).

    uv run --with pillow python art/grid_findability.py SHOT.png [GROUND.png]
    python3 art/grid_findability.py --selftest        # no Pillow, no shot

Box 2 forbids "a repeating motif a person can point to". This asks the player's question rather
than a ratio: for every candidate column spacing, offset 0..31, it reports the mean |dL| across
the columns at that offset. Offset 0 is the real tile boundary; the other 31 are interior to a
tile and are what the boundary has to hide among.

**WHY THIS IS NOT NAMED `check_*.py`, so nobody re-learns it.** `art/check_ci_runs_every_check.py`
globs `art/check_*.py` and requires CI to name every one, so a `check_` file that CI cannot run
lands red. CI cannot run this one: it judges a **window shot**, `build.yml` runs Godot
`--headless` at every step with no xvfb, and `window_shot.gd` under `--headless` writes a blank
frame and still exits SUCCESS. The exit codes below match the art checks anyway, so the day there
is a GUI runner this is promoted by renaming the file and adding a step.

**THE BAR, AND THE ONE IT REPLACES (Maren, 2026-10-04).** The first version of this failed a
ground if offset 0 was RANK 1 of the 32. That bar was unmeetable by construction: **32 offsets
always have a rank 1.** A rank says WHICH offset stepped most and never BY HOW MUCH, so a ground
with no grid at all fails one time in 32 on a coin flip -- and that is exactly what happened to
Cove's 8x8 field, which is visibly gridless and lost by 0.42 of 255.

So the bar is a magnitude: **offset 0 must sit within 3 standard deviations of the 31 interior
offsets.** No hand-set constant but the sigma count, and it asks the player's question with a
size attached -- is the join distinguishable from a column picked at random?

The numbers it was calibrated against, both from real window shots at seed 14247, tick 301:

    main c1fafb3, six ground images     vert Z +10.17   horiz Z +10.31   FINDABLE
    the 8x8 field, 64 images (#220)     vert Z  -0.08   horiz Z  +1.87   passes

**The field's horizontal offset 0 IS still rank 1, and that is the proof rather than the
problem**: E[max of 31 N(0,1)] = 2.06, so at Z +1.87 the real tile join steps LESS than a
randomly chosen offset is expected to. Main sits five sd past that expectation.

**WHAT IT DOES NOT MEASURE.** Only joins between two PURE-GROUND tiles count -- a tile holding
ore, a machine or the player is skipped -- so this says nothing about how a deposit meets the
dirt. Ground is identified by palette membership in the shipped sheet rather than by a remembered
coordinate, so a shot and a sheet from different commits will quietly find few tiles; the tile
count is printed for exactly that reason. And a seam the eye sees as TONE across many tiles is
not a step at a tile edge: this is the edge instrument, not the field one.

Exit codes match the other art checks: 0 green, 1 a grid is findable, 2 NO VERDICT.
"""
import sys
from pathlib import Path

ART = Path(__file__).resolve().parent
DEFAULT_SHEET = ART.parent / "client/assets/sprites/ground.png"

# The map rectangle inside a `window_shot.gd` capture, and the display pitch. Both are the client's
# numbers, not this script's: `AssayHud` owns them and a shot from a differently sized window is a
# different instrument.
MAP = (24, 96, 932, 696)
TILE = 32

# How far offset 0 may sit above the interior offsets, in their own standard deviations.
MAX_Z = 3.0


def lum(p):
    """Rec. 709 luminance, the same weights `AssayHud` uses for its contrast ratios."""
    return 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]


def verdict(means):
    """One direction's 32 offset means -> the boundary's size against the interior's spread.

    `means[0]` is the real tile boundary; `means[1:]` are interior to a tile. The rank is reported
    because it is what the withdrawn bar read, and because seeing rank 1 beside Z +1.87 is the
    clearest way to say why a rank is not a size.
    """
    boundary, interior = means[0], means[1:]
    mu = sum(interior) / len(interior)
    sd = (sum((v - mu) ** 2 for v in interior) / (len(interior) - 1)) ** 0.5
    if sd == 0.0:
        # A flat colour has no interior variation, so "how many sd above" has no meaning. That is a
        # shot of something other than this ground, not a ground that passes.
        return None
    rank = sorted(range(len(means)), key=lambda o: -means[o]).index(0) + 1
    return {"boundary": boundary, "mu": mu, "sd": sd, "z": (boundary - mu) / sd, "rank": rank}


def offsets(shot_path, sheet_path):
    """(vertical, horizontal) offset means from a window shot, or None if nothing is measurable."""
    from PIL import Image  # imported here so --selftest needs no Pillow

    sheet = Image.open(sheet_path).convert("RGB")
    palette = set()
    for i in range(sheet.height // 64):
        palette |= set(sheet.crop((0, i * 64, 64, i * 64 + 64)).get_flattened_data())

    im = Image.open(shot_path).convert("RGB")
    px = im.load()
    pure = set()
    y = MAP[1] + TILE - 8
    while y + TILE <= MAP[3]:
        x = MAP[0] + TILE - 8
        while x + TILE <= MAP[2]:
            if all(p in palette for p in im.crop((x, y, x + TILE, y + TILE)).get_flattened_data()):
                pure.add((x, y))
            x += TILE
        y += TILE

    vert = [[0.0, 0] for _ in range(TILE)]
    horiz = [[0.0, 0] for _ in range(TILE)]
    for (x, y) in sorted(pure):
        if (x + TILE, y) in pure:
            for k in range(1, TILE + 1):
                step = sum(abs(lum(px[x + k, y + dy]) - lum(px[x + k - 1, y + dy]))
                           for dy in range(TILE)) / TILE
                vert[k % TILE][0] += step
                vert[k % TILE][1] += 1
        if (x, y + TILE) in pure:
            for k in range(1, TILE + 1):
                step = sum(abs(lum(px[x + dx, y + k]) - lum(px[x + dx, y + k - 1]))
                           for dx in range(TILE)) / TILE
                horiz[k % TILE][0] += step
                horiz[k % TILE][1] += 1
    return pure, vert, horiz


def report(name, means):
    """Prints one direction and returns True if a grid is findable there."""
    v = verdict(means)
    if v is None:
        print("%s: NO VERDICT, the interior offsets have zero spread" % name)
        return None
    print("%s  boundary %6.2f   interior %6.2f +/- %4.2f   Z %+6.2f sd   rank %2d of %d   %s"
          % (name, v["boundary"], v["mu"], v["sd"], v["z"], v["rank"], TILE,
             "FINDABLE" if v["z"] > MAX_Z else "lost in the noise"))
    return v["z"] > MAX_Z


def selftest():
    """Prove it red before trusting it green, with no shot and no Pillow.

    Two synthetic sets of offset means: a ground whose tile boundary steps hard, and one whose
    boundary is a draw from the same spread as every other column. The second is the case the
    withdrawn rank bar got wrong -- its boundary is the maximum, and it must still pass.
    """
    jitter = [4.6 + 0.3 * ((i * 7) % 5 - 2) for i in range(TILE - 1)]
    grid = [13.2] + jitter
    field = [max(jitter) + 0.1] + jitter
    ok = True
    for label, means, want_findable in (("a grid", grid, True), ("a field", field, False)):
        v = verdict(means)
        got = v["z"] > MAX_Z
        print("  %-8s Z %+6.2f  rank %2d  -> %s" % (
            label, v["z"], v["rank"], "FINDABLE" if got else "lost in the noise"))
        if got != want_findable:
            print("  SELFTEST FAILED: %s should have been %s"
                  % (label, "FINDABLE" if want_findable else "lost"))
            ok = False
    if field.index(max(field)) != 0:
        print("  SELFTEST FAILED: the field case must put its maximum ON the boundary")
        ok = False
    print("SELFTEST %s: the gridless case is rank 1 and still passes, which is the whole point"
          % ("OK" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv):
    if "--selftest" in argv:
        return selftest()
    if not argv:
        print(__doc__.strip().splitlines()[1].strip(), file=sys.stderr)
        return 2
    shot = Path(argv[0])
    sheet = Path(argv[1]) if len(argv) > 1 else DEFAULT_SHEET
    for p in (shot, sheet):
        if not p.exists():
            print("NO VERDICT: %s does not exist" % p, file=sys.stderr)
            return 2
    try:
        pure, vert, horiz = offsets(shot, sheet)
    except ImportError:
        print("NO VERDICT: Pillow. Run it as `uv run --with pillow python ...`", file=sys.stderr)
        return 2
    print("%d pure-ground tiles in %s" % (len(pure), shot.name))
    if len(pure) < 2:
        # Almost always a shot and a sheet from different commits rather than a ground with no
        # dirt in it, so it says so instead of dividing by a sample of nothing.
        print("NO VERDICT: too few pure-ground tiles. Is the sheet the one this shot was taken "
              "with?", file=sys.stderr)
        return 2
    results = [report("VERTICAL  ", [t / max(n, 1) for t, n in vert]),
               report("HORIZONTAL", [t / max(n, 1) for t, n in horiz])]
    if None in results:
        return 2
    return 1 if any(results) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
