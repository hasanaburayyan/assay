"""Ground tiles: seamless 1x1 variants with real value structure. (ASSA-115)

WHAT WAS WRONG, MEASURED BY MAREN AND NOT BY ME. The tile was one flat plane with
two to five tiny dark pebbles on it. Inside a tile, luminance ran p5 145.2 to p95
145.5 out of 255 -- no structure at all -- and the four variants differed in
10-19% of their pixels at a MEAN ABSOLUTE CHANNEL DIFFERENCE OF 0.9 TO 1.7. At
32 px they were the same image, four times. The board called the demo felt and
candy; this file is the felt, and it is 100% of the frame.

THREE LAYERS, AND EACH ONE IS A DIFFERENT SPATIAL FREQUENCY, because that is what
"ground" is made of and what a flat plane cannot have:

  1. PATCHES -- 5 very flat discs, radius 0.12-0.26 of a tile, two light and three
     dark. Eight at a wider light step read as CAMOUFLAGE at 32 px: every tile a busy
     cell with no quiet ground in it, and the eye finds the repeat in four variants
     immediately. Ground is mottled, not patterned, and most of it is quiet. At 32 px/tile these are 4-8 px across: the scale a player reads as "this
     bit of ground is drier than that bit". They are nearly flat (squash 0.03) ON
     PURPOSE -- they are COLOUR, not relief, and a patch with height would read as a
     boulder.
  2. GRIT -- 18 small rocks, radius 0.035-0.075, squash 0.4, with real height.
     These are the ones the sun catches: at a 9-degree key, a 2 px bump makes a
     1 px shadow, and that is the grain. One or two pixels is all a 32 px tile
     has room for.
  3. SPECKS -- 12 tiny dark points, radius 0.015-0.03. Below the resample they
     do not survive as objects; they survive as dither, which is what stops the
     patches from banding into flat zones of their own.

SEAMLESS, AND NOW ACTUALLY SEAMLESS. Every piece is drawn nine times, once per
neighbouring tile, so anything crossing an edge arrives from the other side --
shadows and side faces included. THE OLD VERSION PASSED NO ROTATION, so `rock()`
rolled a fresh random one for each of the nine copies: a pebble leaving the east
edge came back at the west edge as a DIFFERENT pebble. It never showed because
the pebbles were two pixels wide. It would have shown the moment anything here
got bigger, which is exactly what this change does, so the rotation is now drawn
once per spot and passed to all nine.

VARIANTS DIFFER BY LAYOUT, NEVER BY TONE. Four tiles of the same ground, not four
grounds: same three pigments, same counts drawn from the same distribution, a
different arrangement each time. A player must never be able to point at a tile
and say that one is lighter -- that would read as terrain the sim does not have.

WHAT IT MAY NOT DO. Ore owns saturation (rig.py rule 6) and ore has to stay
FINDABLE on this: my own floor is 3.9 dE between the quietest deposit and the
ground it sits on. A ground with a wide value spread can eat that, so the spread
here is in LUMINANCE and the chroma stays where it was -- and the number is
re-measured against the real ore sheet rather than assumed. See the item.
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig

out = rig.args()
# SIX, NOT FOUR. The anti-repeat lever `ore.py` already prescribes for its own grid is
# MORE ARRANGEMENTS, never more density, and the ground is the surface a player scans
# most. Two extra rows cost two renders; the client picks v[hash % len(rows)] and does
# not care how many there are.
VARIANTS = 6


def wrapped(r, spots, squash, z=0.004):
    """Draw every spot in all nine tiles, so the tile wraps.

    `spots` are (x, y, radius, colour, rotation). The ROTATION IS THE CALLER'S,
    not `rock()`'s own random one: nine copies of one pebble have to be one
    pebble, or the tile is only seamless in its colours and not in its shapes.
    """
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for (x, y, s, color, rot) in spots:
                r.rock(s, (x + dx, y + dy, z), rig.mat(color), squash=squash, rot=rot)


def softened(spots, tones):
    """A light patch, redrawn as concentric discs so it has no hard edge.

    BOX 11 ASKS FOR THREE THINGS AND I DELIVERED ONE OF THEM TWICE. "Softer, larger,
    lighter": a bigger disc at a bigger tone step is lighter and larger and HARDER, and
    both renders of that read as camouflage at 32 px -- every tile its own cell, the
    32 px lattice easier to find than before, not harder. Pictures, not an opinion:
    `/tmp/cove-115-field*.png`.

    So the step is spread over radius instead of being spent at one edge. Each light
    patch becomes len(`tones`) discs on one centre and one rotation, the widest in the
    gentlest tone, and the sprite is drawn at 64 px for a 32 px display, so a three-step
    ramp over ~8 px of radius is about a pixel a step once it lands. A patch with a
    gradient is a patch of ground; a patch with an edge is an object.

    Each ring sits a hair above the last because they are coplanar otherwise and
    z-fighting is not a soft edge.
    """
    out = []
    for (x, y, s, color, rot) in spots:
        if color != "ground_lt":
            out.append([(x, y, s, color, rot)])
            continue
        out.append([(x, y, s * scale, tone, rot)
                    for scale, tone in zip((1.0, 0.72, 0.45), tones)])
    return out


def scatter(n, rmin, rmax, light):
    """n spots at random places in the unit tile, each with its own fixed rotation.

    THE TONE BUDGET IS FIXED AND ONLY THE ARRANGEMENT IS RANDOM: exactly `light` of
    the n spots are the light tone, the rest dark. Drawing the colour per spot with
    `random.choice` is what the first render did, and the four variants came out with
    medians 126.8, 126.8, 158.7 and 144.8 -- a player could point at a tile and say
    that one is lighter, which reads as terrain the sim does not have.
    """
    cols = ["ground_lt"] * light + ["ground_dk"] * (n - light)
    random.shuffle(cols)
    return [(random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5),
             random.uniform(rmin, rmax), c, (0, 0, random.random() * math.tau))
            for c in cols]


asset = rig.Asset("ground", out, (1, 1))
for v in range(VARIANTS):
    r = rig.Rig(samples=48, outlines=False)
    r.ground(4)
    random.seed(200 + v)
    # 1. PATCHES: colour at the size a player sees, laid flat. Eight, three of them
    # light: the first render used 9-13 at up to r 0.34 with a free light/dark roll and
    # came out as camouflage -- near half the tile in the light tone, every tile reading
    # as its own cell. Ground is mottled, not patterned.
    # SOFTER, LARGER, LIGHTER (box 11), in that order of importance. Radius 0.12-0.26 ->
    # 0.14-0.30 (9-19 px across at 32 px/tile), the light tone is a real +14 step instead
    # of +1.9, and the step is spread over three concentric discs so the patch has no
    # edge -- see `softened`. The COUNT stays at five with two light: the camouflage
    # failure recorded above was eight patches at a wide step, and 0.16-0.36 at a hard
    # edge reproduced it exactly. A tile has to stay mostly quiet.
    rings = softened(scatter(5, 0.14, 0.30, light=2),
                     ("ground_lt1", "ground_lt2", "ground_lt"))
    for i in range(3):
        wrapped(r, [spot[i] for spot in rings if len(spot) > i], squash=0.03,
                z=0.004 + 0.0002 * i)
    # 2. GRIT: the layer with height, so the key light has something to catch.
    wrapped(r, scatter(18, 0.035, 0.075, light=4), squash=0.4)
    # 3. SPECKS: dither under the patches.
    wrapped(r, scatter(12, 0.015, 0.03, light=0), squash=0.5)
    r.frame(1, 1)
    r.render(asset.path(f"v{v}"), transparent=False)
    asset.add(f"v{v}", 1)
asset.write()
