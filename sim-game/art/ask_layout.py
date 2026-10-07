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

WHEN IT FAILS IT HAS TO SAY WHY, AND IT USED TO GET THIS WRONG TWO WAYS
(ASSA-268). Both were found the expensive way: a stale binding cost an hour of
the studio Mac and two wrong causes reported in writing.

  1. IT KNEW "BINDING MISSING" AND NOT "BINDING STALE". A `libsim_godot` that
     is PRESENT but older than the GDScript calling it is the likeliest failure
     in a working checkout -- `sim-godot` gains methods on main while a local
     build sits still -- and it has its own signature, a method the registered
     class does not have:
         Parse Error: Static function "x()" not found in base
                      "GDScriptNativeClass"
     On the recorded blob in `fixtures/stale_binding.txt`: "not declared" 0,
     "gdextension" 0, "libsim_godot" 0. Neither old test matched, so the reader
     got no cause at all. "Missing" and "stale" are different sentences to type.

  2. IT PRINTED THE END OF THE OUTPUT, AND A COMPILE FAILURE BEGINS AT THE TOP.
     Once a compile fails, `main.tscn` cannot instantiate and `_process` re-emits
     the same runtime errors every frame -- 97,110 times in the recorded case,
     874,015 lines. `blob[-1200:]` was therefore pure spin loop, naming whatever
     `_process` touched last and never the cause. The excerpt now leads with the
     FIRST distinct errors and collapses repetition to a count.

`check_ask_layout.py` reads both of those off recorded real output, because this
is prose and prose has no test until someone writes one.
"""
import json
import os
import re
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
    raise CannotCheck("the probe printed no LAYOUT_JSON.%s\n--- godot said ---\n%s"
                      % (diagnose(blob), excerpt(blob)))


# A method the GDScript asks for that the registered class does not have. This is what a
# binding one build behind looks like; `not declared` (an unknown CLASS) is the cache case.
_STALE = re.compile(r'(?:Static function|Function) "([^"]+)\(\)" not found in base '
                    r'"GDScriptNativeClass"')


def diagnose(blob):
    """The likely cause, in the reader's own next command, or "" if none is recognised.

    Order matters: STALE is tested before MISSING, because a stale binding's output can
    also mention the library by name and the fix to type is different.
    """
    stale = _STALE.search(blob)
    if stale:
        return ("\nTHE LIKELY CAUSE: the sim-godot binding is STALE -- present, but older\n"
                "than the GDScript calling it. `%s()` is registered by the Rust crate and\n"
                "this build of the library does not have it, so every script depending on\n"
                "it fails to compile. Run `make client-lib`.\n"
                "(A binding that is MISSING looks different: the engine names the library\n"
                "or the .gdextension. This one loaded fine and is simply behind main.)\n"
                % stale.group(1))
    if "not declared" in blob:
        return ("\nTHE LIKELY CAUSE: the class cache is missing, so the engine does not\n"
                "know `AssaySprites` yet. Run `godot --headless --import` TWICE in\n"
                "client/ -- twice, because the first run after `.godot/` is gone\n"
                "crashes on exit having already written a complete cache.\n")
    if "gdextension" in blob.lower() or "libsim_godot" in blob:
        return "\nTHE LIKELY CAUSE: the binding is missing. Run `make client-lib`.\n"
    return ""


def excerpt(blob, budget=1600):
    """The FIRST distinct error lines, with repetition collapsed to a count.

    Not the tail. A compile failure announces itself in the first few lines and then
    repeats a consequence forever, so the end of the output is the one part guaranteed
    not to contain the cause. Blank lines and pure backtrace indentation are dropped;
    everything else keeps its original order and its first-seen wording.
    """
    lines = blob.splitlines()
    seen, order, counts = set(), [], {}
    for raw in lines:
        line = raw.rstrip()
        if not line.strip():
            continue
        counts[line] = counts.get(line, 0) + 1
        if line not in seen:
            seen.add(line)
            order.append(line)
    out, used = [], 0
    for line in order:
        tail = "   (x%d)" % counts[line] if counts[line] > 1 else ""
        piece = line + tail
        if used + len(piece) + 1 > budget:
            out.append("... %d more distinct line(s) suppressed" % (len(order) - len(out)))
            break
        out.append(piece)
        used += len(piece) + 1
    hidden = len(lines) - len(order)
    if hidden > 0:
        out.append("(%d repeated line(s) collapsed; %d distinct)" % (hidden, len(order)))
    return "\n".join(out)


def kind_of(entry):
    """The kind as the stack line says it, which is the word the player reads on that row.

    Read off the row the engine laid out, not off a list of kinds written down somewhere: if
    the client ever stops drawing a kind, this follows it instead of asserting a roster.
    """
    return entry["line"].split("x ")[-1].split("\u00d7 ")[-1].rsplit(" (", 1)[0].split()[-1]
