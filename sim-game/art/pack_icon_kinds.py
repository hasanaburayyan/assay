#!/usr/bin/env python3
"""CAN THE ICON CARRY THE KIND, now that the buttons have stopped? (ASSA-101)

    godot --headless --path client --script "$PWD/art/pack_icon_layout.gd" \
      | sed -n 's/^LAYOUT_JSON //p' > /tmp/cove-layout.json
    uv run --with pillow python art/pack_icon_kinds.py /tmp/cove-layout.json

Writes assets/review/pack_icon_kinds.png and prints the table.

WHY THIS EXISTS
  Maren's ASSA-86 ruling takes every MAKE verb off the pack row, and her 02:35 judgement of
  the 1:1 render (ASSA-99) says what that costs: "the buttons stop saying what kind of thing a
  row holds; the icon and `stack_line` carry that alone. That is the ruling working, not a
  loss." I agree with the ruling. It also moves load onto a surface I own, and nothing in the
  repo measured that surface.

  Before the split, a part row was told from an ore row by its VERBS. After it, seven rows
  share three button sets -- `Fuel Smelt` / `Frame`-`Mount` / `Place` -- and FOUR consecutive
  part rows carry one identical word.

THE FACT THAT MAKES IT WORTH MEASURING, and it is the whole reason the question is not idle:
  A PACK IS ONE PLAYER'S, SO EVERY STACK IN IT CARRIES THE SAME SPECIES TINT. Read off the
  live screen, all seven icons are `modulate = 3333ff` -- the tint the demo STARTS on. So hue
  carries exactly ZERO kind information inside a pack, however well the species palette
  separates across worlds. Kind reads from silhouette and interior value alone, through a
  blue-dominant multiply, which is the worst case the contrast ceiling in `pack_icon_sheet.py`
  describes: `modulate` is a per-channel multiply and blue is 7% of luminance.

  Everything previously measured about these sprites asked a SPECIES question (`loudness.py`,
  `species_probe.py`: is ore loud enough, are six species even). Maren's own rule splits the
  two -- species are judged on EVENNESS, kinds on DISCRIMINATION (ASSA-71) -- and the kind half
  had no instrument.

WHAT THIS IS NOT
  NOT A DEFECT CLAIM. `stack_line` is still a sentence ("1 x Minyte frame (B)"), so the icon is
  one of TWO carriers and the rule that the icon may never be the only read still holds.
  NOT A GATE, and deliberately not a `check_*.py`. It reports a spread; which spread is
  acceptable is the Game Director's call and not a number I may pick on my own. Same stance as
  `pack_icon_sheet.py`, for the same reason.

  THAT GATE NOW EXISTS ELSEWHERE and this file is still not it (ASSA-111). Maren ruled the
  spread acceptable, so `art/check_icon_kinds.py` guards the ruling in CI -- the same two
  measures out of the same `pack_icon_draw`, on the player-facing property only. This file
  stays a probe: it prints the whole table and the pictures, which is what a judgement is made
  from, and the check prints a verdict, which is what a regression is caught by.

WHAT IS MEASURED, and the point is that the two measures DO NOT SHARE A QUANTITY
  Both run on the composited 32x48 plate box -- the icon as the engine drew it, on the slot
  plate the engine painted, at the scale the engine chose -- for all 21 pairs of the seven
  kinds, at one species, which is the control that matters: a real pack never mixes tints.

  A. SILHOUETTE: intersection over union of the two BODY masks. Pure shape. 1.0 means one
     outline, 0.0 means no shared pixel. It cannot see colour at all.
  B. INTERIOR: mean dE76 over the pixels where BOTH are body ink. Pure colour, on the overlap
     only. It cannot see shape at all, because a pixel one sprite does not cover is not in it.

  A pair that is close on A is two things of the same outline; a pair close on B is two things
  of the same colour; a pair close on BOTH is two things a player tells apart by neither. That
  last is the only reading this file makes, and the number that decides "close" is Maren's.

  dE76 and the 12.0 reference line come from `species_probe.DISTINCT`, imported rather than
  retyped: "two species a player must never confuse at a glance". It is quoted here as the
  only house number of its kind and is NOT asserted to be the right bound for kinds -- a kind
  has a silhouette to help it and a species does not, so if anything it should be lower.

THE RED CONTROL IS RUN, NOT DESCRIBED
  Every kind is measured against ITSELF and those seven pairs must come back at IoU 1.000 and
  dE 0.00. A discrimination measure that cannot report "these are the same picture" when handed
  the same picture twice is measuring something else, and I have shipped one of those before.

WHAT I DID NOT BELIEVE, AND WHY THE REGISTRATION TABLE IS PRINTED BELOW THE PAIRS
  The first run said head shares ZERO pixels with handle, frame AND hopper while overlapping
  all three ITEMS. Four parts drawn into the same 32 x 25.5 band cannot miss each other, so I
  went and looked instead of reporting it. The number is right and my reading of it was wrong:
  `rig.py` rule 3 fixes ONE JOIN HEIGHT and PART_TILES = (2, 1) "so both halves of a join fit
  one frame", and the parts are placed about that join -- head to the RIGHT of the frame's
  centre (source x 58..113), handle, frame and hopper to the LEFT (x 0..56, 0..58, 2..49).

  SO PART-AGAINST-PART IoU IS LARGELY MEASURING REGISTRATION, NOT SHAPE, and it is reported
  with that said rather than quietly. Those three zeroes are not three well-separated
  silhouettes; they are head standing on the other side of the join. The honest shape
  comparisons among parts are the three pairs that DO share the left half.

  It is also why the part rows look sparse. `rig.py` rule 3 says in writing that "a part is
  drawn to be assembled, and `items.py` is where loose things on the ground are drawn" -- and
  the pack draws a LOOSE part out of the assembly sheet. The slot fill column below is what
  that costs.
"""
import itertools
import json
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import review_sources  # noqa: E402  the shipped art this sheet composites, stamped into it
review_sources.start()  # before the first read -- `species_probe` reads art on import (ASSA-144)
# The engine's sampling, the composite and the two-measure comparison, once, shared with
# `check_icon_kinds.py` -- the CI guard on what this file measures (ASSA-111). A probe and
# the check that enforces its finding must not be able to disagree about the pixels.
from pack_icon_draw import (  # noqa: E402
    BODY_ALPHA, PillowBackend, compare, drawn_icon, rgb)
from ask_layout import kind_of  # noqa: E402  one reading of the row's word, shared
from species_probe import DISTINCT  # noqa: E402  the house threshold, Maren's not mine

HERE = Path(__file__).resolve().parent.parent
SPRITES = HERE / "client/assets/sprites"
REVIEW = HERE / "assets/review"
os.makedirs(REVIEW, exist_ok=True)

LAYOUT = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "/tmp/cove-layout.json"))
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else REVIEW / "pack_icon_kinds.png"

ROWS = [r for r in LAYOUT["rows"] if "icon" in r]


def drawn(entry):
    """The icon on its plate, exactly as the engine put it there, plus its body mask.

    One line, because the compositing lives in `pack_icon_draw` where the check can reach it
    too (ASSA-111). Pillow, because this file goes on to resize and paste these icons into a
    review sheet; the check passes the stdlib backend to the same function.
    """
    return drawn_icon(entry, SPRITES, PillowBackend)


def source_body_bbox(entry):
    """Where the sprite's solid ink sits INSIDE its own source frame.

    The thing being judged, read off the shipped sheet rather than inferred from the drawn
    result: a bbox derived from the 32px blit could not tell a part placed left of the join
    from a part that simply happens to land there.
    """
    ic = entry["icon"]
    sheet = Image.open(SPRITES / Path(ic["sheet"]).name).convert("RGBA")
    x, y, w, h = ic["region"]
    alpha = sheet.crop((int(x), int(y), int(x + w), int(y + h))).split()[-1]
    return alpha.point(lambda v: 255 if v >= BODY_ALPHA else 0).getbbox()


# `compare` moved to `pack_icon_draw` with the blit (ASSA-111): the probe and the check must
# not be able to hold two opinions about what "close" measures.


# ------------------------------------------------------------------ measure
tints = {r["icon"]["modulate"] for r in ROWS}
kinds = [kind_of(r) for r in ROWS]
icons = {k: drawn(r) for k, r in zip(kinds, ROWS)}

# The probe's own scale arithmetic, asserted rather than trusted (ASSA-57's lesson).
for r in ROWS:
    ic = r["icon"]
    want = min(ic["rect"][0] / ic["frame"][0], ic["rect"][1] / ic["frame"][1])
    assert abs(want - ic["scale"]) < 1e-6, (r["line"], want, ic["scale"])

print("PACK ICONS: DOES THE PICTURE SAY WHAT KIND THE ROW HOLDS? (ASSA-101)")
print("Source: the live layout probe. Every rect, region, tint and plate below is the "
      "engine's answer.")
print("\nTINTS IN THIS PACK: %s  <- one player, one species, so HUE CARRIES NO KIND"
      % ", ".join("#" + t for t in sorted(tints)))
print("PLATE: #%s. Reference line dE76 %.1f (species_probe.DISTINCT, quoted not adopted).\n"
      % (ROWS[0]["icon"]["plate"], DISTINCT))

slot = icons[kinds[0]][0].size[0] * icons[kinds[0]][0].size[1]
print("DRAWN SIZE PER KIND, and how much of the %dx%d slot the sprite's ink actually fills:"
      % icons[kinds[0]][0].size)
for k, r in zip(kinds, ROWS):
    ic = r["icon"]
    print("  %-8s %-11s frame %gx%g  scale %.2f  drawn %gx%g  body %3d px  = %4.1f%% of slot"
          % (k, Path(ic["sheet"]).name, ic["frame"][0], ic["frame"][1], ic["scale"],
             ic["drawn"][0], ic["drawn"][1], len(icons[k][1]), 100.0 * len(icons[k][1]) / slot))

print("\nWHERE EACH SPRITE SITS INSIDE ITS OWN SOURCE FRAME (read off the shipped sheet):")
print("  rig.py rule 3 fixes one join height and PART_TILES=(2,1) 'so both halves of a join")
print("  fit one frame', so the parts are placed ABOUT THE JOIN, not centred in the frame.")
for k, r in zip(kinds, ROWS):
    bb = source_body_bbox(r)
    fw = r["icon"]["frame"][0]
    # THE BODY'S CENTRE, not its left edge. Testing `bb[0] >= fw/2` called head "left of the
    # join": its ink starts at x=58 and runs to 112, so the edge is a hair inside the join and
    # the object is plainly beyond it. The claim is about where the part SITS.
    mid = (bb[0] + bb[2] - 1) / 2.0
    side = ("" if Path(r["icon"]["sheet"]).name == "items.png"
            else "   <- %s of the join (x=%g), centre %.0f"
            % ("RIGHT" if mid >= fw / 2 else "left", fw / 2, mid))
    print("  %-8s body x %3d..%-3d  y %3d..%-3d  of a %gx%g frame%s"
          % (k, bb[0], bb[2] - 1, bb[1], bb[3] - 1, fw, r["icon"]["frame"][1], side))

print("\nRED CONTROL -- every kind against ITSELF. These must be IoU 1.000 / dE 0.00:")
bad = []
for k in kinds:
    iou, de, _ = compare(icons[k], icons[k])
    flag = "" if (abs(iou - 1.0) < 1e-9 and de is not None and de < 1e-9) else "  <-- BROKEN"
    if flag:
        bad.append(k)
    print("  %-8s IoU %.3f  interior dE %.2f%s" % (k, iou, de, flag))
print("  %s" % ("CONTROL FAILED on %s: the measure cannot recognise one picture as itself, so "
                "nothing below means anything." % ", ".join(bad) if bad
               else "Control holds: the measure reports a picture as identical to itself."))

is_part = {k: Path(r["icon"]["sheet"]).name != "items.png" for k, r in zip(kinds, ROWS)}

print("\nALL %d PAIRS, worst first by silhouette. dE is over the OVERLAP only, so a pair with"
      % (len(kinds) * (len(kinds) - 1) // 2))
print("little overlap has a dE drawn from few pixels -- the two columns are read together.")
print("(reg) marks a part/part pair, where IoU is largely REGISTRATION about the join and not")
print("shape: head is placed on the far side of it from handle, frame and hopper.")
pairs = []
for a, b in itertools.combinations(kinds, 2):
    iou, de, n = compare(icons[a], icons[b])
    pairs.append((iou, de, n, a, b))
pairs.sort(key=lambda p: -p[0])
for iou, de, n, a, b in pairs:
    des = "   --  (no shared pixel)" if de is None else "%6.2f" % de
    tag = " (reg)" if (is_part[a] and is_part[b]) else "      "
    mark = "  <-- same outline AND same colour" if (de is not None and iou >= 0.5
                                                    and de < DISTINCT) else ""
    print("  %-8s / %-8s%s IoU %.3f   interior dE %s   over %4d px%s"
          % (a, b, tag, iou, des, n, mark))

worst = pairs[0]
print("\nWORST SILHOUETTE PAIR: %s / %s at IoU %.3f." % (worst[3], worst[4], worst[0]))
same_fam = [p for p in pairs if p[1] is not None and p[0] >= 0.5 and p[1] < DISTINCT]
print("PAIRS CLOSE ON BOTH (IoU >= 0.5 and interior dE < %.1f): %s"
      % (DISTINCT, ", ".join("%s/%s" % (p[3], p[4]) for p in same_fam) if same_fam else "none"))

overlapping_parts = [p for p in pairs if is_part[p[3]] and is_part[p[4]] and p[2] > 0]
if overlapping_parts:
    print("\nAMONG PARTS, the pairs that actually share the join's side -- the only part/part")
    print("numbers that are about SHAPE rather than placement:")
    for iou, de, n, a, b in overlapping_parts:
        print("  %-8s / %-8s  IoU %.3f   interior dE %6.2f" % (a, b, iou, de))
print("\nI propose no threshold. Maren rules whether this is enough, on the picture.")

# ------------------------------------------------------------------ the sheet
BG = (48, 48, 48)
Z = 6
PAD = 6


# The sheets' one font, shared (ASSA-114). It was three copies of `load_default`,
# which has no glyph for the U+00D7 in every stack line, so all three drew a tofu box.
from review_font import font  # noqa: E402


f11, f13, f15 = font(11), font(13), font(15)
bw, bh = icons[kinds[0]][0].size
cell = bw * Z
top_h = 26 + bh * Z + 18
# 1:1 strip under the magnified one: the size the judgement is actually about.
one_h = bh + 16
rows_shown = min(4, len(pairs))
pair_h = 20 + bh * Z + 16
# Wide enough for BOTH strips: the seven kinds, and the pair row, which is two icons per pair
# and ran off the right edge when the width was set from the kinds alone.
W = max(PAD * 2 + len(kinds) * (cell + PAD), PAD * 2 + rows_shown * (2 * cell + 20), 760)
# GENEROUS, THEN CROPPED TO THE CONTENT at the end. Computing the exact height from a formula
# is how the last three caption lines got silently cut off the first time this sheet rendered:
# the formula and the drawing code each knew the layout and only one of them was updated.
H = top_h + one_h + 30 + pair_h + 60 + 22 * (rows_shown + 24)
img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)

d.text((PAD, 6), "WHAT THE ICON HAS TO SAY NOW THAT THE BUTTONS DO NOT (ASSA-101)",
       font=f15, fill=(245, 245, 245))
y = 26
for i, k in enumerate(kinds):
    x = PAD + i * (cell + PAD)
    img.paste(icons[k][0].resize((cell, bh * Z), Image.NEAREST), (x, y))
    d.text((x, y + bh * Z + 3), k, font=f13, fill=(235, 235, 235))
y += bh * Z + 18

d.text((PAD, y + 1), "THE SAME SEVEN AT 1:1, which is the size being judged:",
       font=f13, fill=(210, 210, 210))
y += 16
for i, k in enumerate(kinds):
    img.paste(icons[k][0], (PAD + i * (bw + 6), y))
y += bh + 14

d.text((PAD, y), "THE FOUR CLOSEST PAIRS BY SILHOUETTE (IoU), left to right:",
       font=f13, fill=(210, 210, 210))
y += 20
x = PAD
for iou, de, n, a, b in pairs[:rows_shown]:
    img.paste(icons[a][0].resize((cell, bh * Z), Image.NEAREST), (x, y))
    img.paste(icons[b][0].resize((cell, bh * Z), Image.NEAREST), (x + cell + 2, y))
    d.text((x, y + bh * Z + 2), "%s / %s" % (a, b), font=f11, fill=(235, 235, 235))
    d.text((x, y + bh * Z + 14), "IoU %.2f  dE %s"
           % (iou, "--" if de is None else "%.1f" % de), font=f11, fill=(190, 190, 190))
    x += 2 * cell + 20
y += bh * Z + 32

part_fill = ", ".join("%s %.0f%%" % (k, 100.0 * len(icons[k][1]) / slot)
                      for k in kinds if is_part[k])
item_fill = ", ".join("%s %.0f%%" % (k, 100.0 * len(icons[k][1]) / slot)
                      for k in kinds if not is_part[k])
lines = [
    "A pack is ONE player's, so every icon carries the SAME species tint (#%s here, the tint"
    % sorted(tints)[0],
    "the demo starts on). Hue does no kind work inside a pack: only silhouette and value do.",
    "",
    "IoU is shape alone -- it cannot see colour. Interior dE is colour alone, over the pixels",
    "where both are ink -- it cannot see shape. A pair close on BOTH is told apart by neither.",
    "",
    "THE PART ROWS ARE DRAWN OUT OF THE ASSEMBLY SHEETS. rig.py rule 3: 'a part is drawn to be",
    "assembled, and items.py is where loose things on the ground are drawn.' So a part sits",
    "where it sits on a machine -- head RIGHT of the join, handle/frame/hopper LEFT -- and its",
    "frame is 2 tiles wide, which KEEP_ASPECT fits by width into 32x25.5 of a 32x48 slot.",
    "Ink filling that slot:  parts %s   vs items %s." % (part_fill, item_fill),
    "That is also why three part/part pairs score IoU 0.000: head is simply on the other side",
    "of the join. CORRECTED (ASSA-104), and the attribution matters because the correction is",
    "the useful part: the claim that re-centring the part frames would DELETE that separation",
    "was MAREN'S, in her 04:39 deferral, and she reversed it herself at 05:11 with the numbers.",
    "What was mine is worse and is the reason this line is still here -- I took the argument",
    "because it came from my manager and sounded tidy, and wrote it into my own notes as a",
    "lesson about me. Deference is not verification. It does not hold. A uniform shift moves",
    "every part by the same amount and the",
    "registration is RELATIVE, so the 3px window move shipped in #141 left the three head pairs",
    "at exactly 0.000 and moved the rest TOWARD more separation. What would spend it is moving",
    "the parts relative to EACH OTHER, which is the items.py job, not a trim.",
    "",
    "THERE IS NOW A GATE, and this file is still not it: art/check_icon_kinds.py (ASSA-111) runs",
    "in CI on the player-facing property -- no pair close on BOTH measures. This sheet still",
    "proposes no threshold of its own; dE %.1f is quoted from species_probe.DISTINCT."
    % DISTINCT,
]
for ln in lines:
    d.text((PAD, y), ln, font=f11, fill=(200, 200, 200))
    y += 14
y += 6
for iou, de, n, a, b in pairs[:rows_shown + 3]:
    d.text((PAD, y), "%-8s / %-8s   IoU %.3f   interior dE %s   over %d px"
           % (a, b, iou, "--" if de is None else "%.2f" % de, n), font=f11, fill=(225, 225, 225))
    y += 14

img = img.crop((0, 0, W, min(H, y + 8)))
img.save(OUT, pnginfo=review_sources.png_info())
print("\nwrote %s (%dx%d)" % (OUT, img.width, img.height))
