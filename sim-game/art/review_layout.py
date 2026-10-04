"""WHICH CLIENT LAYOUT A REVIEW SHEET DREW, stamped into it as it draws (ASSA-151).

    import review_layout

    LAYOUT = review_layout.load(sys.argv[1], probe="pack_icon_layout.gd")
    img.save(OUT, pnginfo=review_layout.png_info(review_sources.png_info()))

THE HALF OF STALENESS ASSA-144 LEFT OPEN, AND I AM THE ONE WHO LEFT IT. `review_sources.py`
records the shipped ART a sheet composited, which is the right answer for the six sheets that
composite sprites. Two of the nine are pictures of a CLIENT PANEL -- `pack_rows.png` and
`pack_icons.png` -- and their content is `pack_icon_layout.gd`'s answer: row heights, icon
scales, verbs, plate colours, the panel's width. None of that is a sprite, so none of it was in
the stamp:

    CURRENT     assets/review/pack_rows.png
        - 2 shipped file(s) unchanged since it was drawn: items.png, ui_theme.json

Both files are real sources and neither can go stale when a pack row's SCALE moves. Move it and
that sheet goes on saying CURRENT about a panel that no longer exists.

IT WAS NOT BROKEN WHEN I FOUND IT, WHICH IS THE POINT. ASSA-121 moved every pack row to scale
0.5 and both sheets are current -- because I remembered to redraw them in the same PR. Maren's
ruling 3 on ASSA-144 is the argument against leaving it there: *a rule that depends on
remembering is a rule that fails on the wake-up somebody is tired.*

A DIGEST OF THE ANSWER, NOT OF THE FILE. The generators are handed a `/tmp` JSON produced by
piping the probe's stdout, so the bytes on disk carry whatever the pipeline did to them. What
is stamped is the CANONICAL form of the parsed answer (sorted keys, no whitespace), which is
what `check_review_layout.py` can reproduce by re-asking the engine. Measured before it was
built: two runs of the probe print byte-identical JSON (3193 bytes), so the comparison is a
comparison and not a flake.

THE PROBE IS DECLARED BY THE GENERATOR, AND A WRONG DECLARATION IS RED RATHER THAN GREEN. The
generator knows which probe its JSON is supposed to come from; it cannot know which one it
actually came from. So `probe=` is a claim -- and if somebody feeds a sheet a different probe's
answer, the digest will not match the declared probe's answer today and the check says so. The
failure direction is the safe one.

WHY NOT FOLD IT INTO `review_sources`. That module answers "which files did this run open",
and a layout is not a file this run opened: it is an answer a human piped in from a different
process. Two claims, two keys, one sheet -- the same shape as `pack_words.KEY` riding
`pack_icons.png` beside the sources stamp, which is the precedent this follows.
"""
import hashlib
import json

#: The `tEXt` keyword. A sibling of `review_sources.KEY` and `pack_words.KEY`; three
#: differently-keyed claims can ride one sheet.
KEY = "assay-review-layout"

#: probe name -> canonical digest of the answer this process was given. A dict rather than a
#: single value because a sheet drawn from two probes should stamp both; nothing does today.
_given = {}


def canonical(answer):
    """The text a digest is taken over: the parsed answer, sorted, with no whitespace.

    THE FORM IS THE WHOLE RELIABILITY OF THIS. The generator reads a file and the check reads a
    subprocess's stdout, so hashing raw bytes would compare a pipeline against a pipe. Both
    sides parse first and re-spell the same way, so the only thing that can move the digest is
    the layout itself.
    """
    return json.dumps(answer, sort_keys=True, separators=(",", ":"))


def digest(answer):
    """The identity of one layout answer. Truncated like `review_sources.digest`, and for the
    same reason: it rides in a PNG chunk and people read it in the check's output."""
    return hashlib.sha256(canonical(answer).encode("utf-8")).hexdigest()[:16]


def load(path, probe):
    """Read the layout JSON a sheet is drawn from, remembering which probe answered it.

    The one call site each generator needs: it replaces `json.load(open(...))` and the stamp
    follows from it, so a sheet cannot be drawn from a layout it does not record.
    """
    with open(path) as fh:
        answer = json.load(fh)
    remember(probe, answer)
    return answer


def remember(probe, answer):
    _given[str(probe)] = digest(answer)


def recorded():
    return dict(_given)


def stamp_of(layouts=None):
    """The canonical text written into the PNG. Stable order, no clock -- so redrawing a sheet
    from an unchanged layout reproduces a byte-identical PNG, the property `review_sources`
    and `pack_words` both protect."""
    return json.dumps(recorded() if layouts is None else layouts,
                      sort_keys=True, separators=(",", ":"))


def read_stamp(path):
    """The layout stamp out of a PNG, or None when it carries none."""
    from png_text import read_text
    return read_text(path, KEY)


def png_info(info=None, layouts=None):
    """A `PngInfo` carrying this claim, usually wrapped around `review_sources.png_info()`."""
    if info is None:
        from PIL import PngImagePlugin
        info = PngImagePlugin.PngInfo()
    info.add_text(KEY, stamp_of(layouts))
    return info
