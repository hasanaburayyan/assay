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


## PRESS A TILE THROUGH THE SCREEN'S OWN ANSWER FOR WHERE THAT TILE IS (`point_of_tile`), not through
## a copy of the arithmetic. This used to spell `MARGIN + (tile + 0.5) * _cell` itself, which was
## right while there was one view of the world and wrong in sixteen tests the hour a second one
## arrived (ASSA-119): every press landed on a tile 40 away and read as the sim refusing a walk.
## FROM WHICHEVER VIEW SHOWS THE TILE, and that branch is a fact about the GAME rather than about this
## harness. The close-up is 28x18 tiles of a 96x64 world, so the starter deposit 26 tiles away is
## genuinely not on screen and no real click could land on it -- crossing the world is what the
## schematic is for (Maren's ruling, ASSA-119). A synthetic press that names a tile has to pick a view
## the way a player would, press, and put the view back. `tools/button_play.gd::_click` does the same
## for the same reason.
func _click(screen: Node, tile: Vector2i, button: int) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	var was: bool = screen._close_up
	if was and not AssayHud.world_rect().has_point(screen.point_of_tile(tile)):
		screen._show_close_up(false)
	event.position = screen.point_of_tile(tile)
	screen._unhandled_input(event)
	if was != screen._close_up:
		screen._show_close_up(was)


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


## THE SESSION TOOL'S OWN ROW FINDER, PRESSED THROUGH, because `_row_for` below is a SECOND
## IMPLEMENTATION of the same lookup and the two have already disagreed. #81 moved the pack sentence
## out of child 0; `_row_for` was fixed in that PR and `tools/button_play.gd` was not, so
## `tools/button_session.gd -- offline` could no longer press anything on a pack row and stopped at
## `Craft smelter` -- while every test in this file still passed, because they all ask `_row_for`
## (ASSA-62). Nothing in CI runs the session, so this is the only cheap witness: the one assertion
## here that fails when the TOOL rots rather than when the screen does.
func test_the_session_tool_can_press_a_pack_row() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var stack: Dictionary = screen._sim.inventory_of(screen._client.player_id)[0]
		var play := AssayButtonPlay.new(screen, 0)
		_asked.clear()
		# A MOVE VERB, because `Craft smelter` is not on a pack row any more (ASSA-86): the pack is
		# what you have and where it can go. `Fuel` is the one every ore row carries whatever the
		# sheet says (Maren, ASSA-37), so it is the honest thing to look for here.
		if not play._press_on_stack(String(stack.get("kind", "")),
				int(stack.get("species", -1)), "Fuel"):
			ok = _fail("AssayButtonPlay found no `Fuel` on the row reading `%s`; the pack "
					% AssayHud.stack_line(stack) + "shows %s" % _text_of(screen._carrying))
		# NO COMMAND IS ASSERTED FOR THE PACK HALF, and that is the honest reading: `Insert` carries
		# a building id, so with nothing right-clicked the client cannot form the command at all and
		# says so on the status line. What ASSA-62 broke was the tool's ability to FIND and press a
		# row, which is what this asserts. The menu half below does submit.
		elif play.pressed.is_empty():
			ok = _fail("the tool pressed a pack row and recorded nothing")
		else:
			# AND THE TOOL'S MENU FINDER, for the same reason: the make-verbs moved, so the press
			# that used to rot silently is `_press_on_offer` now. Nothing in CI runs the session.
			_asked.clear()
			if not play._press_on_offer("craft", "Smelter", int(stack.get("species", -1))):
				ok = _fail("AssayButtonPlay found no craft/Smelter row in the menu: %s"
						% _text_of(screen._make))
			elif _asked.size() != 1:
				ok = _fail("the tool's menu press submitted %s, not one command" % [_asked])
	screen.queue_free()
	return ok


## NO PACK ROW OFFERS A VERB THAT MAKES SOMETHING (ASSA-86, Maren's ruling: the pack is what you
## HAVE and where it can GO).
##
## DERIVED FROM THE COMMANDS, NOT FROM THE LABELS. Pressing every button on every row and requiring
## that none of them submits a `Craft` or a `MakePart` reads the sim's own command names, so it keeps
## working the day a label is reworded or a fifth part kind appears -- where a list of allowed labels
## written in this file would be one more thing to keep in step.
##
## TWO SPECIES IN THE PACK, because the bug Maren measured needed two: the duplicate `Craft smelter`
## only appears once you carry ore of two kinds.
##
## That a row's buttons act on THAT row's stack is `test_an_insert_submits_the_count_it_read_at_the_press`
## with a real building in reach; this is about which verbs are there at all.
func test_no_pack_row_offers_a_verb_that_makes_something() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_two_species(screen)
	var presses := 0
	if ok:
		for row in screen._carrying.get_children():
			for button in _buttons_under(row):
				_asked.clear()
				presses += 1
				button.pressed.emit()
				for command in _asked:
					var sent: Dictionary = command
					if sent.has("Craft") or sent.has("MakePart"):
						ok = _fail("a pack row's `%s` submitted %s; making something left the pack"
								% [button.text, JSON.stringify(sent)])
						break
				if not ok:
					break
			if not ok:
				break
	if ok and presses == 0:
		ok = _fail("no buttons on any pack row, so nothing was checked")
	screen.queue_free()
	return ok


func _buttons_under(node: Node) -> Array:
	var out := []
	for child in node.get_children():
		if child is Button:
			out.append(child)
		out.append_array(_buttons_under(child))
	return out


## AND THE SMELTER IS ACTUALLY MADE, through the button and nothing else. The shape being right is
## `test_actions.gd`'s business; this is the stepped world agreeing that the press meant something.
func test_pressing_craft_puts_a_smelter_in_the_pack() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var stacks: Array = screen._sim.inventory_of(screen._client.player_id)
		# FROM THE MENU SINCE ASSA-86, which is also a better test of the move: the row has to name
		# the smelter it will make for this to find it at all.
		var button := _make_button_for(screen, "smelter")
		if button == null:
			ok = _fail("no menu row offers a smelter: %s" % _text_of(screen._make))
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


## WITH NO BUILDING TARGETED THERE IS NOTHING TO SUBMIT, AND SAYING SO IS THE ANSWER. `_insert`'s
## early return: with no building there is no `BuildingId` to put in the command at all, so the
## sentence is honest rather than a swallowed press. (Maren's "never refuse" is about commands the sim
## should judge; this one cannot be built.)
##
## THIS TEST USED TO CLAIM MORE THAN IT PROVED, and Nerite caught it by mutation (ASSA-55). It was
## named for the stale-count rule, and its comment said the refusal sentence "names the number it was
## about to insert". It does not: the early return happens BEFORE any count is read, so putting the
## captured `stack.count` back left this green and the suite at 111/0. The rule it was named for is
## tested next door against a smelter that really stands in the world. What is left here is the
## branch this actually covers -- and the "no building" precondition is now ASSERTED rather than
## assumed, because that is the only thing keeping it in this branch.
func test_an_insert_with_no_building_targeted_submits_nothing_and_says_so() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var stack := _stack_of(screen, "ore")
		var row := _row_for(screen, AssayHud.stack_line(stack))
		var button: Button = null if row == null else _find(row, "Fuel")
		if button == null:
			ok = _fail("no `Fuel` button on an ore row: %s" % _labels_of(row if row != null
					else screen._carrying))
		elif screen._sim.tile_at(screen._target_tile()).get("building") != null:
			ok = _fail("a building stands on %s, so this is not the early-return branch"
					% screen._target_tile())
		else:
			_asked.clear()
			button.pressed.emit()
			var said: String = screen._status.text
			if not _asked.is_empty():
				ok = _fail("Insert with no building targeted submitted %s" % [_asked])
			elif not said.contains("nothing to insert into"):
				ok = _fail("pressing Fuel with no building targeted said: %s" % said)
	screen.queue_free()
	return ok


## NO BUTTON MAY CARRY A COUNT IT READ EARLIER, AND THE PROOF HAS TO REACH THE SUBMITTED COMMAND
## (ASSA-55).
##
## The pack only rebuilds when its SHAPE changes, so a stack's count climbs under a row that is never
## rebuilt -- and `Fuel`/`Smelt` insert the WHOLE stack. The first version of `_insert` captured the
## count in the closure: the button-driven session pressed `Fuel` on a row reading 12 and inserted 2,
## and the fire went out mid-stack.
##
## So this needs all three at once, which is why it builds a smelter: a targeted building (or
## `_insert` returns early and nothing is sent), a count that has MOVED since the button was made,
## and the SAME button object still on screen.
##
## THE EXPECTED NUMBER IS READ OFF THE SIM, NOT THROUGH `AssayInventory.held`. That function is
## what `_insert` itself calls, and a test that computes its expectation with the code under test
## agrees with its bugs -- a grade filter that stopped filtering would be invisible to both. `_counted`
## sums the sim's own `count` fields instead.
func test_an_insert_submits_the_count_it_read_at_the_press() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	var at := _a_placed_smelter(screen)
	if at < 0:
		ok = false
	else:
		var stack := _stack_of(screen, "ore")
		var row := _row_for(screen, AssayHud.stack_line(stack))
		var button: Button = null if row == null else _find(row, "Fuel")
		var mine := _find(screen._actions, "Mine")
		if button == null:
			ok = _fail("no `Fuel` button on the ore row after placing a smelter: %s"
					% _labels_of(screen._carrying))
		elif mine == null:
			ok = _fail("no `Mine` button to start the count climbing again")
		else:
			var before := _counted(screen, stack)
			# Mining again under a row that is NOT rebuilt: crafting the smelter took the activity, so
			# the swinging has to be asked for a second time.
			mine.pressed.emit()
			_tick(screen, 40)
			var now := _counted(screen, stack)
			if now <= before:
				ok = _fail("mined 40 more ticks and hold %d of the ore, was %d; nothing stale to catch"
						% [now, before])
			elif _find(row, "Fuel") != button:
				ok = _fail("the ore row rebuilt, so a stale count could not have survived on it")
			else:
				_asked.clear()
				button.pressed.emit()
				var want: Variant = AssayActions.insert(at, AssayActions.SLOT_FUEL,
						AssayActions.item_of_stack(stack), now)
				var said: String = screen._status.text
				if _asked.size() != 1:
					ok = _fail("`Fuel` on a targeted smelter submitted %s, not one Insert" % [_asked])
				elif _asked[0] != want:
					# The stale number is whatever the ROW was built with, which is lower still than
					# `before` -- this test only took hold of the button afterwards. So report both
					# honestly rather than naming `before` as the closure's value.
					ok = _fail(("`Fuel` submitted %s, not %s: a count read EARLIER. The sim said %d "
							+ "when this test took the button, and says %d now.")
							% [_asked[0], want, before, now])
				elif AssaySimHost.command_echo(_asked[0]) == "":
					ok = _fail("Insert submitted %s, which serde refuses" % [_asked[0]])
				elif not said.contains(str(now)):
					# THE NUMBER TOLD AND THE NUMBER SENT ARE ONE NUMBER. `_act`'s sentence is the only
					# report the player gets, and a true command under a stale sentence is still a lie.
					ok = _fail("submitted an Insert of %d and told the player: %s" % [now, said])
	screen.queue_free()
	return ok


## A SMELTER THAT REALLY STANDS IN THE WORLD, MADE THE WAY A PLAYER MAKES ONE, and targeted. Returns
## its `BuildingId`, or -1 having already failed the run.
##
## BUILT, NOT PLANTED. `_insert` reads its building out of `tile_at`, so a world with a building
## written into it by the harness would be testing the harness. Every stage here is a press or a
## click: mine, `Craft smelter`, right-click a free 2x2, `Place`. The right-click that chooses where
## it goes is also what targets it afterwards -- Place, Insert and Take share one mechanism (ASSA-37),
## which is the whole reason that is worth leaning on here.
func _a_placed_smelter(screen: Node) -> int:
	if not _mine_some_ore(screen):
		return -1
	var ore := _stack_of(screen, "ore")
	if ore.is_empty():
		_fail("mined and hold no ore stack to craft from")
		return -1
	# ENOUGH THAT THE ORE ROW SURVIVES THE CRAFT. Five ore go into the smelter; if that empties the
	# row, the pack's shape changes, every button on it is freed, and there is no stale count to have.
	var want := AssayDemoPlan.SMELTER_ORE + 4
	for _i in range(12):
		if _counted(screen, ore) >= want:
			break
		_tick(screen, 20)
	if _counted(screen, ore) < want:
		_fail("mined and hold %d of %s, want %d before crafting a smelter"
				% [_counted(screen, ore), AssayHud.stack_line(ore), want])
		return -1
	# FROM THE CRAFTING MENU SINCE ASSA-86: the pack row carries only the verbs that MOVE an item.
	var craft := _make_button_for(screen, "smelter")
	if craft == null:
		_fail("no menu row offers a smelter: %s" % _text_of(screen._make))
		return -1
	craft.pressed.emit()
	for _i in range(6):
		if not _stack_of(screen, "smelter").is_empty():
			break
		_tick(screen, AssayDemoPlan.CRAFT_TICKS)
	var smelter := _stack_of(screen, "smelter")
	if smelter.is_empty():
		_fail("pressed `Craft smelter` and no smelter arrived in %d ticks"
				% (6 * AssayDemoPlan.CRAFT_TICKS))
		return -1
	var me: Vector2i = screen._my_tile()
	var spot := AssayDemoPlan.smelter_spot(me, screen._sim.size_tiles(), _buildings_near(screen, me))
	if spot.x < 0:
		_fail("no free 2x2 within reach of %s for a smelter" % me)
		return -1
	_click(screen, spot, MOUSE_BUTTON_RIGHT)
	var place: Button = _button_on_row(screen, smelter, "Place")
	if place == null:
		return -1
	place.pressed.emit()
	_tick(screen, 4)
	var building: Variant = screen._sim.tile_at(spot).get("building")
	if building == null:
		_fail("pressed `Place` for a smelter at %s and nothing stands there" % spot)
		return -1
	if screen._target_tile() != spot:
		_fail("placed a smelter at %s and the buttons act on %s" % [spot, screen._target_tile()])
		return -1
	return int((building as Dictionary).get("id", -1))


## The first stack of a kind the SIM says is in the pack, or {}.
func _stack_of(screen: Node, kind: String) -> Dictionary:
	for entry in screen._sim.inventory_of(screen._client.player_id):
		var stack: Dictionary = entry
		if String(stack.get("kind", "")) == kind:
			return stack
	return {}


## HOW MANY OF THAT EXACT ITEM THE SIM SAYS WE HOLD, summed off the snapshot's own `count` fields.
##
## Deliberately not `AssayInventory.held`: that is the function `_insert` calls, so using it here
## would make the expectation and the thing it checks share their arithmetic. Kind, species AND grade,
## because two grades of one ore are two stacks and two rows.
func _counted(screen: Node, item: Dictionary) -> int:
	var total := 0
	for entry in screen._sim.inventory_of(screen._client.player_id):
		var stack: Dictionary = entry
		if String(stack.get("kind", "")) != String(item.get("kind", "")):
			continue
		if int(stack.get("species", -1)) != int(item.get("species", -1)):
			continue
		if String(stack.get("grade", "")) != String(item.get("grade", "")):
			continue
		total += int(stack.get("count", 0))
	return total


## A labelled button on the pack row describing this stack, or null having failed the run.
func _button_on_row(screen: Node, stack: Dictionary, label: String) -> Button:
	var line := AssayHud.stack_line(stack)
	var row := _row_for(screen, line)
	if row == null:
		_fail("no pack row reads `%s`: %s" % [line, _labels_of(screen._carrying)])
		return null
	var button := _find(row, label)
	if button == null:
		_fail("no `%s` button on the row reading `%s`: %s" % [label, line, _labels_of(row)])
	return button


## The tiles around us the SIM says already carry a building, which is what `smelter_spot` picks
## between. Reach is 3, so four tiles out covers every spot it would consider.
func _buildings_near(screen: Node, at: Vector2i) -> Array:
	var taken := []
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var tile := at + Vector2i(dx, dy)
			if screen._sim.tile_at(tile).get("building") != null:
				taken.append(tile)
	return taken


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


## THE COUNT KEEPS CLIMBING WITHOUT THE ROW BEING REBUILT, WHICH IS THE BUG I MADE ADDING THE ICON.
##
## `_refresh_pack` has a fast path: if the pack's SHAPE is unchanged it re-texts each row's sentence
## instead of rebuilding, because a count climbs every mining cycle and rebuilding ten times a second
## would destroy a button under the pointer. That path used to fetch `row.get_child(0)` as the Label.
## Adding a 32px icon (ASSA-46) made child 0 a TextureRect, so the fast path found null and SILENTLY
## STOPPED UPDATING THE COUNT -- the number would freeze while mining and only correct itself when some
## other item appeared and changed the shape.
##
## Three unrelated tests happened to catch it because they look rows up by their text. That was luck,
## so this is the test that is actually about it: mine past one cycle with the shape held constant and
## require the sentence on screen to have moved.
func test_the_pack_count_climbs_without_rebuilding_the_row() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var stacks: Array = screen._sim.inventory_of(screen._client.player_id)
		if stacks.is_empty():
			ok = _fail("mined and the pack is empty")
		else:
			var first := AssayHud.stack_line(stacks[0] as Dictionary)
			var row := _row_for(screen, first)
			if row == null:
				ok = _fail("no row reads `%s`" % first)
			else:
				var shape_before: String = screen._pack_showing
				# Keep mining: the count climbs and the SHAPE does not change, so the fast path runs.
				_tick(screen, 40)
				var after: Array = screen._sim.inventory_of(screen._client.player_id)
				var wanted := AssayHud.stack_line(after[0] as Dictionary)
				if wanted == first:
					ok = _fail("the sim's count did not move in 40 ticks, so this proves nothing")
				elif screen._pack_showing != shape_before:
					ok = _fail("the pack shape changed, so the rebuild path ran and the fast path is "
							+ "still untested")
				else:
					var label := row.find_child(screen.STACK_LINE, true, false) as Label
					if label == null:
						ok = _fail("the row has no %s label any more" % screen.STACK_LINE)
					elif label.text != wanted:
						ok = _fail(("the row still reads `%s` while the sim says `%s`. The fast path "
								+ "stopped finding its label.") % [label.text, wanted])
	screen.queue_free()
	return ok


## ASSA-49: A RUNNING CRAFT SAYS SO ON SCREEN, AND STOPS SAYING SO WHEN IT FINISHES.
##
## Pressing Craft again while one runs refunds the current unit and starts over -- "latest command
## wins", the same as `MoveTo` and `Mine` -- and that rule is right. The defect was silence: a person
## who presses a button and sees nothing presses it again and throws the work away. So the line is the
## fix, and this is the test that it is actually on the panel rather than merely available.
##
## IT ASKS THE SCREEN, NOT THE SIM. `crafting_readout` is unit-tested in `sim/tests/crafting.rs`
## against the whole sentence; what can only be checked here is that `_refresh` puts it on the panel
## and takes it away again, which is the half that broke twice this week in other panels.
##
## **MOVED TO THE HEAD OF THE CRAFTING MENU (ASSA-88, Maren's ruling), AND THIS TEST MOVED WITH IT
## RATHER THAN BEING LOOSENED.** It used to read the `do` section, where the sentence competed with
## Mine and Assay and sat nowhere near the button that started the craft. Two things are asserted now
## that were not before: that the press comes from a MENU row, and that **collapsing the menu does
## not take the countdown away** -- a craft is a CONDITION, not a moment, so a line a closed menu
## could hide would not discharge it.
func test_a_running_craft_is_named_at_the_head_of_the_crafting_menu() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok and screen._crafting.visible:
		ok = _fail("the panel claimed a craft before one was started: %s" % screen._crafting.text)
	if ok:
		var button := _make_button_for(screen, "smelter")
		if button == null:
			ok = _fail("no menu row offers a smelter: %s" % _text_of(screen._make))
		else:
			button.pressed.emit()
			_tick(screen, 2)
			var during: String = screen._crafting.text
			if not screen._crafting.visible:
				ok = _fail("a craft is running and the countdown is hidden: `%s`" % during)
			elif not during.contains("making ") or not during.contains("ticks left"):
				ok = _fail(("a craft is running and the head of the menu does not say so: %s. The "
						+ "ticks come from the sim; this client only prints them.") % during)
			else:
				# THE CLAUSE MAREN ADDED. The menu folds; the condition does not.
				screen._show_make(false)
				screen._refresh()
				if not screen._crafting.visible:
					ok = _fail("folding the menu away hid the running craft, which lasts until it "
							+ "finishes whatever the menu is doing")
				elif screen._make.visible:
					ok = _fail("_show_make(false) left the rows visible, so this proves nothing")
				else:
					screen._show_make(true)
					# AND IT GOES AWAY. A line that appears and never clears is worse than no line:
					# it would say a craft is running forever, which is the same lie the silence was.
					_tick(screen, PATIENCE)
					if screen._crafting.visible or screen._crafting.text != "":
						ok = _fail("the craft finished and the panel still claims one: %s"
								% screen._crafting.text)
	screen.queue_free()
	return ok


## THE MENU ROW THAT OFFERS `want`, by the SIM'S OWN SENTENCE and never by a button label: every
## row's button says the same word on purpose (Maren's ruling), so the row is found by what it says
## it makes and the button is then the one inside it.
func _make_button_for(screen: Node, want: String) -> Button:
	for row in screen._make.get_children():
		var line := row.find_child(screen.MAKE_LINE, true, false) as Label
		if line != null and line.text.contains(want):
			return _find(row, AssayHud.make_button_text())
	return null


## A REFUSAL REACHES THE ALWAYS-VISIBLE LINE WITH THE LOG HIDDEN (ASSA-89), THROUGH A REAL SIM.
##
## The log is folded away by default now, and it was the only place the sentence explaining why a
## button did nothing ever appeared. So: press **Mine** standing where there is no deposit, which is
## a refusal the sim produces rather than one this file writes, and require the sentence on the
## status line while the log is hidden.
##
## **WHAT IS NOT ASSERTED, AND WHY.** Not that the status text equals
## `_sim.attention_lines(id)[-1]` -- that is the expression `_remember_events` runs, so it would
## pass by construction the moment the function was called at all, about nothing. What is asserted
## is the RELATIONSHIP BETWEEN THE TWO SURFACES: the status line must be a sentence the log also
## carries (so the client moved a line rather than composing one of its own), it must have replaced
## the join message (so something actually arrived), and the log must still carry it (so the loud
## copy is a copy and the log was not drained to feed it).
func test_a_refused_press_reaches_the_status_line_while_the_log_is_hidden() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var joined_said: String = screen._status.text
	var ok := true
	if screen._log.visible:
		ok = _fail("the log is visible in a fresh client, so this test proves nothing")
		screen.queue_free()
		return ok
	var mine := _find(screen._actions, "Mine")
	if mine == null:
		ok = _fail("no Mine button in the `do` section")
		screen.queue_free()
		return ok
	# Spawn is not a deposit: the two chunks BESIDE spawn hold the starter material, which is what
	# makes this a refusal rather than a mining cycle. Checked, not assumed.
	var standing: Dictionary = screen._sim.tile_at(screen._my_tile())
	if standing.get("deposit", null) != null:
		ok = _fail("this seed spawns the player on a deposit, so Mine would succeed: %s" % standing)
		screen.queue_free()
		return ok
	mine.pressed.emit()
	_tick(screen, 2)
	var said: String = screen._status.text
	var log_text := _text_of(screen._log)
	if said == joined_said:
		ok = _fail(("the sim refused a press and the always-visible line still reads '%s'. With the "
				+ "log hidden the player is told nothing at all.") % said)
	elif said.strip_edges() == "":
		ok = _fail("the status line was blanked rather than written")
	elif not log_text.contains(said):
		ok = _fail(("the status line says '%s', which is not one of the log's own sentences: '%s'. "
				+ "A client that words its own refusal is a second describer.") % [said, log_text])
	elif screen._log.visible:
		ok = _fail("showing the player a refusal unfolded the whole log")
	screen.queue_free()
	return ok


## AND A SUCCESS DOES NOT TAKE THE LINE. The separation is the whole property: if every event were
## loud the always-visible line would be a one-row log, and a player learns to stop reading a surface
## that talks constantly. Walking is the plainest success there is -- a left click, three events, none
## of them a problem.
##
## **IT TOOK TWO WRONG VERSIONS TO GET THE ASSERTION RIGHT, AND BOTH ARE WORTH LEAVING WRITTEN DOWN.**
##
## First I required the status line to be UNCHANGED by a walk. It failed, correctly: offline play
## puts its own note there ("offline, so no hash report was sent") through the same `_say` the link
## uses, so "unchanged" was never the property.
##
## Then I read the status line ONCE, at the end, and required it not to be one of the log's
## sentences. That passed -- and it passed a mutation that promoted EVERY event line, which is the
## one thing this test exists to catch. The reason is a 20-tick clock: a hash report is owed every
## twenty ticks, its note lands on the status line after the walk's events, and I was ticking twenty
## times. The surface I was reading had been overwritten by the time I looked at it.
##
## So the status line is sampled after EVERY tick and none of the samples may be a sentence the log
## carries. That is the claim as stated -- "no success is ever promoted" -- rather than a claim about
## what the line happens to hold at one arbitrary moment.
func test_walking_does_not_shout_on_the_always_visible_line() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	var before := _text_of(screen._log)
	_click(screen, screen._my_tile() + Vector2i(2, 0), MOUSE_BUTTON_LEFT)
	var samples := PackedStringArray()
	for _i in range(20):
		_tick(screen, 1)
		samples.append(screen._status.text)
	var log_text := _text_of(screen._log)
	if log_text == before or log_text.strip_edges() == "":
		ok = _fail("the walk produced no event lines, so this proves nothing about what is loud")
	else:
		for said in samples:
			if said.strip_edges() == "":
				ok = _fail("the status line was blanked during the walk")
				break
			if log_text.contains(said):
				ok = _fail(("walking promoted one of the log's own sentences onto the "
						+ "always-visible line: '%s'. Successes are the log's; that surface holds "
						+ "one line and it is for what went wrong.") % said)
				break
	screen.queue_free()
	return ok


## ASSA-88: THE BUG THE BOARD HIT, AT THE WINDOW. Maren measured their pack: two ore species drew two
## buttons both labelled exactly `Craft smelter`, building smelters with DIFFERENT WALLS, told apart
## only by which row you were standing on. Walls decide what a smelter can ever melt.
##
## So: carry two species of ore and require that the menu's rows for one recipe (a) are two, and
## (b) DO NOT READ ALIKE. That is the whole defect as a property, and it cannot be satisfied by a
## label this client writes -- the only text on a row is the sim's sentence.
func test_two_species_of_ore_give_two_menu_rows_that_do_not_read_alike() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_two_species(screen)
	if ok:
		var species: Array = screen._sim.species_names()
		var rows := _make_lines_containing(screen, "smelter")
		if rows.size() < 2:
			ok = _fail("two species of ore in the pack and %d smelter rows: %s"
					% [rows.size(), _text_of(screen._make)])
		elif rows[0] == rows[1]:
			ok = _fail("two rows read exactly `%s` and make different machines" % rows[0])
		else:
			var named := 0
			for name in species:
				for row in rows:
					if String(row).contains(String(name)):
						named += 1
						break
			if named < 2:
				ok = _fail("the two smelter rows name %d species between them: %s" % [named, rows])
	screen.queue_free()
	return ok


## EVERY ROW IS THE SIM'S SENTENCE AND NOT A STRING THIS CLIENT BUILT. Asserted as a property rather
## than by comparing against `make_offers()[i].line`, which is the expression `_rebuild_make` runs and
## would pass by construction about nothing: a row must name its material in WORDS (the species name
## and a grade in brackets) and must never carry the typed `ore:species:b` spec or a serde tag.
func test_no_menu_row_shows_a_typed_spec_or_a_wire_tag() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var lines := _make_lines_containing(screen, "")
		if lines.is_empty():
			ok = _fail("a pack with ore in it produced no menu rows at all")
		for entry in lines:
			var line := String(entry)
			if line.contains("ore:") or line.contains("refined:"):
				ok = _fail("a row carries the typed item spec, which is what you TYPE: %s" % line)
				break
			if line.contains("Smelter") or line.contains("Sort") or line.contains("{"):
				ok = _fail("a row carries a wire tag rather than a sentence: %s" % line)
				break
			if not line.contains("(") or not line.contains(")"):
				ok = _fail("a row names no grade, so two grades of one rock read alike: %s" % line)
				break
	screen.queue_free()
	return ok


## PRESSING A ROW SUBMITS THE SAME `PlayerCommand` `sim-cli` SENDS, and the recipe and item in it are
## the sim's own -- the tag out of `make_offers`, the item rearranged by `item_of_stack`. Read off the
## real `asked` signal, so a button wired to nothing collects nothing.
##
## AND THE COUNT IS ALWAYS 1 (ASSA-55). The sentence on the row says how many you hold; nothing in the
## closure does, so there is no number here that can go stale between the build and the press.
##
## **EVERY ROW, NOT THE FIRST ONE.** I wrote this against `offers[0]` and a mutation walked straight
## through it: make every button send `offers[0]`'s item and the test still passed, because the only
## row it ever pressed was the one that mutation happened to be right about. A menu's whole job is
## that row N acts on row N's material.
func test_pressing_any_menu_row_submits_the_sims_own_command_for_that_row() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	# TWO SPECIES, NOT ONE, AND THAT IS WHAT MAKES THIS TEST ABOUT PAIRING. With one stack in the
	# pack every offer has the SAME input item and only the recipe differs, so "every button sends
	# the first row's item" is indistinguishable from correct -- a mutation walked through this test
	# until the pack held two kinds of rock.
	var ok := _mine_two_species(screen)
	if ok:
		var offers: Array = screen._sim.make_offers(screen._client.player_id)
		var inputs := {}
		for entry in offers:
			inputs[int((entry as Dictionary).get("species", -1))] = true
		if offers.size() < 2:
			ok = _fail("a pack with ore in it offers %d rows; one row proves nothing about pairing"
					% offers.size())
		elif inputs.size() < 2:
			ok = _fail("every row acts on the same material, so pairing cannot be tested here")
		for i in range(offers.size()):
			if not ok:
				break
			var offer: Dictionary = offers[i]
			var row: Node = screen._make.get_child(i)
			var line := row.find_child(screen.MAKE_LINE, true, false) as Label
			var button := _find(row, AssayHud.make_button_text())
			_asked.clear()
			if line == null or button == null:
				ok = _fail("row %d has no sentence or no button" % i)
				break
			button.pressed.emit()
			var wanted := "craft" if String(offer.get("verb", "")) == "craft" else "make"
			var key := "Craft" if wanted == "craft" else "MakePart"
			if _asked.size() != 1:
				ok = _fail("one press on row %d submitted %d commands" % [i, _asked.size()])
				break
			var sent: Dictionary = _asked[0]
			var body: Dictionary = sent.get(key, {})
			var tag_key := "recipe" if key == "Craft" else "kind"
			var item_key := "item" if key == "Craft" else "material"
			# THE SENTENCE AND THE COMMAND MUST BE ABOUT THE SAME THING. This is the pairing the
			# fast path makes by INDEX (`offers[i]` against `_make.get_child(i)`): get that wrong
			# and a row would say one thing and do another, which no amount of correct wording
			# would save.
			var species: PackedStringArray = screen._sim.species_names()
			var named: String = species[int(offer.get("species", -1))]
			if body.is_empty():
				ok = _fail("row %d reading `%s` sent %s" % [i, line.text, JSON.stringify(sent)])
			elif not line.text.contains(named):
				ok = _fail("row %d acts on %s and its sentence says `%s`" % [i, named, line.text])
			elif JSON.stringify(body.get(tag_key)) != JSON.stringify(offer.get("tag")):
				ok = _fail("row %d sent tag %s for an offer tagged %s"
						% [i, JSON.stringify(body.get(tag_key)), JSON.stringify(offer.get("tag"))])
			elif int(body.get("count", -1)) != 1:
				ok = _fail("row %d sent count %d; a row is one batch and never a captured number"
						% [i, int(body.get("count", -1))])
			elif JSON.stringify(body.get(item_key)) != JSON.stringify(
					AssayActions.item_of_stack(offer)):
				ok = _fail("row %d sent item %s for an offer of %s"
						% [i, JSON.stringify(body.get(item_key)), JSON.stringify(offer)])
	screen.queue_free()
	return ok


## THE ROW THE REBUILD PUTS ON SCREEN IS ALREADY THE SIM'S SENTENCE, before any later refresh has
## touched it.
##
## **WHY THIS TEST EXISTS, AND IT IS A FAILURE OF MINE.** Every other test here reads the menu after
## several ticks, by which time `_refresh_make`'s FAST PATH has re-texted every row -- so I could
## replace the rebuild's text with `"craft ore"` composed in GDScript and all 143 tests passed. The
## fast path repairs it on the next frame, which is lucky rather than correct: the two paths agreeing
## is the thing to assert, and the rebuild is the one that pairs a sentence with a button.
func test_a_rebuilt_row_carries_the_sims_sentence_before_any_refresh() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var offers: Array = screen._sim.make_offers(screen._client.player_id)
		# FORCE THE REBUILD PATH and nothing else: a shape nothing can equal, then one refresh.
		screen._make_showing = "not a shape any pack has"
		screen._refresh_make()
		if offers.is_empty():
			ok = _fail("nothing to rebuild")
		elif screen._make.get_child_count() != offers.size():
			ok = _fail("the rebuild made %d rows for %d offers"
					% [screen._make.get_child_count(), offers.size()])
		else:
			for i in range(offers.size()):
				var wanted := String((offers[i] as Dictionary).get("line", ""))
				var line := screen._make.get_child(i).find_child(screen.MAKE_LINE,
						true, false) as Label
				if line == null:
					ok = _fail("rebuilt row %d has no sentence" % i)
					break
				if line.text != wanted:
					ok = _fail(("the rebuild wrote `%s` where the sim says `%s`. A sentence this "
							+ "client composed is one the sim cannot correct.")
							% [line.text, wanted])
					break
	screen.queue_free()
	return ok


## THE COUNT IN A ROW'S SENTENCE CLIMBS WITHOUT THE ROW BEING REBUILT. Every row says "N of your M",
## and M is the pack's count, which rises every mining cycle. The shape-signature path exists so a
## button under the pointer is not destroyed ten times a second, and the cost of that is a sentence
## that must be re-TEXTED instead -- which is the half that silently stopped working on the pack rows
## when an icon became child 0 (ASSA-46).
##
## THE SIGNATURE IS CHECKED NOT TO HAVE MOVED, or the rebuild path ran and this proves nothing.
func test_the_menu_re_texts_its_rows_as_the_pack_grows() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var first: Array = screen._sim.make_offers(screen._client.player_id)
		if first.is_empty():
			ok = _fail("nothing to make, so nothing to re-text")
		else:
			var shape_before: String = screen._make_showing
			var before := String((first[0] as Dictionary).get("line", ""))
			var mine := _find(screen._actions, "Mine")
			if mine == null:
				ok = _fail("no Mine button to grow the pack with")
			else:
				mine.pressed.emit()
				_tick(screen, 40)
				var after: Array = screen._sim.make_offers(screen._client.player_id)
				var wanted := String((after[0] as Dictionary).get("line", ""))
				var row: Node = screen._make.get_child(0)
				var label := row.find_child(screen.MAKE_LINE, true, false) as Label
				if wanted == before:
					ok = _fail("the sim's count did not move in 40 ticks, so this proves nothing")
				elif screen._make_showing != shape_before:
					ok = _fail("the menu's shape changed, so the rebuild path ran and the fast path "
							+ "is still untested")
				elif label == null:
					ok = _fail("the row has no %s label any more" % screen.MAKE_LINE)
				elif label.text != wanted:
					ok = _fail(("the row still reads `%s` while the sim says `%s`. The fast path "
							+ "stopped finding its label.") % [label.text, wanted])
	screen.queue_free()
	return ok


## Walk to a deposit of species `species` and mine it, so the pack can hold two species at once.
##
## NOT `starter_pair()[1]`, WHICH IS WHERE I WROTE THIS FIRST AND IT QUIETLY MINED THE SAME ROCK
## TWICE. The starter pair is (material, fuel) and nothing stops ONE species being both -- in the
## offline test world it is, so the helper walked back to the deposit it was already standing on and
## the pack still held one kind. The caller picks two distinct workable species instead.
func _mine_some_ore_of(screen: Node, species: int) -> bool:
	var deposit := AssaySessionPlan.nearest_of_species(screen._sim.deposits(), species,
			screen._my_tile(), 0)
	if deposit.is_empty():
		return _fail("no deposit of species %d has ore in it" % species)
	var centre: Vector2i = deposit.get("center", Vector2i.ZERO)
	_click(screen, centre, MOUSE_BUTTON_LEFT)
	_tick(screen, PATIENCE)
	if screen._my_tile() != centre:
		return _fail("walked to %s and stopped at %s" % [centre, screen._my_tile()])
	var mine := _find(screen._actions, "Mine")
	if mine == null:
		return _fail("no Mine button on the deposit")
	var pack_before: Array = screen._sim.inventory_of(screen._client.player_id)
	var kinds_before := pack_before.size()
	mine.pressed.emit()
	_tick(screen, 20)
	var stop := _find(screen._actions, "Stop")
	if stop != null:
		stop.pressed.emit()
		_tick(screen, 2)
	# DID IT ACTUALLY MINE. Pressing Mine and waiting is not evidence: a species can be refused for
	# hardness, and a helper that returns true anyway makes the test above fail about the wrong thing.
	var pack_after: Array = screen._sim.inventory_of(screen._client.player_id)
	if pack_after.size() <= kinds_before:
		var said := PackedStringArray()
		for line in screen._sim.event_lines(screen._client.player_id):
			said.append(String(line))
		return _fail("mined species %d at %s and the pack still holds %d kinds. %s"
				% [species, centre, kinds_before, " / ".join(said)])
	return true


## Every menu row's sentence containing `want` ("" for all of them), read off the named label.
func _make_lines_containing(screen: Node, want: String) -> Array:
	var out := []
	for row in screen._make.get_children():
		var line := row.find_child(screen.MAKE_LINE, true, false) as Label
		if line != null and (want == "" or line.text.contains(want)):
			out.append(line.text)
	return out


## EVERY BUTTON IN THE MENU SAYS THE SAME WORD, which is Maren's ruling stated as a property rather
## than as a style note. The defect she measured was a LABEL that was the only read and was ambiguous:
## two buttons both saying exactly `Craft smelter`, making smelters with different walls. A row's
## identity therefore lives in its sentence, and the only way that can rot is a label growing
## information again -- so this asserts labels carry NONE, with two species in the pack so there is
## something for a label to be wrong about.
func test_no_menu_button_label_carries_what_the_row_makes() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var labels := {}
		for row in screen._make.get_children():
			# AT ANY DEPTH, for the reason in `test_species_panel.gd`: this walked exactly two
			# levels, and ASSA-117 put the verb row one level further down inside the row's body.
			# Two nested loops over `get_children` is a shape assertion wearing a property's clothes.
			for button in row.find_children("*", "Button", true, false):
				labels[(button as Button).text] = true
		if labels.size() == 0:
			ok = _fail("the menu has no buttons at all: %s" % _text_of(screen._make))
		elif labels.size() > 1:
			ok = _fail("the menu's buttons say %s; a label that names the row is the bug Maren "
					% JSON.stringify(labels.keys()) + "measured on the board's own pack")
		elif not labels.has(AssayHud.make_button_text()):
			ok = _fail("the menu's button says %s" % JSON.stringify(labels.keys()))
	screen.queue_free()
	return ok


## MINE TWO DIFFERENT SPECIES OF ORE, so the pack holds two stacks.
##
## NOT `starter_pair()[0]` AND `[1]`: the pair is (material, fuel) and ONE species can be both, which
## in the offline test world it is -- so that reading walked back to the deposit it was already
## standing on and the pack still held one kind. The second species is any hand-minable one with ore
## left that is not the first.
func _mine_two_species(screen: Node) -> bool:
	if not _mine_some_ore(screen):
		return false
	var workable := AssaySessionPlan.workable_species(screen._sim.deposits(),
			screen._sim.species_sheets())
	if workable.size() < 2:
		return _fail("this world has %d hand-minable species with ore left, so two stacks of rock "
				% workable.size() + "cannot be reached at all")
	var carrying: Array = screen._sim.inventory_of(screen._client.player_id)
	var first := int((carrying[0] as Dictionary).get("species", -1))
	var second := -1
	for id in workable:
		if int(id) != first:
			second = int(id)
			break
	return _mine_some_ore_of(screen, second)


## MAREN'S WALLS CLAUSE ON A REAL PACK (ASSA-125), which is two claims a Rust test cannot make: that
## the field survives the binding, and that the row a player looks at carries it.
##
## **NOTHING HERE NAMES THE SMELTER**, deliberately, the way the dead-end test names no gear. It asks
## the SIM which rows carry a clause and then requires exactly those rows to show exactly that
## sentence. The day a second recipe output gets walls, this test covers it without being edited.
##
## A VARIANT FIELD IS INVISIBLE FROM RUST: I inverted `is_frame` in the binding on ASSA-103 and all
## 40 Rust tests stayed green, because nothing on that side reads a `VarDictionary` key. The guard
## for a field crossing into GDScript has to live in GDScript.
func test_a_menu_row_carries_the_sims_walls_clause_where_the_sim_puts_it() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_two_species(screen)
	if ok:
		var offers: Array = screen._sim.make_offers(screen._client.player_id)
		if screen._make.get_child_count() != offers.size():
			return _fail("%d rows for %d offers" % [screen._make.get_child_count(), offers.size()])
		var carried := 0
		for i in range(offers.size()):
			var offer: Dictionary = offers[i]
			var walls := String(offer.get("walls", ""))
			if walls == "":
				continue
			carried += 1
			var said := ""
			for child in screen._make.get_child(i).find_children("*", "Label", true, false):
				said += " " + (child as Label).text
			if not said.contains(walls):
				ok = _fail("row %d should carry the sim's clause `%s` and reads `%s`"
						% [i, walls, said])
				break
		# THE PREMISE, ASSERTED BEFORE THE ASSERTIONS OVER IT. A loop over rows that all have an
		# empty clause passes every check inside it, so an empty pack or a dropped binding field
		# would read as a green test about a sentence nobody drew.
		if ok and carried == 0:
			ok = _fail("no row carried a walls clause: a pack with two kinds of rock in it offers "
					+ "two smelters, so either the binding dropped the field or the sim stopped "
					+ "wording it")
	return ok


## ASSA-107: CHOOSING A PART PUTS IT IN THE MENU, AND CLEARING IT TAKES IT BACK OUT — through the
## real refresh path, with a real stack the sim named.
##
## `_choose_part` IS CALLED DIRECTLY AND THAT IS DELIBERATE. What this test is about is where the
## chosen parts are DRAWN and whether the two buttons there work; getting a real head into the pack
## costs the whole chain (mine, smelt, make part) and `tools/button_session.gd -- offline` already
## drives that end to end.
##
## **IT USED TO CHOOSE AN ORE STACK, AND ASSA-103 TOOK THAT AWAY.** A press the sim would refuse is
## now refused AT the press, so an ore never reaches the menu at all -- which is the next test. The
## stack here is a real mined one with its KIND swapped for a frame kind out of the sim's own
## catalogue: everything the block draws (species, grade, count, the sim's name) is still the sim's,
## and the one invented field is the one the refusal reads.
func test_choosing_a_part_draws_it_in_the_menu_and_clear_takes_it_back() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var stack: Dictionary = (screen._sim.inventory_of(screen._client.player_id)[0]
				as Dictionary).duplicate()
		var frame_kind := ""
		for entry in AssaySimHost.part_kinds():
			if bool((entry as Dictionary).get("is_frame", false)):
				frame_kind = String((entry as Dictionary).get("name", ""))
				break
		if frame_kind == "":
			screen.queue_free()
			return _fail("the sim's catalogue has no frame kind, so nothing can be chosen at all")
		stack["kind"] = frame_kind
		if _text_of(screen._assembling) != "":
			ok = _fail("something is in the assembling block before anything was chosen: %s"
					% _text_of(screen._assembling))
		else:
			screen._choose_part(stack)
			var said := _text_of(screen._assembling)
			if said == "":
				ok = _fail("chose a part and the menu shows nothing")
			# `building_line`'s OWN WORDING, not `stack_line`'s, and that is correct rather than
			# a near miss: a chosen part is ONE item, so the block names the item (`name`, the
			# sim's) where a pack row counts a stack. I asserted `stack_line` first and the test
			# caught me, not the code.
			elif not said.contains(String(stack.get("name", "?"))):
				ok = _fail("the block does not name what was chosen: `%s`" % said)
			elif _find(screen._assembling, "Assemble") == null:
				ok = _fail("no Assemble button beside the chosen parts: %s"
						% _labels_of(screen._assembling))
			elif _text_of(screen._actions).contains("assembling:"):
				ok = _fail("the chosen part is ALSO still drawn in the do section")
			else:
				var clear := _find(screen._assembling, "Clear")
				if clear == null:
					ok = _fail("no Clear button: %s" % _labels_of(screen._assembling))
				else:
					clear.pressed.emit()
					if _text_of(screen._assembling) != "":
						ok = _fail("pressed Clear and the block still reads `%s`"
								% _text_of(screen._assembling))
	screen.queue_free()
	return ok


## **A PRESS THE SIM WOULD REFUSE IS ANSWERED AT THE PRESS, IN THE SIM'S OWN SENTENCE** (Maren,
## ASSA-103, ruling 2) -- and never confirmed in the colour that means it worked.
##
## THE COST OF THE OLD BEHAVIOUR IS WHAT MAKES THIS WORTH A TEST. An impossible press was appended
## and confirmed in the JOINED colour; the refusal arrived at `Assemble`, which clears the whole
## sequence -- so the player lost every good press as well as the bad one, and nothing on screen had
## told them which press was the bad one.
##
## A REAL MINED STACK AND THE SIM'S OWN WORDING, compared against the binding's answer rather than
## against a sentence typed in here: an ore is not a part at all, which is the one fault reachable
## without the whole mine-smelt-make chain. `sim/tests/part_press.rs` is where the rule lives.
func test_a_press_the_sim_would_refuse_is_refused_at_the_press_not_at_assemble() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var ore: Dictionary = screen._sim.inventory_of(screen._client.player_id)[0]
		var refusal := AssaySimHost.part_press_refusal(PackedStringArray(),
				String(ore.get("kind", "")))
		if refusal == "":
			ok = _fail("the sim does not refuse an ore as a frame, so this test proves nothing")
		else:
			screen._choose_part(ore)
			var said: String = screen._status.text
			if said != refusal:
				ok = _fail("the screen says `%s`; the sim's own sentence is `%s`" % [said, refusal])
			# THE COLOUR IS HALF THE DEFECT. A refusal drawn in the colour that means "you are in" is a
			# confirmation, whatever the words say.
			elif screen._status.modulate != AssayHud.status_color(AssayHud.Say.FAILED):
				ok = _fail("the refusal is drawn in %s, not the failed colour"
						% screen._status.modulate)
			# AND NOTHING LANDED: the old code appended first and the menu drew it.
			elif not screen._building.is_empty():
				ok = _fail("the refused press still went into the assembly: %s" % [screen._building])
			elif _text_of(screen._assembling) != "":
				ok = _fail("the refused press is drawn in the menu: %s"
						% _text_of(screen._assembling))
			# **AND THE PARTS ALREADY CHOSEN REACH THE SIM, WHICH THE FIRST HALF CANNOT SHOW.** With
			# nothing chosen the `chosen` array is empty either way, so a client that never passed it
			# would pass everything above. A second frame on a frame is Maren's other half of the swap:
			# the rows that say `Frame` are exactly the ones a frame-first design must refuse.
			else:
				var frame := _a_frame_stack(ore)
				if frame.is_empty():
					ok = _fail("the sim's catalogue has no frame kind")
				else:
					screen._choose_part(frame)
					if screen._building.size() != 1:
						ok = _fail("a frame was refused as the first part: %s" % screen._status.text)
					else:
						var second := AssaySimHost.part_press_refusal(
								PackedStringArray([String(frame.get("kind", ""))]),
								String(frame.get("kind", "")))
						if second == "":
							ok = _fail("the sim allows two frames, so this half proves nothing")
						else:
							screen._choose_part(frame)
							if screen._building.size() != 1:
								ok = _fail("a second frame was accepted; the parts already chosen "
										+ "never reached the sim")
							elif screen._status.text != second:
								ok = _fail("the second frame says `%s`, the sim says `%s`"
										% [screen._status.text, second])
	screen.queue_free()
	return ok


## A REAL MINED STACK WITH ITS KIND SWAPPED FOR A FRAME KIND OUT OF THE SIM'S CATALOGUE. Everything
## drawn from it -- species, grade, count, the sim's name -- stays the sim's; the one invented field
## is the one the refusal reads. Getting a real frame into a pack costs the whole mine-smelt-make
## chain, which `tools/button_session.gd -- offline` drives end to end instead.
func _a_frame_stack(like: Dictionary) -> Dictionary:
	for entry in AssaySimHost.part_kinds():
		var part: Dictionary = entry
		if bool(part.get("is_frame", false)):
			var stack := like.duplicate()
			stack["kind"] = String(part.get("name", ""))
			return stack
	return {}


## THE ICON ON A CRAFTING ROW IS WHAT THE ROW MAKES, NOT WHAT IT SPENDS (Maren's ruling, ASSA-117
## box 4). She found it by hashing the plates in `04-pack.png`: five rows, one picture -- the refined
## slab -- because `_icon_box(offer)` read the offer's own `kind`/`species`/`grade`, which are the
## INPUT. In a menu whose only job is choosing between things, the icon distinguished nothing.
##
## **THE LEVER IS MAREN'S PROPERTY, NOT AN EQUALITY WITH `icon_for`.** Two rows that spend the SAME
## stack and make DIFFERENT things may not draw the same picture. That is the defect stated as
## something the drawn window must be true of, and it fails on the shipped code by construction:
## every row off one stack drew that stack. Nothing in it mentions which argument `_rebuild_make`
## passes, so it cannot be satisfied by the bug coming back in another shape.
##
## The second half -- each row's picture IS its output's -- is admitted construction (it compares
## against the same `icon_for` the rebuild calls) and is here only to stop "any picture that is not
## the input" from passing. The first half is the evidence.
##
## **AND IT REFUSES A VERDICT RATHER THAN PASSING VACUOUSLY.** With a fixture whose rows all make the
## same thing, or whose outputs share one sheet row, the property is true of the bug too. So the
## fixture is required to contain a pair that can tell them apart, and the test FAILS saying so if it
## does not -- the shape of the two mutations that walked through my menu tests on 10-02 was exactly
## a fixture that could not distinguish right from wrong.
func test_a_crafting_row_draws_what_it_makes_not_what_it_spends() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var offers: Array = screen._sim.make_offers(screen._client.player_id)
		var rows: Array = screen._make.get_children()
		if offers.is_empty():
			ok = _fail("a pack with ore in it produced no crafting offers at all")
		elif rows.size() != offers.size():
			ok = _fail("%d offers and %d rows, so nothing below pairs" % [offers.size(), rows.size()])
		else:
			# WHAT IS ON SCREEN, read off the row rather than recomputed: the AtlasTexture the
			# TextureRect is actually holding, found by CLASS because a row is [icon?][VBox] and the
			# icon is wrapped in a Panel when the pipeline ships a plate.
			var drawn := {}
			for i in range(rows.size()):
				drawn[i] = _drawn_icon_id(rows[i])
			# THE PAIR THAT MAKES THE ASSERTION ABLE TO FAIL: same input stack, different output,
			# and the two outputs must be drawable as different pictures.
			var pairs := 0
			for i in range(offers.size()):
				var a: Dictionary = offers[i]
				for j in range(i + 1, offers.size()):
					var b: Dictionary = offers[j]
					if _input_of(a) != _input_of(b):
						continue
					var makes_a: Dictionary = a.get("makes", {})
					var makes_b: Dictionary = b.get("makes", {})
					if makes_a == makes_b or makes_a.is_empty() or makes_b.is_empty():
						continue
					var want_a := _icon_id(AssaySprites.icon_for(makes_a))
					var want_b := _icon_id(AssaySprites.icon_for(makes_b))
					if want_a == "" or want_b == "" or want_a == want_b:
						continue
					pairs += 1
					if drawn[i] == drawn[j]:
						ok = _fail(("two rows spend `%s` and make `%s` and `%s`, and both draw %s"
								+ " -- the icon is the input") % [_input_of(a),
								makes_a.get("kind"), makes_b.get("kind"), drawn[i]])
						break
				if not ok:
					break
			if ok and pairs == 0:
				ok = _fail(("NO VERDICT: no two rows in this pack spend one stack, make different"
						+ " things and have distinguishable art, so the property is true of the bug"
						+ " as well. Offers: %s") % [_inputs_and_outputs(offers)])
			if ok:
				for i in range(offers.size()):
					var makes: Dictionary = (offers[i] as Dictionary).get("makes", {})
					var want := _icon_id(AssaySprites.icon_for(makes))
					if drawn[i] != want:
						ok = _fail("row %d makes `%s` and draws %s, the output's art is %s"
								% [i, makes.get("kind", "nothing"), drawn[i], want])
						break
	screen.queue_free()
	return ok


## The icon a row is ACTUALLY drawing, as a comparable string. Empty when the row draws none.
func _drawn_icon_id(row: Node) -> String:
	for art in row.find_children("*", "TextureRect", true, false):
		return _icon_id((art as TextureRect).texture as AtlasTexture)
	return ""


## An AtlasTexture's identity: which sheet and which region of it. Two calls to `icon_for` return
## different objects for the same item, so `==` on the textures themselves answers nothing.
func _icon_id(icon: AtlasTexture) -> String:
	if icon == null or icon.atlas == null:
		return ""
	return "%s%s" % [icon.atlas.resource_path.get_file(), icon.region]


func _input_of(offer: Dictionary) -> String:
	return "%s/%d/%s" % [String(offer.get("kind", "?")), int(offer.get("species", -1)),
			String(offer.get("grade", "?"))]


func _inputs_and_outputs(offers: Array) -> String:
	var out := PackedStringArray()
	for entry in offers:
		var offer: Dictionary = entry
		var makes: Dictionary = offer.get("makes", {})
		out.append("%s -> %s" % [_input_of(offer), String(makes.get("kind", "nothing"))])
	return " | ".join(out)
