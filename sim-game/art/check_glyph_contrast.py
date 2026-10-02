#!/usr/bin/env python3
"""Is the letter on a map disc readable, and does the CLIENT pick the better one?
(ASSA-44, which is acceptance 4 of ASSA-39)

    art/check_glyph_contrast.py

RED ON MAIN TODAY, ON PURPOSE: 226 of 600 disc states are given the glyph with
LESS contrast than the other option would have had. That is ASSA-39, Limpet's
fix in `hud.gd`. This check needs no edit from me to go green when it lands.

WHY THIS FILE EXISTS AND `species_probe.py` WAS NOT ENOUGH
  The probe measures disc against disc and disc against map background. It had
  never once measured the glyph against the disc it sits on, so "the map is
  green" was green about two of the three things on the map. A letter at
  contrast ratio 2.22 survived two days of my checks.

THE TRAP I BUILT THIS TO AVOID, because it is the mistake I keep making
  The obvious implementation is: compute both contrast ratios in Python, pick
  the better, then assert that picking the better picks the better. That passes
  by construction. It measures nothing. It would stay green if `hud.gd`
  reverted to a luminance threshold tomorrow, and it is the same shape as my
  map-disc check certifying a disc the client never draws.

  So this does not reimplement the rule. It runs the CLIENT, headless, calls
  `AssayHud.deposit_color` and `AssayHud.glyph_color` for all 600 states, and
  asks what they actually returned. Python's only job is to score those answers
  against the real linearised WCAG ratio. If the engine cannot be run, this
  exits 2 and says so -- "could not check" is never allowed to look like a pass.

TWO DIFFERENT CLAIMS, AND ONLY ONE OF THEM IS MINE
  1. OPTIMALITY, which is the client's. At every species x purity, the glyph
     returned must be whichever of the two options has the higher true ratio.
     Maren's instrument of choice over a >= 3.0 floor, and she is right: any
     rule choosing between two fixed colours can do no better than
     max(dark, light), so this is always satisfiable, cannot rot when the tints
     move, and fails the moment anyone goes back to a threshold.
  2. READABILITY AT ALL, which is MINE, because the tints are mine. If a future
     tint made BOTH glyph options unreadable, no picker could rescue it. The bar
     is WCAG AA for normal text, 4.5 -- not large text's 3.0, because
     `glyph_size` draws down to 10px and `hud.gd`'s own comment claiming the 3.0
     bar is wrong about its own glyph (Maren, ASSA-39).

     MEASURED MARGIN: 0.0152. The worst state in the table is #FF80BF at purity
     24, which clears 4.5 by one part in 300. That is tight and I am not hiding
     it: a tint change that drops this below 4.5 is a DESIGN conversation for
     Maren about the tint, not a number to raise in this file.

WHAT TURNED OUT NOT TO BE TRUE, so the lever is not the one I planned
  ASSA-39 found the worst RATIO sits mid-range (purple 52, blue 65), so I
  assumed a sparse end-sampled check would pass while the defect existed, and
  wrote that down before measuring it. Wrong: purity 1 is suboptimal for three
  species and purity 100 for two, so sampling the ends catches this fine. What
  does hide it is sampling one SPECIES: #FFFF33 is 0 of 100 suboptimal, the one
  tint the broken threshold happens to get right everywhere. Hence the lever
  below is per-species, not per-purity.

LEVERS
  GLYPH_FAKE_THRESHOLD=1   ignore the engine's answers and replicate the old
                           `get_luminance() > 0.221` rule -> MUST FAIL. This is
                           the regression lever and it keeps working after the
                           fix lands.
  GLYPH_ONE_SPECIES=<0-5>  grade only that species. With 3 (#FFFF33) it PASSES
                           optimality while 226 states are broken. A lever that
                           makes a check pass is worth having explicitly: it is
                           what a narrowed sweep would have reported.
  GLYPH_FAKE_LINEAR=1      make linearisation the identity, i.e. a dead
                           transform. My scoring would then share the client's
                           bug and call the defect optimal. The self-test must
                           catch it before any state is graded.

Needs Godot and the gdextension built (`make client-lib`), because opening the
project aborts without the library the `.gdextension` names.
"""
import os
import re
import subprocess
import sys
import tempfile

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
CLIENT = os.path.join(ROOT, "client")
GODOT = os.environ.get("GODOT", "/Applications/Godot_mono.app/Contents/MacOS/Godot")

FAKE_THRESHOLD = os.environ.get("GLYPH_FAKE_THRESHOLD") == "1"
FAKE_LINEAR = os.environ.get("GLYPH_FAKE_LINEAR") == "1"
ONE_SPECIES = os.environ.get("GLYPH_ONE_SPECIES")

# WCAG AA for normal text. A standard, not a number I chose; see the docstring.
AA_NORMAL = 4.5
# What large text would have to make. Recorded as a fact for comparison, NOT the
# gate: `glyph_size` draws a 10px letter, which is not large text.
AA_LARGE = 3.0

DUMP = r'''extends SceneTree
# Asks the CLIENT for its real answers. No rule is reimplemented here: the whole
# point is to learn what AssayHud returns, not what it ought to return.
func _init() -> void:
	for s: int in range(6):
		for p: int in range(1, 101):
			var d: Color = AssayHud.deposit_color(s, p)
			var g: Color = AssayHud.glyph_color(d)
			print("ROW %d %d %.10f %.10f %.10f %.10f %.10f %.10f"
				% [s, p, d.r, d.g, d.b, g.r, g.g, g.b])
	print("CONST DARK %.10f %.10f %.10f"
		% [AssayHud.GLYPH_DARK.r, AssayHud.GLYPH_DARK.g, AssayHud.GLYPH_DARK.b])
	print("CONST LIGHT %.10f %.10f %.10f"
		% [AssayHud.GLYPH_LIGHT.r, AssayHud.GLYPH_LIGHT.g, AssayHud.GLYPH_LIGHT.b])
	quit(0)
'''


def linearise(c):
    """sRGB -> linear light. The step `Color.get_luminance()` does NOT do, which
    is the whole defect: 0.221 is a crossover in the encoded space and means
    nothing about what a reader can see."""
    if FAKE_LINEAR:
        return c
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = (linearise(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def self_test():
    """Before grading anything, prove the instrument is alive.

    Both facts come from the sRGB and WCAG definitions, not from this project,
    so they cannot drift with the art: mid-grey linearises to 0.2140, and pure
    white against pure black is exactly 21:1. A dead linearisation fails the
    first; a broken ratio fails the second."""
    mid = linearise(0.5)
    white_black = ratio((1.0, 1.0, 1.0), (0.0, 0.0, 0.0))
    print("self-test: linearise(0.5) = %.6f (sRGB says 0.214041)" % mid)
    print("self-test: white against black = %.4f (WCAG says 21.0)" % white_black)
    if abs(mid - 0.214041) > 1e-5 or abs(white_black - 21.0) > 1e-6:
        print("\n  FAIL: the instrument is wrong before it has graded a single\n"
              "  state. A linearisation that is the identity would make this\n"
              "  check share the client's bug and call the defect optimal, which\n"
              "  is exactly what GLYPH_FAKE_LINEAR=1 reproduces.")
        return False
    return True


def ask_the_engine():
    """Run the client headless and collect what it really returns."""
    if not os.path.exists(GODOT):
        raise SystemExit(
            "CANNOT CHECK (exit 2): no Godot at %r. Set GODOT=<path>.\n"
            "This is deliberately not a pass: the one thing this file exists to\n"
            "avoid is a verdict about a rule nobody asked the engine for." % GODOT)
    with tempfile.NamedTemporaryFile("w", suffix=".gd", delete=False) as f:
        f.write(DUMP)
        script = f.name
    try:
        p = subprocess.run([GODOT, "--headless", "--path", CLIENT, "--script", script],
                           capture_output=True, text=True)
    finally:
        os.unlink(script)
    rows, consts = [], {}
    for line in p.stdout.splitlines():
        if line.startswith("ROW "):
            f = line.split()[1:]
            rows.append((int(f[0]), int(f[1]),
                         tuple(float(x) for x in f[2:5]),
                         tuple(float(x) for x in f[5:8])))
        elif line.startswith("CONST "):
            f = line.split()
            consts[f[1]] = tuple(float(x) for x in f[2:5])
    if len(rows) != 600 or len(consts) != 2:
        raise SystemExit(
            "CANNOT CHECK (exit 2): expected 600 states and 2 constants from the\n"
            "engine, got %d and %d. Build the binding first (`make client-lib`):\n"
            "opening the project aborts without it.\n--- godot said ---\n%s"
            % (len(rows), len(consts), (p.stdout + p.stderr)[-1500:]))
    return rows, consts["DARK"], consts["LIGHT"]


def main():
    print(__doc__.splitlines()[0])
    print()
    if not self_test():
        return 1
    print()

    rows, dark, light = ask_the_engine()
    print("asked the engine: %d states, GLYPH_DARK=%s GLYPH_LIGHT=%s"
          % (len(rows), dark, light))

    if FAKE_THRESHOLD:
        print("[RED LEVER] replicating the old `get_luminance() > 0.221` rule and\n"
              "            ignoring what the engine returned; MUST FAIL.")
        def srgb_luma(c):
            return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        rows = [(s, p, d, dark if srgb_luma(d) > 0.221 else light)
                for s, p, d, _ in rows]
    if ONE_SPECIES is not None:
        rows = [r for r in rows if r[0] == int(ONE_SPECIES)]
        print("[LEVER] grading only species %s: %d states. This is expected to\n"
              "        PASS optimality while the other species are broken -- it is\n"
              "        what a narrowed sweep would have told us." % (ONE_SPECIES, len(rows)))
    print()

    # 1. OPTIMALITY of the client's rule (Limpet's claim, asserted not assumed).
    suboptimal, per_species = [], {}
    worst_available = (float("inf"), None)
    for s, p, disc, glyph in rows:
        r_dark, r_light = ratio(disc, dark), ratio(disc, light)
        # Which one did the engine actually hand back? Compare to both constants
        # rather than guessing from brightness.
        picked = r_dark if glyph == dark else r_light if glyph == light else None
        if picked is None:
            print("  FAIL: species %d purity %d got glyph %s, which is neither\n"
                  "  GLYPH_DARK nor GLYPH_LIGHT." % (s, p, glyph))
            return 1
        best = max(r_dark, r_light)
        if best < worst_available[0]:
            worst_available = (best, (s, p))
        if picked < best - 1e-12:
            suboptimal.append((s, p, picked, best))
        cur = per_species.get(s)
        if cur is None or picked < cur[0]:
            per_species[s] = (picked, p)

    print("worst CURRENT ratio per species, as the client picks today:")
    for s in sorted(per_species):
        r, p = per_species[s]
        print("  species %d  %.2f at purity %3d%s"
              % (s, r, p, "" if r >= AA_LARGE else "   <- under large text's 3.0"))
    print()

    ok = True
    if suboptimal:
        ok = False
        worst = min(suboptimal, key=lambda t: t[2])
        print("  FAIL (optimality): %d of %d states are given the glyph with LESS\n"
              "  contrast than the other option would have had. Worst: species %d\n"
              "  purity %d got %.2f where %.2f was available.\n"
              "  This is ASSA-39 and the fix is in `hud.gd`'s `glyph_color`: pick by\n"
              "  the ratio itself, never by a threshold on `get_luminance()`, which\n"
              "  is the sRGB-encoded luminance and not a perceptual one."
              % (len(suboptimal), len(rows), worst[0], worst[1], worst[2], worst[3]))
    else:
        print("OPTIMALITY: all %d states get the better of the two glyph colours."
              % len(rows))
    print()

    # 2. READABILITY AT ALL, which is the tints' problem and therefore mine.
    wa, where = worst_available
    print("WORST AVAILABLE contrast max(dark, light) over %d states: %.4f\n"
          "  at species %d purity %d -- the ceiling of any possible picker."
          % (len(rows), wa, where[0], where[1]))
    print("  against WCAG AA normal text (%.1f): margin %+.4f" % (AA_NORMAL, wa - AA_NORMAL))
    print("  against large text (%.1f), recorded for comparison only: margin %+.4f"
          % (AA_LARGE, wa - AA_LARGE))
    if wa < AA_NORMAL:
        ok = False
        print("\n  FAIL (readability): the tint table no longer admits a glyph that\n"
              "  meets AA for normal text at every state, and NO picker can fix\n"
              "  that -- %.4f is the best any rule could do. The glyph is the\n"
              "  accessibility read, so this is a design conversation about the\n"
              "  TINT (Maren's call), not a bound to raise in this file." % wa)

    print("\nVERDICT: %s" % ("GREEN" if ok else "RED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
