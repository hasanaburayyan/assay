#!/usr/bin/env python3
"""A CHANGE MUST NOT QUIETLY PUT A FILE BACK THE WAY IT WAS (ASSA-75).

    python3 tools/revert_guard.py                     # before you open a PR
    python3 tools/revert_guard.py --base X --head Y    # any two revisions

Git only: no network, no Godot, no dependencies. Exit 0 green, 1 a finding,
2 NO VERDICT (something it needs is not where it expects), which fails a job
rather than passing quietly.

WHY THIS EXISTS, AS THE FAILURE IT CAME FROM -- MINE. I squashed ASSA-68 with
`git reset --soft origin/main` after a `git fetch` had moved that ref from my
branch's base (1e0641d) to a712be6, which was Limpet's #95. `reset --soft`
moves HEAD and nothing else, so the index still held the OLD tree plus my two
edits. The commit I pushed had a712be6 as its parent and a tree without it: a
byte-exact revert of ten files, including a CI guard and its own step, which is
why main then went green while drawing pack icons at the wrong scale.

**`git status` and `git diff` were both clean.** The index was exactly what I
had asked for. And 'Test and lint' could not see it: #95 was GDScript, Python
and workflow, so the Rust gate passed on a tree that had thrown it away. That
is the gap this closes -- Limpet's words for it: *"main is green" and "main
contains what we merged" are different claims, and only the first is
automated.*

TWO RULES, BOTH ANSWERABLE FROM GIT ALONE, so this does not care which hand
movement produced the stale tree -- `reset --soft`, a stash restore, a bad
conflict resolution or a full-tree copy all land the same way here:

  1. NO RESURRECTION. A file's new content must not equal a blob that same
     file already had before the base. Seven of my ten files went back to
     their 1e0641d blobs; that is this rule, caught at PR time.
  2. DELETIONS ARE DECLARED. Every path the change deletes must be named in a
     commit message on the branch (or in the PR body). My #97 deleted three
     files and said nothing about any of them. A healthy PR deletes files on
     purpose and can afford one sentence.

THE ESCAPE HATCH IS TO SAY WHAT YOU DID. Naming the path in a commit message
clears either rule -- there is no flag to pass and nothing to configure. Rule
1 has a real innocent case that needs it: a regenerated art sheet can come out
byte-identical to an older blob (Limpet hit exactly that re-rendering
`pack_icons.png`), and the fix is one line in the commit message saying it was
regenerated.

WHAT IT DOES NOT COVER, said here rather than discovered later. A commit that
takes this script AND its CI step in one stale-tree overwrite still passes,
because CI config comes from the commit under test: a repo cannot hold a guard
its own PR cannot remove. Limpet wrote that about their wiring check and it is
just as true of this one. What it closes is the likely half -- an ACCIDENT, and
an accident does not usually also delete the one instrument that would catch
it. #97 took Limpet's art guard only because that file happened to sit inside
#95's diff. A person reading main's diff after a merge is still the backstop,
and that person is how #97 was found at all.

NOT AN ARGUMENT ABOUT DECISION #39. "Require branches to be up to date" would
not have caught this: my branch *was* up to date with main. The index was not.

It is deliberately NOT named `check_*.py`: `art/check_ci_runs_every_check.py`
holds the set of `art/check_*.py` files equal to the set `build.yml` names, so
a repo-wide guard borrowing that prefix from another directory would read to it
as a step naming a file that does not exist. One convention, one directory.
"""

import argparse
import os
import subprocess
import sys

# Rule 2 reads these for an intent to delete, in this order, and stops at the
# first that names the path. The PR body comes from the workflow; locally there
# is none, which is correct -- what you can say locally is a commit message.
PR_BODY_ENV = ("PR_BODY", "REVERT_GUARD_BODY")


class NoVerdict(Exception):
    """Something this needs is not where it expects. Never a silent pass."""


def git(*args: str) -> str:
    proc = subprocess.run(
        ("git",) + args, capture_output=True, text=True, cwd=repo_root()
    )
    if proc.returncode != 0:
        raise NoVerdict("git %s failed: %s" % (" ".join(args), proc.stderr.strip()))
    return proc.stdout


_ROOT = None


def repo_root() -> str:
    global _ROOT
    if _ROOT is None:
        proc = subprocess.run(
            ("git", "rev-parse", "--show-toplevel"), capture_output=True, text=True
        )
        if proc.returncode != 0:
            raise NoVerdict("not inside a git work tree")
        _ROOT = proc.stdout.strip()
    return _ROOT


def parents(rev: str) -> list[str]:
    return git("rev-list", "--parents", "-n", "1", rev).split()[1:]


def pick_base(head: str) -> tuple[str, str]:
    """The revision `head` is judged against, and why it was chosen.

    Three cases, and which one ran is printed, because a guard that silently
    compared the wrong pair would be the very thing it is here to prevent.
    """
    ps = parents(head)
    if len(ps) >= 2:
        # A `pull_request` checkout is a merge of the PR into the base branch,
        # so the first parent IS main's tip and the diff against it is exactly
        # this PR's effect on main.
        return ps[0], "first parent of the PR merge commit"
    if os.environ.get("GITHUB_EVENT_NAME") == "push" and ps:
        # On a push to main, HEAD is the squash commit that just landed. Same
        # question, asked after the fact: this is the post-merge half.
        return ps[0], "parent of the commit just pushed"
    if not ps:
        raise NoVerdict("%s is a root commit; nothing to compare against" % head)
    for ref in ("origin/main", "main"):
        proc = subprocess.run(
            ("git", "merge-base", ref, head),
            capture_output=True,
            text=True,
            cwd=repo_root(),
        )
        if proc.returncode == 0:
            return proc.stdout.strip(), "merge base with %s" % ref
    raise NoVerdict("no origin/main or main to find a merge base with")


def changed(base: str, head: str) -> list[tuple[str, str, str]]:
    """(status, path, new_blob) per file. Renames are resolved, not reported."""
    # `--abbrev=40` is load-bearing: `--raw` abbreviates blob shas to 7 by
    # default, and rule 1 compares them against the full shas `cat-file` gives.
    # Without it that rule can never match and the guard looks healthy because
    # the deletion rule still fires. Found by running this against the real #97
    # and reading the output instead of the exit code.
    raw = git(
        "diff", "--raw", "-z", "--abbrev=40", "--find-renames", "%s..%s" % (base, head)
    )
    fields = raw.split("\0")
    out = []
    i = 0
    while i < len(fields):
        meta = fields[i]
        if not meta.startswith(":"):
            i += 1
            continue
        parts = meta.split()
        # :<old mode> <new mode> <old sha> <new sha> <status>
        if len(parts) < 5:
            raise NoVerdict("cannot read diff record %r" % meta)
        new_blob, status = parts[3], parts[4]
        if status.startswith("R") or status.startswith("C"):
            # A rename carries two paths and is not a deletion of the old one.
            i += 3
            continue
        path = fields[i + 1]
        out.append((status, path, new_blob))
        i += 2
    return out


def earlier_blobs(base: str, path: str) -> dict[str, str]:
    """blob -> the commit it came from, for every version of `path` strictly
    before `base`. `base`'s own version is excluded: matching it is not a
    resurrection, it is a no-op the diff would not have listed."""
    revs = git("rev-list", base, "--", path).split()
    if not revs:
        return {}
    want = ["%s:%s" % (rev, path) for rev in revs[1:]]
    if not want:
        return {}
    proc = subprocess.run(
        ("git", "cat-file", "--batch-check"),
        input="\n".join(want) + "\n",
        capture_output=True,
        text=True,
        cwd=repo_root(),
    )
    if proc.returncode != 0:
        raise NoVerdict("git cat-file failed: %s" % proc.stderr.strip())
    found = {}
    for rev, line in zip(revs[1:], proc.stdout.splitlines()):
        bits = line.split()
        # "<sha> blob <size>", or "<name> missing" when the path did not exist
        # in that commit, which is normal and not an error.
        if len(bits) >= 2 and bits[1] == "blob":
            found.setdefault(bits[0], rev)
    return found


def declared(path: str, prose: str) -> bool:
    """Did whoever wrote this change SAY they touched this path?

    A SIDECAR COUNTS AS DECLARED WHEN ITS OWNER IS. Godot writes `x.gd.uid`
    beside `x.gd` and nobody writing prose mentions both; the first real
    restore this ran against -- Limpet's #100, which names ten files honestly
    -- was flagged for `inventory.gd.uid` alone. So one suffix is dropped and
    tried again. Only one: stripping down to a bare `inventory` would let the
    word clear the file, which is not the same as saying you touched it.
    """
    name = os.path.basename(path)
    for candidate in (path, name, name.rsplit(".", 1)[0] if name.count(".") > 1 else None):
        if candidate and candidate in prose:
            return True
    return False


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--base", help="revision to judge against (default: see pick_base)")
    ap.add_argument("--head", default="HEAD")
    args = ap.parse_args()

    head = git("rev-parse", args.head).strip()
    if args.base:
        base, why = git("rev-parse", args.base).strip(), "given on the command line"
    else:
        base, why = pick_base(head)

    prose = git("log", "--format=%B", "%s..%s" % (base, head))
    for name in PR_BODY_ENV:
        prose += "\n" + os.environ.get(name, "")

    files = changed(base, head)
    print(
        "revert_guard: %s..%s (%s), %d file(s) changed"
        % (base[:9], head[:9], why, len(files))
    )

    findings = []
    for status, path, new_blob in files:
        if status.startswith("D"):
            if not declared(path, prose):
                findings.append(
                    "DELETED AND NOT DECLARED: %s\n"
                    "    Nothing in this change's commit messages names it. If the deletion is\n"
                    "    meant, say so in the message. If it is not, your tree is stale: compare\n"
                    "    `git diff --stat %s...HEAD` against what you actually edited."
                    % (path, base[:9])
                )
            continue
        if declared(path, prose):
            continue
        older = earlier_blobs(base, path)
        where = older.get(new_blob)
        if where:
            findings.append(
                "PUT BACK AS IT WAS: %s\n"
                "    Its new content is byte-identical to the version in %s, which is older\n"
                "    than the base. If you meant to revert it, name the file in the commit\n"
                "    message (a regenerated file that comes out identical counts). If you did\n"
                "    not, this change is carrying a stale tree and is throwing away whatever\n"
                "    landed in between." % (path, where[:9])
            )

    if findings:
        print("")
        for f in findings:
            print(f)
        print(
            "\n%d finding(s). A green test run says main WORKS; it does not say main still\n"
            "CONTAINS what was merged. That is the gap this stands in." % len(findings)
        )
        return 1

    print("revert_guard: nothing put back, nothing deleted without saying so.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except NoVerdict as e:
        print("NO VERDICT: %s" % e, file=sys.stderr)
        sys.exit(2)
