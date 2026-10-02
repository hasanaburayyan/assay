#!/usr/bin/env -S uv run --quiet --with pillow python
"""Can a tint carry six generated species on a 32px ore tile?

    art/species_probe.py

Writes assets/review/species_probe.png and prints the numbers.

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
import re
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from species_tints import SPECIES_TINTS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The sheets live inside the Godot project: res:// does not go up (ASSA-34).
SPR = os.path.join(ROOT, "client", "assets", "sprites")
# Review output stays out of the project, so an export never packs it.
REVIEW = os.path.join(ROOT, "assets", "review")
os.makedirs(REVIEW, exist_ok=True)
GAME = 32
SPECIES = 6        # sim/src/tuning.rs SPECIES_PER_WORLD
# The sim's grades, worst first. Keyed to Grade::letter(); the art no longer
# invents quartiles that cross no real boundary.
GRADE_ROWS = ("C", "B", "A")

# dE76 thresholds. 2.3 is the just-noticeable difference under ideal side-by-
# side viewing; nothing on a game map is ideal or side-by-side, so:
JND = 2.3
DISTINCT = 12.0     # two species a player must never confuse at a glance
POP = 10.0          # ore against the terrain it sits on
# Grade C is deliberately sparse, so it is held to a lower floor than POP --
# but to a floor. Maren, ruling 2 on ASSA-20: "5.7 is a sentence, not a
# guard." It measured 3.9 before the ladder was rebuilt on the sim's real
# boundaries and nothing here would have said a word if it slid back.
# THRESHOLD SET FROM THE DEFECT: 3.9 is what was wrong, 5.7 is what ships,
# 5 sits between them, so the guard can actually catch the regression it is
# named after instead of sitting below it.
POP_C = 5.0

# THE MAP DISC IS A SECOND SURFACE AND IT HAS ITS OWN FLOOR (ASSA-24, Maren).
# The probe certified the ORE TILE at three grades and nothing else. The client
# also draws each deposit as a flat ~9px disc on the schematic map, one colour,
# whose brightness rides purity CONTINUOUSLY instead of in three steps -- so a
# tile that passes says nothing about a disc at low purity.
#
# THE CONSTANTS ARE READ OUT OF hud.gd, NOT WRITTEN DOWN HERE (ASSA-29), and
# that is the whole correction. The first version of this check retyped them
# and got all three wrong, each in the direction that makes the measured disc
# BRIGHTER than the drawn one:
#
#   1. It gated at 0.55 and printed "the client's constant: purity multiply
#      bottoms out at 0.55". hud.gd bottoms out at 0.525 -- `purity_part` is
#      clamped to 0.05 low, not to 0. Nobody compared the number to the file
#      it claimed to come from.
#   2. It modelled the disc as OPAQUE. `deposit_color` returns alpha 0.85 over
#      a near-black map, which pulls every disc toward the background and costs
#      1 to 2 dE of a*b* separation. hud.gd's own `glyph_color` composites
#      exactly this way, so the client always knew; the probe did not.
#   3. It asserted "the floor is the only purity worth gating ... every
#      brighter purity is slack". False: the CLOSEST PAIR changes with
#      brightness, so the minimum is not at an end. At the shipped constants
#      it sits at purity 6, not purity 1.
#
# Same failure as `art/build.py`'s colour-blind block, which went on drawing
# four empty strips after the row it grepped for was renamed: a number copied
# out of another file is a number that has stopped being about that file.
#
# RED LEVERS, and they reproduce the cause rather than lowering a bar:
#   MAP_FLOOR=k   pretends the client shipped base `k` instead of the one in
#                 hud.gd. At 0.33 the check MUST fail -- a client constant set
#                 too low is the regression the guard is named after.
#   MAP_ALPHA=a   pretends the client shipped alpha `a`. At 0.85 the check MUST
#                 fail (10.8 at purity 6): that was the shipped disc this file
#                 was written to catch, and it is what proves the composite is
#                 still load-bearing rather than arithmetic that cancels out.
#   MAP_OPAQUE=1  the original form of the lever above, back when the client
#                 drew the disc at alpha 0.85 and modelling it solid was the
#                 generous error. hud.gd now ships alpha 1.0 (Maren's ruling,
#                 ASSA-7), so pretending it is opaque CHANGES NOTHING and the
#                 lever can no longer fail. It says so rather than going quietly
#                 green: a lever that cannot fire is not evidence, and a green
#                 run from a dead lever is how this check came to certify a disc
#                 the client did not draw in the first place. Use MAP_ALPHA.
MAP_OPAQUE = bool(os.environ.get("MAP_OPAQUE"))

HUD_GD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "client", "scripts", "hud.gd")


def _hud_number(pattern, what, scope=None):
    """One constant out of hud.gd, or a loud exit.

    Scoped to `deposit_color`'s body where it matters, following
    art/check_species_tints.py: hud.gd is mostly prose about how these numbers
    were derived, and the prose quotes them. A docstring is not a constant.

    EXITING IS THE POINT. If the client renames a constant, this check must
    stop rather than carry on measuring the last shape it understood -- the
    silent version of that is the bug ASSA-29 is about."""
    text = open(HUD_GD).read()
    if scope:
        body = re.search(scope, text, re.DOTALL)
        if not body:
            sys.exit("species_probe: no %s in hud.gd, so the map disc cannot be"
                     " measured as the client draws it." % what)
        text = body.group(0)
    found = re.search(pattern, text)
    if not found:
        sys.exit("species_probe: cannot read %s out of hud.gd (pattern: %s).\n"
                 "  Do not retype it here: this check exists because the last"
                 " copy of these\n  numbers drifted from the client and kept"
                 " passing. Fix the pattern." % (what, pattern))
    return [float(g) for g in found.groups()]


DEPOSIT_COLOR = r"static func deposit_color\(.*?\n\n"
# `dimmed = base + span * purity_part`, and `purity_part` is clamped LOW --
# which is why the dimmest disc is 0.525 and not 0.50.
MAP_BASE, MAP_SPAN = _hud_number(
    r"dimmed\s*:?=\s*([0-9.]+)\s*\+\s*([0-9.]+)\s*\*\s*purity_part",
    "the purity dim formula", DEPOSIT_COLOR)
(MAP_PURITY_MIN,) = _hud_number(
    r"clampf\(float\(purity\)\s*/\s*100\.0,\s*([0-9.]+),", "the purity clamp",
    DEPOSIT_COLOR)
(MAP_ALPHA,) = _hud_number(r"tint\.b \* dimmed,\s*([0-9.]+)\)",
                           "the disc's alpha", DEPOSIT_COLOR)
_bg = _hud_number(r"MAP_BG\s*:?=\s*Color\(([0-9.]+),\s*([0-9.]+),\s*([0-9.]+)\)",
                  "MAP_BG")
MAP_BG = tuple(round(c * 255) for c in _bg)

# THE LETTER ON THE DISC (ASSA-44). Read from hud.gd for the same reason as
# everything above it: a retyped pair of glyph colours is a copy that can drift.
#
# NOT ROUNDED to 8-bit, unlike MAP_BG above, and the difference is not academic.
# `Color(0.02, 0.02, 0.03)` is 5.1/5.1/7.65 out of 255; rounding it to (5, 5, 8)
# moved my worst state from species2 purity 24 to species5 purity 46 and the
# worst ratio by 0.003. Harmless anywhere else in this file, decisive here,
# because three species sit within 0.015 of each other at their flip points. The
# client computes this in float and so does this check now. `_lin` divides by
# 255 itself, so a float scaled to 255 is the right thing to hand it.
GLYPH_DARK = tuple(c * 255.0 for c in _hud_number(
    r"GLYPH_DARK\s*:?=\s*Color\(([0-9.]+),\s*([0-9.]+),\s*([0-9.]+)\)", "GLYPH_DARK"))
GLYPH_LIGHT = tuple(c * 255.0 for c in _hud_number(
    r"GLYPH_LIGHT\s*:?=\s*Color\(([0-9.]+),\s*([0-9.]+),\s*([0-9.]+)\)", "GLYPH_LIGHT"))
# WCAG AA for normal text. Not large text's 3.0, even though hud.gd's own
# comment claims that bar: `glyph_size` draws a letter down to 10px, which is
# not large text (Maren, ASSA-39).
GLYPH_AA = 4.5

# The lever overrides the client's base, never the alpha: pretending the client
# shipped a different base is a question you can ask, and pretending it ships a
# disc it does not draw is the mistake this file just made.
if os.environ.get("MAP_FLOOR"):
    MAP_BASE = float(os.environ["MAP_FLOOR"])
    MAP_SPAN = 1.0 - MAP_BASE
    print("[RED LEVER] map purity base forced to %.2f, overriding hud.gd; at"
          " 0.33 the\n            MAP DISC check MUST fail.\n" % MAP_BASE)
if os.environ.get("MAP_ALPHA"):
    MAP_ALPHA = float(os.environ["MAP_ALPHA"])
    print("[RED LEVER] map disc alpha forced to %.2f, overriding hud.gd; at"
          " 0.85 the\n            MAP DISC check MUST fail (10.8 at purity 6),"
          " because that is the\n            disc the client used to draw.\n"
          % MAP_ALPHA)
if MAP_OPAQUE:
    if MAP_ALPHA >= 1.0:
        print("[DEAD LEVER] MAP_OPAQUE does nothing: hud.gd already draws the"
              " disc at\n             alpha %.2f, so the solid model IS the"
              " shipped one. A lever that\n             cannot fail is not"
              " evidence -- use MAP_ALPHA=0.85, which must FAIL.\n"
              % MAP_ALPHA)
    else:
        print("[RED LEVER] map disc modelled as OPAQUE, the way this check had"
              " it\n            wrong until ASSA-29. It MUST pass that way; the"
              " client\n            draws it at alpha %.2f over a near-black"
              " map.\n" % MAP_ALPHA)


def map_disc(hexcolour, purity):
    """One deposit disc EXACTLY as hud.gd draws it: the species slot, dimmed by
    purity, then composited over the map at the disc's own alpha.

    Scaling r, g and b together cannot move hue or saturation, which is how
    hud.gd keeps "purity may never move the hue" by construction. The alpha
    composite CAN: it mixes toward a near-black background, and that costs
    chroma. That is the part this check used to miss."""
    c = dim_v(hex_rgb(hexcolour),
              MAP_BASE + MAP_SPAN * max(MAP_PURITY_MIN, purity / 100.0))
    if MAP_OPAQUE:
        return c
    return tuple(MAP_BG[i] * (1 - MAP_ALPHA) + c[i] * MAP_ALPHA for i in range(3))

# RED LEVER FOR POP_C. The regression this guard is named after was a COVERAGE
# one -- a grade-C tile with fewer rocks on it is more terrain, and pop fell to
# 3.9 -- so the lever reproduces the cause rather than lowering the bar:
# PROBE_SPARSE=0.5 keeps half the ore pixels. The C check MUST then fail.
SPARSE = float(os.environ.get("PROBE_SPARSE", "1.0"))
if SPARSE < 1.0:
    print("[RED RUN] ore coverage thinned to %.2f; the grade C pop check MUST fail"
          % SPARSE)

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


def wcag_ratio(a, b):
    """Contrast ratio between two colours, the WCAG way: LINEARISED relative
    luminance, which is the step `Color.get_luminance()` in Godot does not take.

    That omission is the whole of ASSA-39 -- a crossover picked in the encoded
    space says nothing about what a reader can see -- so this reuses `_lin`
    rather than carrying a second copy of the transfer curve. dE is the wrong
    instrument here and every other number in this file is dE: contrast is a
    LUMINANCE relation and a letter on a disc either has it or does not,
    regardless of how far apart their hues are."""
    ya = 0.2126 * _lin(a[0]) + 0.7152 * _lin(a[1]) + 0.0722 * _lin(a[2])
    yb = 0.2126 * _lin(b[0]) + 0.7152 * _lin(b[1]) + 0.0722 * _lin(b[2])
    hi, lo = max(ya, yb), min(ya, yb)
    return (hi + 0.05) / (lo + 0.05)


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
    g.alpha_composite(thin(img if img.size == g.size else at_1x(img)))
    return as_seen(g, observer, space) if observer != "normal" else g


def thin(img):
    """Drop ore pixels on a fixed lattice (SPARSE < 1). No RNG: a red lever
    whose answer moved between runs would be worse than no lever."""
    if SPARSE >= 1.0:
        return img
    img = img.convert("RGBA").copy()
    px = img.load()
    keep = max(1, round(1.0 / max(SPARSE, 1e-6)))
    i = 0
    for y in range(img.height):
        for x in range(img.width):
            if px[x, y][3] > 0:
                if i % keep:
                    px[x, y] = px[x, y][:3] + (0,)
                i += 1
    return img


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


def dim_v(rgb, k):
    """Scale HSV VALUE by k, which is what the client's purity multiply does.
    Not a multiply toward black and not a blend toward the background: V is
    the channel hud.gd actually rides, so the probe has to ride the same one
    or it is certifying a surface nobody draws."""
    h, s, v = colorsys.rgb_to_hsv(*[c / 255.0 for c in rgb])
    return tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, s, v * k))


def disc_exact(hexcolour, purity):
    """The disc as a FLOAT, for the one check whose margin is smaller than a
    rounding step. (ASSA-44)

    `map_disc` goes through `dim_v`, which ROUNDS to 8-bit. Everywhere else in
    this file that is correct and I am not touching it: dE cannot see half a
    code value, and every existing number here was measured with it.

    The glyph gate can see it. Three species sit within 0.015 of each other at
    their flip points, so rounding moved my worst state from species2 purity 24
    to species5 purity 46 and the worst ratio by 0.022 -- larger than the whole
    margin the gate has. I found that by disagreeing with my OWN other check
    rather than by thinking about it.

    Verified against the engine: this reproduces `AssayHud.deposit_color`'s own
    output for all 600 states to within 1.1e-5 of a code value, where `map_disc`
    is off by up to 0.5. Scaling r, g and b together is identical to scaling
    HSV's V -- V is just max(r, g, b) -- so this is the same operation as
    `dim_v` without the quantisation, and it is also literally the line
    `deposit_color` runs."""
    part = min(1.0, max(MAP_PURITY_MIN, purity / 100.0))
    dimmed = MAP_BASE + MAP_SPAN * part
    c = tuple(v * dimmed for v in hex_rgb(hexcolour))
    if MAP_OPAQUE or MAP_ALPHA >= 1.0:
        return c
    return tuple(_bg[i] * 255.0 * (1 - MAP_ALPHA) + c[i] * MAP_ALPHA for i in range(3))


def dAB(a, b):
    """dE on HUE AND CHROMA ONLY (a*, b*), with L* dropped.

    This is the right measure for the map disc and the wrong one for most
    things, so it is worth being explicit. On the map, BRIGHTNESS ALREADY
    MEANS PURITY. If L* counted here, two discs of the same species at
    different purity would score as "distinct" and a palette could pass by
    being a brightness ramp -- which is exactly how a muted table fooled me
    once already, scoring 16.3 while being one hue at six brightnesses."""
    la, lb = lab(a), lab(b)
    return math.hypot(la[1] - lb[1], la[2] - lb[2])


def seen_flat(rgb, observer):
    """One flat colour through one observer, reusing the pipeline's matrices."""
    px = tuple(int(round(v)) for v in rgb)
    return as_seen(Image.new("RGBA", (1, 1), px + (255,)), observer,
                   "linear").convert("RGBA").getpixel((0, 0))[:3]


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
    # GRADE C, THE DARKEST TILE, ON PURPOSE. This used to be the middle of
    # the ladder, which measured species where the art is kindest to them.
    # `modulate` is a multiply, so a darker rock scales the gap between two
    # species by exactly its own factor - the same arithmetic Maren used to
    # rule that purity must not dim the tint, applied to my own ladder. The
    # worst case for telling two species apart is the bottom of the ladder,
    # so every species number below is measured there.
    base = frame_of("ore", "C_full_v0")
    # ...but FINDABILITY is a different question and belongs at a different
    # grade. Species separation is worst where the rock is darkest (C), so it
    # is measured there. "Does a deposit stand off the terrain" is about
    # COVERAGE, and a grade C tile is sparse ON PURPOSE - poor ore should look
    # poor. Judging pop at C rejects every tint there is and tells you nothing
    # about the art, so pop is measured on a typical tile and C is reported
    # separately as the subtle end of the ladder.
    pop_base = frame_of("ore", "B_full_v0")
    ground = at_1x(frame_of("ground", "v0"))
    gmean = mean_rgb(ground)
    ok = True

    # Is the base actually neutral and actually light? Both are load-bearing
    # for a multiply tint and both were ASSERTED in rig.py before they were
    # ever checked here.
    bm = mean_rgb(at_1x(base))
    bl = lab(bm)
    chroma = math.sqrt(bl[1] ** 2 + bl[2] ** 2)
    print("base ore/C_full_v0 (darkest grade): mean rgb (%.0f, %.0f, %.0f), L* %.1f, chroma %.1f"
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
    # TWO TABLES, TWO LINES, AND ONLY ONE OF THEM GATES. Maren caught this on
    # ASSA-24: I put the grade-C floor on `hues(n)`, the EVEN-SPACED STAND-IN,
    # which is a palette we do not ship and check 5 rejects. One number was
    # doing two jobs.
    #   STAND-IN  answers "can ANY id-derived hue scheme pop off our terrain" -
    #             the right instrument for that question, so it is reported.
    #   SHIPPED   answers "does the ore we actually ship pop" - the only one
    #             that can block, because it is the only one a player sees.
    print()
    n = 6
    stand_in = hues(n)
    for g in GRADE_ROWS:
        gt = frame_of("ore", "%s_full_v0" % g)
        floor = POP_C if g == "C" else POP
        shipped = [dE(mean_rgb(over_ground(tint(gt, hex_rgb(c)))), gmean)
                   for c in SPECIES_TINTS]
        generic = [dE(mean_rgb(over_ground(tint(gt, h))), gmean) for h in stand_in]
        if min(shipped) >= POP:
            note = ""
        elif g == "C":
            note = ("<-- subtle by design, floor %.0f" % POP_C
                    if min(shipped) >= POP_C else "<-- TOO FAINT EVEN FOR C")
        else:
            note = "<-- SINKS INTO TERRAIN"
        print("grade %s vs ground: SHIPPED table worst %5.1f, best %5.1f  %s"
              % (g, min(shipped), max(shipped), note))
        print("                    stand-in (even hues) worst %5.1f  [reported,"
              " does not gate]" % min(generic))
        if min(shipped) < floor:
            ok = False
            if g == "C":
                print("  FAIL: grade C is allowed to be subtle, not invisible. It"
                      "\n  measured %.1f against a floor of %.1f. This slid to 3.9"
                      "\n  once already; a sparse tile is still a tile you have to"
                      "\n  be able to spot on the map." % (min(shipped), POP_C))
    pops = [dE(mean_rgb(over_ground(tint(pop_base, h))), gmean) for h in stand_in]

    # ---- 2b. THE MAP DISC, a second surface with its own floor (ASSA-24).
    #
    # Everything above certifies the ORE TILE: textured rock, over olive
    # terrain, at three discrete grades. The client draws the same deposit a
    # SECOND way -- a flat ~9px disc on the schematic map, one colour, over a
    # near-black background, with brightness riding purity CONTINUOUSLY. None
    # of those four differences is cosmetic, so a tile that passes says
    # nothing about a disc, and the probe was silent about half of what a
    # player looks at.
    #
    # SWEPT ACROSS THE WHOLE PURITY RANGE, not sampled at the floor. The old
    # version gated one row and said every brighter purity was slack; the
    # closest PAIR changes with brightness, so the minimum is not at an end.
    # Hue/chroma only: see dAB() for why L* must not count on this surface.
    print("\nthe MAP DISC: flat %d-colour discs on the schematic map, as hud.gd"
          % len(SPECIES_TINTS))
    print("draws them -- dimmed by %.2f + %.2f * clamp(purity/100, %.2f, 1), then"
          % (MAP_BASE, MAP_SPAN, MAP_PURITY_MIN))
    print("composited at alpha %.2f over MAP_BG rgb%s. a*b* only, worst of %d"
          % (MAP_ALPHA, MAP_BG, len(OBSERVERS)))
    print("observers, floor %.0f. Every constant above is READ from hud.gd."
          % DISTINCT)

    def closest(purity):
        cols = [map_disc(c, purity) for c in SPECIES_TINTS]
        worst, who = 99.0, None
        for obs in OBSERVERS:
            s = [seen_flat(c, obs) for c in cols]
            for i in range(len(cols)):
                for j in range(i + 1, len(cols)):
                    d = dAB(s[i], s[j])
                    if d < worst:
                        worst, who = d, (obs, i, j)
        return worst, who, min(dE(c, MAP_BG) for c in cols)

    swept = [(p,) + closest(p) for p in range(1, 101)]
    for p in (1, 6, 10, 20, 40, 70, 100):
        _, w, who, bg = next(r for r in swept if r[0] == p)
        print("  purity %3d (V*%.3f): closest pair %d vs %d under %-6s"
              " dE(a*b*) %5.1f  %-9s | vs background dE %5.1f"
              % (p, MAP_BASE + MAP_SPAN * max(MAP_PURITY_MIN, p / 100.0),
                 who[1], who[2], who[0], w,
                 "OK" if w >= DISTINCT else "TOO CLOSE", bg))
    p, w, who, bg = min(swept, key=lambda r: r[1])
    print("  WORST OVER THE WHOLE RANGE: %.1f at purity %d (species %d vs %d,"
          " %s)." % (w, p, who[1], who[2], who[0]))
    if w < DISTINCT:
        ok = False
        print("  FAIL: two species are %.1f apart for a %s player on the"
              "\n  surface they use to decide where to walk, under %.0f. It is"
              "\n  NOT at the dimmest disc -- the closest pair moves with"
              "\n  brightness, which is why this is swept and not sampled."
              "\n  The table is measured and shipped, so the lever is hud.gd's"
              "\n  base: %.2f + %.2f*p fails, 0.65 + 0.35*p holds 12.9. That"
              "\n  costs purity legibility (range %.2f:1 -> 1.54:1) and is the"
              "\n  Director's trade to make, not this file's."
              % (w, who[0], DISTINCT, MAP_BASE, MAP_SPAN,
                 1.0 / (MAP_BASE + MAP_SPAN * MAP_PURITY_MIN)))
    pb, _, _, bgw = min(swept, key=lambda r: r[3])
    if bgw < DISTINCT:
        ok = False
        print("  FAIL: a disc sinks into the map background at purity %d"
              " (dE %.1f)." % (pb, bgw))

    # AND THE ONE I GOT WRONG, kept as a reported line because it is the
    # evidence against my own recommendation. I told Limpet (ASSA-25) that
    # SPECIES_TINTS are multipliers rather than fills, that a flat #7A29CC
    # would SINK into the dark map, and that the map should use a table
    # derived from the tinted ore tile instead. I never measured any of it.
    #   - nothing sinks: the dimmest disc clears the background by 34.7
    #   - and the derived table is WORSE, because the ore tile's mean carries
    #     the rock's dark outline and shading, so it starts with less chroma
    #     and has less to spend on the dimming the map applies.
    # Maren's ruling (use the tints) is the one with the margin. The gap below
    # is real and does not gate: the map is deliberately more chromatic than
    # the world because it is a flat disc on near-black rather than textured
    # rock on olive, and it needs the chroma to survive being dimmed.
    print("\n  map table vs the world tile it stands for (reported, does not gate):")
    for i, c in enumerate(SPECIES_TINTS):
        world = mean_rgb(at_1x(tint(frame_of("ore", "C_full_v0"), hex_rgb(c))))
        print("    species%d  map %s  world #%02X%02X%02X  dE(a*b*) %5.1f"
              % (i, c, round(world[0]), round(world[1]), round(world[2]),
                 dAB(hex_rgb(c), world)))

    # ---- 2c. THE LETTER ON THE DISC (ASSA-44, acceptance 4 of ASSA-39).
    #
    # This file measured disc against disc and disc against map background for
    # two days and never once measured the GLYPH against the disc it sits on.
    # So "the map is green" was green about two of the three things on the map,
    # and a letter at contrast ratio 2.22 went out under my own passing check.
    # The map disc is the cue colourblind players lose; the letter is what they
    # are supposed to read instead, which makes it the least optional thing here.
    #
    # WHAT THIS GATES AND WHAT IT DELIBERATELY DOES NOT.
    #   MINE: that the tint table admits a readable letter AT ALL. If both glyph
    #   colours are unreadable on some disc, no picking rule can rescue it, and
    #   the tints are mine. So the gate is on max(dark, light) -- the ceiling of
    #   any possible picker -- against WCAG AA for normal text.
    #
    #   NOT MINE, AND NOT MEASURABLE HERE: whether `glyph_color` actually PICKS
    #   the better of the two. That is a property of a GDScript function, and
    #   the honest way to check it is to run the client and ask -- which is
    #   `art/check_glyph_contrast.py`, and which is RED today for the 226 states
    #   ASSA-39 is about. It would be very easy to compute both ratios here,
    #   take the better, and assert that taking the better takes the better.
    #   That passes by construction, measures nothing, and would stay green if
    #   the client reverted tomorrow. A tautology is worse than no check,
    #   because it occupies the place where a check should be.
    print("\nthe LETTER ON THE DISC: %d species x purity 1-100, true WCAG"
          % len(SPECIES_TINTS))
    print("contrast (LINEARISED, which is the step get_luminance() skips).")
    print("dark %s / light %s (of 255, unrounded), both READ from hud.gd."
          % (tuple(round(c, 2) for c in GLYPH_DARK),
             tuple(round(c, 2) for c in GLYPH_LIGHT)))
    print("Gate is on the")
    print("BEST AVAILABLE letter, floor %.1f = WCAG AA normal text." % GLYPH_AA)

    glyph_worst = (99.0, None)
    glyph_cases = []
    for i, c in enumerate(SPECIES_TINTS):
        per = (99.0, None)
        for p in range(1, 101):
            disc = disc_exact(c, p)
            best = max(wcag_ratio(disc, GLYPH_DARK), wcag_ratio(disc, GLYPH_LIGHT))
            if best < per[0]:
                per = (best, p)
            if best < glyph_worst[0]:
                glyph_worst = (best, (i, p))
        d_at, l_at = (wcag_ratio(disc_exact(c, per[1]), g) for g in (GLYPH_DARK, GLYPH_LIGHT))
        print("    species%d %s  best letter %5.2f at purity %3d  (dark %5.2f,"
              " light %5.2f)" % (i, c, per[0], per[1], d_at, l_at))
        glyph_cases.append((i, c, per[1], d_at, l_at))
    gw, (gs, gp) = glyph_worst
    print("  worst available over %d states: %.4f at species%d purity %d,"
          % (6 * 100, gw, gs, gp))
    print("  margin %+.4f on AA normal text (%.1f), %+.4f on large text (3.0)."
          % (gw - GLYPH_AA, GLYPH_AA, gw - 3.0))
    # Said out loud because 0.0152 is one part in 300 and I would rather the
    # team knew it than discovered it. The worst state sits exactly where the
    # two glyph colours are equally readable -- the flip point -- so this is a
    # property of the tint ramp and not of any picker.
    if gw < GLYPH_AA:
        ok = False
        print("\n  FAIL: the tint table no longer admits a letter that meets AA"
              "\n  for normal text at every state, and NO picking rule can fix"
              "\n  it -- %.4f is the ceiling. The letter is the accessibility"
              "\n  read, so this is a conversation about the TINT (the"
              "\n  Director's call), never a bound to raise in this file." % gw)

    # ---- 3. THE AXIS COLLISION
    # An ore tile already spends a visual axis on TIER, and parts spend one on
    # GRADE - both of them tone. If species is hue and tier is tone, a player
    # reads a 32px tile that is carrying two things at once. The question is
    # not whether each axis works alone; it is whether a low tier of one
    # species lands on a high tier of another.
    print("\naxis collision: species (hue) against grade (tone), 6 species x 3 grades")
    cells = {}
    for s, h in enumerate(hues(6)):
        for t, row in enumerate(GRADE_ROWS):
            tile = over_ground(tint(frame_of("ore", "%s_full_v0" % row), h))
            cells[(s, t)] = mean_rgb(tile)
    cross = [(dE(cells[a], cells[b]), a, b)
             for a in cells for b in cells if a < b and a[0] != b[0]]
    same = [(dE(cells[(s, t1)], cells[(s, t2)]), s, t1, t2)
            for s in range(6) for t1 in range(len(GRADE_ROWS))
            for t2 in range(t1 + 1, len(GRADE_ROWS))]
    cw, ca, cb = min(cross)
    sw, ss, st1, st2 = min(same)
    print("  closest DIFFERENT-species pair across all grades: %s vs %s at dE %5.1f"
          % (ca, cb, cw))
    print("  closest same-species grade step (how readable grade is): dE %5.1f (species %d, %s vs %s)"
          % (sw, ss, GRADE_ROWS[st1], GRADE_ROWS[st2]))
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
        compm = [mean_rgb(over_ground(tint(pop_base, h))) for h in hues(6, sat=s)]
        worst = min(dE(rockm[i], rockm[j])
                    for i in range(6) for j in range(i + 1, 6))
        gpop = min(dE(m, gmean) for m in compm)
        mark = "OK" if worst >= DISTINCT and gpop >= POP else "TOO CLOSE"
        if mark == "OK":
            floor_sat = s
        print("  sat %.2f: closest species pair dE %5.1f, worst vs ground dE %5.1f  %s"
              % (s, worst, gpop, mark))
    if floor_sat is None:
        print("  -> NO saturation passes both floors on this tile. At the bottom of")
        print("     the ladder that is a COVERAGE result, not a colour one: a sparse")
        print("     tile is mostly terrain, so it cannot differ from terrain.")
    else:
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
    print("\ngrade readability on the art as it ships (no tint)")
    means = [mean_rgb(over_ground(frame_of("ore", "%s_full_v0" % g))) for g in GRADE_ROWS]
    steps = [dE(means[i], means[i + 1]) for i in range(len(means) - 1)]
    worst_orig = min(steps)
    print("  %s   full %s-%s range %5.1f"
          % ("  ".join("%s>%s %5.1f" % (GRADE_ROWS[i], GRADE_ROWS[i + 1], steps[i])
                       for i in range(len(steps))),
             GRADE_ROWS[0], GRADE_ROWS[-1], dE(means[0], means[-1])))
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
            compm = [mean_rgb(over_ground(tint(pop_base, h), observer)) for h in hs]
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
            compm = [mean_rgb(over_ground(tint(pop_base, mute(c, k)), observer))
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

    # ---- 6c. WHAT THE LADDER COSTS THE SPECIES MARGIN.
    #
    # Maren ruled that purity must not DIM the species tint, because a
    # uniform multiply scales the gap between two species by exactly its own
    # factor. That ruling is about the map circle, but the arithmetic does not
    # care which surface it is on, and MY LADDER IS PARTLY LIGHTNESS: a grade
    # C rock is darker than a grade A one, so the same compression happens
    # inside the tile art. Neither of us said that out loud, and every species
    # number I have reported until now was measured at ONE grade.
    #
    # So: measure the six tints at each grade. The spread between the grades
    # is what the ladder costs, and grade C is the number that has to clear
    # the floor. If it does not, the ladder has to buy its contrast from
    # COVERAGE instead of value - which is free, because count and size change
    # how much rock there is without changing how bright it is.
    print("\n  what the grade ladder costs THE SHIPPED TABLE (art/species_tints.py),")
    print("  closest pair by hue/chroma, worst observer, at each grade:")
    ladder_ok = True
    for g in GRADE_ROWS:
        worst, worst_o = 1e9, None
        for o in OBSERVERS:
            ls = [lab(mean_rgb(as_seen(at_1x(tint(frame_of("ore", "%s_full_v0" % g),
                                                  hex_rgb(c))), o)))
                  for c in SPECIES_TINTS]
            w = min(math.sqrt(sum((ls[i][t] - ls[j][t]) ** 2 for t in (1, 2)))
                    for i in range(len(SPECIES_TINTS))
                    for j in range(i + 1, len(SPECIES_TINTS)))
            if w < worst:
                worst, worst_o = w, o
        mark = "OK" if worst >= DISTINCT else "BELOW FLOOR"
        if worst < DISTINCT:
            ladder_ok = False
        print("    grade %s: %5.1f  (worst observer: %s)  %s" % (g, worst, worst_o, mark))
    if not ladder_ok:
        ok = False
        print("    -> the ladder is too dark at the bottom, so grade is eating the")
        print("       species margin. Move contrast from VALUE to COVERAGE in")
        print("       ore.py (shade() floor, count/size) - coverage is free here.")
    else:
        print("    -> the grade ladder costs the species read nothing it cannot")
        print("       afford. Grade C is the binding one, and it clears.")

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

    def derive(label, sats, pop_base=pop_base):
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
                    poplayer = tint(pop_base, c)
                    pop = min(dE(mean_rgb(over_ground(poplayer, o)), gmeans[o]) for o in OBSERVERS)
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
        tile = over_ground(tint(frame_of("ore", "%s_full_v0" % GRADE_ROWS[t]), hues(6)[s]))
        sheet_img.alpha_composite(tile, (gap + s * (cell + gap), gap + t * (cell + gap)))
    table = slots()
    for b, colours in enumerate(([hues(6, span=SPAN)[i] for i in range(6)], table)):
        y0 = 4 * (cell + gap) + gap + (b + 1) * bar + b * len(OBSERVERS) * (cell + gap)
        for i, observer in enumerate(OBSERVERS):
            for s, c in enumerate(colours):
                tile = over_ground(tint(base, c), observer)
                sheet_img.alpha_composite(tile, (gap + s * (cell + gap), y0 + i * (cell + gap)))
    # ---- block 4: THE LETTER ON THE DISC, at map size (ASSA-44)
    #
    # The numbers in section 2c are a luminance relation and I do not trust
    # myself to imagine one. Each species at its OWN worst purity, the disc
    # drawn the size the map draws it, with the dark letter on the left of the
    # pair and the light one on the right. The point of the picture is that at
    # these states the two are nearly equal, so neither looks obviously wrong --
    # which is exactly why a threshold that picks the worse one went unnoticed.
    # The slot is wider than the two discs because the label under it is wider
    # than the two discs; at 2*GAME they ran into each other and "6.96p72" is
    # not a number anyone can read.
    pair, pad, slot = GAME, 3, 2 * GAME + 16
    gw_ = len(glyph_cases) * slot + pad
    strip = Image.new("RGBA", (gw_, pair + 2 * pad + 12), tuple(MAP_BG) + (255,))
    gd = ImageDraw.Draw(strip)
    letters = ImageFont.load_default(size=int(pair * 0.7))
    for n, (i, c, p, d_at, l_at) in enumerate(glyph_cases):
        x0 = pad + n * slot
        disc = tuple(int(round(v)) for v in disc_exact(c, p))
        for k, glyph in enumerate((GLYPH_DARK, GLYPH_LIGHT)):
            x = x0 + k * pair
            gd.ellipse([x, pad, x + pair - 1, pad + pair - 1], fill=disc + (255,))
            gd.text((x + pair / 2, pad + pair / 2), chr(ord("A") + i),
                    fill=tuple(int(round(v)) for v in glyph) + (255,),
                    font=letters, anchor="mm")
        gd.text((x0, pad + pair + 1), "p%d %.2f/%.2f" % (p, d_at, l_at),
                fill=(200, 200, 200, 255))
    full = Image.new("RGBA", (max(sheet_img.width, strip.width),
                              sheet_img.height + strip.height + bar),
                     (30, 32, 30, 255))
    full.alpha_composite(sheet_img, (0, 0))
    full.alpha_composite(strip, (0, sheet_img.height + bar))
    sheet_img = full

    sheet_img.save(os.path.join(REVIEW, "species_probe.png"))
    print("\nwrote assets/review/species_probe.png: 6 species x 3 grades, then the")
    print("same six through normal/protan/deutan/tritan twice - EVEN HUE first,")
    print("then the DESIGNED SLOTS. Compare the protan row of each block.")
    print("Last strip is THE LETTER ON THE DISC at map size: each species at its")
    print("own worst purity, dark letter then light letter, labelled p<purity>")
    print("<dark>/<light>. At these states the pair is near-equal, which is how a")
    print("threshold picking the worse one stayed invisible for two days.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
