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

THREE STATES, AND THE MIDDLE ONE IS WHY THIS IS NOT ONE LINE.
  CURRENT     every file the sheet recorded is byte-identical to the shipped art today.
  NO SOURCES  the sheet recorded an EMPTY list. `design_rows.png` draws an engine layout and
              composites no sprites, so it cannot go stale against them. Green, and it is a
              measured empty rather than an assumed one: that script records too, so the day it
              blits an icon the stamp grows by itself and this check starts holding it to one.
  UNSTAMPED   no chunk at all. RED, and deliberately not merged with the case above: a sheet
              that cannot say what it reviewed is the exact condition this item is about, and
              reading it as "composited nothing" would hand every pre-ASSA-144 sheet a clean
              bill. That is also why the stamping and this check had to land in one commit --
              on the commit before, all nine were UNSTAMPED and this check would have been red
              on a tree nobody had broken.

THE ANTI-VACUITY CHECKS, because "no source moved" is trivially true of a sheet that recorded
nothing, and this check's whole value rests on a recorder it cannot see run.
  1. At least one sheet must carry a NON-EMPTY stamp. If a bad merge left all nine empty, every
     one would pass and the guard would be gone while staying green.
  2. The recorder must still SEE the four ways this pipeline opens a file -- including
     `pathlib.Path.read_bytes()`, which patching `builtins.open` alone misses because `io.open`
     is a separate binding to the same function. Measured, not reasoned: if the recorder ever
     stops observing a pattern, new stamps silently lose sources and this check goes green over
     a sheet drawn from art it never recorded. NO VERDICT, not a pass.

THE RED LEVER, since two guards in this pipeline have silently stopped guarding:

    REVIEW_SOURCES_FAKE_MOVE=ground.png python3 art/check_review_sources.py   # must FAIL

It reproduces the CAUSE rather than lowering a bar: the digest of one shipped file is perturbed
exactly as a re-render would perturb it, and every sheet that composited that file must name it.
The honest version was run too -- a real byte appended to a real sprite, red reproduced, then
restored -- because a lever I wrote cannot be the only thing that has ever made this red.

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

    patterns = prove_the_recorder_still_sees_opens()
    print("\n  recorder sees: %s" % ", ".join(patterns))

    sheets = sorted(f for f in os.listdir(REVIEW) if f.endswith(".png"))
    if not sheets:
        raise CannotCheck("there are no review sheets in %s to check." % REVIEW)

    if FAKE_MOVE:
        print("\n  [RED RUN] pretending client/assets/sprites/%s was re-rendered; every sheet\n"
              "            that composited it MUST be named below." % FAKE_MOVE)

    bad, states, stamped_any = [], {}, False
    print("\n  %-22s %-11s %s" % ("sheet", "verdict", "sources"))
    for name in sheets:
        path = os.path.join(REVIEW, name)
        if FAKE_MOVE:
            # Perturb the RECORDED side, which is what a re-render does to the relationship
            # between a sheet and the art under it, without touching a committed file.
            stamp = review_sources.read_stamp(path)
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

        states[name] = state
        stamp = review_sources.read_stamp(path)
        if stamp:
            try:
                stamped_any = stamped_any or bool(json.loads(stamp))
            except ValueError:
                pass
        n = "-" if stamp is None else str(len(json.loads(stamp))) if stamp.startswith("{") else "?"
        print("  %-22s %-11s %s" % (name, state, n))
        if state in (STALE, ABSENT):
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
        for s in (CURRENT, EMPTY, STALE, ABSENT) if any(v == s for v in states.values()))))

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
    print("\nVERDICT: PASS (exit 0). Every committed review sheet names the shipped art it\n"
          "  composited, and every one of those files is byte-identical to what ships today.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CannotCheck as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n%s" % why)
        sys.exit(2)
