"""Ground tiles: a few seamless 1x1 variants so a big map doesn't repeat."""
import sys, os, random
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig

out = rig.args()
VARIANTS = 4


def wrapped_rocks(r, spots, color, squash=0.4):
    """Rocks inside the unit tile, duplicated to the 8 neighbours so the tile
    wraps seamlessly (shadows and side faces cross the edge)."""
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for (x, y, s) in spots:
                r.rock(s, (x + dx, y + dy, 0.005), rig.mat(color), squash=squash)


asset = rig.Asset("ground", out, (1, 1))
for v in range(VARIANTS):
    r = rig.Rig(samples=48, outlines=False)
    r.ground(4)
    random.seed(200 + v)
    count = random.choice([2, 3, 3, 5])
    spots = [(random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5), random.uniform(0.035, 0.08)) for _ in range(count)]
    wrapped_rocks(r, spots, "ground_dk")
    r.frame(1, 1)
    r.render(asset.path(f"v{v}"), transparent=False)
    asset.add(f"v{v}", 1)
asset.write()
