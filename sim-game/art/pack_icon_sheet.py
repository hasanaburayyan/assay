#!/usr/bin/env python3
"""THE PACK ROW AS THE ENGINE DRAWS IT, so a person can look at it (ASSA-57).

    godot --headless --path client --script "$PWD/art/pack_icon_layout.gd" \
      | sed -n 's/^LAYOUT_JSON //p' > /tmp/layout.json
    uv run --with pillow python art/pack_icon_sheet.py /tmp/layout.json

An ABSOLUTE path to the probe, not `res://`: it lives outside the Godot project on purpose, the
same way the review sheets do, so an export can never pack it.

NOT A GATE. There is no threshold in here and there should not be one yet: what it reports is a
spread between species, and which spread is acceptable is the Game Director's call, not a number
I may pick on my own. It exists so that call can be made by looking.

Every number that decides geometry comes from the layout JSON, which is Godot's answer
after `main.tscn` was instantiated and the real pack rebuilt: the laid-out rect of each
TextureRect, the atlas region, `modulate`, the row height, the font size and the clear colour.
Nothing here is a constant copied out of a GDScript file.

WHAT IS REPLICATED RATHER THAN ASKED. Headless Godot has no renderer, so the one thing this
cannot ask the engine for is the pixels. The two documented rules that stand in for it --
STRETCH_KEEP_ASPECT_CENTERED and TEXTURE_FILTER_NEAREST, and why a half-pixel rect (25.5) at a
non-integer scale (15/32) makes them matter -- now live in `art/pack_icon_draw.py`, which is
imported below. They moved there when `pack_icon_kinds.py` needed the same pixels to ask a
different question, so that the two sheets can never disagree about what the client drew.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ask_layout import kind_of  # noqa: E402  one reader of what a row holds
from pack_icon_draw import nearest_blit  # noqa: E402  the engine's own sampling, defined once

HERE = Path(__file__).resolve().parent.parent
LAYOUT = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "/tmp/cove-layout.json"))
SPRITES = HERE / "client/assets/sprites"
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE / "assets/review/pack_icons.png"

TINTS = ["7A29CC", "FF3333", "FF80BF", "FFFF33", "3333FF", "509BE6"]


def srgb_to_lin(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = (srgb_to_lin(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def clear_colour():
    """The viewport's own clear colour, as the framebuffer gets it. 2D is sRGB-native."""
    nums = LAYOUT["clear_color"].strip("()").split(",")
    return tuple(int(round(float(n) * 255)) for n in nums[:3])


BG = clear_colour()


def tint_of(entry):
    h = entry["icon"]["modulate"]
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def frame_of(entry):
    """The atlas region as its own RGBA image."""
    sheet = Image.open(SPRITES / Path(entry["icon"]["sheet"]).name).convert("RGBA")
    x, y, w, h = entry["icon"]["region"]
    return sheet.crop((int(x), int(y), int(x + w), int(y + h)))


def plate_of(entry):
    """The slot plate the ENGINE painted behind this icon, or None when it painted none.

    READ OFF THE LAYOUT JSON, NOT RECOMPUTED FROM `ground.png`. This script used to open the
    ground sheet and take its median itself. That was honest while no plate existed -- it was
    drawing a proposal -- and became a trap the moment one did, because it would have gone on
    showing a correct-looking plate even if the client never read `ui_theme.json`, never applied
    the StyleBoxFlat, or applied some other colour. The picture would have agreed with the
    pipeline while disagreeing with the game. That is panel 3's stale-caption bug with the
    halves swapped, and every other number in this file is already what the engine did.
    """
    h = entry["icon"].get("plate") or ""
    if len(h) < 6:
        return None
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def plate_rect_of(entry, row_h):
    """The plate's laid-out size, falling back to the icon box when there is no plate."""
    rect = entry["icon"].get("plate_rect") or []
    return (float(rect[0]), float(rect[1])) if len(rect) == 2 else (ICON, float(row_h))


def ink_bbox(frame):
    bbox = frame.split()[-1].getbbox()
    return bbox


# The sheets' one font, shared (ASSA-114). It was three copies of `load_default`,
# which has no glyph for the U+00D7 in every stack line, so all three drew a tofu box.
from review_font import font  # noqa: E402


ROWS = LAYOUT["rows"]
PANEL = int(LAYOUT["panel_px"])
ICON = LAYOUT["icon_px"]
SEP = ROWS[0]["separation"]

# ---------------------------------------------------------------- panel 1: the column, 1:1
col_h = sum(int(r["row_size"][1]) for r in ROWS) + 10 * (len(ROWS) - 1)
column = Image.new("RGB", (PANEL, col_h), BG)
d = ImageDraw.Draw(column)
f13 = font(13)
f12 = font(12)
y = 0
report = []
for r in ROWS:
    rh = int(r["row_size"][1])
    x = 0
    if "icon" in r:
        dw, dh = r["icon"]["drawn"]
        s = min(ICON / r["icon"]["frame"][0], rh / r["icon"]["frame"][1])
        assert abs(s - r["icon"]["scale"]) < 1e-6, (s, r["icon"]["scale"])
        frame = frame_of(r)
        # THE SLOT PLATE, BEFORE THE ICON, so the ink composites over what it really sits on
        # (ASSA-71). The plate is `SIZE_SHRINK_CENTER` in the row, so it is centred on the row's
        # own centre -- which is the same centre the icon is drawn on, and why a 72px refined row
        # still shows a 48px plate. Drawn first and not merely measured: an antialiased edge
        # blends with its background, so measuring the ink over the clear colour and then
        # claiming a plate was behind it would be a different picture from the one that ships.
        base = BG
        plate_c = plate_of(r)
        if plate_c is not None:
            pw, ph = plate_rect_of(r, rh)
            py = y + (rh - ph) / 2.0
            d.rectangle([0, int(round(py)), int(round(pw)) - 1, int(round(py + ph)) - 1],
                        fill=plate_c)
            base = plate_c
        ink = nearest_blit(column, frame, tint_of(r), (ICON - dw) / 2.0, y + (rh - dh) / 2.0, dw, dh)
        report.append((r["line"], r["icon"], ink, ink_bbox(frame), frame.size, base))
        x = ICON + SEP
    else:
        report.append((r["line"], None, [], None, None, BG))
    d.text((x, y + 1), r["line"], font=f13, fill=(235, 235, 235))
    # WRAP ONTO A SECOND LINE, which is what the row itself does. This used to reset `vx` to the
    # left margin WITHOUT moving down, so a row with more verbs than fit drew them on top of each
    # other: the refined row affords seven and only the last three survived, under a heading
    # saying this panel is the pack as the engine draws it. The engine gives that row a height of
    # 72 against everyone else's 48 precisely BECAUSE it takes two lines -- the layout JSON was
    # carrying the evidence the picture was contradicting.
    vx, vy = x, y + 18
    for verb in r["verbs"]:
        w = int(d.textlength(verb, font=f12)) + 10
        if vx + w > PANEL:
            vx = x
            vy += 20
        d.rectangle([vx, vy, vx + w, vy + 18], fill=(78, 78, 82), outline=(110, 110, 115))
        d.text((vx + 5, vy + 3), verb, font=f12, fill=(225, 225, 230))
        vx += w + 4
    y += rh + 10

# ---------------------------------------------------------------- panel 2: the icon slot at 4x
ZOOM = 4
zoom_h = sum(int(r["row_size"][1]) for r in ROWS) * ZOOM + 10 * (len(ROWS) - 1)
zoom_w = int(ICON) * ZOOM + 8
zoomed = Image.new("RGB", (zoom_w, zoom_h), BG)
y = 0.0
for r in ROWS:
    rh = int(r["row_size"][1])
    if "icon" in r:
        dw, dh = r["icon"]["drawn"]
        # The plate at 4x too, or this panel shows the slot on a surface the game never draws.
        plate_c = plate_of(r)
        if plate_c is not None:
            pw, ph = plate_rect_of(r, rh)
            py = y + (rh - ph) / 2.0
            ImageDraw.Draw(zoomed).rectangle(
                [0, int(round(py * ZOOM)), int(round(pw * ZOOM)) - 1,
                 int(round((py + ph) * ZOOM)) - 1], fill=plate_c)
        nearest_blit(zoomed, frame_of(r), tint_of(r), (ICON - dw) / 2.0, y + (rh - dh) / 2.0,
                     dw, dh, zoom=ZOOM)
    # IN SOURCE UNITS: `nearest_blit` multiplies by `zoom` itself, and adding zoomed pixels here
    # put five of the six icons off the bottom of the panel. I only noticed by looking at it.
    y += rh + 10.0 / ZOOM

# ------------------------------------------------- panel 3: 15/32 against a clean 1/2, ore, 4x
ore = next(r for r in ROWS if "ore" in r["line"])
ore_frame = frame_of(ore)
fw, fh = ore_frame.size
# WIDE ENOUGH FOR ITS OWN RIGHT-HAND LABEL, not just for the two gems. At 2*32*4+36 the panel was
# 292px and "1/2 = 0.500 (a clean half)" starting at x=164 needed 294, so the sheet explaining the
# shipped scale lost the last two characters of the explanation. Same bug as the sheet width, one
# level down: a picture sized for the pictures and not for the words under them.
CAP_RIGHT = "1/2 = 0.500 (a clean half)"
_right_x = int(ICON) * ZOOM + 36
cmp_w = max(2 * int(ICON) * ZOOM + 36,
            _right_x + int(ImageDraw.Draw(Image.new("RGB", (1, 1))).textlength(CAP_RIGHT, font=f12)) + 4)
cmp_h = 48 * ZOOM + 24
compare = Image.new("RGB", (cmp_w, cmp_h), BG)
nearest_blit(compare, ore_frame, tint_of(ore), 1.0, 1.0, ore["icon"]["drawn"][0],
             ore["icon"]["drawn"][1], zoom=ZOOM)
nearest_blit(compare, ore_frame, tint_of(ore), int(ICON) + 9.0, 1.0, fw * 0.5, fh * 0.5,
             zoom=ZOOM)
dc = ImageDraw.Draw(compare)
# THE LEFT LABEL IS READ, NOT TYPED (Limpet, ASSA-65). The left blit has always used the drawn
# size out of the layout JSON, so the PICTURE followed the client; the caption under it said
# "15/32 = 0.469 (shipped)" as a literal and went stale the moment the icon got a fixed box --
# a panel captioned "shipped" showing a scale that is not shipped. Now the two halves of this
# panel agree when the client is right, which is the point of putting them side by side.
_shipped = ore["icon"]["scale"]
_inverse = 1.0 / _shipped if _shipped else 0.0
dc.text((2, 46 * ZOOM),
        ("1/%d = %.3f (shipped)" % (round(_inverse), _shipped)
         if _shipped and abs(_inverse - round(_inverse)) < 1e-4
         else "%.3f = 1/%.3f (shipped)" % (_shipped, _inverse)),
        font=f12, fill=(240, 240, 240))
dc.text((_right_x, 46 * ZOOM), CAP_RIGHT, font=f12, fill=(240, 240, 240))

# ---------------------------------------------------- panel 4: every species, the same ore icon
sp_w = (int(ICON) + 10) * len(TINTS)
sp_h = 48 + 18
species = Image.new("RGB", (sp_w, sp_h), BG)
ds = ImageDraw.Draw(species)
per_species = []
for i, hexv in enumerate(TINTS):
    tint = tuple(int(hexv[j:j + 2], 16) for j in (0, 2, 4))
    x = i * (int(ICON) + 10)
    ink = nearest_blit(species, ore_frame, tint, x + (ICON - ore["icon"]["drawn"][0]) / 2.0, 2.0,
                       ore["icon"]["drawn"][0], ore["icon"]["drawn"][1])
    cs = sorted(contrast(p, BG) for p in ink)
    per_species.append((hexv, cs))
    ds.text((x, 50), "%.2f" % cs[-1], font=f12, fill=(240, 240, 240))

# ------------------------------------------- panel 5: the same icons on a PLATE of the rock they
# were lit against. The sheets are drawn species-neutral ON LIGHT ROCK (ASSA-19/20) and every
# measurement I have made of them composited them over light rock; the HUD panel is mid-grey, which
# is a surface the art has never been judged on. The plate colour is not picked: it is the ground's
# own median, so the pack row and the map show the same object (Maren's ruling, ASSA-71).
#
# TAKEN FROM THE ENGINE NOW, not from `ground.png`. See `plate_of`.
PLATE = plate_of(ore)
PLATE_SHIPPED = PLATE is not None
if PLATE is None:
    # The engine painted no plate behind the icon it laid out. Fall back to what the PIPELINE
    # ships so this panel still has a proposal to show -- and say which in the caption, because a
    # panel captioned as the client's doing while showing a colour the client ignored is exactly
    # the failure Limpet fixed in panel 3.
    PLATE = tuple(int(v) for v in json.load(open(SPRITES / "ui_theme.json"))["pack_icon_plate_rgb"])
plate = Image.new("RGB", (sp_w, sp_h), BG)
dp = ImageDraw.Draw(plate)
on_plate = []
for i, hexv in enumerate(TINTS):
    tint = tuple(int(hexv[j:j + 2], 16) for j in (0, 2, 4))
    x = i * (int(ICON) + 10)
    dp.rectangle([x, 0, x + int(ICON) - 1, 47], fill=PLATE)
    ink = nearest_blit(plate, ore_frame, tint, x + (ICON - ore["icon"]["drawn"][0]) / 2.0, 2.0,
                       ore["icon"]["drawn"][0], ore["icon"]["drawn"][1])
    cs = sorted(contrast(p, PLATE) for p in ink)
    on_plate.append((hexv, cs))
    dp.text((x, 50), "%.2f" % cs[-1], font=f12, fill=(240, 240, 240))

# ------------------------------------ panel 6: EVERY ART ROW, panel against plate (Maren, ASSA-71)
# Panels 4 and 5 ask the plate question of ORE across six species. Maren's note on ASSA-71 says the
# rows the plate has to work for are the ones nobody has measured: THE FOUR PART ICONS ARE THE
# DARKEST THINGS ON THE PANEL, they were never in the swatch strip, and at 1:1 the frame, the hopper
# and the new refined bar read as three dark boxes in a column. A plate that fixes ore and does
# nothing for those three has not done the job it was ruled in for.
#
# ONE TINT FOR ALL OF THEM, the one the engine actually hands each row (`modulate`), so this strip
# is the shipped pack and not six species of part. The species sweep is panels 4 and 5' job.
art_rows = [r for r in ROWS if "icon" in r]
# THE LABELS DECIDE THE CELL WIDTH, not the other way round (ASSA-118). This used to
# draw `line.split()[-2][:6]` into a fixed 42 px cell, which is a truncation in the units
# of my LAYOUT (characters) rather than of the thing: the strip said "refine" and "smelte"
# -- neither of which is a kind in this game -- and "hopper" ran into "ore". Measured, as
# the captions below already measure themselves. The kind comes from `kind_of`, the same
# reader the checks use, rather than from counting words in the sentence.
_KIND_LABELS = [kind_of(r) for r in art_rows]
_label_w = max(int(ImageDraw.Draw(Image.new("RGB", (1, 1))).textlength(s, font=f12))
               for s in _KIND_LABELS)
CELL = max(int(ICON) + 10, _label_w + 6)
SWATCH = 48
both_w = CELL * len(art_rows)
both_h = 2 * (SWATCH + 18) + 14  # the last 14 is the kind label's own line, under both numbers
both = Image.new("RGB", (both_w, both_h), BG)
db = ImageDraw.Draw(both)
per_row = []
for i, r in enumerate(art_rows):
    dw, dh = r["icon"]["drawn"]
    fr, tint = frame_of(r), tint_of(r)
    x = i * CELL
    measured = []
    for j, surface in enumerate((BG, PLATE)):
        top = j * (SWATCH + 18)
        db.rectangle([x, top, x + int(ICON) - 1, top + SWATCH - 1], fill=surface)
        ink = nearest_blit(both, fr, tint, x + (ICON - dw) / 2.0, top + (SWATCH - dh) / 2.0, dw, dh)
        cs = sorted(contrast(p, surface) for p in ink)
        measured.append(cs)
        db.text((x, top + SWATCH + 2), "%.2f" % cs[-1], font=f12, fill=(240, 240, 240))
    # The kind, not the whole sentence: "22 x Minyte ore (B)" does not fit a cell this
    # wide. Whole word, though -- the cell above was measured to hold the longest of them.
    db.text((x, 2 * (SWATCH + 18)), _KIND_LABELS[i], font=f12, fill=(170, 170, 175))
    per_row.append((r["line"], measured[0], measured[1]))

# ---------------------------------------------------------------------------- assemble
GAP = 18
TITLE = 22
# THE CAPTIONS, GATHERED BEFORE THE WIDTH IS DECIDED, because they are what sets it. Three of
# these ran off the right edge of the sheet -- "1/2 = 0.500 (a clean ha", "the ground's own
# media" -- so a panel explaining itself was itself unreadable. The width is now DERIVED from the
# longest caption rather than from the pictures alone and hoping the words fit under them.
CAP_PLATE = (("the same icons on the plate the client paints, #%02X%02X%02X (ground's median)"
              if PLATE_SHIPPED else
              "PROPOSAL: the client painted NO plate. #%02X%02X%02X is from ui_theme.json") % PLATE)
CAP_BOTH = "every art row, its own tint: on the panel (top), on the plate (bottom)"
CAP_CMP = "ore: shipped scale vs a clean half, 4x / every species"
_cap_w = max(int(ImageDraw.Draw(Image.new("RGB", (1, 1))).textlength(c, font=f12))
             for c in (CAP_PLATE, CAP_BOTH, CAP_CMP)) + 4
width = PANEL + GAP + zoom_w + GAP + max(cmp_w, sp_w, both_w, _cap_w) + GAP
height = TITLE + max(col_h, zoom_h,
                     cmp_h + GAP + sp_h + GAP + sp_h + GAP + both_h + 14) + GAP
sheet = Image.new("RGB", (width, height), (24, 24, 26))
sheet.paste(column, (0, TITLE))
sheet.paste(zoomed, (PANEL + GAP, TITLE))
sheet.paste(compare, (PANEL + GAP + zoom_w + GAP, TITLE))
sheet.paste(species, (PANEL + GAP + zoom_w + GAP, TITLE + cmp_h + GAP))
sheet.paste(plate, (PANEL + GAP + zoom_w + GAP, TITLE + cmp_h + GAP + sp_h + GAP))
_both_y = TITLE + cmp_h + GAP + sp_h + GAP + sp_h + GAP + 14
sheet.paste(both, (PANEL + GAP + zoom_w + GAP, _both_y))
dt = ImageDraw.Draw(sheet)
dt.text((PANEL + GAP + zoom_w + GAP, TITLE + cmp_h + GAP + sp_h + 4), CAP_PLATE,
        font=f12, fill=(200, 200, 205))
dt.text((PANEL + GAP + zoom_w + GAP, _both_y - 14), CAP_BOTH, font=f12, fill=(200, 200, 205))
dt.text((0, 4), "pack rows 1:1, on the viewport's own clear colour #%02X%02X%02X" % BG,
        font=f12, fill=(200, 200, 205))
dt.text((PANEL + GAP, 4), "the 32px slot at 4x", font=f12, fill=(200, 200, 205))
dt.text((PANEL + GAP + zoom_w + GAP, 4), CAP_CMP, font=f12, fill=(200, 200, 205))
OUT.parent.mkdir(parents=True, exist_ok=True)
sheet.save(OUT)

# ---------------------------------------------------------------------------- the numbers
print("background %s, luminance %.4f" % (BG, luminance(BG)))
print("%-24s %-14s %-9s %-11s %-13s %s"
      % ("row", "drawn", "scale", "ink bbox", "ink drawn px",
         "body contrast vs WHAT IS BEHIND IT: max / median"))
for line, icon, ink, bbox, size, base in report:
    if icon is None:
        print("%-24s %s" % (line, "NO ICON"))
        continue
    # AGAINST WHAT THE ROW ACTUALLY SITS ON. This used to be `BG` for every row, which was the
    # same thing while nothing was drawn behind an icon. With a plate it is not, and a column
    # reporting plated icons against the clear colour would understate every one of them.
    cs = sorted(contrast(p, base) for p in ink)
    bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]
    print("%-24s %-14s %-9.5f %-11s %-13s %.2f / %.2f  under 3:1 %d%%"
          % (line, "%gx%g" % tuple(icon["drawn"]), icon["scale"],
             "%dx%d" % (bw, bh), "%.1fx%.1f" % (bw * icon["scale"], bh * icon["scale"]),
             cs[-1], cs[len(cs) // 2], round(100 * sum(1 for c in cs if c < 3.0) / len(cs))))
print()
for (hexv, cs), (_, ps) in zip(per_species, on_plate):
    print("species #%s  ore icon on the panel: max %.2f median %.2f under3 %3d%%   "
          "| on the ground plate: max %.2f median %.2f under3 %3d%%"
          % (hexv, cs[-1], cs[len(cs) // 2],
             round(100 * sum(1 for c in cs if c < 3.0) / len(cs)),
             ps[-1], ps[len(ps) // 2],
             round(100 * sum(1 for c in ps if c < 3.0) / len(ps))))
print("panel #%02X%02X%02X spread (max contrast, worst..best): %.2f..%.2f = %.1fx"
      % (BG + (min(c[-1] for _, c in per_species), max(c[-1] for _, c in per_species),
         max(c[-1] for _, c in per_species) / min(c[-1] for _, c in per_species))))
print("plate #%02X%02X%02X spread (max contrast, worst..best): %.2f..%.2f = %.1fx"
      % (PLATE + (min(c[-1] for _, c in on_plate), max(c[-1] for _, c in on_plate),
         max(c[-1] for _, c in on_plate) / min(c[-1] for _, c in on_plate))))
# MAREN'S BAR, STATED AS SHE STATED IT (ASSA-71): not a floor to clear but a DOMINANCE TEST -- a
# candidate plate must BOTH close the max/min spread AND raise the minimum, and one without the
# other is the wrong colour. Printed as a verdict so nobody has to do the comparison by eye, and
# computed from the two tables above rather than asserted.
_sn = [c[-1] for _, c in per_species]
_sp = [c[-1] for _, c in on_plate]
print("DOMINANCE TEST, ore across six species (both halves must move): spread %s (%.1fx -> %.1fx),"
      " floor %s (%.2f -> %.2f)"
      % ("CLOSES" if max(_sp) / min(_sp) < max(_sn) / min(_sn) else "does NOT close",
         max(_sn) / min(_sn), max(_sp) / min(_sp),
         "RISES" if min(_sp) > min(_sn) else "does NOT rise", min(_sn), min(_sp)))
# WHAT THE TEST BUYS AND WHAT IT COSTS, named rather than left to be spotted in the table. "Even
# beats high" is Maren's ruling and it necessarily means the brightest species gets WORSE: it was
# only ever the brightest because the panel is dark. Printed because the floor rising is the
# headline and this is the bill, and a summary that shows only the headline is a sales pitch.
_worst = min(zip(per_species, on_plate), key=lambda t: t[1][1][-1])
_hurt = min(zip(per_species, on_plate), key=lambda t: t[1][1][-1] - t[0][1][-1])
print("  the plate's own worst species is #%s at %.2f (it was %.2f on the panel);"
      " the species it COSTS most is #%s, %.2f -> %.2f, and %d%% of its body is under 3:1 there"
      % (_worst[0][0], _worst[1][1][-1], _worst[0][1][-1],
         _hurt[0][0], _hurt[0][1][-1], _hurt[1][1][-1],
         round(100 * sum(1 for c in _hurt[1][1] if c < 3.0) / len(_hurt[1][1]))))
print()
# MAREN'S BOX 4: the part icons measured too, not just ore -- "they are darker than any ore and
# were not in the strip", and at 1:1 the frame, the hopper and the refined bar read as three dark
# boxes. What the plate has to do for them is make them LEGIBLE.
#
# AND NOT HER DOMINANCE TEST, WHICH IS A SPECIES ARGUMENT AND DOES NOT TRANSFER HERE. The reason
# the spread had to close across species is that "every species is the same kind of thing and the
# HUD must not rank them" -- six interchangeable things must not look like a lantern and a
# silhouette. Kinds are NOT interchangeable: ore and a frame are different objects and the HUD is
# entitled to tell them apart. So the max/min ratio across kinds is reported below as a number and
# NOT scored as a pass or a fail, because scoring it would be me quietly re-pointing someone else's
# bar at a population it was not written about. Maren's call, not mine.
#
# (For the record, the ratio across kinds WIDENS, 1.2x -> 1.4x, and that is not a defect: on the
# panel all six rows sat in 1.90..2.28 because they were uniformly illegible. A tight spread of
# uniformly bad is what the plate is supposed to break.)
print("EVERY ART ROW on the two surfaces (Maren's box 4). Body = alpha >= 200.")
print("%-24s %-24s %s" % ("row", "on the panel", "on the plate"))
for line, cs, ps in per_row:
    print("%-24s max %5.2f median %5.2f   max %5.2f median %5.2f"
          % (line[:24], cs[-1], cs[len(cs) // 2], ps[-1], ps[len(ps) // 2]))
_pn = [c[-1] for _, c, _ in per_row]
_pl = [p[-1] for _, _, p in per_row]
print("all art rows, panel: %.2f..%.2f = %.1fx   plate: %.2f..%.2f = %.1fx"
      % (min(_pn), max(_pn), max(_pn) / min(_pn),
         min(_pl), max(_pl), max(_pl) / min(_pl)))
print("the floor across kinds %s: %.2f -> %.2f. Worst-lit row on the panel: %s."
      % ("RISES" if min(_pl) > min(_pn) else "does NOT rise", min(_pn), min(_pl),
         min(per_row, key=lambda t: t[1][-1])[0]))
print("the max/min ratio across kinds goes %.1fx -> %.1fx, REPORTED AND NOT SCORED (see source)."
      % (max(_pn) / min(_pn), max(_pl) / min(_pl)))
print()
# WHICH SOURCE ROWS AND COLUMNS SURVIVE. A scale of 1/2 or 1/4 keeps every nth; 15/32 does not.
#
# THE VERDICT IS COMPUTED, NOT ASSERTED (Limpet, ASSA-65). The size in the label and the words
# "not evenly spaced" used to be literals -- true when this was written against 15/32, and false
# the moment the icon got a fixed box: the run below reported `gaps [2]`, a single uniform gap,
# under a sentence saying the spacing was uneven. One gap is even sampling; more than one is not.
for (dw, dh), (fw_, fh_) in [(tuple(ore["icon"]["drawn"]), ore_frame.size)]:
    cols = [int((dx + 0.5) / dw * fw_) for dx in range(int(dw))]
    kept = len(set(cols))
    gaps = sorted(set(b - a for a, b in zip(cols, cols[1:])))
    print("ore %gx%g from %gx%g: %d of %d source columns survive, and they are %s (gaps %s)"
          % (dw, dh, fw_, fh_, kept, fw_,
             "evenly spaced" if len(gaps) == 1 else "NOT evenly spaced", gaps))
print("sheet written to %s (%dx%d)" % (OUT, sheet.width, sheet.height))
