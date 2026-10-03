"""JUST ENOUGH OF PILLOW'S IMAGE SURFACE for a CI check to run the real blit.

    from stdlib_image import StdlibBackend
    frame = StdlibBackend.open_frame(path, x, y, w, h)   # RGBA, cropped
    plate = StdlibBackend.new_plate(w, h, (r, g, b))     # RGB, filled

WHY THIS EXISTS, and it is not "to avoid a dependency". `pack_icon_draw.py`
holds the ONE copy of how the engine samples a pack icon -- nearest with a
fractional quad edge -- and its docstring says why that may never be
duplicated: two copies of a sampling rule can disagree about what the client
drew while both look right.

A `check_*.py` runs on plain `python3` with no pip. So the choice was: let the
check reimplement the blit in stdlib (two copies of the rule, the exact failure
that module exists to prevent), or give the existing blit an image object it can
work on without Pillow. This is the second. `nearest_blit` is called UNCHANGED
by the Pillow caller and by the stdlib caller, so there is one sampling rule and
two ways of holding pixels.

WHAT IS DELIBERATELY MISSING. No resize, no paste, no save: the review sheets
need those and they are Pillow's job, outside CI. A check only needs to read a
frame, fill a plate and composite. If a future check needs more than that, add
it here rather than growing a second decoder -- the PNG reading itself is
Maren's `png_stdlib.read_rgba`, vendored once.

NOT A SECOND DECODER AND NOT A SECOND METRIC: pixels come from `png_stdlib`,
colour distance comes from `colour.py`. This file holds no arithmetic about
either.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from png_stdlib import read_rgba  # noqa: E402  (after sys.path, on purpose)


class _Pixels:
    """`px[x, y]` get and set, Pillow's indexing order, over a row-major list."""

    def __init__(self, rows):
        self._rows = rows

    def __getitem__(self, xy):
        x, y = xy
        return self._rows[y][x]

    def __setitem__(self, xy, value):
        x, y = xy
        self._rows[y][x] = value


class StdlibImage:
    """An image with `.size`, `.width`, `.height` and `.load()`. Nothing else.

    Pixels are whatever tuple width the caller put in: a frame read off a sheet
    holds (r, g, b, a) and a plate holds (r, g, b), which is exactly what the
    Pillow versions of each hand to `nearest_blit`. This class does not convert
    between them, because a conversion here would be a rule about colour living
    in a container.
    """

    def __init__(self, rows):
        self._rows = rows
        self.height = len(rows)
        self.width = len(rows[0]) if rows else 0
        self.size = (self.width, self.height)

    def load(self):
        return _Pixels(self._rows)


class StdlibBackend:
    """The two factories `pack_icon_draw.drawn_icon` needs, without Pillow."""

    name = "stdlib"

    @staticmethod
    def open_frame(path, x, y, w, h):
        _sw, _sh, px = read_rgba(str(path))
        x, y, w, h = int(x), int(y), int(w), int(h)
        return StdlibImage([row[x:x + w] for row in px[y:y + h]])

    @staticmethod
    def new_plate(w, h, colour):
        return StdlibImage([[colour for _ in range(w)] for _ in range(h)])
