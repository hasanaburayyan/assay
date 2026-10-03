#!/usr/bin/env -S uv run --quiet --with pillow python
"""WHAT DOES THIS RIG DO TO A LIGHT ALBEDO? (ASSA-115)

    art/headroom_probe.py                      # the shipped view transform
    art/headroom_probe.py --vt Standard        # ...and any other, to compare

Renders rock geometry -- the SAME `rig.Rig.rock()` call `assets/ore.py` makes,
one fixed rotation, one fixed size -- at a ramp of neutral albedos, and reads
the lit body back. Sixteen cells differing in nothing but albedo, so the only
thing the table can be measuring is the rig's own transfer curve.

WHY IT EXISTS. Three separate assets fell off the top of this rig and each was
written up as its own bug: ASSA-28's grade-A chassis blowing out to the same
value as a hopper, the grade-A glint landing on a species yellow nobody chose,
and 34% of a grade-A ore tile going flat (Maren, ASSA-115). They are one
defect, and it is not in any of the three asset scripts -- it is that under
`Standard` a lit face of this rig is about a stop over the clip, so every
albedo from 192 up renders as the same white. You cannot see that by reading an
asset script. You can see it in four lines of a ramp.

THE NUMBER IT EXISTS TO PRODUCE is the highest albedo that still renders with
shading in it. Under `Standard` that was 183, against a grade-C ore rock that
is already 173 -- which is how we know the ladder could not be re-fitted and
the transform had to move (see the HEADROOM comment in rig.py).

NOT A GATE and deliberately so: it needs Blender and ~50 s per transform. The
gate that runs in CI is `art/check_headroom.py`, which measures the SHIPPED
sheets and needs no renderer. Run this one when you change a lamp, the view
transform, or anything else about how light becomes a pixel.
"""
import os, subprocess, sys

ART = os.path.dirname(os.path.abspath(__file__))
BLENDER = os.environ.get("BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")
# 16 neutral greys. The bottom is below anything in the palette and the top is
# pure white, so the ramp always brackets whatever the palette is doing.
VALS = [120, 129, 138, 147, 156, 165, 174, 183, 192, 201, 210, 219, 228, 237, 246, 255]
CELLS = 4  # 4x4 grid on a 4x4-tile frame


# --------------------------------------------------------------- in Blender
def render(out_png, view_transform):
    import bpy, random  # noqa: F401  (only importable inside Blender)
    sys.path.insert(0, ART)
    import rig
    from rig import mat
    r = rig.Rig(samples=48)
    if view_transform:
        bpy.context.scene.view_settings.view_transform = view_transform
    r.shadow_catcher()
    for i, v in enumerate(VALS):
        cx, cy = -1.5 + (i % CELLS), 1.5 - (i // CELLS)
        random.seed(7)  # same displacement in every cell: albedo is the only variable
        r.rock(0.34, (cx, cy, 0.01), mat("#%02X%02X%02X" % (v, v, v), rough=0.68),
               sub=1, squash=0.58, rot=(0.1, -0.05, 0.7), env=False)
    r.frame(CELLS, CELLS)
    r.render(out_png)


# ------------------------------------------------------------------ reading
def read(png):
    from PIL import Image
    im = Image.open(png).convert("RGBA")
    cw, ch = im.size[0] // CELLS, im.size[1] // CELLS
    rows = []
    for i, v in enumerate(VALS):
        cell = im.crop(((i % CELLS) * cw, (i // CELLS) * ch,
                        (i % CELLS + 1) * cw, (i // CELLS + 1) * ch))
        mx = sorted(max(p[0], p[1], p[2]) for p in cell.getdata() if p[3] > 200)
        # Drop the Freestyle outline: it is ink, not surface, and it would drag
        # every percentile down by a constant that has nothing to do with albedo.
        body = [x for x in mx if x > 60]
        if not body:
            continue
        n = len(body)
        rows.append((v, body[n // 2], body[n * 95 // 100], body[-1],
                     100.0 * sum(1 for x in body if x >= 254) / n))
    return rows


def main(argv):
    vt = None
    if "--vt" in argv:
        vt = argv[argv.index("--vt") + 1]
    out = os.path.join(ART, "out", "headroom")
    os.makedirs(out, exist_ok=True)
    png = os.path.join(out, "ramp_%s_00.png" % (vt or "shipped").replace(" ", "_"))
    inner = [BLENDER, "--background", "--factory-startup", "--python", __file__,
             "--", "--render", png] + (["--vt", vt] if vt else [])
    p = subprocess.run(inner, capture_output=True, text=True)
    if p.returncode != 0 or not os.path.exists(png):
        sys.exit("headroom_probe: Blender failed\n" + (p.stdout + p.stderr)[-2000:])

    rows = read(png)
    print("THE RIG'S TRANSFER CURVE, lit rock body, view transform %r.\n" % (vt or "as shipped"))
    print("%7s %8s %6s %5s %8s" % ("albedo", "p50", "p95", "max", "%at 254+"))
    for v, p50, p95, mx, clip in rows:
        print("%7d %8d %6d %5d %8.1f" % (v, p50, p95, mx, clip))
    clean = [r[0] for r in rows if r[4] < 1.0]
    dirty = [r[0] for r in rows if r[4] >= 1.0]
    print("\nHighest albedo that still renders with shading in it: %s" %
          (max(clean) if clean else "NONE -- everything clips"))
    if dirty:
        print("Clipping starts at albedo %d. Every palette entry above that renders as\n"
              "the same white, and under the client's multiply tint it is not 'bright',\n"
              "it is exactly the species hex." % min(dirty))
    else:
        print("Nothing on the ramp clips: the whole palette is printable.")
    print("\nRamp: %s" % png)
    return 0


if __name__ == "__main__":
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if "--render" in a:
        render(a[a.index("--render") + 1], a[a.index("--vt") + 1] if "--vt" in a else None)
    else:
        sys.exit(main(a))
