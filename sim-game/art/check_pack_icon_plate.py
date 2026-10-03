#!/usr/bin/env python3
"""Is the pack icon's slot plate still THE GROUND'S OWN COLOUR? (ASSA-71, Maren's ruling)

    art/check_pack_icon_plate.py

WHAT THE RULING ACTUALLY SAYS, because that is what has to be guarded. The plate is
not "a colour that tested well": it is the ground's own median, so that a stack in the
pack row and a rock on the map are THE SAME OBJECT, and the player's task at a pack row
is connecting a stack to a rock they walked over. The contrast numbers follow from that
claim; they are not the claim. A hex that merely happens to equal today's ground would
satisfy every ratio and still be wrong the morning the ground is re-rendered.

So the thing to check is an IDENTITY BETWEEN THREE SOURCES that are written, built and
drawn by different things and can each go stale on their own:

  1. THE SHEET      `client/assets/sprites/ground.png`, median of its opaque pixels --
                    recomputed here, now, from the file that actually ships.
  2. THE PIPELINE   `client/assets/sprites/ui_theme.json`, what the last build wrote.
  3. THE ENGINE     the `StyleBoxFlat` the client really painted behind the icon, read
                    out of the live scene by `art/pack_icon_layout.gd`.

Each pair catches a different, real failure:
  1 vs 2  the ground was re-rendered and nobody rebuilt the theme, or somebody edited
          the JSON by hand. The shipped colour has stopped being the ground's.
  2 vs 3  the client stopped reading `ui_theme.json` -- the file was renamed, the parse
          silently returned TRANSPARENT, or somebody put the hex back in GDScript where
          Maren's constraint 1 says it may never live. The picture would look right in
          every review sheet and be wrong in the game.

WHY NOT JUST ASSERT THE HEX. Writing `#88986C` in here would make this check a copy of
the thing it checks: it would pass forever, including the day the ground changes, which
is the one day it needs to fail. Nothing in this file names a colour.

THE DERIVATION IS NOT REIMPLEMENTED EITHER. The median comes from `art/ui_theme.py`, the
same function `build.py` calls, so this cannot drift into being a second opinion about
what "the ground's colour" means. That is why `ui_theme.py` is stdlib-only: CI runs these
checks on plain `python3` with no pip, so the build and the check share one decoder
instead of a Pillow one and a hand-rolled one that can disagree.

WHAT THIS CANNOT SEE, said out loud rather than quietly skipped. The ruling also says the
plate is constant ACROSS ALL SIX SPECIES AND THREE GRADES. One offline pack holds one
species, so species-invariance is not measurable from it. What is measurable is that the
plate does not vary across the rows that ARE there (which do differ in kind, tint and
verb count), and that no GDScript file contains a colour literal for it -- together those
cover the mechanism by which a plate could start carrying information. The six-species
claim rests on the client reading one colour from one file and never tinting it, and this
check does not pretend to have measured it.

Exit codes, matching the other two engine checks: 0 green, 1 the plate is wrong,
2 NO VERDICT -- could not ask the engine, or had nothing to measure.
"""

import json
import os
import re
import sys

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
CLIENT = os.path.join(ROOT, "client")
SPRITES = os.path.join(CLIENT, "assets", "sprites")
THEME = os.path.join(SPRITES, "ui_theme.json")
SCRIPTS = os.path.join(CLIENT, "scripts")

sys.path.insert(0, ART)
import ui_theme  # noqa: E402  (after sys.path, on purpose)
# Running the layout probe is shared with the other two checks that need the engine's
# own answer (ASSA-111); it used to be a character-for-character copy in each.
from ask_layout import CannotCheck, ask_the_engine  # noqa: E402

WHY_THE_ENGINE = ("whether the CLIENT paints the plate is half of what this file\n"
                  "checks, and it cannot be answered without the engine.")


def hexs(rgb):
    return "#%02X%02X%02X" % tuple(rgb)


def gdscript_colour_literals(wanted):
    """GDScript files that spell the plate colour as a literal.

    Maren's constraint 1: the colour is derived in the pipeline and travels in the
    manifest, NOT typed into GDScript. Catches `Color8(136, 152, 108)`, `"88986C"` and
    `#88986c` in any case. Finds the hex inside a longer string too, which is the point:
    a literal that is merely hard to spot is still a literal.
    """
    r, g, b = wanted
    patterns = [
        re.compile(r"%02x\s*%02x\s*%02x" % (r, g, b), re.I),
        re.compile(r"Color8\s*\(\s*%d\s*,\s*%d\s*,\s*%d" % (r, g, b)),
    ]
    found = []
    if not os.path.isdir(SCRIPTS):
        return found
    for base, _dirs, files in os.walk(SCRIPTS):
        for name in files:
            if not name.endswith(".gd"):
                continue
            path = os.path.join(base, name)
            try:
                text = open(path, encoding="utf-8").read()
            except OSError:
                continue
            for pat in patterns:
                for m in pat.finditer(text):
                    line = text.count("\n", 0, m.start()) + 1
                    found.append("%s:%d spells the plate colour as a literal (%r)"
                                 % (os.path.relpath(path, ROOT), line, m.group(0)))
    return found


def main():
    print(__doc__.splitlines()[0])

    # ---- source 1: the sheet, recomputed now.
    try:
        from_sheet = ui_theme.plate_rgb(SPRITES)
    except (OSError, SystemExit) as why:
        raise CannotCheck("could not read the ground sheet in %s: %s"
                          % (os.path.relpath(SPRITES, ROOT), why))

    # ---- source 2: what the last build shipped.
    if not os.path.exists(THEME):
        raise CannotCheck(
            "no %s. The pipeline has never written the theme, so there is no shipped\n"
            "colour to compare. Run `art/build.py`." % os.path.relpath(THEME, ROOT))
    try:
        theme = json.load(open(THEME))
        from_pipeline = tuple(int(v) for v in theme["pack_icon_plate_rgb"])
    except (ValueError, KeyError, TypeError) as why:
        raise CannotCheck("%s is not a theme this check understands: %s"
                          % (os.path.relpath(THEME, ROOT), why))

    # ---- source 3: what the engine painted.
    layout = ask_the_engine(WHY_THE_ENGINE)
    art = [r for r in layout.get("rows", []) if r.get("icon")]
    if not art:
        raise CannotCheck(
            "not one row in the richest pack had an icon, so no plate was drawn for\n"
            "this check to look at. Either the sheets stopped loading or the pack\n"
            "changed shape.")

    print("\n  %-24s %-9s %s" % ("row", "plate", "plate rect"))
    for r in art:
        icon = r["icon"]
        print("  %-24s %-9s %s"
              % (r["line"][:24], icon.get("plate") or "-",
                 "%gx%g" % tuple(icon["plate_rect"]) if icon.get("plate_rect") else "-"))

    bad = []
    painted = {(r["icon"].get("plate") or "").lower() for r in art}
    if painted == {""}:
        bad.append(
            "the client painted NO plate behind any icon. `ui_theme.json` ships %s,\n"
            "      so either `AssaySprites.pack_icon_plate()` is not being called, or it\n"
            "      returned TRANSPARENT because the file did not parse." % hexs(from_pipeline))
    elif len(painted) > 1:
        bad.append("the plate is not one colour across the pack: %s. A plate that varies "
                   "by row is carrying information, which the ruling forbids."
                   % sorted(p or "(none)" for p in painted))
    else:
        from_engine = tuple(int(list(painted)[0][i:i + 2], 16) for i in (0, 2, 4))
        if from_engine != from_pipeline:
            bad.append(
                "the client painted %s but the pipeline ships %s. The client is not\n"
                "      drawing the colour the build derived."
                % (hexs(from_engine), hexs(from_pipeline)))

    # 1 vs 2: has the shipped colour stopped being the ground's?
    if from_sheet != from_pipeline:
        bad.append(
            "%s ships %s but ground.png's median is %s today. The plate has stopped\n"
            "      being the ground's own colour -- re-run `art/build.py` if the ground\n"
            "      was re-rendered on purpose."
            % (os.path.relpath(THEME, ROOT), hexs(from_pipeline), hexs(from_sheet)))

    # The plate is the icon's own slot, not some other rectangle.
    boxes = {tuple(r["icon"]["plate_rect"]) for r in art if r["icon"].get("plate_rect")}
    rects = {tuple(r["icon"]["rect"]) for r in art}
    if boxes and boxes != rects:
        bad.append("the plate is %s but the icon box is %s. ASSA-71 puts the plate behind "
                   "the icon's own slot; if they differ the icon is sitting on something "
                   "else." % (sorted(boxes), sorted(rects)))

    # Maren's constraint 1, structurally.
    for hit in gdscript_colour_literals(from_sheet):
        bad.append("%s. The colour is derived in the pipeline and travels beside the "
                   "manifest; GDScript reads it." % hit)

    # ANTI-VACUITY. "One colour across the pack" is free if there is only one row to be
    # consistent across, and the 1-vs-2 identity is free if the sheet is a flat colour --
    # a median is trivially itself then, and would stay correct through any re-render.
    if len(art) < 2:
        raise CannotCheck(
            "only one row had art, so 'the plate is constant across the pack' had\n"
            "nothing to be constant across. No verdict rather than a free pass.")
    tints = {r["icon"].get("modulate") for r in art}
    if len(tints) < 2 and len({r["line"].split()[-2] for r in art}) < 2:
        raise CannotCheck(
            "every row with art is the same kind at the same tint, so a plate that\n"
            "followed the icon would look identical to one that did not.")

    print("\n  the sheet says %s, the pipeline ships %s, the engine painted %s"
          % (hexs(from_sheet), hexs(from_pipeline),
             sorted(painted)[-1].upper() if painted != {""} else "nothing"))
    print("  measured across %d rows of %d kinds" % (len(art), len({r["line"].split()[-2] for r in art})))

    if bad:
        print("\nVERDICT: FAIL (exit 1)")
        for line in bad:
            print("  - %s" % line)
        return 1
    print("\nVERDICT: PASS (exit 0). The sheet, the shipped theme and the colour the\n"
          "  client actually painted are the same, and no GDScript names it.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CannotCheck as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n%s" % why)
        sys.exit(2)
