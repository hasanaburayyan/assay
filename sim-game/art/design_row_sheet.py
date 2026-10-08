#!/usr/bin/env -S uv run --quiet --with pillow python
"""THE BENCH AS THE ENGINE LAID IT OUT, at 1:1, so Decision #38 can be looked at. (ASSA-83)

    godot --headless --path client --script "$PWD/client/tools/button_session.gd" \
      -- offline 14247 designs=/tmp/designs.json
    godot --path client --script "$PWD/art/design_row_layout.gd" \
      -- /tmp/designs.json | sed -n 's/^DESIGN_LAYOUT_JSON //p' > /tmp/layout.json
    uv run --with pillow python art/design_row_sheet.py /tmp/layout.json

THE SECOND LINE HAS NO `--headless` AND THE OMISSION IS LOAD-BEARING (ASSA-173). Headless there is
no layout pass, so the probe reported 98 drawn lines for a four-line paragraph and the refusal below
fired on every attempt -- which is why this sheet had not been redrawn since 2026-10-03. The first
line keeps its `--headless` because `button_session.gd` draws nothing; it builds the world offline.
The old recipe read the designs off a live relay on port 7803, which no current client can join
(ASSA-178); `button_session.gd designs=` writes the same shape from a seed (#357).

Decision #38 asks whether the part menu reads as A DESIGN or as A DEBUG STRIP. Until this existed
the only ways to answer were reading `hud.gd` and playing the text client, and neither is the thing
being judged. This is `pack_icon_sheet.py`'s sibling, pointed at the bench.

EVERY NUMBER THAT DECIDES GEOMETRY COMES FROM THE LAYOUT JSON -- the laid-out rect of every label
and button, the font sizes, the verdict colours, the panel width and the viewport's clear colour,
all read back off the nodes the real `main.tscn` built. Nothing here recomputes a position.

THE ONE THING IT CANNOT ASK THE ENGINE FOR IS GLYPHS. The probe hands this script JSON and not an
image, so the letterforms below are this script's font at the engine's font SIZE, not Godot's. (That
reason used to read "headless Godot has no renderer", which stopped being the reason the day the
probe moved into a real window -- ASSA-173. The limit is the same; the cause was not.) Which means line
lengths here are approximate even though every box around them is exact -- so each text line is
drawn with a tick at the width THE ENGINE measured it to be, in the Label's own font. If a line were
ever going to overflow the panel, that tick is where it would cross, and it is the engine's opinion
rather than this script's.

AND THE WRAPPING IS ASSERTED, NOT ASSUMED. The body Label is AUTOWRAP_WORD_SMART at panel width. The
probe reports both the engine's drawn `line_count` and the text's own `logical` lines; this script
refuses to draw a row where they disagree, because then the picture would be a paragraph broken
somewhere the client does not break it.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
# THE ONE SHEET THAT COMPOSITES NO SHIPPED ART (ASSA-144). It draws an engine layout and its
# own fonts, so it records nothing and stamps an EMPTY source list -- which is a real answer,
# not a missing one: this picture cannot go stale against the sprites because it does not
# depend on them. Recording anyway, rather than hard-coding "empty", so the day it starts
# blitting an icon the stamp grows by itself and the check begins holding it to one.
import review_sources  # noqa: E402
review_sources.start()
# WHICH CLIENT PANEL THIS IS A PICTURE OF (ASSA-151, and ASSA-173 is what made it possible here).
# The sources stamp above says this sheet composites no shipped art, which is true and was the
# whole answer for one sheet too long: the content of this picture is `design_row_layout.gd`'s
# answer, so it can go stale against the client without a single sprite moving. That is the half
# `review_layout` closes, and it is why `design_rows.png` was the last sheet in the repo named in
# `check_review_layout.py::UNDECLARABLE`.
import review_layout  # noqa: E402
import design_row_dump  # noqa: E402

HERE = Path(__file__).resolve().parent.parent
LAYOUT = review_layout.load(sys.argv[1] if len(sys.argv) > 1 else "/tmp/cove-dlayout.json",
                            probe=design_row_dump.PROBE)
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE / "assets/review/design_rows.png"
PROVENANCE = json.load(open(sys.argv[3])) if len(sys.argv) > 3 else {}

ROWS = LAYOUT["rows"]
PANEL = int(LAYOUT["panel_px"])


def clear_colour():
    """The viewport's own clear colour, as the framebuffer gets it. 2D is sRGB-native."""
    nums = LAYOUT["clear_color"].strip("()").split(",")
    return tuple(int(round(float(n) * 255)) for n in nums[:3])


BG = clear_colour()
GAP = 14
PAD = 12


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def draw_row(dst, row, ox, oy):
    """One design row at 1:1, every rect and colour from the engine."""
    d = ImageDraw.Draw(dst)
    verdict, body = row["verdict"], row["body"]
    if body and int(body["line_count"]) != len(body["logical"]):
        raise SystemExit(
            "design_row_sheet: the engine drew %d lines where the text has %d, so it WRAPPED and "
            "this script would draw the paragraph broken somewhere the client does not break it. "
            "Teach it the engine's breaks before drawing this row." % (
                int(body["line_count"]), len(body["logical"])))
    if verdict:
        vx, vy = verdict["pos"]
        d.text((ox + vx, oy + vy), verdict["text"], font=font(int(verdict["font_size"])),
               fill=rgb(verdict["color"]))
    if body:
        bx, by = body["pos"]
        fs = int(body["font_size"])
        f = font(fs)
        # The Label's line height, from the rect the engine gave the whole paragraph.
        step = body["size"][1] / max(1, len(body["logical"]))
        for i, (line, width) in enumerate(zip(body["logical"], body["widths"])):
            y = oy + by + i * step
            d.text((ox + bx, y), line, font=f, fill=rgb(body["color"]))
            # THE ENGINE'S OWN WIDTH FOR THIS LINE. The glyphs are this script's font; the tick is
            # where the client's font actually ends.
            d.line([(ox + bx + width, y + 1), (ox + bx + width, y + step - 2)],
                   fill=(120, 120, 120), width=1)
    for verb in row["verbs"]:
        bxx, byy = verb["pos"]
        bw, bh = verb["size"]
        d.rectangle([ox + bxx, oy + byy, ox + bxx + bw - 1, oy + byy + bh - 1],
                    outline=(150, 150, 150), fill=(88, 88, 88))
        f = font(12)
        tw = d.textlength(verb["label"], font=f)
        d.text((ox + bxx + (bw - tw) / 2.0, oy + byy + (bh - 12) / 2.0 - 1),
               verb["label"], font=f, fill=(232, 232, 232))


def stamp_of(row):
    """WHICH RUN AND TICK THIS ROW IS A PICTURE OF, or "" when the dump predates provenance.

    **THIS IS THE ITEM'S OWN SUBJECT POINTED AT ITSELF** (Maren, ASSA-173 06:01). The sheet used
    to print one `tick:` and one `hash:` in the caption over rows from TWO runs, so the two fields
    named the showcase run and lied about the other row -- "ASSA-144 with the names changed". The
    numbers now ride each design through the probe and are printed against the row they belong to.

    `tick` is forced to an int because it crosses GDScript's JSON as a double and comes back
    `516.0`, which reads as a precision nobody has.
    """
    s = row.get("source") or {}
    if not s.get("run"):
        return ""
    tick = s.get("tick")
    return "run %s (%s) · tick %s · hash %s" % (
        s.get("run"), s.get("flags", "?"),
        int(tick) if isinstance(tick, (int, float)) else "?", s.get("hash", "?"))


#: Room under each row for [`stamp_of`]. The gap between rows was always this script's own choice
#: and not the engine's `separation`, so spending it on the stamp costs the picture nothing.
STAMP_H = 15


def column(zoom=1, stamps=True):
    """The bench, rows stacked the way the VBox stacks them, each with its provenance under it.

    `stamps` is off for the 2x copy: that column is a magnifier for the letterforms, and doubling
    11px provenance text adds no information and a lot of ink.
    """
    sep = 10
    extra = STAMP_H if stamps else 0
    h = int(sum(r["row_size"][1] + extra for r in ROWS) + sep * (len(ROWS) - 1))
    img = Image.new("RGB", (PANEL, h), BG)
    d = ImageDraw.Draw(img)
    y = 0
    for r in ROWS:
        draw_row(img, r, 0, y)
        y += int(r["row_size"][1])
        if stamps:
            d.text((0, y + 2), stamp_of(r), font=font(11), fill=(150, 156, 168))
            y += extra
        y += sep
    if zoom != 1:
        img = img.resize((img.width * zoom, img.height * zoom), Image.NEAREST)
    return img


one = column(1)
two = column(2, stamps=False)

cap = font(13)
head = font(15)
small = font(12)
paragraph = (
    "THE BENCH AS THE ENGINE LAYS IT OUT. Decision #38 asks whether this reads as a DESIGN or as "
    "a DEBUG STRIP. Every rect, font size, verdict colour and the %d px panel width are read back "
    "off the nodes real main.tscn built; only the letterforms are this sheet's font, so each line "
    "carries a tick at the width the ENGINE measured it to be. Widest line %d px of %d."
    % (PANEL, int(max(max(r["body"]["widths"]) for r in ROWS if r["body"])), PANEL))
# NO `tick` AND NO `hash` IN THIS LIST, and their absence is the point rather than an omission.
# They are per-row facts (see `stamp_of`) and a single one of each over merged rows is the lie
# Maren refused on 06:01. A caption key that cannot be true for every row does not belong to the
# caption.
facts = ["%s: %s" % (k, PROVENANCE[k])
         for k in ("source", "seed", "rules", "note") if k in PROVENANCE]

W = max(PANEL, one.width) + GAP + two.width + PAD * 3


def wrapped(text, f, width):
    """`text` broken to `width` px in `f`, by words.

    **A STAMP NOBODY CAN READ IS THIS ITEM'S SUBJECT TOO** (Maren). The caption used to be a list
    of pre-broken string literals drawn unwrapped, while the sheet's WIDTH comes from the panels --
    so a provenance line longer than two bench columns ran off the right edge mid-word and the
    sheet said nothing. Wrapping here means the caption adapts to the picture instead of a human
    guessing the width at the time they typed it.
    """
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    out, line = [], ""
    for word in text.split():
        trial = (line + " " + word).strip()
        if line and probe.textlength(trial, font=f) > width:
            out.append(line)
            line = word
        else:
            line = trial
    return out + [line] if line else out


AVAIL = W - PAD * 2
lines = [(head, l) for l in wrapped(paragraph, head, AVAIL)]
lines += [(cap, l) for fact in facts for l in wrapped(fact, cap, AVAIL)]

cap_h = PAD * 2 + len(lines) * 17
H = max(cap_h + one.height, cap_h + two.height) + PAD * 2 + 24
sheet = Image.new("RGB", (W, H), (34, 34, 34))
d = ImageDraw.Draw(sheet)
y = PAD
for f, line in lines:
    d.text((PAD, y), line, font=f, fill=(236, 236, 236))
    y += 17
y += PAD
d.text((PAD, y - 15), "1:1 (the honest size)", font=small, fill=(176, 176, 176))
sheet.paste(one, (PAD, y))
d.text((PAD * 2 + one.width, y - 15), "2x", font=small, fill=(176, 176, 176))
sheet.paste(two, (PAD * 2 + one.width, y))
OUT.parent.mkdir(parents=True, exist_ok=True)
# TWO CLAIMS, TWO KEYS, ONE SHEET: the art it composited (none) and the client layout it drew.
sheet.save(OUT, pnginfo=review_layout.png_info(review_sources.png_info()))

for r in ROWS:
    b = r["body"]
    print("%-11s %s  row %sx%s  verbs %s" % (
        r["verdict"]["text"], r["verdict"]["color"],
        int(r["row_size"][0]), int(r["row_size"][1]),
        ", ".join(v["label"] for v in r["verbs"]) or "none"))
    for line, w in zip(b["logical"], b["widths"]):
        print("    %5.0f px | %s" % (w, line))
print("sheet written to %s (%dx%d)" % (OUT, sheet.width, sheet.height))
