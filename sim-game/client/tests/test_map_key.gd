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
