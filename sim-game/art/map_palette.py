#!/usr/bin/env -S uv run --quiet --with pillow python
"""The map and the world have to be ONE palette. Are they?

    art/map_palette.py

The client draws deposits twice: as tinted ore tiles in the world, and as
coloured patches on the schematic map in `client/scripts/hud.gd`. A player
learns "species 2 is the pink one" from whichever they look at first, so the
two have to agree or the colour is teaching two different lessons.

WHAT THIS FOUND (ASSA-25). They do not agree, and the map's palette is the
one the art rejected. `deposit_color()` is
`Color.from_hsv(species/count, 0.55, 0.30 + 0.60*purity)` -- six hues evenly
spaced round the wheel, which is exactly the scheme species_probe.py measured
at protan 5.7 and Decision #36 replaced with a slot table. Nobody shipped a
mistake: the client's version predates the table and the fix never crossed
the language boundary. That is the normal way a palette rots, which is why
this is a script and not a note.

WHY THE SHIPPED TINTS ARE NOT THE ANSWER, DIRECTLY. `art/species_tints.py`
holds MULTIPLIERS over light rock, not fills. #7A29CC painted flat on a dark
map sinks into the background; it is only vivid because it is multiplied over
an L* 84 base. The colour a player actually learns is the RESULT -- a tinted
ore tile -- so the map's table is derived from that, here, rather than
retyped from the tints or invented again in GDScript.

The derivation is deliberately the same instrument as everywhere else in this
pipeline: dE76, the Machado matrices, DISTINCT = 12, all imported from
species_probe rather than restated.

RED LEVER: MAP_PALETTE_EVEN=1 derives the table from evenly spaced hues
instead -- the scheme that is in the client today -- which MUST fail the
colour-blind floor. A check I have not seen fail is not a check.
"""
import colorsys
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from species_tints import SPECIES_TINTS
from species_probe import DISTINCT, OBSERVERS, as_seen, dE
from loudness import at_1x, frame_of, measure, tint

# client/scripts/main.gd: draw_rect(..., Color(0.10, 0.11, 0.13), true)
MAP_BG = (26, 28, 33)
# The two ends hud.gd interpolates between: grade C is the dim end, A the
# bright one, which is the shape deposit_color() already has.
ENDS = ("C", "A")

EVEN = os.environ.get("MAP_PALETTE_EVEN")
if EVEN:
    print("[RED LEVER] deriving the table from six evenly spaced hues -- the\n"
          "            scheme that is in hud.gd today. It MUST fail.\n")


def seen_by(rgb, observer):
    """One colour through one observer, using the pipeline's own matrices."""
    px = tuple(int(round(v)) for v in rgb)
    im = Image.new("RGBA", (1, 1), px + (255,))
    return as_seen(im, observer, "linear").convert("RGBA").getpixel((0, 0))[:3]


def world_colour(species, grade):
    """What the WORLD shows for this species at this grade: the mean of a real
    tinted ore tile at the size the player sees it."""
    if EVEN:
        h = species / float(len(SPECIES_TINTS))
        v = 0.42 if grade == "C" else 0.84
        return tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, 0.55, v))
    img = at_1x(tint(frame_of("ore", "%s_full_v0" % grade), SPECIES_TINTS[species]))
    return tuple(round(v) for v in measure(img)["rgb"])


def main():
    n = len(SPECIES_TINTS)
    ok = True
    print("ONE PALETTE, TWO SURFACES -- the map table derived from the world.")
    print("dE76, Machado full severity, floor %.0f: all imported from"
          " species_probe.py.\n" % DISTINCT)

    table = {}
    for g in ENDS:
        table[g] = [world_colour(i, g) for i in range(n)]

    for g in ENDS:
        cols = table[g]
        print("grade %s: %s" % (g, "  ".join("#%02X%02X%02X" % c for c in cols)))
        for obs in OBSERVERS:
            s = [seen_by(c, obs) for c in cols]
            worst, i, j = min((dE(s[a], s[b]), a, b)
                              for a in range(n) for b in range(a + 1, n))
            good = worst >= DISTINCT
            ok = ok and good
            print("   %-7s closest pair %d vs %d at dE %5.1f  %s"
                  % (obs, i, j, worst, "OK" if good else "TOO CLOSE"))
        # A swatch that matches the world perfectly and vanishes into the map
        # is not a fix. The background is the other thing it has to beat.
        bg, k = min((dE(c, MAP_BG), i) for i, c in enumerate(cols))
        good = bg >= DISTINCT
        ok = ok and good
        print("   vs map background #%02X%02X%02X: worst is species%d at dE %5.1f  %s"
              % (MAP_BG + (k, bg, "OK" if good else "SINKS")))
        print()

    print("Drop into hud.gd as a species-indexed constant, interpolated by")
    print("purity between the two ends the way deposit_color() already")
    print("interpolates V. It is a table indexed by species, so it keeps the")
    print("rule that no GDScript file reads a species sheet (Decision #36).")
    print("\nconst SPECIES_MAP_LOW := [%s]"
          % ", ".join('Color("%02x%02x%02x")' % c for c in table["C"]))
    print("const SPECIES_MAP_HIGH := [%s]"
          % ", ".join('Color("%02x%02x%02x")' % c for c in table["A"]))

    print("\nVERDICT: %s" % ("GREEN" if ok else "RED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
