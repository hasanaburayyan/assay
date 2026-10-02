#!/usr/bin/env -S uv run --quiet --with pillow python
"""Can the engine actually reach the art? Now: yes, and this is what holds it. (ASSA-34)

    art/check_client_can_see_art.py

Every other check in this folder judges what a sprite LOOKS like. This one
asks the question underneath all of them, which nobody had asked: whether the
game can load the file at all.

WHAT IT FOUND, AND WHY IT WAS RED FOR A DAY
  A Godot project's `res://` is its project folder and nothing above it. The
  project is `client/`; `build.py` used to write sheets to `assets/sprites/`,
  which is its SIBLING. So no script in the client COULD name a sheet, no
  texture had ever been imported there (not one `.import` file existed), and
  an export packs what is under the project folder, so a bundle carried none
  of it either.

  That was eleven files, a manifest and four measured checks, and the game had
  never drawn a pixel of any of it. Not a failure of ordering - graphics come
  last by this repo's rules - but "we will wire the art up later" had a wall
  in front of it that nobody had priced, including me. I shipped
  `[importer_defaults]` into `project.godot` (ASSA-14) for textures that could
  not arrive, and I verified that work by copying a sprite in BY HAND, which
  is exactly how I managed not to notice.

  Marlow ruled option A and `build.py` now writes to `client/assets/sprites/`.
  This file stops being the finding and becomes the guard: it is in CI, and it
  is what fails if the sheets ever drift back out of the project.

WHAT IT CHECKS, and both halves have a lever that reproduces their own cause:
  1. REACHABLE. Every sheet named by `manifest.json` resolves to a path under
     the Godot project root. Lever: `CLIENT_ROOT=<other dir>` moves the
     boundary the sheets are measured against, which is the cause, and every
     sheet must then be reported unreachable.
  2. PACKED. No export preset's `exclude_filter` catches it, and if a preset
     sets a non-empty `include_filter`, the sheet matches it. A file that lives
     in the project and is filtered out of the bundle is the same failure one
     step later, and it fails silently in a build rather than in the editor.
     Lever: `CLIENT_EXCLUDE=assets/*` adds that pattern to every preset.

ONE THING THE MOVE BROKE IN THIS FILE, which is worth writing down because the
lever still exited non-zero and I nearly ticked it off. `CLIENT_ROOT` used to
be the project directory for EVERY purpose: the boundary, the manifest search
and where `export_presets.cfg` is read from. That was harmless while the
manifest lived outside the client, because forcing the root elsewhere left the
manifest exactly where it was. After the move the manifest lives INSIDE the
client, so `CLIENT_ROOT=/tmp` made the search miss it entirely and the check
died with "no manifest.json" - red, but for a missing file rather than for an
unreachable sheet. A lever that reproduces the wrong cause is not a lever.
So the project directory and the BOUNDARY are now two separate things: the
manifest and the presets always come from the real `client/`, and `CLIENT_ROOT`
moves only the line that sheets are judged against.

It reads the manifest from wherever it is - inside the client since the move,
beside `art/` before it - and says which one it used. The inside copy wins, so
if someone restores the old directory the check still grades what ships.
"""
import fnmatch
import json
import os
import sys

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
# The project itself: where the manifest and the export presets are read from.
# Not lever-controlled, see the docstring's last paragraph.
CLIENT = os.path.join(ROOT, "client")
# The line sheets are judged against. This is what the lever moves.
BOUNDARY = os.environ.get("CLIENT_ROOT") or CLIENT
EXTRA_EXCLUDE = os.environ.get("CLIENT_EXCLUDE")

if os.environ.get("CLIENT_ROOT"):
    print("[RED LEVER] boundary forced to %r while the project stays %r; every\n"
          "            sheet MUST be reported unreachable."
          % (BOUNDARY, os.path.relpath(CLIENT, ROOT)))
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
    if BOUNDARY != CLIENT:
        print("boundary (lever):   %s" % BOUNDARY)
    print("%d files the client would need:" % len(files))

    ok = True
    reachable = []
    for f in files:
        full = os.path.abspath(os.path.join(sprites, f))
        inside = os.path.commonpath([full, os.path.abspath(BOUNDARY)]) == os.path.abspath(BOUNDARY)
        if inside:
            rel = os.path.relpath(full, BOUNDARY)
            reachable.append((f, rel))
            print("  %-18s res://%s" % (f, rel))
        else:
            ok = False
            print("  %-18s UNREACHABLE: %s is outside the project root"
                  % (f, os.path.relpath(full, ROOT)))

    if not reachable:
        print("\n  FAIL: nothing the manifest names is inside the Godot project, so\n"
              "  no script can load it and no export can pack it. The sheets have to\n"
              "  live under the project folder, because res:// does not go up. This\n"
              "  was the state ASSA-34 found and fixed; if you are seeing it for real\n"
              "  rather than through the CLIENT_ROOT lever, the output has drifted\n"
              "  back out of client/assets/sprites/.")
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
