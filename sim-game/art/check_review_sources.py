#!/usr/bin/env python3
"""DOES EVERY COMMITTED REVIEW SHEET STILL MATCH THE SHIPPED ART IT DREW? (ASSA-144)

    python3 art/check_review_sources.py

No Godot, no Pillow, no network: it reads nine PNGs' text chunks and digests the files they
name.

WHAT WENT WRONG. `assets/review/` holds nine tracked PNGs and `sim-game/CLAUDE.md` tells
everyone to judge the art off one of them. The pack sheet's slot plate was `#889868` while the
shipped ground's median had moved to `#879A66`: the sheet predated the ground re-render, and
nothing in the repo could say so. A review sheet is the one artefact whose job is to be
BELIEVED, so a stale one is worse than none -- and Maren's point on ASSA-144 is that it is not
only internal. The board judges a look from whatever picture is nearest, and that has already
been a review sheet rather than the game.

NOT A HASH OF THE SHEET'S OWN PIXELS, which is Cove's ruling and the reason this check exists
in this shape. Hashing the output goes red on every legitimate re-render, "and a check that
cries wolf is a check that gets regenerated blind". The generators stamp the identity of their
SOURCES instead (`review_sources.py`), so re-drawing a sheet from unchanged art is green and
moving the art under a sheet nobody re-drew is red.

FOUR STATES, AND THE MIDDLE TWO ARE WHY THIS IS NOT ONE LINE.
  CURRENT     every file the sheet recorded is byte-identical to the shipped art today.
  NO SOURCES  the sheet recorded an EMPTY list. **RED unless `composites_no_art` accepts it**,
              in which case it is reported as NO ART PATH below. It was green for free until
              ASSA-144 box 4, and the justification written here -- "a MEASURED empty rather
              than an assumed one: every generator records" -- rested on an invariant Cove
              broke by walking into it: a path that writes the stamp OUTSIDE `recording()`
              produces a present, well-formed, empty one. An empty stamp cannot tell "I
              composited nothing" from "the recorder was not running", so it may not pass on
              its own word; it passes only on the same measured key UNSTAMPED already needed.
  NO ART PATH the one narrow exemption, for a sheet that recorded NOTHING -- no stamp or an
              empty one -- whose generator cannot reach shipped art at all. `design_rows.png`
              only. Keyed to a measured property of the script rather than an allowlist, fails
              safe, and designed to become dead code -- see `composites_no_art`, which states
              the hole it leaves.
  UNSTAMPED   no chunk at all. RED, and deliberately not merged with NO SOURCES: a sheet that
              cannot say what it reviewed is the exact condition this item is about, and
              reading it as "composited nothing" would hand every pre-ASSA-144 sheet a clean
              bill. That is also why the stamping and this check had to land in one commit --
              on the commit before, all nine were UNSTAMPED and this check would have been red
              on a tree nobody had broken.

ONE HONEST LIMIT ON WHAT A RED MEANS. The stamp is per-FILE identity, so a sheet goes red when
a file it opened changes even if that change could not have altered THIS picture --
`manifest.json` growing a smelter row turns `species_probe.png` red though it only draws ore
and ground. That is the conservative direction on purpose (red means "look", not "the picture
is wrong") and it is cheap to clear: redraw the sheet, and if the pixels do not move, only the
stamp does. The alternative -- recording which BYTES of a source a sheet actually read -- buys
precision with a far more fragile recorder, and a check nobody can explain is a check that gets
regenerated blind.

THE ANTI-VACUITY CHECKS, because "no source moved" is trivially true of a sheet that recorded
nothing, and this check's whole value rests on a recorder it cannot see run.
  1. At least one sheet must carry a NON-EMPTY stamp. If a bad merge left all nine empty, every
     one would pass and the guard would be gone while staying green.
  2. The recorder must still SEE the four ways this pipeline opens a file -- including
     `pathlib.Path.read_bytes()`, which patching `builtins.open` alone misses because `io.open`
     is a separate binding to the same function. Measured, not reasoned: if the recorder ever
     stops observing a pattern, new stamps silently lose sources and this check goes green over
     a sheet drawn from art it never recorded. NO VERDICT, not a pass.

TWO RED LEVERS, since two guards in this pipeline have silently stopped guarding. They prove
DIFFERENT guards and a run can only be evidence for one, so setting both is NO VERDICT.

    REVIEW_SOURCES_FAKE_MOVE=ground.png python3 art/check_review_sources.py   # must exit 1
    REVIEW_SOURCES_FAKE_EMPTY=1         python3 art/check_review_sources.py   # must exit 2

Each reproduces a CAUSE rather than lowering a bar. FAKE_MOVE perturbs the digest of one
shipped file exactly as a re-render would, and every sheet that composited that file must name
it. FAKE_EMPTY reads every stamp as present and EMPTY -- what a bad merge or a recorder that
stopped recording leaves behind -- and ANTI-VACUITY 1 must fire.

**FAKE_EMPTY MUST END IN exit 2 AND NOT exit 1, AND THAT IS THE WHOLE POINT OF HAVING IT**
(ASSA-326). All nine empty makes eight sheets individually red as well, so the only thing
separating "the guard is gone" from "a sheet is stale" is that ANTI-VACUITY 1 is tested before
`if bad`. Nothing held that order down. A reader who got exit 1 here would go redraw sheets
while the recorder stayed broken.

The honest version of each was run too, because a lever I wrote cannot be the only thing that
has ever made this red. FAKE_MOVE: a real byte appended to a real sprite, red reproduced, then
restored. FAKE_EMPTY: all nine committed sheets really rewritten without their chunk (Pillow,
each strip asserted on disk), the check run with NO lever set, exit 2 on a real tree, then
`git checkout -- assets/review` and green again.

Exit codes, matching the other art checks: 0 green, 1 a sheet is stale or unstamped, 2 NO
VERDICT (the recorder is broken, or there is nothing to measure), which fails the job rather
than passing quietly.
"""
import hashlib
import json
import os
import sys

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
REVIEW = os.path.join(ROOT, "assets", "review")

sys.path.insert(0, ART)
import review_sources  # noqa: E402
from review_sources import ABSENT, CURRENT, EMPTY, KEY, STALE  # noqa: E402

#: Perturb one shipped file's digest as a re-render would. See the docstring.
FAKE_MOVE = os.environ.get("REVIEW_SOURCES_FAKE_MOVE")

#: Read EVERY stamp as a present, well-formed, EMPTY one -- a bad merge, or a recorder that
#: stopped recording. Proves ANTI-VACUITY 1 still bites. See the docstring.
FAKE_EMPTY = os.environ.get("REVIEW_SOURCES_FAKE_EMPTY")

#: Which script draws which sheet. Needed anyway -- a red that does not say what to re-run is a
#: red people route around -- and a new sheet landing without an entry is NO VERDICT rather
#: than a silent pass, which is the forward case `check_ci_runs_every_check.py` worries about.
GENERATOR = {
    "assembled.png": "assemble.py",
    "contact.png": "build.py",
    "design_rows.png": "design_row_sheet.py",
    "loudness.png": "loudness.py",
    "mock_scene.png": "mock_scene.py",
    "pack_icon_kinds.png": "pack_icon_kinds.py",
    "pack_icons.png": "pack_icon_sheet.py",
    "pack_rows.png": "pack_row_sheet.py",
    "species_probe.png": "species_probe.py",
}

#: How a generator spells the shipped-art folder. All eight that read art contain one of these.
SPRITE_PATH_MARKS = ('assets/sprites', 'assets", "sprites')

NOT_A_COMPOSITE = "NO ART PATH"


def composites_no_art(sheet):
    """Can this sheet's generator reach shipped art AT ALL?

    THE ONE NARROW EXEMPTION, and it is worth stating exactly what it buys and what it cannot.

    `design_rows.png` is the only committed sheet drawn before stamping existed that cannot be
    redrawn here: it needs a `bench_read.gd` dump from a LIVE relay with designs in the bench,
    the original dump was a `/tmp` file and is gone, and hand-writing one would invent the
    masses, budgets and verdicts that `design_row_layout.gd` exists to take from the sim. So it
    carries no stamp, and UNSTAMPED is red -- correctly, but red on a sheet nobody broke.

    Rather than an allowlist of sheets to skip, the exemption is keyed to a MEASURED property
    of the generator: `design_row_sheet.py` contains no reference to the shipped-art path and
    is the only one of the nine that does not (8 of 9 reference it, measured). A sheet whose
    script cannot name the art folder cannot have composited art, so it cannot be stale against
    it.

    IT FAILS IN THE SAFE DIRECTION, which is the whole reason it is allowed to exist. It excuses
    a sheet that recorded NOTHING -- no stamp at all, or a stamp with an empty list; a sheet that
    named any art is held to it whatever its script says. And the day somebody teaches that
    script to blit an icon, the reference appears, the exemption evaporates, and the sheet goes
    red until it is redrawn.

    **THIS USED TO GATE `UNSTAMPED` ALONE AND THAT WAS THE HOLE** (ASSA-144 box 4, Maren's ruling
    of 2026-10-05, Cove's finding). `NO SOURCES` -- a stamp that is present, well-formed and
    EMPTY -- was handed a pass with no key at all, so a sheet whose generator provably CAN reach
    shipped art but ran outside `recording()` read green while its guard was gone: the condition
    this check exists to kill, wearing the other state's clothes. Both states now come through
    here, and a sheet that records nothing while its script names the art folder is RED.

    I ALSO HAD THE SUNSET WRONG, in this docstring, in my own words. It said the hole below
    "closes by itself the first time this sheet is redrawn, because then it will carry a measured
    empty stamp and take the EMPTY path instead" -- which was only ever true because the EMPTY
    path was green for free. Redrawing moves `design_rows.png` from `UNSTAMPED` to `NO SOURCES`
    and this function keys both, so a redraw does not retire the exemption. **Only the script
    learning to name the art folder does.**

    WHAT IT IS NOT: a test of behaviour. A generator that read art through a helper holding the
    path would be wrongly exempted. That is a real hole, bounded by the paragraph above, and it
    is why this function is designed to become dead code rather than to be trusted for ever.
    """
    script = GENERATOR.get(sheet)
    if not script:
        return False
    path = os.path.join(ART, script)
    if not os.path.exists(path):
        return False
    with open(path) as fh:
        text = fh.read()
    return not any(mark in text for mark in SPRITE_PATH_MARKS)


class CannotCheck(Exception):
    """Something this check needs is not where it expects. Exit 2, never a pass."""


def prove_the_recorder_still_sees_opens():
    """Anti-vacuity check 2: the stamps are only as complete as the recorder's observation.

    Writes a throwaway file INSIDE the shipped-art folder and reads it back the four ways this
    pipeline reads art, asserting each is recorded and that a WRITE is not. Pillow's
    `Image.open` is not exercised here (CI has no Pillow) and does not need to be: it opens a
    path through `builtins.open`, which is pattern 1.
    """
    from pathlib import Path

    probe = os.path.join(review_sources.SPRITES, "__check_review_sources_probe.json")
    if os.path.exists(probe):
        raise CannotCheck("%s already exists; refusing to clobber it." % probe)
    missed = []
    try:
        with open(probe, "w") as fh:
            fh.write('{"probe": 1}')
        for label, read in (
            ("builtins.open", lambda: open(probe).close()),
            ("json.load(open(Path))", lambda: json.load(open(Path(probe)))),
            ("Path.read_bytes", lambda: Path(probe).read_bytes()),
        ):
            review_sources.reset()
            with review_sources.recording():
                read()
            if os.path.basename(probe) not in review_sources.recorded():
                missed.append(label)
        # And a write must NOT be a source, or a generator would stamp its own output.
        review_sources.reset()
        with review_sources.recording():
            with open(probe, "a") as fh:
                fh.write("")
        if review_sources.recorded():
            missed.append("a WRITE was recorded as a source")
    finally:
        review_sources.reset()
        if os.path.exists(probe):
            os.remove(probe)
    if missed:
        raise CannotCheck(
            "the recorder no longer observes: %s.\n"
            "Every stamp written from now on would be missing those reads, and this check\n"
            "would pass over a sheet drawn from art it never recorded." % ", ".join(missed))
    return ["builtins.open", "json.load(open(Path))", "Path.read_bytes", "writes ignored"]


def stamp_as_read(path):
    """The stamp this run is reasoning about: the file's own, or a lever's forgery.

    ONE PLACE, because the stamp used to be read twice by two routes -- once for the per-sheet
    verdict and once for ANTI-VACUITY 1 -- and a lever that only reached the first would have
    reported nine EMPTY sheets and then checked the anti-vacuity guard against the real file,
    which is green. That is the shape of a lever that proves nothing.

    The forgery is spelled by `review_sources.stamp_of`, the same function that writes real
    stamps, so an empty stamp here is byte-identical to the empty stamp a broken recorder
    would actually leave behind.
    """
    if FAKE_EMPTY:
        return review_sources.stamp_of({})
    return review_sources.read_stamp(path)


def fake_moved(sources):
    """The stamp as it would read if one shipped file had been re-rendered."""
    out = dict(sources)
    if FAKE_MOVE in out:
        out[FAKE_MOVE] = hashlib.sha256(("moved:" + out[FAKE_MOVE]).encode()).hexdigest()[:16]
    return out


def main():
    print(__doc__.splitlines()[0])
    if not os.path.isdir(REVIEW):
        raise CannotCheck("no review folder at %s" % REVIEW)
    if not os.path.isdir(review_sources.SPRITES):
        raise CannotCheck("no shipped art at %s" % review_sources.SPRITES)

    if FAKE_MOVE and FAKE_EMPTY:
        raise CannotCheck(
            "both red levers are set. They prove different guards and a run can only be\n"
            "evidence for one: FAKE_MOVE must end in exit 1 naming the sheets that drew the\n"
            "moved file, FAKE_EMPTY in exit 2 on ANTI-VACUITY 1. Set one.")

    patterns = prove_the_recorder_still_sees_opens()
    print("\n  recorder sees: %s" % ", ".join(patterns))

    sheets = sorted(f for f in os.listdir(REVIEW) if f.endswith(".png"))
    if not sheets:
        raise CannotCheck("there are no review sheets in %s to check." % REVIEW)
    unmapped = [s for s in sheets if s not in GENERATOR]
    if unmapped:
        raise CannotCheck(
            "no generator recorded for %s. A new review sheet needs an entry in GENERATOR, or\n"
            "its red cannot say what to re-run -- and the exemption below cannot be measured\n"
            "for it either. Add it rather than letting it ride." % ", ".join(unmapped))
    missing = [n for n, s in sorted(GENERATOR.items()) if not os.path.exists(os.path.join(ART, s))]
    if missing:
        raise CannotCheck("GENERATOR names a script that does not exist, for: %s"
                          % ", ".join(missing))

    if FAKE_MOVE:
        print("\n  [RED RUN] pretending client/assets/sprites/%s was re-rendered; every sheet\n"
              "            that composited it MUST be named below." % FAKE_MOVE)
    if FAKE_EMPTY:
        print("\n  [RED RUN] reading every stamp as present and EMPTY, which is what a bad merge\n"
              "            or a recorder that stopped recording leaves behind. This MUST end in\n"
              "            NO VERDICT (exit 2) on ANTI-VACUITY 1, and never in a pass.")

    bad, states, stamped_any = [], {}, False
    print("\n  %-22s %-11s %s" % ("sheet", "verdict", "sources"))
    for name in sheets:
        path = os.path.join(REVIEW, name)
        if FAKE_MOVE or FAKE_EMPTY:
            # Perturb the RECORDED side, which is what a re-render (FAKE_MOVE) or a stopped
            # recorder (FAKE_EMPTY) does to the relationship between a sheet and the art under
            # it, without touching a committed file. An empty stamp moves nothing, so it falls
            # through to EMPTY below and then through the exemption, exactly as a real one does.
            stamp = stamp_as_read(path)
            sources = json.loads(stamp) if stamp else None
            if sources is None:
                state, lines = ABSENT, ["carries no `%s` stamp." % KEY]
            else:
                state, lines = CURRENT, ["%d file(s)" % len(sources)]
                moved = []
                for rel, was in sorted(fake_moved(sources).items()):
                    full = os.path.join(review_sources.SPRITES, rel)
                    now = review_sources.digest(full) if os.path.exists(full) else "GONE"
                    if now != was:
                        moved.append("client/assets/sprites/%s moved: the sheet drew %s, the\n"
                                     "      shipped art is now %s." % (rel, was, now))
                if moved:
                    state, lines = STALE, moved
                elif not sources:
                    state, lines = EMPTY, ["composited no shipped art."]
        else:
            state, lines = review_sources.verdict(path)

        # The one narrow exemption, for a sheet that recorded NOTHING -- whether that is no stamp
        # (UNSTAMPED) or a present, empty one (NO SOURCES). See `composites_no_art`: keyed to a
        # measured property of the generator, fails safe, dead code the day that script names the
        # art folder. EMPTY was UNGATED until ASSA-144 box 4 and that was the whole hole: a sheet
        # that CAN reach shipped art and recorded none of it passed for free.
        if state in (ABSENT, EMPTY) and composites_no_art(name):
            how = ("It carries no stamp because it predates stamping"
                   if state == ABSENT else "Its stamp is present and empty")
            state = NOT_A_COMPOSITE
            lines = ["%s names no shipped-art path, so this sheet composites none and cannot\n"
                     "      be stale against it. %s." % (GENERATOR[name], how)]
        elif state == EMPTY:
            # SAY WHAT TO DO, NOT WHAT IS MISSING. `review_sources.verdict` phrases EMPTY as
            # "nothing for it to go stale against", which was an explanation while this state
            # was green and is an excuse now that it is red: a reader of that line learns
            # nothing they can act on. The exemption just declined this sheet, so we know the
            # one thing worth printing -- its generator CAN name the art folder and recorded
            # none of it, which is a recorder that was not running.
            lines = ["recorded an EMPTY source list while %s names the shipped-art path, so it\n"
                     "      was drawn OUTSIDE `review_sources.recording()` and its stamp is a\n"
                     "      forgery of 'composited nothing'. Redraw it through the recorder\n"
                     "      (for contact.png: `art/build.py --contact-only`, never a direct\n"
                     "      `contact()` call)." % GENERATOR[name]]

        states[name] = state
        stamp = stamp_as_read(path)
        if stamp:
            try:
                stamped_any = stamped_any or bool(json.loads(stamp))
            except ValueError:
                pass
        n = "-" if stamp is None else str(len(json.loads(stamp))) if stamp.startswith("{") else "?"
        print("  %-22s %-11s %s" % (name, state, n))
        # EMPTY JOINED THIS LIST IN ASSA-144 box 4. It is only reachable here when the exemption
        # above declined it, which means the generator CAN name shipped art and recorded none --
        # a recorder that stopped recording, not a sheet that composites nothing.
        if state in (STALE, ABSENT, EMPTY):
            for line in lines:
                bad.append("%s %s" % (name, line))

    # ANTI-VACUITY 1. Every sheet recording nothing would pass while guarding nothing.
    if not stamped_any:
        raise CannotCheck(
            "not one of the %d sheets carries a non-empty source list, so 'no source moved'\n"
            "was true of all of them without measuring any art. One sheet composites no\n"
            "sprites by design (design_rows.png); all of them doing so is a broken recorder\n"
            "or a bad merge, not a tree in good order." % len(sheets))

    print("\n  %d sheets: %s" % (len(sheets), ", ".join(
        "%d %s" % (sum(1 for v in states.values() if v == s), s)
        for s in (CURRENT, EMPTY, NOT_A_COMPOSITE, STALE, ABSENT)
        if any(v == s for v in states.values()))))

    if bad:
        print("\nVERDICT: FAIL (exit 1)")
        for line in bad:
            print("  - %s" % line)
        print("\n  A STALE sheet means the art moved and the picture did not. Redraw that\n"
              "  sheet from the shipped art and commit it:\n"
              "    uv run --with pillow python art/<its script>.py\n"
              "    art/build.py --contact-only          # for contact.png, and NEVER --pack:\n"
              "                                         # that repacks from a local cache\n"
              "  Then `python3 art/review_sources.py` to read the verdict back off the file.")
        return 1
    held = sum(1 for v in states.values() if v == CURRENT)
    print("\nVERDICT: PASS (exit 0). %d sheet(s) name the shipped art they composited, and every\n"
          "  one of those files is byte-identical to what ships today." % held)
    for name, state in sorted(states.items()):
        # Say out loud which sheets this pass is NOT a statement about, or the green reads as
        # a stronger claim than it is -- the exact way a review sheet got believed in the
        # first place.
        if state == NOT_A_COMPOSITE:
            # THIS SENTENCE USED TO END "says nothing about whether that picture is current",
            # and that stopped being true the day ASSA-173 landed: `design_rows.png` now carries
            # a LAYOUT stamp and `check_review_layout.py` re-asks the probe that drew it. The old
            # wording was right when nothing checked the other half and would have gone on
            # telling a reader to distrust a sheet that is now held -- a green sentence outliving
            # its reason, which is the same rot this check exists to catch in pictures.
            print("  %s is exempt and recorded no art: %s names no shipped-art path. Whether that\n"
                  "    picture is still the CLIENT's is a different claim, on a different key:\n"
                  "    check_review_layout.py."
                  % (name, GENERATOR[name]))
    # THERE IS NO `elif state == EMPTY` HERE ANY MORE, and its removal is the fix rather than
    # tidying (ASSA-144 box 4). It printed "recorded an empty source list, so there is nothing
    # to compare" on a PASS, which is the sentence a forged empty stamp wanted said about it.
    # EMPTY is now either declined by the exemption and RED above, or accepted by it and
    # reported as NO ART PATH on the line before this one, so reaching here is impossible.
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CannotCheck as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n%s" % why)
        sys.exit(2)
