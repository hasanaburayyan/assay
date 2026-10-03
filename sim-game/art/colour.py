"""THE HOUSE COLOUR METRIC, in one place and importable without Pillow.

    from colour import DISTINCT, dE, lab

NOT NEW MATH. Every line here was `species_probe.py`'s and is moved UNCHANGED;
that file now imports it back, so there is still exactly one `dE` in the repo
and `assemble.py` and `loudness.py` keep importing it from where they always
did. If this ever disagrees with species_probe, the bug is that somebody made
a second copy, which is the thing the move exists to prevent.

WHY IT HAD TO MOVE. `species_probe.py` does `from PIL import Image` at module
scope, and CI runs the `art/check_*.py` family on plain `python3` with no pip
(PIL is not installed on the studio Mac either -- Maren, in `png_stdlib.py`).
So a check could not ask the house question "how far apart are these two
colours" without retyping the answer. One of those retyped copies is how the
map-disc constants went wrong three times in a row, each time in the direction
that flattered the art.

THE THRESHOLDS ARE MAREN'S, NOT MINE, and that matters when a check quotes
them: a guard built on `DISTINCT` is enforcing a ruling, while a guard built on
a number its author chose is enforcing an opinion. Anything in `art/` that
needs a bound takes it from here or says out loud in its own output that the
number is the author's.
"""
import math

# dE76 thresholds. 2.3 is the just-noticeable difference under ideal side-by-
# side viewing; nothing on a game map is ideal or side-by-side, so:
JND = 2.3
DISTINCT = 12.0     # two species a player must never confuse at a glance


def _lin(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lab(rgb):
    r, g, b = (_lin(c) for c in rgb[:3])
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = (0.2126 * r + 0.7152 * g + 0.0722 * b)
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    f = lambda t: t ** (1 / 3.0) if t > 0.008856 else 7.787 * t + 16 / 116.0
    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def dE(a, b):
    la, lb = lab(a), lab(b)
    return math.sqrt(sum((la[i] - lb[i]) ** 2 for i in range(3)))
