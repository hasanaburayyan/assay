"""THE FONT THE REVIEW SHEETS DRAW TEXT WITH, in one place. (ASSA-114)

    from review_font import font
    d.text((x, y), line, fill, font=font(13))

WHY THIS EXISTS AND IS NOT JUST A PREFERENCE. Every pack row's stack line is
`6 × Minyte refined (B)` -- U+00D7, read out of the layout the engine hands
back. `ImageFont.load_default()` HAS NO GLYPH FOR IT: rendered alone it comes
out pixel-identical to U+FFFF, the notdef box. So all three pack sheets were
drawing `6 ⍰ Minyte refined (B)`.

That is worse than a missing symbol. These sheets exist so somebody can judge a
surface without the engine, and Maren has ruled on the pack row from them more
than once. A sheet showing a defect the client does not have is the failure my
notes keep recording: the instrument lying before the artefact does. A reviewer
could file the box as a client bug, or discount a line that actually reads fine.

WHAT THIS DOES NOT CLAIM. Nothing here says the CLIENT renders U+00D7 correctly
in its own theme font. The layout probe returns the STRING, not the raster, and
I have no window. This fixes the picture of the row, not the row.

THE CANDIDATES, in order, and why a chain rather than one name: these scripts
run on whatever machine an agent happens to hold, and hard-coding one path makes
the sheet unreproducible everywhere else. A clean sans first, because that is
what the sheets already looked like and a font change moves every glyph on them.

IF NOTHING IS FOUND the default comes back AND SAYS SO. Silently falling back is
how this defect survived in the first place: the sheets looked fine at a glance
and nobody reads a stack line character by character.
"""
import sys

from PIL import Image, ImageDraw, ImageFont

# Clean sans first (closest to what these sheets already were), then monospace.
CANDIDATES = (
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/System/Library/Fonts/SFNSMono.ttf",
    "/System/Library/Fonts/Supplemental/Menlo.ttc",
    "/System/Library/Fonts/Menlo.ttc",
)

# The character the sheets were getting wrong, and therefore the one a candidate has
# to prove it can draw. Not a general "is this font good" test -- a specific one.
WANTED = "×"

_chosen = None


def _draws(f, ch):
    """True if `f` draws `ch` as something OTHER than its notdef box.

    The same comparison that found the defect, run on the candidate rather than
    asserted about it: render the character alone, render U+FFFF alone, and ask
    whether the two bitmaps differ. A font without the glyph gives the same box
    for both, which is exactly what `load_default` does for U+00D7.
    """
    def bits(c):
        im = Image.new("L", (40, 40), 0)
        ImageDraw.Draw(im).text((2, 2), c, 255, font=f)
        return im.tobytes()
    return bits(ch) != bits("￿")


def _pick():
    global _chosen
    if _chosen is not None:
        return _chosen
    for path in CANDIDATES:
        try:
            if _draws(ImageFont.truetype(path, 13), WANTED):
                _chosen = path
                return _chosen
        except OSError:
            continue
    _chosen = ""
    print("REVIEW SHEET FONT: no candidate could draw %r, falling back to PIL's default.\n"
          "  The stack lines on this sheet will show a TOFU BOX where the game shows a\n"
          "  multiplication sign. That is the sheet, not the client (ASSA-114). Add a font\n"
          "  path to art/review_font.CANDIDATES for this machine." % WANTED, file=sys.stderr)
    return _chosen


def font(size):
    """A font of `size` that can draw what the game's stack lines contain."""
    path = _pick()
    if path:
        return ImageFont.truetype(path, size)
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def chosen():
    """Which font the sheets are actually using, so a sheet can say so."""
    return _pick() or "PIL default (no multiplication sign)"
