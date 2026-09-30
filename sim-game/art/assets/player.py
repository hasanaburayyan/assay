"""Player character: idle and walk cycles in 8 directions.

Rows are named <anim>_<dir>, dir in S, SE, E, NE, N, NW, W, SW (S faces the
camera; the order is a +45 degree turn about z each step). Rendered as a chunky engineer in an orange suit: readable at 32px,
and the colour pairs with the machines.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()
DIRS = ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]
WALK_FRAMES, IDLE_FRAMES = 8, 4

r = rig.Rig(samples=48)
r.shadow_catcher()
suit, dark, skin, visor, steel = mat("suit"), mat("gun"), mat("skin"), rig.lamp("visor"), rig.steel()

root = r.empty()
body = r.empty((0, 0, 0.78), root)
with r.group(body):
    r.box((0.46, 0.30, 0.56), (0, 0, 0), suit, bev=0.08)               # torso
    r.box((0.50, 0.10, 0.16), (0, 0, -0.18), dark, bev=0.03)            # belt
    r.box((0.34, 0.16, 0.42), (0, 0.20, 0.02), dark, bev=0.04)          # backpack
    r.cyl(0.05, 0.3, (0.12, 0.28, 0.1), steel, bev=0.01, verts=12)     # tank
    r.box((0.36, 0.36, 0.36), (0, 0, 0.46), skin, bev=0.10)             # head
    r.box((0.42, 0.42, 0.18), (0, 0, 0.60), suit, bev=0.07)             # helmet
    r.box((0.30, 0.05, 0.12), (0, -0.20, 0.47), visor, bev=0.01)        # visor
limbs = {}
for side, x in (("l", -0.32), ("r", 0.32)):
    sh = r.empty((x, 0, 0.22), body)
    with r.group(sh):
        r.box((0.17, 0.17, 0.46), (0, 0, -0.24), suit, bev=0.05)
        r.box((0.19, 0.19, 0.12), (0, 0, -0.50), dark, bev=0.03)        # glove
    hip = r.empty((x * 0.42, 0, -0.30), body)
    with r.group(hip):
        r.box((0.20, 0.20, 0.50), (0, 0, -0.25), dark, bev=0.05)
        r.box((0.22, 0.30, 0.12), (0, -0.04, -0.52), suit, bev=0.03)    # boot
    limbs[side] = (sh, hip)

asset = rig.Asset("player", out, (1, 1), headroom=1.0)
asset.anim("idle", IDLE_FRAMES, 4); asset.anim("walk", WALK_FRAMES, 12)
r.frame(1, 1, headroom=1.0)
SWING = math.radians(38)


def pose(walk_phase=None, idle_phase=None):
    if walk_phase is not None:
        sw = math.sin(walk_phase) * SWING
        limbs["l"][1].rotation_euler = (sw, 0, 0); limbs["r"][1].rotation_euler = (-sw, 0, 0)
        limbs["l"][0].rotation_euler = (-sw * 0.8, 0, 0); limbs["r"][0].rotation_euler = (sw * 0.8, 0, 0)
        body.location.z = 0.78 + 0.035 * abs(math.sin(walk_phase))
    else:
        for s in ("l", "r"):
            limbs[s][1].rotation_euler = (0, 0, 0); limbs[s][0].rotation_euler = (0, 0, 0)
        body.location.z = 0.78 + 0.015 * math.sin(idle_phase)
        limbs["l"][0].rotation_euler = (0, 0.06 * math.sin(idle_phase), 0)
        limbs["r"][0].rotation_euler = (0, -0.06 * math.sin(idle_phase), 0)


for d, name in enumerate(DIRS):
    root.rotation_euler = (0, 0, math.radians(d * 45))
    for f in range(IDLE_FRAMES):
        pose(idle_phase=2 * math.pi * f / IDLE_FRAMES)
        r.render(asset.path(f"idle_{name}", f))
    asset.add(f"idle_{name}", IDLE_FRAMES)
    for f in range(WALK_FRAMES):
        pose(walk_phase=2 * math.pi * f / WALK_FRAMES)
        r.render(asset.path(f"walk_{name}", f))
    asset.add(f"walk_{name}", WALK_FRAMES)
asset.write()
