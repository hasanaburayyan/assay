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

A 10% TRIMMED MEAN. NOT A MEDIAN, AND NOT A BARE MEAN (ASSA-261, Maren's call).

This said "MEDIAN, NOT MEAN" until ASSA-150 put a cross-tile mottle on the
ground, and then the median broke in the one way nobody had priced: it moved
-8.57 L while the surface it describes moved +0.97 L. The cause is not the
mottle, it is what the median was standing on. The old ground piled 32.5% of
its pixels on ONE luminance level and the median sat on that spike, so
shattering the spike moved the statistic nine times further than it moved the
ground. **A statistic pinned to the ground being flat, chosen while the ground
happened to be flat.**

The old reasoning was still RIGHT about the thing it was about: "a mean is
dragged by the few darkest and lightest speckles". That is an OUTLIER argument,
and it survives here instead of being thrown away with the median -- which is
why this is a trimmed mean and not the bare mean that also tracks the surface.

WHY 10% AND NOT A ROUND NUMBER SOMEBODY LIKED. Measured, both halves, on the
real pre-mottle and shipped sheets (`shared/assay/cove-assa261/`, plate_tail.py):

  - HOW FEW ARE "THE FEW SPECKLES"? On the shipped sheet, 0.29% of pixels lie
    beyond 2 robust sigma and 0.02% beyond 2.5. The tail a trim has to be
    bigger than is well under 1% of the sheet.
  - DRIFT UNDER HEAVIER SPECKLE, swept over outlier mass x trim fraction: a
    trim of f holds while the outlier mass stays under f, and 10% is the
    LOWEST-DRIFT trim at every outlier mass from 0.5% to 5% -- 5 to 17 times
    the tail actually present. At 2% outlier mass the bare mean drifts -1.80 L
    and this drifts -0.38 L.
  - TRACKING THE SURFACE: it moves +0.898 L where the surface moves +0.968,
    an error of 0.07 of a level. The median's error is 9.54.

So 10% is an argmin between two failures and not a taste: trim less and the
speckle gets through (2% drifts -3.16 at 5% outlier mass), trim more and the
spike-pinning comes back (25% errors -1.04 against the surface, 40% errors
-6.82). Anything from 5% to 15% would do; 10% sits in the middle of that band
so an honest re-render that shifts the tail a little falls off neither edge.

ROUND, NOT TRUNCATE, AND THAT IS PART OF THE FIX. A median of integers lands
on an integer or a .5, so `int()` cost nothing. A mean lands anywhere, so
truncating it biases the plate DOWN by about half a level in every channel on
every build -- a systematic darkening introduced by the pipeline rather than by
the art. It is also why ASSA-150 §10 reported the surface moving "+0.36" and a
rerun said "+1.00": the same two sheets, differing only by int() vs round(),
because the surface's real move is smaller than one level.

PER CHANNEL, like the median it replaces: R, G and B are trimmed separately, so
the plate is a computed colour and not a pixel picked off the sheet. Unchanged
in kind from what shipped before; said out loud because it is easy to assume
otherwise.

WHY NOT IN manifest.json, which is where ASSA-71 asked for it. The manifest's
top level is an ASSET NAMESPACE: `check_client_can_see_art.py` does
`man[a]["sheet"]` for every key, `test_sprites.gd` walks it both ways and fails
on "the manifest describes X and there is no X.png", and `build.py` ends with
`manifest = {k: manifest[k] for k in ORDER if k in manifest}` -- so a key that
is not an asset would break two checks AND be silently dropped by the next
build. Exactly the finding that put the part contract in its own file. This is
a sibling of the manifest for the same reason.

STDLIB ONLY, deliberately. `build.py` runs under `uv` with Pillow, but the CI
check that keeps this honest runs on plain `python3` with no pip, exactly like
`check_part_contract.py`. If the derivation lived here in Pillow and again in
the check in stdlib, there would be two implementations of the shipped colour
that can disagree -- the "two readers" failure this pipeline keeps getting
bitten by. So it is written once, in the decoder both can use. That constraint
also ruled out every candidate statistic needing numpy.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from png_stdlib import read_rgba  # noqa: E402  (after sys.path, on purpose)

# A pixel is ground rather than the transparent margin around it. The sheet is
# opaque where there is tile at all, so this only excludes the edges.
OPAQUE = 200

PLATE_RULE = (
    "the pack-row icon's slot plate. One constant colour for every species and "
    "every grade: it must never carry information, because a tinted plate is a "
    "second colour channel competing with the icon. The client draws it behind "
    "the icon's own box and nowhere else yet.")

# Fraction of the sorted values cut from EACH end before averaging. Chosen by the
# measured sweep in the docstring, not by taste; the safe band is 0.05 to 0.15.
PLATE_TRIM = 0.10

PLATE_SOURCE = ("per-channel %d%% trimmed mean of the opaque pixels of ground.png"
                % round(PLATE_TRIM * 100))


def _trimmed_mean(vals, frac):
    """Mean of `vals` with `frac` of the sorted mass cut from each end.

    A sorted-index trim rather than a sigma clip: it is monotone in `frac`, it has
    no iteration that could fail to converge inside a build, and it needs nothing
    outside the standard library.
    """
    s = sorted(vals)
    k = int(len(s) * frac)
    if k and len(s) - 2 * k > 0:
        s = s[k:len(s) - k]
    return sum(s) / len(s)


def plate_rgb(sprites_dir):
    """(r, g, b) of the pack-icon plate, read off the SHIPPED ground sheet.

    Takes the directory rather than finding it, so the check and the build are
    provably reading the same file rather than each resolving a path.
    """
    path = os.path.join(sprites_dir, "ground.png")
    _w, _h, px = read_rgba(path)
    pixels = [p for row in px for p in row if p[3] >= OPAQUE]
    if not pixels:
        raise SystemExit("ui_theme: %s has no opaque pixels, so it is not a ground sheet" % path)
    # round(), not int(): see ROUND, NOT TRUNCATE above. Truncating a mean darkens
    # the plate half a level per channel on every build, forever.
    return tuple(int(round(_trimmed_mean([p[i] for p in pixels], PLATE_TRIM)))
                 for i in range(3))


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
