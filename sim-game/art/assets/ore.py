"""Ore deposit tiles, 1x1 and seamless. SPECIES-NEUTRAL: the client tints.

Rows: t<1-4>_<full|edge>[_v<n>] and depleted_<full|edge>. 14 rows, and not
one mineral name among them. A world rolls six species from its seed (ADR
0001) and no rule, recipe or sprite may name one, so the old 56 rows of
iron / copper / coal / stone were art for a design that was withdrawn.

- tier 1..4 = purity 1-25 / 26-50 / 51-75 / 76-100: more rock, bigger rock,
  lighter rock, and from tier 3 up emissive crystal glints.
- full = tile surrounded by ore, edge = tile at the patch border (sparser, so
  the patch outline isn't a hard staircase). Same ground under both.
- depleted: pitted dark ground with a few dead rocks.

THREE RULES THIS FILE EXISTS TO HOLD, all measured in art/species_probe.py:

1. THE BASE IS LIGHT AND NEAR-NEUTRAL. The client multiplies a species
   colour over these pixels (Godot `modulate` is a per-channel MULTIPLY).
   Multiply cannot brighten, so a mid-grey base turns every species into mud,
   and a base with a hue of its own drags every species toward that hue. The
   lightness here is a budget for the tint to spend, not a look.

1b. WHICH IS WHY THESE TILES ARE TRANSPARENT: ROCK ONLY, NO GROUND BAKED IN.
   They used to render opaque with the ground under them, which was fine when
   each ore kind had one fixed colour. It is a bug the moment the client
   tints, because `modulate` multiplies the WHOLE texture - the terrain
   showing between the rocks would be tinted along with the ore. Measured:
   baked in, the "neutral" base tile had a mean of (163, 172, 145) and a
   chroma of 15, which is not a neutral rock, it is grass. The client draws
   the ground tile and composites this over it, which is what mock_scene.py
   already did.

2. TIER IS THE ONLY AXIS THE ART STILL CARRIES BY ITSELF, because colour has
   been spent on species. So it has to be a strong value-and-coverage ladder.
   It was not: the old code picked each rock's shade from three candidates
   and only ONE of the three moved with tier, so two rocks in three were the
   same colour at purity 5 and purity 95. That is why the smallest adjacent
   tier step measured 3.5 dE, 1.5x JND, against species at 33.7 - the lever
   was real but connected to a third of the rocks. Every shade moves now.
"""
import sys, os, random, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()
FULL_VARIANTS = 2
BASE, DARK, HI = rig.PALETTE["ore"], rig.PALETTE["ore_dk"], rig.PALETTE["ore_hi"]


def mix(a, b, t):
    """hex mix a->b by t"""
    pa = [int(a[i:i + 2], 16) for i in (1, 3, 5)]; pb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{int(round(x + (y - x) * t)):02X}" for x, y in zip(pa, pb))


def shade(tier, offset):
    """A rock colour for this tier. `offset` varies rock to rock WITHIN a
    tile; the tier term moves all of them together, which is the fix."""
    k = 0.30 + 0.70 * ((tier - 1) / 3.0) + offset
    if k <= 1.0:
        return mix(DARK, BASE, max(0.0, k))
    return mix(BASE, HI, min(1.0, k - 1.0))


def rock(r, s, loc, color):
    """One generic rock. There is no per-species shape any more: six species
    are rolled from a seed and cannot each have a mesh. What the old art got
    from four hand-picked silhouettes, the new art has to get from colour
    alone - which is exactly the readability question Decision #36 carries."""
    m = mat(color, rough=0.68)
    return r.rock(s, loc, m, sub=1, squash=0.58,
                  rot=(random.uniform(-0.3, 0.3), random.uniform(-0.2, 0.2),
                       random.random() * math.tau), env=False)


def glint(r, s, loc):
    m = mat("ore_hi", emit=4)
    for _ in range(random.choice([1, 2])):
        ang = random.random() * math.tau
        r.cone(s * 0.35, 0.0, s * 1.6, (loc[0] + math.cos(ang) * s * 0.3, loc[1] + math.sin(ang) * s * 0.3, s * 0.9), m,
               verts=5, rot=(random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), ang))


def tile(tier, full, seed):
    random.seed(seed)
    r = rig.Rig(samples=48)
    r.shadow_catcher()  # contact shadow only; the ground itself is NOT drawn
    if tier == 0:  # depleted: a couple of small dark scars and dead rocks
        scar = mat(mix(rig.PALETTE["ground"], "#000000", 0.35))
        for (x, y, s) in [(-0.18, 0.12, 0.17), (0.22, -0.2, 0.12)][: 2 if full else 1]:
            r.cyl(s, 0.02, (x, y, -0.005), scar, bev=0, verts=16, env=True)
        spots = [(random.uniform(-0.45, 0.45), random.uniform(-0.45, 0.45), random.uniform(0.04, 0.07)) for _ in range(3 if full else 2)]
        colors = [mix(DARK, rig.PALETTE["ground_dk"], 0.6)] * len(spots)
    else:
        # COVERAGE is half the tier ladder: a tile's mean colour is its rocks
        # against the ground showing between them, so more and bigger rock
        # moves the read as much as a lighter rock does.
        count = int((4 + tier * 3.5) * (1.0 if full else 0.45))
        smin, smax = 0.055 + tier * 0.014, 0.10 + tier * 0.022
        spots = [(random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5), random.uniform(smin, smax)) for _ in range(count)]
        colors = [shade(tier, random.choice((0.0, 0.20, -0.15))) for _ in spots]
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            random.seed(seed * 7 + 1)  # same rotations in every wrapped copy
            for (x, y, s), c in zip(spots, colors):
                rock(r, s, (x + dx, y + dy, 0.01), c)
                if tier >= 3 and (x * 7 + y * 13) % 1 < 0.15 * (tier - 2):
                    glint(r, s, (x + dx, y + dy, 0))
    r.frame(1, 1)
    return r


asset = rig.Asset("ore", out, (1, 1))
seed = 1
for tier in (1, 2, 3, 4):
    for v in range(FULL_VARIANTS):
        row = f"t{tier}_full_v{v}"
        tile(tier, True, seed).render(asset.path(row)); asset.add(row, 1); seed += 1
    row = f"t{tier}_edge"
    tile(tier, False, seed).render(asset.path(row)); asset.add(row, 1); seed += 1
for full in (True, False):
    row = f"depleted_{'full' if full else 'edge'}"
    tile(0, full, seed).render(asset.path(row)); asset.add(row, 1); seed += 1
asset.write()
