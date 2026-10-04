"""THE WORDS A PACK ROW CARRIES, written into the review sheet and read back out (ASSA-132).

    from pack_words import stamp_of, read_stamp, KEY

WHY THIS EXISTS. `assets/review/pack_icons.png` shipped for days saying **Frame** on all four
part rows while the client said **Mount** on two of them. Nothing was wrong with the pipeline:
every word in that sheet came from the engine's own buttons. The sheet was simply drawn before
ASSA-103 changed the word and never redrawn -- #157 regenerated `pack_rows.png` and not this
one. A review sheet is the thing people check the game against, so a stale one is worse than
none: it is believed, and it is believed about a game it no longer describes.

A guard INSIDE the generator cannot catch that, because the failure is the generator not being
run. So the generator STAMPS what it drew into the PNG, and `check_pack_row_word.py` asks the
live engine for the same words and compares. The sheet going stale is then a red check that
names the rows, rather than a thing someone notices by chance months later.

WHAT IS IN THE STAMP, AND WHY SO LITTLE. Only the row's kind and the words on its buttons --
the claim the sheet makes IN TEXT. Deliberately not a hash of the pixels: every sprite
re-render would turn it red while the sheet's words were still true, and a check that cries
wolf is a check that gets regenerated blind. The stamp is also deterministic, so regenerating
an unchanged sheet produces a byte-identical PNG.

(The pixels going stale is real -- this sheet's plate was #889868 when the shipped ground's
median had moved to #879A66 -- but it is a different claim with a different fix, and I am not
smuggling it in under a check about words.)

NO PIL ON THE READING SIDE. `tEXt` is a documented PNG chunk and the checks in `art/` run under
CI's bare `python3`, which has no Pillow. Writing it needs Pillow; the sheet scripts already do.
"""
import json
import struct

#: The `tEXt` keyword. Latin-1, <=79 chars, no colon-space weirdness: PNG keywords allow
#: printable Latin-1 and that is all this needs.
KEY = "assay-pack-words"


def rows_words(rows):
    """The (kind, words) claim for every pack row the engine laid out, in row order.

    `kind_of` is the same reader the sheets label their cells with, so the stamp cannot name a
    row something the picture does not (ASSA-118's lesson, one panel further along).
    """
    from ask_layout import kind_of
    return [{"kind": kind_of(r), "words": [str(v) for v in r.get("verbs", [])]} for r in rows]


def stamp_of(rows):
    """The canonical text written into the PNG. Stable key order, no whitespace, no clock."""
    return json.dumps(rows_words(rows), sort_keys=True, separators=(",", ":"))


def read_stamp(path):
    """The stamp text out of a PNG's `tEXt` chunks, or None when the file carries none.

    Hand-parsed rather than Pillow-parsed so a CHECK can read it; see the module docstring.
    """
    with open(path, "rb") as fh:
        blob = fh.read()
    if blob[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    at = 8
    while at + 8 <= len(blob):
        (length,) = struct.unpack(">I", blob[at:at + 4])
        kind = blob[at + 4:at + 8]
        data = blob[at + 8:at + 8 + length]
        if kind == b"tEXt":
            keyword, _, value = data.partition(b"\x00")
            if keyword.decode("latin-1") == KEY:
                return value.decode("latin-1")
        if kind == b"IEND":
            break
        at += 12 + length  # length + type + data + crc
    return None


def png_info(rows):
    """A `PngInfo` carrying the stamp, for `Image.save(..., pnginfo=...)`. Needs Pillow."""
    from PIL import PngImagePlugin
    info = PngImagePlugin.PngInfo()
    info.add_text(KEY, stamp_of(rows))
    return info
