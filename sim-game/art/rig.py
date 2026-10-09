"""Shared render rig for every sprite. Run inside Blender (see build.py).

Everything visual that must stay consistent across assets lives here: the
palette, the camera angle, the light, the outline pass and the pixel scale.
Asset scripts in `assets/` only describe shapes.

Conventions:
- 1 Blender unit = 1 tile. +y is north (up on screen), -y is south.
- Sprites are rendered at SS x the authoring size, then downscaled in post.
- The camera is orthographic, tilted TILT from straight down, with a pixel
  aspect correction so a ground tile renders as a square.
- Objects in the Model collection get dark outlines. Env (ground, shadow
  catcher) does not.
"""
import bpy, math, os, json, random
from mathutils import Vector

TILE_PX = 64          # authoring size per tile (game shows 32 at 1x zoom)
SS = 4                # supersample factor for the raw render
TILT = math.radians(30)
COS = math.cos(TILT)

# ---------------------------------------------------------------- shadow
#
# A CONTACT SHADOW, NOT A CAST ONE (Maren's ruling, ASSA-11). The bound she
# set is the one that matters and it is not a number: AT 1x NO SHADOW MAY
# READ AS A PART. It was failing that outright -- measured on the part set at
# true 1x, the shadow was 1.6-2.1x as many pixels as the BODY, peaked at
# alpha 247-249 (so, near-opaque black) and reached up to 22 px past the body
# to the south-east, which at a 64 px sprite is most of a tile. Tiled on a
# full screen it smeared into the sprite beside it, and a shadow that reads
# as a second object loses to GAME.md's "readability at small size beats
# detail" every time.
#
# Two knobs, because the defect has two halves:
#   SUN_TILT      LENGTH. Shadow runs as tan(tilt) of the object's height,
#                 so casting at 9 degrees instead of the key's 42 takes it to
#                 a sixth (tan 0.90 -> 0.16) and tucks it under the object
#                 instead of laying it out beside it.
#   SHADOW_ENERGY OPACITY. The catcher's alpha is the shadow lamp's SHARE of
#                 the light, so a weak caster among strong shadowless fills
#                 is a grey shadow rather than a black one. Raising the fills
#                 instead does NOT work -- measured: lifting the downward
#                 fill 0.9 -> 2.6 moved the handle's peak alpha 249 -> 249.
# SUN_SOFTNESS is the third: a hard edge is what made it read as geometry.
#
# A CLAUSE THAT LIVED HERE FOR AN HOUR AND WAS WITHDRAWN, kept as a note
# because the next person will have the same idea. "The contact shadow must
# fall entirely inside the occupied tile" (Maren, ASSA-30) sounds right and is
# UNSATISFIABLE: a machine's body is two tiles wide and sits ON the ground, so
# its contact shadow is two tiles wide too, and no render obeys the rule. I
# measured the shipped art against it and it failed by most of a tile, which is
# how the clause got withdrawn rather than how the art got fixed (ASSA-38).
#
# A sprite MAY overhang the tile it stands on -- that part stands. What a
# shadow may not do is CARRY OCCUPANCY: which tile a building claims is sim
# state the snapshot already has, so the client draws it (placement cursor,
# `building_at` in the tile readout) and the sprite says nothing about it. A
# renderer reading the sim beats a rule baked into a picture.
SUN_TILT = math.radians(9)
SUN_SOFTNESS = math.radians(30)
SHADOW_ENERGY = 0.9

# Flat, saturated palette. Few colours, high contrast. Add here, not in assets.
PALETTE = {
    "orange": "#F08A24", "orange_dk": "#B85A12", "gun": "#2E333B", "grey": "#6F7883",
    "steel": "#B9C2CC", "cyan": "#3FD8FF", "brass": "#E2B04A", "rubber": "#1B1D22",
    # GROUND IS THREE TONES, NOT ONE (ASSA-115). `ground_lt` is the light step the
    # tile was missing: with one base plus one dark it had no value structure at all --
    # luminance p5 to p95 INSIDE a tile was 145.2 to 145.5 out of 255, which is a mat
    # rather than ground. Low chroma on purpose, like its two siblings: ore owns
    # saturation (rule 6) and the ground is 100% of the frame, so it is the surface
    # that can least afford to shout.
    #
    # AND THE LIGHT STEP WAS NOT A STEP (ASSA-115 box 11). Measured on the hexes
    # themselves: `ground_dk` is -14.7 luminance from the base and `ground_lt` was
    # **+1.9**. So "three tones" was two -- a base with dark blotches on it -- which is
    # why the tile still read as one surface with specks however the patches moved. The
    # light tone is now +14.0, the mirror of the dark one. Chroma did NOT come with it:
    # 32.4% against the base's 36.1%, because a step up must not be bought in
    # saturation on the surface rule 6 reserves for ore. It pays twice, which is why
    # Wren asked for it: light patches are also the ground a DARK species tint has to
    # be found against, and those are the species that were washing out.
    #
    # `ground_lt1` / `ground_lt2` ARE THE RAMP, NOT TWO MORE TONES. A light patch is
    # drawn as three concentric discs, widest in `lt1`, so the +14 step arrives over a
    # radius instead of at an edge. Spent at an edge it reads as an object and the tile
    # becomes a cell -- which is what the first two renders of box 11 did.
    "ground": "#6E7A4E", "ground_dk": "#5F6B43", "ground_lt": "#7C885C",
    "ground_lt1": "#737F53", "ground_lt2": "#778357",
    "ground_ore": "#57603F",
    "skin": "#E0B48C", "suit": "#F08A24", "visor": "#3FD8FF",
    # ORE: one species-neutral set, base / dark / accent (accent is the
    # high-purity glint). There is deliberately no iron, copper, coal or
    # stone here and there must never be again - a world rolls six species
    # from its seed (ADR 0001) and nothing may name one.
    #
    # LIGHT ON PURPOSE. The client multiplies a species colour over these
    # pixels and a multiply cannot brighten, so this lightness is the budget
    # the tint spends; a mid-grey base makes every species mud. Near-neutral
    # on purpose too: whatever hue sits here is added to all six species at
    # once. Both measured in art/species_probe.py.
    "ore": "#CCC8C2", "ore_dk": "#7B7872", "ore_hi": "#F6F2EA",
    "line": "#1A1D23",
    # A LIT SMELTER'S HEARTH (ASSA-126), and deliberately NOT `glint` below.
    # Warm and near-white: a multiply tint owns the hue, so the fire's job is
    # to sit at the top of whatever value the species leaves it. It is a STATE
    # mark, which is why it must not be the glint's #FFFFFF -- that hex means
    # "grade changes a number in sim" and nothing else may emit it.
    "fire": "#FFE9C4",
    # The grade-A glint EMITS this and nothing else emits it. Neutral by
    # necessity, not by taste: see GRADE_GLINT_COLOR.
    "glint": "#FFFFFF",
}

from species_tints import SPECIES_TINTS  # noqa: F401  (data, see that file)
from part_layout import PART_REPEAT_OFFSET  # noqa: F401  (rule 5, see that file)
from part_layout import RIM_PX as _RIM_PX, RIM_K as _RIM_K  # (ASSA-159, see PART_RIM_PX)

# ---------------------------------------------------------------- parts
#
# PARTS LIE DOWN, AND THEY ALL MOUNT AT THE ORIGIN. Both rules are here and
# not in an asset script because they are the two things every part piece has
# to agree on, and agreement is what this file is for.
#
# 1. LIE DOWN. The camera is TILT off VERTICAL, so it mostly sees an object's
#    TOP. A part drawn standing shows the viewer its end cap, and anything
#    wider up the axis -- a collar over a taper -- covers the whole piece at
#    every size. Measured on ASSA-11: a 0.30 collar over a 0.26 taper hid the
#    entire bit, and the sprite read as a lid on a drum. Lying along X also
#    costs nothing, because the tilt compresses Y and leaves X alone. This is
#    why `items.py` reads: its chunks lie on the ground rather than stand on
#    it. Use `rot=LYING` on anything whose long axis is the part's long axis.
#
# 2. MOUNT AT THE ORIGIN, WORK TOWARDS +X. A machine is drawn by stacking
#    whole part sprites at the SAME frame position -- that is what "modular
#    machines look modular" has to mean mechanically, and it only works if
#    every piece agrees where the join is. So the join sits at x=0: a head's
#    collar straddles it and its bit runs east; a frame (held or planted)
#    straddles it and its body runs west. Compose by overlaying frames, never
#    by rendering a per-machine sprite.
#
#    OVERLAY WITH `part_layout.stack`, NOT WITH PLAIN `over`: colour composites
#    over, alpha takes the MAX. When this was written every part sprite carried
#    its own contact shadow, so the obvious operator compounded them and a
#    machine's shadow darkened with each part bolted on -- measured, 122 to 167
#    from one part to four, a gradient reporting part count that nobody chose
#    (ASSA-38). A renderer drawing these sprites has to do the same thing.
#
#    ASSA-64 TOOK THAT SHADOW OFF EVERY MOUNTED PART, so the sheets shipping
#    today cannot compound one: only a planted frame stands on the ground, and
#    a Design has exactly one frame. The operator is still the rule, because it
#    is what makes `over` correct rather than lucky and the next ground-standing
#    part kind brings the compounding back with it. Do not read "take the MAX"
#    as evidence that these sheets still stack shadows -- they do not, and the
#    guard that keeps it that way is check 4 of check_part_contract.py.
#
# 5. REPEATED PARTS STEP ALONG THE FRAME (the offset rule). Rule 2 is right
#    for parts that DIFFER and cannot express a COUNT: two hopper sprites
#    stacked at one position are one hopper. Measured on ASSA-16, a drill's
#    solid footprint at 1x went 1258 -> 1376 -> 1389 px for zero, one and two
#    hoppers - the second added 13 px, which is antialiased edge hardening,
#    not a part. Capacity is a real number in sim (MAX_HOPPER_SLOTS x
#    HOPPER_CAPACITY) and the grade-glint rule below says a real difference
#    owes the picture a visible one, so the nth repeat of a part kind is drawn
#    at n * PART_REPEAT_OFFSET, in Assembly::parts() order. The offset and the
#    reasoning behind its value live in art/part_layout.py, which is importable
#    without Blender; art/assemble.py executes the rule and judges it at a FULL
#    machine rather than at the two hoppers the demo happens to use.
#
# Part frames are PART_TILES wide so both halves of a join fit one frame.
# 3. ONE JOIN HEIGHT FOR EVERY PIECE. Overlaying frames only assembles a
#    machine if the parts agree how high the join sits, so PART_AXIS is it.
#    It is the head's collar radius, because the collar is the widest thing
#    in the set and an assembled pick lying down rests on its head -- which
#    is also true of a real one. A thin handle therefore floats clear of the
#    ground when rendered ALONE, and that is correct rather than a bug: a
#    part is drawn to be assembled, and `items.py` is where loose things on
#    the ground are drawn.
# 4. ONE FRAME SIZE. Overlaying only works if every part renders the same
#    rectangle, so tiles AND headroom are fixed here for the whole set. The
#    headroom is set by the TALLEST piece, not by each piece's own need: at
#    0.3 the hopper's mouth was clipped flat against the top of its frame
#    (body reaching row 0, measured) while every other part had room to
#    spare. A per-asset headroom would have hidden that as four frames of
#    different heights that silently refuse to compose.
#
#    4b. AND ONE WINDOW POSITION INSIDE IT (ASSA-104). Rule 4 guarded the
#    vertical axis only, and the horizontal axis had the same defect for as
#    long as nobody measured it: handle and frame ran 2 px off the WEST edge,
#    so the ink rim that closes that side was never rendered. The fix is NOT
#    more room -- `headroom` widens `frame_px`, and widening a part frame
#    shrinks the pack icon (it fits by width: 0.25 -> 0.2353 drops a part icon
#    from 32x25.5 to 32x24.0, on the one surface where a part reaches a
#    player). It is the SAME frame, looking 3 px further west, so the subject
#    lands 3 px east of where it did and the cut becomes a 1 px margin.
#
#    THE SHIFT IS THE WHOLE SET'S OR IT IS A BUG. Parts assemble by being
#    overlaid, so three parts shifted and one not would be a machine that
#    comes apart by 3 px. That is why `part_window()` and `part_asset()` exist
#    below and why no asset script is trusted to pass the offset itself.
#    Because every part translates by the same amount, the RELATIVE placement
#    ASSA-101 measures is untouched: head still sits right of the join and the
#    rest left, and IoU between two masks that both translate is unchanged.
#    Maren measured that before approving it (largest delta 0.029, every one
#    toward MORE separation); ASSA-111's check is the standing guard on it.
#
#    1 PX OF WEST MARGIN IS THE DESIGN, not an oversight to pad later
#    (Maren's ruling): if a future shape eats that pixel,
#    `art/check_part_frame_fit.py` goes red and somebody looks.
#
# 6. ORE OWNS SATURATION (Maren, ruling 3 on ASSA-20). Ore is the only fully
#    saturated thing in Assay. Ground, buildings, parts, items and UI chrome
#    all stay UNDER the quietest ore surface a player can see -- not under
#    the average species, under the floor of the shipped table, because a
#    machine that out-shouts two of six species has beaten ore on the map
#    where those two species live.
#
#    WHY THIS IS A RULE AND NOT A PREFERENCE. Species identity is carried by
#    TINT ALONE (Decision #36). Shape, outline, pattern and tier are all
#    already spent on other things, so colour is not ore's best channel, it
#    is ore's only one. Everything else in the game has shape and position to
#    spend instead, which is why the budget falls on them and not on ore.
#    Measured the other way round too: art/species_probe.py shows a muted
#    species table cannot work, because a low-chroma multiply stays low over
#    any base -- so ore's loudness is mandatory, not a taste.
#
#    ENFORCED by art/loudness.py against the real packed sheets, with the
#    floor read from art/species_tints.py rather than written down here. It
#    was RED on player/* and frame/A, and Decision #37 cleared both, each the
#    honest way round: frame/A was a BUG in the glint (see `graded_accent`)
#    and was fixed; the PLAYER was ruled out of scope, because the budget
#    covers what a player SCANS -- ground, machines, ground items, UI chrome
#    -- and an avatar is one humanoid sprite you never search a field for.
#    That exemption attaches to the SURFACE, never to a palette entry:
#    `suit` and `orange` are two names for one hex and stay independent
#    forever, so a machine can never claim the player's exemption by wearing
#    the player's colour.
LYING = (0, math.pi / 2, 0)
PART_TILES = (2, 1)
PART_AXIS = 0.28
PART_HEADROOM = 0.6
# How far EAST every part sits inside its unchanged frame (rule 4b). 3, because the
# measured overhang is 2 px (ASSA-104, from a wider re-render -- a cut sprite cannot
# report its own extent) and the rim needs the third. In authoring px, so it is a
# whole number of subpixels at SS and the downscale cannot smear it.
PART_SHIFT_PX = 3

# THE DARK RIM EVERY MACHINE PART WEARS, in authoring px and as a multiplier
# (ASSA-159, Maren's ruling of 2026-10-04). `build.py::darken_rim` applies it to
# the outer PART_RIM_PX rings of a part's ALPHA MASK, after the downscale to
# authoring size; `art/check_machine_vs_own_ore.py` is what holds it here.
#
# WHAT IT IS FOR. A building and the ore of its species wear the SAME `modulate`
# colour by construction (scene_view.gd:239 and :314 -> sprites.gd:226 ->
# hud.gd:200), and a drill must stand ON a deposit to run, so the first machine a
# player builds is drawn in the exact colour of the ground it stands on. The tint
# cancels out of the ratio, which makes this a property of the greyscale sheets:
# shipped, a planted machine was 1.49 : 1 against the ore of its own species and
# 83% of its silhouette pixels sat under 3 : 1.
#
# WHY A RIM ON THE ALPHA MASK AND NOT ONE OF THE TWO OBVIOUS LEVERS, both
# rendered and both measured short:
#   - DARKENING THE PART (material or fill light) pays the ratio out of the same
#     pixels that name the species. Reaching 3 : 1 on medians costs the species
#     read: worst pair dE 8.2 against species_probe's DISTINCT of 12.
#   - THICKENING THE FREESTYLE LINE inks every crease as well as the silhouette,
#     so it buys interior detail nobody asked for with body brightness
#     (114 -> 61), and it still left 16% of the edge under the bar. It also costs
#     frame space: at 2px the body of `frame` and `handle` lands ON the west frame
#     edge and `art/check_part_frame_fit.py` goes red (ASSA-104 ruled against
#     buying sideroom, because it shrinks the pack icon).
# A rim on the alpha mask touches the silhouette and nothing else, so the body
# that names the material is untouched: worst species pair dE goes 14.48 -> 12.52,
# still clear of 12.
#
# WHY 2 PX AND WHY k = 0.15 -- both pinned by measurement, not chosen -- is in
# `part_layout.py` beside the numbers.
#
# THE NUMBERS THEMSELVES LIVE IN `part_layout.py`, re-exported here so an asset
# script reads one name: `check_part_contract.py` needs the width too (the rim is
# ink, and a shadow check that did not know that would call a part's own outline a
# contact shadow), and that check runs outside Blender where this file cannot be
# imported at all.
PART_RIM_PX = _RIM_PX
PART_RIM_K = _RIM_K


def srgb(h):
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return tuple(((c / 12.92) if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4) for c in (r, g, b))


_mats = {}


def mat(color, rough=0.75, metal=0.0, emit=0.0, emit_color=None):
    """Material for a palette name (or hex). Cached per (color, params).

    `emit_color` is the colour of the LIGHT, which is not always the colour of
    the surface. It defaults to the surface's own colour -- right for a lamp,
    where the hue IS the signal -- but see `graded_accent`: an emissive
    SATURATED surface does not get brighter, it slides sideways into another
    hue, because the channels clip one at a time."""
    key = (color, rough, metal, emit, emit_color)
    if key in _mats:
        return _mats[key]
    hexcol = PALETTE.get(color, color)
    m = bpy.data.materials.new(f"{color}_{rough}_{metal}_{emit}_{emit_color}")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(hexcol), 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Specular IOR Level"].default_value = 0.3
    if emit:
        b.inputs["Emission Color"].default_value = (
            *srgb(PALETTE.get(emit_color, emit_color) if emit_color else hexcol), 1)
        b.inputs["Emission Strength"].default_value = emit
    _mats[key] = m
    return m


def steel():
    return mat("steel", rough=0.45, metal=0.6)


# ------------------------------------------------------------------ grade
#
# THREE STEPS, C/B/A -- the sim's `Grade`, not GAME.md's four purity tiers,
# which are about DEPOSITS. A part is kind + species + grade, and grade is
# three, so a four-step look would invent a distinction the player can never
# act on (Maren's ruling, ASSA-11).
#
# ONE GEOMETRY, GRADE AS A PARAMETER, the lever `ore.py` already uses for
# tiers: dull toward the dark shade low, full colour high, an emissive glint
# at the top. Three drawings of a part would be three things to keep in step,
# and the point of a part is that it is one shape.
#
# SPECIES IS NOT HERE AND MUST NOT BE. A world rolls six species at seed time
# with generated sheets, so there is nothing to bake; species is colour the
# client applies at runtime over these neutral pieces.
GRADES = ("C", "B", "A")
GRADE_DULL = (0.45, 0.15, 0.0)      # mixed toward GRADE_SHADE
GRADE_SHADE = "gun"
GRADE_GLINT = (0.0, 0.0, 2.5)       # emission on the part's warm accent, A only
GRADE_GLINT_COLOR = "glint"         # ...and the LIGHT is neutral. See below.

# WHICH PARTS WEAR A WARM MARK, and it is not "all of them".
#
#   A PART WEARS A VISIBLE WARM MARK IF AND ONLY IF ITS GRADE CHANGES A NUMBER
#   IN SIM.
#
# Both halves of that are load-bearing. The "only if" is the half I got wrong
# first: I had generalised to "every part needs a warm mark", because I had
# just found the handle rendering grade as tone alone -- mean luminance apart,
# but the peak clipped at 255 for both B and A, so the top two steps were
# indistinguishable at 32 px. That part did need one. The fix is not a rule
# about parts, it is a rule about what the glint PROMISES.
#
# The head, the handle (which is the held frame) and the planted frame all have
# grade setting strength, and so budget and durability. Their glint is a promise
# the sim keeps: this grade does something. A hopper's grade is inert --
# capacity is flat, mass is size x density, and density never scales with grade
# -- so a glint on a hopper would advertise a difference that does not exist.
# See hopper.py, where the band is deliberately left where the camera cannot
# see it.
#
# A tone step alone is NOT a visible mark: it does not survive 32 px once the
# highlight clips. If a part's grade matters, give it a surface the glint can
# land on; if it does not, give it nothing and say so where the part is built.


def mix_hex(a, b, t):
    a, b = PALETTE.get(a, a), PALETTE.get(b, b)
    return "#" + "".join("%02x" % round(int(a[i:i + 2], 16) * (1 - t) + int(b[i:i + 2], 16) * t)
                         for i in (1, 3, 5))


def graded(color, g, **kw):
    """`mat` for a part body at grade index g (0=C, 1=B, 2=A)."""
    t = GRADE_DULL[g]
    return mat(mix_hex(color, GRADE_SHADE, t) if t else color, **kw)


def graded_accent(color, g, **kw):
    """The one warm mark a part wears, which is where grade is loudest: dulled
    at C, as drawn at B, and glinting at A. The glint is the top step's whole
    signal at 1x -- a tone difference alone does not survive 32 px.

    THE GLINT BLOWS OUT TO NEUTRAL, AND THE COLOUR IS NOT A CHOICE (Decision
    #37, Maren). An emissive SATURATED surface does not get brighter, it
    slides into a different hue: `orange` #F08A24 at strength 2.5 clips R and
    G at the ceiling and leaves B behind at 89, so the brightest pixels of
    frame/A came out rgb(255, 254, 89). That is species3's yellow, dE76 10.9
    from its grade-C ore, under species_probe's DISTINCT of 12. Nobody picked
    that hue. The clip picked it, the same way ore.py's `_edge` variant
    invented a gradient the sim did not have (ASSA-26).

    Which makes it a RULE rather than a repaint, because the cause is general:
    every saturated hue in this game now belongs to a species (Decision #36),
    so ANY clipped saturated emitter lands on one of them -- it is only a
    question of which. Emission is intensity, not hue, so the ladder
    (dulled -> as drawn -> glinting) is untouched and legal; what is illegal
    is a saturated hue in the blowout. A neutral blowout clips to white, and
    no species tint is neutral.

    A LAMP IS NOT A GLINT and keeps its own colour (`lamp`): the cyan of a
    powered machine IS the information, and it measures clear of all six
    species on real sprites (drill/idle mark dE 49.5, spawn/pad 53.5).
    Enforced on the packed sheets by art/loudness.py, measure C."""
    return mat(mix_hex(color, GRADE_SHADE, GRADE_DULL[g]) if GRADE_DULL[g] else color,
               emit=GRADE_GLINT[g],
               emit_color=GRADE_GLINT_COLOR if GRADE_GLINT[g] else None, **kw)


def lamp(color="cyan"):
    return mat(color, emit=6)


# ---------------------------------------------------------------- scene setup

class Rig:
    def __init__(self, samples=64, outlines=True):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        _mats.clear()
        self.scene = sc = bpy.context.scene
        self.model = bpy.data.collections.new("Model"); sc.collection.children.link(self.model)
        self.env = bpy.data.collections.new("Env"); sc.collection.children.link(self.env)
        self._parent = None

        # THE KEY NO LONGER CASTS THE SHADOW. That is the whole fix, and it is
        # why nothing else about the lighting had to move: the key stays where
        # it was (42 degrees, same colour, same energy), so every existing
        # sprite keeps the modelling it was approved with, and a separate lamp
        # owns the shadow. Tying the two together is what made the shadow
        # un-fixable -- shortening it meant flattening the key, and lightening
        # it meant washing out the forms.
        key = bpy.data.lights.new("key", "SUN"); key.energy = 3.2
        key.angle = math.radians(8); key.use_shadow = False
        k = bpy.data.objects.new("key", key); sc.collection.objects.link(k)
        k.rotation_euler = (math.radians(42), math.radians(-18), math.radians(-30))

        # THE SHADOW LAMP: the only thing in the scene that casts. Nearly
        # overhead so the shadow sits UNDER the object rather than beside it,
        # soft so its edge is not read as geometry, and weak because the
        # catcher's alpha is this lamp's SHARE of the total light -- which is
        # the opacity knob, now independent of how the object is modelled.
        sun = bpy.data.lights.new("sun", "SUN")
        sun.energy = SHADOW_ENERGY; sun.angle = SUN_SOFTNESS
        s = bpy.data.objects.new("sun", sun); sc.collection.objects.link(s)
        s.rotation_euler = (SUN_TILT, 0, math.radians(-30))

        # Fill light comes from shadowless lamps, not the sky: sky light would
        # make the shadow catcher record a soft AO halo that gets cut off at
        # the frame edge. The world stays black.
        sc.world = bpy.data.worlds.new("w"); sc.world.use_nodes = True
        sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
        for rot, energy, color in (((math.radians(20), math.radians(15), math.radians(150)), 1.4, (0.62, 0.74, 1.0)),
                                   ((0, 0, 0), 0.9, (0.75, 0.8, 0.95))):
            fill = bpy.data.lights.new("fill", "SUN"); fill.energy = energy; fill.color = color
            fill.angle = math.radians(60); fill.use_shadow = False
            f = bpy.data.objects.new("fill", fill); sc.collection.objects.link(f); f.rotation_euler = rot

        sc.render.engine = "CYCLES"
        sc.cycles.samples = samples; sc.cycles.use_denoising = True
        sc.cycles.device = "CPU"
        if os.environ.get("ART_GPU"):  # Metal works when Blender can init it; opt in, it can hang headless
            prefs = bpy.context.preferences.addons["cycles"].preferences
            prefs.compute_device_type = "METAL"; prefs.get_devices()
            for d in prefs.devices: d.use = True
            sc.cycles.device = "GPU"
        sc.render.image_settings.file_format = "PNG"; sc.render.image_settings.color_mode = "RGBA"
        # HEADROOM: THE TOP THIRD OF THE PALETTE WAS NOT PRINTABLE (ASSA-115).
        #
        # `Standard` is a hard clip at 1.0, and these four lamps put a lit
        # face about a stop over it. Measured on this rig -- `art/
        # headroom_probe.py` renders the SAME rock geometry at a ramp of
        # neutral albedos and reads the lit body back:
        #
        #   albedo      174  183  192  201  210  219  228  237  246  255
        #   Standard    215  225  237  248  255  255  255  255  255  255
        #   % at 254+   0.0  0.0 17.2 36.1 60.0 73.6 90.4 90.9 94.1 96.4
        #
        # So every albedo from 192 up renders as the same white, and 15.7% of
        # ALL shipped pixels were sitting on the ceiling with no shading left
        # in them -- which under the client's multiply tint is not "bright",
        # it is "exactly the species hex". THAT is one cause for all three
        # symptoms: ASSA-28's grade-A chassis matching the hoppers, the
        # grade-A glint landing on a species yellow, and 34% of a grade-A ore
        # tile going flat (Maren, ASSA-115).
        #
        # IT CANNOT BE FIXED IN THE PALETTE, and that is why this line moved
        # rather than a colour. Grade C's lightest rock is already albedo 173
        # against a ceiling of 183 -- C is held UP by rule 3 in ore.py (a
        # multiply scales species differences by its own factor, so a dark
        # rock is a small gap between two species). Ten units of room, three
        # grades to fit in it: the ladder does not fit under this exposure,
        # so the exposure is the defect.
        #
        # WHY THIS TRANSFORM AND NOT LESS LIGHT. Cutting the lamps a stop
        # fixes the clip by darkening everything -- the ground's median goes
        # 142 -> ~105. `Khronos PBR Neutral` is a shoulder instead: it leaves
        # the midtones where they were and rolls off only the top.
        #
        #   albedo      120  138  156  174  183  192  210  228  246  255
        #   Khronos     143  165  187  210  220  230  240  245  248  248
        #   vs Standard  -9   -8   -7   -5   -5  +recovered, monotonic, 0% clipped
        #
        # Filmic was measured too and REJECTED: it crushes the whole ramp
        # into 155-221, which buys headroom by spending contrast everywhere.
        # AND IT IS NOT A PURE SHOULDER, so it comes with a compensation.
        # Khronos pulls the whole curve down a little, not just the top: on the
        # ramp above every midtone lost 5-9 of 255. Uncompensated that is a
        # change to art nobody asked me to change -- the ground's median had
        # just been judged at 142 (ASSA-115 part 1) and would have arrived at
        # 135 with no note. Worse, it is not cosmetic at the BOTTOM: the
        # hopper's shaded interior fell from 1 opaque pixel under
        # `part_layout.SHADOW_CEILING` to 305, and that ceiling is a SHIPPED
        # CONTRACT -- `part_layout.json` tells the client that anything below
        # it is contact shadow, to be composited alpha-MAX. A surface drifting
        # under it does not just fail `check_part_contract.py`, it makes the
        # client composite the inside of a hopper as a shadow.
        #
        # +0.2 stops puts the midtones back (linear 143 -> 152 is +0.195) and
        # the shoulder absorbs it at the top, which is the whole point of
        # having one. Measured after, on the shipped sheets, not predicted.
        sc.view_settings.view_transform = "Khronos PBR Neutral"
        sc.view_settings.exposure = 0.2
        sc.render.pixel_aspect_x = 1 / COS; sc.render.pixel_aspect_y = 1.0

        sc.render.use_freestyle = outlines
        if outlines:
            fs = sc.view_layers[0].freestyle_settings
            fs.crease_angle = math.radians(125)
            for old in list(fs.linesets): fs.linesets.remove(old)
            ls = fs.linesets.new("model")
            ls.select_silhouette = ls.select_border = ls.select_crease = True
            ls.select_by_collection = True; ls.collection = self.model
            ls.linestyle.color = srgb(PALETTE["line"])
            # ~1px after the SS downscale -- ON THE SHEET, WHICH IS NOT THE LAST
            # DOWNSCALE (ASSA-172). `scene_view.gd::_place` draws parts at scale 0.5
            # with NEAREST filtering, so this line arrives on 278 of 402 silhouette
            # pixels (69%) and is sampled away on the rest. Widening it here is NOT the
            # fix and was measured: it inks creases as well as the silhouette, and at
            # 2px the body of `frame` and `handle` lands on the west frame edge
            # (ASSA-159). What a machine's silhouette gets instead is PART_RIM_PX, which
            # is a post-process on the alpha mask and touches no crease.
            sc.render.line_thickness = ls.linestyle.thickness = 0.35 * SS

    # ------------------------------------------------------------ primitives
    def _place(self, o, coll, m, bev, seg=4):
        for c in o.users_collection: c.objects.unlink(o)
        coll.objects.link(o)
        if m is not None:
            o.data.materials.append(m)
        if bev:
            mod = o.modifiers.new("bev", "BEVEL"); mod.width = bev; mod.segments = seg
            mod.limit_method = "ANGLE"
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
        if self._parent is not None:
            o.parent = self._parent
        return o

    def box(self, size, loc, m, bev=0.04, rot=(0, 0, 0), env=False):
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
        o = bpy.context.object; o.scale = size
        return self._place(o, self.env if env else self.model, m, bev)

    def cyl(self, r, h, loc, m, bev=0.02, verts=48, rot=(0, 0, 0), env=False):
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, vertices=verts, rotation=rot)
        return self._place(bpy.context.object, self.env if env else self.model, m, bev)

    def cone(self, r1, r2, h, loc, m, bev=0.01, verts=48, rot=(0, 0, 0)):
        bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=h, location=loc, vertices=verts, rotation=rot)
        return self._place(bpy.context.object, self.model, m, bev)

    def rock(self, r, loc, m, sub=1, squash=0.55, rot=None, env=True):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=r, location=loc)
        o = bpy.context.object; o.scale.z = squash
        o.rotation_euler = rot or (0, 0, random.random() * math.tau)
        return self._place(o, self.env if env else self.model, m, 0)

    def pipe(self, a, b, r, m, flanges=True):
        a, b = Vector(a), Vector(b); d = b - a
        o = self.cyl(r, d.length, (a + b) / 2, m, bev=0)
        o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        if flanges:
            for p in (a, b): self.cyl(r * 1.35, 0.06, p, mat("gun"), bev=0.005)
        return o

    def bolt(self, loc, r=0.035):
        return self.cyl(r, 0.04, loc, steel(), bev=0.008, verts=8)

    def empty(self, loc=(0, 0, 0), parent=None):
        e = bpy.data.objects.new("empty", None); self.scene.collection.objects.link(e)
        e.location = loc; e.parent = parent
        return e

    def group(self, parent):
        """Context: primitives created inside are parented to `parent`."""
        rig = self

        class _G:
            def __enter__(s): rig._parent = parent
            def __exit__(s, *a): rig._parent = None
        return _G()

    def ground(self, size, color="ground", z=0.0):
        bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, z))
        return self._place(bpy.context.object, self.env, mat(color), 0)

    def shadow_catcher(self, size=12):
        bpy.ops.mesh.primitive_plane_add(size=size)
        o = bpy.context.object; o.is_shadow_catcher = True
        return self._place(o, self.env, None, 0)

    def bounce(self, size=12):
        """The ground as a LIGHT SOURCE ONLY: it bounces, it records no shadow.

        For a part that never touches the ground (ASSA-64). Dropping
        `shadow_catcher()` from head and hopper removed the shadow AND the
        biggest fill in the scene with it -- measured on the first attempt, the
        hopper went from 15% of its pixels under L*35 to 81%, so the body
        joined its own well and `art/assemble.py`'s open-shape check went red.
        That is the catcher's SECOND job, which nobody had written down: a
        default-material plane under a key light at 9 degrees is most of what
        lights the underside of these parts.

        So the plane stays, with the same default albedo, and only the two
        flags that make it a shadow change: it is not a catcher, and the camera
        cannot see it.
        """
        bpy.ops.mesh.primitive_plane_add(size=size)
        o = bpy.context.object
        o.is_shadow_catcher = False
        o.visible_camera = False
        return self._place(o, self.env, None, 0)

    # ---------------------------------------------------------------- camera
    def frame(self, tiles_w, tiles_h, headroom=0.0, center=(0, 0)):
        """Frame a footprint of tiles_w x tiles_h tiles centred on `center`,
        plus `headroom` tiles above it for tall geometry. Returns the raw
        render size in px."""
        sc = self.scene
        res_x = int(round(tiles_w * TILE_PX * SS))
        res_y = int(round((tiles_h + headroom) * TILE_PX * SS))
        sc.render.resolution_x, sc.render.resolution_y = res_x, res_y
        a, b = res_x * sc.render.pixel_aspect_x, res_y * sc.render.pixel_aspect_y
        ortho = tiles_w if a >= b else tiles_w * b / a
        cam = sc.camera
        if cam is None:
            data = bpy.data.cameras.new("cam"); data.type = "ORTHO"
            cam = bpy.data.objects.new("cam", data); sc.collection.objects.link(cam); sc.camera = cam
        cam.data.ortho_scale = ortho
        # the frame's vertical centre sits headroom/2 tiles north of the footprint centre
        tx, ty = center[0], center[1] + headroom / 2
        cam.location = (tx, ty - 20 * math.sin(TILT), 20 * math.cos(TILT))
        cam.rotation_euler = (TILT, 0, 0)
        return res_x, res_y

    def part_window(self):
        """EVERY part's camera window, so rule 4b cannot land on three parts of four.

        The frame is `PART_TILES` + `PART_HEADROOM`, exactly as before; only the centre
        moves, `PART_SHIFT_PX` WEST, which puts the subject that many px EAST inside the
        same rectangle. An asset script calls this instead of `frame()` and therefore
        cannot forget the offset or pick its own -- which would be a machine that comes
        apart by 3 px, and nothing in the pipeline would say so.
        """
        return self.frame(PART_TILES[0], PART_TILES[1], headroom=PART_HEADROOM,
                          center=(-PART_SHIFT_PX / TILE_PX, 0))

    def render(self, path, transparent=True):
        sc = self.scene
        sc.render.film_transparent = transparent
        os.makedirs(os.path.dirname(path), exist_ok=True)
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        return path


# ------------------------------------------------------------------ output

class Asset:
    """Collects rendered frames for one asset and writes its manifest.

    Layout on the packed sheet (done by build.py): one row per sprite, one
    column per frame. `tiles` is the footprint; `anchor` is where the
    footprint's top-left tile corner sits in the frame, in authoring px.
    """

    def __init__(self, name, out_root, tiles, headroom=0.0, anchor_x=0, block=None, rim=None,
                 fill=None):
        self.name = name
        self.dir = os.path.join(out_root, name)
        os.makedirs(self.dir, exist_ok=True)
        self.tiles = list(tiles)
        self.frame_px = [int(tiles[0] * TILE_PX), int(round((tiles[1] + headroom) * TILE_PX))]
        # `anchor_x` moves with the camera window, never on its own: if the window looks
        # PART_SHIFT_PX west, the footprint's corner sits that many px east in the frame.
        # Letting these two disagree would draw every machine off its tile (rule 4b).
        self.anchor = [int(anchor_x), int(round(headroom * TILE_PX))]
        # A TILE SHEET'S ROWS ARE A BLOCK, NOT A BAG, and the sheet is the only thing
        # that knows which (ASSA-115 box 2). `block` = (w, h) says: these w*h rows are
        # row-major cells of ONE continuous w x h-tile picture, so a renderer must place
        # cell (x mod w, y mod h) at tile (x, y) and may NOT pick one at random. The
        # alternative was a literal in the client, which is `scene_view.gd::ore_row`'s
        # recorded mistake: a count hardcoded there silently shipped new rows to nobody.
        # Absent (the normal case) the rows are interchangeable and a hash picks one.
        self.block = list(block) if block else None
        # (px, k): darken the outer `px` rings of this asset's alpha mask by `k` after
        # the downscale (PART_RIM_PX / PART_RIM_K has why). A POST-PROCESS and not a
        # render setting, because the ring is defined on the alpha mask the sheet ends
        # up with -- Blender does not know where the silhouette will land after LANCZOS.
        # It travels in asset.json so `--pack` applies it too: a repack that quietly
        # dropped the rim would ship art that fails its own CI check.
        self.rim = list(rim) if rim else None
        # "top": THIS SHEET'S FRAMES ARE ICON BOXES, NOT TILE WINDOWS, so `pack()` fits
        # each frame's paint to its box -- aspect preserved, top edge at y=0, slack at the
        # BOTTOM (ASSA-376, Maren's rule: "a frame's own transparency is air, and ASSA-328
        # governs it"). Only an asset whose frames are never used to place a thing on the
        # ground may say this: the fit moves the art inside the frame, so a sheet whose
        # `anchor_px`/`tiles` a renderer READS would come off its tile. `items` qualifies
        # because `sprites.gd::_frame_from` takes the whole frame and no anchor term, and
        # because nothing composites it (`sprites.gd:78` -- that is the part sheets).
        # Like `rim`, it travels in asset.json so `--pack` applies it too.
        self.fill = str(fill) if fill else None
        self.slice = None
        self.rows = []
        self.animations = {}
        self.derive = []

    def path(self, row, frame=0):
        return os.path.join(self.dir, f"{row}_{frame:02d}.png")

    def add(self, row, frames):
        self.rows.append({"name": row, "frames": frames})

    def light_row(self, row, body, lit):
        """A row that is EMITTED LIGHT rather than material (ASSA-137, Maren's rule).

        The client tints a placement with Godot `modulate`, a per-channel MULTIPLY by the
        species colour. That is right for a wall, which is made of the species, and wrong
        for a fire, which is not: a multiply can only subtract, so a pixel standing for
        emitted light gets capped by a quantity it has nothing to do with. Measured on the
        shipped smelter, the brightest pixel of a burning fire came out DARKER than the
        ground in three of the six species. Maren's tripwire: a quantity the sim treats as
        independent of species may not be drawn in a channel species multiplies.

        So the lit state is split in two. `body` is the material and keeps its tint; this
        row is the light and is drawn over it at `Color.WHITE`. It is DERIVED rather than
        rendered -- `build.py` subtracts the two rendered rows at authoring size -- so the
        untinted picture is bit-for-bit the one that was approved, not a new one to judge.

        The row carries `"light": true` and `"over": <body row>` into the manifest, and
        those two are the whole contract: a renderer draws `over` with the species tint
        and this row on top of it at `Color.WHITE`, never the other way round and never
        with a tint on this one. The pairing is in the data because the client needs it
        to place the second draw, and because a guard that had to guess which row a light
        row belongs to would be guessing about the thing it is checking.

        IF THE DERIVATION EVER STOPS BEING FAITHFUL, the principled replacement is a Cycles
        LIGHT GROUP on the emitter rendered as its own AOV, composited additively. It needs
        a blend mode the client does not have yet, which is the only reason it is not this.
        """
        self.derive.append({"row": row, "kind": "light", "body": body, "lit": lit})
        self.rows.append({"name": row, "frames": 1, "light": True, "over": body})

    def slice_from(self, row, margin_px=0):
        """THE ROWS ARE CUT OUT OF ONE RENDER, AFTER IT IS DOWNSAMPLED. (ASSA-115 box 2)

        For a `block`: rendering each cell on its own looked equivalent to rendering the
        field once, and was not. A cell rendered alone is its own IMAGE -- Cycles denoises
        it as an image, `build.py` resamples it as an image -- and both are truncated at its
        border. On the sheet that made, two rows across a cell boundary stepped +0.401 of
        255 more than two rows inside a cell, enough to leave the true tile offset rank 1 of
        32 on the findability test. The geometry was continuous and the pipeline put the
        seam back.

        So the asset script renders the whole field to ONE raw frame and names it here, and
        `pack()` downsamples that frame and then cuts the cells. The order is the whole
        point: cropping first would reintroduce the border this removes.

        `margin_px` is authoring px of NEIGHBOURING field rendered on every side and
        thrown away after the resize, so the image's own edge -- the last border in the
        pipeline -- falls outside the shipped picture. Without it the field's wrap join
        measured +0.844 of 255 against +0.078 at an interior cell boundary.
        """
        self.slice = {"source": row, "margin": int(margin_px)}

    def anim(self, name, frames, fps):
        self.animations[name] = {"frames": frames, "fps": fps}

    def write(self):
        meta = {"name": self.name, "tiles": self.tiles, "frame_px": self.frame_px,
                "anchor_px": self.anchor, "rows": self.rows,
                "animations": self.animations, "derive": self.derive}
        # Only when there IS one, so no other asset's manifest entry moves a byte.
        if self.block:
            meta["block"] = self.block
        if self.rim:
            meta["rim"] = self.rim
        if self.fill:
            meta["fill"] = self.fill
        if self.slice:
            meta["slice"] = self.slice
        with open(os.path.join(self.dir, "asset.json"), "w") as f:
            json.dump(meta, f, indent=1)


def args():
    """(out_root) from the command line after `--`."""
    import sys
    return sys.argv[sys.argv.index("--") + 1]


def part_asset(name, out_root):
    """EVERY part's Asset (rule 4b). One frame rectangle, one anchor, for the whole set.

    `art/assemble.py` asserts that all parts share one frame size AND one anchor, because
    overlaying is how a machine is assembled. This is the single place that decides both,
    so that assertion can never be satisfied by three parts agreeing and one drifting.
    """
    return Asset(name, out_root, PART_TILES, headroom=PART_HEADROOM, anchor_x=PART_SHIFT_PX,
                 rim=(PART_RIM_PX, PART_RIM_K))
