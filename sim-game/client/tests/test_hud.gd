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


## **A ROCK NOTHING CAN MINE IS A HOLLOW DISC, AND IT PAYS FOR THAT OUT OF NO OTHER CHANNEL**
## (ASSA-187, Maren's ruling). Hue is the species, brightness is the purity, radius is the radius; the
## fourth fact — whether anything you can build gets the ore out — had nowhere to go, on the one
## surface whose job is choosing where to walk.
##
## **SWEPT, AND THE SWEEP IS THE POINT.** All six tints x purity 1..100 x both states: `colour` must
## be bit-identical to `deposit_color` in BOTH, which is box 4 ("the existing three channels are not
## traded away for the new one") expressed as an identity rather than an opinion. A fix that dimmed
## or re-tinted the unminable disc fails here, and that is the fix the ruling forbids.
##
## **THE INK IS CHECKED FOR OPTIMALITY, NOT AGAINST A NUMBER**, exactly as
## `test_the_species_letter_always_takes_the_higher_contrast_colour` argues: picking the better of two
## is optimal by construction, so the invariant cannot rot when a tint moves. What IS asserted as a
## number is that the hollow state is no worse than the filled family's worst (4.5), because the
## letter sits on `MAP_BG` there rather than on the species colour -- a hollow disc with an ink chosen
## for a fill that is not there would be the obvious way to break box 4 while passing everything else.
## Measured: 17.06 on the bare map against 4.52 at the worst fill, so the letter reads BETTER hollow.
##
## WHAT THIS CANNOT SEE: that `main.gd::_draw` consumes any of it. `test_main_screen.gd` holds the
## wiring and the shot holds the picture; a painter that ignored `filled` leaves this green.
func test_a_rock_nothing_can_mine_is_hollow_and_trades_no_other_channel() -> bool:
	var checked := 0
	var worst_hollow := 99.0
	var worst_filled := 99.0
	for species in range(AssayHud.SPECIES_TINTS.size()):
		for purity in range(1, 101):
			var want := AssayHud.deposit_color(species, purity)
			for minable: bool in [true, false]:
				var deposit := {"species": species, "purity": purity, "hand_minable": minable}
				var disc := AssayHud.deposit_disc(deposit, 18.0)
				var colour: Color = disc["colour"]
				if colour != want:
					return _fail(("species %d at purity %d, minable %s: the disc is %s and "
							+ "`deposit_color` says %s. Species and purity are the other two reads "
							+ "and this item may not spend them.") % [species, purity, minable,
							colour, want])
				if bool(disc["filled"]) != minable:
					return _fail(("species %d at purity %d: minable %s was drawn filled=%s. Fill "
							+ "IS the channel; inverted, every dead end reads as a patch worth a "
							+ "40-tile walk.") % [species, purity, minable, disc["filled"]])
				# THE SURFACE THE LETTER SITS ON, which is the whole reason the ink differs: a
				# hollow disc shows `MAP_BG` through itself, so coverage is 0 there.
				var lit := AssayHud.MAP_BG.lerp(Color(colour.r, colour.g, colour.b),
						1.0 if minable else 0.0)
				var dark := _wcag_ratio(lit, AssayHud.GLYPH_DARK)
				var light := _wcag_ratio(lit, AssayHud.GLYPH_LIGHT)
				var ink: Color = disc["ink"]
				var took: float = dark if ink == AssayHud.GLYPH_DARK else light
				if took < maxf(dark, light) - 1e-6:
					return _fail(("species %d at purity %d, minable %s: the letter took the ink "
							+ "worth %f when %f was there. An ink chosen for a fill that is not "
							+ "drawn is how the hollow disc would lose its letter.")
							% [species, purity, minable, took, maxf(dark, light)])
				if minable:
					worst_filled = minf(worst_filled, took)
				else:
					worst_hollow = minf(worst_hollow, took)
				checked += 1
	if checked != 1200:
		return _fail("swept %d states, expected 1200" % checked)
	if worst_hollow < 4.5:
		return _fail(("the letter on a hollow disc is worth only %f, under the %f the worst FILLED "
				+ "disc manages. Box 4 is that the species letter still reads.")
				% [worst_hollow, worst_filled])
	print("    disc letter: worst %f filled, %f hollow (hollow sits on MAP_BG, so it reads better)"
			% [worst_filled, worst_hollow])
	# AND THE OUTLINE IS THICK ENOUGH TO CARRY A COLOUR. A 1px ring at a few per cent coverage reads
	# as grey, which would spend the purity channel to buy this one.
	for radius: float in [9.0, 18.0, 36.0, 200.0]:
		var stroke := float(AssayHud.deposit_disc(
				{"species": 0, "purity": 50, "hand_minable": false}, radius)["stroke"])
		if stroke < 2.0 or stroke > 6.0 or absf(stroke - clampf(radius * 0.2, 2.0, 6.0)) > 1e-6:
			return _fail("a radius-%f disc outlines at %f px" % [radius, stroke])
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
	tile["building"] = {"id": 2, "kind": "smelter", "pos": Vector2i(10, 9), "status": "no fuel"}
	tile["players_here"] = PackedStringArray(["ada", "limpet"])
	var lines := "\n".join(AssayHud.tile_lines(tile))
	for wanted in ["DEPLETED", "smelter 2", "no fuel", "ada, limpet"]:
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
	if not lines.contains("Tonore smelter (A) 2"):
		return _fail("the building is not named: %s" % lines)
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
	if not String(occupied[2]).contains("Minyte smelter (B) 0"):
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
	if not joined.contains("kuri smelter (B) 0"):
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
	var joined := AssayHud.status_color(AssayHud.Say.JOINED)
	if joined.g <= joined.r or joined.g <= joined.b:
		return _fail("the joined colour is not green: %s" % joined)
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
	var joined := AssayHud.status_color(AssayHud.Say.JOINED)
	if not accent.is_equal_approx(joined):
		return _fail(("the theme's ACCENT %s is no longer status_color(JOINED) %s. One of them was "
				+ "changed alone, and a focused field and a good status are now two opinions about "
				+ "success") % [accent, joined])
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
## at 912x600 is 220. `chrome + newest + (n - 1) * pitch` is the panel's height, which is the same
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
## - the footprint rect's CORNER, which a filled rect contains and a diamond leaves empty;
## - the 45-degree point at 0.6 of the radius, which an inscribed CIRCLE contains (0.849r) and a
##   diamond does not (|x| + |y| = 1.2r against a limit of r).
##
## Plus the area, which pins it exactly: a diamond is half of its own bounding box, where a rect is
## all of it and an inscribed circle is pi/4 of it (78.5%). Three different numbers, one measurement.
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
func test_a_building_on_the_schematic_is_neither_a_disc_nor_a_rect() -> bool:
	var origin := Vector2(24.0, 96.0)
	for case in [{"foot": Vector2i(2, 2), "cell": 9.0}, {"foot": Vector2i(1, 1), "cell": 9.0},
			{"foot": Vector2i(2, 2), "cell": 18.0}, {"foot": Vector2i(3, 2), "cell": 32.0}]:
		var foot: Vector2i = case["foot"]
		var cell: float = case["cell"]
		var pos := Vector2i(12, 7)
		var mark := AssayHud.building_mark({"pos": pos, "footprint": foot}, cell, origin)
		var points: PackedVector2Array = mark["points"]
		if points.size() != 4:
			return _fail("a %s building drew a %d-point mark" % [foot, points.size()])
		# BOX 2: THE TILE THE SIM GAVE IT. The top-left corner tile plus half the footprint.
		var want := origin + (Vector2(pos) + Vector2(foot) * 0.5) * cell
		var at: Vector2 = mark["at"]
		if at.distance_to(want) > 1e-4:
			return _fail(("a %s building at tile %s and %.0fpx a tile is centred on %s; its "
					+ "footprint's centre is %s. `pos` is the TOP-LEFT, so reading it as the centre "
					+ "draws a smelter a tile up and left of itself.") % [foot, pos, cell, at, want])
		var span: Vector2 = mark["span"]
		var box := Rect2(at - span * 0.5, span)
		# BOX 3, HALF ONE: NOT A FILLED RECT. The bounding box's own corner is outside the mark.
		for corner: Vector2 in [box.position, box.position + Vector2(box.size.x, 0.0),
				box.position + Vector2(0.0, box.size.y), box.end]:
			var inset := corner + (at - corner).normalized() * 0.5
			if Geometry2D.is_point_in_polygon(inset, points):
				return _fail(("a %s building's mark contains its own bounding-box corner %s, so it "
						+ "is a filled rect: at %.0fpx a tile that is the player's shape at the "
						+ "player's size (%.0fpx) separated only by hue, on the one view co-op "
						+ "exists for.") % [foot, corner, cell, AssayHud.PLAYER_MARK_PX])
		# BOX 3, HALF TWO: NOT A DISC. A point an inscribed circle contains, 0.849 of the way out.
		var radius := minf(span.x, span.y) * 0.5
		var diagonal := at + Vector2(1.0, 1.0).normalized() * radius * 0.849
		if Geometry2D.is_point_in_polygon(diagonal, points):
			return _fail(("a %s building's mark contains %s, which is inside an inscribed circle of "
					+ "radius %.1f. A disc is the deposit's shape and deposits are 18-36px of "
					+ "radius on this view.") % [foot, diagonal, radius])
		# AND THE AREA PINS WHICH SHAPE IT IS: half the box, against a rect's 100% and a circle's
		# 78.5%. Shoelace, so a mark that grew a fifth point is measured rather than assumed.
		var area := 0.0
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			area += a.x * b.y - b.x * a.y
		area = absf(area) * 0.5
		var ratio := area / (span.x * span.y)
		if absf(ratio - 0.5) > 0.01:
			return _fail(("a %s building's mark covers %.1f%% of its bounding box. A diamond is "
					+ "50%%, a filled rect 100%% and an inscribed circle 78.5%%; this is the number "
					+ "that says which of the three it is.") % [foot, ratio * 100.0])
		# THE EDGE IS THE MAP'S OWN GROUND AND NOT A NEW COLOUR: a drill is planted ON a deposit, so
		# the ring is what separates this mark from a bright species tint under it.
		if mark["edge"] != AssayHud.MAP_BG:
			return _fail("the mark's ring is %s and not MAP_BG" % mark["edge"])
		if float(mark["edge_width"]) < 1.0:
			return _fail("a ring %.2fpx wide is a sub-pixel line, which separates nothing"
					% mark["edge_width"])
	return true


## **A ONE-TILE MACHINE IS STILL FINDABLE ON A BIG WORLD, AND STILL SMALLER THAN A PERSON** (ASSA-189,
## and it is `PLAYER_MARK_PX`'s lesson applied to the other mark).
##
## Maren's finding on the player was that a mark scaling with the tile gets SMALLER exactly as the
## world gets big enough to need a map. A machine's footprint is 1x1: 9px here, 4.5px on a world
## twice as wide, 2px where `map_cell` floors. So the footprint sets the size and
## `BUILDING_MARK_MIN_PX` is the floor -- and the floor is BELOW the player's 16px on purpose,
## because a one-tile machine drawn bigger than a person is the mistake in the other direction.
func test_the_smallest_building_mark_has_a_floor_and_stays_under_the_player() -> bool:
	if AssayHud.BUILDING_MARK_MIN_PX >= AssayHud.PLAYER_MARK_PX:
		return _fail(("the building floor is %.0fpx and a player is %.0fpx, so a one-tile machine is "
				+ "drawn at least as big as a person")
				% [AssayHud.BUILDING_MARK_MIN_PX, AssayHud.PLAYER_MARK_PX])
	for cell: float in [2.0, 4.5, 9.0]:
		var span: Vector2 = AssayHud.building_mark({"pos": Vector2i(1, 1),
				"footprint": Vector2i(1, 1)}, cell, Vector2.ZERO)["span"]
		if absf(span.x - AssayHud.BUILDING_MARK_MIN_PX) > 1e-4 \
				or absf(span.y - AssayHud.BUILDING_MARK_MIN_PX) > 1e-4:
			return _fail(("a 1x1 machine at %.1fpx a tile is drawn %s, not the %.0fpx floor: on a "
					+ "big world a drill would be a few pixels on the one surface for finding it")
					% [cell, span, AssayHud.BUILDING_MARK_MIN_PX])
	# AND THE FLOOR DOES NOT OVERRIDE A FOOTPRINT BIGGER THAN IT: a 2x2 at 18px a tile is 36px.
	var big: Vector2 = AssayHud.building_mark({"pos": Vector2i(1, 1), "footprint": Vector2i(2, 2)},
			18.0, Vector2.ZERO)["span"]
	if absf(big.x - 36.0) > 1e-4:
		return _fail("a 2x2 at 18px a tile is %s, and the footprint is what sizes it" % big)
	return true
