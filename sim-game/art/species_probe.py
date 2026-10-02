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
SPECIES = 6        # sim/src/tuning.rs SPECIES_PER_WORLD

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


def over_ground(img, observer="normal", space="linear"):
    """The ore layer composited onto the ground tile, which is what the screen
    actually shows. Ore tiles are rock-only with alpha, so two different
    questions need two different measurements and conflating them hid a bug:
    the SPECIES read is the mean of the opaque rock pixels (what the tint
    lands on), and the POP and TIER reads are of the whole composited tile
    (where coverage counts, because sparse ore is mostly terrain).

    I got this wrong in both directions before getting it right. Measuring
    species on the composite drags every species toward the same green, so
    even the designed table "failed" for normal vision; measuring pop on the
    rocks alone scores coverage as free, so a tile that is nine tenths grass
    "pops". Neither is a fact about the art. The eye segments the rock
    cluster from the terrain, so species is a rock question and coverage is a
    tile question, and the probe now asks each of them where it lives."""
    g = at_1x(frame_of("ground", "v0")).convert("RGBA").copy()
    g.alpha_composite(img if img.size == g.size else at_1x(img))
    return as_seen(g, observer, space) if observer != "normal" else g


def at_1x(img):
    k = GAME / float(img.width)
    return img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)


def hues(n, sat=0.62, val=1.0, span=1.0):
    """N species evenly spaced round the wheel - the best case for any
    id-derived scheme. If six cannot be separated HERE they cannot be
    separated by a hash either.

    `span` is how much of the wheel they are spread over, and exists only so
    the checks below can be run RED: span=0.1 crowds all six into 36 degrees,
    which MUST fail. A check I have not seen fail is not a check.
    """
    return [tuple(round(c * 255) for c in colorsys.hsv_to_rgb(i * span / float(n), sat, val))
            for i in range(n)]


# Machado et al. 2009, full severity - the same three matrices build.py already
# uses for the ore contact sheet. Applied per pixel here rather than through
# PIL's convert() so alpha survives and the function works on any asset.
CVD = {
    "protan": (0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998),
    "deutan": (0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.011820, 0.042940, 0.968881),
    "tritan": (1.255528, -0.076749, -0.178779, -0.078411, 0.930809, 0.147602, 0.004733, 0.691367, 0.303900),
}


OBSERVERS = ("normal", "protan", "deutan", "tritan")

# How much of the hue wheel the even-spacing scheme gets, and how crowded the
# designed table is. Both are 1.0 in a real run; PROBE_SPAN<1 crowds BOTH so
# checks 5 and 6 can be seen to fail. A check I have not seen fail is not a
# check - ASSA-16 passed on the exact defect it existed to find.
SPAN = float(os.environ.get("PROBE_SPAN", "1.0"))

# Okabe & Ito (2008), the standard qualitative palette for protan/deutan
# viewers. Black and the dark blue (#0072B2) of the eight are dropped: Godot's
# modulate is a multiply and cannot brighten, so a dark tint on a light base is
# mud. Six left, which is exactly SPECIES_PER_WORLD.
SLOTS = ["#E69F00", "#56B4E9", "#009E73", "#F0E442", "#D55E00", "#CC79A7"]

# How far a slot is pulled toward its own grey. 1.0 = the colour as published,
# 0.0 = grey. This is the saturation budget in the form art direction needs it.
MUTES = (1.0, 0.8, 0.6, 0.5, 0.4, 0.3)


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def lift(rgb, k):
    """Blend a tint toward white. Exists because `modulate` only DARKENS: a
    mid-luminance tint spends the light base's whole lightness budget, and
    what it buys is a tile that no longer stands off the terrain. Lifting
    costs a little chroma and buys back luminance."""
    c = lambda x: max(0, min(255, int(round(x + (255 - x) * k))))
    return (c(rgb[0]), c(rgb[1]), c(rgb[2]))


def mute(rgb, keep):
    """Pull a colour toward its own luma grey. keep=1 is the colour itself."""
    v = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
    c = lambda x: max(0, min(255, int(round(v + (x - v) * keep))))
    return (c(rgb[0]), c(rgb[1]), c(rgb[2]))


def slots():
    """The designed table, or a deliberately crowded stand-in for the RED run."""
    if SPAN == 1.0:
        return [hex_rgb(h) for h in SLOTS]
    return hues(len(SLOTS), sat=0.62, span=SPAN)


def _unlin(c):
    """linear 0..1 -> sRGB 0..255."""
    c = 0.0 if c < 0 else (1.0 if c > 1 else c)
    s = 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055
    return int(round(s * 255))


def as_seen(img, observer, space="linear"):
    """The tile as a protan / deutan / tritan viewer sees it. 'normal' returns
    it untouched.

    APPLIED IN LINEAR RGB, which is what Machado et al. define the matrices
    for. build.py applies the same three matrices straight to sRGB and says
    so in its docstring - that is fine for a review sheet, where the job is
    "does this look collapsed", and not fine here, where the number decides
    whether I tell the director a scheme is unusable. `space="srgb"` runs it
    the review-sheet way so the two can be compared rather than assumed
    equivalent.
    """
    if observer == "normal":
        return img
    m = CVD[observer]
    px = img.convert("RGBA").load()
    out = Image.new("RGBA", img.size)
    op = out.load()
    srgb = space == "srgb"
    clamp = lambda v: 0 if v < 0 else (255 if v > 255 else int(round(v)))
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if srgb:
                op[x, y] = (clamp(m[0] * r + m[1] * g + m[2] * b),
                            clamp(m[3] * r + m[4] * g + m[5] * b),
                            clamp(m[6] * r + m[7] * g + m[8] * b), a)
            else:
                lr, lg, lb = _lin(r), _lin(g), _lin(b)
                op[x, y] = (_unlin(m[0] * lr + m[1] * lg + m[2] * lb),
                            _unlin(m[3] * lr + m[4] * lg + m[5] * lb),
                            _unlin(m[6] * lr + m[7] * lg + m[8] * lb), a)
    return out


def main():
    # THE REAL ART NOW. This used to be neutralise(ore/stone_t3_full_v0) - a
    # stand-in for art that did not exist, which is what a probe is for. The
    # species-neutral tiles are rendered, so the stand-in would now be
    # measuring my own filter instead of the thing that ships. neutralise()
    # is kept for the one comparison below that still needs it.
    base = frame_of("ore", "t3_full_v0")
    ground = at_1x(frame_of("ground", "v0"))
    gmean = mean_rgb(ground)
    ok = True

    # Is the base actually neutral and actually light? Both are load-bearing
    # for a multiply tint and both were ASSERTED in rig.py before they were
    # ever checked here.
    bm = mean_rgb(at_1x(base))
    bl = lab(bm)
    chroma = math.sqrt(bl[1] ** 2 + bl[2] ** 2)
    print("base ore/t3_full_v0: mean rgb (%.0f, %.0f, %.0f), L* %.1f, chroma %.1f"
          % (bm[0], bm[1], bm[2], bl[0], chroma))
    if bl[0] < 55:
        ok = False
        print("  FAIL: too dark for a multiply tint - every species comes out mud.")
    # THRESHOLD SET FROM THE DEFECT, NOT FROM TASTE. The version of this
    # tile with the ground baked into it measured chroma 15.4 - and my first
    # threshold here was 18, so the guard passed the exact thing it exists to
    # catch. The fixed tile measures 0.5. Six sits clear of both.
    if chroma > 6:
        ok = False
        print("  FAIL: the base has a hue of its own, which is added to all six")
        print("  species. Baked-in ground measured 15.4 here; rock-only is 0.5.")

    print("\ntint = per-channel")
    print("multiply (Godot modulate). All dE76 on the mean of opaque pixels at")
    print("true %dpx. JND %.1f, species-vs-species floor %.0f, ore-vs-ground floor %.0f.\n"
          % (GAME, JND, DISTINCT, POP))

    # ---- 1. how many species fit on the wheel
    for n in (4, 6, 8):
        means = [mean_rgb(at_1x(tint(base, h))) for h in hues(n)]
        pairs = [(dE(means[i], means[j]), i, j)
                 for i in range(n) for j in range(i + 1, n)]
        worst, i, j = min(pairs)
        print("%d species evenly spaced: closest pair is %d vs %d at dE %5.1f %s"
              % (n, i, j, worst, "OK" if worst >= DISTINCT else "TOO CLOSE"))
        if n == 6 and worst < DISTINCT:
            ok = False

    # ---- 2. does ore pop off the ground
    #
    # Measured ON THE COMPOSITE, not on the rock pixels. Ore is a transparent
    # overlay, so a sparse tile is mostly terrain and a patch of it reads as
    # terrain however vivid its few rocks are. Measuring the rocks alone would
    # score coverage as if it were free.
    print()
    n = 6
    pops = [dE(mean_rgb(over_ground(tint(base, h))), gmean) for h in hues(n)]
    for k, d in enumerate(pops):
        print("species %d vs ground: dE %5.1f %s" % (k, d, "" if d >= POP else "<-- SINKS INTO TERRAIN"))
    if min(pops) < POP:
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
            tile = over_ground(tint(frame_of("ore", "%s_full_v0" % row), h))
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
        # NOT a probe failure: this is measured on EVEN HUE spacing, which
        # check 5 rejects and check 7 replaces. Left in because it is the
        # step that shows why two axes on one 32px tile is the real question.
        print("  two DIFFERENT species collide once tier is also in play.\n"
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
        rockm = [mean_rgb(at_1x(tint(base, h))) for h in hues(6, sat=s)]
        compm = [mean_rgb(over_ground(tint(base, h))) for h in hues(6, sat=s)]
        worst = min(dE(rockm[i], rockm[j])
                    for i in range(6) for j in range(i + 1, 6))
        gpop = min(dE(m, gmean) for m in compm)
        mark = "OK" if worst >= DISTINCT and gpop >= POP else "TOO CLOSE"
        if mark == "OK":
            floor_sat = s
        print("  sat %.2f: closest species pair dE %5.1f, worst vs ground dE %5.1f  %s"
              % (s, worst, gpop, mark))
    print("  -> six species hold down to saturation %.2f. Below that they start\n"
          "     merging into each other or into the terrain." % floor_sat)

    # ---- 4. IS THE TIER LADDER ITSELF READABLE, on the art as it ships?
    #
    # Tier is the one axis the ART still carries, because the client has spent
    # colour on species, so this is the check that guards the re-render. The
    # old art scored a smallest adjacent step of 3.5 dE (1.5x JND) because it
    # moved only one rock shade in three with tier; ore.py moves all of them
    # and adds coverage. REGRESSION GUARD: it must not go back.
    #
    # Measured untinted, which is also why this check exists at all: check 3
    # once reported a ~3 dE tier step and my first instinct was "tier is
    # invisible", when the number came out of my own neutralise(). If tier had
    # lived in saturation, stripping hue would have destroyed it and I would
    # have blamed the art for what my probe did.
    # TWO NUMBERS, AND THE GAP BETWEEN THEM IS REPORTED RATHER THAN HIDDEN.
    # TIER_STEP is the regression guard: the re-render must keep beating the
    # art it replaced. TIER_TARGET is what I actually wanted and did not get.
    #
    # I made two bounded attempts at the target and both came out WORSE than
    # the config here (3.8 and 4.1 against 5.3), which is the finding. The low
    # end is structurally compressed: ore is a transparent overlay, so a t1
    # tile is mostly terrain, and the mean of two sparse tiles is dominated by
    # the ground they share. Darkening t1 to separate it made it worse,
    # because it walked t1 toward the dark olive instead of away from it.
    # Tier reads well where it matters (t1-t4 spans 23.6) and weakly step to
    # step at the bottom. Raising it further means changing what tier IS -
    # arrangement or a mark, not value and coverage - and that is a design
    # call, not a parameter I should keep nudging.
    OLD_TIER_STEP = 3.5   # the art this replaced
    TIER_STEP = 5.0       # enforced: must stay well clear of what it replaced
    TIER_TARGET = 6.0     # wanted, not reached; see above
    print("\ntier readability on the art as it ships (no tint)")
    means = [mean_rgb(over_ground(frame_of("ore", "t%d_full_v0" % t))) for t in (1, 2, 3, 4)]
    steps = [dE(means[i], means[i + 1]) for i in range(3)]
    worst_orig = min(steps)
    print("  t1>t2 %5.1f  t2>t3 %5.1f  t3>t4 %5.1f   full t1-t4 range %5.1f"
          % (steps[0], steps[1], steps[2], dE(means[0], means[3])))
    print("  smallest adjacent step dE %.1f (%.1fx JND), against %.1f for the art\n"
          "  this replaced (+%.0f%%). Guard %.1f: %s. Target %.1f: %s."
          % (worst_orig, worst_orig / JND, OLD_TIER_STEP,
             100 * (worst_orig - OLD_TIER_STEP) / OLD_TIER_STEP,
             TIER_STEP, "OK" if worst_orig >= TIER_STEP else "FAIL, tier regressed",
             TIER_TARGET, "met" if worst_orig >= TIER_TARGET else "NOT met, reported above"))
    if worst_orig < TIER_STEP:
        ok = False

    # ---- 5. THE OBSERVER. Does tint-ONLY species survive colour blindness?
    #
    # Every number above is for a normal observer, and that is not the whole
    # question, because of what the re-render DELETES. The art being replaced
    # was colourblind-safe by SHAPE as well as colour - ore.py's docstring
    # says so in those words and build.py renders a protan/deutan/tritan
    # contact block to back it up. Six species rolled from a seed cannot each
    # have their own mesh, so species becomes hue and hue only, and six hues
    # 60 degrees apart are not 60 degrees apart for a deutan viewer. If they
    # do not hold here then "the client tints" is an incomplete answer and the
    # re-render owes the tile a second redundant axis.
    #
    # Swept across saturation rather than measured once, because the useful
    # output for art direction is not "it works" but "it works down to sat X
    # for the WORST observer" - and 3b's 0.22 was a normal-vision figure.
    if SPAN != 1.0:
        print("\n[RED RUN] six colours crowded into %.0f degrees; checks 5 and 6 MUST fail"
              % (SPAN * 360))
    print("\nTHE OBSERVER: six species as protan / deutan / tritan see them")
    sats = (0.70, 0.62, 0.50, 0.40, 0.30, 0.22, 0.15, 0.10)
    floors, fails = {}, []
    for observer in OBSERVERS:
        gm = mean_rgb(as_seen(ground, observer))
        floor, at62, by_sat = None, None, []
        for s in sats:
            hs = hues(6, sat=s, span=SPAN)
            rockm = [mean_rgb(as_seen(at_1x(tint(base, h)), observer)) for h in hs]
            compm = [mean_rgb(over_ground(tint(base, h), observer)) for h in hs]
            worst = min(dE(rockm[i], rockm[j])
                        for i in range(6) for j in range(i + 1, 6))
            gpop = min(dE(m, gm) for m in compm)
            if worst >= DISTINCT and gpop >= POP:
                floor = s
            if s == 0.62:
                at62 = (worst, gpop)
            by_sat.append("%.2f:%.0f" % (s, worst))
        floors[observer] = floor
        print("  %-7s sat 0.62: closest pair dE %5.1f, worst vs ground dE %5.1f  %s"
              % (observer, at62[0], at62[1],
                 "OK" if at62[0] >= DISTINCT and at62[1] >= POP else "FAIL"))
        print("          closest pair by saturation  %s   holds to sat %s"
              % ("  ".join(by_sat), ("%.2f" % floor) if floor else "NONE"))
        if at62[0] < DISTINCT or at62[1] < POP:
            fails.append(observer)
    # Deliberately NOT a probe failure. That even hue spacing breaks for a
    # protan viewer is a FINDING about my scheme, and check 6 tests the fix.
    # Setting ok=False here would have hidden which of the two is broken.
    if fails:
        print("  -> EVEN HUE SPACING FAILS FOR: %s. ASSA-18's 33.7 dE was a\n"
              "     normal-vision figure and I reported it without that word."
              % ", ".join(fails))
    else:
        print("  -> even hue spacing survives every observer; worst holds to sat %.2f"
              % max(floors[o] for o in OBSERVERS if floors[o]))

    # ---- 6. THE FIX: A DESIGNED SLOT TABLE, NOT A HUE FORMULA.
    #
    # Check 5 says evenly-spaced hue fails, so the obvious question is whether
    # that is a fact about tinting or a fact about MY SCHEME. Even spacing on
    # the hue wheel is the naive answer: it optimises for a normal observer and
    # protan/deutan confusion runs along a specific axis, so even spacing walks
    # species straight onto each other. Picking six colours that are separable
    # for those observers instead is a solved problem, and Okabe & Ito (2008)
    # is the standard solution.
    #
    # This stays option A of Decision #35 - colour is still a function of the
    # species INDEX. It only changes index -> hue formula into index -> slot in
    # a table, which is also exactly what sim-cli/src/tui.rs already does
    # (SPECIES_COLORS, "one (live, depleted) colour pair per species index").
    #
    # Black and the dark blue of the eight are dropped: modulate is a multiply
    # and cannot brighten, so a dark tint on a light base is mud.
    print("\nTHE FIX: six DESIGNED slots (Okabe-Ito) instead of even hue spacing")
    print("  each cell: closest species PAIR / worst vs GROUND, floors %.0f and %.0f."
          % (DISTINCT, POP))
    print("  %-8s" % "observer" + "".join("  keep %.1f " % k for k in MUTES))
    table = slots()
    slot_floor = {}
    for observer in OBSERVERS:
        gm = mean_rgb(as_seen(ground, observer))
        cells_ok, keep_floor = [], None
        for k in MUTES:
            rockm = [mean_rgb(as_seen(at_1x(tint(base, mute(c, k))), observer))
                     for c in table]
            compm = [mean_rgb(over_ground(tint(base, mute(c, k)), observer))
                     for c in table]
            worst = min(dE(rockm[i], rockm[j])
                        for i in range(len(table)) for j in range(i + 1, len(table)))
            gpop = min(dE(m, gm) for m in compm)
            if worst >= DISTINCT and gpop >= POP:
                keep_floor = k
            # Mark WHICH floor bit. The first version of this printed one "!"
            # for either, and a cell reading 16.6! looked like a species
            # collision when it was the terrain.
            cells_ok.append(" %4.1f%s/%4.1f%s"
                            % (worst, " " if worst >= DISTINCT else "p",
                               gpop, " " if gpop >= POP else "g"))
        slot_floor[observer] = keep_floor
        print("  %-8s%s  holds to keep %s"
              % (observer, "".join(cells_ok),
                 ("%.1f" % keep_floor) if keep_floor else "NONE"))
    print("  (p = species pair below %.0f, g = ore sinks into terrain below %.0f)"
          % (DISTINCT, POP))
    # Is the verdict an artefact of HOW the matrices are applied? The review
    # sheet applies them to sRGB, this probe to linear RGB. If those two
    # disagree about pass/fail then the measure is not solid enough to carry a
    # "this scheme is unusable" to the director, so both get printed.
    srgb_line = []
    for observer in OBSERVERS[1:]:
        gm = mean_rgb(as_seen(ground, observer, space="srgb"))
        means = [mean_rgb(as_seen(at_1x(tint(base, c)), observer, space="srgb"))
                 for c in table]
        worst = min(dE(means[i], means[j])
                    for i in range(len(table)) for j in range(i + 1, len(table)))
        srgb_line.append("%s %4.1f" % (observer, worst))
    print("  cross-check, keep 1.0 with the matrices applied to sRGB instead of")
    print("  linear: %s  (linear is the one above)" % ", ".join(srgb_line))

    # ---- 6b. LIFTING THE TABLE, because the two floors fail for different
    # reasons. At keep 1.0 the designed slots clear the SPECIES floor for
    # every observer; what fails is ore-vs-TERRAIN, and only for colourblind
    # ones. That is a luminance problem, not a hue one: modulate darkens, the
    # published Okabe-Ito values are mid-luminance, and a tinted rock ends up
    # nearer the olive ground than the untinted one was. So lift the table
    # toward white and find the smallest lift that passes BOTH floors for ALL
    # four observers. One sweep, one answer, no re-render.
    print("\n  lifting the table toward white (fixes vs-ground, costs chroma):")
    best = None
    for L in (0.0, 0.10, 0.20, 0.30, 0.40, 0.50):
        lit = [lift(c, L) for c in table]
        row, worst_pair, worst_pop = [], 99.0, 99.0
        for observer in OBSERVERS:
            gm = mean_rgb(as_seen(ground, observer))
            rockm = [mean_rgb(as_seen(at_1x(tint(base, c)), observer)) for c in lit]
            compm = [mean_rgb(over_ground(tint(base, c), observer)) for c in lit]
            pair = min(dE(rockm[i], rockm[j])
                       for i in range(len(lit)) for j in range(i + 1, len(lit)))
            pop = min(dE(m, gm) for m in compm)
            worst_pair, worst_pop = min(worst_pair, pair), min(worst_pop, pop)
            row.append("%s %4.1f/%4.1f" % (observer[:4], pair, pop))
        good = worst_pair >= DISTINCT and worst_pop >= POP
        if good and best is None:
            best = L
        print("    lift %.2f  %s  %s" % (L, "  ".join(row), "OK" if good else ""))
    if best is None:
        print("    -> no lift passes both floors for all four observers, and the\n"
              "       per-species numbers say why: it is a hue collision with the\n"
              "       terrain, not a luminance problem. Check 7 acts on that.")
    else:
        print("    -> SMALLEST LIFT THAT PASSES EVERYTHING: %.2f. The table the\n"
              "       client should use (species index -> slot):" % best)
        print("       %s" % " ".join("#%02X%02X%02X" % lift(c, best) for c in table))
    if all(slot_floor[o] is not None for o in OBSERVERS):
        print("  -> SIX DESIGNED SLOTS SURVIVE ALL FOUR OBSERVERS, down to keep %.1f.\n"
              "     Species stays a function of index (Decision #35 option A); the index\n"
              "     picks a SLOT, not a hue. The re-render is unblocked."
              % max(slot_floor[o] for o in OBSERVERS))
    else:
        # Again not a probe failure. A BORROWED table is the second thing I
        # tried; check 7 derives one instead. The verdict lives there.
        print("  -> the borrowed table does not clear both floors either. It is close\n"
              "     on species and fails on terrain, which check 7 explains.")

    # ---- 7. DERIVE THE TABLE AGAINST OUR OWN TERRAIN.
    #
    # The lift sweep failed and the per-species numbers said why: slot 2 is
    # Okabe-Ito's bluish green #009E73, and to a protan viewer a green ore on
    # the olive ground tile is dE 5.8. No amount of lifting fixes that,
    # because it is a HUE collision with the terrain and lifting only moves
    # luminance. I was fixing the wrong axis for a whole sweep.
    #
    # Okabe-Ito is a palette for categories separable FROM EACH OTHER on a
    # white page. Ours carries a second constraint it was never designed for -
    # every colour also has to stay off one particular olive - so borrowing it
    # was always going to be approximate. Derive the table instead: sweep a
    # grid of candidate tints, throw away everything that sinks into the
    # terrain for ANY observer, then greedily pick the six that are furthest
    # apart FOR THE OBSERVER WHO SEES THEM MOST ALIKE. Optimising the normal
    # number is what produced the even-hue scheme that fails at protan 5.7.
    gmeans = {o: mean_rgb(as_seen(ground, o)) for o in OBSERVERS}

    def derive(label, sats):
        cands = []
        # SPAN is the RED lever: at 1.0 these are 24 hues round the wheel, and
        # below it they crowd into a slice too narrow to hold six species, so
        # the probe's verdict - not just its narration - can be seen to fail.
        for hdeg in [i * 360.0 * SPAN / 24 for i in range(24)]:
            for sat in sats:
                for val in (0.80, 0.90, 1.00):
                    c = tuple(round(x * 255) for x in colorsys.hsv_to_rgb(hdeg / 360.0, sat, val))
                    layer = tint(base, c)
                    rock = {o: lab(mean_rgb(as_seen(at_1x(layer), o))) for o in OBSERVERS}
                    pop = min(dE(mean_rgb(over_ground(layer, o)), gmeans[o]) for o in OBSERVERS)
                    if pop >= POP:
                        cands.append((c, rock, pop))
        total = 24 * len(sats) * 3
        print("\n  --- %s ---" % label)
        print("  %d candidate tints, %d clear the terrain for every observer"
              % (total, len(cands)))
        if len(cands) < SPECIES:
            print("  -> not enough survive; the terrain itself is the problem.")
            return False
        n = len(cands)
        D = [[0.0] * n for _ in range(n)]
        for i in range(n):
            for j in range(i + 1, n):
                # (a*, b*) ONLY - hue and chroma, not lightness. Scoring the
                # full dE76 is what produced the muted table: it reached 16.3
                # for the worst observer while its hue separation was 3.7, so
                # the six "distinct" species were one family at six
                # brightnesses, exactly as the contact sheet showed. Lightness
                # is already spoken for by TIER anyway, so spending it on
                # species would collide with the axis the art still carries.
                d = min(math.sqrt(sum((cands[i][1][o][t] - cands[j][1][o][t]) ** 2
                                      for t in (1, 2)))
                        for o in OBSERVERS)
                D[i][j] = D[j][i] = d
        best_set, best_score = None, -1.0
        for seed_i in range(n):  # farthest-point greedy from every seed
            chosen = [seed_i]
            while len(chosen) < SPECIES:
                nxt, nd = -1, -1.0
                for k in range(n):
                    if k in chosen:
                        continue
                    d = min(D[k][p] for p in chosen)
                    if d > nd:
                        nxt, nd = k, d
                chosen.append(nxt)
            score = min(D[chosen[i]][chosen[j]]
                        for i in range(SPECIES) for j in range(i + 1, SPECIES))
            if score > best_score:
                best_score, best_set = score, chosen
        pops = min(cands[i][2] for i in best_set)
        # TWO NUMBERS PER OBSERVER, because the contact sheet disagreed with
        # the first one. dE76 includes L*, so a table can score well while the
        # six species read as ONE HUE AT SIX BRIGHTNESSES - which is what the
        # protan and deutan strips of contact.png actually look like. The
        # second number drops L* and measures (a*, b*) only: separation a
        # player could use to say "that is a different mineral" rather than
        # "that is the same mineral in shadow".
        for o in OBSERVERS:
            pairs = [(i, j) for i in range(SPECIES) for j in range(i + 1, SPECIES)]
            w = min(math.sqrt(sum((cands[best_set[i]][1][o][t] - cands[best_set[j]][1][o][t]) ** 2
                                  for t in range(3))) for i, j in pairs)
            wc = min(math.sqrt(sum((cands[best_set[i]][1][o][t] - cands[best_set[j]][1][o][t]) ** 2
                                   for t in (1, 2))) for i, j in pairs)
            print("    %-7s closest pair dE %5.1f   of which hue/chroma only %5.1f %s"
                  % (o, w, wc, "" if wc >= DISTINCT else "<-- mostly LIGHTNESS"))
        good = best_score >= DISTINCT and pops >= POP
        print("  worst observer: closest pair HUE/CHROMA dE %.1f (floor %.0f), worst"
              " vs terrain dE %.1f (floor %.0f)  %s"
              % (best_score, DISTINCT, pops, POP, "OK" if good else "FAIL"))
        print("  TABLE (species index -> tint, Godot modulate):")
        print("    %s" % " ".join("#%02X%02X%02X" % cands[i][0] for i in best_set))
        return good

    # Run twice. The free search maximises separation and lands on near
    # primaries, which is the right answer to the question asked and probably
    # the wrong palette for a game that wants to look like dirt. The muted run
    # asks the same question with saturation capped, so the director chooses
    # with both numbers in front of them instead of being handed the
    # optimiser's taste as if it were a finding.
    print("\nDERIVING A TABLE for this terrain, all four observers at once")
    free_ok = derive("free", (0.35, 0.50, 0.65, 0.80))
    muted_ok = derive("muted, saturation capped at 0.50", (0.25, 0.35, 0.50))
    if not free_ok:
        print("\n  -> even the best six fall short; species needs a non-colour axis.")
        ok = False
    elif not muted_ok:
        print("\n  -> six species work, but NOT at a muted saturation. The palette")
        print("     has to be brighter than the rest of the game, or species needs")
        print("     the non-colour axis Decision #36 option A adds.")

    # ---- the sheet
    #
    # Three blocks, because the numbers above are not the whole check: I look
    # at the picture too. That is how I caught ASSA-16's check passing on the
    # exact defect it existed to find.
    #   block 1  6 species across, 4 tiers down - the axis-collision grid
    #   block 2  EVEN HUE spacing, the same six, through each observer
    #   block 3  the DESIGNED SLOTS, the same six, through each observer
    # Block 3 should stay six readable colours all the way down. Block 2 is
    # where protan and deutan collapse, and seeing those two rows side by side
    # is the argument.
    cell, gap, bar = GAME, 4, 10
    w = 6 * (cell + gap) + gap
    rows = 4 + len(OBSERVERS) * 2
    sheet_img = Image.new("RGBA", (w, rows * (cell + gap) + gap + 2 * bar), (30, 32, 30, 255))
    for (s, t), _ in sorted(cells.items()):
        tile = over_ground(tint(frame_of("ore", "%s_full_v0" % ("t1", "t2", "t3", "t4")[t]), hues(6)[s]))
        sheet_img.alpha_composite(tile, (gap + s * (cell + gap), gap + t * (cell + gap)))
    table = slots()
    for b, colours in enumerate(([hues(6, span=SPAN)[i] for i in range(6)], table)):
        y0 = 4 * (cell + gap) + gap + (b + 1) * bar + b * len(OBSERVERS) * (cell + gap)
        for i, observer in enumerate(OBSERVERS):
            for s, c in enumerate(colours):
                tile = over_ground(tint(base, c), observer)
                sheet_img.alpha_composite(tile, (gap + s * (cell + gap), y0 + i * (cell + gap)))
    sheet_img.save(os.path.join(SPR, "species_probe.png"))
    print("\nwrote assets/sprites/species_probe.png: 6 species x 4 tiers, then the")
    print("same six through normal/protan/deutan/tritan twice - EVEN HUE first,")
    print("then the DESIGNED SLOTS. Compare the protan row of each block.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
