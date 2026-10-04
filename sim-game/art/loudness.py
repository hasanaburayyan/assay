#!/usr/bin/env -S uv run --quiet --with pillow python
"""Ore owns saturation. Does it, though?

    art/loudness.py

Maren's ruling 3 on ASSA-20, in full: "ore is the only fully saturated thing
in Assay; ground, buildings, items and UI chrome all stay under it -- ore's
loudness is measured-mandatory, so anything else going loud competes with the
one surface that cannot afford to lose."

WHY IT NEEDS A CHECK AT ALL
  That ruling arrived as prose in a work-item comment, which is the same
  shape as the rule that preceded it: rig.py said for days that a machine is
  drawn by stacking whole part sprites, and when ASSA-16 finally composited
  two hoppers the second one was invisible. A comment is not a check. The
  species table is also the newest thing in the art -- it was fixed yesterday
  -- so nothing in the pipeline has ever compared it against the sprites that
  were drawn before it existed.

WHY ORE CANNOT AFFORD TO LOSE, in one line: species identity is carried by
  TINT ALONE (Decision #36), and the tint is a multiply. Every other axis the
  art could have spent on species -- shape, outline, pattern -- is already
  spent. So a loud machine does not cost ore a little legibility; it competes
  with the only channel ore has.

TWO MEASURES, AND NEITHER THRESHOLD IS INVENTED HERE
  A. THE BUDGET. Mean C*ab over a surface's opaque pixels, against the
     QUIETEST shipped species x grade ore surface. Not the average species:
     the shipped table spans 33.8 to 110.3, so an average would let a machine
     out-shout two real species and still pass. The floor is the quietest ore
     a player will ever actually see on the map.
  B. THE CONFUSION, AT THE WHOLE SURFACE. dE76 from a non-ore surface's mean
     to the nearest tinted ore surface, against DISTINCT = 12 -- the number
     species_probe.py already uses for "two things a player must never
     confuse at a glance", imported rather than retyped. Loudness is not the
     only failure: a machine that reads AS a deposit is worse than one that
     merely shouts.
  C. THE CONFUSION, AT THE MARK. The same dE, but on the mean of each
     surface's most saturated TENTH -- the pixels that actually carry its
     colour -- against the same tenth of each ore surface.

  D. THE SAME CONFUSION WITH L* DROPPED, through four observers. REPORTED,
     NEVER A GATE, and the reason it is not a gate is the whole of what D is
     for. Maren measured flat #F08A24 against the six tints on hue and
     chroma alone and found it 0.5 to 10.0 from species1 red -- under
     DISTINCT -- while this file's measure C put the same orange 46 to 53
     clear. Both numbers are right. The difference is not flat swatches
     versus rendered pixels (D reproduces their result on the rendered
     sprites: 0.3 to 6.5, worst observer); it is whether LIGHTNESS COUNTS.

     IT COUNTS HERE AND IT DOES NOT COUNT BETWEEN TWO SPECIES. `dAB` exists
     because species may not be told apart by brightness -- GRADE already
     spends brightness, so two species separated only by L* are one species
     at two purities. A MACHINE is not a grade of ore. Nothing is using
     lightness to mean something else between a drill and a deposit, so
     lightness is a channel they are entitled to be told apart by, and dE76
     is the honest measure of that pair.

     D'S PAIR IS NOT C'S PAIR, and the first version of this comment got
     that wrong by subtracting one column from the other. C's nearest
     deposit to frame/C is species1 at grade C, 51.4 away and mostly in hue
     (dAB 50.7, dL* 8.3). D's nearest is species1 at grade A through a
     protan eye, where the two are the SAME hue and chroma (dAB 0.3) and
     10.4 of L* apart. Both are true of the same sprite. What D adds is:
     for a colour-blind player the machine orange has no hue advantage over
     a deposit left at all, and lightness is carrying the whole read.

     WHY IT IS STILL NOT A GATE. Turning D into one means a rule about what
     VALUE a machine may take, and nobody has written that rule. Worse, the
     obvious upgrade -- re-running measure C's dE76 THROUGH the observer --
     is not sound as the mark is defined: the mark is the most saturated
     TENTH, and a CVD transform collapses chroma, so after it the ordering
     that picks those pixels is noise. Run that way, hopper/B (a grey part
     with a hidden band, mean C 8.1) scores 5.0 against species2's pink,
     which is an answer about the method and not about the art. A sound
     version needs a mark defined by something the transform does not
     destroy. Recorded so it is not re-derived; see ASSA-27.

     C EXISTS BECAUSE B LIED. B passes every row today with 15 dE to spare,
     and I nearly shipped it alone. Checked instead of trusted: frame/A is a
     dark deck inside a bright rim, so its MEAN sits 35.7 from the nearest
     ore while its twenty brightest pixels are rgb(255,254,89) -- 10.9 from
     species3's grade-C ore, under the floor. (35.7 and 10.9 are the numbers
     this file prints; my scratch pass said 51.3 because it compared a mean
     against a decile. Measuring the measurement needs the same care as
     measuring the art.) The average of a two-tone
     sprite is a colour that appears nowhere on it. This is the fourth time a
     measurement of mine has been the thing deceiving me rather than my
     intuition, and the only reason it got caught is that I went looking for
     it after the check came back clean.

WHY MEAN AND NOT PEAK. A surface is what it mostly is. The grade glint is a
  deliberate near-white specular accent and it puts max C*ab at 80 on a part
  whose body is grey; scoring peaks would condemn the glint rule and tell you
  nothing about the surface. Median and max are printed beside the mean so a
  mark can be told from a repaint -- head/A reads 10.7 mean against 8.3
  median (grey body, warm mark) where frame/A reads 41.5 against 38.0 (the
  chassis itself is the mark, which frame.py says in writing).

WHY ROCK PIXELS AND NOT THE COMPOSITE for ore. An ore tile is a transparent
  overlay, so the tile a player sees is part rock and part terrain, and a
  sparse grade-C tile would score the GROUND's chroma rather than the ore's.
  The ore surface is the rock. The terrain is in the budget separately, on
  its own row, which is the honest way to ask whether the ground is loud.

EXEMPTIONS ARE WRITTEN DOWN OR THEY DO NOT EXIST. `EXEMPT` below carries a
reason and the name of whoever ruled it. Nothing is exempt by being omitted
from a list, because that is how build.py's colour-blind block went on
drawing four empty strips after the row it grepped for was renamed.

RED LEVERS, ONE PER MEASURE, because a lever that only exercises measure A
leaves B as prose with a number next to it:
  LOUDNESS_MUTE=0       pulls every non-ore surface to its own grey. Measure
                        A is RED on the art as it ships, so the run that
                        proves A is a check is the one where it goes GREEN.
  LOUDNESS_FAKE_ORE=n   replaces every non-ore surface with species n's own
                        tinted ore rock. B is GREEN on the art as it ships
                        (nothing reads as a deposit, worst row clears by 15),
                        so this is the run that proves B can fail: every row
                        is then literally ore and every row MUST be reported
                        as reading like it.
  LOUDNESS_NO_EXEMPT=1  drops every exemption. The run MUST then go red on
                        player/*, which is what proves those rows are passing
                        BECAUSE a Director ruled on them and not because the
                        numbers quietly changed under the exemption. An
                        exemption is the one mechanism here that can swallow a
                        real failure, so it gets a lever like the measures do.
Any mute value in 0..1 works (1.0 = untouched).

STATUS: GREEN, and it got there by being believed when it was red.
  Measure C was written because B lied, and the first thing C found on real
  art was frame/A's twenty brightest pixels sitting at rgb(255,254,89), dE
  10.9 from species3's ore -- a hue nobody chose, produced by an emissive
  ORANGE clipping R and G at the ceiling and leaving B behind. Decision #37
  fixed the cause rather than the row: the grade-A glint now emits NEUTRAL
  (rig.graded_accent), so the blowout clips to white and no species tint is
  neutral. The other red, player/*, was ruled out of scope rather than
  painted over, with the reason written into EXEMPT below.
"""
import json
import math
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# Record the shipped art this sheet composites, so the committed PNG can say whether it is
# still current (ASSA-144). BEFORE the `species_probe` import, not merely before the first
# read in this file: that module loads `manifest.json` at ITS module level, and importing it
# is already a read of shipped art this sheet's numbers depend on.
import review_sources
review_sources.start()
import review_layout  # noqa: E402  this sheet's declaration that it draws no layout
# NOT A PICTURE OF A CLIENT PANEL, SAID OUT LOUD (CO-6). `check_review_layout.py`
# used to print `NO LAYOUT` here and pass, so this sheet and a panel sheet that had
# FORGOTTEN its stamp were the same state -- and two sheets really were the second
# thing. The claim is the sheet's own, so a copy of it carries the reason with it.
ART_ONLY = review_layout.art_only(
    "a picture of the shipped sprites measured against each other; every number in it comes from the sheets, not from anything the client lays out")
from species_tints import SPECIES_TINTS
from species_probe import DISTINCT, GRADE_ROWS, GAME, dE, dAB, lab, seen_flat

OBSERVERS = ("normal", "protan", "deutan", "tritan")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The sheets live inside the Godot project: res:// does not go up (ASSA-34).
SPR = os.path.join(ROOT, "client", "assets", "sprites")
# Review output stays out of the project, so an export never packs it.
REVIEW = os.path.join(ROOT, "assets", "review")
os.makedirs(REVIEW, exist_ok=True)
man = json.load(open(os.path.join(SPR, "manifest.json")))

# A surface is exempt only with a reason and a name on it.
#
# KEYED BY ASSET, NOT BY ROW, and the keys are checked against the manifest
# below. Sixteen row names spelled out here would be sixteen chances to go
# quietly stale, which is exactly how build.py's colour-blind block went on
# drawing four empty strips after the row it grepped for was renamed.
EXEMPT = {
    "player": ("Maren, Decision #37", """
        THE BUDGET COVERS WHAT THE PLAYER SCANS: ground, machines, ground
        items, UI chrome. The avatar is not in that set. There is one of it
        (three in co-op), it is humanoid rather than a tile, and it moves
        when you press a key -- you never search a field for it, so it is
        not competing with ore for the attention ore's budget is protecting.
        Self-location is its own claim on loudness.

        THE EXEMPTION ATTACHES TO THIS SURFACE AND NEVER TO A PALETTE ENTRY.
        rig.py has `suit` and `orange` as two names for one hex (#F08A24).
        They stay independent forever: if `orange` has to move, `suit` does
        not follow, and a MACHINE may never claim the player's exemption on
        the grounds that it wears the player's colour. The exemption is
        about what the thing is, not about what colour it happens to be."""),
}


NO_EXEMPT = os.environ.get("LOUDNESS_NO_EXEMPT")


def exempt(name):
    """`asset/row` -> the exemption on its asset, or None."""
    if NO_EXEMPT:
        return None
    return EXEMPT.get(name.split("/")[0])


_missing = [a for a in EXEMPT if a not in man]
if _missing:
    sys.exit("loudness.py: EXEMPT names an asset that is not in the manifest: "
             + ", ".join(_missing) + ".\nAn exemption that matches nothing is a"
             " surface going unchecked in silence. Fix the name or delete it.")


def frame_of(asset, row, f=0):
    m = man[asset]
    fw, fh = m["frame_px"]
    y = [r["name"] for r in m["rows"]].index(row)
    sheet = Image.open(os.path.join(SPR, m["sheet"])).convert("RGBA")
    return sheet.crop((f * fw, y * fh, (f + 1) * fw, (y + 1) * fh))


def at_1x(img):
    """Judge at the size the player sees. 64 px is authoring; 32 is the game."""
    w, h = img.size
    return img.resize((GAME, max(1, round(h * GAME / w))), Image.LANCZOS)


def tint(img, hexcolour):
    """Godot `modulate`: per-channel multiply, exactly as the client does it."""
    h = hexcolour.lstrip("#")
    cr, cg, cb = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    px = img.load()
    w, hh = img.size
    out = Image.new("RGBA", (w, hh))
    op = out.load()
    for y in range(hh):
        for x in range(w):
            r, g, b, a = px[x, y]
            op[x, y] = (r * cr // 255, g * cg // 255, b * cb // 255, a)
    return out


MUTE = os.environ.get("LOUDNESS_MUTE")
if MUTE is not None:
    MUTE = float(MUTE)
    print("[RED LEVER] non-ore surfaces muted to %.2f of their chroma; at 0 the\n"
          "            BUDGET check MUST pass, which is what proves it measures\n"
          "            chroma and not something that happens to correlate.\n" % MUTE)

FAKE_ORE = os.environ.get("LOUDNESS_FAKE_ORE")
if FAKE_ORE is not None:
    FAKE_ORE = int(FAKE_ORE)
    print("[RED LEVER] every non-ore surface replaced by species %d's own tinted\n"
          "            ore rock. The CONFUSION check MUST then fail on every row:\n"
          "            each one IS that species, at dE 0.\n" % FAKE_ORE)


def mute(img, keep):
    """Pull toward the pixel's own luma, so lightness and shape are untouched."""
    px = img.load()
    w, h = img.size
    out = Image.new("RGBA", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            op[x, y] = (round(lum + (r - lum) * keep),
                        round(lum + (g - lum) * keep),
                        round(lum + (b - lum) * keep), a)
    return out


def opaque(img):
    px = img.load()
    w, h = img.size
    return [px[x, y][:3] for y in range(h) for x in range(w) if px[x, y][3] > 200]


def chroma(rgb):
    _, a, b = lab(rgb)
    return math.hypot(a, b)


def measure(img):
    """mean / median / max chroma, chroma-weighted hue, and the mean colour.

    Hue is weighted by chroma because a grey pixel has no hue to vote with:
    averaging raw angles lets a part's gun-metal body drag the answer toward
    whatever its antialiasing happens to be."""
    px = opaque(img)
    if not px:
        return None
    cs = sorted(chroma(p) for p in px)
    sa = sb = sw = 0.0
    for p in px:
        _, a, b = lab(p)
        c = math.hypot(a, b)
        sa += a * c
        sb += b * c
        sw += c
    mean_c = sum(cs) / len(cs)
    # A grey surface has no hue, and atan2 on two rounding errors prints a
    # confident number for one. Say so instead.
    hue = (math.degrees(math.atan2(sb / sw, sa / sw)) % 360
           if sw and mean_c >= 0.5 else None)
    mean = tuple(sum(p[i] for p in px) / len(px) for i in range(3))
    # THE MARK: the mean of the most saturated tenth. A sprite's average is a
    # colour that may appear nowhere on it; this is the colour it is actually
    # wearing. Same tenth taken from ore, so the comparison is like for like.
    top = sorted(px, key=chroma, reverse=True)[:max(1, len(px) // 10)]
    mark = tuple(sum(p[i] for p in top) / len(top) for i in range(3))
    return {"mean_c": mean_c, "med_c": cs[len(cs) // 2], "max_c": cs[-1],
            "hue": hue, "rgb": mean, "mark": mark, "mark_n": len(top)}


def hue_s(m):
    return "   --" if m["hue"] is None else "%5.1f" % m["hue"]


def sheet(loud, conf, ore_surfaces, floor_name):
    """Write the argument as a picture, on the real ground, at 1x and 3x.

    The numbers above are the case; this is the thing a Director can actually
    rule on. Order is the point: the quietest ore in the game sits FIRST, and
    everything that beat it follows, so "louder than ore" is something you can
    see rather than a column to be trusted."""
    quiet = min(ore_surfaces, key=lambda s: s[1]["mean_c"])[0]
    loudest = max(ore_surfaces, key=lambda s: s[1]["mean_c"])[0]
    panels = []
    for label, which in ((quiet, "quiet"), (loudest, "loud")):
        i = int(label.split()[0][len("species"):])
        g = label.split()[-1]
        panels.append(("ORE " + label.split()[1] + " " + g + " (" + which + "est ore)",
                       at_1x(tint(frame_of("ore", "%s_full_v0" % g), SPECIES_TINTS[i]))))
    seen = set()
    for r in sorted(loud, key=lambda r: -r[2]):
        name, over = r[0], r[2]
        asset = name.split("/")[0]
        if asset in seen:          # one row per asset; eight walk directions
            continue               # of the same suit is not eight findings
        seen.add(asset)
        panels.append(("%s  +%.1f over" % (name, over), at_1x(frame_of(*name.split("/")))))
    for r in sorted(conf, key=lambda r: min(r[3], r[5]))[:4]:
        name = r[0]
        if name in seen:
            continue
        seen.add(name)
        panels.append(("%s  dE %.1f to ore" % (name, min(r[3], r[5])),
                       at_1x(frame_of(*name.split("/")))))

    ground = at_1x(frame_of("ground", "v0")).convert("RGBA")
    cellw, pad, lab_h = 32 + 96 + 12, 10, 12
    out = Image.new("RGBA", (len(panels) * (cellw + pad) + pad,
                             96 + lab_h + 2 * pad), (46, 48, 52, 255))
    x = pad
    for label, img in panels:
        for scale, ox in ((3, 0), (1, 96 + 12)):
            tile = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
            tile.alpha_composite(ground.resize((32, 32), Image.LANCZOS))
            tile.alpha_composite(img.crop((0, max(0, img.size[1] - 32),
                                           32, img.size[1])))
            s = tile.resize((32 * scale, 32 * scale), Image.NEAREST)
            out.alpha_composite(s, (x + ox, pad + (96 - 32 * scale)))
        x += cellw + pad
    out.save(os.path.join(REVIEW, "loudness.png"),
             pnginfo=review_layout.png_info(review_sources.png_info(),
                                            layouts=ART_ONLY))
    print("\nwrote assets/review/loudness.png: the quietest and loudest ore in")
    print("the game, then every surface that beat the quiet one, each on the")
    print("real ground at 3x and at 1x. Judge it at the 1x column.")
    print("  order: %s" % ", ".join(p[0] for p in panels))


def main():
    print("ORE OWNS SATURATION (Maren, ruling 3 on ASSA-20) -- measured.")
    print("All chroma is C*ab; all distances dE76; every surface judged at %dpx,"
          % GAME)
    print("the size the player sees. Species x grade floor below is the whole")
    print("shipped table (art/species_tints.py), not an average of it.\n")

    # ---- the thing that must stay loudest
    ore_surfaces = []
    print("%-26s %7s %7s %7s %7s" % ("ore as it ships", "hue", "mean C", "med", "max"))
    for i, t in enumerate(SPECIES_TINTS):
        for g in GRADE_ROWS:
            m = measure(at_1x(tint(frame_of("ore", "%s_full_v0" % g), t)))
            ore_surfaces.append(("species%d %s grade %s" % (i, t, g), m))
            print("%-26s %7s %7.1f %7.1f %7.1f"
                  % ("species%d %s %s" % (i, t, g), hue_s(m), m["mean_c"],
                     m["med_c"], m["max_c"]))
    # Measure D's ore side, computed once: every ore mark through every
    # observer. (18 surfaces x 4 observers; the per-row cost is 4.)
    ore_seen = [(n, {o: seen_flat(m["mark"], o) for o in OBSERVERS})
                for n, m in ore_surfaces]

    floor_name, floor_m = min(ore_surfaces, key=lambda s: s[1]["mean_c"])
    floor = floor_m["mean_c"]
    print("\nFLOOR: the quietest ore surface in the game is %s at mean C %.1f."
          % (floor_name, floor))
    print("That is the budget. Nothing else may be louder.\n")

    # ---- everything else
    print("%-26s %7s %7s %7s %7s %8s %8s %8s" %
          ("every other surface", "hue", "mean C", "med", "max",
           "dE whole", "dE mark", "D: dAB"))
    rows = []
    for asset, e in sorted(man.items()):
        if asset == "ore":
            continue
        for row in [r["name"] for r in e["rows"]]:
            img = at_1x(frame_of(asset, row))
            if FAKE_ORE is not None:
                img = at_1x(tint(frame_of("ore", "B_full_v0"),
                                 SPECIES_TINTS[FAKE_ORE]))
            if MUTE is not None:
                img = mute(img, MUTE)
            m = measure(img)
            if m is None:
                continue
            name = "%s/%s" % (asset, row)
            near_d, near_n = min((dE(m["rgb"], o["rgb"]), n) for n, o in ore_surfaces)
            mark_d, mark_n = min((dE(m["mark"], o["mark"]), n) for n, o in ore_surfaces)
            seen = {o: seen_flat(m["mark"], o) for o in OBSERVERS}
            ab_d, ab_n, ab_o = min((dAB(seen[o], s[o]), n, o)
                                   for n, s in ore_seen for o in OBSERVERS)
            over = m["mean_c"] - floor
            flag = ""
            if exempt(name):
                flag = " [exempt: %s]" % exempt(name)[0]
            else:
                if over > 0:
                    flag += " LOUDER THAN ORE"
                if near_d < DISTINCT:
                    flag += " READS AS ORE"
                if mark_d < DISTINCT:
                    flag += " MARK READS AS ORE"
            rows.append((name, m, over, near_d, near_n, mark_d, mark_n, flag,
                         ab_d, ab_n, ab_o))
            print("%-26s %7s %7.1f %7.1f %7.1f %8.1f %8.1f %8.1f%s"
                  % (name, hue_s(m), m["mean_c"], m["med_c"], m["max_c"],
                     near_d, mark_d, ab_d, flag))

    loud = [r for r in rows if r[2] > 0 and not exempt(r[0])]
    conf = [r for r in rows if r[3] < DISTINCT and not exempt(r[0])]
    mconf = [r for r in rows if r[5] < DISTINCT and not exempt(r[0])]

    print("\n" + "=" * 72)
    # Printed BEFORE the verdict, every run, loudly. An exemption that only
    # shows up as a quiet flag in one column is an exemption nobody re-reads.
    for asset, (who, why) in sorted(EXEMPT.items()):
        n = sum(1 for r in rows if r[0].split("/")[0] == asset)
        worst = max((r[2] for r in rows if r[0].split("/")[0] == asset),
                    default=0.0)
        print("EXEMPT: %s/* (%d rows, worst +%.1f over the floor) -- %s"
              % (asset, n, worst, who))
        print("\n".join("        " + l.strip() for l in why.strip().splitlines()))
        print()
    print("A. THE BUDGET: mean C must not exceed %.1f (%s)" % (floor, floor_name))
    if not loud:
        print("   PASS: every non-ore surface sits under the quietest species.")
    else:
        print("   FAIL: %d rows out-loud the quietest ore in the game."
              % len(loud))
        for name, m, over, _, _, _, _, _, _, _, _ in sorted(loud, key=lambda r: -r[2]):
            print("     %-24s mean C %5.1f  (+%4.1f over), hue %s, median %4.1f"
                  % (name, m["mean_c"], over, hue_s(m), m["med_c"]))
        worst = max(loud, key=lambda r: r[2])
        print("   worst: %s, +%.1f" % (worst[0], worst[2]))

    print("\nB. THE CONFUSION, WHOLE SURFACE: mean dE76 to the nearest tinted"
          "\n   ore must clear %.0f" % DISTINCT)
    if not conf:
        print("   PASS: no surface AS A WHOLE reads as a deposit."
              "\n   (This measure passed everything on the day it was written, which"
              "\n   is why C exists. Read it with C, never on its own.)")
    else:
        print("   FAIL: %d rows land inside a species' colour." % len(conf))
        for name, m, _, d, n, _, _, _, _, _, _ in sorted(conf, key=lambda r: r[3]):
            print("     %-24s dE %5.1f to %s" % (name, d, n))

    print("\nC. THE CONFUSION, AT THE MARK: dE76 between the most saturated"
          "\n   tenth of a surface and the same tenth of an ore tile, floor %.0f"
          % DISTINCT)
    if not mconf:
        print("   PASS: no surface's own colour lands on a species' colour.")
    else:
        print("   FAIL: %d rows wear a species' colour." % len(mconf))
        for name, m, _, _, _, d, n, _, _, _, _ in sorted(mconf, key=lambda r: r[5]):
            print("     %-24s dE %5.1f to %s" % (name, d, n))
            print("       its %d most saturated pixels are rgb(%.0f, %.0f, %.0f);"
                  " the whole-surface measure scores this row %.1f and misses it."
                  % (m["mark_n"], m["mark"][0], m["mark"][1], m["mark"][2],
                     [r[3] for r in rows if r[0] == name][0]))

    print("\nD. THE SAME CONFUSION WITH L* DROPPED, worst of %d observers."
          "\n   REPORTED, NOT A GATE -- see the header for why lightness is a"
          "\n   channel a machine is entitled to be told from a deposit by."
          % len(OBSERVERS))
    for name, m, _, _, _, mark_d, _, _, ab_d, ab_n, ab_o in sorted(
            rows, key=lambda r: r[8])[:6]:
        print("     %-24s dAB %5.1f to %s (%s), where measure C scores it %.1f"
              % (name, ab_d, ab_n, ab_o, mark_d))
    print("   These are NOT the pairs measure C found; read the two columns as"
          "\n   two questions, not as a subtraction. C asks whether any deposit"
          "\n   is this colour. D asks whether any deposit is this HUE to a"
          "\n   colour-blind eye, and the answer is yes for every orange surface"
          "\n   in the game -- so lightness, shape and grid position are carrying"
          "\n   that read on their own. See the header for why it is not a gate.")

    sheet(loud, conf + mconf, ore_surfaces, floor_name)

    ok = not loud and not conf and not mconf
    print("\nVERDICT: %s" % ("GREEN" if ok else "RED"))
    if not ok and MUTE is None:
        print("  This is the art as it ships. The measures above are the"
              "\n  Director's ruling turned into numbers; which way the red gets"
              "\n  cleared -- quieter machines, or a louder floor under the"
              "\n  species table -- is a look decision, not a bug to paint over.")
    print("=" * 72)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
