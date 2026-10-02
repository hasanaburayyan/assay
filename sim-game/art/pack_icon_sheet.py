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
cannot ask the engine for is the pixels. Two documented rules are reimplemented:
  - STRETCH_KEEP_ASPECT_CENTERED: scale = min(rect.w/frame.w, rect.h/frame.h), result centred.
    The engine's own `scale` is in the JSON and this script asserts its arithmetic matches.
  - TEXTURE_FILTER_NEAREST: a destination pixel takes the source texel under its CENTRE, and a
    destination pixel is drawn at all only if its centre is inside the quad. That is why a
    half-pixel rect (25.5) and a non-integer scale (15/32) matter.
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

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


def nearest_blit(dst, frame, tint, dest_x, dest_y, dest_w, dest_h, zoom=1):
    """Draw `frame` into `dst` the way a TextureRect with NEAREST does, tinted by `modulate`.

    Returns the list of composited (r,g,b) for every pixel whose source texel had any alpha --
    which is what a contrast question is about: the ink, not the transparent frame around it.
    """
    fw, fh = frame.size
    px = frame.load()
    ink = []
    x0 = math.floor(dest_x * zoom)
    y0 = math.floor(dest_y * zoom)
    x1 = math.ceil((dest_x + dest_w) * zoom)
    y1 = math.ceil((dest_y + dest_h) * zoom)
    out = dst.load()
    for dy in range(y0, y1):
        v = (dy + 0.5) / zoom - dest_y
        if v < 0 or v >= dest_h:
            continue
        sy = min(fh - 1, int(v / dest_h * fh))
        for dx in range(x0, x1):
            u = (dx + 0.5) / zoom - dest_x
            if u < 0 or u >= dest_w:
                continue
            sx = min(fw - 1, int(u / dest_w * fw))
            r, g, b, a = px[sx, sy]
            if a == 0:
                continue
            r = r * tint[0] // 255
            g = g * tint[1] // 255
            b = b * tint[2] // 255
            if 0 <= dx < dst.width and 0 <= dy < dst.height:
                base = out[dx, dy]
                f = a / 255.0
                mixed = tuple(int(round(c * f + base[i] * (1 - f))) for i, c in enumerate((r, g, b)))
                out[dx, dy] = mixed
                # SOLID INK ONLY, and this is a correction rather than a choice: the part frames
                # carry a contact shadow whose alpha runs down to 1, so counting every a>0 pixel
                # made the measure mostly about the shadow -- it reported "100% under 3:1" for a
                # sprite whose body plainly reads. A pixel is the sprite's body at a >= 200.
                if a >= 200:
                    ink.append(mixed)
    return ink


def ink_bbox(frame):
    bbox = frame.split()[-1].getbbox()
    return bbox


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


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
        ink = nearest_blit(column, frame, tint_of(r), (ICON - dw) / 2.0, y + (rh - dh) / 2.0, dw, dh)
        report.append((r["line"], r["icon"], ink, ink_bbox(frame), frame.size))
        x = ICON + SEP
    else:
        report.append((r["line"], None, [], None, None))
    d.text((x, y + 1), r["line"], font=f13, fill=(235, 235, 235))
    vx = x
    for verb in r["verbs"]:
        w = int(d.textlength(verb, font=f12)) + 10
        if vx + w > PANEL:
            vx = x
        d.rectangle([vx, y + 18, vx + w, y + 36], fill=(78, 78, 82), outline=(110, 110, 115))
        d.text((vx + 5, y + 21), verb, font=f12, fill=(225, 225, 230))
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
        nearest_blit(zoomed, frame_of(r), tint_of(r), (ICON - dw) / 2.0, y + (rh - dh) / 2.0,
                     dw, dh, zoom=ZOOM)
    # IN SOURCE UNITS: `nearest_blit` multiplies by `zoom` itself, and adding zoomed pixels here
    # put five of the six icons off the bottom of the panel. I only noticed by looking at it.
    y += rh + 10.0 / ZOOM

# ------------------------------------------------- panel 3: 15/32 against a clean 1/2, ore, 4x
ore = next(r for r in ROWS if "ore" in r["line"])
ore_frame = frame_of(ore)
fw, fh = ore_frame.size
cmp_w = 2 * int(ICON) * ZOOM + 36
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
dc.text((int(ICON) * ZOOM + 36, 46 * ZOOM), "1/2 = 0.500 (a clean half)",
        font=f12, fill=(240, 240, 240))

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
# is a surface the art has never been judged on. The plate colour is READ FROM `ground.png` (its
# median opaque pixel), not picked: it is literally the ground the game draws under everything.
ground = Image.open(SPRITES / "ground.png").convert("RGBA")
gpx = [q[:3] for q in list(ground.getdata()) if q[3] > 200]
PLATE = tuple(sorted(c[i] for c in gpx)[len(gpx) // 2] for i in range(3))
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

# ---------------------------------------------------------------------------- assemble
GAP = 18
TITLE = 22
width = PANEL + GAP + zoom_w + GAP + max(cmp_w, sp_w) + GAP
height = TITLE + max(col_h, zoom_h, cmp_h + GAP + sp_h + GAP + sp_h) + GAP
sheet = Image.new("RGB", (width, height), (24, 24, 26))
sheet.paste(column, (0, TITLE))
sheet.paste(zoomed, (PANEL + GAP, TITLE))
sheet.paste(compare, (PANEL + GAP + zoom_w + GAP, TITLE))
sheet.paste(species, (PANEL + GAP + zoom_w + GAP, TITLE + cmp_h + GAP))
sheet.paste(plate, (PANEL + GAP + zoom_w + GAP, TITLE + cmp_h + GAP + sp_h + GAP))
dt = ImageDraw.Draw(sheet)
dt.text((PANEL + GAP + zoom_w + GAP, TITLE + cmp_h + GAP + sp_h + 4),
        "the same icons on a plate of #%02X%02X%02X, the ground's own median" % PLATE,
        font=f12, fill=(200, 200, 205))
dt.text((0, 4), "pack rows 1:1, on the viewport's own clear colour #%02X%02X%02X" % BG,
        font=f12, fill=(200, 200, 205))
dt.text((PANEL + GAP, 4), "the 32px slot at 4x", font=f12, fill=(200, 200, 205))
dt.text((PANEL + GAP + zoom_w + GAP, 4), "ore: shipped scale vs a clean half, 4x / every species",
        font=f12, fill=(200, 200, 205))
OUT.parent.mkdir(parents=True, exist_ok=True)
sheet.save(OUT)

# ---------------------------------------------------------------------------- the numbers
print("background %s, luminance %.4f" % (BG, luminance(BG)))
print("%-24s %-14s %-9s %-11s %-13s %s"
      % ("row", "drawn", "scale", "ink bbox", "ink drawn px", "body contrast vs bg: max / median"))
for line, icon, ink, bbox, size in report:
    if icon is None:
        print("%-24s %s" % (line, "NO ICON"))
        continue
    cs = sorted(contrast(p, BG) for p in ink)
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
