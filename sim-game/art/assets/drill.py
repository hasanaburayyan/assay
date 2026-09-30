"""Mining drill, 2x2 tiles. Rows: idle (1 frame) and work (8 frames, the
collar turns and the lamp pulses)."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()
WORK_FRAMES = 8

r = rig.Rig(samples=64)
r.shadow_catcher()
orange, orange_dk, gun, grey, brass, steel = mat("orange"), mat("orange_dk"), mat("gun"), mat("grey"), mat("brass"), rig.steel()

# chassis: heavy rounded frame on four feet, darker inner plate
r.box((1.9, 1.9, 0.3), (0, 0, 0.15), orange, bev=0.12)
r.box((1.5, 1.5, 0.06), (0, 0, 0.31), gun, bev=0.02)
for sx in (-1, 1):
    for sy in (-1, 1):
        r.cyl(0.17, 0.5, (sx * 0.78, sy * 0.78, 0.25), gun, bev=0.03, verts=24)
        r.cyl(0.08, 0.06, (sx * 0.78, sy * 0.78, 0.52), steel, bev=0.01, verts=12)
# drill column, the hero element
r.cyl(0.66, 0.36, (0, 0, 0.5), grey, bev=0.05)
r.cyl(0.56, 0.12, (0, 0, 0.72), gun, bev=0.02)
collar = r.empty((0, 0, 0.85))
with r.group(collar):
    r.cyl(0.44, 0.22, (0, 0, 0), orange_dk, bev=0.03)
    for i in range(6):
        a = i * math.pi / 3
        r.box((0.16, 0.08, 0.16), (0.5 * math.cos(a), 0.5 * math.sin(a), 0.01), brass, bev=0.015, rot=(0, 0, a))
    # bit: a sharp cone with two thread rings
    r.cone(0.30, 0.02, 0.8, (0, 0, 0.5), steel, bev=0.005)
    r.cyl(0.25, 0.05, (0, 0, 0.32), gun, bev=0.005)
    r.cyl(0.17, 0.05, (0, 0, 0.55), gun, bev=0.005)
# motor block along the back edge, with fins and a lamp
r.box((1.5, 0.42, 0.5), (0, 0.72, 0.55), gun, bev=0.06)
for i in range(5):
    r.box((0.06, 0.34, 0.34), (-0.5 + i * 0.25, 0.72, 0.7), orange, bev=0.01)
lamp = r.cyl(0.1, 0.06, (0.62, 0.72, 0.83), rig.lamp("cyan"), bev=0, verts=24)
# output chute on the east side, pokes past the frame
r.box((0.5, 0.36, 0.22), (0.9, -0.25, 0.42), steel, bev=0.03)
r.box((0.3, 0.3, 0.16), (1.05, -0.25, 0.36), gun, bev=0.02)
# hydraulic struts from the motor block to the ring
for sx in (-1, 1):
    r.pipe((sx * 0.45, 0.55, 0.7), (sx * 0.3, 0.35, 0.75), 0.06, steel, flanges=False)

asset = rig.Asset("drill", out, (2, 2), headroom=1.0)
asset.anim("work", WORK_FRAMES, 12)
r.frame(2, 2, headroom=1.0)
lamp.data.materials[0] = mat("iron_dk")
r.render(asset.path("idle")); asset.add("idle", 1)
for f in range(WORK_FRAMES):
    collar.rotation_euler = (0, 0, (math.pi / 3) * f / WORK_FRAMES)   # one tooth pitch per loop
    lamp.data.materials[0] = rig.lamp("cyan") if f % 4 < 2 else mat("cyan", emit=1.5)
    r.render(asset.path("work", f))
asset.add("work", WORK_FRAMES)
asset.write()
