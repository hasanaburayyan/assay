extends SceneTree
## CI: gated
## THE CLIENT'S ONE THEME, GENERATED RATHER THAN DRAWN (ASSA-116 box 1).
##
##   godot --headless --path . --script res://tools/build_theme.gd
##
## Writes `res://theme/assay.tres`, which `project.godot` names as `gui/theme/custom` -- so it
## reaches EVERY Control in the client without a single node opting in, including the ones built in
## code by `main.gd` and the ones a future screen has not been written yet.
##
## WHY A GENERATOR AND NOT A HAND-EDITED `.tres`. The same rule the art pipeline runs on (`art/`:
## "sprites are generated, never hand-edited"), for the same reason. A theme is forty small numbers
## that have to agree with each other; as a resource file those numbers are unreviewable and drift
## one inspector click at a time. Here the scale is arithmetic, the palette has one source, and a
## reviewer reads intent instead of diffing floats.
##
## THE PALETTE IS `AssayHud`'S, NOT A SECOND ONE. `hud.gd` already decides what this game's surfaces
## look like -- `MAP_BG`, `status_color`, and a WCAG contrast pair (`relative_luminance`,
## `contrast_ratio`) written for the species glyphs. A theme that invented its own greys would be the
## ASSA-43/52 defect in paint: two vocabularies for one thing, free to disagree. So the panel colour
## is derived from the map's background, and every text colour is checked against the surface it is
## actually drawn on using the function already in the repo.
##
## **AND THAT CHECK IS THE POINT, because a theme is otherwise unfalsifiable.** Taste cannot fail a
## test. Contrast can: `MIN_CONTRAST` is the WCAG AA threshold for body text, and this script
## REFUSES TO WRITE A THEME whose own text would fail it. The failure mode it exists to stop is the
## ordinary one -- somebody nudges a grey two points darker to make a screenshot look calmer, and the
## readout nobody tests becomes unreadable for the players who most need it.
##
## Prints `THEME BUILT` LAST and only on success, because Godot exits 0 even on a compile error.

const OUT := "res://theme/assay.tres"
## WCAG 2.1 AA for body text. The repo already computes this ratio; this is the line it has to clear.
const MIN_CONTRAST := 4.5
## Muted text is still text. AA large-text (3.0) would let a 14px readout through, so it is held to
## the same bar as body: "secondary" describes importance, never legibility.
const MIN_MUTED_CONTRAST := 4.5
## THE TWO INKS MUST STAY TELLABLE APART (ASSA-152 box 4, Maren).
##
## Her constraint on the fix: *"the ratio is not bought by moving INK_MUTED towards INK -- two inks
## that stop being distinguishable would trade a legibility defect for the loss of the hierarchy
## that tells a player what to read first."* The cheap way to pass a contrast floor is to brighten
## the dimmer ink until it is the brighter one, and every check above would go green while the
## column lost the thing that says which line to read.
##
## MEASURED, NOT CHOSEN: `INK` against `INK_MUTED` is **1.80:1** today. The floor is 1.5 so an
## ordinary retune of either ink does not trip it and a COLLAPSE does. It is deliberately not held
## near 1.80 -- a guard that fires on every nudge gets raised rather than obeyed.
const MIN_INK_SEPARATION := 1.5

## **THE NON-TEXT FLOOR, FOR THE ONE MARK IN THIS THEME THAT IS A FACT RATHER THAN A WORD**
## (ASSA-288; Maren's rule 3 on ASSA-276 move 3, 2026-10-08).
##
## Her ruling: *"THE AXIS IS THE FACT, NOT THE CONTAINER, AND YOURS IS INVISIBLE ... Floor: track >=
## 3:1 against the plate behind it (the non-text floor; 4.5:1 still holds for text)."* The track I
## drew in the mock was `RAISED` on `SURFACE`, which she measured at **1.27:1** -- a floating segment
## whose axis you cannot see is a block at an arbitrary place.
##
## 3.0 and not 4.5 because an axis is not text; it is the same bar WCAG sets for graphical objects.
## It lives HERE rather than in `track.gd` so the number is refused at build time like every other
## contrast in this file, instead of being a sentence in a docstring that a palette nudge outlives.
const MIN_AXIS_CONTRAST := 3.0

# ---------------------------------------------------------------------------
# THE TYPE SCALE. Four sizes, and the reason there are four is that `main.gd` currently reaches for
# 12, 13 and 19 by hand at eight separate call sites, which is how a screen ends up with no scale at
# all. Named here, they can be used by name.
const DISPLAY := 20  # the bench verdict, SAFE / UNCERTAIN / WILL BREAK -- the one word to read first
const HEADING := 15  # section headings: make, you, do, bench, rocks, cursor, last tick
const BODY := 13  # readouts and rows
const SMALL := 11  # dense secondary lines, and the toggles that name their own key

# THE PALETTE. Two surfaces and three inks, which is as much as this screen needs.
## The panel, lifted off the map rather than matched to it: `AssayHud.MAP_BG` is what the world is
## drawn on, and a panel at the same value would have no edge without a border to draw one.
const SURFACE := Color(0.145, 0.157, 0.188)
## Raised: buttons and fields, so a thing you can press is lighter than the thing it sits on.
const RAISED := Color(0.208, 0.224, 0.263)
const BORDER := Color(0.290, 0.310, 0.360)
const INK := Color(0.898, 0.914, 0.945)
const INK_MUTED := Color(0.655, 0.690, 0.745)
## The one accent, borrowed from `AssayHud.status_color`'s "joined" green so a focused field and a
## good status are the same colour rather than two opinions about success.
const ACCENT := Color(0.50, 0.90, 0.55)

## **THE INK THAT GOES ON TOP OF THE ACCENT** (ASSA-224 / Maren's Gap 1). The primary button is a
## filled accent rectangle, which is a surface this theme never had before, and `INK` on it would be
## pale-on-pale. It is `SURFACE` rather than a new colour because the palette already owns that value
## and the result reads as the panel punched out of the accent rather than as a seventh grey.
##
## NOT TAKEN ON TRUST: it is a pair in `_contrast_problems` like every other ink-on-surface here, so
## the build refuses the theme if this is ever nudged under 4.5:1.
const ON_ACCENT := SURFACE

## **THE AXIS A READING IS A POSITION ON** (ASSA-288). `BORDER` itself is only **1.80:1** against
## `SURFACE` and `RAISED` is **1.27:1**, so neither of the two greys this palette already owns can
## carry Maren's 3:1 -- and brightening the axis past this point starts eating the one thing drawn ON
## it, because a rough mark is `INK_MUTED` and the gap between them closes from both sides.
##
## DERIVED, NOT A SEVENTH GREY: `lightened` is this file's own idiom for a related surface (the
## button's hover fill and the scrollbar's grabber are both derived the same way), so the axis moves
## with the palette instead of pinning it. The lift is the smallest round step that clears the floor
## with room -- **3.48:1** today against a 3.0 bar -- for the same reason `MIN_INK_SEPARATION` is not
## held near its measured value: a guard that fires on every nudge gets raised rather than obeyed.
##
## A FUNCTION AND NOT A `const`, because GDScript will not fold `Color.lightened` at parse time. The
## alternative was writing the result out as a literal `Color(0.4675, 0.4825, 0.52)`, which is the
## seventh grey this comment says it is not: three numbers nobody can check against `BORDER` without
## doing the arithmetic by hand. Derived at build time is the honest form.
const AXIS_LIFT := 0.25


static func axis() -> Color:
	return BORDER.lightened(AXIS_LIFT)

const PAD_X := 10
const PAD_Y := 6
const RADIUS := 4
## **AIR ABOVE A HEADING, WHICH IS WHAT MAKES IT A HEADING AND NOT A FIRST LINE** (Maren's Gap 1:
## "headings at INK with air above them"). A heading with the same gap above it as below belongs to
## the block before it as much as to its own.
##
## A STYLEBOX ON THE TYPE, NOT A SPACER AT EIGHT CALL SITES: the column, the log and any screen
## nobody has written yet get the same rhythm by saying `theme_type_variation = "Heading"`.
## `_log_lines_that_fit` in `main.gd` had to learn to ask for it -- it measured a heading with
## `font.get_height()` alone, which was exactly right until this margin existed.
const HEADING_AIR := 10

## **HOW PRESENT A QUIET BUTTON'S EDGE IS AT REST** (ASSA-233). An alpha on `BORDER` rather than a
## new colour. 0.45 is the weight at which the outline reads as an outline at 1x and still leaves a
## visible step up to the default button's full `BORDER` on hover.
##
## **THIS CONSTANT WENT AWAY AND CAME BACK, AND THE REASON IT IS BACK IS A MEASUREMENT.** Maren ruled
## the border three times in one day -- keep (14:25Z), delete (17:00Z), keep (18:40Z) -- and I built
## the middle one, having filed evidence ten minutes after a reversal I had not read. The 17:00Z
## argument was *"a border at rest makes quiet into default and spends the rank"*. The 18:40Z position
## measured the same frame and disproved it: **what marks the DEFAULT weight is its FILL**, `RAISED`
## (53,57,67), while a quiet toggle stays panel-flush on `SURFACE` (37,40,48) and a `LineEdit` sinks
## to its own darker well (28,30,36). A hairline says "pressable" without buying the default weight;
## a fill is what would buy it. So the edge costs nothing it was accused of costing.
##
## `_style_quiet_button` ASSERTS THAT RANK RATHER THAN RESTATING IT: the test for this weight checks
## that quiet's fill is the panel's own and default's is not, which is the property the ruling turns
## on. Flattening the two fills together is what would really spend the rank, and that now reddens.
const QUIET_EDGE := 0.45


## **A ONE-SHOT TOOL CAN RUN FOR EVER TOO, AND THIS IS THE HALF ASSA-182 DID NOT FIX FIRST TIME.**
## `SceneTree`'s own `_process` returns false, so a tool with no `_process` of its own does not end when
## `_initialize` returns -- it ends when something calls `quit()`. A runtime error inside `_initialize`
## skips that call and the engine spins with no output and no exit: measured 2026-10-04 with a scratch
## script, alive after 25 s. The looping tools got a wall-clock ceiling; this needs no clock, because
## there is nothing a one-shot tool legitimately waits for.
##
## `_quitting` is set beside every `quit()` in this file rather than at the end of `_initialize`, so a
## deliberate early exit -- a bad argument, a missing world -- stays deliberate, and only a
## fall-through reaches the sentence below.
var _quitting := false


func _process(_delta: float) -> bool:
	if not _quitting:
		print("FAIL  build_theme.gd: _initialize ended without asking to quit -- see the error above")
		quit(1)
	return true


func _initialize() -> void:
	var problems := _contrast_problems()
	if not problems.is_empty():
		for line in problems:
			print("  ", line)
		_fail("the theme's own text fails WCAG AA on the surface it is drawn on")
		return
	# THE HIERARCHY, SEPARATELY AND ON PURPOSE. This is NOT appended to `_contrast_problems`: every
	# pair in that list is an ink on a surface a player actually sees it drawn on, and its own
	# comment says a pair nobody draws would be a test of nothing. INK against INK_MUTED is not a
	# pairing on the screen, it is a requirement ABOUT the two inks. Putting it in that list would
	# have made that comment false, which is the way these files rot.
	var separation := AssayHud.contrast_ratio(INK, INK_MUTED)
	if separation < MIN_INK_SEPARATION:
		print("  body vs secondary: %.2f:1, needs %.1f:1" % [separation, MIN_INK_SEPARATION])
		_fail("the two inks have collapsed into one, so nothing tells a player what to read first")
		return

	var theme := Theme.new()
	theme.default_font_size = BODY
	_style_label(theme)
	_style_button(theme)
	_style_line_edit(theme)
	_style_panel(theme)
	_style_scroll(theme)
	_style_track(theme)

	if DirAccess.make_dir_recursive_absolute("res://theme") != OK:
		_fail("cannot make res://theme")
		return
	if ResourceSaver.save(theme, OUT) != OK:
		_fail("cannot write %s" % OUT)
		return
	print("  %s  %d type variations, body %dpx, contrast floor %.1f"
			% [OUT, theme.get_type_variation_list("Label").size(), BODY, MIN_CONTRAST])
	print("THEME BUILT")
	_quitting = true
	quit(0)


## EVERY INK AGAINST EVERY SURFACE IT IS ACTUALLY DRAWN ON, by `AssayHud`'s own WCAG function.
##
## Each pair is a real pairing on the screen, not a matrix: ink on panel is the readouts, ink on
## raised is a button's label, muted on panel is every secondary line in the column. A pair nobody
## draws would be a test of nothing.
func _contrast_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	for pair in [["body text", INK, SURFACE, MIN_CONTRAST],
			["button label", INK, RAISED, MIN_CONTRAST],
			["secondary text", INK_MUTED, SURFACE, MIN_MUTED_CONTRAST],
			["secondary on a button", INK_MUTED, RAISED, MIN_MUTED_CONTRAST],
			["accent on a field", ACCENT, RAISED, MIN_CONTRAST],
			# **THE PRIMARY BUTTON IS A NEW SURFACE WITH TEXT ON IT, SO IT IS A NEW PAIR** (ASSA-224).
			# A variation added without its pair would be the one surface in the game this file
			# cannot refuse -- which is how a check stops covering the thing it exists for.
			["primary button label", ON_ACCENT, ACCENT, MIN_CONTRAST],
			["quiet button label", INK_MUTED, SURFACE, MIN_MUTED_CONTRAST],
			# **THE ONE PAIR HERE THAT IS NOT TEXT** (ASSA-288). An axis on the panel, at the non-text
			# floor. It is in this list for exactly the reason the primary button's label is: a mark
			# the build cannot refuse is a mark that drifts.
			["reading axis", axis(), SURFACE, MIN_AXIS_CONTRAST]]:
		var ratio := AssayHud.contrast_ratio(pair[1], pair[2])
		if ratio < float(pair[3]):
			problems.append("%s: %.2f:1, needs %.1f:1" % [pair[0], ratio, pair[3]])
	return problems


## LABELS, AND THE THREE NAMES ANYTHING ELSE REACHES FOR. A type variation rather than a font-size
## override at the call site: `main.gd` says what a label IS ("Heading") and this file says how big
## that is, so the scale can be retuned once instead of at eight call sites.
func _style_label(theme: Theme) -> void:
	theme.set_color("font_color", "Label", INK)
	theme.set_font_size("font_size", "Label", BODY)
	# **`Heading` IS `INK`, AND IT WAS `INK_MUTED`** (Maren, Gap 1): "the section headings are
	# Heading, which is INK_MUTED: the structure of the column is dimmer than its contents." A
	# heading that is quieter than the paragraph under it inverts the one job a heading has. The
	# muted ink keeps its own name, `Muted`, for the lines that really are secondary.
	for variation in [["Display", DISPLAY, INK], ["Heading", HEADING, INK],
			["Muted", SMALL, INK_MUTED]]:
		var name := StringName(variation[0])
		theme.add_type(name)
		theme.set_type_variation(name, "Label")
		theme.set_font_size("font_size", name, variation[1])
		theme.set_color("font_color", name, variation[2])
	var air := StyleBoxEmpty.new()
	air.content_margin_top = HEADING_AIR
	theme.set_stylebox("normal", &"Heading", air)


func _style_button(theme: Theme) -> void:
	theme.set_font_size("font_size", "Button", SMALL)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", INK_MUTED.darkened(0.25))
	theme.set_stylebox("normal", "Button", _box(RAISED, BORDER))
	theme.set_stylebox("hover", "Button", _box(RAISED.lightened(0.10), BORDER.lightened(0.15)))
	theme.set_stylebox("pressed", "Button", _box(RAISED.darkened(0.18), ACCENT))
	theme.set_stylebox("disabled", "Button", _box(SURFACE, BORDER.darkened(0.3)))
	# A FOCUS RING THAT IS VISIBLE, because keyboard focus is the half nobody looks at. Godot's
	# default focus box is a flat outline that vanishes on a dark panel.
	theme.set_stylebox("focus", "Button", _box(RAISED, ACCENT))
	_style_primary_button(theme)
	_style_quiet_button(theme)


## **THE WEIGHT FOR THE ONE THING YOU ARE MOST LIKELY TO PRESS NEXT** (Maren, Gap 1: "a Button
## variation set -- primary (accent fill), default, quiet ... The accent belongs to the thing you are
## most likely to press next"). Until now this game had ONE button style, so Mine, Stop, Assay, Take,
## Pick up, Fuel, Smelt, Mount, Frame, Make and Play solo were the same grey box at the same 11 px
## and nothing on the screen had rank.
##
## IT IS BIGGER AS WELL AS GREENER, and that is the half that survives a greyscale print: a primary
## action told apart only by hue is no primary action for the players Maren's contrast floor exists
## for. `BODY` against the default's `SMALL`.
##
## **THE FOCUS RING INVERTS HERE, AND IT HAS TO.** Every other control rings itself in `ACCENT`
## against a grey fill; on a button whose fill IS the accent that ring would be invisible. `INK`
## instead, which is the same decision the default style makes -- ring in whatever the fill is not.
func _style_primary_button(theme: Theme) -> void:
	var name := &"Primary"
	theme.add_type(name)
	theme.set_type_variation(name, "Button")
	theme.set_font_size("font_size", name, BODY)
	theme.set_color("font_color", name, ON_ACCENT)
	theme.set_color("font_hover_color", name, ON_ACCENT)
	theme.set_color("font_pressed_color", name, ON_ACCENT)
	theme.set_color("font_disabled_color", name, INK_MUTED)
	theme.set_stylebox("normal", name, _box(ACCENT, ACCENT.darkened(0.15)))
	theme.set_stylebox("hover", name, _box(ACCENT.lightened(0.12), ACCENT))
	theme.set_stylebox("pressed", name, _box(ACCENT.darkened(0.18), ACCENT.darkened(0.3)))
	theme.set_stylebox("disabled", name, _box(SURFACE, BORDER.darkened(0.3)))
	theme.set_stylebox("focus", name, _box(ACCENT, INK))


## **THE WEIGHT FOR A CONTROL THAT MUST BE THERE AND MUST NOT SHOUT** -- the toggles that name their
## own key ("show the event log (L)", "hide what I can make (M)"). On `01-join.png` those two read
## as loudly as the section headings they sit between, so the column's structure competes with its
## own furniture.
##
## IT KEEPS ITS EDGE ONLY WHILE POINTED AT. The fill and border are the panel's own colour, so at
## rest it is a label; on hover the border arrives and it admits to being a button. This is the one
## variation where "quiet" could have become "invisible", so the ink stays `INK_MUTED` -- held to the
## same 4.5:1 as body text by `MIN_MUTED_CONTRAST`, because secondary describes importance and never
## legibility.
##
## **AND THE INK IS THE SAME TOKEN THE BODY ROWS USE, WHICH IS WHY A CONTRAST BAR WAS THE WRONG
## INSTRUMENT HERE.** Maren's Q1 clause (b) asked for "ink at or above the brightest body row
## (5.44), not below it", off rendered glyphs where these toggles read 4.22 and 4.79. `_note()` in
## `main.gd` paints every body row `INK_MUTED` out of this theme and so does this variation: 6.73:1
## nominal, the identical 24-bit value on the identical surface. The toggles are not below the
## brightest body row, they ARE it. Her two numbers were `SMALL` (11px) against `BODY` (13px) on a
## mean-over-glyph-box reading -- a smaller glyph spends proportionally more of itself on
## partly-covered edge pixels, so one colour reported two numbers. **She withdrew the 5.44 bar on
## the measurement (18:40Z).**
##
## **AND `SMALL` STAYS AT 11, WHICH IS HER RULING AND THE ARGUMENT I ARGUED AGAINST MYSELF.** I
## recommended promoting these to `BODY` as the one lever that would move her number, while also
## writing down the case against; she took the case against, and it is the better one. With no edge,
## a promoted quiet control would be **pixel-identical to body prose**: same `INK_MUTED`, same 13px,
## same left alignment, no box. That is not a quieter control, it is a sentence you can click.
func _style_quiet_button(theme: Theme) -> void:
	var name := &"Quiet"
	theme.add_type(name)
	theme.set_type_variation(name, "Button")
	theme.set_font_size("font_size", name, SMALL)
	theme.set_color("font_color", name, INK_MUTED)
	theme.set_color("font_hover_color", name, INK)
	theme.set_color("font_pressed_color", name, ACCENT)
	theme.set_color("font_disabled_color", name, INK_MUTED.darkened(0.25))
	# **AN EDGE AT REST, AT LOWER ALPHA** (ASSA-233, Maren's 18:40Z ruling, which is her third on this
	# clause and the only one carrying a measurement -- see `QUIET_EDGE`). A dim centred line across
	# the top of a panel is exactly where a TITLE sits, and that is what she read `show the event log
	# (L)` as when this weight had no edge at all. Quiet was meant to stop it shouting, not to stop it
	# being a button.
	#
	# **THE RANK IS CARRIED BY THE FILL, WHICH IS WHY THE EDGE IS FREE.** Measured on the real frame:
	# default `Join` fills `RAISED` (53,57,67), a quiet toggle stays panel-flush on `SURFACE`
	# (37,40,48), a `LineEdit` sinks to (28,30,36). The accusation against this hairline was that it
	# "makes quiet into default"; it cannot, because what a player reads as the default weight is that
	# lighter fill, and this weight never acquires one.
	#
	# `QUIET_EDGE` IS AN ALPHA ON `BORDER`, not a seventh colour: the same token this theme already
	# draws every other edge with, at a weight that reads as "there is an outline here" without
	# competing with the default button beside it.
	#
	# AND THE LEFT ALIGNMENT STAYS TOO, in `main.gd`. It was built as the replacement for this edge
	# and is now a second cue rather than the only one: every other control in the column sits at the
	# body column's x=11, and these two were the only centred rows in it.
	theme.set_stylebox("normal", name, _box(SURFACE, Color(BORDER, QUIET_EDGE)))
	theme.set_stylebox("hover", name, _box(SURFACE, BORDER))
	theme.set_stylebox("pressed", name, _box(SURFACE.darkened(0.15), BORDER))
	theme.set_stylebox("disabled", name, _box(SURFACE, SURFACE))
	theme.set_stylebox("focus", name, _box(SURFACE, ACCENT))


func _style_line_edit(theme: Theme) -> void:
	theme.set_font_size("font_size", "LineEdit", BODY)
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", INK_MUTED)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_stylebox("normal", "LineEdit", _box(SURFACE.darkened(0.25), BORDER))
	theme.set_stylebox("focus", "LineEdit", _box(SURFACE.darkened(0.25), ACCENT))


func _style_panel(theme: Theme) -> void:
	theme.set_stylebox("panel", "Panel", _box(SURFACE, BORDER))
	theme.set_stylebox("panel", "PanelContainer", _box(SURFACE, BORDER))


## **THE AXIS, AS A THEME ENTRY RATHER THAN A SECOND DERIVATION IN THE CONTROL** (ASSA-288).
##
## `AssayTrack` reads `axis_color`/`Track` with `get_theme_color`, the same way `main.gd` reads its
## two log inks. The alternative -- `BORDER.lightened(0.25)` written again in `track.gd` -- would be
## two places computing one colour, which is the ASSA-43/52 defect in paint: two vocabularies for one
## fact, free to disagree. Here the value is computed once, checked once by `_contrast_problems`, and
## looked up at the one place it is drawn.
##
## **A VARIATION OF `Control`, SO THE TRACK CAN NAME ITS OWN TYPE AND READ WITH NO TYPE ARGUMENT.**
## `tab_strip.gd:159` paid for that lesson: Godot compares the `theme_type` argument against the
## node's own class before building the type list, so a read WITH a type can silently resolve
## something else. A registered variation plus `theme_type_variation = &"Track"` makes
## `get_theme_color(&"axis_color")` the same lookup the engine makes when it draws.
##
## `Control` and not `Label`, because a track has no text and inheriting a font size would be
## furniture it never uses.
func _style_track(theme: Theme) -> void:
	theme.add_type(&"Track")
	theme.set_type_variation(&"Track", "Control")
	theme.set_color("axis_color", "Track", axis())


## THE SCROLLBAR, which is the one control on this screen that is load-bearing and invisible.
## The right-hand column is taller than the window, so the bar is the only thing telling a player
## there is more below -- it is widened and given the accent, not hidden.
func _style_scroll(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = SURFACE.darkened(0.3)
	track.set_corner_radius_all(RADIUS)
	track.content_margin_left = 2
	track.content_margin_right = 2
	var grab := StyleBoxFlat.new()
	grab.bg_color = BORDER.lightened(0.2)
	grab.set_corner_radius_all(RADIUS)
	theme.set_stylebox("scroll", "VScrollBar", track)
	theme.set_stylebox("grabber", "VScrollBar", grab)
	theme.set_stylebox("grabber_highlight", "VScrollBar", _flat(ACCENT))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _flat(ACCENT))


func _box(fill: Color, edge: Color) -> StyleBoxFlat:
	var box := _flat(fill)
	box.border_color = edge
	box.set_border_width_all(1)
	box.content_margin_left = PAD_X
	box.content_margin_right = PAD_X
	box.content_margin_top = PAD_Y
	box.content_margin_bottom = PAD_Y
	return box


func _flat(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(RADIUS)
	return box


func _fail(why: String) -> void:
	print("FAIL  %s" % why)
	_quitting = true
	quit(1)
