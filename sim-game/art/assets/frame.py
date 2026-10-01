"""Part: the FRAME -- the PLANTED kind (note D6).

The other kind of frame. A head on this is a drill: it stands on the ground
and works on its own, where the held frame is swung by a player. Hoppers bolt
to it, which is why its deck is flat and clear.

HOW IT IS TOLD FROM THE HANDLE, and it is not hue. This is a CHUNKY CHASSIS
on four feet; `handle.py` is a thin shaft. At 32 px that is a solid block
against a one-pixel line -- it survives greyscale and colour-blind
simulation on shape alone. Orange is the second channel, and it is also what
says "machine" in this palette: the drill chassis and the player suit are the
same orange, and nothing a player carries by hand is.

Lies along X, mounts at the origin, body runs WEST. Rules in `rig.py`.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat, LYING, PART_AXIS as AXIS

out = rig.args()

r = rig.Rig(samples=64)
r.shadow_catcher()
orange, orange_dk, gun, steel = mat("orange"), mat("orange_dk"), mat("gun"), rig.steel()

# THE YOKE at the join: a collar-sized cradle the head's mount drops into.
# Sized to read just proud of the head's 0.30 collar when assembled, so the
# join looks like a join and not like the head floating on a box.
r.cyl(0.33, 0.16, (-0.17, 0, AXIS), orange_dk, bev=0.03, rot=LYING)
for sy in (-1, 1):
    r.box((0.12, 0.1, 0.5), (-0.17, sy * 0.3, AXIS - 0.06), orange, bev=0.03)

# THE DECK: a flat chassis running west. Flat on top ON PURPOSE -- a hopper
# bolts down here, and a domed or cluttered deck would make every hopper look
# like it had landed on the machine rather than been fitted to it.
r.box((0.86, 0.72, 0.26), (-0.60, 0, 0.30), orange, bev=0.06)
r.box((0.66, 0.52, 0.05), (-0.60, 0, 0.44), gun, bev=0.02)

# FOUR FEET. The whole of "planted" is carried by these: a thing with feet is
# standing, a thing without is being held. They also lift the deck clear of
# the ground so the shadow reads as a gap.
for sx in (-1, 1):
    for sy in (-1, 1):
        r.cyl(0.085, 0.3, (-0.60 + sx * 0.3, sy * 0.26, 0.15), gun, bev=0.02, verts=20)
        r.cyl(0.11, 0.05, (-0.60 + sx * 0.3, sy * 0.26, 0.02), steel, bev=0.01, verts=16)

# A strut from deck to yoke, so the two masses read as one machine.
r.pipe((-0.34, 0.2, 0.44), (-0.22, 0.12, AXIS + 0.1), 0.05, steel, flanges=False)
r.pipe((-0.34, -0.2, 0.44), (-0.22, -0.12, AXIS + 0.1), 0.05, steel, flanges=False)

asset = rig.Asset("frame", out, rig.PART_TILES, headroom=rig.PART_HEADROOM)
r.frame(rig.PART_TILES[0], rig.PART_TILES[1], headroom=rig.PART_HEADROOM)
r.render(asset.path("idle")); asset.add("idle", 1)
asset.write()
