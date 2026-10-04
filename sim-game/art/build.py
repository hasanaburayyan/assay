#!/usr/bin/env -S uv run --quiet --with pillow python
"""Render sprites with Blender and pack them for the client.

    art/build.py            # everything
    art/build.py ore head   # only these assets
    art/build.py --pack     # skip rendering, just repack art/out

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
ORDER = ["ground", "ore", "items", "head", "handle", "frame", "hopper", "spawn", "smelter",
         "player"]


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


def pack(name):
    meta = json.load(open(os.path.join(OUT, name, "asset.json")))
    fw, fh = meta["frame_px"]
    cols = max(r["frames"] for r in meta["rows"])
    sheet = Image.new("RGBA", (cols * fw, len(meta["rows"]) * fh), (0, 0, 0, 0))
    for y, row in enumerate(meta["rows"]):
        for f in range(row["frames"]):
            im = Image.open(os.path.join(OUT, name, f"{row['name']}_{f:02d}.png")).convert("RGBA")
            sheet.alpha_composite(im.resize((fw, fh), Image.LANCZOS), (f * fw, y * fh))
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
    out.save(os.path.join(REVIEW, "contact.png"))


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
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(SPRITES, exist_ok=True); os.makedirs(REVIEW, exist_ok=True)
    if "--pack" not in argv:
        for n in names: render(n)
    manifest_path = os.path.join(SPRITES, "manifest.json")
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}
    for n in names:
        if os.path.exists(os.path.join(OUT, n, "asset.json")):
            manifest[n] = pack(n)
    manifest = {k: manifest[k] for k in ORDER if k in manifest}
    json.dump(manifest, open(manifest_path, "w"), indent=1)
    write_part_contract()
    write_ui_theme()
    contact(manifest)
    print(f"wrote {SPRITES}/manifest.json")
    print(f"wrote {SPRITES}/part_layout.json")
    print(f"wrote {SPRITES}/ui_theme.json")
    print(f"wrote {REVIEW}/contact.png")


if __name__ == "__main__":
    main(sys.argv[1:])
