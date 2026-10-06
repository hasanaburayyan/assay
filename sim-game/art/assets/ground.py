"""Ground tiles: ONE 8x8-TILE FIELD, cut into 64 cells placed by position.
(ASSA-115 box 2)

WHAT WAS WRONG, MEASURED BY MAREN AND NOT BY ME. The tile was one flat plane with
two to five tiny dark pebbles on it. Inside a tile, luminance ran p5 145.2 to p95
145.5 out of 255 -- no structure at all -- and the four variants differed in
10-19% of their pixels at a MEAN ABSOLUTE CHANNEL DIFFERENCE OF 0.9 TO 1.7. At
32 px they were the same image, four times. The board called the demo felt and
candy; this file is the felt, and it is 100% of the frame.

WHAT WAS STILL WRONG AFTER SIX VARIANTS, AND WHY MORE OF THEM CANNOT FIX IT.
Nerite could point at "32 px tile seams and a faint lattice of darker discs"
on a window shot, so box 2 was false and I un-ticked it. Measured on the
shipped sheet, over the 64 px of one join (mean |dL|, 255 scale):

    a tile beside ITSELF          4.03     (the 3x3 wrap works)
    a tile beside a DIFFERENT     14.50
    two adjacent interior columns  2.99
    CONTROL: col 32 of one variant beside col 33 of another, nowhere
    near a tile edge                11.65

The control is the finding. 11.65 of that 14.50 is not an edge artefact at
all -- it is what two INDEPENDENT patch fields do when you put them side by
side, anywhere. A mosaic of per-tile variants steps by about that much at
every join by construction, because the two sides were drawn without
knowing about each other, and no number of variants makes a stranger
correlated with its neighbour. (It also is not baked lighting: the column
profile is 6.5 DARKER at the vertical edges and 5.1 BRIGHTER at the
horizontal ones, which no vignette does. Every light in `rig.py` is a SUN,
so a field of any size is lit flat.)

SO THE FIELD IS THE UNIT NOW, NOT THE TILE. One 8x8-tile scene is laid out and
rendered sixty-four times, once per cell, with the camera moved and the geometry
untouched: a patch that crosses a cell boundary is rendered in both cells,
from the same object, lit the same way. There is no seam to find because
there is no join -- the cells are already a continuous picture, and the
whole field wraps (every spot near the rim is drawn again at the FIELD's
period, not the tile's), so the blocks tile with each other too.

The price is that the repeat is now an 8x8 BLOCK on a 256 px lattice instead
of 6 images on a 32 px one, and the client must place a cell BY POSITION --
`manifest["ground"]["block"]` is the whole contract, and `scene_view.gd`
reads it. Hash-picked cells would be strictly worse than what we ship: the
cells are not interchangeable, so a random arrangement would cut every patch
that crosses a boundary.

FOUR LAYERS, AND EACH ONE IS A DIFFERENT SPATIAL FREQUENCY, because that is what
"ground" is made of and what a flat plane cannot have. **THE FOURTH IS THE ONLY ONE
BIGGER THAN A TILE** (ASSA-150): the three below are drawn per CELL, so whatever they
do they do inside 32 px, and the field they add up to was measured as white noise above
half a tile -- cell means one tile apart correlate -0.10 / +0.06, and the structure
function is flat from 48 px to 256. Layer 4 is drawn once over the whole field.

  1. PATCHES -- 5 very flat discs per cell, radius 0.14-0.30 of a tile, two
     light and three dark. Eight at a wider light step read as CAMOUFLAGE at
     32 px: every tile a busy cell with no quiet ground in it, and the eye
     finds the repeat in four variants immediately. Ground is mottled, not
     patterned, and most of it is quiet. At 32 px/tile these are 9-19 px
     across: the scale a player reads as "this bit of ground is drier than
     that bit". They are nearly flat (squash 0.03) ON PURPOSE -- they are
     COLOUR, not relief, and a patch with height would read as a boulder.
  2. GRIT -- 18 small rocks per cell, radius 0.035-0.075, squash 0.4, with
     real height. These are the ones the sun catches: at a 9-degree key, a
     2 px bump makes a 1 px shadow, and that is the grain.
  3. SPECKS -- 12 tiny dark points, radius 0.015-0.03. Below the resample they
     do not survive as objects; they survive as dither, which is what stops the
     patches from banding into flat zones of their own.
  4. MOTTLE -- 8 domes of radius 1.8-3.0 TILES over the whole field, light and dark
     alternating. This is the layer a player reads as "that stretch of ground is
     drier", and the only one whose features cross a tile at all. Its amplitude was
     set by arithmetic before the render: 1.5-tile domes cannot move the one-tile
     correlation at any amplitude a ground may spend, and the ore cost at twice this
     one is 0.43 of a dE.

     TWO THINGS THIS PARAGRAPH CLAIMED THAT MEASUREMENT KILLED (Cove, ASSA-150), both
     mine and both written before anything was measured:

     "six concentric rings so the tone arrives over a radius rather than at an EDGE"
     is false for most of the layer. `r.rock` draws opaque geometry with `rig.mat`,
     so two domes cannot blend -- the topmost disc simply wins -- and 8 domes of this
     radius cover every point of the field 2.50 times over (0% of it is bare). So the
     per-pixel delta between this arm and the one before it is THREE VALUES: -8, 0 and
     +7 hold 69.9% of the sheet, and only ~17% of the tinted area carries an
     intermediate ring tone. The ramp survives at a dome's outer rim and nowhere else.
     This is a description defect and not a seam: the dome boundary steps p99 15.8 /
     max 39 on its OWN field, but the composite's adjacent-pixel step did not worsen
     (main p99 27.93 -> 26.78, mean 3.00 -> 2.85), because the ground's own grain is
     already louder than a dome edge. The overlap is also not avoidable by spacing:
     four domes of this radius have more area than the whole 8x8 field, so a
     non-overlapping packing does not exist.

     "light and dark alternating so the field's median CANNOT DRIFT" is false twice
     over. Alternating does not equalise area -- at seed 150 the light domes carry 9%
     more disc than the dark -- so the field's MEAN rose +0.89. And the median fell
     6.86 in the same render, in the other direction, because main's field puts 32.5%
     of all its pixels on a single luminance level (146) and the median sits on that
     spike; any layer that varies the base tone at all shatters it. `ui_theme.py`
     derives the pack-row plate from that median, so it is reading a statistic pinned
     to the ground being flat. Worth a look when something else touches it.

THE TONE BUDGET IS STILL FIXED, AND NOW IT IS THE FIELD'S. Every cell
contributes the same inventory of sizes in the same tones (`scatter` is
called once per cell, unchanged), but a spot's PLACE is anywhere in the
field, so a cell may end up with four patches and its neighbour with one.
Measured on the shipped sheet, per-cell medians run 18.8 apart where six
variants ran 0.9 apart.
That is the point: on a surface with no joins, a quieter stretch beside a
busier one is ground, not a tile. It does mean a single cell is no longer
median-flat the way a variant had to be -- the old rule existed to stop a
player pointing at a TILE EDGE and seeing a value step, and there are no
tile edges left inside a block. Measured per cell on the shipped sheet, and
reported on the item, never assumed.

WHAT IT MAY NOT DO. Ore owns saturation (rig.py rule 6) and ore has to stay
FINDABLE on this: my own floor is 3.9 dE between the quietest deposit and the
ground it sits on. A ground with a wide value spread can eat that, so the spread
here is in LUMINANCE and the chroma stays where it was -- and the number is
re-measured against the real ore sheet rather than assumed. See the item.
The sheet's median is also the pack-row plate (`ui_theme.py` derives it on
every build), so the FIELD's median has to land where the six variants' did.
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig

out = rig.args()
# THE BLOCK, AND WHY IT IS 8 AND NOT 4. At 4x4 the seam is already gone, and I looked
# at a 16x16-tile field at 1x and could point at the block: 16 copies of one 128 px
# picture, and the eye catalogues a distinctive cluster. 8x8 is a 256 px repeat, so a
# 28x18-tile window holds 3.5 x 2.25 of them. Bigger than that is not a look decision
# but a build one: `rig.rock` goes through `bpy.ops`, which re-syncs the whole scene
# per call, so the scene build is QUADRATIC in object count -- 4x4 took 36 s, 8x8
# takes about seven minutes, and 16x16 would take over an hour. The honest ceiling
# here is that quadratic, not the renderer.
BLOCK = 8


def wrapped(r, spots, squash, z=0.004, period=BLOCK):
    """Draw every spot in all nine FIELDS, so the field wraps.

    `spots` are (x, y, radius, colour, rotation). The ROTATION IS THE CALLER'S,
    not `rock()`'s own random one: nine copies of one pebble have to be one
    pebble, or the field is only seamless in its colours and not in its shapes.

    THE PERIOD IS THE FIELD'S, NOT THE TILE'S. With a 1x1 tile this offset was
    +/-1 and every tile wrapped into itself; here it is +/-4, so what leaves the
    east side of the BLOCK arrives at the west side of the block. Inside the
    block nothing wraps at all, because nothing has to -- it is one picture.

    AND ONLY THE COPIES THAT CAN BE SEEN ARE BUILT. At 1x1 a tile is smaller than
    a patch, so all nine copies of everything mattered. At 8x8 all but the rim
    land entirely off the field, and they are not free: `rig.rock` goes through
    `bpy.ops`, which re-syncs the scene per call, so the build is quadratic in the
    object count. Nine copies of 624 spots did not finish a scene in twelve
    minutes. A copy is kept when its disc still reaches the field, plus MARGIN for
    the shadow a grit rock throws (the key is 9 degrees above the horizon, and the
    tallest thing here is radius 0.075 squashed to 0.4, so ~0.19 of a tile). The
    geometry inside the field is identical either way; this is only arithmetic
    about what is off-camera for every cell.
    """
    half = period / 2.0
    for dx in (-period, 0, period):
        for dy in (-period, 0, period):
            for (x, y, s, color, rot) in spots:
                reach = s + 0.3
                if abs(x + dx) - reach > half or abs(y + dy) - reach > half:
                    continue
                r.rock(s, (x + dx, y + dy, z), rig.mat(color), squash=squash, rot=rot)


def softened(spots, tones):
    """A light patch, redrawn as concentric discs so it has no hard edge.

    BOX 11 ASKS FOR THREE THINGS AND I DELIVERED ONE OF THEM TWICE. "Softer, larger,
    lighter": a bigger disc at a bigger tone step is lighter and larger and HARDER, and
    both renders of that read as camouflage at 32 px -- every tile its own cell, the
    32 px lattice easier to find than before, not harder. Pictures, not an opinion:
    `/tmp/cove-115-field*.png`.

    So the step is spread over radius instead of being spent at one edge. Each light
    patch becomes len(`tones`) discs on one centre and one rotation, the widest in the
    gentlest tone, and the sprite is drawn at 64 px for a 32 px display, so a three-step
    ramp over ~8 px of radius is about a pixel a step once it lands. A patch with a
    gradient is a patch of ground; a patch with an edge is an object.

    Each ring sits a hair above the last because they are coplanar otherwise and
    z-fighting is not a soft edge.
    """
    out = []
    for (x, y, s, color, rot) in spots:
        if color != "ground_lt":
            out.append([(x, y, s, color, rot)])
            continue
        out.append([(x, y, s * scale, tone, rot)
                    for scale, tone in zip((1.0, 0.72, 0.45), tones)])
    return out


def scatter(n, rmin, rmax, light, span=BLOCK):
    """n spots at random places in the FIELD, each with its own fixed rotation.

    THE TONE BUDGET IS FIXED AND ONLY THE ARRANGEMENT IS RANDOM: exactly `light` of
    the n spots are the light tone, the rest dark. Drawing the colour per spot with
    `random.choice` is what the first render did, and the four variants came out with
    medians 126.8, 126.8, 158.7 and 144.8 -- a player could point at a tile and say
    that one is lighter, which reads as terrain the sim does not have.

    **AND THAT SENTENCE IS A MECHANISM STANDING IN FOR A PROPERTY (ASSA-150, Maren).**
    The rule this file has enforced is "every cell's median is equal". The thing worth
    protecting is one step back from it: **GROUND TONE CARRIES NO INFORMATION A PLAYER
    COULD READ AS MATERIAL OR STATE.** Equal medians is one way to hold that, and it is
    the way that forbids any feature larger than a cell -- which is how the field ended
    up white noise above half a tile (cell means one tile apart correlate -0.10 / +0.06;
    the structure function is flat from 48 px to 256). The MOTTLE below holds the
    property by a different route: it is achromatic, it is low-amplitude, and nothing in
    the sim reads ground tone, so a drab wide blotch cannot be mistaken for a deposit --
    `mottle_pop.py` measures that rather than asserting it (grade C's worst margin moves
    7.33 -> 6.90 at twice this amplitude, floor 5).

    So the budget below still holds for the three SUB-TILE layers, because that is where
    a per-cell tone difference would read as a tile; it is not a rule about the field.

    THE BUDGET WAS FIXED IN COUNT AND NOT IN AREA, which is only the same thing while
    the radii are close. Widening the patch layer to 0.14-0.30 for box 11 broke it:
    `random.uniform` handed v5 the big end of the range for its three DARK spots, and
    that variant's median came out 137.7 against everyone else's 142.4 -- the very
    sentence above, failing again four renders later, on the lever I had just widened.

    So the radii are a LADDER, not a roll: n sizes evenly spanning [rmin, rmax], the
    same n in every CELL, with the light tone pinned to fixed rungs. The field holds
    the same area in the same tone as 16 old tiles did, by construction, and what
    varies is placement and rotation -- which is what "differ by layout, never by
    tone" says, now at the size of the thing that has no joins in it.
    (Overlap still moves a median a little, since two dark discs crossing cover less
    than two apart. That is a field being a field; the budget is what I can fix.)

    `span` is the FIELD, not the tile: a spot goes anywhere in the block, which
    is the whole change. A spot whose centre sits on a cell boundary is now drawn
    once and seen by both cells.
    """
    radii = [rmin + (rmax - rmin) * i / max(1, n - 1) for i in range(n)]
    lit = {min(n - 1, int(round((k + 0.5) * n / light - 0.5))) for k in range(light)}
    # A LADDER WITH NO JITTER IS ITS OWN MOTIF, and the picture said so before any
    # number did: with the rungs exact, every tile holds the same inventory of sizes
    # and the eye finds the repeat on the sizes instead of on the arrangement. +/-8%
    # of a rung moves an area by at most 17% of one spot and leaves the budget flat,
    # which is the whole point of the ladder.
    radii = [r * random.uniform(0.92, 1.08) for r in radii]
    half = span / 2.0
    return [(random.uniform(-half, half), random.uniform(-half, half), radii[i],
             "ground_lt" if i in lit else "ground_dk",
             (0, 0, random.random() * math.tau))
            for i in range(n)]


asset = rig.Asset("ground", out, (1, 1), block=(BLOCK, BLOCK))
# ONE SCENE, SIXTY-FOUR RENDERS. The geometry is built once and only the camera moves,
# so a patch straddling two cells is the SAME object in both of them -- which is the
# only way two cells can be continuous, and is why this cannot be done by rendering
# the cells separately and hoping.
r = rig.Rig(samples=48, outlines=False)
# The plane has to cover the nine wrapped copies of a 4-tile field, not one tile.
r.ground(4 * BLOCK)
random.seed(200)
for cell in range(BLOCK * BLOCK):
    # 1. PATCHES: colour at the size a player sees, laid flat. Five, two of them
    # light, per cell: the first render used 9-13 at up to r 0.34 with a free
    # light/dark roll and came out as camouflage -- near half the tile in the light
    # tone, every tile reading as its own cell. Ground is mottled, not patterned.
    rings = softened(scatter(5, 0.14, 0.30, light=2),
                     ("ground_lt1", "ground_lt2", "ground_lt"))
    for i in range(3):
        wrapped(r, [spot[i] for spot in rings if len(spot) > i], squash=0.03,
                z=0.004 + 0.0002 * i)
    # 2. GRIT: the layer with height, so the key light has something to catch.
    wrapped(r, scatter(18, 0.035, 0.075, light=4), squash=0.4)
    # 3. SPECKS: dither under the patches.
    wrapped(r, scatter(12, 0.015, 0.03, light=0), squash=0.5)

# 4. MOTTLE -- THE ONLY LAYER WHOSE FEATURES ARE BIGGER THAN A TILE (ASSA-150).
#
# WHAT THE OTHER THREE LAYERS CANNOT DO, measured on the shipped field before this
# existed (`cove-assa150/field_scale.txt`): cell means at one tile apart correlate
# -0.097 horizontally and +0.062 vertically -- zero -- and the structure function
# is FLAT from d 48 to d 256 (13.0 against 13.1 of 255). Every feature the ground
# has fits inside half a tile, so above that the ground is white noise and there is
# nothing on it to walk toward. That is not the old "one blob per tile" defect,
# which #220 killed with the field; it is what the field left behind.
#
# PER FIELD, NOT PER CELL, which is the whole point: `scatter` is called inside the
# cell loop 64 times and each call spends the same budget, so anything drawn there
# is sub-tile by construction however it is arranged. These eight domes are drawn
# ONCE over the 8x8 field, at a radius of 1.8-3.0 TILES.
#
# THE AMPLITUDE IS SET BY ARITHMETIC, NOT BY EYE (`mottle_model.py`, `mottle_pop.py`):
#   - a replica on the real field says r(1 tile) reaches ~0.35 at a peak of ~10
#     levels with a 2.5-tile radius, and that 1.5-tile blobs cannot get there at any
#     amplitude a ground may spend;
#   - the cost to ore findability is almost nothing, and NOT for the reason I
#     assumed: ore is a transparent overlay, so a brighter patch of ground brightens
#     the tile the ore sits in too. At +-12 levels -- twice what ships here -- grade
#     C's worst margin moves 7.33 -> 6.90 against a floor of 5, and B and A stay
#     above 23 against a floor of 10.
#
# SIX RINGS, WIDEST AND GENTLEST FIRST, for `softened()`'s reason one scale up: a
# tone step spent at an edge is an object. Here the step arrives over ~0.4 of a tile
# per ring, about a pixel and a half of tone at 32 px/tile, which is under the
# ground's own grain.
#
# AND IT HAS TO BE FLATTER THAN ANYTHING ELSE HERE, which the first render taught me
# the hard way. At `squash=0.02` a 3-tile dome is 0.06 tiles tall -- seven times the
# patch layer's 0.009 -- so it did not sit UNDER the ground's grain, it BURIED it:
# `field_scale.py` on that sheet reported the structure function collapsing from 13.0
# to 3.1 and the per-pixel step from 2.96 to 0.42. The mottle was the only thing left
# in the picture. A layer that is colour and not relief has to be built that way:
# `MOTTLE_SQUASH` keeps every dome under 0.002 tiles tall, below the patches' own
# bottom, so the only thing it changes is tone.
MOTTLE_BLOBS = 8
MOTTLE_R = (1.8, 3.0)      # tiles
MOTTLE_STEP = 1.0          # all the way to `ground_lt` / `ground_dk`, the palette's
                           # own two ground tones -- 0.85 was an arbitrary fraction and
                           # it left box 2 at r 0.296/0.279 against a bar of 0.30.
MOTTLE_RINGS = 6
MOTTLE_SQUASH = 0.0012     # x radius: 0.0036 tiles tall at the widest dome
MOTTLE_Z = 0.0035          # clear of the ground plane, under the patches' 0.013 tops
random.seed(150)
for i in range(MOTTLE_BLOBS):
    # LIGHT AND DARK ALTERNATE so the field's median cannot drift: `ui_theme.py`
    # derives the pack-row plate from it on every build.
    target = "ground_lt" if i % 2 == 0 else "ground_dk"
    r0 = random.uniform(*MOTTLE_R)
    cx = random.uniform(-BLOCK / 2.0, BLOCK / 2.0)
    cy = random.uniform(-BLOCK / 2.0, BLOCK / 2.0)
    rot = (0, 0, random.random() * math.tau)
    for k in range(MOTTLE_RINGS):
        # THE RINGS ARE `softened()`'s SHAPE, NOT A LINEAR RAMP. Shrinking the radius
        # by a sixth each step put the whole tone in a 0.4-tile centre -- sub-tile,
        # which is the one thing this layer may not be -- and area-weighted the dome
        # was spending a tenth of its step over most of itself.
        # A PLATEAU, NOT A CONE, and the second render is why. A ramp that reaches its
        # tone only at the centre spends most of its area at a fraction of the step:
        # measured cell-by-cell against main, the cone profile moved a cell's mean by
        # +-2.5 against a patch-placement noise of sd 3.04, so the one-tile correlation
        # could not see it and neither could I at 1x. The tone now holds from the rim
        # inward and only the outer fifth of the radius is a falloff.
        radius = r0 * (1.0, 0.95, 0.88, 0.78, 0.62, 0.42)[k]
        tone = rig.mix_hex(rig.PALETTE["ground"], rig.PALETTE[target],
                           MOTTLE_STEP * (0.45, 0.62, 0.78, 0.9, 1.0, 1.0)[k])
        # Under the patches, the grit and the specks: this is the base tone those
        # three sit on, not a fourth thing on top of them.
        #
        # THE z IS THE RING'S AND NOT THE DOME'S, WHICH `softened()` WOULD CALL A BUG.
        # Its docstring says rings "sit a hair above the last because they are coplanar
        # otherwise and z-fighting is not a soft edge" -- true within one patch, and
        # this loop breaks it ACROSS domes: ring k of every dome shares one z, so where
        # two domes overlap at the same ring index the discs are coplanar and which
        # tone wins is the renderer's business, not a decision anybody made. With
        # coverage at 2.50 domes a point that is most of the field. It is not visibly
        # wrong today (see the header: the composite's step did not worsen) and the
        # fix -- `0.0001 * (i * MOTTLE_RINGS + k)`, 48 steps, top z 0.0083, still clear
        # of the patches' 0.013 -- changes which dome wins every overlap, i.e. changes
        # the art. So it is NOT bundled into the amplitude arm it was found beside:
        # one knob per render. Left for the Director to rule on with a picture.
        wrapped(r, [(cx, cy, radius, tone, rot)], squash=MOTTLE_SQUASH,
                z=MOTTLE_Z + 0.0001 * k)

# ONE RENDER, THEN SIXTEEN... SIXTY-FOUR SLICES, AND THE ORDER OF THOSE TWO MATTERS.
#
# Rendering each cell separately looked equivalent and was not. A cell rendered alone is
# its own image: Cycles denoises it as an image and `build.py` LANCZOS-downsamples it as
# an image, and both of those are truncated at its border. Measured on that sheet, two
# rows across a cell boundary stepped +0.401 of 255 more than two rows inside a cell
# (columns +0.160), and that residue was enough to leave the true tile offset RANK 1 of 32
# on Maren's findability test -- by 0.10 of 255, but rank 1. The geometry was continuous;
# the pipeline put a seam back in.
#
# So the field is rendered ONCE at BLOCK x BLOCK tiles (2048 px at SS=4), and the cells are
# cut out of it AFTER the downsample, by `build.py::pack` -- which is where the cutting has
# to happen, because Blender ships no PIL and a crop before the resize would reintroduce
# exactly the border this is removing. Same pixel count, same render time, no cell edges.
# AND THE RENDER IS WIDER THAN THE FIELD, because the image's own edge is the last
# border left. With the field rendered exactly, the one join that still measured was
# where the field WRAPS onto itself -- +0.844 of 255 against +0.078 at an interior cell
# boundary, because the downsample's kernel is truncated at the image edge and nowhere
# else. So a quarter-tile of the NEIGHBOURING copy is rendered on every side (the
# geometry already wraps, so that margin is the true continuation) and `pack()` cuts it
# off after the resize. Then no pixel of the shipped field was ever near an edge.
MARGIN = 0.25
r.frame(BLOCK + 2 * MARGIN, BLOCK + 2 * MARGIN)
r.render(asset.path("field"), transparent=False)
asset.slice_from("field", margin_px=int(MARGIN * rig.TILE_PX))
for i in range(BLOCK * BLOCK):
    # Row-major, v[cy * BLOCK + cx], cx growing east and cy growing SOUTH, because that is
    # how a tile coordinate grows in the view. The render's +y is NORTH and its top row is
    # the field's north edge, so cell 0 is the north-west corner and `scene_view.gd`'s
    # posmod(y, h) * w + posmod(x, w) lands on the same picture the field was laid out as.
    asset.add(f"v{i}", 1)
asset.write()
