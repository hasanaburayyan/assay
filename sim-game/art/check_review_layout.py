#!/usr/bin/env python3
"""IS A COMMITTED REVIEW SHEET STILL A PICTURE OF THE CLIENT IT DREW? (ASSA-151)

    GODOT=<path> python3 art/check_review_layout.py

THE HALF `check_review_sources.py` CANNOT SEE. That check digests the shipped ART a sheet
composited, which is the whole answer for the six sheets that are pictures of sprites. Two are
pictures of a CLIENT PANEL: `pack_rows.png` and `pack_icons.png` are drawn from
`pack_icon_layout.gd`'s answer -- row heights, icon scales, verbs, plate colours, panel width --
and not one of those is a file, so moving any of them left both sheets reading CURRENT.

NOT HYPOTHETICAL, AND NOT BROKEN WHEN IT WAS FOUND. ASSA-121 moved every pack row to scale 0.5
and both sheets were current, because the person who moved it remembered to redraw them. Maren's
ruling 3 on ASSA-144: *a rule that depends on remembering is a rule that fails on the wake-up
somebody is tired.* This is that rule, mechanised.

HOW IT ASKS. `ask_layout.ask_the_engine` runs the real probe against the real `main.tscn` under
headless Godot -- the same call six other checks make -- and the answer is canonicalised and
digested exactly as the generator did it (`review_layout.canonical`). Equal digests mean the
sheet was drawn from the layout the client has today. Deliberately NOT a comparison of the two
JSON files: the generator is handed a `/tmp` file out of a pipe, so raw bytes would compare
pipelines rather than layouts.

THREE STATES.
  CURRENT    the sheet's layout digest is the engine's answer today.
  STALE      it is not. The client's panel has moved since the sheet was drawn: redraw it.
  NO LAYOUT  the sheet carries no layout stamp. Not a failure BY ITSELF -- six sheets are
             pictures of sprites and have no layout to go stale against -- but see the
             anti-vacuity check below, which is what stops that from being a hole.

ANTI-VACUITY, because "no layout moved" is trivially true of a repo where nothing is stamped.
  1. At least one sheet must carry a layout stamp. A bad merge that dropped the stamping would
     otherwise leave this check green with nothing to check.
  2. EVERY GENERATOR THAT READS A LAYOUT MUST STAMP ONE. Measured off the generator, not off an
     allowlist: a script that mentions `review_layout` must produce a sheet that carries the
     stamp. That is the forward case -- a new panel sheet landing unstamped is NO VERDICT here
     rather than a quiet pass -- and it is the same shape as `composites_no_art`'s measured
     exemption in the sources check.

NO GODOT IS NOT A PASS. Every failure path raises `CannotCheck` -> EXIT 2, NO VERDICT, which
fails the job. A check about what the engine laid out, run without the engine, must never be
able to look green; `ask_layout` is built on that rule and this inherits it.

THE RED LEVER:

    REVIEW_LAYOUT_FAKE_MOVE=1 GODOT=<path> python3 art/check_review_layout.py   # must FAIL

It perturbs the ENGINE's answer the way a client change would, rather than lowering a bar, so
every sheet drawn from that probe must name itself. The honest version was run too: a real pack
row's scale changed in `main.gd` with the sheets left alone, red reproduced, then restored.

Exit codes, matching the other art checks: 0 green, 1 a sheet is stale, 2 NO VERDICT.
"""
import os
import sys

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
REVIEW = os.path.join(ROOT, "assets", "review")

sys.path.insert(0, ART)
import review_layout  # noqa: E402
from ask_layout import CannotCheck, ask_the_engine  # noqa: E402

#: Perturb the engine's answer as a client change would. See the docstring.
FAKE_MOVE = os.environ.get("REVIEW_LAYOUT_FAKE_MOVE")

#: THE SHEETS THAT ARE PICTURES OF A CLIENT PANEL, and therefore must carry a layout stamp
#: whatever their script happens to say today. The sources check holds the full nine; these two
#: are the ones whose subject is a layout.
#:
#: **IT IS A WRITTEN LIST AND THE MEASURED ONE BESIDE IT IS NOT ENOUGH, which a mutation taught
#: me rather than my reasoning.** I first derived this set only from the generators (a script
#: that imports `review_layout` draws a panel), which is the right shape for the FORWARD case:
#: a new panel sheet is held without anyone adding a row here. It is the wrong shape for the
#: BACKWARD one. Revert one generator to `json.load` and redraw its sheet, and the sheet has no
#: stamp, its script no longer claims to need one, and the check goes green over exactly the
#: regression it exists to catch. So the two sets are unioned: this one cannot be dropped out
#: of by editing a script, and the measured one covers what this one does not know about yet.
GENERATOR = {
    "pack_icons.png": "pack_icon_sheet.py",
    "pack_rows.png": "pack_row_sheet.py",
}

#: The only probe this check knows how to re-ask. A sheet naming any other is NO VERDICT, never
#: green: the day a second probe appears, `ask_layout` grows a parameter and this grows a row --
#: and until then a stamp this cannot reproduce must not be read as one that matched.
ASKABLE = {"pack_icon_layout.gd": lambda: ask_the_engine(
    "ASSA-151: a review sheet claims it was drawn from this layout, and only the engine can say "
    "whether that is still the layout the client has.")}

CURRENT, STALE, NONE = "CURRENT", "STALE", "NO LAYOUT"


def sheets():
    if not os.path.isdir(REVIEW):
        raise CannotCheck("no %s to check" % REVIEW)
    return [os.path.join(REVIEW, f) for f in sorted(os.listdir(REVIEW)) if f.endswith(".png")]


def generators_that_read_a_layout():
    """Which generators reach a layout at all, measured off the script rather than listed here.

    A script that imports `review_layout` is one whose sheet is a picture of a client panel, so
    its sheet must carry a stamp. A script that does not cannot have drawn one. The day somebody
    teaches a sprite sheet to draw a panel, the import appears and this starts holding it.
    """
    found = {}
    for sheet, script in GENERATOR.items():
        path = os.path.join(ART, script)
        if not os.path.exists(path):
            raise CannotCheck("%s draws %s and is not there" % (script, sheet))
        with open(path) as fh:
            if "review_layout" in fh.read():
                found[sheet] = script
    return found


def answer_now(probe):
    """The engine's layout today, digested the way the generator digested it."""
    if probe not in ASKABLE:
        raise CannotCheck(
            "a sheet names the probe %r, which this check cannot re-ask. A stamp that cannot be\n"
            "reproduced is NO VERDICT, not a pass: teach `ASKABLE` to ask it." % probe)
    answer = ASKABLE[probe]()
    if FAKE_MOVE:
        # THE CAUSE, REPRODUCED, NOT A BAR LOWERED: this is what a changed client looks like to
        # this check -- the same answer with one value moved -- so every sheet drawn from it
        # must go red and name itself.
        answer = {"__fake_move__": FAKE_MOVE, "real": answer}
    return review_layout.digest(answer)


def main():
    measured = generators_that_read_a_layout()
    if not measured:
        raise CannotCheck(
            "no generator reads a layout any more, so the stamping has been removed wholesale.\n"
            "That is the bug, not a reason to pass: see ASSA-151.")
    # BOTH SETS, and `GENERATOR` second so a sheet named there cannot be edited out of the
    # requirement by its own script. See `GENERATOR`'s comment for the mutation that proved it.
    must_stamp = dict(measured)
    must_stamp.update(GENERATOR)
    asked = {}
    stamped = 0
    worst = 0
    for sheet in sheets():
        name = os.path.basename(sheet)
        raw = review_layout.read_stamp(sheet)
        if raw is None:
            if name in must_stamp:
                raise CannotCheck(
                    "%s is drawn by %s, which reads a layout, and carries no `%s` stamp.\n"
                    "Redraw it; that is what writes the stamp. Green here would be a check\n"
                    "passing because the thing it checks stopped happening."
                    % (name, must_stamp[name], review_layout.KEY))
            print("%-10s %s" % (NONE, os.path.relpath(sheet, ROOT)))
            continue
        try:
            import json
            layouts = json.loads(raw)
            if not isinstance(layouts, dict) or not layouts:
                raise ValueError("not a non-empty object")
        except ValueError as why:
            raise CannotCheck("%s carries a `%s` stamp that is not readable (%s)"
                              % (name, review_layout.KEY, why))
        stamped += 1
        moved = []
        for probe in sorted(layouts):
            if probe not in asked:
                asked[probe] = answer_now(probe)
            if asked[probe] != layouts[probe]:
                moved.append("%s has moved: the sheet was drawn from %s, the client lays out\n"
                             "      %s today. Redraw it -- see %s's header for the command."
                             % (probe, layouts[probe], asked[probe],
                                GENERATOR.get(name, "its generator")))
        state = STALE if moved else CURRENT
        print("%-10s %s" % (state, os.path.relpath(sheet, ROOT)))
        for line in moved:
            print("    - %s" % line)
        if not moved:
            print("    - drawn from the layout the client has today: %s"
                  % ", ".join("%s %s" % (p, layouts[p]) for p in sorted(layouts)))
        worst = max(worst, 1 if moved else 0)
    if stamped == 0:
        raise CannotCheck(
            "not one committed sheet carries a `%s` stamp, so every sheet passed by default.\n"
            "That is the vacuous green this check exists to refuse." % review_layout.KEY)
    return worst


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CannotCheck as why:
        print("NO VERDICT  %s" % why)
        sys.exit(2)
