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

#: THE ONE KEY INSIDE THE STAMP THAT IS NOT A PROBE: a sheet saying out loud that it is a picture
#: of ART, with no client layout behind any part of it and so nothing to go stale against.
#:
#: **IT EXISTS BECAUSE SILENCE WAS THE DEFAULT** (QA, CO-6). `check_review_layout.py` printed
#: `NO LAYOUT` for seven of nine committed sheets and exited 0, so "this sheet is art" and "this
#: sheet forgot to record the layout it was drawn from" were the same state -- and two of those
#: seven turned out to be the second thing. A declaration cannot be fallen into.
#:
#: It can never be mistaken for a probe, and that is CHECKED rather than agreed: a probe is a
#: `.gd` file and [`classify`] refuses any other key.
ART_ONLY = "art-only"

#: probe name -> canonical digest of the answer this process was given, or `ART_ONLY` -> the
#: reason. A dict rather than a single value because a sheet drawn from two probes should stamp
#: both; nothing does today.
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


def art_only(reason):
    """The stamp for a sheet that is a picture of ART: no engine layout answered for any of it.

    The counterpart of [`load`] and the other way a generator may satisfy the check. It takes a
    REASON and not a flag because the reason is the whole value of the declaration: the check
    prints it, so the next person reads why this sheet is exempt instead of inferring it from
    the exemption's existence.

    **IT RETURNS THE STAMP INSTEAD OF RECORDING IT, WHICH THE FIRST VERSION GOT WRONG AND A RUN
    CAUGHT.** Written as `_given[ART_ONLY] = reason` it was module STATE, and these generators
    import each other -- `pack_icon_kinds.py` reads `species_probe.DISTINCT`, so importing it
    ran its declaration -- which meant whichever call ran LAST owned the stamp. Three sheets
    came out carrying `species_probe.py`'s sentence about itself, and `pack_icon_kinds.png`
    came out declaring art-only AND a layout at once. A claim about one sheet does not belong
    in state every other sheet's process shares: it is passed at the save, beside the picture
    it is about.

    Pass it as `png_info(..., layouts=art_only(...))`. A generator still may not say both --
    [`classify`] refuses a stamp carrying a reason and a probe, which is what caught this.
    """
    return {ART_ONLY: str(reason)}


def classify(layouts):
    """Which claim a parsed stamp is making: `(ART_ONLY, reason)` or `("layout", {probe: digest})`.

    ONE DEFINITION FOR THE WRITER AND THE READER. The generators write these stamps and
    `check_review_layout.py` reads them, so the shape rules live here and neither side gets its
    own opinion about what a stamp means.

    Raises `ValueError` for a stamp that is neither or both, which the check turns into NO
    VERDICT: an unreadable declaration must not be read as the harmless one.
    """
    if not isinstance(layouts, dict) or not layouts:
        raise ValueError("not a non-empty object")
    reason = layouts.get(ART_ONLY)
    probes = {k: v for k, v in layouts.items() if k != ART_ONLY}
    if reason is not None and probes:
        raise ValueError(
            "declares both %r and the layout(s) %s. A sheet is a picture of art or of a "
            "layout; it cannot be exempt from a thing it records" % (ART_ONLY, sorted(probes)))
    if reason is not None:
        if not str(reason).strip():
            raise ValueError("declares %r with no reason" % ART_ONLY)
        return ART_ONLY, str(reason)
    # EVERY OTHER KEY MUST LOOK LIKE A PROBE, so a future declaration key cannot land in here
    # and be silently re-asked as a probe -- `answer_now` would call it NO VERDICT, which is
    # safe, but it would be the wrong sentence about the wrong problem.
    odd = sorted(k for k in probes if not str(k).endswith(".gd"))
    if odd:
        raise ValueError("names %s, which is neither a probe (`*.gd`) nor %r" % (odd, ART_ONLY))
    return "layout", probes


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
