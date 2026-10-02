#!/usr/bin/env -S uv run --quiet --with pillow python
"""Can the engine actually reach the art? Today: no. (ASSA-34)

    art/check_client_can_see_art.py

Every other check in this folder judges what a sprite LOOKS like. This one
asks the question underneath all of them, which nobody had asked: whether the
game can load the file at all.

WHY THIS IS RED, AND WHY THAT IS THE POINT
  A Godot project's `res://` is its project folder and nothing above it. The
  project is `client/`; `build.py` writes sheets to `assets/sprites/`, which is
  its sibling. So no script in the client CAN name a sheet, no texture has ever
  been imported there (there is not one `.import` file in the project), and an
  export packs what is under the project folder, so a bundle would not carry
  them either.

  That is eleven sheets, a manifest and four measured checks, and the game has
  never drawn a pixel of any of it. It is not a failure of ordering - graphics
  come last by this repo's rules and the client is still on step 6 of the demo
  loop - but "we will wire the art up later" had a wall in front of it that
  nobody had priced, including me. I shipped `[importer_defaults]` into
  `project.godot` (ASSA-14) for textures that cannot arrive, and I verified
  that work by copying a sprite in BY HAND, which is exactly how I managed not
  to notice.

  So this file is the finding, kept where it cannot be forgotten, and it stays
  as the guard once the layout question (ASSA-34) is answered either way. It is
  deliberately NOT in CI while it is red.

WHAT IT CHECKS, and both halves have a lever that reproduces their own cause:
  1. REACHABLE. Every sheet named by `manifest.json` resolves to a path under
     the Godot project root. Lever: `CLIENT_ROOT=<other dir>` moves the root,
     which is the cause, and every sheet must then be reported unreachable.
  2. PACKED. No export preset's `exclude_filter` catches it, and if a preset
     sets a non-empty `include_filter`, the sheet matches it. A file that lives
     in the project and is filtered out of the bundle is the same failure one
     step later, and it fails silently in a build rather than in the editor.
     Lever: `CLIENT_EXCLUDE=assets/*` adds that pattern to every preset.

It reads the manifest from wherever it is - next to `art/` today, under the
client if ASSA-34 moves it - and says which one it used, so the move does not
need a second edit here.
"""
import fnmatch
import json
import os
import sys

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
CLIENT = os.environ.get("CLIENT_ROOT") or os.path.join(ROOT, "client")
EXTRA_EXCLUDE = os.environ.get("CLIENT_EXCLUDE")

if os.environ.get("CLIENT_ROOT"):
    print("[RED LEVER] Godot project root forced to %r; every sheet MUST be\n"
          "            reported unreachable." % CLIENT)
if EXTRA_EXCLUDE:
    print("[RED LEVER] %r added to every preset's exclude_filter; any sheet it\n"
          "            matches MUST be reported as not packed." % EXTRA_EXCLUDE)

# The manifest is the list of what ships. Searched rather than hard-coded, so
# that moving the output (ASSA-34, option A) needs no edit here. The INSIDE one
# wins if both exist: that is the post-move state, and a check that kept
# grading the old copy after a move would pass while the game shipped nothing.
CANDIDATES = [os.path.join(CLIENT, "assets", "sprites"),
              os.path.join(ROOT, "assets", "sprites")]


def find_manifest():
    for d in CANDIDATES:
        p = os.path.join(d, "manifest.json")
        if os.path.exists(p):
            return d, p
    raise SystemExit("no manifest.json in any of:\n  " + "\n  ".join(CANDIDATES))


def presets():
    """`(name, include_filter, exclude_filter)` per export preset.

    Parsed with string work rather than configparser: Godot's .cfg has
    `[preset.0]` and `[preset.0.options]` sections whose keys repeat, and the
    only two keys this needs are plain quoted strings."""
    path = os.path.join(CLIENT, "export_presets.cfg")
    if not os.path.exists(path):
        raise SystemExit("check_client_can_see_art.py: no %s" % path)
    out, cur = [], None
    for line in open(path):
        line = line.strip()
        if line.startswith("[preset.") and not line.endswith(".options]"):
            cur = {"name": line[1:-1], "include": "", "exclude": ""}
            out.append(cur)
        elif cur is not None and line.startswith("name="):
            cur["name"] = line.split("=", 1)[1].strip().strip('"') or cur["name"]
        elif cur is not None and line.startswith("include_filter="):
            cur["include"] = line.split("=", 1)[1].strip().strip('"')
        elif cur is not None and line.startswith("exclude_filter="):
            cur["exclude"] = line.split("=", 1)[1].strip().strip('"')
    if not out:
        raise SystemExit("check_client_can_see_art.py: no presets in %s" % path)
    return out


def globs(s):
    return [g.strip() for g in s.split(",") if g.strip()]


def main():
    sprites, manifest_path = find_manifest()
    man = json.load(open(manifest_path))
    files = sorted({man[a]["sheet"] for a in man} | {"manifest.json"})
    print("manifest: %s" % os.path.relpath(manifest_path, ROOT))
    print("Godot project root: %s" % os.path.relpath(CLIENT, ROOT))
    print("%d files the client would need:" % len(files))

    ok = True
    reachable = []
    for f in files:
        full = os.path.abspath(os.path.join(sprites, f))
        inside = os.path.commonpath([full, os.path.abspath(CLIENT)]) == os.path.abspath(CLIENT)
        if inside:
            rel = os.path.relpath(full, CLIENT)
            reachable.append((f, rel))
            print("  %-18s res://%s" % (f, rel))
        else:
            ok = False
            print("  %-18s UNREACHABLE: %s is outside the project root"
                  % (f, os.path.relpath(full, ROOT)))

    if not reachable:
        print("\n  FAIL: nothing the manifest names is inside the Godot project, so\n"
              "  no script can load it and no export can pack it. See ASSA-34: the\n"
              "  sheets have to live under the project folder, because res:// does\n"
              "  not go up. This is the state the check was written against.")
        return 1

    for p in presets():
        inc, exc = globs(p["include"]), globs(p["exclude"]) + globs(EXTRA_EXCLUDE or "")
        for f, rel in reachable:
            hit = next((g for g in exc if fnmatch.fnmatch(rel, g)), None)
            if hit:
                ok = False
                print("  FAIL: preset %r excludes %s via %r. It would be in the\n"
                      "  project and missing from the bundle, which is a failure you\n"
                      "  only meet in an exported build." % (p["name"], rel, hit))
            elif inc and not any(fnmatch.fnmatch(rel, g) for g in inc):
                ok = False
                print("  FAIL: preset %r has a non-empty include_filter and %s does\n"
                      "  not match it." % (p["name"], rel))
        print("preset %-22s include=%r exclude=%r" % (p["name"], p["include"], p["exclude"]))

    print("\nVERDICT: %s" % ("GREEN" if ok else "RED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
