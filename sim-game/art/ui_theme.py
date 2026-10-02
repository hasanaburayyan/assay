"""Colours the CLIENT draws that are not in any sprite. (ASSA-71)

Right now there is exactly one: the plate behind a pack-row icon.

WHY THIS IS DERIVED FROM A SHEET AND NOT WRITTEN DOWN. Maren's ruling on
ASSA-71 is that the plate is "the ground's own colour", so that a stack in the
pack and a rock on the map read as the SAME OBJECT. That is a statement about
`ground.png`, not about a hex: the day the ground is re-rendered a little
greener, a hex typed anywhere stops being the ground's colour and nobody finds
out. So the number is computed from the shipped sheet on every build, the same
way `part_layout.json` is computed from the module the rig uses rather than
copied beside it (ASSA-54).

MEDIAN, NOT MEAN. The ground sheet has rock speckle on it. A mean is dragged
by the few darkest and lightest speckles; the median is the colour most of the
tile actually is, which is what "the ground's own colour" means to an eye.
Measured on the shipped sheet: median #88986C, mean #87976C -- close here, but
the median is the one that stays right if the speckle ever gets heavier.

WHY NOT IN manifest.json, which is where ASSA-71 asked for it. The manifest's
top level is an ASSET NAMESPACE: `check_client_can_see_art.py` does
`man[a]["sheet"]` for every key, `test_sprites.gd` walks it both ways and fails
on "the manifest describes X and there is no X.png", and `build.py` ends with
`manifest = {k: manifest[k] for k in ORDER if k in manifest}` -- so a key that
is not an asset would break two checks AND be silently dropped by the next
build. Exactly the finding that put the part contract in its own file. This is
a sibling of the manifest for the same reason.
"""
import os
import statistics

# A pixel is ground rather than the transparent margin around it. The sheet is
# opaque where there is tile at all, so this only excludes the edges.
OPAQUE = 200

PLATE_RULE = (
    "the pack-row icon's slot plate. One constant colour for every species and "
    "every grade: it must never carry information, because a tinted plate is a "
    "second colour channel competing with the icon. The client draws it behind "
    "the icon's own box and nowhere else yet.")

PLATE_SOURCE = "per-channel median of the opaque pixels of ground.png"


def plate_rgb(sprites_dir):
    """(r, g, b) of the pack-icon plate, read off the SHIPPED ground sheet.

    Takes the directory rather than finding it, so the check and the build are
    provably reading the same file rather than each resolving a path.
    """
    from PIL import Image
    path = os.path.join(sprites_dir, "ground.png")
    pixels = [p for p in Image.open(path).convert("RGBA").getdata() if p[3] >= OPAQUE]
    if not pixels:
        raise SystemExit("ui_theme: %s has no opaque pixels, so it is not a ground sheet" % path)
    return tuple(int(statistics.median([p[i] for p in pixels])) for i in range(3))


def contract(sprites_dir):
    """What gets written to `ui_theme.json` beside the manifest."""
    rgb = plate_rgb(sprites_dir)
    return {
        "source": "art/ui_theme.py, from client/assets/sprites/ground.png",
        "pack_icon_plate_rgb": list(rgb),
        "pack_icon_plate_hex": "#%02X%02X%02X" % rgb,
        "pack_icon_plate_source": PLATE_SOURCE,
        "pack_icon_plate_rule": PLATE_RULE,
    }
