#!/usr/bin/env python3
"""HOW MUCH OF THE FIRST SCREEN IS PICTURE (ASSA-292, Maren's rectangle and card rulings).

Her two numbers off my own 1x shot were what turned "the plate looks like a band" into two ordered
moves, and both of them are shares of the window:

    lit world + plate   912x672 at x 24..935    66.5% of the window
    the plate           912x261 at y 229..489   25.8%
    visible picture                             40.7%
    BARE DARK WINDOW                            33.5%
      one column of it  344x720 at x 936..1279  26.9%, every px (26,28,33)

So this measures the same three things on a frame, and nothing else: how much is bare window, how
much is plate, how much is left as picture.

HOW EACH ONE IS FOUND, and why neither is a guess:

  BARE WINDOW is exactly `MAP_BG` (26,28,33). Not "dark": exact. That is the colour the world layer
  paints where nothing is drawn, and Maren's column was every pixel of it. An exact match cannot be
  confused with a shadowed grass tile, and if the ground ever stops covering the world, this number
  rises and says so -- which is a defect too.

  THE PLATE is `SURFACE` at alpha 0.90 over whatever is behind it, so a plate pixel is
  `0.9*SURFACE + 0.1*world`: every channel lands within a tenth of the world's range above
  0.9*SURFACE. That gives a tight band per channel which `MAP_BG` itself falls outside (26 < 33),
  so the two measurements cannot double-count. **THE CONTROL FOR THAT CLAIM IS PRINTED, NOT
  ASSUMED**: the script reports the plate's bounding box and how solidly it is filled, and a
  detector that has found something other than a rectangle will not report ~100%.

**A DETECTOR WITH NO BOUND IS WORSE THAN NONE** (the rule this file exists under). Two bounds here:
a run of plate-coloured pixels shorter than MIN_RUN is not a plate row, and the fill percentage of
the bounding box is printed so a scatter of false positives is visible as a low number rather than
as a confident rectangle.

Usage: nacre_door_plate_share.py FRAME.png [FRAME.png ...]
"""
import sys
import zlib
import struct

MAP_BG = (26, 28, 33)
SURFACE = (37, 40, 48)
ALPHA = 0.90

## A row needs this many plate-coloured pixels to count as a row of plate. The narrowest card this
## screen can produce still carries the wordmark, which is 152 px of ink plus two 24 px pads.
MIN_RUN = 120


def read_png(path):
    """Minimal PNG reader: 8-bit RGB/RGBA, non-interlaced."""
    with open(path, "rb") as handle:
        data = handle.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    at, idat, width, height, depth, kind = 8, b"", None, None, None, None
    while at < len(data):
        length = struct.unpack(">I", data[at:at + 4])[0]
        tag = data[at + 4:at + 8]
        chunk = data[at + 8:at + 8 + length]
        at += 12 + length
        if tag == b"IHDR":
            width, height, depth, kind = struct.unpack(">IIBB", chunk[:10])
        elif tag == b"IDAT":
            idat += chunk
        elif tag == b"IEND":
            break
    assert depth == 8 and kind in (2, 6), (depth, kind)
    channels = 3 if kind == 2 else 4
    raw = zlib.decompress(idat)
    stride = width * channels
    out = bytearray()
    prev = bytearray(stride)
    at = 0
    for _ in range(height):
        filt = raw[at]
        at += 1
        line = bytearray(raw[at:at + stride])
        at += stride
        for x in range(stride):
            a = line[x - channels] if x >= channels else 0
            b = prev[x]
            c = prev[x - channels] if x >= channels else 0
            if filt == 1:
                line[x] = (line[x] + a) & 255
            elif filt == 2:
                line[x] = (line[x] + b) & 255
            elif filt == 3:
                line[x] = (line[x] + ((a + b) >> 1)) & 255
            elif filt == 4:
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        out += line
        prev = line
    rows = []
    for y in range(height):
        row = []
        base = y * stride
        for x in range(width):
            o = base + x * channels
            row.append((out[o], out[o + 1], out[o + 2]))
        rows.append(row)
    return width, height, rows


def plate_band():
    """The per-channel range a `SURFACE`-at-0.90 pixel can land in, over any world pixel 0..255."""
    lo = tuple(int(ALPHA * c) for c in SURFACE)
    hi = tuple(int(ALPHA * c + (1.0 - ALPHA) * 255) + 1 for c in SURFACE)
    return lo, hi


def is_plate(px, lo, hi):
    return all(lo[i] <= px[i] <= hi[i] for i in range(3))


def measure(path):
    width, height, rows = read_png(path)
    lo, hi = plate_band()
    total = width * height
    bare = 0
    bare_right = 0
    plate_px = 0
    top = left = 1 << 30
    bottom = right = -1
    for y in range(height):
        row = rows[y]
        run = 0
        first = None
        last = None
        for x in range(width):
            px = row[x]
            if px == MAP_BG:
                bare += 1
                if x >= 936:
                    bare_right += 1
                continue
            if is_plate(px, lo, hi):
                run += 1
                if first is None:
                    first = x
                last = x
        if run >= MIN_RUN:
            plate_px += run
            top = min(top, y)
            bottom = max(bottom, y)
            left = min(left, first)
            right = max(right, last)
    print("%s  %dx%d" % (path, width, height))
    print("  bare window (exactly MAP_BG)   %7d px  %5.1f%%   of it right of x=936: %d px"
          % (bare, 100.0 * bare / total, bare_right))
    if bottom < 0:
        print("  plate                           NONE FOUND (no row had %d plate pixels)" % MIN_RUN)
        print("  visible picture                %7d px  %5.1f%%" % (total - bare,
                                                                    100.0 * (total - bare) / total))
        return
    box_w = right - left + 1
    box_h = bottom - top + 1
    box = box_w * box_h
    print("  plate                          %7d px  %5.1f%%   %dx%d at x %d..%d y %d..%d"
          % (plate_px, 100.0 * plate_px / total, box_w, box_h, left, right, top, bottom))
    print("  plate box fill (the control)     %5.1f%%   <- a scatter of false positives reads low"
          % (100.0 * plate_px / box))
    picture = total - bare - plate_px
    print("  visible picture                %7d px  %5.1f%%" % (picture, 100.0 * picture / total))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for frame in sys.argv[1:]:
        measure(frame)
