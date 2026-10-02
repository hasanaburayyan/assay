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
SUN_TILT = math.radians(9)
SUN_SOFTNESS = math.radians(30)
SHADOW_ENERGY = 0.9

# Flat, saturated palette. Few colours, high contrast. Add here, not in assets.
PALETTE = {
    "orange": "#F08A24", "orange_dk": "#B85A12", "gun": "#2E333B", "grey": "#6F7883",
    "steel": "#B9C2CC", "cyan": "#3FD8FF", "brass": "#E2B04A", "rubber": "#1B1D22",
    "ground": "#6E7A4E", "ground_dk": "#5F6B43", "ground_ore": "#57603F",
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
}

from species_tints import SPECIES_TINTS  # noqa: F401  (data, see that file)
from part_layout import PART_REPEAT_OFFSET  # noqa: F401  (rule 5, see that file)

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
#    is RED today on player/* and frame/A; which way that red clears is the
#    Director's call and is NOT to be painted over by an exemption.
LYING = (0, math.pi / 2, 0)
PART_TILES = (2, 1)
PART_AXIS = 0.28
PART_HEADROOM = 0.6


def srgb(h):
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return tuple(((c / 12.92) if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4) for c in (r, g, b))


_mats = {}


def mat(color, rough=0.75, metal=0.0, emit=0.0):
    """Material for a palette name (or hex). Cached per (color, params)."""
    key = (color, rough, metal, emit)
    if key in _mats:
        return _mats[key]
    hexcol = PALETTE.get(color, color)
    m = bpy.data.materials.new(f"{color}_{rough}_{metal}_{emit}")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(hexcol), 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Specular IOR Level"].default_value = 0.3
    if emit:
        b.inputs["Emission Color"].default_value = (*srgb(hexcol), 1)
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
    signal at 1x -- a tone difference alone does not survive 32 px."""
    return mat(mix_hex(color, GRADE_SHADE, GRADE_DULL[g]) if GRADE_DULL[g] else color,
               emit=GRADE_GLINT[g], **kw)


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
        sc.view_settings.view_transform = "Standard"
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
            # ~1px after the SS downscale
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

    def __init__(self, name, out_root, tiles, headroom=0.0):
        self.name = name
        self.dir = os.path.join(out_root, name)
        os.makedirs(self.dir, exist_ok=True)
        self.tiles = list(tiles)
        self.frame_px = [int(tiles[0] * TILE_PX), int(round((tiles[1] + headroom) * TILE_PX))]
        self.anchor = [0, int(round(headroom * TILE_PX))]
        self.rows = []
        self.animations = {}

    def path(self, row, frame=0):
        return os.path.join(self.dir, f"{row}_{frame:02d}.png")

    def add(self, row, frames):
        self.rows.append({"name": row, "frames": frames})

    def anim(self, name, frames, fps):
        self.animations[name] = {"frames": frames, "fps": fps}

    def write(self):
        with open(os.path.join(self.dir, "asset.json"), "w") as f:
            json.dump({"name": self.name, "tiles": self.tiles, "frame_px": self.frame_px,
                       "anchor_px": self.anchor, "rows": self.rows, "animations": self.animations}, f, indent=1)


def args():
    """(out_root) from the command line after `--`."""
    import sys
    return sys.argv[sys.argv.index("--") + 1]
