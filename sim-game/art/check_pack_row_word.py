#!/usr/bin/env python3
"""Does the SHIPPED review sheet say what the client says? (ASSA-132)

    art/check_pack_row_word.py

WHAT WENT WRONG. `assets/review/pack_icons.png` labelled the head, handle, frame and hopper
rows all **Frame**. The client labels two of them **Mount** and has since ASSA-103, which made
the word a property of the KIND (`is_frame` out of the sim's catalogue) instead of a property
of how far into an assembly the player had got. The sheet was drawn before that and never
redrawn: #157 regenerated `pack_rows.png` from a fresh engine layout and left this one alone.

WHY THAT IS WORTH A CI STEP. These sheets exist so the Director can judge the pack WITHOUT
running the game (ASSA-71). Everything else in the pipeline is checked against the engine;
the sheet is the one artefact whose job is to be believed, and nothing checked it. A sheet
that lies about the client is worse than no sheet. It is the mock scene holding a machine the
game cannot build, one surface further out.

TWO CLAIMS.

 1. THE WORD IS THE KIND'S. For every part row the engine laid out, the label on its `build`
    button is `Frame` if the catalogue says `is_frame` and `Mount` if it does not -- and the
    same row's `labels_building` column (the probe asking `AssayHud.stack_verbs` a second
    time) says the same thing, so the word has not started swapping with client state again.
    Both sides come from the engine; nothing here holds a list of which kinds are frames.

 2. THE SHIPPED SHEET SAYS THE SAME. `pack_icon_sheet.py` stamps the words it drew into the
    PNG (`pack_words.py`); this recomputes them from the live engine and compares. Red when
    the sheet is stale, naming the rows and both words.

THE ANTI-VACUITY CHECK, which is why claim 1 is worth anything. If every part kind in the
catalogue were a frame -- or none were -- then "the word follows `is_frame`" would be one
word everywhere and could not fail. This needs at least one frame kind AND one mounted kind
among the rows it measured, and reports NO VERDICT rather than a pass when it does not have
them. Measured: 1 frame row and 2 mounted rows today (handle and frame are frames; head and
hopper are not), which is also Maren's `Assembly::validate` run on ASSA-86.

NOT A PICTURE CHECK. The stamp carries the sheet's WORDS, not its pixels; a re-rendered
sprite is not this check's business and turning red for one would train people to regenerate
blind. See `pack_words.py`.

Exit codes, matching the other three engine checks: 0 green, 1 the sheet or the client is
wrong, 2 NO VERDICT -- could not ask the engine, or had nothing to measure.
"""

import json
import os
import sys

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
SHEET = os.path.join(ROOT, "assets/review/pack_icons.png")

sys.path.insert(0, ART)
from ask_layout import CannotCheck, ask_the_engine, kind_of  # noqa: E402
from pack_words import KEY, read_stamp, stamp_of  # noqa: E402

WHY_THE_ENGINE = ("the question is whether a picture of the client agrees with the client.\n"
                  "Answering it from the pipeline's own idea of the labels would compare a\n"
                  "file with itself.")

#: The two words ASSA-103 allows, indexed by the catalogue's `is_frame`.
WORD = {1: "Frame", 0: "Mount"}


def build_word(row):
    """The label on this row's `build` button, or None when it affords no `build`.

    By POSITION in the verb list, because `verbs` is the button text in button order and
    `verb_kinds` is the sim-facing verb in the same order (`pack_icon_layout.gd`). Matching on
    the text would be a fact about English -- the exact trap ASSA-99 records.
    """
    kinds = list(row.get("verb_kinds", []))
    words = list(row.get("verbs", []))
    for i, verb in enumerate(kinds):
        if verb == "build" and i < len(words):
            return words[i]
    return None


def main():
    print(__doc__.splitlines()[0])
    layout = ask_the_engine(WHY_THE_ENGINE)
    rows = layout.get("rows", [])
    if not rows:
        raise CannotCheck("the engine laid out no pack rows at all, so there was nothing to\n"
                          "read a word off.")

    parts = [r for r in rows if r.get("is_frame", -1) in (0, 1)]
    print("\n  %-24s %-9s %-7s %-7s %s"
          % ("row", "catalogue", "button", "owed", "labels_building"))
    for r in rows:
        flag = r.get("is_frame", -1)
        print("  %-24s %-9s %-7s %-7s %s"
              % (r["line"][:24], {1: "frame", 0: "mounted"}.get(flag, "not a part"),
                 build_word(r) or "-", WORD.get(flag, "-"),
                 ",".join(r.get("labels_building", [])) or "-"))

    bad = []

    # CLAIM 1: the word is the kind's, both times the probe asks for it.
    for r in parts:
        owed = WORD[r["is_frame"]]
        got = build_word(r)
        if got is None:
            bad.append("%s is a part row and affords no `build` button at all, so the word\n"
                       "      ASSA-103 is about is not on the screen." % r["line"])
            continue
        if got != owed:
            bad.append("%s says %r; the catalogue says is_frame=%d, so it owes %r."
                       % (r["line"], got, r["is_frame"], owed))
        building = list(r.get("labels_building", []))
        if building != list(r.get("verbs", [])):
            bad.append("%s swaps its words once an assembly is started: %s -> %s. That is the\n"
                       "      ASSA-103 defect itself, not a stale picture."
                       % (r["line"], list(r.get("verbs", [])), building))

    # THE ANTI-VACUITY CHECK. See the docstring: one word everywhere cannot be wrong.
    flags = {r["is_frame"] for r in parts}
    if flags != {0, 1}:
        raise CannotCheck(
            "the rows measured hold %s, so 'the word follows the catalogue' had nothing to\n"
            "vary against: every part row would owe the same word and claim 1 would pass with\n"
            "the ASSA-103 defect present. %d part rows, flags %s."
            % ("only frame kinds" if flags == {1} else
               "only mounted kinds" if flags == {0} else "no part rows", len(parts),
               sorted(flags)))

    # CLAIM 2: the shipped sheet says the same thing the engine does.
    live = stamp_of(rows)
    if not os.path.exists(SHEET):
        bad.append("there is no sheet at %s to compare." % os.path.relpath(SHEET, ROOT))
    else:
        stamped = read_stamp(SHEET)
        if stamped is None:
            bad.append(
                "%s carries no `%s` stamp, so whether it agrees with the client cannot be\n"
                "      read off it. Regenerate it: that is what writes the stamp."
                % (os.path.relpath(SHEET, ROOT), KEY))
        elif stamped != live:
            was = {d["kind"]: d["words"] for d in json.loads(stamped)}
            now = {d["kind"]: d["words"] for d in json.loads(live)}
            for kind in sorted(set(was) | set(now)):
                if was.get(kind) != now.get(kind):
                    bad.append("the sheet draws the %s row as %s; the client says %s."
                               % (kind, was.get(kind, "NO SUCH ROW"),
                                  now.get(kind, "NO SUCH ROW")))

    print("\n  part rows: %d (%d frame, %d mounted). Sheet: %s"
          % (len(parts), sum(1 for r in parts if r["is_frame"] == 1),
             sum(1 for r in parts if r["is_frame"] == 0),
             "stamped" if os.path.exists(SHEET) and read_stamp(SHEET) else "NO STAMP"))
    if bad:
        print("\nVERDICT: FAIL (exit 1)")
        for line in bad:
            print("  - %s" % line)
        print("\n  Regenerate the sheet from a FRESH engine layout (never a cached JSON):\n"
              "    godot --headless --path client --script \"$PWD/art/pack_icon_layout.gd\" \\\n"
              "      | sed -n 's/^LAYOUT_JSON //p' > /tmp/layout.json\n"
              "    uv run --with pillow python art/pack_icon_sheet.py /tmp/layout.json")
        return 1
    print("\nVERDICT: PASS (exit 0). Every part row carries its kind's own word, and the\n"
          "  shipped sheet draws the same words the client does.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CannotCheck as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n%s" % why)
        sys.exit(2)
