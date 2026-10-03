#!/usr/bin/env python3
"""Is a pack icon drawn at a scale someone CHOSE? (ASSA-65, from Cove's ASSA-57)

    art/check_pack_icon_scale.py

WHAT WENT WRONG, which is why this is a check and not a comment. `custom_minimum_size`
is a FLOOR. A `TextureRect` in an `HBoxContainer` fills the row vertically, so the
icon's rect was 32 x WHATEVER THE ROW WAS, and `STRETCH_KEEP_ASPECT_CENTERED` scaled
by `min(32/fw, h/fh)`. Cove asked the engine and got **15/32** for an ore item: 30 of
64 source columns surviving, spaced 2 and 3 apart. Nobody chose 15/32. It fell out of
how many buttons the row happened to afford, which means THE SAME ITEM CHANGED SIZE
WHEN ITS VERBS CHANGED -- a UI count deciding how art is resampled.

THE TRAP THIS IS BUILT TO AVOID is the one I keep walking into: asserting the code
back to itself. Reading `custom_minimum_size` and `size_flags_vertical` out of
`main.gd` and checking they are the two values `main.gd` sets would pass by
construction and would still pass if Godot's layout semantics were not what I believe
they are. So this does not read the client's intentions. It runs Cove's
`pack_icon_layout.gd`, which instantiates the real scene, rebuilds the richest pack
the offline session really holds, lets layout settle and prints what the engine
ACTUALLY laid out. Python's only job is to score those numbers.

THREE CLAIMS, and the third is why the first two are worth anything:

 1. EVERY SCALE IS AN EXACT RECIPROCAL. 1/2 and 1/4 keep every source pixel on a whole
    number of screen pixels; 15/32 does not. The bar is `1/scale` being a whole number,
    not a named list of allowed scales, so a new sheet at a new size is fine as long as
    it lands cleanly.
 2. EVERY ICON RECT IS THE SAME BOX. One item, one size, wherever it sits.
 3. THE ROWS AFFORD DIFFERENT VERBS ANYWAY. This is the anti-vacuity check, and the
    first version of it was wrong in a way worth recording. I asked for differing ROW
    HEIGHTS, and after the fix there are none: the 48px box is the tallest thing in
    every art row, so it SETS the height and all five come out at 48. The invariance
    I wanted was never against height -- it is against what ASSA-65 actually says,
    "the icon's scale does not change when a row's VERBS change". So this requires
    the measured rows to afford different verb sets, which is the thing that used to
    move the scale. If they ever stop differing, this exits 2 (NO VERDICT) rather
    than quietly reporting a pass over nothing.

Exit codes, matching `check_glyph_contrast.py`: 0 green, 1 the client is wrong,
2 NO VERDICT -- could not ask the engine, or had nothing to measure.
"""

import os
import sys

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)

sys.path.insert(0, ART)
# Running the layout probe is shared with the other two checks that need the engine's
# own answer (ASSA-111); it used to be a character-for-character copy in each.
from ask_layout import CannotCheck, ask_the_engine  # noqa: E402

WHY_THE_ENGINE = ("a verdict about a layout nobody asked the engine for is the thing\n"
                  "this file exists to avoid.")

# Float slack. The engine hands back sizes as floats; 1/4 of 102 is 25.5 and a scale
# comes back as 0.25000001 often enough to matter. Nothing here needs finer.
EPS = 1e-4


def main():
    print(__doc__.splitlines()[0])
    layout = ask_the_engine(WHY_THE_ENGINE)
    rows = layout.get("rows", [])
    art = [r for r in rows if r.get("icon")]
    if not art:
        raise CannotCheck(
            "not one row in the richest pack had an icon, so there was nothing to\n"
            "measure. Either the sheets stopped loading or the pack changed shape.")

    print("\n  %-24s %-7s %-9s %-11s %-7s %s"
          % ("row", "row h", "icon rect", "drawn", "scale", "verbs"))
    for r in art:
        icon = r["icon"]
        print("  %-24s %-7.1f %-9s %-11s %-7s %s"
              % (r["line"][:24], r["row_size"][1],
                 "%gx%g" % tuple(icon["rect"]), "%gx%g" % tuple(icon["drawn"]),
                 "%.6g" % icon["scale"], ",".join(r.get("verbs", [])) or "-"))

    bad = []

    # CLAIM 1: every scale is an exact reciprocal.
    for r in art:
        scale = r["icon"]["scale"]
        if scale <= 0:
            bad.append("%s is drawn at scale %g" % (r["line"], scale))
            continue
        inverse = 1.0 / scale
        if abs(inverse - round(inverse)) > EPS:
            bad.append(
                "%s is drawn at %.6g = 1/%.4f, which is not a whole-number reciprocal.\n"
                "      %g of %g source columns survive, unevenly spaced."
                % (r["line"], scale, inverse,
                   r["icon"]["drawn"][0], r["icon"]["frame"][0]))

    # CLAIM 2: one box, every row.
    boxes = {tuple(r["icon"]["rect"]) for r in art}
    if len(boxes) > 1:
        bad.append("the icon rect is not one box: %s. A row's height is deciding how "
                   "its art is scaled." % sorted(boxes))

    # CLAIM 3: the anti-vacuity check. Claims 1 and 2 are free unless the rows being
    # compared really do afford different verbs, because the verbs are what used to
    # move the scale. (NOT row heights: after the fix the box is the tallest thing in
    # every art row and sets it, so they are all 48. See the docstring.)
    verb_sets = {tuple(r.get("verbs", [])) for r in art}
    if len(verb_sets) < 2:
        raise CannotCheck(
            "every row with art affords the same verbs %s, so 'the scale does not\n"
            "follow the verbs' had nothing to be invariant against. This check would\n"
            "pass with the bug present, so it reports no verdict instead."
            % [list(v) for v in verb_sets])

    heights = {round(r["row_size"][1], 3) for r in art}
    print("\n  rows with art: %d, affording %d different verb sets, at row heights %s"
          % (len(art), len(verb_sets), sorted(heights)))
    if bad:
        print("\nVERDICT: FAIL (exit 1)")
        for line in bad:
            print("  - %s" % line)
        print("\n  `main.gd` gives the icon `ICON_BOX_PX` and SIZE_SHRINK_CENTER so the\n"
              "  rect cannot follow the row. If that changed, this is what it cost.")
        return 1
    print("\nVERDICT: PASS (exit 0). Every icon is drawn at a whole-number reciprocal\n"
          "  in one fixed box, across rows affording %d different verb sets."
          % len(verb_sets))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CannotCheck as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n%s" % why)
        sys.exit(2)
