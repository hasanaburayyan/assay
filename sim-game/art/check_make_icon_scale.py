#!/usr/bin/env python3
"""Is a CRAFTING ROW's icon drawn at a scale someone CHOSE? (ASSA-306, ASSA-116 box 3)

    art/check_make_icon_scale.py

ASSA-116 box 3 is *"Pack AND CRAFTING rows show icons at their drawn size"* and until this
file only the pack half was measured. The crafting half rested on two things, neither of
them a measurement of the drawn size: the menu calls the same `_icon_box` as the pack, so
the scale is right BY CONSTRUCTION -- which is the exact argument `check_pack_icon_scale.py`
rejects in its own docstring -- and a suite assertion that reads
`custom_minimum_size.x` back, which is the property `main.gd` set, in a suite that runs
before any layout pass.

AND SHARING A FUNCTION REALLY IS NOT ENOUGH, because ASSA-65's defect was a CONTAINER
defect: a `TextureRect` in an `HBoxContainer` FILLS, so the icon's rect became 32 x
whatever-the-row-was and an ore came out at 15/32 -- "nobody chose that; it fell out of how
many buttons the row afforded". A make row is a different container shape from a pack row
(ASSA-247 put the sentence and its one verb on a line inside a VBox inside the row), so
what holds in one says nothing about the other.

WHAT THIS MEASURES, AND IT IS TWO LISTS IN ONE RUN. `client/tools/make_icon_layout.gd`
plays the real demo loop offline, finds the tick the two panels are fullest on, OPENS EACH
TAB and prints what the engine laid out. Python's only job is to score those numbers.

**THE TAB IS WHY THIS COULD NOT BE A KEY IN THE PACK PROBE'S JSON.** ASSA-264 put the
column's sections in tabs and `mineralogy` is the one that opens, so `MakeBody` and
`InventoryBody` are both `visible = false` until somebody presses their tab -- and an
invisible container keeps nothing but its children's MINIMUM sizes. A pack row's real size
IS its minimum, so the pack probe reads 48px rows out of a hidden tab and is right by luck.
A make row's sentence is `EXPAND_FILL` and wraps: measured in a hidden tab, the five rows
came back 95px wide and 837-1361px TALL, and the scale scored green over all of it.

FOUR CLAIMS, and the third is why the first two are worth anything:

 1. EVERY SCALE IS AN EXACT RECIPROCAL, the pack check's bar, for the same reason: 1/2 and
    1/4 keep every source pixel on a whole number of screen pixels and 15/32 does not.
 2. ONE BOX, ACROSS BOTH LISTS. This is the pack check's claim 2 asked of the thing ASSA-65
    actually says -- one item, one size, WHEREVER IT SITS -- which no check could ask while
    only one list was ever measured.
 3. THE MAKE ROWS DIFFER IN HEIGHT. The anti-vacuity check, and it is a DIFFERENT variable
    from the pack's on purpose. The pack check requires differing VERB SETS because verbs
    are what used to move a pack row's scale; every make row says exactly `Make`, so verbs
    would be a constant here and the invariance would be against nothing. What varies in
    this list is the row's HEIGHT -- a dead-end clause or a walls clause adds a line -- and
    height is precisely what a vertically FILLing icon follows. If the rows ever stop
    differing, this exits 2 (NO VERDICT) rather than passing over nothing.
 4. A RESERVED BOX IS THE SAME BOX AS A DRAWN ONE (ASSA-240, Maren's ruling). A row whose
    kind has no sheet gets `ICON_BOX_PX` of nothing so the sentence beside it starts where
    every other sentence starts. Her defect was two left edges 39px apart in one list, and
    nothing has measured the reserved box since: it is the one claim here that is about the
    rows WITHOUT art.

Exit codes, matching `check_pack_icon_scale.py`: 0 green, 1 the client is wrong,
2 NO VERDICT -- could not ask the engine, or had nothing to measure.
"""

import os
import sys

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
PROBE = os.path.join(ROOT, "client", "tools", "make_icon_layout.gd")

sys.path.insert(0, ART)
from ask_layout import CannotCheck, ask_the_engine  # noqa: E402

WHY_THE_ENGINE = ("a crafting row's drawn size has never been measured, and the two things\n"
                  "offered in its place were the code asserting itself back.")

# Float slack, `check_pack_icon_scale.py`'s number and its reason: the engine hands back
# sizes as floats and a scale comes back as 0.25000001 often enough to matter.
EPS = 1e-4


def rows_with_art(layout, key):
    return [r for r in layout.get(key, []) if r.get("icon")]


def main():
    print(__doc__.splitlines()[0])
    layout = ask_the_engine(WHY_THE_ENGINE, probe=PROBE)

    # THE STATES THE MEASUREMENT IS ONLY VALID IN. Each of these is a way for every number
    # below to be about a layout no player will ever see, and the probe REPORTS them rather
    # than setting them so that a regression in any one says NO VERDICT instead of passing.
    for flag, what in (
            ("make_visible_in_tree", "the crafting menu's rows were not visible in the tree"),
            ("pack_visible_in_tree", "the pack's rows were not visible in the tree"),
            ("make_shown", "the crafting menu was FOLDED (`_show_make(false)`)"),
            ("column_visible", "the HUD column was hidden (ASSA-231 Gap 5)")):
        if not layout.get(flag):
            raise CannotCheck(
                "%s, so every rect below is a minimum and not a drawn size. The probe opens\n"
                "each tab itself, so this is a change in the client, not a missing step." % what)
    if layout.get("viewport") != layout.get("viewport_declared"):
        raise CannotCheck(
            "the window was %s and the project declares %s. Headless shrinks the root\n"
            "viewport to 64x64 on the first frame, in which every row is its own minimum."
            % (layout.get("viewport"), layout.get("viewport_declared")))

    make = rows_with_art(layout, "make_rows")
    pack = rows_with_art(layout, "pack_rows")
    if not make:
        raise CannotCheck(
            "not one crafting row had an icon, so the half of box 3 this file exists for was\n"
            "not measured. The loop reached %d rows at tick %s; either the sheets stopped\n"
            "loading or `_icon_box` stopped returning art for every kind the menu offers."
            % (layout.get("rows_now", 0), layout.get("tick")))
    if not pack:
        raise CannotCheck(
            "not one pack row had an icon, so claim 2 ('one box wherever it sits') had only\n"
            "one list to compare and would have passed on it alone.")

    print("\n  %-6s %-34s %-7s %-9s %-11s %-7s %s"
          % ("list", "row", "row h", "icon rect", "drawn", "scale", "verbs"))
    for r in make + pack:
        icon = r["icon"]
        print("  %-6s %-34s %-7.1f %-9s %-11s %-7s %s"
              % (r["kind"], r["line"][:34], r["row_size"][1],
                 "%gx%g" % tuple(icon["rect"]), "%gx%g" % tuple(icon["drawn"]),
                 "%.6g" % icon["scale"], ",".join(r.get("verbs", [])) or "-"))
    reserved = [r for r in layout.get("make_rows", []) if r.get("reserved")]
    for r in reserved:
        print("  %-6s %-34s %-7.1f %-9s  (reserved, no sheet for this kind)"
              % (r["kind"], r["line"][:34], r["row_size"][1], "%gx%g" % tuple(r["reserved"])))

    bad = []

    # CLAIM 1: every scale is an exact reciprocal.
    for r in make + pack:
        scale = r["icon"]["scale"]
        if scale <= 0:
            bad.append("the %s row `%s` is drawn at scale %g" % (r["kind"], r["line"], scale))
            continue
        inverse = 1.0 / scale
        if abs(inverse - round(inverse)) > EPS:
            bad.append(
                "the %s row `%s` is drawn at %.6g = 1/%.4f, which is not a whole-number\n"
                "      reciprocal. %g of %g source columns survive, unevenly spaced."
                % (r["kind"], r["line"], scale, inverse,
                   r["icon"]["drawn"][0], r["icon"]["frame"][0]))

    # CLAIM 2: ONE BOX, ACROSS BOTH LISTS. The pack check can only ask this within one list.
    boxes = {}
    for r in make + pack:
        boxes.setdefault(tuple(r["icon"]["rect"]), []).append("%s/%s" % (r["kind"], r["line"]))
    if len(boxes) > 1:
        bad.append("an item is not the same size wherever it sits: %s. A row's shape is "
                   "deciding how its art is scaled."
                   % {"%gx%g" % box: rows for box, rows in sorted(boxes.items())})

    # CLAIM 4: a reserved box is the same box as a drawn one (ASSA-240).
    if reserved:
        drawn = sorted(boxes)[0]
        for r in reserved:
            if tuple(r["reserved"]) != drawn:
                bad.append(
                    "the reserved box on `%s` is %gx%g and a drawn icon is %gx%g, so that row's\n"
                    "      sentence starts somewhere no other sentence does (ASSA-240)."
                    % ((r["line"],) + tuple(r["reserved"]) + drawn))

    # CLAIM 3: the anti-vacuity check, in THIS list's own variable. See the docstring.
    heights = {round(r["row_size"][1], 3) for r in layout.get("make_rows", [])}
    if len(heights) < 2:
        raise CannotCheck(
            "every crafting row is %s px tall, so 'the scale does not follow the row' had\n"
            "nothing to be invariant against in this list -- and the pack check's variable\n"
            "(differing verb sets) is a constant here, because every make row says `Make`.\n"
            "This check would pass with the bug present, so it reports no verdict instead."
            % sorted(heights))

    print("\n  tick %s, %d crafting row(s) with art + %d reserved, %d pack row(s) with art,"
          % (layout.get("tick"), len(make), len(reserved), len(pack)))
    print("  at crafting row heights %s in a %s window" % (sorted(heights), layout.get("viewport")))
    if bad:
        print("\nVERDICT: FAIL (exit 1)")
        for line in bad:
            print("  - %s" % line)
        print("\n  `_icon_box` sets `ICON_BOX_PX` and SIZE_SHRINK_CENTER once above its branch so\n"
              "  the rect cannot follow the row -- on the plate path it is the PANEL that carries\n"
              "  them and the art fills it. If one of those moved, this is what it cost.")
        return 1
    print("\nVERDICT: PASS (exit 0). A crafting row's icon is drawn at a whole-number\n"
          "  reciprocal in the same box a pack row's is, across %d crafting row heights."
          % len(heights))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CannotCheck as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n%s" % why)
        sys.exit(2)
