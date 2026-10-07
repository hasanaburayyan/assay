#!/usr/bin/env python3
"""THE PLATE'S DERIVATION, ON INPUTS WHOSE RIGHT ANSWER IS KNOWN BY CONSTRUCTION (ASSA-261)

    art/check_plate_statistic.py                 # the guard
    art/check_plate_statistic.py <dir-with-ui_theme.py>   # judge another copy, e.g. the old one:
        mkdir /tmp/old && git show <sha>:sim-game/art/ui_theme.py > /tmp/old/ui_theme.py
        cp art/png_stdlib.py /tmp/old/ && art/check_plate_statistic.py /tmp/old   -> FAIL, as it must

WHY THIS EXISTS. `check_pack_icon_plate.py` guards an IDENTITY -- the sheet, the shipped
`ui_theme.json` and the colour the engine painted are the same -- and that is blind to the
derivation being the wrong statistic. It passed every day `ui_theme.py` derived the plate from a
per-channel MEDIAN while 32.5% of the ground sat on one luminance level and the median sat on that
spike, so the plate was 3.2 levels off the ground it is supposed to BE (ASSA-71). Nothing went red.
Same shape as the gap `check_ground_form.py` closed for the ground itself.

AND WHY IT IS NOT A TOLERANCE ON THE REAL SHEET, which is the obvious version and is circular.
Pin the plate near the real ground's bare mean and the bare mean has become the definition -- which
goes red on exactly the heavy-speckle case the trim exists for. Pick a looser number that happens
to catch the old median and you are choosing a constant to catch the case you already know about.

So this guards the derivation on SYNTHETIC sheets instead, where the correct answer is arithmetic
rather than taste. Three properties, each a defect the plate has actually had or nearly had, each
failing a different wrong implementation:

  1. A MAJORITY SPIKE MUST NOT CAPTURE THE PLATE.  Fails a median.
  2. THE VALUE IS ROUNDED, NOT TRUNCATED.          Fails a TRUNCATED mean.
  3. A SMALL ONE-SIDED TAIL MUST BE RESISTED.      Fails a bare mean.

Property 2 is about the statistic that ships, not about `int()` in the abstract: `int()` on a
median passes it, correctly, because a median of integers is already an integer. Truncation cost
nothing for as long as the statistic was a median, and costs half a level per channel on every
build the moment it is not. Each of the three was proved red on a real file rather than asserted:
1 on `git show 62835a2:…/ui_theme.py`, 2 on that file with `round` removed, 3 on it with the trim
set to zero.

Property 1 is the ASSA-261 defect, 3 is the reason `ui_theme.py` chose a median in the first place
and the reason Maren's call was "trimmed, not bare", and 2 is the half-level darkening that
switching to a mean would otherwise have smuggled in. A statistic has to satisfy all three, which
is what rules out all three wrong answers at once.

EXIT CODES
  0 PASS       -- the derivation has all three properties.
  1 FAIL       -- it does not; the report says which and what it gave instead.
  2 NO VERDICT -- could not build a sheet or import the module. Never a pass.
"""
import os
import struct
import sys
import zlib

ART = os.path.dirname(os.path.abspath(__file__))

# Alpha for "this is ground". Must be >= ui_theme.OPAQUE or the sheets read as empty.
SOLID = 255


def write_png(path, rows):
    """Minimal RGBA8 PNG. Written here because `png_stdlib` only reads.

    Deliberately a real file through a real encoder: the point is to drive the SHIPPED
    `plate_rgb`, which opens a path and decodes it. A test that called the trimming
    helper directly would pass with the shipped function wired up wrongly -- the exact
    way a sub-tile test of mine stayed green through the bug it was written for.
    """
    w, h = len(rows[0]), len(rows)
    raw = b"".join(b"\x00" + b"".join(bytes(px) for px in row) for row in rows)

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data +
                struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        f.write(chunk(b"IEND", b""))


def sheet_from_counts(counts, side=120):
    """A `side`x`side` sheet holding each (level, count-share) in the given proportion.

    Grey (r == g == b), so every channel sees the same distribution and the expected
    answer is one number instead of three. Laid out in reading order, which is enough:
    nothing in the derivation looks at position.
    """
    total = side * side
    flat = []
    for level, share in counts:
        flat += [(level, level, level, SOLID)] * int(round(total * share))
    if len(flat) < total:
        flat += [flat[-1]] * (total - len(flat))
    flat = flat[:total]
    return [flat[y * side:(y + 1) * side] for y in range(side)]


def trimmed(vals, frac):
    """Reference trimmed mean, for stating what each property's right answer IS.

    Not imported from `ui_theme`: this is the thing the expectations are computed from,
    so sharing the implementation would make every expectation agree with the code under
    test by construction. That is the "control that cannot fail" trap, and it has caught
    me twice this week.
    """
    s = sorted(vals)
    k = int(len(s) * frac)
    if k and len(s) - 2 * k > 0:
        s = s[k:len(s) - k]
    return sum(s) / len(s)


def values(rows):
    return [px[0] for row in rows for px in row]


def main():
    print(__doc__.splitlines()[0])

    mod_dir = sys.argv[1] if len(sys.argv) > 1 else ART
    sys.path.insert(0, os.path.abspath(mod_dir))
    try:
        import ui_theme
    except ImportError as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n"
              "  no ui_theme.py importable from %s: %s" % (mod_dir, why))
        return 2
    trim = getattr(ui_theme, "PLATE_TRIM", None)
    print("  module under test: %s" % os.path.relpath(ui_theme.__file__, os.path.dirname(ART)))
    print("  it says its statistic is: %s" % getattr(ui_theme, "PLATE_SOURCE", "(unstated)"))

    tmp = os.path.join(os.environ.get("TMPDIR", "/tmp"), "assay-plate-statistic")
    os.makedirs(tmp, exist_ok=True)

    cases = []

    # ---- 1. A MAJORITY SPIKE MUST NOT CAPTURE THE PLATE.
    # 55% of the sheet on level 120 and 45% on level 160. A median is 120 EXACTLY and stays
    # 120 however far the other 45% moves, which is the ASSA-261 defect in miniature. Any
    # statistic that reports the ground's colour has to land between the two masses.
    rows = sheet_from_counts([(120, 0.55), (160, 0.45)])
    vals = values(rows)
    cases.append((
        "1. a majority spike does not capture the plate",
        rows, "120 on 55% of the sheet, 160 on 45%",
        "between the two masses, not pinned to 120",
        lambda got: got > 130.0,
        "a median gives 120.0; the true mean is %.1f" % (sum(vals) / len(vals))))

    # ---- 2. THE VALUE IS ROUNDED, NOT TRUNCATED.
    # Two adjacent levels in a ratio chosen so the trimmed mean lands at k + 0.81: round()
    # gives k+1, int() gives k. Half a level per channel on every build, forever, and it
    # would have shipped inside the change that exists because the plate drifted dark.
    rows = sheet_from_counts([(100, 0.25), (101, 0.75)])
    vals = values(rows)
    want_raw = trimmed(vals, trim) if trim is not None else sum(vals) / len(vals)
    cases.append((
        "2. the value is rounded, not truncated",
        rows, "100 on 25% of the sheet, 101 on 75%",
        "%d (the raw statistic is %.4f)" % (round(want_raw), want_raw),
        lambda got, w=want_raw: got == float(round(w)),
        "int() would give %d" % int(want_raw)))

    # ---- 3. A SMALL ONE-SIDED TAIL MUST BE RESISTED.
    # A body of 97% spread evenly 130..150 (mean 140) plus 3% of pixels at 50. The body's
    # answer is 140 by construction; a bare mean is dragged to 137.3. This is the property
    # `ui_theme.py`'s original docstring was right about, and the reason Maren's call was
    # "trimmed, not bare" rather than just "not a median".
    body = [(lvl, 0.97 / 21.0) for lvl in range(130, 151)]
    rows = sheet_from_counts(body + [(50, 0.03)])
    vals = values(rows)
    cases.append((
        "3. a small one-sided tail is resisted",
        rows, "97% spread 130..150 (mean 140), 3% at 50",
        "within 1.0 of 140",
        lambda got: abs(got - 140.0) <= 1.0,
        "a bare mean gives %.2f" % (sum(vals) / len(vals))))

    print()
    print("  %-46s %10s %10s  %s" % ("property", "expected", "got", ""))
    bad = []
    for name, rows, inp, want, ok, alt in cases:
        d = os.path.join(tmp, name.split(".")[0])
        os.makedirs(d, exist_ok=True)
        write_png(os.path.join(d, "ground.png"), rows)
        try:
            rgb = ui_theme.plate_rgb(d)
        except (OSError, SystemExit) as why:
            print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n"
                  "  %s: plate_rgb refused the synthetic sheet: %s" % (name, why))
            return 2
        if len(set(rgb)) != 1:
            print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n"
                  "  %s: a grey sheet came back as %s, so the channels are not independent\n"
                  "  and this check's single-number expectations do not apply." % (name, rgb))
            return 2
        got = float(rgb[0])
        passed = ok(got)
        print("  %-46s %10s %10.1f  %s" % (name, want, got, "" if passed else "<-- FAIL"))
        print("  %-46s   in: %s" % ("", inp))
        print("  %-46s   %s" % ("", alt))
        if not passed:
            bad.append("%s: wanted %s, got %.1f. %s" % (name, want, got, alt))

    if bad:
        print("\nVERDICT: FAIL (exit 1)")
        for line in bad:
            print("  - %s" % line)
        print("\n  All three have to hold at once, and that is what rules out the wrong answers\n"
              "  together: a median fails 1, a bare mean fails 3, and a TRUNCATED mean fails 2.\n"
              "  (int() on a median passes 2, correctly -- a median of integers is an integer,\n"
              "  which is why truncation cost nothing until the statistic stopped being one.)\n"
              "  The band satisfying all three on the real sheets is a 5-15% trim: ASSA-261,\n"
              "  shared/assay/cove-assa261/.")
        return 1

    print("\nVERDICT: PASS (exit 0). The plate's derivation is not captured by a majority\n"
          "  spike, does not truncate, and resists a small one-sided tail.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
