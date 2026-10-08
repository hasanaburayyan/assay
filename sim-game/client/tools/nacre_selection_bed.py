#!/usr/bin/env python3
"""WHAT COLOUR THE ENGINE ACTUALLY PAINTS A SELECTION (ASSA-315 box 3).

Maren ruled `selection_color := BORDER` (74,79,92) and `font_selected_color := INK`, and flagged
the one thing her own constants cannot answer:

    "Godot may composite `selection_color` with alpha rather than painting it flat. If the drawn
     pixel is not (74,79,92), my 6.73 is wrong and the measurement must be re-earned on a real
     frame -- shoot it, do not assume it."

So this reads the two frames `nacre_selection_shot.gd` writes -- the same host box, unselected and
selected -- and reports the DRAWN colours and the two ratios her ruling claims: `INK` on the bed
(derived 6.73:1, floor 4.5) and the bed against the well (derived 2.04:1, so you can see what you
selected).

    nacre_selection_bed.py BEFORE.png AFTER.png X Y W H
    nacre_selection_bed.py --selftest

THE DIFF IS WHAT NAMES THE BED, and that is the whole method. A selection is the only thing that
changed between the two frames, so the changed pixels ARE the selection run -- no threshold, no
guess about which grey is a stylebox. `nacre_door_contrast.py` learned this the expensive way: its
first version took "background" to be every pixel that was not text and measured a letter against
its own anti-aliased fringe, reporting 1.10:1 where Maren measured 14.0:1. Here the bed is the MODE
of the changed pixels (a glyph is thin; its bed is not), the ink is the mode of what is left once
the bed is removed, and the fringe between them is reported separately rather than counted as
either.

THE CONTROLS, because a number with no control is a claim:
  1. `--selftest` builds synthetic frames with known colours and checks the pipeline returns the
     ratio those colours have, to two decimals.
  2. The same selftest runs a case where the bed IS the well, and the bed-vs-well reading must come
     back 1.00:1. **An instrument that cannot fail cannot pass.**
  3. On real frames: pixels that changed inside the box but outside the selection's own bounding box
     are reported. They should be none -- the box's well is opaque, so nothing under it drifts --
     and any at all mean the before/after pair differs by more than the selection.
"""
import collections
import os
import sys

# THE PNG READER AND THE WCAG ARITHMETIC ARE `nacre_door_contrast.py`'S, imported rather than
# copied: two copies of `luminance` is two places for the ratio on this screen to disagree. The path
# is added by hand so the import survives `python3 -I`, which drops the script's own directory.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nacre_door_contrast import pixel, ratio, read_png  # noqa: E402

# From `client/tools/build_theme.gd`, which is where the ruling's arithmetic came from.
INK = (229, 233, 241)
BORDER = (74, 79, 92)
WELL = (28, 30, 36)  # SURFACE.darkened(0.25), the box's own bed
ACCENT = (128, 229, 140)  # the caret, and the one thing ASSA-224 says a selection may not be
NEAR = 6  # one colour, allowing for the 8-bit rounding of a composite


def near(a, b, tol=NEAR):
    return max(abs(a[i] - b[i]) for i in range(3)) <= tol


def inside_rect(pixels, rect):
    """Every coordinate of `pixels` that falls in `rect`, which is (x, y, w, h)."""
    return [at for at in pixels
            if rect[0] <= at[0] < rect[0] + rect[2] and rect[1] <= at[1] < rect[1] + rect[3]]


def crop(frame, rect):
    width, height, channels, rows = frame
    x0, y0, w, h = rect
    out = []
    for y in range(max(0, y0), min(height, y0 + h)):
        for x in range(max(0, x0), min(width, x0 + w)):
            out.append(((x, y), pixel(rows, channels, x, y)))
    return out


def measure(before, after, rect):
    """Every number this script reports, off two frames and the box's rect."""
    was = dict(crop(before, rect))
    now = dict(crop(after, rect))
    if not was or not now:
        raise SystemExit("the rect %s is outside the frame" % str(rect))
    changed = [at for at in now if was.get(at) != now[at]]
    if not changed:
        raise SystemExit("NOTHING CHANGED inside the box: the two frames show the same state, so "
                         "no selection was drawn and there is nothing to measure")

    # THE BED: the flat fill of the run. A glyph is a few px wide and a selection is a rectangle.
    bed, bed_px = collections.Counter(now[at] for at in changed).most_common(1)[0]

    # THE RUN IS THE BED'S OWN BOX, NOT THE BOX OF EVERYTHING THAT MOVED, and that distinction is
    # the second defect this script's control caught. Eleven pixels at the box's two right corners
    # differ between the frames (stylebox corner anti-aliasing, 240 px away from any selected
    # glyph), and taking the bbox of ALL changed pixels stretched the run to the whole 240x30 box.
    # The ink mode inside that was then the empty WELL, so the script reported 2.03:1 -- real
    # arithmetic about two colours neither of which is the ink.
    bedded = [at for at in changed if near(now[at], bed)]
    xs = [at[0] for at in bedded]
    ys = [at[1] for at in bedded]
    run = (min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1)

    # THE INK IS NOT IN THE DIFF, AND THAT IS RULING 2 DRAWN RATHER THAN DESCRIBED.
    # `font_selected_color := INK` is *the same ink as unselected* -- "a selection is a BED, not a
    # second ink" -- so a glyph's core is byte-identical in the two frames and the changed set
    # cannot contain it. The first version of this script looked for the ink in the diff and
    # reported (0,0,0) 0 px: it was asking for the one thing the ruling guarantees will not be
    # there. So the ink is read from the RUN's own rectangle instead, and `unchanged_ink` below is
    # the positive form of the same fact.
    inside = inside_rect(now, run)
    rest = collections.Counter(now[at] for at in inside if not near(now[at], bed))
    ink, ink_px = rest.most_common(1)[0] if rest else ((0, 0, 0), 0)
    # THE FRINGE: between the two, counted and named rather than folded into either.
    fringe = sum(n for colour, n in rest.items() if not near(colour, ink))
    unchanged_ink = sum(1 for at in inside if near(now[at], ink) and was.get(at) == now[at])

    # THE WELL: the box's own bed, from the BEFORE frame, which is the only frame where no selection
    # is in the way. Mode of the whole crop, which is overwhelmingly empty well.
    well, well_px = collections.Counter(was.values()).most_common(1)[0]

    # The control: what changed inside the box that is NOT in the run? Reported with where it is and
    # what it turned into, because that is how the corner pixels above were identified instead of
    # being absorbed.
    strays = [at for at in changed
              if not (run[0] <= at[0] < run[0] + run[2] and run[1] <= at[1] < run[1] + run[3])]
    # AND BROKEN DOWN BY WHAT THEY TURNED INTO, because "34 px changed somewhere else" is a shrug
    # and "18 px became ACCENT in one column at x=517" is the caret moving to the end of the
    # selection. A stray nobody can name is the only kind worth worrying about.
    stray_kinds = []
    for colour, group in collections.Counter(now[at] for at in strays).most_common(4):
        where = [at for at in strays if now[at] == colour]
        stray_kinds.append((colour, group, min(at[0] for at in where), max(at[0] for at in where),
                            min(at[1] for at in where), max(at[1] for at in where)))
    # **ALL THE ACCENT IN THE BOX, AND IT IS NOT THE CARET.** This counter was written expecting a
    # caret's worth of green and reported 518 px -- because `_style_line_edit`'s FOCUS stylebox
    # draws the box's whole 1 px edge in `ACCENT` (`build_theme.gd`), and the unfocused frame has
    # exactly 0. The caret is the 18 px column inside that total which MOVES to the end of the
    # selection, and it shows up in the stray breakdown rather than here. Counted over the whole box
    # for that reason: the move takes it out of the bed's run.
    caret = sum(1 for at in now if near(now[at], ACCENT))
    caret_was = sum(1 for at in was if near(was[at], ACCENT))
    return {
        "changed": len(changed), "run": run, "strays": len(strays), "stray_kinds": stray_kinds,
        "caret": caret, "caret_was": caret_was,
        "top": collections.Counter(now[at] for at in inside).most_common(5),
        "bed": bed, "bed_px": bed_px, "ink": ink, "ink_px": ink_px, "fringe": fringe,
        "well": well, "well_px": well_px, "unchanged_ink": unchanged_ink,
        "ink_on_bed": ratio(ink, bed), "bed_on_well": ratio(bed, well),
    }


def say(got):
    print("  changed    %d px inside the box; the BED's run is %s" % (got["changed"], str(got["run"])))
    print("  strays     %d changed px outside the run, each named:" % got["strays"])
    for colour, n, x0, x1, y0, y1 in got["stray_kinds"]:
        print("               %-16s x%-4d x %d..%d  y %d..%d" % (str(colour), n, x0, x1, y0, y1))
    print("  ACCENT     %d px in the box, was %d before the selection" % (got["caret"], got["caret_was"]))
    print("  BED  drawn %-16s %6d px   ruled BORDER (74, 79, 92)  %s"
          % (str(got["bed"]), got["bed_px"],
             "SAME" if near(got["bed"], BORDER) else "DIFFERENT -- composited, not flat"))
    print("  INK  drawn %-16s %6d px   ruled INK (229, 233, 241)  %s"
          % (str(got["ink"]), got["ink_px"],
             "SAME" if near(got["ink"], INK) else "DIFFERENT"))
    print("  WELL drawn %-16s %6d px   expected (28, 30, 36)      %s"
          % (str(got["well"]), got["well_px"],
             "SAME" if near(got["well"], WELL) else "DIFFERENT"))
    print("  fringe between ink and bed: %d px (anti-aliasing, counted as neither)" % got["fringe"])
    # EVERY COLOUR IN THE RUN, SO NOBODY HAS TO TRUST THE TWO I PICKED. The caret is ACCENT and a
    # few dozen px; a third flat colour in here would mean the run holds something I have not named.
    print("  the run's five commonest colours: %s"
          % "  ".join("%s x%d" % (str(c), n) for c, n in got["top"]))
    print("  RULING 2 DRAWN: %d ink px inside the run are byte-identical in the two frames, so "
          % got["unchanged_ink"] + "selecting a word did not change what the word is")
    print("  INK ON THE BED   %5.2f:1   ruled 6.73 derived   %s"
          % (got["ink_on_bed"], "PASS >= 4.5" if got["ink_on_bed"] >= 4.5 else "FAILS the 4.5 floor"))
    print("  BED ON THE WELL  %5.2f:1   ruled 2.04 derived   %s"
          % (got["bed_on_well"],
             "visible" if got["bed_on_well"] >= 1.2 else "INVISIBLE: you cannot see what you selected"))


def flat(width, height, colour):
    return [bytes(bytearray(list(colour) * width)) for _ in range(height)]


def frame(width, height, rows):
    return (width, height, 3, rows)


def paint(rows, width, rect, colour, ink=None):
    """A run of `colour` with a 1-px `ink` stripe down the middle of it, as a glyph stands in a bed."""
    out = [bytearray(row) for row in rows]
    x0, y0, w, h = rect
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            use = ink if (ink is not None and x == x0 + w // 2) else colour
            out[y][x * 3:x * 3 + 3] = bytes(use)
    return [bytes(row) for row in out]


def planted(bed):
    """Two frames of a 40x10 selection run with a 1-px ink stripe, the bed painted only in the
    second -- the shape the real pair has, including the ink being identical in both."""
    size, rect = (60, 20), (4, 4, 40, 10)
    base = flat(size[0], size[1], WELL)
    before = frame(size[0], size[1], paint(base, size[0], rect, WELL, INK))
    after = frame(size[0], size[1], paint(base, size[0], rect, bed, INK))
    return before, after, rect


def selftest():
    """THREE CASES, AND TWO OF THEM MUST FAIL. A detector that only ever passes is not one."""
    ok = True

    print("\nSELFTEST 1: the ruled colours -- the pipeline must return the ratio they have")
    before, after, rect = planted(BORDER)
    got = measure(before, after, rect)
    say(got)
    for what, drawn, want in [("bed", got["bed"], BORDER), ("ink", got["ink"], INK),
                              ("well", got["well"], WELL)]:
        if drawn != want:
            print("  WRONG: %s read %s, planted %s" % (what, str(drawn), str(want)))
            ok = False
    for what, drawn, want in [("ink-on-bed", got["ink_on_bed"], ratio(INK, BORDER)),
                              ("bed-on-well", got["bed_on_well"], ratio(BORDER, WELL))]:
        if abs(drawn - want) > 0.01:
            print("  WRONG: %s read %.2f, planted colours give %.2f" % (what, drawn, want))
            ok = False

    print("\nSELFTEST 2: a bed EQUAL to the well -- nothing is drawn, so the run must be REFUSED")
    before, after, rect = planted(WELL)
    try:
        measure(before, after, rect)
        print("  WRONG: a selection whose bed is the well changed no pixel and was measured anyway")
        ok = False
    except SystemExit as refusal:
        print("  refused, correctly: %s" % str(refusal).split(":")[0])

    print("\nSELFTEST 3: a bed one shade off the well -- a number, and the verdict must say it is "
          "invisible")
    before, after, rect = planted((32, 34, 40))
    got = measure(before, after, rect)
    print("  bed-on-well %5.2f:1" % got["bed_on_well"])
    if got["bed_on_well"] >= 1.2:
        print("  WRONG: (32,34,40) on (28,30,36) is not a bed anybody can see")
        ok = False

    print("\nSELFTEST %s" % ("OK: it returns the planted ratio, refuses a pair with no selection "
                            "in it, and calls an unseeable bed unseeable" if ok else "FAILED"))
    raise SystemExit(0 if ok else 1)


def main():
    if "--selftest" in sys.argv:
        selftest()
    if len(sys.argv) != 7:
        raise SystemExit(__doc__)
    before = read_png(sys.argv[1])
    after = read_png(sys.argv[2])
    rect = tuple(int(a) for a in sys.argv[3:7])
    print("THE DRAWN SELECTION, host box %s" % str(rect))
    got = measure(before, after, rect)
    say(got)
    # WHAT MAKES THIS RUN A FAIL. The two ratios are the ruling; the stray share is the instrument
    # saying it was pointed at the wrong thing. A tenth of the diff landing outside the bed's run
    # means the pair differs by more than a selection and no colour in it can be trusted.
    bad = (got["ink_on_bed"] < 4.5 or got["bed_on_well"] < 1.2
           or got["strays"] > got["changed"] // 10)
    raise SystemExit(1 if bad else 0)


if __name__ == "__main__":
    main()
