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
# ONE LITERAL `client/tools/...`, NOT THREE JOINED COMPONENTS, and that is not style:
# `check_tools_declare_ci.py` decides a tool is gated by looking for exactly this path in the
# scripts the workflow names, because a bare filename is satisfied by prose about the tool
# (ASSA-282). Spelled as components, this probe reads as declared-gated-and-wired-to-nothing --
# which is what that check told me on its first run, correctly.
PROBE = os.path.join(ROOT, "client/tools/make_icon_layout.gd")

sys.path.insert(0, ART)
from ask_layout import CannotCheck, ask_the_engine  # noqa: E402

WHY_THE_ENGINE = ("a crafting row's drawn size has never been measured, and the two things\n"
                  "offered in its place were the code asserting itself back.")

# Float slack, `check_pack_icon_scale.py`'s number and its reason: the engine hands back
# sizes as floats and a scale comes back as 0.25000001 often enough to matter.
EPS = 1e-4


def drawn(rows):
    return [r for r in rows if r.get("icon")]


def moment_named(layout, label):
    """The one moment with this label, or a refusal naming what the probe could not find.

    A claim whose moment never occurred has to arrive here as a refusal and not as silence:
    the mutation that passed did so because a claim was scored over rows that could not
    disagree with it, which reads exactly like a claim that held.
    """
    for m in layout.get("moments", []):
        if m.get("label") == label:
            return m
    raise CannotCheck(
        "the play never reached a `%s` moment, so the claim measured there was not measured\n"
        "at all. The probe reports %s as unfindable on seed %s. A claim with no moment is a\n"
        "pass over nothing, which is what this exit code exists to say instead."
        % (label, list(layout.get("unmeasured", [])) or "nothing", layout.get("seed")))


def main():
    print(__doc__.splitlines()[0])
    layout = ask_the_engine(WHY_THE_ENGINE, probe=PROBE)

    # THE STATES EVERY NUMBER BELOW IS ONLY VALID IN, per moment. Each is a way for the whole
    # run to be about a layout no player will ever see, and the probe REPORTS them rather than
    # setting them, so a regression in any one says NO VERDICT instead of passing.
    for m in layout.get("moments", []):
        for flag, what in (
                ("make_visible_in_tree", "the crafting menu's rows were not visible in the tree"),
                ("pack_visible_in_tree", "the pack's rows were not visible in the tree"),
                ("make_shown", "the crafting menu was FOLDED (`_show_make(false)`)"),
                ("column_visible", "the HUD column was hidden (ASSA-231 Gap 5)")):
            if not m.get(flag):
                raise CannotCheck(
                    "at the `%s` moment (tick %s) %s, so every rect there is a minimum and not a\n"
                    "drawn size. TWO CAUSES AND THEY ARE DIFFERENT FIXES: the probe opens each tab\n"
                    "itself, so either that step was lost from `make_icon_layout.gd` (look at its\n"
                    "`_open` phases) or the client changed what showing a tab does. Check the probe\n"
                    "first -- it is the cheaper of the two to be wrong about."
                    % (m.get("label"), m.get("tick"), what))
    if layout.get("viewport") != layout.get("viewport_declared"):
        raise CannotCheck(
            "the window was %s and the project declares %s. Headless shrinks the root\n"
            "viewport to 64x64 on the first frame, in which every row is its own minimum."
            % (layout.get("viewport"), layout.get("viewport_declared")))

    # **CLAIMS 1-3 ARE SCORED AT THE `falsifiable` MOMENT AND NOWHERE ELSE**, because it is the
    # only one where a vertically FILLing icon shows up: a row that carries art AND is taller
    # than the icon box. At the fullest moment every drawn row is exactly ICON_BOX_PX tall, so
    # `min(w/fw, h/fh)` cannot move and the bug is invisible. See the probe's `_initialize`.
    sharp = moment_named(layout, "falsifiable")
    make = drawn(sharp.get("make_rows", []))
    pack = drawn(sharp.get("pack_rows", []))
    if not make:
        raise CannotCheck(
            "the `falsifiable` moment (tick %s) held no crafting row with art, so the half of\n"
            "box 3 this file exists for was not measured. Either the sheets stopped loading or\n"
            "`_icon_box` stopped returning art for the kinds the menu offers." % sharp.get("tick"))
    if not pack:
        raise CannotCheck(
            "the `falsifiable` moment (tick %s) held no pack row with art, so claim 2 ('one box\n"
            "wherever it sits') had one list to compare and would have passed on it alone."
            % sharp.get("tick"))

    print("\n  %-11s %-6s %-30s %-7s %-9s %-11s %-7s %s"
          % ("moment", "list", "row", "row h", "icon rect", "drawn", "scale", "verbs"))
    for r in make + pack:
        icon = r["icon"]
        print("  %-11s %-6s %-30s %-7.1f %-9s %-11s %-7s %s"
              % (sharp["label"], r["kind"], r["line"][:30], r["row_size"][1],
                 "%gx%g" % tuple(icon["rect"]), "%gx%g" % tuple(icon["drawn"]),
                 "%.6g" % icon["scale"], ",".join(r.get("verbs", [])) or "-"))

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
        # THE SCALE TRAVELS WITH THE ROW NAME, because this is the clause that fires when the
        # RECT follows the row and `min(w/fw, h/fh)` does not -- a 32-wide box pins the scale
        # at 1/2 however tall the rect gets, so the number a reader needs is the pair.
        boxes.setdefault(tuple(r["icon"]["rect"]), []).append(
            "%s/%s at %.6g" % (r["kind"], r["line"], r["icon"]["scale"]))
    if len(boxes) > 1:
        bad.append("an item is not the same size wherever it sits: %s. A row's shape is "
                   "deciding how its art is scaled -- and note the scale can be right while "
                   "the box is wrong, because the width pins it."
                   % {"%gx%g" % box: rows for box, rows in sorted(boxes.items())})

    # CLAIM 3: the anti-vacuity check, in THIS list's own variable. See the docstring. Asked of
    # the DRAWN rows only: a tall row with no icon is what made the fullest moment look sharp.
    heights = {round(r["row_size"][1], 3) for r in make}
    if len(heights) < 2:
        raise CannotCheck(
            "every crafting row WITH ART at the `falsifiable` moment is %s px tall, so 'the\n"
            "scale does not follow the row' had nothing to be invariant against -- and the pack\n"
            "check's variable (differing verb sets) is a constant here, because every make row\n"
            "says `Make`. This check would pass with the bug present, so it reports no verdict."
            % sorted(heights))

    # **CLAIM 4 IS SCORED AT THE `fullest` MOMENT**, which is the only one that has a reserved
    # row: the kind with no sheet turns up late in the loop, and no tick of this seed's play
    # carries a reserved row and a tall drawn row at once.
    full = moment_named(layout, "fullest")
    reserved = [r for r in full.get("make_rows", []) if r.get("reserved")]
    full_drawn = drawn(full.get("make_rows", []))
    if not reserved or not full_drawn:
        raise CannotCheck(
            "the `fullest` moment (tick %s) held %d reserved row(s) and %d drawn row(s), so\n"
            "ASSA-240's claim -- a reserved box is the same box as a drawn one -- had nothing\n"
            "to compare." % (full.get("tick"), len(reserved), len(full_drawn)))
    box = tuple(full_drawn[0]["icon"]["rect"])
    for r in reserved:
        print("  %-11s %-6s %-30s %-7.1f %-9s  (reserved, no sheet for this kind)"
              % (full["label"], r["kind"], r["line"][:30], r["row_size"][1],
                 "%gx%g" % tuple(r["reserved"])))
        if tuple(r["reserved"]) != box:
            bad.append(
                "the reserved box on `%s` is %gx%g and a drawn icon in the same list is %gx%g,\n"
                "      so that row's sentence starts somewhere no other sentence does (ASSA-240)."
                % ((r["line"],) + tuple(r["reserved"]) + box))

    print("\n  seed %s in a %s window. `falsifiable` tick %s: %d crafting row(s) with art at"
          % (layout.get("seed"), layout.get("viewport"), sharp.get("tick"), len(make)))
    print("  heights %s, %d pack row(s) with art. `fullest` tick %s: %d reserved row(s)."
          % (sorted(heights), len(pack), full.get("tick"), len(reserved)))
    if bad:
        print("\nVERDICT: FAIL (exit 1)")
        for line in bad:
            print("  - %s" % line)
        print("\n  `_icon_box` sets `ICON_BOX_PX` and SIZE_SHRINK_CENTER once above its branch so\n"
              "  the rect cannot follow the row -- on the plate path it is the PANEL that carries\n"
              "  them and the art fills it. If one of those moved, this is what it cost.")
        return 1
    print("\nVERDICT: PASS (exit 0). A crafting row's icon is drawn at a whole-number\n"
          "  reciprocal in the same box a pack row's is, across %d crafting row heights,\n"
          "  and a row with no sheet reserves that same box." % len(heights))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CannotCheck as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n%s" % why)
        sys.exit(2)
