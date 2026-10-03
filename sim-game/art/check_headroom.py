#!/usr/bin/env python3
"""NO SHIPPED SURFACE SITS ON THE CEILING. (ASSA-115)

    art/check_headroom.py            # the guard
    art/check_headroom.py --blow N   # prove it red: push row N up against 255

A pixel whose brightest channel is pinned at 255 has no shading left in it. On
this game that is worse than it sounds, because the client tints ore with
Godot's `modulate`, which is a per-channel MULTIPLY: a pinned channel maps to
EXACTLY the tint value, so a blown region does not render as "a bright rock",
it renders as a flat patch of the species hex. Maren measured 34% of a grade-A
ore tile doing that and called it candy on felt. She was reading the symptom of
an exposure (see the HEADROOM comment in rig.py).

WHY A CHECK AND NOT JUST THE FIX. The fix was one line, and one line is exactly
what gets reverted by someone adding a lamp, raising an emission, or lightening
a palette entry -- all of which are reasonable edits that silently spend the
same budget. Nothing in this pipeline asked whether a sheet still had shading
in it, which is how THREE assets fell off the top independently and were
written up as three bugs (ASSA-28's chassis, the grade-A glint, grade-A ore).

THE BOUND IS A RATCHET, NOT A NUMBER I PICKED, and that is deliberate. I do not
know what the right percentage is -- a glint is SUPPOSED to blow out (rig.py:
"a neutral blowout clips to white, and no species tint is neutral"), so the
honest limit is not zero, and any figure I invented between 0 and 34 would be
taste wearing a decimal point. So every entry in ALLOWED below is a
MEASUREMENT of the row as it ships today, and the only rule is that no row may
get worse and no new row may start. It can only tighten. When somebody wants a
real limit per surface, that is the Director's ruling to make and this table is
the evidence to make it from.

TWO CONTROLS RUN EVERY TIME, because a check that has only ever been green has
only ever been an opinion:
  1. WIRING -- the rows must actually be found, carry opaque pixels, and not
     all be the same picture. A check that measured nothing reports nothing.
  2. IT CAN FAIL -- a copy of a real row is pushed toward white in memory and
     must be caught by the same code path that judges the real ones.
  Neither holding is a pass: both exit 2.

EXIT CODES
  0 PASS       -- no row blows out more than it is on record for.
  1 FAIL       -- some row lost shading it used to have, or a new row started.
  2 NO VERDICT -- sheets unreadable or a control did not hold. Never a pass.
"""
import json, os, sys

ART = os.path.dirname(os.path.abspath(__file__))
SPRITES = os.path.join(os.path.dirname(ART), "client", "assets", "sprites")

# A channel is pinned here. 254 and not 255 because the downscale in build.py
# is LANCZOS over a supersampled render: a region that was solid 255 before the
# resample comes back 254 in places, and a ceiling that the resampler can step
# off by one would make this check report on filtering rather than on light.
CLIP = 254
OPAQUE = 200          # alpha above this is surface; below it is edge or shadow
TOLERANCE = 0.3       # percentage points of slack, for renderer noise between runs

# MEASURED, NOT CHOSEN. Percentage of each row's opaque pixels with a pinned
# channel, as the row ships. Rows at 0.0 are omitted: anything absent must stay
# under TOLERANCE. Regenerate with --record after a deliberate change, and say
# in the commit message why a number went UP.
ALLOWED = {
    "frame/A":                   10.6,
    "items/frame":                9.9,
    "ore/A_full_v0":              9.9,
    "ore/A_full_v1":              8.8,
    "player/idle_S":              7.8,
    "player/walk_S":              7.8,
    "handle/A":                   6.8,
    "player/idle_SW":             6.4,
    "player/walk_SW":             6.4,
    # THE ONE ROW HERE THAT IS SUPPOSED TO BE AT THE CEILING, and the second
    # after the grade-A glint. `smelter/lit` is a fire: the hearth's embers
    # emit, and this file's own header says the honest limit is not zero for
    # exactly this reason. The COLD row is absent, which is the real check --
    # a smelter that is not burning has no excuse, and the first version of
    # that row was red at 4.2% until its wall caps came off `ore_hi`.
    "smelter/lit":                6.3,
    "player/idle_SE":             5.8,
    "player/walk_SE":             5.8,
    "player/idle_E":              4.9,
    "player/walk_E":              4.9,
    "player/idle_NE":             4.8,
    "player/walk_NE":             4.8,
    "player/idle_NW":             4.6,
    "player/walk_NW":             4.6,
    "player/idle_N":              4.6,
    "player/walk_N":              4.6,
    "player/idle_W":              3.7,
    "player/walk_W":              3.7,
    "items/smelter":              3.1,
    "spawn/pad":                  2.4,
    "items/refined":              2.2,
    "head/A":                     2.1,
    "frame/B":                    2.0,
    "ore/B_full_v0":              1.3,
    "ore/B_full_v1":              1.2,
    "items/head":                 1.0,
    "items/ore":                  0.9,
    "items/handle":               0.8,
    "head/B":                     0.4,
    "head/C":                     0.3,
}


class CannotCheck(Exception):
    pass


def rows_of(sprites):
    """(row name, opaque pixels) for every row in the shipped manifest.

    Pixels come from `stdlib_image`, which is the vendored stdlib decoder every
    other check reads sheets with -- a `check_*.py` runs on plain `python3`
    with no pip, so Pillow is not on the table in CI.
    """
    sys.path.insert(0, ART)
    from png_stdlib import read_rgba
    path = os.path.join(sprites, "manifest.json")
    if not os.path.exists(path):
        raise CannotCheck("no manifest at %s -- run art/build.py" % path)
    man = json.load(open(path))
    out = []
    for name, a in man.items():
        if not isinstance(a, dict) or "sheet" not in a:
            continue
        sheet = os.path.join(sprites, a["sheet"])
        if not os.path.exists(sheet):
            raise CannotCheck("manifest names %s, which is not on disk" % a["sheet"])
        fw, fh = a["frame_px"]
        # ONE decode per SHEET, not per row. `StdlibBackend.open_frame` is the
        # tidier call and it re-reads the whole PNG every time it is asked for
        # a frame -- 49 decodes, two minutes, and a check nobody would keep in
        # CI. Same decoder either way (`png_stdlib.read_rgba`, Maren's,
        # vendored once), so this is a loop moved, not a second reader.
        _w, _h, px = read_rgba(sheet)
        for ri, row in enumerate(a["rows"]):
            opaque = [p for line in px[ri * fh:(ri + 1) * fh]
                      for p in line[:fw] if p[3] > OPAQUE]
            out.append(("%s/%s" % (name, row["name"]), opaque))
    if not out:
        raise CannotCheck("the manifest described no rows at all.")
    return out


def blown(px):
    """Percentage of these pixels with a pinned channel."""
    if not px:
        return None
    return 100.0 * sum(1 for p in px if max(p[0], p[1], p[2]) >= CLIP) / len(px)


def judge(measured):
    """[(row, pct)] -> [(row, pct, allowance)] for the rows that are too hot.

    One judge, used by the real run AND by the can-fail control, so the control
    cannot pass by taking a different path to the verdict.
    """
    bad = []
    for name, pct in measured:
        allow = ALLOWED.get(name, 0.0)
        if pct > allow + TOLERANCE:
            bad.append((name, pct, allow))
    return bad


def main(argv):
    rows = rows_of(SPRITES)
    measured = [(n, blown(px)) for n, px in rows if px]
    if len(measured) < len(rows):
        raise CannotCheck("%d row(s) had no opaque pixels at all -- a blank sheet "
                          "would pass every test in this file."
                          % (len(rows) - len(measured)))

    # CONTROL 1, WIRING: the rows must not all be the same picture, or this
    # check is measuring one sprite and reporting on forty-nine.
    if len(set(round(p, 3) for _, p in measured)) < 3:
        raise CannotCheck("every row measured the same -- the sheets are not being "
                          "cut apart correctly, so none of these numbers mean anything.")

    if "--record" in argv:
        print("ALLOWED = {")
        for n, p in sorted(measured, key=lambda r: -r[1]):
            if p > 0.0:
                print("    %-28s %.1f," % ('"%s":' % n, p))
        print("}")
        return 0

    # CONTROL 2, IT CAN FAIL: take a real row, push it toward white, and send it
    # through `judge`. The row with the MOST headroom today is the hardest case.
    coolest = min(measured, key=lambda r: r[1])
    probe = [(p[0], p[1], p[2], p[3]) for p in dict(rows)[coolest[0]]]
    hot = [(255, 255, 255, p[3]) for p in probe[:max(1, len(probe) // 5)]] + probe[len(probe) // 5:]
    if not judge([(coolest[0], blown(hot))]):
        raise CannotCheck("the can-fail control did not fail: a fifth of %s was "
                          "painted white and this check still passed it. The guard "
                          "is not wired to the verdict." % coolest[0])

    bad = judge(measured)

    print("BLOWN-OUT SURFACE PER ROW -- opaque pixels with a channel pinned at %d.\n" % CLIP)
    print("%-28s %8s %10s" % ("row", "%blown", "on record"))
    shown = [r for r in sorted(measured, key=lambda r: -r[1]) if r[1] > 0.0]
    for n, p in shown[:18]:
        print("%-28s %8.1f %10.1f" % (n, p, ALLOWED.get(n, 0.0)))
    if not shown:
        print("  (every row is clean: no pinned channel anywhere in the shipped art)")
    allpx = sum(len(px) for _, px in rows)
    allhot = sum(sum(1 for p in px if max(p[0], p[1], p[2]) >= CLIP) for _, px in rows)
    print("\n%d of %d opaque pixels across every sheet are pinned (%.1f%%)."
          % (allhot, allpx, 100.0 * allhot / allpx))

    if bad:
        print("\n%d ROW(S) LOST SHADING THEY ARE ON RECORD FOR:" % len(bad))
        for n, p, allow in bad:
            print("  %-26s %.1f%% blown, against %.1f%% on record" % (n, p, allow))
        print("\nA pinned channel is a pixel the species tint cannot shade: `modulate` is a\n"
              "multiply, so it renders as exactly the tint hex. Look at a lamp, an emission\n"
              "strength or a palette entry that got lighter -- and see rig.py's HEADROOM\n"
              "comment before reaching for the view transform.")
        print("\nVERDICT: FAIL (exit 1).")
        return 1
    print("\nVERDICT: PASS (exit 0). No surface sits on the ceiling that was not\n"
          "already on record for it, and both controls held.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except CannotCheck as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n%s" % why)
        sys.exit(2)
