"""Part: the HOPPER. Optional on a planted frame; what the ore falls into.

Third of the three part kinds (note D6: head, frame, hopper). Optional means
the drill has to read as a drill without it, so this piece may add nothing
load-bearing to the silhouette -- it is allowed to be the thing you notice
second.

ITS JOB AT 32 PX IS TO BE A CONTAINER, and a container is an OPEN shape. Every
other part in the set is solid: a taper, a shaft, a block on feet. So the
hopper is the only piece with a hole in it, which is a silhouette difference
rather than a colour one and is the whole reason it can sit on the frame's
deck without reading as more chassis.

Sits WEST of the join, on the deck `frame.py` keeps flat for it. It does not
straddle the origin -- a hopper mounts to the frame, not to the head -- but
it is authored in the same frame and at the same scale, so it composes by
being overlaid like everything else.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()

CX, DECK = -0.60, 0.47     # centred on the frame's deck, standing on its plate


def build(g):
    """One geometry, grade as a parameter (`rig.GRADES`). Shape never varies."""
    r = rig.Rig(samples=64)
    r.shadow_catcher()
    gun = mat("gun")
    steel = rig.graded("steel", g, rough=0.45, metal=0.6)
    brass = rig.graded_accent("brass", g)

    # THE MOUTH: a wide, shallow, OPEN funnel. Built as four leaning walls
    # rather than a cone so the opening stays a hard-edged quadrilateral at
    # size -- a round mouth downsamples into a blob, and a blob is just
    # another solid.
    for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        r.box((0.055 if sx else 0.62, 0.62 if sx else 0.055, 0.42),
              (CX + sx * 0.28, sy * 0.28, DECK + 0.21), steel,
              bev=0.02, rot=(sy * 0.32, -sx * 0.32, 0))
    # The dark interior. This is the piece doing the work at 1x: a shadowed
    # well inside a light rim is what says "open" when the walls are two
    # pixels thick.
    r.box((0.44, 0.44, 0.06), (CX, 0, DECK + 0.07), mat("rubber"), bev=0.01)

    # THE THROAT below the mouth, down to the deck: narrow, dark and square so
    # the piece reads as mouth-over-neck rather than as one tapered lump.
    r.box((0.34, 0.34, 0.2), (CX, 0, DECK - 0.07), gun, bev=0.03)
    # A brass band at the throat, the same mark the head wears at its collar:
    # one warm accent per part, in the place the part attaches -- and so the
    # same place grade glints.
    r.box((0.38, 0.38, 0.05), (CX, 0, DECK - 0.16), brass, bev=0.01)
    return r


asset = rig.Asset("hopper", out, rig.PART_TILES, headroom=rig.PART_HEADROOM)
for g, gname in enumerate(rig.GRADES):
    r = build(g)
    r.frame(rig.PART_TILES[0], rig.PART_TILES[1], headroom=rig.PART_HEADROOM)
    r.render(asset.path(gname)); asset.add(gname, 1)
asset.write()
