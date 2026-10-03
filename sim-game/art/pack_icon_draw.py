#!/usr/bin/env python3
"""HOW THE ENGINE PUTS A PACK ICON ON SCREEN, in one place.

Not a script: a module, imported by `pack_icon_sheet.py` (the 1:1 review sheet) and by
`pack_icon_kinds.py` (the kind-discrimination measure). It exists because those two ask
DIFFERENT questions of the SAME pixels, and the moment each carried its own copy of the
sampling rule they could disagree about what the client drew while both looked right.

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
