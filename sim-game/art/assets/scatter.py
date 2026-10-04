"""Scatter: the non-interactive second ground layer (ASSA-202).

WHY THIS SHEET EXISTS. 96.3% of the player's view is one material (Maren,
measured on a real window shot), and worse than that: `manifest.ground.block ==
[8,8]` is placed BY POSITION, so the ground picture repeats every 8 tiles = 256
drawn px. The map rect is 912 px = 28.5 tiles, so ONE SCREEN HOLDS 3.5 COPIES OF
THE SAME PICTURE and two screens 16 or 24 tiles apart are pixel-identical
(measured on `02-play.png`: 100.00% identical over 193,800 px at a 256 px shift).
There is nothing to navigate by because there is literally nothing new to see.

SO THIS LAYER IS KEYED BY A HASH OF THE TILE COORDINATE, NEVER BY A BLOCK --
`scene_view.variant_of`'s own FNV. A hash is aperiodic, so it cannot be caught
repeating the way the ground is; a second block would just add a second lattice.

WHAT IT MAY NOT DO, AND WHY THAT IS STRUCTURAL RATHER THAN TUNED. Ore owns
saturation (rig rule 6). Measured on the shipped frame, the ore's separation from
the ground is delta E 56.2, of which the CHROMA leg is 50.8 against a lightness
leg of 24.0: the ore's signal is chroma.

SO ORE AND SCATTER MOVE IN OPPOSITE DIRECTIONS ON THAT ONE AXIS. Every colour
here is the ground's family pulled toward `grey`, which takes chroma AWAY: ore
sits at saturation 0.792 against the ground's 0.357 and this layer at 0.144, so
scatter is the least saturated thing on the screen and ore the most. They cannot
be confused because they are on opposite sides of the same ground, which is a
stronger guarantee than being quieter would be.

I FIRST WROTE "scatter spends LUMINANCE and has no chroma to spare" HERE, AND IT
IS BACKWARDS. Measured on the composited frame with the scatter pixels named by
the overlay's own alpha: delta E 17.5, of which 17.4 is chroma and 1.5 is
lightness. It barely moves in luminance at all. The sentence was written before
the measurement and the measurement reversed it. The consequence worth knowing:
a delta L* of +1.5 means this layer nearly VANISHES in a greyscale copy, so the
navigation read is carried by hue-free SHAPE rather than by tone, and a landmark
that must survive greyscale needs lightness added on purpose.

TWO SCALES, BECAUSE THE PLACEMENT STUDY SAID ONE WAS NOT ENOUGH
(`shared/assay/cove-assa202/`). Uniform small props make two places look like
the same place, because statistically they ARE the same place; what a player
navigates by is the rare large thing. So:

  GRIT    3 rows, 1-3 small stones per frame, a few px each. Regional character:
          the field clumps these, so there are stony stretches and bare ones.
  LARGE   3 kinds x 2, each a landmark you could walk back to. They are three
          different KINDS on purpose -- a boulder, a tuft and a log read apart
          from each other at 1x, where six boulders would only read as "a rock".

THE THREE KINDS ARE THREE DIFFERENT SURFACES, not three silhouettes:
  BOULDER  relief, catches the 9-degree key, so it has a lit top and a shadow.
  TUFT     flattened and soft, NO relief -- it is colour, like the ground's own
           patches, so it reads as vegetation rather than as a small rock.
  LOG      long and straight. Everything else in this game at this scale is
           round; one straight edge is the cheapest way to break that.

A CONTACT SHADOW IS CORRECT HERE and is not the ASSA-64 case: these things
stand on the ground, which is exactly what the shadow is allowed to mean.

HEADROOM 0.30 GIVES AN ODD AUTHORED FRAME AND MUST CHANGE TO 0.3125 BEFORE THIS
SHEET IS PACKED. `rig` rounds `headroom * 64` to 19, so the frame is 64x83 --
and every sheet already on main is even in both axes (ground 64, items 96, parts
102, player 128, smelter 144, spawn 208). The client halves an authored frame
with NEAREST at `scale 0.5`, so 83 lands on 41.5 drawn px and an anchor of 19 on
9.5: the halving keeps a different row than `build.py` and the ASSA-202
composite kept. Sub-pixel, nothing visible has been seen, and the fix is this one
constant -- 0.3125 is 20 px, frame 84, drawn 42, offset 10. NOT APPLIED YET on
purpose: it costs a re-render of all nine rows and of the frame the Director is
judging, and her density ruling costs the same re-render. One render, after the
ruling, doing both.
"""
import sys, os, math

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()

# THE COLOURS: the ground family pulled toward `grey`, never a new literal and
# never a mineral name (rig rule 7). `mix_hex` is the same helper spawn.py uses
# for its dead lens. Stone is the ground gone grey and a little lighter; its dark
# side is the ground gone grey and darker. Tufts stay greener than stone, because
# a plant is not a rock.
STONE = rig.mix_hex("ground_lt", "grey", 0.45)
STONE_DK = rig.mix_hex("ground_dk", "grey", 0.35)
TUFT = rig.mix_hex("ground_lt", "ground", 0.35)
TUFT_DK = rig.mix_hex("ground_dk", "ground_ore", 0.40)
LOG = rig.mix_hex("ground_lt", "grey", 0.62)       # bleached: the lightest thing here
LOG_DK = rig.mix_hex("ground", "grey", 0.50)

HEADROOM = 0.30
asset = rig.Asset("scatter", out, (1, 1), headroom=HEADROOM)


def new():
    r = rig.Rig(samples=64)
    r.shadow_catcher()
    return r


def grit(seed, n):
    """`n` small stones, scattered inside the tile. Drawn small on purpose: at
    32 px/tile these land at 3-7 px, the size the eye reads as grain rather than
    as an object it could walk to."""
    r = new()
    for i in range(n):
        a = (seed * 2.3 + i * 2.39996)                  # golden-angle, no clumping
        d = 0.10 + 0.26 * ((seed + i * 3) % 5) / 4.0
        s = 0.070 + 0.034 * ((seed + i * 7) % 4) / 3.0
        r.rock(s, (d * math.cos(a), d * math.sin(a), s * 0.45),
               mat(STONE if (seed + i) % 2 else STONE_DK),
               sub=1, squash=0.50, rot=(0, 0, a))
    return r


def boulder(seed):
    """One rock with real height, plus two chips at its foot so it sits in the
    ground instead of on it."""
    r = new()
    big = 0.21 + 0.05 * (seed % 2)
    r.rock(big, (0.02, -0.02, big * 0.62), mat(STONE), sub=2, squash=0.78,
           rot=(0, 0, 0.6 + seed))
    r.rock(big * 0.42, (-big * 1.15, big * 0.35, big * 0.22), mat(STONE_DK),
           sub=1, squash=0.55, rot=(0, 0, 2.1 - seed))
    r.rock(big * 0.30, (big * 1.05, big * 0.55, big * 0.16), mat(STONE_DK),
           sub=1, squash=0.50, rot=(0, 0, 0.3 + seed))
    return r


def tuft(seed):
    """A scrub clump: seven very flat blades, NO relief. Squash 0.12 is the
    ground's own patch trick -- it is colour, not a bump, so it cannot grow the
    lit-top-and-shadow that would make it read as a small boulder."""
    r = new()
    for i in range(7):
        a = i * 0.8976 + seed
        d = 0.055 * i
        r.rock(0.085 + 0.030 * ((i + seed) % 3), (d * math.cos(a), d * math.sin(a), 0.012),
               mat(TUFT if i % 2 else TUFT_DK), sub=1, squash=0.12, rot=(0, 0, a))
    return r


def log(seed):
    """A bleached trunk. One straight edge, because every other silhouette in
    this game at this scale is round.

    RADIUS 0.13 AND NOT 0.075, AND THE PICTURE IS WHY. At 0.075 the trunk is
    2.4 tile-units of radius = about 5 px thick at 32 px/tile, and in the
    composited frame it did not read as a log at all -- it read as a thin white
    scratch, the kind of mark a player would take for a rendering fault. A long
    shape has to be thick enough to have an inside; below about 7 px it is a
    line, and lines already mean something else in this game.
    """
    r = new()
    ang = 0.5 + 1.5 * seed
    length, rad = 0.66, 0.13
    r.cyl(rad, length, (0, 0, rad * 0.9), mat(LOG), bev=0.02, verts=12,
          rot=(math.pi / 2, 0, ang))
    # the broken end, darker, so the cylinder has a near and a far end
    r.cyl(rad * 0.97, 0.07, (length * 0.5 * math.cos(ang), length * 0.5 * math.sin(ang),
                             rad * 0.9), mat(LOG_DK), bev=0.01, verts=12,
          rot=(math.pi / 2, 0, ang))
    return r


ROWS = [("grit0", lambda: grit(0, 1)), ("grit1", lambda: grit(1, 2)),
        ("grit2", lambda: grit(2, 3)),
        ("boulder0", lambda: boulder(0)), ("boulder1", lambda: boulder(1)),
        ("tuft0", lambda: tuft(0)), ("tuft1", lambda: tuft(1)),
        ("log0", lambda: log(0)), ("log1", lambda: log(1))]

for name, build in ROWS:
    r = build()
    r.frame(1, 1, headroom=HEADROOM)
    r.render(asset.path(name))
    asset.add(name, 1)
asset.write()
