#!/usr/bin/env python3
"""AN ICON FRAME CARRIES NO BAND OF AIR ABOVE ITS ART. (ASSA-376)

    art/check_items_top_band.py            # the guard
    art/check_items_top_band.py --push N   # prove it red: drop a real row N px

Maren's rule, one level below ASSA-328: *a frame's own transparency is air, and
ASSA-328 governs it -- an icon frame carries no transparent band above its art.
Slack collects at the BOTTOM.* ASSA-328 said that about a BLOCK, where the air
is panel layout; this says it about the FRAME, where the air is the sprite
sheet's own and no layout can reach it.

WHY A CHECK AND NOT JUST THE RE-AUTHOR. The band is invisible at 1x. It only
became a defect when ASSA-357 earned the build screen's output picture a whole
scale of its room, and 27 px of frame padding came out as 81 px of nothing
between a label and the thing it labels. So this is a rule nobody can SEE
being broken on the surface most of this art is judged on: the next row drawn
in a 1x1 window with half a tile of headroom inherits the defect silently, and
a reviewer looking at `contact.png` would be right not to spot it.

THE FLOOR IS THE WHOLE INSTRUMENT, AND `alpha > 0` IS THE TRAP.
Every raw frame of this sheet carries a film of alpha 1-4 across the ENTIRE
256x384 -- Cycles sampling noise on a transparent film. So `alpha > 0` reports
six of the seven items rows as a full-bleed 64x96 and calls a 40 px band of air
no band at all. That artefact is exactly what Cove's own ASSA-357 measurement
("six of seven rows are full-bleed") counted, and it is why ASSA-376's first
acceptance box was already green on the day it was written, with the defect at
its worst. A guard that inherited the same threshold would have inherited the
same blindness, so the floor is declared here, it matches `build.py`'s
PAINT_FLOOR, and the third control below measures whether the verdict depends
on it at all.

THREE CONTROLS RUN EVERY TIME, because a check that has only ever been green has
only ever been an opinion:
  1. WIRING -- every declared row must be found, carry opaque pixels, and not
     all be the same picture.
  2. IT CAN FAIL -- a real row is dropped down its frame in memory and must be
     caught by the same code path that judges the shipped ones.
  3. THE FLOOR IS NOT LOAD-BEARING -- the whole verdict is re-formed at nine
     floors from 1 to 200 and every one must reach the SAME verdict. Note what
     this control does NOT require: that the number agree. Run against the
     sheet as it shipped on main, `ore`'s top reads 32 at a floor of 1 and 34
     at 64, and every floor says "this row has a band of air above it".
     The first draft of this control compared the NUMBERS and refused to give
     a verdict on exactly the defect it was written for -- a check whose
     tripwire is tighter than its claim. A verdict function is a claim too.
  None of the three holding is a pass: all three exit 2.

AND THE DECLARATION IS CHECKED, NOT ASSUMED. The fit lives in
`rig.Asset(fill="top")` in the asset script; `build.py` pops it, so it never
reaches the shipped manifest and this file cannot read it there. So SHEETS
below is a list with a reason, and the check fails if the named asset script
has stopped asking for the fit -- the same reason `check_part_contract.py`
compares a shipped file against the module it was derived from. A guard whose
subject quietly stopped existing would pass forever.

EXIT CODES
  0 PASS       -- no row has air above its art, and every row fills an axis.
  1 FAIL       -- a row regained a top band, or stopped filling its box.
  2 NO VERDICT -- sheets unreadable, a control did not hold, or the floor is
                  load-bearing. Never a pass.
"""
import json, os, sys

ART = os.path.dirname(os.path.abspath(__file__))
SPRITES = os.path.join(os.path.dirname(ART), "client", "assets", "sprites")
sys.path.insert(0, ART)
from png_stdlib import read_rgba  # noqa: E402  (after sys.path, on purpose)

# Same number and same reasoning as build.py's PAINT_FLOOR and LIGHT_FLOOR: the worst a
# discarded pixel can be wrong by is the floor itself, which over the build panel's own
# SURFACE (37,40,48) is a shift of under one step of the 8-bit ramp.
PAINT_FLOOR = 4
OPAQUE = 200            # "a drawn pixel" everywhere else in art/; used by the wiring control
# THE LADDER STOPS AT 64, AND THE BOUND IS MEASURED RATHER THAN CHOSEN. Every floor here
# has to be asking "is there any paint in this pixel", because that is the question the
# rule asks; a floor in the high hundreds asks "is this pixel nearly opaque", which the
# antialiased TOP ROW of any resampled sprite is not. Measured on this sheet: the sampling
# film tops out at alpha 1, and the softest fitted top row is `hopper`'s at 127 (the rest
# 173-194). So 1..64 sits strictly between the two with the nearest art a factor of two
# away, and nothing at all below. Floors of 128 and 200 were in the first draft: at 200
# all seven rows reported a false 1 px band -- their own top row of picture -- which is
# the instrument measuring the resampler again.
FLOORS = (1, 2, 4, 8, 16, 32, 64)

# A sheet whose frames are ICON BOXES rather than tile windows, and the asset script that
# has to keep saying so. Only an asset no renderer places on the ground may be here: the
# fit moves art inside its frame, so a sheet whose `anchor_px`/`tiles` someone READS would
# come off its tile.
SHEETS = {
    "items": ("assets/items.py",
              "an icon sheet parallel to the world sheets: `sprites.gd:34` draws `ore` the "
              "ITEM from here and `ore.png` the world tile from there, and `_frame_from` "
              "(sprites.gd:184) takes the whole frame with no anchor term"),
}

# TWO RULES, TWO INSTRUMENTS, AND THE SECOND ONE IS HERE BECAUSE THIS GUARD CAUGHT THREE
# GOOD ROWS BEFORE IT CAUGHT ANY BAD ONE.
#
# THE TOP is measured at PAINT_FLOOR, for the reason in the header: `alpha > 0` cannot see
# a band of air because the raw render's 1-4 film reaches the frame edge.
#
# THE FILL is measured at alpha > 0, and PAINT_FLOOR is the wrong instrument for it. The
# fit pastes an exactly `nw x nh` picture into an otherwise transparent frame, so the
# frame's OWN TRANSPARENCY -- which is the quantity Maren's rule is about -- reports the
# fitted size to the pixel. Measured at PAINT_FLOOR instead, the first run of this check
# failed `head`, `frame` and `hopper`: the fit is computed on the 4x raw render and the
# LANCZOS downscale softens the outermost pixels of a tapering edge below any floor, so
# `head` reads 60 px wide in a frame its art fills exactly. That is a measurement of the
# resampler, not of the fit. So the fill test asks the transparency and the top test asks
# the paint, and neither number is a tolerance anyone chose.
FILL_SLACK_PX = 0


class CannotCheck(Exception):
    pass


def rows_of(sheet, meta):
    """[(row name, frame width, frame height, [[(r,g,b,a)...] ...])] for one sheet."""
    path = os.path.join(SPRITES, meta["sheet"])
    if not os.path.exists(path):
        raise CannotCheck("%s is in the manifest and not on disk" % path)
    fw, fh = meta["frame_px"]
    w, h, px = read_rgba(path)
    if w < fw or h < fh * len(meta["rows"]):
        raise CannotCheck("%s is %dx%d, too small for %d frames of %dx%d"
                          % (path, w, h, len(meta["rows"]), fw, fh))
    out = []
    for i, row in enumerate(meta["rows"]):
        out.append(("%s/%s" % (sheet, row["name"]), fw, fh,
                    [[px[i * fh + y][x] for x in range(fw)] for y in range(fh)]))
    return out


def extent(frame, floor=PAINT_FLOOR):
    """(top, bottom_slack, width, height) of the paint in one frame, or None if empty."""
    fh, fw = len(frame), len(frame[0])
    x0 = y0 = None
    x1 = y1 = -1
    for y in range(fh):
        for x in range(fw):
            if frame[y][x][3] > floor:
                if x0 is None or x < x0:
                    x0 = x
                if x > x1:
                    x1 = x
                if y0 is None:
                    y0 = y
                y1 = y
    if y1 < 0:
        return None
    return (y0, fh - 1 - y1, x1 - x0 + 1, y1 - y0 + 1)


def judge(measured):
    """[(name, fw, fh, paint extent, opaque-or-not extent)] -> the offenders.

    The only place a verdict is formed. `e` is measured at PAINT_FLOOR and answers the
    top; `any_e` is measured at alpha > 0 and answers the fill. See FILL_SLACK_PX.
    """
    bad = []
    for name, fw, fh, e, any_e in measured:
        if e is None:
            bad.append((name, "no paint above alpha %d anywhere in the frame" % PAINT_FLOOR))
            continue
        top, _bot, _bw, _bh = e
        _t, _b, aw, ah = any_e
        if top > 0:
            bad.append((name, "%d px of air above the art" % top))
        elif fw - aw > FILL_SLACK_PX and fh - ah > FILL_SLACK_PX:
            bad.append((name, "fills neither axis: %dx%d of a %dx%d box"
                              % (aw, ah, fw, fh)))
    return bad


def push_down(frame, n):
    """A real row dropped `n` px down its own frame, for the can-fail control."""
    fh, fw = len(frame), len(frame[0])
    clear = [(0, 0, 0, 0)] * fw
    return [list(clear) for _ in range(n)] + [list(r) for r in frame[:fh - n]]


def main(argv):
    manifest_path = os.path.join(SPRITES, "manifest.json")
    if not os.path.exists(manifest_path):
        raise CannotCheck("no %s -- run art/build.py first" % manifest_path)
    manifest = json.load(open(manifest_path))

    for sheet, (script, _why) in sorted(SHEETS.items()):
        src = os.path.join(ART, script)
        if not os.path.exists(src):
            raise CannotCheck("%s names %s and there is no such file" % (__file__, src))
        if 'fill="top"' not in open(src).read():
            raise CannotCheck(
                "%s no longer asks for the fit (`fill=\"top\"` is gone from it), so this "
                "check would be judging a rule nothing applies. Either put it back or "
                "take %s out of SHEETS and say why in the same commit." % (script, sheet))
        if sheet not in manifest:
            raise CannotCheck("%s is in SHEETS and not in the manifest" % sheet)

    measured = []
    for sheet in sorted(SHEETS):
        for name, fw, fh, frame in rows_of(sheet, manifest[sheet]):
            measured.append((name, fw, fh, extent(frame), extent(frame, 0), frame))

    # ---------------------------------------------------------------- control 1: wiring
    if not measured:
        raise CannotCheck("no rows measured: the sheets in SHEETS have no rows")
    for name, _fw, _fh, _e, _a, frame in measured:
        if not any(p[3] > OPAQUE for row in frame for p in row):
            raise CannotCheck("%s has no opaque pixel in it: this check is reading an "
                              "empty frame, not judging art" % name)
    seen = {}
    for name, _fw, _fh, _e, _a, frame in measured:
        key = tuple(tuple(p) for row in frame for p in row[::7])
        seen.setdefault(key, []).append(name)
    same = [v for v in seen.values() if len(v) > 1]
    if same:
        raise CannotCheck("these rows are the same picture, so the sheet is not what this "
                          "check thinks it is: %s" % "; ".join(", ".join(v) for v in same))

    # ------------------------------------------------------------- control 2: it can fail
    victim = max(measured, key=lambda m: m[3][3] if m[3] else 0)
    hurt = push_down(victim[5], 10)
    if not judge([(victim[0], victim[1], victim[2], extent(hurt), extent(hurt, 0))]):
        raise CannotCheck("the can-fail control did not fail: %s was dropped 10 px down "
                          "its frame and this check still passed it. The guard is not "
                          "wired to the verdict." % victim[0])

    # -------------------------------------------------- control 3: the floor is not the answer
    ladder = []
    for name, _fw, _fh, _e, _a, frame in measured:
        ladder.append((name, [(extent(frame, f) or (-1,))[0] for f in FLOORS]))
    at_floor = {}
    for f in FLOORS:
        verdict = judge([(n, fw, fh, extent(fr, f), a) for n, fw, fh, _e, a, fr in measured])
        at_floor[f] = sorted(n for n, _why in verdict)
    distinct = sorted(set(tuple(v) for v in at_floor.values()))
    if len(distinct) > 1:
        raise CannotCheck(
            "the verdict MOVES with the alpha floor, so it is a verdict about the "
            "threshold and not about the art:\n" +
            "\n".join("  floor %3d: %s" % (f, ", ".join(at_floor[f]) or "every row clean")
                      for f in FLOORS) +
            "\nLook at the rows before anyone picks a floor. (The NUMBERS are allowed to "
            "move -- a soft edge is a few px wide at any threshold; it is the ANSWER that "
            "may not.)")

    bad = judge([m[:5] for m in measured])

    # `--push N`: the same mutation as control 2, on every row, so the failure path can be
    # read rather than trusted.
    push = 0
    if "--push" in argv:
        push = int(argv[argv.index("--push") + 1])
        measured = [(n, fw, fh, extent(push_down(f, push)), extent(push_down(f, push), 0),
                     push_down(f, push)) for n, fw, fh, _e, _a, f in measured]
        bad = judge([m[:5] for m in measured])

    print("AIR ABOVE THE ART, PER ROW -- top at alpha > %d, fitted size at alpha > 0.%s\n"
          % (PAINT_FLOOR, "  (--push %d)" % push if push else ""))
    print("%-18s %6s %6s %12s %12s %8s" % ("row", "top", "bottom", "paint", "fitted", "box"))
    for name, fw, fh, e, any_e, _f in measured:
        if e is None:
            print("%-18s %6s" % (name, "empty"))
            continue
        top, bot, bw, bh = e
        print("%-18s %6d %6d %12s %12s %8s%s"
              % (name, top, bot, "%dx%d" % (bw, bh), "%dx%d" % (any_e[2], any_e[3]),
                 "%dx%d" % (fw, fh), "" if top == 0 else "   <-- air above the art"))
    print("\nThe same tops at alpha floors %s:" % ", ".join(str(f) for f in FLOORS))
    for name, tops in ladder:
        print("  %-18s %s" % (name, " ".join("%3d" % t for t in tops)))
    print("\nFor comparison, the instrument this check refuses to use: at `alpha > 0` the\n"
          "raw render's 1-4 sampling film reaches the frame edge, so every one of these\n"
          "rows reports a top of 0 whether or not it has a band of air above it.")

    if bad:
        print("\n%d ROW(S) BREAK THE RULE:" % len(bad))
        for name, why in bad:
            print("  %-18s %s" % (name, why))
        print("\nAn icon frame carries no transparent band above its art and slack collects\n"
              "at the bottom (ASSA-376, Maren). At the build screen's picture scale a band\n"
              "is multiplied: 27 px of frame padding came out as 81 px between a label and\n"
              "the thing it labels. The fit is `rig.Asset(fill=\"top\")` plus\n"
              "`build.py::fit_to_frame`; if a row is here, either it lost that declaration\n"
              "or something downstream resized the sheet.")
        print("\nVERDICT: FAIL (exit 1).")
        return 1
    print("\nVERDICT: PASS (exit 0). Every row's paint starts at y=0 and fills an axis of\n"
          "its box, and all three controls held.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except CannotCheck as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n%s" % why)
        sys.exit(2)
