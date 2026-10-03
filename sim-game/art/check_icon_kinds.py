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

THE PROPERTY: NO PAIR OF KINDS IS CLOSE ON COLOUR.
  Measured on the composited plate box -- the icon as the engine drew it, at the scale the
  engine chose, through the tint the engine applied -- for every pair of kinds the client
  actually drew: mean dE76 where BOTH are body ink, against Maren's DISTINCT. A pair with
  no shared pixel has no interior to compare and is not close.

  IT WAS A CONJUNCTION UNTIL 2026-10-03 (dE AND a silhouette IoU above a midpoint of
  MINE), and Maren deleted my half of it: "deleting is strictly stricter, still passes by
  3.90 dE, and removes a bound of mine-by-adoption that decides nothing. I have set six
  bounds on this palette that turned out to be the wrong instrument; I am not keeping a
  seventh alive because it is harmless today."

  WHAT IT COSTS, which I said to her rather than only here: this file used to argue that a
  colour-only guard "would go red the day two kinds are separated legitimately BY SHAPE".
  That day is still possible -- two kinds in one palette, told apart by silhouette alone,
  now fail. The trade is deliberate: the failure is a FALSE RED, which is loud, arguable
  and in front of the Director, where the conjunction's failure was a quiet pass bought
  with a number nobody had derived. A guard that errs should err toward being read.

WHOSE NUMBER THIS IS, said in the output and not just here
  DISTINCT = 12.0 comes from `colour.py` and is Maren's: "two species a player must never
  confuse at a glance". There is no number of mine left in this file. The silhouette IoU
  is still MEASURED and still printed for every pair -- it is what a reader needs to tell
  a dE drawn from 400 shared pixels from one drawn from 40 -- it just no longer decides
  anything.

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
  0 PASS     -- no pair is close on colour.
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

def close_on_colour(de):
    """THE PROPERTY. No positions, no fill fractions, no names, and no bound of mine.

    A pair with no shared pixel has `de is None`: there is no interior to compare, and
    treating that as 0.00 would read as "identical colour", the exact opposite of true.
    """
    return de is not None and de < DISTINCT


def verdict(icons):
    """(failures, table) for a dict of kind -> (image, body mask). The one judge."""
    table = []
    for a, b in itertools.combinations(sorted(icons), 2):
        iou, de, n = compare(icons[a], icons[b])
        table.append((iou, de, n, a, b))
    table.sort(key=lambda row: -row[0])
    return [r for r in table if close_on_colour(r[1])], table


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
    print("\nTHE ONE BOUND, and it is not mine:")
    print("  DISTINCT  %5.2f  dE76, Maren's (colour.py): two things a player must never"
          % DISTINCT)
    print("                   confuse at a glance. My silhouette bound was deleted on")
    print("                   2026-10-03 (her ruling); IoU is measured and shown, never judged.")
    if overlapping:
        worst = min(overlapping)
        print("\n  Minimum interior dE over every overlapping pair: %.2f (%s / %s), margin\n"
              "  %.2f dE over DISTINCT." % (worst[0], worst[1], worst[2], worst[0] - DISTINCT))

    if failures:
        print("\n%d PAIR(S) CLOSE ON COLOUR -- a player tells these apart by shape alone:"
              % len(failures))
        for iou, de, n, x, y in failures:
            print("  %s / %s: interior dE %.2f < %.2f over %d px (silhouette IoU %.3f, shown\n"
                  "    because it says how many pixels that dE came from -- it is not a bound)"
                  % (x, y, de, DISTINCT, n, iou))
        print("\nVERDICT: FAIL (exit 1). The pack row's icon is one of two carriers of kind\n"
              "and these two kinds are not separable on it. Either re-earn the separation\n"
              "in the art, or the Director decides the row may lean on `stack_line` alone.")
        return 1

    print("\nVERDICT: PASS (exit 0). No pair of kinds is close on colour, so every icon the\n"
          "client drew is separable from every other on its interior alone -- strictly more\n"
          "than the property Maren ruled acceptable on ASSA-101.")
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
