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
  TUFT     flattened and soft, NO relief -- a blade cluster, so it reads as
           vegetation by SHAPE. It used to read as vegetation by COLOUR, which
           measured invisible; see the palette note below.
  LOG      long and straight. Everything else in this game at this scale is
           round; one straight edge is the cheapest way to break that. It must
           not read MANUFACTURED, which is a harder bar than "not a blob": see
           `log()`.

A CONTACT SHADOW IS CORRECT HERE and is not the ASSA-64 case: these things
stand on the ground, which is exactly what the shadow is allowed to mean.

HEADROOM IS 0.3125 AND NOT 0.30 SO THE AUTHORED FRAME IS EVEN IN BOTH AXES.
`rig` rounds `headroom * 64`, and 0.30 rounds to 19, which makes the frame 64x83
-- the only odd one there would be (ground 64, items 96, parts 102, player 128,
smelter 144, spawn 208). The client halves an authored frame with NEAREST at
`scale 0.5`, so 83 lands on 41.5 drawn px and an anchor of 19 on 9.5, and the
halving then keeps a different source row than `build.py` kept. 0.3125 is 20 px:
frame 84, drawn 42, offset 10.
"""
import sys, os, math

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()

# THE COLOURS: the ground family pulled toward `grey`, never a new literal and
# never a mineral name (rig rule 7). `mix_hex` is the same helper spawn.py uses
# for its dead lens. Stone is the ground gone grey and a little lighter; its dark
# side is the ground gone grey and darker.
STONE = rig.mix_hex("ground_lt", "grey", 0.45)
STONE_DK = rig.mix_hex("ground_dk", "grey", 0.35)

# THE TUFT WAS MADE OF GROUND COLOURS AND MEASURED INVISIBLE (Maren's ruling,
# 2026-10-04). It was `ground_lt`->`ground` and `ground_dk`->`ground_ore`: four
# ground tones mixed with each other, so per-pixel against the ground it is drawn
# on, tuft0 came out p50 3.5 dE with 32.4% of its pixels over 6. "A plant is not a
# rock" was a sentence about materials and it bought a prop nobody can see.
#
# The floor Maren set is p50 >= 10 dE per-pixel, and the only axis this layer may
# spend is the one everything else here spends: CHROMA, away from the ground and
# toward grey (ore goes the other way, rule 6). So a tuft is now the same move as
# the stone, taken from DARKER ground tones and kept at the stone's distance -- it
# stays a plant by SHAPE, which is what this layer's navigation read rests on
# anyway, and no longer by being the colour of the thing it stands on.
TUFT = rig.mix_hex("ground", "grey", 0.42)
TUFT_DK = rig.mix_hex("ground_ore", "grey", 0.38)

# THE LOG WAS THE LOUDEST THING IN THE SET AND IT OUTSHOUTED THE BOULDERS: p50
# 25.6 against 20.6, at mix 0.62, the lightest colour here. Maren ruled it back to
# the boulders' separation, so it is 0.46 -- still the palest prop, no longer the
# loudest. (The shape change is in `log()`.)
LOG = rig.mix_hex("ground_lt", "grey", 0.46)
LOG_MID = rig.mix_hex("ground", "grey", 0.46)
LOG_DK = rig.mix_hex("ground_dk", "grey", 0.42)

HEADROOM = 0.3125
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
    """A scrub clump: eleven very flat blades, NO relief. Squash 0.12 is the
    ground's own patch trick -- it is colour, not a bump, so it cannot grow the
    lit-top-and-shadow that would make it read as a small boulder.

    A STAR AND NOT A HEAP, AND THAT IS THE WHOLE DESIGN. Once the palette moved
    this prop out of the ground's colours to clear the visibility floor, it is
    made of the same greyed material as the stone -- so the thing that tells a
    player "plant, not rock" can only be the SILHOUETTE. A round clump of blades
    in stone colours is a pebble; six tapering spikes radiating from a centre is
    not, at any colour. I rendered the round one first and it read as a small
    flat rock, which is exactly what `boulder()` already provides.

    A BLADE IS THREE FLAT ROCKS, SHRINKING OUTWARD, because `rock()` takes one
    radius and a blade needs a taper. The inner one of each blade overlaps its
    neighbours, so the clump still has the solid middle that stops a per-pixel
    median drowning in antialiased fringe.
    """
    r = new()
    for b in range(6):
        a = b * (math.tau / 6) + 0.45 * seed + 0.17 * (b % 2)
        for k, (d, rad) in enumerate(((0.045, 0.082), (0.125, 0.056), (0.200, 0.034))):
            r.rock(rad + (0.008 if (b + seed) % 2 else 0.0),
                   (d * math.cos(a), d * math.sin(a), 0.012),
                   mat(TUFT if (b + k) % 2 else TUFT_DK), sub=1, squash=0.12,
                   rot=(0, 0, a))
    return r


def log(seed):
    """A fallen trunk. One straight edge, because every other silhouette in
    this game at this scale is round.

    RADIUS 0.13 AND NOT 0.075, AND THE PICTURE IS WHY. At 0.075 the trunk is
    2.4 tile-units of radius = about 5 px thick at 32 px/tile, and in the
    composited frame it did not read as a log at all -- it read as a thin white
    scratch, the kind of mark a player would take for a rendering fault. A long
    shape has to be thick enough to have an inside; below about 7 px it is a
    line, and lines already mean something else in this game.

    AND THE FIRST ONE READ AS MANUFACTURED, WHICH IS A WORSE FAILURE THAN THE
    SCRATCH (Maren's ruling, her eye, named as such). One smooth cylinder of
    constant diameter with flat circular end caps is a PIPE SEGMENT in a factory
    game -- a thing the player walks over and tries to pick up. Three changes,
    all aimed at that one read and none at the silhouette, which was right:
      * THE ENDS ARE BROKEN, NOT CUT. No cap. Each end is three shards at
        different angles and heights, so the end is a splintered stump.
      * THE BODY HAS A WAIST. Three segments at 1.00 / 0.92 / 1.03 of the
        radius: a trunk tapers and a pipe does not.
      * BARK. Four dark ridges lying along the body, so the surface has grain
        rather than one specular sweep.
    It is also no longer the loudest prop in the set -- that is the palette, see
    `LOG` -- because a dead stick out-shouting a boulder is the wrong order of
    importance for a thing you navigate by.
    """
    r = new()
    ang = 0.5 + 1.5 * seed
    length, rad = 0.66, 0.13
    ux, uy = math.cos(ang), math.sin(ang)
    # BODY: three segments, the middle one thinner, so the silhouette has a waist.
    # They OVERLAP by design: at 0.37 of the length each they barely met, and the
    # three seams read as three stones in a row rather than as one trunk.
    for k, (t, rr) in enumerate(((-0.30, 1.00), (0.0, 0.92), (0.30, 1.03))):
        r.cyl(rad * rr, length * 0.52, (t * length * ux, t * length * uy, rad * 0.9),
              mat(LOG if k != 1 else LOG_MID), bev=0.03, verts=10,
              rot=(math.pi / 2, 0, ang))
    # BARK: ridges along the top, dark, alternating to either side of the axis.
    for i in range(4):
        t = (-0.30 + 0.20 * i) * length
        off = 0.055 * (1 if i % 2 else -1)
        r.rock(0.034 + 0.008 * ((i + seed) % 2),
               (t * ux - off * uy, t * uy + off * ux, rad * 1.5),
               mat(LOG_DK), sub=1, squash=0.42, rot=(0, 0, ang))
    # SPLINTERS: three shards at each end, angled out of the axis. No flat cap.
    for end in (-1, 1):
        bx, by = end * length * 0.50 * ux, end * length * 0.50 * uy
        for j in range(3):
            a = ang + (j - 1) * 0.6 + 0.3 * seed
            r.rock(0.052 + 0.018 * j,
                   (bx + end * 0.045 * math.cos(a), by + end * 0.045 * math.sin(a),
                    rad * (0.55 + 0.4 * j)),
                   mat(LOG_DK if j == 1 else LOG), sub=1, squash=0.62, rot=(0, 0, a))
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
