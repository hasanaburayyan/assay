#!/usr/bin/env python3
"""Count accent-family pixels in a band of a 1x shot, and crop that band out.

WHY THIS EXISTS AND WHY IT SHARES NO LINE OF CODE WITH THE CLIENT. `window_shot.gd`'s `rank` leg
counts the same thing from inside the process that drew the frame. If that counter is wrong, the
leg is wrong in exactly the same way and the two say green together -- which is one instrument
with two names. This reads the PNG off disk with nothing but stdlib zlib, so the two can only
agree by both being right. Maren measured the original defect this way (`maren-assa150/strip.py`)
and I would rather her number and mine come from different code.

ACCENT-FAMILY IS `g - max(r, b) >= 8`, WHICH IS NOT A COLOUR MATCH. Anti-aliased text is never the
declared colour -- every glyph edge is a blend of the ink and the surface behind it -- so `==
ACCENT` counts a handful of interior pixels of a bold glyph and misses a thin word entirely. On
this theme the four colours that can appear in the HUD column separate cleanly on green dominance:

    ACCENT    (128,229,140)   +89     <- the only positive one
    SURFACE    (37, 40, 48)    -8
    INK       (229,233,241)    -8
    INK_MUTED (167,176,190)   -14

A blend of SURFACE and ACCENT crosses zero at 8% accent and the margin at 17%, so any pixel with a
sixth of accent in it is caught and nothing else in the palette can be. The margin is what makes
this a measurement rather than a rounding artefact: at `>= 1` a rounded grey would read as green.

**POINT IT AT TEXT AND CHROME, NEVER AT A BAND WITH SPRITES IN IT.** The reasoning above is about
the THEME's palette, and a prerendered item icon is not in it. Scanning the whole HUD column of
`02-play.png` reports 3514 accent-family pixels, and 2012 of them are the two inventory icons at
x 946..977 whose commonest value is an olive `(130,149,99)` that Blender rendered. That is art, not
an unchosen UI colour -- but a reader handed the single figure 3514 would file a defect. The bands
that mean something here are one control's rect at a time:

    y  96..130   x 946..997   1502 px   <- `Mine`, the screen's one Primary. Core (128,229,140).
    y 186..214   x 936..1256     0 px   <- the four tab names. The defect, gone.
    y 214..320   x 946..977   2012 px   <- two item SPRITES. Not a colour anybody chose in a theme.

    tools/strip_accent.py <shot.png> x0 y0 x1 y1 [out-crop.png]
"""

import struct
import sys
import zlib

MARGIN = 8


def read_png(path):
    """Return (width, height, rows as packed RGB bytes). 8-bit RGB/RGBA, no interlace."""
    with open(path, "rb") as handle:
        data = handle.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "%s is not a PNG" % path
    pos, idat, width, height, channels = 8, bytearray(), 0, 0, 0
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        kind = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour = struct.unpack(">IIBB", body[:10])
            assert depth == 8, "only 8-bit PNGs, got %d" % depth
            assert body[12] == 0, "interlaced PNGs are not handled"
            channels = {2: 3, 6: 4}.get(colour)
            assert channels, "only RGB/RGBA PNGs, got colour type %d" % colour
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
        pos += 12 + length
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    out, prior, at = [], bytearray(stride), 0
    for _ in range(height):
        filt = raw[at]
        line = bytearray(raw[at + 1 : at + 1 + stride])
        at += 1 + stride
        # The five PNG line filters, in full: a partial implementation is the kind of thing that
        # reads fine on one image and silently shifts colours on the next.
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prior[i]
            c = prior[i - channels] if i >= channels else 0
            if filt == 1:
                line[i] = (line[i] + a) & 0xFF
            elif filt == 2:
                line[i] = (line[i] + b) & 0xFF
            elif filt == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                best = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + best) & 0xFF
        prior = line
        out.append(b"".join(bytes(line[i : i + 3]) for i in range(0, stride, channels)))
    return width, height, out


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + row for row in rows)
    chunks = b""
    for kind, body in (
        (b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)),
        (b"IDAT", zlib.compress(raw, 9)),
        (b"IEND", b""),
    ):
        chunks += struct.pack(">I", len(body)) + kind + body
        chunks += struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n" + chunks)


def main():
    if len(sys.argv) < 6:
        sys.exit(__doc__)
    shot = sys.argv[1]
    x0, y0, x1, y1 = (int(v) for v in sys.argv[2:6])
    width, height, rows = read_png(shot)
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(width, x1), min(height, y1)
    found, lo, hi, cols = 0, width, -1, {}
    band = []
    for y in range(y0, y1):
        row = rows[y]
        out = bytearray()
        for x in range(x0, x1):
            r, g, b = row[3 * x], row[3 * x + 1], row[3 * x + 2]
            out += bytes((r, g, b))
            if g - max(r, b) >= MARGIN:
                found += 1
                lo, hi = min(lo, x), max(hi, x)
                cols[(r, g, b)] = cols.get((r, g, b), 0) + 1
        band.append(bytes(out))
    print("%s  band x %d..%d y %d..%d" % (shot, x0, x1, y0, y1))
    print("  accent-family pixels (g - max(r,b) >= %d): %d" % (MARGIN, found))
    if found:
        print("  they span x %d..%d" % (lo, hi))
        for colour, n in sorted(cols.items(), key=lambda kv: -kv[1])[:3]:
            print("    %-18s %d px" % (str(colour), n))
    if len(sys.argv) > 6:
        write_png(sys.argv[6], x1 - x0, y1 - y0, band)
        print("  crop -> %s" % sys.argv[6])


main()
