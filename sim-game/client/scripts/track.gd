## **AN AXIS WITH A MARK ON IT: THE TWO GRAMMARS, NEVER ONE** (ASSA-288, ASSA-276 move 3).
##
## Maren's ruling, 2026-10-08, in her words: *"A RATIO FILLS FROM ITS ORIGIN; A READING NEVER DOES."*
## `holding 2 of 60` is an amount with a true zero, so it fills. A reading is a POSITION on
## `SHEET_SCALE`, which is `(1, 100)` and therefore has no zero to fill from — a left fill there
## states a quantity the sim does not have.
##
## **SO THERE ARE TWO ENTRY POINTS AND NO WAY TO GET ONE GRAMMAR'S SHAPE OUT OF THE OTHER'S FACTS.**
## That is the whole reason the amount arm exists in a slice that ships only readings: a single
## `set_value(0..1)` is how the next person with a ratio borrows the band, and then nothing on screen
## means what it looks like. The grammars are separate functions with separate tests, and
## `test_track.gd` asserts the one property that tells them apart — an amount's ink always contains
## the track's origin, a reading's need not.
##
## **WHY A HAIRLINE AND NOT A FILLED TRACK, which is Maren's own option taken with a number.** Her
## rule 3 is that the axis must clear 3:1 against the plate behind it, and she offered: *"If three
## greys will not fit in a dark panel, the axis may be a hairline with end ticks instead of a filled
## bar — your call, measured."* Three greys do not fit, and here is why:
##
##   a filled track at 3:1 surrounds the mark, so MARK-vs-TRACK governs    INK_MUTED : axis  1.93:1
##   a hairline leaves the mark surrounded by the plate, so MARK-vs-PLATE  INK_MUTED : plate 6.75:1
##
## A rough band is the common state, not the rare one — the sheet is in bands until somebody spends
## 30 ticks — so the governing ratio is the one the rough band gets. The hairline moves it from 1.93
## to 6.75 and costs nothing. Both numbers are printed by `test_track.gd` from the shipped theme, not
## read off this comment.
##
## **NO `Color` LITERAL** (Maren's corrected ruling 3 on ASSA-116: she counted 21 of them). The inks
## and the plate come out of the theme actually in force, and the axis colour is a real theme entry
## (`axis_color`/`Track`) rather than a second derivation here — `build_theme.gd` computes it once
## and REFUSES TO WRITE A THEME where it misses 3:1, so rule 3 is a build-time guard and not a
## sentence in a docstring.
class_name AssayTrack
extends Control

## Which grammar the last `show_*` call put on this track. `NOTHING` is a real state and it is drawn
## as nothing at all: see `show_reading`'s refusal.
enum Grammar { NOTHING, AMOUNT, READING }

## The axis itself. 2 px for the same reason `AssayHud.MARK_KEYLINE_PX` is 2 — that file's own
## comment calls it "the thinnest rim" that survives 1x — and it is read from there rather than
## retyped, so the two thin marks in this client cannot drift apart.
const AXIS_PX := AssayHud.MARK_KEYLINE_PX

## The end ticks, and the mark, are both taller than the axis so the mark reads as something ON the
## line rather than a thickening OF it. They are equal on purpose: the mark slides between two
## landmarks of its own height, which is what makes "low / middle / high" answerable (Maren's rule 6).
const TICK_PX := 8.0
const MARK_PX := 8.0

## **MAREN'S RULE 4, AS A NUMBER: the answer may never read as LESS than the guess.** An assayed
## reading crosses as `(v, v)`, which on an 86 px track is 0.9 px — the thing you paid 30 ticks for
## drawn THINNER than the band it replaced. So a reading's mark is never narrower than this.
##
## **IT DOES NOT APPLY TO AN AMOUNT, and that is not an oversight.** `holding 0 of 60` is a true
## zero; a 2 px stub there would say "a little bit". A floor on an amount would be this client
## inventing a quantity, which is the same defect class as composing wording (ASSA-136).
const MIN_MARK_PX := AssayHud.MARK_KEYLINE_PX

## **ONE LEFT EDGE AND ONE RIGHT EDGE, WHICH IS MAREN'S RULE 2 AND THE ONLY THING A POSITION
## ENCODING IS FOR.** My own mock had four 87 px tracks at four different x — 1078 / 1083 / 1089 /
## 1110 — because each was parked beside its own right-aligned number, and she measured it: *"A
## position encoding whose axes are not aligned cannot be compared down the column."* A fixed width
## here plus a fixed label column in `AssayReadingRow` is what makes every track in the panel share
## an axis. `test_track.gd` measures it in pixels off a real window; a structural assertion alone
## would pass at a headless zero.
const WIDTH_PX := 86.0

var _grammar: Grammar = Grammar.NOTHING
var _mark := Rect2()
var _assayed := false


func _init() -> void:
	# SIZED TO THE AXIS, NOT TO THE ROW. The height is the tick, which is the tallest thing drawn.
	custom_minimum_size = Vector2(WIDTH_PX, TICK_PX)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A track answers no clicks. It is a readout, and a Control that eats the pointer over a scroll
	# box is how a list stops scrolling under the cursor.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# **IT NAMES ITS OWN THEME TYPE SO IT CAN READ WITH NO TYPE ARGUMENT**, which is the read the
	# engine makes when it draws. See `build_theme.gd::_style_track` and the lesson in
	# `tab_strip.gd:159`: `get_theme_color(name, &"SomeType")` compares that type against the node's
	# own class first and can resolve something else entirely.
	theme_type_variation = &"Track"


## **A READING: A SEGMENT PLACED ON THE SIM'S OWN AXIS.**
##
## `low`/`high` are one entry of `reading_ranges` (`AssaySim.species_sheets`) and `scale` is
## `AssaySim.reading_scale()` (ASSA-279, Marlow, main `c50f146`). **100 is never typed here** — the
## denominator is published precisely so a client cannot hold a stale copy of it.
##
## **A DEGENERATE SCALE DRAWS NOTHING, DELIBERATELY.** `sim_host.gd` answers `Vector2i.ZERO` with no
## sim, and Marlow's comment says why: *"a plausible fallback is how a wrong axis reaches a screen."*
## An axis of zero width cannot carry a position, so this refuses rather than dividing — and refuses
## loudly in the one way a readout can, by being absent. `test_track.gd` has the control (ZERO draws
## nothing) and the positive case (a real scale draws an axis and a mark) so the refusal cannot be
## the reason every assertion passes.
func show_reading(low: int, high: int, scale: Vector2i, assayed: bool) -> void:
	if scale.y <= scale.x:
		show_nothing()
		return
	_grammar = Grammar.READING
	_assayed = assayed
	var span := reading_span(low, high, scale, WIDTH_PX)
	_mark = Rect2(span.x, 0.0, span.y, MARK_PX)
	queue_redraw()


## **AN AMOUNT: A FILL FROM THE ORIGIN.** `value` of `total`, both the sim's.
##
## `total <= 0` is not a full bar and not an empty one, it is an absent fact, so it draws nothing for
## the same reason a zero-width axis does. A `value/0` fill would be `inf` clamped to full, which
## reads as "completely full" — the most confident possible rendering of a number nobody has.
func show_amount(value: int, total: int) -> void:
	if total <= 0:
		show_nothing()
		return
	_grammar = Grammar.AMOUNT
	_assayed = true
	_mark = Rect2(0.0, 0.0, amount_width(value, total, WIDTH_PX), MARK_PX)
	queue_redraw()


## **NO AXIS AND NO MARK, which is a state and not an error.** Three callers reach it: a scale the
## sim will not vouch for (`Vector2i.ZERO` with no world), a total of zero, and a property the
## binding sent words for but no range. All three mean the same thing on screen -- this readout has
## no position to report -- and drawing an empty axis instead would promise one is coming.
func show_nothing() -> void:
	_grammar = Grammar.NOTHING
	_mark = Rect2()
	queue_redraw()


## WHERE A READING'S SEGMENT SITS, as `(x, width)` in track-local pixels. Static and pure, so the
## geometry is testable without a window, a theme or a paint pass — the three things that read zero
## or nothing in a headless suite.
##
## `low` and `high` are clamped INTO the axis rather than allowed off it: a band wider than the scale
## is a binding regression, and `test_sim_host.gd` is the place that catches it with a sentence.
## Drawing it off the end would make the defect look like a layout bug instead.
static func reading_span(low: int, high: int, scale: Vector2i, width: float) -> Vector2:
	var axis := float(scale.y - scale.x)
	if axis <= 0.0 or width <= 0.0:
		return Vector2.ZERO
	var lo := clampf(float(clampi(low, scale.x, scale.y) - scale.x) / axis, 0.0, 1.0) * width
	var hi := clampf(float(clampi(high, scale.x, scale.y) - scale.x) / axis, 0.0, 1.0) * width
	# THE FLOOR, THEN THE CLAMP, AND IN THAT ORDER. Widening a mark at the top of the scale pushes it
	# off the right end, so the pull-back comes after. I wrote the clamp first on ASSA-281 and the
	# clamp put the thing back on top of what it was moving off; a fix that silently stops fixing is
	# worse than the bug.
	var w := maxf(MIN_MARK_PX, hi - lo)
	var x := minf(lo, width - w)
	return Vector2(maxf(0.0, x), minf(w, width))


## HOW WIDE AN AMOUNT'S FILL IS. No floor (see `MIN_MARK_PX`): an empty tank draws nothing.
static func amount_width(value: int, total: int, width: float) -> float:
	if total <= 0 or width <= 0.0:
		return 0.0
	return clampf(float(value) / float(total), 0.0, 1.0) * width


## The mark the last `show_*` placed, for a test that wants the geometry without reading pixels.
func mark_rect() -> Rect2:
	return _mark


func grammar() -> Grammar:
	return _grammar


## **WHAT THIS TRACK WOULD PAINT, AT A HEIGHT YOU NAME**, in paint order, as
## `{rect: Rect2, color: Color, what: String}`.
##
## **THE PLAN IS SEPARATE FROM THE PAINT BECAUSE THE SUITE NEVER PAINTS.** `run_tests.gd` runs inside
## `SceneTree._initialize`: `_ready` never fires and no frame is drawn, so a test that asserted on
## recorded `draw_rect` calls would assert on an empty list and pass for that reason alone. That is
## the shape of defect I keep catching in my own instruments -- a check that cannot fail. Here the
## test asks for the plan at a height it chooses, and `_draw` is a two-line loop over the same plan,
## so what is asserted is what is painted.
##
## **THE HEIGHT IS AN ARGUMENT FOR THE SAME REASON.** `size.y` is window-derived and reads 0 in the
## harness (Limpet's correction: content-derived sizes survive headless, window-derived ones do not),
## which would put every rect at a negative y and make the vertical geometry untestable.
##
## **AND THIS IS WHERE MAREN'S RULE 5 LIVES:** *"NOTHING INSIDE THE BAND. No midpoint tick, no centre
## dot, no gradient, no fade at the ends."* The mark is the LAST entry and it is exactly ONE rect, so
## a later centre dot or a gradient of five slices reddens `test_track.gd` instead of shipping a
## probability the sim does not publish -- `Sheet::band` has two ends and nothing between them.
func plan_for(height: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _grammar == Grammar.NOTHING:
		return out
	var axis := axis_color()
	out.append({"rect": Rect2(0.0, floorf((height - AXIS_PX) * 0.5), WIDTH_PX, AXIS_PX),
			"color": axis, "what": "axis"})
	# **THE END TICKS BELONG TO A READING AND NOT TO AN AMOUNT, and the reason is the grammar rather
	# than decoration.** Ticks mark an axis you have to LOCATE ink on; a fill locates itself, because
	# its own left edge is the origin and its right edge is the answer. Giving both the same furniture
	# would spend the one cue that separates them for free.
	if _grammar == Grammar.READING:
		var tick_top := floorf((height - TICK_PX) * 0.5)
		out.append({"rect": Rect2(0.0, tick_top, AXIS_PX, TICK_PX), "color": axis,
				"what": "tick_low"})
		out.append({"rect": Rect2(WIDTH_PX - AXIS_PX, tick_top, AXIS_PX, TICK_PX), "color": axis,
				"what": "tick_high"})
	var mark := _mark
	mark.position.y = floorf((height - MARK_PX) * 0.5)
	out.append({"rect": mark, "color": mark_color(), "what": "mark"})
	return out


## THE AXIS COLOUR, OUT OF THE THEME IN FORCE. `build_theme.gd` owns the value and refuses to write a
## theme where it misses 3:1 against the plate, so this is a lookup and not a second opinion.
func axis_color() -> Color:
	return get_theme_color(&"axis_color")


## THE MARK'S COLOUR: Maren's rule 4. `INK` once the sheet is exact, `INK_MUTED` while it is rough —
## *"the UI sharpening as you learn is carried by weight instead of by width"* — and it survives
## greyscale (229 against 167). `ACCENT` is untouched: it still means "press this next".
## **MAREN'S RULE 4: the mark's weight says whether it is an answer.** `INK` once the sheet is exact,
## `INK_MUTED` while it is rough -- *"the UI sharpening as you learn is carried by weight instead of
## by width"* -- and it survives greyscale (229 against 167). `ACCENT` is untouched: it still means
## "press this next" and nothing else.
##
## An amount is always certain, so it takes `INK`: a ratio the sim published is not a guess about
## anything.
func mark_color() -> Color:
	return get_theme_color(&"font_color", &"Label" if _assayed else &"Muted")


## Two lines, on purpose. Every decision is in `plan_for`, which a test can read.
func _draw() -> void:
	for item in plan_for(size.y):
		draw_rect(item["rect"] as Rect2, item["color"] as Color)
