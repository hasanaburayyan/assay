#!/usr/bin/env python3
"""A part fits inside the frame it is rendered in, on all four sides. (ASSA-104)

    art/check_part_frame_fit.py

WHAT IS WRONG TODAY, AND WHY THIS EXISTS
  `handle.png` and `frame.png` run off the WEST edge of their own 128x102 frame.
  Measured two ways that agree:

    - The shipped sheets have solid body ink in column 0, and the ink is still
      GROWING away from the edge (handle 19,20,21,22 px down columns 0..3;
      frame 58,59,60,61). A shape ending naturally at the edge falls to zero.
    - Re-rendered in a 4-tile window instead of their 2-tile one, with the same
      px per tile, both extend to x = -2. Clipping that wide render back to the
      ship window reproduces every shipped bounding box exactly, for all four
      parts, which is what says the wide render is of the same thing.

  So the cut is exactly TWO pixels on handle and frame. head and hopper fit.

WHY NOTHING CAUGHT IT. `rig.py` already treats this as a defect in the VERTICAL
axis: its rule 4 records that at headroom 0.3 "the hopper's mouth was clipped
flat against the top of its frame (body reaching row 0, measured)", and the fix
was to raise PART_HEADROOM to 0.6. There was never a horizontal equivalent --
PART_TILES = (2, 1) is fixed and nothing asked whether a part fits the width it
buys. This is that question, asked on all four edges so neither axis is special.

WHY "TOUCHES THE EDGE" IS THE RULE, rather than something cleverer about rims
  A part sprite is not a picture on its own: `part_layout.stack` composites
  several into one machine, and every silhouette in the set is drawn with an ink
  rim. A body pixel ON the boundary means the rim that should close that side is
  outside the frame -- which is exactly what the shipped sheets show, a rim on
  three sides and a flat cut on the fourth. It is also the rule rig.py already
  applied vertically, so this adds no new standard; it extends an existing one
  to the axis nobody checked.

  It cannot be "measure the missing part", because a cut sprite does not record
  its own full extent. That took a re-render, and a re-render is not something
  CI can do.

NOT A STYLE BOUND I PICKED. There is no threshold here to tune: zero body pixels
on the four edge lines, or it fails. The only judgement is BODY_ALPHA, which is
inherited from the pipeline rather than chosen here (see below).

PROVING IT RED. It IS red on the sheets as shipped today -- that is the defect it
was written for, so no lever is needed to see it fail. For the opposite direction,
once the art is fixed, `FAKE_FIT_SHEET=handle=<path>` reads one kind's sheet from
somewhere else: point it at a pre-fix sheet and this check must fail again.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from png_stdlib import read_rgba  # noqa: E402  stdlib only: CI runs this without pip

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
SPRITES = os.path.join(ROOT, "client", "assets", "sprites")
ASSEMBLY = os.path.join(ROOT, "sim", "src", "assembly.rs")

# A destination pixel is the sprite's BODY at source alpha >= 200. Same bound the
# pack-icon pipeline uses, and it is a correction rather than a choice: the part
# frames carry a contact shadow whose alpha runs down to 1, so counting every
# a > 0 pixel would measure the shadow feathering out and call every part clipped.
BODY_ALPHA = 200


def part_kinds():
    """Every part kind's asset name, read out of sim's own catalogue.

    A spec is `kind: PartKind::X` followed by `name: "y"`. Unlike
    `check_part_contract.py`, which wants the MOUNTED kinds only, this wants all
    of them: a frame runs off its frame exactly as easily as a head does, and a
    fifth part kind should arrive here without anyone editing this file.

    Returns [] if the file cannot be read, and the caller treats that as a
    failure rather than as "no parts, nothing to check" -- the vacuous green.
    """
    try:
        src = open(ASSEMBLY).read()
    except IOError:
        return []
    return [name for _kind, name in
            re.findall(r"kind:\s*PartKind::(\w+)[^,]*,\s*\n\s*name:\s*\"(\w+)\"", src)]


def edge_ink(path, frame_w, frame_h):
    """Body pixels on each of the four edge lines, per grade row.

    Returns a list of (row_index, {"west": n, "east": n, "north": n, "south": n}).
    SCANS ONE GRADE ROW AT A TIME, which is png_stdlib's own warning: the part
    sheets are three 128x102 rows stacked, and scanning the whole sheet counts
    everything three times and puts two interior boundaries where no frame edge is.
    """
    w, h, px = read_rgba(path)
    out = []
    for row in range(h // frame_h):
        top = row * frame_h
        counts = {"west": 0, "east": 0, "north": 0, "south": 0}
        for y in range(top, top + frame_h):
            if px[y][0][3] >= BODY_ALPHA:
                counts["west"] += 1
            if px[y][frame_w - 1][3] >= BODY_ALPHA:
                counts["east"] += 1
        for x in range(frame_w):
            if px[top][x][3] >= BODY_ALPHA:
                counts["north"] += 1
            if px[top + frame_h - 1][x][3] >= BODY_ALPHA:
                counts["south"] += 1
        out.append((row, counts))
    return out


def main():
    kinds = part_kinds()
    if not kinds:
        print("FAIL: no part kinds parsed out of %s, so there is nothing to check and that\n"
              "  is the vacuous green this guard exists to avoid." % os.path.relpath(ASSEMBLY, ROOT))
        return 1
    print("part kinds, per %s: %s" % (os.path.relpath(ASSEMBLY, ROOT), ", ".join(kinds)))

    try:
        manifest = json.load(open(os.path.join(SPRITES, "manifest.json")))
    except (IOError, ValueError) as e:
        print("FAIL: no readable manifest.json, so the frame size is unknown: %s" % e)
        return 1

    override = {}
    if os.environ.get("FAKE_FIT_SHEET"):
        kind, _, path = os.environ["FAKE_FIT_SHEET"].partition("=")
        override[kind] = path
        print("\n[RED LEVER] %s's sheet read from %s instead of the shipped one.\n"
              "            Point this at a sheet whose part runs off the frame and this\n"
              "            check MUST fail.\n" % (kind, path))

    ok = True
    print("\n%-9s %-5s %s" % ("kind", "row", "body pixels ON the frame edge (want 0 everywhere)"))
    for kind in kinds:
        if kind not in manifest:
            ok = False
            print("  FAIL: the manifest has no `%s`: a part kind ships no sheet at all, or the\n"
                  "  art's name for it has drifted from sim's." % kind)
            continue
        fw, fh = (int(v) for v in manifest[kind]["frame_px"])
        path = override.get(kind, os.path.join(SPRITES, "%s.png" % kind))
        if not os.path.exists(path):
            ok = False
            print("  FAIL: %s is in the manifest and %s does not exist." % (kind, path))
            continue
        for row, c in edge_ink(path, fw, fh):
            bad = {k: v for k, v in c.items() if v}
            if bad:
                ok = False
            print("  %-9s %-5s %s" % (kind, row,
                  "clear" if not bad else
                  "CUT: " + ", ".join("%s %d px" % (k, v) for k, v in sorted(bad.items()))))

    if ok:
        print("\nVERDICT: GREEN. Every part's ink stops before all four edges of its frame, so\n"
              "the rim that closes each silhouette is inside the sheet and `part_layout.stack`\n"
              "composites a whole part rather than a cut one.")
        return 0
    print("\nVERDICT: RED. A part's body reaches the boundary of its own frame, so its ink rim\n"
          "on that side was never rendered -- the sprite is cut, not merely tight. rig.py rule 4\n"
          "fixed the same defect on the vertical axis by giving the frame more room\n"
          "(PART_HEADROOM 0.3 -> 0.6); the horizontal axis has had no such room and no check.\n"
          "ASSA-104 carries the measurement: handle and frame overhang west by exactly 2 px.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
