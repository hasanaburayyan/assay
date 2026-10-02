"""Item icons, 1x1 tile, transparent. SPECIES-NEUTRAL: the client tints.

One row, `ore`. It was four rows named iron / copper / coal / stone, which is
art for a withdrawn design: a world rolls six species from its seed and an
inventory can hold any of them, so a per-species icon was never going to be
renderable in the first place.

Same generic rock as the deposit tile and the same light near-neutral base,
so a chunk in the inventory is recognisably the thing on the ground once both
have been multiplied by the same species colour. See `ore.py` for why the
base is light.

`items.py` is also where loose things on the ground are drawn, which is why
these chunks LIE on the ground rather than stand on it (rig.py rule 1).
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()
asset = rig.Asset("items", out, (1, 1), headroom=0.5)

random.seed(0)
r = rig.Rig(samples=64)
r.shadow_catcher()
base, dark = mat("ore", rough=0.68), mat("ore_dk", rough=0.68)
r.rock(0.34, (0, 0, 0.16), base, sub=1, squash=0.7, rot=(0.2, 0.1, 0.6), env=False)
r.rock(0.18, (0.28, -0.22, 0.08), dark, sub=1, squash=0.7, rot=(0, 0, 1.2), env=False)
r.frame(1, 1, headroom=0.5)
r.render(asset.path("ore")); asset.add("ore", 1)
asset.write()
