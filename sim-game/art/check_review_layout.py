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

EVERY SHEET SAYS WHICH IT IS, AND SAYING NOTHING IS A FINDING (QA, CO-6). This printed
`NO LAYOUT` for seven of nine committed sheets and exited 0, so one class held both "a picture
of sprites, nothing to go stale against" and "a picture of a client panel that forgot to record
its layout" -- and when I went to declare the seven, TWO of them were the second thing:
`pack_icon_kinds.png` is drawn from the very probe this check can already re-ask, and
`design_rows.png` from a second one. A state nothing has to opt into is a state things fall into.

FIVE STATES.
  CURRENT       the sheet's layout digest is the engine's answer today.
  STALE         it is not. The client's panel has moved since it was drawn: redraw it. EXIT 1.
  ART ONLY      the sheet DECLARES, in its own stamp, that no engine layout is behind it, and
                says why. Checked against its generator: a script that reads a layout may not
                make this claim.
  NO STAMP YET  named in `UNDECLARABLE` with a reason, for the one sheet whose probe needs a
                live bench. Printed every run, not silent, and dead code once it is redrawn.
  UNDECLARED    no claim at all. EXIT 1 -- the check cannot tell which of the two it is, and
                that ambiguity is the bug CO-6 is about.

ANTI-VACUITY, because "no layout moved" is trivially true of a repo where nothing is stamped.
  1. At least one sheet must carry a layout stamp. A bad merge that dropped the stamping would
     otherwise leave this check green with nothing to check.
  2. EVERY GENERATOR THAT READS A LAYOUT MUST STAMP ONE. Measured off the generator, not off an
     allowlist: a script that mentions `review_layout` must produce a sheet that carries the
     stamp. That is the forward case -- a new panel sheet landing unstamped is NO VERDICT here
     rather than a quiet pass -- and it is the same shape as `composites_no_art`'s measured
     exemption in the sources check. **That claim was false until CO-6**: the scan iterated the
     two-sheet written list, so it could only ever re-measure what was already written down.
     See `generators_that_read_a_layout`.
  3. And the counts of all five states print on green as well as red, because a verdict that
     only says PASS cannot show a reader that sheets have moved out of the checked class.

NO GODOT IS NOT A PASS. Every failure path raises `CannotCheck` -> EXIT 2, NO VERDICT, which
fails the job. A check about what the engine laid out, run without the engine, must never be
able to look green; `ask_layout` is built on that rule and this inherits it.

THE RED LEVER:

    REVIEW_LAYOUT_FAKE_MOVE=1 GODOT=<path> python3 art/check_review_layout.py   # must FAIL

It perturbs the ENGINE's answer the way a client change would, rather than lowering a bar, so
every sheet drawn from that probe must name itself. The honest version was run too: a real pack
row's scale changed in `main.gd` with the sheets left alone, red reproduced, then restored.

THE SECOND RED LEVER, for the declaration rule (CO-6 box 3):

    REVIEW_LAYOUT_STRIP=<sheet.png> GODOT=<path> python3 art/check_review_layout.py  # must FAIL

It drops one sheet's declaration on a SCRATCH COPY of the review folder, so the committed sheet
is never touched, and the sheet must come back UNDECLARED. Stripping is the real cause -- a
sheet arriving without a claim -- rather than a bar lowered.

Exit codes, matching the other art checks: 0 green, 1 a sheet is stale or undeclared,
2 NO VERDICT.
"""
import os
import sys

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
REVIEW = os.path.join(ROOT, "assets", "review")

sys.path.insert(0, ART)
import review_layout  # noqa: E402
import design_row_dump  # noqa: E402
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
ASKABLE = {
    "pack_icon_layout.gd": lambda: ask_the_engine(
        "ASSA-151: a review sheet claims it was drawn from this layout, and only the engine can "
        "say whether that is still the layout the client has."),
    # THE SECOND PROBE, AND THE ROW THE COMMENT ABOVE PROMISED (ASSA-173). It costs three Godot
    # runs rather than one -- two offline demo runs for the bench's two verdicts, then the layout
    # probe over the merge -- so the whole chain lives in `design_row_dump` and both the generator
    # and this check call the one definition. Measured before it was wired: two independent full
    # chains digest identically (b988766c5d5bb8b0), so this is a comparison and not a flake, the
    # same thing `review_layout`'s header measured for the first probe.
    design_row_dump.PROBE: lambda: _ask_the_bench(),
}


def _ask_the_bench():
    """`design_row_layout.gd`'s answer today, in a scratch directory that does not survive."""
    import tempfile
    with tempfile.TemporaryDirectory(prefix="design-rows-") as scratch:
        return design_row_dump.layout_now(scratch)

#: SHEETS THAT CANNOT DECLARE THEMSELVES YET, NAMED OUT LOUD WITH THEIR REASON (CO-6).
#:
#: **EMPTY SINCE ASSA-173, WHICH IS WHAT IT WAS BUILT FOR.** Its only entry was `design_rows.png`,
#: and the exemption did its job in the way an exemption should: it stayed visible, printed its
#: reason on every run, and was deleted by the commit that removed the need for it rather than
#: surviving as a habit. The counts went `3 current, 5 art only, 1 no stamp yet` -> `4 current,
#: 5 art only`, and the `NO STAMP YET` class now never prints.
#:
#: **THE REASON PRINTED HERE WAS WRONG FOR THREE DAYS AND I WROTE IT** -- it said the probe needs a
#: LIVE RELAY with designs in it. That was the first of three wrong blockers on that item, none of
#: them the real one (the probe is fine headless; what was missing was a REPRODUCIBLE chain the
#: check could re-run, which is now `design_row_dump.py`). Kept as a dict rather than deleted
#: outright because the mechanism is sound and the next sheet in this position should land in a
#: named list with a reason, not in silence -- which is the whole finding of CO-6.
UNDECLARABLE = {}

# `ART_DECLARED` and not `ART`: `ART` is this module's path to the art folder, and naming
# a state the same thing made every generator "not there" -- a collision I shipped into my
# own first run of this change.
CURRENT, STALE, ART_DECLARED, UNDECLARED = "CURRENT", "STALE", "ART ONLY", "UNDECLARED"
EXEMPT = "NO STAMP YET"


#: Reproduce the UNDECLARED red by taking one sheet's declaration away. See the header.
STRIP = os.environ.get("REVIEW_LAYOUT_STRIP")


def scratch_without(name):
    """A COPY of the review folder with one sheet's layout claim removed, for the red lever.

    A copy, because a lever that edits a committed sheet is a lever that leaves the repo dirty
    when it fails. The chunk is dropped at the PNG level rather than by re-saving through PIL,
    so the scratch sheet's PIXELS are byte-identical to the committed one and the only thing
    that moved is the claim -- which is what makes this a reproduction of the cause ("a sheet
    arrived with no declaration") rather than a different picture.
    """
    import shutil
    import struct
    import tempfile
    scratch = tempfile.mkdtemp(prefix="review-layout-strip-")
    for f in sorted(os.listdir(REVIEW)):
        shutil.copy2(os.path.join(REVIEW, f), os.path.join(scratch, f))
    target = os.path.join(scratch, name)
    if not os.path.exists(target):
        raise CannotCheck("REVIEW_LAYOUT_STRIP names %s, which is not a committed sheet" % name)
    with open(target, "rb") as fh:
        blob = fh.read()
    out, at, dropped = blob[:8], 8, 0
    while at + 8 <= len(blob):
        (length,) = struct.unpack(">I", blob[at:at + 4])
        kind = blob[at + 4:at + 8]
        chunk = blob[at:at + 12 + length]
        keyword = blob[at + 8:at + 8 + length].partition(b"\x00")[0].decode("latin-1")
        if kind == b"tEXt" and keyword == review_layout.KEY:
            dropped += 1
        else:
            out += chunk
        at += 12 + length
        if kind == b"IEND":
            break
    if dropped != 1:
        raise CannotCheck(
            "%s carries %d `%s` chunks, so stripping one proves nothing about the check.\n"
            "The lever must take away a claim that was really there." % (name, dropped,
                                                                        review_layout.KEY))
    with open(target, "wb") as fh:
        fh.write(out)
    print("RED LEVER: %s copied to %s with its `%s` claim removed (pixels untouched).\n"
          % (name, scratch, review_layout.KEY))
    return scratch


def sheets():
    folder = scratch_without(STRIP) if STRIP else REVIEW
    if not os.path.isdir(folder):
        raise CannotCheck("no %s to check" % folder)
    return [os.path.join(folder, f) for f in sorted(os.listdir(folder)) if f.endswith(".png")]


def generators_that_read_a_layout():
    """Which generators reach a layout at all, measured off the script rather than listed here.

    A script that calls `review_layout.load` or `.remember` is one whose sheet is a picture of a
    client panel, so its sheet must carry a stamp. A script that does not cannot have drawn one.
    The day somebody teaches a sprite sheet to draw a panel, the call appears and this starts
    holding it.

    **IT MEASURED THE IMPORT UNTIL CO-6, WHICH THE SAME COMMIT MADE WRONG.** Declaring a sheet
    art-only is also a `review_layout` call, so five sprite sheets gained the import and would
    have been required to stamp a layout they had just said they do not have -- each one failing
    as "declares art-only, but its generator reads a layout". The two calls that take an ANSWER
    are the measurement; importing the module is not.

    **IT SCANNED ONLY THE TWO SHEETS IN `GENERATOR`, SO THAT LAST SENTENCE WAS FALSE FROM THE
    DAY I WROTE IT** (found while fixing CO-6, and it is mine). Iterating `GENERATOR` makes the
    measured set a SUBSET of the written list, which is the one shape that cannot discover a
    third sheet -- the entire forward case the docstring claimed. Two sheets had already walked
    through the gap: `pack_icon_kinds.png` is drawn from the very probe `ASKABLE` can re-ask,
    and `design_rows.png` from a second one, and both sat in the silent `NO LAYOUT` class.
    It now reads the FULL sheet->script map from the sibling check, which is the only list in
    the repo that a new sheet must already be added to (`check_review_sources` raises on an
    unmapped sheet), so a new panel sheet cannot arrive unnoticed by both checks at once.
    """
    found = {}
    for sheet, script in sorted(all_generators().items()):
        path = os.path.join(ART, script)
        if not os.path.exists(path):
            raise CannotCheck("%s draws %s and is not there" % (script, sheet))
        with open(path) as fh:
            src = fh.read()
        if any(call in src for call in ("review_layout.load(", "review_layout.remember(")):
            found[sheet] = script
    return found


def all_generators():
    """Every committed sheet and the script that draws it, from the sibling check's one map.

    Imported rather than copied: two lists of the same nine sheets is how one of them goes
    stale, and that map is already load-bearing -- `check_review_sources.py` refuses a sheet it
    does not name, so it is the list a new sheet cannot skip.
    """
    import check_review_sources
    return dict(check_review_sources.GENERATOR)


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
    counts = {CURRENT: 0, STALE: 0, ART_DECLARED: 0, EXEMPT: 0, UNDECLARED: 0}
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
            # NO DECLARATION IS A FINDING ABOUT THE SHEET, NOT A SHRUG (CO-6). This printed
            # `NO LAYOUT` and passed, so the class held both "a picture of sprites" and "a
            # picture of a panel that forgot to say so" -- and both were really in it.
            state = EXEMPT if name in UNDECLARABLE else UNDECLARED
            counts[state] += 1
            print("%-10s %s" % (state, os.path.relpath(sheet, ROOT)))
            if state is EXEMPT:
                print("    - named in UNDECLARABLE: %s" % UNDECLARABLE[name])
            else:
                print("    - carries no `%s` claim at all, so this check cannot tell a picture\n"
                      "      of art from a picture of a panel that forgot to record its layout.\n"
                      "      Its generator (%s) must call either `review_layout.load(..., probe=)`\n"
                      "      or `review_layout.art_only(<why>)`, and the sheet be redrawn."
                      % (review_layout.KEY, all_generators().get(name, "unknown")))
                worst = max(worst, 1)
            continue
        try:
            import json
            kind, body = review_layout.classify(json.loads(raw))
        except ValueError as why:
            raise CannotCheck("%s carries a `%s` stamp that is not readable (%s)"
                              % (name, review_layout.KEY, why))
        if kind == review_layout.ART_ONLY:
            # A DECLARATION IS STILL CHECKED AGAINST THE GENERATOR. A sheet whose script reads a
            # layout cannot declare itself art, or the declaration would be the new silent pass.
            if name in must_stamp:
                raise CannotCheck(
                    "%s declares itself `%s`, but %s reads a layout. One of the two is wrong and\n"
                    "this check may not choose: a sheet drawn from a layout must record it."
                    % (name, review_layout.ART_ONLY, must_stamp[name]))
            counts[ART_DECLARED] += 1
            print("%-10s %s" % (ART_DECLARED, os.path.relpath(sheet, ROOT)))
            print("    - declares no client layout: %s" % body)
            continue
        layouts = body
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
        counts[state] += 1
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

    # THE TALLY ON GREEN AS WELL AS RED (CO-6 box 2). A verdict that only says PASS cannot tell
    # a reader that six sheets moved out of the checked class and into an exempt one, which is
    # how this check went quiet in the first place. The numbers are the thing that would have
    # shown it.
    print("\n%d sheets: %s" % (sum(counts.values()),
                               ", ".join("%d %s" % (counts[k], k.lower())
                                         for k in (CURRENT, STALE, ART_DECLARED, EXEMPT, UNDECLARED)
                                         if counts[k])))
    if worst == 0:
        print("VERDICT: PASS (exit 0). Every sheet says which it is, and every one drawn from a\n"
              "  layout was drawn from the layout the client has today.")
        if counts[EXEMPT]:
            print("  %d sheet(s) are named in UNDECLARABLE above and say nothing either way."
                  % counts[EXEMPT])
    return worst


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CannotCheck as why:
        print("NO VERDICT  %s" % why)
        sys.exit(2)
