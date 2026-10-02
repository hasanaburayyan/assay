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
func test_purity_is_brightness_and_never_touches_hue() -> bool:
	var last_value := -1.0
	var hue := AssayHud.deposit_color(2, 6, 1).h
	for purity in [1, 20, 40, 60, 80, 100]:
		var colour := AssayHud.deposit_color(2, 6, purity)
		if absf(colour.h - hue) > 0.001:
			return _fail(("purity %d moved the hue to %f, from %f. Purity may only move brightness; "
					+ "hue is species.") % [purity, colour.h, hue])
		if colour.v <= last_value:
			return _fail("purity %d is no brighter than the purity below it (%f after %f)"
					% [purity, colour.v, last_value])
		if colour.s < 0.4:
			return _fail(("saturation fell to %f at purity %d. A washed-out patch is the hardest "
					+ "thing on the map to see; that was the bug.") % [colour.s, purity])
		last_value = colour.v
	# A grade-A patch of any species is the brightest thing on screen -- the game is named after it.
	if AssayHud.deposit_color(0, 6, 100).v <= AssayHud.deposit_color(5, 6, 39).v:
		return _fail("a pure patch is not brighter than an impure one of another species")
	return true


## Six species land far enough apart to be told apart. Maren's bar for body hue is 30 degrees; evenly
## spaced sixths are 60 apart, and this fails if anyone crowds them.
func test_every_species_gets_its_own_hue() -> bool:
	var hues := []
	for species in range(6):
		hues.append(AssayHud.deposit_color(species, 6, 50).h * 360.0)
	for i in range(hues.size()):
		for j in range(i + 1, hues.size()):
			var apart: float = absf(hues[i] - hues[j])
			apart = minf(apart, 360.0 - apart)
			if apart < 30.0:
				return _fail("species %d and %d are %f degrees apart, under the 30 degree bar"
						% [i, j, apart])
	# One species, or a species id past the end of the roster, must still produce a colour rather than
	# divide by zero: a client may draw a frame before it has counted the roster.
	if AssayHud.deposit_color(9, 0, 50).v <= 0.0:
		return _fail("a species count of 0 produced no colour")
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
