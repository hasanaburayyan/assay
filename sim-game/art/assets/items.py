"""Item icons, 1x1 tile, transparent. SPECIES-NEUTRAL: the client tints.

Two rows, `ore` and `refined`. It was four rows named iron / copper / coal /
stone, which is art for a withdrawn design: a world rolls six species from its
seed and an inventory can hold any of them, so a per-species icon was never
going to be renderable in the first place.

Same generic rock as the deposit tile and the same light near-neutral base,
so a chunk in the inventory is recognisably the thing on the ground once both
have been multiplied by the same species colour. See `ore.py` for why the
base is light.

`items.py` is also where loose things on the ground are drawn, which is why
these chunks LIE on the ground rather than stand on it (rig.py rule 1).

WHY `refined` IS CAST BARS AND NOT A TIDIER ROCK (ASSA-66). `refined` is the
kind the demo loop handles most -- 6 stacks of the richest pack the offline
session holds, against 22 of ore -- and it had no art at all. The two rows
share a palette, a species tint and often a species NAME in the same pack, so
colour cannot be what separates them: the whole read has to come from
silhouette. Ore is two irregular squashed spheres; refined is boxes with
straight top edges and a stacked step. At the size this is drawn, a straight
horizontal edge and a step are the only things that survive.

SIZE IT IS JUDGED AT: a pack row draws an items frame at EXACTLY 1/2. The
frame is 64x96 and `main.gd`'s `ICON_BOX_PX` is (32, 48) with
`SIZE_SHRINK_CENTER`, so `min(32/64, 48/96)` is 1/2 and every 2x2 source block
becomes one pixel (ASSA-65 made it exact; before that it was 15/32, which
sampled 30 of 64 columns unevenly). So this must read at 32x48, and the thing
it must not do is read as "ore but tidier".

THE BARS LIE DOWN AND KEEP THEIR CONTACT SHADOW. Both are the same rule as the
ore chunk: an item on the ground is on the ground. ASSA-64 took the shadow off
mounted PART sprites because a part bolted to a frame never touches the
ground; nothing in this file is a part, so nothing here changes.
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()
asset = rig.Asset("items", out, (1, 1), headroom=0.5)


def ore_row():
    """Two irregular chunks of the deposit's own rock."""
    random.seed(0)
    r = rig.Rig(samples=64)
    r.shadow_catcher()
    base, dark = mat("ore", rough=0.68), mat("ore_dk", rough=0.68)
    r.rock(0.34, (0, 0, 0.16), base, sub=1, squash=0.7, rot=(0.2, 0.1, 0.6), env=False)
    r.rock(0.18, (0.28, -0.22, 0.08), dark, sub=1, squash=0.7, rot=(0, 0, 1.2), env=False)
    return r


def refined_row():
    """Three cast bars, two down and one across them.

    EVERY CHOICE HERE IS ABOUT THE SILHOUETTE AT 1/2, because that is all the
    pack row has (see the header):

    - BOXES, NOT ROCKS. A straight top edge is the one thing ore cannot have.
    - ALL THREE PARALLEL, AND ORDERLY. The first version crossed the top bar
      over the other two at 1.17 rad, on the theory that three bars lying the
      same way merge into one slab. The crossed one did separate -- and read as
      a plank dropped on a pile, which is the opposite of what `refined` means.
      Tidiness IS the signal here. The separation problem was real but the fix
      is VALUE, below, not disorder.
    - LAID OUT IN THE PLANE, NOT PILED UP IN Z. This is rig.py rule 1 again and
      I walked into it anyway. The camera is tilted off VERTICAL, so it mostly
      sees an object's TOP: three bars stacked in Z show the top bar's face and
      a thin rim of the ones under it, and with the top bar inset and lightest
      the whole icon read as an OPEN CRATE -- a wall around a pale panel. Bars
      side by side on the ground show three full tops, which is the thing that
      actually says "bars". It is also what `items.py` already claims in its
      header: these LIE on the ground.
    - THE BANDS SEPARATE BY SHADE AS WELL AS BY A GAP. At 1/2 a gap between two
      bars of the same colour closes up -- the first version's bottom pair read
      as one slab. The gaps here are ~0.09 world units, about 3 px at 1x and
      still 1-2 after halving, and the shades alternate so the bands survive
      even where a gap does not.
    - ROUGHLY ORE'S FOOTPRINT. The first version came out 16x17 px against the
      ore chunk's 23x26 at 1/2, so the kind this game handles MOST looked like
      the minor one of the two in adjacent pack rows. Sized up to match.
    - LOW ROUGHNESS AND A LITTLE METAL, which is the cast-metal read: it puts a
      hard specular band along the top face and the chamfer, where the rock's
      0.68 scatters. Not full metal -- a metal surface has no diffuse albedo to
      multiply, so a species tint would have nothing to tint (rule: the client
      tints these by multiply, see ore.py rule 1).
    - SAME `ore` PALETTE AS THE CHUNK. Refined ore is the same material
      processed, the tint budget has to stay identical, and anything I invented
      here would be a second near-neutral light base to keep in step.
    """
    random.seed(7)
    r = rig.Rig(samples=64)
    r.shadow_catcher()
    cast = mat("ore", rough=0.30, metal=0.25)
    cast_mid = mat(rig.mix_hex(rig.PALETTE["ore"], rig.PALETTE["ore_dk"], 0.38),
                   rough=0.30, metal=0.25)
    cast_hi = mat("ore_hi", rough=0.26, metal=0.25)
    # Three bars side by side along X, ends staggered so the row is not one
    # straight edge, shades alternating so each stays its own band.
    r.box((0.58, 0.17, 0.11), (-0.04, 0.22, 0.055), cast_mid, bev=0.024)
    r.box((0.58, 0.17, 0.11), (0.03, 0.00, 0.055), cast, bev=0.024)
    r.box((0.58, 0.17, 0.11), (-0.02, -0.22, 0.055), cast_mid, bev=0.024)
    # One resting on the middle bar, pushed back so the bar underneath still
    # shows. This is the only piece carrying height, and it is what stops the
    # icon reading as a flat sticker beside the ore chunk.
    r.box((0.44, 0.16, 0.11), (0.06, 0.05, 0.165), cast_hi, bev=0.024)
    return r


for row, build in (("ore", ore_row), ("refined", refined_row)):
    r = build()
    r.frame(1, 1, headroom=0.5)
    r.render(asset.path(row))
    asset.add(row, 1)
asset.write()
