extends RefCounted
## THE SCREEN ITSELF, INSTANTIATED. `test_hud.gd` checks the words and colours; this checks that they
## are wired to anything at all.
##
## Everything here runs headless with no relay, so nothing joins and no world is simulated. That still
## covers the two rulings about the FRONT DOOR -- clicking Join must say something before the answer
## comes back, and a failure must not look like an instruction -- which are exactly the two things a
## suite about text alone would let rot.

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## A live `scenes/main.tscn` with `_ready` run. Freed by the caller.
##
## `_ready` IS CALLED BY HAND, and that is not a shortcut. The suite does all its work inside
## `SceneTree._initialize`, which happens before the root window is in the tree -- measured: a node
## added to the runner there reports `is_inside_tree() == false` and its `_ready` fires only after the
## suite has already printed its verdict. So the choice is calling it here or not testing the screen at
## all. Nothing below leans on layout the engine would have done later; it reads the positions this
## file's code sets.
func _screen() -> Node:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var node: Node = scene.instantiate()
	runner.root_node.add_child(node)
	node._ready()
	return node


## WHERE A SECTION ACTUALLY IS, in the screen's own coordinates.
##
## Positions are SUMMED UP THE ANCESTOR CHAIN rather than read off one node, because the HUD column
## lives inside a `ScrollContainer` now (a full pack plus a bench is taller than the window, and a
## button pushed off the bottom is worse than a disabled one). The scroll box carries the position
## and the column sits at the origin inside it, so asking either one alone would give the wrong
## answer. `get_global_position` is not an option: the suite runs inside `SceneTree._initialize`,
## before there is a layout pass to make it mean anything.
func _left_edge_of(node: Node) -> float:
	var x := 0.0
	var walk: Node = node
	while walk != null and not (walk is Node2D):
		if walk is Control:
			x += (walk as Control).position.x
		walk = walk.get_parent()
	return x


## THE SCREEN IS BUILT ONCE, however many times `_ready` runs. This file calls `_ready()` by hand AND
## adds the node to the tree, so the engine calls it again -- which used to build the HUD column twice
## and reparent every label into the second one. Harmless on screen (the real client readies once) but
## it filled the suite output with `Can't add child ... already has a parent`, and error spam nobody
## reads is where a real error goes to hide.
func test_the_screen_is_built_once_even_if_ready_runs_twice() -> bool:
	var screen := _screen()
	var column: Node = screen._carrying.get_parent()
	screen._ready()
	var ok := true
	if screen._carrying.get_parent() != column:
		ok = _fail("a second _ready reparented the HUD into a new column")
	var columns := 0
	for child in screen.get_children():
		if child is ScrollContainer:
			columns += 1
	if ok and columns != 1:
		ok = _fail("a second _ready left %d HUD columns on the screen" % columns)
	screen.queue_free()
	return ok


## EVERY SECTION IS BESIDE THE MAP, including the two that grew buttons (ASSA-37). A button over the
## map would be a click that means two things, which is the one thing the right-click target rule
## exists to avoid.
func test_the_screen_builds_a_hud_column_beside_the_map() -> bool:
	var screen := _screen()
	var ok := true
	var beside := AssayHud.VIEW.x - AssayHud.PANEL - AssayHud.MARGIN.x
	for part in [["you", screen._carrying], ["do", screen._actions], ["bench", screen._bench],
			["cursor", screen._cursor], ["last tick", screen._log]]:
		var section: Control = part[1]
		if section.get_parent() == null:
			ok = _fail("the %s section was never added to the screen" % part[0])
			break
		var at := _left_edge_of(section)
		if at < beside:
			ok = _fail("the %s section starts at x %f, which is over the map" % [part[0], at])
			break
	screen.queue_free()
	return ok


## THE COLUMN SCROLLS, so a pack with eight stacks in it cannot push the bench's buttons off the
## bottom of the window. Checked as a property of the screen and not of my arithmetic: the thing that
## must be true is that the section's own container can grow past the window and still be reachable.
func test_the_hud_column_is_scrollable_so_a_full_pack_cannot_hide_a_button() -> bool:
	var screen := _screen()
	var scroll: ScrollContainer = null
	for child in screen.get_children():
		if child is ScrollContainer:
			scroll = child
	var ok := true
	if scroll == null:
		ok = _fail("the HUD column is not inside a ScrollContainer, so a tall pack hides buttons")
	elif scroll.custom_minimum_size.y <= 0.0 or scroll.custom_minimum_size.y > AssayHud.VIEW.y:
		ok = _fail("the scroll box is %f tall against a %f window"
				% [scroll.custom_minimum_size.y, AssayHud.VIEW.y])
	elif scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		ok = _fail("the column scrolls sideways, which would hide a button rather than reveal it")
	screen.queue_free()
	return ok


## MAREN'S RULING 1: clicking Join must say something before the answer comes back, or a player who
## sees nothing clicks again and gets told they are already joining -- which reads as their fault.
func test_clicking_join_says_connecting_before_anything_can_block() -> bool:
	var screen := _screen()
	# Nothing listens on port 1. The point is what the screen says BEFORE the socket has an answer.
	screen._host.text = "127.0.0.1:1"
	screen._on_join()
	var said: String = screen._status.text
	var colour: Color = screen._status.modulate
	screen.queue_free()
	if not said.to_lower().contains("connecting"):
		return _fail("clicking Join left the status line saying %s" % said)
	if colour != AssayHud.status_color(AssayHud.Say.CONNECTING):
		return _fail("a connecting status is coloured %s, not the connecting colour" % colour)
	return true


## MAREN'S RULING 2: "enter a host address and join" and a connection error are the same words in the
## same place. The colour is the only thing that can tell an instruction from a failure.
func test_a_failure_does_not_look_like_the_instruction_it_replaces() -> bool:
	var screen := _screen()
	var idle: Color = screen._status.modulate
	var instruction: String = screen._status.text
	screen._client.link_failed.emit("could not reach 127.0.0.1:1")
	var failed: Color = screen._status.modulate
	var said: String = screen._status.text
	screen.queue_free()
	if instruction == said:
		return _fail("a failure did not reach the status line at all")
	if failed == idle:
		return _fail("a failure is the same colour as the instruction it replaced (%s)" % failed)
	if failed != AssayHud.status_color(AssayHud.Say.FAILED):
		return _fail("a failure is coloured %s, not the failed colour" % failed)
	return true


## A desync is unrecoverable in the demo, so it is a failure, not narration.
func test_a_desync_is_reported_as_a_failure() -> bool:
	var screen := _screen()
	screen._client.desynced.emit(140)
	var said: String = screen._status.text
	var colour: Color = screen._status.modulate
	screen.queue_free()
	if not said.contains("140"):
		return _fail("a desync at tick 140 was reported as %s" % said)
	if colour != AssayHud.status_color(AssayHud.Say.FAILED):
		return _fail("a desync is coloured %s, not the failed colour" % colour)
	return true


## Before a Welcome there is no world and no player id, and the HUD must ask for neither. This is the
## frame a client spends on its first screen, and it is where an "every frame" read crashes.
##
## NOW ALSO: NO BUTTON BEFORE THERE IS A WORLD TO PRESS IT IN. The pack and the `do` section are rows
## of verbs built from what the sim reports, so with no sim they must offer nothing -- a Mine button
## whose only possible answer is "not joined" would be the Join button's job, badly done.
func test_the_hud_asks_for_nothing_before_there_is_a_world() -> bool:
	var screen := _screen()
	screen._refresh()
	var buttons := _buttons_under(screen._carrying) + _buttons_under(screen._actions) \
			+ _buttons_under(screen._bench)
	var pack: int = screen._carrying.get_child_count()
	screen.queue_free()
	if not buttons.is_empty():
		return _fail("the HUD offered %s with no world to act in" % [buttons])
	if pack != 1:
		return _fail("the pack holds %d rows for a world that does not exist" % pack)
	return true


## Every `Button` anywhere under a node, by its label.
func _buttons_under(node: Node) -> Array:
	var found := []
	for child in node.get_children():
		if child is Button:
			found.append((child as Button).text)
		found.append_array(_buttons_under(child))
	return found


## THE PART MENU IS ON THE SCREEN, not only in `AssayHud`'s pure functions. A tested helper that
## nothing calls is the failure I keep repeating in new costumes: 42 tests passed while `main.gd`
## had a parse error, because nothing loaded it.
##
## Before a world there are no designs, so the honest state is the one a player sees most today: a
## heading with a sentence under it that says which kind of empty it is.
func test_the_bench_is_wired_into_the_column_and_says_when_it_is_empty() -> bool:
	var screen := _screen()
	var bench: VBoxContainer = screen._bench
	var ok := true
	var at := _left_edge_of(bench)
	if bench.get_parent() == null:
		ok = _fail("the bench was never added to the screen")
	elif at < AssayHud.VIEW.x - AssayHud.PANEL - AssayHud.MARGIN.x:
		ok = _fail("the bench starts at x %f, which is over the map" % at)
	elif bench.get_child_count() != 1:
		ok = _fail("an empty bench should hold one line, holds %d" % bench.get_child_count())
	else:
		var line: Label = bench.get_child(0) as Label
		if line == null or not line.text.contains("nothing built"):
			ok = _fail("an empty bench must say so, shows '%s'"
					% ("" if line == null else line.text))
	screen.queue_free()
	return ok
