"""Spawn marker: a 3x3 landing pad with a 4-frame beacon blink."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()
FRAMES = 4

r = rig.Rig(samples=64)
r.shadow_catcher()
gun, orange, steel = mat("gun"), mat("orange"), rig.steel()

# octagonal plate with a raised rim and inset panel lines
r.cyl(1.42, 0.10, (0, 0, 0.05), gun, bev=0.03, verts=8, rot=(0, 0, math.pi / 8))
r.cyl(1.25, 0.04, (0, 0, 0.12), mat("grey"), bev=0.01, verts=8, rot=(0, 0, math.pi / 8))
for i in range(4):  # hazard chevrons pointing inward on the four sides
    a = i * math.pi / 2
    r.box((0.55, 0.08, 0.02), (1.05 * math.cos(a), 1.05 * math.sin(a), 0.15), orange, bev=0, rot=(0, 0, a + math.pi / 2))
    r.box((0.35, 0.08, 0.02), (0.85 * math.cos(a), 0.85 * math.sin(a), 0.15), orange, bev=0, rot=(0, 0, a + math.pi / 2))
r.cyl(0.45, 0.02, (0, 0, 0.15), orange, bev=0, verts=48)          # centre ring
r.cyl(0.36, 0.02, (0, 0, 0.16), mat("grey"), bev=0, verts=48)
lamps = []
for i in range(4):  # corner beacons
    a = i * math.pi / 2 + math.pi / 4
    x, y = 1.15 * math.cos(a), 1.15 * math.sin(a)
    r.cyl(0.12, 0.22, (x, y, 0.21), steel, bev=0.02, verts=16)
    lamps.append(r.cyl(0.08, 0.06, (x, y, 0.34), rig.lamp("cyan"), bev=0, verts=16))
off = mat("iron_dk")

asset = rig.Asset("spawn", out, (3, 3), headroom=0.25)
asset.anim("blink", FRAMES, 4)
r.frame(3, 3, headroom=0.25)
for f in range(FRAMES):
    for i, l in enumerate(lamps):
        l.data.materials[0] = rig.lamp("cyan") if (i + f) % 2 == 0 else off
    r.render(asset.path("pad", f))
asset.add("pad", FRAMES)
asset.write()
