#!/usr/bin/env python3
"""WHEN THE ENGINE PROBE FAILS, DOES THE HELPER NAME THE CAUSE? (ASSA-268)

    art/check_ask_layout.py

`ask_layout.ask_the_engine` is the one place three checks ask the engine what it laid out
(ASSA-111), and when the probe prints no `LAYOUT_JSON` it tries to tell the reader why. That
explanation is PROSE, and nothing has ever read it. It was wrong in two ways at once, both found
by losing an hour to them rather than by review:

  1. It knew "the binding is MISSING" and not "the binding is STALE" -- present, but older than
     the GDScript calling it, which is the likeliest failure in a working checkout because
     `sim-godot` gains methods on main while a local build sits still. On the recorded output
     below, every string the old code tested for appears ZERO times, so the reader was handed no
     cause at all.
  2. It printed `blob[-1200:]`. A compile failure announces itself in the first few lines and then
     `_process` re-emits a consequence every frame -- 97,110 times, 874,015 lines, in the recorded
     case. The end of that output is the one part guaranteed not to contain the cause.

WHY THIS READS A RECORDING AND NOT SENTENCES I WROTE. A check built from strings I invent only
proves I can match my own strings; it would have passed on the old code for the stale case, because
I would have written the fixture to say "gdextension". `fixtures/stale_binding.txt` is captured
from the real failing run (paths rewritten to <REPO>, lines repeated >50x kept once, nothing else
edited), and this file RE-EXPANDS the trailing block so the shape is faithful too -- otherwise
test 2 would pass on a 45-line input where the tail is perfectly informative.

NO GODOT NEEDED, stdlib only: `diagnose` and `excerpt` are pure string functions, which is why
they were split out of `ask_the_engine`. The one thing this cannot see is whether
`ask_the_engine` still CALLS them, so it checks that too, by reading its source.

EXIT CODES
  0 PASS       -- every recorded failure is named, and the cause survives the excerpt.
  1 FAIL       -- a failure is unnamed or its cause was truncated away.
  2 NO VERDICT -- the fixture or the module is missing. Never a pass.
"""
import os
import sys

ART = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ART)

FIXTURES = os.path.join(ART, "fixtures")


def load_fixture(name):
    path = os.path.join(FIXTURES, name)
    if not os.path.exists(path):
        raise SystemExit(2)
    lines = [ln for ln in open(path, encoding="utf-8").read().splitlines()
             if not ln.startswith("#")]
    return "\n".join(lines)


def as_it_really_was(blob, frames=4000):
    """Re-expand the recorded spin loop, so the excerpt is judged on the real shape.

    The capture keeps one copy of each repeated line. The live run repeated the last few
    runtime errors once per frame forever; this repeats the tail block `frames` times, which
    reproduces the only property that matters here -- that the END of the output is many
    thousands of lines away from the compile error that caused it.
    """
    lines = blob.splitlines()
    head, spin = lines[:-6], lines[-6:]
    return "\n".join(head + spin * frames)


def main():
    print(__doc__.splitlines()[0])
    try:
        import ask_layout
    except ImportError as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n  no ask_layout: %s" % why)
        return 2
    for fn in ("diagnose", "excerpt"):
        if not hasattr(ask_layout, fn):
            print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n"
                  "  ask_layout has no %s(); this check cannot judge what it cannot call." % fn)
            return 2

    try:
        stale = as_it_really_was(load_fixture("stale_binding.txt"))
    except SystemExit:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n"
              "  fixtures/stale_binding.txt is missing -- the recording IS the evidence here.")
        return 2

    bad = []

    # ---- 1. THE RECORDED REAL FAILURE IS NAMED, and named as STALE rather than missing.
    why = ask_layout.diagnose(stale)
    print("\n  recorded stale-binding run: %d lines after re-expansion" % len(stale.splitlines()))
    print("  the strings the OLD code tested for, counted on it:")
    for probe in ("not declared", "gdextension", "libsim_godot"):
        print("    %-16s %d" % (probe, stale.lower().count(probe.lower())))
    if not why.strip():
        bad.append("the recorded stale-binding failure gets NO cause at all. This is the exact\n"
                   "      state that cost an hour: 874,015 lines and not a word about why.")
    elif "STALE" not in why:
        bad.append("the recorded failure is diagnosed, but not as STALE: %r.\n"
                   "      'missing' and 'stale' are different commands to type." % why.strip()[:90])
    elif "make client-lib" not in why:
        bad.append("the stale diagnosis never names the command that fixes it.")
    if "dead_end_label" not in why:
        bad.append("the diagnosis does not name the method the engine could not find, so the\n"
                   "      reader cannot tell which build they are behind.")

    # ---- 2. THE CAUSE SURVIVES THE EXCERPT. This is the half a tail cannot do.
    ex = ask_layout.excerpt(stale)
    print("\n  excerpt is %d chars from %d lines" % (len(ex), len(stale.splitlines())))
    if "dead_end_label" not in ex:
        bad.append("the excerpt does not contain the line that explains the failure. The cause\n"
                   "      is in the first few lines of the output and must not be truncated away.")
    if "_refresh_join_band" in ex and "dead_end_label" not in ex:
        bad.append("the excerpt shows the spin loop and not the cause -- this is the tail bug.")
    if len(ex) > 4000:
        bad.append("the excerpt is %d chars; it is meant to be readable, not the whole log."
                   % len(ex))

    # ---- 3. THE OTHER TWO CAUSES STILL RESOLVE TO THEMSELVES, not swallowed by the new one.
    cache = ('SCRIPT ERROR: Parse Error: Identifier "AssaySimHost" not declared in the '
             'current scope.\n   at: GDScript::reload (<REPO>/art/pack_icon_layout.gd:41)')
    missing = ('ERROR: Can\'t open dynamic library: <REPO>/client/bin/libsim_godot.dylib\n'
               '   at: open_dynamic_library (platform/macos/os_macos.mm:220)')
    for name, blob, want in (("missing class cache", cache, "--headless --import"),
                             ("missing binding", missing, "the binding is missing")):
        got = ask_layout.diagnose(blob)
        ok = want in got
        print("  %-22s -> %s" % (name, "names it" if ok else "NOT NAMED"))
        if not ok:
            bad.append("a %s no longer resolves to its own answer (got %r)." % (name, got[:80]))
        if "STALE" in got:
            bad.append("a %s is being reported as a STALE binding. The new case has swallowed "
                       "an older one." % name)

    # ---- 4. ANTI-VACUITY: the helper must still USE these, or all of the above is theatre.
    src = open(os.path.join(ART, "ask_layout.py"), encoding="utf-8").read()
    body = src.split("def ask_the_engine", 1)[-1].split("\ndef ", 1)[0]
    for fn in ("diagnose(", "excerpt("):
        if fn not in body:
            bad.append("ask_the_engine does not call %s -- these functions could be perfect and "
                       "the reader would still see the old message." % fn.rstrip("("))

    if bad:
        print("\nVERDICT: FAIL (exit 1)")
        for line in bad:
            print("  - %s" % line)
        return 1
    print("\nVERDICT: PASS (exit 0). The recorded failure is named as a stale binding, the\n"
          "  cause survives the excerpt, the two older causes still answer for themselves,\n"
          "  and ask_the_engine still calls both.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
