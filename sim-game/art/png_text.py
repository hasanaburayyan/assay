"""ONE WALK OVER A PNG'S `tEXt` CHUNKS, for every stamp this pipeline keys into a sheet.

    from png_text import read_text

    read_text("assets/review/pack_icons.png", "assay-pack-words")   # str or None

WHY IT IS ITS OWN FILE. `pack_words.py` (ASSA-132) wrote the first stamp and owned the chunk
walk. ASSA-144 adds a SECOND, differently-keyed claim to the same sheets -- what shipped art
they composited -- and copying twenty lines of chunk arithmetic into it is how this repo has
repeatedly ended up with two readers that can disagree. `png_stdlib.py` says the same thing
about PNG *pixel* decoders in its own docstring; this is that rule applied to the text chunks.

So the walk lives here once, and `pack_words.read_stamp` / `review_sources.read_stamp` are both
thin wrappers that pass their own key.

NO PILLOW ON THE READING SIDE. `tEXt` is a documented PNG chunk and the checks in `art/` run
under CI's bare `python3`, which has no Pillow. Writing a chunk needs Pillow; only the sheet
generators do that, and they already depend on it.

A FILE MAY CARRY SEVERAL `tEXt` CHUNKS WITH DIFFERENT KEYWORDS, which is the whole reason two
claims can ride one sheet: `assets/review/pack_icons.png` holds both keys and each reader finds
its own. Reading stops at the FIRST chunk matching the key asked for -- PNG permits repeats of
a keyword and nothing here writes them, so a duplicate would be a bug upstream, not something
to silently merge.
"""
import struct

_MAGIC = b"\x89PNG\r\n\x1a\n"


def read_text(path, key):
    """The text of the first `tEXt` chunk with this keyword, or None.

    None covers all three of "not a PNG", "no text chunks" and "no chunk with this key": the
    callers all treat those the same way (the stamp cannot be read off the file, so the file
    cannot vouch for itself) and each says so in its own words.
    """
    with open(path, "rb") as fh:
        blob = fh.read()
    if blob[:8] != _MAGIC:
        return None
    at = 8
    while at + 8 <= len(blob):
        (length,) = struct.unpack(">I", blob[at:at + 4])
        kind = blob[at + 4:at + 8]
        data = blob[at + 8:at + 8 + length]
        if kind == b"tEXt":
            keyword, _, value = data.partition(b"\x00")
            if keyword.decode("latin-1") == key:
                return value.decode("latin-1")
        if kind == b"IEND":
            break
        at += 12 + length  # length + type + data + crc
    return None
