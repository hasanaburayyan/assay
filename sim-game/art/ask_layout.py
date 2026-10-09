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


def ask_the_engine(because, probe=None):
    """Run a layout probe and return the whole answer. `because` is the caller's reason.

    `probe` names which one, defaulting to the pack's. ASSA-306 added a second: the crafting
    menu's rows need their own tab opened and the real loop played, which is a different run
    and not a key in the pack probe's JSON -- but every failure path above is the same, and
    the whole argument of this module is that a copy of a rule is a copy.
    """
    if not os.path.exists(GODOT):
        raise CannotCheck(
            "no Godot at %r. Set GODOT=<path>.\nDeliberately not a pass: %s" % (GODOT, because))
    probe = probe or PROBE
    if not os.path.exists(probe):
        raise CannotCheck("no layout probe at %s" % probe)
    try:
        p = subprocess.run(
            [GODOT, "--headless", "--path", CLIENT, "--script", probe],
            capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        raise CannotCheck(
            "Godot did not finish in %ds. Another headless Godot may be sitting on\n"
            "%s (check `pgrep -f Godot`), or an import is mid-flight. Raise it with\n"
            "ICON_GODOT_TIMEOUT=<seconds>." % (TIMEOUT, os.path.relpath(CLIENT, ROOT)))
    for line in p.stdout.splitlines():
        if line.startswith("LAYOUT_JSON "):
            return trust(json.loads(line[len("LAYOUT_JSON "):]), because)
    blob = p.stdout + p.stderr
    raise CannotCheck("the probe printed no LAYOUT_JSON.%s\n--- godot said ---\n%s"
                      % (diagnose(blob), excerpt(blob)))


def trust(answer, because):
    """THE PROBE'S OWN SELF-REPORT, REFUSED IN ONE PLACE FOR EVERY CHECK THAT READS IT.

    ASSA-319. A probe can answer perfectly about a layout nobody will ever see, and for a
    year this one did: the pack list has been a TAB since ASSA-264 and `mineralogy` is the
    tab that opens, so `_carrying` was never visible, and an invisible container is never
    laid out -- what its children keep is their own MINIMUM size. For a pack row that
    happens to be the real size, so six checks scored it right by luck. Same shape on the
    make list, whose sentence is `EXPAND_FILL`: five rows 95 px wide and 837 to 1361 px
    tall, scored green over all of it. The window was the same story -- `--script` leaves
    the root viewport at 64x64 unless a probe sets it every frame.

    SO THE REFUSAL LIVES HERE AND NOT IN THE CHECKS, for this module's own reason: a copy
    of a rule is a copy, and this one would be seven copies. A check that reads these rows
    is asking what the engine DREW, and neither a collapsed container nor a 64 px window
    can answer that -- so it is `CannotCheck`, which every caller turns into EXIT 2, never
    a pass and never a red.

    IT ONLY JUDGES WHAT THE PROBE VOLUNTEERS. Two probes answer through here (the pack's
    and the crafting menu's), their JSON has different shapes, and a key that is absent is
    not a failure: an older probe that reports neither state is exactly as trusted as it
    was before, and gets no false confidence either.

    **AND IT JUDGES THE TAB, NOT `is_visible_in_tree`, WHICH I FOUND OUT BY MEASURING.**
    The obvious gate is the pack container's visibility, and on the pack probe it is FALSE
    even when the layout is perfect: pressing the tab moved every row from its minimum
    (156-175 px wide) to its laid-out 300, and the flag stayed false, because that probe
    never joins a world and the screen the column hangs under is not on display. Keyed on
    it, this function would have refused all seven checks that read the probe while they
    were measuring the right thing. `pack_box` is reported beside the rows for a reader who
    wants to tell a width from a minimum.
    """
    if answer.get("pack_tab_selected") is False:
        raise CannotCheck(
            "the probe measured the pack list without its TAB open, so every rect it reported\n"
            "is a `custom_minimum_size` and not a drawn size -- an invisible container is\n"
            "never laid out. Press it through `AssayTabStrip.select` before measuring.\n"
            "Deliberately not a pass: %s" % because)
    got, want = answer.get("viewport"), answer.get("viewport_declared")
    if got and want and list(got) != list(want):
        raise CannotCheck(
            "the probe measured a %sx%s window; the project declares %sx%s. Under `--script`\n"
            "the engine shrinks the root viewport on frame one, so `root.size` has to be set\n"
            "every frame, not once.\nDeliberately not a pass: %s"
            % (got[0], got[1], want[0], want[1], because))
    return answer


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
