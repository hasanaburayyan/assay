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

# Flat, saturated palette. Few colours, high contrast. Add here, not in assets.
PALETTE = {
    "orange": "#F08A24", "orange_dk": "#B85A12", "gun": "#2E333B", "grey": "#6F7883",
    "steel": "#B9C2CC", "cyan": "#3FD8FF", "brass": "#E2B04A", "rubber": "#1B1D22",
    "ground": "#6E7A4E", "ground_dk": "#5F6B43", "ground_ore": "#57603F",
    "skin": "#E0B48C", "suit": "#F08A24", "visor": "#3FD8FF",
    # ore kinds: base / dark / accent (accent is the high-purity glint)
    "iron": "#8FA7C4", "iron_dk": "#4C5C73", "iron_hi": "#DCEBFF",
    "copper": "#D9772E", "copper_dk": "#8A4517", "copper_hi": "#5FE0B0",
    "coal": "#33363D", "coal_dk": "#1B1D22", "coal_hi": "#FF8A3C",
    "stone": "#B8AE94", "stone_dk": "#7B7461", "stone_hi": "#FFF2C0",
    "line": "#1A1D23",
}
ORE_KINDS = ["iron", "copper", "coal", "stone"]

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

        sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 3.2; sun.angle = math.radians(8)
        s = bpy.data.objects.new("sun", sun); sc.collection.objects.link(s)
        s.rotation_euler = (math.radians(42), math.radians(-18), math.radians(-30))
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
