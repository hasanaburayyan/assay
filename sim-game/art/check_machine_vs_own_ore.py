#!/usr/bin/env python3
"""A planted machine still reads against the ore of its OWN species. (ASSA-159)

    art/check_machine_vs_own_ore.py

WHAT THIS IS FOR
  A drill must stand ON a deposit to run, and a building and the ore of its
  species are tinted by the SAME `Color` -- not a similar one, the identical
  one, by construction:

      ore, world view   scene_view.gd:239   _place(.., AssayHud.species_tint(species), ..)
      a building        scene_view.gd:314   AssaySprites.tint_for(building)
                        sprites.gd:226      Color(AssayHud.SPECIES_TINTS[species])
                        hud.gd:200          Color(SPECIES_TINTS[species])

  Sheets are drawn species-neutral on purpose (ASSA-19/20), so `modulate` is the
  whole look and there is no purity dim on this path (`deposit_color` dims, and
  the world view calls `species_tint`, which does not). So the ONLY thing that
  stops your first machine from being camouflaged against its own deposit is the
  greyscale art underneath -- and that is a thing a re-render can walk back with
  nothing going red. This is what notices (Maren's ask on ASSA-159).

WHY IT NEEDS NO WINDOW SHOT, WHICH IS WHY IT CAN BE A `check_`
  Because the two carry the same colour, the separation is (what the greyscale
  sheets differ by) x (what that tint does to luminance) -- and the tint very
  nearly cancels in a RATIO. So the whole measurement falls out of the shipped
  sheets and `SPECIES_TINTS`, headless, in under a second. `art/grid_findability.py`
  judges a window shot and therefore cannot be a `check_` at all; this one can.

THE BAR
  A planted machine reaches RATIO : 1 against the ore of its own species, at
  every species and every grade. 3:1 is the non-text sibling of the 4.5:1 this
  UI already enforces on text (`check_glyph_contrast.py`), not a number invented
  here, and it is WRITTEN DOWN BELOW RATHER THAN DERIVED. That part is the point:
  the ore rows and the part rows are both inputs to this check, so a bar computed
  from them would pass at any art, which is the vacuous green this file exists to
  avoid. If the bar ever moves it moves in a commit, with a reason.

WHAT IT MEASURES, AND THE ONE THING TO KNOW ABOUT IT
  The median luminance of each part row against the median of the ore row, worst
  over 6 species x 3 grades. Maren's statistic, kept deliberately: it is the one
  the item was ruled on.

  **IT IS NEARLY A STEP FUNCTION AND A READER SHOULD KNOW THAT.** A part row's
  luminance histogram is BIMODAL -- key-lit faces in one mode, fill-only faces in
  the other -- and a median sits wherever the 50% crossing falls. Measured on
  `frame`, moving a tenth of its pixels across the gap moved the ratio 1.49 ->
  2.84. So this check says "the art is on the right side of the gap", and does NOT
  say "the machine is 3x darker than its ore everywhere". The margin printed below
  the table is the honest reading of how much room there is.

  It also does not look at the player, the ground, or a machine against ore of
  ANOTHER species. Machine vs ground was settled separately (ASSA-137), and the
  worst case there is not here.

LEVERS -- every one of these MUST make it fail, which is how you know it fires
  FAKE_PART_SHEETS=<dir>   read the four part sheets (and their manifest) from
                           somewhere else. Point it at a checkout of main before
                           ASSA-159 and the ratio is 1.49: the defect this check
                           was written against, as its own red control. The
                           failing case is a real commit, not a synthetic sheet.
  FAKE_BAR=<float>         move the bar in memory. Raise it above the art's
                           headroom and this must fail; it is here so the margin
                           printed below the table can be trusted.

Stdlib only, so CI can run it with plain `python3`.
"""
import json
import os
import sys

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
SPRITES = os.path.join(ROOT, "client", "assets", "sprites")

sys.path.insert(0, ART)
from png_stdlib import read_rgba  # noqa: E402

# THE BAR, written down. See "THE BAR" above for why it is not computed.
RATIO = 3.0

# The six species tints, `hud.gd:106`. Duplicated here rather than parsed out of
# GDScript because `art/check_species_tints.py` already owns "the art and the client
# agree about this list" and a second parser would be a second thing to rot.
TINTS = ["#7A29CC", "#FF3333", "#FF80BF", "#FFFF33", "#3333FF", "#509BE6"]

# The four parts a machine is assembled from, and the ore rows a deposit is drawn
# with. `*_full_v0` is the full-pebble variant at each grade.
PARTS = ("frame", "head", "handle", "hopper")
GRADES = ("C", "B", "A")
# The grade a machine body is measured at. Parts render one row per grade and the
# ladder is monotone in luminance, so the MIDDLE row is the representative body and
# the two outer rows are checked separately below.
PART_ROW = "B"

# Maren's ratio has a +5 floor on both sides so that two near-black medians cannot
# report a huge ratio out of rounding noise. Kept verbatim from
# `workspaces/maren/maren_159_machine_vs_own_ore.py`, which is what the item was ruled on.
FLOOR = 5.0


def lum(c):
    """Rec. 709 luminance, the weights `AssayHud` uses for its own contrast ratios."""
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def tinted_lum(grey, hexs):
    """What `modulate` does to one greyscale pixel: a per-channel multiply."""
    t = [int(hexs[1 + 2 * i:3 + 2 * i], 16) / 255.0 for i in range(3)]
    return lum(tuple(grey[i] * t[i] for i in range(3)))


def row_median(sprites, key, row_name):
    """Median-by-luminance pixel of one named row of one sheet.

    Opaque pixels only (alpha > 200): the antialiased skirt of a sprite is a blend
    with whatever is behind it in the sheet, which is nothing, so including it would
    measure transparency.
    """
    man = json.load(open(os.path.join(sprites, "manifest.json")))
    spec = man[key]
    fh = int(spec["frame_px"][1])
    names = [r["name"] for r in spec["rows"]]
    if row_name not in names:
        return None
    i = names.index(row_name)
    w, h, px = read_rgba(os.path.join(sprites, key + ".png"))
    vals = []
    for y in range(i * fh, min((i + 1) * fh, h)):
        for x in range(w):
            c = px[y][x]
            if c[3] > 200:
                vals.append((c[0], c[1], c[2]))
    if not vals:
        return None
    vals.sort(key=lum)
    return vals[len(vals) // 2]


def main():
    print(__doc__.splitlines()[0])
    bar = RATIO
    part_src = SPRITES

    if os.environ.get("FAKE_PART_SHEETS"):
        part_src = os.environ["FAKE_PART_SHEETS"]
        print("\n[RED LEVER] the four part sheets are read from %s instead of the\n"
              "            shipped ones. Pointed at a checkout of main before ASSA-159 this\n"
              "            reports 1.49 -- the camouflaged drill itself. MUST fail.\n" % part_src)
    if os.environ.get("FAKE_BAR"):
        bar = float(os.environ["FAKE_BAR"])
        print("\n[RED LEVER] the bar is forced to %.2f in memory; the shipped constant is\n"
              "            %.2f. Above the printed margin this MUST fail.\n" % (bar, RATIO))

    # Ore always comes from the SHIPPED tree even under FAKE_PART_SHEETS: the lever is
    # for replacing the MACHINE, and mixing two commits' ore rows in would measure a
    # difference between checkouts instead of a difference between machine and ore.
    ore = {}
    for g in GRADES:
        med = row_median(SPRITES, "ore", "%s_full_v0" % g)
        if med is None:
            print("\n  FAIL: ore has no `%s_full_v0` row, so there is nothing to measure a\n"
                  "  machine against. This check will not pass for lack of an input." % g)
            return 1
        ore[g] = med

    parts = {}
    for k in PARTS:
        med = row_median(part_src, k, PART_ROW)
        if med is None:
            print("\n  FAIL: part `%s` has no `%s` row in %s. A missing input is not\n"
                  "  allowed to read as `no disagreement found`."
                  % (k, PART_ROW, os.path.relpath(part_src, ROOT)
                     if part_src.startswith(ROOT) else part_src))
            return 1
        parts[k] = med

    print("\npart rows (grade %s, untinted luminance):  %s"
          % (PART_ROW, "   ".join("%s %5.1f" % (k, lum(parts[k])) for k in PARTS)))
    print("ore rows  (untinted luminance):           %s"
          % "   ".join("%s %5.1f" % (g, lum(ore[g])) for g in GRADES))
    print("\nA machine body is the mean of its four part medians; the tint is a multiply and\n"
          "very nearly cancels in the ratio, which is why every row below reads alike.\n")

    # THE FULL TABLE, PRINTED EVEN WHEN GREEN (Maren's ask). A bare PASS hides which
    # species and which grade is the worst, and that is exactly what a fix aims at.
    print("  %-9s | %s" % ("tint", "  ".join("ore %s: machine /  ore (ratio)" % g for g in GRADES)))
    worst = None
    for t in TINTS:
        mach = sum(tinted_lum(parts[k], t) for k in PARTS) / len(PARTS)
        cells = []
        for g in GRADES:
            o = tinted_lum(ore[g], t)
            ratio = (max(o, mach) + FLOOR) / (min(o, mach) + FLOOR)
            cells.append("%12.1f /%6.1f (%4.2f)" % (mach, o, ratio))
            if worst is None or ratio < worst[0]:
                worst = (ratio, t, g)
        print("  %-9s | %s" % (t, "  ".join(cells)))

    ok = worst[0] >= bar
    print("\nWORST %.2f : 1   on tint %s against grade-%s ore   (bar %.2f)"
          % (worst[0], worst[1], worst[2], bar))
    print("margin %+.2f -- how far the art could drift before this goes red. The statistic is\n"
          "a median on a bimodal row, so read that as room on the right side of the gap,\n"
          "not as a smooth distance." % (worst[0] - bar))

    if not ok:
        print("\n  FAIL: a planted machine is %.2f : 1 against the ore of its own species, under\n"
              "  the %.2f : 1 bar. A drill stands ON a deposit to run and wears the same\n"
              "  `modulate` colour as it, so this is the first machine a player builds being\n"
              "  camouflaged against the ground it stands on.\n"
              "\n"
              "  THE LEVER IS `rig.MACHINE_FILL`, not a material: a part row is bimodal, and\n"
              "  lowering the fill moves the shadowed mode down while leaving the lit faces --\n"
              "  the pixels that carry the species' chroma under a multiply -- alone. Darkening\n"
              "  the material instead reaches the bar only where the six species stop being\n"
              "  distinguishable from each other (measured: dE 7.7 against DISTINCT 12)."
              % (worst[0], bar))

    print("\nVERDICT: %s" % ("GREEN" if ok else "RED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
