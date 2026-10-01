#!/usr/bin/env -S uv run --quiet --with pillow python
"""Render sprites with Blender and pack them for the client.

    art/build.py            # everything
    art/build.py ore drill  # only these assets
    art/build.py --pack     # skip rendering, just repack art/out

Pipeline: assets/<name>.py runs inside Blender and writes raw SSx frames to
art/out/<name>/ plus asset.json. This script downscales them to authoring
size (64 px per tile), packs one sheet per asset into assets/sprites/, writes
manifest.json, and renders assets/sprites/contact.png for review.
"""
import json, os, subprocess, sys, time
from PIL import Image, ImageDraw

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
OUT = os.path.join(ART, "out")
SPRITES = os.path.join(ROOT, "assets", "sprites")
BLENDER = os.environ.get("BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")
SS = 4
# render order = contact sheet order
ORDER = ["ground", "ore", "items", "head", "drill", "spawn", "player"]


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
            # colour-blind check: tier-4 full tile of each kind, side by side
            picks = [r for r in rows if r["name"].endswith("_t4_full_v0")]
            for cvd in ("normal", "protan", "deutan", "tritan"):
                line = Image.new("RGBA", (label_w + len(picks) * (fw + pad) * 2, fh + pad), bg)
                ImageDraw.Draw(line).text((4, 4), f"ore/cvd {cvd}", fill=(220, 220, 220, 255))
                x = label_w
                for r in picks:
                    ry = rows.index(r) * fh
                    fr = sheet.crop((0, ry, fw, ry + fh))
                    if cvd != "normal": fr = simulate_cvd(fr, cvd)
                    line.alpha_composite(fr, (x, 0)); x += fw + pad
                    line.alpha_composite(fr.resize((fw // 2, fh // 2), Image.LANCZOS), (x, fh // 2)); x += fw // 2 + pad
                blocks.append(line)
    W = max(b.width for b in blocks); H = sum(b.height for b in blocks)
    out = Image.new("RGBA", (W, H), bg); y = 0
    for b in blocks:
        out.alpha_composite(b, (0, y)); y += b.height
    out.save(os.path.join(SPRITES, "contact.png"))


def main(argv):
    names = [a for a in argv if not a.startswith("--")] or ORDER
    os.makedirs(OUT, exist_ok=True); os.makedirs(SPRITES, exist_ok=True)
    if "--pack" not in argv:
        for n in names: render(n)
    manifest_path = os.path.join(SPRITES, "manifest.json")
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}
    for n in names:
        if os.path.exists(os.path.join(OUT, n, "asset.json")):
            manifest[n] = pack(n)
    manifest = {k: manifest[k] for k in ORDER if k in manifest}
    json.dump(manifest, open(manifest_path, "w"), indent=1)
    contact(manifest)
    print(f"wrote {SPRITES}/manifest.json and contact.png")


if __name__ == "__main__":
    main(sys.argv[1:])
