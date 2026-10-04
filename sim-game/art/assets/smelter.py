"""A planted smelter, 2x2, in the world. Two rows: `cold` and `lit`.

WHY IT IS ITS OWN SPRITE AND NOT A COMPOSITE (Maren, ASSA-126). `sim`'s
`BuildingKind` has two arms and only `Machine` holds an `Assembly`;
`BuildingKind::Smelter` is slots (`input`, `fuel`, `burn_left`,
`burn_temperature`, `output`, `progress`) and the building's material is a
single `Item` on `Building.material`. There is nothing to composite. It is
also not `items.png`'s pack icon stretched: that is a 64x96 HELD object on a
32px anchor, and a planted smelter's footprint is (2, 2) = 64x64 on screen.

TWO ROWS, NOT SIX, AND THAT IS A SIM FACT RATHER THAN A SAVING. The brief
said the tint should carry "species and grade like every other surface". Ore
carries grade in its ROW, not its tint -- and a smelter's grade changes
nothing the sim will ever read:

    world.rs::max_temperature  ->  self.species(b.material.species)
                                       .sheet.heat_tolerance

It takes the species' RAW heat tolerance. Not `effective()`, which is the
only place grade is ever applied, and which could not help anyway:
`Property::scales_with_grade` is `!matches!(self, Density | HeatTolerance)`.
So the walls of a grade-A smelter cap the fire at exactly the temperature a
grade-C one does. A grade ladder here would be a visible mark for a
difference that does not exist -- rig rule 6 inverted, the same defect as
`ore.py`'s old step at purity 50 and the `_edge` tile Maren killed in
ASSA-26. If grade ever starts scaling heat tolerance, this file owes the
player three rows; today it owes them two. (Flagged to Maren; her box says
"species and grade", and I have not quietly reworded it.)

THE LIT READ IS A HEARTH, NOT A FLAME, AND THAT IS ARITHMETIC. The client
tints with Godot `modulate`, a per-channel MULTIPLY, so every luminance
RATIO inside this sprite survives the tint unchanged -- which cuts both
ways. The walls are `ore` (#CCC8C2), light on purpose because the lightness
is the budget a multiply spends (`ore.py` rule 1). The brightest a pixel can
ever be is white. So:

    white fire / ore wall = 1.26 to 1.28 for EVERY ONE OF THE SIX TINTS

A fire can never out-shine these walls by more than a quarter, in any
species, however hot it is drawn. Measured before rendering anything
(`/tmp/cove-126-ceiling.py`). What IS available is the hole it sits in:

    fire / cold hearth = 8.7x, in every tint, for the same reason

So the signal is a DARK HEARTH THAT BECOMES A BRIGHT ONE, read against
itself and against the near-black mouth beside it -- not a flame read
against the walls. The hearth is therefore large and the walls are thick
enough to frame it rather than compete with it.

CONSEQUENCE WORTH KNOWING: under `#3333FF` and `#7A29CC` the whole smelter
is darker than the ground it stands on (fire ceiling 74 and 84 against the
ground's 136.5). That is fine -- it reads as a dark block on olive, and the
hearth still reads inside it -- but nothing drawn here can be made to glow
"brightly" for those two species, and no amount of emission changes it.

IT STANDS ON THE GROUND, so it carries a contact shadow (rig rule: a shadow
means it stands on the ground). A planted smelter is the one building that
unambiguously does.

NOT DRAWN, deliberately: smoke, damage, animation, and any separate mark for
`OutputFull` / `NoFuel` / `FireTooCool`. Maren ruled lit-versus-not is the
field-scale read and the individual stalls belong on the panel and in the
log, where they already are.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()

# The footprint is 2x2 tiles = 2.0 world units. The shell stops short of the
# edge so a smelter beside a smelter does not weld into one slab: the sim
# lets you plant them adjacent, and two of these sharing a wall would read as
# one four-tile building.
OUTER = 0.86          # half-width of the shell
WALL = 0.26           # wall thickness
HEIGHT = 0.42         # wall height; low enough that the hearth stays visible
HEARTH = OUTER - WALL  # half-width of the opening in plan

r = rig.Rig(samples=64)
r.shadow_catcher()

# THE WALLS ARE NOT `ore_hi`, AND THAT IS PART 2'S LESSON ARRIVING ON TIME.
# My first version capped the walls with `ore_hi` (#F6F2EA) for a light step
# and `check_headroom.py` went red on the COLD row at 4.2% blown -- a cold
# smelter sitting on the ceiling, which is ASSA-115's defect in a brand new
# asset. The printable top of this rig is about albedo 183; `ore_hi` is 246
# and `ore.py` only ever reaches it through `shade()` at the very top of the
# ladder or as an emissive glint. So the cap is `ore` and the body is pulled
# DOWN to make the step, rather than the cap pushed up past the ceiling.
body = mat(rig.mix_hex("ore", "ore_dk", 0.40), rough=0.72)
rim = mat("ore", rough=0.6)
dark = mat("ore_dk", rough=0.8)
cold = mat("line", rough=0.9)

# THE SLAB the walls stand on, a hair proud of the ground so the shell is one
# object rather than four walls dropped on grass.
r.box((OUTER * 2, OUTER * 2, 0.08), (0, 0, 0.04), dark, bev=0.03)

# THE SHELL: four walls, with the SOUTH one split to leave a mouth. South is
# toward the camera (rig rule 1: the camera is tilted off vertical and mostly
# sees an object's top), so the mouth is the face a player actually sees.
MOUTH = 0.40          # half-width of the gap in the south wall
for side in ("n", "e", "w"):
    if side == "n":
        r.box((OUTER * 2, WALL, HEIGHT), (0, OUTER - WALL / 2, 0.08 + HEIGHT / 2), body, bev=0.05)
    else:
        x = (OUTER - WALL / 2) * (1 if side == "e" else -1)
        r.box((WALL, (OUTER - WALL) * 2, HEIGHT), (x, 0, 0.08 + HEIGHT / 2), body, bev=0.05)
for sign in (-1, 1):   # the two cheeks of the south wall, mouth between them
    w = OUTER - MOUTH
    r.box((w, WALL, HEIGHT), (sign * (OUTER - w / 2), -(OUTER - WALL / 2), 0.08 + HEIGHT / 2),
          body, bev=0.05)

# A LIGHT CAP on the wall tops. The camera sees tops, so this is the surface
# that says "thick wall" rather than "line drawing of a square".
for side in ("n", "e", "w"):
    if side == "n":
        r.box((OUTER * 2, WALL, 0.05), (0, OUTER - WALL / 2, 0.08 + HEIGHT), rim, bev=0.015)
    else:
        x = (OUTER - WALL / 2) * (1 if side == "e" else -1)
        r.box((WALL, (OUTER - WALL) * 2, 0.05), (x, 0, 0.08 + HEIGHT), rim, bev=0.015)
for sign in (-1, 1):
    w = OUTER - MOUTH
    r.box((w, WALL, 0.05), (sign * (OUTER - w / 2), -(OUTER - WALL / 2), 0.08 + HEIGHT), rim, bev=0.015)

# THE HEARTH: the floor inside the shell. A floor and not a hole, for
# `items.py`'s reason -- left open it would show bare ground through the
# middle and read as a frame around the terrain rather than as a vessel with
# something in it.
r.box((HEARTH * 2, HEARTH * 2, 0.04), (0, 0, 0.10), dark, bev=0.01)

# THE FUEL BED, and this is the part that changes between the two rows.
#
# MY FIRST VERSION LIT THE WHOLE HEARTH FLOOR and I rendered it before
# believing it: at 32px/tile it read as a flat bright square, a UI swatch
# rather than a fire, and every species turned the smelter into one pastel
# block. The lift was there in the numbers and the picture was wrong, which
# is the only reason this file has a second version.
#
# Lumps instead. The dark floor stays visible BETWEEN them in both states, so
# the lit read is "the dark hole has embers in it" rather than "the hole
# changed colour" -- and the 8x hearth-to-fire ratio is measured against
# cold hearth still on screen beside it, not against a remembered frame.
random = __import__("random")
random.seed(7)
coals = []
for _ in range(9):
    x = random.uniform(-HEARTH + 0.14, HEARTH - 0.14)
    y = random.uniform(-HEARTH + 0.14, HEARTH - 0.14)
    s = random.uniform(0.10, 0.17)
    coals.append(r.rock(s, (x, y, 0.12), cold, sub=1, squash=0.5,
                        rot=(0, 0, random.random() * math.tau), env=False))

# A LIP across the mouth so the opening is a mouth rather than a missing
# wall: the hearth floor runs out to the sprite's south edge and stops at a
# low sill the eye reads as the front of the fire box.
r.box((MOUTH * 2, 0.06, 0.10), (0, -(OUTER - WALL / 2), 0.09), dark, bev=0.01)

asset = rig.Asset("smelter", out, (2, 2), headroom=0.25)
r.frame(2, 2, headroom=0.25)

# COLD first, so the only difference between the two renders is the hearth's
# material. Anything else that moved between them would be a second variable
# in the one measurement this sprite exists to pass.
r.render(asset.path("cold"))
asset.add("cold", 1)

# LIT. `fire` is its own palette entry and deliberately NOT `glint`
# (#FFFFFF), which rig.py reserves: a white blowout means "grade changes a
# number in sim" and a fire means a state. Warm enough to read as fire before
# the tint, bright enough to sit at the ceiling after it.
glow = mat("fire", emit=5)
for c in coals:
    c.data.materials[0] = glow
r.render(asset.path("lit"))
asset.add("lit", 1)

asset.write()
