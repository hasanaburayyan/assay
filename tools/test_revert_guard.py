#!/usr/bin/env python3
"""THE FIRST TEST `revert_guard.py` HAS EVER HAD (ASSA-250).

    python3 tools/test_revert_guard.py              # the guard beside me
    python3 tools/test_revert_guard.py /tmp/old.py  # any copy of the guard

Git and the stdlib only: it builds throwaway repositories in a temp directory
and runs the guard against them as a subprocess, so every assertion is about
the exit code and the words a reader of a red CI log actually sees.

WHY IT EXISTS, AS THE FAILURE IT CAME FROM -- MINE, TWICE IN ONE AFTERNOON.
`revert_guard.py` shipped with no test: the only thing exercising it was CI
running it against the real repo, which means it was only ever asked about
trees that happened to exist. #323 and #330 both went GREEN as pull requests
and RED on main sixteen seconds after merging, on the same generated theme
file, and the second red stood unnamed for three hours. One variable: the
guard reads `PR_BODY`, GitHub only sets it on a `pull_request` event, and the
push run that judges the squash commit sees an empty string. The sentence that
cleared #330 was not even meant as a declaration -- it was a line about a
different CI step that happened to contain the basename.

THE SECOND ARGUMENT FOR THE PATH ARGUMENT. `python3 tools/test_revert_guard.py
<a copy of the old guard>` is how "this test fails on the shipped code" stops
being a claim. Case 1's body-only arm is the lever: it exits 0 on the guard
main carried before this landed and 1 after.

NOT NAMED `check_*.py` ON PURPOSE. `art/check_ci_runs_every_check.py` holds
the set of `art/check_*.py` files equal to the set `build.yml` names, so a
`tools/check_revert_guard.py` step would read to it as a step naming a file
that does not exist. One convention, one directory -- the same reason the
guard itself avoids that prefix.

Exit 0 green, 1 an assertion failed, 2 NO VERDICT (the fixture or git is not
where this expects), which fails a job rather than passing quietly.
"""

import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_GUARD = os.path.join(HERE, "revert_guard.py")

FIXTURE_ENV = {
    "GIT_AUTHOR_NAME": "revert_guard fixture",
    "GIT_AUTHOR_EMAIL": "fixture@r2ts.local",
    "GIT_COMMITTER_NAME": "revert_guard fixture",
    "GIT_COMMITTER_EMAIL": "fixture@r2ts.local",
    # A fixture must not inherit the developer's commit template, hooks or
    # includes: this test is about the guard, not about anyone's ~/.gitconfig.
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_SYSTEM": os.devnull,
}


class NoVerdict(Exception):
    """The fixture could not be built. Never a silent pass."""


def git(repo: str, *args: str) -> str:
    env = dict(os.environ)
    env.update(FIXTURE_ENV)
    proc = subprocess.run(
        ("git",) + args, cwd=repo, capture_output=True, text=True, env=env
    )
    if proc.returncode != 0:
        raise NoVerdict(
            "fixture: git %s failed: %s" % (" ".join(args), proc.stderr.strip())
        )
    return proc.stdout.strip()


def write(repo: str, path: str, text: str) -> None:
    with open(os.path.join(repo, path), "w") as fh:
        fh.write(text)


def commit(repo: str, message: str) -> str:
    git(repo, "add", "-A")
    git(repo, "commit", "--quiet", "-m", message)
    return git(repo, "rev-parse", "HEAD")


def run_guard(guard: str, repo: str, base: str, head: str, body: str = None):
    """(exit code, everything printed). `body` is the PR body, or None for a
    push run, which is the difference this whole file is about."""
    env = dict(os.environ)
    for name in ("PR_BODY", "REVERT_GUARD_BODY", "GITHUB_EVENT_NAME"):
        env.pop(name, None)
    if body is not None:
        env["PR_BODY"] = body
    proc = subprocess.run(
        [sys.executable, guard, "--base", base, "--head", head],
        cwd=repo,
        capture_output=True,
        text=True,
        env=env,
    )
    return proc.returncode, proc.stdout + proc.stderr


class Results:
    def __init__(self):
        self.failures = []
        self.checks = 0

    def expect(self, label: str, got, want) -> bool:
        self.checks += 1
        if got == want:
            print("  ok   %s" % label)
            return True
        print("  FAIL %s\n       wanted %r\n       got    %r" % (label, want, got))
        self.failures.append(label)
        return False

    def expect_in(self, label: str, needle: str, haystack: str) -> bool:
        self.checks += 1
        if needle in haystack:
            print("  ok   %s" % label)
            return True
        print(
            "  FAIL %s\n       no %r in the output:\n%s"
            % (label, needle, "\n".join("       | " + x for x in haystack.splitlines()))
        )
        self.failures.append(label)
        return False


BODY_ONLY = "DECLARED IN THE PR BODY ONLY"
PUT_BACK = "PUT BACK AS IT WAS"
UNDECLARED_DELETE = "DELETED AND NOT DECLARED"
ALL_CLEAR = "nothing put back, nothing deleted without saying so"


def case_resurrection(guard: str, repo: str, r: Results) -> None:
    """THE CASE THE AFTERNOON ACTUALLY HAD, with its control in the fixture.

    A..B..A on one generated file, then TWO heads with BYTE-IDENTICAL TREES
    that differ only in where the sentence naming the file sits. Three arms off
    one base: nothing names it, a commit message names it, only the PR body
    names it. If all three gave the same verdict this test would be asserting
    nothing, so the trees are compared first and the three verdicts have to
    differ from each other.
    """
    print("CASE 1 rule 1, a generated file put back as it was")
    git(repo, "init", "--quiet")
    write(repo, "gen.txt", "A\n")
    write(repo, "unrelated.txt", "a file nothing in this test touches\n")
    commit(repo, "the first version of the generated file")
    write(repo, "gen.txt", "B\n")
    base = commit(repo, "regenerate it: B")

    git(repo, "checkout", "--quiet", "-b", "quiet", base)
    write(repo, "gen.txt", "A\n")
    quiet_head = commit(repo, "a ruling was reversed, so the constant comes back")

    git(repo, "checkout", "--quiet", "-b", "declared", base)
    write(repo, "gen.txt", "A\n")
    named_head = commit(
        repo, "a ruling was reversed: gen.txt regenerates to its older bytes"
    )

    # The control's own control. Two heads that did not carry the same tree
    # would make the comparison below meaningless, and nothing else here would
    # notice.
    r.expect(
        "the two heads carry byte-identical trees, so the only variable is the prose",
        git(repo, "rev-parse", "%s^{tree}" % quiet_head),
        git(repo, "rev-parse", "%s^{tree}" % named_head),
    )

    code, out = run_guard(guard, repo, base, quiet_head)
    r.expect("nothing names it: exit 1", code, 1)
    r.expect_in("nothing names it: says PUT BACK AS IT WAS", PUT_BACK, out)
    r.expect_in("nothing names it: names the path", "gen.txt", out)

    code_named, out_named = run_guard(guard, repo, base, named_head)
    r.expect("a commit message names it: exit 0", code_named, 0)
    r.expect_in("a commit message names it: all clear", ALL_CLEAR, out_named)

    # THE LEVER. Same tree as the arm above, same base; the declaration has
    # moved from the commit message to the PR body, which is the one place it
    # cannot reach main.
    code_body, out_body = run_guard(
        guard,
        repo,
        base,
        quiet_head,
        body="This PR regenerates gen.txt, and that is deliberate.",
    )
    r.expect("the PR body alone names it: exit 1", code_body, 1)
    r.expect_in("the PR body alone names it: %s" % BODY_ONLY, BODY_ONLY, out_body)
    r.expect_in(
        "and it says WHY the PR body is not enough",
        "empty on the push",
        out_body,
    )
    r.expect_in(
        "and it says what to do instead",
        "commit message",
        out_body,
    )
    # A PR-body-only declaration must not be reported as a stale tree: it is a
    # declaration in the wrong place, and telling the author their tree is
    # stale would send them to look for a bug that is not there.
    r.expect("the PR-body arm does not also cry stale tree", PUT_BACK in out_body, False)

    # THE THREE VERDICTS AS ONE CLAIM. This started out as "the three arms
    # disagree", which passed on the guard main carried before this landed --
    # (1, 0, 0) disagrees too. An assertion that takes either answer asserts
    # neither, so it says the triple.
    r.expect(
        "the verdicts: nothing names it 1, a commit message 0, the PR body 1",
        (code, code_named, code_body),
        (1, 0, 1),
    )


def case_deletion(guard: str, repo: str, r: Results) -> None:
    """RULE 2, WHOSE DOCSTRING USED TO ALLOW THE PR BODY IN SO MANY WORDS.

    The allowance is withdrawn for exactly the reason above, so it is asserted
    here rather than left as a sentence someone has to notice changed.
    """
    print("CASE 2 rule 2, a deleted file")
    git(repo, "init", "--quiet")
    write(repo, "doomed.gd", "func _ready():\n\tpass\n")
    write(repo, "unrelated.txt", "a file nothing in this test touches\n")
    commit(repo, "add the file this case deletes")
    write(repo, "unrelated.txt", "edited so the base is its own commit\n")
    base = commit(repo, "an unrelated edit")

    git(repo, "checkout", "--quiet", "-b", "quiet-delete", base)
    os.remove(os.path.join(repo, "doomed.gd"))
    quiet_head = commit(repo, "tidy up the client a little")

    git(repo, "checkout", "--quiet", "-b", "named-delete", base)
    os.remove(os.path.join(repo, "doomed.gd"))
    named_head = commit(repo, "delete doomed.gd: nothing has called it since ASSA-1")

    code, out = run_guard(guard, repo, base, quiet_head)
    r.expect("an undeclared deletion: exit 1", code, 1)
    r.expect_in("an undeclared deletion: the original wording", UNDECLARED_DELETE, out)

    code_named, out_named = run_guard(guard, repo, base, named_head)
    r.expect("a commit message names the deletion: exit 0", code_named, 0)
    r.expect_in("a commit message names the deletion: all clear", ALL_CLEAR, out_named)

    code_body, out_body = run_guard(
        guard, repo, base, quiet_head, body="Deletes doomed.gd, which nothing calls."
    )
    r.expect("the PR body alone names the deletion: exit 1", code_body, 1)
    r.expect_in(
        "the PR body alone names the deletion: %s" % BODY_ONLY, BODY_ONLY, out_body
    )
    r.expect(
        "and NOT the undeclared wording, because it WAS declared -- in the wrong place",
        UNDECLARED_DELETE in out_body,
        False,
    )


def case_plain_change(guard: str, repo: str, r: Results) -> None:
    """THE REGRESSION ARM. A change that resurrects nothing and deletes nothing
    declares nothing and stays green -- otherwise a guard that reddens on every
    PR would pass every case above."""
    print("CASE 3 an ordinary change, declaring nothing")
    git(repo, "init", "--quiet")
    write(repo, "gen.txt", "A\n")
    base = commit(repo, "the first version")
    write(repo, "gen.txt", "A\nand a line never seen in this file before\n")
    write(repo, "new.txt", "a path that has never existed\n")
    head = commit(repo, "ordinary work, named after nothing")

    code, out = run_guard(guard, repo, base, head)
    r.expect("an ordinary change: exit 0", code, 0)
    r.expect_in("an ordinary change: all clear", ALL_CLEAR, out)

    code_body, out_body = run_guard(
        guard, repo, base, head, body="A PR body that names gen.txt in passing."
    )
    r.expect(
        "a PR body naming a file with nothing wrong with it is still exit 0",
        code_body,
        0,
    )
    r.expect_in("...and still all clear", ALL_CLEAR, out_body)


def case_no_verdict(guard: str, repo: str, r: Results) -> None:
    """A guard that cannot answer must say so rather than pass."""
    print("CASE 4 a revision that does not exist")
    git(repo, "init", "--quiet")
    write(repo, "gen.txt", "A\n")
    head = commit(repo, "the only commit")

    code, out = run_guard(guard, repo, "0000000000000000000000000000000000000000", head)
    r.expect("an unresolvable base: exit 2, NO VERDICT", code, 2)
    r.expect_in("an unresolvable base: says NO VERDICT", "NO VERDICT", out)


def main() -> int:
    guard = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_GUARD
    if not os.path.exists(guard):
        print("NO VERDICT: no guard at %s" % guard, file=sys.stderr)
        return 2
    print("testing %s" % guard)

    r = Results()
    for case in (case_resurrection, case_deletion, case_plain_change, case_no_verdict):
        repo = tempfile.mkdtemp(prefix="revert_guard_fixture_")
        try:
            case(guard, repo, r)
        finally:
            shutil.rmtree(repo, ignore_errors=True)

    if r.failures:
        print(
            "\n%d of %d assertions failed: %s"
            % (len(r.failures), r.checks, "; ".join(r.failures))
        )
        return 1
    print("\n%d assertions, all green." % r.checks)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except NoVerdict as e:
        print("NO VERDICT: %s" % e, file=sys.stderr)
        sys.exit(2)
