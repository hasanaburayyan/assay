#!/usr/bin/env python3
"""The shipped part-layout contract still matches the module it came from.
(ASSA-54)

    art/check_part_contract.py

WHAT THIS IS FOR
  `client/assets/sprites/part_layout.json` carries the two rules that turn
  part sprites into a machine, because a client cannot work them out from the
  sheets: the repeat OFFSET (rule 5) and the shadow-safe stack operator's
  SHADOW_CEILING. Both live in `art/part_layout.py`, which only Python can
  import, so the JSON is how the engine gets them.

  A shipped copy of a constant is a copy, and copies rot. This is the thing
  that notices. It re-imports `part_layout` and compares, so the only way to
  change a rule is to change the module and rebuild; editing the JSON by hand,
  or editing the module and forgetting `art/build.py`, both fail here.

WHY NOT JUST PUT IT IN manifest.json, which is what ASSA-54 originally said
  I specified that and then checked it. The manifest's top level is an ASSET
  NAMESPACE. `check_client_can_see_art.py` does `man[a]["sheet"]` for every
  key, and the client's own `test_sprites.gd` walks it in both directions and
  fails with "the manifest describes `X` and there is no X.png". A
  `part_layout` key would have broken both on the commit that added it, so the
  contract ships as a sibling file instead.

WHAT IT CHECKS
  1. The file exists where the client will look for it, parses, and carries
     every key a client needs. A missing key is not allowed to read as "no
     disagreement found" -- that is the vacuous pass this kind of check dies
     of.
  2. Every NUMBER in it equals the module's value today.
  3. The prose fields are non-empty. They are the half a client cannot infer:
     which order repeats count in, and what to do instead of plain `over`.

  4. NO MOUNTED PART SHIPS A CONTACT SHADOW (ASSA-64). A shadow means "this
     part stands on the ground"; head and hopper never do, and a re-render that
     quietly put one back would make a client's plain `over` wrong again with
     nothing going red. WHICH KINDS MOUNT IS READ OUT OF `sim/src/assembly.rs`,
     not listed here: a part kind is mounted iff its `PartKind` is not a
     `Frame`, which is the same fact `AssemblyError::FrameMounted` enforces.
     If that file stops parsing, this check FAILS rather than passing with an
     empty list.

     The measure is not "dark pixels", which cannot reach zero: the Freestyle
     outline over transparency comes back nearly black, so a sprite's own ink
     rim counts as dark. It is a dark pixel more than `INK_RIM_PX` from any
     SURFACE pixel, with alpha above `SHADOW_NOISE_ALPHA`. Both live in
     `part_layout.py` with their reasons.

LEVERS
  FAKE_CONTRACT_OFFSET=8,8   moves the module's offset in memory without
                             touching the shipped file, which is exactly what
                             "someone edited part_layout.py and did not
                             rebuild" looks like. MUST FAIL.
  FAKE_SHADOW_SHEET=head=<path>
                             reads one mounted kind's sheet from somewhere
                             else. Point it at the pre-ASSA-64 head.png and the
                             shadow is back: that is the mutation this guard
                             exists for, run with a real sheet rather than a
                             synthetic one. MUST FAIL.

Stdlib only, so CI can run it with plain `python3`.
"""
import json
import os
import re
import sys

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
CONTRACT = os.path.join(ROOT, "client", "assets", "sprites", "part_layout.json")

SPRITES = os.path.join(ROOT, "client", "assets", "sprites")
ASSEMBLY = os.path.join(ROOT, "sim", "src", "assembly.rs")

sys.path.insert(0, ART)
import part_layout  # noqa: E402  (after sys.path, on purpose)
from png_stdlib import read_rgba  # noqa: E402

OFFSET = tuple(part_layout.PART_REPEAT_OFFSET)
CEILING = part_layout.SHADOW_CEILING
RIM = part_layout.INK_RIM_PX
NOISE = part_layout.SHADOW_NOISE_ALPHA


def mounted_kinds():
    """The part kinds that MOUNT, read out of sim's own catalogue.

    A spec is `kind: PartKind::X` followed by `name: "y"`. Mounted means the
    kind is not a `Frame(..)` -- the distinction `Assembly` enforces by type.
    Returns ([], 0) if the file cannot be read, and the caller treats that as a
    failure rather than as "no mounted kinds, nothing to check".
    """
    try:
        src = open(ASSEMBLY).read()
    except IOError:
        return [], 0
    specs = re.findall(r"kind:\s*PartKind::(\w+)[^,]*,\s*\n\s*name:\s*\"(\w+)\"", src)
    return [name for kind, name in specs if kind != "Frame"], len(specs)


def shadow_in(path, row_h):
    """(worst alpha, pixel count, which row) of contact shadow in one sheet.

    Shadow is a pixel the stack operator would treat as shadow (brightest
    channel below SHADOW_CEILING) that is more than INK_RIM_PX from any SURFACE
    pixel, so the sprite's own near-black outline is not counted as one.
    """
    w, h, px = read_rgba(path)
    worst, count, where = 0, 0, -1
    for row in range(max(1, h // row_h)):
        y0 = row * row_h
        surface = [[max(px[y0 + y][x][:3]) >= CEILING and px[y0 + y][x][3] > 0
                    for x in range(w)] for y in range(row_h)]
        for y in range(row_h):
            for x in range(w):
                r, g, b, a = px[y0 + y][x]
                if a == 0 or max(r, g, b) >= CEILING:
                    continue
                near = any(surface[y + dy][x + dx]
                           for dy in range(-RIM, RIM + 1) for dx in range(-RIM, RIM + 1)
                           if 0 <= y + dy < row_h and 0 <= x + dx < w)
                if near:
                    continue
                count += 1
                if a > worst:
                    worst, where = a, row
    return worst, count, where

if os.environ.get("FAKE_CONTRACT_OFFSET"):
    OFFSET = tuple(int(v) for v in os.environ["FAKE_CONTRACT_OFFSET"].split(","))
    print("[RED LEVER] part_layout.PART_REPEAT_OFFSET forced to %s in memory while\n"
          "            the shipped file is untouched -- the shape of editing the\n"
          "            module and not rebuilding. This check MUST fail.\n" % (OFFSET,))

PROSE = ("source", "repeat_offset_space", "repeat_rule", "shadow_rule")


def main():
    print(__doc__.splitlines()[0])
    if not os.path.exists(CONTRACT):
        print("\n  FAIL: no %s.\n  `art/build.py --pack` writes it; the client has no way to\n"
              "  learn the repeat offset or the shadow rule without it."
              % os.path.relpath(CONTRACT, ROOT))
        return 1
    try:
        c = json.load(open(CONTRACT))
    except ValueError as e:
        print("\n  FAIL: %s does not parse: %s" % (os.path.relpath(CONTRACT, ROOT), e))
        return 1

    print("shipped: %s" % os.path.relpath(CONTRACT, ROOT))
    ok = True

    # 1. Every key present. Checked before any comparison, so a file that is
    #    missing the field cannot pass by having nothing to disagree with.
    missing = [k for k in ("repeat_offset_px", "shadow_ceiling") + PROSE if k not in c]
    if missing:
        print("\n  FAIL: the contract is missing %s. A client reading this file\n"
              "  would have to invent the rule, which is the whole thing ASSA-54\n"
              "  exists to stop." % ", ".join(missing))
        return 1

    # 2. The numbers.
    shipped_offset = tuple(c["repeat_offset_px"])
    print("  repeat_offset_px  shipped %-10s module %s" % (str(shipped_offset), str(OFFSET)))
    if shipped_offset != OFFSET:
        ok = False
        print("  FAIL: the shipped offset %s is not part_layout's %s. Either the\n"
              "  module moved and `art/build.py --pack` was not run, or the file\n"
              "  was edited by hand. The module is the source."
              % (shipped_offset, OFFSET))
    print("  shadow_ceiling    shipped %-10s module %s" % (str(c["shadow_ceiling"]), str(CEILING)))
    if c["shadow_ceiling"] != CEILING:
        ok = False
        print("  FAIL: the shipped shadow_ceiling %s is not part_layout's %s. A\n"
              "  client compositing against the wrong boundary treats shadow as\n"
              "  surface, which is how shadows start compounding again."
              % (c["shadow_ceiling"], CEILING))

    # 3. The prose. A client cannot infer the ORDER repeats count in, nor what
    #    to do instead of `over`; an empty string here ships a contract that
    #    says nothing while passing every numeric test above.
    empty = [k for k in PROSE if not str(c.get(k, "")).strip()]
    if empty:
        ok = False
        print("  FAIL: %s empty. The numbers alone do not tell a client which\n"
              "  order repeats count in or what operator to use." % ", ".join(empty))

    # 4. No mounted part ships a contact shadow (ASSA-64).
    kinds, specs_found = mounted_kinds()
    if not kinds:
        print("\n  FAIL: could not read which part kinds mount out of %s (%d specs\n"
              "  parsed). This check will not pass with an empty list -- that is the\n"
              "  vacuous green it exists to avoid."
              % (os.path.relpath(ASSEMBLY, ROOT), specs_found))
        return 1
    print("\nmounted kinds, per %s: %s" % (os.path.relpath(ASSEMBLY, ROOT), ", ".join(kinds)))
    try:
        manifest = json.load(open(os.path.join(SPRITES, "manifest.json")))
    except (IOError, ValueError) as e:
        print("  FAIL: no readable manifest.json, so the grade-row height is unknown: %s" % e)
        return 1
    override = {}
    if os.environ.get("FAKE_SHADOW_SHEET"):
        kind, _, path = os.environ["FAKE_SHADOW_SHEET"].partition("=")
        override[kind] = path
        print("[RED LEVER] %s's sheet read from %s instead of the shipped one.\n"
              "            Point this at a pre-ASSA-64 sheet and the shadow is back.\n"
              "            This check MUST fail.\n" % (kind, path))
    for kind in kinds:
        if kind not in manifest:
            ok = False
            print("  FAIL: the manifest has no `%s`, so a mounted part kind ships no sheet\n"
                  "  at all -- or the art's name for it has drifted from sim's." % kind)
            continue
        row_h = int(manifest[kind]["frame_px"][1])
        path = override.get(kind, os.path.join(SPRITES, "%s.png" % kind))
        if not os.path.exists(path):
            ok = False
            print("  FAIL: %s is in the manifest and %s does not exist." % (kind, path))
            continue
        worst, count, where = shadow_in(path, row_h)
        print("  %-8s worst shadow alpha %3d  (%d px past a %d px ink rim%s)"
              % (kind, worst, count, RIM, "" if where < 0 else ", worst in row %d" % where))
        if worst > NOISE:
            ok = False
            print("  FAIL: %s carries a contact shadow (alpha %d, more than the %d/255 one\n"
                  "  sample of an SSx render can leave). A mounted part never touches the ground,\n"
                  "  and once one carries a shadow a machine has more than one -- which\n"
                  "  is the compounding `stack()` exists to cap and `over` does not."
                  % (kind, worst, NOISE))

    print("\nVERDICT: %s" % ("GREEN" if ok else "RED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
