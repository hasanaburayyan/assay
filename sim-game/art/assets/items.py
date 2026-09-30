"""Item icons: one chunk of each ore, 1x1 tile, transparent. Same shapes as
the deposit tiles so an inventory icon matches what's on the ground."""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()
asset = rig.Asset("items", out, (1, 1), headroom=0.5)
for kind in rig.ORE_KINDS:
    random.seed(rig.ORE_KINDS.index(kind))
    r = rig.Rig(samples=64)
    r.shadow_catcher()
    base, dark = mat(kind), mat(kind + "_dk")
    if kind == "iron":
        r.rock(0.34, (0, 0, 0.16), base, sub=1, squash=0.7, rot=(0.2, 0.1, 0.6), env=False)
        r.rock(0.18, (0.28, -0.22, 0.08), dark, sub=1, squash=0.7, rot=(0, 0, 1.2), env=False)
    elif kind == "copper":
        r.cyl(0.32, 0.26, (0, 0, 0.13), base, bev=0.05, verts=6, rot=(0, 0, 0.3))
        r.cyl(0.18, 0.2, (0.3, -0.24, 0.1), dark, bev=0.03, verts=6, rot=(0.2, 0, 1.0))
    elif kind == "coal":
        r.box((0.5, 0.42, 0.3), (0, 0, 0.15), mat("coal", rough=0.45), bev=0.09, rot=(0, 0, 0.4))
        r.box((0.26, 0.22, 0.18), (0.3, -0.24, 0.09), dark, bev=0.06, rot=(0, 0, 1.1))
    else:
        r.rock(0.34, (0, 0, 0.15), base, sub=2, squash=0.6, rot=(0, 0, 0.5), env=False)
        r.rock(0.17, (0.3, -0.22, 0.08), dark, sub=2, squash=0.6, rot=(0, 0, 2.0), env=False)
    r.frame(1, 1, headroom=0.5)
    r.render(asset.path(kind)); asset.add(kind, 1)
asset.write()
