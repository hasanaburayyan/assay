#!/usr/bin/env python3
"""IS A LOOSE PART ITS OWN OBJECT IN A PACK SLOT? (ASSA-112)

    art/check_items_kinds.py              # the guard

ONE JUDGED PROPERTY SINCE DECISION #52, AND ONE REPORT. Measured on the ITEMS sheet
at the size a pack slot draws it:

  A. THE FLOOR -- RETIRED BY DECISION #52 (2026-10-09), AND THE SENTENCE IT STOOD FOR
     IS NOW ASSERTED HARDER ELSEWHERE. It said: "no loose part reads smaller in its
     slot than the smallest ITEM does", with the floor read off `ore`/`refined`/
     `smelter` in the same run rather than typed here, and with Maren's escape (a
     measured argument, never a stretch, and never the floor moving).

     WHY IT WENT. ASSA-376 fitted every frame of this sheet to its art, so a row's
     size in its slot no longer measures how big it was DRAWN -- that is now forced to
     100% of one axis. What a slot fill measures after the fit is COMPACTNESS: a rock
     fills its bbox, a rod on a diagonal cannot. The three part rows came out under
     `ore`'s fill (handle 28.9%, head 36.0%, hopper 39.5% against 43.0%) while
     `hopper`'s ink was byte-identical and NOTHING had got smaller -- the floor itself
     had risen 24.7 -> 43.0, because the floor IS ore's number. The hazard the floor
     guarded -- a part drawn small or lazily in its frame -- cannot happen any more,
     and a guard against an impossible hazard is not a guard.

     WHERE THE RULE LIVES NOW: `check_items_top_band.py`, as "art fills 100% of one
     axis of its frame", with the red control Decision #52 §5 asked for (art short on
     BOTH axes must fail, and art short on the axis it does not fill must still pass).
     IT IS NOT REIMPLEMENTED HERE, and not because of tidiness: this file's surface is
     the real engine path, and that path CANNOT carry the question. `drawn_icon`'s body
     mask is source alpha >= 200 (ASSA-111's correction), while the fitted frames'
     outermost paint runs 127-194 after the downscale -- so measured through the engine
     all seven rows report a body bbox inside their 32x48 slot and a "fills an axis"
     judge here would fail every row the fit made perfect. The sheet's own transparency
     is the only instrument that can answer it. Numbers:
     `shared/assay/cove-assa376-items-fill/`.

     THE FILL TABLE IS STILL PRINTED, as a report with no verdict on it, because the
     number is worth seeing and because a reader who remembers the floor should find
     out here that it is gone.

  B. THE SEPARATION, which is ASSA-111's property on a second surface and therefore
     ASSA-111's JUDGE: `verdict` is imported from `check_icon_kinds`, not
     reimplemented -- so Maren deleting the silhouette half of that property on
     2026-10-03 moved this check too, in one edit, which is the whole point of
     importing a judge. It now asks: no pair of kinds is close on COLOUR, interior
     dE76 over the overlap against DISTINCT. Two copies would have rotted apart.

WHY A SECOND CHECK AT ALL, rather than teaching `check_icon_kinds.py` about this.
That check asks the ENGINE what the client drew and measures exactly that -- which is
right, and which is why it cannot see these rows yet: the client's `sprites.gd` still
points its part rows at the assembly sheets, and the switch is its own item (Maren,
ASSA-112: "the client wiring is filed as its own item, not built here"). So this file
measures what the SHEET offers a slot. The day the wiring lands, `check_icon_kinds`
measures the same pixels through the engine and the two agree or somebody looks.

AND IT IS STILL THE ENGINE'S GEOMETRY. Nothing positional is invented here: the probe
is asked for the real layout, the row it hands back that is already drawn FROM THE
ITEMS SHEET is the template, and the only field changed is which row of that sheet to
cut -- the plate, the plate box, the tint and the drawn size are the engine's own. The
template's region is checked against the manifest's `frame_px` first, because a
template that does not match the sheet would make every number here a fiction.

TWO CONTROLS RUN EVERY TIME, because a check that has only ever been green has only
ever been an opinion:
  1. WIRING -- every kind against itself must come back IoU 1.000 / dE 0.00, and the
     rows must not all be the same picture.
  2. THE VERDICT CAN FAIL -- on a COPY of the real answer, one kind's icon is
     substituted for another's and must be caught.
     (This control had a second half, "and one kind redrawn at half scale must fall
     under the floor", which went with the floor. Half scale still spans an axis, so
     kept here it would have been a lever that can only pass -- vacuous, which is the
     shape of defect `--shrink` was written to prevent.)
  Neither holding is a pass: both exit 2.

EXIT CODES
  0 PASS       -- no pair of kinds is close on colour.
  1 FAIL       -- some pair is close on colour.
  2 NO VERDICT -- could not ask the engine, a control did not hold, or there was
                  nothing to measure. Never a pass.
"""
import json
import os
import sys

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
SPRITES = os.path.join(ROOT, "client", "assets", "sprites")

sys.path.insert(0, ART)
from ask_layout import CannotCheck, ask_the_engine  # noqa: E402
from check_icon_kinds import verdict  # noqa: E402  ASSA-111's judge, imported not copied
from colour import DISTINCT  # noqa: E402  Maren's threshold
from pack_icon_draw import compare, drawn_icon  # noqa: E402  the engine's sampling, once
from stdlib_image import StdlibBackend  # noqa: E402  pixels without pip

WHY_THE_ENGINE = ("the plate box, the tint and the drawn size are the client's, and a slot\n"
                  "fill measured against numbers typed in here would be a fact about this\n"
                  "file rather than about the pack.")

# The rows that were items before ASSA-112. The retired floor was the smallest of THEIR
# fills; the fill table still marks them, because "as much of an object as my ore" is
# what a reader of this table is comparing against even now that nothing is judged by it.
ALREADY_ITEMS = ("ore", "refined", "smelter")


def items_template(layout, frame_px):
    """The engine's own entry for a row already drawn from the items sheet."""
    sheet = "items.png"
    for r in layout.get("rows", []):
        ic = r.get("icon")
        if ic and os.path.basename(ic.get("sheet", "")) == sheet:
            x, y, w, h = ic["region"]
            if [w, h] != list(frame_px):
                raise CannotCheck(
                    "the engine cuts %dx%d out of %s where the manifest says the frame is\n"
                    "%dx%d. The template would not describe the rows this check draws."
                    % (w, h, sheet, frame_px[0], frame_px[1]))
            return r
    raise CannotCheck("no row in the engine's layout is drawn from %s, so there is no\n"
                      "template for how this client would draw one." % sheet)


def row_entries(layout, man):
    """One engine-shaped entry per row of the items sheet: only the cut moves."""
    template = items_template(layout, man["frame_px"])
    fw, fh = man["frame_px"]
    out = {}
    for i, row in enumerate(man["rows"]):
        entry = json.loads(json.dumps(template))     # a copy, never the engine's own dict
        entry["icon"]["region"] = [0, i * fh, fw, fh]
        out[row["name"]] = entry
    return out, template


def icons_of(entries, sprites, backend=StdlibBackend):
    """kind -> (plate image, body mask), drawn the way the engine draws one."""
    return {kind: drawn_icon(entry, sprites, backend) for kind, entry in entries.items()}


def fills(icons, box):
    slot = box[0] * box[1]
    return {k: 100.0 * len(body) / slot for k, (img, body) in icons.items()}


def picture(icons, pct, box, path):
    """The same icons this check judged, at 1:1 and at 4x, in one strip.

    THE PICTURE COMES OUT OF THE RUN THAT MEASURED, not a second script drawing the
    same rows a second way -- the numbers under each cell are the ones above. Needs
    Pillow, so it is never asked for in CI; the check itself is stdlib.
    """
    from PIL import Image, ImageDraw  # noqa: E402  only on this path
    sys.path.insert(0, ART)
    from review_font import font
    Z, pad = 4, 12
    cw = box[0] * Z + pad
    sheet = Image.new("RGB", (cw * len(icons) + pad, box[1] * Z + box[1] + 54), (34, 34, 34))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 6), "every items row at 1:1 and at 4x, on the engine's plate and tint "
                     "(ASSA-112)", font=font(13), fill=(236, 236, 236))
    for i, k in enumerate(sorted(icons, key=lambda k: -pct[k])):
        img = icons[k][0]
        x = pad + i * cw
        sheet.paste(img, (x + (box[0] * Z - box[0]) // 2, 26))
        sheet.paste(img.resize((box[0] * Z, box[1] * Z), Image.NEAREST), (x, box[1] + 32))
        d.text((x, box[1] * Z + box[1] + 36), "%s %.1f%%" % (k, pct[k]), font=font(12),
               fill=(230, 230, 230))
    sheet.save(path)
    print("wrote %s" % path)


def main(argv):
    pic = argv[argv.index("--picture") + 1] if "--picture" in argv else None
    man = json.load(open(os.path.join(SPRITES, "manifest.json")))["items"]
    layout = ask_the_engine(WHY_THE_ENGINE)
    entries, template = row_entries(layout, man)
    if len(entries) < 2:
        raise CannotCheck("%d rows on the items sheet: a separation between one thing and\n"
                          "itself is not a property." % len(entries))
    have = [k for k in ALREADY_ITEMS if k in entries]
    icons = icons_of(entries, SPRITES)
    box = template["icon"]["plate_rect"] or template["icon"]["rect"]
    box = [int(round(v)) for v in box]
    pct = fills(icons, box)
    print("MEASURED %d items rows at the size the engine draws one: a %dx%d slot, the\n"
          "engine's own plate and tint (%s), sheet %s"
          % (len(icons), box[0], box[1], template["icon"]["modulate"], man["sheet"]))

    # CONTROL 1: the instrument recognises a picture as itself, and the rows are not all
    # one picture.
    for k in sorted(icons):
        iou, de, _ = compare(icons[k], icons[k])
        if abs(iou - 1.0) > 1e-9 or de is None or de > 1e-9:
            raise CannotCheck("WIRING CONTROL FAILED: %s against itself came back IoU %.3f /\n"
                              "dE %s, not 1.000 / 0.00." % (k, iou, de))
    if len({tuple(sorted(body)) for _, body in icons.values()}) == 1:
        raise CannotCheck("every row came back with the identical body mask, so the cut is not\n"
                          "moving down the sheet. These would be seven copies of one row.")
    print("CONTROL 1 holds: every kind is itself at IoU 1.000 / dE 0.00, and the rows differ.")

    # CONTROL 2: both verdicts can fail, on a copy of the real answer.
    a, b = sorted(icons)[:2]
    red, _ = verdict({**icons, b: icons[a]})
    if not any({x[3], x[4]} == {a, b} for x in red):
        raise CannotCheck("RED CONTROL FAILED: with %s's icon substituted for %s's, the\n"
                          "separation verdict did not catch them." % (a, b))
    print("CONTROL 2 holds: substituting %s's icon for %s's is caught." % (a, b))

    # -------------------------------------------- A. RETIRED (Decision #52): a report
    print("\nSLOT FILL -- A REPORT, JUDGED BY NOTHING. Property A ('no part smaller in its\n"
          "slot than the smallest item') was retired by Decision #52: after ASSA-376's fit\n"
          "this number measures COMPACTNESS, not size, and the size rule it stood for is\n"
          "asserted absolutely by art/check_items_top_band.py -- 100% of one axis of the\n"
          "frame, with its own both-axes red control.")
    for k in sorted(pct, key=lambda k: -pct[k]):
        print("  %-8s %5.1f%%%s" % (k, pct[k], "  (item before ASSA-112)" if k in have else ""))

    # ------------------------------------------------------------ B. the separation
    failures, table = verdict(icons)
    print("\nALL %d PAIRS, worst silhouette first. dE is over the OVERLAP only, so the two\n"
          "columns are read together." % len(table))
    for iou, de, n, x, y in table:
        shown = "   --  (no shared pixel)" if de is None else "%7.2f" % de
        print("  %-8s / %-8s  IoU %.3f   interior dE %s   over %4d px" % (x, y, iou, shown, n))
    overlapping = [(de, x, y) for iou, de, n, x, y in table if de is not None]
    if overlapping:
        worst = min(overlapping)
        print("\n  Minimum interior dE over every overlapping pair: %.2f (%s / %s), against\n"
              "  DISTINCT %.2f -- Maren's, from colour.py." % (worst[0], worst[1], worst[2], DISTINCT))

    bad = 0
    if failures:
        bad = 1
        print("\n%d PAIR(S) CLOSE ON COLOUR -- a player tells these apart by shape alone:"
              % len(failures))
        for iou, de, n, x, y in failures:
            print("  %s / %s: interior dE %.2f < %.2f over %d px (silhouette IoU %.3f, shown"
                  " because it says how many pixels that dE came from)"
                  % (x, y, de, DISTINCT, n, iou))
        print("A loose drawing has no join to borrow separation from, so each kind has to be\n"
              "its own object (Maren, ASSA-112). Re-earn it in the art.")
    if bad:
        print("\nVERDICT: FAIL (exit 1).")
        return 1
    print("\nVERDICT: PASS (exit 0). No pair of kinds is close on colour. (Size is no longer\n"
          "judged here: see property A above and check_items_top_band.py.)")
    if pic:
        from pack_icon_draw import PillowBackend
        picture(icons_of(entries, SPRITES, backend=PillowBackend), pct, box, pic)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except CannotCheck as why:
        print("\nVERDICT: NO VERDICT (exit 2). This is not a pass.\n%s" % why)
        sys.exit(2)
