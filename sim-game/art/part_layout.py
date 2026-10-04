"""How parts are placed when a machine is assembled. DATA, not art.

In its own module for the same reason `species_tints.py` is: both the Blender
rig and the plain-python tools need these numbers, and importing `rig.py`
outside Blender dies on `import bpy`.

THE OFFSET RULE (rig.py rule 5)
-------------------------------
rig.py rule 2 says a machine is drawn by overlaying whole part sprites at ONE
frame position. That is right for parts that differ, and it cannot express a
COUNT. Measured in art/assemble.py: a drill's solid footprint at 1x went
1258 -> 1376 -> 1389 px for zero, one and two hoppers. The first hopper added
118 px of new shape and the second added 13, which is antialiased edges
hardening, not a part. The second hopper was invisible.

That matters because capacity is a real number in sim - `MAX_HOPPER_SLOTS`
frames' worth of `HOPPER_CAPACITY` - and the minimal demo's points 5 and 9
both turn on a player seeing that a drill has two. rig.py's own grade-glint
rule says a visible mark must correspond to a real difference; this is the
same rule pointing the other way, and the difference was real while the
picture stayed silent.

So: THE NTH REPEAT OF A PART KIND IS DRAWN AT n * PART_REPEAT_OFFSET, where n
counts from 0 in `Assembly::parts()` order - frame first, then the mounted
parts, which sim documents as "the one canonical order" and every rule that
has to pick a part already walks. Taking the order from sim rather than from
the renderer is what stops two peers drawing the same machine differently.

WHY (14, -6) AND NOT A ROUNDER NUMBER
  Swept, not chosen. Two bounds decided it:
  - Maren's test: the second hopper must add roughly the first's 118 px, not
    13. At (14, -6) it adds 109, which is 92%. Larger steps overshoot - at
    (22, -18) the second adds 267 px, which is not a part sitting on a
    machine, it is a part hanging off one.
  - It has to survive a FULL machine. `MAX_HOPPER_SLOTS` is 4, so the rule is
    judged at four, not at the two the demo happens to use. At (8, -8), which
    scored better on the first bound, the fourth hopper loses 122 px off the
    top of the frame rectangle. At (14, -6) nothing clips and the footprint
    grows 118 / 109 / 160 / 193 - every hopper adds at least 92% of the first.
  Up and to the east, because the frame body runs west and the head works
  east: repeats step back along the machine, the way a row of real hoppers
  would sit.

The frame rectangle is the hard limit. If a part kind ever gets more slots
than fit, the answer is a cap plus a number in the UI (Maren's option 2), not
a smaller offset that makes them invisible again.
"""

# Authoring pixels (TILE_PX 64). The game shows 32 at 1x, so this is a 7 x 3
# step on screen.
PART_REPEAT_OFFSET = (14, -6)

# WHAT COUNTS AS SHADOW RATHER THAN SURFACE, and it is read off the palette
# rather than picked. A pixel is shadow if its brightest channel is below this.
#
# The contact catcher writes RGB 0, so "exactly black" was my first rule -- and
# it was wrong by measurement, not in theory: 106 pixels of a six-part machine
# came out (2, 3, 5) or (0, 0, 1), shadow that has picked up a trace of the ink
# outline it lies against, and they went on compounding while the check called
# them geometry. The boundary that is not arbitrary is the PALETTE's own: the
# darkest colour rig.py can put on screen is #1B1D22, whose brightest channel
# is 34, so anything below 34 is darker than any surface the game owns and can
# only be shadow, or shadow with a trace of a surface mixed into it.
#
# art/assemble.py re-derives this from rig.py's palette on every run and fails
# if the two disagree, so adding a darker colour cannot silently turn a surface
# into shadow.
SHADOW_CEILING = 34

# WHOSE SHADOW IT IS (ASSA-64, Maren's ruling). A contact shadow means "this
# part stands on the ground", and only a PLANTED FRAME does. Head and hopper
# are mounted -- they exist only bolted to a frame -- and they carried the most
# shadow of the four parts (2473 and 2621 pixels per grade frame) while the
# planted frame carried the least (1718). They are rendered with no shadow
# catcher now.
#
# WHY THIS IS AN INVARIANT AND NOT A TIDY-UP: sim's `Design` is
# `{ frame: Part, mounted: Vec<Part> }`, exactly one frame enforced by the
# type, with `AssemblyError::FrameMounted` refusing a frame in a mounted slot.
# So once only frames carry shadow, a machine has EXACTLY ONE contact shadow by
# construction. `stack()` below still takes alpha MAX and `SHADOW_CEILING` is
# unchanged -- both stay because they cost nothing and a future ground-standing
# part would need them -- but a client that composites with plain `over` is now
# correct rather than lucky.
MOUNTED_PARTS_CARRY_NO_SHADOW = (
    "only a planted frame carries a contact shadow; mounted parts (head, "
    "hopper) are rendered without one. sim's Design has exactly one frame, so "
    "a machine has exactly one contact shadow and plain `over` cannot compound "
    "what is not there.")

# THE DARK RIM EVERY MACHINE PART WEARS, in authoring px and as a multiplier
# (ASSA-159, Maren's ruling of 2026-10-04). `build.py::darken_rim` multiplies the
# outer RIM_PX rings of a part's ALPHA MASK by RIM_K after the downscale to
# authoring size, and `art/check_machine_vs_own_ore.py` is what holds it there.
#
# WHAT IT IS FOR, in one line: a building and the ore of its own species carry the
# IDENTICAL `modulate` colour (scene_view.gd:239 and :314 -> sprites.gd:226 ->
# hud.gd:200) and a drill must stand ON a deposit to run, so without this the
# first machine a player builds is drawn in the exact colour of the ground under
# it -- measured, 1.49 : 1, with 83% of its silhouette under the 3 : 1 bar.
#
# IT LIVES HERE AND NOT IN `rig.py` for this module's own reason: the renderer, the
# packer and two CI checks all need it, and importing `rig.py` outside Blender dies
# on `import bpy`. `rig.py` re-exports it so an asset script reads one name.
#
# WIDTH AND DARKNESS ARE BOTH PINNED, not tuned. 1 px is sampled away on 31% of the
# silhouette by the client's NEAREST half-scale draw (a dotted line is not a mark);
# 3 px takes the worst species pair to dE 11.25 and the species read is lost. The k
# window is [0, ~0.19] and box 3 wants it HIGH, so 0.15 sits near the top of it.
RIM_PX = 2
RIM_K = 0.15

# HOW WIDE THE INK RIM IS, in authoring pixels, and why a shadow check needs to
# know. `rig.py` draws outlines with Freestyle at `line_thickness = 0.35 * SS`,
# which is a sub-pixel stroke once the SSx render is downscaled to authoring
# size -- but a sub-pixel stroke over transparency comes back from the
# compositor as NEARLY BLACK pixels (measured: 114 pixels of one grade frame are
# exactly (0,0,0)), so "dark" alone cannot tell a sprite's own outline from a
# shadow lying beside it. A dark pixel this far from any SURFACE pixel is not
# the outline. One pixel for the stroke, one for its antialiasing.
#
# PLUS `RIM_PX`, BECAUSE THE INK IS NOW WIDER BY DESIGN (ASSA-159). The rim above
# multiplies two rings of the alpha mask by 0.15, which puts them under
# SHADOW_CEILING: by this module's own definition they are not a surface, and they
# are not a shadow either -- they are the part's outline, drawn on purpose. DERIVED
# rather than re-picked, so the day the rim changes width this follows it; a
# constant bumped by hand to keep a check green is a check tuned to its own art.
#
# IT COSTS THE SHADOW GUARD ALMOST NOTHING. A contact shadow is a POOL: the ones
# ASSA-64 stripped off head and hopper ran 2473 and 2621 px at alpha 122-250, tens
# of authoring px out from the sprite. Four authoring px is two px at 1x, so the
# thing this guard was written to catch is still caught by an order of magnitude.
INK_RIM_PX = 2 + RIM_PX

# The most alpha a dark pixel out past the ink rim may carry before it counts as
# a shadow, and it is DERIVED rather than chosen. Sheets are downscaled from an
# SSx supersampled render, so ONE stray sample in a destination pixel comes out
# at 255/SS**2. Anything at or below that is less ink than a single sample of
# the render can produce; a real contact shadow covers whole pixels and arrives
# at alpha 122-250 (measured on the sheets this replaced). The stripped head and
# hopper come in at 2 and 1.
#
# SS is read out of `rig.py` rather than copied, because a constant copied out
# of another file has stopped being about that file. Text, not import: rig.py
# needs `bpy` and this module is imported by plain-python tools too.
def _supersample():
    import os
    import re
    rig_py = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rig.py")
    found = re.search(r"^SS\s*=\s*(\d+)", open(rig_py).read(), re.M)
    if not found:
        raise ValueError("no `SS = ` in rig.py, so the render's supersample factor is "
                         "unknown and the shadow bound below would be invented")
    return int(found.group(1))


SHADOW_NOISE_ALPHA = 255 // (_supersample() ** 2)


def stack(dst, src):
    """Overlay one part frame onto another: colour OVER, alpha MAX.

    THE SECOND HALF OF RULE 2, and it exists because the obvious operator was
    wrong (Maren's ruling, ASSA-38). Every part sprite carries its own contact
    shadow, so plain `alpha_composite` compounds those shadows: measured, the
    darkest shadow alpha under a machine went 122 -> 128 -> 145 -> 167 as parts
    were bolted on. That makes shadow darkness a readout of part count -- an
    invented gradient, chosen by the over-operator and by nobody, and exactly
    what rig.py's glint rule forbids in the other direction.

    Taking the MAX of the two alphas cannot compound: the darkest shadow a
    machine can have is the darkest shadow one of its parts has. Colour still
    composites OVER, so the nearer part still occludes the farther one and
    the join reads as it did.

    ALPHA-MAX APPLIES ONLY WHERE THE PIXEL COMES OUT BLACK, and that
    restriction is not caution, it is a measured cost. Taking the max
    everywhere also stops two parts' ANTIALIASED EDGES adding their coverage,
    which measurably thinned a six-part silhouette: 232 pixels, worst by
    80/255, enough to drop one of them under the threshold this pipeline calls
    solid. Invisible in the picture, but it is a silhouette paying for a
    shadow's problem, and there is no reason to spend it. Pure black is the
    contact shadow (the catcher writes RGB 0; the darkest thing in the palette
    is `line` #1A1D23, which is not black), so the rule reads: SHADOW DOES NOT
    ACCUMULATE, EVERYTHING ELSE COMPOSITES NORMALLY.

    If that colour test is ever wrong about a pixel, the cost is bounded: the
    pixel gets max instead of over, which is the operator above, which was
    already invisible. A misread cannot produce something worse than the
    version of this function I measured and rejected.

    PIL is imported inside the function on purpose: `rig.py` imports this
    module from inside Blender, whose Python has no Pillow.
    """
    from PIL import Image
    if dst.size != src.size:
        raise ValueError("stack() needs one frame rectangle, got %s and %s"
                         % (dst.size, src.size))
    w, h = dst.size
    out = Image.new("RGBA", (w, h))
    d, s, o = dst.load(), src.load(), out.load()
    for y in range(h):
        for x in range(w):
            dr, dg, db, da = d[x, y]
            sr, sg, sb, sa = s[x, y]
            if sa == 0:
                o[x, y] = (dr, dg, db, da)
                continue
            if da == 0 or sa == 255:
                o[x, y] = (sr, sg, sb, max(sa, da))
                continue
            # Straight-alpha `over` for the colour, then the alpha is replaced
            # by the max. Normalising by the over-alpha keeps the blend itself
            # unchanged, so this is the same picture with a different coverage.
            ia = sa / 255.0
            ib = (da / 255.0) * (1.0 - ia)
            tot = ia + ib
            r = int(round((sr * ia + dr * ib) / tot))
            g = int(round((sg * ia + dg * ib) / tot))
            b = int(round((sb * ia + db * ib) / tot))
            # Darker than any surface the palette owns: shadow, so take the max
            # and it cannot compound. Anything else is geometry and composites
            # `over` exactly as it always did.
            a = (max(sa, da) if max(r, g, b) < SHADOW_CEILING
                 else int(round(tot * 255)))
            o[x, y] = (r, g, b, min(255, a))
    return out
