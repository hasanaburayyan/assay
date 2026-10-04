#!/usr/bin/env python3
"""ground.png IS STILL ONE PICTURE, not sixty-four strangers (ASSA-115 box 2, ASSA-168).

    python3 art/check_ground_block.py

No Godot, no Pillow, no window, no network: `png_stdlib.read_rgba` and one imported bar, ~0.7s.

WHAT IT GUARDS. `manifest.ground.block == [8, 8]` declares the sixty-four 64 px rows of
`ground.png` to be the row-major cells of ONE continuous 8x8-tile picture, rendered from a single
Blender scene with the camera moved sixty-four times (`art/assets/ground.py`). The client relies
on that: `scene_view.gd::ground_row` places cell (x mod 8, y mod 8) at tile (x, y) BY POSITION,
because a patch crossing a cell boundary is the same object in both cells and the cells are
therefore not interchangeable. If the sheet is ever re-rendered as sixty-four independent images
while still declaring a block, every tile join in the game becomes a seam between strangers --
and nothing else in the tree notices. That is the whole reason this file exists: the sheet is
re-rendered by hand, and the judge that would catch it needs a window.

THE QUESTION, WHICH NEEDS NO SHOT. If the block claim is true then the join between cell (r, c)
and cell (r, c+1) is not an edge at all -- it is the middle of a render -- so the step across it
must sit among the steps between columns INTERIOR to a cell. Measured on the sheet at its native
64 px, with no camera, no downsample and no placement rule.

    SHIPPED      vertical Z -0.08 (rank 31 of 64)   horizontal Z +0.73 (rank 12 of 64)
    CONTROL      vertical Z +38.0 (rank  1 of 64)   horizontal Z +40.0 (rank  1 of 64)

THE BAR IS IMPORTED, NOT COPIED: `grid_findability.verdict`, the same 3-sd magnitude that judges
a window shot, so the sheet and the screen are held to one rule. A rank is printed and is NOT the
bar -- sixty-four offsets always have a rank 1, which is the defect that bar replaced (ASSA-162).

THE RED PATH RUNS ON EVERY PASS. The control above is not a number in this docstring, it is
measured each time: every cell on the dark squares of a checkerboard is lifted by `CONTROL_STEP`,
which puts a step across BOTH a left|right and an upper/lower join. That is the failure this check
exists for, performed. If the control does not go red the instrument is broken and this exits 2
rather than reporting a pass -- a green that has not been shown capable of being red says nothing.

    (The REALISTIC control -- shuffling the cells out of field order -- is the one that reads
    +67 / +49, and it is run by hand, not here. It is not used as the automatic control because it
    depends on a coincidence not happening: a shuffle can put a join back together, and one did,
    at Z +0.90. A control that can go green by luck is not a control. See `control()` below.)

AND IT CANNOT GO TO SLEEP. The block shape is read from the shipped manifest, not written here.
A manifest that stops declaring a block, or declares one the sheet cannot hold, exits 2: the
question this asks would be meaningless, and meaningless is not a pass. (Same guard, same
reason, as `test_scene_view.gd::test_a_ground_block_is_placed_by_position_and_not_by_hash`.)

WHAT IT DOES NOT COVER, said plainly so nobody relies on it for more. It reads the SHEET. It
cannot see the CLIENT change its mind -- swap `ground_row` back to hash-picking and this still
passes, because a check that shares a rule with the thing it checks measures nothing. That half
is the GDScript test named above, which reads the same shipped manifest. The two together cover
the art and the code; either alone covers half. And a seam the eye reads as TONE across many
tiles is not a step at a join: this is the edge instrument, as `grid_findability.py` is.

Exit codes match the other art checks: 0 green, 1 a seam is findable, 2 NO VERDICT.
"""
import json
import sys
from pathlib import Path

ART = Path(__file__).resolve().parent
sys.path.insert(0, str(ART))

from grid_findability import MAX_Z, lum, verdict  # noqa: E402  the bar, imported not copied
from png_stdlib import read_rgba  # noqa: E402

SPRITES = ART.parent / "client/assets/sprites"
SHEET = SPRITES / "ground.png"
MANIFEST = SPRITES / "manifest.json"


def block_and_cells():
    """((w, h), cell_px, [cells]) off disk, or a reason this cannot be asked."""
    if not SHEET.exists() or not MANIFEST.exists():
        return None, "no sheet at %s or no manifest at %s" % (SHEET, MANIFEST)
    ground = json.loads(MANIFEST.read_text()).get("ground", {})
    block = ground.get("block", [])
    if len(block) != 2:
        return None, ("the shipped ground sheet declares no block, so this check would be "
                      "asleep. If the sheet is deliberately loose variants now, delete this "
                      "check and its CI step together")
    w, h = int(block[0]), int(block[1])
    if w <= 1 or h <= 1:
        return None, "a %dx%d block is not a block" % (w, h)
    cell = int(ground.get("frame_px", [0, 0])[0])
    if cell <= 1:
        return None, "the manifest gives no usable frame_px for ground"
    sw, sh, rows = read_rgba(SHEET)
    if sw != cell:
        return None, "the sheet is %d px wide but frame_px says %d" % (sw, cell)
    n = sh // cell
    if n < w * h:
        return None, "a %dx%d block needs %d cells and the sheet holds %d" % (w, h, w * h, n)
    cells = [[row[:cell] for row in rows[i * cell:(i + 1) * cell]] for i in range(n)]
    return ((w, h), cell, cells), None


# How far the control lifts every other cell, in luminance. Chosen to be a seam no reviewer would
# accept and still a fraction of what a real stranger-join measures (13 against an interior 3).
CONTROL_STEP = 8


def control(cells, block):
    """A sheet with a seam AT EVERY JOIN BY CONSTRUCTION, both directions.

    WHY NOT A SHUFFLE, which is the realistic failure. I tried that first and it is a control that
    can pass by luck: re-ordering the cells can leave a pair field-adjacent anyway, and on a sheet
    that was already shuffled it put the horizontal joins back together and measured Z +0.90 --
    green, from a control whose whole job is to be red. A control that depends on a coincidence
    not happening is the vacuous check this file is otherwise built to avoid.

    So the control is arithmetic instead: lift every cell on the dark squares of a checkerboard by
    `CONTROL_STEP`. `(r + c)` parity differs across BOTH a left|right and an upper/lower join, so
    every join in both directions steps by a known amount and no ordering accident can hide it.
    The realistic shuffle is still worth running by hand -- it measures Z +67 / +49 on the shipped
    sheet, five times this control -- it is just not what a gate should rest on.
    """
    w, _h = block
    out = []
    for i, cell in enumerate(cells):
        r, c = divmod(i, w)
        if (r + c) % 2 == 0:
            out.append(cell)
            continue
        out.append([[(min(255, p[0] + CONTROL_STEP), min(255, p[1] + CONTROL_STEP),
                      min(255, p[2] + CONTROL_STEP)) + tuple(p[3:]) for p in row]
                    for row in cell])
    return out


def means(cells, block, cell):
    """(vertical, horizontal) offset means. Offset 0 is a cell join, 1..cell-1 are interior.

    VERTICAL is the step a column of pixels makes across a left|right join, HORIZONTAL the step
    across an upper/lower one -- the same two names `grid_findability.py` prints, so a sheet
    report and a shot report can be read side by side.
    """
    w, h = block
    vert = [[0.0, 0] for _ in range(cell)]
    horiz = [[0.0, 0] for _ in range(cell)]
    for r in range(h):
        for c in range(w):
            here = cells[r * w + c]
            if c + 1 < w:
                right = cells[r * w + c + 1]
                pair = [here[y] + right[y] for y in range(cell)]
                for k in range(1, cell + 1):
                    step = sum(abs(lum(row[k]) - lum(row[k - 1])) for row in pair) / cell
                    vert[k % cell][0] += step
                    vert[k % cell][1] += 1
            if r + 1 < h:
                pair = here + cells[(r + 1) * w + c]
                for k in range(1, cell + 1):
                    step = sum(abs(lum(pair[k][x]) - lum(pair[k - 1][x]))
                               for x in range(cell)) / cell
                    horiz[k % cell][0] += step
                    horiz[k % cell][1] += 1
    return ([a / max(n, 1) for a, n in vert], [a / max(n, 1) for a, n in horiz])


def report(label, cells, block, cell):
    """Prints both directions and returns True if a seam is findable in either, None for no verdict."""
    findable = False
    for name, m in zip(("vertical  ", "horizontal"), means(cells, block, cell)):
        v = verdict(m)
        if v is None:
            print("%s %s: NO VERDICT, the interior columns have zero spread" % (label, name))
            return None
        print("%-8s %s  join %6.2f   interior %6.2f +/- %4.2f   Z %+7.2f sd   rank %2d of %d   %s"
              % (label, name, v["boundary"], v["mu"], v["sd"], v["z"], v["rank"], cell,
                 "A SEAM IS FINDABLE" if v["z"] > MAX_Z else "lost in the noise"))
        findable = findable or v["z"] > MAX_Z
    return findable


def main() -> int:
    got, why = block_and_cells()
    if got is None:
        print("NO VERDICT: %s" % why, file=sys.stderr)
        return 2
    block, cell, cells = got
    print("ground.png: %d cells of %d px, declared as a %dx%d block"
          % (len(cells), cell, block[0], block[1]))

    shipped = report("SHIPPED", cells, block, cell)

    # THE CONTROL, EVERY RUN: a seam built into the same cells must be caught. A check that has
    # never been shown to fail is a comment, and this is the cheapest possible demonstration.
    ctl = report("CONTROL", control(cells, block), block, cell)
    if ctl is not True:
        print("\nNO VERDICT: the control did not go red, so this instrument cannot see a seam "
              "and its pass above means nothing.", file=sys.stderr)
        return 2

    if shipped is not True:
        print("\nThe cell joins are lost among the interior columns: the sheet is still one "
              "continuous picture, and the client may keep placing it by position.")
        return 0
    print("\nA SEAM IS FINDABLE AT THE CELL JOINS. ground.png is no longer one continuous "
          "picture, so `scene_view.gd::ground_row` is drawing strangers side by side at every "
          "tile boundary. Re-render the field as one scene (art/assets/ground.py), or drop "
          "`block` from the manifest so the cells are hash-picked as loose variants.",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
