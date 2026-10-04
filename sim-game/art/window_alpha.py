#!/usr/bin/env python3
"""ASK THE CLIENT WHICH PIXELS IT DREW. Per-pixel alpha in window space (ASSA-181).

    python3 art/window_alpha.py --selftest                       # arithmetic only, no shots
    python3 art/window_alpha.py variants --sheet client/assets/sprites/player.png --out DIR
    python3 art/window_alpha.py field  --bg B.png --black E.png [--shot A.png] [--png OUT.png]
    python3 art/window_alpha.py bands  --out DIR                 # the control's probe sheet
    python3 art/window_alpha.py control --dir DIR                # the known-alpha control

`art/shoot_window_alpha.sh` is the documented shoot script: it makes the variants, takes the
window shots, PUTS THE REAL SHEETS BACK and proves that with `git status`.

**WHY THIS IS NOT NAMED `check_*.py`, and must never be.** `art/check_ci_runs_every_check.py`
globs `art/check_*.py` and requires `build.yml` to name every one. CI cannot run this: its input
is a set of **window shots**, and `build.yml` runs Godot `--headless` with no xvfb, where
`window_shot.gd` writes a blank frame and still exits SUCCESS. Same reason as
`art/grid_findability.py`, same promotion route -- the day there is a GUI runner, rename and add a
step. `--selftest` is the part that needs no Godot and no shot; it checks the arithmetic, not the
art, and is run from the shoot script rather than from CI.

**WHY IT EXISTS: ON 2026-10-04 FOUR MASKS LIED IN ONE DAY**, all of them difference masks, three
mine and one Maren's (ASSA-181 has the four with times). A difference mask answers "did these two
runs differ here", and every window question we actually ask is "IS THIS PIXEL THE MACHINE". Those
are not the same question and the gap is not small: a difference mask has HOLES wherever two
variants agree (317 of 399 of my "silhouette" pixels were interior hole rims), its outer ring is
the ANTIALIASED FRINGE over the ground (433 px at alpha 0.09, 91% ground), and it picks up
anything else that moved -- 124 px of PLAYER, because two Godot runs do not agree on its idle
frame.

**THE FIX IS ARITHMETIC, NOT A HEURISTIC.** `world_layer.gd` draws every sprite with
`draw_texture_rect_region(tex, dest, src, tint)`, so a screen pixel holds

    screen = bg*(1 - a) + c*a              a = the sheet's alpha there, c = sheet RGB * tint

Shoot the same frame twice with the sheet under test altered and nothing else:

    B   sheet BLANKED (alpha 0 everywhere)   ->  bg, EXACTLY, as integers
    E   sheet RGB ZEROED, alpha kept         ->  K = bg*(1 - a)      ->  a = 1 - K/bg

`tint` is a per-channel multiply, so BLACK TIMES ANY SPECIES TINT IS STILL BLACK: a tinted sheet
cannot contaminate E. That is why the probe shot is black and not white -- white times a tint is
the tint, and `a` would come out multiplied by a colour. (The player is the one sheet drawn at
`Color.WHITE`, `scene_view.gd:519`, so a white probe would work there and nowhere else. Not worth
two code paths.)

**WHAT THIS RETURNS THAT A DIFFERENCE MASK CANNOT**, per pixel, inside the map rect:
  * `a` with a PROVEN interval, not an estimate. `bg` is an integer read off the B shot, so
    `K = round(bg*(1-a))` pins `a` to a window of width `1/bg` per channel; the three channels
    give three windows and the tool INTERSECTS them. The reported bound is that intersection's
    half-width, per pixel, and it is arithmetic rather than a tolerance someone chose.
  * the UNBLENDED colour `c = (screen - bg*(1-a))/a` -- the colour the sheet handed over, before
    the ground showed through it. The thing you wanted when you measured a screen pixel's L.
  * `UNSTABLE` pixels: where the two runs CONTRADICT the model. If `K > bg`, a pixel got BRIGHTER
    with pure black drawn over it, which cannot happen -- so something other than this sheet moved
    between the runs. That is the player-idle-frame bug, reported as a number instead of silently
    joining the mask. An instrument that can say "I do not know" is the whole point; blank the
    player sheet in every run and watch this go to near zero.

**WHAT IT STILL CANNOT DO**, said out loud. Where `bg` is dark the interval is wide (`1/bg`), so a
sheet drawn over black is unmeasurable and reported as such rather than guessed -- `--min-bg`
pixels are skipped, not zeroed. Two draws of the SAME sheet overlapping compound to
`1-(1-a1)(1-a2)`, so this says how much of the sheet is in a pixel, not how many times it was
drawn. And it cannot separate two DIFFERENT sheets in one pass: that needs one pair per sheet.

Exit codes match the art checks: 0 green, 1 a gate failed, 2 NO VERDICT (an input is missing).
"""
import argparse
import json
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from png_stdlib import read_rgba                                     # noqa: E402

## THE MAP RECT, from `window_shot.gd` -- the HUD is not the world and must not be measured as it.
MAP_RECT = (24, 96, 932, 696)

## A pixel whose background is darker than this in every channel is NOT MEASURED. At bg 8 the
## interval on `a` is 1/8 of full scale, which is not an answer, and a confident wrong number is
## the failure this file exists to stop.
MIN_BG = 24

## DRAWN, matching `art/check_machine_vs_own_ore.py` so a window number is comparable with a sheet
## number. Everything between 0 and this is the fringe, which is named rather than hidden.
OPAQUE = 200


def unstable(bg, k):
    """Does pure black over `bg` give `k`? Returns the channel that says no, else -1.

    `k > bg` is the whole test: `bg*(1-a)` is at most `bg` for any `a` in [0, 1], and both are
    integers off two real shots, so one grey level of slack covers the round-off and nothing else.
    """
    for i in range(3):
        if k[i] > bg[i] + 1:
            return i
    return -1


def alpha_of(bg, k, min_bg=MIN_BG):
    """(a, half_width, raw_lo) for one pixel, or None when no channel is bright enough to say.

    Per channel `K = round(bg*(1-a))`, so `bg*(1-a)` is within half a grey level of `K` and
    `a` is pinned to an interval of width `1/bg`. Three channels, three intervals, INTERSECTED --
    which is strictly tighter than averaging them, and gives a bound instead of a hope.

    `raw_lo` IS THE INTERVAL'S BOTTOM BEFORE IT IS CLAMPED TO ZERO, and it is what decides
    whether the sheet drew here at all. When `K == bg` in every channel the interval CONTAINS
    a = 0, so "the sheet drew nothing" is one of the answers consistent with the two shots and
    the tool must not pick a positive one. Keeping the clamped midpoint instead cost me 30,086
    phantom fringe pixels the first time I ran this (2026-10-04): a floor of effectively zero,
    which is the trap this whole file was written about.
    """
    lo, hi, said = -1.0, 2.0, False
    for i in range(3):
        if bg[i] < min_bg:
            continue
        said = True
        lo = max(lo, 1.0 - (k[i] + 0.5) / bg[i])
        hi = min(hi, 1.0 - (k[i] - 0.5) / bg[i])
    if not said or lo > 1.0 or hi < 0.0:
        return None
    raw_lo = lo
    lo, hi = max(0.0, lo), min(1.0, hi)
    if hi < lo:
        return None
    return (0.5 * (lo + hi), 0.5 * (hi - lo), raw_lo)


def unblend(screen, bg, a):
    """The colour the sheet handed over, or None below 1/255 of alpha.

        screen = bg*(1 - a) + c*a      =>      c = bg + (screen - bg) / a

    WRITTEN IN THAT SECOND FORM ON PURPOSE: the sheet's colour is the background plus the
    screen's DEPARTURE from the background, divided by how much of the sheet is in the pixel.
    So the error in `c` is the error in `a` amplified by `1/a`, which is why a faint pixel's
    colour is a worse measurement than a faint pixel's alpha, and `unblend_bound` says by how
    much instead of leaving the caller to find out.

    NOT CLAMPED to 0..255. A value a little outside that range is the round-off in `a` showing,
    and clamping it would quietly turn a measurement into a plausible colour.
    """
    if a < 1.0 / 255.0:
        return None
    return tuple(bg[i] + (screen[i] - bg[i]) / a for i in range(3))


def unblend_bound(screen, bg, a, half):
    """(colour, half_width) -- the colour with a PROVEN bound, or None when alpha is too small.

    `c = bg + (screen - bg)/a` is monotone in `a` and in `screen` separately, so the four corners
    of (`a` +- its own bound) x (`screen` +- half a grey level) give the exact interval. No
    tolerance is chosen here either: it is the alpha interval propagated.
    """
    if a - half < 1.0 / 255.0:
        return None
    out, width = [], 0.0
    for i in range(3):
        vals = [bg[i] + (screen[i] + ds - bg[i]) / av
                for av in (a - half, a + half) for ds in (-0.5, 0.5)]
        out.append(0.5 * (min(vals) + max(vals)))
        width = max(width, 0.5 * (max(vals) - min(vals)))
    return (tuple(out), width)


def field(bg_px, k_px, rect=MAP_RECT, min_bg=MIN_BG):
    """{(x, y): (a, half_width)} over `rect`, plus a report of what it refused to answer.

    A pixel is IN the field only when its alpha interval EXCLUDES ZERO -- the two shots prove
    the sheet put something there. No threshold is chosen anywhere; the cut is the arithmetic's
    own resolution, which at background `bg` is one part in `2*bg` and is reported per pixel.
    So `len(field)` is "pixels this pair of shots can prove hold some of this sheet", fringe
    included, and a fringe fainter than the window can resolve is absent rather than invented.
    """
    out, bad, dark, faint = {}, [], [], 0
    x0, y0, x1, y1 = rect
    for y in range(y0, y1):
        for x in range(x0, x1):
            bg, k = bg_px[y][x], k_px[y][x]
            if unstable(bg, k) >= 0:
                bad.append((x, y))
                continue
            if max(bg[:3]) < min_bg:
                dark.append((x, y))
                continue
            got = alpha_of(bg, k, min_bg)
            if got is None:
                bad.append((x, y))
            elif got[2] > 0.0:
                out[(x, y)] = (got[0], got[1])
            elif got[0] > 0.0:
                faint += 1
    return out, {"unstable": bad, "too_dark": dark, "unresolved": faint,
                 "area": (x1 - x0) * (y1 - y0)}


# A PIXEL THE TOOL REFUSED, for a caller that must not read a refusal as an answer. "Too dark"
# and "the two runs disagree" are both NOT-KNOWN; only `unresolved` means "provably less sheet
# here than the window can resolve", which is the one that may safely be drawn as nothing.
def refused(rep):
    return set(rep["unstable"]) | set(rep["too_dark"])


def drawn_of(fld, opaque=OPAQUE):
    return {p for p, (a, _) in fld.items() if a * 255.0 > opaque}


def silhouette_of(drawn):
    """A drawn pixel with a 4-neighbour that is not drawn -- `check_machine_vs_own_ore.py`'s own
    definition, so the window and the sheet are answering the same question."""
    return [p for p in drawn
            if any((p[0] + dx, p[1] + dy) not in drawn
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]


def pct(vals, f):
    vals = sorted(vals)
    return vals[min(len(vals) - 1, int(f * len(vals)))] if vals else float("nan")


def write_png(path, w, h, rows, nch=3):
    """Minimal PNG writer, so the tool can hand out its own pictures and its own probe sheets
    with no Pillow in the room -- the same stdlib-only rule the CI checks live under."""
    raw = b"".join(b"\x00" + bytes(v for px in row for v in px[:nch]) for row in rows)

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))
    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6 if nch == 4 else 2, 0, 0, 0)))
        fh.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        fh.write(chunk(b"IEND", b""))


# ---------------------------------------------------------------------------------------------
# the probe sheets. The tool knows what shots it needs, so it makes them rather than describing
# them in a comment somebody then types out slightly differently.
# ---------------------------------------------------------------------------------------------
def run_variants(args):
    """`blank.png` and `black.png` for one real sheet: the two shots `field` needs.

    BLANK is fully transparent and the SAME SIZE, because `scene_view._place` reads
    authored-pixels-per-tile out of the manifest's frame size and a sheet of another size would
    move every rectangle on screen -- then `bg` would not be the background.
    """
    w, h, px = read_rgba(args.sheet)
    os.makedirs(args.out, exist_ok=True)
    write_png(os.path.join(args.out, "variant_blank.png"), w, h,
              [[(0, 0, 0, 0)] * w for _ in range(h)], 4)
    write_png(os.path.join(args.out, "variant_black.png"), w, h,
              [[(0, 0, 0, px[y][x][3]) for x in range(w)] for y in range(h)], 4)
    kept = sum(1 for y in range(h) for x in range(w) if px[y][x][3] > 0)
    print("variants of %s (%dx%d): variant_blank.png, variant_black.png -- alpha on %d px"
          % (os.path.basename(args.sheet), w, h, kept))
    return 0


def run_bands(args):
    """The CONTROL sheet: horizontal bands of alpha I authored, over one authored RGB.

    WHY BANDS AND NOT A REAL SPRITE. The control has to compare a recovered alpha with the
    authored one, and matching screen pixels to authored pixels would be a second thing to get
    wrong -- `_place` scales by 0.5 and samples the ODD authored pixel, which is exactly the kind
    of arithmetic I have got wrong twice this week. So instead: every band spans the sheet's full
    WIDTH, and the period divides the frame height, so EVERY frame of EVERY row carries the same
    pattern and every drawn screen pixel's authored alpha is one of `--alphas` whatever the wall
    clock picked. The tool is never told where the sprite is.

    The RGB is one flat colour for the same reason, and a colour the game does not contain
    (magenta), so a recovered colour cannot be a coincidence with the ground.
    """
    alphas = [int(v) for v in args.alphas.split(",")]
    rgb = tuple(int(v) for v in args.rgb.split(","))
    w, h = args.w, args.h
    band = max(1, args.band)
    os.makedirs(args.out, exist_ok=True)
    rows_rgb, rows_black = [], []
    for y in range(h):
        a = alphas[(y // band) % len(alphas)]
        rows_rgb.append([(rgb[0], rgb[1], rgb[2], a)] * w)
        rows_black.append([(0, 0, 0, a)] * w)
    write_png(os.path.join(args.out, "bands_rgb.png"), w, h, rows_rgb, 4)
    write_png(os.path.join(args.out, "bands_black.png"), w, h, rows_black, 4)
    write_png(os.path.join(args.out, "bands_blank.png"), w, h,
              [[(0, 0, 0, 0)] * w for _ in range(h)], 4)
    with open(os.path.join(args.out, "known.json"), "w") as fh:
        json.dump({"alphas": alphas, "rgb": list(rgb), "band": band,
                   "sheet": [w, h]}, fh, indent=1)
    if h % (band * len(alphas)):
        print("WARNING: band period %d does not divide the sheet height %d, so the pattern is "
              "not frame-independent" % (band * len(alphas), h))
    print("control sheet %dx%d: bands of %d px, alphas %s of 255, rgb %s"
          % (w, h, band, alphas, list(rgb)))
    return 0


# ---------------------------------------------------------------------------------------------
# selftest: the arithmetic, with no Godot and no shot. Simulates the client's own blend.
# ---------------------------------------------------------------------------------------------
def selftest():
    """Round-trips every (bg, a) the window can hold through `round(bg*(1-a))` and back.

    THE GATE IS THE TOOL'S OWN BOUND, NOT A NUMBER I LIKE: for every pixel the true `a` must lie
    inside the interval the tool reports. A tolerance I chose would be a tolerance I could widen;
    this fails the moment the interval arithmetic is wrong in either direction.
    """
    worst, worst_at, n, outside = 0.0, None, 0, 0
    cworst, coutside, cn = 0.0, 0, 0
    truth = (208, 32, 160)
    for bgv in range(MIN_BG, 256, 7):
        bg = (bgv, max(MIN_BG, bgv - 13), min(255, bgv + 11))
        for ai in range(0, 256):
            a = ai / 255.0
            k = tuple(int(round(bg[i] * (1.0 - a))) for i in range(3))
            got = alpha_of(bg, k)
            assert got is not None, (bg, a)
            n += 1
            err = abs(got[0] - a)
            if err > got[1] + 1e-9:
                outside += 1
            if err > worst:
                worst, worst_at = err, (bg, a, got)
            # THE COLOUR ARM, through the same simulated blend, so the propagated interval is
            # tested with no Godot in the room: `screen = round(bg*(1-a) + c*a)`.
            screen = tuple(int(round(bg[i] * (1.0 - a) + truth[i] * a)) for i in range(3))
            cg = unblend_bound(screen, bg, got[0], got[1])
            if cg:
                cn += 1
                ce = max(abs(cg[0][i] - truth[i]) for i in range(3))
                if ce > cg[1] + 1e-6:
                    coutside += 1
                cworst = max(cworst, ce)
    # the UNSTABLE arm must fire, or it is decoration
    fired = unstable((100, 100, 100), (101, 100, 100)) < 0 and \
        unstable((100, 100, 100), (102, 100, 100)) == 0
    print("SELFTEST %d pixels: worst |a - a_hat| %.5f (%.2f/255), %d outside the reported bound"
          % (n, worst, worst * 255.0, outside))
    print("  worst at bg %s a %.4f -> a_hat %.4f, bound %.4f"
          % (worst_at[0], worst_at[1], worst_at[2][0], worst_at[2][1]))
    print("  UNBLENDED COLOUR on %d of those: worst error %.2f of 255, %d outside the "
          "propagated bound" % (cn, cworst, coutside))
    print("  UNSTABLE fires at K = bg+2 and not at K = bg+1: %s" % ("yes" if fired else "NO"))
    ok = outside == 0 and coutside == 0 and cn > 0 and fired
    print("SELFTEST %s" % ("GREEN" if ok else "RED"))
    return 0 if ok else 1


# ---------------------------------------------------------------------------------------------
# field: the tool on a real shot set
# ---------------------------------------------------------------------------------------------
def run_field(args):
    rect = tuple(int(v) for v in args.rect.split(",")) if args.rect else MAP_RECT
    for p in [args.bg, args.black] + ([args.shot] if args.shot else []):
        if not os.path.exists(p):
            print("NO VERDICT: %s is not there" % p)
            return 2
    _, _, bg = read_rgba(args.bg)
    _, _, kk = read_rgba(args.black)
    fld, rep = field(bg, kk, rect, args.min_bg)
    drawn = drawn_of(fld)
    sil = silhouette_of(drawn)
    print("WINDOW ALPHA over rect %s (%d px)" % (str(rect), rep["area"]))
    print("  %d px hold some of this sheet; %d are DRAWN (a*255 > %d), %d are the FRINGE"
          % (len(fld), len(drawn), OPAQUE, len(fld) - len(drawn)))
    print("  silhouette (4-neighbour, the sheet checks' own definition): %d px" % len(sil))
    bounds = [b * 255.0 for (_, b) in fld.values()]
    if bounds:
        print("  bound on a, in grey levels: median %.2f/255, p95 %.2f/255, worst %.2f/255"
              % (pct(bounds, 0.5), pct(bounds, 0.95), max(bounds)))
    print("  REFUSED: %d UNSTABLE (the two runs contradict the model -- another sheet moved), "
          "%d too dark (bg < %d), %d too faint to resolve (interval contains a = 0)"
          % (len(rep["unstable"]), len(rep["too_dark"]), args.min_bg, rep["unresolved"]))
    if rep["unstable"]:
        xs = [p[0] for p in rep["unstable"]]
        ys = [p[1] for p in rep["unstable"]]
        print("    unstable bbox x %d..%d y %d..%d" % (min(xs), max(xs), min(ys), max(ys)))
    if drawn:
        bx = (min(p[0] for p in drawn), max(p[0] for p in drawn),
              min(p[1] for p in drawn), max(p[1] for p in drawn))
        print("  drawn bbox x %d..%d y %d..%d = %dx%d"
              % (bx[0], bx[1], bx[2], bx[3], bx[1] - bx[0] + 1, bx[3] - bx[2] + 1))
    if args.shot:
        _, _, sh = read_rgba(args.shot)
        cols = [unblend(sh[y][x], bg[y][x], fld[(x, y)][0]) for (x, y) in drawn]
        cols = [c for c in cols if c]
        if cols:
            lum = sorted(0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2] for c in cols)
            print("  UNBLENDED colour of the drawn px in %s: L p05 %.1f p50 %.1f p95 %.1f"
                  % (os.path.basename(args.shot), lum[len(lum) // 20], lum[len(lum) // 2],
                     lum[-max(1, len(lum) // 20)]))
    if args.png:
        x0, y0, x1, y1 = rect
        shaky = refused(rep)
        rows = []
        for y in range(y0, y1):
            row = []
            for x in range(x0, x1):
                got = fld.get((x, y))
                if got is None:
                    # RED for a pixel the tool REFUSED, so a refusal is as visible as an answer.
                    row.append((190, 30, 30) if (x, y) in shaky else (0, 0, 0))
                else:
                    v = int(round(got[0] * 255.0))
                    row.append((v, v, v) if (x, y) in drawn else (0, v, v))
            rows.append(row)
        write_png(args.png, x1 - x0, y1 - y0, rows, 3)
        print("  wrote %s: grey = drawn alpha, cyan = fringe, RED = REFUSED (unstable or "
              "background too dark), black = resolvably nothing" % args.png)
    return 0


# ---------------------------------------------------------------------------------------------
# control: a sheet whose alpha I authored, recovered off a real window shot
# ---------------------------------------------------------------------------------------------
def run_control(args):
    """The control for ASSA-181 box 3. `--dir` holds bg.png, black.png, shot.png, known.json.

    `known.json` names the authored alpha values and the authored RGB; the answer key never
    reaches the estimator, only the comparison.

    WHY THIS NEEDS NO PIXEL-TO-PIXEL MAPPING, which is the part that would have made it a second
    thing to get wrong: the control sheet is horizontal bands of CONSTANT alpha spanning its whole
    width and repeating every band-period down every frame, so whichever animation frame the
    client happened to draw, every drawn pixel's authored alpha is one of the band values. The
    tool is never told where the sprite is.

    THREE GATES, AND THE REASON THERE ARE THREE. The one that matters is CONTAINMENT: the true
    alpha must lie inside the interval the tool reported for that pixel. That is the claim the
    tool actually makes, and it goes red if the blend model or the interval arithmetic is wrong
    in either direction. But containment ALONE IS BUYABLE BY WIDENING -- an estimator that
    reported "a is somewhere in [0, 1]" would pass it for ever, which is the
    instrument-that-cannot-fail Maren caught me building on 2026-10-04. So:

      1. CONTAINMENT   every px: |a_hat - a| <= the bound the tool reported for that px.
      2. PRECISION     the MEDIAN reported bound must itself be <= `--tol`. This is what
                       widening cannot survive, and it is measured against the tool's claim,
                       not against the outcome.
      3. CONDITIONAL   among px whose reported bound is <= `--tol` -- selected from `bg` and `K`
                       alone, before the answer key is opened -- the worst error must be
                       <= `--tol`. "Where it claims 1/255, it delivers 1/255."

    `--tol` is NOT a tolerance on the result; the result's tolerance is per-pixel and derived.
    It is the precision this control demands the tool ACHIEVE, and 1/255 is the figure ASSA-181
    box 3 asked for. Pixels over a dark background cannot reach it -- the window's resolution
    there is 1/(2*bg) -- and they are reported in a row of their own rather than dropped.
    """
    need = ["bg.png", "black.png", "shot.png", "known.json"]
    for n in need:
        if not os.path.exists(os.path.join(args.dir, n)):
            print("NO VERDICT: %s/%s is not there" % (args.dir, n))
            return 2
    known = json.load(open(os.path.join(args.dir, "known.json")))
    want = sorted(v / 255.0 for v in known["alphas"])
    rgb = known["rgb"]
    _, _, bg = read_rgba(os.path.join(args.dir, "bg.png"))
    _, _, kk = read_rgba(os.path.join(args.dir, "black.png"))
    _, _, sh = read_rgba(os.path.join(args.dir, "shot.png"))
    rect = tuple(int(v) for v in args.rect.split(",")) if args.rect else MAP_RECT
    fld, rep = field(bg, kk, rect, args.min_bg)
    print("CONTROL: authored alphas %s of 255, authored rgb %s"
          % (known["alphas"], rgb))
    print("  %d px hold the control sheet; %d UNSTABLE, %d too dark"
          % (len(fld), len(rep["unstable"]), len(rep["too_dark"])))
    if not fld:
        print("CONTROL RED: the sheet was not drawn at all")
        return 1
    errs, bounds, tight, loose = [], [], [], []
    cerrs, cbounds, c_in = [], [], 0
    in_bound, hist = 0, {v: 0 for v in known["alphas"]}
    for (x, y), (a, half) in fld.items():
        near = min(want, key=lambda w: abs(w - a))
        e = abs(a - near) * 255.0
        errs.append(e)
        bounds.append(half * 255.0)
        hist[int(round(near * 255.0))] += 1
        if abs(a - near) <= half + 1e-9:
            in_bound += 1
        # SELECTED BEFORE THE ANSWER KEY IS OPENED: `half` comes from bg and K only.
        (tight if half * 255.0 <= args.tol else loose).append(e)
        got = unblend_bound(sh[y][x], bg[y][x], a, half)
        if got:
            c, cw = got
            ce = max(abs(c[i] - rgb[i]) for i in range(3))
            cerrs.append(ce)
            cbounds.append(cw)
            if ce <= cw + 1e-9:
                c_in += 1
    print("  ALPHA, against the NEAREST authored band, in grey levels of 255:")
    print("    error   median %.3f  p95 %.3f  worst %.3f" % (pct(errs, 0.5), pct(errs, 0.95),
                                                             max(errs)))
    print("    bound   median %.3f  p95 %.3f  worst %.3f" % (pct(bounds, 0.5), pct(bounds, 0.95),
                                                             max(bounds)))
    print("    px per authored band: %s" % ", ".join("%d:%d" % kv for kv in sorted(hist.items())))
    print("  1 CONTAINMENT  %d of %d px inside their own reported bound (%.2f%%)"
          % (in_bound, len(errs), 100.0 * in_bound / len(errs)))
    print("  2 PRECISION    median reported bound %.3f, gate <= %.2f" % (pct(bounds, 0.5),
                                                                         args.tol))
    print("  3 CONDITIONAL  of the %d px claiming a bound <= %.2f, worst error %.3f; the other "
          "%d (dark background) worst %.3f"
          % (len(tight), args.tol, max(tight) if tight else 0.0, len(loose),
             max(loose) if loose else 0.0))
    if cerrs:
        print("  UNBLENDED COLOUR, worst channel vs the authored rgb:")
        print("    error median %.2f  p95 %.2f  worst %.2f;  propagated bound median %.2f "
              "worst %.2f" % (pct(cerrs, 0.5), pct(cerrs, 0.95), max(cerrs),
                              pct(cbounds, 0.5), max(cbounds)))
        print("    inside the propagated bound: %d of %d (%.2f%%)"
              % (c_in, len(cerrs), 100.0 * c_in / len(cerrs)))
    bands_seen = sum(1 for v in hist.values() if v > 20)
    print("  bands with more than 20 px: %d of %d" % (bands_seen, len(hist)))
    ok = (in_bound == len(errs)
          and pct(bounds, 0.5) <= args.tol
          and (not tight or max(tight) <= args.tol)
          and (not cerrs or c_in == len(cerrs))
          and bands_seen == len(hist))
    print("CONTROL %s" % ("GREEN" if ok else "RED"))
    return 0 if ok else 1


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("mode", nargs="?", default="field",
                    choices=["field", "control", "variants", "bands"])
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--bg")
    ap.add_argument("--black")
    ap.add_argument("--shot")
    ap.add_argument("--sheet")
    ap.add_argument("--out")
    ap.add_argument("--dir")
    ap.add_argument("--png")
    ap.add_argument("--rect")
    ap.add_argument("--min-bg", type=int, default=MIN_BG, dest="min_bg")
    ap.add_argument("--tol", type=float, default=1.0)
    ap.add_argument("--alphas", default="64,128,192,255")
    ap.add_argument("--rgb", default="208,32,160")
    ap.add_argument("--band", type=int, default=8)
    ap.add_argument("--w", type=int, default=512)
    ap.add_argument("--h", type=int, default=2048)
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    if args.mode == "variants":
        if not (args.sheet and args.out):
            print("NO VERDICT: variants needs --sheet and --out")
            return 2
        return run_variants(args)
    if args.mode == "bands":
        if not args.out:
            print("NO VERDICT: bands needs --out")
            return 2
        return run_bands(args)
    if args.mode == "control":
        if not args.dir:
            print("NO VERDICT: control needs --dir")
            return 2
        return run_control(args)
    if not (args.bg and args.black):
        print("NO VERDICT: field needs --bg and --black")
        return 2
    return run_field(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
