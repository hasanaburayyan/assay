#!/usr/bin/env python3
"""IS THIS DIRECTORY SAFE TO HAND A COLD READER? (ASSA-302, the other half of ASSA-294.)

    python3 client/tools/blind_frames.py <dir> [<dir> ...]     # before you send one
    python3 client/tools/blind_frames.py --summary <root>      # how bad is it, over a tree

Exit 0 when every directory given is pictures and nothing else. Exit 1 naming what would tell the
reader what they are about to be asked to find. Exit 2 if a path is not a directory, because "no
directory" must never read the same as "nothing to tell".

WHY THIS EXISTS AND WHY IT IS NOT ASSA-294. ASSA-294 taught `window_shot.gd` a `blind` mode: it
writes pictures to `<out>/frames/` and everything naming them to `<out>/key/`, and it refuses its
own green line if the two ever mix. That can only protect runs made AFTER it. The measurement that
came with it: `shared/assay` holds **166 directories with two or more frames, and 64 of them (39%)
also hold a file that names the marks** -- a `*-marks.json`, a `*hover.json`, a shot log, a report.
Those are the obvious place to go for a frame of a past state, and "read this one again on the old
build" is a normal ask that today silently spends a reader.

A cold read is the only instrument we have for *can a player tell what this is*. Nothing in the
suite can run it, it costs a whole person's attention, and contamination invalidates a pass and
never a fail (ASSA-206). Nacre was handed the walk's endpoints `(58,59) -> (67,59)` printed beside
the frame and said so: *"I read it as a grey scratch and only called it the walk because I was told
to."* That read is worth nothing and cannot be re-run on them.

**A PICTURE CAN BE THE ANSWER KEY TOO, WHICH IS THE MISTAKE I SHIPPED INSIDE ASSA-294 BEFORE
CATCHING IT.** My first sweep there refused non-pictures and walked straight past
`09-whole-world-key.png` -- it IS a PNG, and it is the MAP KEY, the one frame whose whole job is to
say what the marks mean. Testing the file EXTENSION is not testing the property, so `names_marks`
below is the same rule `window_shot.gd` applies, held in one sentence rather than two places.

**DELIBERATELY NOT NAMED `check_*`.** `art/check_ci_runs_every_check.py` globs `art/check_*.py` and
regexes bare `check_*.py` filenames out of build.yml; ASSA-282 hit exactly that collision when a
`check_` script landed outside `art/`. This also runs on `shared/`, which is not in the repo, so no
gate can run it -- it is an instrument a human points at a directory, and that is the whole design.
"""
import os
import re
import sys

#: Extensions that are a picture and nothing else. Everything else in a frame directory is prose,
#: a dump or a log, and all three can name a mark.
PICTURE = (".png", ".jpg", ".jpeg", ".webp")


#: `key` or `marks` AS A WHOLE TOKEN, not as a substring. The first version of this asked
#: `"key." in name`, which refuses `donkey.png`, and a guard that refuses a thing it should not is
#: a guard that gets switched off rather than obeyed -- the same reason Maren refused a colour guard
#: on ASSA-267. Tokens are separated by `-`, `_`, `.` or the ends of the name.
TELL_TOKENS = ("key", "marks")


def names_marks(name):
    """Whether this filename advertises the answer, picture or not.

    The same rule as `window_shot.gd::_names_marks`: a shot called `09-whole-world-key.png` or
    `04-marks-two.json` says on its face that it is about the marks. Kept as one function so the
    property is stated once -- the version of this that asked "is it a .png" had a hole the exact
    shape of the map key, which is the mistake I shipped there before catching it.
    """
    tokens = re.split(r"[-_.]+", name.lower())
    return any(t in TELL_TOKENS for t in tokens)


def tells(directory):
    """Every file in `directory` that would tell a reader what to find, sorted.

    Not recursive, and that is a decision rather than an omission: a frame directory is what gets
    handed over, and a subdirectory is handed over separately (which is exactly what ASSA-294's
    `frames/` and `key/` split relies on). `--summary` walks the tree itself.
    """
    out = []
    for name in sorted(os.listdir(directory)):
        if os.path.isdir(os.path.join(directory, name)):
            continue
        if not name.lower().endswith(PICTURE) or names_marks(name):
            out.append(name)
    return out


def pictures(directory):
    return [n for n in sorted(os.listdir(directory))
            if n.lower().endswith(PICTURE) and not names_marks(n)
            and not os.path.isdir(os.path.join(directory, n))]


#: Files that do not merely sit beside the pictures but NAME COORDINATES -- a planted-mark dump, a
#: shot log, a report. The narrow question, kept separate from the strict one on purpose: see
#: [`summary`].
import re as _re  # noqa: E402  (beside the pattern it is for)
NAMES_COORDINATES = _re.compile(
    r"(marks.*\.json|hover\.json|discs.*\.json|^shot.*\.log$|window.?shot.*\.log$|^run\.log$"
    r"|report\.txt$)", _re.I)


def summary(root):
    """How many frame directories under `root` carry their own answer key -- BOTH WAYS.

    **TWO COUNTS, BECAUSE I QUOTED ONE OF THEM AS IF IT WERE THE OTHER.** ASSA-302 was filed saying
    "64 of 166 (39%)", measured with the narrow pattern below. The first run of this tool said "119
    of 171 (70%)", because what it GATES on is the strict property -- anything that is not a
    picture, which is the same rule `window_shot.gd` refuses its green line for, and which counts a
    `README.md` and an analysis `.py` too.

    Both are true and they answer different questions, so the tool prints both rather than letting
    one silently replace the other in somebody's memory. A number I cannot say which question it
    answers is a number I have decided not to measure.

    A directory counts as a frame directory when it holds two or more pictures: one picture is a
    crop, not a read.
    """
    dirs = strict = narrow = 0
    rows = []
    for here, _subdirs, files in os.walk(root):
        shots = [f for f in files if f.lower().endswith(PICTURE) and not names_marks(f)]
        if len(shots) < 2:
            continue
        dirs += 1
        found = tells(here)
        named = [f for f in found if NAMES_COORDINATES.search(f) or names_marks(f)]
        if found:
            strict += 1
            rows.append((os.path.relpath(here, root), len(shots), found, named))
        if named:
            narrow += 1
    for where, n, found, named in sorted(rows):
        mark = "!" if named else " "
        print("%s %-44s %3d frames  <- %s" % (mark, where, n, ", ".join(found)))
    pct = (lambda k: (100.0 * k / dirs) if dirs else 0.0)
    print("\n%d directories hold 2+ frames." % dirs)
    print("  %3d (%.0f%%) hold ANYTHING that is not a picture -- what this tool refuses, and the "
          "same rule window_shot.gd's blind mode holds." % (strict, pct(strict)))
    print("  %3d (%.0f%%) hold a file that NAMES COORDINATES -- a mark dump, a shot log, a report, "
          "or a key picture. Marked `!` above." % (narrow, pct(narrow)))
    return 0


def report(directory):
    """One directory, the question being `can I send this`. Returns True when it is safe."""
    found = tells(directory)
    shots = pictures(directory)
    if not found:
        print("SAFE TO SEND  %s" % directory)
        print("  %d picture(s) and nothing else: %s" % (len(shots), ", ".join(shots) or "none"))
        return True
    print("DO NOT SEND   %s" % directory)
    print("  %d file(s) here name what the reader would be asked to find:" % len(found))
    for name in found:
        why = "a PICTURE, but its name says it is the key" if name.lower().endswith(PICTURE) \
            else "not a picture"
        print("    %-34s %s" % (name, why))
    print("  %d picture(s) would be safe on their own: %s"
          % (len(shots), ", ".join(shots) or "none"))
    print("  Send a `blind` run instead (window_shot.gd ... blind), or copy only the pictures.")
    return False


def main(argv):
    if not argv:
        print(__doc__.strip().splitlines()[0])
        print("\n    python3 client/tools/blind_frames.py <dir> [<dir> ...]")
        print("    python3 client/tools/blind_frames.py --summary <root>")
        return 2
    if argv[0] == "--summary":
        if len(argv) != 2 or not os.path.isdir(argv[1]):
            print("ERROR  --summary wants one directory")
            return 2
        return summary(argv[1])
    # A MISSING PATH EXITS 2, NEVER 0. "I could not look" and "there is nothing to tell" are the
    # same green to a tired asker, and that is the failure this whole item is about.
    for path in argv:
        if not os.path.isdir(path):
            print("ERROR  %s is not a directory, so nothing was checked" % path)
            return 2
    ok = True
    for path in argv:
        if not report(path):
            ok = False
        print("")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
