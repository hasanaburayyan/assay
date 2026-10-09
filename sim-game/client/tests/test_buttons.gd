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

## **ONE `BODY` ROW.** The number Maren's `BUILD_COMMIT_BAR` is six of (its own arithmetic:
## `6 x 18 = 108`, plus the 6 px inset = 114), and the theme's `BODY` is a 13 pt face on an 18 px
## line. It is a LITERAL on purpose: the thing it guards against is a slot label that is 126 px tall
## instead of one row, and a bound derived from the same engine call the subject uses would move
## with the defect. The 1x shot is its cross-check (ASSA-362).
const BODY_ROW_PX := 18.0

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
##
## **IT IS ALSO ASSA-366'S CONTROL, AND IT COULD NOT FAIL UNTIL THAT ITEM STRENGTHENED IT.** Opening a
## machine's menu now AIMS at that machine, which is two assignments in `_open_machine_menu`; the same
## two lines written one level up, in `_unhandled_input` before the branches, would aim at every tile a
## player clicked -- including the one they only meant to walk to. This test asked what the left click
## SUBMITTED and never what it left the cursor on, so that mutation walked straight past it. The clause
## below is the one that reddens: on an EMPTY tile, left still only walks.
func test_a_left_click_walks_and_a_right_click_chooses_the_target() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	var spawn: Vector2i = screen._sim.spawn_tile()
	var walk_to := spawn + Vector2i(3, 2)
	# NOTHING IS AIMED AT YET, which is what makes the clause below a control rather than a coincidence.
	if screen._targeted:
		screen.queue_free()
		return _fail("a fresh screen already aims at %s" % screen._target_tile())
	_asked.clear()
	_click(screen, walk_to, MOUSE_BUTTON_LEFT)
	if _asked.size() != 1 or _asked[0] != AssayActions.move_to(walk_to):
		ok = _fail("a left click on %s asked for %s" % [walk_to, _asked])
	elif screen._targeted:
		# `_targeted` AND NOT THE TILE, because `_target_tile()` answers `_my_tile()` while nothing is
		# chosen -- and this walk moves `_my_tile()`, so a tile comparison here would be a race.
		ok = _fail(("a left click on the empty tile %s aimed the buttons at %s: an empty tile keeps "
				+ "today's split exactly (ASSA-316 ruling 8, kept by ASSA-366)")
				% [walk_to, screen._target_tile()])
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
	var stack := _a_smelter_in_the_pack(screen)
	var ok := not stack.is_empty()
	if ok:
		var play := AssayButtonPlay.new(screen, 0)
		_asked.clear()
		# **`Place` ON A SMELTER, BECAUSE `Fuel` IS THE ROW THAT NO LONGER EXISTS** (ASSA-331). This
		# pressed `Fuel` -- "the one every ore row carries whatever the sheet says" -- until Maren ruled
		# the insert pair off the pack. `Place` is now the only verb a fresh world's pack can offer, which
		# makes it the only thing this witness can be built on; the tool's INSERT path is a menu press and
		# is witnessed by `test_the_session_tool_can_put_ore_in_a_machine_through_its_menu`.
		if not play._press_on_stack(String(stack.get("kind", "")),
				int(stack.get("species", -1)), "Place"):
			ok = _fail("AssayButtonPlay found no `Place` on the row reading `%s`; the pack "
					% AssayHud.stack_line(stack) + "shows %s" % _text_of(screen._carrying))
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
			# **AND THE CHAIN LEAVES NO SCREEN STANDING OVER THE MAP.** `Build` does not close the
			# build screen -- deliberately, so a person can make a second batch -- and this driver
			# makes six parts and then hands the window to a SHOT. Between #432 and this assertion
			# every whole-world frame taken after a played chain was a picture of the make screen:
			# ASSA-273's re-shoot came back with ZERO pixels of any map mark on either seed, and
			# nothing failed, because a chain that reports FINISHED is the only thing we check.
			# Pressing is not enough to assert here; what matters is the state the window is left in.
			elif screen._build_screen_open() or screen._build_box.visible:
				ok = _fail(("the session tool left the build screen open after `%s`, so every "
						+ "picture taken after a played chain is of that screen and not of the map "
						+ "(open=%s visible=%s)") % [AssayHud.build_button_text(),
						screen._build_screen_open(), screen._build_box.visible])
	screen.queue_free()
	return ok


## **THE SESSION TOOL'S INSERT, WHICH IS NOW TWO GESTURES AND A LABEL IT DOES NOT OWN** (ASSA-331).
##
## SAME WITNESS AS THE TEST ABOVE AND THE SAME REASON (ASSA-62): nothing in CI runs the session, so a
## tool that can no longer play the game fails nowhere. Deleting the pack row's `Fuel` moved the loop's
## two insert beats onto the machine menu, which means a CLICK that must open the right machine's menu
## and a button whose label carries a count and a slot -- three things that can rot independently.
##
## IT ASSERTS THE COMMAND AND THE CLEAN-UP. The command, because a tool that pressed something harmless
## would look identical; the clean-up, because the loop's next stage walks, and a dismissing left click
## is consumed (ruling 7) -- so a menu the tool left open costs the walk its click.
func test_the_session_tool_can_put_ore_in_a_machine_through_its_menu() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var at := _a_placed_smelter(screen)
	if at < 0:
		screen.queue_free()
		return false
	var ok := true
	var ore := _stack_of(screen, "ore")
	var held := _counted(screen, ore)
	var play := AssayButtonPlay.new(screen, 0)
	# THE TOOL'S OWN FIELD FOR WHERE ITS SMELTER IS, set the way its own `_placing` stage sets it.
	play._smelter_at = screen._target_tile()
	_asked.clear()
	play._press_insert_once("ore in", "ore", int(ore.get("species", -1)), AssayActions.SLOT_INPUT)
	var want: Variant = AssayActions.insert(at, AssayActions.SLOT_INPUT,
			AssayActions.item_of_stack(ore), held)
	if _asked.size() != 1:
		ok = _fail("AssayButtonPlay's insert submitted %s, not one Insert; it pressed %s"
				% [_asked, play.pressed])
	elif _asked[0] != want:
		ok = _fail("AssayButtonPlay's insert submitted %s, not %s" % [_asked[0], want])
	elif play.pressed.is_empty():
		ok = _fail("the tool inserted and recorded no press")
	elif screen._menu_at != -1:
		ok = _fail("the tool left the menu on %d open, so the next walk loses its click"
				% screen._menu_at)
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
##
## **A SMELTER IS CRAFTED FIRST SINCE ASSA-331, AND THE REASON IS THIS TEST'S OWN CONTROL.** With the
## insert pair deleted, two ore rows carry no buttons between them -- so every press this walk makes
## would be zero presses, and `presses == 0` below would (rightly) call that measuring nothing. The
## smelter item is the one stack a fresh pack can hold that still has a verb.
func test_no_pack_row_offers_a_verb_that_makes_something() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_two_species(screen)
	if ok and _a_smelter_in_the_pack(screen).is_empty():
		ok = false
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
		var button := _build_button_for(screen, "smelter")
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


## **NO PRESS ON A PACK ROW IS ANSWERED BY THIS CLIENT SAYING IT CANNOT BUILD THE COMMAND** (ASSA-331,
## Maren's ruling: the insert verbs are deleted, not re-targeted).
##
## **THIS REPLACES A TEST OF THE DEFECT ITSELF**, which asserted that `Fuel` with no building under the
## placement cursor submitted nothing and said *"nothing to insert into"*. That was honest behaviour for
## a button that could be aimed; ruling 8 gave both mouse buttons on a building to its menu, so the
## cursor can no longer be put on one and every press of that button was the refusal. A test of a
## sentence a control only ever says is a test that the control is useless.
##
## **THE INVARIANT IS THE GESTURE AND NOT THE LAYOUT:** on the rows where the pair used to live -- the
## ones holding something the SIM says a building eats -- every button is pressed, and a press must
## either submit a command or choose a part. A press whose whole effect is a sentence is the defect.
##
## BOUNDED: the row has to EXIST or this measured nothing, and it is the ore row, which is the one row
## the deleted buttons were drawn on. The loop is deliberately restricted to those rows rather than the
## whole pack: `Mount` on a part with no frame chosen is refused by `AssayAssembly`'s own reading
## (ASSA-102) and would fail this rule for a reason that is not this item's.
func test_no_pack_row_press_is_answered_by_the_client_refusing_to_aim() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	var at := _a_placed_smelter(screen)
	if at < 0:
		screen.queue_free()
		return false
	# A REAL PLAYER'S CURSOR, MOVED BY A REAL GESTURE: a right click on my own tile, which is where the
	# target starts and the one tile every player has. The smelter it just placed is off the cursor now,
	# which is the state every press below is made in.
	_click(screen, screen._my_tile(), MOUSE_BUTTON_RIGHT)
	var recipes := AssaySimHost.recipes()
	var rows := 0
	for entry in screen._sim.inventory_of(screen._client.player_id):
		var stack: Dictionary = entry
		if AssayHud.insert_slots(stack, recipes).is_empty():
			continue
		var row := _row_for(screen, AssayHud.stack_line(stack))
		if row == null:
			ok = _fail("the sim says a building eats `%s` and the pack draws no row for it"
					% AssayHud.stack_line(stack))
			break
		rows += 1
		for button in _buttons_under(row):
			var pressable: Button = button
			_asked.clear()
			var chosen: int = screen._building.size()
			pressable.pressed.emit()
			if not _asked.is_empty() or screen._building.size() != chosen:
				continue
			ok = _fail(("`%s` on the row reading `%s` submitted nothing and chose nothing, with the "
					+ "cursor on %s: its whole effect was the sentence `%s`")
					% [pressable.text, AssayHud.stack_line(stack), screen._target_tile(),
							screen._status.text])
			break
	if ok and rows == 0:
		ok = _fail("no pack row holds anything a building eats, so nothing here was measured: %s"
				% _labels_of(screen._carrying))
	screen.queue_free()
	return ok


## NO BUTTON MAY CARRY A COUNT IT READ EARLIER, AND THE PROOF HAS TO REACH THE SUBMITTED COMMAND
## (ASSA-55).
##
## A menu only rebuilds when the PACK'S SHAPE changes (`_menu_showing`), so a stack's count climbs under
## a slot button that is never rebuilt -- and `put all N` sends the whole stack. The first version of
## this path captured the count in the closure: the button-driven session pressed `Fuel` on a row
## reading 12 and inserted 2, and the fire went out mid-stack.
##
## **IT WAS A PACK ROW'S `Fuel` UNTIL ASSA-331 AND IS NOW A MENU'S SLOT BUTTON.** Maren deleted the
## pack-row pair; the rule did not go with it, because the surface it moved to caches rows the same way.
## The staleness is now VISIBLE in the evidence rather than inferred: the count is written on the
## button, so finding the button under its OLD label is how this test knows the menu did not rebuild,
## and the submitted number still has to be the one the sim says NOW.
##
## So this needs all three at once, which is why it builds a smelter: an open menu on a real machine, a
## count that has MOVED since the button was made, and the SAME button object still on screen.
##
## THE EXPECTED NUMBER IS READ OFF THE SIM, NOT THROUGH `AssayInventory.held`. That function is
## what `_insert_into` itself calls, and a test that computes its expectation with the code under test
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
		# THE MENU IS OPENED BY A REAL CLICK ON THE MACHINE, which is Maren's ruling 7 and the only way
		# in: `_a_placed_smelter` leaves the cursor on the smelter it just placed.
		var spot: Vector2i = screen._target_tile()
		_click(screen, spot, MOUSE_BUTTON_LEFT)
		var stack := _stack_of(screen, "ore")
		var before := _counted(screen, stack)
		var label := AssayHud.insert_label(before, String(stack.get("name", "?")),
				AssayActions.SLOT_FUEL)
		var button := _find(screen._menu_box, label)
		var mine := _find(screen._actions, "Mine")
		if screen._menu_at != at:
			ok = _fail("a left click on %s opened a menu on %d, not the smelter %d"
					% [spot, screen._menu_at, at])
		elif button == null:
			ok = _fail("no `%s` button in the menu on the smelter: %s"
					% [label, _labels_of(screen._menu_box)])
		elif mine == null:
			ok = _fail("no `Mine` button to start the count climbing again")
		else:
			# Mining again under a menu that is NOT rebuilt: crafting the smelter took the activity, so
			# the swinging has to be asked for a second time.
			mine.pressed.emit()
			_tick(screen, 40)
			var now := _counted(screen, stack)
			if now <= before:
				ok = _fail("mined 40 more ticks and hold %d of the ore, was %d; nothing stale to catch"
						% [now, before])
			elif _find(screen._menu_box, label) != button:
				ok = _fail(("the menu rebuilt -- `%s` is no longer the button it was -- so a stale count "
						+ "could not have survived on it") % label)
			else:
				_asked.clear()
				button.pressed.emit()
				var want: Variant = AssayActions.insert(at, AssayActions.SLOT_FUEL,
						AssayActions.item_of_stack(stack), now)
				if _asked.size() != 1:
					ok = _fail("`%s` on the menu's smelter submitted %s, not one Insert" % [label, _asked])
				elif _asked[0] != want:
					# The stale number is the one WRITTEN ON THE BUTTON, which this test read as `before`
					# -- so for once the closure's value is knowable and is named in the failure.
					ok = _fail(("`%s` submitted %s, not %s: the count on the label, read when the menu "
							+ "was built. The sim said %d then and says %d now.")
							% [label, _asked[0], want, before, now])
				elif AssaySimHost.command_echo(_asked[0]) == "":
					ok = _fail("Insert submitted %s, which serde refuses" % [_asked[0]])
				# **THE "NUMBER TOLD" CLAUSE IS GONE BECAUSE THE SENTENCE IS** (ASSA-239). It read
				# `said.contains(str(now))` on `_act`'s echo, with the note "`_act`'s sentence is the
				# only report the player gets, and a true command under a stale sentence is still a
				# lie". Maren's ruling on ASSA-237 deleted that echo -- an accepted command now says
				# nothing, because what happened arrives as the sim's own event in the log and a
				# submission stamped with a tick is not news.
				#
				# **NOTHING THIS TEST EXISTS FOR IS LOST, AND THAT IS THE POINT:** ASSA-55's invariant
				# is that the COMMAND carries the count read at the press, which `_asked[0] != want`
				# above asserts directly against the sim's own total. The deleted clause guarded a
				# sentence disagreeing with that command, and a sentence that is never written cannot
				# disagree with anything. If the echo ever comes back, this clause comes back with it.
	screen.queue_free()
	return ok


## A SMELTER THAT REALLY STANDS IN THE WORLD, MADE THE WAY A PLAYER MAKES ONE, and targeted. Returns
## its `BuildingId`, or -1 having already failed the run.
##
## BUILT, NOT PLANTED. The menu reads its machine out of `tile_at` like everything else, so a world
## with a building written into it by the harness would be testing the harness. Every stage here is a
## press or a click: mine, `Craft smelter`, right-click a free 2x2, `Place`. The right-click that
## chooses where it goes is also what targets it afterwards -- which is worth leaning on here, and is
## **all that is left of the mechanism ASSA-37 gave to Place, Insert and Take together**: Take went to
## the machine menu with ASSA-316's ruling 3 and Insert with ASSA-331, so Place is the last verb on it.
func _a_placed_smelter(screen: Node) -> int:
	var smelter := _a_smelter_in_the_pack(screen)
	if smelter.is_empty():
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


## A SMELTER IN THE PACK, crafted through the real buttons, or {} having already failed the run.
##
## **SPLIT OUT OF `_a_placed_smelter` BY ASSA-331**, because two tests now need a pack row that still
## carries a verb at all: with the insert pair deleted, an ore row has NO buttons, so a test that
## presses every button on every row would press nothing -- and both of those tests have a control that
## catches exactly that. A smelter item is the one thing a fresh world can carry with a verb on it.
func _a_smelter_in_the_pack(screen: Node) -> Dictionary:
	if not _mine_some_ore(screen):
		return {}
	# **THE STACK UNDER YOUR FEET, NOT THE PACK'S FIRST ONE.** `Mine` acts on the tile you STAND on
	# (`step.rs:124`, `NotOnDeposit`), so the count that climbs below is the species of the deposit
	# beneath us -- and after `_mine_two_species` that is not `_stack_of(screen, "ore")`. Reading the
	# first stack cost me a red suite: it sat at 5 while twelve batches of mining filled the other one.
	var standing: Variant = screen._sim.tile_at(screen._my_tile()).get("deposit")
	var here := -1 if standing == null else int((standing as Dictionary).get("species", -1))
	var ore := _stack_of(screen, "ore")
	for entry in screen._sim.inventory_of(screen._client.player_id):
		var stack: Dictionary = entry
		if String(stack.get("kind", "")) == "ore" and int(stack.get("species", -1)) == here:
			ore = stack
			break
	if ore.is_empty():
		_fail("mined and hold no ore stack to craft from")
		return {}
	# ENOUGH THAT THE ORE ROW SURVIVES THE CRAFT. Five ore go into the smelter; if that empties the
	# row, the pack's shape changes, every button on it is freed, and there is no stale count to have.
	#
	# **AND ENOUGH FOR A SECOND BATCH TO STILL BE OFFERED** (ASSA-331): `test_the_session_tool_can_press
	# _a_pack_row` now crafts a smelter before pressing `Place` on it, and then goes on to press the
	# crafting menu's own `Smelter` row -- which is a row about ore the first craft had already spent.
	var want := AssayDemoPlan.SMELTER_ORE * 2 + 4
	for _i in range(12):
		if _counted(screen, ore) >= want:
			break
		_tick(screen, 20)
	if _counted(screen, ore) < want:
		_fail("mined and hold %d of %s, want %d before crafting a smelter"
				% [_counted(screen, ore), AssayHud.stack_line(ore), want])
		return {}
	# FROM THE CRAFTING MENU SINCE ASSA-86: the pack row carries only the verbs that MOVE an item.
	var craft := _build_button_for(screen, "smelter")
	if craft == null:
		_fail("no menu row offers a smelter: %s" % _text_of(screen._make))
		return {}
	craft.pressed.emit()
	for _i in range(6):
		if not _stack_of(screen, "smelter").is_empty():
			break
		_tick(screen, AssayDemoPlan.CRAFT_TICKS)
	var smelter := _stack_of(screen, "smelter")
	if smelter.is_empty():
		_fail("pressed `Craft smelter` and no smelter arrived in %d ticks"
				% (6 * AssayDemoPlan.CRAFT_TICKS))
	return smelter


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
## **MOVED OUT OF THE CRAFTING MENU AND INTO THE CHROME (ASSA-133, Maren's ruling 1), AND THIS TEST
## MOVED WITH IT RATHER THAN BEING LOOSENED.** It has now been in three places, and each move made it
## assert more: the `do` section (where the sentence competed with Mine and Assay), the head of the
## crafting menu (ASSA-88), and now the chrome's `running` block beside `stopped`.
##
## WHAT THE MOVE BUYS, AND WHY THE FOLD CLAUSE IS STILL HERE RATHER THAN DELETED AS TRIVIAL. The
## countdown is no longer in the scroll box at all, so "collapsing the menu cannot hide it" is now
## structurally impossible rather than arranged. A test that cannot fail is worth keeping only if it
## says so, so: this clause can no longer fail by placement, and it is kept because what it really
## guards is that `_show_make` never learns to reach the countdown again.
func test_a_running_craft_is_named_in_the_chrome_and_outlives_the_menu() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok and _running_text(screen).contains("making "):
		ok = _fail("the panel claimed a craft before one was started: %s" % _running_text(screen))
	if ok:
		var button := _build_button_for(screen, "smelter")
		if button == null:
			ok = _fail("no menu row offers a smelter: %s" % _text_of(screen._make))
		else:
			button.pressed.emit()
			_tick(screen, 2)
			var during := _running_text(screen)
			# TWO ACTIVITIES AT ONCE, WHICH IS THE WHOLE REASON THE LIST IS A LIST (ASSA-95).
			# `_mine_some_ore` leaves the mining RUNNING and `step` never clears it for a craft, so
			# this is the state a single-activity readout would misreport -- it would say the mining
			# had stopped. Asserted here rather than in its own test because this is the one place
			# the suite already has both running, and a fixture built to have one activity would be
			# proving the easy half.
			if not during.contains("mining "):
				ok = _fail(("a craft started while the mining ran on, and the block names only: %s. "
						+ "A list that silently omits a kind teaches that it is complete.") % during)
			if not screen._running_box.visible:
				ok = _fail("a craft is running and the running block is hidden: `%s`" % during)
			elif not during.contains("making ") or not during.contains("ticks left"):
				ok = _fail(("a craft is running and the chrome does not say so: %s. The ticks come "
						+ "from the sim; this client only prints them.") % during)
			else:
				# THE CLAUSE MAREN ADDED ON ASSA-88. The menu folds; the condition does not.
				screen._show_make(false)
				screen._refresh()
				if not _running_text(screen).contains("making "):
					ok = _fail("folding the menu away hid the running craft, which lasts until it "
							+ "finishes whatever the menu is doing")
				elif screen._make.visible:
					ok = _fail("_show_make(false) left the rows visible, so this proves nothing")
				else:
					screen._show_make(true)
					# AND IT GOES AWAY. A line that appears and never clears is worse than no line:
					# it would say a craft is running forever, which is the same lie the silence was.
					_tick(screen, PATIENCE)
					if _running_text(screen).contains("making "):
						ok = _fail("the craft finished and the panel still claims one: %s"
								% _running_text(screen))
					# AND THE BLOCK IS NOT ASSERTED EMPTY HERE, WHICH IS A CORRECTION OF MY OWN
					# TEST. I wrote `elif screen._running_box.visible: fail` and it reddened with
					# `mining Minyte` -- because `_mine_some_ore` above leaves the mining RUNNING,
					# and `step` never clears it for a craft. The block is right and the assertion
					# was wrong: that is the plural list doing exactly its job, and asserting the
					# block empties when one of three activities ends would have pinned the bug
					# ASSA-95 exists to prevent. The empty case is covered where it is honestly
					# empty, in test_main_screen's chrome-blocks test.
	screen.queue_free()
	return ok


## THE CHROME'S RUNNING LINES AS ONE STRING, or "" when the block is hidden. Reads the LINES box
## rather than the whole block so the client's own "running" heading cannot satisfy an assertion
## about the sim's sentences.
func _running_text(screen: Node) -> String:
	if not is_instance_valid(screen._running_box) or not screen._running_box.visible:
		return ""
	if not is_instance_valid(screen._running_lines):
		return ""
	return _text_of(screen._running_lines)


## THE MENU ROW THAT OFFERS `want`, by the SIM'S OWN SENTENCE and never by a button label: every
## row's button says the same word on purpose (Maren's ruling), so the row is found by what it says
## it makes and the button is then the one inside it.
## THE ROW'S OWN CONTROL, which since ASSA-328 only OPENS the build screen. For tests about the row:
## its label, whether it is pressable, where it sits.
func _make_launcher_for(screen: Node, want: String) -> Button:
	for row in screen._make.get_children():
		var line := row.find_child(screen.MAKE_LINE, true, false) as Label
		if line != null and line.text.contains(want):
			return _find(row, AssayHud.make_launch_text())
	return null


## **CRAFTING IS TWO GESTURES NOW, AND THIS IS WHERE THE SUITE LEARNS THEM** (ASSA-328; Maren's §2
## price: *"there is no one-click make any more"*).
##
## **IT RETURNS THE SECOND BUTTON, NOT THE FIRST, so every caller that pressed one button and expected
## a craft still presses one button and gets a craft.** That is deliberate: the three callers are
## about what the SIM does with a press (a smelter lands in the pack, a countdown starts, a machine
## gets placed), and rewriting each of them to know about a screen would make three tests about this
## item instead of one helper.
##
## **AND IT GOES THROUGH THE REAL CONTROLS, NOT `_open_build_screen`.** Pressing the row's `Make…` is
## what a player does; calling the open function directly would leave the row's one control untested
## by every one of these paths, which is exactly how a launcher that opens nothing would ship green.
func _build_button_for(screen: Node, want: String) -> Button:
	var launcher := _make_launcher_for(screen, want)
	if launcher == null:
		return null
	launcher.pressed.emit()
	return _find(screen._build_box, AssayHud.build_button_text())


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


## **AND IT REACHES THAT LINE WITH THE LOG OPEN TOO, WHICH IS THE HALF NOTHING HELD** (ASSA-116 box 2
## as the Game Director restated it on 2026-10-08: *"a refusal reaches the always-visible line whether
## or not the log is open"*).
##
## `_remember_events` already says this in writing — *"NOT CONDITIONAL ON THE TOGGLE... a notice that
## only fired while hidden would be a notice whose test passes or fails on the state of a different
## control"* — and a comment was the whole of what held it. The arm above presses Mine with the log
## folded away, so **nothing would have gone red if the notice had been wrapped in `if not
## _log.visible`**: half of the box rested on a docstring. I would rather not tick a box on prose I
## wrote myself, which is the same objection I raised against `hud_probe` never running in CI.
##
## THE LOG IS OPENED THROUGH ITS OWN TOGGLE, not by calling `_show_log`, because the state this claim
## is about is the one a player can put the screen into.
##
## The assertions are the arm above's, for the reason given there — the relationship between the two
## surfaces, never `status == attention_lines[-1]`, which would pass by construction — plus the one
## this state adds: the log that was open stays open, so a refusal neither needs nor causes a fold.
func test_a_refused_press_reaches_the_status_line_while_the_log_is_open() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var joined_said: String = screen._status.text
	var ok := true
	screen._log_toggle.pressed.emit()
	if not screen._log.visible:
		ok = _fail("pressing the log's own toggle did not open it, so this test proves nothing")
		screen.queue_free()
		return ok
	var mine := _find(screen._actions, "Mine")
	if mine == null:
		ok = _fail("no Mine button in the `do` section")
		screen.queue_free()
		return ok
	# Same premise as the hidden arm, asserted rather than assumed: spawn is not a deposit, so Mine is
	# a refusal the sim produces and not a mining cycle.
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
		ok = _fail(("the sim refused a press with the log OPEN and the always-visible line still "
				+ "reads '%s'. A notice that only fires while the log is folded away is a notice "
				+ "conditional on a different control") % said)
	elif said.strip_edges() == "":
		ok = _fail("the status line was blanked rather than written")
	elif not log_text.contains(said):
		ok = _fail(("the status line says '%s', which is not one of the log's own sentences: '%s'. "
				+ "A client that words its own refusal is a second describer.") % [said, log_text])
	elif not screen._log.visible:
		ok = _fail("showing the player a refusal folded the log they had opened")
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
		# **AN EMPTY SAMPLE IS THE RESTING STATE NOW, NOT A DEFECT** (ASSA-245). This loop used to fail
		# on a blank line, because when it was written the status line always held something (offline
		# play's own `offline, so no hash report was sent` note, which the docstring above names) and a
		# blank could only mean the line had been wiped. Since ASSA-239/245 a healthy screen IS quiet:
		# a `Say.JOINED` sentence ages out after `SAYING_DWELL_TICKS`, and that note no longer reaches
		# the status line at all once you are in a world. So blanks are skipped rather than failed --
		# **an empty line promotes nothing, which is this test's whole claim** -- and the guard below
		# is what stops the skip making the test vacuous.
		var read := 0
		for said in samples:
			if said.strip_edges() == "":
				continue
			read += 1
			if log_text.contains(said):
				ok = _fail(("walking promoted one of the log's own sentences onto the "
						+ "always-visible line: '%s'. Successes are the log's; that surface holds "
						+ "one line and it is for what went wrong.") % said)
				break
		# THE GUARD THE SKIP ABOVE NEEDS. A walk says `walking to x, y` through `_on_map_click`, so at
		# least one sample must carry something; if every one were blank this test would be reading an
		# empty surface twenty times and calling it proof.
		if ok and read == 0:
			ok = _fail("every one of the %d samples was blank, so nothing was checked for promotion"
					% samples.size())
	screen.queue_free()
	return ok


## WHAT THE LOG KEEPS IS THE SIM'S OWN SENTENCE, WITH NOTHING THIS CLIENT ADDED TO IT (ASSA-222).
##
## **IT EXISTS BECAUSE NERITE'S MUTATION PASSED.** On main `25c18b2` they put the old prefix back --
## `_events.append("%d · %s" % [_sim.tick(), line])` -- and the client suite stayed **345 / 0**. The
## defect ASSA-222 slice 1 fixed could be rebuilt in one line with nothing red. The reason is that
## every other test about this section PLANTS lines into `_events` and drives `_rebuild_log`, so the
## one function that decides what gets stored had comments saying "no `tick N ·` prefix" and no
## guard. This drives the real path instead: a real sim, a real bundle, `_on_tick_bundle` ->
## `_remember_events`.
##
## **VERBATIM EQUALITY, NOT "DOES NOT BEGIN WITH A DIGIT".** A tick prefix is one way a host can add
## to the sim's wording; a suffix, a bullet, a re-worded refusal or a renamed building are others,
## and ASSA-222 is the item saying all of them are the same defect -- one describer, two audiences,
## chosen in `AssaySim::describe` and nowhere else. So the claim asserted is the general one: the
## stored line IS the sim's line. A test shaped around the prefix would go green the day someone
## adds something else.
##
## **WHY `event_lines` STILL ANSWERS AFTER THE TICK.** `_on_tick_bundle` applies the bundle and then
## copies, and nothing clears the sim's events until the next apply -- so reading them back here
## reads the same strings the copy saw. That is a fact about the Rust side, and it is not assumed:
## if it stopped holding, every comparison would be skipped and the non-vacuity check below fails.
##
## **NON-VACUITY IS ASSERTED, because the way this test dies is silently.** A seed where the click
## lands on the tile we already stand on walks nowhere, says nothing, compares nothing, and reports
## green. I have shipped that shape twice this week; `compared` is the cure.
func test_the_log_keeps_the_sims_sentence_and_adds_nothing_to_it() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	_click(screen, screen._my_tile() + Vector2i(2, 0), MOUSE_BUTTON_LEFT)
	var compared := 0
	for _i in range(20):
		_tick(screen, 1)
		var said := PackedStringArray()
		for line in screen._sim.event_lines(screen._client.player_id):
			said.append(String(line))
		# A tick saying more than the log keeps would make the tail comparison meaningless: the
		# oldest of those lines is trimmed away by design (`trimmed_log`), and that is not a defect.
		# One tick of a walk says one to three things, so this skip is a guard and not the usual case.
		if said.is_empty() or said.size() > screen.LOG_LINES:
			continue
		var kept: PackedStringArray = screen._events
		if kept.size() < said.size():
			ok = _fail(("the sim said %d lines this tick and the log holds %d in total, so lines "
					+ "the sim produced were never stored: %s") % [said.size(), kept.size(), said])
			break
		for at in said.size():
			var stored := String(kept[kept.size() - said.size() + at])
			if stored != said[at]:
				ok = _fail(("the sim said `%s` and the log stored `%s`. The window's wording is "
						+ "chosen in the sim (ASSA-222); a host that adds to the line is a second "
						+ "describer, and the `tick N ·` prefix came back this way.")
						% [said[at], stored])
				break
		if not ok:
			break
		compared += said.size()
	if ok and compared == 0:
		ok = _fail("twenty ticks of a walk produced no event line at all, so nothing was compared")
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
			# **THROUGH BOTH GESTURES, AND THE PAIRING THIS TEST IS ABOUT NOW HAS A SECOND HOP TO
			# SURVIVE** (ASSA-328). The row no longer sends anything: it opens the build screen on its
			# own offer, and `Build` sends. So this walks row `i`'s launcher and then the screen's one
			# act, and still requires the command to be about the sentence on row `i` -- which makes it
			# a test of `_open_build_screen` carrying the right offer across, not just of the index.
			var launcher := _find(row, AssayHud.make_launch_text())
			if line == null or launcher == null:
				ok = _fail("row %d has no sentence or no launcher" % i)
				break
			launcher.pressed.emit()
			var button := _find(screen._build_box, AssayHud.build_button_text())
			_asked.clear()
			if button == null:
				ok = _fail("row %d opened a screen with no Build button" % i)
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


## THE COUNT IN A ROW'S SENTENCE CLIMBS WITHOUT THE ROW BEING REBUILT. Every row ends "you have M",
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
		elif not labels.has(AssayHud.make_launch_text()):
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
			# THE DRAWN COLOUR, NOT `modulate` ALONE (ASSA-251). The status line STATES its colour
				# with a `font_color` override now; reading one factor of the product is what let a
				# 3.983:1 sentence pass every sweep in this repo.
			elif _drawn_status(screen) != AssayHud.status_color(AssayHud.Say.FAILED):
				ok = _fail("the refusal is drawn in %s, not the failed colour"
						% _drawn_status(screen))
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


## **WHAT THE `do` PANEL CALLS A BUILDING, READ OFF THE REAL DICT (ASSA-244).**
##
## **IT EXISTS BECAUSE THE OLD TEST ASSERTED THE DEFECT.** `test_actions.gd` pinned
## `chosen.contains("smelter 3")` against a hand-built `{"kind": "smelter", "id": 3}` — a fixture
## with no `name` key at all, so it could not represent what the binding actually returns and it
## froze the wrong form. Nerite read `chosen · smelter 0` at 1x on a real window; no test could.
##
## **SO THIS ONE OWNS NO FIXTURE.** The smelter is built by presses (`_a_placed_smelter`: mine,
## Craft, right-click, Place) and the dictionary comes from `tile_at`, which is the same dict
## `main.gd` hands `target_line`. A form the sim does not produce cannot pass here.
##
## The two rulings asserted are both already ruled and were both already written in `hud.gd`:
## **ASSA-136** — a building is named `Tonore smelter (A)`, not `smelter` — and **ASSA-222** — a
## reader who points carries no `BuildingId`, because there is nothing to type it into.
##
## NON-VACUITY: the species name is read out of the sim and asserted non-empty before it is used,
## because `contains("")` is true of every string and would make this whole test green by accident.
func test_the_do_panel_names_a_building_the_sims_way_and_carries_no_id() -> bool:
	var screen := _joined()
	var id := _a_placed_smelter(screen)
	if id < 0:
		return false
	var spot: Vector2i = screen._target_tile()
	var facts: Dictionary = screen._sim.tile_at(spot)
	var building: Variant = facts.get("building")
	if building == null:
		return _fail("no building in tile_at(%s) after _a_placed_smelter" % spot)
	var named := String((building as Dictionary).get("name", ""))
	if named == "":
		return _fail("the binding gave a building with no `name`; run `make client-lib`")
	if not named.contains("smelter"):
		return _fail("expected the sim's noun to mention the kind, got \"%s\"" % named)
	# THE NOUN CARRIES THE SPECIES, which is the whole point of ASSA-136: the species in that name
	# is the one that caps the fire and the one that comes back in your pack.
	if named == "smelter":
		return _fail(("the sim's noun is the bare kind, so this test cannot tell the ruled form "
				+ "from the defect: \"%s\"") % named)
	var line := AssayHud.target_line(spot, true, facts)
	if not line.contains(named):
		return _fail(("the do panel does not name the building the sim's way (ASSA-136).\n"
				+ "wanted: %s\nline:   %s") % [named, line])
	# AND NO INDEX, in either spelling the defect used: `smelter 0` or a trailing bare number.
	if line.contains("smelter %d" % id):
		return _fail(("the do panel still spells the building `kind id` (ASSA-136/222): %s")
				% line)
	if line.contains("%s %d" % [named, id]):
		return _fail("the do panel still appends the BuildingId after the noun: %s" % line)
	return true


## **EVERY ROW IN `make` STARTS ITS SENTENCE AT THE SAME x, WHETHER OR NOT ITS ITEM HAS ART**
## (ASSA-240, Maren's ruling: *"reserve it and leave it EMPTY, no placeholder glyph. A ragged left
## edge on a five-row list costs more than one blank square."*).
##
## **MEASURED AT 1x BEFORE THE FIX**, on my own real-window shot of main `03c8966`, seed 14247:
## `Tonore head`, `handle` and `frame` each carried a 32px icon and began at **x=985**, while
## `Tonore gear (A)` began at **x=946**. One list, two left edges, **39px apart**. What decides which
## a row gets is not the game -- it is whether `assets/sprites` ships a sheet for that kind (Marlow)
## -- so the only vertical line a list of wrapped sentences has broke on the row whose art does not
## exist, and will not be drawn: Maren ruled on ASSA-84 that nothing consumes a gear.
##
## **THE OFFERS ARE BUILT HERE AND THAT COST ME A GREEN TEST FIRST.** My first version played a real
## world and read the menu it produced. It passed, and **it still passed when I mutated the fix
## away** -- because every row that fixture can reach (`smelter`, `ore`) has a sprite, so there was no
## ragged edge to find. A test that cannot see the defect it is named for reads as coverage, which is
## worse than no test. The one artless kind is `gear`, and reaching it needs the whole smelt-and-
## refine chain.
##
## So this drives `_rebuild_make` -- the REAL row builder, the one `_refresh_make` calls -- with two
## offers whose shape is the sim's: `kind`/`species`/`grade`/`line`/`verb`, exactly as `offers_for`
## spells them. **The LAYOUT is what is under test, and the layout's input is an offer list.** The
## premise that one of the two genuinely lacks art is asserted rather than assumed, so this cannot go
## quiet again if a `gear` sheet ever ships.
func test_every_make_row_starts_its_sentence_at_the_same_x() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	var with_art := {"kind": "ore", "species": 0, "grade": "B", "count": 1, "name": "ore"}
	var no_art := {"kind": "gear", "species": 0, "grade": "B", "count": 1, "name": "gear"}
	screen._rebuild_make([
		{"makes": with_art, "line": "a rock you can carry", "verb": "craft", "tag": 0},
		{"makes": no_art, "line": "a gear nothing uses", "verb": "make", "tag": 0},
	])
	var rows: Array = screen._make.get_children()
	if rows.size() != 2:
		screen.queue_free()
		return _fail("the builder made %d rows from two offers" % rows.size())

	# THE PREMISE, ASSERTED: one row has a sprite and the other has none. A `TextureRect` is what a
	# drawn icon is; a reserved-empty column is a bare `Control` and draws nothing at all.
	var drawn := 0
	for row in rows:
		if not row.find_children("*", "TextureRect", true, false).is_empty():
			drawn += 1
	if drawn != 1:
		screen.queue_free()
		return _fail(("%d of 2 rows drew an icon; this test needs exactly one with art and one "
				+ "without, or it is not asking its question") % drawn)

	# **THE CLAIM IS MEASURED IN CHILDREN, NOT IN PIXELS, AND THAT IS NOT A SHORTCUT.** My second
	# version summed `position.x` up each row and compared the two. It passed -- and it passed the
	# mutation too, because **the suite runs inside `SceneTree._initialize`, before any layout pass**,
	# so every `position` in here is still (0, 0) and both edges read 0.0. I was comparing two zeros
	# and calling it an alignment check. This file's own `_left_edge_of` carries the same warning and
	# I walked into it anyway.
	#
	# What a container HAS done by now is accept its children, so the observable thing headless is
	# whether each row OPENS WITH the icon column. A row that skips it starts with its body instead.
	# **The pixel claim is a window shot's job** -- `shared/assay/nacre-assa240-icons/` at 1x -- and a
	# headless test that pretends to make it is the blank-frame trap one layer up.
	for row in rows:
		var first: Control = null
		for child in row.get_children():
			first = child as Control
			break
		if first == null:
			ok = _fail("a make row has no children at all")
		elif first.custom_minimum_size.x != screen.ICON_BOX_PX.x:
			var line := row.find_child(screen.MAKE_LINE, true, false) as Label
			ok = _fail(("a make row opens with a %s %s wide instead of the %.0fpx icon column, so "
					+ "its sentence starts further left than every other row's: `%s`")
					% [first.get_class(), first.custom_minimum_size, screen.ICON_BOX_PX.x,
					"?" if line == null else line.text])
	screen.queue_free()
	return ok


## **WHAT ONE BATCH SPENDS IS A NUMBER THE SIM HOLDS** (ASSA-256). `MakeOffer.cost` has always been a
## `u32` in `sim::debug`; until now it did not cross the binding, so a surface wanting "spend 3, get
## 1" as data had only the row's sentence to read it out of -- a renderer taking a fact from our
## wording, which is the failure `make_offers`' own docstring warns about for `verb`.
##
## **THE PREMISE IS THAT THIS PACK OFFERS TWO DIFFERENT COSTS**, and it is a guard rather than a nicety:
## with one cost on every row, "cross the constant 1" and "cross the pack count" are both
## indistinguishable from correct. `smelt` spends 1 ore and `sort` spends 3, so a pack with ore in it
## has both. Asserting `cost != count` somewhere is the second half: `have` is the same on every row
## built from one stack, which is exactly the field a tired hand reaches for.
##
## NOT ASSERTED: that the sentence contains the number. The line holds several numbers and matching on
## one of them keys this test to wording that is allowed to move -- I have broken two tests that way
## this week. The sim test for `cost` is in Rust; this one is about the field crossing at all.
func test_every_menu_row_carries_what_one_batch_spends() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var offers: Array = screen._sim.make_offers(screen._client.player_id)
		if offers.is_empty():
			ok = _fail("a pack with ore in it produced no offers at all, so nothing here is tested")
		var costs := {}
		var differs_from_count := false
		for entry in offers:
			var offer: Dictionary = entry
			if not offer.has("cost"):
				ok = _fail(("an offer crossed without `cost`: %s. A chip showing what a batch spends "
						+ "has to parse the sentence without it.") % [offer.keys()])
				break
			if typeof(offer["cost"]) != TYPE_INT:
				ok = _fail("`cost` crossed as %s, not an int" % type_string(typeof(offer["cost"])))
				break
			var cost := int(offer["cost"])
			if cost < 1:
				ok = _fail("`cost` crossed as %d; a batch that spends nothing is not a cost" % cost)
				break
			costs[cost] = true
			if cost != int(offer["count"]):
				differs_from_count = true
		if ok and costs.size() < 2:
			ok = _fail(("every row reports the same cost (%s), so this world cannot tell the real "
					+ "number from a constant and the assertions above prove nothing")
					% [costs.keys()])
		if ok and not differs_from_count:
			ok = _fail("no row's cost differs from its pack count, so `cost` could be `have` here")
		if ok:
			print("    %d make rows, costs %s" % [offers.size(), costs.keys()])
	screen.queue_free()
	return ok


## **A ROW YOU CANNOT AFFORD DOES NOT OFFER A PRESSABLE BUTTON** (ASSA-247; Maren 17:22 UTC: *"when a
## recipe is unavailable, the line says what you LACK"*, and ASSA-224's rule that a control which
## does not follow availability is a lying control).
##
## **DRIVEN THROUGH `_rebuild_make` WITH OFFERS THIS TEST WRITES, and that is the opposite choice to
## the test above on purpose.** A real world's pack is affordable or not according to how the fixture
## happens to mine, so a real-world version of this test would pass on a menu that never disables
## anything and I would not know. Three rows, one of each case, is the only shape that can fail for
## the right reason:
##
## - short (cost 3, holding 1): disabled.
## - exact (cost 1, holding 1): pressable -- the boundary, because `<` and `<=` both read fine in
##   prose and only one of them lets you spend the last batch you own.
## - no `cost` key at all: pressable, which is ASSA-141's rule. A binding that stopped sending the
##   field leaves the menu exactly as it was before this slice rather than disabling every row.
func test_a_row_you_cannot_afford_is_not_pressable_and_the_last_batch_is() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var made := {"kind": "ore", "species": 0, "grade": "B", "count": 1, "name": "ore"}
	screen._rebuild_make([
		{"makes": made, "line": "short of it", "verb": "craft", "tag": 0, "cost": 3, "count": 1},
		{"makes": made, "line": "your last batch", "verb": "craft", "tag": 0, "cost": 1, "count": 1},
		{"makes": made, "line": "no cost crossed", "verb": "craft", "tag": 0, "count": 1},
	])
	var ok := true
	var rows: Array = screen._make.get_children()
	if rows.size() != 3:
		screen.queue_free()
		return _fail("the builder made %d rows from 3 offers" % rows.size())
	for i in range(rows.size()):
		var button := _find(rows[i], AssayHud.make_launch_text())
		var line := (rows[i] as Node).find_child(screen.MAKE_LINE, true, false) as Label
		if button == null:
			ok = _fail("row %d has no launcher at all" % i)
		elif button.disabled:
			# **EVERY ROW OPENS, INCLUDING THE ONE YOU CANNOT AFFORD -- WHICH IS THE OPPOSITE OF WHAT
			# THIS TEST ASSERTED BEFORE ASSA-328, AND IT IS THE SAME PRINCIPLE.** ASSA-247 disabled an
			# unaffordable row because the control MADE something and the sim would refuse it: *"a
			# weight that does not follow availability is a lying control"*. The control now opens the
			# screen where have/need is printed for every material at once, and looking at what
			# something costs is available always -- so the row a player most needs to open is the one
			# the old rule shut.
			ok = _fail(("the row reading `%s` cannot be pressed; since ASSA-328 the control opens the "
					+ "build screen and the player who cannot afford it is the one who needs to read "
					+ "the cost") % ["?" if line == null else line.text])
	# **AND THE SCREEN DOES NOT BELIEVE THE ROW, WHICH THIS FIXTURE IS THE PROOF OF** (ASSA-328).
	#
	# **I EXPECTED THE COST BLOCK TO SAY `1 / 3` HERE AND IT SAYS SO FOR NO OFFER AT ALL -- the test
	# was wrong and the client is right.** These three offers are written by this file; the sim never
	# made them. `_chosen_offer` re-reads `make_offers` at every refresh and matches on the sim's own
	# `verb`/`tag`/species/grade, so a screen opened from a row the sim does not offer says exactly
	# that. **That is ASSA-55's rule on a surface that stays open for thousands of ticks**: nothing
	# drawn or sent comes from what the row was showing when it was pressed.
	#
	# The two real counts are asserted against a real world in
	# `test_the_build_screen_costs_a_real_offer_in_the_sims_own_two_numbers`, which is where a cost
	# belongs: a number this file invented could only ever prove this file can echo itself.
	if ok:
		var short := _find(rows[0], AssayHud.make_launch_text())
		short.pressed.emit()
		if not screen._build_box.visible:
			ok = _fail("a row the sim does not offer opened no screen at all")
		elif not _text_of(screen._build_detail).contains("no longer offers"):
			ok = _fail(("the screen opened on an offer this file invented and its detail says `%s`; "
					+ "a surface that echoed the row would have drawn a cost for it")
					% _text_of(screen._build_detail))
	screen.queue_free()
	return ok


## **ONE LIST, ONE OBJECT, TWO STATES — AND THE MATERIAL ROW NAMES THE MATERIAL** (ASSA-343; Maren's
## ASSA-328 rulings 3 and her §5.5 of 20:51).
##
## Her words for the first: *"A selected and an unselected member of one list must be one object in
## two states, never two objects — otherwise the state reads as a difference in kind."* So the
## assertion is about CLASS and STATE, not about a colour: every row of both pickers is a `Button`,
## no row is a `Label`, and exactly one of them is pressed.
##
## **AND THE LABEL IS THE MATERIAL, NOT THE STACK.** Her second ruling, off the shipped code: the row
## printed `8 × Tonore refined (A)` one row above a `need · have` about that same count. Zipped
## against `_offers_for_open_row` and compared to the SIM'S `name` on the pack stack, so this cannot
## be satisfied by a row carrying some other row's words — and a literal is impossible here anyway,
## because which species a seeded world hands you is worldgen's business.
func test_a_picker_is_one_object_in_two_states_and_names_the_material() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var launcher := _make_launcher_for(screen, "smelter")
		if launcher == null:
			ok = _fail("no menu row offers a smelter: %s" % _text_of(screen._make))
		else:
			launcher.pressed.emit()
			# THE RECIPE PICKER: every row a Button, exactly one pressed.
			var pressed := 0
			for child in screen._build_picker.get_children():
				if child is Label:
					ok = _fail("the recipe picker draws `%s` as a Label; a chosen member of a list is "
							% (child as Label).text + "the same object in another state")
					break
				var row := child as Button
				if row == null:
					ok = _fail("the recipe picker holds a %s, which is neither" % child.get_class())
					break
				if not row.toggle_mode or row.button_group == null:
					ok = _fail("`%s` is not a toggle in a group, so `exactly one is chosen` is a "
							% row.text + "thing each rebuild has to remember")
					break
				if row.button_pressed:
					pressed += 1
			if ok and pressed != 1:
				ok = _fail("%d of %d recipe rows read as chosen"
						% [pressed, screen._build_picker.get_child_count()])
			# THE MATERIAL PICKER: the same two properties, plus the sim's own name for the material.
			if ok:
				var offers: Array = screen._offers_for_open_row()
				var chosen := 0
				for i in range(screen._build_materials.get_child_count()):
					var row: Node = screen._build_materials.get_child(i)
					var press := row.get_child(0) as Button
					if press == null:
						ok = _fail("material row %d leads with a %s, not a Button"
								% [i, row.get_child(0).get_class()])
						break
					if press.button_pressed:
						chosen += 1
					var mine: Dictionary = screen._pack_stack_of(offers[i] as Dictionary)
					var named := String(mine.get("name", ""))
					if press.text != named:
						ok = _fail(("material row %d is labelled `%s`; the sim's name for that "
								+ "material is `%s`, and the count belongs on the row below")
								% [i, press.text, named])
						break
				if ok and chosen != 1:
					ok = _fail("%d of %d material rows read as chosen"
							% [chosen, screen._build_materials.get_child_count()])
	screen.queue_free()
	return ok


## **THE TWO COUNTS, FROM A REAL WORLD AND A REAL CATALOGUE** (ASSA-332; Maren's §5.5: *"`need 1 ·
## have 2`: no slash, need first, both numbers always"*, and §3's Factorio borrowing -- affordability
## is READ, never computed by the player in their head).
##
## **THE NUMBERS COME OUT OF `make_offers` AND ARE COMPARED TO THE SCREEN, which is the only pairing
## worth asserting here.** A literal would prove nothing: the fixture mines a seeded world, so how
## much ore is in the pack at this tick is the sim's business and not a number this file may know.
## What it may require is that the two numbers on the screen are the sim's `cost` and `count` for the
## row that was pressed, in that order.
##
## **THE GRAMMAR IS SPELLED OUT HERE AND NOT ASKED OF THE FUNCTION UNDER TEST.** This read
## `AssayHud.have_need_line(...)` and compared it to the screen, which is a function compared with
## itself -- the exact shape that let a wrong constructor through my ASSA-325 refusal test the same
## day. A swapped pair of `int`s or a slash coming back now reddens this, because the format string
## lives in the test.
##
## **AND A MATERIAL ROW PER MATERIAL, which is the column Maren's mock does not have** (I gave the
## middle column to materials in slice 1; it is on ASSA-328 for her to reverse). Asserted as "one row
## per offer the sim makes for this recipe" rather than as a count, because how many materials a pack
## holds is worldgen's answer.
func test_the_build_screen_costs_a_real_offer_in_the_sims_own_two_numbers() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var launcher := _make_launcher_for(screen, "smelter")
		if launcher == null:
			ok = _fail("no menu row offers a smelter: %s" % _text_of(screen._make))
		else:
			launcher.pressed.emit()
			var offer: Dictionary = screen._chosen_offer()
			if offer.is_empty():
				ok = _fail("the screen opened from a real row and points at no offer")
			else:
				var want := "need %d · have %d" % [int(offer.get("cost", 0)),
						int(offer.get("count", 0))]
				# **THIS READ THE COST BLOCK UNTIL ASSA-341, AND IT NOW READS THE PICKER.** Maren
				# deleted block 6 on the make path because `MakeOffer.input` is singular, so its one
				# entry could only ever be the selected material row -- the duplicate this test was
				# half-asserting. **The property it was written for is untouched**: the two counts on
				# screen are the SIM's, never numbers this file invented. They simply have one home
				# now, and §3 keeps them in the picker because comparing two materials must not cost
				# two gestures.
				var said := _text_of(screen._build_materials)
				if not said.contains(want):
					ok = _fail(("the sim says one batch needs %d and you have %d, so the material "
							+ "picker should carry `%s`; it says `%s`") % [int(offer.get("cost", 0)),
							int(offer.get("count", 0)), want, said])
				elif screen._build_cost.visible or screen._build_cost_box.visible:
					ok = _fail(("block 6 is shown on the make path (rows=%s, section=%s); its single "
							+ "entry can only ever duplicate the material row")
							% [screen._build_cost.visible, screen._build_cost_box.visible])
				elif said.contains("/"):
					# **§5.5 TOOK THE SLASH AWAY AND SAID WHY**: a slash is a ratio's mark and a ratio
					# needs left <= right, so the surplus case -- the normal one on a stocked pack -- read
					# as 200% of something. Asserted as an ABSENCE, because the old grammar coming back
					# anywhere on this block is the defect and not only in one function's output.
					ok = _fail("the cost block says `%s`; §5.5 took the slash away" % said)
				# THE BAR IS THE SIM'S OWN SENTENCE AND NOT A RE-WORDING OF IT (ASSA-88), and since
				# ASSA-332 that sentence lives in the commit bar rather than the detail column.
				elif not _text_of(screen._build_said).contains(String(offer.get("line", ""))):
					ok = _fail(("the commit bar says `%s` and the sim's sentence for this row is "
							+ "`%s`; a client that re-words one is ASSA-43's defect")
							% [_text_of(screen._build_said), String(offer.get("line", ""))])
				else:
					var materials: int = screen._build_materials.get_child_count()
					var offers: Array = screen._offers_for_open_row()
					if materials != offers.size():
						ok = _fail(("the sim offers this recipe in %d materials and the picker draws "
									+ "%d rows") % [offers.size(), materials])
					# **AND EVERY ONE OF THEM STATES ITS OWN TWO COUNTS, IN THE SAME GRAMMAR**, which is
					# the half that makes it a choice: a picker that costed only the chosen row would send
					# the player back to pressing each material to find out what it costs.
					#
					# **ZIPPED AGAINST THE SIM'S OFFERS IN ORDER, NOT SCANNED FOR A MARK** (ASSA-332): a row
					# carrying some OTHER row's two numbers is the defect a `contains("·")` cannot see, and
					# these rows are built from this same array in this same order.
					else:
						for i in range(materials):
							var each: Dictionary = offers[i]
							var owed := "need %d · have %d" % [int(each.get("cost", 0)),
									int(each.get("count", 0))]
							var row: Node = screen._build_materials.get_child(i)
							if not _text_of(row).contains(owed):
								ok = _fail("material row %d says `%s`; the sim's counts are `%s`"
										% [i, _text_of(row), owed])
								break
	screen.queue_free()
	return ok


## **ONE POP-UP AT A TIME, AND ESC CLOSES WHICHEVER IT IS** (ASSA-328; Maren's §1: *"the build screen
## and a machine menu are mutually exclusive -- opening either closes the other"*, and ASSA-316
## ruling 2 for Esc).
##
## **BOTH DIRECTIONS, because a rule stated at one end holds until somebody opens the other.** The
## exclusion is written in `_open_build_screen` AND in `_open_machine_menu`, so a test that only
## opened them in one order would pass with half of it deleted.
##
## **AND CLOSING LOSES NOTHING** (her §1: *"a half-built design is client state until Build; it
## survives a close and re-opens as you left it"*). Checked as the chosen material surviving a close,
## which is the only chosen state slice 1 has.
func test_the_build_screen_and_a_machine_menu_are_one_at_a_time() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var id := _a_placed_smelter(screen)
	var ok := id >= 0
	if ok:
		var launcher := _make_launcher_for(screen, "ore")
		if launcher == null:
			ok = _fail("no menu row offers anything to make from ore: %s" % _text_of(screen._make))
		else:
			launcher.pressed.emit()
			if not screen._build_box.visible:
				ok = _fail("the row's launcher opened no screen")
			elif screen._menu_at != -1:
				ok = _fail("opening the build screen left machine %d's menu open" % screen._menu_at)
			else:
				var chose: int = screen._build_species
				# THE MENU, OPENED SECOND, TAKES THE SCREEN DOWN.
				screen._open_machine_menu(screen._menu_tile, id)
				if screen._build_box.visible:
					ok = _fail("opening a machine menu left the build screen on screen")
				elif screen._build_verb != "":
					ok = _fail("the build screen is hidden and still reports itself open")
				else:
					# AND RE-OPENING FINDS THE MATERIAL STILL CHOSEN.
					launcher.pressed.emit()
					if screen._menu_at != -1:
						ok = _fail("re-opening the screen left the machine menu open")
					elif screen._build_species != chose:
						ok = _fail(("closing the screen forgot the chosen material: %d became %d")
								% [chose, screen._build_species])
					else:
						var esc := InputEventKey.new()
						esc.keycode = KEY_ESCAPE
						esc.pressed = true
						screen._unhandled_key_input(esc)
						if screen._build_box.visible:
							ok = _fail("Esc did not close the build screen")
	screen.queue_free()
	return ok


## **THE SENTENCE AND ITS ONE CONTROL SHARE A LINE** (ASSA-247, Maren's Gap 3), which is where this
## slice's density came from: a make row measured 73 px with the verb below the sentence, and the
## section needs 500 px of reachable button against a budget of about 313.
##
## **ASSERTED AS A SHARED PARENT, NOT AS PIXELS, and this file's own warning is why**: the suite runs
## inside `SceneTree._initialize`, so every `position` and `size.y` in here reads 0.0 and a height
## assertion would pass on any layout at all. The pixel claim belongs to
## `tools/nacre_tab_budget_probe.gd` in a real window; what is observable headless is the structure
## that produces it -- the button and the `MakeLine` label have the same parent, and that parent is an
## `HBoxContainer`.
func test_a_make_rows_verb_sits_on_the_sentences_own_line() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var made := {"kind": "ore", "species": 0, "grade": "B", "count": 1, "name": "ore"}
	screen._rebuild_make([
		{"makes": made, "line": "a rock you can carry", "verb": "craft", "tag": 0,
				"cost": 1, "count": 4},
	])
	var ok := true
	var row: Node = screen._make.get_child(0)
	var line := row.find_child(screen.MAKE_LINE, true, false) as Label
	var button := _find(row, AssayHud.make_launch_text())
	if line == null or button == null:
		ok = _fail("the row has no sentence or no button")
	elif button.get_parent().get_parent() != line.get_parent():
		ok = _fail(("the verb is not on the sentence's line: the sentence sits in a %s and the "
				+ "button's row in a %s") % [line.get_parent().get_class(),
				button.get_parent().get_parent().get_class()])
	elif not (line.get_parent() is HBoxContainer):
		ok = _fail("the sentence and the verb share a %s, which stacks them rather than pairing them"
				% line.get_parent().get_class())
	elif line.size_flags_horizontal != Control.SIZE_EXPAND_FILL:
		ok = _fail("the sentence does not expand, so the button is beside the text instead of hard "
				+ "right and the row's width is whatever the sim's sentence happens to be")
	screen.queue_free()
	return ok


## THE COLOUR THE STATUS LINE IS ACTUALLY DRAWN IN (ASSA-251). `font_color` TIMES `modulate`: the
## defect this guards was `modulate = status_color(...)` multiplying the theme's INK, so a test that
## read either factor alone would have passed over it.
func _drawn_status(screen) -> Color:
	var c: Color = screen._status.get_theme_color(&"font_color")
	var m: Color = screen._status.modulate
	return Color(c.r * m.r, c.g * m.g, c.b * m.b, c.a * m.a)


## **THE CLOSE-UP IS TOLD WHICH TILE THE BUTTONS ACT ON** (ASSA-276 move 4).
##
## The geometry of the mark is `tests/test_selection_mark.gd`'s. This is the wiring: a right click
## is the one gesture that chooses a tile (`_unhandled_input`, ASSA-37), and until this item nothing
## downstream of it reached the view a player is actually looking at. Asserted through the real
## click path rather than by setting `_targeted`, so what is held is the thing a player can do.
##
## **AND THE THIRD CLAUSE IS A BUG THAT PREDATES THE MARK.** `_targeted` was set by a right click and
## cleared nowhere, so after a session died and the player pressed Join, `_target_tile()` still
## answered a tile chosen in the PREVIOUS world -- and Mine, Assay, Place and Pick up all read it.
## Invisible while nothing drew it; move 4 would have drawn it. The mark is why it was found, and the
## fix belongs with the mark.
func test_the_close_up_is_given_the_tile_the_buttons_act_on() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	if screen._world.selection != null:
		ok = _fail(("a fresh screen already has a selection (%s): with nothing chosen the buttons "
				+ "act on your own feet, which the foot mark already shows")
				% screen._world.selection)
	var spawn: Vector2i = screen._sim.spawn_tile()
	var chosen := spawn + Vector2i(2, -1)
	_click(screen, chosen, MOUSE_BUTTON_RIGHT)
	_tick(screen, 1)
	if screen._world.selection == null:
		ok = _fail("a right click chose %s and the close-up was told nothing: the only thing on "
				% chosen + "screen naming the subject of the next press is a line of text")
	elif (screen._world.selection as Rect2i) != Rect2i(chosen, Vector2i.ONE):
		ok = _fail(("a right click on %s marked %s instead. This tile is bare, and a bare tile is "
				+ "exactly one tile: `Place` and `PlaceAssembly` carry a `TilePos`, so the subject "
				+ "really is the tile here (ASSA-348)") % [chosen, screen._world.selection])
	elif not (screen._world.selection as Rect2i).has_point(screen._target_tile()):
		ok = _fail(("the mark is on %s and the buttons act on %s. A mark that does not even cover "
				+ "the tile the verb uses is worse than no mark")
				% [screen._world.selection, screen._target_tile()])
	# THE SESSION DIES. The selection was made in a world that is gone.
	screen._session_ended()
	if screen._world.selection != null:
		ok = _fail(("the selection survived the session that made it (%s): press Join and the "
				+ "buttons act on a tile chosen in another world")
				% screen._world.selection)
	if screen._targeted:
		ok = _fail("`_targeted` survived the session, so `_target_tile()` still answers a stale "
				+ "tile even with the mark cleared")
	screen.queue_free()
	return ok


## **A CLICK ON A MACHINE OPENS ITS MENU, FROM EITHER BUTTON, AND THE MENU IS NEVER OVER IT**
## (ASSA-316; the board, 10-08: *"machines should have menus so we can interact with them"*).
##
## BOTH BUTTONS, BECAUSE BOTH ARE RULED (Maren 7 and 8) AND THEY ARE DIFFERENT BRANCHES: left-click
## would otherwise walk, right-click would otherwise arm a placement the sim refuses on an occupied
## tile. One of them passing says nothing about the other.
func test_either_click_on_a_machine_opens_a_menu_beside_it() -> bool:
	var screen := _joined()
	var ok := true
	var id := _a_placed_smelter(screen)
	if id < 0:
		screen.queue_free()
		return false
	var spot: Vector2i = screen._target_tile()
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		screen._close_machine_menu()
		_asked.clear()
		_click(screen, spot, button)
		if screen._menu_at != id:
			ok = _fail("button %d on the machine at %s left the menu at %d, want %d"
					% [button, spot, screen._menu_at, id])
			break
		if not _asked.is_empty():
			ok = _fail("button %d on a machine submitted %s; opening a menu is not a command"
					% [button, _asked])
			break
		if not screen._menu_box.visible:
			ok = _fail("the menu is open at %d and its panel is not visible" % screen._menu_at)
			break
		# **THE POSITION IS THE TETHER SINCE ASSA-334** (Maren reversing ruling 1), SO THE RING IS NOT.
		# Ruling 8 gave the menu's machine the mark ASSA-276 move 4 had put on the acted-on tile; with
		# the panel beside its machine, the ring goes back to `_target` and tracks it whatever menu is
		# open. **THIS TEST CANNOT TELL THE TWO RULES APART AND SAYS SO**: the smelter was placed on the
		# targeted tile, so here the acted-on tile IS the menu's machine and both rules predict the same
		# mark. `test_the_ring_stays_on_the_acted_on_tile_while_a_menus_machine_is_elsewhere` is the one
		# that separates them.
		var want: Variant = screen._footprint_tiles(screen._target) if screen._targeted else null
		if screen._world.selection != want:
			ok = _fail("the ring is on %s and the acted-on subject is %s"
					% [screen._world.selection, want])
			break
		# **AND THE PANEL IS BESIDE ITS MACHINE, ASKED OF THE SCREEN'S OWN GEOMETRY** -- the box's rect
		# and not the region's, which is the whole world now and exists to clip.
		var footprint: Rect2 = screen._footprint_rect()
		# THE REGION'S OWN POSITION PLUS THE BOX'S, AND NOT `global_position`: this screen is not in a
		# window, so the only positions that mean anything are the ones `_place_machine_menu` WROTE.
		var box := Rect2(screen._menu_region.position + screen._menu_box.position,
				screen._menu_box.size)
		if box.intersects(footprint):
			ok = _fail("the menu %s is drawn over its own machine's footprint %s" % [box, footprint])
			break
		if box.size.x <= 0.0 or box.size.y <= 0.0:
			ok = _fail("the menu measures %s, so the check above asserts nothing" % box.size)
			break
		# IT TOUCHES ITS MACHINE, which is the half "never over it" does not say: a panel parked in the
		# far corner also never covers anything. One gap either side is the most it may be away.
		var gap: float = minf(absf(box.position.x - footprint.end.x),
				absf(footprint.position.x - box.end.x))
		if gap > AssayHud.MENU_ANCHOR_GAP + 0.01:
			ok = _fail("the menu %s stands %.0f px from its machine %s, not beside it"
					% [box, gap, footprint])
			break
		# NEVER OVER THE HUD COLUMN (ruling 2): a menu over the log hides the only answer the sim's
		# refusals get.
		if not AssayHud.world_rect().encloses(box):
			ok = _fail("the menu's box %s is not inside the world %s"
					% [box, AssayHud.world_rect()])
			break
	screen.queue_free()
	return ok


## **NOTHING IN THE MENU WRAPS AND NOTHING OVERFLOWS IT, ON THE WORST STRINGS THE SIM CAN HAND IT**
## (ASSA-334 §6; Maren's floor and cap). Her rule is that past its room it SCROLLS; nothing reaches
## that today, so the bound is this test and the `ScrollContainer` is the day it goes red.
##
## **IT ASSERTS THE SIZE IS NOT ZERO FIRST, WHICH IS THE WHOLE POINT.** A headless suite lays nothing
## out, so `size <= room` would be the greenest and most worthless check in the file -- the exact shape
## of the fold probe I had to withdraw on ASSA-247. The minimum size is the engine's answer about
## content and is available with no window, so that is what is measured.
##
## **AND THE WORST CASE IS CONSTRUCTED, NOT PLAYED.** A seed's menu is narrow -- short species names, a
## two-digit cap -- so a measurement of the real one passes and says nothing. Every string the sim can
## hand this menu is re-texted here at its bound: a species name at the sim's own cap, the longest
## item kind, and the longest stall sentence the sim writes. **If that fails, the floor is wrong and
## the number goes to Maren** -- her §6 budgeted 343 px of content for exactly this row.
##
## **THE CAP IS ASKED OF THE SIM, NOT TYPED** (`AssaySim.species_name_max`, added for this test on
## Marlow's call). It read `20` of its own until then, and the failure that shape makes is the one he
## had just shipped and withdrawn: raise `SPECIES_NAME_MAX` and this "worst case" gets SHORTER than
## the real one, the check stays green, and the row it exists to bound overflows in a real window
## with nothing going red. A worst case that silently stops being the worst case is worse than none.
func test_nothing_in_a_machine_menu_wraps_at_the_worst_strings_the_sim_can_write() -> bool:
	var screen := _joined()
	var ok := true
	var id := _a_placed_smelter(screen)
	if id < 0:
		screen.queue_free()
		return false
	_click(screen, screen._target_tile(), MOUSE_BUTTON_LEFT)
	var want: Vector2 = screen._menu_box.get_combined_minimum_size()
	if want.x <= 0.0 or want.y <= 0.0:
		ok = _fail("the menu's content measures %s, so this check asserts nothing" % want)
	# **THE REAL MENU FIRST, THEN THE WORST ONE**, so a failure says which of the two it was.
	elif want.x > AssayHud.MENU_CAP_PX:
		ok = _fail("the menu a real smelter draws is %.0f px wide and the cap is %.0f"
				% [want.x, AssayHud.MENU_CAP_PX])
	if ok:
		# **A FRESH PANEL AND NOT THE LIVE ONE RE-TEXTED, BECAUSE THE LIVE ONE'S ANSWER IS CACHED.**
		# The first version of this test set the real controls' text to the worst strings and asked the
		# box again: `Control.update_minimum_size` queues its recalculation for a frame, and this harness
		# runs inside `_initialize` where no frame ever comes, so it returned the number it had computed
		# BEFORE the stretch -- real 254, "worst case" 254, a check that could not fail. A fresh tree is
		# measured on its first ask, which is how `test_track.gd` compares two rows.
		# **THE KIND COMES OUT OF THE SIM'S RECIPE TABLE, NOT OFF THE TOP OF MY HEAD.** The first
		# version of this measurement used `smelter`, which is the longest ITEM kind in the game and
		# cannot reach a slot: `insert_slots` offers a put only for a kind some NON-HAND recipe eats, so
		# the widest put button is bounded by the longest of THOSE. It made the number I was about to
		# hand Maren 28 px too dear, which is the mistake I made once before in her disfavour -- an
		# inflated number is as bad as no number.
		var kind := ""
		for entry in AssaySimHost.recipes():
			var recipe: Dictionary = entry
			if not bool(recipe.get("hand", false)) \
					and String(recipe.get("input", "")).length() > kind.length():
				kind = String(recipe.get("input", ""))
		if kind == "":
			screen.queue_free()
			return _fail("no non-hand recipe in the sim's table, so nothing can be put in a slot")
		# THE SIM'S OWN CAP, ASKED FOR RATHER THAN COPIED (`sim::tuning::SPECIES_NAME_MAX`). `W` is the
		# worst letter and a real one: `mineral::validate_name` allows only ASCII letters, digits and
		# hyphens, so no legal name is wider than this many Ws.
		var cap: Variant = ClassDB.class_call_static("AssaySim", "species_name_max")
		if typeof(cap) != TYPE_INT or int(cap) <= 0:
			screen.queue_free()
			return _fail("species_name_max answered %s, so the worst case has no bound" % [cap])
		var worst := "%s %s (A)" % ["W".repeat(int(cap)), kind]
		var probe := PanelContainer.new()
		var inside := VBoxContainer.new()
		probe.add_child(inside)
		# EVERY KIND OF LINE THE MENU HAS, AT ITS BOUND: the sim's longest stall sentence, a slot's own
		# ratio row, the sim's longest item name on the line under it, and the widest put button a
		# `SPECIES_NAME_MAX` species and a four-digit stack can produce.
		var state := Label.new()
		state.text = "stalled: fire 9999 too cool for ore needing 9999"
		inside.add_child(state)
		var row: HBoxContainer = screen._amount_row()
		(row.get_node(screen.ROW_WORDS) as Label).text = "output"
		(row.get_node(screen.ROW_COUNTS) as Label).text = AssayHud.amount_counts_line(9999, 9999)
		inside.add_child(row)
		var what := Label.new()
		what.text = worst
		inside.add_child(what)
		var put := Button.new()
		put.text = AssayHud.insert_label(9999, worst, AssayActions.SLOT_FUEL)
		inside.add_child(put)
		var stretched: Vector2 = probe.get_combined_minimum_size()
		# THE DECOMPOSITION, SO THE NUMBER HANDED TO MAREN IS NOT JUST A TOTAL: her 343 is the string
		# and the rest is furniture she never measured because nothing asked.
		var font := ThemeDB.fallback_font
		var theme: Theme = load("res://theme/assay.tres")
		var words := font.get_string_size(put.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				theme.get_font_size(&"font_size", &"Button") if theme != null else 13).x \
				if theme != null else 0.0
		print(("menu width: real %.0f px, worst case %.0f px (widest string %.0f + %.0f of button and "
				+ "panel padding), floor %.0f, cap %.0f")
				% [want.x, stretched.x, words, stretched.x - words, AssayHud.MENU_FLOOR_PX,
				AssayHud.MENU_CAP_PX])
		probe.free()
		# **THE RATCHET, NOT THE CAP, AND THE DIFFERENCE IS WHOSE DECISION IT IS.** The worst case
		# measures 455 px against Maren's 408 -- her floor is a STRING width and this is the control's,
		# with 112 px of button and panel padding between them. The cap is hers to move, so this asserts
		# the number does not get WORSE (`MENU_WORST_CONTENT_PX`, where the three ways out are written
		# down) and the gap itself is reported on the item rather than silently chosen here.
		if stretched.x > AssayHud.MENU_WORST_CONTENT_PX:
			ok = _fail(("the worst case now wants %.0f px and the number on record is %.0f: a label "
					+ "grew, and the overflow past Maren's %.0f cap grew with it")
					% [stretched.x, AssayHud.MENU_WORST_CONTENT_PX, AssayHud.MENU_CAP_PX])
	screen.queue_free()
	return ok


## **THE TWO VERBS THAT LEFT `do` ACT ON THE MENU'S OWN MACHINE** (ASSA-316, Maren's ruling 3 and her
## condition that they leave on the commit that makes the menu reachable).
func test_take_and_pick_up_left_do_and_act_on_the_menus_machine() -> bool:
	var screen := _joined()
	var ok := true
	var id := _a_placed_smelter(screen)
	if id < 0:
		screen.queue_free()
		return false
	var spot: Vector2i = screen._target_tile()
	# THE COLUMN IS ASKED WHILE A MACHINE IS TARGETED, which is the state that used to grow the row.
	if _find(screen._actions, "Take") != null or _find(screen._actions, "Pick up") != null:
		ok = _fail("`do` still offers Take or Pick up with a machine targeted: %s"
				% [_labels_of(screen._actions)])
	_click(screen, spot, MOUSE_BUTTON_LEFT)
	var take := _find(screen._menu_box, "Take")
	if take == null:
		ok = _fail("the machine menu offers no Take: %s" % [_labels_of(screen._menu_box)])
	elif ok:
		_asked.clear()
		take.pressed.emit()
		if _asked.size() != 1 or _asked[0] != AssayActions.take(id):
			ok = _fail("Take in the menu for building %d asked for %s" % [id, _asked])
	if ok and _find(screen._menu_box, "Pick up") == null:
		ok = _fail("the machine menu offers no Pick up: %s" % [_labels_of(screen._menu_box)])
	# **AND THE MENU CLOSES ITSELF WHEN ITS MACHINE IS GONE**, which is the common way to leave it.
	if ok:
		var away := _find(screen._menu_box, "Pick up")
		away.pressed.emit()
		_tick(screen, 8)
		if screen._menu_at != -1:
			ok = _fail("picked the machine up and its menu is still open at %d" % screen._menu_at)
		elif screen._menu_box.visible:
			ok = _fail("the menu closed at the id and left its panel on screen")
	screen.queue_free()
	return ok


## **ESC CLOSES. A CLICK ON THE GROUND CLOSES AND DOES NOT WALK. A SECOND CLICK WALKS** (ASSA-316,
## Maren's ruling 2 and ruling 7's condition).
func test_esc_closes_a_menu_and_a_dismissing_click_does_not_walk() -> bool:
	var screen := _joined()
	var ok := true
	var id := _a_placed_smelter(screen)
	if id < 0:
		screen.queue_free()
		return false
	var spot: Vector2i = screen._target_tile()
	_click(screen, spot, MOUSE_BUTTON_LEFT)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	screen._unhandled_key_input(esc)
	if screen._menu_at != -1:
		ok = _fail("Esc left the menu open at %d" % screen._menu_at)
	# THE DISMISSING CLICK: open again, then click a tile that is NOT the machine.
	if ok:
		_click(screen, spot, MOUSE_BUTTON_LEFT)
		var ground: Vector2i = screen._my_tile() + Vector2i(1, 0)
		_asked.clear()
		_click(screen, ground, MOUSE_BUTTON_LEFT)
		if screen._menu_at != -1:
			ok = _fail("a click on %s left the menu open at %d" % [ground, screen._menu_at])
		elif not _asked.is_empty():
			ok = _fail("the click that closed the menu also asked for %s" % [_asked])
		else:
			# A SECOND CLICK WALKS, which is what makes the first one a dismissal and not a dead zone.
			_click(screen, ground, MOUSE_BUTTON_LEFT)
			if _asked.size() != 1 or _asked[0] != AssayActions.move_to(ground):
				ok = _fail("the click after the dismissal asked for %s, not a walk to %s"
						% [_asked, ground])
	# **AND THE RIGHT BUTTON CLOSES AND STILL TARGETS** (Maren's ruling 8: an empty tile keeps today's
	# split exactly). This is the case that broke the demo loop when I consumed both buttons: open a
	# menu to Take, right-click a free tile to aim the next placement, and the aim was swallowed -- so
	# Place landed on the stale target and the sim refused it.
	if ok:
		_click(screen, spot, MOUSE_BUTTON_LEFT)
		var aim: Vector2i = screen._my_tile() + Vector2i(0, 1)
		_asked.clear()
		_click(screen, aim, MOUSE_BUTTON_RIGHT)
		if screen._menu_at != -1:
			ok = _fail("a right click on %s left the menu open at %d" % [aim, screen._menu_at])
		elif not _asked.is_empty():
			ok = _fail("the right click that closed the menu asked for %s" % [_asked])
		elif screen._target_tile() != aim:
			ok = _fail("a right click that closed a menu left the target at %s, not %s"
					% [screen._target_tile(), aim])
	screen.queue_free()
	return ok


## **A SLOT BUTTON SENDS THE WHOLE STACK INTO THE MENU'S OWN MACHINE, COUNTED AT THE PRESS; A FRACTION
## SENDS ITS OWN NUMBER** (ASSA-316, Maren's ruling 4).
##
## **THE BUILDING IS THE MENU'S AND NOT `_target_tile`'s, AND THAT IS THE ASSERTION WORTH HAVING.** The
## pack row's `Fuel` found its building through the placement cursor; a menu already knows which machine
## it is about. **That row is deleted (ASSA-331) and `_insert_into` has one caller now**, so a menu that
## quietly used the cursor would pass every other check in this file.
##
## **AND THE SLOT IS PINNED EXACTLY, WHICH IT COULD NOT BE YESTERDAY.** This read *"either slot is a
## pass and the count is not"*, because the button's label named neither and the harness may not decide
## that ore is fuel. Maren's ASSA-331 label ruling put the slot IN the label, so the press can be aimed
## at the fuel slot and the command checked against it -- the hedge was a cost of the wording, not a
## principle. Which slots exist is still asked of the sim (`insert_slots`), never assumed.
func test_a_slot_button_fuels_the_menus_machine_with_the_count_at_the_press() -> bool:
	var screen := _joined()
	var ok := true
	var id := _a_placed_smelter(screen)
	if id < 0:
		screen.queue_free()
		return false
	var spot: Vector2i = screen._target_tile()
	# THE CURSOR IS MOVED OFF THE MACHINE FIRST, so a menu reading `_target_tile` cannot pass by luck.
	_click(screen, screen._my_tile(), MOUSE_BUTTON_RIGHT)
	_click(screen, spot, MOUSE_BUTTON_LEFT)
	var ore := _stack_of(screen, "ore")
	if ore.is_empty():
		screen.queue_free()
		return _fail("no ore in the pack to put into a slot")
	var held := _counted(screen, ore)
	if not Array(AssayHud.insert_slots(ore, AssaySimHost.recipes())).has(AssayActions.SLOT_FUEL):
		screen.queue_free()
		return _fail("the sim offers ore no fuel slot, so this test is aimed at a button that cannot "
				+ "exist")
	var label := AssayHud.insert_label(held, String(ore.get("name", "?")), AssayActions.SLOT_FUEL)
	var whole := _find(screen._menu_box, label)
	if whole == null:
		ok = _fail("no `%s` button in the menu: %s" % [label, _labels_of(screen._menu_box)])
	else:
		_asked.clear()
		whole.pressed.emit()
		var want: Variant = AssayActions.insert(id, AssayActions.SLOT_FUEL,
				AssayActions.item_of_stack(ore), held)
		if _asked.size() != 1:
			ok = _fail("a slot button asked for %s" % [_asked])
		elif _asked[0] != want:
			ok = _fail("`%s` asked for %s, not %s" % [label, _asked[0], want])
	# THE FRACTION SENDS ITS OWN NUMBER. `put 1` is the one count every stack of two or more offers.
	#
	# **THE FRACTIONS STILL DO NOT NAME THEIR SLOT, SO THIS HALF KEEPS THE HEDGE ON PURPOSE** -- the two
	# `put 1` buttons under the two slot rows read alike, and the one found here is whichever the sim's
	# slot order put first. Maren's ASSA-334 §5 renamed them (`or 1` is not a sentence) and did NOT ask
	# for the slot in them, while her acceptance box asks that no two buttons in the menu read alike;
	# those two cannot both hold here, and the reason I kept her sentence over her box is her own ruling
	# 6: with the slot in the row's own button, repeating it twice more under it is the same answer three
	# times. It is cheap to reverse -- one argument to `insert_some_label` -- and it is hers.
	if ok and AssayHud.insert_fractions(held).size() > 0:
		var some := _find(screen._menu_box, AssayHud.insert_some_label(1))
		if some == null:
			ok = _fail("a stack of %d offers no `or 1`: %s" % [held, _labels_of(screen._menu_box)])
		else:
			_asked.clear()
			some.pressed.emit()
			var one: Variant = AssayActions.insert(id, AssayActions.SLOT_FUEL,
					AssayActions.item_of_stack(ore), 1)
			var one_in: Variant = AssayActions.insert(id, AssayActions.SLOT_INPUT,
					AssayActions.item_of_stack(ore), 1)
			if _asked.size() != 1:
				ok = _fail("`put 1` asked for %s" % [_asked])
			elif _asked[0] != one and _asked[0] != one_in:
				ok = _fail("`put 1` asked for %s, not an Insert of 1 into building %d"
						% [_asked[0], id])
	screen.queue_free()
	return ok


## **OPENING A MACHINE'S MENU AIMS THE VERBS AT THAT MACHINE** (ASSA-366; Maren amending her ASSA-316
## ruling 8: *"opening a machine's menu also targets that machine ... a mechanism no gesture invokes is
## not a design, it is dead weight"*).
##
## **THIS IS THE FIXTURE THAT SEPARATES THE RULES, AND NO OTHER TEST IN THE FILE HAS IT.** Every other
## menu test places its smelter on the targeted tile, so the acted-on tile and the menu's machine are
## the same tile and every rule ever written here predicts the same mark -- which is how ruling 8
## shipped and was measured green, and why no fixture could tell "the menu moves the target" from "the
## menu leaves it alone". Here the cursor is aimed at my own feet FIRST and the menu is then opened on
## a machine a tile away, so the assertion is about a target that MOVED.
##
## **IT ASSERTED THE OPPOSITE UNTIL ASSA-366 AND THE HISTORY IS THE POINT.** Under ruling 8 this read
## *"the ring stays on the acted-on tile while a menu's machine is elsewhere"* -- and it was right about
## the rule it was written for. What nobody had measured was the consequence: `_unhandled_input` returns
## into the menu above the one line that assigns `_target`, so **a player could never aim at a standing
## building at all**, and the "elsewhere" in the old name was the only reachable state rather than an
## edge case. Maren amended her own ruling on ASSA-348 rather than let the mark keep a meaning no
## gesture could produce.
##
## THE ORDER OF THE TWO GESTURES IS STILL FORCED by her ruling 7 amendment: a right-click that dismisses
## a menu still aims, so right-clicking AFTER opening would close the menu. Aim first, then open.
func test_opening_a_menu_aims_the_verbs_at_that_machine() -> bool:
	var screen := _joined()
	var ok := true
	var id := _a_placed_smelter(screen)
	if id < 0:
		screen.queue_free()
		return false
	var machine: Vector2i = screen._target_tile()
	var feet: Vector2i = screen._my_tile()
	if machine == feet:
		screen.queue_free()
		return _fail("the smelter stands on my own feet, so this fixture cannot tell the two apart")
	_click(screen, feet, MOUSE_BUTTON_RIGHT)
	# THE PREMISE, ASSERTED RATHER THAN ASSUMED: without this the test could pass on a client that never
	# moved the target at all, if the smelter happened to be where the cursor already was.
	if screen._target_tile() != feet:
		screen.queue_free()
		return _fail("aiming at my own feet %s left the cursor on %s" % [feet, screen._target_tile()])
	_click(screen, machine, MOUSE_BUTTON_LEFT)
	# **BOTH SIDES ARE `Rect2i` SINCE ASSA-348 AND THAT IS NOT A CAST.** The ring carries the subject's
	# whole footprint now, so comparing it to a bare `Vector2i` would be false whatever the mark did --
	# a guard that can no longer fire. Asked of `_footprint_tiles`, the same sim crossing the screen uses.
	var machine_area: Rect2i = screen._footprint_tiles(machine)
	if screen._menu_at != id:
		ok = _fail("the menu did not open on the machine at %s" % machine)
	elif screen._target_tile() != machine:
		ok = _fail(("the menu opened on the machine at %s and the verbs still act on %s: the one subject "
				+ "three of the five verbs take is the one a player cannot aim at")
				% [machine, screen._target_tile()])
	elif screen._world.selection != machine_area:
		ok = _fail("the verbs act on %s and the ring is on %s" % [machine_area, screen._world.selection])
	# **AND THE `do` COLUMN NAMES THE SAME SUBJECT IN THE SAME FRAME** -- the half a `_refresh_world()`
	# would miss. This is the defect ASSA-334 was filed for and it survived into my own 1x evidence
	# (`nacre-assa334-anchor/14-machine-menu.png`: the panel said `Tonore smelter (A)` while the column
	# said `acting on (57, 59) · on a deposit`), so it is asserted here rather than trusted to a refresh.
	if ok:
		var said := _text_of(screen._actions)
		if not said.contains("%d, %d" % [machine.x, machine.y]):
			ok = _fail(("the menu is open on the machine at %s and the `do` column says: %s")
					% [machine, said])
	screen.queue_free()
	return ok


## **CLOSING THE MENU LEAVES THE TARGET WHERE THE MENU PUT IT** (ASSA-366, Maren's condition 2: *"the
## ring is the trace of what you were working on, and the `do` column's verbs still need somewhere to
## point"*).
##
## **IT GUARDS A DECISION THAT IS CURRENTLY AN ABSENCE.** `_close_machine_menu` clears `_menu_at` and
## nothing else, so condition 2 holds today by nobody having written a line -- and that is exactly the
## kind of behaviour that gets "tidied" into a clear by the next person reading the open/close pair and
## making them symmetrical. Her condition says they are not symmetrical on purpose.
func test_closing_a_menu_leaves_the_verbs_aimed_at_its_machine() -> bool:
	var screen := _joined()
	var ok := true
	var id := _a_placed_smelter(screen)
	if id < 0:
		screen.queue_free()
		return false
	var machine: Vector2i = screen._target_tile()
	_click(screen, machine, MOUSE_BUTTON_LEFT)
	if screen._menu_at != id:
		screen.queue_free()
		return _fail("the menu did not open on the machine at %s" % machine)
	# **`close_text()` AND NOT THE STRING ITSELF** -- that function exists because a literal in two places
	# is what ASSA-62 was, and a test matching a label by hand rots the same silent way a tool does.
	var close := _find(screen._menu_box, AssayHud.close_text())
	if close == null:
		ok = _fail("the menu offers no named close: %s" % [_labels_of(screen._menu_box)])
	else:
		close.pressed.emit()
		if screen._menu_at != -1:
			ok = _fail("the named close left the menu open at %d" % screen._menu_at)
		elif not screen._targeted or screen._target_tile() != machine:
			ok = _fail(("closing the menu moved the verbs off %s to %s: the trace of what you were "
					+ "working on is gone with the panel") % [machine, screen._target_tile()])
		elif screen._world.selection != screen._footprint_tiles(machine):
			ok = _fail("the menu closed and the ring went to %s" % [screen._world.selection])
	screen.queue_free()
	return ok


## **PICK THE MACHINE UP AND THE RING COLLAPSES TO ONE TILE** (ASSA-366, and this is the MEASUREMENT I
## handed Maren back instead of building her condition 1).
##
## Her condition was *"the ring may not outlive its subject"*, against the hazard that *"the first thing
## a player does after picking a machine up is look at a footprint ring around bare ground"*. **That
## cannot happen, and this is the proof rather than my say-so**: `_refresh_world` re-reads
## `_footprint_tiles(_target)` every refresh and that function asks the sim what stands on the tile, so
## the tick the building leaves, the ring is one tile -- which `_footprint_tiles`' own docstring calls
## the right answer rather than a fallback, because `Place` carries a `TilePos`.
##
## **WHAT SURVIVES IS A PLACEMENT CURSOR ON THE TILE YOU JUST CLEARED**, indistinguishable from a
## deliberate right-click there, and the state that lets you press `Place` and put the machine back.
## Clearing it would send the next placement to your feet and would cost a new `_target_building` id to
## compare against -- new state, which is what her own safety argument for this ruling rests on not
## having. Hers to reverse; this test is what she would be reversing.
func test_picking_a_machine_up_leaves_a_one_tile_cursor_and_not_a_ring_round_nothing() -> bool:
	var screen := _joined()
	var ok := true
	var id := _a_placed_smelter(screen)
	if id < 0:
		screen.queue_free()
		return false
	var machine: Vector2i = screen._target_tile()
	_click(screen, machine, MOUSE_BUTTON_LEFT)
	var span: Rect2i = screen._footprint_tiles(machine)
	# THE PREMISE: a 1x1 would make the collapse invisible, so the fixture is refused rather than passed.
	if span.size == Vector2i.ONE:
		screen.queue_free()
		return _fail("the sim says this machine is one tile, so nothing can be seen to collapse")
	if screen._world.selection != span:
		ok = _fail("the menu is open and the ring is %s, not the footprint %s"
				% [screen._world.selection, span])
	var away := _find(screen._menu_box, "Pick up")
	if away == null:
		ok = _fail("the machine menu offers no Pick up: %s" % [_labels_of(screen._menu_box)])
	elif ok:
		away.pressed.emit()
		_tick(screen, 8)
		if screen._sim.tile_at(machine).get("building") != null:
			ok = _fail("the sim still has a building on %s, so nothing was picked up" % machine)
		elif screen._world.selection != Rect2i(machine, Vector2i.ONE):
			ok = _fail(("the machine is gone and the ring is %s: a %s ring around bare ground is the "
					+ "thing Maren's condition 1 was written against")
					% [screen._world.selection, span.size])
		elif screen._target_tile() != machine:
			ok = _fail("the machine is gone and the placement cursor left %s for %s"
					% [machine, screen._target_tile()])
	screen.queue_free()
	return ok


## **A SMELTER IS OUTLINED WHOLE, AND THE QUARTER THAT WAS CLICKED IS NOT THE SUBJECT** (ASSA-348;
## Maren: *"the outline follows the subject, and the sim says what the subject is"*).
##
## `Take`, `Pickup` and `Insert` all carry a `BuildingId` (`sim/src/command.rs`), so on three of the
## five verbs the subject is a whole building and a smelter covers four tiles. Before this the ring
## marked one of them -- and since the menus shipped, the anchored panel and the ring were two marks
## on screen disagreeing about the extent of one machine.
##
## **THE SECOND HALF IS ASKED OF A QUARTER THE PLAYER CANNOT CURRENTLY TARGET, AND THAT IS DELIBERATE
## RATHER THAN THOROUGH.** A click on an occupied tile opens that machine's menu and returns
## (`_unhandled_input`), so `_target` only ever lands on a building at its placement anchor, where
## `pos` and the clicked tile are the same tile and the two rules cannot be told apart -- the exact
## shape of ruling 8 shipping green. `_footprint_tiles` is asked about the far quarter directly,
## against the same live sim, so the fixture's blind spot is named instead of being mistaken for
## coverage.
func test_a_smelters_outline_is_its_whole_footprint_and_not_one_quarter() -> bool:
	var screen := _joined()
	var ok := true
	if _a_placed_smelter(screen) < 0:
		screen.queue_free()
		return false
	_tick(screen, 1)
	var spot: Vector2i = screen._target_tile()
	var building: Variant = screen._sim.tile_at(spot).get("building")
	if building == null:
		screen.queue_free()
		return _fail("no smelter at the targeted tile %s" % spot)
	var at: Dictionary = building
	var pos: Vector2i = at.get("pos", spot)
	var span: Vector2i = at.get("footprint", Vector2i.ONE)
	# THE FIXTURE ONLY MEANS SOMETHING IF THE SIM REALLY CALLS THIS THING 2x2.
	if span != Vector2i(2, 2):
		ok = _fail("the sim says this smelter is %s, so it cannot show a 2x2 outlined whole" % span)
	elif screen._world.selection != Rect2i(pos, span):
		ok = _fail(("the ring is %s and the sim says the building is %s at %s: press Pick up and the "
				+ "sim takes the whole smelter while the mark claims a quarter of it")
				% [screen._world.selection, span, pos])
	# EVERY QUARTER ANSWERS THE SAME BUILDING, asked of the sim crossing the screen itself uses.
	for quarter in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var got: Rect2i = screen._footprint_tiles(pos + (quarter as Vector2i))
		if got != Rect2i(pos, Vector2i(2, 2)):
			ok = _fail("the quarter at %s reports the subject %s, not the whole smelter at %s"
					% [pos + (quarter as Vector2i), got, pos])
			break
	# AND THE CONTROL: BARE GROUND IS STILL EXACTLY ONE TILE. `Place` and `PlaceAssembly` carry a
	# `TilePos`, so a footprint there would overstate the subject as badly as a quarter understates
	# it -- and without this clause a `_footprint_tiles` that returned 2x2 for everything would pass.
	var bare: Vector2i = screen._my_tile()
	if screen._sim.tile_at(bare).get("building") == null:
		var one: Rect2i = screen._footprint_tiles(bare)
		if one != Rect2i(bare, Vector2i.ONE):
			ok = _fail("bare ground at %s reports the subject %s; `Place` takes a TilePos, so one "
					% [bare, one] + "tile is the right answer there and not a fallback")
	screen.queue_free()
	return ok


## **THE STATE LINE COMES BACK OUT OF `FAILED` WHEN THE MACHINE STOPS BEING STALLED** (ASSA-334).
##
## **THE BUG THIS CLOSES REACHED A SCREENSHOT AND NO NUMBER SAW IT.** The refresh read the ordinary
## ink back off the Label with `get_theme_color`, which answers out of that node's OWN overrides
## first -- so after one stall the colour it restored was the `FAILED` it had just written, and the
## line stayed red for the rest of the session. `nacre-assa334-anchor/14-machine-menu.png` had
## `idle: nothing to refine` in (242,102,89) on a smelter the sim called idle.
##
## **IT FORCES THE RED RATHER THAN WAITING FOR A STALL**, which is the honest way to test a
## transition whose other half needs fuel, a fire and twenty ticks: the defect is in the RESTORE, so
## the fixture is "red is on the node, now refresh an idle machine".
func test_an_idle_machines_state_line_is_not_left_in_the_failure_ink() -> bool:
	var screen := _joined()
	var ok := true
	if _a_placed_smelter(screen) < 0:
		screen.queue_free()
		return false
	_click(screen, screen._target_tile(), MOUSE_BUTTON_LEFT)
	var failed := AssayHud.status_color(AssayHud.Say.FAILED)
	var facts: Dictionary = screen._sim.tile_at(screen._menu_tile).get("building", {})
	if AssayHud.state_is_failure(String(facts.get("state", ""))):
		screen.queue_free()
		return _fail("this smelter IS stalled (%s), so the restore is not what is being tested"
				% facts.get("state"))
	screen._menu_state.add_theme_color_override(&"font_color", failed)
	screen._refresh_machine_menu()
	var got: Color = screen._menu_state.get_theme_color(&"font_color")
	if got == failed:
		ok = _fail("the machine is `%s` and its line is still drawn in FAILED %s"
				% [facts.get("state"), got])
	# AND THE CONTROL: a stall must still be able to turn it red, or the check above passes on a menu
	# that never uses the failure ink at all.
	screen._menu_state.add_theme_color_override(&"font_color",
			AssayHud.status_color(AssayHud.Say.FAILED) \
			if AssayHud.state_is_failure("stalled") else screen._menu_state_ink)
	if ok and screen._menu_state.get_theme_color(&"font_color") != failed:
		ok = _fail("a stalled machine's line does not reach the failure ink either")
	screen.queue_free()
	return ok


## **EVERY SLOT THE MACHINE HAS DRAWS ITS FILL AS A BAND, AND A MACHINE WITH NO BATCH DRAWS NONE**
## (ASSA-339; Maren's ASSA-316 ruling 5, and Marlow's two conditions on it).
##
## **THE SLOT LIST IS THE SIM'S AND THE TEST WALKS IT**, so a menu that drew two of the three slots a
## smelter has would fail rather than look complete. `output` takes no insert and still gets a row: it
## is the slot that answers *is there anything for Take*, and under ASSA-316 it had no line at all.
##
## **THE NIL CASE IS THE ONE MARLOW NAMED AND IT IS ASSERTED AS NIL, NOT AS ZERO** -- *"`0 of 100` on a
## drill standing on bare ground is a number that reads as a promise"*. A fresh smelter has nothing in
## front of it, so `work` is nil and the batch row must be ABSENT; the control is that the slot bands,
## on the same surface in the same grammar, are present in the same frame. Without that control a menu
## that drew no bands at all would pass the half this test exists for.
func test_every_slot_draws_a_band_and_a_machine_with_no_batch_draws_none() -> bool:
	var screen := _joined()
	var ok := true
	if _a_placed_smelter(screen) < 0:
		screen.queue_free()
		return false
	_click(screen, screen._target_tile(), MOUSE_BUTTON_LEFT)
	var facts: Dictionary = screen._sim.tile_at(screen._menu_tile).get("building", {})
	var slots: Array = facts.get("slots", [])
	if slots.is_empty():
		screen.queue_free()
		return _fail("the sim gives this smelter no slots, so this test asserts nothing")
	for entry in slots:
		var slot: Dictionary = entry
		var role := String(slot.get("role", "?"))
		var row: Variant = screen._menu_slot_rows.get(role)
		if row == null:
			ok = _fail("the `%s` slot has no row in the menu: %s"
					% [role, screen._menu_slot_rows.keys()])
			break
		var band := (row as Node).get_node(screen.ROW_BAND) as AssayTrack
		var counts := ((row as Node).get_node(screen.ROW_COUNTS) as Label).text
		if band.grammar() != AssayTrack.Grammar.AMOUNT:
			ok = _fail("the `%s` slot's band is grammar %d, not an amount" % [role, band.grammar()])
			break
		# THE NUMBERS ARE THE SIM'S PAIR AND NOT A RATIO THIS CLIENT WORKED OUT.
		var want := AssayHud.amount_counts_line(int(slot.get("count", 0)), int(slot.get("cap", 0)))
		if counts != want:
			ok = _fail("the `%s` slot reads `%s` and the sim says `%s`" % [role, counts, want])
			break
	if ok and facts.get("work") != null:
		ok = _fail("a freshly placed smelter reports a batch (%s), so the nil case is untested here"
				% [facts.get("work")])
	if ok and screen._menu_work.visible:
		ok = _fail("there is no batch and the menu draws a row for it: `%s`"
				% (screen._menu_work.get_node(screen.ROW_COUNTS) as Label).text)
	if ok and (screen._menu_work.get_node(screen.ROW_BAND) as AssayTrack).grammar() \
			!= AssayTrack.Grammar.NOTHING:
		ok = _fail("there is no batch and its band has a grammar, so something is drawn for it")
	# **AND THE BURN STAYS TEXT, WHICH IS MARLOW'S RULING AND IS HERE SO NOBODY ADDS IT AS AN
	# OVERSIGHT.** A fire's denominator is `reactivity * BURN_TICKS_PER_REACTIVITY`, a sim rule, and a
	# host multiplying it out would be writing that rule in GDScript. So `burn_left` gets no band: the
	# only bands in this menu are the slots' fills and the batch, one per slot plus at most one.
	if ok:
		var bands := 0
		for node in _tracks_of(screen._menu_box):
			bands += 1 if (node as AssayTrack).grammar() != AssayTrack.Grammar.NOTHING else 0
		if bands != slots.size():
			ok = _fail(("%d bands are drawn for %d slots and no batch: a burn band is Marlow's to add "
					+ "in the sim, not this file's to divide") % [bands, slots.size()])
	screen.queue_free()
	return ok


## EVERY `AssayTrack` UNDER A NODE, so a band count is a fact about the tree rather than about the
## names this test remembers.
func _tracks_of(node: Node) -> Array:
	var out := []
	for child in node.get_children():
		if child is AssayTrack:
			out.append(child)
		out.append_array(_tracks_of(child))
	return out


## **NO TWO `put all` BUTTONS IN THE MENU READ ALIKE** (ASSA-334 §5; Maren: *"two buttons both reading
## `put all 2 Tonore refined (A)`, told apart only by the heading above them, are one label twice"*).
##
## **IT IS THE `put all` BUTTONS AND NOT EVERY BUTTON, WHICH IS A READING OF HER RULING RATHER THAN HER
## BOX.** Her acceptance asks that no two buttons in the menu carry identical labels; the fraction
## toggles under one slot's button are `put 1` and `put 18`, and they repeat under the next slot. Her
## own §5 sentence renamed them and did not ask for the slot in them -- and naming the slot in a
## fraction would put it three times in three consecutive lines, which is her ruling 6. Said here
## because this test is where somebody would come looking for it.
func test_no_two_put_all_buttons_in_a_machine_menu_read_alike() -> bool:
	var screen := _joined()
	var ok := true
	if _a_placed_smelter(screen) < 0:
		screen.queue_free()
		return false
	_click(screen, screen._target_tile(), MOUSE_BUTTON_LEFT)
	var seen := {}
	var puts := 0
	for label in _labels_of(screen._menu_box):
		if not label.begins_with("put all"):
			continue
		puts += 1
		if seen.has(label):
			ok = _fail("two buttons in the menu read `%s`" % label)
			break
		seen[label] = true
	# **A STACK THE SIM TAKES AS EITHER FUEL OR INPUT IS WHAT THE RULING IS ABOUT**, so one button is
	# not evidence: with a single slot row the check above cannot fail.
	if ok and puts < 2:
		ok = _fail("only %d `put all` button(s) in this menu, so two cannot be compared: %s"
				% [puts, _labels_of(screen._menu_box)])
	screen.queue_free()
	return ok


## **BOTH BRANCHES OF A COST ENTRY, STATED RATHER THAN MINED FOR** (ASSA-332; Maren's §5.5: two
## rows, name then counts right-aligned, and the WHOLE entry in `FAILED` when have < need).
##
## **DRIVEN THROUGH `_cost_entry` WITH TWO PAIRS OF `int`s**, for the reason on that function: an
## offer this file invents never survives `_chosen_offer`, and whether a seeded fixture's pack happens
## to be short of the recipe it opens is worldgen's business. A `FAILED` branch that only a lucky
## fixture reaches is my own written-down hole -- a state green for free.
func test_a_cost_entry_is_two_rows_and_goes_failed_whole_when_short() -> bool:
	var screen := _joined()
	var ok := true
	var lacking: Node = screen._cost_entry("Bokase refined (B)", 3, 1)
	var plenty: Node = screen._cost_entry("Bokase refined (B)", 1, 2)
	var failed := AssayHud.status_color(AssayHud.Say.FAILED)
	for entry in [lacking, plenty]:
		if ok and (entry as Node).get_child_count() != 2:
			ok = _fail("a cost entry drew %d rows; §5.5 says name then counts, always"
					% (entry as Node).get_child_count())
	if ok:
		var named := lacking.get_child(0) as Label
		var counts := lacking.get_child(1) as Label
		if named.text != "Bokase refined (B)":
			ok = _fail("the name row says `%s`; it is the sim's `name` on the pack stack" % named.text)
		elif counts.text != "need 3 · have 1":
			ok = _fail("the counts row says `%s`" % counts.text)
		elif counts.horizontal_alignment != HORIZONTAL_ALIGNMENT_RIGHT:
			ok = _fail("the counts are not right-aligned, so block 6 is not a column you can scan")
		elif not named.has_theme_color_override(&"font_color") \
				or not counts.has_theme_color_override(&"font_color"):
			ok = _fail("a short entry left a row in the ordinary ink; §5.5 says the WHOLE entry")
		elif named.get_theme_color(&"font_color") != failed:
			ok = _fail("a short entry's name is drawn %s and FAILED is %s"
					% [named.get_theme_color(&"font_color"), failed])
	if ok:
		# **AND THE ENTRY YOU CAN AFFORD TAKES NO STATUS INK AT ALL** -- the half a lucky fixture would
		# never have shown. `FAILED` on every entry is as wrong as on none, and this is the mutation my
		# own rule asks for: make the comparison matter in both directions.
		for row in plenty.get_children():
			if (row as Label).has_theme_color_override(&"font_color"):
				ok = _fail("an affordable entry's `%s` is painted in the status scale"
						% (row as Label).text)
				break
	# NEITHER ENTRY WAS EVER PARENTED, so freeing the screen does not take them with it,
	# and `free()` rather than `queue_free()` because this suite runs inside
	# `SceneTree._initialize`: a queued free may never reach an idle frame.
	lacking.free()
	plenty.free()
	screen.queue_free()
	return ok


## **THE OUTPUT PICTURE LEAVES THE PLATE THAT THE PACK ROWS KEEP** (ASSA-341 boxes 1 and 2; Maren's
## ruling off my own 1x shot, overturning the half of her own ASSA-71 that does not travel).
##
## The sprite measures **1.24:1** on the olive plate and **5.57:1** on the panel's own ground. Her
## rule is a bar -- *any sprite placed on that plate must clear 3:1 against it* -- so ASSA-71 stands
## for the pack, where a LIST of ore is both what the plate was measured on and what it is for.
##
## **BOTH HALVES IN ONE TEST, BECAUSE EITHER ONE ALONE IS SATISFIED BY DELETING THE PLATE ENTIRELY.**
## A test that only asserted the build screen has no plate would go green if `plated` were ignored
## and `pack_icon_plate` returned transparent -- which is the ruling inverted, the pack losing the one
## surface its species spread needs. So the assertion is the PAIRING: gone here, still there.
##
## **AND IT IS ABOUT THE COLOUR THAT IS PAINTED, NOT ABOUT A NODE CLASS.** Wrapping the art in some
## other container that draws the same ink would be a different implementation of the same defect,
## and a class check would call it fixed.
func test_the_output_picture_leaves_the_plate_the_pack_rows_keep() -> bool:
	var plate := AssaySprites.pack_icon_plate()
	if plate.a <= 0.0:
		# NOT A VERDICT ABOUT THE SCREEN. With no plate colour at all the two grounds ARE the same
		# ground, so this test cannot tell them apart; it names the thing that is missing rather than
		# reporting a contrast win it never measured.
		return _fail(("`pack_icon_plate()` is %s -- transparent, so nothing here draws the plate and "
				+ "this test cannot tell the pack's ground from the panel's. `ui_theme.json` is "
				+ "missing from `res://`, which is its own defect.") % [plate])
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var launcher := _make_launcher_for(screen, "smelter")
		if launcher == null:
			ok = _fail("no menu row offers a smelter: %s" % _text_of(screen._make))
		else:
			launcher.pressed.emit()
			var on_plate := _nodes_on_plate(screen._build_detail, plate)
			if not on_plate.is_empty():
				ok = _fail(("the build screen's picture still stands on the pack plate %s (%s); the "
						+ "sprite reads 1.24:1 on it and 5.57:1 on the panel's own ground")
						% [plate, on_plate])
			# THE OTHER HALF: the pack still stands on it, or ASSA-71 was deleted rather than scoped.
			if ok and _nodes_on_plate(screen._carrying, plate).is_empty():
				ok = _fail(("no pack row stands on the plate %s any more. ASSA-71 is unchanged for the "
						+ "pack -- the species spread closes BECAUSE the list sits on one surface, and "
						+ "only the build screen's single picture was exempted") % [plate])
	screen.queue_free()
	return ok


## **THE OUTPUT PICTURE IS THE AUTHORED FRAME AT A WHOLE-NUMBER SCALE, AND THE SCALE IS THE ROOM'S
## ANSWER AND NOT A NUMBER ANYONE TYPED** (ASSA-357 box 5; Maren's box 4 ruling, 3x today).
##
## **THE CLAIM IS THE RATIO, WHICH IS WHY THIS CANNOT BE SATISFIED BY A SECOND TYPED SIZE.** Until
## tonight the box was `(ICON_PX, ICON_PX)` = 32x32 under a 64x96 frame -- `32/64` and `32/96`, two
## different ratios, neither whole. Any box that is the frame times one whole number passes; any box
## that is a size someone picked does not, because two axes of a 2:3 frame only agree when the
## multiplier is the same on both.
##
## **AND THE 32x32 WAS NOT DRAWING AT 32 EITHER, WHICH IS WHY THE RATIO IS THE CLAIM AND NOT THE
## SIZE.** `KEEP_ASPECT_CENTERED` fits by the smaller ratio, so the shipped box drew the frame at
## 1/3; measured off the paint in a 1x window, the smelter's ink was **17 x 22 px**
## (`shared/assay/limpet-assa363-centres/build-screen-14247.png`, x 675..691 y 146..167). A test that
## asserted a SIZE would have gone green on a box whose contents were a third of it.
##
## **AND THE UPPER BOUND IS RE-DERIVED HERE RATHER THAN ASKED OF THE CODE UNDER TEST.** A test that
## called `_build_picture_room` would assert only that the call site uses it. This walks the screen's
## own rect, the panel's own padding and the crown's own minimum to the columns region, and asserts
## block 5's whole content fits inside it -- which is ASSA-362's property, the P0 that says a
## shrinking section's content is a hard floor under the window.
func test_the_output_picture_is_the_authored_frame_at_a_whole_scale_of_its_room() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var launcher := _make_launcher_for(screen, "smelter")
		if launcher == null:
			ok = _fail("no menu row offers a smelter: %s" % _text_of(screen._make))
		else:
			launcher.pressed.emit()
			var art: TextureRect = null
			for child in screen._build_detail.get_children():
				var rect_node := child as TextureRect
				if rect_node != null and rect_node.texture != null:
					art = rect_node
			if art == null:
				ok = _fail(("block 5 holds no picture at all: %s. This block's whole job is showing "
						+ "the object you are about to spend parts on")
						% [screen._build_detail.get_children()])
			else:
				var frame := art.texture.get_size()
				var box := art.custom_minimum_size
				var across := box.x / frame.x
				var down := box.y / frame.y
				if not is_equal_approx(across, down):
					ok = _fail(("the picture's box is %s under a %s frame -- %.3f across and %.3f "
							+ "down. A box that is not the frame times ONE number is a size someone "
							+ "picked, and `KEEP_ASPECT_CENTERED` then throws the larger ratio away")
							% [box, frame, across, down])
				elif not is_equal_approx(across, floorf(across)):
					ok = _fail(("the picture's box is %s under a %s frame, which is %.3f x -- a "
							+ "fractional scale is resampling, and Maren's ASSA-362 refusal is that "
							+ "a layout number is never paid for by resampling art") % [box, frame,
							across])
				elif across < 2.0:
					ok = _fail(("the picture is the frame at %.0fx (%s). Block 5 is the right "
							+ "column's only visible section on the make path and the one picture the "
							+ "screen is for; at 1x it is a pack row's icon") % [across, box])
				else:
					ok = _picture_fits_the_columns_region(screen, box)
	screen.queue_free()
	return ok


## **BLOCK 5's WHOLE CONTENT INSIDE THE COLUMNS REGION, DERIVED FROM THE SCREEN'S RECT** (ASSA-357
## box 5). Re-walked here on purpose -- see the test above -- out of `build_screen_rect`, the panel's
## own content margin, the crown's own minimum, two gutters and `BUILD_COMMIT_BAR`.
##
## **WHY A CONTENT OVERFLOW IS THE FAILURE AND NOT A CLIPPED PICTURE**: block 5 is built
## `fill := false`, so it is `SHRINK_BEGIN` with scrolling disabled and what stands in it is a FLOOR
## under the section, the column and the whole screen (ASSA-362). An oversized picture does not get
## cut off; it pushes `Build` off the window.
func _picture_fits_the_columns_region(screen: Node, box: Vector2) -> bool:
	var rect := AssayHud.build_screen_rect(AssayHud.world_rect(), screen._world_band_top())
	var pad := Vector2.ZERO
	var skin := (screen._build_box as Control).get_theme_stylebox(&"panel")
	if skin != null:
		pad = Vector2(skin.get_margin(SIDE_LEFT), skin.get_margin(SIDE_TOP))
	var gutter := float(screen.BUILD_GUTTER)
	var crown := (screen._build_crown as Control).get_combined_minimum_size().y
	var columns := AssayHud.build_columns_height(rect, pad, crown, gutter)
	var width := AssayHud.build_column_width(rect.size.x - pad.x * 2.0, screen.BUILD_COLUMNS,
			screen.BUILD_COLUMNS.size() - 1, gutter)
	if box.x > width:
		return _fail(("the picture is %.0f px wide in a %.0f px column, so it is the thing that sets "
				+ "the column's width") % [box.x, width])
	# THE BLOCK'S CONTENT: the heading, every row, and a separation between each pair.
	var air := float(screen._build_detail.get_theme_constant(&"separation"))
	var content := (screen._build_detail_heading as Control).get_combined_minimum_size().y + air
	var rows: Array = screen._build_detail.get_children()
	for at in rows.size():
		content += (rows[at] as Control).get_combined_minimum_size().y
		if at > 0:
			content += air
	if content > columns:
		return _fail(("block 5 asks for %.0f px inside a %.0f px columns region. A `SHRINK_BEGIN` "
				+ "section with scrolling disabled is a floor under the screen, so this is ASSA-362's "
				+ "P0 and it pushes `Build` off the window") % [content, columns])
	return true


## Every node under `root` painted with `ink` as its `panel` stylebox, named. Reads the override
## rather than the resolved theme box: the plate is applied as a `StyleBoxFlat` override, and asking
## the theme would return whatever `Panel` inherits for every node that has no plate at all.
func _nodes_on_plate(root: Node, ink: Color) -> PackedStringArray:
	var found := PackedStringArray()
	if root == null:
		return found
	var control := root as Control
	if control != null and control.has_theme_stylebox_override(&"panel"):
		var flat := control.get_theme_stylebox(&"panel") as StyleBoxFlat
		if flat != null and flat.bg_color.is_equal_approx(ink):
			found.append("%s (%s)" % [control.name, control.get_class()])
	for child in root.get_children():
		found.append_array(_nodes_on_plate(child, ink))
	return found


## **ON THE MAKE PATH THE TWO COUNTS ARE DRAWN ONCE, AND IN THE PICKER** (ASSA-341 ruling 3, boxes 4,
## 6 and 7; Maren's, off my own 1x shot, with her scope correction read first).
##
## The shot printed `need 5 · have 19` twice verbatim. It can never be otherwise here and that is the
## shape of the TYPE: `MakeOffer` carries `pub input: Item` -- singular -- so one offer is one recipe
## x one material, one `cost`, one `have`, and block 6's single entry is always the selected material
## row. A second copy of a sim sentence is the ASSA-43/52 defect named in `have_need_line`'s own
## docstring.
##
## **THE COUNTS THEMSELVES ARE NOT UNDER TEST AND MUST NOT BE** -- what the pack holds at this tick is
## worldgen's business. The string compared is the one the SIM's two numbers make
## (`cost_counts_line(offer.cost, offer.count)`), and the assertion is how many times that string is
## on screen. So this cannot pass by the counts being wrong in both places, and it cannot pass by the
## counts vanishing: her §3 keeps them in the picker, because comparing two materials must not cost
## two gestures.
##
## **BOTH OF BLOCK 6's NODES ARE ASSERTED, not just the rows.** Hiding the rows alone leaves the word
## `cost` standing over nothing and leaves every tool asking `_build_cost.visible` reading `true`
## about a block nobody can see -- ASSA-117's defect, which `_show_log` on this same screen exists to
## prevent.
func test_the_make_path_prints_the_two_counts_once_and_only_in_the_picker() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var launcher := _make_launcher_for(screen, "smelter")
		if launcher == null:
			ok = _fail("no menu row offers a smelter: %s" % _text_of(screen._make))
		else:
			launcher.pressed.emit()
			var offer: Dictionary = screen._chosen_offer()
			if offer.is_empty():
				ok = _fail("the screen opened on no offer at all, so there are no counts to count")
			else:
				var pair := AssayHud.cost_counts_line(int(offer.get("cost", 0)),
						int(offer.get("count", 0)))
				if screen._build_cost.visible or screen._build_cost_box.visible:
					ok = _fail(("block 6 is still shown on the make path (rows visible=%s, section "
							+ "visible=%s); its one entry can only ever be the material row above it")
							% [screen._build_cost.visible, screen._build_cost_box.visible])
				if ok:
					var seen := _visible_labels_with(screen._build_box, pair)
					if seen.size() != 1:
						# THE 0 CASE AND THE 2 CASE ARE DIFFERENT DEFECTS, so the message carries the
						# material column's text either way: 0 means the counts left the picker (or
						# that this test's visibility walk is wrong), 2 means the duplicate is back.
						ok = _fail(("`%s` is drawn %d times in one frame (%s). One offer is one recipe "
								+ "x one material, so a second copy is a copy by construction. The "
								+ "material column reads: %s")
								% [pair, seen.size(), seen, _text_of(screen._build_materials)])
					elif _visible_labels_with(screen._build_materials, pair).size() != 1:
						ok = _fail(("the counts are drawn once but not in the material column -- they "
								+ "are the picker (her §3); they ended up at %s") % [seen])
				var said := _text_of(screen._build_said)
				if ok and not said.contains(String(offer.get("line", ""))):
					ok = _fail(("the commit bar no longer carries the sim's sentence whole: it reads "
							+ "`%s` and the sim said `%s`") % [said, offer.get("line", "")])
	screen.queue_free()
	return ok


## Names of every Label under `root` whose text contains `needle` and which nothing BETWEEN IT AND
## `root` has hidden.
##
## **`is_visible_in_tree` IS THE OBVIOUS CALL AND IT IS WRONG HERE, MEASURED RATHER THAN REASONED.**
## My first version used it and the test failed with `drawn 0 times` while its own message printed
## the material column reading ` · need 5 · have 60 · ` -- the counts were right there. In this suite
## the screen is built but the window chain above it is not visible, so `is_visible_in_tree` is false
## for every node on it and the count would have been 0 whatever the screen did. **A check that
## answers 0 for every possible screen is not a check**, and it would have gone green the moment the
## duplicate came back, because 0 != 1 looks the same as 2 != 1 only until you read the number.
##
## So the walk stops at `root`: what is asked is "did anything on this screen hide it", which is the
## property the ruling is about (block 6's section hidden takes its rows with it) and the only part
## of visibility that a headless tree can honestly answer.
func _visible_labels_with(root: Node, needle: String) -> PackedStringArray:
	var found := PackedStringArray()
	for label in _labels_under(root, needle):
		var node: Node = label
		var shown := true
		while node != null and node != root:
			var control := node as Control
			if control != null and not control.visible:
				shown = false
				break
			node = node.get_parent()
		if shown:
			found.append("%s=`%s`" % [label.name, label.text])
	return found


## Every Label under `root` whose text contains `needle`, hidden or not.
func _labels_under(root: Node, needle: String) -> Array[Label]:
	var found: Array[Label] = []
	if root == null:
		return found
	var label := root as Label
	if label != null and label.text.contains(needle):
		found.append(label)
	for child in root.get_children():
		found.append_array(_labels_under(child, needle))
	return found


## A STACK SHAPED LIKE ONE PART KIND, out of the sim's own catalogue name. The species and grade are
## a real world's -- species 0 exists in every world worldgen makes -- because `design_readout` reads
## the species sheet to band a design even though it never looks at the pack.
func _part_stack_of(kind: String) -> Dictionary:
	return {"kind": kind, "species": 0, "species_name": "Testore", "grade": "C", "count": 1,
			"name": kind}


## The frame kind with the most room in it, and the one slot of that frame with the most room, both
## out of the SIM's catalogue rather than typed: a renamed kind or a fifth one must not rewrite a
## test, and `max` is the number the shape is drawn from.
func _roomiest_frame() -> Dictionary:
	var best := {}
	for entry in AssaySimHost.part_kinds():
		var row: Dictionary = entry
		if not bool(row.get("is_frame", false)):
			continue
		var widest := {}
		for slot in (row.get("slots", []) as Array):
			var limit: Dictionary = slot
			if widest.is_empty() or int(limit.get("max", 0)) > int(widest.get("max", 0)):
				widest = limit
		var room := int(widest.get("max", 0))
		if best.is_empty() or room > int(best.get("room", -1)):
			best = {"kind": String(row.get("name", "")), "room": room,
					"mounts": String(widest.get("name", "")), "slots": row.get("slots", [])}
	return best


## **THE SCREEN'S TWO MODES ARE THE SAME TWO RECTS DOING TWO JOBS** (ASSA-317 slice 2b; Maren's 00:32
## ruling (A): *"a player learns this screen once instead of twice"*).
##
## **BOTH DIRECTIONS AND THE HOLDERS AS WELL AS THE ROWS.** A section whose rows are hidden under a
## heading that is not is the ASSA-117 bug this very screen has had once already (`_show_log`), and it
## passes any test that only asks the rows.
##
## **AND BLOCK 5 IS HIDDEN WHILE ASSEMBLING, WHICH IS ASSERTED AS A STATE AND NOT AS A TODO**: her
## ruling makes that rect the mass/budget picture, so until it is drawn a heading reading `what you
## get` over nothing is a labelled empty gap.
func test_the_build_screen_swaps_block_three_between_making_and_assembling() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := _mine_some_ore(screen)
	if ok:
		var launcher := _make_launcher_for(screen, "ore")
		if launcher == null:
			ok = _fail("no menu row to open the screen on: %s" % _text_of(screen._make))
		else:
			launcher.pressed.emit()
			if not screen._build_materials.visible:
				ok = _fail("the material picker is hidden on the make path, where it IS the choice")
			elif screen._build_slots.visible or screen._build_mounts.visible:
				ok = _fail(("the make path shows the slots (%s) or the mount list (%s); a recipe has no "
						+ "slots") % [screen._build_slots.visible, screen._build_mounts.visible])
			elif not screen._build_detail.visible:
				ok = _fail("block 5 is hidden on the make path, where it holds the one picture")
			elif screen._build_title.text != "make":
				ok = _fail("the make path's title reads `%s`" % screen._build_title.text)
	if ok:
		screen._build_verb = screen.BUILD_ASSEMBLE
		screen._build_showing = screen.UNBUILT
		screen._refresh_build_screen()
		var heading: Label = screen._section_heading(screen._build_picker)
		if screen._build_materials.visible:
			ok = _fail("the material picker is shown while assembling; a design has no recipe material")
		elif not screen._build_slots.visible or not screen._build_mounts.visible:
			ok = _fail(("assembling shows the slots as %s and the mount list as %s; both are block 3 "
					+ "under ruling (A)") % [screen._build_slots.visible, screen._build_mounts.visible])
		elif screen._build_detail.visible:
			ok = _fail("block 5 is shown while assembling and its picture is the next slice")
		elif screen._build_title.text != "assemble":
			ok = _fail("the assembly path's title reads `%s`" % screen._build_title.text)
		elif heading == null or heading.text != "which frame":
			ok = _fail(("block 2's heading reads `%s` over a list of frames; a heading is this file's "
					+ "word for what is UNDER it") % [heading.text if heading != null else "<none>"])
		else:
			# AND WITH NOTHING IN THE PACK BOTH LISTS SAY SO RATHER THAN DRAWING NOTHING, which is this
			# screen's own rule on the make path: absence is never a cue.
			if not _text_of(screen._build_picker).contains("not carrying a frame"):
				ok = _fail("the frame list with no frame in the pack says `%s`"
						% _text_of(screen._build_picker))
	if ok:
		for rows in [screen._build_materials, screen._build_detail, screen._build_slots,
				screen._build_mounts]:
			var holder: Control = screen._section_holder(rows as Control)
			if holder == null or holder.visible != (rows as Control).visible:
				ok = _fail(("a section's rows are %s and its holder is %s, so a heading stands over a "
						+ "block nobody can see (ASSA-117)")
						% [(rows as Control).visible, "<none>" if holder == null else holder.visible])
				break
	screen.queue_free()
	return ok


## **A FRAME'S SLOTS ARE DRAWN AS A SHAPE, AND WHAT DOES NOT FIT IS DRAWN TOO** (ASSA-317 slice 2b;
## `assay-build-screen` §3, and Maren's 00:32 consequence: *"switching the frame may never silently
## unmount anything"*).
##
## **ONE BOX PER UNIT OF ROOM AND THE PARTS ARE ONE MORE THAN FITS**, so the overflow case is the
## case under test rather than a lucky fixture: `room + 1` hoppers on a `room` frame must draw `room`
## filled boxes and leave exactly one part with nowhere to stand.
##
## **THEN THE FRAME IS SWAPPED FOR THE ONE WITH THE LEAST ROOM AND NOTHING MAY VANISH.** The property
## is stated as a literal count of `_building` -- the array is the design, and a client that dropped
## the parts that no longer fit would leave a player's arrangement gone with no sentence anywhere
## (the ASSA-116 shape). The DRAWN count is held against it separately, because a shape that silently
## stopped drawing the extras would pass the first half.
func test_a_frames_slots_are_drawn_as_a_shape_and_nothing_mounted_is_dropped() -> bool:
	var screen := _joined()
	var ok := true
	var frame := _roomiest_frame()
	if frame.is_empty() or int(frame.get("room", 0)) <= 0 or String(frame.get("mounts", "")) == "":
		ok = _fail("the sim's catalogue offers no frame with room in it: %s" % [frame])
	else:
		var room := int(frame.get("room", 0))
		var mounts := String(frame.get("mounts", ""))
		screen._building = [_part_stack_of(String(frame.get("kind", "")))]
		for _i in range(room + 1):
			screen._building.append(_part_stack_of(mounts))
		screen._rebuild_build_slots()
		var rows := _slot_rows_of(screen)
		var standing := _boxes_holding_parts(screen)
		if not rows.has(mounts):
			ok = _fail("the shape draws no row for the `%s` slots: rows are %s" % [mounts, rows])
		elif int(rows.get(mounts, -1)) != room:
			ok = _fail(("the `%s` row draws %d boxes and the sim gives that slot room for %d; the shape "
					+ "is what states the limit") % [mounts, int(rows.get(mounts, -1)), room])
		elif not rows.has("nowhere to stand"):
			ok = _fail(("%d parts went onto a frame with room for %d and nothing is drawn as left over: "
					+ "rows are %s") % [room + 1, room, rows])
		elif int(rows.get("nowhere to stand", -1)) != 1:
			ok = _fail("one part too many is drawn as %d boxes with nowhere to stand"
					% int(rows.get("nowhere to stand", -1)))
		elif standing != room + 1:
			ok = _fail(("%d parts are mounted and %d boxes hold one; a part that is drawn nowhere is a "
					+ "part the player has lost") % [room + 1, standing])
		else:
			var carried: int = screen._building.size()
			var tight := _tightest_frame()
			screen._choose_frame(_part_stack_of(String(tight.get("kind", ""))))
			screen._rebuild_build_slots()
			if screen._building.size() != carried:
				ok = _fail(("the design held %d items and holds %d after the frame was swapped; switching "
						+ "a frame may never silently unmount anything")
						% [carried, screen._building.size()])
			elif _boxes_holding_parts(screen) != carried - 1:
				ok = _fail(("%d parts are mounted on the narrower frame and %d are drawn; the ones that no "
						+ "longer fit must be visible, not dropped")
						% [carried - 1, _boxes_holding_parts(screen)])
	screen.queue_free()
	return ok


## **A SLOT KIND IS READ AS A WORD, NOT A COLUMN OF LETTERS** (ASSA-362).
##
## `_slot_row`'s label comes from `_note`, which sets `AUTOWRAP_WORD_SMART` -- right for every
## sentence on this screen and wrong for a one-word label in an `HBoxContainer` that gives its width
## to the boxes. Squeezed under one character, WORD_SMART breaks ANYWHERE: the first 1x shot of this
## screen drew `h`/`e`/`a`/`d` stacked vertically beside the head box and `h`/`o`/`p`/`p`/`e`/`r`
## beside the hoppers.
##
## **IT WAS NOT COSMETIC.** This block is the one section built `fill := false`, so its
## `ScrollContainer` neither scrolls nor shrinks and its content is a hard floor under the whole
## screen: six letters tall twice over took the screen to 864x729 against an 864x592 rect, over both
## world controls, and put `Build` off the bottom of a 720 px window.
##
## **THE PROPERTY HELD IS THE MINIMUM WIDTH, AND THE FLAG IS CHECKED SECOND.** `AUTOWRAP_OFF` is the
## mechanism; what actually stops the squeeze is that such a Label reports its WHOLE TEXT as its
## minimum width, so no parent can give it less. A test on the flag alone would pass the day somebody
## reached the same wrap through a different property -- the Game Director's own ASSA-341 box 9
## ruling, that the flags which make a thing true are not the thing.
##
## **IT DOES NOT ASSERT THE SCREEN'S LAID-OUT HEIGHT AND DOES NOT PRETEND TO:** a container's minimum
## is recalculated DEFERRED, so asking this block its height right after building it answers the old
## number. The 137 px belongs to the 1x shot.
func test_a_slot_kinds_label_is_a_word_and_not_a_column_of_letters() -> bool:
	var screen := _joined()
	var ok := true
	var frame := _roomiest_frame()
	if frame.is_empty() or String(frame.get("kind", "")) == "":
		ok = _fail("the sim's catalogue offers no frame to draw slots for: %s" % [frame])
	else:
		screen._building = [_part_stack_of(String(frame.get("kind", "")))]
		screen._rebuild_build_slots()
		var checked := 0
		for child in screen._build_slots.get_children():
			var row := child as HBoxContainer
			if row == null or row.get_child_count() == 0:
				continue
			var label := row.get_child(0) as Label
			if label == null or label.text == "":
				continue
			checked += 1
			# THE SAME WORD MEASURED BY THE FONT, not a width this test invented. Two different engine
			# paths -- a Label's own minimum against `Font.get_string_size` -- so neither is checking
			# itself.
			var font := label.get_theme_font(&"font")
			var pt := label.get_theme_font_size(&"font_size")
			var word := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pt).x
			var least := label.get_minimum_size()
			if least.x + 1.0 < word:
				ok = _fail(("the `%s` slot label reports a %.0f px minimum width for a word that measures "
						+ "%.0f: a parent can squeeze it below one word, which is how it came to be drawn "
						+ "one letter per row") % [label.text, least.x, word])
				break
			elif least.y > BODY_ROW_PX + 1.0:
				ok = _fail(("the `%s` slot label is already %.0f px tall before any parent squeezes it, "
						+ "against one `BODY` row of %.0f") % [label.text, least.y, BODY_ROW_PX])
				break
			elif label.autowrap_mode != TextServer.AUTOWRAP_OFF:
				ok = _fail(("the `%s` slot label wraps (mode %d): a slot kind is one of the sim's words and "
						+ "must be read as one") % [label.text, label.autowrap_mode])
				break
		if ok and checked == 0:
			ok = _fail("the shape drew no labelled slot row at all, so nothing was measured")
	screen.queue_free()
	return ok


## The frame kind with the LEAST room, for the swap above.
func _tightest_frame() -> Dictionary:
	var best := {}
	for entry in AssaySimHost.part_kinds():
		var row: Dictionary = entry
		if not bool(row.get("is_frame", false)):
			continue
		var boxes: int = AssayHud.slot_boxes(row.get("slots", []) as Array).size()
		if best.is_empty() or boxes < int(best.get("boxes", 99)):
			best = {"kind": String(row.get("name", "")), "boxes": boxes}
	return best


## Each labelled row of the drawn shape and how many BOXES it holds: the row's first child is its
## label and the rest are boxes, which is `_slot_row`'s own order.
func _slot_rows_of(screen: Node) -> Dictionary:
	var rows := {}
	for child in screen._build_slots.get_children():
		var row := child as HBoxContainer
		if row == null or row.get_child_count() == 0:
			continue
		var label := row.get_child(0) as Label
		if label == null:
			continue
		rows[label.text] = row.get_child_count() - 1
	return rows


## How many drawn boxes hold a part. **Read off the tooltip rather than off a child count**, because
## a box's picture is `null` for any kind the art pipeline has no sprite for -- counting children
## would make this a test about `items.png` instead of about the fill.
func _boxes_holding_parts(screen: Node) -> int:
	var held := 0
	for child in screen._build_slots.get_children():
		for box in (child as Node).get_children():
			var panel := box as Panel
			if panel != null and not panel.tooltip_text.begins_with("room for"):
				held += 1
	return held


## **THE COMMIT BAR ON A DESIGN IS THE SIM'S OWN WORD, AND IT MOVES ON EVERY CLICK** (ASSA-317 slice
## 2b, over ASSA-325 and ASSA-329).
##
## **EQUALITY, NOT `contains`.** The bar must carry the sim's string and NOTHING ELSE on this path:
## `contains` would pass a client that wrapped the verdict in a sentence of its own, which is the
## ASSA-43/52 defect and the one rule ASSA-317 names as unbendable. So the drawn text is held equal
## to the field the sim crossed.
##
## **AND THE TWO STATES ARE HELD APART.** A frame on its own is `unfinished` -- real numbers, a slot
## still empty, the sim's `fault` where the verdict goes -- and mounting what it asks for turns that
## into a verdict. A bar that printed one of them in both states would pass either half alone, so the
## test also asserts the text CHANGED: that is the whole of "watch the numbers move".
##
## **NO MINING, DELIBERATELY.** `design_readout` takes no player and prices nothing (its docstring),
## so a design the pack cannot pay for reads exactly the same -- which is why the pack's own cost is
## block 6's job and a different item. A test that played the world to a real frame would be testing
## worldgen's generosity.
func test_the_commit_bar_on_a_design_is_the_sims_own_verdict_and_moves() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	var frame := _roomiest_frame()
	var needs := ""
	for entry in AssayHud.slot_boxes(frame.get("slots", []) as Array):
		var box: Dictionary = entry
		if bool(box.get("required", false)):
			needs = String(box.get("name", ""))
			break
	if frame.is_empty() or needs == "":
		ok = _fail("no frame in the sim's catalogue requires a part, so there is no unfinished state")
	else:
		screen._build_verb = screen.BUILD_ASSEMBLE
		screen._building = [_part_stack_of(String(frame.get("kind", "")))]
		screen._refresh_build_said()
		var waiting: Dictionary = screen._design_readout()
		var said := _only_said(screen)
		if not bool(waiting.get("unfinished", false)):
			ok = _fail(("a `%s` with its `%s` slot empty is not `unfinished` to the sim: %s -- so this "
					+ "test is not reading the state it is about")
					% [String(frame.get("kind", "")), needs, waiting])
		elif String(waiting.get("fault", "")) == "":
			ok = _fail("the sim names no fault for a design with an empty required slot: %s" % [waiting])
		elif said != String(waiting.get("fault", "")):
			ok = _fail(("the bar says `%s` and the sim's fault is `%s`; on this path the bar carries the "
					+ "sim's string and nothing else") % [said, String(waiting.get("fault", ""))])
		else:
			screen._building.append(_part_stack_of(needs))
			screen._refresh_build_said()
			var whole: Dictionary = screen._design_readout()
			var now := _only_said(screen)
			if String(whole.get("verdict", "")) == "":
				ok = _fail(("a `%s` with a `%s` mounted is still not a machine to the sim: %s")
						% [String(frame.get("kind", "")), needs, whole])
			elif now != String(whole.get("verdict", "")):
				ok = _fail(("the bar says `%s` and the sim's verdict is `%s`")
						% [now, String(whole.get("verdict", ""))])
			elif now == said:
				ok = _fail(("the bar reads `%s` both with and without the required part mounted, so it is "
						+ "not live") % now)
	screen.queue_free()
	return ok


## **PRESSING `Build` WHILE ASSEMBLING SENDS `Assemble`, AND AN EMPTY DESIGN IS ANSWERED** (ASSA-317
## slice 2b).
##
## **THE PRESS IS THE REAL BUTTON**, not `_send_build` called by name: what makes this screen the
## board's *interactive build screen* is that its one accent commits the design, and a wiring mistake
## there is invisible to a test that calls the function the button was supposed to be connected to.
##
## **AND THE EMPTY CASE IS A STATE, NOT A GUARD I FANCIED.** A primary control that is never disabled
## has to answer every press (ASSA-262's dead button in Mineralogy); `_assemble` returns silently on
## an empty design because the bench's `Assemble` sits beside a sentence saying what is chosen, and
## this one does not.
##
## **THE DESIGN THIS PRESSES IS A FINISHED ONE SINCE ASSA-373, AND THE OLD FIXTURE WAS THE DEFECT
## WRITTEN DOWN AS CORRECT.** It pressed `Build` on a frame ALONE and then asserted both that the
## command went out and that `_building` came back empty -- and a frame alone is exactly the
## `unfinished` design Maren found the client eating. So this test was the harm's own regression
## guard, pointing the wrong way: my fix for ASSA-373 reddened it, which is the only reason I read it.
## It keeps its subject -- the accent reaching the one file that spells a command -- on a design the
## sim would actually accept, and the refusal case is
## `test_build_refuses_an_unfinished_design_without_eating_it` below.
##
## **THE PREMISE IS ASSERTED RATHER THAN ASSUMED**: if the completed design were still `unfinished`
## to the sim, the press would take the refusal path and every assertion here would be about nothing.
func test_build_sends_assemble_on_the_assembly_path_and_answers_an_empty_design() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	screen._build_verb = screen.BUILD_ASSEMBLE
	screen._building = []
	_asked.clear()
	screen._build_act.pressed.emit()
	if not _asked.is_empty():
		ok = _fail("pressing Build with no frame chosen submitted %s" % [_asked])
	elif not screen._status.text.contains("frame"):
		ok = _fail(("pressing Build with no frame chosen said `%s`; a control that is never disabled "
				+ "has to answer every press") % screen._status.text)
	else:
		var roomy := _roomiest_frame()
		var needs := _required_slot_of(roomy)
		var frame := _part_stack_of(String(roomy.get("kind", "")))
		if needs == "":
			ok = _fail(("no slot of `%s` is required, so nothing mounted on it can finish the design "
					+ "and this half would be pressing the refusal path") % [roomy])
		else:
			var fills := _part_stack_of(needs)
			screen._building = [frame, fills]
			screen._refresh_build_said()
			var whole: Dictionary = screen._design_readout()
			if bool(whole.get("unfinished", false)):
				ok = _fail(("a `%s` with its `%s` mounted is still `unfinished` to the sim (%s), so this "
						+ "press takes ASSA-373's refusal path and proves nothing about submitting")
						% [String(roomy.get("kind", "")), needs, whole])
			else:
				_asked.clear()
				screen._build_act.pressed.emit()
				# **COMPARED AGAINST `AssayActions`' OWN BUILDER, not against a payload typed here** (the
				# `do` section's rule in this file): the point is that the accent reaches the one file that
				# spells a command, not that I can spell one twice.
				var want: Variant = AssayActions.assemble(AssayActions.item_of_stack(frame),
						[AssayActions.item_of_stack(fills)])
				if _asked.size() != 1:
					ok = _fail("Build on a finished design asked for %d commands, not one: %s"
							% [_asked.size(), _asked])
				elif _asked[0] != want:
					ok = _fail("Build submitted %s, not %s" % [_asked[0], want])
				elif AssaySimHost.command_echo(_asked[0]) == "":
					ok = _fail("Build submitted %s, which serde refuses" % [_asked[0]])
				elif not screen._building.is_empty():
					# **STILL CLEARED ON THE SUBMISSION, AND ASSA-373 PART 2 IS WHY THAT IS NOT YET A
					# DEFECT HERE**: this design is one the sim accepts, so clearing it is right. Clearing
					# a design the sim REFUSES is the part that is still wrong, and it is blocked on an
					# outcome crossing the binding -- see `_assemble`'s docstring.
					ok = _fail(("a design the sim accepts survived the press as %s; `_assemble` clears on "
							+ "the submission") % [screen._building])
	screen.queue_free()
	return ok


## **A REFUSAL MAY COST YOU A PRESS. IT MAY NEVER COST YOU YOUR WORK** (ASSA-373 part 1; Maren's
## rule, found by reading `limpet-assa362-after/build-screen-14247-slots-empty.png` cold).
##
## Mount four optional parts on a frame whose required slot is still empty -- the bar is already
## saying so -- and press the one accent on the screen. It used to submit an `Assemble` the sim
## refuses and then clear `_building` anyway, so **the bad press cost every good one**: word for word
## the harm `_choose_part`'s docstring records as fixed for part presses.
##
## **FOUR MOUNTS AND NOT ONE, BECAUSE THE CLAIM IS ABOUT LOSING WORK.** A one-part design loses
## nothing a player would miss; the defect is the four hoppers coming off. So the fixture mounts the
## roomiest slot to its limit and the assertion is on the parts BY KIND, not on `_building.size()` --
## a client that cleared the array and re-appended the frame would pass a size check.
##
## **EVERY GESTURE HERE IS ONE A PLAYER MAKES.** `_open_assembly_screen` is the pack row's press and
## `_choose_part` is the mount press, so each part goes in through `part_press_refusal` rather than
## being assigned into `_building` -- which is what makes the premise ("the sim accepted these four")
## a measurement rather than my assumption.
##
## **AND IT ASSERTS WHAT WAS NOT SENT, THROUGH THE REAL `asked` SIGNAL.** `_asked` fires inside
## `submit`, so an empty `_asked` is the wire staying quiet and not an inference from the toast.
func test_build_refuses_an_unfinished_design_without_eating_it() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	var roomy := _roomiest_frame()
	var needs := _required_slot_of(roomy)
	var spare := String(roomy.get("mounts", ""))
	var room := int(roomy.get("room", 0))
	if needs == "" or spare == "" or spare == needs or room < 2:
		screen.queue_free()
		return _fail(("premise: `%s` needs `%s` and has %d of `%s` to spare -- this test wants a frame "
				+ "with a required slot AND a roomier optional one") % [roomy, needs, room, spare])
	screen._open_assembly_screen(_part_stack_of(String(roomy.get("kind", ""))))
	for _i in range(room):
		screen._choose_part(_part_stack_of(spare))
	var mounted := PackedStringArray()
	for entry in screen._building:
		mounted.append(String((entry as Dictionary).get("kind", "")))
	var readout: Dictionary = screen._design_readout()
	var fault := String(readout.get("fault", ""))
	if not screen._assembling_mode():
		ok = _fail("the pack row's press did not put the screen in assembling mode")
	elif mounted.size() != room + 1:
		ok = _fail(("the sim accepted %d of the %d presses (%s), so this design is not the one the test "
				+ "is about") % [mounted.size() - 1, room, mounted])
	elif not bool(readout.get("unfinished", false)):
		ok = _fail(("a `%s` with its `%s` slot empty is not `unfinished` to the sim (%s), so the press "
				+ "below takes a different branch and proves nothing") % [roomy, needs, readout])
	elif fault == "":
		# THE SENTENCE THE PRESS MUST SAY HAS TO EXIST, or the fix would be a silent refusal -- which
		# is the dead button ASSA-262 found, reached by a different road.
		ok = _fail("the sim names no fault for an unfinished design (%s), so there is nothing to say"
				% [readout])
	else:
		_asked.clear()
		screen._build_act.pressed.emit()
		var after := PackedStringArray()
		for entry in screen._building:
			after.append(String((entry as Dictionary).get("kind", "")))
		if not _asked.is_empty():
			ok = _fail(("Build submitted %s for a design the sim calls unfinished; the flag exists to be "
					+ "read before the wire") % [_asked])
		elif after != mounted:
			ok = _fail(("the press changed the design from %s to %s; the sim spends nothing on a refusal, "
					+ "so the client must take nothing") % [mounted, after])
		elif screen._status.text != fault:
			ok = _fail(("the press said `%s`; the sim's own fault is `%s`, and a refusal in this client's "
					+ "own words is ASSA-43/52") % [screen._status.text, fault])
		elif screen._base_level != AssayHud.Say.FAILED:
			ok = _fail("the refusal was said at level %d, not FAILED (%d) the way a refused part press is"
					% [screen._base_level, AssayHud.Say.FAILED])
		elif screen._build_act.disabled:
			ok = _fail("the refusal disabled `Build`; ASSA-316 ruling 2 says the sim does the refusing")
		elif screen._build_act.theme_type_variation != &"Primary":
			ok = _fail("the refusal took `Build` out of the accent (`%s`)"
					% screen._build_act.theme_type_variation)
	screen.queue_free()
	return ok


## **`unfinished` AND `fault` ARE NOT THE SAME QUESTION, AND THIS IS THE STATE THAT PROVES IT**
## (ASSA-373's second box: *"never a string test on `fault`"*).
##
## **WHY A CONTRACT TEST RATHER THAN A CLIENT ONE.** `_send_build`'s gate reads `unfinished`; swapping
## it for `fault != ""` leaves every client test of mine GREEN, because in every state a PRESS can
## reach the two agree. So the box cannot be held by the press -- it is held by showing that the sim
## answers a non-empty `fault` with `unfinished` FALSE, which is the readout a text gate would refuse
## and the flag would not. `AssemblyError::is_unfinished` is where the sim draws that line
## (`assembly.rs:726`: `TooFew` is recoverable, `NoSuchSlot` and `TooMany` are not).
##
## **THE REQUIRED SLOT IS FILLED ON PURPOSE.** `validate` reports one error, and a frame with an empty
## required slot would answer `TooFew` -- which IS unfinished -- so an unfilled fixture would make the
## two fields agree and this test would pass about the wrong state. That is the near-miss shape I keep
## hitting: a mutation tripping an earlier assertion than the one it is aimed at.
##
## **WHAT THIS DOES NOT CLAIM: what `Build` should do about such a readout.** Maren scoped that to
## ASSA-373 part 2 by name (`TooMany` after a frame switch), and it is unreachable by presses today --
## `part_press_refusal` refuses the mount that would make it. Asserting a behaviour here would be me
## inventing the ruling part 2 exists to make.
func test_the_sims_unfinished_flag_is_not_its_fault_sentence() -> bool:
	var screen := _joined()
	_tick(screen, 2)
	var ok := true
	var spare := String(_roomiest_frame().get("mounts", ""))
	var narrow := _frame_without(spare)
	var needs := _required_slot_of(narrow)
	if spare == "" or narrow.is_empty() or needs == "":
		screen.queue_free()
		return _fail(("premise: no frame in the catalogue both lacks a `%s` slot and requires something "
				+ "(%s), so there is no permanently-refused design to read") % [spare, narrow])
	screen._building = [_part_stack_of(String(narrow.get("name", ""))),
			_part_stack_of(needs), _part_stack_of(spare)]
	var readout: Dictionary = screen._design_readout()
	var fault := String(readout.get("fault", ""))
	if fault == "":
		ok = _fail(("mounting a `%s` on a `%s`, which has no such slot, is no fault to the sim (%s)")
				% [spare, String(narrow.get("name", "")), readout])
	elif bool(readout.get("unfinished", false)):
		ok = _fail(("the sim calls `%s` unfinished (`%s`), so the flag and the sentence agree here and "
				+ "a text gate would be indistinguishable") % [readout, fault])
	elif String(readout.get("verdict", "")) != "":
		ok = _fail("a design the sim refuses carries the verdict `%s`" % String(readout.get("verdict", "")))
	screen.queue_free()
	return ok


## **A FRAME WITH NO SLOT OF THIS KIND AT ALL**, out of the sim's catalogue -- the held frame today,
## named by its shape rather than by its name so a fifth kind does not rewrite the test.
func _frame_without(slot_kind: String) -> Dictionary:
	for entry in AssaySimHost.part_kinds():
		var row: Dictionary = entry
		if not bool(row.get("is_frame", false)):
			continue
		var offers := false
		for slot in (row.get("slots", []) as Array):
			if String((slot as Dictionary).get("name", "")) == slot_kind:
				offers = true
		if not offers:
			return row
	return {}


## **THE NAME OF ONE SLOT THIS FRAME REQUIRES, OR `""`** -- out of `slot_boxes`, which is the same
## walk the screen draws the shape from, so a test and the picture cannot disagree about which boxes
## are required. `required` is per BOX (`i < min`), not per kind, so the first required box's name is
## the kind a design cannot be finished without.
func _required_slot_of(frame: Dictionary) -> String:
	for entry in AssayHud.slot_boxes(frame.get("slots", []) as Array):
		var box: Dictionary = entry
		if bool(box.get("required", false)):
			return String(box.get("name", ""))
	return ""


## **THE ONE LABEL IN THE COMMIT BAR, OR A COMPLAINT NAMING HOW MANY THERE ARE.**
##
## **NOT `_text_of`, AND THE REASON IS A NEAR-MISS RATHER THAN A PREFERENCE.** That helper joins with
## ` · ` and appends each child's own recursion, so a single Label comes back as `<text> · ` -- a
## trailing clause mark this file added, which read exactly like the client having composed one. The
## count is asserted HERE because that is the half `contains` could never hold: a client that drew the
## sim's string and a sentence of its own beside it is the ASSA-43/52 defect, and on this path the bar
## carries one sim string and nothing else.
func _only_said(screen: Node) -> String:
	var labels := PackedStringArray()
	for child in screen._build_said.get_children():
		var label := child as Label
		if label != null:
			labels.append(label.text)
	if labels.size() != 1:
		return "<%d labels: %s>" % [labels.size(), labels]
	return labels[0]
