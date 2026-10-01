"""Part: the working HEAD, 1x1 tile. The end that meets the rock.

THE PIECE THAT HAS TO COMBINE (GAME.md: "modular machines must look
modular"). A head is never a tool on its own -- it is carried by a handle to
make a hand tool, or by a frame to make a machine. So the drawing has to say
"something mounts here" without being told, and it has to say it from the one
orientation we render. That is what the COLLAR is for: a band of a different
colour, a flat seat above it, and a key lug. Those three are the mount, and
they are drawn big enough to survive 32 px rather than detailed enough to
look good at 256.

SPECIES-NEUTRAL, by Maren's ruling: a world rolls six species at seed time
with generated names and sheets, so there is no species to draw. Species is
colour the client applies at runtime. Everything here is the machine palette.
Grade (C/B/A, three steps, not four) is a parameter for later and is
deliberately NOT in this file yet -- the silhouette has to work first, or
shading it is wasted work.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()

r = rig.Rig(samples=64)
r.shadow_catcher()
gun, grey, brass, steel = mat("gun"), mat("grey"), mat("brass"), rig.steel()

# IT LIES DOWN, AND THAT IS THE WHOLE DRAWING DECISION.
#
# I built this standing up first -- bit pointing at the floor, mount on top,
# "drawn the way it is used". On the contact sheet it was a grey lid on a
# dark drum. The camera is 30 degrees off VERTICAL, so a standing part shows
# the viewer its top, and the collar (r 0.30) is wider than the taper it
# mounts (r 0.26), so the collar's disc covered the entire bit. The piece
# that makes a head a head was not on screen at any size.
#
# Lying along X is what fixes it: the tilt compresses Y by cos(30) and leaves
# X alone, so the long axis laid east-west gives the full profile with no
# foreshortening at all. This is also why `items.py` reads -- its chunks lie
# on the ground, they do not stand on it.
AXIS = 0.28     # the part rests on its widest point, the collar

# THE BIT, point east. A cone rather than a wedge because a part icon has no
# facing and a cone reads the same whichever way the client happens to flip it.
# `cone(r1, r2, ...)` puts r1 at local -z, and the +90 about Y sends local +z
# east -- so the WIDE radius is r1 (it lands west, at the mount) and the point
# is r2. Writing it the other way round builds a funnel aimed at the handle.
r.cone(0.26, 0.03, 0.62, (0.16, 0, AXIS), steel, bev=0.005, rot=(0, math.pi / 2, 0))
# Two thread rings. At 32 px these stop being threads and become BANDING --
# two dark interruptions along a light taper, which is what tells a head from
# a plain spike at size. Kept to two: three closes up into a smear.
r.cyl(0.175, 0.055, (0.33, 0, AXIS), gun, bev=0.008, rot=(0, math.pi / 2, 0))
r.cyl(0.225, 0.055, (0.07, 0, AXIS), gun, bev=0.008, rot=(0, math.pi / 2, 0))

# THE MOUNT, and it is the identity of the piece: the part is a thing that
# attaches, and the drawing has to say so without a caption. Dark collar,
# light seat ring, and a bore you can see into.
r.cyl(0.30, 0.20, (-0.30, 0, AXIS), gun, bev=0.04, rot=(0, math.pi / 2, 0))
r.cyl(0.235, 0.05, (-0.17, 0, AXIS), grey, bev=0.015, rot=(0, math.pi / 2, 0))
# The bore: a dark disc recessed into the west end. A socket you can see into
# is the difference between "a part" and "a finished object".
r.cyl(0.17, 0.06, (-0.39, 0, AXIS), mat("rubber"), bev=0.01, rot=(0, math.pi / 2, 0))
# The key lug, on TOP where this camera can see it. The one asymmetric
# feature on a solid of revolution: the cheapest way to say "this seats one
# way round", and the only detail here that survives a thumbnail as a SHAPE
# rather than as shading.
r.box((0.12, 0.16, 0.1), (-0.30, 0, AXIS + 0.3), brass, bev=0.02)
for sy in (-1, 1):
    r.bolt((-0.30, sy * 0.21, AXIS + 0.2))

asset = rig.Asset("head", out, (1, 1), headroom=0.3)
r.frame(1, 1, headroom=0.3)
r.render(asset.path("idle")); asset.add("idle", 1)
asset.write()
