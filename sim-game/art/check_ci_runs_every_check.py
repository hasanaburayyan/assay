#!/usr/bin/env python3
"""EVERY `art/check_*.py` IN THE TREE IS RUN BY CI, AND EVERY ONE CI NAMES EXISTS (ASSA-72).

    python3 art/check_ci_runs_every_check.py

No Godot, no Pillow, no network: it reads two things off disk and compares two sets.

WHY THIS EXISTS, STATED AS THE FAILURE IT CAME FROM. #97 deleted `art/check_pack_icon_scale.py`
AND removed its `build.yml` step in the same commit, so main went back to drawing pack icons at
15/32 and CI stayed green -- there was nothing left to fail. A guard that can be deleted together
with its own invocation is not a guard, it is a comment. This file makes the two halves check
each other: drop the step and the file is unreferenced; delete the file and the step is dangling.

WHAT IT DOES NOT COVER, SAID OUT LOUD SO NOBODY RELIES ON IT FOR MORE. A commit that takes a
check, its step AND THIS FILE'S OWN STEP in one stale-tree overwrite still passes, because CI
config comes from the commit under test -- a repo cannot hold a guard its own PR cannot remove.
The only thing that caught #97 was a person reading main's diff after the merge, and that is
still the backstop. What this closes is the much likelier half: ONE of the two halves going
missing, in either direction, including the forward case nobody has been burnt by yet -- a new
`art/check_*.py` landing wired to nothing, which is silent for exactly as long as it takes
someone to assume it is running.

Exit codes match the other art checks: 0 green, 1 the sets disagree, 2 NO VERDICT (something it
needs is not where it expects), which fails the job rather than passing quietly.
"""
import re
import sys
from pathlib import Path

ART = Path(__file__).resolve().parent
ROOT = ART.parent.parent
WORKFLOW = ROOT / ".github/workflows/build.yml"

# This file is the one check that is ABOUT the wiring rather than about the art, so requiring it
# to be wired is not circular -- it is wired, and if its own step goes missing the remaining
# checks lose their cross-reference silently. It is listed here because the set below is "checks
# this script expects CI to name", and that includes itself.
SELF = Path(__file__).name


def main() -> int:
    if not WORKFLOW.exists():
        print("NO VERDICT: no workflow at %s" % WORKFLOW, file=sys.stderr)
        return 2
    present = {p.name for p in sorted(ART.glob("check_*.py"))}
    if not present:
        # The glob matching nothing means this script is looking in the wrong directory, not that
        # the repo has no checks -- it is sitting in that directory.
        print("NO VERDICT: no check_*.py beside me in %s" % ART, file=sys.stderr)
        return 2

    text = WORKFLOW.read_text()
    # THE TWO DIRECTIONS ASK DIFFERENT QUESTIONS, SO THEY MATCH DIFFERENTLY, and conflating them
    # cost a red build the first time a `check_*.py` lived anywhere but here (ASSA-282 put one in
    # `client/tools/`). A bare-filename grep reported `DANGLING IN CI: build.yml names
    # art/check_tools_declare_ci.py and there is no such file` -- about a file that exists, is run
    # by CI, and was never claimed to be in `art/`. The name was right and the directory was
    # invented by this check.
    #
    #   UNRUN (a check here that CI does not run) is GENEROUS: any mention of the filename counts
    #   as naming it. A step that invokes one through a variable or a shell script still runs it,
    #   and a false "NOT RUN" would send someone to add a step that already exists.
    #
    #   DANGLING (CI names a check that is not there) is STRICT: only an `art/`-pathed reference
    #   counts, because that is the only kind this directory can be missing. A check somewhere
    #   else in the tree is not this check's business.
    #
    # Each direction's wrong answer is the one the other rule would produce.
    named_anywhere = set(re.findall(r"check_[A-Za-z0-9_]+\.py", text))
    named_here = set(re.findall(r"art/(check_[A-Za-z0-9_]+\.py)", text))

    unrun = sorted(present - named_anywhere)
    dangling = sorted(named_here - present)

    for name in unrun:
        print("NOT RUN BY CI: art/%s exists and no step in build.yml names it" % name)
    for name in sorted(dangling):
        print("DANGLING IN CI: build.yml names art/%s and there is no such file" % name)

    if unrun or dangling:
        print(
            "\n%d check(s) in the tree, %d named by CI as art/. A check and its step must land "
            "and leave together." % (len(present), len(named_here))
        )
        return 1

    print(
        "%d art checks, all named by build.yml: %s" % (len(present), ", ".join(sorted(present)))
    )
    if SELF not in present:
        # Unreachable while this file is the one globbing, and it says so rather than asserting
        # a tautology: if the glob ever stops seeing its own directory, exit 2 above fires first.
        print("NO VERDICT: I did not find myself", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
