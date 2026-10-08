"""WHICH SHIPPED ART A REVIEW SHEET COMPOSITED, stamped into it as it draws (ASSA-144).

    import review_sources

    with review_sources.recording():
        ...open shipped sheets, draw...
    img.save(OUT, pnginfo=review_sources.png_info())

    python3 art/review_sources.py assets/review/*.png      # is this sheet current?

WHY THIS EXISTS. `assets/review/` holds nine committed PNGs and `sim-game/CLAUDE.md` tells
everyone to judge the art off one of them. A sheet does not evaporate at the end of a wake-up:
it sits in the repo and the next reader takes it as current. The pack sheet's slot plate was
`#889868` while the shipped ground's median had moved to `#879A66` -- the sheet predated the
ground re-render and nothing could say so. Maren's ruling on ASSA-144: an artefact used as
evidence must say what it is evidence ABOUT.

NOT A HASH OF THE SHEET'S OWN PIXELS, and Cove's reasoning for that is the design. Hashing the
output turns red on every legitimate re-render, "and a check that cries wolf is a check that
gets regenerated blind". So the stamp carries the identity of the SOURCES. Re-drawing a sheet
from unchanged art reproduces the same stamp; moving the art is what turns it red.

WHY IT RECORDS RATHER THAN DECLARES. Nine sheets are drawn by nine scripts, and the obvious
design -- each one naming the art it reviews -- is a list someone has to keep in step with the
code, which is the failure mode this whole item is about one level up. Eight of the nine reach
shipped art through a single path constant (`SPRITES` / `SPR`, both `client/assets/sprites`),
so the honest answer to "which art does this sheet review" is **the files it actually opened**.
`recording()` observes the opens, so the stamp is a fact about the run instead of a claim about
it. Adding a sprite to a sheet needs no edit here.

HOW THE OPENS ARE SEEN. Every shipped-art read in this pipeline is `json.load(open(...))` or
`Image.open(...)`, and Pillow opens a path with `builtins.open` too, so one patch sees them
all. `io.open` is patched as well: it is a SEPARATE module attribute bound to the same
function, so patching `builtins` alone would miss `pathlib.Path.read_bytes()` -- nothing in the
pipeline reads art that way today and the day someone does, it should not silently drop out of
the stamp. `tools/test_review_sources.py` asserts all four patterns are caught, including that
one, because "the patch covers it" is exactly the sort of thing I have been wrong about by
reading the source instead of asking.

WRITES ARE NOT SOURCES. `build.py` packs sheets INTO `client/assets/sprites/` and then reads
them back to draw the contact sheet; only the reads are recorded, or a generator would end up
stamping its own output as the art it reviewed.

AN EMPTY STAMP IS A REAL ANSWER, NOT A MISSING ONE. `design_row_sheet.py` composites no shipped
art at all (it draws an engine layout), so it stamps `{}`: this sheet cannot go stale against
the art because it does not depend on it. That is why the check distinguishes ABSENT (no chunk
-- the sheet predates stamping and cannot vouch for itself) from EMPTY (a run that opened
nothing). Guessing which one a bare sheet meant is how a stale picture gets a clean bill.
"""
import hashlib
import json
import os

from png_text import read_text

#: The `tEXt` keyword. A sibling of `pack_words.KEY` on purpose: two differently-keyed claims
#: ride the same sheets, and `assets/review/pack_icons.png` carries both.
KEY = "assay-review-sources"

ART = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ART)
#: Shipped art: the only tree whose files count as sources. Review sheets are deliberately
#: outside the Godot project (see `build.py`), so a sheet reading a sheet is not a source.
SPRITES = os.path.realpath(os.path.join(ROOT, "client", "assets", "sprites"))

#: relpath under SPRITES -> sha256 of the bytes on disk when it was opened.
_seen = {}
_depth = 0

#: The real `open`, captured at import time -- before any patching can have happened, because
#: `recording()` cannot run until this module is imported. Digesting a file through the patched
#: `open` would recurse into the recorder on every read.
_ORIGINAL_OPEN = open


def _real_open(path):
    """Read a file without going through whatever `open` is currently patched to."""
    with _ORIGINAL_OPEN(path, "rb") as fh:
        return fh.read()


def digest(path):
    """The identity of one shipped file: sha256 of its bytes, truncated.

    Truncated because the stamp rides inside a PNG chunk and 16 hex digits is already far past
    anything this pipeline could collide by accident; the check prints these, so they are read
    by people as well as compared.
    """
    return hashlib.sha256(_real_open(path)).hexdigest()[:16]


def _is_read(mode):
    return not any(c in mode for c in "wax+")


def _record(path, mode):
    """Note a read of a shipped-art file. Anything else is ignored."""
    if not _is_read(mode):
        return
    try:
        full = os.path.realpath(path)
    except (TypeError, ValueError):
        return
    if not full.startswith(SPRITES + os.sep):
        return
    rel = os.path.relpath(full, SPRITES)
    if rel in _seen:
        return
    try:
        _seen[rel] = hashlib.sha256(_real_open(full)).hexdigest()[:16]
    except OSError:
        # An open that is about to fail is not a source. Let the caller's own error stand
        # rather than turning a missing sprite into an error from the stamping code.
        pass


class recording:
    """Record shipped-art reads for the duration of the block.

    Re-entrant and additive: `build.py` draws its contact sheet inside one block, and a script
    that opens the same file twice records it once. `reset()` if you ever draw two sheets in
    one process -- nothing does today.
    """

    def __enter__(self):
        global _depth
        _depth += 1
        if _depth == 1:
            import builtins
            import io
            self._saved = (builtins.open, io.open)

            real = builtins.open

            def watched(file, mode="r", *a, **kw):
                _record(file, mode)
                return real(file, mode, *a, **kw)

            builtins.open = watched
            io.open = watched
        return self

    def __exit__(self, *exc):
        global _depth
        _depth -= 1
        if _depth == 0:
            import builtins
            import io
            builtins.open, io.open = self._saved
        return False


def start():
    """Record for the rest of the process. For the sheet scripts that read art at import time.

    Four of the generators load `manifest.json` at module level and open the sheets it names
    deep inside a drawing loop, so there is no block to wrap: the reads are the whole script.
    These are one-shot scripts that draw one sheet and exit, so a patch that is never lifted
    costs nothing and keeps the call sites to one line. `build.py` is the exception and uses
    `recording()`, because it also PACKS art and only its contact-sheet pass is a review.
    """
    recording().__enter__()


def reset():
    _seen.clear()


def recorded():
    """What has been recorded so far: relpath under `client/assets/sprites` -> digest."""
    return dict(_seen)


def stamp_of(sources):
    """The canonical text written into the PNG. Stable key order, no whitespace, no clock.

    Deterministic for the same inputs, so re-drawing an unchanged sheet from unchanged art
    produces a byte-identical PNG -- the same property `pack_words` protects, and the reason
    `git status` after a build stays readable.
    """
    return json.dumps(sources, sort_keys=True, separators=(",", ":"))


def read_stamp(path):
    """The sources stamp out of a PNG, or None when it carries none. See `png_text`."""
    return read_text(path, KEY)


def png_info(info=None, sources=None):
    """A `PngInfo` carrying the stamp, for `Image.save(..., pnginfo=...)`. Needs Pillow.

    Pass an existing `PngInfo` to add this claim beside another one: `pack_icon_sheet.py`
    already stamps the words it drew (`pack_words.png_info`), and both keys ride that sheet.
    """
    if info is None:
        from PIL import PngImagePlugin
        info = PngImagePlugin.PngInfo()
    info.add_text(KEY, stamp_of(recorded() if sources is None else sources))
    return info


# ---------------------------------------------------------------- reading a sheet back

#: Verdicts, worst first. The check and the CLI share them so one wording covers both.
CURRENT, EMPTY, STALE, ABSENT = "CURRENT", "NO SOURCES", "STALE", "UNSTAMPED"


def verdict(sheet):
    """Is this committed sheet current against the shipped art it recorded?

    Returns `(verdict, lines)`, where lines NAME what moved rather than reporting that
    something did -- the difference between a check someone acts on and one they regenerate
    blind.
    """
    stamped = read_stamp(sheet)
    if stamped is None:
        return ABSENT, ["carries no `%s` stamp, so it cannot say which art it reviews.\n"
                        "      Regenerate it; that is what writes the stamp." % KEY]
    try:
        sources = json.loads(stamped)
        if not isinstance(sources, dict):
            raise ValueError("not an object")
    except ValueError as why:
        return ABSENT, ["carries a `%s` stamp that is not readable (%s)." % (KEY, why)]
    if not sources:
        # **THIS LINE USED TO BE A CLEAN BILL AND IT WAS NOT ENTITLED TO BE ONE** (ASSA-144 box
        # 4). It read "composited no shipped art, so there is nothing for it to go stale
        # against" -- stated as a fact about the picture, where the stamp only supports a fact
        # about the RECORDING. A present, empty stamp is what a generator run outside
        # `recording()` writes, which is how Cove reached one, so the two readings are
        # indistinguishable FROM THIS FILE. Box 4 asks whether a reader can tell a stale sheet
        # from a current one without git archaeology; where they cannot, the honest output says
        # so rather than reassuring them.
        return EMPTY, ["recorded an EMPTY source list, and this file cannot say which of two\n"
                       "      things that means: a sheet that composites no shipped art, or a\n"
                       "      generator that drew it outside `review_sources.recording()`.\n"
                       "      `art/check_review_sources.py` decides, by asking whether the\n"
                       "      generator can name the shipped-art path at all."]
    moved = []
    for rel in sorted(sources):
        full = os.path.join(SPRITES, rel)
        if not os.path.exists(full):
            moved.append("client/assets/sprites/%s is GONE; the sheet drew it at %s."
                         % (rel, sources[rel]))
            continue
        now = digest(full)
        if now != sources[rel]:
            moved.append("client/assets/sprites/%s moved: the sheet drew %s, the shipped art\n"
                         "      is now %s." % (rel, sources[rel], now))
    if moved:
        return STALE, moved
    return CURRENT, ["%d shipped file(s) unchanged since it was drawn: %s"
                     % (len(sources), ", ".join(sorted(sources)))]


def main(argv):
    """Answer box 4 of ASSA-144: can a reader tell, from the sheet alone, if it is current?"""
    if not argv:
        review = os.path.join(ROOT, "assets", "review")
        argv = [os.path.join(review, f) for f in sorted(os.listdir(review))
                if f.endswith(".png")]
    worst = 0
    for sheet in argv:
        state, lines = verdict(sheet)
        print("%-11s %s" % (state, os.path.relpath(sheet, ROOT)))
        for line in lines:
            print("    - %s" % line)
        worst = max(worst, {CURRENT: 0, EMPTY: 0, STALE: 1, ABSENT: 1}[state])
    return worst


if __name__ == "__main__":
    import sys
    sys.path.insert(0, ART)
    sys.exit(main(sys.argv[1:]))
