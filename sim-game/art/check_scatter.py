#!/usr/bin/env python3
"""A SCATTER LANDMARK MUST BE VISIBLE ON THE GROUND IT IS DRAWN ON (ASSA-202).

    python3 art/check_scatter.py

No Godot, no Pillow, no network: `png_stdlib.read_rgba` and `colour.dE`, the same
two the other art checks use.

THE FLOOR IS THE GAME DIRECTOR'S, NOT MINE, AND IT CAME FROM A PROP THAT FAILED IT.
Maren ruled on 2026-10-04: *"a landmark row must reach p50 >= 10 dE per-pixel against
the ground it is drawn on"*. She set it because `tuft0` shipped at **p50 3.5 dE with
only 32.4% of its pixels over 6** -- made of four ground tones mixed with each other,
so it was the colour of the thing it stood on. My own aggregate number for the whole
layer (dE 17.5) passed its acceptance box while hiding that dead row, which is the
real lesson here: **a mean over a patch with internal structure cannot report the
patch invisible.** This file is that ruling made executable, so the next prop cannot
arrive invisible and be waved through by an average.

WHAT IT MEASURES, AND WHERE EVERY CHOICE COMES FROM.

  * DRAWN pixels, not authored ones. The client halves an authored frame with
    NEAREST at `TILE_PX 32` against 64 authored px per tile, so this takes every
    other pixel of both sheets -- exactly what the engine keeps. A check at
    authoring scale would be measuring pixels no player ever sees.
  * OPAQUE pixels only (alpha 255). A fringe pixel is part ground by construction
    and sits near 0 dE; counting it measures the antialiaser, not the art. On the
    engine's own frames 77% of the pixels a scatter prop changes are fringe.
  * AGAINST EVERY GROUND CELL, not one. `manifest.ground.block == [8, 8]`, so a prop
    can land on any of 64 different ground pictures. Each prop pixel is compared with
    the ground pixel under it in every cell and the medians are pooled, so "the
    ground it is drawn on" means all of it rather than whichever tile I sampled.
    The worst single cell is printed too, as information -- it is NOT the gate,
    because one unlucky cell is not what a player's eye integrates.
  * GRIT IS EXEMPT ON PURPOSE. The ruling is about LANDMARKS -- the rare large
    things a player navigates by. Grit is texture: it is allowed to be quiet, and
    gating it at 10 dE would turn the ground's second layer into a rash.

Exit codes match the other art checks: 0 green, 1 a landmark row is below the floor,
2 NO VERDICT (something it needs is not where it expects), which fails the job rather
than passing quietly.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from png_stdlib import read_rgba  # noqa: E402
from colour import dE  # noqa: E402

ART = os.path.dirname(os.path.abspath(__file__))
SPRITES = os.path.join(os.path.dirname(ART), "client", "assets", "sprites")

FLOOR = 10.0                     # Maren's ruling, per-pixel median dE
LANDMARK_PREFIXES = ("boulder", "tuft", "log")
GRIT_PREFIX = "grit"


def no_verdict(msg):
    print("NO VERDICT: %s" % msg)
    sys.exit(2)


def halve(px, w, h):
    """What the engine keeps: NEAREST at scale 0.5, so every other pixel."""
    return [[px[y * 2][x * 2] for x in range(w // 2)] for y in range(h // 2)]


def rows_of(manifest, asset):
    return [str(r.get("name", "")) for r in manifest[asset].get("rows", [])]


def main():
    manifest_path = os.path.join(SPRITES, "manifest.json")
    if not os.path.exists(manifest_path):
        no_verdict("no %s; run art/build.py first" % manifest_path)
    manifest = json.load(open(manifest_path))
    if "scatter" not in manifest:
        print("no `scatter` in the manifest: nothing to check, and that is not a failure.")
        return 0
    if "ground" not in manifest:
        no_verdict("the manifest has `scatter` but no `ground` to measure it against")

    gw, gh, gpx = read_rgba(os.path.join(SPRITES, "ground.png"))
    sw, sh, spx = read_rgba(os.path.join(SPRITES, "scatter.png"))
    gfw, gfh = manifest["ground"]["frame_px"]
    sfw, sfh = manifest["scatter"]["frame_px"]
    if sfw % 2 or sfh % 2:
        no_verdict("the scatter frame is %dx%d and an odd authored frame does not halve "
                   "onto whole drawn pixels" % (sfw, sfh))

    ground_rows = rows_of(manifest, "ground")
    scatter_rows = rows_of(manifest, "scatter")
    # The ground sheet is one column of `block` cells; each is a different picture a
    # prop may land on. Halved, each is 32x32.
    cells = []
    for i in range(len(ground_rows)):
        band = [gpx[i * gfh + y] for y in range(gfh)]
        cells.append(halve(band, gfw, gfh))
    if not cells:
        no_verdict("the ground sheet has no rows")
    ch = len(cells[0])
    cw = len(cells[0][0])

    print("floor: a landmark row must reach p50 >= %.1f dE per-pixel (Maren, ASSA-202)" % FLOOR)
    print("scatter %dx%d authored -> %dx%d drawn; %d ground cells of %dx%d drawn\n"
          % (sfw, sfh, sfw // 2, sfh // 2, len(cells), cw, ch))
    print("%-10s %7s | %6s %6s %6s | %s" % ("row", "opaque", "p10", "p50", "p90", "worst cell p50"))

    failures = []
    for index, name in enumerate(scatter_rows):
        band = [spx[index * sfh + y] for y in range(sfh)]
        drawn = halve(band, sfw, sfh)
        opaque = [(x, y) for y in range(len(drawn)) for x in range(len(drawn[0]))
                  if drawn[y][x][3] == 255]
        if not opaque:
            no_verdict("row %s has no opaque pixel at all" % name)
        if name.startswith(GRIT_PREFIX):
            print("%-10s %7d | %s" % (name, len(opaque), "exempt: grit is texture, not a landmark"))
            continue
        if not name.startswith(LANDMARK_PREFIXES):
            no_verdict("row %s is neither grit nor a known landmark kind %s -- this check "
                       "must be told which it is rather than guess" % (name, LANDMARK_PREFIXES))

        pooled = []
        per_cell = []
        # `head` is the frame's headroom in drawn px: the prop's own tile is the BOTTOM
        # 32 rows of the frame, which is the part that lands on ground at all.
        head = len(drawn) - ch
        for cell in cells:
            ds = []
            for (x, y) in opaque:
                under = cell[(y - head) % ch][x % cw]
                ds.append(dE(drawn[y][x][:3], under[:3]))
            ds.sort()
            per_cell.append(ds[len(ds) // 2])
            pooled.extend(ds)
        pooled.sort()
        n = len(pooled)
        p50 = pooled[n // 2]
        worst = min(per_cell)
        flag = "" if p50 >= FLOOR else "   <- BELOW THE FLOOR"
        print("%-10s %7d | %6.1f %6.1f %6.1f | %6.1f%s"
              % (name, len(opaque), pooled[n // 10], p50, pooled[int(n * 0.9)], worst, flag))
        if p50 < FLOOR:
            failures.append((name, p50))

    if failures:
        print("\nFAIL: %s below p50 %.1f dE against the ground it is drawn on."
              % (", ".join("%s (%.1f)" % f for f in failures), FLOOR))
        print("A landmark a player cannot see is not a landmark. Fix the row or cut it;")
        print("if you cut it, raise LANDMARK_ODDS so visible supply stays at ~6 a screen.")
        return 1
    print("\nOK: every landmark row clears the floor.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
