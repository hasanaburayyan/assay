#!/usr/bin/env python3
"""List an exported Godot .pck from its own bytes. (ASSA-34 acceptance 2)

    art/list_pck.py <pack.pck>

NOT A GATE, and not in CI: it needs an export to exist, and exporting needs
Godot plus (for a real build) its templates. It is the instrument behind the
claim "the sheets actually ship", which is a different claim from
`check_client_can_see_art.py`'s "the sheets are reachable and not filtered
out". That check reads paths and presets; this reads the bundle.

To produce a pack to point it at:

    make client-lib
    cd client && godot --headless --import && godot --headless --import
    godot --headless --export-pack macOS /tmp/assay.pck
    cd .. && art/list_pck.py /tmp/assay.pck

`--export-pack` needs NO export templates, which is why this is runnable on a
dev machine that has only the editor.

WHAT ARRIVES IN THE PACK, because it is not what you would guess: the source
`.png` files are NOT in there. Godot ships the IMPORTED texture as
`.godot/imported/<name>.png-<hash>.ctex` and the `assets/sprites/<name>.png.import`
sidecar is the remap that makes `res://assets/sprites/<name>.png` resolve to
it. So a pack with no `.png` in it is correct and loadable; a pack with no
`.ctex` would be the failure.

TWO PARSER BUGS I MADE HERE, both of which produced a confident wrong answer:
  1. Pack format 3 with flags=2 keeps its file INDEX at the END of the pack
     (`dir_offset`), not after the header. Reading the format-1 layout found
     the count in a reserved field and reported "0 files" for a pack Godot had
     plainly just filled. The parser was lying, not the pack.
  2. flags=2 also means every entry's offset is RELATIVE to `file_base`.
     Dropping that 112-byte base made every single md5 mismatch, which looks
     exactly like a corrupt bundle and is in fact an instrument reading the
     wrong 112 bytes off the front of every file.
Hence the two self-checks below: the index must consume exactly to EOF, and
every entry's bytes must match the md5 the pack itself stored. If either of
those fails, distrust this script before distrusting the bundle.
"""
import hashlib
import struct
import sys


def read(path):
    d = open(path, "rb").read()
    if d[:4] != b"GDPC":
        raise SystemExit("%s is not a Godot pack (magic %r)" % (path, d[:4]))
    pv, vmaj, vmin, vpat, flags = struct.unpack_from("<5I", d, 4)
    file_base, dir_offset = struct.unpack_from("<2Q", d, 24)
    print("%s: pack format %d, engine %d.%d.%d, flags %d"
          % (path, pv, vmaj, vmin, vpat, flags))
    print("file data from %d, index at %d, pack is %d bytes"
          % (file_base, dir_offset, len(d)))
    o = dir_offset
    n, = struct.unpack_from("<I", d, o); o += 4
    rows = []
    for _ in range(n):
        pl, = struct.unpack_from("<I", d, o); o += 4
        p = d[o:o + pl].rstrip(b"\0").decode(); o += pl
        off, size = struct.unpack_from("<QQ", d, o); o += 16
        md5 = d[o:o + 16]; o += 16
        fl, = struct.unpack_from("<I", d, o); o += 4
        blob = d[off + file_base:off + file_base + size]
        rows.append((p, size, blob, md5, fl))
    # Self-check 1: an index that stops short means the entry layout is wrong.
    if o != len(d):
        raise SystemExit("index ended at %d, not EOF %d: this parser has the "
                         "entry layout wrong" % (o, len(d)))
    return rows


def main(argv):
    if len(argv) != 1:
        raise SystemExit(__doc__.strip().splitlines()[2].strip())
    rows = read(argv[0])
    print("%d files, index consumed exactly to EOF\n" % len(rows))

    bad = 0
    for p, size, blob, md5, fl in rows:
        if len(blob) != size or hashlib.md5(blob).digest() != md5:
            bad += 1
            print("  BAD BYTES %s" % p)
    # Self-check 2: see parser bug 2 in the docstring.
    if bad:
        raise SystemExit("%d of %d entries do not match the md5 the pack stored. "
                         "Suspect this script before the bundle." % (bad, len(rows)))
    print("all %d entries match the md5 the pack itself stored\n" % len(rows))

    groups = [("sheet sources and remaps", lambda p: p.startswith("assets/sprites/")),
              ("imported textures (what actually draws)", lambda p: p.startswith(".godot/imported/")),
              ("everything else", lambda p: not p.startswith("assets/sprites/")
               and not p.startswith(".godot/imported/"))]
    for title, pred in groups:
        hits = sorted((p, size) for p, size, _, _, _ in rows if pred(p))
        print("--- %s (%d)" % (title, len(hits)))
        for p, size in hits:
            print("  %-62s %8d" % (p, size))
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
