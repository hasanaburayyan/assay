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
  EVERY SILHOUETTE PIXEL of a machine reaches RATIO : 1 against the ore of its
  own species, at every species and every grade. 3:1 is the non-text sibling of
  the 4.5:1 this UI already enforces on text (`check_glyph_contrast.py`), not a
  number invented here, and it is WRITTEN DOWN BELOW RATHER THAN DERIVED. That
  part is the point: the ore rows and the part rows are both inputs to this
  check, so a bar computed from them would pass at any art, which is the vacuous
  green this file exists to avoid. If the bar ever moves it moves in a commit,
  with a reason.

WHY PER PIXEL AND NOT A MEAN (Maren's ruling, 2026-10-04)
  The first draft of this check scored the machine BODY against the ore with a
  median, and the second scored the silhouette with a MEAN. Both are wrong in the
  same way: a mean cannot tell an unbroken line from a dotted one twice as dark.
  Measured, a 1 px rim scores 3.09 as a mean of its silhouette -- a comfortable
  pass -- while a quarter of that silhouette is under 3 : 1, because NEAREST at
  scale 0.5 samples the line away on 31% of the edge. A gap in a dotted outline
  is bare body against ore, which is the defect itself.

  So the statistic is the WORST edge pixel, and the count under the bar is
  printed beside it. No coverage clause and nothing estimated: a gap fails on its
  own merits.

WHERE IT MEASURES: AT THE SIZE THE GAME DRAWS (ASSA-159 box 5)
  `scene_view.gd::_place` draws part sheets at scale 0.5 with NEAREST filtering
  (`project.godot:45` sets `default_texture_filter=0`), because parts are authored
  at 64 px per tile and the client's `TILE_PX` is 32. Every other authored pixel
  is DISCARDED, not blended, so a mark that is 1 px on the sheet is missing from
  half the places it was drawn. This check downsamples the same way before it
  looks at anything; judging the authoring sheet would pass marks the player
  never receives.

WHAT IT DOES NOT LOOK AT
  The player, the ground, and a machine against ore of ANOTHER species. Machine
  vs ground was settled separately (ASSA-137) and its worst case is not here.

LEVERS -- every one of these MUST make it fail, which is how you know it fires
  FAKE_PART_SHEETS=<dir>   read the four part sheets (and their manifest) from
                           somewhere else. Point it at a checkout of main before
                           ASSA-159 and the worst edge pixel is 1.01 with 83% of
                           the silhouette under the bar: the camouflaged drill
                           itself, as this check's red control. The failing case
                           is a real commit, not a synthetic sheet.
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

# What `scene_view.gd::_place` does to a part sheet. Not a tunable: if the client's
# TILE_PX or the parts' authored tile size ever change, this number changes with
# them or the check stops being about the picture.
DRAW_SCALE = 2

# A pixel is DRAWN if its alpha is over this, the threshold the rest of the art
# tools use. The antialiased fringe outside it is already ink.
OPAQUE = 200

# Maren's ratio has a +5 floor on both sides so that two near-black values cannot
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


def rows_of(sprites, key):
    man = json.load(open(os.path.join(sprites, "manifest.json")))
    spec = man[key]
    return spec, int(spec["frame_px"][1])


def row_pixels(sprites, key, row_name):
    """One named row of one sheet, first frame, as px[y][x] rgba. None if absent."""
    spec, fh = rows_of(sprites, key)
    names = [r["name"] for r in spec["rows"]]
    if row_name not in names:
        return None
    i = names.index(row_name)
    fw = int(spec["frame_px"][0])
    w, h, px = read_rgba(os.path.join(sprites, key + ".png"))
    return [[px[y][x] for x in range(min(fw, w))]
            for y in range(i * fh, min((i + 1) * fh, h))]


def drawn(rows):
    """The sheet as the client receives it: NEAREST at 1/DRAW_SCALE.

    Godot maps a destination pixel's CENTRE back through the sampler, so for a
    halving it reads source texel 2x+1, not 2x -- the odd pixel, not the even one.
    Doing that by hand rather than with a library resize keeps this file stdlib,
    and it is the one line that has to match the engine rather than a convention.
    """
    s = DRAW_SCALE
    h, w = len(rows), len(rows[0])
    return [[rows[min(h - 1, y * s + s - 1)][min(w - 1, x * s + s - 1)]
             for x in range(w // s)] for y in range(h // s)]


def silhouette(d):
    """Drawn pixels with a transparent 4-neighbour. Off-image counts as transparent:
    a part clipped by its frame edge still ends there on screen."""
    h, w = len(d), len(d[0])

    def solid(x, y):
        return 0 <= x < w and 0 <= y < h and d[y][x][3] > OPAQUE

    out = []
    for y in range(h):
        for x in range(w):
            if not solid(x, y):
                continue
            if not all(solid(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out.append((d[y][x][0], d[y][x][1], d[y][x][2]))
    return out


def ore_median(sprites, grade):
    rows = row_pixels(sprites, "ore", "%s_full_v0" % grade)
    if rows is None:
        return None
    vals = [(c[0], c[1], c[2]) for row in rows for c in row if c[3] > OPAQUE]
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
              "            reports 1.01 -- the camouflaged drill itself. MUST fail.\n" % part_src)
    if os.environ.get("FAKE_BAR"):
        bar = float(os.environ["FAKE_BAR"])
        print("\n[RED LEVER] the bar is forced to %.2f in memory; the shipped constant is\n"
              "            %.2f. Above the printed margin this MUST fail.\n" % (bar, RATIO))

    # Ore always comes from the SHIPPED tree even under FAKE_PART_SHEETS: the lever is
    # for replacing the MACHINE, and mixing two commits' ore rows in would measure a
    # difference between checkouts instead of a difference between machine and ore.
    ore = {}
    for g in GRADES:
        med = ore_median(SPRITES, g)
        if med is None:
            print("\n  FAIL: ore has no `%s_full_v0` row, so there is nothing to measure a\n"
                  "  machine against. This check will not pass for lack of an input." % g)
            return 1
        ore[g] = med

    # EVERY grade row of every part, because a grade-A machine standing on grade-C ore
    # is a real world: a part's rows differ in ink and glint, so one of them can fail
    # while the middle one passes.
    edges = {}
    for k in PARTS:
        spec, _ = rows_of(part_src, k)
        for row in spec["rows"]:
            if row.get("light"):
                continue  # emitted light, drawn at Color.WHITE over the body: not material
            rows = row_pixels(part_src, k, row["name"])
            if rows is None:
                print("\n  FAIL: part `%s` has no `%s` row in %s. A missing input is not\n"
                      "  allowed to read as `no disagreement found`."
                      % (k, row["name"], part_src))
                return 1
            e = silhouette(drawn(rows))
            if not e:
                print("\n  FAIL: part `%s` row `%s` draws no silhouette at 1x." % (k, row["name"]))
                return 1
            edges[(k, row["name"])] = e

    print("\nore rows (untinted luminance):  %s"
          % "   ".join("%s %5.1f" % (g, lum(ore[g])) for g in GRADES))
    print("silhouette pixels at 1x:        %s"
          % "   ".join("%s/%s %d" % (k, r, len(e)) for (k, r), e in sorted(edges.items())))
    print("\nWORST edge pixel : 1 against the ore row, and how many of that silhouette's\n"
          "pixels are under the bar. The tint is a multiply and very nearly cancels in a\n"
          "ratio, so the six species read alike; the worst of them is what is printed.\n")

    print("  %-14s | %s" % ("part / row", "   ".join("vs ore %s" % g for g in GRADES)))
    worst = None
    for key in sorted(edges):
        cells = []
        for g in GRADES:
            w_cell, under = None, 0
            for t in TINTS:
                o = tinted_lum(ore[g], t)
                rs = [(max(o, e) + FLOOR) / (min(o, e) + FLOOR)
                      for e in (tinted_lum(c, t) for c in edges[key])]
                w_cell = min(rs) if w_cell is None else min(w_cell, min(rs))
                # The worst species, not their sum: one species where a quarter of the
                # silhouette vanishes is a quarter of the silhouette vanishing.
                under = max(under, sum(1 for r in rs if r < bar))
            cells.append("%5.2f (%3d)" % (w_cell, under))
            if worst is None or w_cell < worst[0]:
                worst = (w_cell, key, g, under)
        print("  %-14s | %s" % ("%s/%s" % key, "   ".join(cells)))

    ok = worst[0] >= bar
    print("\nWORST %.2f : 1   %s/%s against grade-%s ore   (bar %.2f, %d of its %d edge px under)"
          % (worst[0], worst[1][0], worst[1][1], worst[2], bar, worst[3],
             len(edges[worst[1]])))
    print("margin %+.2f -- how far the darkest-reading edge could drift before this goes red."
          % (worst[0] - bar))

    if not ok:
        print("\n  FAIL: a planted machine has silhouette pixels only %.2f : 1 against the ore\n"
              "  of its own species, under the %.2f : 1 bar. A drill stands ON a deposit to\n"
              "  run and wears the same `modulate` colour as it, so this is the first machine\n"
              "  a player builds being camouflaged against the ground it stands on.\n"
              "\n"
              "  THE LEVER IS `rig.PART_RIM_PX` / `rig.PART_RIM_K`, a ring of the alpha mask,\n"
              "  and NOT a darker part: anything that darkens the BODY pays for the separation\n"
              "  with the pixels that name the material, and reaches the bar only where the\n"
              "  six species stop being distinguishable (dE 8.2 against DISTINCT 12).\n"
              "  Widening the Freestyle line is not it either -- it inks creases as well as\n"
              "  the silhouette, and costs frame space `check_part_frame_fit.py` will refuse."
              % (worst[0], bar))

    print("\nVERDICT: %s" % ("GREEN" if ok else "RED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
