#!/usr/bin/env python3
"""EVERY `client/tools/*.gd` SAYS WHETHER A GATE RUNS IT, AND THE TREE AGREES (ASSA-282).

    python3 client/tools/check_tools_declare_ci.py

No Godot, no network, no Pillow: it reads the workflow, the scripts the workflow names, and the
header of every tool, and compares what each file CLAIMS against what is actually wired.

WHY THIS EXISTS, AS THE FAILURE IT CAME FROM. `art/check_ci_runs_every_check.py` can ask its
question with a set difference because `art/check_*.py` has ONE class: every check should run.
`client/tools/` has two, and most of it SHOULD stay local -- the `maren_*` shots answer one
design question each, `nacre_tab_budget_probe.gd` measures a fold that reads 0 px headless and
must never be wired up, `window_shot.gd` writes a blank frame under `--headless` and reports
success. So "is this tool in CI?" has no right answer from outside the file, and until now the
two classes were indistinguishable from the tree: 4 of 45 ran in a gate, 32 printed an `X OK`
marker nothing greps, and "`hud_probe.gd` has never run in CI" was discoverable only by grepping
a 79 KB YAML by hand, weeks after the probe was written.

So the FILE carries the answer and this script holds it to it, in both directions: a tool that
says `gated` and is wired to nothing is red, and a tool that says `local` while a gate runs it is
red too -- the stale-declaration case, which is the one that rots quietly after somebody wires a
probe up and does not edit its header.

**REACHABILITY, NOT A GREP OF THE WORKFLOW, AND THAT DISTINCTION IS NOT THEORETICAL.** The first
version of this asked "does build.yml contain this filename". It would have called `hud_probe.gd`
UNGATED -- the probe this whole item was found while building -- because the gate runs
`sim-game/tools/hud_in_a_gate.sh` and the shell script runs the probe. A tool is gated when it is
reachable from a non-comment workflow line, through however many named scripts it takes.

**AND COMMENTS DO NOT COUNT, which is the other half of the same mistake.** `window_shot.gd` is
named in `build.yml` -- inside a comment explaining why nothing runs it. A check satisfied by a
line other than the one it is about is a check that is strongest where the bug is least likely.
YAML comment lines are stripped before anything is searched, and `client/tools/` is the one
directory this reads: a tool named in a comment reads as not run, which is the truth.

THREE CLASSES, because two would force a false declaration on three files:

  `# CI: gated`            a gate runs it. Must be reachable, and must `extends SceneTree`.
  `# CI: local -- reason`  nothing runs it and that is deliberate. Must NOT be reachable, must
                           `extends SceneTree`, and the reason may not be empty.
  `# CI: library`          not a script you run at all -- `button_play.gd`, `demo_plan.gd` and
                           `session_plan.gd` are `class_name` libraries the tools import. Must
                           NOT `extends SceneTree`, so the claim is cross-examined rather than
                           believed.

That last column is the point. A free-text reason nobody checks is a comment; every declaration
here carries at least one claim this script can measure against the file itself, so a wrong
declaration is caught by machine and only the WORDING rests on the author.

WHAT IT DOES NOT COVER, said out loud. It cannot tell a tool that is wired and BROKEN from one
that is wired and working -- that is the job of the gate step itself -- and like its `art/`
counterpart it cannot survive a commit that removes a tool, its step and this check's own step
together. What it closes is the likelier half: a declaration and the wiring drifting apart in
either direction.

Exit codes match the other checks: 0 green, 1 the tree and the declarations disagree, 2 NO
VERDICT (something it needs is not where it expects), which fails the job rather than passing.
"""
import re
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent.parent.parent
WORKFLOW = ROOT / ".github/workflows/build.yml"
SIM_GAME = TOOLS.parent.parent

GATED, LOCAL, LIBRARY = "gated", "local", "library"
# The declaration, anywhere in a tool's header. `--` separates the class from its reason because
# that is the separator every docstring in this directory already uses for an aside.
DECLARATION = re.compile(r"^#+\s*CI:\s*(\w+)\s*(?:--\s*(.*))?$")
# How far in to look. Every tool in here opens with `extends SceneTree` and a docstring; 40 lines
# is past the usage block of the longest of them and short of anything that could mention `CI:`
# in passing.
HEADER_LINES = 40
# This check is ABOUT the wiring, so requiring CI to name it is not circular -- it is wired, and
# if its own step goes missing the declarations stop being held to anything.
SELF = Path(__file__).name


def uncommented(text):
    """The workflow with its comment lines removed.

    Line-level and not token-level on purpose: a `#` inside a shell command is not a YAML comment
    and stripping to end-of-line would eat real `run:` content.
    """
    return "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))


def gate_text():
    """Everything a gate actually executes: the workflow, plus the scripts it names, transitively.

    Returns None when the workflow is missing, which is a NO VERDICT and not a pass.
    """
    if not WORKFLOW.exists():
        return None
    # SELF IS SKIPPED, and not as tidiness: build.yml names this file, so without it this
    # script's own prose about which tools are local would read as the gate running them.
    seen, pending, out = {"client/tools/%s" % SELF}, [uncommented(WORKFLOW.read_text())], []
    while pending:
        text = pending.pop()
        out.append(uncommented(text))
        # ONLY WHAT A STEP ACTUALLY INVOKES, and only by the path it was written with. Resolving
        # a bare filename with `rglob` was the first cut and it dragged in every script in the
        # tree that any followed file happened to mention, so `rules_refusal_check.sh` -- which
        # no workflow names -- became "the gate" and took `join_probe.gd` with it. A reference
        # with no directory in it is prose.
        for rel in re.findall(r"[\w.-]+/[\w./-]+\.(?:sh|py)", uncommented(text)):
            if rel in seen:
                continue
            seen.add(rel)
            for base in (ROOT, SIM_GAME):
                found = base / rel
                if found.is_file():
                    pending.append(found.read_text())
                    break
    return "\n".join(out)


def reaches(gate, name):
    """Does the gate text RUN `client/tools/<name>`, as opposed to mentioning it?

    **A PATH, NOT A BARE FILENAME, AND THIS CHECK TAUGHT ME WHY BY FAILING ON ITSELF.** The first
    run reported `window_shot.gd`, `nacre_tab_budget_probe.gd` and all three libraries as wired
    up. They are: in the prose of THIS FILE, which `build.yml` names and `gate_text` therefore
    reads. A docstring explaining why a tool is local is not a step that runs it.

    `client/tools/x.gd` is how a shell step names one and `res://tools/x.gd` is how Godot does, so
    those two are the invocation and everything else is talk. `SELF` is skipped above as well --
    belt and braces, because the day this file stops being the only one that lists tool names in
    prose, the path rule is what still holds.
    """
    return ("client/tools/%s" % name) in gate or ("res://tools/%s" % name) in gate


def declaration_of(path):
    """`(klass, reason)` for a tool, or `(None, None)` when it declares nothing."""
    for line in path.read_text().splitlines()[:HEADER_LINES]:
        found = DECLARATION.match(line.strip())
        if found:
            return found.group(1).lower(), (found.group(2) or "").strip()
    return None, None


def main():
    gate = gate_text()
    if gate is None:
        print("NO VERDICT: no workflow at %s" % WORKFLOW, file=sys.stderr)
        return 2
    tools = sorted(TOOLS.glob("*.gd"))
    if not tools:
        # The glob matching nothing means this script is looking in the wrong directory, not that
        # the repo has no tools -- it is sitting in that directory.
        print("NO VERDICT: no *.gd beside me in %s" % TOOLS, file=sys.stderr)
        return 2
    if SELF not in gate:
        print("NO VERDICT: CI does not name %s, so nothing holds these declarations to the\n"
              "tree -- the hole art/check_ci_runs_every_check.py was written to close." % SELF,
              file=sys.stderr)
        return 2

    bad, counts = [], {GATED: 0, LOCAL: 0, LIBRARY: 0}
    for path in tools:
        klass, reason = declaration_of(path)
        reachable = reaches(gate, path.name)
        is_scene_tree = path.read_text().lstrip().startswith("extends SceneTree")
        if klass is None:
            bad.append("%s declares nothing. Add `# CI: gated`, `# CI: local -- <why not>` or\n"
                       "      `# CI: library` to its header." % path.name)
            continue
        if klass not in counts:
            bad.append("%s declares `# CI: %s`, which is not one of gated/local/library."
                       % (path.name, klass))
            continue
        counts[klass] += 1
        if klass == GATED and not reachable:
            bad.append("%s says `gated` and NOTHING in CI reaches it -- not build.yml, not any\n"
                       "      script build.yml names. Either wire it up or say `local`."
                       % path.name)
        if klass == LOCAL and reachable:
            bad.append("%s says `local` and CI reaches it. The declaration went stale when\n"
                       "      somebody wired it up; say `gated`." % path.name)
        if klass == LOCAL and not reason:
            bad.append("%s says `local` with no reason. `local` is a decision, and a decision\n"
                       "      with no reason is the thing this check exists to stop." % path.name)
        if klass == LIBRARY and is_scene_tree:
            bad.append("%s says `library` and `extends SceneTree`, so it IS a script somebody\n"
                       "      can run. Say `gated` or `local`." % path.name)
        if klass in (GATED, LOCAL) and not is_scene_tree:
            bad.append("%s says `%s` but does not `extends SceneTree`, so there is nothing to\n"
                       "      run. Say `library`." % (path.name, klass))
        if klass == LIBRARY and reachable:
            bad.append("%s says `library` and CI reaches it by name." % path.name)

    # THE OTHER DIRECTION, and the one #97 taught this repo: a step naming a script that is not
    # there. `art/check_ci_runs_every_check.py` catches it for checks; nothing did for tools.
    present = {p.name for p in tools}
    for name in sorted(set(re.findall(r"[\w-]+\.gd", gate))):
        if reaches(gate, name) and name not in present:
            bad.append("CI names client/tools/%s and no such file exists." % name)

    print("  %d tools: %d gated, %d local, %d library"
          % (len(tools), counts[GATED], counts[LOCAL], counts[LIBRARY]))
    for path in tools:
        klass, _ = declaration_of(path)
        if klass == GATED:
            print("    gated   %s" % path.name)
    if bad:
        print("\nVERDICT: FAIL (exit 1)")
        for line in bad:
            print("  - %s" % line)
        return 1
    print("\nVERDICT: PASS (exit 0). Every tool says whether a gate runs it, and every claim\n"
          "  agrees with the workflow and with the file itself.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
