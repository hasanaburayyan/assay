"""Part: the HEAD. The end that meets the rock.

One of three part kinds the demo assembles (note D6: head, frame in its two
kinds, hopper). A head is never a tool on its own -- a held frame makes it a
pick, a planted frame with hoppers makes it a drill -- so the drawing has to
say "something mounts here" from the one orientation we render. That is the
COLLAR: a dark band straddling the join, a light seat, and a brass key lug.
Those three are the mount, drawn big enough to survive 32 px rather than
detailed enough to look good at 256.

Lies down and mounts at the origin; both rules and their reasons are in
`rig.py`. The bit runs east from the join, so a frame coming west meets it.

SPECIES-NEUTRAL by Maren's ruling: a world rolls six species at seed time
with generated names and sheets, so there is no species to draw -- species is
colour the client applies at runtime. Grade (C/B/A, three steps, not the four
purity tiers, which are about deposits) is a parameter for later and is
deliberately absent: the silhouette has to work in both combinations first,
or shading it is wasted work.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat, LYING

out = rig.args()
AXIS = 0.28     # the part rests on its widest point, the collar


def build(g):
    """One geometry, grade as a parameter (rig.GRADES). Nothing about the
    SHAPE depends on `g` -- only the ink -- which is the point: a part is one
    silhouette the player learns once, and grade is how good that part is."""
    r = rig.Rig(samples=64)
    # NO SHADOW CATCHER -- A BOUNCE PLANE INSTEAD, AND THAT IS THE DRAWING
    # SAYING SOMETHING (ASSA-64,
    # Maren's ruling). A contact shadow means "this part stands on the
    # ground". A head never does: in sim it is a MOUNTED part, it only ever
    # exists bolted to a frame, and `Design { frame, mounted }` enforces that
    # by type. It carried one anyway -- measured, 2473 shadow pixels per grade
    # frame against the planted frame's 1718, so the one part that really
    # stands on the ground had the LEAST shadow of the four. With this gone,
    # every machine has exactly one contact shadow by construction, which is
    # what makes a client's plain `over` correct rather than approximate.
    r.bounce()
    gun, grey = mat("gun"), rig.graded("grey", g)
    steel = rig.graded("steel", g, rough=0.45, metal=0.6)

# THE MOUNT, straddling the join at x=0. It is the identity of the piece:
# a part is a thing that attaches, and the drawing says so without a caption.
    r.cyl(0.30, 0.20, (0.0, 0, AXIS), gun, bev=0.04, rot=LYING)
    r.cyl(0.235, 0.05, (0.13, 0, AXIS), grey, bev=0.015, rot=LYING)
# The key lug, on TOP where this camera can see it. The one asymmetric
# feature on a solid of revolution: the cheapest way to say "this seats one
# way round", and the only detail here that survives a thumbnail as a SHAPE
# rather than as shading.
    r.box((0.12, 0.16, 0.1), (0.0, 0, AXIS + 0.3), rig.graded_accent("brass", g), bev=0.02)
    for sy in (-1, 1):
        r.bolt((0.0, sy * 0.21, AXIS + 0.2))

# THE BIT, running east off the join. A cone rather than a wedge because a
# part icon has no facing and a cone reads the same whichever way the client
# flips it. `cone(r1, r2, ...)` puts r1 at local -z, which LYING sends WEST,
# so the wide radius is r1; written the other way it is a funnel aimed at the
# handle.
    r.cone(0.26, 0.03, 0.62, (0.46, 0, AXIS), steel, bev=0.005, rot=LYING)
# Two thread rings. At 32 px these stop being threads and become BANDING --
# dark interruptions along a light taper, which is what tells a head from a
# plain spike at size. Two, not three: three closes up into a smear.
    r.cyl(0.225, 0.055, (0.37, 0, AXIS), gun, bev=0.008, rot=LYING)
    r.cyl(0.175, 0.055, (0.63, 0, AXIS), gun, bev=0.008, rot=LYING)
    return r


asset = rig.Asset("head", out, rig.PART_TILES, headroom=rig.PART_HEADROOM)
for g, name in enumerate(rig.GRADES):
    r = build(g)
    r.frame(rig.PART_TILES[0], rig.PART_TILES[1], headroom=rig.PART_HEADROOM)
    r.render(asset.path(name)); asset.add(name, 1)
asset.write()
