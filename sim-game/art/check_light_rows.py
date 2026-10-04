#!/usr/bin/env python3
"""A FIRE IS NOT MADE OF THE WALLS. (ASSA-137)

    art/check_light_rows.py             # the guard
    art/check_light_rows.py --tinted    # prove it red: tint the light rows

The client tints a world sprite with Godot `modulate`, a per-channel MULTIPLY
by the species colour. For a wall that is right -- the wall is made of the
species. For a fire it is a bug with no bottom to it: a multiply can only
subtract, so a pixel standing for EMITTED LIGHT is capped by a number it has
nothing to do with, and no amount of emission in Blender can lift it back.
Maren measured the shipped smelter and the brightest pixel of a burning fire
came out BELOW the ground's median luminance in three of the six species
(#3333FF -82.4, #7A29CC -77.9, #FF3333 -52.8) and a wash in two more. The
demo's own smelter is the species that cleared it by 11.7.

Her rule, which is wider than the smelter: A QUANTITY THE SIM TREATS AS
INDEPENDENT OF SPECIES MAY NOT BE DRAWN IN A CHANNEL SPECIES MULTIPLIES.

So a light row exists (`rig.Asset.light_row`, `build.py:light_layer`), carries
`"light": true` and `"over": <body row>` in the manifest, and is drawn
untinted on top of its tinted body. This file is what stops that from quietly
coming undone. It composites exactly what the client draws -- nearest, 32px per
tile, the body multiplied by each species tint, the light row over it at full
white -- onto the shipped ground, and holds two things:

  A. THE LIGHT CLEARS THE DIRT IN EVERY SPECIES. Its brightest pixel must beat
     the ground's median luminance, which is the sentence from the bug report
     turned into a number. This is not free: it is a property of the derived
     ALPHA. A dimmer render, or a threshold in `light_layer` set high enough to
     drop the hot core, pulls the dark species back under the ground and this
     goes red.

  B. NO SPECIES SEES LESS OF THE LIGHT THAN THE UNTINTED SHEET DOES. The floor
     is the row's own untinted contrast, measured in the same run -- derived,
     not chosen, and it cannot be tuned, because making the art brighter raises
     the floor by the same amount. It holds because a dark tint darkens the
     body the light is read against; the day it fails, light has leaked back
     into the multiply.

WHY B AND NOT JUST A. A is about one pixel and could be passed by a single hot
coal on an otherwise dead sheet. B is about the whole sprite and is the thing a
player actually reads from across a field: lit smelter, not lit smelter.

TWO CONTROLS RUN EVERY TIME, the shape `check_headroom.py` uses:
  1. WIRING -- there must be a light row, it must have ink, its body must
     exist, and the two must not be the same picture.
  2. IT CAN FAIL -- `--tinted` is also run in-process every time: the light row
     is passed through the species multiply, the way the sheet shipped before
     ASSA-137, and the judge must reject it. It reproduces Maren's table.
  Neither holding is a pass: both exit 2.

EXIT CODES
  0 PASS       -- every light row clears the ground and loses nothing to a tint.
  1 FAIL       -- a light row is being dimmed by the species it is drawn in.
  2 NO VERDICT -- sheets unreadable or a control did not hold. Never a pass.

Stdlib only: CI runs this on plain `python3` with no pip. Pixels come from
`png_stdlib.read_rgba`, the one decoder every other check reads sheets with.
"""
import json, os, sys

ART = os.path.dirname(os.path.abspath(__file__))
SPRITES = os.path.join(os.path.dirname(ART), "client", "assets", "sprites")
sys.path.insert(0, ART)
from png_stdlib import read_rgba              # noqa: E402  (after sys.path, on purpose)
from species_tints import SPECIES_TINTS       # noqa: E402

TILE = 32        # display pixels per tile, the size this is judged at
OPAQUE = 127     # alpha above this is surface, matching Maren's measurement


class CannotCheck(Exception):
    pass


def lum(p):
    return 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]


def nearest(px, x0, y0, w, h, dw, dh):
    """A (w, h) window of `px` resampled to (dw, dh) the way the engine samples.

    Nearest with the sample taken at the destination pixel's CENTRE, which is
    what Godot does and what Pillow's NEAREST does, so this agrees with Maren's
    Pillow measurements rather than being off by half a texel from them.
    """
    return [[px[y0 + min(h - 1, int((j + 0.5) * h / dh))][x0 + min(w - 1, int((i + 0.5) * w / dw))]
             for i in range(dw)] for j in range(dh)]


def ground_median(sprites, man):
    g = man.get("ground")
    if not g:
        raise CannotCheck("no ground in the manifest; there is nothing to be brighter than.")
    gw, gh = g["frame_px"]
    _w, _h, px = read_rgba(os.path.join(sprites, g["sheet"]))
    vals = []
    for i in range(len(g["rows"])):
        for line in nearest(px, 0, i * gh, gw, gh, TILE, TILE):
            vals += [lum(p) for p in line]
    if not vals:
        raise CannotCheck("the ground sheet had no pixels.")
    return sorted(vals)[len(vals) // 2]


def multiply(p, tint):
    return tuple(p[c] * tint[c] // 255 for c in range(3)) + (p[3],)


def composite(body, light, tint, light_tint):
    """One pixel of what the client draws: light over (tint * body).

    `light_tint` is (255, 255, 255) in the real run. The can-fail control passes
    the species tint in, which is precisely the defect ASSA-137 removed.
    """
    b = multiply(body, tint)
    a = light[3] / 255.0
    f = multiply(light, light_tint)
    return tuple(f[c] * a + b[c] * (1 - a) for c in range(3))


def hex_rgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def measure(pairs, tint_the_light):
    """[(row, tint name, max light luminance, mean cold->lit contrast)] for every pair.

    `tint_the_light` is False in the real run: the light row is drawn at full white. The
    can-fail control passes True, which puts the light back through the species multiply
    -- the sheet exactly as it shipped before ASSA-137.
    """
    out = []
    for key, (body, light) in sorted(pairs.items()):
        lit_px = [(y, x) for y in range(len(light)) for x in range(len(light[0]))
                  if light[y][x][3] > 0]
        ink = [(y, x) for y in range(len(body)) for x in range(len(body[0]))
               if body[y][x][3] > OPAQUE]
        for name in ["none"] + list(SPECIES_TINTS):
            t = (255, 255, 255) if name == "none" else hex_rgb(name)
            lt = t if tint_the_light else (255, 255, 255)
            top = max(lum(composite(body[y][x], light[y][x], t, lt)) for y, x in lit_px)
            d = [abs(lum(composite(body[y][x], light[y][x], t, lt))
                     - lum(multiply(body[y][x], t))) for y, x in ink]
            out.append((key, name, top, sum(d) / len(d)))
    return out


def judge(measured, floor):
    """[(row, tint, why)] for every pair that fails A or B. One judge, both runs."""
    untinted = {r: c for r, n, _t, c in measured if n == "none"}
    bad = []
    for row, name, top, contrast in measured:
        if top <= floor:
            bad.append((row, name, "brightest light pixel %.1f, ground median %.1f (A)"
                        % (top, floor)))
        elif contrast < untinted[row] - 0.5:
            bad.append((row, name, "contrast %.2f against %.2f untinted (B)"
                        % (contrast, untinted[row])))
    return bad


def load(sprites):
    """{asset/row: (body pixels, light pixels)} at display size, plus the ground median."""
    path = os.path.join(sprites, "manifest.json")
    if not os.path.exists(path):
        raise CannotCheck("no manifest at %s -- run art/build.py" % path)
    man = json.load(open(path))
    pairs = {}
    for name, a in sorted(man.items()):
        if not isinstance(a, dict) or "sheet" not in a:
            continue
        lights = [r for r in a["rows"] if r.get("light")]
        if not lights:
            continue
        fw, fh = a["frame_px"]
        dw = a["tiles"][0] * TILE
        dh = int(round(fh * dw / float(fw)))
        _w, _h, px = read_rgba(os.path.join(sprites, a["sheet"]))
        index = {r["name"]: i for i, r in enumerate(a["rows"])}
        for r in lights:
            over = r.get("over")
            if over not in index:
                raise CannotCheck("%s/%s is a light row whose `over` is %r, which is not a "
                                  "row of %s. A light row that does not say what it sits on "
                                  "cannot be drawn or checked."
                                  % (name, r["name"], over, name))
            pairs["%s/%s" % (name, r["name"])] = (
                nearest(px, 0, index[over] * fh, fw, fh, dw, dh),
                nearest(px, 0, index[r["name"]] * fh, fw, fh, dw, dh))
    return pairs, ground_median(sprites, man)


def main(argv):
    pairs, floor = load(SPRITES)
    white = (255, 255, 255)

    # CONTROL 1, WIRING.
    if not pairs:
        raise CannotCheck("no row in the shipped manifest carries `light: true`. Either the "
                          "smelter's fire stopped being its own row, or this check is "
                          "looking at a manifest built before ASSA-137. It is measuring "
                          "nothing either way.")
    for key, (body, light) in pairs.items():
        if not any(p[3] for line in light for p in line):
            raise CannotCheck("%s is empty: a fully transparent light row passes every "
                              "brightness test ever written." % key)
        if body == light:
            raise CannotCheck("%s and its body are the same picture, so the split this "
                              "check exists to defend did not happen." % key)

    measured = measure(pairs, tint_the_light=False)

    # CONTROL 2, IT CAN FAIL: run the light rows back through the species multiply -- the
    # sheet as it shipped before ASSA-137 -- and require the judge to reject it.
    was = measure(pairs, tint_the_light=True)
    if not judge(was, floor):
        raise CannotCheck("the can-fail control did not fail: every light row was put back "
                          "through the species multiply and this check still passed it. The "
                          "guard is not wired to the verdict.")

    if "--tinted" in argv:
        measured = was

    print("LIGHT ROWS -- drawn as the client draws them: nearest, %dpx per tile, body\n"
          "multiplied by the species tint, the light row over it%s.\n"
          % (TILE, " MULTIPLIED TOO (--tinted: this is the defect)" if "--tinted" in argv
             else " at full white"))
    print("ground median luminance %.1f\n" % floor)
    print("%-20s %-9s %12s %10s %10s" % ("row", "tint", "light max", "vs ground", "contrast"))
    for row, name, top, contrast in measured:
        print("%-20s %-9s %12.1f %+10.1f %10.2f" % (row, name, top, top - floor, contrast))

    bad = judge(measured, floor)
    if bad:
        print("\n%d LIGHT ROW/SPECIES PAIR(S) ARE BEING DIMMED BY A SPECIES:" % len(bad))
        for row, name, why in bad:
            print("  %-20s %-9s %s" % (row, name, why))
        print("\nA multiply can only subtract. If a light row is reaching the species tint,\n"
              "the renderer is drawing it with a modulate it may not use, or `light_layer`\n"
              "stopped giving the hot core alpha 1. See ASSA-137.")
        print("\nVERDICT: FAIL (exit 1).")
        return 1
    print("\nVERDICT: PASS (exit 0). Every light row clears the ground in every species,\n"
          "no species sees less of it than the untinted sheet does, and both controls held.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except CannotCheck as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n%s" % why)
        sys.exit(2)
