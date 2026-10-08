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


## **THE RECTANGLE THE WORDS STAND ON -- AND THE VERSION THIS REPLACES UNIONED EVERY ROW'S RUN.**
##
## That defect was mine and it is worth writing down, because it made the instrument blame the thing
## it was built to defend. `dark` grew by `min`/`max` over every row holding a long dark run, so ONE
## row reaching a single pixel further left than the plate moved `px0` for ALL of them -- and the ring
## then sampled that column down all 233 rows of the card, where it is not plate at all but lit
## grass. On ASSA-311's sweep that read **1.83:1** and failed Maren's floor on 8 of 128 frames. The
## card had not moved a pixel; my box had.
##
## **A PLATE IS A RECTANGLE, SO ASK THE ROWS WHAT THEY AGREE ON.** The span the most rows report
## EXACTLY is the plate's own; a stray row beside it, an anti-aliased edge pixel, or a dark world band
## of some other width is one row each and loses. **Exactness is the whole point** -- an off-by-one
## edge pixel is precisely the thing that must not be absorbed, which is why these are not clustered
## within a tolerance. A tolerance here would re-create the bug with extra steps.
##
## The y extent is read off the rows that match that span and nothing else, so a dark band elsewhere
## in the world cannot stretch the box vertically either.
##
## **IT REPORTS THE UNION IT DID NOT USE.** A disagreement between the union and the agreed span is
## real information -- something dark is touching the plate -- and a detector that quietly picked the
## better of two answers would be the same class of check as the one it replaces.
##
## Returns `(rect, union, rows_agreeing, rows_dark)`, or None when no row holds a plate-wide run.
def plate_rect(rows, channels, door):
    x0, y0, x1, y1 = door
    spans = {}
    for y in range(y0, y1):
        run_start = None
        for x in range(x0, x1 + 1):
            is_dark = x < x1 and luminance(pixel(rows, channels, x, y)) < PLATE_MAX_LUMA
            if is_dark:
                if run_start is None:
                    run_start = x
                continue
            if run_start is not None and x - run_start >= PLATE_MIN_RUN:
                spans.setdefault((run_start, x - 1), []).append(y)
            run_start = None
    if not spans:
        return None
    # Most rows wins; a tie goes to the wider span, because the plate is the widest thing in this
    # picture that is dark and a tie broken by dict order would make the answer depend on scan order.
    (lo, hi), ys = max(spans.items(), key=lambda kv: (len(kv[1]), kv[0][1] - kv[0][0]))
    union = (min(span[0] for span in spans),
             min(min(rows_at) for rows_at in spans.values()),
             max(span[1] for span in spans),
             max(max(rows_at) for rows_at in spans.values()))
    return (lo, min(ys), hi, max(ys)), union, len(ys), sum(len(v) for v in spans.values())


def write_png(path, width, height, fill, rects):
    """A PNG writer that exists ONLY for `selftest`, so the control needs no screenshot to run."""
    pixels = [[fill] * width for _ in range(height)]
    for rx0, ry0, rx1, ry1, colour in rects:
        for y in range(ry0, ry1 + 1):
            for x in range(rx0, rx1 + 1):
                pixels[y][x] = colour
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for rgb in row:
            raw.extend(rgb)

    def chunk(tag, body):
        return (struct.pack(">I", len(body)) + tag + body
                + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))

    head = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", head)
                     + chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b""))


def selftest():
    """**THE CONTROL FOR THE DETECTOR, ON PICTURES THIS FILE DRAWS ITSELF.**

    The script's other control -- Maren's 14.0:1 and 7.79:1 on the flat field -- is the better one
    because she measured it independently, and it stays. It cannot catch THIS defect: the flat field
    has no plate to mis-detect, so the union and the agreed span are the same rectangle there and the
    bug passed that control for as long as it existed.

    So the plate-finding gets a control of its own, on synthetic frames with a rectangle at a known
    place. Case A is the exact shape of the bug and fails loudly on the old code; case B is the flat
    field, which must still come back as the whole door; case C is a frame with no plate at all,
    which must stay unreadable rather than quietly returning something.
    """
    import os
    import tempfile
    grass = (92, 120, 74)
    plate = (48, 53, 55)
    map_bg = (26, 28, 33)
    # ASSA-292's card, as Maren measured it: 565x233 at x 357..921, y 229..461.
    card = (357, 229, 921, 461)
    out = tempfile.mkdtemp(prefix="nacre-plate-control-")
    failures = []

    def check(name, got, want):
        print("  %-34s %s\n%s%s" % (name, "PASS" if got == want else "FAILS",
                                    " " * 37, "got %s want %s" % (got, want)))
        if got != want:
            failures.append(name)

    # CASE A: THE BUG. The card, plus ONE stray plate-wide dark run beside it starting a single pixel
    # further left. The union answer is x 356.., which is what read 1.83:1 off a grass column.
    path_a = os.path.join(out, "a-stray-run-beside-the-card.png")
    write_png(path_a, 1280, 720, grass,
              [(card[0], card[1], card[2], card[3], plate), (356, 200, 596, 200, plate)])
    width, height, channels, rows = read_png(path_a)
    rect, union, agree, total = plate_rect(rows, channels, DOOR)
    check("A card found, not the union", rect, card)
    check("A union is reported, not hidden", union, (356, 200, 921, 461))
    check("A the stray row is one row", total - agree, 1)

    # CASE B: the flat field. Every row of the door is one plate-wide run, so the answer is the door.
    path_b = os.path.join(out, "b-flat-field.png")
    write_png(path_b, 1280, 720, map_bg, [])
    width, height, channels, rows = read_png(path_b)
    rect, union, agree, total = plate_rect(rows, channels, DOOR)
    check("B flat field is the whole door", rect, (DOOR[0], DOOR[1], DOOR[2] - 1, DOOR[3] - 1))
    check("B union agrees on the flat field", union, rect)

    # CASE C: no plate. Must stay unreadable; `summarise` turns that into a non-zero exit.
    path_c = os.path.join(out, "c-no-plate.png")
    write_png(path_c, 1280, 720, grass, [])
    width, height, channels, rows = read_png(path_c)
    check("C no plate reads as nothing", plate_rect(rows, channels, DOOR), None)

    print("\n=== DETECTOR CONTROL: %s ===" % ("PASS" if not failures else "FAILED " + str(failures)))
    raise SystemExit(1 if failures else 0)


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
    ## THE DETECTOR'S OWN CONTROL, which needs no window and no shot: `--selftest`. Run it after any
    ## change to `plate_rect`; it fails on the union bug this file used to have.
    if sys.argv[1] == "--selftest":
        selftest()
    ## ONE READING PER FILE, kept so a set of files can be reduced to its worst member. See the
    ## summary at the bottom: this is how box 2's "the worst frame of the drift" is answered, and the
    ## per-file numbers above are unchanged by it.
    readings = []
    unreadable = []
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
        found = plate_rect(rows, channels, (x0, y0, x1, y1))
        if found is None:
            print("  no plate and no dark field found: nothing to measure")
            unreadable.append(path)
            continue
        (px0, py0, px1, py1), union, agree, total = found
        print("  surface x %d..%d  y %d..%d  (%dx%d)  %d of %d dark rows agree on that span"
              % (px0, px1, py0, py1, px1 - px0 + 1, py1 - py0 + 1, agree, total))
        if union != (px0, py0, px1, py1):
            print("  NOTE the union of every dark row is x %d..%d y %d..%d: something dark touches "
                  "the plate. Measuring the AGREED span, which is the plate."
                  % (union[0], union[2], union[1], union[3]))
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
            unreadable.append(path)
            continue
        print("  worst surface pixel %-16s at (%d,%d), out of %d ring px"
              % (str(worst[0]), worst[2], worst[3], ring))
        got_all = {}
        for name, token in INKS.items():
            got = ratio(token, worst[0])
            got_all[name] = got
            print("    %-10s %6.2f:1   %s"
                  % (name, got, "PASS >= 4.5" if got >= 4.5 else "FAILS MAREN FLOOR 1"))
        readings.append((path, got_all, worst))
    if len(sys.argv) > 2:
        summarise(readings, unreadable)


def summarise(readings, unreadable):
    """**THE WORST FRAME OF A SET, WHICH IS MAREN'S BOX 2** (ASSA-292): *"measured at the WORST frame
    of the drift and not frame 0, with the sample gap stated."*

    The sample gap is the other tool's business -- `tools/nacre_door_drift_sweep.gd` sweeps one whole
    `TITLE_DRIFT_PERIOD` in a real window and prints the step it achieved between neighbours. This
    reduces the frames it wrote to the one that reads worst, per ink, because a floor is a promise
    about every frame and so it is decided by the worst of them.

    **AN UNREADABLE FRAME IS A LOUD FAILURE AND NOT A SKIPPED ROW.** A minimum over the frames that
    happened to parse is exactly the shape of a check that cannot fail: the frame where the plate
    went missing is the frame most likely to read worst, and quietly dropping it would turn the
    defect into a better number.
    """
    print("\n=== WORST OF %d FRAMES ===" % len(readings))
    if unreadable:
        print("  %d FRAMES HELD NO MEASURABLE SURFACE, so there is no worst-frame claim to make "
              "here: %s" % (len(unreadable), ", ".join(unreadable[:4])))
        raise SystemExit(1)
    if not readings:
        print("  nothing was measured")
        raise SystemExit(1)
    failed = False
    for name in INKS:
        path, got_all, worst = min(readings, key=lambda row: row[1][name])
        verdict = "PASS >= 4.5" if got_all[name] >= 4.5 else "FAILS MAREN FLOOR 1"
        failed = failed or got_all[name] < 4.5
        print("  %-10s %6.2f:1   %s   worst at %s, surface %s"
              % (name, got_all[name], verdict, path.split("/")[-1], str(worst[0])))
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
