#!/usr/bin/env -S uv run --quiet --with pillow python
"""Render sprites with Blender and pack them for the client.

    art/build.py            # everything
    art/build.py ore head   # only these assets
    art/build.py --pack     # skip rendering, just repack art/out
    art/build.py --contact-only   # redraw assets/review/contact.png, touch no shipped art

Pipeline: assets/<name>.py runs inside Blender and writes raw SSx frames to
art/out/<name>/ plus asset.json. This script downscales them to authoring
size (64 px per tile), packs one sheet per asset into client/assets/sprites/,
writes manifest.json there, and renders assets/review/contact.png.

TWO DESTINATIONS, AND THE SPLIT IS NOT TIDINESS (ASSA-34)
  `client/assets/sprites/` is what SHIPS. It is inside the Godot project
  because `res://` is the project folder and nothing above it, so a sheet
  anywhere else cannot be loaded by a script or packed by an export. That was
  the finding: eleven files, four measured checks, and nothing the engine
  could reach.

  `assets/review/` is what WE LOOK AT - the contact sheet and the probes. They
  stay OUTSIDE the project on purpose. Both export presets set
  `export_filter="all_resources"`, which packs every resource in the project
  whether a scene references it or not, so a review sheet left next to the
  game sheets would ride into every shipped bundle and get a Godot `.import`
  sidecar for a texture no script will ever load. Measured at the move:
  1.45 MB of review sheets against 680 KB of actual game art, so the review
  output was more than twice the size of the thing it reviews.
"""
import json, os, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw
import review_sources
import review_layout  # the contact sheet's declaration that it draws no client layout

# NOT A PICTURE OF A CLIENT PANEL, SAID OUT LOUD (CO-6). `check_review_layout.py` used to print
# `NO LAYOUT` for this sheet and pass, so "a contact sheet of sprites" and "a panel sheet that
# FORGOT its layout stamp" were one state -- and two sheets really were the second thing. The
# contact sheet is laid out by the loop below, from the manifest; the client never answers for it.
ART_ONLY = review_layout.art_only(
    "a contact sheet of the shipped sprites at 1x and 0.5x, laid out by build.py's own loop "
    "from the manifest; no engine layout is behind any part of it")

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
OUT = os.path.join(ART, "out")
# Shipped art, inside the Godot project. See the module docstring.
SPRITES = os.path.join(ROOT, "client", "assets", "sprites")
# Review sheets, deliberately outside it.
REVIEW = os.path.join(ROOT, "assets", "review")
BLENDER = os.environ.get("BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")
SS = 4
# render order = contact sheet order
ORDER = ["ground", "scatter", "ore", "items", "head", "handle", "frame", "hopper", "spawn",
         "smelter", "player"]


def render(name):
    script = os.path.join(ART, "assets", f"{name}.py")
    t = time.time()
    p = subprocess.run([BLENDER, "--background", "--factory-startup", "--python", script, "--", OUT],
                       capture_output=True, text=True)
    log = p.stdout + p.stderr
    if p.returncode != 0 or "Traceback" in log or "Error:" in log:
        tail = "\n".join(l for l in log.splitlines() if "Traceback" in l or "Error" in l or "line " in l or "  File" in l)
        sys.exit(f"{name}: Blender failed\n{tail[-3000:]}")
    n = sum(1 for f in os.listdir(os.path.join(OUT, name)) if f.endswith(".png"))
    print(f"  {name}: {n} frames in {time.time() - t:.0f}s")


# A LIGHT ROW IS DERIVED, NOT RENDERED, and this is the one number in that
# derivation that is a judgement (ASSA-137; `rig.Asset.light_row` says why the
# row exists at all).
#
# The layer is the difference between two renders of the same scene, so every
# pixel that Cycles sampled slightly differently is a "change". At a threshold
# of zero, 58.2% of the smelter's inked pixels had moved -- against the 24.2%
# that moved by more than 12, which is Maren's fire. Threshold-zero counting is
# the mistake I keep making, so the threshold is built in from the start rather
# than discovered afterwards.
#
# 4/255 on the largest channel. Measured on the smelter: the layer covers 36.5%
# of the frame instead of 58.2%, and the worst a discarded pixel can be wrong by
# is the threshold itself -- 4/255, under one step of the 8-bit ramp the eye can
# see on a mid grey. Higher thresholds start dropping the warm spill on the wall
# the fire is actually lighting, which is the part that says "the fire is in
# THIS building".
LIGHT_FLOOR = 4


def light_layer(body, lit):
    """`lit` split into the material it is made of and the light falling on it.

    Returns the layer L for which `over(L, body) == lit`, with the SMALLEST alpha
    that can do it:

        a      = max over channels of (lit_c - body_c) / (255 - body_c)
        L.rgb  = (lit - (1-a)*body) / a

    Alpha is the light's share of the pixel, so a coal that burns to white comes
    out opaque and keeps its own colour under any tint, while a wall the fire only
    warms stays mostly its own species. Pixels that got DARKER keep the body: a
    light layer may only add, and cold->lit darkening in a path-traced render is
    sampling noise, not shadow.

    Done at AUTHORING size, after the downscale, because that is the sheet the
    client samples. Deriving at supersample size and then resizing would run a
    straight-alpha layer through LANCZOS and fringe every coal.
    """
    out = Image.new("RGBA", body.size)
    bd, ld = list(body.getdata()), list(lit.getdata())
    px = []
    for i in range(len(bd)):
        b, l = bd[i], ld[i]
        if l[3] == 0 or max(l[ch] - b[ch] for ch in range(3)) <= LIGHT_FLOOR:
            px.append((0, 0, 0, 0))
            continue
        a = 0.0
        for ch in range(3):
            if 255 - b[ch] > 0:
                a = max(a, (l[ch] - b[ch]) / (255 - b[ch]))
        a = min(1.0, max(0.0, a))
        a8 = max(1, int(round(a * 255)))
        a = a8 / 255.0
        px.append(tuple(int(round(min(255.0, max(0.0, (l[ch] - (1 - a) * b[ch]) / a))))
                        for ch in range(3)) + (a8,))
    out.putdata(px)
    return out


def darken_rim(im, width, k):
    """Multiply the outer `width` rings of this frame's ALPHA MASK by `k` (ASSA-159).

    WHY THE SILHOUETTE AND NOT THE BODY. A building and the ore of its own species
    carry the identical `modulate` colour, so the tint cancels and only the greyscale
    sheet separates a drill from the deposit it must stand on to run. Everything that
    darkens the BODY pays for that separation with the pixels that name the material:
    measured, reaching the bar that way costs the species read (worst pair dE 8.2
    against DISTINCT 12). A ring is tint-independent and leaves the body alone --
    black is the one ink a multiply cannot recolour. `rig.PART_RIM_PX` has the rest,
    including why the width is 2 and the k is 0.15.

    A RING OF THE ALPHA MASK, NOT A STROKE OF THE DRAWING. Freestyle can only widen
    the line everywhere, which inks creases too; this walks in from transparency, so
    it touches exactly the pixels that border what the player sees as the edge.

    MULTIPLY, NOT A FLAT INK. The ring keeps its own modelling and its own hue at
    15%, so a lit face still reads lighter than a shadowed one along the rim, and the
    pixels still carry (a little) species chroma under the tint. A flat fill would be
    a second outline colour the palette does not own.

    `alpha > 200` is what counts as opaque, the same threshold the rest of the art
    tools use for "a drawn pixel"; the antialiased fringe outside it is already ink.
    Off-image counts as transparent, so a part clipped by its frame edge is rimmed
    along that edge too -- it is a silhouette on screen whatever made it one.

    THE ALPHA MASK THIS WALKS IN FROM IS PARTLY FREESTYLE'S, WHICH IS NOT OBVIOUS
    (ASSA-172). Measured by rendering the four parts with the outline pass on and off
    and differencing: 1,203 to 1,577 px per part change ALPHA, so the line extends
    past the geometry rather than sitting inside it. So the outer rings this darkens
    are partly line pixels that are already dark, and the ring's effect is smaller
    than the width suggests. Nobody re-deriving `RIM_PX` or `part_layout.INK_RIM_PX`
    should assume the mask is the model's own silhouette.
    """
    px = im.load()
    w, h = im.size
    cur = {(x, y) for y in range(h) for x in range(w) if px[x, y][3] > 200}
    out = im.copy()
    po = out.load()
    for _ in range(width):
        ring = {p for p in cur
                if any((p[0] + dx, p[1] + dy) not in cur
                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))}
        for (x, y) in ring:
            r, g, b, a = px[x, y]
            po[x, y] = (int(r * k), int(g * k), int(b * k), a)
        cur -= ring
    return out


# A FRAME'S OWN TRANSPARENCY IS AIR. (ASSA-376, Maren's rule, one level down from ASSA-328)
#
# `rig.Asset(fill="top")` means: this sheet's frames are ICON BOXES, so fit each frame's
# paint to its box -- aspect preserved, top edge at y=0, slack at the BOTTOM. See
# `rig.Asset.fill` for which assets may say it and why `items` qualifies.
#
# THE FLOOR IS THE WHOLE INSTRUMENT, AND `alpha > 0` IS THE TRAP IT EXISTS TO AVOID.
# Every raw frame on this sheet carries a film of alpha 1-4 over the ENTIRE 256x384 --
# Cycles sampling noise on a transparent film -- so `alpha > 0` puts six of seven items
# rows at a full-bleed 64x96 and reports a 40 px band of air as no band at all. That
# artefact is what my own ASSA-357 "six of seven rows are full-bleed" measurement counted,
# and it is why ASSA-376's first acceptance box was green on the day it was written.
#
# 4 of 255, the same number and the same reasoning as LIGHT_FLOOR above: the worst a
# discarded pixel can be wrong by is the floor itself, which over the panel's own SURFACE
# (37,40,48) is a shift of under one step of the 8-bit ramp. And the answer does not rest
# on it -- measured on the shipped sheet, every floor from 1 to 200 puts each row's top
# within 2 px of every other floor's, because the art goes from 0 to 255 in two rows.
PAINT_FLOOR = 4


def fit_to_frame(im, fw, fh, floor=PAINT_FLOOR):
    """Crop `im` to its paint and scale that into `fw x fh`, top-aligned, centred in x.

    One axis lands exactly on the frame; the other rounds, so the aspect error is at
    most half a pixel on the rounded axis and nothing is stretched. Done on the RAW
    render rather than after the downscale, so the fit is a resample of the 4x source
    and not a resize of a resize.
    """
    px = im.load()
    w, h = im.size
    x0 = y0 = None; x1 = y1 = -1
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > floor:
                if x0 is None or x < x0: x0 = x
                if x > x1: x1 = x
                if y0 is None: y0 = y
                y1 = y
    if y1 < 0:
        raise SystemExit("fit_to_frame: a frame with no paint above alpha %d" % floor)
    bw, bh = x1 - x0 + 1, y1 - y0 + 1
    s = min(fw / bw, fh / bh)
    nw, nh = max(1, min(fw, int(round(bw * s)))), max(1, min(fh, int(round(bh * s))))
    out = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    out.alpha_composite(im.crop((x0, y0, x1 + 1, y1 + 1)).resize((nw, nh), Image.LANCZOS),
                        ((fw - nw) // 2, 0))
    return out


def pack(name):
    meta = json.load(open(os.path.join(OUT, name, "asset.json")))
    fw, fh = meta["frame_px"]
    cols = max(r["frames"] for r in meta["rows"])
    derived = {d["row"]: d for d in meta.pop("derive", [])}

    # A SLICED ASSET IS ONE RENDER CUT INTO ROWS, AND THE CUT COMES AFTER THE RESIZE.
    #
    # `rig.Asset.slice_from` says why it exists: a cell rendered on its own is denoised and
    # resampled as an image, so it carries a border, and on a block that border IS a tile
    # seam (+0.401 of 255 across a cell boundary, enough to leave the tile offset rank 1 of
    # 32 on Maren's findability test). Here the whole field is downsampled first and the
    # cells are cut out of the finished picture, so no cell ever has an edge of its own.
    # Cutting first would reintroduce exactly what this removes, which is the one thing
    # about this function that must not be "tidied".
    sliced = meta.pop("slice", None)
    cells = {}
    if sliced:
        bw, bh = meta["block"]
        whole = Image.open(os.path.join(OUT, name, f"{sliced['source']}_00.png")).convert("RGBA")
        # The render carries `margin` authoring px of the NEIGHBOURING field on every side
        # (the geometry wraps, so it is the true continuation). Resize WITH it, then cut it
        # off: that way the image edge -- the one border the resize cannot see past -- is
        # never inside the shipped field. The field's own wrap join measured +0.844 of 255
        # without this and +0.078 at an interior cell boundary.
        m = int(sliced.get("margin", 0))
        whole = whole.resize((bw * fw + 2 * m, bh * fh + 2 * m), Image.LANCZOS)
        if m:
            whole = whole.crop((m, m, m + bw * fw, m + bh * fh))
        for i in range(bw * bh):
            cx, cy = i % bw, i // bw
            cells[f"v{i}"] = whole.crop((cx * fw, cy * fh, (cx + 1) * fw, (cy + 1) * fh))

    # Popped like `rim`: an instruction to this function, not part of the client's
    # contract. REFUSED on the three shapes whose frames are not independent pictures --
    # a per-frame fit would scale two frames of one animation differently (jitter), the
    # two halves of a light-row derivation differently (the subtraction stops meaning
    # anything), and the cells of a block out of register with each other.
    fill = meta.pop("fill", None)
    if fill and fill != "top":
        sys.exit("%s: fill=%r is not a rule pack() knows (only \"top\")" % (name, fill))
    if fill and (sliced or meta.get("block") or derived
                 or any(r["frames"] > 1 for r in meta["rows"])):
        sys.exit("%s: fill=\"top\" needs one independent frame per row -- no slice, no "
                 "block, no derived light row, no animation. See fit_to_frame." % name)

    def authored(row, f):
        if row in cells:
            return cells[row]
        im = Image.open(os.path.join(OUT, name, f"{row}_{f:02d}.png")).convert("RGBA")
        if fill:
            return fit_to_frame(im, fw, fh)
        return im.resize((fw, fh), Image.LANCZOS)

    # The rim is a property of the SHEET, so it is applied here and not in the asset
    # script: the ring is walked in from the alpha mask the downscale produced, which
    # no Blender setting can see. Popped rather than kept, because it is an
    # instruction to this function and not part of the client's contract.
    rim = meta.pop("rim", None)

    sheet = Image.new("RGBA", (cols * fw, len(meta["rows"]) * fh), (0, 0, 0, 0))
    for y, row in enumerate(meta["rows"]):
        for f in range(row["frames"]):
            d = derived.get(row["name"])
            im = light_layer(authored(d["body"], f), authored(d["lit"], f)) if d \
                else authored(row["name"], f)
            if rim and not row.get("light"):
                # Never a light row: that one is EMITTED LIGHT drawn at Color.WHITE over
                # the body (`rig.Asset.light_row`), so darkening its edge would dim a
                # fire for a reason about material.
                im = darken_rim(im, int(rim[0]), float(rim[1]))
            sheet.alpha_composite(im, (f * fw, y * fh))
    sheet.save(os.path.join(SPRITES, f"{name}.png"))
    meta["sheet"] = f"{name}.png"; meta["columns"] = cols
    return meta


def simulate_cvd(im, kind):
    """Machado et al. 2009 full-severity matrices, applied to sRGB (good
    enough for a review sheet)."""
    M = {"protan": (0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998),
         "deutan": (0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.011820, 0.042940, 0.968881),
         "tritan": (1.255528, -0.076749, -0.178779, -0.078411, 0.930809, 0.147602, 0.004733, 0.691367, 0.303900)}[kind]
    m = M
    rgb = im.convert("RGB").convert("RGB", (m[0], m[1], m[2], 0, m[3], m[4], m[5], 0, m[6], m[7], m[8], 0))
    return rgb.convert("RGBA")


def contact(manifest):
    """Every row's first frame at authoring size and at 1x game size, on a
    neutral background, labelled. Ore tiles also get colour-blind
    simulations so the four kinds can be checked for shape readability."""
    pad, label_w = 6, 150
    bg = (44, 48, 44, 255)
    blocks = []
    for name in ORDER:
        if name not in manifest: continue
        meta = manifest[name]
        fw, fh = meta["frame_px"]
        sheet = Image.open(os.path.join(SPRITES, meta["sheet"])).convert("RGBA")
        rows = meta["rows"]
        # A BLOCK IS ONE PICTURE, SO THE SHEET SHOWS IT AS ONE (ASSA-115 box 2).
        #
        # `meta["block"]` means these w*h rows are the row-major cells of a single
        # continuous w x h-tile render and a client places them by position
        # (`rig.Asset.block`, `scene_view.gd::ground_row`). Drawn the normal way that
        # is 64 unlabelled green squares, which is not the asset and cannot be judged:
        # the whole question about a ground block is whether its 8x8 repeat is
        # findable, and that is a question about the assembled picture. So it is
        # assembled here, at authoring size and at 1x, exactly like every other row.
        if meta.get("block"):
            bw, bh = meta["block"]
            field = Image.new("RGBA", (bw * fw, bh * fh))
            for i in range(min(bw * bh, len(rows))):
                field.alpha_composite(sheet.crop((0, i * fh, fw, (i + 1) * fh)),
                                      ((i % bw) * fw, (i // bw) * fh))
            line = Image.new("RGBA", (label_w + field.width + field.width // 2 + 3 * pad,
                                      field.height + pad), bg)
            ImageDraw.Draw(line).text((4, 4), "%s/%dx%d block" % (name, bw, bh),
                                      fill=(220, 220, 220, 255))
            line.alpha_composite(field, (label_w, 0))
            line.alpha_composite(field.resize((field.width // 2, field.height // 2),
                                              Image.LANCZOS),
                                 (label_w + field.width + pad, field.height // 2))
            blocks.append(line)
            continue
        # animated assets: show every frame of each row; static: 8 rows per line
        per_line = 1 if meta["columns"] > 1 else 8
        for i in range(0, len(rows), per_line):
            chunk = rows[i:i + per_line]
            shown = max(r["frames"] for r in chunk) if meta["columns"] > 1 else len(chunk)
            line = Image.new("RGBA", (label_w + shown * (fw + fw // 2 + 2 * pad), fh + pad), bg)
            d = ImageDraw.Draw(line)
            d.text((4, 4), f"{name}/{chunk[0]['name']}" + (f" +{len(chunk) - 1}" if len(chunk) > 1 else ""), fill=(220, 220, 220, 255))
            x = label_w
            for j, row in enumerate(chunk):
                ry = (i + j) * fh
                for f in range(row["frames"] if meta["columns"] > 1 else 1):
                    fr = sheet.crop((f * fw, ry, (f + 1) * fw, ry + fh))
                    line.alpha_composite(fr, (x, 0)); x += fw + pad
                    line.alpha_composite(fr.resize((fw // 2, fh // 2), Image.LANCZOS), (x, fh // 2)); x += fw // 2 + pad
            blocks.append(line)
        if name == "ore":
            # COLOUR-BLIND CHECK. This used to put the tier-4 tile of each of
            # the four named ores side by side, which stopped checking
            # anything the moment the ore art went species-neutral: there are
            # no kinds left to tell apart, the row it grepped for stopped
            # existing, and it quietly drew four empty strips.
            #
            # What needs checking now is the thing that REPLACED shape: the
            # six species tints, multiplied over one neutral tile, over the
            # ground, through each observer. If two of these six ever stop
            # being six, this is where it shows.
            from species_tints import SPECIES_TINTS as tints
            t4 = next((r for r in rows if r["name"] == "t4_full_v0"), None)
            gm = manifest.get("ground")
            if t4 is not None and tints:
                ry = rows.index(t4) * fh
                tile = sheet.crop((0, ry, fw, ry + fh))
                under = None
                if gm:
                    gsheet = Image.open(os.path.join(SPRITES, gm["sheet"])).convert("RGBA")
                    gw, gh = gm["frame_px"]
                    under = gsheet.crop((0, 0, gw, gh)).resize((fw, fh), Image.LANCZOS)
                for cvd in ("normal", "protan", "deutan", "tritan"):
                    line = Image.new("RGBA", (label_w + len(tints) * (fw + fw // 2 + 2 * pad), fh + pad), bg)
                    ImageDraw.Draw(line).text((4, 4), f"ore/species {cvd}", fill=(220, 220, 220, 255))
                    x = label_w
                    for hexc in tints:
                        c = [int(hexc[i:i + 2], 16) for i in (1, 3, 5)]
                        tinted = Image.new("RGBA", tile.size)
                        tp, op = tile.load(), tinted.load()
                        for yy in range(fh):
                            for xx in range(fw):
                                r_, g_, b_, a_ = tp[xx, yy]
                                op[xx, yy] = (r_ * c[0] // 255, g_ * c[1] // 255, b_ * c[2] // 255, a_)
                        fr = under.copy() if under else Image.new("RGBA", tile.size, (0, 0, 0, 0))
                        fr.alpha_composite(tinted)
                        if cvd != "normal": fr = simulate_cvd(fr, cvd)
                        line.alpha_composite(fr, (x, 0)); x += fw + pad
                        line.alpha_composite(fr.resize((fw // 2, fh // 2), Image.LANCZOS), (x, fh // 2)); x += fw // 2 + pad
                    blocks.append(line)
    W = max(b.width for b in blocks); H = sum(b.height for b in blocks)
    out = Image.new("RGBA", (W, H), bg); y = 0
    for b in blocks:
        out.alpha_composite(b, (0, y)); y += b.height
    out.save(os.path.join(REVIEW, "contact.png"),
             pnginfo=review_layout.png_info(review_sources.png_info(), layouts=ART_ONLY))


def draw_contact(manifest_path):
    """The contact sheet's whole drawing pass, recorded, and the ONLY way it is ever drawn.

    ONE FUNCTION BECAUSE THE STAMP MUST NOT DEPEND ON WHICH FLAG YOU PASSED (ASSA-144). My
    first cut recorded a wider block in the full build than in `--contact-only`, and it was
    wrong twice over: the two paths would stamp different source sets for identical art, so
    the check would flip on the flag rather than on the art -- and the full build read
    `manifest.json` BEFORE `pack()` rewrote it, stamping the digest of a manifest that no
    longer existed, which turns the check red the moment a real build succeeds.

    So the manifest is re-read here, after any packing, inside the recording: what the sheet
    composited is the manifest that SHIPPED, not the one that was on disk when the run began.
    """
    with review_sources.recording():
        contact(json.load(open(manifest_path)))


def write_part_contract():
    """Ship the two rules that turn part sprites into a machine. (ASSA-54)

    A SEPARATE FILE RATHER THAN A BLOCK IN manifest.json, which is what I
    first specified and then checked. The manifest's top level is an ASSET
    NAMESPACE: `check_client_can_see_art.py` does `man[a]["sheet"]` for every
    key, and the client's own `test_sprites.gd` walks it both ways and fails
    on "the manifest describes `X` and there is no X.png". A `part_layout`
    key would have broken both the moment it shipped.

    DERIVED, NOT COPIED: the numbers come from importing `part_layout`, the
    same module `assemble.py` and the Blender rig use, so there is no second
    place to edit. `check_part_contract.py` fails if this file and the module
    ever disagree, which is what a stale manifest looks like.

    WHY IT HAS TO BE SHIPPED AT ALL. The sheets and the manifest tell a client
    how to slice frames, and nothing tells it how to COMBINE them. A client
    that blits part frames at one position with the default operator gets the
    defect this pipeline measured and rejected: repeats become invisible (a
    second hopper adds 25 px at 1x instead of 108, which is antialiasing).
    Measured 2026-10-02, picture in `shared/assay/part-contract-2026-10-02.png`.

    THE SHADOW HALF OF THAT SENTENCE IS NO LONGER TRUE AND I AM NOT LEAVING IT
    STANDING. It read "darkest alpha runs 128 -> 221 over four hoppers". Since
    ASSA-64 a hopper carries no contact shadow, so plain `over` and `stack`
    both come out flat at 93 -- re-measured both ways today, not edited to
    agree. The rule still ships, because a client is still held to it and
    because the day a ground-standing part is drawn the compounding is back.
    """
    import part_layout
    contract = {
        "source": "art/part_layout.py",
        "repeat_offset_px": list(part_layout.PART_REPEAT_OFFSET),
        "repeat_offset_space": (
            "the same authoring pixels as `frame_px` in manifest.json; scale it "
            "by exactly what you scale the frame by"),
        "repeat_rule": (
            "the nth repeat of a part KIND is drawn at n * repeat_offset_px, n "
            "counting from 0 in sim's Assembly::parts() order (frame first). "
            "Without it, repeats land on each other and a machine cannot show "
            "how many of a part it has."),
        "shadow_ceiling": part_layout.SHADOW_CEILING,
        "shadow_rule": (
            "a pixel whose brightest channel is below shadow_ceiling is contact "
            "shadow: composite colour OVER but take alpha MAX, so shadows never "
            "accumulate. Plain `over` makes a machine's shadow darken with every "
            "part added, which is a gradient reporting part count."),
        # ASSA-64. The rule above is still the contract; this says why a client
        # that ignored it would no longer produce the defect, which is a
        # different claim and worth shipping beside it.
        "shadow_source": part_layout.MOUNTED_PARTS_CARRY_NO_SHADOW,
    }
    json.dump(contract, open(os.path.join(SPRITES, "part_layout.json"), "w"), indent=1)


def write_ui_theme():
    """Ship the colours the client draws that are in no sprite. (ASSA-71)

    One so far: the plate behind a pack-row icon, which is the ground's own
    median so that a stack in the pack and a rock on the map read as the same
    object. Derived from the SHIPPED `ground.png` on every build, for the same
    reason the part contract is derived rather than copied -- the day the
    ground is re-rendered, a hex written down anywhere stops being the ground's
    colour and nobody finds out. Rationale in `art/ui_theme.py`, including why
    this is a sibling of the manifest and not a key inside it.
    """
    import ui_theme
    json.dump(ui_theme.contract(SPRITES), open(os.path.join(SPRITES, "ui_theme.json"), "w"), indent=1)


def main(argv):
    names = [a for a in argv if not a.startswith("--")] or ORDER
    manifest_path = os.path.join(SPRITES, "manifest.json")

    # --contact-only: REDRAW THE REVIEW SHEET WITHOUT TOUCHING SHIPPED ART (ASSA-144).
    #
    # Every other path through this script repacks. `--pack` looked like the cheap way to
    # refresh `contact.png`, and it is the documented hazard at the top of `art/README.md`:
    # `art/out/` is git-ignored, so it holds whatever THIS machine last rendered, and packing
    # from a stale or empty cache silently rewrites sheets merged from someone else's
    # checkout. That cost a ruled-on `frame.png` row once already.
    #
    # ASSA-144 made that a trap rather than a hazard: stamping the contact sheet with the art
    # it composited is a reason to re-run this script, and the only available way to do it
    # also risked replacing the art. So there is now a path that only READS shipped art.
    if "--contact-only" in argv:
        if not os.path.exists(manifest_path):
            sys.exit("--contact-only needs a packed %s; run a real build first." % manifest_path)
        draw_contact(manifest_path)
        print(f"wrote {REVIEW}/contact.png  (shipped art read, never written)")
        return

    os.makedirs(OUT, exist_ok=True)
    os.makedirs(SPRITES, exist_ok=True); os.makedirs(REVIEW, exist_ok=True)
    if "--pack" not in argv:
        for n in names: render(n)
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}
    for n in names:
        if os.path.exists(os.path.join(OUT, n, "asset.json")):
            manifest[n] = pack(n)
    manifest = {k: manifest[k] for k in ORDER if k in manifest}
    json.dump(manifest, open(manifest_path, "w"), indent=1)
    write_part_contract()
    write_ui_theme()
    draw_contact(manifest_path)
    print(f"wrote {SPRITES}/manifest.json")
    print(f"wrote {SPRITES}/part_layout.json")
    print(f"wrote {SPRITES}/ui_theme.json")
    print(f"wrote {REVIEW}/contact.png")


if __name__ == "__main__":
    main(sys.argv[1:])
