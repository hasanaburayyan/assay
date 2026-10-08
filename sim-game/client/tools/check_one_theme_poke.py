#!/usr/bin/env python3
"""THE SUITE POKES A CONTROL IN EXACTLY ONE PLACE (ASSA-312).

    python3 client/tools/check_one_theme_poke.py

WHY THIS EXISTS, STATED AS THE FAILURE IT CAME FROM. A `Control` that gets its theme from the
PROJECT theme keeps resolving the plain type's entries -- `Label`, `Button` -- and ignores its own
`theme_type_variation` until it receives `NOTIFICATION_THEME_CHANGED`, which running `_process`
frames does not deliver (ASSA-246). The shipped window is fine; only headless reads are wrong, and
headless reads are this suite.

ASSA-267 is why this is a check and not a convention. `test_tab_strip.gd` read a colour with no
type argument, and its own comment said why that was honest: *an override is consulted FIRST and
bypasses the type chain entirely.* That was true, and it was the ONLY thing propping up the read.
ASSA-267 moved the rule into the theme and removed the override, and **12 assertions went red
against a theme that was already correct**. Nothing had broken. The prop went away and nothing said
so, which no amount of remembering catches on the wake-up somebody is tired.

TWO ARMS, AND THE SECOND IS THE ONE THAT WOULD HAVE CAUGHT ASSA-267 EARLY:

1. The poke appears in `tests/theme_poke.gd` and nowhere else under `tests/`.
2. `tests/theme_poke.gd` still contains one, so "zero pokes anywhere" cannot pass this.

WHAT THIS DOES NOT CHECK, SAID OUT LOUD RATHER THAN IMPLIED. It does not find a theme READ that
skips the helper -- `get_theme_color`, `get_theme_font_size` and friends are called legitimately
inside the helper and inside the client's own scripts, and a grep that tried to tell a test's read
from a client's would be the "satisfied by a line other than the one it is about" mistake I have
shipped often enough to write down. So a new test file CAN still read a theme value raw. What this
guarantees is narrower and real: **nobody hand-rolls the poke again**, which is how the suite ended
up with two sites. The read-side gap belongs to whoever next needs it, with a measurement attached.

NOT NAMED AFTER `art/check_*.py` BY ACCIDENT: that family has ONE class -- every check should run --
and `art/check_ci_runs_every_check.py` enforces it with a set difference, regexing bare
`check_*.py` filenames out of build.yml and resolving them against `art/`. ASSA-282 hit the
collision when a `check_` script landed in `client/tools/`, and scoped that resolution to
`art/`-paths, so this name is safe here. Stdlib only, no Godot, milliseconds.
"""
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent.parent
TESTS = HERE / "tests"
HELPER = "theme_poke.gd"

#: The call itself. Written to match the ARGUMENT and not just the method, because `notification()`
#: is an ordinary Godot call a test may legitimately make for something else entirely.
POKE = re.compile(r"notification\s*\(\s*Control\.NOTIFICATION_THEME_CHANGED\s*\)")

#: A `##`/`#` comment line. The poke is DISCUSSED in several docstrings -- including this file's
#: subject matter -- and a check that counts prose is the mistake it exists to prevent. Stripping
#: comments is the same lesson ASSA-282 learned when `window_shot.gd` read as gated off a comment
#: saying why nothing ran it.
COMMENT = re.compile(r"^\s*#")


def pokes_in(path):
    """Line numbers of real poke calls in `path`, comments stripped."""
    found = []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if COMMENT.match(line):
            continue
        if POKE.search(line):
            found.append(n)
    return found


def main():
    if not TESTS.is_dir():
        # A GLOB MATCHING NOTHING MEANS THIS SCRIPT IS LOOKING IN THE WRONG PLACE, not that the
        # tree is clean. Exit 2: no verdict, never a pass.
        print("NO VERDICT: %s is not a directory, so nothing was checked" % TESTS)
        return 2
    scripts = sorted(TESTS.glob("*.gd"))
    if not scripts:
        print("NO VERDICT: no .gd files under %s, so nothing was checked" % TESTS)
        return 2

    strays = {}
    helper_count = 0
    for path in scripts:
        found = pokes_in(path)
        if path.name == HELPER:
            helper_count = len(found)
        elif found:
            strays[path.name] = found

    if strays:
        print("FAIL  the theme poke is hand-rolled outside %s, so the suite has more than one "
              "place to forget:" % HELPER)
        for name in sorted(strays):
            print("        %-28s line(s) %s" % (name, ", ".join(str(n) for n in strays[name])))
        print("      Use `const Poke := preload(\"res://tests/%s\")` and call `Poke.poke(control)`,"
              % HELPER)
        print("      or `Poke.drawn_color(label)` / `Poke.drawn_font_size(label)` to read through it.")
        print("      WHY: ASSA-267 removed the one override propping up a raw read in")
        print("      test_tab_strip.gd and 12 assertions went red on a theme that was CORRECT.")
        return 1

    if helper_count != 1:
        # THE ARM THAT STOPS "ZERO POKES" FROM PASSING. A green that can be earned by deleting the
        # thing under test is not a check, and ASSA-144's ruling is that a state green for free is
        # a hole rather than a state.
        print("FAIL  %s holds %d poke(s), want exactly 1. Deleting the poke must not satisfy this "
              "check -- the whole point is that one place HAS it." % (HELPER, helper_count))
        return 1

    print("VERDICT: PASS (exit 0). The theme poke lives once, in tests/%s, and %d test script(s) "
          "carry none." % (HELPER, len(scripts) - 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
