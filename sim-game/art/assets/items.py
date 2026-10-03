"""Item icons, 1x1 tile, transparent. SPECIES-NEUTRAL: the client tints.

Two rows, `ore` and `refined`. It was four rows named iron / copper / coal /
stone, which is art for a withdrawn design: a world rolls six species from its
seed and an inventory can hold any of them, so a per-species icon was never
going to be renderable in the first place.

Same generic rock as the deposit tile and the same light near-neutral base,
so a chunk in the inventory is recognisably the thing on the ground once both
have been multiplied by the same species colour. See `ore.py` for why the
base is light.

`items.py` is also where loose things on the ground are drawn, which is why
these chunks LIE on the ground rather than stand on it (rig.py rule 1).

WHY `refined` IS CAST BARS AND NOT A TIDIER ROCK (ASSA-66). `refined` is the
kind the demo loop handles most -- 6 stacks of the richest pack the offline
session holds, against 22 of ore -- and it had no art at all. The two rows
share a palette, a species tint and often a species NAME in the same pack, so
colour cannot be what separates them: the whole read has to come from
silhouette. Ore is two irregular squashed spheres; refined is boxes with
straight top edges and a stacked step. At the size this is drawn, a straight
horizontal edge and a step are the only things that survive.

SIZE IT IS JUDGED AT: a pack row draws an items frame at EXACTLY 1/2. The
frame is 64x96 and `main.gd`'s `ICON_BOX_PX` is (32, 48) with
`SIZE_SHRINK_CENTER`, so `min(32/64, 48/96)` is 1/2 and every 2x2 source block
becomes one pixel (ASSA-65 made it exact; before that it was 15/32, which
sampled 30 of 64 columns unevenly). So this must read at 32x48, and the thing
it must not do is read as "ore but tidier".

THE BARS LIE DOWN AND KEEP THEIR CONTACT SHADOW. Both are the same rule as the
ore chunk: an item on the ground is on the ground. ASSA-64 took the shadow off
mounted PART sprites because a part bolted to a frame never touches the
ground; nothing in this file is a part, so nothing here changes.
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()
asset = rig.Asset("items", out, (1, 1), headroom=0.5)


def ore_row():
    """Two irregular chunks of the deposit's own rock."""
    random.seed(0)
    r = rig.Rig(samples=64)
    r.shadow_catcher()
    base, dark = mat("ore", rough=0.68), mat("ore_dk", rough=0.68)
    r.rock(0.34, (0, 0, 0.16), base, sub=1, squash=0.7, rot=(0.2, 0.1, 0.6), env=False)
    r.rock(0.18, (0.28, -0.22, 0.08), dark, sub=1, squash=0.7, rot=(0, 0, 1.2), env=False)
    return r


def refined_row():
    """Three cast bars, two down and one across them.

    EVERY CHOICE HERE IS ABOUT THE SILHOUETTE AT 1/2, because that is all the
    pack row has (see the header):

    - BOXES, NOT ROCKS. A straight top edge is the one thing ore cannot have.
    - ALL THREE PARALLEL, AND ORDERLY. The first version crossed the top bar
      over the other two at 1.17 rad, on the theory that three bars lying the
      same way merge into one slab. The crossed one did separate -- and read as
      a plank dropped on a pile, which is the opposite of what `refined` means.
      Tidiness IS the signal here. The separation problem was real but the fix
      is VALUE, below, not disorder.
    - LAID OUT IN THE PLANE, NOT PILED UP IN Z. This is rig.py rule 1 again and
      I walked into it anyway. The camera is tilted off VERTICAL, so it mostly
      sees an object's TOP: three bars stacked in Z show the top bar's face and
      a thin rim of the ones under it, and with the top bar inset and lightest
      the whole icon read as an OPEN CRATE -- a wall around a pale panel. Bars
      side by side on the ground show three full tops, which is the thing that
      actually says "bars". It is also what `items.py` already claims in its
      header: these LIE on the ground.
    - THE BANDS SEPARATE BY SHADE AS WELL AS BY A GAP. At 1/2 a gap between two
      bars of the same colour closes up -- the first version's bottom pair read
      as one slab. The gaps here are ~0.09 world units, about 3 px at 1x and
      still 1-2 after halving, and the shades alternate so the bands survive
      even where a gap does not.
    - ROUGHLY ORE'S FOOTPRINT. The first version came out 16x17 px against the
      ore chunk's 23x26 at 1/2, so the kind this game handles MOST looked like
      the minor one of the two in adjacent pack rows. Sized up to match.
    - LOW ROUGHNESS AND A LITTLE METAL, which is the cast-metal read: it puts a
      hard specular band along the top face and the chamfer, where the rock's
      0.68 scatters. Not full metal -- a metal surface has no diffuse albedo to
      multiply, so a species tint would have nothing to tint (rule: the client
      tints these by multiply, see ore.py rule 1).
    - SAME `ore` PALETTE AS THE CHUNK. Refined ore is the same material
      processed, the tint budget has to stay identical, and anything I invented
      here would be a second near-neutral light base to keep in step.
    """
    random.seed(7)
    r = rig.Rig(samples=64)
    r.shadow_catcher()
    cast = mat("ore", rough=0.30, metal=0.25)
    cast_mid = mat(rig.mix_hex(rig.PALETTE["ore"], rig.PALETTE["ore_dk"], 0.38),
                   rough=0.30, metal=0.25)
    cast_hi = mat("ore_hi", rough=0.26, metal=0.25)
    # Three bars side by side along X, ends staggered so the row is not one
    # straight edge, shades alternating so each stays its own band.
    r.box((0.58, 0.17, 0.11), (-0.04, 0.22, 0.055), cast_mid, bev=0.024)
    r.box((0.58, 0.17, 0.11), (0.03, 0.00, 0.055), cast, bev=0.024)
    r.box((0.58, 0.17, 0.11), (-0.02, -0.22, 0.055), cast_mid, bev=0.024)
    # One resting on the middle bar, pushed back so the bar underneath still
    # shows. This is the only piece carrying height, and it is what stops the
    # icon reading as a flat sticker beside the ore chunk.
    r.box((0.44, 0.16, 0.11), (0.06, 0.05, 0.165), cast_hi, bev=0.024)
    return r


def smelter_row():
    """A ring of walls with a dark MOUTH in it. (ASSA-87)

    THE SIM'S SMELTER IS WALLS. `building.rs` gives it a 2x2 footprint and
    walls whose heat tolerance is the species' own, and `recipe.rs` builds it
    out of 5 ore of any species. So an enclosure is the honest object; a
    generic furnace with a chimney would be drawing a machine this game does
    not have.

    IT IS THE ONLY ITEM ROW WITH ENCLOSED NEGATIVE SPACE, and that topology is
    what separates it rather than any colour distance. Maren flood-filled the
    three rows from outside the silhouette at the client's own 32x48: smelter
    has exactly ONE enclosed dark region, ore has zero, refined has zero. That
    cannot drift with a render's extremes the way a threshold can.

    THE HOLE IS A SLOT, NOT THE SQUARE WELL I FIRST WROTE HERE. Measured at
    drawn size it is 40 px, bbox 10x4, aspect 2.50 -- the rig's tilt
    foreshortens the opening into a letterbox. I had described the geometry I
    authored instead of the picture it produces, and Maren caught it: at this
    angle it reads as a MOUTH, and a mouth is what says furnace. The render was
    better than its own docstring, so the words moved and the art did not.

    AND THE HOLE IS NOT WHAT MAKES THE ROW FINDABLE -- the silhouette is. At
    drawn size the body is 709 px against ore's 448 and refined's 435 (Maren's
    count, taken at a different alpha cut from the 540/380/396 further down this
    file; do not line the two sets up). What the mouth earns is RECOGNITION: "a
    thing with a mouth" rather than "a brick".

    AND IT PLAYS TO THE CAMERA RATHER THAN AGAINST IT. rig.py rule 1: the
    camera is tilted off VERTICAL and mostly sees an object's TOP. That is what
    turned my first `refined` attempt into an open crate when I did not want
    one -- a wall around a pale panel. Here the top-down read IS the subject, so
    the same geometry that was a defect there is the signal here.

    THE HEARTH IS A DARK FLOOR, NOT A HOLE THROUGH THE SPRITE. Left open, the
    middle would show whatever is behind the icon -- the slot plate in the pack
    (ASSA-71), bare ground on the map -- so the shape would read as a frame
    around the background rather than as a vessel with something in it. A floor
    makes it an inside. It is `ore_dk` pushed toward black rather than a new
    palette entry, so the species tint still lands on it like everything else.

    UNLIT, deliberately. A fire is a STATE and a pack holds an unplaced
    smelter; a glow would also collide with the grade-glint rule, where an
    emissive mark means "grade changes a number in sim" and nothing else.

    WALLS THICK ENOUGH TO SURVIVE THE HALVING. At the size a pack row draws an
    items frame -- exactly 1/2 since ASSA-65 -- a wall thinner than about 0.1
    world units closes up against its neighbour and the ring becomes a blob.

    THE MOUTH'S CONTRAST HAS A CEILING THAT IS NOT MINE TO RAISE, and the next
    person to look at this number should not spend a render on it. Mouth
    against the wall within 2 px of it, through the client's own `modulate`, on
    its own plate, at 32x48: 6.85 untinted, 6.58 on #FFFF33, down to 1.87 on
    #7A29CC and 1.88 on #3333FF -- the species the demo starts you on. Maren
    tried the obvious fix before asking for it: taking this hearth to black
    buys 6.58 -> 10.35 on yellow but only 1.88 -> 2.07 on blue. `modulate` is a
    per-channel multiply and blue carries 7% of luminance, so NOTHING drawn in
    this sheet holds an interior read under a blue-dominant tint. Take the
    near-black hearth free whenever this file next renders; do not make a trip
    for it, and do not reach for a new pigment, because the limit is the tint
    and not the paint.
    """
    random.seed(11)
    r = rig.Rig(samples=64)
    r.shadow_catcher()
    wall = mat("ore", rough=0.62)
    wall_dk = mat(rig.mix_hex(rig.PALETTE["ore"], rig.PALETTE["ore_dk"], 0.45), rough=0.62)
    hearth = mat(rig.mix_hex(rig.PALETTE["ore_dk"], "#000000", 0.78), rough=0.85)
    span, thick, high = 0.62, 0.15, 0.34
    # The hearth bed first, so the walls sit on it and its edge never shows.
    r.box((span, span, 0.06), (0, 0, 0.03), hearth, bev=0.01)
    # Four walls. The two running along X are full width; the two along Y are
    # inset by a wall so the corners butt rather than overlap, which keeps the
    # bevels from doubling into a bright corner pip at 1/2.
    arm = span - thick
    r.box((span, thick, high), (0, (span - thick) / 2, high / 2 + 0.04), wall, bev=0.02)
    r.box((span, thick, high), (0, -(span - thick) / 2, high / 2 + 0.04), wall_dk, bev=0.02)
    r.box((thick, arm, high), ((span - thick) / 2, 0, high / 2 + 0.04), wall_dk, bev=0.02)
    r.box((thick, arm, high), (-(span - thick) / 2, 0, high / 2 + 0.04), wall, bev=0.02)
    return r


# ----------------------------------------------------- loose parts (ASSA-112)
#
# WHY A PART IS DRAWN TWICE. `assets/head.py` and its three siblings draw a part
# TO BE ASSEMBLED: 2x1 tiles of landscape frame built around the join at x=0, a
# head east of it and a frame/handle/hopper west, so that overlaying two frames
# makes a machine (rig.py rules 3 and 4). That frame is doing its job and is not
# touched here.
#
# A part in your PACK is not being assembled, it is a loose thing on the ground,
# and this file is where loose things are drawn (rig.py rule 3, in writing).
# Maren's ASSA-112: the pack slot is 32x48, portrait, 2:3. An items frame is
# 64x96, exactly 2:3, so an item fills the plate; a part's 128x102 fitted by
# width into that slot loses 22.5 px of height before the drawing starts, and
# the object then occupies part of its own wide frame. Measured, a part filled
# 4.5-13.3% of the slot where every item fills 24.7-35.2%. No re-render of the
# assembly sheets could fix that, because the aspect is the cause.
#
# THREE THINGS CHANGE WHEN A PART COMES OFF A MACHINE, and each is a statement:
#
#   1. IT TURNS. These objects are long, and the slot is tall: the assembly
#      drawings run EAST-WEST because that is where the join is, and these run
#      NORTH-SOUTH (or on a diagonal) because that is where the room is.
#   2. IT LIES ON THE GROUND AND KEEPS A CONTACT SHADOW. `head.py` and
#      `hopper.py` use `rig.bounce()` instead of a shadow catcher, because a
#      MOUNTED part never touches the ground (ASSA-64). A part in a pack, drawn
#      with the ore chunks and the bars, is on the ground like them. Same rule,
#      opposite answer, for the same reason.
#   3. IT HAS NO GRADE ROW. The part sheets carry C/B/A because grade changes
#      numbers in sim and a machine shows it. These rows follow the items
#      convention instead -- ore, refined and smelter are one row each and the
#      stack line carries `(B)` -- so the palettes here are the parts' own, with
#      the grade lever left alone rather than frozen at a grade I would be
#      choosing silently.
#
# NOT TO SCALE, like every other row in this file: the smelter item is a 2x2
# building drawn inside one tile. Each of these is sized to fill its slot, which
# is the only size question a pack row asks.
#
# AND SEPARATION IS EARNED HERE, NOT INHERITED. Three part pairs score IoU 0.000
# on the assembly sheets only because head sits east of the join and the rest sit
# west -- registration, not shape (ASSA-101). With no join to borrow from, each
# of these has to be its own object: a LINE with a grip (handle), a DRUM with a
# taper (head), a chunky deck on FEET (frame), an open square MOUTH (hopper).
# Measured against ASSA-111's conjunction in art/check_items_kinds.py.

# Where the camera's vertical centre sits on the ground: `frame(1, 1,
# headroom=0.5)` pushes it half a tile north of the footprint, so a flat object
# centred here is centred in the picture.
MID = 0.18
# A direction in the ground plane, `t` units along it from the middle, for
# cylinders authored lying down. `rot=(pi/2, 0, phi)` points a cylinder's axis
# north and then swings it phi toward the west.
def along(phi, t, z, x0=0.0, y0=MID):
    d = (-math.sin(phi), math.cos(phi))
    return (x0 + t * d[0], y0 + t * d[1], z)


def lying(phi):
    return (math.pi / 2, 0, phi)


def fit(r, s, down_px=0.0):
    """Scale the whole composition about the frame's middle by `s`, then push it
    `down_px` AUTHORING PIXELS down the picture.

    WHY A LEVER RATHER THAN RE-AUTHORED NUMBERS. Every one of these was drawn to
    fill the slot and the first render of all four burst it: solid ink on the
    frame border, which `check_part_frame_fit.py` exists to catch on the part
    sheets (ASSA-104) and which a CLIPPED SPRITE CANNOT REPORT ABOUT ITSELF --
    its own extent is cut off with it. So composition is one set of numbers and
    SIZE IN THE SLOT is one more, measured at the drawn size and turned here.

    Only the model is scaled. The shadow-catching ground plane lives in `r.env`
    and must not move with it.
    """
    # Down the picture is north-to-south on the ground: the camera is tilted TILT off
    # vertical, so a pixel of picture is 1/cos(TILT) of ground.
    dy = -(down_px / rig.TILE_PX) / math.cos(rig.TILT)
    for o in r.model.objects:
        x, y, z = o.location
        o.location = (x * s, (y - MID) * s + MID + dy, z * s)
        o.scale = tuple(v * s for v in o.scale)
    return r


def handle_row():
    """The held frame, loose: one long line with a grip, laid on the diagonal.

    THE DIAGONAL IS THE DRAWING CHOICE AND IT IS LOAD-BEARING. A rod is thin --
    that is its whole identity against `frame`'s chassis, and thickening it to
    fill a slot would spend the one thing that tells the two frames apart at
    32 px. What a rod CAN have is length, and the longest line in a 32x48 box is
    its diagonal. So this one runs corner to corner rather than straight up.
    """
    r = rig.Rig(samples=64)
    r.shadow_catcher()
    gun, rubber, grey = mat("gun"), mat("rubber"), mat("grey")
    brass = mat("brass")
    phi = -0.52                 # ~30 deg east of north: the slot's own diagonal
    z = 0.155                   # it rests on the shaft's radius
    # THE SHAFT: one straight run, same slenderness as the assembly drawing.
    r.cyl(0.155, 1.06, along(phi, 0.0, z), grey, bev=0.02, rot=lying(phi))
    # THE FERRULE at the north end -- the socket that says this end takes
    # something. Brass, the handle's warm mark, as on the part sheet.
    r.cyl(0.215, 0.17, along(phi, 0.60, z), brass, bev=0.02, rot=lying(phi))
    r.cyl(0.225, 0.05, along(phi, 0.70, z), gun, bev=0.01, rot=lying(phi))
    # THE GRIP at the south end: two rubber bands and a butt cap, so a loose
    # shaft does not read as a pipe somebody cut.
    for t in (-0.46, -0.61):
        r.cyl(0.195, 0.11, along(phi, t, z), rubber, bev=0.02, rot=lying(phi))
    r.cyl(0.175, 0.07, along(phi, -0.72, z), gun, bev=0.015, rot=lying(phi))
    return fit(r, 0.82)


def head_row():
    """The head, loose: a drum with a tapering bit, lying on its side.

    IT POINTS NORTH BECAUSE IT CANNOT POINT ANYWHERE ELSE: the drum is 0.8 of a
    tile across and the slot is one tile wide, so any angle off vertical pushes
    it through the frame edge. The silhouette is a wide round end narrowing to a
    point, which is the opposite of the handle's even line.
    """
    r = rig.Rig(samples=64)
    r.shadow_catcher()
    gun, grey = mat("gun"), mat("grey")
    steel = mat("steel", rough=0.45, metal=0.6)
    brass = mat("brass")
    phi = 0.0
    z = 0.40                    # the collar is the widest point, so it rests on it
    # THE MOUNT, the end that attaches. On a machine this straddles the join;
    # loose, it is the fat end of the object.
    r.cyl(0.40, 0.27, along(phi, -0.42, z), gun, bev=0.04, rot=lying(phi))
    r.cyl(0.315, 0.07, along(phi, -0.24, z), grey, bev=0.015, rot=lying(phi))
    # The key lug, on top where this camera sees it: the one asymmetric feature.
    r.box((0.16, 0.21, 0.13), along(phi, -0.42, z + 0.40), brass, bev=0.02)
    # THE BIT, tapering away south->north. `cone` puts r1 at local -z, which is
    # the drum side, so the wide radius is r1.
    # `cone(r1, r2, ...)` puts r1 at local -z, and `lying()` sends that NORTH -- the
    # opposite of `head.py`, where LYING sends it west to the drum. Written the other
    # way round it is a funnel standing on a blob, which is what the first render was.
    r.cone(0.04, 0.35, 0.84, along(phi, 0.21, z), steel, bev=0.005, rot=lying(phi))
    # Two thread rings: at this size they are banding, which is what says head
    # rather than spike.
    r.cyl(0.30, 0.07, along(phi, -0.07, z), gun, bev=0.008, rot=lying(phi))
    r.cyl(0.235, 0.07, along(phi, 0.28, z), gun, bev=0.008, rot=lying(phi))
    return fit(r, 0.78, down_px=2)


def frame_row():
    """The planted frame, loose: the chunky deck, still on its feet.

    FEET ARE WHAT PLANTED MEANS (frame.py), so a loose one keeps them and keeps
    its contact shadow -- it is the one part that stands on the ground whether or
    not a machine is built on it. Turned north-south and sized to the slot.
    """
    r = rig.Rig(samples=64)
    r.shadow_catcher()
    gun = mat("gun")
    orange, orange_dk = mat("orange"), mat("orange_dk")
    steel = mat("steel", rough=0.45, metal=0.6)
    # THE YOKE at the north end, where a head would drop in.
    r.cyl(0.33, 0.16, (0, MID + 0.44, 0.30), orange_dk, bev=0.03, rot=(0, math.pi / 2, 0))
    for sx in (-1, 1):
        r.box((0.1, 0.12, 0.5), (sx * 0.3, MID + 0.44, 0.24), orange, bev=0.03)
    # THE DECK, flat on top because a hopper bolts down here.
    r.box((0.78, 0.92, 0.28), (0, MID - 0.12, 0.34), orange, bev=0.06)
    # THE DECK PLATE IS WIDER HERE THAN ON THE PART SHEET, and the reason is rule 6
    # rather than taste. A loose frame is drawn big enough to fill a slot, and at that
    # size the orange top face is most of the body: `art/loudness.py` measured this row
    # at mean C* 37.4 against the quietest ore's 34.8 -- a machine out-shouting two of
    # six species, which is the one thing ore's budget forbids. The pigments are
    # `frame.py`'s unchanged; what moved is how much of the picture is deck and how
    # much is the gun-metal plate a hopper bolts to. Re-measure with loudness.py if
    # this geometry ever changes again.
    r.box((0.66, 0.82, 0.05), (0, MID - 0.12, 0.49), gun, bev=0.02)
    # FOUR FEET, lifting the deck clear so the shadow reads as a gap.
    for sx in (-1, 1):
        for sy in (-1, 1):
            r.cyl(0.085, 0.34, (sx * 0.28, MID - 0.12 + sy * 0.32, 0.17), gun, bev=0.02, verts=20)
            r.cyl(0.11, 0.05, (sx * 0.28, MID - 0.12 + sy * 0.32, 0.02), steel, bev=0.01, verts=16)
    # Struts from deck to yoke, so the two masses read as one object.
    for sx in (-1, 1):
        r.pipe((sx * 0.2, MID + 0.22, 0.48), (sx * 0.12, MID + 0.38, 0.36), 0.05, steel, flanges=False)
    return fit(r, 0.78, down_px=3)


def hopper_row():
    """The hopper, loose: an open square mouth, standing on its own throat.

    ENCLOSED NEGATIVE SPACE IS ITS SIGNAL, the same topology argument the
    smelter row makes -- except the smelter's mouth is a letterbox slot in a
    ring of walls and this is a wide funnel with a dark well in it. The two are
    the closest pair here by shape and are told apart by the mouth's size and by
    the throat the hopper stands on.
    """
    r = rig.Rig(samples=64)
    r.shadow_catcher()
    gun = mat("gun")
    body = mat("grey", rough=0.45, metal=0.6)
    span, wall, high = 0.72, 0.065, 0.48
    deck = 0.30
    # FOUR LEANING WALLS, not a cone: a hard-edged quadrilateral survives the
    # halving where a round mouth downsamples into a blob.
    for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        r.box((wall if sx else span, span if sx else wall, high),
              (sx * span / 2.2, MID + sy * span / 2.2, deck + high / 2),
              body, bev=0.02, rot=(sy * 0.32, -sx * 0.32, 0))
    # THE WELL: the dark interior is what says "open" when the walls are two
    # pixels thick.
    r.box((0.52, 0.52, 0.07), (0, MID, deck + 0.07), mat("rubber"), bev=0.01)
    # THE THROAT it stands on: narrow, dark, square, so it reads as
    # mouth-over-neck and not as one tapered lump.
    r.box((0.40, 0.40, 0.30), (0, MID, 0.15), gun, bev=0.03)
    return fit(r, 0.85, down_px=6)


for row, build in (("ore", ore_row), ("refined", refined_row), ("smelter", smelter_row),
                   ("handle", handle_row), ("head", head_row),
                   ("frame", frame_row), ("hopper", hopper_row)):
    r = build()
    r.frame(1, 1, headroom=0.5)
    r.render(asset.path(row))
    asset.add(row, 1)
asset.write()
