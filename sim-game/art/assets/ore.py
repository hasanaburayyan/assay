"""Ore deposit tiles, 1x1 and seamless.

Rows: <kind>_t<tier>_<full|edge>[_v<n>] and <kind>_depleted_<full|edge>.
- kind: shape AND colour differ (colorblind-safe): iron = angular chunks,
  copper = hex nuggets, coal = rounded blocks, stone = smooth pebbles.
- tier 1..4 = purity 1-25 / 26-50 / 51-75 / 76-100: more, bigger, brighter,
  and from tier 3 up emissive crystal glints.
- full = tile surrounded by ore, edge = tile at the patch border (sparser,
  so the patch outline isn't a hard staircase). Same ground under both.
- depleted: pitted dark ground with a few dead rocks.
"""
import sys, os, random, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()
FULL_VARIANTS = 2


def mix(a, b, t):
    """hex mix a->b by t"""
    pa = [int(a[i:i + 2], 16) for i in (1, 3, 5)]; pb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{int(round(x + (y - x) * t)):02X}" for x, y in zip(pa, pb))


def rock(r, kind, s, loc, color):
    m = mat(color, rough=0.7 if kind != "coal" else 0.5)
    rz = random.random() * math.tau
    if kind == "iron":
        return r.rock(s, loc, m, sub=1, squash=0.6, rot=(random.uniform(-0.3, 0.3), 0, rz), env=False)
    if kind == "copper":
        return r.cyl(s * 0.95, s * 0.7, (loc[0], loc[1], s * 0.3), m, bev=s * 0.12, verts=6,
                     rot=(random.uniform(-0.25, 0.25), random.uniform(-0.25, 0.25), rz))
    if kind == "coal":
        return r.box((s * 1.6, s * 1.3, s * 0.8), (loc[0], loc[1], s * 0.35), m, bev=s * 0.3, rot=(0, 0, rz))
    return r.rock(s, loc, m, sub=2, squash=0.5, rot=(0, 0, rz), env=False)


def glint(r, kind, s, loc):
    m = mat(kind + "_hi", emit=4)
    for i in range(random.choice([1, 2])):
        ang = random.random() * math.tau
        r.cone(s * 0.35, 0.0, s * 1.6, (loc[0] + math.cos(ang) * s * 0.3, loc[1] + math.sin(ang) * s * 0.3, s * 0.9), m,
               verts=5, rot=(random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), ang))


def tile(kind, tier, full, seed):
    random.seed(seed)
    r = rig.Rig(samples=48)
    r.ground(4)
    base, dark = rig.PALETTE[kind], rig.PALETTE[kind + "_dk"]
    if tier == 0:  # depleted: a couple of small dark scars and dead rocks
        scar = mat(mix(rig.PALETTE["ground"], "#000000", 0.35))
        for (x, y, s) in [(-0.18, 0.12, 0.17), (0.22, -0.2, 0.12)][: 2 if full else 1]:
            r.cyl(s, 0.02, (x, y, -0.005), scar, bev=0, verts=16, env=True)
        spots = [(random.uniform(-0.45, 0.45), random.uniform(-0.45, 0.45), random.uniform(0.04, 0.07)) for _ in range(3 if full else 2)]
        colors = [mix(dark, rig.PALETTE["ground_dk"], 0.6)] * len(spots)
    else:
        count = int((5 + tier * 3) * (1.0 if full else 0.45))
        smin, smax = 0.06 + tier * 0.012, 0.11 + tier * 0.02
        spots = [(random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5), random.uniform(smin, smax)) for _ in range(count)]
        # low purity is dull (closer to the dark shade); high purity is the full colour
        bright = [mix(dark, base, 0.35 + 0.65 * (tier - 1) / 3), base, mix(base, dark, 0.35)]
        colors = [random.choice(bright) for _ in spots]
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            random.seed(seed * 7 + 1)  # same rotations in every wrapped copy
            for (x, y, s), c in zip(spots, colors):
                rock(r, kind, s, (x + dx, y + dy, 0.01), c)
                if tier >= 3 and (x * 7 + y * 13) % 1 < 0.15 * (tier - 2):
                    glint(r, kind, s, (x + dx, y + dy, 0))
    r.frame(1, 1)
    return r


asset = rig.Asset("ore", out, (1, 1))
seed = 1
for kind in rig.ORE_KINDS:
    for tier in (1, 2, 3, 4):
        for v in range(FULL_VARIANTS):
            row = f"{kind}_t{tier}_full_v{v}"
            tile(kind, tier, True, seed).render(asset.path(row), transparent=False); asset.add(row, 1); seed += 1
        row = f"{kind}_t{tier}_edge"
        tile(kind, tier, False, seed).render(asset.path(row), transparent=False); asset.add(row, 1); seed += 1
    for full in (True, False):
        row = f"{kind}_depleted_{'full' if full else 'edge'}"
        tile(kind, 0, full, seed).render(asset.path(row), transparent=False); asset.add(row, 1); seed += 1
asset.write()
