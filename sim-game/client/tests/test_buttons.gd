extends RefCounted
## THE BUTTONS, PRESSED, IN A REAL WORLD, WITH NO RELAY.
##
## `test_actions.gd` proves the command SHAPES are the ones serde reads. This proves the other half,
## which is the half ASSA-37 is actually about: that pressing the thing a person can see submits that
## command, about the thing the row is describing, at the tile they chose. A command can be perfectly
## correct and have no click target -- that is exactly what this client was until today.
##
## HOW THERE IS A WORLD AT ALL. `AssaySimHost.fresh_welcome_json` writes the `Welcome` a relay would
## write, `AssayNetClient.play_offline` takes it through the real frame reader and the real `_handle`,
## and `_tick` below writes the `TickBundle` a relay would have sent out of whatever the buttons
## asked for. Everything but the socket is the code a joined client runs -- which matters, because a
## harness with its own command path would prove nothing about the real one.
##
## `tools/button_session.gd` plays the WHOLE loop this way, which is slower than a suite wants. What
## is here is the wiring: the first commands, the two map clicks, and the one row whose button must
## never be hidden.

## Ticks to run before giving up on something the sim was asked to do. Hand mining is a 4-tick cycle
## and a walk is a tile a tick, so this is generous rather than tight.
const PATIENCE := 120

var runner = null
## Every command the screen asked its client to submit, in order. Collected through the real `asked`
## signal, which fires inside `submit` -- so a button wired to nothing collects nothing.
var _asked: Array = []


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## A live screen, welcomed into a fresh offline world. `_ready` BY HAND for the same reason
## `test_main_screen.gd` does it: the suite works inside `SceneTree._initialize`, before the root
## window is in the tree, so the engine's own call comes too late to be useful.
func _joined(seed_text := "777042") -> Node:
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


## One tick: hand back the bundle a relay would have sent for whatever was asked, then let the screen
## step and redraw its panels.
##
## A BUNDLE IS NUMBERED WITH THE TICK WE ARE AT, not the one it produces. The relay builds
## `TickBundle { tick: world.tick }` and only then steps; I had that backwards once and every bundle
## a real relay sent was refused.
func _tick(screen: Node, count := 1) -> void:
	for _i in range(count):
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": screen._client.player_id, "command": command}})
		_asked.clear()
		var at: int = screen._sim.tick()
		screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))


## The first `Button` labelled `label` anywhere under a node, or null.
func _find(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == label:
			return child
		var found := _find(child, label)
		if found != null:
			return found
	return null


func _click(screen: Node, tile: Vector2i, button: int) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	var cell: float = screen._cell
	event.position = AssayHud.MARGIN + (Vector2(tile) + Vector2(0.5, 0.5)) * cell
	screen._unhandled_input(event)


## THERE IS A WORLD, AND IT IS THE SIM'S. Everything below leans on this, so it is asserted on its
## own: a harness that quietly failed to start a world would make every test after it vacuous.
func test_an_offline_client_is_welcomed_into_a_world_the_sim_built() -> bool:
	var screen := _joined()
	var ok := true
	if not screen._sim.running():
		ok = _fail("no world offline: %s" % screen._sim.fail_reason)
	elif screen._client.player_id < 0:
		ok = _fail("welcomed with no player id, so every read would be somebody else's")
	elif screen._sim.size_tiles() != Vector2i(96, 64):
		ok = _fail("the offline world is %s, not the relay's 96x64" % screen._sim.size_tiles())
	elif screen._cell <= 0.0:
		# The bug this caught for real: `_cell` was set by `_draw`, so a click meant nothing until
		# something had been painted -- and headless nothing ever is.
		ok = _fail("the map has no tile size, so no click on it can become a tile")
	else:
		_tick(screen, 3)
		if screen._sim.applied != 3:
			ok = _fail("fed 3 bundles and the sim applied %d" % screen._sim.applied)
	screen.queue_free()
	return ok


## BOX ONE: Mine, Stop and Assay are on the screen and submit the sim's own commands.
##
## Compared against `AssayActions`' own builders rather than against text I typed here: the point is
## that the BUTTON reaches the one file that spells a command, not that I can spell one twice.
func test_the_do_section_submits_the_sims_own_commands() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	for pair in [["Mine", AssayActions.mine()], ["Assay", AssayActions.assay()],
			["Stop", AssayActions.stop()]]:
		var label := String(pair[0])
		var button := _find(screen._actions, label)
		if button == null:
			ok = _fail("no %s button in the `do` section" % label)
			break
		_asked.clear()
		button.pressed.emit()
		if _asked.size() != 1:
			ok = _fail("%s asked for %d commands, not one" % [label, _asked.size()])
			break
		if _asked[0] != pair[1]:
			ok = _fail("%s submitted %s, not %s" % [label, _asked[0], pair[1]])
			break
		if AssaySimHost.command_echo(_asked[0]) == "":
			ok = _fail("%s submitted %s, which serde refuses" % [label, _asked[0]])
			break
	screen.queue_free()
	return ok


## LEFT CLICK WALKS, RIGHT CLICK CHOOSES WHERE THE BUTTONS ACT. One mechanism for Place, Insert and
## Take, so a click never means two things -- and the tile it chose is SAID, not only drawn.
func test_a_left_click_walks_and_a_right_click_chooses_the_target() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	var spawn: Vector2i = screen._sim.spawn_tile()
	var walk_to := spawn + Vector2i(3, 2)
	_asked.clear()
	_click(screen, walk_to, MOUSE_BUTTON_LEFT)
	if _asked.size() != 1 or _asked[0] != AssayActions.move_to(walk_to):
		ok = _fail("a left click on %s asked for %s" % [walk_to, _asked])
	else:
		# And the sim actually walks us there, which is the only proof the tile was the right one.
		_tick(screen, PATIENCE)
		var me: Vector2i = screen._my_tile()
		if me != walk_to:
			ok = _fail("walked toward %s and ended at %s" % [walk_to, me])
	if ok:
		var target := spawn + Vector2i(-2, 1)
		_asked.clear()
		_click(screen, target, MOUSE_BUTTON_RIGHT)
		if not _asked.is_empty():
			ok = _fail("a right click submitted %s; choosing a tile is not a command" % [_asked])
		elif screen._target_tile() != target:
			ok = _fail("a right click on %s left the target at %s"
					% [target, screen._target_tile()])
		else:
			var said := _text_of(screen._actions)
			if not said.contains("%d, %d" % [target.x, target.y]):
				ok = _fail("the `do` section never says which tile buttons act on: %s" % said)
	screen.queue_free()
	return ok


## BOX TWO AND THE PACK: a row describes one stack the sim reports, and its buttons act on THAT item.
##
## The command's item is compared against the sim's own stack, so a row wired to the wrong stack --
## two grades of one ore are two rows -- fails here rather than as a refusal nobody sees.
func test_a_pack_row_submits_a_command_about_its_own_stack() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var stacks: Array = screen._sim.inventory_of(screen._client.player_id)
		var stack: Dictionary = stacks[0]
		var row := _row_for(screen, AssayHud.stack_line(stack))
		if row == null:
			ok = _fail("no pack row reads `%s`; rows are %s"
					% [AssayHud.stack_line(stack), _text_of(screen._carrying)])
		else:
			var button := _find(row, "Craft smelter")
			if button == null:
				ok = _fail("no `Craft smelter` on an ore row: %s" % _labels_of(row))
			else:
				_asked.clear()
				button.pressed.emit()
				var want: Variant = AssayActions.craft(AssaySimHost.recipe_tag("smelter"),
						AssayActions.item_of_stack(stack), 1)
				if _asked.size() != 1 or _asked[0] != want:
					ok = _fail("`Craft smelter` submitted %s, not %s" % [_asked, want])
				elif AssaySimHost.command_echo(_asked[0]) == "":
					ok = _fail("`Craft smelter` submitted %s, which serde refuses" % [_asked[0]])
	screen.queue_free()
	return ok


## AND THE SMELTER IS ACTUALLY MADE, through the button and nothing else. The shape being right is
## `test_actions.gd`'s business; this is the stepped world agreeing that the press meant something.
func test_pressing_craft_puts_a_smelter_in_the_pack() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var stacks: Array = screen._sim.inventory_of(screen._client.player_id)
		var row := _row_for(screen, AssayHud.stack_line(stacks[0] as Dictionary))
		var button: Button = null if row == null else _find(row, "Craft smelter")
		if button == null:
			ok = _fail("no `Craft smelter` button to press")
		else:
			button.pressed.emit()
			# `RecipeId::Smelter` takes 20 ticks, and PRESSING AGAIN WOULD REFUND AND RESTART IT
			# (`sim::step`), which is how the button-driven session first failed: it pressed every
			# tick and the progress bar reset forever.
			_tick(screen, PATIENCE)
			if AssayDemoPlan.held(screen._sim.inventory_of(screen._client.player_id),
					"smelter", int((stacks[0] as Dictionary).get("species", -1))) < 1:
				ok = _fail("pressed Craft smelter and no smelter is in the pack: %s"
						% [screen._sim.inventory_of(screen._client.player_id)])
	screen.queue_free()
	return ok


## BOX THREE AND FOUR: A PLACE BUTTON ON A PLANTED DESIGN, AT EVERY VERDICT, CARRYING THAT DESIGN'S
## OWN INDEX AND THE TILE THAT WAS CLICKED.
##
## The design rows are built straight from `_design_button`, because getting a real planted design
## takes the whole craft chain (`tools/button_session.gd` does that, end to end, against a relay).
## What is checked here is the part that is easy to get wrong and silent when it is: the command
## carries the SIM'S `index`, not the row's position -- the tool in hand is a row whose index is -1,
## so counting rows would equip or plant the wrong design the moment anything was in hand.
func test_a_planted_row_places_that_design_on_the_clicked_tile() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	var spawn: Vector2i = screen._sim.spawn_tile()
	var target := spawn + Vector2i(2, -1)
	_click(screen, target, MOUSE_BUTTON_RIGHT)
	for verdict in ["SAFE", "UNCERTAIN", "WILL BREAK"]:
		var design := {"index": 3, "in_hand": false, "mount": "planted", "verdict": verdict}
		var verbs := AssayHud.design_verbs(design)
		if verbs.size() != 1:
			ok = _fail("a %s planted design offers %s" % [verdict, verbs])
			break
		var button: Button = screen._design_button(verbs[0] as Dictionary, design)
		if button == null or button.text != "Place":
			ok = _fail("a %s planted design's button is %s" % [verdict, button])
			break
		if button.disabled:
			ok = _fail("Place is DISABLED on a %s design; Maren's ruling is that it never is"
					% verdict)
			break
		_asked.clear()
		button.pressed.emit()
		var want: Variant = AssayActions.place_assembly(3, target)
		if _asked.size() != 1 or _asked[0] != want:
			ok = _fail("Place on a %s design submitted %s, not %s" % [verdict, _asked, want])
			break
		if AssaySimHost.command_echo(_asked[0]) == "":
			ok = _fail("Place submitted %s, which serde refuses" % [_asked[0]])
			break
	screen.queue_free()
	return ok


## Equip carries the sim's index too, and the tool in hand offers Unequip instead -- the one row that
## would be wrong if the client counted rows.
func test_equip_carries_the_sims_index_and_the_tool_in_hand_offers_unequip() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	var bench := {"index": 2, "in_hand": false, "mount": "held", "verdict": "SAFE"}
	var equip: Button = screen._design_button(
			AssayHud.design_verbs(bench)[0] as Dictionary, bench)
	_asked.clear()
	equip.pressed.emit()
	if equip.text != "Equip" or _asked != [AssayActions.equip(2)]:
		ok = _fail("a held design's `%s` submitted %s, not Equip 2" % [equip.text, _asked])
	else:
		var held := {"index": -1, "in_hand": true, "mount": "held", "verdict": "SAFE"}
		var spare: Button = screen._design_button(
				AssayHud.design_verbs(held)[0] as Dictionary, held)
		_asked.clear()
		spare.pressed.emit()
		if spare.text != "Unequip" or _asked != [AssayActions.unequip()]:
			ok = _fail("the tool in hand's `%s` submitted %s, not Unequip"
					% [spare.text, _asked])
	screen.queue_free()
	return ok


## NO BUTTON MAY CARRY A COUNT IT READ EARLIER. The pack only rebuilds when its SHAPE changes, so a
## stack's count climbs under a row that is never rebuilt -- and `Fuel`/`Smelt` insert the WHOLE
## stack. The first version of this captured the count in the closure: the button-driven session
## pressed `Fuel` on a row reading 12 and inserted 2, and the fire went out mid-stack.
func test_an_insert_counts_the_stack_when_it_is_pressed() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var stacks: Array = screen._sim.inventory_of(screen._client.player_id)
		var stack: Dictionary = stacks[0]
		var row := _row_for(screen, AssayHud.stack_line(stack))
		var button: Button = null if row == null else _find(row, "Fuel")
		if button == null:
			ok = _fail("no `Fuel` button on an ore row: %s" % _labels_of(row if row != null
					else screen._carrying))
		else:
			var before: int = int(stack.get("count", 0))
			# Keep mining, WITHOUT rebuilding the row: the shape of the pack has not changed, so the
			# same button object is still there and its label is the only thing that moved.
			_tick(screen, 40)
			var now := AssayDemoPlan.held(screen._sim.inventory_of(screen._client.player_id),
					String(stack.get("kind", "")), int(stack.get("species", -1)),
					String(stack.get("grade", "")))
			if now <= before:
				ok = _fail("mined 40 more ticks and hold %d, was %d; nothing to catch" % [now, before])
			elif _find(row, "Fuel") != button:
				ok = _fail("the row rebuilt, so this test cannot catch a stale count")
			else:
				# No building is targeted, so nothing is submitted -- but the sentence names the
				# number it was about to insert, which is where a stale count shows.
				_asked.clear()
				button.pressed.emit()
				var said: String = screen._status.text
				if not _asked.is_empty():
					ok = _fail("Insert with no building targeted submitted %s" % [_asked])
				elif not said.contains("nothing to insert into"):
					ok = _fail("pressing Fuel with no building targeted said: %s" % said)
	screen.queue_free()
	return ok


## Mine until the sim reports ore in the pack. Through the `do` section's own Mine button, because a
## test that filled an inventory by hand would be testing a world no button could have made.
func _mine_some_ore(screen: Node) -> bool:
	var deposit := AssaySessionPlan.nearest_of_species(screen._sim.deposits(),
			screen._sim.starter_pair()[0], screen._my_tile(), 0)
	if deposit.is_empty():
		return _fail("the offline world has no starter deposit with ore in it")
	var centre: Vector2i = deposit.get("center", Vector2i.ZERO)
	_click(screen, centre, MOUSE_BUTTON_LEFT)
	_tick(screen, PATIENCE)
	if screen._my_tile() != centre:
		return _fail("walked toward the deposit at %s and stopped at %s"
				% [centre, screen._my_tile()])
	var mine := _find(screen._actions, "Mine")
	if mine == null:
		return _fail("no Mine button in the `do` section")
	mine.pressed.emit()
	_tick(screen, PATIENCE)
	var stacks: Array = screen._sim.inventory_of(screen._client.player_id)
	if stacks.is_empty():
		return _fail("pressed Mine on the deposit at %s for %d ticks and hold nothing"
				% [centre, PATIENCE])
	return true


## The pack row whose first line reads exactly this.
func _row_for(screen: Node, line: String) -> Node:
	for row in screen._carrying.get_children():
		# BY NAME, NOT BY POSITION. A pack row is [icon?][VBox: line, verbs] since ASSA-46, so the
		# sentence is not child 0 and is not at a fixed depth either -- whether the icon exists depends
		# on whether we have art for that item.
		var label := row.find_child(screen.STACK_LINE, true, false) as Label
		if label != null and label.text == line:
			return row
	return null


func _text_of(node: Node) -> String:
	var out := PackedStringArray()
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		out.append(_text_of(child))
	return " · ".join(out)


func _labels_of(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for child in node.get_children():
		if child is Button:
			out.append((child as Button).text)
		out.append_array(_labels_of(child))
	return out
