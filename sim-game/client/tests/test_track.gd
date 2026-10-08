extends RefCounted
## **THE SIX RULES MAREN GAVE MOVE 3, ONE TEST EACH** (ASSA-288; ASSA-276 move 3, 2026-10-08).
##
## Rule 6 is hers to sit, not mine to assert -- *"a reader is shown ONE row at 1x with the label and
## the number masked, and says amount or range"* -- and so is the pixel measurement of rule 2, which
## needs a real window. Those go to `tools/nacre_track_shot.gd` and a shot. The five that are
## properties of the drawing rather than of a reader are here.
##
## **WHAT THIS FILE REFUSES TO DO, because I have shipped the mistake twice.** Nothing here asserts a
## `position` or a `size`: the suite runs inside `SceneTree._initialize`, so no frame is drawn and no
## container lays out, and every window-derived number reads 0. An assertion about a 0 that was
## always going to be 0 is the check that cannot fail. What is asserted instead is (a) pure geometry
## from `AssayTrack.plan_for`, at a height the test names, and (b) content-derived minimum sizes,
## which Godot computes from font metrics and children and which therefore survive headless.
##
## **AND EVERY DETECTOR HERE HAS A CONTROL AND A POSITIVE CASE.** The refusal paths (no scale, no
## total) draw nothing, which would make a lazy assertion about "what was drawn" pass by being empty;
## so each of those tests also proves the drawing arm draws.

var runner = null

## The axis the sim actually publishes, asked of the binding rather than typed. `reading_scale()` is
## Marlow's (ASSA-279) and its whole point is that nobody writes 100 down. Cached per test.
var _scale := Vector2i.ZERO


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## A STARTED WORLD, so the suite can ask the binding things. Cached, because `fresh_welcome_json`
## builds a whole world and five tests want the same one.
var _host = null

## THE SIM'S OWN AXIS, ASKED FOR AND NOT TYPED (ASSA-279).
##
## **IT NEEDS A STARTED HOST, which cost me a red run and is the guard working.** `reading_scale()`
## is a static fact about the rules, so I reached for a bare `AssaySimHost.new()` -- and
## `sim_host.gd` answers `Vector2i.ZERO` without a world on purpose, "because a plausible fallback is
## how a wrong axis gets onto a screen" (Marlow). Seven tests failed with `(0, 0)` rather than
## quietly checking a drawing against a scale nobody vouched for. That refusal is exactly what it is
## for.
func _world():
	if _host == null:
		var host := AssaySimHost.new()
		if not host.start(AssaySimHost.fresh_welcome_json("14247", "marlow")):
			return null
		_host = host
	return _host


func _axis() -> Vector2i:
	if _scale == Vector2i.ZERO:
		var host = _world()
		_scale = Vector2i.ZERO if host == null else host.reading_scale()
	return _scale


func _track() -> AssayTrack:
	return AssayTrack.new()


## **RULE 1: A RATIO FILLS FROM ITS ORIGIN; A READING NEVER DOES.**
##
## The test is the one property that tells the grammars apart with the label and the number masked,
## which is the state Maren's reader test puts them in: an amount's ink contains the track's origin,
## a reading's need not. Asserted over the whole axis, not at one convenient value.
func test_an_amount_fills_from_its_origin_and_a_reading_does_not() -> bool:
	var scale := _axis()
	if scale.y <= scale.x:
		return _fail("the binding published no reading scale (%s), so no grammar can be checked"
				% scale)
	var track := _track()
	# EVERY AMOUNT THAT HAS ANY INK AT ALL STARTS AT 0. An empty tank draws nothing, which is the
	# only case with no origin to contain, and it is checked separately below.
	for value in [1, 2, 7, 30, 59, 60]:
		track.show_amount(value, 60)
		var mark := track.mark_rect()
		if mark.size.x <= 0.0:
			return _fail("holding %d of 60 drew no ink at all" % value)
		if mark.position.x != 0.0:
			return _fail(("an amount is a fill and must start at the origin: %d of 60 starts at "
					+ "x=%.2f") % [value, mark.position.x])
	# A ZERO AMOUNT IS A TRUE ZERO AND DRAWS NOTHING. A 2 px stub there would say "a little bit";
	# the floor in `MIN_MARK_PX` is a reading's and not an amount's.
	track.show_amount(0, 60)
	if track.mark_rect().size.x != 0.0:
		return _fail("0 of 60 drew %.2f px of ink, which claims a quantity the sim does not have"
				% track.mark_rect().size.x)
	# AND A READING AT THE SAME PLACE ON THE SCALE DOES NOT TOUCH THE ORIGIN. The exact value is the
	# one that matters: a band could legitimately start at the bottom of the scale, but a reading of
	# the MIDDLE that filled from the left would be the mock's own defect.
	var mid := scale.x + int(float(scale.y - scale.x) * 0.5)
	track.show_reading(mid, mid, scale, true)
	if track.mark_rect().position.x <= 0.0:
		return _fail(("a reading of %d on %s is a POSITION and was drawn from the origin: that "
				+ "states a quantity the sim does not have (Maren, rule 1)") % [mid, scale])
	# THE SAME NUMBERS THROUGH THE TWO GRAMMARS MUST NOT LOOK THE SAME. If they do, a reader with the
	# label masked cannot answer Maren's question however carefully the code is written.
	track.show_reading(mid, mid, scale, true)
	var as_reading := track.mark_rect()
	track.show_amount(mid - scale.x, scale.y - scale.x)
	var as_amount := track.mark_rect()
	if as_reading.is_equal_approx(as_amount):
		return _fail("the middle of the scale draws identically as a reading and as an amount (%s)"
				% as_reading)
	return true


## **RULE 2, THE HALF THAT CAN BE CHECKED WITHOUT A WINDOW: the label's width cannot depend on its
## word.**
##
## Maren's rule is that every reading track shares one left and one right edge. In a row of
## `label | track | value` that is true exactly when nothing before the track is sized by its
## content -- and `custom_minimum_size` does NOT give that, because it is a floor and a `Label` grows
## to its text. `clip_text` is what makes the floor the whole story.
##
## `get_combined_minimum_size()` is content-derived (font metrics, children's minimums), so it is a
## real number in a headless suite. The pixel proof of the shared edge is in a real window; this is
## the structural reason the pixels come out that way, and it reddens the moment someone turns
## `clip_text` off to "fix" a stub.
func test_a_property_name_cannot_push_the_track_out_of_line() -> bool:
	var short := AssayReadingRow.new()
	short.show_reading("a", "1", 1, 1, _axis(), true)
	var long := AssayReadingRow.new()
	long.show_reading("a property name far longer than any sheet will ever publish", "100-100",
			1, 1, _axis(), true)
	var a := short.get_combined_minimum_size()
	var b := long.get_combined_minimum_size()
	if not is_equal_approx(a.x, b.x):
		return _fail(("a row's width depends on its label: `a` wants %.1f px and a long name wants "
				+ "%.1f px. Every track in the panel would then sit at its own x, and a position "
				+ "encoding whose axes are not aligned cannot be compared down the column "
				+ "(Maren, rule 2)") % [a.x, b.x])
	# THE POSITIVE CASE: the row really does reserve the three columns, so the equality above is not
	# two zeroes agreeing.
	var want := AssayReadingRow.LABEL_W + AssayTrack.WIDTH_PX + AssayReadingRow.VALUE_W
	if a.x < want:
		return _fail(("a row's minimum width is %.1f px, under the %.1f the three columns need: the "
				+ "comparison above was between two numbers that mean nothing") % [a.x, want])
	return true


## **BOTH FIXED COLUMNS ARE WIDE ENOUGH FOR WHAT THE SIM ACTUALLY PUBLISHES, BY FONT METRICS.**
##
## The two columns fail in opposite directions and both failures break rule 2:
##  - the LABEL is clipped, so a long property name cannot push the track -- but it becomes a stub on
##    screen, which nobody would ever see go wrong.
##  - the VALUE may not be clipped, because it is the number, so it GROWS and pushes everything.
##
## **THIS IS THE TEST THAT CAUGHT THE SECOND ONE: `100-100` measured 49.0 px against a 48.0 px
## column.** One pixel, on the sharpest sheet in the game, and every track in the panel would have
## moved. So the bound is the widest string the sim's own scale permits, not a guess, and it is asked
## of the engine's font rather than counted off a glyph table.
func test_both_fixed_columns_fit_what_the_sim_publishes() -> bool:
	var host = _world()
	if host == null:
		return _fail("no world, so there are no real property names to measure")
	var scale := _axis()
	var font := ThemeDB.fallback_font
	var theme: Theme = load("res://theme/assay.tres")
	if theme == null:
		return _fail("no theme/assay.tres to read the two type sizes out of")
	# THE TWO SIZES THE ROW ACTUALLY DRAWS WITH: the label is `Muted`, the value is a plain Label.
	var label_px := theme.get_font_size(&"font_size", &"Muted")
	var value_px := theme.get_font_size(&"font_size", &"Label")
	var sheets: Array = host.species_sheets()
	if sheets.is_empty():
		return _fail("no species sheets in a started world")
	var widest_name := ""
	var widest_name_px := 0.0
	var widest_value := ""
	var widest_value_px := 0.0
	# **EVERY STRING THE WORLD ACTUALLY HOLDS, PLUS THE WORST ONE IT COULD.** A fresh world has
	# assayed nothing, so its readings are all bands; `100-100` never appears in it and is exactly the
	# string that broke the column. A measurement over real data only would have passed.
	var candidates := PackedStringArray(["%d-%d" % [scale.y, scale.y], "%d-%d" % [scale.x, scale.y]])
	for entry in sheets:
		var readings: Dictionary = (entry as Dictionary).get("readings", {})
		for property in readings:
			var name_px := font.get_string_size(String(property), HORIZONTAL_ALIGNMENT_LEFT, -1.0,
					label_px).x
			if name_px > widest_name_px:
				widest_name_px = name_px
				widest_name = String(property)
			candidates.append(String(readings[property]))
	for text in candidates:
		var px := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, value_px).x
		if px > widest_value_px:
			widest_value_px = px
			widest_value = text
	print(("columns: label %.1f px holds `%s` at %.1f · value %.1f px holds `%s` at %.1f")
			% [AssayReadingRow.LABEL_W, widest_name, widest_name_px, AssayReadingRow.VALUE_W,
			widest_value, widest_value_px])
	if widest_name_px > AssayReadingRow.LABEL_W:
		return _fail(("the property `%s` wants %.1f px and the label column is %.1f: it would be "
				+ "clipped to a stub on screen, which is a defect nobody would notice")
				% [widest_name, widest_name_px, AssayReadingRow.LABEL_W])
	if widest_value_px > AssayReadingRow.VALUE_W:
		return _fail(("the reading `%s` wants %.1f px and the value column is %.1f: a value column "
				+ "that grows pushes every track in the panel out of line (Maren, rule 2)")
				% [widest_value, widest_value_px, AssayReadingRow.VALUE_W])
	return true


## **RULE 2 AGAIN, AND RULE 3'S CONTAINER: the track is one fixed width for every reading.**
func test_every_track_is_the_same_width() -> bool:
	var scale := _axis()
	var widths := {}
	for pair in [[scale.x, scale.x], [scale.x, scale.y], [40, 70], [99, 100]]:
		var row := AssayReadingRow.new()
		row.show_reading("p", "x", int(pair[0]), int(pair[1]), scale, false)
		widths[row.track().custom_minimum_size.x] = true
	if widths.size() != 1:
		return _fail("tracks came out %d different widths: %s" % [widths.size(), widths.keys()])
	if widths.keys()[0] != AssayTrack.WIDTH_PX:
		return _fail("a track is %.1f px wide, not the declared %.1f"
				% [widths.keys()[0], AssayTrack.WIDTH_PX])
	return true


## **RULE 3: THE AXIS IS THE FACT, AND IT CLEARS THE NON-TEXT FLOOR AGAINST THE PLATE IT IS ON.**
##
## Maren measured my mock's track at **1.27:1** and ruled a floor of 3:1. This reads the SHIPPED
## theme rather than `build_theme.gd`'s constants, so it is a statement about what players get.
##
## **IT ALSO RECORDS THE TWO LOSING CANDIDATES AND THE HAIRLINE ARGUMENT**, because the ruling left
## the choice to me "measured" and a decision with no numbers beside it gets re-litigated. The
## printed line is the evidence for picking a hairline over a filled track.
func test_the_axis_clears_the_non_text_floor_against_its_plate() -> bool:
	var theme: Theme = load("res://theme/assay.tres")
	if theme == null:
		return _fail("no theme/assay.tres to read the shipped axis out of")
	var plate_box := theme.get_stylebox(&"panel", &"PanelContainer") as StyleBoxFlat
	if plate_box == null:
		return _fail("the theme declares no flat panel box, so this test cannot name the plate "
				+ "without a literal, which is what it refuses to do")
	var plate := plate_box.bg_color
	var axis := theme.get_color(&"axis_color", &"Track")
	var ratio := AssayHud.contrast_ratio(axis, plate)
	var floor_ratio := 3.0
	# THE LOSERS, SO THE CHOICE IS ON THE RECORD. Both are greys this palette already owns, and
	# neither can carry the floor -- which is why the axis is derived at all.
	var raised := (theme.get_stylebox(&"normal", &"Button") as StyleBoxFlat).bg_color
	var muted := theme.get_color(&"font_color", &"Muted")
	print(("axis %.2f:1 on the plate (floor %.1f) · RAISED would be %.2f:1 · the border %.2f:1 · "
			+ "a rough mark is %.2f:1 on the plate and %.2f:1 on the axis, which is why the axis "
			+ "is a hairline and not a filled track")
			% [ratio, floor_ratio, AssayHud.contrast_ratio(raised, plate),
			AssayHud.contrast_ratio(plate_box.border_color, plate),
			AssayHud.contrast_ratio(muted, plate), AssayHud.contrast_ratio(muted, axis)])
	if ratio < floor_ratio:
		return _fail(("the reading axis is %.2f:1 against the plate behind it, under the %.1f:1 "
				+ "non-text floor: a floating segment whose track you cannot see is a block at an "
				+ "arbitrary place (Maren, rule 3)") % [ratio, floor_ratio])
	# **AND THE HAIRLINE'S OWN PREMISE, ASSERTED AND NOT ASSUMED.** The whole case for a 2 px axis
	# instead of a filled one is that it leaves the mark surrounded by the PLATE rather than by the
	# track. If a rough mark ever reads better against the axis than against the plate, that premise
	# is dead and the shape should be reconsidered rather than this line deleted.
	if AssayHud.contrast_ratio(muted, plate) <= AssayHud.contrast_ratio(muted, axis):
		return _fail(("a rough mark now reads better on the axis (%.2f:1) than on the plate "
				+ "(%.2f:1), which is the opposite of the measurement a hairline was chosen on")
				% [AssayHud.contrast_ratio(muted, axis), AssayHud.contrast_ratio(muted, plate)])
	return true


## **RULE 4: THE ANSWER MAY NEVER READ AS LESS THAN THE GUESS.**
##
## Two halves, and the second is the one that carries it. An assayed reading crosses as `(v, v)`,
## which is 0.9 px on an 86 px track, so (a) it is never narrower than `MIN_MARK_PX`, and (b) since
## it is still narrower than the band it replaced, the certainty has to be carried by WEIGHT: `INK`
## when assayed, `INK_MUTED` while rough. Checked at every value on the sim's own axis, so a clamp
## that fails at one end cannot hide.
func test_an_exact_reading_is_never_thinner_or_dimmer_than_the_band_it_replaced() -> bool:
	var scale := _axis()
	var theme: Theme = load("res://theme/assay.tres")
	if theme == null:
		return _fail("no theme/assay.tres")
	var ink := theme.get_color(&"font_color", &"Label")
	var muted := theme.get_color(&"font_color", &"Muted")
	var track := _track()
	for v in range(scale.x, scale.y + 1):
		track.show_reading(v, v, scale, true)
		var mark := track.mark_rect()
		if mark.size.x < AssayTrack.MIN_MARK_PX:
			return _fail(("an exact reading of %d is %.2f px wide, under the %.1f px floor: the "
					+ "thing a player spent 30 ticks on would be drawn thinner than the guess "
					+ "(Maren, rule 4)") % [v, mark.size.x, AssayTrack.MIN_MARK_PX])
		if not track.mark_color().is_equal_approx(ink):
			return _fail("an exact reading of %d is drawn %s, want the theme's INK %s"
					% [v, track.mark_color(), ink])
	track.show_reading(26, 50, scale, false)
	if not track.mark_color().is_equal_approx(muted):
		return _fail("a rough band is drawn %s, want INK_MUTED %s" % [track.mark_color(), muted])
	# THE WEIGHT HAS TO BE A REAL STEP, and in the direction that makes certainty the brighter state.
	# Equal inks would pass every clause above with the screen saying nothing about what is known.
	if AssayHud.relative_luminance(ink) <= AssayHud.relative_luminance(muted):
		return _fail(("the assayed ink %s is not brighter than the rough one %s, so sharpening a "
				+ "sheet changes nothing a player can see") % [ink, muted])
	return true


## **RULE 5: NOTHING INSIDE THE BAND.** *"No midpoint tick, no centre dot, no gradient, no fade at
## the ends."*
##
## Asserted on the paint plan, in paint order: the mark is exactly ONE rect and it is the LAST thing
## drawn. A centre dot or a five-slice gradient added later cannot satisfy both clauses. `_draw` is a
## two-line loop over this same plan, so what is asserted is what is painted.
func test_nothing_is_drawn_inside_the_band() -> bool:
	var scale := _axis()
	var track := _track()
	track.show_reading(26, 50, scale, false)
	var plan := track.plan_for(AssayTrack.TICK_PX)
	if plan.is_empty():
		return _fail("a rough band on %s painted nothing at all" % scale)
	var marks := 0
	for i in range(plan.size()):
		if String(plan[i]["what"]) == "mark":
			marks += 1
			if i != plan.size() - 1:
				return _fail(("the mark is painted %d of %d, so %s is drawn on top of the band: "
						+ "`Sheet::band` publishes two ends and nothing between them (Maren, rule "
						+ "5)") % [i + 1, plan.size(), plan[i + 1]["what"]])
	if marks != 1:
		return _fail(("the band is %d rects, not 1: a gradient or a midpoint tick would leak a "
				+ "probability the sim does not have") % marks)
	# THE AXIS AND ITS TWO END TICKS, AND NOTHING ELSE. A fourth piece of furniture is something a
	# reader has to account for, and this is where it would be noticed.
	var what := PackedStringArray()
	for item in plan:
		what.append(String(item["what"]))
	if "|".join(what) != "axis|tick_low|tick_high|mark":
		return _fail("a reading paints `%s`, want `axis|tick_low|tick_high|mark`" % "|".join(what))
	# AN AMOUNT HAS NO END TICKS, which is the second cue separating the grammars: ticks mark an axis
	# you must locate ink on, and a fill locates itself.
	track.show_amount(2, 60)
	var fill := PackedStringArray()
	for item in track.plan_for(AssayTrack.TICK_PX):
		fill.append(String(item["what"]))
	if "|".join(fill) != "axis|mark":
		return _fail("an amount paints `%s`, want `axis|mark`" % "|".join(fill))
	return true


## **A MARK NEVER LEAVES ITS AXIS, AT EITHER END.**
##
## This is the test for the mistake I made on ASSA-281 and wrote into my own memory: the 2 px floor
## WIDENS a mark, so applying it after a clamp pushes the mark off the right-hand end -- a fix that
## silently stops fixing. Checked at every pair the sim can publish, in both orders, not at the
## three values that happen to be convenient.
func test_a_mark_never_leaves_its_axis() -> bool:
	var scale := _axis()
	var width := AssayTrack.WIDTH_PX
	for low in range(scale.x, scale.y + 1):
		for high in [low, mini(low + 24, scale.y), scale.y]:
			var span := AssayTrack.reading_span(low, int(high), scale, width)
			if span.x < 0.0:
				return _fail("the band %d-%s starts at x=%.2f, off the left of its axis"
						% [low, high, span.x])
			if span.x + span.y > width + 0.001:
				return _fail(("the band %d-%s ends at %.2f on an axis %.0f px wide: the 2 px floor "
						+ "widened it past its own scale") % [low, high, span.x + span.y, width])
			if span.y < AssayTrack.MIN_MARK_PX:
				return _fail("the band %d-%s is %.2f px wide, under the floor" % [low, high, span.y])
	return true


## **A FACT THE SIM WILL NOT VOUCH FOR IS DRAWN AS NOTHING, AND THE DRAWING ARM STILL DRAWS.**
##
## `sim_host.gd` answers `Vector2i.ZERO` for `reading_scale()` with no world, deliberately unusable,
## because (Marlow) *"a plausible fallback is how a wrong axis reaches a screen"*. An axis of zero
## width cannot carry a position, so the track refuses.
##
## **THE POSITIVE CASE IS THE POINT OF THIS TEST.** Every assertion about a refusal passes trivially
## if the control draws nothing ever, which is the shape of my own worst instruments. So each refusal
## is paired with the same call on a real axis, which must draw.
func test_a_scale_the_sim_will_not_vouch_for_draws_nothing() -> bool:
	var track := _track()
	track.show_reading(26, 50, Vector2i.ZERO, false)
	if not track.plan_for(AssayTrack.TICK_PX).is_empty():
		return _fail("a reading on a zero-width axis was drawn anyway: %s"
				% track.plan_for(AssayTrack.TICK_PX))
	if track.grammar() != AssayTrack.Grammar.NOTHING:
		return _fail("a zero-width axis left the track in grammar %d" % track.grammar())
	track.show_reading(26, 50, _axis(), false)
	if track.plan_for(AssayTrack.TICK_PX).is_empty():
		return _fail("THE CONTROL NEVER DRAWS: a real reading on %s painted nothing, so the "
				+ "refusal above proves nothing" % _axis())
	track.show_amount(2, 0)
	if not track.plan_for(AssayTrack.TICK_PX).is_empty():
		return _fail("`2 of 0` was drawn: a value over a total nobody has would read as full")
	track.show_amount(2, 60)
	if track.plan_for(AssayTrack.TICK_PX).is_empty():
		return _fail("THE AMOUNT ARM NEVER DRAWS: `2 of 60` painted nothing")
	# A ROW WITH WORDS AND NO RANGE KEEPS THE WORDS AND WITHHOLDS THE POSITION (`show_unmarked`).
	# This is the branch I first wrote as a `Vector2i.ZERO` default, which would have clamped to a
	# confident 2 px mark at the very bottom of the scale -- the most specific possible claim about a
	# number nobody sent.
	var row := AssayReadingRow.new()
	row.show_unmarked("density", "26-50")
	if row.value_text() != "26-50":
		return _fail("an unmarked row dropped the sim's own reading: `%s`" % row.value_text())
	if not row.track().plan_for(AssayTrack.TICK_PX).is_empty():
		return _fail("a property the binding sent no range for was given a position anyway: %s"
				% row.track().plan_for(AssayTrack.TICK_PX))
	return true


## **THE AXIS THE MARKS ARE PLACED ON IS THE SIM'S, AND 100 IS NOT TYPED ANYWHERE IN THIS CLIENT.**
##
## ASSA-279's whole reason for existing. `test_sim_host.gd` already checks the binding publishes a
## usable scale; this checks the DRAWING uses it -- the same reading against two different axes must
## land in two different places, which it cannot do if the denominator is a constant in `track.gd`.
func test_the_denominator_is_the_sims_and_not_a_literal() -> bool:
	var scale := _axis()
	var narrow := Vector2i(scale.x, scale.x + (scale.y - scale.x) / 2)
	var mid := scale.x + (scale.y - scale.x) / 2
	var on_real := AssayTrack.reading_span(mid, mid, scale, AssayTrack.WIDTH_PX)
	var on_narrow := AssayTrack.reading_span(mid, mid, narrow, AssayTrack.WIDTH_PX)
	if is_equal_approx(on_real.x, on_narrow.x):
		return _fail(("the same reading lands at x=%.2f on %s and on %s, so the scale is not what "
				+ "places the mark: some constant in the client is") % [on_real.x, scale, narrow])
	# AND THE TOP OF WHATEVER SCALE IS HANDED OVER REACHES THE RIGHT-HAND END, so the axis is read as
	# inclusive at both ends the way `reading_scale()`'s docstring says it is.
	var top := AssayTrack.reading_span(narrow.y, narrow.y, narrow, AssayTrack.WIDTH_PX)
	if not is_equal_approx(top.x + top.y, AssayTrack.WIDTH_PX):
		return _fail(("the top of the scale %s ends at %.2f, not at the axis's right edge %.0f: the "
				+ "scale's ends are inclusive") % [narrow, top.x + top.y, AssayTrack.WIDTH_PX])
	return true
