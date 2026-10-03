#!/usr/bin/env python3
"""HOW THE ENGINE PUTS A PACK ICON ON SCREEN, in one place.

Not a script: a module, imported by `pack_icon_sheet.py` (the 1:1 review sheet), by
`pack_icon_kinds.py` (the kind-discrimination measure) and by `check_icon_kinds.py` (the
CI guard on it). It exists because those ask DIFFERENT questions of the SAME pixels, and
the moment each carried its own copy of the sampling rule they could disagree about what
the client drew while both looked right.

WHICH IS WHY THIS FILE IS STDLIB-ONLY (ASSA-111). A `check_*.py` runs on plain `python3`
with no pip, so if the blit needed Pillow the check would have had to retype it. Instead
the two things Pillow was used for -- opening a frame and filling a plate -- are behind a
two-method BACKEND, and everything that is a rule about pixels lives below, called once by
both callers. `PillowBackend` imports PIL inside its methods on purpose: importing this
module must never require it.

That is the same failure `check_part_contract.py` was written for, stated for code instead
of for a constant: a shipped copy of a rule is a copy, and copies rot.

WHAT IS REPLICATED RATHER THAN ASKED, and why it has to be. Headless Godot has no renderer,
so the pixels are the one thing the layout probe cannot hand back. Everything else in both
callers -- the laid-out rect, the atlas region, `modulate`, the plate colour -- is read off
`pack_icon_layout.gd`'s answer after the real `main.tscn` was instantiated. Only this file
reimplements engine behaviour, and only these two documented rules:

  - STRETCH_KEEP_ASPECT_CENTERED: scale = min(rect.w/frame.w, rect.h/frame.h), result
    centred. Callers pass the already-scaled destination rect; the probe's own `scale` is in
    the JSON so a caller can assert the arithmetic.
  - TEXTURE_FILTER_NEAREST: a destination pixel takes the source texel under its CENTRE, and
    is drawn at all only if its centre lies inside the quad.

THE SECOND RULE IS WHY `PIL.Image.resize(..., NEAREST)` IS NOT GOOD ENOUGH HERE and is not
used. A part icon's destination rect is 32 x 25.5 at scale 0.25 -- a HALF pixel tall, at a
non-integer scale. PIL resizes to a whole number of pixels on its own sampling convention;
the engine rasterises a quad with a fractional edge and decides each destination pixel by
where its centre falls. The two answers differ along that edge, which is exactly the region
a silhouette measure is about.
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from colour import dE  # noqa: E402  the house colour metric, never a second copy

# A DESTINATION PIXEL IS THE SPRITE'S BODY AT SOURCE ALPHA >= 200.
#
# This is a correction, not a taste: the part frames carry a contact shadow whose alpha runs
# all the way down to 1, so counting every a > 0 pixel made the contrast measure mostly about
# the shadow -- it reported "100% under 3:1" for a sprite whose body plainly reads. Anything
# asking "what did a player see of the OBJECT" wants this bound; anything compositing wants
# every a > 0 pixel, which the blit does regardless.
BODY_ALPHA = 200


def nearest_blit(dst, frame, tint, dest_x, dest_y, dest_w, dest_h, zoom=1, body=None):
    """Draw `frame` into `dst` the way a TextureRect with NEAREST does, tinted by `modulate`.

    Returns the list of composited (r,g,b) for every pixel whose source texel was BODY ink --
    which is what a contrast question is about: the object, not the transparent frame around
    it or the contact shadow feathering out of it.

    `body`, when given, is a set that collects the (x, y) of each of those pixels. That is the
    silhouette the engine actually put on the plate, and it comes from here rather than from a
    second pass over the frame because a silhouette derived any other way would be a different
    sampling of the same quad -- which is the whole reason this module exists.
    """
    fw, fh = frame.size
    px = frame.load()
    ink = []
    x0 = math.floor(dest_x * zoom)
    y0 = math.floor(dest_y * zoom)
    x1 = math.ceil((dest_x + dest_w) * zoom)
    y1 = math.ceil((dest_y + dest_h) * zoom)
    out = dst.load()
    for dy in range(y0, y1):
        v = (dy + 0.5) / zoom - dest_y
        if v < 0 or v >= dest_h:
            continue
        sy = min(fh - 1, int(v / dest_h * fh))
        for dx in range(x0, x1):
            u = (dx + 0.5) / zoom - dest_x
            if u < 0 or u >= dest_w:
                continue
            sx = min(fw - 1, int(u / dest_w * fw))
            r, g, b, a = px[sx, sy]
            if a == 0:
                continue
            r = r * tint[0] // 255
            g = g * tint[1] // 255
            b = b * tint[2] // 255
            if 0 <= dx < dst.width and 0 <= dy < dst.height:
                base = out[dx, dy]
                f = a / 255.0
                mixed = tuple(int(round(c * f + base[i] * (1 - f))) for i, c in enumerate((r, g, b)))
                out[dx, dy] = mixed
                if a >= BODY_ALPHA:
                    ink.append(mixed)
                    if body is not None:
                        body.add((dx, dy))
    return ink


def rgb(h):
    """A `#`-less hex string as the engine hands it back, as (r, g, b)."""
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


class PillowBackend:
    """Opens frames and plates with Pillow. For the review sheets, which need resize/paste.

    PIL is imported INSIDE the methods, so a CI check can import this module on a python
    that has never heard of Pillow. That is the whole reason the backend exists.
    """

    name = "pillow"

    @staticmethod
    def open_frame(path, x, y, w, h):
        from PIL import Image
        sheet = Image.open(str(path)).convert("RGBA")
        return sheet.crop((int(x), int(y), int(x + w), int(y + h)))

    @staticmethod
    def new_plate(w, h, colour):
        from PIL import Image
        return Image.new("RGB", (w, h), colour)


def drawn_icon(entry, sprites_dir, backend):
    """The icon on its plate, exactly as the engine put it there, plus its body mask.

    Returns (image, body) where `image` is the composited plate box and `body` is the set of
    (x, y) the sprite's solid ink actually landed on. Both come out of ONE blit, because a
    mask computed separately would be a second sampling of the same quad.

    Everything positional is READ OFF THE PROBE'S ANSWER -- the region, the plate box, the
    drawn size, the tint -- after the real `main.tscn` was instantiated. The only arithmetic
    here is STRETCH_KEEP_ASPECT_CENTERED's centring, and `pack_icon_kinds.py` asserts the
    probe's own scale against the rect rather than trusting either.
    """
    ic = entry["icon"]
    x, y, w, h = ic["region"]
    frame = backend.open_frame(Path(sprites_dir) / Path(ic["sheet"]).name, x, y, w, h)
    bw, bh = (int(round(v)) for v in (ic["plate_rect"] or ic["rect"]))
    dw, dh = ic["drawn"]
    img = backend.new_plate(bw, bh, rgb(ic["plate"]) if ic["plate"] else (0, 0, 0))
    body = set()
    nearest_blit(img, frame, rgb(ic["modulate"]), (bw - dw) / 2.0, (bh - dh) / 2.0, dw, dh,
                 body=body)
    return img, body


def compare(a, b):
    """(IoU of the body masks, mean dE76 over their overlap, overlap pixel count).

    TWO MEASURES THAT SHARE NO QUANTITY, which is the point: IoU cannot see colour and the
    interior dE cannot see shape, because a pixel one sprite does not cover is not in it.
    """
    (ia, ba), (ib, bb) = a, b
    inter = ba & bb
    union = ba | bb
    iou = len(inter) / len(union) if union else 0.0
    if not inter:
        # NO SHARED PIXEL AT ALL: there is no interior to compare, and reporting 0.00 would read
        # as "identical colour" -- the exact opposite of the truth. Say so instead.
        return iou, None, 0
    pa, pb = ia.load(), ib.load()
    total = sum(dE(pa[x, y], pb[x, y]) for (x, y) in inter)
    return iou, total / len(inter), len(inter)
