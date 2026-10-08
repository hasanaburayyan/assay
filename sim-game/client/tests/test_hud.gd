extends RefCounted
## THE HUD'S RULES, AS TESTS. Every design ruling that can be checked without a screen is checked
## here, because the alternative is a comment claiming the rule and a `_draw` quietly breaking it --
## which is exactly what happened to deposit colour: I shipped purity riding on R and G, Maren
## measured it swinging the HUE 130 degrees, and nothing in the suite had an opinion.
##
## Nothing here touches the sim. `AssayHud` takes dictionaries the sim already decided and turns them
## into words and colours; that is all these tests exercise.

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## PURITY IS BRIGHTNESS, SPECIES IS HUE, NEVER BOTH ON ONE CHANNEL (Maren's ruling, 2026-10-02).
## Purity must not move the hue at all: hue is the channel species needs, and six species plus purity
## are two variables that need two channels.
## I AM NO LONGER ASSERTING THE CROSS-SPECIES HALF OF THIS, and that is a correction rather than a
## weakening. The old version also required a grade-A patch of ANY species to outshine an impure patch
## of any other, which was true only because every hue was mixed at one fixed value. Cove's table
## does not share one value by design, so the claim is now false in general (yellow at purity 70
## outshines purple at 100) and a test asserting it would be a test of a scheme we no longer ship.
## What survives is the rule Maren actually gave: WITHIN a species, purity is brightness and nothing
## else, and it never touches hue.
func test_purity_is_brightness_and_never_touches_hue() -> bool:
	for species in range(AssayHud.SPECIES_TINTS.size()):
		var last_value := -1.0
		var first := AssayHud.deposit_color(species, 1)
		for purity in [1, 20, 40, 60, 80, 100]:
			var colour := AssayHud.deposit_color(species, purity)
			if absf(colour.h - first.h) > 0.001:
				return _fail(("species %d: purity %d moved the hue to %f, from %f. Purity may only "
						+ "move brightness.") % [species, purity, colour.h, first.h])
			if absf(colour.s - first.s) > 0.001:
				return _fail("species %d: purity %d moved saturation to %f, from %f"
						% [species, purity, colour.s, first.s])
			if colour.v <= last_value:
				return _fail("species %d: purity %d is no brighter than the purity below it: %f, after %f"
						% [species, purity, colour.v, last_value])
			if colour.s < 0.4:
				return _fail(("species %d: saturation is %f. A washed-out patch is the hardest "
						+ "thing on the map to see; that was the first bug.") % [species, colour.s])
			last_value = colour.v
	return true


## EVERY SPECIES GETS THE TABLE'S SLOT, AND NOTHING COMPUTES A HUE. This replaces
## `test_every_species_gets_its_own_hue`, which asserted six evenly spaced hues: that was Maren's
## 30-degree bar, Cove measured the scheme at dE 5.7 for a protan viewer against a floor of 12, and
## Decision #36 retired both the scheme and the bar. The slot table cannot satisfy the old bar and
## must not be bent to -- two of Okabe-Ito's survivors are the SAME hue.
##
## The separation itself is measured in Python, at true size, against real terrain, under three kinds
## of colour blindness (`art/species_probe.py`). It is not reimplemented here: a second instrument in
## GDScript would be a second opinion about the one number that matters, and a weaker one.
func test_every_species_gets_the_tables_slot() -> bool:
	for species in range(AssayHud.SPECIES_TINTS.size()):
		var wanted := Color(AssayHud.SPECIES_TINTS[species])
		var got := AssayHud.deposit_color(species, 100)
		# Purity 100 is the undimmed slot, so the colour on screen is the table's, not near it.
		for channel in [[wanted.r, got.r], [wanted.g, got.g], [wanted.b, got.b]]:
			if absf(channel[0] - channel[1]) > 0.002:
				return _fail("species %d at full purity drew %s, not its slot %s"
						% [species, got, wanted])
	# A species id past the end of the table must still produce a colour rather than index out of
	# bounds: a client can draw a frame before it has the roster, and a crashed frame is worse than
	# a repeated colour. The roster never actually exceeds the table -- `test_sim_binding.gd` holds
	# the sim's own count to this length -- so this is the seatbelt, not the mechanism.
	if AssayHud.deposit_color(9, 50) != AssayHud.deposit_color(3, 50):
		return _fail("a species id past the table did not wrap onto a slot")
	return true


## THE DISC THE PROBE CERTIFIED IS THE DISC WE DRAW. This is the only test here that pins a constant,
## and the reason is that the measurement lives somewhere CI never goes: `art/species_probe.py` is not
## in the workflow, so the two numbers Maren ruled on (ASSA-7, 2026-10-02) are guarded by a script
## nobody runs unless they are already thinking about colour.
##
## It does NOT re-measure colour separation, and it must never grow into that -- the dE figure belongs
## to one instrument, in Python, against real terrain, under four observers. What it guards is the
## thing that actually went wrong twice: the instrument was pointed at a surface the client did not
## draw. Cove's probe scored a disc it modelled as opaque while we shipped alpha 0.85, and Maren's
## 0.55 was measured flat for the same reason; both read "fine" for a disc that was really 10.8 at
## purity 6, under the floor of 12. So:
##   - ALPHA 1.0, because the certified number is only true of an opaque disc. Nothing is ever drawn
##     under a deposit on this map, so there is nothing to see through it.
##   - THE DIMMEST DISC AT 0.62 of its slot (base 0.60, purity clamped to 0.05). Measured at 14.0;
##     putting this base back on the old alpha scores 11.8 and 0.33 scores 8.8.
## Either one drifting invalidates the measurement rather than merely changing a look, and a failure
## here means: re-run the probe, do not retune the number.
func test_the_map_disc_is_the_surface_the_probe_measured() -> bool:
	for species in range(AssayHud.SPECIES_TINTS.size()):
		var dimmest := AssayHud.deposit_color(species, 1)
		if dimmest.a < 1.0:
			return _fail(("species %d draws its patch at alpha %f. The colour-blindness floor was "
					+ "measured on an OPAQUE disc; anything less mixes the near-black map into every "
					+ "patch and costs 1-2 dE of chroma, which is the whole of ASSA-29.")
					% [species, dimmest.a])
		# `v` is max(r, g, b) and the dim is one multiplier on all three, so this ratio IS the
		# multiplier -- no need to know which channel the slot peaks in.
		var slot := Color(AssayHud.SPECIES_TINTS[species])
		var multiplier := dimmest.v / slot.v
		if multiplier < 0.615:
			return _fail(("species %d's dimmest patch is %f of its slot, under the measured 0.62. "
					+ "Re-run art/species_probe.py rather than lowering this: at 0.525 the worst pair "
					+ "was 11.6 and the floor is 12.") % [species, multiplier])
	return true


## WCAG RELATIVE LUMINANCE, WRITTEN OUT HERE ON PURPOSE AND NOT CALLED FROM `AssayHud`.
##
## This is the whole reason the previous version of this test was useless. It scored contrast with
## `Color.get_luminance()` -- the same quantity `glyph_color` was deciding with -- so the test and the
## bug were computing the identical wrong number and agreeing with each other. It even said so in its
## own docstring ("a consistent measure rather than a certified WCAG figure") and I shipped it anyway.
## 226 of 600 disc states had the worse glyph and this test was green about all of them.
##
## So: the piecewise sRGB transfer function, spelled out, with no call into the file under test. If
## `AssayHud.relative_luminance` and this ever disagree, one of them is wrong and the suite says so.
func _wcag_luminance(c: Color) -> float:
	var channels := [c.r, c.g, c.b]
	var lin := []
	for v: float in channels:
		lin.append(v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


func _wcag_ratio(a: Color, b: Color) -> float:
	var x := _wcag_luminance(a) + 0.05
	var y := _wcag_luminance(b) + 0.05
	return x / y if x > y else y / x


## THE LETTER TAKES THE HIGHER-CONTRAST OF THE TWO GLYPH COLOURS, AT EVERY SPECIES AND EVERY PURITY.
##
## ASSA-39, Maren's ruling (option A) and her sharpening of its acceptance. The assertion is OPTIMALITY,
## not a floor: picking the better of two is optimal by construction, so "the chosen glyph is the
## higher-ratio one" is an invariant that cannot rot, while "every state clears 3.0" is a number that
## would have to be revisited every time a tint moves -- and the tints moved twice this week. The worst
## case of the best possible picker is 4.52, which is the CEILING of this two-colour family rather than
## a target; it is printed, not asserted.
##
## SWEPT, NOT SAMPLED: all six tints x purity 1..100. The old test sampled five purities and the real
## defect was worst at purity 52 for one species and 65 for another. Cove's own correction on the item
## is worth keeping in view though -- end-sampling WOULD have caught this one, because purity 1 is
## suboptimal for three species; what hid it was sampling one species and the broken instrument above.
## Sweeping is cheap and removes the argument entirely.
func test_the_species_letter_always_takes_the_higher_contrast_colour() -> bool:
	var checked := 0
	var worst := 99.0
	var worst_at := ""
	for species in range(AssayHud.SPECIES_TINTS.size()):
		for purity in range(1, 101):
			var patch := AssayHud.deposit_color(species, purity)
			var lit := AssayHud.MAP_BG.lerp(Color(patch.r, patch.g, patch.b), patch.a)
			var dark := _wcag_ratio(lit, AssayHud.GLYPH_DARK)
			var light := _wcag_ratio(lit, AssayHud.GLYPH_LIGHT)
			var got := AssayHud.glyph_color(patch)
			var took: float = dark if got == AssayHud.GLYPH_DARK else light
			var best: float = maxf(dark, light)
			# Equal-contrast states exist (the flip points: red 72, pink 24, sky blue 47), and either
			# choice is correct there, so the comparison has to tolerate the tie rather than demand an
			# identity. 1e-6 is far below the 8-bit quantisation of any colour on screen.
			if took < best - 1e-6:
				return _fail(("species %d at purity %d took the glyph worth %f when %f was available "
						+ "(dark %f, light %f). Picking the better of two is optimal by construction, so "
						+ "this means the rule is deciding on something other than the ratio -- most "
						+ "likely a threshold on Color.get_luminance(), which is not a perceptual "
						+ "luminance. That was ASSA-39.")
						% [species, purity, took, best, dark, light])
			if took < worst:
				worst = took
				worst_at = "species %d at purity %d" % [species, purity]
			checked += 1
	if checked != 600:
		return _fail("swept %d states, expected 600" % checked)
	print("    glyph contrast: worst %f at %s (the ceiling of this pair, not a floor)"
			% [worst, worst_at])
	return true


## **A ROCK NOTHING CAN GET THE ORE OUT OF IS HATCHED, AND IT PAYS FOR THAT OUT OF NO OTHER CHANNEL**
## (ASSA-199, Maren's ruling on Cove's sheet; it replaces the hollow disc of ASSA-187). Hue is the
## species, brightness is the purity, radius is the radius; the fourth fact had nowhere to go, on the
## one surface whose job is choosing where to walk.
##
## **SWEPT, AND THE SWEEP IS THE POINT.** All six tints x purity 1..100 x both states: `colour` must
## be bit-identical to `deposit_color` in BOTH, which is box 6 ("purity, radius and the letter all
## still read") expressed as an identity rather than an opinion. A fix that dimmed or re-tinted the
## dead disc fails here, and that is the fix the ruling forbids.
##
## **AND `filled` IS TRUE IN BOTH STATES, WHICH IS BOX 4.** The old version of this test asserted
## `filled == minable` and measured the letter's contrast on `MAP_BG` for the hollow case. Both are
## gone on purpose: a hollow disc spends the fill, and the fill is where two of the three older reads
## live. The hollow being GONE rather than left underneath is a box of its own, so it is asserted here
## as well as in the picture.
##
## **THE PREDICATE IS `reach_note`, NOT `hand_minable`, AND THAT IS THE OTHER HALF OF THE ITEM.** A
## rock can be minable and still unsmeltable -- 16.3% of them over Maren's 30 seeds -- and those drew
## exactly like good ore. So the sweep runs both keys independently and asserts the mark follows the
## NOTE: a `hand_minable` rock carrying a note must still be hatched, which is the state the shipped
## code got wrong and the one a test keyed on `hand_minable` cannot see.
##
## WHAT THIS CANNOT SEE: that `main.gd::_draw` consumes any of it, or what the hatch LOOKS like.
## `test_main_screen.gd` holds the wiring, `test_the_hatch_stays_inside_its_disc` holds the geometry,
## and the picture is a GUI shot measured by `shared/assay/assa187_measure.py`.
func test_a_dead_end_rock_is_hatched_and_trades_no_other_channel() -> bool:
	var checked := 0
	var worst_ink := 99.0
	var worst_ink_at := ""
	var worst_hatch := 99.0
	var worst_hatch_at := ""
	for species in range(AssayHud.SPECIES_TINTS.size()):
		for purity in range(1, 101):
			var want := AssayHud.deposit_color(species, purity)
			# BOTH KEYS, INDEPENDENTLY. The pair that matters is minable=true with a note: a rock you
			# can dig and cannot smelt. Keying the mark on `hand_minable` passes every other case.
			for case in [{"minable": true, "note": ""}, {"minable": false, "note": "too hard to mine"},
					{"minable": true, "note": "nothing here can smelt it"},
					{"minable": false, "note": "out of reach"}]:
				var note := String(case["note"])
				var deposit := {"species": species, "purity": purity,
						"hand_minable": case["minable"], "reach_note": note}
				var disc := AssayHud.deposit_disc(deposit, 18.0)
				var colour: Color = disc["colour"]
				if colour != want:
					return _fail(("species %d at purity %d, note %s: the disc is %s and "
							+ "`deposit_color` says %s. Species and purity are the other two reads "
							+ "and this item may not spend them.") % [species, purity, note,
							colour, want])
				if not bool(disc["filled"]):
					return _fail(("species %d at purity %d, note %s: the disc is not filled. The "
							+ "hollow of #259 is GONE (box 4); the hatch keeps the fill so radius "
							+ "and purity carry at full strength.") % [species, purity, note])
				if bool(disc["hatch"]) != (note != ""):
					return _fail(("species %d at purity %d: hand_minable %s with note `%s` was "
							+ "hatched=%s. The mark follows the NOTE -- a rock you can dig and "
							+ "cannot smelt is a dead end too, and that is the one `hand_minable` "
							+ "misses.") % [species, purity, case["minable"], note, disc["hatch"]])
				# **THE HATCH INK IS ONE OF TWO NAMED COLOURS AND NEVER A THIRD** (ASSA-209). It
				# used to be the single `MAP_BG`, and because `MAP_BG` is a near-black the mark's
				# legibility was a property of the DISC, which the mark does not choose: 1.42:1 on a
				# dim purple, where absent and subtle are the same picture. It is now the better of
				# `MAP_BG` and `GLYPH_LIGHT` for that fill, which spends no new literal.
				var hatch: Color = disc["hatch_ink"]
				if hatch != AssayHud.MAP_BG and hatch != AssayHud.GLYPH_LIGHT:
					return _fail(("species %d at purity %d: the hatch ink is %s, which is neither "
							+ "MAP_BG nor GLYPH_LIGHT. A map whose named set exists to be countable "
							+ "may not grow a colour here.") % [species, purity, hatch])
				var on_bg := _wcag_ratio(colour, AssayHud.MAP_BG)
				var on_white := _wcag_ratio(colour, AssayHud.GLYPH_LIGHT)
				var hatch_took: float = on_bg if hatch == AssayHud.MAP_BG else on_white
				if hatch_took < maxf(on_bg, on_white) - 1e-6:
					return _fail(("species %d at purity %d: the hatch took the ink worth %f when %f "
							+ "was on the table. Picking the better of two is optimal by "
							+ "construction; a threshold would be tuned to today's six tints.")
							% [species, purity, hatch_took, maxf(on_bg, on_white)])
				if note != "":
					worst_hatch = minf(worst_hatch, hatch_took)
					if hatch_took <= worst_hatch + 1e-9:
						worst_hatch_at = "slot %d (%s) at purity %d" \
								% [species, AssayHud.SPECIES_TINTS[species], purity]
				# **THE LETTER IS JUDGED ON THE FILL IN BOTH STATES, AND THAT IS A STATEMENT ABOUT
				# THE PICKER, NOT ABOUT THE PICTURE.** This asserts `glyph_color` takes the better of
				# the two inks against the fill it was handed -- optimal by construction, and that is
				# all it can mean. It said "and since #293 that is true of the picture too", on the
				# grounds that the bed restores the bare fill; **ASSA-218 measured the drawn bed at
				# 4.35:1 where the fill is 9.20:1**, so the picture does not follow and this test
				# cannot see it. Nothing headless rasterises a glyph; the picture is a window shot.
				var under := colour
				var dark := _wcag_ratio(under, AssayHud.GLYPH_DARK)
				var light := _wcag_ratio(under, AssayHud.GLYPH_LIGHT)
				var ink: Color = disc["ink"]
				var took: float = dark if ink == AssayHud.GLYPH_DARK else light
				if took < maxf(dark, light) - 1e-6:
					return _fail(("species %d at purity %d, note `%s`: the letter took the ink worth "
							+ "%f when %f was there, on the surface it is actually drawn on.")
							% [species, purity, note, took, maxf(dark, light)])
				worst_ink = minf(worst_ink, took)
				if took <= worst_ink + 1e-9:
					worst_ink_at = "slot %d (%s) at purity %d, %s" % [species,
							AssayHud.SPECIES_TINTS[species], purity,
							"hatched" if note != "" else "clean"]
				checked += 1
	if checked != 2400:
		return _fail("swept %d states, expected 2400" % checked)
	# **THE FLOOR, AT THE WORST PAIR, AND THE FAILURE NAMES THE SPECIES** (ASSA-209 box 6: "it must
	# name the worst species pair, not an average"). 3.0:1 is chosen as a floor the SHIPPED ink fails
	# by a wide margin (1.42:1 on a dim purple, 1.43:1 on a dim M-blue) and the two-value ink clears
	# by a wide margin (4.13:1) -- so it is a bar, not a tuning, and no reading of the arithmetic puts
	# the old code the right side of it. It is NOT 4.5: WCAG AA is a rule about text, and this is a
	# 1.41px diagonal stroke at 28.6% coverage, which that number was never written about.
	if worst_hatch < 3.0:
		return _fail(("THE DEAD-END HATCH IS BELOW THE FLOOR ON ITS WORST PAIR: %.2f:1 at %s, floor "
				+ "3.00:1. The ink is near-black, so on a dark species the mark is not subtle, it is "
				+ "ABSENT -- and the disc then says `good ore` to a player who cannot work it. 79%% "
				+ "of worlds hold at least one purple or M-blue dead end (Maren, 400 seeds).")
				% [worst_hatch, worst_hatch_at])
	# **NO FLOOR ON THE LETTER, ON PURPOSE, and that is Maren's sharpening on ASSA-39 rather than my
	# choice.** Picking the better of two inks is optimal by construction, so the assertion that holds
	# is the one above -- "the chosen ink is the higher-ratio one at every state" -- and 4.5152 is the
	# CEILING of this two-colour family, not a target. A floor here would rot the moment a tint moves.
	print("    hatch vs fill: worst %.2f:1 at %s (floor 3.00, shipped ink was 1.42)"
			% [worst_hatch, worst_hatch_at])
	print("    disc letter:   worst %.2f:1 at %s, on the surface it is drawn on"
			% [worst_ink, worst_ink_at])
	return true


## **THE HATCH ONLY EVER REPAINTS PIXELS INSIDE ITS OWN DISC, AND AT THE RULED DENSITY** (ASSA-199
## box 2 and Cove's constraint). The ink is `MAP_BG`, so a stroke that overshot the circle would paint
## the map's own ground over a neighbour, over a player, or over the antialiased edge the whole mark
## is supposed to leave alone -- and on open ground it would be invisible while doing it.
##
## **THE DENSITY IS CHECKED AS AREA, WHICH IS THE NUMBER MAREN RULED ON.** Cove's sheet is the pixel
## rule `(x + y) % 7 < 2` = 2/7 = 28.6% of a disc, and they measured 22.2-27.1% on real hatched discs.
## Their prose also says "2px wide", which PERPENDICULAR would be 40% -- half again as much ink as the
## picture she approved. So the strokes' area over the disc's area has to land near 2/7, and the
## tolerance is wide because the chord inset and the rasteriser both take a little off.
func test_the_hatch_stays_inside_its_disc() -> bool:
	for radius: float in [9.0, 18.0, 27.0, 36.0]:
		for at: Vector2 in [Vector2(100.0, 200.0), Vector2(541.5, 631.5), Vector2(64.3, 17.9)]:
			var strokes := AssayHud.hatch_segments(at, radius)
			if strokes.size() < 4 or strokes.size() % 2 != 0:
				return _fail(("a radius-%.0f disc at %s got %d hatch points: it must be pairs, and a "
						+ "disc with no strokes is a dead end drawn as good ore")
						% [radius, at, strokes.size()])
			var width := float(AssayHud.HATCH_ON) / sqrt(2.0)
			var area := 0.0
			for i in range(0, strokes.size(), 2):
				var a := strokes[i]
				var b := strokes[i + 1]
				# EVERY CORNER OF THE STROKE'S QUAD, because `draw_line` is a quad and it is the
				# CORNERS that leave a circle, not the endpoints a reader checks.
				var out := (b - a).normalized().orthogonal() * width * 0.5
				for corner: Vector2 in [a + out, a - out, b + out, b - out]:
					if corner.distance_to(at) > radius + 0.01:
						return _fail(("a hatch stroke on the radius-%.0f disc at %s reaches %s, "
								+ "%.2fpx outside it. MAP_BG outside a disc paints the map's own "
								+ "ground over whatever is there.")
								% [radius, at, corner, corner.distance_to(at) - radius])
				area += a.distance_to(b) * width
			var share := area / (PI * radius * radius)
			var want := float(AssayHud.HATCH_ON) / float(AssayHud.HATCH_PERIOD)
			if absf(share - want) > 0.06:
				return _fail(("the hatch covers %.1f%% of the radius-%.0f disc at %s; the ruled "
						+ "density is %d in %d = %.1f%%. Cove's prose says 2px wide, which "
						+ "perpendicular would be 40%% -- this is the sheet's density, not that.")
						% [share * 100.0, radius, at, AssayHud.HATCH_ON, AssayHud.HATCH_PERIOD,
						want * 100.0])
	return true


## AND THE ENGINE'S LINEARISATION IS THE ONE WCAG SPECIFIES, which the rule above leans on entirely.
## `AssayHud.relative_luminance` uses `Color.srgb_to_linear()`; this checks it against the formula
## written out in `_wcag_luminance`, over every value an 8-bit channel can hold. Measured rather than
## assumed, because "the engine surely does the standard thing" is how the old 0.221 comment happened.
func test_the_engines_linearisation_is_the_wcag_one() -> bool:
	var worst := 0.0
	var worst_at := 0
	for i in range(0, 256):
		var v := float(i) / 255.0
		var grey := Color(v, v, v)
		var gap := absf(AssayHud.relative_luminance(grey) - _wcag_luminance(grey))
		if gap > worst:
			worst = gap
			worst_at = i
	if worst > 1e-5:
		return _fail(("Color.srgb_to_linear() is not the WCAG transfer function: channel %d is off by "
				+ "%f. glyph_color's choice is only meaningful if this holds.") % [worst_at, worst])
	return true


## A GLYPH THAT DOES NOT FIT ITS OWN PATCH IS WORSE THAN NO GLYPH -- it reads as a label for the tile
## next door. So `glyph_size` returns 0 rather than something tiny, and a one-tile deposit on a huge
## world is a colour only.
func test_a_letter_too_big_for_its_patch_is_not_drawn() -> bool:
	for radius in [0.0, 1.0, 3.0, 7.0]:
		if AssayHud.glyph_size(radius) != 0:
			return _fail("a patch of radius %f was given a %d px letter, which cannot fit"
					% [radius, AssayHud.glyph_size(radius)])
	var last := 0
	for radius in [8.0, 12.0, 20.0, 40.0, 400.0]:
		var size := AssayHud.glyph_size(radius)
		if size < 10:
			return _fail("a patch of radius %f got a %d px letter, under the legible floor"
					% [radius, size])
		if float(size) > radius * 1.5:
			return _fail("a %d px letter overflows a patch of radius %f" % [size, radius])
		if size < last:
			return _fail("a bigger patch got a smaller letter (%d after %d)" % [size, last])
		last = size
	if AssayHud.glyph_size(400.0) != 32:
		return _fail("a huge patch is mostly typography: %d px" % AssayHud.glyph_size(400.0))
	return true


## **TWO MACHINES SIDE BY SIDE: THE YOUNGER ONE'S KEYLINE LANDS ON THE OLDER ONE'S BAND, AND WHAT
## SETTLES IT IS THE PAINT ORDER** (ASSA-289, under Maren's rule 11.39: *where two marks overlap, the
## keyline yields and the ink does not*).
##
## **BOX 1 AS WRITTEN CANNOT PASS AND I SAY SO RATHER THAN RE-WORD IT QUIETLY.** It asks for a test on
## `building_mark` alone that fails before the change and passes after — which presumes the *inward
## keyline* mechanism, where the geometry stops overlapping. Two passes do not move a pixel of
## geometry: the overlap is still there, and the band is simply painted after every keyline. So this
## test holds BOTH halves, and only the second one can change:
##
## 1. **The overlap is real and is measured here**, not taken from the item. Two legal adjacent 2x2
##    footprints at cell 9 (no occupancy conflict — the normal thing anyone building a factory does).
##    If it ever stops overlapping, this fails as a stale test rather than passing vacuously.
## 2. **`_draw` paints every machine's outward keyline before any machine's band** — two loops over
##    `shapes`, not one. Nothing headless can read a `draw_rect` back off a canvas, so the order is a
##    source scan, which is exactly the cost Maren named for this mechanism: *"makes paint order
##    load-bearing for a correctness property, which is the kind of thing that dies in a refactor
##    with no test."* This is the test.
func test_two_adjacent_machines_paint_every_keyline_before_any_band() -> bool:
	var cell := 9.0
	var origin := AssayHud.MARGIN
	# Maren's own case, from her probe: 2x2 at (54,56) and (56,56).
	var older := AssayHud.building_mark({"pos": Vector2i(54, 56), "footprint": Vector2i(2, 2)},
			cell, origin)
	var younger := AssayHud.building_mark({"pos": Vector2i(56, 56), "footprint": Vector2i(2, 2)},
			cell, origin)
	var bands: Array[Rect2] = AssayHud.frame_bands(older["rect"], float(older["stroke"]))
	var rims: Array[Rect2] = AssayHud.frame_bands(younger["keyline_rect"], AssayHud.MARK_KEYLINE_PX)
	var band_px := 0
	var eaten := 0
	for band in bands:
		var y := band.position.y + 0.5
		while y < band.end.y:
			var x := band.position.x + 0.5
			while x < band.end.x:
				band_px += 1
				for rim in rims:
					if rim.has_point(Vector2(x, y)):
						eaten += 1
						break
				x += 1.0
			y += 1.0
	if band_px <= 0:
		return _fail("the older machine's frame has no band pixels at all, so this test is vacuous")
	if eaten <= 0:
		return _fail(("two adjacent 2x2 machines no longer overlap: the younger one's keyline covers "
				+ "none of the older one's %d band px. If the geometry changed on purpose, this test "
				+ "is stale and the paint-order scan below is guarding nothing.") % [band_px])
	# **THE ORDER, AND IT IS THE ONLY HALF A CHANGE CAN BREAK.**
	var source := FileAccess.get_file_as_string("res://scripts/main.gd")
	if source == "":
		return _fail("main.gd could not be read, so the order scan says nothing")
	var first_loop := source.find("for shape_entry in shapes:")
	var second_loop := source.find("for shape_entry in shapes:", first_loop + 1)
	var rim_at := source.find("AssayHud.mark_ink_of(&\"building_keyline\", shape[\"keyline\"])")
	var band_at := source.find("AssayHud.mark_ink_of(&\"building\", shape[\"colour\"])")
	if first_loop < 0 or rim_at < 0 or band_at < 0:
		return _fail(("`_draw` no longer paints a machine's keyline (%d) and band (%d) out of a loop "
				+ "over `shapes` (%d) through the map's table, so this scan says nothing")
				% [rim_at, band_at, first_loop])
	if second_loop < 0:
		return _fail(("`_draw` paints machine keylines and bands in ONE loop over `shapes`, so a "
				+ "younger machine's keyline is painted over an older machine's band: %d of its %d "
				+ "band px (%.1f%%) on two legal adjacent 2x2 footprints. Rule 11.39 says the "
				+ "keyline yields and the ink does not, so every keyline goes in a first pass and "
				+ "every band in a second.") % [eaten, band_px, 100.0 * float(eaten) / float(band_px)])
	if not (first_loop < rim_at and rim_at < second_loop and second_loop < band_at):
		return _fail(("the two building passes are out of order: first loop@%d, keyline@%d, second "
				+ "loop@%d, band@%d. The outward keyline belongs to the FIRST pass and the band to "
				+ "the SECOND, or a neighbour's rim eats a band again (%d of %d px).")
				% [first_loop, rim_at, second_loop, band_at, eaten, band_px])
	return true


## **`MIN_DEPOSIT_RADIUS_TILES` IS A SIM FACT LIVING IN A CLIENT CONSTANT, SO IT IS CHECKED AGAINST
## THE SIM** (ASSA-293). The held letter's whole justification is that it fits the narrowest patch
## `worldgen` can roll; `sim/src/worldgen.rs` rolls `rng.range(2, 5)` and there is no named constant
## on the Rust side to ask and nothing that crosses the GDExtension. So this asks the real roster:
## twelve seeds of real deposits, and none of them may be narrower than the number the letter is
## sized for. A one-tile patch would mean every letter on the map overflows its own rock, and the
## only thing that notices is this.
##
## **AND THE SPREAD, which is the other half.** If worldgen ever rolled ONE radius, ASSA-293 would be
## a defect about nothing and `test_main_screen.gd`'s frame assertion would pass by accident. Over a
## dozen seeds there must be at least two.
func test_the_held_letter_fits_the_smallest_patch_the_sim_rolls() -> bool:
	var host := AssaySimHost.new()
	var radii := {}
	var worlds := 0
	var smallest := 99
	for seed_text: String in ["63", "777042", "1", "7", "42", "100", "2026", "31337", "555",
			"90210", "8", "12345"]:
		var welcome := AssaySimHost.fresh_welcome_json(seed_text, "cove")
		if welcome == "" or not host.start(welcome):
			continue
		worlds += 1
		for entry in host.deposits():
			var deposit: Dictionary = entry
			var radius := int(deposit.get("radius", 1))
			radii[radius] = int(radii.get(radius, 0)) + 1
			smallest = mini(smallest, radius)
	if worlds < 6:
		return _fail(("premise: only %d of twelve seeds built a world, so this says nothing about "
				+ "what worldgen rolls (is the GDExtension loaded?)") % [worlds])
	if smallest < AssayHud.MIN_DEPOSIT_RADIUS_TILES:
		return _fail(("worldgen rolled a radius-%d patch over %d seeds and the species letter is held "
				+ "at the size that fits radius %d (%d px at cell 9). Every letter on the map now "
				+ "overflows that rock and reads as a label for the tile next door -- `glyph_size`'s "
				+ "own rule. Lower MIN_DEPOSIT_RADIUS_TILES to %d or ask the sim why it shrank.")
				% [smallest, worlds, AssayHud.MIN_DEPOSIT_RADIUS_TILES,
				AssayHud.glyph_size_held(9.0), smallest])
	if radii.size() < 2:
		return _fail(("worldgen rolls one deposit radius (%s) over %d seeds, so holding the letter "
				+ "constant is a fix for a channel that never varied, and the frame test in "
				+ "test_main_screen.gd passes by accident") % [radii.keys(), worlds])
	# The held size must clear the legible floor at the cell the schematic actually uses, or the map
	# draws no letters at all and three other tests are about nothing.
	if AssayHud.glyph_size_held(9.0) <= 0:
		return _fail("the held letter is not drawn at all at the shipped cell of 9 px")
	return true


## **THE COST OF THE HELD LETTER IS A SENTENCE IN `hud.gd`, AND THIS IS WHAT STOPS IT ROTTING**
## (ASSA-320, on ASSA-293). Holding every letter at the smallest patch's size hands `glyph_size`'s
## 10px floor one decision for the whole map: past a world size the cell falls under 4px and NO letter
## draws, where the wide patches used to keep theirs. `glyph_size_held(9.0) > 0` is asserted one test
## up -- the shipped cell draws -- and the flip itself was prose.
##
## **THE NUMBER IS DERIVED AND THEN HELD AGAINST THE DOCSTRING, never typed into this test.** A change
## to the floor, to `MIN_DEPOSIT_RADIUS_TILES` or to the map rect moves the flip; the sentence in
## `hud.gd` would go on reading as fact, and in this repo prose is what has shipped wrong twice
## (ASSA-174, ASSA-207). So the sweep finds the widest world that still draws a letter and the
## docstring has to name it.
##
## 228 is the answer today and the arithmetic is worth having written down, because I got it wrong
## once: a letter needs `floor(2.8 x cell) >= 10`, i.e. cell >= 3.58 -- but `map_cell` FLOORS to a
## whole pixel, so 3.58 is DRAWN as 3 and the real flip is at cell 4. 912/4 = 228. Dividing the map
## rect by a cell the map never draws gives 304, which is what my note on ASSA-293 said.
func test_the_world_size_where_letters_stop_is_the_one_the_docstring_names() -> bool:
	# The floor, at the two cells either side of it, before any sweep: a letter at 4px of cell and
	# nothing at 3px is what makes the width below a width and not an accident of the loop.
	if AssayHud.glyph_size_held(4.0) <= 0:
		return _fail("a 4px cell draws no letter, so the flip is not where hud.gd says it is")
	if AssayHud.glyph_size_held(3.0) != 0:
		return _fail("a 3px cell still draws a %d px letter: the 10px floor has moved and the cost "
				% AssayHud.glyph_size_held(3.0) + "named in hud.gd is now about something else")
	# **THE SWEEP IS OVER WORLDS, NOT OVER CELLS**, because the sentence is about world size and
	# `map_cell` is the only thing that turns one into the other. Height held at the tallest world the
	# same cell survives, so the width is the term that bites -- the map rect is wider than it is tall.
	var tallest := 168
	var widest := 0
	for width in range(16, 400):
		if AssayHud.glyph_size_held(AssayHud.map_cell(Vector2i(width, tallest))) > 0:
			widest = width
		else:
			break
	if widest <= 96:
		return _fail(("letters stop at %d tiles wide, which is the test world (96) or narrower: the "
				+ "shipped map would have no letters on it at all") % widest)
	var source := FileAccess.get_file_as_string("res://scripts/hud.gd")
	if source == "":
		return _fail("scripts/hud.gd could not be read, so this test is about nothing")
	if not source.contains(str(widest)):
		return _fail(("letters stop past %d tiles wide and `hud.gd` does not say %d anywhere. The "
				+ "held letter's cost is documented there as a number; derive it, do not guess it -- "
				+ "and `map_cell` floors, so it is not the map rect over 3.58.") % [widest, widest])
	return true


## THE MAP MUST NOT RUN UNDER THE HUD. The panel's width comes out of the map's width term, so the map
## shrinks (Maren's ruling). Checked at several world sizes, including one far too big to fit.
func test_the_map_always_stops_short_of_the_hud_column() -> bool:
	for size in [Vector2i(96, 64), Vector2i(16, 16), Vector2i(400, 20), Vector2i(2000, 2000)]:
		var cell := AssayHud.map_cell(size)
		if cell <= 0.0:
			return _fail("a %s world got cell size %f" % [size, cell])
		var right := AssayHud.MARGIN.x + float(size.x) * cell
		var column := AssayHud.VIEW.x - AssayHud.PANEL - AssayHud.MARGIN.x
		# A world too big for the view is clamped to 2px per tile and will overrun; that is a known
		# limit of drawing without a camera, not a layout bug. Everything that fits must stay clear.
		if cell > 2.0 and right > column:
			return _fail("a %s world is drawn to x %f, under a HUD column starting at %f"
					% [size, right, column])
	if AssayHud.map_cell(Vector2i.ZERO) != 0.0:
		return _fail("a world with no tiles got a cell size")
	return true


func test_an_empty_inventory_says_so_rather_than_showing_nothing() -> bool:
	var lines := AssayHud.inventory_lines([])
	if lines.size() != 1 or not lines[0].contains("nothing"):
		return _fail("an empty inventory read as %s" % [lines])
	return true


func test_an_inventory_line_carries_the_count_and_the_sims_own_item_name() -> bool:
	var lines := AssayHud.inventory_lines([
		{"count": 7, "name": "kuri ore (B)", "kind": "ore", "grade": "B"},
		{"count": 1, "name": "kuri smelter (C)", "kind": "smelter", "grade": "C"},
	])
	if lines.size() != 2:
		return _fail("two stacks read as %d lines" % lines.size())
	if not (lines[0].contains("7") and lines[0].contains("kuri ore (B)")):
		return _fail("a stack line lost its count or its name: %s" % lines[0])
	return true


## The cursor is off the map most of the time, and the readout has to say so. Showing tile (0, 0)
## instead would be an answer to a question nobody asked.
func test_a_tile_off_the_map_says_so() -> bool:
	var lines := AssayHud.tile_lines({"in_bounds": false, "pos": Vector2i(-3, 9)})
	if lines.size() != 1 or not lines[0].contains("off the map"):
		return _fail("an out-of-bounds tile read as %s" % [lines])
	if not AssayHud.tile_lines({}).is_empty():
		return _fail("no tile at all should produce no lines")
	return true


## A ROUGH SHEET MUST NAME WHAT WOULD SETTLE IT. Every number about an unassayed species is a 25-wide
## band, and the whole game is named after the action that fixes that, so "rough" without "assay" is
## half a sentence.
func test_an_unassayed_deposit_names_the_action_that_settles_it() -> bool:
	var rough := AssayHud.tile_lines(_tile_with({"assayed": false}))
	var joined := "\n".join(rough)
	if not joined.contains("assay"):
		return _fail("an unassayed deposit never mentions assaying: %s" % joined)
	var exact := "\n".join(AssayHud.tile_lines(_tile_with({"assayed": true})))
	if exact.contains("rough"):
		return _fail("an assayed deposit still calls its sheet rough: %s" % exact)
	if not exact.contains("exact"):
		return _fail("an assayed deposit does not say its sheet is exact: %s" % exact)
	return true


## SPECIES MUST BE READABLE WITHOUT COLOUR. Evenly spaced hues cannot carry species for a colour-blind
## player and two of six will collide, so the name has to be in the words -- Maren's limit, and the
## readout is where it is paid.
func test_the_readout_names_the_species_and_its_grade_in_words() -> bool:
	var lines := "\n".join(AssayHud.tile_lines(_tile_with({})))
	for wanted in ["kuri", "purity 62", "grade B", "deposit 4"]:
		if not lines.contains(wanted):
			return _fail("the readout is missing %s: %s" % [wanted, lines])
	return true


func test_a_depleted_deposit_and_a_building_and_who_is_here_all_show() -> bool:
	var tile := _tile_with({"depleted": true, "amount": 0})
	# FIXTURE GIVEN THE `name` THE BINDING ALWAYS SENDS (ASSA-244). It had only
	# `kind`, so it exercised `tile_lines`' older-host fallback while asserting
	# `smelter 2` — the bare kind plus an index, which is the pair ASSA-136 and
	# ASSA-222 forbid. This test is about three facts all appearing, not about
	# which wording, so it anchors on the sim's noun now.
	tile["building"] = {"id": 2, "kind": "smelter", "name": "Tonore smelter (A)",
			"pos": Vector2i(10, 9), "status": "no fuel"}
	tile["players_here"] = PackedStringArray(["ada", "limpet"])
	var lines := "\n".join(AssayHud.tile_lines(tile))
	for wanted in ["DEPLETED", "Tonore smelter (A)", "no fuel", "ada, limpet"]:
		if not lines.contains(wanted):
			return _fail("the readout is missing %s: %s" % [wanted, lines])
	return true


## A BUILDING IS NAMED THE WAY EVERY OTHER OBJECT IS (Maren, ASSA-136). The words are the sim's
## (`debug::building_name`, which the halted table and sim-cli's tile line also call); this only
## pins that the window SHOWS them, because the species in that name is the one that caps the fire,
## the one that comes back in your pack, and the one a sprite's tint is claiming.
func test_a_standing_building_is_named_by_its_material_and_not_by_its_kind() -> bool:
	var tile := _tile_with({})
	tile["building"] = {"id": 2, "kind": "smelter", "name": "Tonore smelter (A)",
			"pos": Vector2i(10, 9), "status": "walls 73 · no fuel"}
	var lines := "\n".join(AssayHud.tile_lines(tile))
	# NO LONGER `"... (A) 2"`: the BuildingId left this line on ASSA-244, because a reader who
	# points has nothing to type it into (Maren, ASSA-222). The id's absence is asserted below.
	if not lines.contains("Tonore smelter (A)"):
		return _fail("the building is not named: %s" % lines)
	if lines.contains("Tonore smelter (A) 2"):
		return _fail("the BuildingId is still appended to the noun: %s" % lines)
	if not lines.contains("walls 73"):
		return _fail("the status went missing with the rename: %s" % lines)
	# THE OLD SHAPE MUST BE GONE, not merely accompanied: `smelter 2` beside the name would be the
	# bare noun still being shown, which is the thing this fixes.
	if lines.contains("\nsmelter 2") or lines.begins_with("smelter 2"):
		return _fail("the bare kind is still being shown: %s" % lines)
	# AND A DICT WITHOUT A NAME STILL READS. A host older than this field is a protocol mismatch
	# the client already refuses, so this is belt and braces, not a supported state.
	var old := _tile_with({})
	old["building"] = {"id": 7, "kind": "machine", "pos": Vector2i(1, 1), "status": "idle"}
	if not "\n".join(AssayHud.tile_lines(old)).contains("machine 7"):
		return _fail("a building with no name must still be addressable")
	return true


## One bare tile, with `extra` overriding any field: no deposit, nothing on it, and the sim's own
## word for its ground. `ground_note` is held to the real binding by
## `test_the_tile_fixture_still_matches_a_real_tile`.
func _bare_tile(extra: Dictionary) -> Dictionary:
	var tile := {"in_bounds": true, "pos": Vector2i(1, 2), "chunk": Vector2i(0, 0),
			"chunks_from_spawn": 3, "is_spawn": false, "ground_note": "no deposit here",
			"deposit": null, "building": null, "players_here": PackedStringArray()}
	for key in extra:
		tile[key] = extra[key]
	return tile


## THE GROUND LINE IS THE SIM'S WORD, AND A BUILDING CANNOT MAKE IT FALSE (Maren, ASSA-146).
##
## This file used to assert the literal `empty ground`, which was the bug: the phrase carried two
## facts (*no deposit* and *nothing here*) and the building below it is appended by a block that
## does not know this one ran, so the cursor section read "empty ground" directly above
## "Minyte smelter (B) 0 · walls 29 · …". Three surfaces spelled that phrase; now none do.
func test_the_ground_line_never_calls_an_occupied_tile_empty() -> bool:
	var bare := AssayHud.tile_lines(_bare_tile({}))
	if bare.size() != 2 or not String(bare[1]).contains("no deposit here"):
		return _fail("a bare tile read as %s" % [bare])

	# THE BUG ITSELF, AS A COMPARISON RATHER THAN A SEARCH. Putting a building on the tile must
	# APPEND a line and change nothing above it -- which says both halves at once: the ground
	# fact is still there (it is not deleted to buy the silence) and it is the same sentence a
	# bare tile gets, so it cannot have been a claim about occupancy.
	#
	# Not a search for "empty" across the read, either: a smelter's own status says `in empty ·
	# … · out empty` about its two SLOTS -- true, and nothing to do with the tile. That check
	# would fail on the fix.
	var occupied := AssayHud.tile_lines(_bare_tile({"building": {"id": 0, "kind": "smelter",
			"name": "Minyte smelter (B)", "pos": Vector2i(1, 2),
			"status": "walls 29 · in empty · fuel 9 Minyte ore (B) · out empty · idle"}}))
	if occupied.size() != bare.size() + 1:
		return _fail("a building should add one line to %s, got %s" % [bare, occupied])
	for i in range(bare.size()):
		if occupied[i] != bare[i]:
			return _fail("line %d changed when a building appeared: %s became %s"
					% [i, bare[i], occupied[i]])
	if String(occupied[1]).contains("empty"):
		return _fail("the ground line calls an occupied tile empty: %s" % occupied[1])
	# The id dropped off this line on ASSA-244; the noun is what makes the premise.
	if not String(occupied[2]).contains("Minyte smelter (B)"):
		return _fail("the fixture must still name the building, or this proves nothing: %s"
				% [occupied])

	# VERBATIM, OR THE CLIENT IS STILL WORDING THE GROUND. A sentence no file in this repo
	# composes can only have come from the dict, so this fails the moment hud.gd starts
	# deciding the words again -- which is the shape the bug had.
	var sentinel := "GROUND-SENTINEL-7"
	if not "\n".join(AssayHud.tile_lines(_bare_tile({"ground_note": sentinel}))).contains(sentinel):
		return _fail("the ground line is not rendered verbatim from the sim")

	# EMPTY MEANS SILENT, NOT BLANK. `ground_note` is empty on a deposit tile (the deposit line
	# is the ground line there), and a blank row in a four-line readout is a line a player has
	# to account for.
	for line in AssayHud.tile_lines(_bare_tile({"ground_note": ""})):
		if String(line).strip_edges() == "":
			return _fail("an empty ground note left a blank line in the readout")
	return true


## BOX 3 OF ASSA-146: THE CASE THAT WAS ALREADY RIGHT. A deposit under a building composes
## ("deposit 4 · kuri · 37 ore left" over a smelter reads correctly) and that is the half of this
## readout the fix must not touch -- the risk in wording the ground once is wording it twice.
func test_a_deposit_under_a_building_gains_no_ground_line() -> bool:
	var tile := _tile_with({})
	tile["building"] = {"id": 0, "kind": "smelter", "name": "kuri smelter (B)",
			"pos": Vector2i(10, 9), "status": "walls 41 · in empty · out empty · idle"}
	var lines := AssayHud.tile_lines(tile)
	var joined := "\n".join(lines)
	if not joined.contains("deposit 4 · kuri · 37 ore left"):
		return _fail("the deposit line went missing: %s" % joined)
	if not joined.contains("kuri smelter (B)"):
		return _fail("the building line went missing: %s" % joined)
	if joined.contains("no deposit here"):
		return _fail("a tile WITH a deposit was told it has none: %s" % joined)
	# And the same comparison the occupied-bare case makes: the building only ever appends.
	var without := AssayHud.tile_lines(_tile_with({}))
	for i in range(without.size()):
		if lines[i] != without[i]:
			return _fail("line %d changed when a building appeared: %s became %s"
					% [i, without[i], lines[i]])
	return true


## Spawn is unchanged by ASSA-146: it says what the tile IS and never claimed to be bare, so it
## composed over a building before and composes now. The word is the sim's either way.
func test_the_spawn_tile_says_spawn() -> bool:
	var spawn := AssayHud.tile_lines(_bare_tile({"pos": Vector2i(48, 32),
			"chunk": Vector2i(3, 2), "chunks_from_spawn": 0, "is_spawn": true,
			"ground_note": "spawn"}))
	if not "\n".join(spawn).contains("spawn"):
		return _fail("the spawn tile read as %s" % [spawn])
	return true


## A log keeps the NEWEST lines. Keeping the oldest is the easiest version of this to write and the
## exact opposite of a log.
func test_the_log_keeps_the_newest_lines() -> bool:
	var lines := PackedStringArray()
	for i in range(20):
		lines.append("line %d" % i)
	var kept := AssayHud.trimmed_log(lines, 5)
	if kept.size() != 5 or kept[0] != "line 15" or kept[4] != "line 19":
		return _fail("trimming 20 lines to 5 kept %s" % [kept])
	var short := AssayHud.trimmed_log(PackedStringArray(["only"]), 5)
	if short.size() != 1:
		return _fail("a short log was changed: %s" % [short])
	return true


## A FAILURE MUST NOT LOOK LIKE AN INSTRUCTION (Maren's ruling). "enter a host address and join" and
## a connection error are the same words in the same place; the colour is the only thing that can
## tell them apart, so each state needs its own.
func test_each_status_state_has_its_own_colour() -> bool:
	var seen := {}
	for level in [AssayHud.Say.IDLE, AssayHud.Say.CONNECTING, AssayHud.Say.FAILED,
			AssayHud.Say.JOINED]:
		var colour := AssayHud.status_color(level)
		var key := colour.to_html()
		if seen.has(key):
			return _fail("state %d has the same colour as state %d" % [level, seen[key]])
		seen[key] = level
	var failed := AssayHud.status_color(AssayHud.Say.FAILED)
	if failed.r <= failed.g or failed.r <= failed.b:
		return _fail("the failed colour is not red: %s" % failed)
	# **`JOINED` IS NO LONGER GREEN, AND THAT IS A RULING RATHER THAN A REGRESSION** (ASSA-233).
	# This asserted green because green meant "this went well". Since ASSA-224 the accent means
	# "press this" and belongs to the one `Primary` control, so a green readout and a green button
	# in one frame are one colour doing opposite work. What is still required of this state is that
	# it is READABLE and is not one of the two colours that carry an alarm -- an ordinary good
	# status has no business looking like a failure or like a connection in progress. Which colour
	# it IS is pinned against the theme's `INK_MUTED` in
	# `test_the_themes_borrowed_colours_are_still_the_ones_they_say_they_borrowed`.
	var joined := AssayHud.status_color(AssayHud.Say.JOINED)
	if joined.r > joined.g and joined.r > joined.b:
		return _fail("the joined colour reads as an alarm: %s" % joined)
	if AssayHud.contrast_ratio(joined, AssayHud.MAP_BG) < 4.5:
		return _fail("the joined status is %.2f:1 on the map, under the floor the theme refuses at"
				% AssayHud.contrast_ratio(joined, AssayHud.MAP_BG))
	var connecting := AssayHud.status_color(AssayHud.Say.CONNECTING)
	if connecting.b >= connecting.r or connecting.b >= connecting.g:
		return _fail("the connecting colour is not amber: %s" % connecting)
	return true


## One deposit tile, with `extra` overriding any field. Shaped exactly like `AssaySim::tile_at`.
##
## `hand_minable` true and an empty `reach_note` is the YIELDING rock, which is what the sim sends for
## one: the note is empty exactly when the rock can be worked (ASSA-47). The keys are held to the real
## binding by `test_the_deposit_fixture_still_matches_a_real_deposit`, because a fixture I typed is a
## claim about the sim and not a reading of it.
func _tile_with(extra: Dictionary) -> Dictionary:
	var deposit := {"id": 4, "species": 1, "species_name": "kuri", "center": Vector2i(10, 9),
			"radius": 3, "amount": 37, "purity": 62, "grade": "B", "depleted": false,
			"assayed": false, "hand_minable": true, "reach_note": ""}
	for key in extra:
		deposit[key] = extra[key]
	# `ground_note` EMPTY is what the sim sends for a tile whose deposit does the talking: the
	# deposit line IS the ground line there (ASSA-146). A fixture carrying a sentence here would
	# be testing a state `AssaySim::tile_at` cannot produce.
	return {"in_bounds": true, "pos": Vector2i(10, 9), "chunk": Vector2i(0, 0),
			"chunks_from_spawn": 3, "is_spawn": false, "ground_note": "", "deposit": deposit,
			"building": null, "players_here": PackedStringArray()}


## REACH IS STATED BEFORE ANY ASSAY CUE, AND A ROCK NOTHING CAN MINE IS NEVER INVITED TO BE ASSAYED.
## ASSA-47, Marlow's ask. `Assay` is not gated on the rock being workable, so a player can spend the
## 30 ticks, succeed, and learn a sheet they can never use -- you cannot build with ore you cannot get
## out. Maren measured 40.7% of deposits like that.
func test_an_unworkable_deposit_states_reach_and_offers_no_assay() -> bool:
	var note := "Noxore is too hard for anything we can build"
	var lines := AssayHud.tile_lines(_tile_with({"hand_minable": false, "reach_note": note}))
	var joined := "\n".join(lines)
	if not joined.contains(note):
		return _fail("the sim's reach note is missing from the tile line: %s" % joined)
	if joined.contains("assay to be sure"):
		return _fail(("a rock nothing can mine still invited an assay: %s. A softened cue would still "
				+ "be a cue; the clause has to go.") % joined)
	# ORDER IS PART OF THE ASK: reach before the invitation, not after it.
	var note_at := -1
	var purity_at := -1
	for i in range(lines.size()):
		if String(lines[i]).contains(note):
			note_at = i
		if String(lines[i]).begins_with("purity "):
			purity_at = i
	if note_at < 0 or purity_at < 0 or note_at > purity_at:
		return _fail("reach must be stated before the purity line; note at %d, purity at %d, in %s"
				% [note_at, purity_at, joined])
	# The facts stay. Only the offer is conditional.
	if not joined.contains("purity 62 (grade B)"):
		return _fail("purity and grade are facts about the rock and must survive: %s" % joined)
	return true


## AND THE IN-REACH LINE IS BYTE-FOR-BYTE WHAT IT WAS BEFORE ASSA-47, which is the other half of the
## ask: the change may not cost a single character on the deposits a player can actually work. Spelled
## out as a literal rather than rebuilt from the fixture, because a literal is the only version that
## can disagree with me.
func test_the_in_reach_tile_line_is_unchanged() -> bool:
	var lines := AssayHud.tile_lines(_tile_with({}))
	var joined := "\n".join(lines)
	var wanted := ("(10, 9) · chunk (0, 0) · 3 from spawn\ndeposit 4 · kuri · 37 ore left\n"
			+ "purity 62 (grade B) · sheet is rough — stand here and assay to be sure")
	if joined != wanted:
		return _fail("the in-reach tile line changed.\n  wanted: %s\n  got:    %s" % [wanted, joined])
	var assayed := "\n".join(AssayHud.tile_lines(_tile_with({"assayed": true})))
	if not assayed.contains("purity 62 (grade B) · assayed: its sheet is exact"):
		return _fail("an assayed deposit must report it, not invite one: %s" % assayed)
	return true


## AND AN UNWORKABLE ROCK THAT IS ALREADY ASSAYED STILL REPORTS IT. "Assayed" is a statement about
## something already done, not an offer, so the rule about invitations does not reach it. Without this
## the obvious implementation -- one `if hand_minable` around the whole cue -- passes the test above
## while silently dropping a fact from every unworkable rock a player did assay before learning better.
func test_an_unworkable_deposit_that_was_assayed_still_says_so() -> bool:
	var joined := "\n".join(AssayHud.tile_lines(_tile_with({
			"hand_minable": false, "reach_note": "too hard for anything we can build",
			"assayed": true})))
	if not joined.contains("assayed: its sheet is exact"):
		return _fail("an assayed unworkable deposit stopped reporting its own assay: %s" % joined)
	if joined.contains("assay to be sure"):
		return _fail("it invited a second assay: %s" % joined)
	return true


## THE CLIENT DECIDES NOTHING ABOUT WORKABILITY, STATED AS BEHAVIOUR RATHER THAN AS A GREP.
##
## Marlow's third box is `grep -nE '\b40\b|hardness' client/scripts` finding no comparison. I would
## rather not rest a rule on a text search: that grep matches a colour component (`0.40`), the grade
## bands in a comment, and every mention of ASSA-40, so a human has to read the hits and decide, which
## is exactly the judgement a test should be making.
##
## So this asserts the property the grep is a proxy for. The invitation must follow `hand_minable` and
## NOTHING ELSE: sweep purity 1..100 and every grade with the flag held fixed, and the answer may not
## move. If the client ever started working out for itself whether a rock yields -- from a hardness, a
## grade, a purity threshold -- one of these would flip.
func test_the_invitation_follows_the_sims_flag_and_nothing_else() -> bool:
	for minable in [true, false]:
		for grade in ["C", "B", "A"]:
			for purity in range(1, 101):
				var joined := "\n".join(AssayHud.tile_lines(_tile_with({
						"hand_minable": minable, "grade": grade, "purity": purity,
						"reach_note": "" if minable else "nothing we can build will work it"})))
				var invited := joined.contains("assay to be sure")
				if invited != minable:
					return _fail(("hand_minable=%s at grade %s purity %d %s an assay. The invitation "
							+ "must follow the sim's flag and nothing else -- a grade or purity "
							+ "changing the answer means this client is deciding workability.")
							% [minable, grade, purity, "invited" if invited else "did not invite"])
	return true


## THE FIXTURE ABOVE IS A CLAIM ABOUT THE SIM; THIS CHECKS IT AGAINST ONE. Every other test in this
## file reads dictionaries I typed, and a fixture that drifts from the binding is how I have shipped
## wrong readouts twice. `fresh_welcome_json` gives a real world, so a real deposit can answer.
##
## It asserts the KEYS and their types, never the values: which species a seed rolls is worldgen's
## business and moved under us once already today (ASSA-35 re-mapped 571 of 1000 seeds).
func test_the_deposit_fixture_still_matches_a_real_deposit() -> bool:
	var host := AssaySimHost.new()
	if not host.start(AssaySimHost.fresh_welcome_json("777042", "limpet")):
		return _fail("could not build a world from fresh_welcome_json: %s" % host.fail_reason)
	var real := {}
	for entry in host.deposits():
		var found: Variant = host.tile_at((entry as Dictionary).get("center", Vector2i.ZERO) as Vector2i).get("deposit")
		if found != null:
			real = found
			break
	if real.is_empty():
		return _fail("a fresh world had no deposit to read")
	for key in _tile_with({}).get("deposit", {}):
		if not real.has(key):
			return _fail(("the fixture carries `%s` and a real deposit does not. Either the binding "
					+ "dropped it or the fixture invented it; either way the HUD tests are measuring "
					+ "a shape the sim does not send. Real keys: %s") % [key, real.keys()])
	for key in ["hand_minable", "reach_note"]:
		if not real.has(key):
			return _fail("a real deposit has no `%s`, which ASSA-47's rule depends on" % key)
	if typeof(real["hand_minable"]) != TYPE_BOOL:
		return _fail("`hand_minable` is not a bool: %s" % [real["hand_minable"]])
	if typeof(real["reach_note"]) != TYPE_STRING:
		return _fail("`reach_note` is not a String: %s" % [real["reach_note"]])
	return true


## THE SAME CHECK ONE LEVEL UP, FOR THE KEY THE GROUND LINE NOW DEPENDS ON (ASSA-146).
##
## `hud.gd` reads `tile.get("ground_note", "")` and appends nothing when it is empty, so a binding
## that never sent the key would make the ground line DISAPPEAR from the window and every test in
## this file would still pass -- they all read dictionaries I typed. That is the exact shape of a
## test agreeing with its own bug, so the fact comes off a real world: a bare in-bounds tile must
## carry a NON-EMPTY note, and a deposit tile must carry an empty one.
func test_the_tile_fixture_still_matches_a_real_tile() -> bool:
	var host := AssaySimHost.new()
	if not host.start(AssaySimHost.fresh_welcome_json("777042", "limpet")):
		return _fail("could not build a world from fresh_welcome_json: %s" % host.fail_reason)
	for key in _bare_tile({}):
		if not host.tile_at(Vector2i(1, 2)).has(key):
			return _fail(("the fixture carries `%s` and a real tile does not. Real keys: %s")
					% [key, host.tile_at(Vector2i(1, 2)).keys()])

	# A bare tile: search rather than pin, because worldgen decides where the deposits are.
	var bare := Vector2i(-1, -1)
	var covered := Vector2i(-1, -1)
	for y in range(0, 40):
		for x in range(0, 40):
			var at := Vector2i(x, y)
			var tile: Dictionary = host.tile_at(at)
			if not bool(tile.get("in_bounds", false)):
				continue
			if tile.get("deposit") != null:
				covered = at
			elif not bool(tile.get("is_spawn", false)):
				bare = at
	if bare == Vector2i(-1, -1) or covered == Vector2i(-1, -1):
		return _fail("a real world gave no bare tile and no deposit tile to compare")

	var note: Variant = host.tile_at(bare).get("ground_note")
	if typeof(note) != TYPE_STRING:
		return _fail("`ground_note` is not a String: %s" % [note])
	if String(note) == "":
		return _fail(("a real bare tile %s sent an EMPTY ground_note, so the window shows no "
				+ "ground line at all") % bare)
	if String(host.tile_at(covered).get("ground_note", "x")) != "":
		return _fail("a real deposit tile %s sent a ground note as well as its deposit line: %s"
				% [covered, host.tile_at(covered).get("ground_note")])
	return true


## A design as `AssaySim.designs_of` hands it over: an UNCERTAIN held pick of one rough species.
func _design() -> Dictionary:
	return {
		"index": -1, "in_hand": true, "verdict": "UNCERTAIN",
		"mass_low": 26, "mass_high": 50, "budget_low": 40, "budget_high": 40,
		# The sim's own wording, copied from `sim::debug::durability_readout` as it stands. A fixture
		# can say anything, so this one is only ever a SAMPLE OF THE SHAPE: nothing below asserts the
		# string itself. It said "100% of 2400-3600" until 2026-10-02, which was the percentage form I
		# filed as a pool leak (ASSA-5) and Maren then reversed to swings -- so for a few hours this
		# file was the last place in the repo still claiming a wording the sim had abandoned.
		"mount": "held", "durability": "0 of 120-180 swings used",
		"unassayed": PackedStringArray(["Korvite"]),
		# THE SIM'S SMALL PRINT FOR THIS VERDICT (ASSA-90). Absent on a SAFE design, which is the
		# case the tests below erase it to reach. `unassayed` is still here because it is what the
		# sim derives the sentence FROM -- but nothing in the panel may read it now, and
		# `test_the_small_print_is_only_ever_the_sims_own_sentence` is what holds that.
		"note": "assay Korvite to know",
		"parts": [
			{"kind": "frame", "species": 0, "species_name": "Korvite", "symbol": "K",
					"grade": "B", "mass_low": 18, "mass_high": 34},
			{"kind": "head", "species": 0, "species_name": "Korvite", "symbol": "K",
					"grade": "B", "mass_low": 8, "mass_high": 16},
		],
	}


## UNCERTAIN MUST NOT LOOK LIKE A WARNING (Maren's ruling, ASSA-7). It is 36.9% of the designs a
## player can build (measured, 2000 worlds) and it is the advertisement for assaying; if it reads as
## danger, players stop building and
## the loop the game is named after never gets its pitch. So: a COOL hue, and never the colour a
## failure wears.
func test_uncertain_is_not_coloured_like_a_warning() -> bool:
	var uncertain := AssayHud.verdict_color("UNCERTAIN")
	if uncertain.h < 0.45 or uncertain.h > 0.75:
		return _fail(("UNCERTAIN is at hue %f, which is in the warm/alarm half of the wheel. The "
				+ "ruling is that it must not read as danger.") % uncertain.h)
	var breaking := AssayHud.verdict_color("WILL BREAK")
	if breaking.h > 0.2 and breaking.h < 0.8:
		return _fail("WILL BREAK is at hue %f, which is not warm enough to read as a cost"
				% breaking.h)
	if uncertain.is_equal_approx(AssayHud.status_color(AssayHud.Say.FAILED)):
		return _fail("UNCERTAIN wears the same colour as a connection failure")
	if AssayHud.verdict_color("SAFE").is_equal_approx(uncertain):
		return _fail("SAFE and UNCERTAIN are the same colour, so the headline carries no state")
	return true


## A span is the sim's two ends, formatted and never averaged. Exact once a species is assayed, which
## is the only thing that narrows it.
func test_a_span_bands_while_rough_and_is_one_number_when_exact() -> bool:
	if AssayHud.span(26, 50) != "26-50":
		return _fail("a rough reading must show both ends, got %s" % AssayHud.span(26, 50))
	if AssayHud.span(38, 38) != "38":
		return _fail("an exact reading must be one number, got %s" % AssayHud.span(38, 38))
	return true


## **A PART ROW NAMES ITS SPECIES IN WORDS AND DOES NOT ALSO STAMP THE LETTER** (ASSA-180, Maren).
##
## The row read `handle · V Valium B · mass 148`: the species SYMBOL immediately before the species
## NAME, which at 1x reads as a stutter rather than a cue. Maren's finding is not the stutter, it is
## that the comment justifying the letter had expired -- the species panel is in the same column now
## and draws the map's actual disc, letter and tint beside the name, which teaches the pairing
## properly. The grade letter is ruled and stays.
##
## **THE FIXTURE'S SYMBOL IS `Z`, AND THAT IS THE ONLY REASON THIS TEST CAN FAIL.** The shared
## `_design()` fixture uses symbol `K` for `Korvite`, so `contains("K")` is blind -- the letter is
## inside the word. A standalone symbol that appears nowhere else in the row is what makes the
## absence measurable instead of asserted.
##
## **MAREN'S RESERVATION, KEPT:** she declined to rule on a guard pinning "no bare species symbol
## ANYWHERE outside the species panel", because a guard naming one approved spelling argues with the
## next wording change. So this is scoped to `design_lines` and to an absence, not a format, and the
## second half below is what stops it being a licence to delete the wrong field. Box 1's evidence is
## a real window shot at 1x, not this.
func test_a_part_row_names_its_species_without_stamping_the_letter() -> bool:
	var design := _design()
	var parts: Array = []
	for entry in design["parts"]:
		var part: Dictionary = (entry as Dictionary).duplicate()
		part["symbol"] = "Z"
		parts.append(part)
	design["parts"] = parts
	var rows := 0
	for line in AssayHud.design_lines(design):
		var text := String(line)
		if not text.begins_with("  "):
			continue
		rows += 1
		if text.contains("Z"):
			return _fail(("a part row still carries the bare species symbol: %s. The species panel "
					+ "teaches the letter now; this row is the only one in the column spelled with "
					+ "one, and the pack and crafting rows carry none") % text)
		# AND IT STILL SAYS THE THINGS THE ROW IS FOR. Dropping a field is a one-word edit and three
		# of the four words here are load-bearing, so this half is what makes the half above safe.
		for owed: String in ["Korvite", "B", "mass"]:
			if not text.contains(owed):
				return _fail(("a part row stopped naming %s: %s -- the fix was to drop the symbol, "
						+ "not the species, the grade or the mass") % [owed, text])
	if rows != 2:
		return _fail(("the fixture's two parts produced %d indented rows, so the loop above ran on "
				+ "the wrong lines and the assertion is vacuous") % rows)
	return true


## THE VERDICT IS THE HEADLINE, so it must not also be buried in the small print: it is its own
## label in its own colour, and a second copy in grey would undo that.
func test_the_verdict_word_is_not_repeated_in_the_small_print() -> bool:
	for line in AssayHud.design_lines(_design()):
		if String(line).contains("UNCERTAIN"):
			return _fail("the verdict is repeated in the body text: %s" % line)
	return true


## UNCERTAIN MUST NAME WHAT RESOLVES IT. "assay something" is not an action; "assay Korvite to know"
## is, and it is the only advertisement assaying gets.
##
## WHAT MOVED (ASSA-90): the sentence used to be composed HERE, out of `unassayed`, and appended
## whenever that list was non-empty. It is now `sim::debug::verdict_note`'s, arriving in `note`, and
## the second case below moved with it -- erasing `unassayed` no longer proves anything, because the
## panel has stopped reading it. Erasing `note` is the case that matters now, and it is the real SAFE
## design rather than a state the sim does not produce.
func test_an_uncertain_design_names_the_material_to_assay() -> bool:
	var found := false
	for line in AssayHud.design_lines(_design()):
		if String(line).contains("assay Korvite"):
			found = true
	if not found:
		return _fail("no line names the rough species: %s" % AssayHud.design_lines(_design()))
	var settled := _design()
	settled.erase("note")
	for line in AssayHud.design_lines(settled):
		if String(line).begins_with("assay "):
			return _fail("a design the sim gave no small print still advises an assay: %s" % line)
	return true


## THE SMALL PRINT IS ONLY EVER THE SIM'S SENTENCE (Maren's ruling, ASSA-90). Two halves, and the
## second is the one that was broken: this panel appended "assay %s to know" whenever `unassayed` was
## non-empty, so a WILL BREAK design was offered an assay -- which cannot move a verdict whose mass
## and budget spans are already disjoint -- and was never told it would break.
##
## Checked by handing the panel a sentence no part of this repo would write, so the assertion cannot
## pass off a string the panel happens to produce itself.
func test_the_small_print_is_only_ever_the_sims_own_sentence() -> bool:
	var sentinel := "a sentence only the sim could have written"
	var design := _design()
	design["note"] = sentinel
	var lines := AssayHud.design_lines(design)
	var found := false
	for line in lines:
		if String(line) == sentinel:
			found = true
	if not found:
		return _fail("the panel did not print the sim's sentence verbatim: %s" % lines)

	# THE HALF ASSA-90 WAS FILED FOR: a design that will break, with rough species in it, must carry
	# the sim's over-budget sentence and NOT an assay offer the panel composed for itself.
	var breaking := _design()
	breaking["verdict"] = "WILL BREAK"
	breaking["note"] = "this is over budget: it will break when planted or first used"
	breaking["unassayed"] = PackedStringArray(["Korvite"])
	var said_break := false
	for line in AssayHud.design_lines(breaking):
		if String(line).contains("assay"):
			return _fail(("WILL BREAK was offered an assay, which cannot move disjoint spans. "
					+ "The panel is composing from `unassayed` again: %s") % line)
		if String(line).contains("over budget"):
			said_break = true
	if not said_break:
		return _fail("WILL BREAK never says it will break: %s" % AssayHud.design_lines(breaking))
	return true


## DURABILITY IS HELD-ONLY (Maren's ruling, ASSA-5). The binding leaves the key out on a planted
## design, and the panel must not print the word anyway.
##
## THE SECOND CASE IS THE ONE THAT BITES, and this test did not have it until 2026-10-02. Erasing the
## key only proves the panel does not invent a line out of nothing; a panel that had stopped checking
## at all would still pass, because there is no key to print. I mutated the condition in `hud.gd` to
## `if true:` and the suite stayed green at 81/0 -- so the "anyway" in the sentence above was a claim
## with nothing behind it. A planted design carrying a durability key is a BINDING REGRESSION, and the
## panel is the place the ruling has to survive one.
func test_a_planted_design_shows_no_durability_at_all() -> bool:
	var planted := _design()
	planted.erase("durability")
	planted["mount"] = "planted"
	planted["in_hand"] = false
	for line in AssayHud.design_lines(planted):
		if String(line).contains("durability"):
			return _fail("a planted design printed a durability line: %s" % line)
	var regressed := _design()
	regressed["mount"] = "planted"
	regressed["in_hand"] = false
	for line in AssayHud.design_lines(regressed):
		if String(line).contains("durability"):
			return _fail(("a planted design was handed a durability key and the panel printed it: %s. "
					+ "Held-only is Maren's ruling (ASSA-5); the panel must hold it even when the "
					+ "binding hands it the key.") % line)
	# THE PANEL'S JOB, NOT THE SIM'S WORDING. This used to assert the literal string, which is how it
	# came to be the last place in the repo claiming a retired format: an assertion that spells out the
	# sim's sentence has to be edited every time the sim writes a better one, and until someone does,
	# it passes while being wrong. So the expectation is built FROM the fixture -- the panel must print
	# the label and then whatever the sim handed it, verbatim and unparsed.
	var held := _design()
	var wanted := "durability %s" % String(held["durability"])
	var held_lines := "\n".join(AssayHud.design_lines(held))
	if not held_lines.contains(wanted):
		return _fail("a held design must show its pool as '%s', got %s" % [wanted, held_lines])
	return true


## A PART ROW CARRIES KIND, SPECIES, GRADE AND MASS. Nothing else -- every other sheet property
## belongs to the assay panel, and over-showing is how this becomes a spreadsheet. The species comes
## as a NAME, which is the row's own non-colour read.
##
## **IT USED TO COME AS LETTER AND NAME** (Decision #36), on the ground that the row was the only
## place a player saw the glyph and the word together. **Maren withdrew that half herself on
## ASSA-180:** the species panel is in the same column now and draws the map's own disc, letter and
## tint beside the name, so the bare `V` in `handle · V Valium B` was a weaker copy of a lesson
## already on screen, and at 1x it read as a stutter.
##
## **THE LITERAL BELOW IS DELIBERATE, AND SIXTEEN LINES ABOVE THIS ONE I SAID THE OPPOSITE** about
## the durability row -- so the difference is worth naming rather than leaving as an inconsistency.
## That row prints a sentence the SIM composes, so an assertion spelling it out goes stale the day
## the sim writes a better one and passes while wrong (it did). This row is composed HERE, out of
## four named fields, and the claim is "four things and nothing else" -- which only a literal can
## catch, because an extra field added to the format breaks no per-field check.
## `test_a_part_row_names_its_species_without_stamping_the_letter` is the other direction: it
## reddens on a field REMOVED, with a symbol the species name does not contain so the absence is
## measurable.
func test_a_part_row_carries_four_things_and_the_rows_sum_to_the_headline() -> bool:
	var lines := AssayHud.design_lines(_design())
	var rows := PackedStringArray()
	for line in lines:
		if String(line).begins_with("  "):
			rows.append(String(line))
	if rows.size() != 2:
		return _fail("two parts must give two rows, got %s" % [rows])
	if rows[0] != "  frame · Korvite B · mass 18-34":
		return _fail("unexpected part row: '%s'" % rows[0])
	# The sim guarantees the rows add up to the headline; the panel must not lose that by rounding
	# or by showing one end. Checked here because a reader compares them with their eyes.
	var design := _design()
	var low := 0
	var high := 0
	for entry in design["parts"]:
		low += int(entry["mass_low"])
		high += int(entry["mass_high"])
	if low != int(design["mass_low"]) or high != int(design["mass_high"]):
		return _fail("the fixture itself does not add up, which would hide a real failure")
	if not "\n".join(lines).contains("mass 26-50 of 40 budget"):
		return _fail("the headline numbers are missing: %s" % lines)
	return true


## A heading over an empty space reads as a bug. Until the craft chain runs every player has zero
## designs, so this is the panel's normal state today and it has to say which it is.
##
## **AND THERE ARE TWO KINDS OF EMPTY BENCH** (ASSA-186). In a world the route is real; with no world
## "mine, smelt and make parts first" is three instructions a stranger cannot act on, so the no-world
## half must name the door instead and carry none of them. The in-world half is checked for the words
## it has always had, because box 3 of that item is that it does NOT change in a world.
func test_an_empty_bench_says_so_rather_than_showing_nothing() -> bool:
	if not AssayHud.no_designs_line(true).contains("nothing built"):
		return _fail("in a world: got %s" % AssayHud.no_designs_line(true))
	var adrift := AssayHud.no_designs_line(false)
	if not adrift.contains("join a world"):
		return _fail("with no world the bench must name the door, got %s" % adrift)
	for instruction in ["mine", "smelt", "make parts"]:
		if adrift.contains(instruction):
			return _fail("with no world the bench still says `%s`: %s" % [instruction, adrift])
	return true


## MAREN'S 18:15 FINDING ON THE THEME (ASSA-116): **"DERIVED" AND "BORROWED" ARE TRUE BY LITERAL,
## NOT BY CONSTRUCTION, and nothing holds them true.**
##
## `build_theme.gd` says `ACCENT` is borrowed from `AssayHud.status_color`'s joined green and that
## `SURFACE` is `MAP_BG` lifted off the map. Both claims are exactly right today and both are typed
## out as `Color(...)` literals — so the day `MAP_BG` moves for the scene work, the panel silently
## stops being derived from anything with a comment still saying it is. Her words: either compute
## them, or add the check, and she does not mind which.
##
## **THE CHECK, because computing one of them would move a shipped colour.** `SURFACE` is not one
## factor of `MAP_BG` (1.450 / 1.427 / 1.446 per channel), so "deriving" it means picking a factor
## and changing the panel by a hair — a look change nobody asked for, hidden inside a tidy-up. The
## accent IS exact and is asserted exactly. The surface is asserted as the per-channel scale it
## actually is, so a `MAP_BG` that moves reddens this with both numbers in the message.
##
## The precedent is `check_species_tints.py`, which fails CI when two copies of a table drift.
func test_the_themes_borrowed_colours_are_still_the_ones_they_say_they_borrowed() -> bool:
	var theme_script = load("res://tools/build_theme.gd")
	var accent: Color = theme_script.ACCENT
	# **THIS PIN IS INVERTED SINCE ASSA-233, AND THE REASON IS A RULING, NOT A DRIFT.** It used to
	# assert ACCENT *is* `status_color(JOINED)`, on the argument that "a focused field and a good
	# status are the same colour rather than two opinions about success". Maren overturned exactly
	# that argument at 1x: since ASSA-224 the accent means *press this* and is spent on the one
	# `Primary` control, so a green `Play solo` and a green `· submitted at tick 514` in one frame
	# are one colour doing opposite work. **NO STATUS COLOUR MAY BE THE ACCENT**, which is a stronger
	# claim than the old equality and catches the same drift from the other side.
	for level in [AssayHud.Say.IDLE, AssayHud.Say.CONNECTING, AssayHud.Say.FAILED,
			AssayHud.Say.JOINED]:
		var said := AssayHud.status_color(int(level))
		if said.is_equal_approx(accent):
			return _fail(("status_color(%d) is the theme's ACCENT %s. The accent means `press this` "
					+ "and belongs to a button; a readout wearing it is two vocabularies for one "
					+ "colour (ASSA-233)") % [int(level), accent])
	# AND `JOINED` IS THE THEME'S SECONDARY INK, typed in `hud.gd` because the generator imports this
	# file and the cycle would not close. Same arrangement `SURFACE` has below.
	var joined := AssayHud.status_color(AssayHud.Say.JOINED)
	var muted: Color = theme_script.INK_MUTED
	if not joined.is_equal_approx(muted):
		return _fail(("status_color(JOINED) %s is no longer the theme's INK_MUTED %s, so the status "
				+ "line has a colour of its own again") % [joined, muted])
	var surface: Color = theme_script.SURFACE
	var scale := Vector3(surface.r / AssayHud.MAP_BG.r, surface.g / AssayHud.MAP_BG.g,
			surface.b / AssayHud.MAP_BG.b)
	# THE MEASURED SCALE, TO THREE PLACES, as Maren read it off the two constants — and compared to
	# three places, not with `is_equal_approx`, whose epsilon is far tighter than the precision the
	# figure was ever stated at. A test that demands more digits than the claim has is a test that
	# fails for being right.
	var was := Vector3(1.450, 1.427, 1.446)
	if (Vector3(scale) - was).abs().length() > 0.001:
		return _fail(("the panel is no longer the map lifted by the scale it was built at: SURFACE "
				+ "%s over MAP_BG %s is now %v, was %v. If the map moved, move the panel with it; "
				+ "if the panel moved, say so here") % [surface, AssayHud.MAP_BG, scale, was])
	return true


## THE CLIENT WORDS NOTHING ABOUT THE MINING AXIS, PROVED BY CONTRADICTION (ASSA-135, box 3).
##
## A grep for "hand-minable" in this file would pass the day someone wrote `if hand_minable` with a
## different word, so this asserts the BEHAVIOUR the grep is a proxy for: hand the row a `mining`
## sentence that disagrees with `hand_minable`, and the row must follow the sentence. There is no
## honest world where those two disagree -- the binding builds both from the same roster -- which is
## exactly why it is a usable probe: only a client that re-derived the state from the bool can tell
## the difference, and only such a client fails this.
func test_a_species_row_carries_the_sims_own_mining_sentence() -> bool:
	# Not one of the sim's three notes on purpose. A fixture may say anything; what is being tested
	# is that this client passes it through rather than recognising it.
	var invented := "this rock is made of cheese"
	var tags := AssayHud.species_tags({"name": "alpha", "hand_minable": true, "mining": invented})
	if not Array(tags).has(invented):
		return _fail(("the row dropped the sim's mining sentence and kept its own idea: %s")
				% [tags])

	# THE CONTRADICTION. `hand_minable` says yes and the sim's sentence says nothing can mine it.
	# A client reading the bool shows "hand-minable"; a client rendering the sentence shows the
	# sentence. Only one of those is this file's job.
	var dead := "too hard for anything you can build"
	tags = AssayHud.species_tags({"name": "beta", "hand_minable": true, "mining": dead})
	if not Array(tags).has(dead):
		return _fail("the row preferred the bool to the sim's sentence: %s" % [tags])
	for tag in tags:
		if String(tag) == "hand-minable":
			return _fail(("the row composed `hand-minable` from the bool while the sim said `%s`")
					% [dead])

	# AND THE THREE STATES ARE THREE ROWS (box 2). Whatever the sim says, a row says it; nothing
	# here collapses two of them into one appearance.
	var seen := {}
	for note in [dead, "hand-minable, but not smeltable", "hand-minable"]:
		var row := AssayHud.species_tags({"name": "s", "hand_minable": true, "mining": note})
		seen[" ".join(PackedStringArray(row))] = note
	if seen.size() != 3:
		return _fail("three mining states rendered as %d distinct rows: %s" % [seen.size(), seen])

	# NO WORD WHERE THE SIM SENT NONE. If the binding ever stopped sending `mining`, a row one tag
	# short is a visible defect; a confident "hand-minable" invented here would not be.
	tags = AssayHud.species_tags({"name": "gamma", "hand_minable": true})
	for tag in tags:
		if String(tag).contains("minable"):
			return _fail("the row invented a mining tag with no sim sentence to render: %s" % [tags])
	return true


## THE FUEL CLAIM ARRIVES WITH ITS GRADE AND THIS CLIENT WORDS NONE OF IT (ASSA-143, boxes 1 and 4).
##
## Same proof by contradiction as the mining test above, against the other half of the same defect:
## the binding called `fuel_grade` and kept `.is_some()`, so the row showed `[hand-minable] [lights
## from cold]` for a rock whose grade-C deposits will not burn -- 18.8% of the rows this panel tags
## as fuel. The grade was computed and dropped on the line that computed it.
##
## `hand_lit_fuel` is the bool to contradict here. A client that re-derived the claim from it would
## show the same word for every threshold, which is the shipped defect exactly.
func test_a_species_row_carries_the_sims_own_fuel_clause() -> bool:
	# Not one of the sim's four wordings on purpose: what is tested is pass-through, not recognition.
	var invented := "burns if you sing to it"
	var tags := AssayHud.species_tags(
			{"name": "alpha", "hand_lit_fuel": true, "mining": "hand-minable", "fuel": invented})
	if not Array(tags).has(invented):
		return _fail("the row dropped the sim's fuel clause and kept its own idea: %s" % [tags])

	# THE CONTRADICTION. `hand_lit_fuel` is false and the sim's clause says this burns at B. A client
	# reading the bool shows nothing, or shows a bare "fuel"; only one of those is this file's job.
	var at_b := "fuel at B or better"
	tags = AssayHud.species_tags(
			{"name": "beta", "hand_lit_fuel": false, "mining": "hand-minable", "fuel": at_b})
	if not Array(tags).has(at_b):
		return _fail("the row preferred the bool to the sim's fuel clause: %s" % [tags])
	for tag in tags:
		if String(tag) == "fuel":
			return _fail("the row composed a grade-less `fuel` from the bool: %s" % [tags])

	# AND FOUR WORDINGS ARE FOUR ROWS (box 4). The whole item is that a rock burning only above C
	# looked identical on screen to one burning at C.
	var seen := {}
	for clause in ["fuel at C or better", at_b, "fuel at A or better",
			"fuel at C or better if you could mine it"]:
		var row := AssayHud.species_tags(
				{"name": "s", "hand_lit_fuel": true, "mining": "hand-minable", "fuel": clause})
		seen[" ".join(PackedStringArray(row))] = clause
	if seen.size() != 4:
		return _fail("four fuel thresholds rendered as %d distinct rows: %s" % [seen.size(), seen])

	# NO CLAIM WHERE THE SIM MADE NONE. A rock the sim does not call fuel arrives with no key, and a
	# bare "fuel" invented here is the defect this item is about, not a smaller version of it.
	tags = AssayHud.species_tags(
			{"name": "gamma", "hand_lit_fuel": true, "mining": "hand-minable"})
	for tag in tags:
		if String(tag).contains("fuel"):
			return _fail("the row invented a fuel tag with no sim clause to render: %s" % [tags])

	# THE ORDER, because three tags on one line read as a sentence and this is the sentence the
	# table prints: what you can get out of it, at which grade it burns, how it lights.
	tags = AssayHud.species_tags({
		"name": "delta", "mining": "hand-minable", "fuel": at_b, "lighting": "lights from cold",
	})
	if Array(tags) != ["hand-minable", at_b, "lights from cold"]:
		return _fail("the fuel clause is not between the mining and lighting tags: %s" % [tags])

	# AND NO GRADE IS DERIVED FROM A READING. The sheet says reactivity 100 -- which is fuel at C by
	# the sim's own thresholds -- and the clause says A. A client doing its own arithmetic on the
	# readings would print C here; it would also be printing a number that is a 25-wide band until
	# the deposit is assayed.
	var at_a := "fuel at A or better"
	tags = AssayHud.species_tags({
		"name": "epsilon", "mining": "hand-minable", "fuel": at_a, "assayed": true,
		"readings": {"reactivity": "100"},
	})
	if not Array(tags).has(at_a):
		return _fail("the row recomputed the grade from a reading instead of rendering %s: %s"
				% [at_a, tags])
	for tag in tags:
		if String(tag).contains("C or better"):
			return _fail("the row derived grade C from reactivity 100: %s" % [tags])
	return true


## **THE LINE COUNT IS A BOUND IN BOTH DIRECTIONS** (ASSA-156). The log's panel is capped to the room
## above the player's own body and `log_lines_that_fit` is the only arithmetic in that fix, so both
## ways of being wrong are checked here: a count whose panel overflows the room puts the panel back
## on the player's head, and a count one line timid costs a player a line of their own history for
## nothing. The second clause is the one a `- 1` somewhere in that expression would fail.
##
## THE TERMS ARE THE REAL ONES, measured off the engine in `tools/log_room_probe.gd` against the
## shipped theme: a row is 18px, separation 4, the panel's margins 12, the heading 22, and the room
## at 912x600 is 220 -- **288 on the 912x672 map since ASSA-239**, which is why the rows below are a
## spread of plausible rooms rather than today's one number: this is a test of the ARITHMETIC, and it
## must not need editing every time the map's rect moves. `chrome + newest + (n - 1) * pitch` is the panel's height, which is the same
## sum `main.gd` leaves to the engine -- the model is checked against a laid-out window in
## `window_shot.gd::_reveal_report`, because no headless test in this repo can see a real rect.
func test_the_log_line_count_fills_the_room_without_overflowing_it() -> bool:
	var pitch := 22.0
	var chrome := 38.0
	for entry in [220.0, 219.0, 100.0, 76.0, 60.0, 40.0, 1.0, 600.0]:
		var room := float(entry)
		for tallest in [18.0, 36.0, 54.0]:
			var newest := float(tallest)
			var fits := AssayHud.log_lines_that_fit(room, chrome, newest, pitch, 14)
			var tall := chrome + newest + float(fits - 1) * pitch
			if fits < 1 or fits > 14:
				return _fail("a room of %.0fpx asked for %d log lines, outside 1..14" % [room, fits])
			if fits > 1 and tall > room:
				return _fail(("%d lines need %.0fpx of a %.0fpx room (newest %.0f), so the panel "
						+ "draws taller than the room it was given and lands back on the player")
						% [fits, tall, room, newest])
			if fits < 14 and tall + pitch <= room:
				return _fail(("%d lines use %.0f of a %.0fpx room and another whole line would fit "
						+ "in %.0f: the player is losing their own history to nothing")
						% [fits, tall, room, tall + pitch])
	return true


## A ROOM NOBODY MEASURED MUST NOT SHRINK THE LOG. `player_ceiling` answers -1.0 when there is no
## player art to bound a panel by, and a `0` or a negative arriving here has to read as "no claim"
## rather than as "no space" -- a missing manifest showing one log line would be a defect nobody
## would trace back to a sprite sheet.
func test_a_log_with_no_measured_room_keeps_every_line() -> bool:
	for entry in [-1.0, 0.0]:
		if AssayHud.log_lines_that_fit(float(entry), 38.0, 18.0, 22.0, 14) != 14:
			return _fail("a room of %.0f cut the log down instead of leaving it alone" % entry)
	if AssayHud.log_lines_that_fit(220.0, 38.0, 18.0, 0.0, 14) != 14:
		return _fail("a line height of 0 divided the log by nothing and cut it anyway")
	return true


## **THE BUILDING MARK IS NEITHER OF THE TWO SHAPES THIS MAP ALREADY USES, AS GEOMETRY** (ASSA-189,
## Maren's boxes 3 and 4: "not a disc and NOT a fifth filled rect", and "a building is not mistakable
## for a deposit OR for a player at 1x: the distinction survives a greyscale copy").
##
## **GREYSCALE IS WHY EVERY ASSERTION HERE IS ABOUT POINTS AND AREAS AND NONE IS ABOUT A COLOUR.** A
## mark separated by hue fails her ruling no matter how good the hue is, so the checkable form of the
## box is: a point the OTHER shape contains and this one does not. Two of those:
##
## **THE SHAPE IT ASKS FOR IS THE OTHER ONE SINCE ASSA-236** (Maren: "a point (you) gets the
## footprint shape; a footprint gets the point shape"). What the mark must now be:
##
## - the footprint's own axis-aligned RECT, so its corners are the corners of the tiles it covers --
##   the assertion that used to forbid exactly this, turned round, so the two cannot both be green;
## - HOLLOW: a point at its centre is outside it, which is what lets a person stand on a machine
##   without either mark being a choice (`BUILDING_STROKE_PX`);
## - of the footprint's SIZE where the floor does not bite: a 2x2 at 9px a tile is 18px exactly, on
##   the tiles the sim gave it, and the 1x1 case is the floor's and is asserted below rather than
##   here.
##
## **AND IT IS AT THE TILE THE SIM GAVE IT** (box 2). `pos` is the top-left of the footprint, so the
## centre is `pos + footprint / 2` in tiles -- the 2x2 case is the one worth a test, because taking
## `pos` as the centre would draw a smelter a whole tile up and left of itself and nothing on a 1x1
## machine would ever show it.
##
## WHAT THIS CANNOT SEE: whether `main.gd::_draw` consumes any of it.
## `test_main_screen.gd::test_the_schematic_is_handed_every_building_the_sim_reports` holds the
## wiring, and the picture is `tools/window_shot.gd`'s whole-world shot. A painter that computed its
## own diamond and ignored this function would leave this test green.
func test_a_building_on_the_schematic_is_the_footprint_it_stands_on() -> bool:
	var origin := Vector2(24.0, 96.0)
	for case in [{"foot": Vector2i(2, 2), "cell": 9.0}, {"foot": Vector2i(1, 1), "cell": 9.0},
			{"foot": Vector2i(2, 2), "cell": 18.0}, {"foot": Vector2i(3, 2), "cell": 32.0}]:
		var foot: Vector2i = case["foot"]
		var cell: float = case["cell"]
		var pos := Vector2i(12, 7)
		var mark := AssayHud.building_mark({"pos": pos, "footprint": foot}, cell, origin)
		var points: PackedVector2Array = mark["points"]
		# NOT A POINT COUNT. An earlier version of this demanded exactly four points and that is how
		# a check stops being evidence: an octagon-shaped mutation -- a disc in all but name, which is
		# Maren's other banned shape -- was caught by "8 points" and the two assertions below about
		# BEING a disc never ran. Four points is not what she ruled; a hexagon would satisfy her. So
		# the floor here is only "is it a polygon at all", and the geometry speaks.
		if points.size() < 3:
			return _fail("a %s building drew a %d-point mark, which has no interior"
					% [foot, points.size()])
		# BOX 2: THE TILE THE SIM GAVE IT. The top-left corner tile plus half the footprint.
		var want := origin + (Vector2(pos) + Vector2(foot) * 0.5) * cell
		var at: Vector2 = mark["at"]
		if at.distance_to(want) > 1e-4:
			return _fail(("a %s building at tile %s and %.0fpx a tile is centred on %s; its "
					+ "footprint's centre is %s. `pos` is the TOP-LEFT, so reading it as the centre "
					+ "draws a smelter a tile up and left of itself.") % [foot, pos, cell, at, want])
		var span: Vector2 = mark["span"]
		var box := Rect2(at - span * 0.5, span)
		# **BOX 2, HALF ONE: IT IS THE FOOTPRINT'S RECT, CORNERS AND ALL.** This is the assertion
		# that said the opposite until ASSA-236 ("contains its own bounding-box corner, so it is a
		# filled rect"), because the shape was Maren's answer to a question she has since re-asked.
		for corner: Vector2 in [box.position, box.position + Vector2(box.size.x, 0.0),
				box.position + Vector2(0.0, box.size.y), box.end]:
			var inset := corner + (at - corner).normalized() * 0.5
			if not Geometry2D.is_point_in_polygon(inset, points):
				return _fail(("a %s building's mark misses its own bounding-box corner %s, so it is "
						+ "a point shape and not a footprint: the only thing on this map with a "
						+ "tile footprint would again be the one mark rotated off the grid it "
						+ "stands on.") % [foot, corner])
		# **BOX 2, HALF TWO: AXIS-ALIGNED.** Every edge is horizontal or vertical, which is what
		# "aligned to the grid it stands on" is in arithmetic. A diamond fails all four.
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			if absf(a.x - b.x) > 1e-4 and absf(a.y - b.y) > 1e-4:
				return _fail(("a %s building's mark has the edge %s-%s, which is neither horizontal "
						+ "nor vertical: it is not aligned to the grid it stands on") % [foot, a, b])
		# **AND IT IS HOLLOW, WHICH IS THE HALF THE SHAPE IS FOR.** Two filled marks on one tile
		# cannot both survive -- ASSA-203 measured 92.4% against 0.0% and called it an order
		# question. A hole is not a style: it is what makes the order cost nothing.
		var hole: PackedVector2Array = mark["hole_points"]
		if not Geometry2D.is_point_in_polygon(at, hole):
			return _fail(("a %s building's mark is solid at its own centre %s: a person standing on "
					+ "this machine is painted out by it") % [foot, at])
		var ring_area := AssayHud.polygon_area(points) - AssayHud.polygon_area(hole)
		var want_ring := span.x * span.y - maxf(span.x - 2.0 * AssayHud.BUILDING_STROKE_PX, 0.0) \
				* maxf(span.y - 2.0 * AssayHud.BUILDING_STROKE_PX, 0.0)
		if absf(ring_area - want_ring) > 0.01:
			return _fail(("a %s building's frame is %.1fpx of ink where a %.0fpx stroke on a %s box "
					+ "is %.1f: the band is not the thickness it says it is")
					% [foot, ring_area, AssayHud.BUILDING_STROKE_PX, span, want_ring])
		# **AND THE FOOTPRINT IS THE SIZE WHERE THE FLOOR DOES NOT BITE.** A 2x2 at 9px is 18px on
		# its own four tiles; the floor's case is the next test's and is an admitted overstatement.
		var reach := float(maxi(foot.x, foot.y)) * cell
		if reach >= AssayHud.BUILDING_MARK_PX and absf(span.x - reach) > 1e-4:
			return _fail(("a %s building at %.0fpx a tile is drawn %.1fpx across where its footprint "
					+ "is %.1f: the mark is not the tiles it covers") % [foot, cell, span.x, reach])
		# **THE APPROVED COLOUR, AND IT SPENDS NO NEW HUE** (Cove's ASSA-193, Maren at 17:25). `HOVER`
		# with a `MAP_BG` rim. I shipped a green of my own here (ASSA-203) -- a 22nd literal on a map
		# whose named set exists to stop exactly that.
		if mark["colour"] != AssayHud.HOVER:
			return _fail(("a %s building's mark is %s, not HOVER. The approved mark spends no new "
					+ "hue: filled-vs-hollow is what tells it from the cursor at 1x.")
					% [foot, mark["colour"]])
		if mark["keyline"] != AssayHud.MAP_BG:
			return _fail("the mark's keyline is %s and not MAP_BG" % mark["keyline"])
		# **THE RIM IS 2 px PERPENDICULAR, AND ON THIS SHAPE THE OBVIOUS ARITHMETIC IS THE RIGHT
		# ONE** -- every edge is axis-aligned, so `grow(t)` moves each one by exactly `t`. It was not
		# on the diamond (a diagonal grown by `d` gives a rim of `d/(2*sqrt(2))`), which is why this
		# is measured off the polygon the painter is handed rather than restated.
		var rim: PackedVector2Array = mark["keyline_points"]
		if rim.size() != points.size():
			return _fail("the mark is a %d-gon and its keyline a %d-gon, so the rim is not its shape"
					% [points.size(), rim.size()])
		var gap := points[0].x - rim[0].x
		if absf(gap - AssayHud.MARK_KEYLINE_PX) > 0.01 \
				or absf((points[0].y - rim[0].y) - AssayHud.MARK_KEYLINE_PX) > 0.01:
			return _fail(("a %s building's keyline is %.2fpx thick perpendicular, not %.2f")
					% [foot, gap, AssayHud.MARK_KEYLINE_PX])
		# AND IT IS OUTSIDE THE MARK, not a stroke straddling its edge: every point of the mark is
		# inside the rim, so the mark keeps all 16px of the size Cove sized it at.
		for point: Vector2 in points:
			if not Geometry2D.is_point_in_polygon(point, rim):
				return _fail(("a %s building's mark reaches %s, which is outside its own keyline: the "
						+ "rim is being paid for out of the mark instead of grown around it.")
						% [foot, point])
	return true


## **EVERY PIXEL OF A MACHINE'S BAND HAS A DARK NEIGHBOUR ON BOTH SIDES** (ASSA-278, Maren's ruling
## at 23:10 EDT: option 1, the inward keyline).
##
## **HER REASON IS NOT THE ONE I FILED IT UNDER, AND THE DIFFERENCE IS THIS TEST.** I filed "a hollow
## mark whose hole is as bright as its band is not hollow". She ruled on the band instead: *"every
## pixel of the band gets a dark neighbour on both sides, so the band stops renting its weight from
## the ground it stands on"* -- which is true on any ore tint, where a statement about the hole is a
## statement about one seed's disc.
##
## **WHAT WAS WRONG.** `MARK_KEYLINE_PX` was grown OUTWARD only, so the frame's outer edge read
## 11.40:1 on every ground we had shot and its inner edge read whatever the map had put there. On
## seed 63's grade-A disc the band measured **1.53:1** against the ring immediately inside it, and
## Nerite -- the only independent reader we had -- could not call the mark a machine at all. With the
## rim that ring is `MAP_BG`: **15.23:1**, exactly the dark-map number.
##
## **IT FAILED NOTHING. 394 passed, 0 failed, WITH the defect, and 394/0 WITHOUT it.** The test above
## asserts the hole is a hole in GEOMETRY -- a point at the centre is outside the ink -- and geometry
## is exactly what was never wrong. Nothing here asked what the band stands next to.
##
## **THE PROPERTY, NOT A PIXEL COUNT.** A band pixel's four neighbours are each either band or
## keyline, never the map. One assertion covers both edges, it is independent of what the ground
## happens to be, and it reddens with the rim removed naming the pixel and the direction. A pixel
## count would pass a rim drawn in the mark's own white.
##
## **THE RIM IS NOT FREE AND THE PRICE IS IN HERE BECAUSE IT IS WHERE THE NEXT PERSON MEETS IT**
## (`tools/person_under_machine.gd`, the real geometry at cell 9): `_draw` paints buildings AFTER
## players, so the rim lands on whoever is standing on the machine. A partner on a 1x1 keeps **69.2%
## of their cross without the rim and 38.5% with it**, and ASSA-236's whole case for the hollow frame
## was that it ended that trade (25.3% -> 70.4%). So the hole must still have a middle, which is the
## second assertion below -- and the hole's clear square is 8x8 px where it was 12x12.
##
## **WHAT IT CANNOT SEE, the same gap every mark test here admits: whether `_draw` paints these three
## lists.** Nothing headless rasterises a `draw_rect`. The bands come out of `AssayHud` in the
## painter's own order and `test_main_screen.gd` holds the wiring; the 1x proof is the window shot on
## ASSA-278, two seeds.
func test_a_machines_band_has_a_dark_neighbour_on_both_of_its_edges() -> bool:
	var origin := Vector2(24.0, 96.0)
	for case in [{"foot": Vector2i(1, 1), "cell": 9.0}, {"foot": Vector2i(2, 2), "cell": 9.0},
			{"foot": Vector2i(3, 2), "cell": 32.0}]:
		var foot: Vector2i = case["foot"]
		var cell: float = case["cell"]
		var mark := AssayHud.building_mark({"pos": Vector2i(12, 7), "footprint": foot}, cell, origin)
		if not mark.has("hole_rect"):
			return _fail(("a %s building's mark carries no `hole_rect`, so the painter has no inward "
					+ "rim to ask for: the band's inner edge is whatever the map put there, which on "
					+ "a grade-A disc is 1.53:1 and unfindable (ASSA-278)") % [foot])
		# THE THREE LISTS `_draw` PAINTS FOR ONE MACHINE, in its order, asked of the same functions it
		# asks. `hole_rect` and not `hole_points`, because the painter needs a Rect2 to grow bands from
		# and a polygon cannot be handed to `frame_bands`.
		var band: Array[Rect2] = AssayHud.frame_bands(mark["rect"], float(mark["stroke"]))
		var dark: Array[Rect2] = AssayHud.frame_bands(mark["keyline_rect"], AssayHud.MARK_KEYLINE_PX)
		dark.append_array(AssayHud.frame_bands(mark["hole_rect"], AssayHud.MARK_KEYLINE_PX))
		# **AND THE TWO INKS MAKE A STEP, AS A NUMBER.** Without this the property above is satisfied
		# by a rim in any colour at all -- including the band's own white, which is the shape of the
		# defect: a neighbour that is not an edge.
		var step := AssayHud.contrast_ratio(mark["colour"] as Color, mark["keyline"] as Color)
		if step < 4.5:
			return _fail(("a %s building's band is %s against a keyline of %s: %.2f:1, so the "
					+ "neighbour on each side is not an EDGE and the rim buys nothing")
					% [foot, mark["colour"], mark["keyline"], step])
		# SAMPLED AT A QUARTER PIXEL, NOT AT A PIXEL CENTRE: the map's rects sit on half-pixels at
		# cell 9 (a 1x1 mark is 16px about a tile's middle) and on integers at cell 32, and a sample
		# that lands on an edge is a coin toss in `Rect2.has_point`.
		var outer: Rect2 = mark["keyline_rect"]
		var y := floorf(outer.position.y) + 0.25
		var seen := 0
		while y <= outer.end.y:
			var x := floorf(outer.position.x) + 0.25
			while x <= outer.end.x:
				var point := Vector2(x, y)
				if _in_any(band, point):
					seen += 1
					for step_to: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
						var next := point + step_to
						if _in_any(band, next) or _in_any(dark, next):
							continue
						return _fail(("a %s building's band at %s has the map itself %s of it: the "
								+ "band is renting its weight from whatever is under the mark, which "
								+ "on a grade-A disc is 1.53:1 and which QA could not read at all "
								+ "(ASSA-278). Every band pixel needs a %s neighbour on both sides.")
								% [foot, point, step_to, mark["keyline"]])
				x += 1.0
			y += 1.0
		if seen == 0:
			return _fail("a %s building's frame sampled 0 band pixels inside its own keyline rect %s, "
					% [foot, outer] + "so this test looked at nothing")
		# **AND THE HOLE STILL HAS A MIDDLE.** The rim is painted over a person standing on the
		# machine (buildings go in after players), so a rim that closed the hole would be ASSA-203's
		# 0.0% back by another route. 8x8 px of a 1x1's 12x12 hole, and the cost is in the docstring.
		var centre: Vector2 = (mark["rect"] as Rect2).get_center()
		if _in_any(band, centre) or _in_any(dark, centre):
			return _fail(("a %s building's mark is ink at its own centre %s once the inward rim is "
					+ "drawn: a person standing on this machine is painted out by it, which is the "
					+ "trade the hollow frame was filed to end (ASSA-236)") % [foot, centre])
	return true


## **THE HOVERED TILE'S OUTLINE HAS A RIM OF ITS OWN, AND THE RIM IS OPAQUE WHERE THE MARK IS NOT**
## (ASSA-284, Maren's finding on ASSA-275 box 5).
##
## **THE ASYMMETRY IS THE WHOLE FACT, so it is what this asserts.** `hover_tile` is `HOVER` at alpha
## 0.55, which means it has no value of its own -- only the ground's, lifted. On seed 63's grade-A ore
## that lift is `234,234,47` -> `239,239,154`: 5/255 in R and G and nearly all of it in BLUE, so **in a
## greyscale copy the mark is gone**, and this map's rule is that a mark survives a greyscale copy. A
## translucent mark therefore needs an OPAQUE rim, or the rim inherits the same ore and separates
## nothing. A rim at alpha 0.55 would satisfy "it has a keyline" and fix nothing at all.
##
## **AND IT IS GROWN OUTWARD.** Beside a machine the outline was eating one of the 2 px of `MAP_BG`
## that hold two hollow squares apart (Maren's row at x=707 and x=509: the machine's rim read
## 145,146,148 while hovered). A rim paid for out of the mark would shrink the outline instead, and
## then the two marks would still touch -- so "inside the rim" is asserted on the real rects.
##
## WHAT THIS CANNOT SEE: whether `_draw` paints the rim, or what it looks like at 1x.
## `test_map_key.gd` holds the table-against-`_draw` wiring in both directions, and the 1x judgement
## is Maren's on the window shot (ASSA-284 box 6).
func test_the_hovered_tiles_outline_carries_its_own_opaque_rim() -> bool:
	var origin := Vector2(24.0, 96.0)
	var entry := AssayHud.mark_entry(&"hover_keyline")
	if entry.is_empty():
		return _fail("AssayHud.MAP_MARKS carries no `hover_keyline`: the hovered tile's outline is "
				+ "the one mark on this map with no rim, which on grade-A ore leaves it a hue change "
				+ "and no value change at all (ASSA-284)")
	if StringName(entry.get("keyed_by", &"")) != &"hover_tile":
		return _fail("`hover_keyline` is keyed by `%s` and not by `hover_tile`, so the key would "
				+ "either grow a row for a rim or explain it as something else" % entry.get("keyed_by", "<nothing>"))
	var rim := AssayHud.mark_ink(&"hover_keyline")
	var mark := AssayHud.mark_ink(&"hover_tile")
	if rim != AssayHud.MAP_BG:
		return _fail("the hovered tile's rim is %s and not MAP_BG: a rim in any other colour is a "
				% rim + "22nd literal on this map and a new meaning for it")
	if not is_equal_approx(rim.a, 1.0):
		return _fail(("the hovered tile's rim is at alpha %.2f. The mark it rims is itself at %.2f, "
				+ "which is why it has no value of its own on a bright disc; a translucent rim "
				+ "inherits the same ore and separates nothing (ASSA-284)") % [rim.a, mark.a])
	if is_equal_approx(mark.a, 1.0):
		return _fail(("the hovered tile's outline is opaque now (alpha %.2f). If that is deliberate "
				+ "the reasoning on this test is stale: the rim was ruled BECAUSE the mark is "
				+ "translucent and borrows the ground's value") % [mark.a])
	for cell: float in [9.0, 18.0, 32.0]:
		var hover := AssayHud.hover_mark(Vector2i(12, 7), cell, origin)
		var box: Rect2 = hover["cell_rect"]
		# THE CELL ITSELF, FROM ITS CORNER: the one mark on this map that is a cell rather than a
		# thing standing on one (ASSA-220's rule, and this is its documented exception).
		#
		# **THIS READ `hover["rect"]` UNTIL ASSA-284 BOX 7 AND THAT WAS THE DEFECT, NOT THE GUARD.**
		# A rect whose edges sit ON the cell boundary paints half a pixel outside it, so "covers
		# exactly the cell" as a RECT meant "paints a column of tile 52" as PIXELS. The cell is now
		# `cell_rect` and the stroked rect is inset half a stroke inside it; the pixels are asserted
		# by `test_the_hovered_outline_paints_no_pixel_of_a_tile_it_does_not_name`.
		if not box.position.is_equal_approx(origin + Vector2(12.0, 7.0) * cell) \
				or not box.size.is_equal_approx(Vector2(cell, cell)):
			return _fail("at %.0f px a tile the hovered outline is %s, which is not tile (12, 7)'s "
					% [cell, box] + "own cell: this mark is the cell and must cover exactly it")
		var keyline: Rect2 = hover["keyline_rect"]
		var out := box.size - keyline.size
		if not out.is_equal_approx(Vector2(3.0, 3.0) * AssayHud.HOVER_STROKE_PX):
			return _fail(("at %.0f px a tile the rim is inset from the cell by %s, not %.1f px "
					+ "perpendicular on each side (half a stroke for the outline's own centring plus "
					+ "a whole one to clear the column it paints)")
					% [cell, out, 1.5 * AssayHud.HOVER_STROKE_PX])
		# **AND THE RIM IS INSIDE THE CELL, WHICH IS THE OPPOSITE OF EVERY OTHER RIM ON THIS MAP AND
		# IS MEASURED RATHER THAN PREFERRED.** Grown OUTWARD -- which is what Maren ruled and what I
		# built first -- the rim lands on the neighbouring tile, and the neighbour is where a machine's
		# mark starts: shot on both seeds, the smelter's band went 242 -> 28 at the shared edge, so an
		# outward rim buys this mark a dark neighbour by deleting one of the machine's two band pixels.
		# A mark may not pay for its own legibility out of the mark next door.
		if not box.encloses(keyline):
			return _fail(("the hovered tile's rim %s is not inside its own cell %s. Outward, it lands "
					+ "on the neighbouring tile and deletes a pixel of whatever mark starts there -- "
					+ "measured at a smelter's band on two seeds, 242 -> 28 (ASSA-284)")
					% [keyline, box])
		if keyline.size.x <= 0.0 or keyline.size.y <= 0.0:
			return _fail(("at %.0f px a tile the rim leaves the hovered cell no middle at all (%s): "
					+ "the outline would be a filled square and the ore under it gone")
					% [cell, keyline])
		if not is_equal_approx(float(hover["width"]), AssayHud.HOVER_STROKE_PX):
			return _fail("the hovered outline is drawn %.1f px wide and the constant says %.1f"
					% [hover["width"], AssayHud.HOVER_STROKE_PX])
	return true


## **THE HOVERED TILE'S OUTLINE MAY PAINT ONLY PIXELS OF THE CELL IT NAMES** (ASSA-284 box 7, Maren:
## "ASSA-213 lets a mark lie about SIZE and never about POSITION, and this is the one mark that *is* a
## cell, so it has no size to hide behind").
##
## The defect this catches shipped for a day and no rect-level guard could see it. `hover_mark`'s rect
## was the cell exactly -- tile 53 at x=501, span 9 -- which is the right RECT and the wrong PIXELS:
## Godot's unfilled `draw_rect` centres its stroke on the edge it is given, so a 1 px edge at x=501
## covers 500.5-501.5 and lands in tile 52's column. Shot on seed 63, the outline's own pixel sat on
## the smelter's `MAP_BG` rim at the shared edge.
##
## So this asserts PIXEL COLUMNS, not rects, for the outline AND its rim, over three cell sizes and
## both parities of origin: every column and row either stroke paints must belong to the hovered cell.
## It is the pixel half of [method test_the_hovered_tiles_outline_carries_its_own_opaque_rim], which
## keeps the rect-level facts (the rim's colour, its alpha, that it is inside the cell).
##
## WHAT IT CANNOT SEE: the rasteriser. The span arithmetic here is Godot's documented centring, and
## the frame that confirms it is `shared/assay/cove-assa284/` -- the hover shot's own changed-pixel
## columns against `cell_rect`, which is why that rect is now in the shot table.
func test_the_hovered_outline_paints_no_pixel_of_a_tile_it_does_not_name() -> bool:
	for origin: Vector2 in [Vector2(24.0, 24.0), Vector2(24.0, 96.0), Vector2(25.0, 97.0)]:
		for cell: float in [9.0, 18.0, 32.0]:
			var tile := Vector2i(53, 56)
			var hover := AssayHud.hover_mark(tile, cell, origin)
			var cell_rect: Rect2 = hover["cell_rect"]
			var width := float(hover["width"])
			var painted := {}
			for part: String in ["rect", "keyline_rect"]:
				var stroked: Rect2 = hover[part]
				for axis: int in [0, 1]:
					# The stroke straddles each edge by half its width; a pixel index `i` covers
					# [i, i+1), so the painted columns run floor(lo) .. ceil(hi) - 1.
					var lo: float = stroked.position[axis] - 0.5 * width
					var hi: float = stroked.position[axis] + stroked.size[axis] + 0.5 * width
					var first := int(floor(lo))
					var last := int(ceil(hi)) - 1
					var own_first := int(floor(cell_rect.position[axis]))
					var own_last := int(ceil(cell_rect.position[axis] + cell_rect.size[axis])) - 1
					if first < own_first or last > own_last:
						return _fail(("at %.0f px a tile, origin %s: the hovered outline's `%s` "
								+ "paints %s %d..%d and tile (53, 56) owns only %d..%d. This mark IS "
								+ "the cell, so a pixel outside it is the mark naming its "
								+ "neighbour (ASSA-284 box 7, ASSA-213)")
								% [cell, origin, part, "columns" if axis == 0 else "rows",
								first, last, own_first, own_last])
					# **AND THE RIM MAY NOT PAINT THE OUTLINE'S OWN COLUMNS**, which is the other way
					# a half-pixel edge goes wrong: a rim centred one whole stroke in from a
					# boundary-straddling edge overlaps the mark it is meant to separate, and since
					# the rim is drawn FIRST and opaque the outline survives -- but at 1 px wide,
					# any rim pixel that lands on the mark is a rim that shrank it. Paired
					# half-stroke insets is what makes the two abut instead.
					var key := "%d:%d" % [axis, first]
					var far := "%d:%d" % [axis, last]
					if part == "rect":
						painted[key] = true
						painted[far] = true
					elif painted.has(key) or painted.has(far):
						return _fail(("at %.0f px a tile, origin %s: the rim paints %s %d and %d, "
								+ "and the outline already paints one of them. A rim that lands on "
								+ "the mark it separates is paid for out of the mark (ASSA-284)")
								% [cell, origin, "columns" if axis == 0 else "rows", first, last])
	return true


## **A PERSON STANDING ON A MACHINE KEEPS THEIR BODY** (ASSA-278 box 7, Maren's size ruling at 06:49
## UTC: `BUILDING_MARK_PX` 16 -> 20, *"the smallest value that meets the bar I set -- 85.3 / 69.2,
## hole 12x12, rim untouched"*).
##
## **THIS IS THE BAR AS A TEST, AND IT IS THE ONE THING ASSA-278 NEVER HAD.** The inward rim shipped
## on 1d8b6af because every band pixel got a dark neighbour, which was true and cost a partner on a
## 1x1 **69.2% of their cross down to 38.5%** -- a number that existed only in a tool nobody runs in
## CI. ASSA-236's whole case for the hollow frame was that it ENDED that trade, and nothing in the
## suite noticed it coming back. So the share is asserted here, at the painter's own geometry.
##
## **WHY A SHARE AND NOT A GEOMETRIC CONTAINMENT.** At 20 the clear hole is 12x12 and a body's diamond
## reaches 8 px from the centre on each axis, so four tips still poke into the band -- the hole does
## NOT enclose the body, and asserting that it did would fail a design Maren has ruled correct. What
## changed at 20 is WHICH band takes those tips: at 16 the rim took them on top of what the band
## already took (47.1% / 38.5%), and at 20 the rim sits inside the body's own reach and takes exactly
## what the band took before it existed (85.3% / 69.2%). The share is the only honest statement of it.
##
## WHAT IT CANNOT SEE: ink, antialiasing, or whether `_draw` paints these lists. It is an area count
## over the painter's rects, the same method as `tools/person_under_machine.gd`, which is where the
## sweep that found 20 lives.
func test_a_person_standing_on_a_machine_keeps_their_body() -> bool:
	var cell := 9.0
	var origin := Vector2(24.0, 24.0)
	var tile := Vector2i(12, 7)
	# The tile's MIDDLE: both marks are built about the same point, because the play loop plants on
	# the tile you are STANDING on, so this is the normal case and not a contrived one.
	var at := origin + (Vector2(tile) + Vector2(0.5, 0.5)) * cell
	var mark := AssayHud.building_mark({"pos": tile, "footprint": Vector2i(1, 1)}, cell, origin)
	# THE THREE LISTS `_draw` PAINTS FOR ONE MACHINE, in its order and from the same functions.
	var ink: Array[Rect2] = AssayHud.frame_bands(mark["keyline_rect"], AssayHud.MARK_KEYLINE_PX)
	ink.append_array(AssayHud.frame_bands(mark["rect"], float(mark["stroke"])))
	ink.append_array(AssayHud.frame_bands(mark["hole_rect"], AssayHud.MARK_KEYLINE_PX))
	# Maren's bar, as the shares she wrote. A floor and not an equality: a change that leaves MORE of
	# a person is not a defect, and `is_equal_approx` on a sampled area would be a trap.
	for case in [{"mine": true, "who": "you", "floor": 0.85}, {"mine": false, "who": "a partner",
			"floor": 0.69}]:
		var body: PackedVector2Array = AssayHud.player_mark(at, bool(case["mine"]))["points"]
		var total := 0
		var kept := 0
		# Sampled at a quarter pixel, not a pixel centre: a 1x1's mark sits on half-pixels at cell 9
		# and on integers at cell 32, and a sample that lands on an edge is a coin toss.
		var box := Rect2(body[0], Vector2.ZERO)
		for point in body:
			box = box.expand(point)
		var y := floorf(box.position.y) + 0.25
		while y <= box.end.y:
			var x := floorf(box.position.x) + 0.25
			while x <= box.end.x:
				var point := Vector2(x, y)
				if Geometry2D.is_point_in_polygon(point, body):
					total += 1
					if not _in_any(ink, point):
						kept += 1
				x += 1.0
			y += 1.0
		if total == 0:
			return _fail("%s has a body of 0 sampled pixels, so this test looked at nothing"
					% case["who"])
		var share := float(kept) / float(total)
		if share < float(case["floor"]):
			return _fail(("%s standing on a 1x1 machine keeps %.1f%% of their body (%d of %d px) and "
					+ "Maren's bar is %.0f%%. A machine's mark may take space from the GROUND for "
					+ "free and never from a person (11.14): at `BUILDING_MARK_PX` 16 the inward rim "
					+ "took a partner from 69.2%% to 38.5%%, which is the trade ASSA-236's hollow "
					+ "frame was filed to END (ASSA-278)")
					% [case["who"], 100.0 * share, kept, total, 100.0 * float(case["floor"])])
	return true


## True when [param point] is inside any of [param rects]; the painter's bands as drawn, so a gap
## between two of them is a gap here too.
func _in_any(rects: Array[Rect2], point: Vector2) -> bool:
	for rect in rects:
		if rect.has_point(point):
			return true
	return false


## **THE GLYPH BED COVERS EVERY PIXEL AT DISTANCE 1 FROM THE LETTER'S INK** (ASSA-218, Maren's P1 on
## the half of ASSA-213 that did not work).
##
## WHAT WENT WRONG WITH THE SHIPPED BED, measured on a real window rather than argued: an antialiased
## 2 px outline is about 1 px of solid and 1 px of fade, so on the light-ink case (seed 777042, a
## machine on Minyte at (74,36), white ink on a near-white `HOVER` diamond) only **13% of the letter's
## boundary inside the mark had a 4.5:1 edge within 2 px**. 56.8% of the 600 species-and-purity states
## carry `GLYPH_LIGHT`, so that is the majority case and not a corner.
##
## **THIS IS A PROPERTY AND NOT A LIST.** Asserting that the constant holds eight particular vectors
## would pass any mutation that kept eight vectors. So the test builds an ink mask with the shapes a
## letter actually has -- a stroke, a stroke's END and a one-pixel serif, where a diagonal neighbour
## has no ink two pixels away to be covered from -- works out its own 8-neighbour ring, and asks
## whether every ring pixel lands under some stamped copy. Dropping the four diagonals leaves that
## mask's corners bare and this reddens; a wider OUTLINE would not satisfy it at all, which is the
## point of the item.
##
## **THE INK MASK IS A FIXTURE AND THIS SENTENCE IS THE POINT OF IT** (ASSA-218 box 3, Maren's
## standard, and she accepted the fixture only on condition that it says so). The mask above is five
## squares I typed, not a rasterised glyph, so **it cannot fail when the real letter changes** -- a
## new font, a different `glyph_size`, a letter with a counter this mask has no shape for, and this
## test stays green while the picture moves. By ASSA-189 box 6's letter ("reads the painter's own
## glyph box, not a colour table") that makes it a fixture, and the honest name for what it proves is
## narrow: *given this mask, the eight offsets cover its distance-1 ring.*
##
## **WHAT COVERS THE REAL RASTER, because the alternative to a fixture here is no test at all:**
## nothing headless rasterises a glyph. The real letter is measured on a 1x window shot, and these
## are the two in this item's evidence --
##
##   `shared/assay/marlow-assa218-bed/ring.py`      the 13% -> 81% edge figures
##   `shared/assay/marlow-assa218-bedclaim/`        the three arms behind box 2's surface bar:
##                                                  the bed AS DRAWN is 4.35:1 against a white
##                                                  letter where the bare fill is 9.20:1
##
## Both are seed 777042, a machine standing on Minyte at (74,36). **The judgement on the picture is
## Maren's and the number is not a substitute for it:** her own ASSA-229 finding is that an edge bar
## scores 99-100% on letters reading 2.43:1 against their real surround, so a pass here, and a pass
## on any bar in this family, measures what a mark COSTS a letter and never whether it reads.
func test_the_glyph_bed_covers_every_neighbour_of_the_inks_own_pixels() -> bool:
	var ink := {}
	for y in range(0, 5):
		for x in range(0, 2):
			ink[Vector2i(x, y)] = true
	ink[Vector2i(2, 4)] = true
	ink[Vector2i(4, 0)] = true
	var stamps: Array[Vector2] = AssayHud.GLYPH_BED_STAMPS
	if stamps.is_empty():
		return _fail("the glyph bed stamps no copy of the letter at all, so there is no solid bed "
				+ "under the ink -- only the antialiased outline that ASSA-218 is about")
	for offset: Vector2 in stamps:
		if offset == Vector2.ZERO:
			return _fail("a bed stamp sits at (0,0), which paints the bed colour over the ink itself "
					+ "rather than around it")
	var ring := {}
	for key in ink:
		var at: Vector2i = key
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var near := at + Vector2i(dx, dy)
				if not ink.has(near):
					ring[near] = true
	if ring.is_empty():
		return _fail("premise: the fixture's ink has no ring, so this test measures nothing")
	var bare := []
	for key in ring:
		var at: Vector2i = key
		var covered := false
		for offset: Vector2 in stamps:
			if ink.has(at - Vector2i(offset.round())):
				covered = true
				break
		if not covered:
			bare.append(at)
	if not bare.is_empty():
		return _fail(("%d of %d pixels at distance 1 from the ink are painted by no bed stamp (%s "
				+ "first): on a light letter under a near-white mark those pixels read 1.12:1 and the "
				+ "letter stops having an edge, which is ASSA-218.")
				% [bare.size(), ring.size(), bare[0]])
	# AND THE OUTLINE IS STILL UNDER IT: the stamps are the solid core, the outline the soft 2px edge
	# Maren ruled on ASSA-213. A bed that lost its width would be a different mark.
	if AssayHud.GLYPH_BED_PX < 2.0:
		return _fail("the glyph bed's outline is %.1fpx: the stamps cover distance 1, the outline is "
				% AssayHud.GLYPH_BED_PX + "what makes the rim the width that was ruled")
	return true


## **A SHOT CAN SAY WHETHER A MACHINE WAS STANDING ON A SPECIES LETTER, INCLUDING "NO"** (ASSA-213 box
## 2: "the case is in a shot: a building placed on a deposit CENTRE, not on its edge -- today's shots
## cannot report this absent").
##
## WHY THE SIM'S QUESTION AND THE PAINTER'S ARE ASKED SEPARATELY: a reviewer with only pixels cannot
## tell a run where no machine ever stood on a rock from a run where one did and the map failed to mark
## it. The first is a boring world, the second is ASSA-189. So `machines_on_letters` asks the sim (a
## footprint holding the tile a letter is drawn on) and `letter_occlusions` asks the painter (a diamond
## landing on that letter's cap box), and `tools/window_shot.gd` only reports a defect when they
## disagree.
##
## **THE PREMISE IS MEASURED BEFORE EVERY NEGATIVE, because an empty fixture answers "nothing is
## covered" without looking.** My first premise on this item asked what share of the letter's BOX the
## diamond covered, got 9.3% and called the case absent; the diamond's own share was 99.3%. Both
## numbers are in the output now, and this test pins each to its own denominator -- the failure that
## has cost me three nights is a share divided by the wrong thing.
##
## THE 2x2 CORNER IS THE CASE WORTH A TEST: Cove's enumeration found a smelter whose footprint's
## bottom-right tile is the deposit's centre the worst of four placements (24.9-56.2% of the letter's
## ink). `Rect2i.has_point` is inclusive of `pos` and exclusive of `pos + footprint`, so an off-by-one
## either way reports the game's worst placement as not-in-frame, or a machine one tile past the rock
## as standing on it.
func test_a_machine_on_a_letter_is_told_apart_from_a_machine_beside_one() -> bool:
	var cell := 9.0
	var origin := Vector2(24.0, 96.0)
	var tile := Vector2i(57, 59)
	# The letter's own geometry, written out rather than taken from a font: `_glyph_marks` is what
	# measures a real one (`test_main_screen.gd` holds that end), and a fixture that needed a font
	# could not state its own box. 15x18 at the tile's corner is the shape of a real 25px capital
	# on this map, centred the way `_glyph_marks` centres it.
	var at := origin + Vector2(tile) * cell
	var letters := [
		{"symbol": "R", "tile": tile, "box": Rect2(at - Vector2(7.5, 13.0), Vector2(15.0, 18.0))},
		{"symbol": "M", "tile": Vector2i(20, 20),
				"box": Rect2(origin + Vector2(180.0, 180.0) - Vector2(7.5, 13.0),
						Vector2(15.0, 18.0))},
	]
	var cases := [
		{"pos": tile, "foot": Vector2i(1, 1), "kind": "drill", "on": true},
		{"pos": tile - Vector2i(1, 1), "foot": Vector2i(2, 2), "kind": "smelter", "on": true},
		{"pos": tile + Vector2i(1, 1), "foot": Vector2i(2, 2), "kind": "smelter", "on": false},
		{"pos": tile - Vector2i(3, 0), "foot": Vector2i(1, 1), "kind": "drill", "on": false},
	]
	for case in cases:
		var building := {"pos": case["pos"], "footprint": case["foot"], "kind": case["kind"]}
		var mark: Dictionary = (AssayHud.building_mark(building, cell, origin) as Dictionary)
		var found: Array = AssayHud.machines_on_letters([building], letters)
		var want: bool = case["on"]
		var wanted := 1 if want else 0
		if found.size() != wanted:
			return _fail(("a %s %s at %s against a letter on %s: the sim's own question answered with "
					+ "%d hit(s), wanted %d. `pos` is the footprint's TOP-LEFT and `has_point` is "
					+ "inclusive of it, exclusive of `pos + footprint`.")
					% [case["foot"], case["kind"], case["pos"], tile, found.size(), wanted])
		if want:
			var hit: Dictionary = found[0]
			if String(hit["symbol"]) != "R" or (hit["tile"] as Vector2i) != tile:
				return _fail("a %s at %s was matched to %s on %s, not R on %s"
						% [case["kind"], case["pos"], hit["symbol"], hit["tile"], tile])
		# THE PAINTER'S SIDE, AND THE PREMISE FIRST: an on-centre machine whose diamond misses the box
		# would make every assertion here vacuous, and that is the shape this item's first measurement
		# got wrong.
		var laps: Array = AssayHud.letter_occlusions([mark], letters)
		if want and laps.is_empty():
			return _fail(("premise: a %s %s at %s is on the letter's own tile and its frame (span "
					+ "%s at %s) touches no letter box. The fixture is not the case.")
					% [case["foot"], case["kind"], case["pos"], mark["span"], mark["at"]])
		for entry in laps:
			var lap: Dictionary = entry
			if int(lap["letter"]) != 0:
				return _fail("a %s at %s laps letter %d (%s), which is 180px away"
						% [case["kind"], case["pos"], lap["letter"], lap["symbol"]])
			# **EACH SHARE AGAINST ITS OWN DENOMINATOR.** `share_of_box` is how much of the letter is
			# at risk and `share_of_mark` how much of the mark is spent on it; they are different
			# numbers about different things, and a reader who takes the second for the first concludes
			# the case is not in the picture.
			var box: Rect2 = (letters[0] as Dictionary)["box"]
			var covered := float(lap["covered_px"])
			if absf(float(lap["share_of_box"]) * box.size.x * box.size.y - covered) > 1e-3:
				return _fail(("share_of_box %.4f x the box's %.1fpx is not the %.1fpx covered: the "
						+ "letter's share is being divided by something else")
						% [lap["share_of_box"], box.size.x * box.size.y, covered])
			# **THE MARK'S AREA IS ITS FRAME, NOT ITS BOX** (ASSA-236): the mark is a hollow
			# footprint now, so its denominator is the four bands and the hole comes off it. Taking
			# the bounding box would make `share_of_mark` smaller than it is and read as good news.
			var mark_area := AssayHud.polygon_area(mark["points"] as PackedVector2Array) \
					- AssayHud.polygon_area(mark["hole_points"] as PackedVector2Array)
			if absf(float(lap["share_of_mark"]) * mark_area - covered) > 1e-3:
				return _fail("share_of_mark %.4f x the mark's %.1fpx is not the %.1fpx covered"
						% [lap["share_of_mark"], mark_area, covered])
			if covered <= 0.0:
				return _fail("a lap is reported with %.1fpx covered, which is not a lap" % covered)
	# AND THE BESIDE CASE IS A POSITION AND NOT AN EMPTY LIST: the 3-tiles-west drill's diamond has to
	# be genuinely clear of the box, or "no lap" says nothing about the arithmetic.
	var beside: Dictionary = AssayHud.building_mark({"pos": tile - Vector2i(3, 0),
			"footprint": Vector2i(1, 1), "kind": "drill"}, cell, origin)
	var gap := (letters[0] as Dictionary)["box"] as Rect2
	var span: Vector2 = beside["span"]
	var mark_box := Rect2((beside["at"] as Vector2) - span * 0.5, span)
	if mark_box.intersects(gap):
		return _fail(("premise: the beside-case mark %s overlaps the letter box %s, so this fixture "
				+ "cannot test a miss") % [mark_box, gap])
	if not AssayHud.letter_occlusions([beside], letters).is_empty():
		return _fail("a drill 3 tiles west of the letter is reported as lapping it")
	return true


## **A ONE-TILE MACHINE IS STILL FINDABLE ON A BIG WORLD, AND IT OCCUPIES A PERSON'S BOX ON PURPOSE**
## (Cove's size rule, ASSA-193; the floor is `PLAYER_MARK_PX`'s lesson applied to the other mark).
##
## Maren's finding on the player was that a mark scaling with the tile gets SMALLER exactly as the
## world gets big enough to need a map. A machine's footprint is 1x1: 9px here, 4.5px on a world
## twice as wide, 2px where `map_cell` floors. So the footprint sets the size and `BUILDING_MARK_PX`
## is the floor.
##
## **THIS TEST DEMANDED THE TWO CONSTANTS BE EQUAL AND MAREN SPENT THAT EQUALITY ON 2026-10-08.**
## Its history, because the assertion has now been all three things:
##
## - ASSA-203: `floor < PLAYER_MARK_PX`, mine, reasoning a one-tile machine must not be drawn bigger
##   than a person.
## - ASSA-193: `==`. Cove's answer was equality, not inequality -- the same box, so the SHAPE does all
##   the telling, which is the half that survives greyscale. *"At 14 the diamond reads lighter than a
##   player, at 20 it outweighs one."*
## - **ASSA-278, today: `>`, by Maren's ruling, `BUILDING_MARK_PX` 20 against a person's 16.** Two
##   constants at the same value turned out to be a COLLISION and not a harmony: at 16 a person's body
##   is exactly inscribed in a 1x1's frame, so the inward rim ASSA-278 needed had nowhere to go but
##   onto whoever was standing there -- a partner's cross from 69.2% to 38.5%. 20 is the smallest
##   value at which the rim costs a person nothing the band was not already costing them.
##
## **AND THE SENTENCE HER RULING OVERRULES WAS EVIDENCE OF MINE, NOT TASTE, SO IT GETS AN ANSWER:** "at 20 it
## outweighs one" was measured on a FILLED DIAMOND and this mark has been a hollow frame since
## ASSA-236. Re-measured in mark pixels at cell 9: the frame is 112 px at 16 and 144 px at 20, against
## a body's 136 px and a partner's 156 px. So the machine does now outweigh YOU, by 6% -- my old
## claim was right about the direction. It is a price her ruling spends, and the number is written
## here so that it is spent knowingly rather than discovered by a reader later.
##
## The relationship is still asserted rather than left to drift: a mutation moving either constant
## alone reddens this, and `test_a_person_standing_on_a_machine_keeps_their_body` holds the share that
## is the whole reason for the gap.
##
## WHAT THIS CANNOT SEE: whether 20 is the right number at 1x. That is a judgement on a picture and it
## is Maren's, against `shared/assay/cove-assa193/assa-193-diamond-sizes-1x.png` and the person
## shares in `tools/person_under_machine.gd`.
func test_a_building_mark_has_a_floor_and_it_clears_a_persons_own_box() -> bool:
	if AssayHud.BUILDING_MARK_PX <= AssayHud.PLAYER_MARK_PX:
		return _fail(("the building floor is %.0fpx and a person is %.0fpx. These were EQUAL until "
				+ "ASSA-278, and equality is what made them collide: a body exactly inscribed in a "
				+ "1x1's frame leaves the inward rim nowhere to go but onto the person standing "
				+ "there (a partner 69.2%% -> 38.5%%). The floor must now CLEAR a person's box.")
				% [AssayHud.BUILDING_MARK_PX, AssayHud.PLAYER_MARK_PX])
	for cell: float in [2.0, 4.5, 9.0]:
		var span: Vector2 = AssayHud.building_mark({"pos": Vector2i(1, 1),
				"footprint": Vector2i(1, 1)}, cell, Vector2.ZERO)["span"]
		if absf(span.x - AssayHud.BUILDING_MARK_PX) > 1e-4 \
				or absf(span.y - AssayHud.BUILDING_MARK_PX) > 1e-4:
			return _fail(("a 1x1 machine at %.1fpx a tile is drawn %s, not the %.0fpx floor: on a "
					+ "big world a drill would be a few pixels on the one surface for finding it")
					% [cell, span, AssayHud.BUILDING_MARK_PX])
	# AND THE FLOOR DOES NOT OVERRIDE A FOOTPRINT BIGGER THAN IT: a 2x2 at 18px a tile is 36px.
	var big: Vector2 = AssayHud.building_mark({"pos": Vector2i(1, 1), "footprint": Vector2i(2, 2)},
			18.0, Vector2.ZERO)["span"]
	if absf(big.x - 36.0) > 1e-4:
		return _fail("a 2x2 at 18px a tile is %s, and the footprint is what sizes it" % big)
	# **SQUARE OFF THE LONGER SIDE, WHICH IS WHAT A PER-AXIS FLOOR GETS WRONG.** Cove's rule is one
	# `s` from `max(foot.x, foot.y)`; what I shipped took the floor per axis, so a footprint that is
	# not square came out a rhombus -- a shape that leans, stating a facing `BuildingFacts` does not
	# carry. That is the reason their chevron candidate lost, arrived at by accident.
	for case in [{"foot": Vector2i(3, 1), "cell": 9.0}, {"foot": Vector2i(1, 4), "cell": 32.0}]:
		var foot: Vector2i = case["foot"]
		var cell: float = case["cell"]
		var span: Vector2 = AssayHud.building_mark({"pos": Vector2i(2, 2), "footprint": foot},
				cell, Vector2.ZERO)["span"]
		var want := maxf(float(maxi(foot.x, foot.y)) * cell, AssayHud.BUILDING_MARK_PX)
		if absf(span.x - want) > 1e-4 or absf(span.y - want) > 1e-4:
			return _fail(("a %s building at %.0fpx a tile is drawn %s, not %.0f square: a per-axis "
					+ "size makes a leaning rhombus out of a footprint that is not square.")
					% [foot, cell, span, want])
	return true


## **THE WINDOW SAYS "dead end" IN THE SIM'S WORDS, AND NEVER IN ITS OWN** (ASSA-158).
##
## Maren's ruling is that a permanent dead end may not be drawn in the same series as a cost: one
## can become true by playing, the other never can. The row used to render `— nothing uses a gear`,
## which is the cost clause's em dash and `_note`'s ink, both measured byte-identical at
## (167,176,190).
##
## **WHAT THIS GUARDS IS THE HALF A SHOT CANNOT**: that the label is the SIM'S. `sim-cli`'s
## catalogue has printed it since ASSA-122, so a client with its own copy would be the ASSA-43/52
## shape — two surfaces free to drift on the Game Director's wording. A source scan is the right
## instrument because the defect is a literal appearing in a client file, which no rendered frame
## can tell apart from the correct one.
##
## NOT guarded here, and said rather than implied: the drawn INK of the two clauses is still
## identical, and whether a label alone separates them at 1x is Maren's judgement on a window shot.
func test_the_dead_end_label_comes_from_the_sim_and_not_from_this_client() -> bool:
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	if main_src == "":
		return _fail("could not read main.gd, so this scan proves nothing")
	# The premise: the row still renders a dead end at all.
	if not main_src.contains("dead_end_label()"):
		return _fail("main.gd no longer asks the sim for the label")
	# The defect: the words typed into a client file. Comments are allowed to
	# discuss them, so only non-comment lines are scanned.
	for raw in main_src.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			continue
		if line.to_lower().contains("\"dead end"):
			return _fail(("main.gd spells the dead-end label itself; it is the sim's word, through "
					+ "`AssaySim.dead_end_label()` (ASSA-158): %s") % line)
	# And the em dash it used to share with the cost clause is gone from THIS row.
	if main_src.contains("_note(\"— %s\" % dead_end)"):
		return _fail("the dead end is still drawn in the cost clause's em-dash series")
	return true


## **THE DOOR PLATE CAN NEVER BE BIGGER THAN THE DOOR** (ASSA-292).
##
## THIS TEST EXISTS BECAUSE THE FIRST PLATE WAS 565x1452 INSIDE A 912x672 DOOR -- taller than the
## whole window -- and I could not explain it from the scene, so I withdrew it rather than patch it.
## The cause is reachable from `main.gd`'s own note one caller away: `autowrap_mode` does not lower a
## Label's reported minimum, so the door sentence can be measured at a width it will never be drawn
## at and its height balloons. **The fix is not to chase that number but to make it unable to reach
## the screen**, and that is one `intersection`.
##
## The pathological case is a real measurement and not an invented one, which is the difference
## between a regression test and a test that agrees with me.
func test_the_door_plate_is_always_inside_the_door() -> bool:
	var door := AssayHud.join_rect()
	var pad := AssayHud.DOOR_PLATE_PAD
	# 1. THE ORDINARY CASE: a block of words near the middle of the door is padded on every side.
	var words := Rect2(door.position + Vector2(200.0, 250.0), Vector2(500.0, 210.0))
	var plate := AssayHud.door_plate_rect(door, words)
	if not door.encloses(plate):
		return _fail("an ordinary block of words produced a plate %s outside the door %s"
				% [plate, door])
	if not plate.encloses(words):
		return _fail("the plate %s does not contain the words %s it is supposed to carry"
				% [plate, words])
	if absf(plate.size.x - (words.size.x + pad * 2.0)) > 0.01 \
			or absf(plate.size.y - (words.size.y + pad * 2.0)) > 0.01:
		return _fail("the plate is %s for words %s: that is not one pad of air on each side"
				% [plate.size, words.size])
	# 2. **THE REGRESSION, WITH THE NUMBER THAT ACTUALLY HAPPENED.** A 1404 px tall content rect is
	# what a mid-layout autowrap Label reported on the night this was withdrawn.
	var ballooned := Rect2(door.position, Vector2(517.0, 1404.0))
	plate = AssayHud.door_plate_rect(door, ballooned)
	if not door.encloses(plate):
		return _fail(("content %s (the real mid-layout measurement) produced a plate %s outside the "
				+ "door %s: the clip is gone and a Label's minimum can paint over the window again")
				% [ballooned.size, plate, door])
	if plate.size.y > door.size.y:
		return _fail("the plate is %.0f px tall in a %.0f px door" % [plate.size.y, door.size.y])
	# 3. CONTENT NOWHERE NEAR THE DOOR IS AN EMPTY PLATE, not a plate somewhere else. The caller
	# reads this as "nothing to stand on yet" and draws nothing.
	var elsewhere := Rect2(door.end + Vector2(500.0, 500.0), Vector2(100.0, 100.0))
	plate = AssayHud.door_plate_rect(door, elsewhere)
	if plate.size.x > 0.0 and plate.size.y > 0.0:
		return _fail("words %s are off the door entirely and still produced a plate %s"
				% [elsewhere, plate])
	return true


## **A CENTRED LABEL IS MOSTLY NOT WORDS** (ASSA-292, Maren's card ruling). `AssayHud.label_ink_rect`
## carries the reasoning; this is the arithmetic, on the numbers that actually caused the defect.
##
## THE WORDMARK'S NUMBERS ARE MAREN'S OWN MEASUREMENT off the 1x frame -- **152x53 of ink** in a
## centred Label as wide as the door -- so case 1 is this screen's real case and not a shape I chose
## to pass.
func test_a_centred_label_is_asked_for_its_ink_and_not_its_width() -> bool:
	# 1. THE WORDMARK. 1280 px of control, 152 px of word, and the ink is centred in it.
	var band := Rect2(Vector2(0.0, 229.0), Vector2(1280.0, 64.0))
	var ink := AssayHud.label_ink_rect(band, Vector2(152.0, 53.0), HORIZONTAL_ALIGNMENT_CENTER)
	if absf(ink.size.x - 152.0) > 0.01:
		return _fail("a 152 px wordmark in a 1280 px Label measured %.0f px wide: a plate fitted to "
				% ink.size.x + "this is still a band across the whole door")
	if absf(ink.get_center().x - band.get_center().x) > 0.01:
		return _fail("the ink is centred in the Label on screen and this puts it at x=%.1f against "
				% ink.get_center().x + "the Label's centre %.1f" % band.get_center().x)
	# **THE HEIGHT IS THE CONTROL'S AND NOT THE MEASUREMENT'S**, deliberately: a `VBoxContainer`
	# already gives a Label its content height, and a measured height here would be a second opinion
	# about line spacing -- which shows up as one clipped descender, not as a test failure.
	if absf(ink.size.y - band.size.y) > 0.01:
		return _fail("the ink rect is %.0f px tall and the Label is %.0f: the height is the "
				% [ink.size.y, band.size.y] + "container's answer and must come across untouched")
	if not band.encloses(ink):
		return _fail("the ink %s is not inside the Label %s that holds it" % [ink, band])
	# 2. **INK WIDER THAN ITS CONTROL IS THE MEASUREMENT TO DISTRUST, NOT THE CONTROL.** This is the
	# mid-layout autowrap case that produced a 1452 px plate in a 672 px door last night, in its
	# horizontal form: clamped, so it can never widen a card past the thing it was measured in.
	var narrow := Rect2(Vector2(100.0, 100.0), Vector2(200.0, 40.0))
	ink = AssayHud.label_ink_rect(narrow, Vector2(900.0, 40.0), HORIZONTAL_ALIGNMENT_CENTER)
	if not narrow.encloses(ink):
		return _fail("a 900 px measurement in a 200 px Label produced %s, outside it" % ink)
	# 3. LEFT AND RIGHT, because the two Labels that move into the toast in a world keep their own
	# alignment and this function has to be right for all three.
	ink = AssayHud.label_ink_rect(band, Vector2(300.0, 20.0), HORIZONTAL_ALIGNMENT_LEFT)
	if absf(ink.position.x - band.position.x) > 0.01:
		return _fail("left-aligned ink starts at x=%.1f and the Label at %.1f"
				% [ink.position.x, band.position.x])
	ink = AssayHud.label_ink_rect(band, Vector2(300.0, 20.0), HORIZONTAL_ALIGNMENT_RIGHT)
	if absf(ink.end.x - band.end.x) > 0.01:
		return _fail("right-aligned ink ends at x=%.1f and the Label at %.1f"
				% [ink.end.x, band.end.x])
	return true


## **THE MACHINE MENU GOES IN THE HALF ITS MACHINE IS NOT IN** (ASSA-316, Maren's ruling 1).
##
## **THE PROPERTY IS "NEVER COVERS THE MACHINE", AND IT IS CHECKED AGAINST THE TILE RATHER THAN AGAINST
## A HALF I NAME HERE.** A test that asserted "x is 504 for a machine on the left" would pass a function
## that had both halves swapped and a sign error cancelling out. So this walks the world's whole width,
## asks for the room at every step, and requires that the machine's own column is outside it -- which is
## the clause the ruling exists for and the one a reader can check by eye.
func test_a_machine_menu_never_opens_over_its_own_machine() -> bool:
	var world := AssayHud.world_rect()
	var halves := {}
	for step in range(0, 913, 8):
		var middle := world.position.x + float(step)
		var room := AssayHud.machine_menu_room(world, middle)
		if room.position.x <= middle and middle <= room.end.x:
			return _fail("a machine at x=%.0f is inside its own menu's room %s" % [middle, room])
		if not world.encloses(room):
			return _fail("the room %s for a machine at x=%.0f is not inside the world %s"
					% [room, middle, world])
		halves[room.position.x] = true
	# **TWO PLACES A PLAYER CAN LEARN, AND NOT THREE.** Her ruling is one boolean; a function that
	# slid the panel along with the machine would pass every check above and fail this one.
	if halves.size() != 2:
		return _fail("a menu opens in %d places across the world, not 2: %s"
				% [halves.size(), halves.keys()])
	return true


## **THE CENTRE LINE IS DECIDED, NOT LEFT TO A FLOAT** (her "deterministic on the exact centre"), AND
## THE CAP IS HALF THE WORLD LESS TWO PADS.
func test_a_machine_menus_room_is_bounded_and_decided_on_the_boundary() -> bool:
	var world := AssayHud.world_rect()
	var middle := world.get_center().x
	var room := AssayHud.machine_menu_room(world, middle)
	# Maren's test is `machine.centre.x < world.centre.x`, which is FALSE on the line: the machine
	# counts as being in the right half, so the menu goes left.
	if room.position.x > middle:
		return _fail("a machine exactly on the centre line sent the menu right, to %s" % room)
	# AND A HAIR EITHER SIDE MUST DISAGREE, or the branch above is vacuous.
	if AssayHud.machine_menu_room(world, middle - 0.5).position.x <= middle:
		return _fail("a machine just left of centre did not send the menu right")
	var want := Vector2(world.size.x * 0.5, world.size.y) - AssayHud.MARGIN * 2.0
	if not room.size.is_equal_approx(want):
		return _fail("the room is %s and half the world less two pads is %s" % [room.size, want])
	return true


## **ONE AND HALF ARE THE ONLY COUNTS DERIVABLE FROM A STACK** (ASSA-316, Maren's ruling 4), AND
## NEITHER IS EVER THE WHOLE STACK -- that is the row's own button, labelled with the result.
func test_a_slots_fractions_are_derived_from_the_stack_and_never_repeat_it() -> bool:
	var cases := {1: [], 2: [1], 3: [1], 4: [1, 2], 37: [1, 18], 210: [1, 105]}
	for count in cases:
		var got := AssayHud.insert_fractions(int(count))
		var want: Array = cases[count]
		if got.size() != want.size():
			return _fail("a stack of %d offers %s, want %s" % [count, got, want])
		for i in range(want.size()):
			if got[i] != int(want[i]):
				return _fail("a stack of %d offers %s, want %s" % [count, got, want])
		if got.has(int(count)):
			return _fail("a stack of %d offers the whole stack as a fraction: %s" % [count, got])
	# A STACK OF 0 IS NOT A ROW, and nothing may be offered for it: `held` answers 0 between the
	# press and the bundle that spends the stack.
	if not AssayHud.insert_fractions(0).is_empty():
		return _fail("a stack of 0 offers %s" % AssayHud.insert_fractions(0))
	return true


## **A SLOT BUTTON NAMES THE RESULT AND A TOGGLE NAMES WHAT YOU WILL GET** (ruling 4). The wording is
## the only thing in this menu that is this client's own, so it is held somewhere a reader can see it.
func test_a_slot_buttons_label_is_the_result_with_its_own_number() -> bool:
	if AssayHud.insert_label(37, "Tonore ore") != "put all 37 Tonore ore":
		return _fail("a slot button reads `%s`" % AssayHud.insert_label(37, "Tonore ore"))
	if AssayHud.insert_some_label(18) != "or 18":
		return _fail("a fraction toggle reads `%s`" % AssayHud.insert_some_label(18))
	return true


## **THE OPEN MENU'S MACHINE GIVES UP ITS LINE IN THE CURSOR READOUT, AND ONLY THAT ONE** (ASSA-316,
## Maren's ruling 6: one fact, one home).
func test_the_machine_whose_menu_is_open_leaves_the_cursor_readout() -> bool:
	var tile := {
		"pos": Vector2i(56, 40),
		"in_bounds": true,
		"chunk": Vector2i(3, 2),
		"chunks_from_spawn": 0,
		"ground_note": "no deposit here",
		"building": {"id": 7, "name": "Minyte machine (B)", "kind": "machine",
				"status": "holding 0 of 210 · mining Minyte"},
	}
	var shown := "\n".join(AssayHud.tile_lines(tile))
	if not shown.contains("Minyte machine (B)"):
		return _fail("the readout does not name a building standing on the tile: %s" % shown)
	var hidden := "\n".join(AssayHud.tile_lines(tile, 7))
	if hidden.contains("Minyte machine (B)"):
		return _fail("the machine whose menu is open is still in the readout: %s" % hidden)
	# EVERY OTHER LINE STAYS. The tile, the chunk, the ground: this drops one line, not a section.
	if not hidden.contains("no deposit here") or not hidden.contains("(56, 40)"):
		return _fail("dropping the building's line took the rest of the readout with it: %s" % hidden)
	# ANOTHER MACHINE'S MENU DOES NOT SILENCE THIS ONE.
	if not "\n".join(AssayHud.tile_lines(tile, 8)).contains("Minyte machine (B)"):
		return _fail("a menu open for building 8 hid building 7's line")
	# **AND A BUILDING WITH NO ID IS NOT SILENCED BY THE DEFAULT.** -1 is "no menu open"; a dictionary
	# with no `id` also reads -1, and that pair is the one way this could drop the line nobody asked
	# it to -- on the building whose name is missing, where this readout is the last surface left.
	var nameless := tile.duplicate(true)
	(nameless["building"] as Dictionary).erase("id")
	(nameless["building"] as Dictionary).erase("name")
	if not "\n".join(AssayHud.tile_lines(nameless)).contains("machine"):
		return _fail("a building with no id lost its line with no menu open: %s"
				% "\n".join(AssayHud.tile_lines(nameless)))
	return true


## **WHERE THE BUILD SCREEN IS ALLOWED TO BE, AS THE THREE THINGS IT MAY NEVER COVER** (ASSA-328;
## Maren's `assay-build-screen` §1).
##
## **THE HUD COLUMN IS ASSERTED AGAINST THE WINDOW, NOT AGAINST `world_rect()`.** Staying off the
## column falls out of taking the world as the frame, so comparing the screen to the world would be a
## check that cannot fail -- the defect shape I have written down twice now. `VIEW.x - PANEL` is where
## the column starts in the WINDOW, which is the claim a player can see.
func test_the_build_screen_covers_neither_the_hud_column_nor_the_worlds_own_controls() -> bool:
	var world := AssayHud.world_rect()
	var band := world.end.y - AssayHud.WORLD_CONTROLS_BAND
	var rect := AssayHud.build_screen_rect(world, band)
	var column := AssayHud.VIEW.x - AssayHud.PANEL
	if rect.end.x > column:
		return _fail("the screen reaches x %.0f and the HUD column starts at %.0f; a screen over the "
				% [rect.end.x, column] + "log is a surface whose failure mode is silence")
	if rect.end.y > band - AssayHud.BUILD_SCREEN_CLEARANCE:
		return _fail("the screen's bottom is %.0f and the world's control band starts at %.0f; the "
				% [rect.end.y, band] + "status toast and `whole world (V)` live in there")
	# NOTHING BELOW THE FOLD AT 1280x720, which is the item's own box and is about the WINDOW.
	if rect.position.y < 0.0 or rect.end.y > AssayHud.VIEW.y or rect.position.x < 0.0:
		return _fail("the screen is %s, which leaves the %s window" % [rect, AssayHud.VIEW])
	if rect.size.x < 320.0 or rect.size.y < 320.0:
		return _fail("the screen is %s, which is too small to hold three columns" % rect.size)
	return true


## **THE BAND IS A MEASUREMENT AND THIS IS THE LEVER THAT PROVES THE SCREEN READS IT** (ASSA-328).
##
## **MY OWN WRITTEN-DOWN RULE: a state green for free is a hole, and a guard with no lever is the same
## thing.** `build_screen_rect` takes the band's top as an ARGUMENT precisely so the real client can
## hand it a measurement off the live controls instead of a constant -- and a function that ignored
## that argument would pass every assertion in the test above, because the shipped band and the
## shipped constant agree. So: raise the band and the screen must get shorter by exactly as much.
func test_the_build_screen_gives_back_whatever_the_control_band_takes() -> bool:
	var world := AssayHud.world_rect()
	var band := world.end.y - AssayHud.WORLD_CONTROLS_BAND
	var tall := AssayHud.build_screen_rect(world, band)
	var raised := AssayHud.build_screen_rect(world, band - 60.0)
	if not is_equal_approx(tall.size.y - raised.size.y, 60.0):
		return _fail(("a band 60 px taller shortened the screen by %.0f, so the screen is not reading "
				+ "the band it is handed") % (tall.size.y - raised.size.y))
	if raised.size.x != tall.size.x:
		return _fail("raising the band changed the screen's WIDTH from %.0f to %.0f"
				% [tall.size.x, raised.size.x])
	# **AND A BAND THAT SWALLOWS THE WHOLE WORLD YIELDS NO SCREEN RATHER THAN AN INVERTED ONE.** A
	# negative height is a rect Godot draws inside out; an empty one is a state a caller can see.
	var none := AssayHud.build_screen_rect(world, world.position.y)
	if none.size.y != 0.0:
		return _fail("a band at the top of the world left a screen %s tall" % none.size.y)
	# THE OTHER WAY: no band at all cannot grow the screen past the world's own pad, or the screen
	# would hang below the world the day a control is deleted.
	var free := AssayHud.build_screen_rect(world, world.end.y + 1000.0)
	if free.end.y > world.end.y - AssayHud.MARGIN.y:
		return _fail("with no band in the way the screen reaches %.0f and the world's pad ends at %.0f"
				% [free.end.y, world.end.y - AssayHud.MARGIN.y])
	return true
