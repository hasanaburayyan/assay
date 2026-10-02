"""Ore deposit tiles, 1x1 and seamless. SPECIES-NEUTRAL: the client tints.

Rows: <grade>_full_v<n> where grade is C, B or A, plus depleted_full. 7 rows,
and not one mineral name among them. A world rolls six species from its seed
(ADR 0001) and no rule, recipe or sprite may name one, so the old 56 rows of
iron / copper / coal / stone were art for a design that was withdrawn.

- grade C / B / A = the sim's purity bands, read from tuning.rs below. Higher
  grade is more rock, bigger rock, lighter rock, and grade A alone carries
  emissive crystal glints.
- depleted: pitted dark ground with a few dead rocks.

THERE IS NO EDGE TILE, AND THERE MUST NOT BE ONE (Maren, ASSA-20). This file
used to draw a sparser `_edge` row for border tiles, to soften the patch
outline. Maren read `ore.rs`: `OreDeposit` is {species, center, radius,
amount, purity}, `contains()` is a radius test on tile centres, and `amount`
is ONE number for the WHOLE patch - depletion is whole-deposit. Every tile in
a deposit is identical in the sim. There is no such thing as an edge tile.

So the 45% density step was a visible mark for a difference that does not
exist - the same mistake as the quartile ladder below, and the second invented
gradient in this one file. The square seams I spent a wake-up blaming on the
shadow catcher were that invention becoming visible; intermediate densities
would have spent renders making a lie continuous.

The hard boundary is a FEATURE. `contains()` is exactly where mining and
placing stop working, and a faded rim hides a hard rule. What ships is the
digital disc the sim describes, which already staircases at tile resolution.

IF IT EVER LOOKS STAMPED-ON, THE LEVER IS MORE ARRANGEMENT VARIANTS, NEVER
DENSITY: v0/v1 move rocks around without claiming anything about quantity.
Add v2/v3 before touching coverage again. REOPEN CONDITION, so this is not
taste: if `amount` ever goes per-tile, or depletion eats a patch from the rim
inward, the density step earns its mark back.

THE LADDER IS THE SIM'S, NOT ONE I INVENTED. This file used to split purity
1-25 / 26-50 / 51-75 / 76-100 while the sim splits it <40 / 40-69 / 70+. They
line up nowhere: there was a visible step at purity 50, where nothing
happens, and no step at 40 or 70, where every stat changes through
`effective()`. That is the grade-glint rule in rig.py inverted - a visible
mark that corresponds to no real difference - and I am the one who wrote that
rule. Maren caught it (Decision #36, ruling 3).

Removing the false step also fixed the weak-ladder finding by SUBTRACTION
rather than by pushing harder: the same visual range now spans two adjacent
steps instead of three.

FOUR RULES THIS FILE EXISTS TO HOLD, all measured in art/species_probe.py:

1. THE BASE IS LIGHT AND NEAR-NEUTRAL. The client multiplies a species
   colour over these pixels (Godot `modulate` is a per-channel MULTIPLY).
   Multiply cannot brighten, so a mid-grey base turns every species into mud,
   and a base with a hue of its own drags every species toward that hue. The
   lightness here is a budget for the tint to spend, not a look.

2. WHICH IS WHY THESE TILES ARE TRANSPARENT: ROCK ONLY, NO GROUND BAKED IN.
   They used to render opaque with the ground under them, which was fine when
   each ore kind had one fixed colour. It is a bug the moment the client
   tints, because `modulate` multiplies the WHOLE texture - the terrain
   showing between the rocks would be tinted along with the ore. Measured:
   baked in, the "neutral" base tile had a mean of (163, 172, 145) and a
   chroma of 15, which is not a neutral rock, it is grass.

3. GRADE C MAY NOT BE DARK ENOUGH TO EAT THE SPECIES MARGIN. Maren's ruling
   that purity must not DIM the tint is about the map circle, but the same
   arithmetic applies here and neither of us said so: a multiply scales
   species differences by exactly its own factor, so a darker rock is a
   smaller gap between two species. Grade C is the darkest tile and therefore
   the worst case for telling two species apart - which is why the probe now
   measures species AT GRADE C and not, as it used to, only at the middle of
   the ladder. The floor under grade C is what stops this ladder going darker.

4. SO THE LADDER LEANS ON COVERAGE. Count and size are free: they change how
   much of the tile is rock without changing how bright the rock is, so they
   move the grade read without spending any of the species margin.
"""
import sys, os, re, random, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()
FULL_VARIANTS = 2
BASE, DARK, HI = rig.PALETTE["ore"], rig.PALETTE["ore_dk"], rig.PALETTE["ore_hi"]
SIMGAME = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def grades():
    """(letter, min_purity) per grade, READ FROM THE SIM.

    Not retyped. The defect this file is fixing was art splitting purity
    where the sim does not, so a copy of those numbers living here would be
    the same bug with a newer date on it. If tuning.rs moves a boundary this
    build follows it, and if the parse ever fails the build stops rather than
    quietly falling back to numbers I made up.
    """
    src = open(os.path.join(SIMGAME, "sim", "src", "tuning.rs")).read()
    def const(name):
        m = re.search(r"pub const %s: u8 = (\d+);" % name, src)
        if not m:
            raise SystemExit("ore.py: could not read %s from sim/src/tuning.rs" % name)
        return int(m.group(1))
    return [("C", 0), ("B", const("GRADE_B_MIN_PURITY")), ("A", const("GRADE_A_MIN_PURITY"))]


GRADES = grades()


def mix(a, b, t):
    """hex mix a->b by t"""
    pa = [int(a[i:i + 2], 16) for i in (1, 3, 5)]; pb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{int(round(x + (y - x) * t)):02X}" for x, y in zip(pa, pb))


def shade(step, offset):
    """A rock colour for grade index `step` (0=C, 2=A). `offset` varies rock
    to rock WITHIN a tile; the grade term moves all of them together.

    The old version moved only ONE of three candidate shades with the ladder,
    so two rocks in three were identical at purity 5 and purity 95 - the lever
    was real but connected to a third of the rocks.

    The floor of 0.42 is rule 3: grade C has to stay light enough that two
    species are still 12 dE apart on it for every observer.
    """
    k = 0.42 + 0.58 * (step / 2.0) + offset
    if k <= 1.0:
        return mix(DARK, BASE, max(0.0, k))
    return mix(BASE, HI, min(1.0, k - 1.0))


def rock(r, s, loc, color):
    """One generic rock. There is no per-species shape any more: six species
    are rolled from a seed and cannot each have a mesh. What the old art got
    from four hand-picked silhouettes, the new art gets from colour plus the
    species initial the client draws (Decision #36 option A)."""
    m = mat(color, rough=0.68)
    return r.rock(s, loc, m, sub=1, squash=0.58,
                  rot=(random.uniform(-0.3, 0.3), random.uniform(-0.2, 0.2),
                       random.random() * math.tau), env=False)


def glint(r, s, loc):
    m = mat("ore_hi", emit=4)
    for _ in range(random.choice([1, 2])):
        ang = random.random() * math.tau
        r.cone(s * 0.35, 0.0, s * 1.6, (loc[0] + math.cos(ang) * s * 0.3, loc[1] + math.sin(ang) * s * 0.3, s * 0.9), m,
               verts=5, rot=(random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), ang))


def tile(step, seed):
    """`step` is the grade index 0..2, or -1 for depleted.

    No `full` parameter: every tile in a patch is the same tile, because every
    tile in a deposit is the same in the sim. See the header."""
    random.seed(seed)
    r = rig.Rig(samples=48)
    # Contact shadow only; the ground itself is NOT drawn.
    #
    # I took this out for a wake-up on the theory that its baked wash was
    # what drew the square seams at a deposit's border, then measured: the
    # ground inside an ore tile is about 3/255 darker than bare ground, which
    # is rock antialiasing, not a shadow wash. The seams were a DENSITY step,
    # from the `edge` row that no longer exists. Removing the catcher also
    # made both measured numbers slightly worse (grade step 8.3 -> 8.0, grade
    # C species margin 15.8 -> 14.8), so it is back. Noted rather than quietly
    # reverted, because the hypothesis was confident and wrong.
    r.shadow_catcher()
    if step < 0:  # depleted: a couple of small dark scars and dead rocks
        scar = mat(mix(rig.PALETTE["ground"], "#000000", 0.35))
        for (x, y, s) in [(-0.18, 0.12, 0.17), (0.22, -0.2, 0.12)]:
            r.cyl(s, 0.02, (x, y, -0.005), scar, bev=0, verts=16, env=True)
        spots = [(random.uniform(-0.45, 0.45), random.uniform(-0.45, 0.45), random.uniform(0.04, 0.07)) for _ in range(3)]
        colors = [mix(DARK, rig.PALETTE["ground_dk"], 0.6)] * len(spots)
    else:
        # COVERAGE DOES MOST OF THE WORK (rule 4). More and bigger rock moves
        # the grade read without darkening anything, so it costs the species
        # margin nothing - unlike value, which is spent against rule 3.
        # Grade C's floor is set by FINDABILITY, not by the ladder. At 5
        # rocks a C tile was 3.9 dE from bare ground - a deposit you cannot
        # see is one you cannot go and mine, whatever its purity. Poor ore
        # should look poor, not absent.
        count = 9 + step * 5
        smin, smax = 0.065 + step * 0.020, 0.115 + step * 0.032
        spots = [(random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5), random.uniform(smin, smax)) for _ in range(count)]
        colors = [shade(step, random.choice((0.0, 0.20, -0.15))) for _ in spots]
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            random.seed(seed * 7 + 1)  # same rotations in every wrapped copy
            for (x, y, s), c in zip(spots, colors):
                rock(r, s, (x + dx, y + dy, 0.01), c)
                # Grade A only. A glint is the rig's "this changes a number"
                # mark, and A is the top of the ladder the parts already use.
                if step == 2 and (x * 7 + y * 13) % 1 < 0.3:
                    glint(r, s, (x + dx, y + dy, 0))
    r.frame(1, 1)
    return r


asset = rig.Asset("ore", out, (1, 1))
seed = 1
for step, (letter, _min_purity) in enumerate(GRADES):
    for v in range(FULL_VARIANTS):
        row = f"{letter}_full_v{v}"
        tile(step, seed).render(asset.path(row)); asset.add(row, 1); seed += 1
row = "depleted_full"
tile(-1, seed).render(asset.path(row)); asset.add(row, 1); seed += 1
asset.write()
