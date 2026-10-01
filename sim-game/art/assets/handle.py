"""Part: the HANDLE -- the HELD kind of frame (note D6).

Not a fourth part kind. A frame is what carries a head, and it comes in two
kinds: held and planted. This is held, so a head on it is a pick. The sim
will have three kinds (head, frame, hopper) and four assets, and this file is
the held frame's asset.

HOW IT IS TOLD FROM THE PLANTED FRAME, and it is not hue. This is a THIN
SHAFT; `frame.py` is a CHUNKY CHASSIS on feet. At 32 px that is a one-pixel
line against a solid block, which survives greyscale and any colour-blind
simulation. The grey-against-orange is the second channel, never the only one.

Lies down, mounts at the origin, body runs WEST so the head's bit runs east
off the same join. Rules and reasons in `rig.py`.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat, LYING, PART_AXIS as AXIS

out = rig.args()


def build(g):
    """One geometry, grade as a parameter (`rig.GRADES`). Nothing about the
    SHAPE depends on `g` -- only the ink. That is the point: a part is one
    silhouette the player learns once, and grade is how good that part is."""
    r = rig.Rig(samples=64)
    r.shadow_catcher()
    gun, rubber = mat("gun"), mat("rubber")
    grey = rig.graded("grey", g)
    steel = rig.graded("steel", g, rough=0.45, metal=0.6)

    # THE FERRULE, just west of where the head's collar lands. Drawn outside
    # the collar's 0.20 of length on purpose: assembled it is the band between
    # head and shaft, and alone it is the socket that says this end takes
    # something.
    r.cyl(0.165, 0.14, (-0.19, 0, AXIS), steel, bev=0.02, rot=LYING)
    r.cyl(0.175, 0.04, (-0.26, 0, AXIS), gun, bev=0.01, rot=LYING)

    # THE SHAFT. One straight run west. Kept to r 0.115 so the silhouette
    # stays a LINE at size -- thickening it to look solid at 256 px is exactly
    # how it would stop reading against the chassis at 32.
    r.cyl(0.115, 0.62, (-0.60, 0, AXIS), grey, bev=0.02, rot=LYING)

    # THE GRIP. Two rubber bands and a butt cap: the west end has to terminate
    # in something, or an unassembled shaft reads as a pipe that was cut off.
    for x in (-0.80, -0.93):
        r.cyl(0.145, 0.09, (x, 0, AXIS), rubber, bev=0.02, rot=LYING)
    r.cyl(0.13, 0.06, (-1.0, 0, AXIS), gun, bev=0.015, rot=LYING)
    return r


asset = rig.Asset("handle", out, rig.PART_TILES, headroom=rig.PART_HEADROOM)
for g, gname in enumerate(rig.GRADES):
    r = build(g)
    r.frame(rig.PART_TILES[0], rig.PART_TILES[1], headroom=rig.PART_HEADROOM)
    r.render(asset.path(gname)); asset.add(gname, 1)
asset.write()
