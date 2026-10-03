#!/usr/bin/env -S uv run --quiet --with pillow python
"""THE PACK ROWS AT 1:1, AS THEY SHIP. (ASSA-105; was ASSA-99, for ASSA-86)

    godot --headless --path client --script "$PWD/art/pack_icon_layout.gd" \
      | sed -n 's/^LAYOUT_JSON //p' > /tmp/layout.json
    uv run --with pillow python art/pack_row_sheet.py /tmp/layout.json

Maren ruled ASSA-86 from counts -- four stacks, ten buttons, a refined row carrying seven in a
320px column -- and asked for the picture. `pack_icon_sheet.py` beside this one is about the icon's
SCALE; this one is about the ROW, which is what the board called clunky.

THE SPLIT IS THE SIM'S, NOT MY READING OF THE LABELS. Maren's ruling keeps the verbs that MOVE an
item (Fuel, Smelt, Place, Frame/Mount) and sends the ones that MAKE something to the crafting menu.
`pack_icon_layout.gd` records each button's `verb` from `AssayHud.stack_verbs`, which reads the
sim's recipe table -- so "Craft gear" is a make-verb because the command is `craft`, not because the
label starts with the word Craft. Parsing my own labels would be a fact about English.

WHAT CHANGED, AND WHY THIS FILE NOW DRAWS A DIFFERENT PICTURE. The ASSA-99 version of this sheet
deliberately did NOT draw the panel after the split: the kept buttons would re-flow, and inventing
that layout would have been a measurement of my own guess. The split landed (#128, with #126), so
the panel exists and drawing it is reporting rather than guessing. The struck-through make-verbs are
gone from the sheet because they are gone from the client.

TWO STATES, BECAUSE THE PART ROWS HAVE TWO. `stack_verbs` returns `"Mount" if building else
"Frame"`, so every part row says a different word once a frame has been chosen. A laid-out row can
only be in one state at a time, so the second column's labels come from `labels_building` -- the
probe asking the same function again -- never from a word typed in here.

AND THE SHEET MARKS WHICH OF THOSE WORDS THE SIM ALWAYS REFUSES, because that is the thing a picture
of four identical buttons cannot say on its own. Frame-ness is read from the sim's catalogue: a
kind's `tag` is the serde form of `PartTag`, so `{"Frame": "Held"}` is a frame and `"Head"` is not
(see `_is_frame_kind` in the probe). It is NOT read from the button saying the word "Frame", which
would be a fact about English -- the same trap the verb split had to avoid.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent.parent
LAYOUT = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "/tmp/cove-layout99.json"))
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE / "assets/review/pack_rows.png"
SPRITES = HERE / "client/assets/sprites"

ROWS = LAYOUT["rows"]
PANEL = int(LAYOUT["panel_px"])
# Maren's ASSA-86 ruling, as sim verbs: these three MOVE an item and stay on the row.
MOVE = {"insert", "place", "build"}


def clear_colour():
    nums = LAYOUT["clear_color"].strip("()").split(",")
    return tuple(int(round(float(n) * 255)) for n in nums[:3])


BG = clear_colour()
PLATE = tuple(json.load(open(SPRITES / "ui_theme.json"))["pack_icon_plate_rgb"])
PAD, GAP = 14, 10


# The sheets' one font, shared (ASSA-114). It was three copies of `load_default`,
# which has no glyph for the U+00D7 in every stack line, so all three drew a tofu box.
from review_font import font  # noqa: E402


def icon_of(entry):
    """The row's icon, tinted and scaled exactly as the layout says the engine drew it."""
    if "icon" not in entry:
        return None
    ic = entry["icon"]
    sheet = Image.open(SPRITES / Path(ic["sheet"]).name).convert("RGBA")
    x, y, w, h = ic["region"]
    frame = sheet.crop((int(x), int(y), int(x + w), int(y + h)))
    dw, dh = ic["drawn"]
    frame = frame.resize((max(1, int(round(dw))), max(1, int(round(dh)))), Image.NEAREST)
    t = tuple(int(ic["modulate"][i:i + 2], 16) for i in (0, 2, 4))
    px = frame.load()
    for yy in range(frame.height):
        for xx in range(frame.width):
            r, g, b, a = px[xx, yy]
            px[xx, yy] = (r * t[0] // 255, g * t[1] // 255, b * t[2] // 255, a)
    return frame


def refused(entry, building):
    """Would the sim refuse the word this part row is showing, in this state?

    `Assembly::validate` wants the FIRST part to be a frame and refuses a frame mounted on a
    frame, so with nothing chosen a non-frame kind pressing `Frame` is `FrameIsNotAFrame`, and
    once a frame is chosen a frame kind pressing `Mount` is `FrameMounted`. Exactly the kinds
    whose frame-ness disagrees with the state.

    `is_frame` is -1 for a row that is not a part at all, which is never refused here.
    """
    is_frame = entry.get("is_frame", -1)
    if is_frame < 0:
        return False
    return is_frame == 1 if building else is_frame == 0


def draw_row(dst, entry, oy, building=False):
    d = ImageDraw.Draw(dst)
    icon = icon_of(entry)
    rh = int(entry["row_size"][1])
    if icon is not None:
        # The slot plate is the icon's own 32x48 box (ASSA-71), centred in the row.
        box_y = oy + (rh - 48) // 2
        d.rectangle([0, box_y, 31, box_y + 47], fill=PLATE)
        dst.alpha_composite(icon, (int((32 - icon.width) / 2), box_y + int((48 - icon.height) / 2)))
    d.text((38, oy + 4), entry["line"], font=font(13), fill=(236, 236, 236))
    # In the building state the labels are the probe's second ask of `stack_verbs`, not a word
    # composed here. Same boxes: only the caption on the button changes.
    labels = entry.get("labels_building", []) if building else entry["verbs"]
    dead = refused(entry, building)
    for label, box in zip(labels, entry.get("verb_boxes", [])):
        bx, by, bw, bh = box
        x0, y0, x1, y1 = bx, oy + by, bx + bw - 1, oy + by + bh - 1
        d.rectangle([x0, y0, x1, y1],
                    outline=(196, 104, 92) if dead else (170, 170, 170),
                    fill=(74, 50, 48) if dead else (92, 92, 92))
        f = font(12)
        tw = d.textlength(label, font=f)
        d.text((x0 + (bw - tw) / 2, y0 + (bh - 12) / 2 - 1), label, font=f,
               fill=(236, 150, 136) if dead else (240, 240, 240))
        if dead:
            # The sim refuses this press every time, in this state, for this kind.
            d.text((x1 + 6, y0 + (bh - 12) / 2 - 1), "always refused", font=font(11),
                   fill=(214, 128, 110))


def build_column(building):
    col_h = sum(int(r["row_size"][1]) for r in ROWS) + GAP * (len(ROWS) - 1)
    col = Image.new("RGBA", (PANEL, col_h), BG)
    y = 0
    for r in ROWS:
        draw_row(col, r, y, building)
        y += int(r["row_size"][1]) + GAP
    return col


if not ROWS:
    raise SystemExit("pack_row_sheet: the probe returned NO ROWS. The pack panel was rebuilt and "
                     "the probe no longer finds it -- that is a broken instrument, not an empty "
                     "pack, and an empty sheet would have said the opposite.")
missing = [r["line"] for r in ROWS if "icon" not in r]
if missing:
    raise SystemExit("pack_row_sheet: no icon found on %d row(s): %s. The icon moved under a new "
                     "wrapper and the probe stopped finding it." % (len(missing), missing))

column = build_column(False)
column_building = build_column(True)
summary = [(r["line"], len(r.get("verb_kinds", [])), int(r["row_size"][1]),
            refused(r, False), refused(r, True)) for r in ROWS]

cap = font(13)
head = font(15)
heights = sorted({h for _, _, h, _, _ in summary})
worst = max(total for _, total, _, _, _ in summary)
dead_a = [l for l, _, _, a, _ in summary if a]
dead_b = [l for l, _, _, _, b in summary if b]

lines = [
    "THE PACK AT 1:1 AS IT SHIPS, AFTER THE ASSA-86 SPLIT (main #128, with #126).",
    "Every rect, size and position is read off the real main.tscn. The verb comes from",
    "AssayHud.stack_verbs' sim-facing `verb`, and frame-ness from the sim's part catalogue --",
    "neither is parsed from the button's text.",
    "GLYPHS ARE THIS SHEET'S FONT, not Godot's -- headless has no renderer. The multiplication",
    "sign used to come out as a BOX here, which was this sheet's font and never the window's;",
    "it is drawn properly now (ASSA-114). What the CLIENT's font does with it is still unseen.",
    "",
    "ROW HEIGHTS: %s. Maren declined to add a row-height rule, on the grounds that a uniform"
    % ", ".join("%dpx" % h for h in heights),
    "height falls out of the verb split and so cannot drift from it. %s"
    % ("That holds: the refined row was 72px before and is 48px now."
       if heights == [48] else "IT DID NOT HOLD -- see the heights above."),
    "WORST ROW: %d verbs (it was 7). Three button sets across seven rows." % worst,
    "",
]
for line, total, h, a, b in summary:
    # WHICH state, not just that there is one: every part row is refused in exactly one of the
    # two, and which one is the whole content of the defect. "one state or both" was true and
    # said nothing.
    when = "  <-- always refused with %s" % (" and ".join(
        s for s, on in (("nothing chosen", a), ("a frame chosen", b)) if on)) if (a or b) else ""
    lines.append("  %-26s %d verb%s  %dpx%s"
                 % (line, total, " " if total == 1 else "s", h, when))
lines += [
    "",
    "LEFT: nothing chosen yet. RIGHT: the same pack once a frame has been chosen -- the only",
    "difference `stack_verbs` makes is the word, so the boxes are identical and the caption is not.",
    "",
    "RED = THE SIM REFUSES THAT PRESS EVERY TIME. Maren's ASSA-86 ruling 1 (the label is a property",
    "of the KIND, not of the state) is NOT in this build: all four part rows still say one word.",
    "  nothing chosen -> %s" % (", ".join(dead_a) if dead_a else "none"),
    "  frame chosen   -> %s" % (", ".join(dead_b) if dead_b else "none"),
    "`FrameIsNotAFrame` is the unrecoverable one: no later press can fix a buffer that starts wrong.",
    "AND THE TWO HALVES SWAP: in each state exactly two of the four part rows are pressable, and",
    "never the same two. There is no state of this pack in which all four part rows work.",
]

cap_h = PAD * 2 + len(lines) * 17
COLGAP = 150  # room for the "always refused" note beside the right-hand column's buttons
W = max(PANEL * 2 + COLGAP + PAD * 2, 860)
H = cap_h + column.height + PAD * 2 + 20
sheet = Image.new("RGBA", (W, H), (34, 34, 34))
d = ImageDraw.Draw(sheet)
yy = PAD
for i, line in enumerate(lines):
    d.text((PAD, yy), line, font=head if i == 0 else cap, fill=(236, 236, 236))
    yy += 17
d.text((PAD, cap_h), "NOTHING CHOSEN", font=cap, fill=(210, 210, 210))
d.text((PAD + PANEL + COLGAP, cap_h), "A FRAME CHOSEN", font=cap, fill=(210, 210, 210))
sheet.alpha_composite(column, (PAD, cap_h + 20))
sheet.alpha_composite(column_building, (PAD + PANEL + COLGAP, cap_h + 20))
OUT.parent.mkdir(parents=True, exist_ok=True)
sheet.convert("RGB").save(OUT)

for line, total, h, a, b in summary:
    print("%-28s %d verbs  %dpx  refused: nothing=%s frame=%s" % (line, total, h, a, b))
print("row heights: %s   worst row: %d verbs" % (heights, worst))
print("sheet written to %s (%dx%d)" % (OUT, sheet.width, sheet.height))
