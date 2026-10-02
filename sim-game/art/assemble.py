#!/usr/bin/env -S uv run --quiet --with pillow python
"""Assemble the demo's machines out of part sprites and judge them at 1x.

    art/assemble.py

Writes assets/sprites/assembled.png: every machine the minimal demo defines,
built the way the client must build it, at the size the player sees.

WHY THIS EXISTS
  rig.py rule 2 says a machine is drawn by stacking whole part sprites at the
  same frame position, never by rendering a per-machine sprite. Every other
  decision in the part set follows from it - one frame size, one join height,
  one anchor, parts meeting at the origin. It was a COMMENT. A comment is not
  a check: twice this week I have written down what a thing does and then
  cited my own sentence as evidence that it did it. So this composites the
  real packed sheets and reports numbers.

WHAT IT CHECKS
  1. A pick (head + handle) and a drill (head + planted frame) both assemble
     from one path, differing only by which frame part goes in. Demo point 6.
  2. Hoppers are COUNTABLE. The demo says a second hopper raises capacity
     with no new recipe (point 5) and that hoppers raise the drill's buffer
     (point 9), so a player has to be able to see that a drill has two. Two
     sprites stacked at one position would make hopper #2 invisible, and no
     amount of sim correctness fixes a machine you cannot read.
  3. The grade ladder survives assembly: a C machine and an A machine still
     differ once the parts are overlaid and shrunk to 1x.
  4. YOU CAN SEE WHERE ONE PART ENDS AND THE NEXT BEGINS. Footprint growth
     (check 2) only sees the SILHOUETTE, so it is blind to two parts that
     touch and share a value: the machine is the right shape and still reads
     as one lump. That is what happened at grade A once the glint began to
     blow out neutral (ASSA-28) - a white deck under a steel hopper, 13.3 dE
     apart at 1x where C was 36.9 and B 55.1, and you could not count the
     hoppers that check 2 had just proved were there.
  5. The hopper is still an OPEN BOX, which is the one thing its silhouette
     owes the player. Fixing 4 means darkening the hopper, and far enough
     down the body falls into its own shadowed well and the hole closes.
  Each is printed as a measurement, and the sheet is there to look at.

The draw order is frame, then hopper(s), then head: the frame is the body and
the thing behind, the head is the working end and must never be occluded, and
hoppers ride on the frame between the two.

STATUS: GREEN. It exited nonzero for two days because a second hopper was
invisible, which was an open design question for the Director rather than a
bug in a sprite I should quietly paint around. Maren ruled the offset rule
(Decision #36 follow-up, ASSA-22) and it is implemented in `assemble()` and
documented in art/part_layout.py, so the check now passes BECAUSE THE ART
CHANGED - the second hopper adds 109 px of new shape against the first's 118.
It was never loosened. CI still never runs the art scripts (they need Blender
and Pillow), so a red check here breaks no build either way.
"""
import json
import os
import re
import sys
from statistics import median

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from part_layout import PART_REPEAT_OFFSET
from species_probe import DISTINCT, GRADE_ROWS, dE, lab

# RED LEVER. ASSA-16's lesson was a check that passed on the exact defect it
# existed to find, so this one has a way to be seen failing: PART_OFFSET=0,0
# puts every repeat back on top of the first, which is the bug this rule was
# written to fix and must report FAIL.
if os.environ.get("PART_OFFSET"):
    PART_REPEAT_OFFSET = tuple(int(v) for v in os.environ["PART_OFFSET"].split(","))
    print("[RED RUN] PART_REPEAT_OFFSET forced to %s; the hopper checks MUST fail"
          % (PART_REPEAT_OFFSET,))

# RED LEVERS FOR CHECKS 4 AND 5, one each, because a guard with no way to be
# seen failing stops guarding silently. Both act on the loaded hopper sheet
# rather than on hopper.py, so they run without Blender - but each reproduces
# the CAUSE and not just the symptom:
#   HOPPER_LIGHT=1  puts the hopper back at the deck's value, which is the
#                   ASSA-28 defect; the PART SEAM check MUST fail at grade A.
#   HOPPER_DARK=1   drives the body down into its own well, which is the way
#                   fixing that breaks the part; the OPEN BOX check MUST fail.
HOPPER_LIGHT = os.environ.get("HOPPER_LIGHT")
HOPPER_DARK = os.environ.get("HOPPER_DARK")
if HOPPER_LIGHT:
    print("[RED RUN] hopper lightened toward the deck; the part-seam check MUST fail at A")
if HOPPER_DARK:
    print("[RED RUN] hopper darkened into its own well; the open-box check MUST fail")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPR = os.path.join(ROOT, "assets", "sprites")
TILE = 64                       # authoring size; the game shows 32 at 1x
GAME = 32

man = json.load(open(os.path.join(SPR, "manifest.json")))
sheets = {}


def frame_of(asset, row, f=0):
    """One frame of a packed sheet, by row NAME - never by index. A row order
    is a packing detail; a name is a promise."""
    if asset not in sheets:
        sheets[asset] = Image.open(os.path.join(SPR, man[asset]["sheet"])).convert("RGBA")
    m = man[asset]
    fw, fh = m["frame_px"]
    names = [r["name"] for r in m["rows"]]
    if row not in names:
        raise SystemExit("%s has no row %r (has %s)" % (asset, row, names))
    y = names.index(row)
    im = sheets[asset].crop((f * fw, y * fh, (f + 1) * fw, (y + 1) * fh))
    if asset == "hopper" and (HOPPER_LIGHT or HOPPER_DARK):
        im = im.copy()
        px = im.load()
        for yy in range(im.height):
            for xx in range(im.width):
                r, g, b, a = px[xx, yy]
                if not a:
                    continue
                px[xx, yy] = ((r + (255 - r) // 2, g + (255 - g) // 2, b + (255 - b) // 2, a)
                              if HOPPER_LIGHT else
                              (r * 35 // 100, g * 35 // 100, b * 35 // 100, a))
    return im


def assemble(parts, grade, owners=False):
    """Stack whole part frames at one position. This is rule 2, executed -
    plus rule 5, the offset rule, for parts that repeat.

    Every part must agree on frame size and anchor or the stack is meaningless,
    so that is asserted here rather than assumed: it is the invariant the whole
    part set is built on and the cheapest possible place to catch it breaking.

    `parts` arrives in Assembly::parts() order - frame first, then the mounted
    parts. Sim calls that "the one canonical order" and every rule that has to
    pick a part walks it, so taking repeat positions from this sequence is what
    stops two peers drawing the same machine differently.
    """
    sizes = {tuple(man[p]["frame_px"]) for p in parts}
    anchors = {tuple(man[p]["anchor_px"]) for p in parts}
    if len(sizes) != 1 or len(anchors) != 1:
        raise SystemExit(
            "parts %s do not share one frame rectangle (sizes %s, anchors %s) -\n"
            "    they cannot be overlaid, which breaks rig.py rule 2."
            % (list(parts), sizes, anchors))
    w, h = sizes.pop()
    out = Image.new("RGBA", (w, h))
    # Which part owns each pixel, by index into `parts`, -1 for none. Kept here
    # rather than recomputed by check 4 so that the thing being measured is
    # the thing the machine is actually made of: one composite, one draw order.
    own = [[-1] * w for _ in range(h)]
    seen = {}
    for i, p in enumerate(parts):
        n = seen.get(p, 0)
        seen[p] = n + 1
        layer = Image.new("RGBA", (w, h))
        layer.alpha_composite(frame_of(p, grade))
        if n:
            # Rule 5: the nth repeat steps by n * PART_REPEAT_OFFSET. Done with
            # a transform rather than a composite offset because the step goes
            # UP, and alpha_composite cannot take a negative destination.
            dx, dy = PART_REPEAT_OFFSET[0] * n, PART_REPEAT_OFFSET[1] * n
            layer = layer.transform((w, h), Image.AFFINE, (1, 0, -dx, 0, 1, -dy))
        lp = layer.load()
        for y in range(h):
            for x in range(w):
                if lp[x, y][3] > 128:
                    own[y][x] = i
        out.alpha_composite(layer)
    return (out, own) if owners else out


def at_1x(img):
    """The game draws a 2x1-tile part at 32px per tile. Judge there."""
    k = GAME / float(TILE)
    return img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)


def _coverage(own, want, w, h, size):
    """One part's pixels as COVERAGE at 1x: an area average, not a sample.

    The masks have to come down from authoring size the same way the picture
    does, or the boundary I measure is not the boundary the player sees. BOX
    is area-averaging, so a 1x pixel that is half deck and half hopper reports
    0.5 and gets thrown away below - which is the point. The colours either
    side of an edge are only meaningful where a pixel is one part or the
    other; the blended pixels ON the edge are the thing being judged, not an
    input to the judgement."""
    m = Image.new("L", (w, h))
    mp = m.load()
    for y in range(h):
        for x in range(w):
            if own[y][x] in want:
                mp[x, y] = 255
    return m.resize(size, Image.BOX)


def boundary(parts, grade, a, b):
    """How far apart two parts look where they MEET, at 1x.

    Returns (median dE76, median |dL*|, pairs) over every pure-`b` pixel that
    has a pure-`a` pixel within three, each paired with its nearest.

    WHY A MEDIAN OF PAIRS AND NOT TWO MEANS. A part's mean is a colour that
    appears nowhere on it - frame/A is a bright deck around a gun-metal plate,
    and its average is neither. Worse, a mean washes out exactly the case this
    check exists for: an edge is a local thing, and two parts can average far
    apart while the places they actually touch are one value. So this walks
    the seam and asks the question at each point on it.

    BOTH CURRENCIES ARE REPORTED ON PURPOSE. dE76 counts hue, chroma and
    lightness together; dL* is the lightness step alone. They disagree here in
    a way worth seeing: a C deck parts from the hopper mostly by HUE (brown
    against grey-blue), an A deck almost entirely by LIGHTNESS, because the
    glint blew the deck out to neutral and a neutral has no hue to differ by.
    Gated on dE76 - ruling 17 and measure D say L* counts between a machine
    and what it sits on, and this is one machine's own parts - but a pairing
    that holds in one currency and collapses in the other is a thing to look
    at rather than to pass."""
    img, own = assemble(parts, grade, owners=True)
    w, h = img.size
    small = at_1x(img)
    sw, sh = small.size
    ai = {i for i, p in enumerate(parts) if p == a}
    bi = {i for i, p in enumerate(parts) if p == b}
    ma = _coverage(own, ai, w, h, (sw, sh)).load()
    mb = _coverage(own, bi, w, h, (sw, sh)).load()
    sp = small.convert("RGBA").load()
    des, dls = [], []
    for y in range(sh):
        for x in range(sw):
            if mb[x, y] < 230:
                continue
            best = None
            for dy in range(-3, 4):
                for dx in range(-3, 4):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < sw and 0 <= ny < sh and ma[nx, ny] >= 230:
                        d = dx * dx + dy * dy
                        if best is None or d < best[0]:
                            best = (d, nx, ny)
            if best:
                c1, c2 = sp[x, y][:3], sp[best[1], best[2]][:3]
                des.append(dE(c1, c2))
                dls.append(abs(lab(c1)[0] - lab(c2)[0]))
    if not des:
        return None
    return median(des), median(dls), len(des)


def open_read(grade):
    """Is the hopper still a box with a hole in it? Two numbers at 1x.

    `dark` is the share of the part that sits under L* 35 - the shadowed well
    and the ink round it. `spread` is the lightest tenth's median L* minus the
    darkest tenth's: the rim against the well.

    The pair is deliberate, because either one alone can be held up by the
    wrong thing. A specular highlight that survives any amount of darkening
    keeps `spread` looking healthy while the body sinks; `dark` cannot be
    fooled that way, because a body that falls under the threshold is counted
    whatever the highlights do. And `dark` alone would be happy with a flat
    pale slab that has no well at all, which `spread` catches."""
    im = at_1x(frame_of("hopper", grade))
    px = im.convert("RGBA").load()
    ls = [lab(px[x, y][:3])[0] for y in range(im.height) for x in range(im.width)
          if px[x, y][3] > 200]
    ls.sort()
    k = max(1, len(ls) // 10)
    return (sum(1 for v in ls if v < 35) / float(len(ls)),
            median(ls[-k:]) - median(ls[:k]))


def differs(a, b):
    """Opaque-pixel difference between two 1x renders: how many pixels changed
    and by how much at the worst. 'They look different' is not a measurement."""
    pa, pb = a.convert("RGBA").load(), b.convert("RGBA").load()
    n, worst = 0, 0
    for y in range(a.height):
        for x in range(a.width):
            ca, cb = pa[x, y], pb[x, y]
            d = max(abs(ca[i] - cb[i]) for i in range(4))
            if d > 8:
                n += 1
                worst = max(worst, d)
    return n, worst


def max_hopper_slots():
    """Read from sim rather than retyped, same reason ore.py reads the grade
    boundaries: a copy of a sim number in the art is a drift waiting to
    happen, and a wrong one here would have the check judge a machine no
    player can build."""
    src = open(os.path.join(ROOT, "sim", "src", "tuning.rs")).read()
    m = re.search(r"pub const MAX_HOPPER_SLOTS: u32 = (\d+);", src)
    if not m:
        raise SystemExit("assemble.py: could not read MAX_HOPPER_SLOTS from sim/src/tuning.rs")
    return int(m.group(1))


def clipped_pixels(part, n):
    """Solid pixels of the nth repeat that fall outside the frame rectangle.

    A repeat that runs off the frame stops adding shape, so the footprint test
    would start passing for the wrong reason. This is the bound that rejected
    the offset which scored best on two hoppers."""
    img = frame_of(part, "A")
    w, h = img.size
    px = img.load()
    dx, dy = PART_REPEAT_OFFSET[0] * n, PART_REPEAT_OFFSET[1] * n
    return sum(1 for y in range(h) for x in range(w)
               if px[x, y][3] > 128 and not (0 <= x + dx < w and 0 <= y + dy < h))


def footprint(img):
    """Count of solid pixels. Stacking a sprite on itself cannot grow this, so
    it is the measure that cannot be fooled by alpha."""
    px = img.convert("RGBA").load()
    return sum(1 for y in range(img.height) for x in range(img.width)
               if px[x, y][3] > 128)


# The machines the minimal demo defines (2026-10-01-minimal-demo-loop.md).
# A pick is a head on a HANDLE, which is the held frame; a drill is a head on
# a planted FRAME with optional hoppers. One assembly path, different parts.
MACHINES = [
    ("pick",          ("handle", "head")),
    ("drill",         ("frame", "head")),
    ("drill+hopper",  ("frame", "hopper", "head")),
    ("drill+2hopper", ("frame", "hopper", "hopper", "head")),
]


def main():
    shots = []
    for name, parts in MACHINES:
        for g in ("C", "A"):
            shots.append((("%s %s" % (name, g)), assemble(parts, g)))

    ok = True

    # 1. CAN YOU COUNT THE HOPPERS?
    #
    # The naive test - "do any pixels differ between one hopper and two" -
    # passes, and it is worthless. I ran it and it reported 486 differing
    # pixels with a worst channel of 254, which sounds decisive. Compositing a
    # sprite ONTO ITSELF cannot add anything to the picture; what it does is
    # push the part-transparent pixels of an antialiased edge and an outline
    # further toward opaque. So the number was real, the pixels did change, and
    # the answer to the question I actually had was still no. My own pixel
    # scripts lie to me in exactly this way, so this measures two things that
    # cannot be fooled:
    #   - the SOLID FOOTPRINT, which stacking a sprite on itself cannot grow;
    #   - adding the second hopper against the CONTROL of adding the first.
    # If the first hopper changes the machine a lot and the second changes it
    # by an edge-alpha rounding error, the machine is not countable.
    # Judged at MAX_HOPPER_SLOTS, not at the two the demo happens to use: the
    # rule has to hold for a machine a player can actually build, and the
    # offset that scored best on two hoppers lost 122 px of the fourth off the
    # top of the frame. Read from sim so it tracks the slot count.
    slots = max_hopper_slots()
    full = [at_1x(assemble(("frame",) + ("hopper",) * n + ("head",), "A"))
            for n in range(slots + 1)]
    foots = [footprint(im) for im in full]
    growth = [foots[i + 1] - foots[i] for i in range(slots)]
    print("hopper count at 1x, all %d slots: footprint %s"
          % (slots, " -> ".join(str(f) for f in foots)))
    print("                    new shape per hopper: %s px"
          % ", ".join("+%d" % g for g in growth))
    if min(growth[1:]) < growth[0] * 0.25:
        ok = False
        print("  FAIL: a repeat hopper adds only %d px against the first's %d."
              % (min(growth[1:]), growth[0]))
    # And nothing may fall off the frame rectangle, which is what makes a
    # repeat silently stop counting at the far end.
    lost = clipped_pixels("hopper", slots - 1)
    print("                    pixels of hopper #%d lost off the frame: %d" % (slots, lost))
    if lost:
        ok = False
        print("  FAIL: hopper #%d is clipped by the frame rectangle. Cap the\n"
              "  visible count and put the number in UI rather than shrinking\n"
              "  the offset until repeats are invisible again." % slots)

    zero = at_1x(assemble(("frame", "head"), "A"))
    one = at_1x(assemble(("frame", "hopper", "head"), "A"))
    two = at_1x(assemble(("frame", "hopper", "hopper", "head"), "A"))
    f0, f1, f2 = footprint(zero), footprint(one), footprint(two)
    g1, g2 = f1 - f0, f2 - f1
    d01, _ = differs(zero, one)
    d12, _ = differs(one, two)
    print("hopper count at 1x: footprint %d -> %d -> %d px for 0 -> 1 -> 2 hoppers" % (f0, f1, f2))
    print("                    new shape: +%d px for the 1st hopper, +%d px for the 2nd (%.0f%%)"
          % (g1, g2, 100.0 * g2 / g1 if g1 else 0))
    print("                    pixels touched: %d for the 1st, %d for the 2nd" % (d01, d12))
    # The verdict is FOOTPRINT GROWTH, not pixels touched. Pixels touched says
    # 486 for the second hopper, which looks like a lot until you notice a
    # sprite composited onto itself touches every antialiased pixel it owns.
    if g2 < g1 * 0.25:
        ok = False
        print("  FAIL: THE SECOND HOPPER IS INVISIBLE. The first hopper adds %d px\n"
              "  of new shape; the second adds %d. That is edge alpha hardening,\n"
              "  not a part. The demo says a second hopper raises the buffer with\n"
              "  no new recipe (point 5) and that hoppers raise the cap (point 9),\n"
              "  so a player has to be able to SEE two. Stacking identical frames\n"
              "  at one position cannot express a COUNT. This wants a design\n"
              "  answer - offset each repeated part along the frame, or cap the\n"
              "  visible hoppers and put the number in UI - not a sprite tweak."
              % (g1, g2))

    # 2. Does the grade ladder survive assembly?
    for name, parts in MACHINES:
        n, worst = differs(at_1x(assemble(parts, "C")), at_1x(assemble(parts, "A")))
        print("grade C vs A on %-14s %4d px differ (worst channel %d)" % (name + ":", n, worst))
        if n == 0:
            ok = False
            print("  FAIL: %s renders identically at C and A." % name)

    # 3. WHERE DOES THE HOPPER END AND THE DECK BEGIN? (ASSA-28)
    #
    # THE BAR IS RELATIVE AND IT IS NOT DISTINCT. Maren, ruling on ASSA-28:
    # "I am not setting another absolute floor on this palette - three of mine
    # have now failed on it, and each time the bound was the fault." So the
    # gate is that NO GRADE IS THE ODD ONE OUT: a grade's seam may not read at
    # less than HALF the strongest grade's on the same machine. Measured on
    # main @2a57a20 the drill's deck-to-hopper seam ran C 36.9, B 55.1, A 13.3
    # at two hoppers, so grade A fails this by 14 and that is the defect.
    #
    # HALF IS A CHOSEN PROPORTION AND I WILL NOT PRETEND OTHERWISE. My first
    # try was "within a JND of the others", which is stricter and wrong: the
    # three grades of a working machine measure 38/54/41 and a rule that calls
    # that a defect is a rule that cries wolf on the art it was written to
    # protect. Half is the same shape as the quarter one check up - the bar is
    # a RATIO against a sibling, because what makes a seam readable is that it
    # is about as readable as the seams beside it, and the defect this has to
    # catch was a QUARTER of its siblings.
    #
    # DISTINCT alone would have let it through. 13.3 clears 12, which is the
    # floor every other check in this pipeline leans on - a sprite can satisfy
    # every absolute bound in the art and still be a machine you cannot read,
    # because what makes a seam visible is that it is as visible as the seams
    # beside it. The absolute floor is kept as a second, weaker gate, and the
    # head-to-hopper pairing is measured too: darkening the hopper to part it
    # from a white deck walks it toward the head, which is grey, and a fix
    # that moves a collision somewhere else is not a fix. At #5F666F it did
    # exactly that, 10.7 dE, which is how this pairing earned its line here.
    slots_tested = range(1, max_hopper_slots())
    print("part seams at 1x, median dE76 / median dL* across the join:")
    for a, b in (("frame", "hopper"), ("head", "hopper")):
        for n in slots_tested:
            parts = ("frame",) + ("hopper",) * n + ("head",)
            got = {g: boundary(parts, g, a, b) for g in ("C", "B", "A")}
            got = {g: v for g, v in got.items() if v}
            if not got:
                continue
            print("  %s|%-7s %d hopper(s): %s" % (
                a, b, n, "  ".join("%s %5.1f/%4.1f" % (g, got[g][0], got[g][1])
                                   for g in ("C", "B", "A") if g in got)))
            best = max(v[0] for v in got.values())
            for g, (de, _dl, _n) in got.items():
                if de < best / 2:
                    ok = False
                    print("  FAIL: at grade %s the %s/%s seam is %.1f dE against %.1f at the\n"
                          "  machine's best grade. One grade of the same machine reads as\n"
                          "  one part while the rest read as two."
                          % (g, a, b, de, best))
                if de < DISTINCT:
                    ok = False
                    print("  FAIL: the %s/%s seam at grade %s is %.1f dE, under DISTINCT %.0f."
                          % (a, b, g, de, DISTINCT))

    # 4. IS THE HOPPER STILL AN OPEN BOX?
    #
    # The cost side of check 3: the hopper parts from a blown-out deck by
    # going dark, and far enough down its body falls into its own shadowed
    # well and the hole closes. Then the part is a solid, like every other
    # part in the set, and the one silhouette difference it owns is gone.
    #
    # HALF is not a tuned coefficient, it is the sentence: a box whose dark
    # interior is most of it is not a box with a hole in it. Shipped, the well
    # is 14-16% of the part. The control render that killed the grade dulling
    # (grey, still dulled) sits at 34.7% at C, already halfway to the cliff
    # with the body only starting to count; the red lever goes past it.
    print("hopper open read at 1x: share under L*35, and rim-to-well L* spread:")
    for g in GRADE_ROWS:
        dark, spread = open_read(g)
        print("  %s: %4.1f%% dark, spread %4.1f L*" % (g, 100 * dark, spread))
        if dark >= 0.5:
            ok = False
            print("  FAIL: %.0f%% of the hopper is under L*35 at grade %s. The body has\n"
                  "  joined the well and the part has stopped being an open shape."
                  % (100 * dark, g))
        if spread < DISTINCT:
            ok = False
            print("  FAIL: rim-to-well spread is %.1f L* at grade %s, under %.0f: the\n"
                  "  well no longer reads as a hole." % (spread, g, DISTINCT))

    # the sheet: 2x authoring on top so you can see what it is made of, and the
    # true 1x row below, which is the verdict.
    pad = 6
    cw = max(im.width for _, im in shots)
    ch = max(im.height for _, im in shots)
    sheet = Image.new("RGBA", (pad + len(shots) * (cw + pad), ch + pad * 3 + round(ch * GAME / TILE)),
                      (30, 32, 30, 255))
    for i, (_, im) in enumerate(shots):
        sheet.alpha_composite(im, (pad + i * (cw + pad), pad))
        small = at_1x(im)
        sheet.alpha_composite(small, (pad + i * (cw + pad), ch + pad * 2))
    # THE COUNT LADDER, at true 1x, zero hoppers to a full machine. The
    # footprint numbers say the repeats add shape; this is where I check that
    # the shape reads as A COUNT and not as a chunkier hopper. It is the
    # picture that settled it - the per-column view above is too thin to
    # judge, and I nearly talked myself out of a working rule by squinting at
    # it instead of putting zero-to-full side by side.
    lz = 4
    lw, lh = full[0].size
    ladder = Image.new("RGBA", (pad + len(full) * (lw * lz + pad), lh * lz + pad * 2),
                       (24, 26, 24, 255))
    for i, im in enumerate(full):
        ladder.alpha_composite(im.resize((lw * lz, lh * lz), Image.NEAREST),
                               (pad + i * (lw * lz + pad), pad))
    stacked = Image.new("RGBA", (max(sheet.width, ladder.width),
                                 sheet.height + ladder.height + pad), (30, 32, 30, 255))
    stacked.alpha_composite(sheet, (0, 0))
    stacked.alpha_composite(ladder, (0, sheet.height + pad))
    sheet = stacked
    sheet.save(os.path.join(SPR, "assembled.png"))
    print("wrote assets/sprites/assembled.png  (%d machines, top row authoring size, bottom row true 1x)"
          % len(shots))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
