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
## How far from a glyph core a pixel must be before it counts as background.
DILATE = 3
## **OTHER CONTROLS ARE NOT "WHAT IS BEHIND THE WORDS", AND THE CONTROL CAUGHT ME TREATING THEM AS
## IT.** On the flat field this script reported 1.00:1 for the wordmark where Maren measured 14.0,
## because a 12 px surround reaches the `Play solo` button and a host field, and their fills are
## bright. A button sitting near a sentence is not the surface the sentence stands on -- and its own
## legibility is already held by `build_theme.gd`, which REFUSES to write a theme whose ink pairs
## fall under 4.5:1. That is a better guard than this script, so this script stays out of its way.
## **ONLY THE BRIGHT ONES, AND LEAVING RAISED IN HERE COST A RUN.** The reported number is the
## BRIGHTEST pixel of the surface, so a dark control can never be it and excluding one buys nothing --
## while `RAISED` (53,57,67) is within tolerance of what the plate itself composites to over grass
## (~48,53,55), so listing it made the script skip the plate and report an empty ring. A filter that
## removes the thing being measured is the same mistake as a mask that counts a glyph fringe as
## background; it is just quieter about it.
FURNITURE = {
    "ACCENT": (128, 229, 140),
    "HOVER": (242, 242, 242),
}
FURNITURE_TOLERANCE = 24
## Above this the pixel is the lit world, below it the plate (or the old flat field).
PLATE_MAX_LUMA = 0.06
## The shortest contiguous dark run that can be a plate. No scatter prop in this world is this wide.
PLATE_MIN_RUN = 200
## How deep the measured ring of plate is, inside DOOR_PLATE_PAD = 24 so it holds no text.
RING = 16
# The door's own rectangle, `AssayHud.join_rect()`: x 24..936, y 24..696. Keeps the HUD column and
# the world's own sprites out of the mask.
DOOR = (24, 24, 936, 696)


def near(rgb, want, tolerance=TOLERANCE):
    return all(abs(rgb[i] - want[i]) <= tolerance for i in range(3))


def main():
    """**MEASURE THE SURFACE, NEVER THE GLYPHS.**

    Four versions of this script tried to separate text pixels from background pixels by colour, and
    all four were wrong in a different way -- the last because a 13 px anti-aliased sentence has
    strokes that NEVER reach the token colour, so the mask missed the glyph entirely and then scored
    its own fringe as background. Colour cannot do this job: a half-lit glyph edge and a bright
    background are the same number, which is precisely the case the tool exists to catch.

    So it stops trying. The inks are KNOWN -- they are tokens out of `build_theme.gd`, not something
    to be found in a picture. The only unknown is the SURFACE the words stand on, and that can be
    measured where there are provably no glyphs: the plate's own padding, `DOOR_PLATE_PAD` of air on
    every side by construction. The reported number is the WORST (brightest) pixel of that ring,
    because a light ink loses contrast as its background brightens.

    The control is unchanged and is what every version was judged against: on the flat field this
    must return Maren's independently measured 14.0:1 and 7.79:1.
    """
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    for path in sys.argv[1:]:
        width, height, channels, rows = read_png(path)
        x0, y0, x1, y1 = DOOR
        x1, y1 = min(x1, width), min(y1, height)
        print("\n=== %s ===" % path)
        # THE PLATE IS THE DARK RECTANGLE INSIDE THE WORLD. Over lit grass it composites to roughly
        # (48,53,55) and over an ore deposit to (58,51,51); the world around it is several times
        # brighter. On the flat field there is no plate and the whole door is dark, so the bounding
        # box becomes the door -- which is the right answer there and is what keeps the control honest
        # rather than needing a second code path.
        # **A PLATE IS A SOLID RUN, NOT SCATTERED DARK PIXELS, and the first version of this did not
        # say so.** The lit world is full of dark specks -- scatter props, ore outlines, the spawn
        # pad -- so a bounding box over every dark pixel spans the whole map and measures nothing.
        # Requiring a contiguous horizontal run of PLATE_MIN_RUN excludes all of them: no prop in
        # this world is 200 px wide.
        dark = None
        for y in range(y0, y1):
            run_start = None
            for x in range(x0, x1 + 1):
                is_dark = x < x1 and luminance(pixel(rows, channels, x, y)) < PLATE_MAX_LUMA
                if is_dark:
                    if run_start is None:
                        run_start = x
                    continue
                if run_start is not None and x - run_start >= PLATE_MIN_RUN:
                    lo, hi = run_start, x - 1
                    dark = (min(dark[0], lo), min(dark[1], y), max(dark[2], hi), max(dark[3], y)) \
                        if dark else (lo, y, hi, y)
                run_start = None
        if dark is None:
            print("  no plate and no dark field found: nothing to measure")
            continue
        px0, py0, px1, py1 = dark
        print("  surface x %d..%d  y %d..%d  (%dx%d)"
              % (px0, px1, py0, py1, px1 - px0 + 1, py1 - py0 + 1))
        # THE RING: the outer band of that rectangle. Provably text-free -- the plate is built with a
        # full pad of air on every side -- and inside it, so it is the same composite the words sit on.
        worst = None
        ring = 0
        for y in range(py0, py1 + 1):
            for x in range(px0, px1 + 1):
                inner = (px0 + RING < x < px1 - RING) and (py0 + RING < y < py1 - RING)
                if inner:
                    continue
                rgb = pixel(rows, channels, x, y)
                if any(near(rgb, f, FURNITURE_TOLERANCE) for f in FURNITURE.values()):
                    continue
                ring += 1
                lum = luminance(rgb)
                if worst is None or lum > worst[1]:
                    worst = (rgb, lum, x, y)
        if worst is None:
            print("  the ring is empty, so the surface cannot be judged")
            continue
        print("  worst surface pixel %-16s at (%d,%d), out of %d ring px"
              % (str(worst[0]), worst[2], worst[3], ring))
        for name, token in INKS.items():
            got = ratio(token, worst[0])
            print("    %-10s %6.2f:1   %s"
                  % (name, got, "PASS >= 4.5" if got >= 4.5 else "FAILS MAREN FLOOR 1"))


if __name__ == "__main__":
    main()
