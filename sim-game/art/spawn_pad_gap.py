#!/usr/bin/env python3
"""IS THERE A COLOUR THE SPAWN PAD CAN BE? (ASSA-283, the gap Maren's ruling gates on)

    art/spawn_pad_gap.py [--dump <engine dump>]

Maren ruled option 1 -- lift the pad's ink -- with a gate and a hard fallback:

    "LIFT THE INK UNTIL IT CLEARS 3:1 AGAINST MAP_BG ... it must stay strictly
     dimmer than the dimmest deposit disc the generator can produce. Spawn must
     never read as ore. Measure that gap before you pick the value."
    "IF THE GAP IS EMPTY ... THE PAD LOSES BOTH ITS ROW AND ITS PIXELS."

So the value is not a taste question and this file is the measurement, run before
any constant moved. It answers three things, in order:

  A. THE GATE AS WORDED. The luminance that clears 3:1 against `MAP_BG`, against
     the luminance of the dimmest disc `worldgen` can roll. If the first is above
     the second the gate is unsatisfiable and the fallback branch applies.
  B. WHY, per species, because the shape of the miss is the finding. A disc's
     dim end is `base + span * 0.05` of a species' own slot, and four of the six
     slots are dark enough that their dimmest disc is itself under the 3:1 mark
     floor. The conflict is structural, not a near miss.
  C. THE GATE RE-ASKED ON THE AXIS THE RULING MEANT. "Must not read as ore" is a
     question about hue and chroma, and the studio already has an instrument for
     it: `dAB` (dE on a*/b*, L* dropped because on this map brightness means
     purity) against `DISTINCT = 12`, Maren's own threshold for two species a
     player must never confuse. Sweeping candidate pad colours against all 600
     disc states says whether a visible pad can be far from every ore.

NO NUMBER IS RETYPED HERE. The tints, the dim base, the span, the purity clamp,
`MAP_BG` and `SPAWN_PAD` all come out of `hud.gd` (the `_hud` readers below, the
pattern `species_probe.py` uses), and `dE`/`DISTINCT` come from `art/colour.py`.
Stdlib only, so CI's plain `python3` can run it.

AND IT IS CHECKED AGAINST THE ENGINE, because a replica of `deposit_color` is
exactly the kind of thing that passes while disagreeing with what is drawn. With
`--dump <file>` holding `ROW <species> <purity> <r> <g> <b> <lum> <contrast>`
lines printed by the client itself, every state is compared and the worst
disagreement is reported. The numbers in the item were taken with the dump.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from colour import DISTINCT, lab  # noqa: E402

ART = os.path.dirname(os.path.abspath(__file__))
HUD_GD = os.path.join(os.path.dirname(ART), "client", "scripts", "hud.gd")

# WCAG's floor for a non-text mark, and Maren's §11.9: a 9x9 mark is a mark.
MARK_FLOOR = 3.0


def _hud(pattern, what, scope=None):
    """Numbers out of hud.gd, or a loud exit. Never a retyped copy."""
    text = open(HUD_GD).read()
    if scope:
        body = re.search(scope, text, re.DOTALL)
        if not body:
            sys.exit("spawn_pad_gap: no %s in hud.gd." % what)
        text = body.group(0)
    found = re.search(pattern, text)
    if not found:
        sys.exit("spawn_pad_gap: cannot read %s out of hud.gd (pattern: %s).\n"
                 "  Fix the pattern rather than typing the number here: a second"
                 " copy of a\n  client constant is the bug this reader exists to"
                 " prevent." % (what, pattern))
    return [float(g) for g in found.groups()]


COLOUR = r"Color\(([0-9.]+), ([0-9.]+), ([0-9.]+)\)"
PAD = tuple(_hud(r"const SPAWN_PAD := " + COLOUR, "SPAWN_PAD"))
BG = tuple(_hud(r"const MAP_BG := " + COLOUR, "MAP_BG"))
TINTS = re.findall(r'"(#[0-9A-Fa-f]{6})"', open(HUD_GD).read())
DEPOSIT = r"static func deposit_color.*?\n\n"
BASE, SPAN = _hud(r"var dimmed := ([0-9.]+) \+ ([0-9.]+) \* purity_part",
                  "the disc's dim base and span", DEPOSIT)
PURITY_MIN = _hud(r"clampf\(float\(purity\) / 100.0, ([0-9.]+), 1.0\)",
                  "the purity clamp", DEPOSIT)[0]


def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lum(c):
    """WCAG relative luminance of a 0..1 triple. `AssayHud.relative_luminance`."""
    r, g, b = (lin(v) for v in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    x, y = lum(a) + 0.05, lum(b) + 0.05
    return x / y if x > y else y / x


def hex_rgb(h):
    return tuple(int(h[1 + 2 * i:3 + 2 * i], 16) / 255.0 for i in range(3))


def disc(species, purity):
    """`AssayHud.deposit_color` in python, the same line it runs."""
    part = min(1.0, max(PURITY_MIN, purity / 100.0))
    dimmed = BASE + SPAN * part
    return tuple(v * dimmed for v in hex_rgb(TINTS[species % len(TINTS)]))


def dAB(a, b):
    """dE on hue and chroma only, 0..255 triples. L* is dropped BECAUSE ON THIS
    MAP BRIGHTNESS ALREADY MEANS PURITY (`species_probe.dAB`, unchanged)."""
    la, lb = lab(a), lab(b)
    return ((la[1] - lb[1]) ** 2 + (la[2] - lb[2]) ** 2) ** 0.5


def px(c):
    return tuple(round(255 * v) for v in c)


def eightbit(c):
    """The colour as it is actually drawn. The framebuffer is 8-bit, so a candidate
    judged on floats can be reported clearing a floor that the drawn pixel misses
    -- which this file did in its first run, printing 2.998:1 beside 'clears 3:1'."""
    return tuple(v / 255.0 for v in px(c))


def lift_to_floor(c):
    """The same colour scaled until it clears the mark floor, 8-bit honest.

    Scaling r, g and b together is scaling HSV's V, so hue and saturation do not
    move -- which is what "same hue, brighter" in the option means."""
    k = 1.0
    while k < 8.0:
        out = eightbit(tuple(min(1.0, v * k) for v in c))
        if contrast(out, BG) >= MARK_FLOOR:
            return out, k
        k += 0.005
    return None, None


STATES = [(s, p) for s in range(len(TINTS)) for p in range(1, 101)]


def check_against_engine(path):
    worst = 0.0
    rows = 0
    for line in open(path):
        f = line.split()
        if not f or f[0] != "ROW":
            continue
        s, p = int(f[1]), int(f[2])
        mine = disc(s, p)
        worst = max(worst, max(abs(a - b) * 255.0 for a, b in zip(mine, map(float, f[3:6]))))
        rows += 1
    print("  checked against the engine's own answers: %d states, worst"
          " disagreement %.2e of a code value" % (rows, worst))
    if rows != len(STATES):
        print("  WARNING: the dump holds %d states, not %d" % (rows, len(STATES)))
    return worst


def main():
    dump = None
    if "--dump" in sys.argv:
        dump = sys.argv[sys.argv.index("--dump") + 1]
    print("SPAWN PAD vs THE DIMMEST ORE (ASSA-283)")
    print("  hud.gd: SPAWN_PAD %s, MAP_BG %s, disc = tint * (%.2f + %.2f * clamp(purity/100, %.2f, 1))"
          % (px(PAD), px(BG), BASE, SPAN, PURITY_MIN))
    print("  %d species slots: %s" % (len(TINTS), " ".join(TINTS)))
    if dump:
        check_against_engine(dump)

    floor_lum = MARK_FLOOR * (lum(BG) + 0.05) - 0.05
    discs = sorted(((lum(disc(s, p)), s, p) for s, p in STATES))
    dim_lum, dim_s, dim_p = discs[0]
    print("")
    print("A. THE GATE AS WORDED")
    print("   today's pad          lum %.6f   %.3f:1 vs MAP_BG" % (lum(PAD), contrast(PAD, BG)))
    print("   %.1f:1 needs          lum %.6f" % (MARK_FLOOR, floor_lum))
    print("   dimmest disc         lum %.6f   %.3f:1 vs MAP_BG   species %d purity %d %s"
          % (dim_lum, contrast(disc(dim_s, dim_p), BG), dim_s, dim_p, px(disc(dim_s, dim_p))))
    width = dim_lum - floor_lum
    if width > 0:
        print("   GAP IS %.6f WIDE: a pad may sit in [%.6f, %.6f)."
              % (width, floor_lum, dim_lum))
    else:
        print("   **GAP IS EMPTY.** The floor is %.6f ABOVE the dimmest disc --"
              " %.1fx its luminance." % (-width, floor_lum / dim_lum))
        print("   Nothing that clears %.1f:1 is dimmer than every disc, so the"
              " gate as worded" % MARK_FLOOR)
        print("   has no solution and the ruling's fallback branch is the live one.")

    print("")
    print("B. WHY, PER SPECIES: the dim end of the purity ladder lives under the mark floor")
    print("   slot      dimmest disc   vs MAP_BG   under the %.1f:1 floor?" % MARK_FLOOR)
    under = 0
    for s in range(len(TINTS)):
        d = disc(s, 1)
        bad = contrast(d, BG) < MARK_FLOOR
        under += bad
        print("   %-8s  %-13s  %6.3f:1   %s" % (TINTS[s], str(px(d)), contrast(d, BG),
                                                "YES" if bad else "no"))
    print("   %d of %d slots: a purity-1 patch of them is itself fainter than the floor that"
          % (under, len(TINTS)))
    print("   condemns the pad. Whether a radius-2..4 disc is a MARK or a REGION is Maren's")
    print("   vocabulary call (§11.9 separates them); the arithmetic is the same either way.")

    print("")
    print("C. THE GATE RE-ASKED ON HUE AND CHROMA: dAB >= %.0f (DISTINCT, art/colour.py)"
          % DISTINCT)
    print("   'must not read as ore' on the axis that carries species, with L* dropped")
    print("   because brightness on this map already means purity.")
    lifted, k = lift_to_floor(PAD)
    grey_lum = floor_lum
    g = 0.0
    while lum((g, g, g)) < grey_lum and g < 1.0:
        g += 0.0005
    candidates = [("today's olive", eightbit(PAD)), ("olive lifted x%.3f" % (k or 0), lifted),
                  ("neutral grey at the floor", eightbit((g, g, g)))]
    print("   candidate                   8-bit        vs MAP_BG   nearest disc (dAB)")
    for name, c in candidates:
        if c is None:
            print("   %-26s  unreachable" % name)
            continue
        near = min(((dAB(px(c), px(disc(s, p))), s, p) for s, p in STATES))
        print("   %-26s  %-11s  %6.3f:1   %6.2f  (species %d purity %d) %s"
              % (name, str(px(c)), contrast(c, BG), near[0], near[1], near[2],
                 "OK" if near[0] >= DISTINCT else "TOO CLOSE TO ORE"))
    print("   a hue sweep at the floor's luminance, 24 hues, same saturation as the pad:")
    best = None
    sat = (max(PAD) - min(PAD)) / max(PAD)
    for i in range(24):
        h = i / 24.0
        c = hsv(h, sat, 1.0)
        c = eightbit(scale_to_lum(c, floor_lum))
        near = min(((dAB(px(c), px(disc(s, p))), s, p) for s, p in STATES))
        if best is None or near[0] > best[0]:
            best = (near[0], h, c, near[1], near[2])
    print("   best hue %.3f at saturation %.2f: %s, nearest disc dAB %.2f (species %d purity %d)"
          % (best[1], sat, str(px(best[2])), best[0], best[3], best[4]))
    print("   (a sweep of the same FAMILY the pad is in, not a proposal: the pad's")
    print("   saturation is held and only the hue moves.)")


def hsv(h, s, v):
    i = int(h * 6) % 6
    f = h * 6 - int(h * 6)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    return [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]


def scale_to_lum(c, target):
    lo, hi = 0.0, 1.0
    for _ in range(40):
        mid = (lo + hi) / 2
        if lum(tuple(v * mid for v in c)) < target:
            lo = mid
        else:
            hi = mid
    return tuple(min(1.0, v * hi) for v in c)


if __name__ == "__main__":
    main()
