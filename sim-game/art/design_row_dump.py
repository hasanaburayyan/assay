#!/usr/bin/env python3
"""THE BENCH SHEET'S WHOLE CHAIN, IN ONE PLACE, SO THE CHECK CAN RE-ASK IT (ASSA-173).

    python3 art/design_row_dump.py /tmp/d            # -> /tmp/d/layout.json + provenance.json
    from design_row_dump import layout_now           # the same answer, for check_review_layout.py

`design_rows.png` was the one committed sheet that could not say whether it is still a picture of
the client, and the reason was never one missing line: drawing it takes TWO Godot runs and a merge,
and that recipe lived in three docstrings in slightly different forms. A recipe a human retypes is
a recipe `check_review_layout.py` cannot run, so the sheet got an `UNDECLARABLE` exemption whose
stale reason printed on every run for three days (ASSA-173, and I wrote that reason).

So the chain is a module. The generator calls it to draw the sheet; the check imports
[`layout_now`] to re-ask the engine and compare. There is exactly one definition of what this
sheet is a picture of, which is the only way the two can be compared at all.

**WHY TWO RUNS, AND WHY THAT IS NOT A FIXTURE.** The bench is the EQUIPPED PICK -- one design per
run -- so one run can show one verdict. `SAFE` and `UNCERTAIN` are the same design with and without
an assay, which is the transition the verdict word exists to teach, and `button_session.gd
hold-assay` (#378) reaches it by HOLDING A BUTTON BACK rather than by building a world. Maren's
line on this item, 06:01: *a flag may change what the player does; it may not change what the world
is.* Both runs are the plain offline demo loop on one seed.

**AND EVERY ROW CARRIES ITS OWN RUN, which is the defect this module was written around.** A dump
has one `tick`, one `hash` and one `seed` for the whole file. Merge two and those three fields name
whichever run was written last and lie about the other row -- "a sheet that cannot say which client
each row reviews is ASSA-144 with the names changed" (Maren, same comment). So the merge moves
provenance ONTO each design as `source`, `design_row_layout.gd` carries it through to the row it
built, and the sheet prints it per row. The singular fields are not merged at all: [`merge`]
refuses to invent one.

NO GODOT IS NOT A PASS, inherited from `ask_layout` rather than reimplemented: every failure path
raises `CannotCheck`, which the check turns into exit 2. A sheet claiming to be a picture of a
layout, checked without the engine, must never look green.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ask_layout import CannotCheck, GODOT, TIMEOUT, CLIENT, ART, excerpt  # noqa: E402

#: The probe this module drives, and the name a sheet's layout stamp declares.
PROBE = "design_row_layout.gd"

#: THE SEED IS PART OF THE SHEET'S IDENTITY, not a convenience default. The digest the check
#: compares is over this world's layout, so moving this number means redrawing the sheet -- which
#: is correct, and is why it is written here once rather than passed in by whoever calls.
SEED = "14247"

#: The runs that make the sheet, in the order their rows appear. `label` is what the sheet prints;
#: `flags` is what makes the player's hand different. Adding a row here is adding a row to the
#: picture, and both the generator and the check pick it up with no further edit.
RUNS = (
    {"label": "assayed", "flags": ()},
    {"label": "rough", "flags": ("hold-assay",)},
)


def _run_godot(args, marker, what):
    """One Godot run from `client/`, returning its stdout. Raises `CannotCheck`, never passes."""
    if not os.path.exists(GODOT):
        raise CannotCheck("no Godot at %r. Set GODOT=<path>.\nDeliberately not a pass: %s"
                          % (GODOT, what))
    try:
        p = subprocess.run([GODOT, "--headless", "--path", ".", "--script"] + list(args),
                           cwd=CLIENT, capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        raise CannotCheck("Godot did not finish %s in %ds (check `pgrep -f Godot`)."
                          % (what, TIMEOUT))
    if marker not in p.stdout:
        blob = p.stdout + p.stderr
        raise CannotCheck("%s printed no %r.\n--- godot said ---\n%s"
                          % (what, marker, excerpt(blob)))
    return p.stdout


def one_run(run, out_path):
    """One offline demo run's bench dump, written to `out_path` and returned parsed.

    `--headless` IS CORRECT HERE AND THE REASON IS NOT THE OBVIOUS ONE (ASSA-173). This script
    draws nothing, so headless is free -- but the probe in the next step is headless too, and for
    weeks this item's own notes said that could not work. It can: a `VBoxContainer` sizes from its
    children and a `Label` wraps against the width it is handed, and neither needs a window. What
    needs a window is a WINDOW-derived size (a clip, a fold), and this sheet measures none.
    """
    args = ["res://tools/button_session.gd", "--", "offline", SEED]
    args += list(run["flags"]) + ["designs=%s" % out_path]
    _run_godot(args, "BUTTON SESSION OK", "the %s demo run" % run["label"])
    if not os.path.exists(out_path):
        raise CannotCheck("the %s run said BUTTON SESSION OK and wrote no %s"
                          % (run["label"], out_path))
    with open(out_path) as fh:
        return json.load(fh)


def merge(dumps):
    """Two bench dumps into one, with provenance moved onto each design.

    THE SINGULAR FIELDS ARE DROPPED RATHER THAN PICKED. A merged dump cannot honestly carry one
    `tick` or one `hash`, and the version of this that kept the first run's pair is exactly what
    Maren refused on the sheet. There is no "primary" run here to inherit from.
    """
    designs = []
    for run, dump in zip(RUNS, dumps):
        if not dump.get("designs"):
            raise CannotCheck("the %s run dumped no designs, so there is no row to draw. The "
                              "bench is the equipped pick; a run with an empty hand draws "
                              "nothing." % run["label"])
        for design in dump["designs"]:
            design = dict(design)
            # EVERY KEY A ROW NEEDS TO NAME ITSELF, taken from the run that produced THIS design.
            design["source"] = {
                "run": run["label"],
                "tick": dump.get("tick"),
                "hash": dump.get("hash"),
                "seed": dump.get("seed"),
                "flags": " ".join(run["flags"]) or "none",
            }
            designs.append(design)
    return {"designs": designs}


def layout_now(scratch):
    """The engine's bench layout today, for the merged two-run world. `scratch` is a directory.

    This is the function `check_review_layout.py` re-asks and the generator draws from, so the
    digest on the sheet and the digest in the check are over the output of one piece of code.
    """
    dumps = [one_run(r, os.path.join(scratch, "designs-%s.json" % r["label"])) for r in RUNS]
    merged = os.path.join(scratch, "designs-merged.json")
    with open(merged, "w") as fh:
        json.dump(merge(dumps), fh, sort_keys=True, separators=(",", ":"))
    out = _run_godot([os.path.join(ART, PROBE), "--", merged],
                     "DESIGN LAYOUT OK", "the bench layout probe")
    for line in out.splitlines():
        if line.startswith("DESIGN_LAYOUT_JSON "):
            return json.loads(line[len("DESIGN_LAYOUT_JSON "):])
    raise CannotCheck("the probe said DESIGN LAYOUT OK and printed no DESIGN_LAYOUT_JSON")


def provenance_of(layout):
    """The caption's own facts, derived from the rows rather than from a run.

    `seed` and `rules` are properties of the world every row shares; there is deliberately no
    `tick` or `hash` here, because those differ per row and the row prints its own.
    """
    runs = [r.get("source", {}) for r in layout["rows"]]
    return {
        "source": "art/design_row_dump.py, seed %s, %d run(s): %s" % (
            SEED, len(RUNS), ", ".join("%s (%s)" % (s.get("run"), s.get("flags")) for s in runs)),
        "seed": next((s.get("seed") for s in runs if s.get("seed")), "unknown"),
        "note": "Each row prints the run and tick it came from; this sheet merges runs, so there "
                "is no single tick or hash for the picture.",
    }


def main():
    scratch = sys.argv[1] if len(sys.argv) > 1 else "/tmp/design-rows"
    os.makedirs(scratch, exist_ok=True)
    layout = layout_now(scratch)
    with open(os.path.join(scratch, "layout.json"), "w") as fh:
        json.dump(layout, fh)
    with open(os.path.join(scratch, "provenance.json"), "w") as fh:
        json.dump(provenance_of(layout), fh)
    for row in layout["rows"]:
        s = row.get("source", {})
        print("  %-11s run %-9s tick %-6s hash %s"
              % (row["verdict"]["text"], s.get("run"), s.get("tick"), s.get("hash")))
    print("layout.json and provenance.json in %s" % scratch)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CannotCheck as why:
        print("NO VERDICT  %s" % why, file=sys.stderr)
        sys.exit(2)
