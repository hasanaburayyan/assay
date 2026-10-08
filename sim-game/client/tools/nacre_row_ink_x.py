#!/usr/bin/env python3
"""WHERE EACH LINE OF A COLUMN STARTS, which is the half a vertical profile cannot answer.

Maren's `shared/assay/maren-rocks-row/ink_rows.py` finds the LINES in the mineralogy column: a
vertical ink profile, so a row's shape is measured rather than eyeballed. It answers "which line,
how tall, how much ink". It cannot answer "and does this line begin under its own name", which is
the question ASSA-264's second half turns on: the verdict was flush with the readings TABLE at x947
while the species name it answers for began at x970, past its 18 px map disc.

So this is the same run-detection on the same bands, reporting the FIRST and LAST x of ink on each
one. Same luminance floor (90, anything brighter than the panel plate) and the same two-pixel
minimum, deliberately, so the bands it prints are the bands her script prints and the two outputs
can be read side by side.

**THE CONTROL IS THE REASON TO TRUST IT** (and it is the rule I keep re-earning: a detector with no
control is worse than none). Run on `shared/assay/nacre-assa264-order/after-05-rocks.png` -- the
reordered row BEFORE the indent -- it must reproduce the three numbers already published on
ASSA-264 and quoted back by Maren: the species name's ink at **x970**, its verdict at **x947**, and
the property labels under it at **x946**. An instrument that cannot find numbers somebody has
already measured is not measuring.

**AND THE CONTROL EARNED ITSELF ON THE FIRST RUN.** Version one reported one first-x per band and
put the name band at **x952**, which is not the name: it is the white LETTER inside the 18 px map
disc, and the band holding the name holds the swatch too. 952 would have been published as "the
name starts here" and the indent measured against it would have been 18 px out. So a band is
reported as horizontal SEGMENTS, split on a gap of `SEG_GAP_PX` -- wide enough to separate the
swatch from the type -- 13 px from the letter, 7 px from the disc's own edge on a species whose
tint clears the floor -- and still narrower than the widest air inside a sentence at `BODY`. The item body already said the disc is excluded *"because its white letter is a
swatch, not type"*; the first version of this tool had no way to honour that.

**WHAT IT IS NOT.** It reports INK, not a node's rect: a glyph's own left side bearing is in these
numbers, so two labels with the same origin can differ by a pixel or two depending on their first
character. That is a real fact about the picture -- it is what a reader sees -- but it means this
tool cannot be used to assert a layout offset to the pixel. The suite asserts the offset off the
nodes; this says what the window actually shows.

Usage: nacre_row_ink_x.py SHOT.png [X0 X1 Y0 Y1]      (defaults: the mineralogy column at 1280x720)
"""
import struct
import sys
import zlib

# The column the mineralogy tab's body occupies at 1280x720, and the band of it below the two
# headline answers -- the same window Maren's profile uses, so the two can be read together.
DEFAULTS = (946, 1246, 390, 700)
INK_FLOOR = 90.0
MIN_RUN_PX = 2
# A band's ink is cut into segments on a gap this wide. 8 was wrong and the control said so: on a
# species whose tint clears the ink floor the whole 18 px disc lights up, and its right edge is only
# 7 px from the name -- so at 8 the swatch and the name merged again on the second row of the very
# frame this was written for. 6 splits both (13 px from the letter, 7 from the disc) and leaves the
# 4-5 px inside a sentence alone. See the control note above.
SEG_GAP_PX = 6


def read_png(path):
    """Minimal PNG reader: 8-bit RGB/RGBA, non-interlaced. Self-contained on purpose -- these tools
    are run with `python3 -I`, which drops the script's own directory from the import path, so a
    sibling import of the identical reader in `nacre_door_contrast.py` would not resolve."""
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
    out, prev, pos = [], bytearray(stride), 0
    for _y in range(height):
        filt = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        for x in range(stride):
            left = line[x - channels] if x >= channels else 0
            up = prev[x]
            upleft = prev[x - channels] if x >= channels else 0
            if filt == 1:
                line[x] = (line[x] + left) & 255
            elif filt == 2:
                line[x] = (line[x] + up) & 255
            elif filt == 3:
                line[x] = (line[x] + (left + up) // 2) & 255
            elif filt == 4:
                p = left + up - upleft
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upleft)
                pred = left if (pa <= pb and pa <= pc) else (up if pb <= pc else upleft)
                line[x] = (line[x] + pred) & 255
        row = []
        for x in range(width):
            base = x * channels
            row.append((line[base], line[base + 1], line[base + 2]))
        out.append(row)
        prev = line
    return width, height, out


def lum(pixel):
    return 0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2]


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__.strip().splitlines()[-1])
    path = sys.argv[1]
    x0, x1, y0, y1 = DEFAULTS
    if len(sys.argv) >= 6:
        x0, x1, y0, y1 = (int(v) for v in sys.argv[2:6])
    width, height, px = read_png(path)
    print("%s  %dx%d   window x %d..%d  y %d..%d" % (path, width, height, x0, x1 - 1, y0, y1 - 1))
    print("  ink y            h   peak   segments (x..x, split on a %d px gap)" % SEG_GAP_PX)
    band = None
    for y in range(y0, min(y1, height)):
        lit = [x for x in range(x0, min(x1, width)) if lum(px[y][x]) > INK_FLOOR]
        if len(lit) >= MIN_RUN_PX:
            if band is None:
                band = [y, y, len(lit), set(lit)]
            else:
                band[1] = y
                band[2] = max(band[2], len(lit))
                band[3] |= set(lit)
        elif band is not None:
            report(band)
            band = None
    if band is not None:
        report(band)


def segments(columns):
    """The band's lit columns as (first, last) runs, broken where the air is `SEG_GAP_PX` wide."""
    out = []
    for x in sorted(columns):
        if out and x - out[-1][1] <= SEG_GAP_PX:
            out[-1][1] = x
        else:
            out.append([x, x])
    return out


def report(band):
    runs = segments(band[3])
    drawn = " | ".join("%d..%d" % (a, b) for a, b in runs)
    print("  %4d..%4d  %4d  %5d   %s" % (band[0], band[1], band[1] - band[0] + 1, band[2], drawn))


main()
