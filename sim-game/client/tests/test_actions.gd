extends RefCounted
## EVERY COMMAND THIS CLIENT CAN SEND, AGAINST THE DESERIALISER THAT WILL READ IT.
##
## `AssayActions` is the only file that spells a `PlayerCommand`, and `main.gd`'s buttons and
## `tools/lockstep_probe.gd` both call it -- so this file is where ASSA-37's fifth box lives: no
## client-only command path. The check that matters is NOT that these shapes look right to me. It is
## `AssaySim.command_echo`, which runs the client's own text through serde, because the two mistakes
## this guards against are both invisible from the GDScript side:
##
##   - `{"Stop": {}}` for a unit variant. I shipped that. Serde refuses it, the relay drops it
##     without a word, and a demo world kept mining itself to death while the probe said OK.
##   - `species: 3.0` where a `u8` belongs. Godot parses `3` and `3.0` back to the same double, so a
##     test comparing parsed values passes; serde refuses the float.
##
## AND THE ECHO IS PROVED TO BE ABLE TO FAIL, below. A check whose refusals I never tested would be
## the lever that cannot fire, which is a shape of mistake I have made twice in one day.

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## A stack as `inventory_of` hands one over.
func _stack(kind: String, species: int, grade: String, count: int) -> Dictionary:
	return {"kind": kind, "species": species, "species_name": "korvite", "grade": grade,
			"count": count, "name": "%s:korvite:%s" % [kind, grade.to_lower()]}


## WHICH `PlayerCommand` SERDE READ THIS AS, or "" if it refused it.
##
## Externally tagged, so a variant with fields echoes as a one-key object and a UNIT VARIANT ECHOES
## AS A BARE STRING. Reading the name back out of serde's own text is what makes this a check on the
## command rather than on my spelling of it.
func _variant_of(command: Variant) -> String:
	var echoed := AssaySimHost.command_echo(command)
	if echoed == "":
		return ""
	var parsed: Variant = JSON.parse_string(echoed)
	if typeof(parsed) == TYPE_STRING:
		return String(parsed)
	if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).size() == 1:
		return String((parsed as Dictionary).keys()[0])
	return ""


## THE WHOLE SURFACE, ONE ROW PER BUILDER. Every command a button or the probe can send, and the
## `PlayerCommand` variant serde lands on. If a builder's shape drifts this fails by name.
func test_serde_reads_every_command_this_client_can_build() -> bool:
	if not ClassDB.class_exists("AssaySim"):
		return _fail("no AssaySim class; see the failure above")
	var ore := AssayActions.item_of_stack(_stack("ore", 2, "C", 9))
	var refined := AssayActions.item_of_stack(_stack("refined", 2, "B", 4))
	var handle := AssayActions.item_of_stack(_stack("handle", 2, "B", 1))
	var head := AssayActions.item_of_stack(_stack("head", 2, "B", 1))
	var expected := [
		["Mine", AssayActions.mine()],
		["Stop", AssayActions.stop()],
		["Assay", AssayActions.assay()],
		["Unequip", AssayActions.unequip()],
		["MoveTo", AssayActions.move_to(Vector2i(40, 31))],
		["Craft", AssayActions.craft(AssaySimHost.recipe_tag("smelter"), ore, 1)],
		["Place", AssayActions.place(AssayActions.item_of_stack(
				_stack("smelter", 2, "C", 1)), Vector2i(41, 33))],
		["Insert", AssayActions.insert(3, AssayActions.SLOT_FUEL, ore, 6)],
		["Insert", AssayActions.insert(3, AssayActions.SLOT_INPUT, ore, 9)],
		["Take", AssayActions.take(3)],
		["Pickup", AssayActions.pickup(3)],
		["MakePart", AssayActions.make_part(AssaySimHost.part_tag("head"), refined, 2)],
		["MakePart", AssayActions.make_part(AssaySimHost.part_tag("handle"), refined, 1)],
		["MakePart", AssayActions.make_part(AssaySimHost.part_tag("frame"), refined, 1)],
		["MakePart", AssayActions.make_part(AssaySimHost.part_tag("hopper"), refined, 1)],
		["Assemble", AssayActions.assemble(handle, [head])],
		["Equip", AssayActions.equip(0)],
		["PlaceAssembly", AssayActions.place_assembly(1, Vector2i(44, 30))],
	]
	for row in expected:
		var want := String(row[0])
		var got := _variant_of(row[1])
		if got != want:
			return _fail("%s was read as %s, not %s (text: %s)"
					% [row[1], "nothing at all" if got == "" else got, want,
					JSON.stringify(row[1])])
	return true


## THE ECHO CAN FAIL, AND THESE ARE THE WAYS IT MUST.
##
## Without this, `test_serde_reads_every_command_this_client_can_build` would pass just as happily
## against a `command_echo` that accepted anything -- which is a lever that cannot fire, and I have
## shipped two of those. The first two rows are the bug I actually shipped, in both spellings.
func test_serde_refuses_the_command_shapes_that_look_right_and_are_not() -> bool:
	if not ClassDB.class_exists("AssaySim"):
		return _fail("no AssaySim class; see the failure above")
	var ore := AssayActions.item_of_stack(_stack("ore", 2, "C", 9))
	for bad in [
		# A unit variant written as an object, which is what I shipped as `Stop`.
		{"Mine": {}},
		{"Stop": {}},
		# Floats where the sim wants integers. Godot cannot tell these from the real thing.
		{"Equip": {"assembly": 0.5}},
		{"MoveTo": {"target": {"x": 40.5, "y": 31}}},
		# A `SystemCommand` is not a player's to send, and the relay's refusal should not be the
		# first thing to notice.
		{"AddPlayer": {"name": "limpet"}},
		# A verb the sim does not have, and a command missing a field it does.
		"Walk",
		{"Craft": {"item": ore, "count": 1}},
	]:
		if AssaySimHost.command_echo(bad) != "":
			return _fail("serde accepted %s, so the echo is not checking anything" % [bad])
	return true


## AN ITEM IS ECHOED, NEVER INVENTED: the kind, species and grade come straight back out of the stack
## the sim described. A client that re-derived any of them would eventually name an item it is not
## carrying, and the command would be refused for the wrong reason.
func test_an_item_is_echoed_out_of_the_stack_the_sim_named() -> bool:
	var stack := _stack("refined", 4, "B", 9)
	var item := AssayActions.item_of_stack(stack)
	if item != AssayActions.item("refined", 4, "B"):
		return _fail("a stack of refined became %s" % [item])
	if int(item["species"]) != 4 or String(item["grade"]) != "B":
		return _fail("the species or grade did not survive: %s" % [item])
	# A lower-case grade off the wire is still a grade; serde spells them upper.
	if AssayActions.item("ore", 1, "c") != AssayActions.item("ore", 1, "C"):
		return _fail("grade case changed the item")
	# An unknown kind is passed through UNCHANGED rather than guessed at, so the sim refuses it by
	# name instead of the client quietly turning it into some other item.
	if AssayActions.item("widget", 1, "C")["kind"] != "widget":
		return _fail("an unknown kind was guessed at: %s" % [AssayActions.item("widget", 1, "C")])
	return true


## ONE SOURCE FOR WHAT A HANDLE IS. `MakePart` names a PART kind and `Assemble` names an ITEM, so the
## same thing is spelled two ways on the wire -- and if they ever disagree, a client would make a
## handle and then assemble something that is not one.
func test_a_part_item_and_a_part_kind_agree_about_what_a_handle_is() -> bool:
	for kind in ["head", "handle", "frame", "hopper"]:
		var item: Variant = AssayActions.item(kind, 2, "C")["kind"]
		if typeof(item) != TYPE_DICTIONARY or not (item as Dictionary).has("Part"):
			return _fail("a %s item is not tagged as a part: %s" % [kind, item])
		if (item as Dictionary)["Part"] != AssayActions.part_kind_tag(kind):
			return _fail("a %s item says %s and MakePart says %s"
					% [kind, (item as Dictionary)["Part"], AssayActions.part_kind_tag(kind)])
	# A handle and a frame are ONE kind with two mounts, which is the catalogue's design.
	if AssayActions.part_kind_tag("handle") == AssayActions.part_kind_tag("frame"):
		return _fail("a handle and a planted frame must not be the same tag")
	return true


## AND THE SIM IS THE AUTHORITY ON THAT TABLE, not this client.
##
## `AssaySim.part_kinds()` hands over serde's own tag for every row of `PART_SPECS`; the table in
## `AssayActions.part_kind_tag` exists only because an ITEM's kind arrives as a word out of
## `inventory_of`. Holding the two against each other means a catalogue change in Rust fails here
## rather than on the wire -- and a NEW part kind fails loudly rather than appearing as a button that
## sends a command nobody can read.
func test_the_part_tags_this_client_knows_are_the_sims_own() -> bool:
	var catalogue := AssaySimHost.part_kinds()
	if catalogue.is_empty():
		return _fail("the sim reported no part kinds at all")
	for entry in catalogue:
		var row: Dictionary = entry
		var name := String(row.get("name", ""))
		if row.get("tag") != AssayActions.part_kind_tag(name):
			return _fail("the sim calls a %s %s and this client calls it %s"
					% [name, row.get("tag"), AssayActions.part_kind_tag(name)])
		if int(row.get("size", 0)) <= 0:
			return _fail("a %s costs %d refined, which cannot be right" % [name, row.get("size", 0)])
	# A kind the catalogue does not have comes back as the name itself, so the command is refused by
	# name rather than quietly becoming some other part.
	if AssaySimHost.part_tag("flywheel") != "flywheel":
		return _fail("an unknown part kind was guessed at: %s" % [AssaySimHost.part_tag("flywheel")])
	return true


## THE RECIPE TABLE IS THE SIM'S TOO, and the two fields the HUD leans on have to mean what they say:
## a hand recipe is one a player's own hands can make, and `input` is the item kind it eats.
func test_the_recipe_table_says_which_recipes_are_a_players_to_make() -> bool:
	var recipes := AssaySimHost.recipes()
	if recipes.is_empty():
		return _fail("the sim reported no recipes at all")
	var hand := PackedStringArray()
	var station := PackedStringArray()
	for entry in recipes:
		var recipe: Dictionary = entry
		if String(recipe.get("input", "")) == "":
			return _fail("recipe %s eats nothing" % [recipe])
		if bool(recipe.get("hand", false)):
			hand.append(String(recipe.get("name", "?")))
		else:
			station.append(String(recipe.get("name", "?")))
	if hand.is_empty():
		return _fail("no recipe is hand-craftable, so the pack can offer no Craft button at all")
	if station.is_empty():
		return _fail("no recipe happens in a building, so no stack can offer an Insert button")
	# The smelter is the one the demo loop turns on, and it has to be hand work: a player with no
	# building cannot make a building any other way.
	if not Array(hand).has("smelter"):
		return _fail("a smelter is not hand-craftable, so the chain cannot start: %s" % [hand])
	if AssaySimHost.recipe_tag("smelter") == "smelter":
		return _fail("the wire tag for a smelter recipe is its lower-case name, which serde refuses")
	return true


## WHICH VERBS A STACK OFFERS IS READ OUT OF THOSE TWO CATALOGUES, never written down here.
##
## The rule being tested: an Insert pair appears because some recipe eats this kind inside a
## BUILDING; Place appears because the item has a footprint; Frame/Mount appears because the kind is
## in the part catalogue. Nothing about whether it is affordable, in reach or hard enough --
## `sim::step` owns all of that.
##
## **AND NO `craft` OR `make`, WHICH IS THE ASSERTION THAT FLIPPED (ASSA-86, Maren's ruling.)** A
## pack row keeps the verbs that MOVE an item; everything that MAKES something is in the crafting
## menu, because a make-verb belongs to a recipe and a stack cannot say which species a shared
## label would make -- the board's pack drew two buttons both labelled exactly `Craft smelter`
## building smelters with different walls. The hand half of the recipe table is still READ here (it
## is how the Insert pair is derived at all); it just stops producing a button.
func test_a_stacks_verbs_come_from_the_sims_recipes_and_catalogue() -> bool:
	var recipes := AssaySimHost.recipes()
	var part_kinds := AssaySimHost.part_kinds()
	var ore := AssayHud.stack_verbs(_stack("ore", 2, "C", 9), recipes, part_kinds,
			Vector2i.ZERO, false)
	if _has(ore, "craft"):
		return _fail("ore offers a Craft; making something belongs to the menu: %s" % [ore])
	if not _has(ore, "insert"):
		return _fail("ore offers no Insert, though a smelter refines it: %s" % [ore])
	if _has(ore, "place"):
		return _fail("ore is not a building and must not offer Place: %s" % [ore])
	# ONE Insert PAIR, not one per smelter recipe: `Refine` and `Resmelt` both eat ore-ish things and
	# two identical buttons beside each other is a menu that looks broken.
	var inserts := 0
	for entry in ore:
		if String((entry as Dictionary).get("verb", "")) == "insert":
			inserts += 1
	if inserts != 2:
		return _fail("ore offers %d Insert buttons; it should be exactly fuel and input" % inserts)

	var smelter := AssayHud.stack_verbs(_stack("smelter", 2, "C", 1), recipes, part_kinds,
			Vector2i(2, 2), false)
	if not _has(smelter, "place"):
		return _fail("a smelter item has a 2x2 footprint and must offer Place: %s" % [smelter])

	var head := AssayHud.stack_verbs(_stack("head", 2, "B", 1), recipes, part_kinds,
			Vector2i.ZERO, false)
	if not _has(head, "build"):
		return _fail("a part offers no way into an Assemble: %s" % [head])
	if _label_of(head, "build") != "Frame":
		return _fail("the first part chosen is the frame, so the button says %s"
				% _label_of(head, "build"))
	var mounting := AssayHud.stack_verbs(_stack("head", 2, "B", 1), recipes, part_kinds,
			Vector2i.ZERO, true)
	if _label_of(mounting, "build") != "Mount":
		return _fail("with a frame already chosen the button should say Mount, says %s"
				% _label_of(mounting, "build"))

	# A kind nothing eats and nothing places offers nothing, and is STILL LISTED by the pack -- the
	# row is what a player is carrying, not a menu of what they can do.
	var gear := AssayHud.stack_verbs(_stack("gear", 2, "B", 1), recipes, part_kinds,
			Vector2i.ZERO, false)
	for entry in gear:
		if String((entry as Dictionary).get("verb", "")) in ["craft", "place", "build"]:
			return _fail("a gear is not craftable, placeable or a part: %s" % [gear])

	# NO KIND THE SIM HAS OFFERS A MAKE-VERB (ASSA-86). Every kind the catalogues name, not the four
	# this file happened to think of: a refined stack used to offer FOUR `Make` buttons plus a
	# `Craft gear`, which was the worst row in the game and the one a player lives in.
	var kinds := ["ore", "refined", "gear", "smelter"]
	for entry in part_kinds:
		kinds.append(String((entry as Dictionary).get("name", "?")))
	for kind in kinds:
		var verbs := AssayHud.stack_verbs(_stack(String(kind), 2, "B", 9), recipes, part_kinds,
				Vector2i.ZERO, false)
		for entry in verbs:
			var verb := String((entry as Dictionary).get("verb", ""))
			if verb == "craft" or verb == "make":
				return _fail("a %s row offers `%s`; making something is the menu's (ASSA-88): %s"
						% [kind, verb, verbs])
	return true


## PLACE IS ON EVERY PLANTED DESIGN, WHATEVER THE VERDICT SAYS (Maren's ruling, ASSA-5/7).
##
## This is the box that is easiest to break by being helpful. An over-budget design BREAKS at
## placement -- that is where the sim tests mass -- and breaking is a soft reset that hands the parts
## back, so hiding or disabling the button would turn a mechanic into an error message and WILL BREAK
## would stop being a prediction a player can choose to test.
func test_place_is_offered_on_a_planted_design_at_every_verdict() -> bool:
	for verdict in ["SAFE", "UNCERTAIN", "WILL BREAK", "?"]:
		var verbs := AssayHud.design_verbs({"index": 1, "in_hand": false, "mount": "planted",
				"verdict": verdict})
		if not _has(verbs, "place_assembly"):
			return _fail("a %s design offers %s instead of Place" % [verdict, verbs])
		if verbs.size() != 1:
			return _fail("a planted design should offer exactly Place, offers %s" % [verbs])
	var held := AssayHud.design_verbs({"index": 0, "in_hand": false, "mount": "held",
			"verdict": "WILL BREAK"})
	if not _has(held, "equip"):
		return _fail("a held design on the bench should offer Equip, offers %s" % [held])
	var in_hand := AssayHud.design_verbs({"index": -1, "in_hand": true, "mount": "held",
			"verdict": "SAFE"})
	if not _has(in_hand, "unequip"):
		return _fail("the tool in hand should offer Unequip, offers %s" % [in_hand])
	return true


## THE TARGET SENTENCE NAMES THE TILE AND SAYS WHICH KIND OF TILE IT IS, because Place, Insert and
## Take all land there and a target that is only drawn is one a player has to infer.
func test_the_target_line_says_where_a_button_will_act() -> bool:
	var standing := AssayHud.target_line(Vector2i(40, 31), false,
			{"in_bounds": true, "pos": Vector2i(40, 31)})
	if not standing.contains("40, 31") or not standing.contains("where you stand"):
		return _fail("before anything is chosen the target should be where you stand: %s" % standing)
	var chosen := AssayHud.target_line(Vector2i(44, 30), true, {"in_bounds": true,
			"building": {"kind": "smelter", "id": 3}})
	if not chosen.contains("44, 30") or not chosen.contains("smelter 3"):
		return _fail("a chosen tile with a building on it should name it: %s" % chosen)
	if chosen.contains("where you stand"):
		return _fail("a chosen tile should not still read as where you stand: %s" % chosen)
	return true


func _has(verbs: Array, verb: String) -> bool:
	for entry in verbs:
		if String((entry as Dictionary).get("verb", "")) == verb:
			return true
	return false


func _label_of(verbs: Array, verb: String) -> String:
	for entry in verbs:
		var row: Dictionary = entry
		if String(row.get("verb", "")) == verb:
			return String(row.get("label", ""))
	return ""
