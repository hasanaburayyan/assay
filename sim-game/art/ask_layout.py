"""ASK THE ENGINE WHAT IT LAID OUT, in one place.

    from ask_layout import CannotCheck, ask_the_engine
    rows = ask_the_engine("why this check needs the engine, in its own words")

Three `check_*.py` now need the pack row's real layout -- scale (ASSA-65), plate
(ASSA-71) and kind separation (ASSA-111) -- and the first two already held
character-for-character copies of this function. The third copy is what made it
worth moving: `pack_icon_draw.py`'s docstring says why, for pixels, and it is
the same argument for process. A copy of a rule is a copy, and copies rot.

WHAT IT DOES AND DOES NOT DECIDE. It runs `pack_icon_layout.gd` under headless
Godot, which instantiates the real `main.tscn` and prints what the engine
actually laid out. Deliberately not "read the two properties `main.gd` sets and
check they are the two values `main.gd` sets" -- that passes by construction and
survives Godot changing its layout rules. Nothing here judges anything; each
check reads the rows and forms its own verdict.

NO GODOT IS NOT A PASS. Every failure path raises `CannotCheck`, which callers
turn into EXIT 2 -- NO VERDICT. A check about what the engine drew, run without
the engine, must never be able to look green. The reason the engine is needed
differs per check, so the caller passes its own sentence rather than inheriting
a generic one.
"""
import json
import os
import subprocess

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
CLIENT = os.path.join(ROOT, "client")
PROBE = os.path.join(ART, "pack_icon_layout.gd")
GODOT = os.environ.get("GODOT", "/Applications/Godot_mono.app/Contents/MacOS/Godot")

# Bounded, because an unbounded wait is not a check -- it is a CI job that burns its
# limit and reports nothing.
TIMEOUT = int(os.environ.get("ICON_GODOT_TIMEOUT", "300"))


class CannotCheck(Exception):
    """No verdict is available. Never allowed to look like a pass."""


def ask_the_engine(because):
    """Run the layout probe and return the whole answer. `because` is the caller's reason."""
    if not os.path.exists(GODOT):
        raise CannotCheck(
            "no Godot at %r. Set GODOT=<path>.\nDeliberately not a pass: %s" % (GODOT, because))
    if not os.path.exists(PROBE):
        raise CannotCheck("no layout probe at %s" % PROBE)
    try:
        p = subprocess.run(
            [GODOT, "--headless", "--path", CLIENT, "--script", PROBE],
            capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        raise CannotCheck(
            "Godot did not finish in %ds. Another headless Godot may be sitting on\n"
            "%s (check `pgrep -f Godot`), or an import is mid-flight. Raise it with\n"
            "ICON_GODOT_TIMEOUT=<seconds>." % (TIMEOUT, os.path.relpath(CLIENT, ROOT)))
    for line in p.stdout.splitlines():
        if line.startswith("LAYOUT_JSON "):
            return json.loads(line[len("LAYOUT_JSON "):])
    blob = p.stdout + p.stderr
    why = ""
    if "not declared" in blob:
        why = ("\nTHE LIKELY CAUSE: the class cache is missing, so the engine does not\n"
               "know `AssaySprites` yet. Run `godot --headless --import` TWICE in\n"
               "client/ -- twice, because the first run after `.godot/` is gone\n"
               "crashes on exit having already written a complete cache.\n")
    elif "gdextension" in blob.lower() or "libsim_godot" in blob:
        why = "\nTHE LIKELY CAUSE: the binding is missing. Run `make client-lib`.\n"
    raise CannotCheck("the probe printed no LAYOUT_JSON.%s\n--- godot said ---\n%s"
                      % (why, blob[-1200:]))


def kind_of(entry):
    """The kind as the stack line says it, which is the word the player reads on that row.

    Read off the row the engine laid out, not off a list of kinds written down somewhere: if
    the client ever stops drawing a kind, this follows it instead of asserting a roster.
    """
    return entry["line"].split("x ")[-1].split("\u00d7 ")[-1].rsplit(" (", 1)[0].split()[-1]
