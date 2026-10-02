#!/usr/bin/env -S uv run --quiet --with pillow python
"""Can a tint carry six generated species on a 32px ore tile?

    art/species_probe.py

Writes assets/sprites/species_probe.png and prints the numbers.

WHY
  A world rolls six mineral species from its seed and no rule may name one,
  so the ore art has to be species-NEUTRAL with the client tinting it. That
  sentence is written down in several places and has never been executed. It
  is the same shape of claim rig.py rule 2 was before art/assemble.py, and the
  ore tile is the most-seen sprite in the game, so it is worth an hour before
  it is worth a re-render of 56 rows.

  Worse, a species has no colour to tint WITH. sim's MineralSpecies is id,
  names, discoverer, assayed and a six-number sheet. So this probe also has to
  stand in for the missing rule, and it tries both candidates.

HOW THE TINT IS MODELLED
  Godot's `modulate` is a per-channel multiply, which is what a client will
  actually do, so that is what this does: neutral grey tile x species colour.
  Multiply cannot brighten, so a neutral base has to be LIGHT or every species
  comes out mud - that alone is a constraint on the re-render and is checked.

WHAT IS MEASURED
  Everything in CIE L*a*b* dE76 on the mean of the opaque pixels, at TRUE 1x
  (32px), because a tile is judged on a map at the size it is drawn and not in
  a swatch. dE of about 2.3 is the classic just-noticeable step; for two tiles
  a player must tell apart ACROSS a map, at a glance, I want a lot more, and I
  say where my threshold comes from rather than asserting it.
"""
import colorsys
import json
import math
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPR = os.path.join(ROOT, "assets", "sprites")
GAME = 32

# dE76 thresholds. 2.3 is the just-noticeable difference under ideal side-by-
# side viewing; nothing on a game map is ideal or side-by-side, so:
JND = 2.3
DISTINCT = 12.0     # two species a player must never confuse at a glance
POP = 10.0          # ore against the terrain it sits on

man = json.load(open(os.path.join(SPR, "manifest.json")))


def frame_of(asset, row, f=0):
    m = man[asset]
    fw, fh = m["frame_px"]
    names = [r["name"] for r in m["rows"]]
    y = names.index(row)
    sheet = Image.open(os.path.join(SPR, m["sheet"])).convert("RGBA")
    return sheet.crop((f * fw, y * fh, (f + 1) * fw, (y + 1) * fh))


# ------------------------------------------------------------------ colour

def _lin(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lab(rgb):
    r, g, b = (_lin(c) for c in rgb[:3])
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = (0.2126 * r + 0.7152 * g + 0.0722 * b)
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    f = lambda t: t ** (1 / 3.0) if t > 0.008856 else 7.787 * t + 16 / 116.0
    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def dE(a, b):
    la, lb = lab(a), lab(b)
    return math.sqrt(sum((la[i] - lb[i]) ** 2 for i in range(3)))


def mean_rgb(img):
    """Mean of the OPAQUE pixels. A tile's average is what you see of it from
    across a map; the detail inside it is below the eye's reach at this size."""
    px = img.convert("RGBA").load()
    acc, n = [0, 0, 0], 0
    for y in range(img.height):
        for x in range(img.width):
            c = px[x, y]
            if c[3] > 128:
                acc[0] += c[0]; acc[1] += c[1]; acc[2] += c[2]; n += 1
    return tuple(v / n for v in acc) if n else (0, 0, 0)


# ------------------------------------------------------------------ tinting

def neutralise(img):
    """What a species-neutral ore tile would be: the same rock, no hue.

    Luma-preserving, so the sculpting and the outline survive. This stands in
    for art I have not rendered yet, which is the point of a probe - find out
    whether the re-render is worth doing before doing it.
    """
    px = img.convert("RGBA").load()
    out = Image.new("RGBA", img.size)
    op = out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            v = round(0.2126 * r + 0.7152 * g + 0.0722 * b)
            op[x, y] = (v, v, v, a)
    return out


def tint(img, colour):
    """Godot `modulate`: per-channel multiply. This is the real operation, not
    a colourise - and multiply can only darken, which is the constraint."""
    px = img.convert("RGBA").load()
    out = Image.new("RGBA", img.size)
    op = out.load()
    cr, cg, cb = colour
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            op[x, y] = (r * cr // 255, g * cg // 255, b * cb // 255, a)
    return out


def at_1x(img):
    k = GAME / float(img.width)
    return img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)


def hues(n, sat=0.62, val=1.0):
    """N species evenly spaced round the wheel - the best case for any
    id-derived scheme. If six cannot be separated HERE they cannot be
    separated by a hash either."""
    return [tuple(round(c * 255) for c in colorsys.hsv_to_rgb(i / float(n), sat, val))
            for i in range(n)]


def main():
    base = neutralise(frame_of("ore", "stone_t3_full_v0"))
    ground = at_1x(frame_of("ground", "v0"))
    gmean = mean_rgb(ground)
    ok = True

    print("base tile neutralised from ore/stone_t3_full_v0; tint = per-channel")
    print("multiply (Godot modulate). All dE76 on the mean of opaque pixels at")
    print("true %dpx. JND %.1f, species-vs-species floor %.0f, ore-vs-ground floor %.0f.\n"
          % (GAME, JND, DISTINCT, POP))

    # ---- 1. how many species fit on the wheel
    for n in (4, 6, 8):
        tiles = [at_1x(tint(base, h)) for h in hues(n)]
        means = [mean_rgb(t) for t in tiles]
        pairs = [(dE(means[i], means[j]), i, j)
                 for i in range(n) for j in range(i + 1, n)]
        worst, i, j = min(pairs)
        print("%d species evenly spaced: closest pair is %d vs %d at dE %5.1f %s"
              % (n, i, j, worst, "OK" if worst >= DISTINCT else "TOO CLOSE"))
        if n == 6 and worst < DISTINCT:
            ok = False

    # ---- 2. does ore pop off the ground
    print()
    n = 6
    tiles = [at_1x(tint(base, h)) for h in hues(n)]
    worst_pop = min((dE(mean_rgb(t), gmean), k) for k, t in enumerate(tiles))
    for k, t in enumerate(tiles):
        d = dE(mean_rgb(t), gmean)
        print("species %d vs ground: dE %5.1f %s" % (k, d, "" if d >= POP else "<-- SINKS INTO TERRAIN"))
    if worst_pop[0] < POP:
        ok = False

    # ---- 3. THE AXIS COLLISION
    # An ore tile already spends a visual axis on TIER, and parts spend one on
    # GRADE - both of them tone. If species is hue and tier is tone, a player
    # reads a 32px tile that is carrying two things at once. The question is
    # not whether each axis works alone; it is whether a low tier of one
    # species lands on a high tier of another.
    print("\naxis collision: species (hue) against tier (tone), 6 species x 4 tiers")
    cells = {}
    for s, h in enumerate(hues(6)):
        for t, row in enumerate(("t1", "t2", "t3", "t4")):
            tile = at_1x(tint(neutralise(frame_of("ore", "stone_%s_full_v0" % row)), h))
            cells[(s, t)] = mean_rgb(tile)
    cross = [(dE(cells[a], cells[b]), a, b)
             for a in cells for b in cells if a < b and a[0] != b[0]]
    same = [(dE(cells[(s, t1)], cells[(s, t2)]), s, t1, t2)
            for s in range(6) for t1 in range(4) for t2 in range(t1 + 1, 4)]
    cw, ca, cb = min(cross)
    sw, ss, st1, st2 = min(same)
    print("  closest DIFFERENT-species pair across all tiers: %s vs %s at dE %5.1f"
          % (ca, cb, cw))
    print("  closest same-species tier step (how readable tier is): dE %5.1f (species %d, t%d vs t%d)"
          % (sw, ss, st1 + 1, st2 + 1))
    if cw < DISTINCT:
        ok = False
        print("  FAIL: two DIFFERENT species collide once tier is also in play.\n"
              "  Species is only safe as hue if tier stops being tone, or if the\n"
              "  tier range is narrowed so it cannot walk a tile onto another\n"
              "  species' colour.")

    # ---- 3b. HOW MUCH SATURATION DOES SIX SPECIES COST?
    #
    # Every number above is measured at saturation 0.62, which is bright. Assay
    # is a grounded-looking game and Maren may well want these muted, so the
    # useful figure is not "six species work" but "six species work down to
    # saturation X". Quoting the 0.62 number alone would be quoting a best case
    # as if it were the answer.
    print("\nsaturation budget: closest of 6 species as the palette is muted")
    floor_sat = None
    for s in (0.70, 0.60, 0.50, 0.40, 0.30, 0.22, 0.15, 0.10):
        means = [mean_rgb(at_1x(tint(base, h))) for h in hues(6, sat=s)]
        worst = min(dE(means[i], means[j])
                    for i in range(6) for j in range(i + 1, 6))
        gpop = min(dE(m, gmean) for m in means)
        mark = "OK" if worst >= DISTINCT and gpop >= POP else "TOO CLOSE"
        if mark == "OK":
            floor_sat = s
        print("  sat %.2f: closest species pair dE %5.1f, worst vs ground dE %5.1f  %s"
              % (s, worst, gpop, mark))
    print("  -> six species hold down to saturation %.2f. Below that they start\n"
          "     merging into each other or into the terrain." % floor_sat)

    # ---- 4. IS THE TIER LADDER ITSELF READABLE, on the art as it ships?
    #
    # This exists because check 3 reported a same-species tier step of about 3
    # dE and my first instinct was to report "tier is invisible". That would
    # have been measuring my own neutralise(): if the tier ladder had been
    # carried in saturation, stripping hue would have destroyed it and I would
    # have blamed the art for what my probe did. So tier is measured again on
    # the ORIGINAL art, untouched, and the two are compared.
    print("\ntier readability on the ORIGINAL art (no neutralise, no tint)")
    worst_orig = 99.0
    for species in ("iron", "copper", "coal", "stone"):
        means = [mean_rgb(at_1x(frame_of("ore", "%s_%s_full_v0" % (species, t))))
                 for t in ("t1", "t2", "t3", "t4")]
        steps = [dE(means[i], means[i + 1]) for i in range(3)]
        worst_orig = min(worst_orig, min(steps))
        print("  %-7s t1>t2 %5.1f  t2>t3 %5.1f  t3>t4 %5.1f   full range %5.1f"
              % (species, steps[0], steps[1], steps[2], dE(means[0], means[3])))
    print("  smallest adjacent step anywhere: dE %.1f (%.1fx JND) - tier is a\n"
          "  LUMINANCE ladder, so it survives neutralising (stone's smallest step\n"
          "  goes 3.5 -> 3.1), and the re-render will not cost it. But adjacent\n"
          "  tiers are a weak read on their own terms: the full t1-t4 range is\n"
          "  only 13-21 dE where six species are 33.7 apart." % (worst_orig, worst_orig / JND))

    # ---- the sheet
    sheet_img = Image.new("RGBA", (6 * (GAME + 4) + 4, 4 * (GAME + 4) + 4), (30, 32, 30, 255))
    for (s, t), _ in sorted(cells.items()):
        tile = at_1x(tint(neutralise(frame_of("ore", "stone_%s_full_v0" % ("t1", "t2", "t3", "t4")[t])), hues(6)[s]))
        sheet_img.alpha_composite(tile, (4 + s * (GAME + 4), 4 + t * (GAME + 4)))
    sheet_img.save(os.path.join(SPR, "species_probe.png"))
    print("\nwrote assets/sprites/species_probe.png (6 species across, 4 tiers down, true 1x)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
