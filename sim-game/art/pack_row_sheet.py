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

ONE COLUMN NOW, AND ONE COLOUR OF BUTTON (Maren, after ASSA-103). This sheet used to draw the pack
twice -- "nothing chosen" beside "a frame chosen" -- because `stack_verbs` returned `"Mount" if
building else "Frame"` and every part row changed its word mid-assembly. ASSA-103 made the word a
property of the KIND, so the two columns became identical: measured off the real scene, not assumed
(handle/frame say Frame, head/hopper say Mount, in both asks). Half the sheet's width was buying two
red boxes moving. The comparison survives as a DERIVED LINE in the caption, which is the stronger
form: a diff that fires is a sentence, where a second identical column is something a reader has to
notice is identical.

AND NOTHING IS PAINTED AS REFUSED, because the client paints nothing as refused. `main.gd:_button`
sets no `disabled`, no modulate and no override -- that is Maren's own ASSA-37 ruling ("nothing is
disabled; the button stays pressable and the sim does the refusing"), and ASSA-103 answers the press
with the sim's sentence instead. A sheet headed "AS IT SHIPS" may paint only what ships, and four
angry red buttons were the loudest thing on a page about a screen that has none.

THE REFUSAL IS A FACT ABOUT THE SIM, SO IT IS TEXT. And the sheet states only the half it can
actually compute. `permanent_fault` has three rules, not two: the first part must be a frame
(`FrameIsNotAFrame`), a frame may not be mounted (`FrameMounted`), and a mount needs a slot on THAT
frame (`NoSuchSlot`). The first depends only on `is_frame`, which the probe reads from the sim's
catalogue, so the sheet can be certain about it. The other two depend on WHICH frame was chosen --
`assembly.rs` is explicit that "a held frame offers no hopper slot at all" -- so "a frame chosen" was
never one state, and the old right-hand column drew a hopper as pressable that a handle always
refuses. The sheet names that limit rather than printing a confident wrong set.

Frame-ness is read from the sim's catalogue, never from the button saying the word "Frame", which
would be a fact about English -- the same trap the verb split had to avoid (see `_is_frame_kind`).
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


def cannot_be_first(entry):
    """Would the sim refuse this row as the FIRST part of a design?

    `permanent_fault` opens with `if !frame.is_frame() { FrameIsNotAFrame }`, so the answer
    depends on `is_frame` ALONE -- no chosen frame, no slot table, nothing this sheet would have
    to guess at. That is the whole reason this is the one refusal stated here: the other two
    (`FrameMounted`, `NoSuchSlot`) need to know WHICH frame was chosen, and a handle and a
    planted frame give different answers for the same hopper.

    `is_frame` is -1 for a row that is not a part at all, which is never a first part question.
    """
    return entry.get("is_frame", -1) == 0


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
    # EVERY BUTTON THE SAME, because `main.gd:_button` builds every button the same: no
    # `disabled`, no modulate, no theme override (ASSA-37, and ASSA-103 answers the press with
    # the sim's sentence instead). A refusal is not a pixel on this screen, so it is not a pixel
    # on this sheet.
    for label, box in zip(entry["verbs"], entry.get("verb_boxes", [])):
        bx, by, bw, bh = box
        x0, y0, x1, y1 = bx, oy + by, bx + bw - 1, oy + by + bh - 1
        d.rectangle([x0, y0, x1, y1], outline=(170, 170, 170), fill=(92, 92, 92))
        f = font(12)
        tw = d.textlength(label, font=f)
        d.text((x0 + (bw - tw) / 2, y0 + (bh - 12) / 2 - 1), label, font=f, fill=(240, 240, 240))


def build_column():
    col_h = sum(int(r["row_size"][1]) for r in ROWS) + GAP * (len(ROWS) - 1)
    col = Image.new("RGBA", (PANEL, col_h), BG)
    y = 0
    for r in ROWS:
        draw_row(col, r, y)
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

column = build_column()
summary = [(r["line"], len(r.get("verb_kinds", [])), int(r["row_size"][1]),
            cannot_be_first(r)) for r in ROWS]

# DOES THE WORD STILL SWAP? Computed, never asserted in prose. This is what the second column used
# to be: `labels_building` is the probe asking `stack_verbs` a second time, and since ASSA-103 it
# must come back identical for every row. A sentence that fires beats a picture a reader has to
# notice is identical -- and if it ever fires, it names the rows rather than leaving them to be
# spotted.
swapped = [(r["line"], list(r["verbs"]), list(r.get("labels_building", [])))
           for r in ROWS if list(r.get("labels_building", [])) != list(r["verbs"])]

cap = font(13)
head = font(15)
heights = sorted({h for _, _, h, _ in summary})
worst = max(total for _, total, _, _ in summary)
not_first = [l for l, _, _, a in summary if a]

lines = [
    "THE PACK AT 1:1 AS IT SHIPS, AFTER THE ASSA-86 SPLIT (main #128, with #126).",
    "Every rect, size and position is read off the real main.tscn. The verb comes from",
    "AssayHud.stack_verbs' sim-facing `verb`, and frame-ness from the sim's part catalogue --",
    "neither is parsed from the button's text.",
    "GLYPHS ARE THIS SHEET'S FONT, not Godot's -- headless has no renderer. The multiplication",
    "sign used to come out as a BOX here, which was this sheet's font and never the window's;",
    "it is drawn properly now (ASSA-114). What the CLIENT's font does with it is still unseen.",
    "",
    # THE CHECK IS UNIFORMITY, WHICH IS THE PROPERTY RULED ON -- not a remembered number. This
    # read `heights == [48]` and so shouted "IT DID NOT HOLD" at a pack whose rows were all 49px:
    # perfectly uniform, one pixel off a figure someone wrote down once. A bar that hardcodes a
    # quantity is checking something other than what it says (Maren, and her own recurring defect).
    "ROW HEIGHTS: %s. Maren declined to add a row-height rule, on the grounds that a uniform"
    % ", ".join("%dpx" % h for h in heights),
    "height falls out of the verb split and so cannot drift from it. %s"
    % ("That holds: every row is the same height, and the refined row was 72px before."
       if len(heights) == 1 else "IT DID NOT HOLD -- the heights above disagree."),
    "WORST ROW: %d verbs (it was 7). Three button sets across seven rows." % worst,
    "",
]
for line, total, h, a in summary:
    when = "  <-- cannot be the first part" if a else ""
    lines.append("  %-26s %d verb%s  %dpx%s"
                 % (line, total, " " if total == 1 else "s", h, when))
lines += [
    "",
    "THE WORD IS THE KIND'S, AND THIS LINE IS COMPUTED, NOT CLAIMED (ASSA-103). The probe asks",
    "`stack_verbs` a second time as if an assembly were part-way built; every label must come back",
]
lines += ([
    "the same, and all %d rows do. The word has stopped swapping." % len(ROWS),
] if not swapped else [
    "THE SAME, AND %d ROW(S) DO NOT -- the word is swapping again:" % len(swapped),
] + ["    %-26s %s -> %s" % (ln, a, b) for ln, a, b in swapped])
lines += [
    "",
    "NOTHING IS DRAWN AS REFUSED, BECAUSE THE CLIENT DRAWS NOTHING AS REFUSED: `_button` sets no",
    "`disabled`, no modulate, no override (ASSA-37), and ASSA-103 answers a bad press at the press",
    "with the sim's own sentence. The one refusal this sheet can be CERTAIN of is the first-part",
    "rule, which `permanent_fault` decides from `is_frame` alone:",
    "  cannot be the first part -> %s" % (", ".join(not_first) if not_first else "none"),
    "`FrameIsNotAFrame` is the unrecoverable one: no later press can fix a buffer that starts wrong.",
    "AND THE SHEET STOPS THERE ON PURPOSE. The other two faults -- `FrameMounted`, `NoSuchSlot` --",
    "need to know WHICH frame was chosen, so \"a frame chosen\" was never one state: assembly.rs says",
    "a held frame offers no hopper slot at all, where a planted one does. The old second column drew",
    "one picture of that and so drew a hopper as pressable that a handle always refuses.",
]

cap_h = PAD * 2 + len(lines) * 17
W = max(PANEL + PAD * 2, 860)
H = cap_h + column.height + PAD * 2 + 20
sheet = Image.new("RGBA", (W, H), (34, 34, 34))
d = ImageDraw.Draw(sheet)
yy = PAD
for i, line in enumerate(lines):
    d.text((PAD, yy), line, font=head if i == 0 else cap, fill=(236, 236, 236))
    yy += 17
d.text((PAD, cap_h), "THE PACK, AT 1:1, EXACTLY AS THE CLIENT DRAWS IT", font=cap,
       fill=(210, 210, 210))
sheet.alpha_composite(column, (PAD, cap_h + 20))
OUT.parent.mkdir(parents=True, exist_ok=True)
sheet.convert("RGB").save(OUT)

for line, total, h, a in summary:
    print("%-28s %d verbs  %dpx  cannot be first: %s" % (line, total, h, a))
print("word swaps: %s" % (swapped if swapped else "none (ASSA-103 holds)"))
print("row heights: %s   worst row: %d verbs" % (heights, worst))
print("sheet written to %s (%dx%d)" % (OUT, sheet.width, sheet.height))
