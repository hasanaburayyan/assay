extends RefCounted
## THE ROCKS PANEL, WHICH IS THE MAP'S LEGEND (ASSA-73).
##
## The sim has always handed this client every species. Nothing drew them, so a window player could
## read "assayed: its sheet is exact" on a tile and never see the numbers that became exact, and
## could never find out which rock lights a fire from cold -- the one fact that unblocks their first
## smelter. The terminal has `species`; the window had nothing.
##
## WHAT THESE TESTS ARE CAREFUL ABOUT. Maren's ruling is that the panel is only a legend if it wears
## the mark the MAP draws. So the glyph test does not compare the row against a letter typed in here
## -- it compares the row against what a DEPOSIT of the same species carries, which is what the map
## paints. Two surfaces against each other, not either one against my opinion.

const PATIENCE := 160

var runner = null
var _asked: Array = []


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## A live screen welcomed into a fresh offline world, the same way `test_buttons.gd` does it:
## `AssaySimHost.fresh_welcome_json` writes the `Welcome` a relay would, and this script is the
## clock. `_ready` by hand because the suite runs inside `SceneTree._initialize`.
func _joined(seed_text := "14247") -> Node:
	_asked = []
	var screen: Node = load("res://scenes/main.tscn").instantiate()
	runner.root_node.add_child(screen)
	screen._ready()
	screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	var welcome := AssaySimHost.fresh_welcome_json(seed_text, "limpet")
	if welcome == "":
		return screen
	screen._client.play_offline()
	screen._client.feed_offline(welcome)
	return screen


func _tick(screen: Node, count := 1) -> void:
	for _i in range(count):
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": screen._client.player_id, "command": command}})
		_asked.clear()
		var at: int = screen._sim.tick()
		screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))


## The rows of the rocks panel, in the order the panel built them.
func _rows(screen: Node) -> Array:
	var out := []
	for child in screen._species.get_children():
		if child.find_child(screen.SPECIES_LINE, true, false) != null:
			out.append(child)
	return out


func _title_of(screen: Node, row: Node) -> String:
	var label := row.find_child(screen.SPECIES_LINE, true, false) as Label
	return "" if label == null else label.text


## The row's glyph: the letter and the colour of the disc behind it, read off the nodes the panel
## really built rather than recomputed.
func _glyph_of(row: Node) -> Dictionary:
	for child in row.get_children():
		for grand in child.get_children():
			if grand is Panel:
				var style := (grand as Panel).get_theme_stylebox("panel") as StyleBoxFlat
				var letter := ""
				for inner in grand.get_children():
					if inner is Label:
						letter = (inner as Label).text
				return {"letter": letter,
						"disc": Color.TRANSPARENT if style == null else style.bg_color}
	return {}


func _all_text(node: Node) -> String:
	var out := PackedStringArray()
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		out.append(_all_text(child))
	return " · ".join(out)


## EVERY SPECIES THE SIM SENDS IS ON THE PANEL, IN THE SIM'S OWN ORDER.
##
## Six rows is the whole surface (ruling 4): no sorting, no "best fuel" marker, no recommendation.
## Ranking the roster is the player's job and this panel is how they do it, so the order has to be
## the one the sim handed over -- a client that sorted would be quietly recommending.
func test_every_species_is_listed_in_the_sims_own_order() -> bool:
	var screen := _joined()
	var ok := true
	var sheets: Array = screen._sim.species_sheets()
	if sheets.is_empty():
		ok = _fail("the sim sent no species at all, so this world has nothing to legend")
	else:
		var rows := _rows(screen)
		if rows.size() != sheets.size():
			ok = _fail("the sim sent %d species and the panel drew %d rows"
					% [sheets.size(), rows.size()])
		else:
			for i in range(sheets.size()):
				var want := String((sheets[i] as Dictionary).get("name", "?"))
				if not _title_of(screen, rows[i]).begins_with(want):
					ok = _fail(("row %d reads `%s` where the sim's %dth species is `%s`. The panel "
							+ "must not reorder: that would be a recommendation.")
							% [i, _title_of(screen, rows[i]), i, want])
					break
	screen.queue_free()
	return ok


## THE ROW WEARS THE MARK THE MAP DRAWS, which is the whole reason this panel is worth having.
##
## MEASURED SURFACE AGAINST SURFACE. The letter on a row is compared to the `symbol` a DEPOSIT of
## that species carries -- the value the map paints on its discs -- not to a character written here.
## The disc colour is compared to `AssayHud.species_tint`, the one lookup `deposit_color` also uses;
## a second copy of that table is exactly what Maren's ruling forbids, and a test holding its own
## third copy would be the same mistake wearing a lab coat.
func test_a_row_wears_the_glyph_and_tint_its_deposits_wear() -> bool:
	var screen := _joined()
	var ok := true
	var letters := {}
	for entry in screen._sim.deposits():
		var deposit: Dictionary = entry
		letters[int(deposit.get("species", -1))] = String(deposit.get("symbol", ""))
	if letters.is_empty():
		ok = _fail("no deposits in this world, so there is no map letter to compare against")
	else:
		var sheets: Array = screen._sim.species_sheets()
		var rows := _rows(screen)
		var compared := 0
		for i in range(mini(rows.size(), sheets.size())):
			var species: Dictionary = sheets[i]
			var id := int(species.get("id", -1))
			var glyph := _glyph_of(rows[i])
			if glyph.is_empty():
				ok = _fail("row %d has no glyph disc at all" % i)
				break
			var want_disc := AssayHud.species_tint(id)
			if Color(glyph.get("disc", Color.TRANSPARENT)) != want_disc:
				ok = _fail(("species %d's row disc is %s and the map's tint for it is %s")
						% [id, glyph.get("disc"), want_disc])
				break
			if not letters.has(id):
				continue
			compared += 1
			if String(glyph.get("letter", "")) != String(letters[id]):
				ok = _fail(("species %d draws `%s` on the map and `%s` in the panel. A legend whose "
						+ "key does not match its map is worse than no legend.")
						% [id, letters[id], glyph.get("letter", "")])
				break
		if ok and compared == 0:
			ok = _fail("not one species had both a row and a deposit, so nothing was compared")
	screen.queue_free()
	return ok


## THE SHEET SHARPENS WHEN YOU ASSAY, WHICH IS THE PAYOFF THE TILE LINE HAS BEEN PROMISING.
##
## Until now "assayed: its sheet is exact" named numbers the player could not see anywhere. This
## presses the `do` section's own Assay button on a real deposit and requires the row for THAT
## species to stop reading as bands.
##
## BANDS AND NUMBERS ARE TOLD APART BY THE SIM'S OWN SPELLING: a band carries a hyphen ("26-50"),
## an exact reading does not. The client never parses either, so the test does not either -- it
## checks the shape of the strings the sim sent.
func test_the_panel_sharpens_from_bands_to_numbers_when_you_assay() -> bool:
	var screen := _joined()
	var ok := true
	var deposit := AssaySessionPlan.nearest_of_species(screen._sim.deposits(),
			screen._sim.starter_pair()[0], screen._my_tile(), 0)
	if deposit.is_empty():
		ok = _fail("no starter deposit to stand on")
	else:
		var species := int(deposit.get("species", -1))
		var before := _readings_for(screen, species)
		if not before.contains("-"):
			ok = _fail(("species %d already reads exact before any assay (%s), so this test could "
					+ "not show a change") % [species, before])
		else:
			var centre: Vector2i = deposit.get("center", Vector2i.ZERO)
			_click(screen, centre)
			_tick(screen, PATIENCE)
			if screen._my_tile() != centre:
				ok = _fail("walked to %s and stopped at %s" % [centre, screen._my_tile()])
			else:
				var assay := _find(screen._actions, "Assay")
				if assay == null:
					ok = _fail("no Assay button in the `do` section")
				else:
					assay.pressed.emit()
					_tick(screen, PATIENCE)
					var after := _readings_for(screen, species)
					if after.contains("-"):
						ok = _fail(("assayed species %d and its row still reads in bands: %s")
								% [species, after])
					elif after == before:
						ok = _fail("the row did not change at all: %s" % after)
					elif not _all_text(screen._species).contains("exact"):
						ok = _fail("the sheet is exact and no row says so: %s"
								% _all_text(screen._species))
	screen.queue_free()
	return ok


## THE TWO FACTS SHOW AS TAGS, NOT AS SENTENCES (ruling 1), and a tag only appears for a species the
## sim says it is true of -- the client never negates and never ranks.
func test_the_boolean_facts_show_as_tags_only_where_the_sim_says_true() -> bool:
	var screen := _joined()
	var ok := true
	var sheets: Array = screen._sim.species_sheets()
	var rows := _rows(screen)
	var seen_fuel := 0
	for i in range(mini(rows.size(), sheets.size())):
		var species: Dictionary = sheets[i]
		var text := _all_text(rows[i])
		var lights := bool(species.get("hand_lit_fuel", false))
		if lights:
			seen_fuel += 1
		if text.contains(AssayHud.TAG_HAND_LIT_FUEL) != lights:
			ok = _fail(("species %s: the sim says hand_lit_fuel=%s and the row reads `%s`")
					% [species.get("name", "?"), lights, text])
			break
		if text.contains(AssayHud.TAG_HAND_MINABLE) != bool(species.get("hand_minable", false)):
			ok = _fail(("species %s: the sim says hand_minable=%s and the row reads `%s`")
					% [species.get("name", "?"), species.get("hand_minable", false), text])
			break
		# NEVER NEGATED. "not hand-minable" would be this client ranking the roster, which ruling 4
		# refuses: a row says what a rock CAN do and the player compares six of them.
		if text.contains("not " + AssayHud.TAG_HAND_MINABLE) \
				or text.contains("no " + AssayHud.TAG_HAND_LIT_FUEL):
			ok = _fail("a row negates a fact instead of leaving the tag off: %s" % text)
			break
	if ok and seen_fuel == 0:
		ok = _fail("no species in this world lights from cold, so the tag was never exercised")
	screen.queue_free()
	return ok


## THE READINGS LINE ALONE, by name, for one species.
##
## NOT the whole row, and the first version of this read the whole row: a band is told from an exact
## number by the hyphen the sim spells it with, and `[hand-minable]` has a hyphen in it. So the test
## called a perfectly sharpened sheet "still in bands". The row is not the measurement; the readings
## label is.
func _readings_for(screen: Node, species: int) -> String:
	var sheets: Array = screen._sim.species_sheets()
	var rows := _rows(screen)
	for i in range(mini(rows.size(), sheets.size())):
		if int((sheets[i] as Dictionary).get("id", -1)) == species:
			var label := rows[i].find_child(screen.SPECIES_READINGS, true, false) as Label
			return "" if label == null else label.text
	return ""


func _click(screen: Node, tile: Vector2i) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = AssayHud.MARGIN + (Vector2(tile) + Vector2(0.5, 0.5)) * screen._cell
	screen._unhandled_input(event)


func _find(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == label:
			return child
		var found := _find(child, label)
		if found != null:
			return found
	return null


## THE CRAFT BUTTON WARNS WHAT ONLY THE TERMINAL'S TABLE WARNED (ASSA-84).
##
## ASSA-59 settled that nothing in this game consumes a gear, and the recipe table says so in a
## clause derived from `is_consumed`. That table is sim-cli only, so the window player got the
## invitation without the warning -- and at a window a BUTTON is a stronger invitation than a row,
## for an output that costs 2 refined.
##
## NOTHING HERE NAMES THE GEAR, and that is the point of the test as much as of the code. It asks the
## SIM which recipes are dead ends and then requires exactly those buttons to carry exactly that
## sentence. The day something consumes that output, the sim stops saying it, this test stops
## expecting it, and no one edits either.
func test_a_craft_button_carries_the_sims_dead_end_clause_and_only_then() -> bool:
	var screen := _joined()
	var ok := true
	var recipes: Array = AssaySimHost.recipes()
	var checked := 0
	var warned := 0
	for entry in recipes:
		var recipe: Dictionary = entry
		if not bool(recipe.get("hand", false)):
			continue
		var stack := {"kind": String(recipe.get("input", "")), "species": 1, "grade": "B",
				"count": 9, "name": "test material"}
		var verbs := AssayHud.stack_verbs(stack, recipes, [], Vector2i.ZERO, false)
		for verb in verbs:
			var descriptor: Dictionary = verb
			if String(descriptor.get("verb", "")) != "craft":
				continue
			if String(descriptor.get("label", "")) != "Craft %s" % String(recipe.get("name", "?")):
				continue
			checked += 1
			var button: Button = screen._stack_button(descriptor, stack, Vector2i.ZERO)
			if button == null:
				ok = _fail("no button for %s" % descriptor)
				break
			# RULING 1: the button exists and is pressable whatever the sim says about its output.
			if button.disabled:
				ok = _fail("`%s` is disabled; a legal action stays offered" % button.text)
				break
			var want := String(recipe.get("dead_end", ""))
			if want == "":
				if button.tooltip_text.contains("nothing uses"):
					ok = _fail(("`%s` warns `%s` while the sim says its output IS consumed")
							% [button.text, button.tooltip_text])
					break
			else:
				warned += 1
				if not button.tooltip_text.contains(want):
					ok = _fail(("`%s` should carry the sim's clause `%s` and reads `%s`")
							% [button.text, want, button.tooltip_text])
					break
		if not ok:
			break
	if ok and checked == 0:
		ok = _fail("no hand-craft buttons were built, so nothing was checked")
	elif ok and warned == 0:
		ok = _fail(("no recipe in this build is a dead end, so the warning was never exercised. "
				+ "If something now consumes every output that is good news and this test should "
				+ "be retired, not loosened."))
	screen.queue_free()
	return ok
