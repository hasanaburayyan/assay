#!/usr/bin/env python3
"""ONE SPECIES PALETTE, HELD IN THREE FILES. This is the check that keeps them equal.

A species' colour has to be the same in two renderers: the Blender pipeline
multiplies it over the species-neutral ore sprite (`species_tints.py`), and the
Godot client fills a deposit on its map with it (`client/scripts/hud.gd`). The
length has to match a third file, `sim/src/tuning.rs`, where the sim decides how
many species a world rolls.

WHY THE DUPLICATION IS ALLOWED AND THE DRIFT IS NOT. A palette cannot live in
`sim`: the sim knows nothing of a renderer (repo CLAUDE.md principle 1). The
client has no asset pipeline to read a Python list through, and Godot cannot
import one. So the honest arrangement is Maren's: exactly ONE table, written down
twice, with a check that only Python can run because only Python can read both
files. Without it the two drift, and the drift is invisible until a colour-blind
player mis-sorts a hopper - there is no screen on which a wrong tint looks wrong.

Run it from anywhere; CI runs it in the `Test and lint` job. Exit 0 is agreement.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ART = Path(__file__).resolve().parent
SIM_GAME = ART.parent
HUD = SIM_GAME / "client" / "scripts" / "hud.gd"
TINTS = ART / "species_tints.py"
TUNING = SIM_GAME / "sim" / "src" / "tuning.rs"

# A #RRGGBB in either file. Upper-cased before comparing: Godot and Blender both
# read case-insensitively, so "#ff3333" is the same colour and not a drift.
HEX = re.compile(r"#[0-9A-Fa-f]{6}")


def fail(message: str) -> None:
    print(f"species tints: {message}", file=sys.stderr)
    sys.exit(1)


def one_list(path: Path, pattern: str) -> list[str]:
    """The colours in the one list `pattern` finds, in order.

    Scoped to the assignment rather than scanning the whole file, because both
    files are mostly prose about how the table was derived and that prose quotes
    colours. A docstring mentioning #FF3333 must not count as a slot.
    """
    if not path.is_file():
        fail(f"{path} is not there, so the tables cannot be compared")
    # MULTILINE as well as DOTALL: `^` without it anchors to the start of the
    # whole file, so the Python table's own pattern matched nothing and the check
    # failed loudly rather than passing quietly. It failing that way is luck, not
    # design -- a pattern that matches too MUCH is the version that passes blind.
    found = re.search(pattern, path.read_text(), re.DOTALL | re.MULTILINE)
    if not found:
        fail(f"no SPECIES_TINTS assignment in {path.name} (pattern: {pattern})")
    return [c.upper() for c in HEX.findall(found.group(1))]


def species_per_world() -> int:
    found = re.search(
        r"SPECIES_PER_WORLD\s*:\s*usize\s*=\s*(\d+)", TUNING.read_text()
    )
    if not found:
        fail(f"no SPECIES_PER_WORLD in {TUNING.name}")
    return int(found.group(1))


def main() -> None:
    art = one_list(TINTS, r"^SPECIES_TINTS\s*=\s*\[(.*?)\]")
    # `[^=\n]*` so the pattern survives the const's TYPE changing without
    # silently matching something else: it crosses `: Array[String] ` to reach
    # the `=` and cannot cross a line or a second `=`. It was pinned to
    # `PackedStringArray(` and CI caught me the first time I changed the const
    # and re-ran this check against the file as it had been, not as it was.
    hud = one_list(HUD, r"const SPECIES_TINTS[^=\n]*=\s*\[(.*?)\]")
    roster = species_per_world()

    if art != hud:
        fail(
            "the two tables disagree, so a species is one colour in the sprite "
            f"and another on the map.\n  {TINTS.name}: {art}\n  {HUD.name}: {hud}"
        )
    # A table SHORTER than the roster aliases two species onto one colour, and
    # the player it misleads is the one who cannot use colour anyway. A table
    # LONGER than the roster is dead slots, which is only untidy - but it also
    # means the derivation was run for a world that does not exist, and the
    # measured separation is then not the separation players get.
    if len(art) != roster:
        fail(
            f"{len(art)} tints for a roster of {roster} species "
            f"(sim/src/tuning.rs SPECIES_PER_WORLD). Rerun art/species_probe.py "
            f"for {roster} slots; do not pad or truncate the table by hand."
        )
    if len(set(art)) != len(art):
        fail(f"two species share a tint: {art}")

    print(f"species tints: {len(art)} slots, agreed in both files, {art}")


if __name__ == "__main__":
    main()
