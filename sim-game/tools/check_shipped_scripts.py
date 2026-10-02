#!/usr/bin/env python3
"""Nothing the shipped client runs may depend on a script the export leaves out (ASSA-51).

WHY THIS EXISTS, in one measured failure. `scripts/main.gd` called
`AssayDemoPlan.held(...)`, and `AssayDemoPlan` is declared in `client/tools/demo_plan.gd`. Both
export presets carry `exclude_filter="tests/*, tools/*"`, so the shipped pack contained no such
class. The exported client could not parse `main.gd`, never reached `_ready`, never wrote the
selfcheck marker, and never exited -- so CI's "The exported client runs" step waited on a process
that would never finish. Six commits' bundles hung for about an hour each, on macOS runners that
bill at ten times the Linux rate, and no zip could leave main.

Every suite we had stayed green, and that is the point: the GDScript tests and
`check_every_script.sh` run against the SOURCE TREE, where `tools/` is present. Only the export
removes it, so only the export could fail, and the export's failure mode was a hang rather than an
error. A check that reads the presets is the only cheap thing that catches it.

Stdlib only, runs in well under a second, and belongs in "Test and lint" rather than the bundle
jobs: the whole point is to be red in eighty seconds instead of hung for six hours.
"""

import re
import sys
from pathlib import Path

CLIENT = Path(__file__).resolve().parent.parent / "client"
PRESETS = CLIENT / "export_presets.cfg"

CLASS_NAME = re.compile(r"^\s*class_name\s+([A-Za-z_]\w*)")


def strip_comment(line: str) -> str:
    """The line with any GDScript comment removed.

    A doc comment that merely NAMES an excluded class is not a dependency on it -- this file's own
    docstring names `AssayDemoPlan` -- so scanning raw text would report the explanation of the bug
    as the bug. Quotes are tracked so a `#` inside a string is not mistaken for a comment.
    """
    quote = ""
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            return line[:i]
    return line


def excluded_globs() -> list[str]:
    """The exclude patterns of every preset, union.

    A file excluded by ANY preset is treated as not shipped: one platform missing a class is a
    broken bundle on that platform, which is exactly the failure this catches.
    """
    text = PRESETS.read_text()
    modes = re.findall(r'export_filter="([^"]*)"', text)
    if not modes:
        sys.exit(f"{PRESETS}: no export_filter found; this check cannot tell what ships")
    # THE CHECK'S OWN ASSUMPTION, ASSERTED. With "all_resources" the pack is everything in the
    # project minus the exclude filter, which is what the logic below models. Any other mode
    # (a scene-driven filter, an include list) means the model is wrong, and a check that is
    # quietly wrong is worse than no check.
    wrong = [m for m in modes if m != "all_resources"]
    if wrong:
        sys.exit(
            f"{PRESETS}: export_filter is {wrong}, not 'all_resources'. "
            "This check models the pack as 'project minus exclude_filter'; teach it the new mode."
        )
    globs: list[str] = []
    for raw in re.findall(r'exclude_filter="([^"]*)"', text):
        for part in raw.split(","):
            # Deduplicated only so the message reads: the presets normally
            # carry identical filters, and "tools/*, tools/*" invites the
            # reader to wonder whether that means something.
            if part.strip() and part.strip() not in globs:
                globs.append(part.strip())
    return globs


def main() -> int:
    globs = excluded_globs()
    if not globs:
        print("check_shipped_scripts: no exclude_filter, so everything ships. OK")
        return 0

    # Where each class_name is declared, and whether that file ships.
    declared: dict[str, Path] = {}
    scripts: list[tuple[Path, bool]] = []
    for path in sorted(CLIENT.rglob("*.gd")):
        rel = path.relative_to(CLIENT)
        if ".godot" in rel.parts:
            continue
        shipped = not any(rel.match(g) for g in globs)
        scripts.append((path, shipped))
        for line in path.read_text().splitlines():
            found = CLASS_NAME.match(line)
            if found:
                declared[found.group(1)] = rel
                break

    missing = {
        name: rel
        for name, rel in declared.items()
        if any(rel.match(g) for g in globs)
    }
    if not missing:
        print("check_shipped_scripts: no class_name is declared outside the pack. OK")
        return 0

    problems: list[str] = []
    for path, shipped in scripts:
        if not shipped:
            continue
        rel = path.relative_to(CLIENT)
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = strip_comment(line)
            for name, home in sorted(missing.items()):
                if re.search(rf"\b{re.escape(name)}\b", code):
                    problems.append(
                        f"{rel}:{number}: uses {name}, declared in {home}, "
                        f"which the export excludes"
                    )

    if problems:
        print("THE SHIPPED CLIENT DEPENDS ON SCRIPTS THE EXPORT LEAVES OUT.")
        print("The exported client will fail to parse and the selfcheck step will HANG.\n")
        for problem in problems:
            print(f"  {problem}")
        print(
            f"\nExcluded by {PRESETS.name}: {', '.join(globs)}"
            "\nMove what the shipped code needs into a directory that ships."
        )
        return 1

    print(
        f"check_shipped_scripts: {len(missing)} class(es) outside the pack "
        f"({', '.join(sorted(missing))}), none referenced by shipped scripts. OK"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
