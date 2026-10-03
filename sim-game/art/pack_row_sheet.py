#!/usr/bin/env -S uv run --quiet --with pillow python
"""THE PACK ROWS AT 1:1, WITH THE VERBS MARKED BY WHAT THEY DO. (ASSA-99, for ASSA-86)

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

WHAT THIS DOES NOT DO: show the panel AFTER the split. The remaining buttons would re-flow, the row
would get shorter, and I have not measured that layout because it does not exist yet -- it is
Limpet's to build. Inventing it here would be me drawing a client that nobody has written. So the
make-verbs are struck through where they sit, and the count beside each row says what survives.
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


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


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


def draw_row(dst, entry, oy):
    d = ImageDraw.Draw(dst)
    icon = icon_of(entry)
    rh = int(entry["row_size"][1])
    if icon is not None:
        # The slot plate is the icon's own 32x48 box (ASSA-71), centred in the row.
        box_y = oy + (rh - 48) // 2
        d.rectangle([0, box_y, 31, box_y + 47], fill=PLATE)
        dst.alpha_composite(icon, (int((32 - icon.width) / 2), box_y + int((48 - icon.height) / 2)))
    d.text((38, oy + 4), entry["line"], font=font(13), fill=(236, 236, 236))
    kinds = entry.get("verb_kinds", [])
    for i, (label, box) in enumerate(zip(entry["verbs"], entry.get("verb_boxes", []))):
        bx, by, bw, bh = box
        x0, y0, x1, y1 = bx, oy + by, bx + bw - 1, oy + by + bh - 1
        moves = i < len(kinds) and kinds[i] in MOVE
        d.rectangle([x0, y0, x1, y1],
                    outline=(170, 170, 170) if moves else (120, 96, 96),
                    fill=(92, 92, 92) if moves else (60, 52, 52))
        f = font(12)
        tw = d.textlength(label, font=f)
        d.text((x0 + (bw - tw) / 2, y0 + (bh - 12) / 2 - 1), label, font=f,
               fill=(240, 240, 240) if moves else (150, 130, 130))
        if not moves:
            # Struck through: this button leaves the row for the crafting menu.
            d.line([(x0 + 3, (y0 + y1) // 2), (x1 - 3, (y0 + y1) // 2)], fill=(214, 128, 110), width=1)


col_h = sum(int(r["row_size"][1]) for r in ROWS) + GAP * (len(ROWS) - 1)
column = Image.new("RGBA", (PANEL, col_h), BG)
y = 0
summary = []
for r in ROWS:
    draw_row(column, r, y)
    y += int(r["row_size"][1]) + GAP
    kinds = r.get("verb_kinds", [])
    keep = sum(1 for k in kinds if k in MOVE)
    summary.append((r["line"], len(kinds), keep))

cap = font(13)
head = font(15)
lines = [
    "THE PACK AT 1:1, AND WHICH BUTTONS ASSA-86 SENDS TO THE CRAFTING MENU.",
    "Every rect, size and position is read off the real main.tscn after #122. Struck-through",
    "buttons are MAKE verbs (sim `craft`/`make`); solid ones MOVE the item and stay on the row.",
    "The verb kind comes from AssayHud.stack_verbs via the sim's recipe table, not from the label.",
    "GLYPHS ARE THIS SHEET'S FONT, not Godot's -- headless has no renderer -- so the client's",
    "multiplication sign comes out as a box here. That is mine, not the window's.",
    "",
]
for line, total, keep in summary:
    lines.append("  %-26s %d verb%s  ->  %d after the split" % (line, total, "" if total == 1 else "s", keep))
lines += [
    "",
    "The panel AFTER the split is not drawn: the kept buttons would re-flow and the rows would",
    "get shorter, and that layout does not exist yet. It is Limpet's to build, not mine to invent.",
]

cap_h = PAD * 2 + len(lines) * 17
W = max(PANEL + PAD * 2, 760)
H = cap_h + column.height + PAD * 2
sheet = Image.new("RGBA", (W, H), (34, 34, 34))
d = ImageDraw.Draw(sheet)
yy = PAD
for i, line in enumerate(lines):
    d.text((PAD, yy), line, font=head if i == 0 else cap, fill=(236, 236, 236))
    yy += 17
sheet.alpha_composite(column, (PAD, cap_h))
OUT.parent.mkdir(parents=True, exist_ok=True)
sheet.convert("RGB").save(OUT)

for line, total, keep in summary:
    print("%-28s %d verbs -> %d kept" % (line, total, keep))
print("sheet written to %s (%dx%d)" % (OUT, sheet.width, sheet.height))
