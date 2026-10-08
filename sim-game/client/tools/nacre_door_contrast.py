#!/usr/bin/env python3
"""WHAT IS ACTUALLY BEHIND THE WORDS ON THE TITLE SCREEN (ASSA-292, Maren's floor 1).

Her floor: *"every word reads >= 4.5:1 against what is actually behind it, measured on the lit
world, never on the dark field it used to sit on."*

THE HARD PART IS NOT THE RATIO, IT IS "BEHIND". A text pixel is opaque, so the thing behind it is
not in the picture. What IS in the picture is the background in the gaps -- inside an `a`, between
two letters, just outside a stem -- and on a lit world those gaps are what the eye reads the letter
against. So:

  1. On the BEFORE frame (flat `MAP_BG`) the inks separate from the field trivially. That gives a
     mask of which pixels are text, and text does not move between the two frames: same layout,
     same font, same string.
  2. In the AFTER frame, the background behind a text block is every pixel inside its bounding box
     that was *the flat field* in the before frame -- `MAP_BG` within a tight tolerance.

     **"NOT TEXT" IS NOT GOOD ENOUGH AND THE CONTROL IS WHAT PROVED IT.** The first version of this
     script took background to be every pixel the ink mask missed, and reported the wordmark at
     **1.10:1 on the flat field** where Maren measured 14.0:1. The culprit is anti-aliasing: a glyph
     edge at (219,223,230) is 11 off `INK` in one channel, so it fell outside the mask and was then
     counted as background -- the instrument was measuring the letter against its own fringe. Asking
     for `MAP_BG` instead names the thing being looked for rather than everything else.
  3. The reported ratio is the WORST one -- the brightest background pixel against a light ink --
     not the mean. A mean hides the one bright tile that eats a letter.

THE CONTROL IS THE WHOLE REASON TO TRUST THE NUMBER. Run on the before frame, this must reproduce
Maren's two independently measured values: the wordmark at 14.0:1 and the sentence at 7.79:1. An
instrument that cannot find a number somebody else already measured is not measuring.

Usage: nacre_door_contrast.py BEFORE.png AFTER.png
"""
import sys
import zlib
import struct


def read_png(path):
    """Minimal PNG reader: 8-bit RGB/RGBA, non-interlaced. Avoids a dependency for 1280x720."""
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("%s is not a PNG" % path)
    pos, width, height, channels, raw = 8, 0, 0, 0, b""
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour = struct.unpack(">IIBB", body[:10])
            if depth != 8 or colour not in (2, 6):
                raise SystemExit("only 8-bit RGB/RGBA handled, got depth %d colour %d"
                                 % (depth, colour))
            channels = 3 if colour == 2 else 4
        elif kind == b"IDAT":
            raw += body
        elif kind == b"IEND":
            break
        pos += 12 + length
    raw = zlib.decompress(raw)
    stride = width * channels
    rows, previous = [], bytearray(stride)
    at = 0
    for _ in range(height):
        filt = raw[at]
        line = bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        for i in range(stride):
            left = line[i - channels] if i >= channels else 0
            up = previous[i]
            upleft = previous[i - channels] if i >= channels else 0
            if filt == 1:
                line[i] = (line[i] + left) & 0xFF
            elif filt == 2:
                line[i] = (line[i] + up) & 0xFF
            elif filt == 3:
                line[i] = (line[i] + (left + up) // 2) & 0xFF
            elif filt == 4:
                p = left + up - upleft
                candidates = (left, up, upleft)
                best = min(candidates, key=lambda c: abs(p - c))
                line[i] = (line[i] + best) & 0xFF
        rows.append(bytes(line))
        previous = line
    return width, height, channels, rows


def pixel(rows, channels, x, y):
    off = x * channels
    row = rows[y]
    return row[off], row[off + 1], row[off + 2]


def luminance(rgb):
    out = []
    for channel in rgb:
        value = channel / 255.0
        out.append(value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4)
    return 0.2126 * out[0] + 0.7152 * out[1] + 0.0722 * out[2]


def ratio(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


# The two inks the door is written in, from `build_theme.gd`. Matched with a tolerance because the
# font is anti-aliased: a glyph's core is the token and its edge fades toward whatever is behind it.
INKS = {"INK": (229, 233, 241), "INK_MUTED": (167, 176, 190)}
TOLERANCE = 10
## `AssayHud.MAP_BG`: what the door was ENTIRELY painted in before this item. On the before frame
## every pixel of it that is not a glyph or a glyph fringe is exactly this, which is what makes the
## before frame usable as a stencil. Tight tolerance: a loose one lets the dark end of the
## anti-aliasing back in and the bug above returns quietly.
MAP_BG = (26, 28, 33)
FIELD_TOLERANCE = 4
# The door's own rectangle, `AssayHud.join_rect()`: x 24..936, y 24..696. Keeps the HUD column and
# the world's own sprites out of the mask.
DOOR = (24, 24, 936, 696)


def near(rgb, want, tolerance=TOLERANCE):
    return all(abs(rgb[i] - want[i]) <= tolerance for i in range(3))


def bands(mask_rows, height):
    """Group masked rows into contiguous bands, so the title and the sentence come out separately."""
    out, run = [], None
    for y in range(height):
        if mask_rows[y]:
            run = [y, y] if run is None else [run[0], y]
        elif run is not None:
            out.append(run)
            run = None
    if run is not None:
        out.append(run)
    return out


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    before_path, after_path = sys.argv[1], sys.argv[2]
    bw, bh, bc, before = read_png(before_path)
    aw, ah, ac, after = read_png(after_path)
    if (bw, bh) != (aw, ah):
        raise SystemExit("frames differ in size: %dx%d vs %dx%d" % (bw, bh, aw, ah))
    x0, y0, x1, y1 = DOOR

    for name, token in INKS.items():
        mask = {}
        rows_hit = [False] * bh
        for y in range(y0, min(y1, bh)):
            for x in range(x0, min(x1, bw)):
                if near(pixel(before, bc, x, y), token):
                    mask.setdefault(y, set()).add(x)
                    rows_hit[y] = True
        for band in bands(rows_hit, bh):
            top, bottom = band
            xs = [x for y in range(top, bottom + 1) for x in mask.get(y, ())]
            if len(xs) < 20:
                continue
            left, right = min(xs), max(xs)
            text_px = len(xs)
            # THE BACKGROUND IS WHAT WAS THE FLAT FIELD, not "whatever the mask missed" -- see the
            # module docstring for the 1.10:1 that reading cost.
            worst_before, worst_after, bg_px = None, None, 0
            for y in range(top, bottom + 1):
                for x in range(left, right + 1):
                    if not near(pixel(before, bc, x, y), MAP_BG, FIELD_TOLERANCE):
                        continue
                    bg_px += 1
                    rb, ra = pixel(before, bc, x, y), pixel(after, ac, x, y)
                    cb, ca = ratio(token, rb), ratio(token, ra)
                    if worst_before is None or cb < worst_before[0]:
                        worst_before = (cb, rb, x, y)
                    if worst_after is None or ca < worst_after[0]:
                        worst_after = (ca, ra, x, y)
            print("%-10s band y %3d..%-3d  x %3d..%-4d  %5d text px, %5d background px"
                  % (name, top, bottom, left, right, text_px, bg_px))
            # A BAND WITH NO FIELD AROUND IT CANNOT BE JUDGED, and reporting it as a pass would be
            # the "check that cannot fail" shape. Say so and move on.
            if bg_px < 40:
                print("    SKIPPED: only %d field pixels in this box, too few to judge" % bg_px)
                continue
            print("    BEFORE (flat field)  worst %6.2f:1 against %-15s at (%d,%d)"
                  % (worst_before[0], str(worst_before[1]), worst_before[2], worst_before[3]))
            print("    AFTER  (lit world)   worst %6.2f:1 against %-15s at (%d,%d)   %s"
                  % (worst_after[0], str(worst_after[1]), worst_after[2], worst_after[3],
                     "PASS >= 4.5" if worst_after[0] >= 4.5 else "FAILS MAREN FLOOR 1"))


if __name__ == "__main__":
    main()
