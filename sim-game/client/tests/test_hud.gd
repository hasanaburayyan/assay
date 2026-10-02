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


## A LETTER ON A PATCH HAS TO BE READABLE ON EVERY PATCH, which is the whole point of having it: the
## tints clear the colour-blindness floor by single digits, so the glyph is what a protan player
## actually reads. Measured as a contrast ratio against the deposit colour composited over the map,
## at the purities the map really draws, for all six slots. The floor is 3.0, WCAG's bar for large
## text.
##
## This is an INSTRUMENT, not an echo of `glyph_color`: it computes contrast, where the function
## decides a threshold. A tint added later that no letter can sit on fails here instead of shipping.
## (Godot's `get_luminance` is a weighted sum of sRGB values, not linearised, so these numbers are a
## consistent measure rather than a certified WCAG figure -- the comparison is what is load-bearing.)
func test_the_species_letter_is_readable_on_every_patch() -> bool:
	var worst := 99.0
	var worst_at := ""
	for species in range(AssayHud.SPECIES_TINTS.size()):
		for purity in [1, 25, 50, 75, 100]:
			var patch := AssayHud.deposit_color(species, purity)
			var lit := AssayHud.MAP_BG.lerp(Color(patch.r, patch.g, patch.b), patch.a)
			var glyph := AssayHud.glyph_color(patch)
			var high: float = maxf(lit.get_luminance(), glyph.get_luminance()) + 0.05
			var low: float = minf(lit.get_luminance(), glyph.get_luminance()) + 0.05
			var ratio := high / low
			if ratio < worst:
				worst = ratio
				worst_at = "species %d at purity %d (%s on %s)" % [species, purity, glyph, lit]
	if worst < 3.0:
		return _fail("the worst species letter makes a contrast ratio of %f, under 3.0: %s"
				% [worst, worst_at])
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


func test_empty_ground_and_spawn_are_told_apart() -> bool:
	var ground := AssayHud.tile_lines({"in_bounds": true, "pos": Vector2i(1, 2),
			"chunk": Vector2i(0, 0), "chunks_from_spawn": 3, "is_spawn": false})
	if not "\n".join(ground).contains("empty ground"):
		return _fail("a bare tile read as %s" % [ground])
	var spawn := AssayHud.tile_lines({"in_bounds": true, "pos": Vector2i(48, 32),
			"chunk": Vector2i(3, 2), "chunks_from_spawn": 0, "is_spawn": true})
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
func _tile_with(extra: Dictionary) -> Dictionary:
	var deposit := {"id": 4, "species": 1, "species_name": "kuri", "center": Vector2i(10, 9),
			"radius": 3, "amount": 37, "purity": 62, "grade": "B", "depleted": false,
			"assayed": false}
	for key in extra:
		deposit[key] = extra[key]
	return {"in_bounds": true, "pos": Vector2i(10, 9), "chunk": Vector2i(0, 0),
			"chunks_from_spawn": 3, "is_spawn": false, "deposit": deposit, "building": null,
			"players_here": PackedStringArray()}


## A design as `AssaySim.designs_of` hands it over: an UNCERTAIN held pick of one rough species.
func _design() -> Dictionary:
	return {
		"index": -1, "in_hand": true, "verdict": "UNCERTAIN",
		"mass_low": 26, "mass_high": 50, "budget_low": 40, "budget_high": 40,
		"mount": "held", "durability": "100% of 2400-3600",
		"unassayed": PackedStringArray(["Korvite"]),
		"parts": [
			{"kind": "frame", "species": 0, "species_name": "Korvite", "symbol": "K",
					"grade": "B", "mass_low": 18, "mass_high": 34},
			{"kind": "head", "species": 0, "species_name": "Korvite", "symbol": "K",
					"grade": "B", "mass_low": 8, "mass_high": 16},
		],
	}


## UNCERTAIN MUST NOT LOOK LIKE A WARNING (Maren's ruling, ASSA-7). It is half of all designs at
## grade B and it is the advertisement for assaying; if it reads as danger, players stop building and
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


## THE VERDICT IS THE HEADLINE, so it must not also be buried in the small print: it is its own
## label in its own colour, and a second copy in grey would undo that.
func test_the_verdict_word_is_not_repeated_in_the_small_print() -> bool:
	for line in AssayHud.design_lines(_design()):
		if String(line).contains("UNCERTAIN"):
			return _fail("the verdict is repeated in the body text: %s" % line)
	return true


## UNCERTAIN MUST NAME WHAT RESOLVES IT. "assay something" is not an action; "assay Korvite to know"
## is, and it is the only advertisement assaying gets.
func test_an_uncertain_design_names_the_material_to_assay() -> bool:
	var found := false
	for line in AssayHud.design_lines(_design()):
		if String(line).contains("assay Korvite"):
			found = true
	if not found:
		return _fail("no line names the rough species: %s" % AssayHud.design_lines(_design()))
	var known := _design()
	known["unassayed"] = PackedStringArray()
	for line in AssayHud.design_lines(known):
		if String(line).begins_with("assay "):
			return _fail("a design with nothing rough still advises an assay: %s" % line)
	return true


## DURABILITY IS HELD-ONLY (Maren's ruling, ASSA-5). The binding leaves the key out on a planted
## design, and the panel must not print the word anyway.
func test_a_planted_design_shows_no_durability_at_all() -> bool:
	var planted := _design()
	planted.erase("durability")
	planted["mount"] = "planted"
	planted["in_hand"] = false
	for line in AssayHud.design_lines(planted):
		if String(line).contains("durability"):
			return _fail("a planted design printed a durability line: %s" % line)
	var held_lines := "\n".join(AssayHud.design_lines(_design()))
	if not held_lines.contains("durability 100% of 2400-3600"):
		return _fail("a held design must show its pool, got %s" % held_lines)
	return true


## A PART ROW CARRIES KIND, SPECIES, GRADE AND MASS. Nothing else -- every other sheet property
## belongs to the assay panel, and over-showing is how this becomes a spreadsheet. The species comes
## as letter AND name: the name is the row's own non-colour read, and the letter is the only place a
## player learns which glyph on the map that name stands for (Maren's ruling, Decision #36).
func test_a_part_row_carries_four_things_and_the_rows_sum_to_the_headline() -> bool:
	var lines := AssayHud.design_lines(_design())
	var rows := PackedStringArray()
	for line in lines:
		if String(line).begins_with("  "):
			rows.append(String(line))
	if rows.size() != 2:
		return _fail("two parts must give two rows, got %s" % [rows])
	if rows[0] != "  frame · K Korvite B · mass 18-34":
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
func test_an_empty_bench_says_so_rather_than_showing_nothing() -> bool:
	if not AssayHud.no_designs_line().contains("nothing built"):
		return _fail("got %s" % AssayHud.no_designs_line())
	return true
