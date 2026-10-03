#!/usr/bin/env python3
"""CAN A PACK ICON STILL CARRY THE KIND ON ITS OWN? (ASSA-111, guarding ASSA-101)

    art/check_icon_kinds.py                 # the guard
    art/check_icon_kinds.py --sprites DIR   # same guard against a doctored sheet tree

WHAT RULING THIS ENFORCES, because a guard that enforces an opinion is worse than no
guard. Maren's split (ASSA-86) took every MAKE verb off the pack row, so seven rows now
share three button sets and four consecutive part rows carry one identical word. ASSA-101
measured what that left the icon carrying and she ruled on the result: "NO RE-RENDER FOR
THE DEMO. The separation is real today whatever its cause, and the icon is not the only
read." Her ruling 2 then said exactly what a guard on it may assert:

  "A GUARD MUST NEVER BE WRITTEN ON THE REGISTRATION. If this becomes a check it asserts
   the player-facing property -- no pair close on both measures -- never the offsets or
   the fill fractions. A guard on positions would turn the *correct* future fix red."

So there is no part offset in this file, no join coordinate, no fill fraction, no named
pair and no roster of kinds. Three of today's part/part pairs separate at IoU 0.000 only
because `rig.py` places head on the far side of the join from the others -- a working
accident. The fix that ends it (loose parts drawn by `items.py`, rig rule 3) must be able
to land green if it re-earns the separation by shape, and red if it does not.

THE PROPERTY, AND WHY IT IS A CONJUNCTION
  Both measures run on the composited plate box -- the icon as the engine drew it, at the
  scale the engine chose, through the tint the engine applied -- for every pair of kinds
  the client actually drew.

  A. SILHOUETTE: intersection over union of the two body masks. Cannot see colour.
  B. INTERIOR: mean dE76 where BOTH are body ink. Cannot see shape.

  FAIL means some pair is close on BOTH: two things a player tells apart by neither. A
  single measure would be the wrong guard in a way that matters here. "Every pair must
  differ in colour" would pass today and would go red the day two kinds are separated
  legitimately BY SHAPE, which is the fix Maren wants left possible.

WHOSE NUMBERS THESE ARE, said in the output and not just here
  DISTINCT = 12.0 comes from `colour.py` and is Maren's: "two species a player must never
  confuse at a glance". CLOSE_IOU is MINE, and I will not pretend otherwise. It is not
  tuned until the art passed: 0.5 is the measure's own midpoint, the point where the
  intersection exceeds half the union and the shapes agree more than they differ.

  It also cannot decide today's verdict, and the check proves that rather than claiming
  it: the minimum interior dE over ALL pairs is printed, and while that minimum is at or
  above DISTINCT the verdict is PASS for every CLOSE_IOU in [0, 1] -- no pair is close on
  colour at all, so the shape bound has nothing to bite on. The day that stops being true
  the output says so, and the bound becomes a real decision for the Director. One line to
  change, or delete CLOSE_IOU and the check becomes "no pair close on colour", which is
  strictly stricter.

TWO CONTROLS RUN EVERY TIME, because a check that has only ever been green has only ever
been an opinion:
  1. WIRING. Every kind against itself must come back IoU 1.000 / dE 0.00. A
     discrimination measure that cannot report "these are the same picture" when handed
     the same picture twice is measuring something else. I have shipped one of those.
  2. THE VERDICT CAN FAIL. One kind's icon is replaced by another's in a COPY of the
     engine's answer, and the same verdict function must return FAIL on it. This is the
     red run, inside the check, on the real path.
  Neither holding is a pass: both exit 2.

ONE TINT, OR NO VERDICT. A pack is one player's, so every icon in it carries the same
species tint -- which is why kind has to read from silhouette and interior value alone.
If the rows ever come back with different tints, part of any separation measured here
would be hue doing work it never does in a real pack, so the measurement would flatter
the art. That exits 2 rather than passing for the wrong reason.

WHAT THIS CANNOT SEE. The icon is one of two carriers: `stack_line` is still a sentence on
every row, and nothing here measures it. A PASS says the icons are separable, never that
the row reads well.

EXIT CODES
  0 PASS     -- no pair is close on both measures.
  1 FAIL     -- some pair is.
  2 NO VERDICT -- could not ask the engine, a control did not hold, or there was nothing
                  to measure. Never a pass.
"""
import itertools
import os
import sys

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
SPRITES = os.path.join(ROOT, "client", "assets", "sprites")

sys.path.insert(0, ART)
from ask_layout import CannotCheck, ask_the_engine, kind_of  # noqa: E402
from colour import DISTINCT  # noqa: E402  Maren's threshold, imported not retyped
from pack_icon_draw import compare, drawn_icon  # noqa: E402  the engine's sampling, once
from stdlib_image import StdlibBackend  # noqa: E402  pixels without pip

WHY_THE_ENGINE = ("what the icons look like AT THE DRAWN SIZE is the whole question, and\n"
                  "the drawn size is the engine's answer, not a number in a script.")

# MINE, not Maren's. The midpoint of the measure: above it the intersection exceeds half
# the union. See the docstring -- and the output, which shows whether it decides anything.
CLOSE_IOU = 0.5


def close_on_both(iou, de):
    """THE PROPERTY. No positions, no fill fractions, no names -- just the two measures.

    A pair with no shared pixel has `de is None`: there is no interior to compare, and
    treating that as 0.00 would read as "identical colour", the exact opposite of true.
    """
    return iou >= CLOSE_IOU and de is not None and de < DISTINCT


def verdict(icons):
    """(failures, table) for a dict of kind -> (image, body mask). The one judge."""
    table = []
    for a, b in itertools.combinations(sorted(icons), 2):
        iou, de, n = compare(icons[a], icons[b])
        table.append((iou, de, n, a, b))
    table.sort(key=lambda row: -row[0])
    return [r for r in table if close_on_both(r[0], r[1])], table


def main(sprites):
    layout = ask_the_engine(WHY_THE_ENGINE)
    rows = [r for r in layout.get("rows", []) if "icon" in r]
    kinds = [kind_of(r) for r in rows]
    if len(set(kinds)) != len(kinds):
        raise CannotCheck("two rows report the same kind %r: this measures kinds, and the\n"
                          "layout is not giving distinct ones." % sorted(kinds))
    if len(kinds) < 2:
        raise CannotCheck("%d icon rows in the pack. Nothing to compare: a separation\n"
                          "between one thing and itself is not a property." % len(kinds))

    tints = {r["icon"]["modulate"] for r in rows}
    if len(tints) != 1:
        raise CannotCheck(
            "the %d rows carry %d different tints (%s). A pack is one player's, so inside\n"
            "one pack hue does ZERO kind work and this check measures what is left. With\n"
            "mixed tints part of the separation would be hue, which flatters the art."
            % (len(rows), len(tints), ", ".join(sorted(tints))))

    icons = {k: drawn_icon(r, sprites, StdlibBackend) for k, r in zip(kinds, rows)}
    where = os.path.relpath(sprites, ROOT)
    print("MEASURED %d icons at the size the engine drew them, one tint (%s), on %s"
          % (len(icons), tints.pop(), sprites if where.startswith("..") else where))

    # CONTROL 1: the instrument can recognise a picture as itself.
    for k in sorted(icons):
        iou, de, _ = compare(icons[k], icons[k])
        if abs(iou - 1.0) > 1e-9 or de is None or de > 1e-9:
            raise CannotCheck("WIRING CONTROL FAILED: %s against itself came back IoU %.3f\n"
                              "dE %s, not 1.000 / 0.00. The measure is not measuring what\n"
                              "this file says it measures." % (k, iou, de))
    print("CONTROL 1 holds: every kind against itself is IoU 1.000 / dE 0.00.")

    # CONTROL 2: the verdict can fail. Two kinds drawn from ONE kind's icon must be caught.
    a, b = sorted(icons)[:2]
    doctored = dict(icons)
    doctored[b] = icons[a]
    red, _ = verdict(doctored)
    if not any({x[3], x[4]} == {a, b} for x in red):
        raise CannotCheck("RED CONTROL FAILED: with %s's icon substituted for %s's, the\n"
                          "verdict did not catch them. A check that cannot fail is not a\n"
                          "check." % (a, b))
    print("CONTROL 2 holds: substituting %s's icon for %s's is caught as a failure." % (a, b))

    failures, table = verdict(icons)

    print("\nALL %d PAIRS, worst silhouette first. dE is over the OVERLAP only, so the two\n"
          "columns are read together: little overlap means a dE drawn from few pixels."
          % len(table))
    for iou, de, n, x, y in table:
        shown = "   --  (no shared pixel)" if de is None else "%7.2f" % de
        print("  %-8s / %-8s  IoU %.3f   interior dE %s   over %4d px" % (x, y, iou, shown, n))

    overlapping = [(de, x, y) for iou, de, n, x, y in table if de is not None]
    print("\nTHE TWO BOUNDS, and which is whose:")
    print("  DISTINCT  %5.2f  dE76, Maren's (colour.py): two things a player must never"
          % DISTINCT)
    print("                   confuse at a glance.")
    print("  CLOSE_IOU %5.2f  MINE: the measure's own midpoint, where the shapes agree"
          % CLOSE_IOU)
    print("                   more than they differ. Not fitted to the art.")
    if overlapping:
        worst = min(overlapping)
        print("\n  Minimum interior dE over every overlapping pair: %.2f (%s / %s)."
              % (worst[0], worst[1], worst[2]))
        if worst[0] >= DISTINCT:
            print("  SO CLOSE_IOU DECIDES NOTHING TODAY: no pair is close on colour at all,\n"
                  "  so the verdict below is PASS for every CLOSE_IOU in [0, 1]. The margin\n"
                  "  on the colour side is %.2f dE." % (worst[0] - DISTINCT))
        else:
            print("  CLOSE_IOU NOW MATTERS: %s / %s is inside DISTINCT on colour, so the\n"
                  "  verdict turns on whether its silhouettes are called close. That is a\n"
                  "  decision for the Director, not a number I may move to go green."
                  % (worst[1], worst[2]))

    if failures:
        print("\n%d PAIR(S) CLOSE ON BOTH MEASURES -- told apart by neither shape nor colour:"
              % len(failures))
        for iou, de, n, x, y in failures:
            print("  %s / %s: IoU %.3f >= %.2f AND interior dE %.2f < %.2f over %d px"
                  % (x, y, iou, CLOSE_IOU, de, DISTINCT, n))
        print("\nVERDICT: FAIL (exit 1). The pack row's icon is one of two carriers of kind\n"
              "and these two kinds are not separable on it. Either re-earn the separation\n"
              "in the art, or the Director decides the row may lean on `stack_line` alone.")
        return 1

    print("\nVERDICT: PASS (exit 0). No pair of kinds is close on both measures, so every\n"
          "icon the client drew is separable from every other by shape, by interior colour,\n"
          "or by both -- which is the property Maren ruled acceptable on ASSA-101.")
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    # `--sprites DIR` exists to prove this check RED against a doctored tree, end to end,
    # without touching a shipped sheet. CI never passes it.
    sprites = SPRITES
    if "--sprites" in args:
        sprites = args[args.index("--sprites") + 1]
    try:
        sys.exit(main(sprites))
    except CannotCheck as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n%s" % why)
        sys.exit(2)
