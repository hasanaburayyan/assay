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

LEVER
  FAKE_CONTRACT_OFFSET=8,8   moves the module's offset in memory without
                             touching the shipped file, which is exactly what
                             "someone edited part_layout.py and did not
                             rebuild" looks like. MUST FAIL.

Stdlib only, so CI can run it with plain `python3`.
"""
import json
import os
import sys

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
CONTRACT = os.path.join(ROOT, "client", "assets", "sprites", "part_layout.json")

sys.path.insert(0, ART)
import part_layout  # noqa: E402  (after sys.path, on purpose)

OFFSET = tuple(part_layout.PART_REPEAT_OFFSET)
CEILING = part_layout.SHADOW_CEILING

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

    print("\nVERDICT: %s" % ("GREEN" if ok else "RED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
