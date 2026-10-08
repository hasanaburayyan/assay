extends RefCounted
## **A MARK CANNOT BE PUT ON THE WHOLE-WORLD MAP WITHOUT A ROW IN ITS KEY** (ASSA-206, Maren's
## constraint: "the key must be GENERATED from the same table the draw loop reads").
##
## **THE SET IS READ OFF THE PAINTER, NEVER WRITTEN DOWN HERE**, and the item itself is the evidence
## that a written one rots: ASSA-206's body lists nine marks, counted off `main.gd::_draw` on purpose
## by the director, and within the day it named a hollow circle ASSA-199 had already replaced with a
## hatch and stopped two marks short of the end of the function. A test with its own list of marks
## would be a third copy of the painter and would pass while the key was wrong.
##
## SO THE CHECK IS A PARSE OF `_draw`'s OWN SOURCE: every `draw_*` call in it, paren-matched, must
## name an entry of `AssayHud.MAP_MARKS` through `mark_ink` or `mark_ink_of`, and every entry of that
## table must be named by a call. Both directions, because each catches a different mistake: one
## catches a mark nobody keyed, the other catches a key row nothing draws.
##
## WHY A SOURCE SCAN AND NOT A RECORDING CANVAS. Nothing in a headless suite can read a
## `draw_colored_polygon` back off a canvas and `--headless` has no frame to photograph -- which is
## how this view went a month with no factories on it at all (ASSA-189). The scan's own weakness is
## that it cannot see a mark drawn from somewhere other than `_draw`; the painter has one entry point
## today (`_building_marks` computes, `_draw` paints) and `test_main_screen.gd` holds that line.
##
## THE COMMENTS ARE STRIPPED BEFORE THE RAW-COLOUR RULE RUNS, because `_draw`'s comments quote the
## very constants the rule forbids ("they are `MAP_BG` drawn on a `MAP_BG` background") -- and a check
## that read prose would be measuring prose, which nothing in this repo tests.

const MAIN := "res://scripts/main.gd"
const KEY_PANEL := "res://scripts/map_key.gd"
## Below this, the scan is broken rather than the painter: a test whose set is empty passes for the
## absence of its own data. Fifteen marks today.
const FEWEST_MARKS := 12
const FEWEST_CALLS := 12
## Every colour name a draw call in `_draw` must no longer reach for directly.
const RAW_INKS := ["AssayHud.MAP_BG", "AssayHud.MINE", "AssayHud.THEIRS", "AssayHud.HOVER",
		"AssayHud.SPAWN_PAD", "AssayHud.GLYPH_DARK", "AssayHud.GLYPH_LIGHT", "Color(", "Color."]

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


func _source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


## The body of a named function, comments and all.
func _body(source: String, signature: String) -> String:
	var kept := PackedStringArray()
	var inside := false
	for raw in source.split("\n"):
		var line := String(raw)
		if line.begins_with(signature):
			inside = true
			continue
		if inside and line.begins_with("func "):
			break
		if inside:
			kept.append(line)
	return "\n".join(kept)


## The same body with every comment gone. A line that is only a comment goes; a trailing comment is
## cut at the `#` unless the line carries a quote, which in this tree means a hex colour or a
## sentence and never a comment to cut.
func _code_only(body: String) -> String:
	var kept := PackedStringArray()
	for raw in body.split("\n"):
		var line := String(raw)
		if line.strip_edges().begins_with("#"):
			continue
		var hash := line.find("#")
		if hash >= 0 and not line.contains("\""):
			line = line.substr(0, hash)
		kept.append(line)
	return "\n".join(kept)


## Every `draw_*(...)` call in this code, as text, with its parentheses matched so a call spread over
## three lines is one entry and a nested call does not end it early.
func _draw_calls(code: String) -> PackedStringArray:
	var calls := PackedStringArray()
	var finder := RegEx.new()
	finder.compile("draw_[a-z_]+\\(")
	for found in finder.search_all(code):
		var at := found.get_end() - 1
		var depth := 0
		var quoted := false
		var cursor := at
		while cursor < code.length():
			var ch := code[cursor]
			if ch == "\"":
				quoted = not quoted
			elif not quoted and ch == "(":
				depth += 1
			elif not quoted and ch == ")":
				depth -= 1
				if depth == 0:
					break
			cursor += 1
		calls.append(code.substr(found.get_start(), cursor - found.get_start() + 1))
	return calls


## The mark ids a call text names, in order.
func _ids_in(call: String) -> PackedStringArray:
	var ids := PackedStringArray()
	var finder := RegEx.new()
	finder.compile("&\"([a-z_]+)\"")
	for found in finder.search_all(call):
		ids.append(found.get_string(1))
	return ids


func _table_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for entry in AssayHud.MAP_MARKS:
		ids.append(String(entry["id"]))
	return ids


## EVERY MARK `_draw` PAINTS NAMES A ROW OF THE TABLE, and every row is painted.
func test_every_draw_call_names_a_mark_in_the_table_and_every_mark_is_drawn() -> bool:
	var code := _code_only(_body(_source(MAIN), "func _draw() -> void:"))
	if code.is_empty():
		return _fail("could not find main.gd::_draw to read")
	var calls := _draw_calls(code)
	if calls.size() < FEWEST_CALLS:
		return _fail("found only %d draw calls in _draw: the scan is broken, not the painter"
				% calls.size())
	var table := _table_ids()
	var drawn := PackedStringArray()
	for call in calls:
		if not (call.contains("mark_ink(") or call.contains("mark_ink_of(")):
			return _fail("a draw call in _draw takes no ink from AssayHud.MAP_MARKS: %s"
					% call.replace("\n", " "))
		var ids := _ids_in(call)
		if ids.is_empty():
			return _fail("a draw call in _draw names no mark id: %s" % call.replace("\n", " "))
		for id in ids:
			if not table.has(id):
				return _fail("_draw paints a mark '%s' that AssayHud.MAP_MARKS does not carry" % id)
			if not drawn.has(id):
				drawn.append(id)
	for id in table:
		if not drawn.has(id):
			return _fail("AssayHud.MAP_MARKS carries '%s' and _draw never paints it" % id)
	return true


## NO DRAW CALL REACHES PAST THE TABLE FOR A COLOUR. This is the rule that makes the check above
## impossible to walk round: without it, a new mark could be painted in `AssayHud.HOVER` directly and
## the scan above would never see an id to miss.
func test_no_colour_in_draw_comes_from_anywhere_but_the_table() -> bool:
	var code := _code_only(_body(_source(MAIN), "func _draw() -> void:"))
	if code.is_empty():
		return _fail("could not find main.gd::_draw to read")
	for ink in RAW_INKS:
		if code.contains(ink):
			return _fail("_draw still reaches for %s directly: every ink goes through mark_ink" % ink)
	return true


## THE TABLE IS WHOLE: ids are unique, every entry carries what the key and the painter read, and
## every entry is either a row of the key or points at the row that speaks for it.
func test_the_table_is_whole_and_every_entry_is_keyed_or_points_at_a_row() -> bool:
	var marks := AssayHud.MAP_MARKS
	if marks.size() < FEWEST_MARKS:
		return _fail("AssayHud.MAP_MARKS has only %d entries" % marks.size())
	var seen := PackedStringArray()
	for entry in marks:
		for field in ["id", "shape", "ink", "label", "in_key"]:
			if not entry.has(field):
				return _fail("a map mark entry has no '%s': %s" % [field, entry])
		var id := String(entry["id"])
		if seen.has(id):
			return _fail("two map marks share the id '%s'" % id)
		seen.append(id)
		if String(entry["label"]).strip_edges().is_empty():
			return _fail("map mark '%s' has no label" % id)
		if bool(entry["in_key"]):
			continue
		if not entry.has("keyed_by"):
			if id == "ground":
				continue
			return _fail("map mark '%s' is not in the key and names no row that speaks for it" % id)
		var speaks_for := AssayHud.mark_entry(StringName(entry["keyed_by"]))
		if speaks_for.is_empty() or not bool(speaks_for.get("in_key", false)):
			return _fail("map mark '%s' is keyed by '%s', which is not a row of the key"
					% [id, entry["keyed_by"]])
	return true


## THE KEY'S ROWS ARE THE TABLE'S, IN THE TABLE'S ORDER. A sort or a second list here is the defect
## this item is about, one level up.
func test_the_key_rows_are_the_tables_own_rows_in_order() -> bool:
	var rows := AssayHud.map_key_rows()
	var wanted := PackedStringArray()
	for entry in AssayHud.MAP_MARKS:
		if bool(entry.get("in_key", false)):
			wanted.append(String(entry["id"]))
	var got := PackedStringArray()
	for row in rows:
		got.append(String(row["id"]))
	if got != wanted:
		return _fail("map_key_rows() gave %s, the table says %s" % [got, wanted])
	if rows.size() < 8:
		return _fail("only %d rows in the key" % rows.size())
	return true


## THE PANEL DRAWS FROM THE TABLE AND HOLDS NO LIST OF ITS OWN: no row's label appears as a literal
## in the panel's source, and the rows come from `map_key_rows()`.
func test_the_panel_holds_no_list_of_its_own() -> bool:
	var source := _source(KEY_PANEL)
	if source.is_empty():
		return _fail("could not read scripts/map_key.gd")
	if not source.contains("AssayHud.map_key_rows()"):
		return _fail("the key panel does not read AssayHud.map_key_rows()")
	for entry in AssayHud.MAP_MARKS:
		# QUOTED, because a label is English: "you" appears in this file's own prose and a bare
		# `contains` would make every sentence a finding. A hand-written list would be literals.
		if source.contains("\"%s\"" % entry["label"]):
			return _fail("the key panel has '%s' written in it: a row it could stop reading"
					% entry["label"])
	return true


## EVERY SHAPE THE TABLE NAMES IS A SHAPE THE PANEL CAN DRAW. A mark whose shape has no branch draws
## nothing in the key -- a row that is there and says nothing, which is worse than a missing row.
func test_the_panel_can_draw_every_shape_the_table_names() -> bool:
	var source := _source(KEY_PANEL)
	if source.is_empty():
		return _fail("could not read scripts/map_key.gd")
	var painter := _body(source, "func _paint_sample(")
	if painter.is_empty():
		return _fail("could not find the key panel's sample painter")
	for entry in AssayHud.MAP_MARKS:
		var shape := String(entry["shape"])
		if not painter.contains("&\"%s\"" % shape):
			return _fail("the key cannot draw shape '%s', which mark '%s' is"
					% [shape, entry["id"]])
	return true


## AN UNKNOWN MARK IS MAGENTA, NOT A DEFAULT. `MAP_BG` would hide the mark on the map's own ground --
## the one wrong answer that looks like nothing happened.
func test_an_unknown_mark_is_refused_in_a_colour_this_game_does_not_own() -> bool:
	if AssayHud.mark_ink(&"no_such_mark") != Color.MAGENTA:
		return _fail("an unknown mark id did not come back magenta")
	if AssayHud.mark_ink_of(&"no_such_mark", AssayHud.MINE) != Color.MAGENTA:
		return _fail("an unknown mark id did not come back magenta from mark_ink_of")
	if not AssayHud.mark_entry(&"no_such_mark").is_empty():
		return _fail("mark_entry invented an entry")
	return true


## THE WEIGHTS LIVE IN THE TABLE, which is what lets the key draw a walk line at the weight the map
## draws it. `_draw` used to build `Color(colour.r, colour.g, colour.b, 0.35)` at the call.
func test_the_table_carries_the_weight_a_mark_is_drawn_at() -> bool:
	if not is_equal_approx(AssayHud.mark_ink(&"walk_mine").a, 0.35):
		return _fail("the walk line's own weight is not in the table")
	if not is_equal_approx(AssayHud.mark_ink(&"walk_theirs").a, 0.25):
		return _fail("a partner's walk line lost its weight")
	if not is_equal_approx(AssayHud.mark_ink(&"hover_tile").a, 0.55):
		return _fail("the hover outline's weight is not in the table")
	if not is_equal_approx(AssayHud.mark_ink(&"player_mine").a, 1.0):
		return _fail("a player mark came back translucent")
	var given := AssayHud.mark_ink_of(&"walk_theirs", AssayHud.MINE)
	if not (is_equal_approx(given.r, AssayHud.MINE.r) and is_equal_approx(given.a, 0.25)):
		return _fail("mark_ink_of changed the colour it was given or dropped the table's weight")
	return true


## **A KEYED MARK IN A FIXED INK CLEARS THE MARK FLOOR AGAINST THE GROUND IT STANDS ON** (ASSA-283).
##
## `in_key: true` is a promise that the thing is on the map; a keyed row nobody can see is the key
## lying, and a cold reader found exactly that -- the spawn pad at **2.23:1**, filed under "things I
## would mistake for something else". Nothing in the suite read that colour: this file checked only
## that the row's ink comes from the table rather than from a literal, which a 1.0:1 row would pass.
##
## 3:1 is the floor for a non-text mark (Maren, §11.9: a 9x9 mark is a mark, and contrast floors are
## for marks and text, never for regions). The ink is composited on `MAP_BG` the way `glyph_color`
## does it, so a row's WEIGHT counts -- a 25% line is not its colour.
##
## **TWO KINDS OF ROW ARE OUT, BOTH BY NAME SO THAT TURNING THEM ON IS DELETING A WORD.** `data_ink`
## rows have no fixed colour to check (a disc's ink is its species and purity; `species_probe.py`
## owns that surface). And `walk_mine` is **2.62:1 today and it is ASSA-274's**, Maren's own item,
## which keeps the walk lines and the terminus while this one owns the pad -- so it is excluded here
## rather than fixed here, and the guard comes on for it the moment 274 lands.
const FLOOR_EXEMPT := [&"walk_mine"]
const MARK_FLOOR := 3.0


func test_a_keyed_mark_in_a_fixed_ink_clears_the_mark_floor() -> bool:
	var checked := 0
	for row: Dictionary in AssayHud.MAP_MARKS:
		if not row.get("in_key", false) or row.get("data_ink", false):
			continue
		if row["id"] in FLOOR_EXEMPT:
			continue
		var ink: Color = AssayHud.mark_ink(row["id"])
		var on_ground := AssayHud.MAP_BG.lerp(Color(ink.r, ink.g, ink.b), ink.a)
		var ratio := AssayHud.contrast_ratio(on_ground, AssayHud.MAP_BG)
		if ratio < MARK_FLOOR:
			return _fail("the key promises `%s` and it is %.3f:1 on MAP_BG, under the %.1f floor"
					% [row["id"], ratio, MARK_FLOOR])
		checked += 1
	# A test whose set came back empty passes for the absence of its own data: five rows qualify
	# today (spawn, player_mine, player_theirs, mine_ring, target, hover_tile).
	if checked < 5:
		return _fail("only %d keyed fixed-ink rows found, so this checked almost nothing" % checked)
	return true


## **THE SPAWN PAD IS THE TILE IT NAMES AND NEVER BIGGER THAN A PERSON** (box 7, Maren's ruling).
func test_the_spawn_pad_is_one_tile_and_never_larger_than_the_player_mark() -> bool:
	var at := Vector2i(48, 32)
	var pad := AssayHud.spawn_pad_rect(at, 9.0, AssayHud.MARGIN)
	if not (is_equal_approx(pad.size.x, 9.0) and is_equal_approx(pad.size.y, 9.0)):
		return _fail("on the test world's 9px tile the pad is %s, not the tile" % pad.size)
	var middle := AssayHud.MARGIN + (Vector2(at) + Vector2(0.5, 0.5)) * 9.0
	if pad.get_center().distance_to(middle) > 0.01:
		return _fail("the pad is not centred on the tile it names")
	# A fatter tile is where the old `cell * 4` rule did the most damage, and where the clamp is the
	# whole rule: 18px tiles would give a one-tile pad bigger than the 16px body standing on it.
	var fat := AssayHud.spawn_pad_rect(at, 18.0, AssayHud.MARGIN)
	if fat.size.x > AssayHud.PLAYER_MARK_PX or fat.size.y > AssayHud.PLAYER_MARK_PX:
		return _fail("on an 18px tile the pad is %s, larger than a person" % fat.size)
	if fat.size.x < AssayHud.PLAYER_MARK_PX:
		return _fail("the clamp took more than it had to: %s" % fat.size)
	return true


## THE PANEL ASKS FOR THE ROOM ITS ROWS NEED, derived from the font and the table rather than written
## down. The runner has no layout at all, so this is the only honest place to hold that number.
func test_the_panel_asks_for_room_for_the_rows_the_table_has() -> bool:
	var rows := AssayHud.map_key_rows()
	var font := ThemeDB.fallback_font
	var wants := AssayMapKey.wants(font, 13, rows)
	var tall := AssayMapKey.PAD * 2.0 + AssayMapKey.PITCH * float(rows.size())
	if not is_equal_approx(wants.y, tall):
		return _fail("the panel wants %s tall for %d rows, not %s" % [wants.y, rows.size(), tall])
	if wants.x <= AssayMapKey.SAMPLE.x:
		return _fail("the panel asked for no room for its labels: %s" % wants.x)
	var fewer: Array[Dictionary] = [rows[0]]
	if AssayMapKey.wants(font, 13, fewer).y >= wants.y:
		return _fail("the panel's height does not follow its row count")
	# IT FITS THE MAP, which is the bound a font change could move: the log's own tool fails a run if
	# its box leaves the map's rect, and this panel is under it on the same surface.
	var world := AssayHud.world_rect()
	if wants.x > world.size.x or wants.y > world.size.y:
		return _fail("the key wants %s and the map is %s" % [wants, world.size])
	return true


## THE TOGGLE NAMES ITS KEY, which is the half of a keyboard shortcut a stranger cannot discover
## (ASSA-88/89, and the pattern every other toggle on this screen follows).
func test_the_toggle_names_the_key_and_says_which_way_it_goes() -> bool:
	var shown := AssayHud.map_key_toggle_text(true)
	var hidden := AssayHud.map_key_toggle_text(false)
	if not (shown.contains("(K)") and hidden.contains("(K)")):
		return _fail("the key's toggle does not name its key: '%s' / '%s'" % [shown, hidden])
	if not (shown.begins_with("hide") and hidden.begins_with("show")):
		return _fail("the toggle does not say what pressing it will do: '%s' / '%s'" % [shown, hidden])
	return true


## **EVERY SWATCH IS VISIBLE AGAINST THE PATCH IT IS DRAWN ON, which the key did not manage for the
## one row it exists to contrast** (Nerite, ASSA-206 01:02 EDT: *"a flat dark square with no stripe --
## the key names a mark it does not draw"*). `map_key_sample_ink` returned `MAP_BG` for `dead_end`;
## `_draw` paints each row's sample on a patch of `ground`, which IS `MAP_BG`; and the hatch branch
## then painted its disc in the sample ink and its strokes in the row's ink. **Three layers of one
## near-black: 1.00:1, exactly nothing**, for 1 of the 11 rows and the one whose whole job is to be
## the other half of the row above it.
##
## THE FLOOR IS 1.5:1 AND IT IS DELIBERATELY LOW. Maren ruled the spawn pad's SIZE rather than its
## colour and it sits at 2.23:1 against the ground, and the panel's own docstring says a key that
## flattered a mark would be worse than none. So this is not a readability bar -- it is "did anything
## get drawn", which is the defect that actually happened, and it must not become a back door to
## re-rule a colour the director has already looked at.
func test_no_key_swatch_is_invisible_on_the_patch_it_is_drawn_on() -> bool:
	var ground := AssayHud.mark_ink(&"ground")
	var floor_ratio := 1.5
	var checked := 0
	for row in AssayHud.map_key_rows():
		var id := StringName(row["id"])
		var ink := AssayHud.map_key_sample_ink(row)
		# **WHAT A ROW PUTS ON THE GROUND IS NOT ALWAYS ITS `ink`, AND GETTING THAT WRONG MADE THIS
		# TEST ACCUSE AN INNOCENT ROW.** My first version compared `ink` for every shape and failed
		# `species_glyph` at 1.19:1 -- but that branch paints a species-tinted DISC first and the
		# letter on top, so 1.19:1 was the letter against the ground it is never drawn on. Both
		# shapes that sit a mark on a disc are listed here, read off `map_key.gd`'s own branches.
		var shape := StringName(row["shape"])
		var body: Color = AssayHud.species_tint(AssayHud.KEY_SAMPLE_SPECIES) \
				if shape == &"hatch" or shape == &"glyph" else ink
		var against_ground := AssayHud.contrast_ratio(body, ground)
		if against_ground < floor_ratio:
			return _fail(("the key's `%s` swatch is %.2f:1 against the ground patch it is drawn on "
					+ "(floor %.2f). A row that draws nothing is a row that names a mark the panel "
					+ "does not draw, which is worse than leaving it out.")
					% [id, against_ground, floor_ratio])
		checked += 1
	if checked < 10:
		return _fail("only %d key rows were checked; the scan is broken, not the panel" % checked)
	# AND THE HATCH'S OWN STROKE AGAINST ITS OWN DISC, at the floor the MAP is held to (ASSA-209).
	# The swatch promises the shape, so the shape has to be there: a stripe the same colour as the
	# disc under it is the map's 1.42:1 defect reproduced inside the legend.
	# **THE STRIPE'S COLOUR COMES BACK THROUGH `map_key_sample_ink`, WHICH IS THE PATH `map_key.gd`
	# ACTUALLY TAKES, and asking `hatch_ink` here instead was a hole my own lever found.** Deleting the
	# `dead_end` branch from `map_key_sample_ink` -- the whole of Nerite's defect -- left all 326 tests
	# green, because this line computed the right number about a function the panel does not call.
	var sample := AssayHud.species_tint(AssayHud.KEY_SAMPLE_SPECIES)
	var hatch_row := AssayHud.mark_entry(&"dead_end")
	if hatch_row.is_empty():
		return _fail("there is no `dead_end` mark to key: this test is measuring nothing")
	var stripe := AssayHud.map_key_sample_ink(hatch_row)
	var on_disc := AssayHud.contrast_ratio(stripe, sample)
	if on_disc < 3.0:
		return _fail(("the key's hatch stripe is %.2f:1 against its own disc (floor 3.00). The map's "
				+ "worst pair clears 4.13:1 since ASSA-209; a legend quieter than the thing it "
				+ "describes teaches the wrong mark.") % [on_disc])
	print("    key swatches: %d rows all visible on the ground; hatch stripe %.2f:1 on its own disc"
			% [checked, on_disc])
	return true


## **THE HATCH SWATCH'S DISC IS NOT PAINTED IN THE ROW'S OWN INK, AND THIS IS A SOURCE SCAN -- SAID
## SO, BECAUSE THE ARITHMETIC ABOVE CANNOT REACH IT.**
##
## Nerite's defect was `draw_circle(middle, radius, colour)` in the `hatch` branch, where `colour` is
## `map_key_sample_ink(row)` -- so the disc, its stripes and the `ground` patch under both were three
## layers of one near-black. **My contrast test cannot catch it and I only know that because a mutation
## passed.** `KEY_SAMPLE_SPECIES` is slot 5, chosen on Maren's sweep precisely because it is BRIGHT, so
## `MAP_BG` against it measures ~5.8:1 and clears any floor worth setting. The number was never the
## problem; what was drawn was. A ratio can only see this once the disc has a colour of its own.
##
## So the assertion is structural, and it is the narrowest one that holds: the branch fills its disc
## from `species_tint`, the way the `deposit` row above it does, and not from the row's ink.
func test_the_hatch_swatch_fills_its_disc_with_a_tint_not_with_the_rows_ink() -> bool:
	var text := FileAccess.get_file_as_string(KEY_PANEL)
	if text.is_empty():
		return _fail("could not read %s" % KEY_PANEL)
	var at := text.find("&\"hatch\":")
	if at < 0:
		return _fail("%s has no `hatch` branch; the key cannot draw the dead-end row at all"
				% KEY_PANEL)
	var next := text.find("&\"glyph\":", at)
	var branch := text.substr(at, (next - at) if next > at else -1)
	if not branch.contains("AssayHud.species_tint("):
		return _fail(("the key's `hatch` branch does not fill its disc from `species_tint`. If it is "
				+ "back to `colour`, the disc, the stripes and the ground patch are all one "
				+ "near-black and the row draws NOTHING -- Nerite, ASSA-206: `a flat dark square "
				+ "with no stripe; the key names a mark it does not draw`."))
	if branch.contains("draw_circle(middle, radius, colour)"):
		return _fail(("the key's `hatch` branch still paints its disc in the row's own ink. That ink "
				+ "is what the STRIPES are drawn in, so the mark is painted on itself."))
	# AND THE WIDTH, the ASSA-206 density debt: `HATCH_ON` is a count of steps in the `x + y` index,
	# and used as a pixel width it draws 40% ink where 28.6% was ruled.
	if not branch.contains("float(AssayHud.HATCH_ON) / sqrt(2.0)"):
		return _fail(("the key's hatch stroke is not `HATCH_ON / sqrt(2)` wide. `HATCH_ON` as a raw "
				+ "pixel width is a 2px PERPENDICULAR stroke at 4.95px spacing = 40% ink, half again "
				+ "the 28.6% Maren ruled; the swatch measured 39.8% against the map's own 2/7."))
	return true


## **THE TABLE'S ORDER IS THE ORDER `_draw` PAINTS IN, AND UNTIL ASSA-213 NOTHING HELD IT THERE.**
##
## `MAP_MARKS`' own docstring already claims this -- "the order a player reads the key in is the order
## `_draw` paints in, so the key reads bottom-of-the-stack first, which is also the order the marks
## cover each other in" -- and the two tests above only check membership, both ways. So the table
## could say the letter goes on last while the painter put it on fourth, which is exactly the state
## ASSA-213 was filed against: a 16px building diamond painting out a 25px species letter, with every
## assertion in this file green.
##
## **WHAT THIS BUYS THAT A SOURCE SCAN FOR TWO CALLS DOES NOT.** The key panel is generated from this
## list, so a mark's row and a mark's paint order are now one fact. Moving a draw call without moving
## its row -- or the other way round -- reddens here, whichever direction the mistake goes, for every
## pair of marks rather than the pair somebody remembered to write a test about.
##
## FIRST APPEARANCE, because one call can name two marks (`&"player_mine" if mine else
## &"player_theirs"`) and a mark can be painted in more than one call.
func test_the_tables_order_is_the_order_draw_paints_in() -> bool:
	var code := _code_only(_body(_source(MAIN), "func _draw() -> void:"))
	if code.is_empty():
		return _fail("could not find main.gd::_draw to read")
	var painted := PackedStringArray()
	for call in _draw_calls(code):
		for id in _ids_in(call):
			if not painted.has(id):
				painted.append(id)
	var table := _table_ids()
	if painted.size() != table.size():
		return _fail(("_draw paints %d of the table's %d marks: %s. The membership tests above say "
				+ "which; this one cannot speak until they agree") % [painted.size(), table.size(),
				painted])
	for i in range(painted.size()):
		if painted[i] == table[i]:
			continue
		return _fail(("the %dth mark `_draw` paints is '%s' and the %dth row of AssayHud.MAP_MARKS "
				+ "is '%s'. The table IS the paint order -- the key is generated from it bottom of "
				+ "the stack first -- so one of the two moved without the other: painted %s, table "
				+ "%s") % [i + 1, painted[i], i + 1, table[i], painted, table])
	return true
