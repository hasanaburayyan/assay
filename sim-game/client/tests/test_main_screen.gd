extends RefCounted
## THE SCREEN ITSELF, INSTANTIATED. `test_hud.gd` checks the words and colours; this checks that they
## are wired to anything at all.
##
## Everything here runs headless with no relay, so nothing joins and no world is simulated. That still
## covers the two rulings about the FRONT DOOR -- clicking Join must say something before the answer
## comes back, and a failure must not look like an instruction -- which are exactly the two things a
## suite about text alone would let rot.

var runner = null


## **A RELAY THAT HAS JUST BECOME READY, WHICH IS A STATE AND NOT A VALUE.** `poll()` sets `address`
## and returns true in the same call; nobody ever hands `main.gd` a relay with an address already on
## it, because the guard at the top of `_process` exists precisely to skip those frames.
##
## Subclassed rather than faked so everything else on the object is the real thing: `stop()`, the
## `failure` field and the save path all come from `AssaySoloRelay`. Only the one call whose real
## implementation needs a child process is replaced, and its contract is pinned against a real
## process in `test_solo_relay.gd::test_the_address_comes_out_of_the_listening_line`.
class _RelayThatIsListening extends AssaySoloRelay:
	var polls := 0

	func poll() -> bool:
		polls += 1
		address = "127.0.0.1:54321"
		return true


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


## AND THE LINK IS PART OF THE SCREEN, which the test above did not cover and should have.
##
## A second `_ready` used to build a SECOND `AssayNetClient` and point `_client` at it. The first one
## stayed connected to every handler, so against a real relay the world kept stepping while
## `_client.stage` read IDLE and `_client.player_id` read -1 -- the HUD showing an empty inventory
## belonging to nobody, of a world that was visibly moving. Nothing in this suite joins anything, so
## the suite could not see it; `tools/button_session.gd` found it against a relay and it looked like a
## join that never happened. This is the cheap check that would have caught it first.
func test_a_second_ready_does_not_replace_the_link() -> bool:
	var screen := _screen()
	var client: Node = screen._client
	var links := 0
	screen._ready()
	for child in screen.get_children():
		if child is AssayNetClient:
			links += 1
	var ok := true
	if screen._client != client:
		ok = _fail("a second _ready replaced the link, so the HUD would read a client nobody joined")
	elif links != 1:
		ok = _fail("the screen holds %d links; the extra one still gets every bundle" % links)
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
			["cursor", screen._cursor], ["last tick", screen._log],
			# The log's toggle, which sits above the column rather than in it (ASSA-89) and so is the
			# one control that could have been placed over the map by arithmetic of its own.
			["log toggle", screen._log_toggle]]:
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


## MAREN'S RULING 2: the opening instruction and a connection error land in the same place. The
## colour is the only thing that can tell an instruction from a failure.
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


## **THE FIRST THING A STRANGER READS NAMES BOTH DOORS, SOLO FIRST** (Maren, ASSA-113).
##
## It used to read "enter a host address and join", which sent them to the one door that needs
## information they do not have -- and it survived the whole of ASSA-106 because I never re-read the
## item between cutting the branch and opening the PR.
func test_the_opening_line_offers_the_door_that_needs_nothing_typed() -> bool:
	var screen := _screen()
	var said: String = screen._status.text
	var colour: Color = screen._status.modulate
	screen.queue_free()
	if not said.contains("Play solo"):
		return _fail("the opening line does not mention Play solo at all: %s" % said)
	if not said.contains("host address"):
		return _fail("the opening line dropped the host door: %s" % said)
	# SOLO FIRST, because the row reads left to right and so does the sentence above it.
	if said.find("Play solo") > said.find("host address"):
		return _fail("the opening line puts the host door first: %s" % said)
	if colour != AssayHud.status_color(AssayHud.Say.IDLE):
		return _fail("the opening instruction is coloured %s, not the idle colour" % colour)
	return true


## **PLAY SOLO IS THE FIRST CONTROL IN THE ROW, AND IT ASKS FOR THE FOCUS** (Maren, ASSA-113).
##
## FOUND BY FIELD AND NOT BY INDEX, because the index is the thing under test: a test that located
## the button by its position in the row could not fail. And `get_parent()` is asserted alongside
## `is_instance_valid`, because a freed node has no parent and a parent-walk over one passes about
## nothing -- that has caught me twice.
##
## WHAT THIS CANNOT DO IS WATCH THE FOCUS LAND. Measured: inside `SceneTree._initialize`, where this
## suite runs, a node added under the root reports `is_inside_tree() == false`, `get_viewport()` is
## null, and `grab_focus()` errors out leaving `has_focus()` false. One frame later it works, so the
## real focus owner is read back off the viewport by `tools/focus_probe.gd` instead, headless.
func test_play_solo_is_the_first_door_in_the_row() -> bool:
	var screen := _screen()
	var button: Button = screen._solo_button
	var ok := true
	if not is_instance_valid(button):
		ok = _fail("the Play solo button does not exist")
	elif button.get_parent() == null:
		ok = _fail("the Play solo button is not in the screen at all")
	elif button.text != "Play solo":
		ok = _fail("the first door reads `%s`" % button.text)
	elif button.get_index() != 0:
		var row := button.get_parent()
		var names := PackedStringArray()
		for child in row.get_children():
			names.append(child.get_class() + ":" + String(child.get("text")))
		ok = _fail("Play solo is child %d of the row, which reads %s"
				% [button.get_index(), ", ".join(names)])
	elif button.focus_mode != Control.FOCUS_ALL:
		ok = _fail("the first door cannot take focus, so Enter cannot press it")
	# THE REQUEST, not the outcome: the outcome needs a tree and a frame, and this suite has neither.
	elif not button.tree_entered.is_connected(button.grab_focus):
		ok = _fail("nothing asks the first door for the focus when it reaches the tree")
	screen.queue_free()
	return ok


## **PRESSING PLAY SOLO DOES NOT TOUCH WHAT THE PLAYER TYPED** (Maren, ASSA-113, and this one was a
## live bug rather than wording).
##
## `_process` used to do `_host.text = _solo.address` before joining, so a player who had typed a
## friend's address and then pressed Play solo watched it silently vanish. The address now goes
## straight to `_join_address`, so the box is neither read nor written by the solo path.
func test_play_solo_neither_reads_nor_wipes_a_typed_host() -> bool:
	var screen := _screen()
	var typed := "friend.example:7777"
	screen._host.text = typed
	# THE FRAME THE BUG LIVED IN IS THE ONE WHERE `poll()` FIRST SAYS YES, and it has to be reached
	# the way production reaches it. My first version of this test set `address` on a real
	# `AssaySoloRelay` and called `_process`, which proves nothing: `_process` returns at its first
	# line when `address != ""`, because that guard is what stops it re-joining on every later frame.
	# The suite caught it (`solo did not join the address its own relay reported`) and the test was
	# right -- the setup was a state production never passes through.
	#
	# So the stub honours `poll()`'s actual contract: set the address, return true, once. That
	# contract is not assumed here, it is verified against a real process in
	# `test_solo_relay.gd::test_the_address_comes_out_of_the_listening_line`.
	var solo := _RelayThatIsListening.new()
	screen._solo = solo
	screen._process(0.016)
	if solo.polls != 1:
		screen._solo = null
		screen.queue_free()
		return _fail("the solo frame polled the relay %d times, not once" % solo.polls)
	var ok := true
	if screen._host.text != typed:
		ok = _fail("Play solo rewrote the host box to `%s`" % screen._host.text)
	# AND IT JOINED THE RELAY, not the typed address -- the other way for this to "pass" is to honour
	# what was typed, which is the same confusion with the blame reversed.
	elif not screen._status.text.contains("127.0.0.1:54321"):
		ok = _fail("solo did not join the address its own relay reported: %s" % screen._status.text)
	elif screen._status.text.contains(typed):
		ok = _fail("solo joined the typed host instead of its own relay: %s" % screen._status.text)
	screen._solo = null
	screen.queue_free()
	return ok


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


## THE LOG IS HIDDEN ON FIRST OPEN, AND ITS HEADING WITH IT (ASSA-89). The board's words were "logs
## are hard on the eyes", and "last tick" over nothing would be a labelled empty gap -- a stranger
## reading an empty section assumes the game has nothing to say rather than that it is folded away.
##
## The toggle is checked as a VISIBLE CONTROL THAT NAMES ITSELF, because "one key/button, named on
## screen" is the acceptance and a bare icon or a bare keybinding would satisfy neither half.
func test_the_event_log_starts_hidden_behind_a_named_control() -> bool:
	var screen := _screen()
	var ok := true
	var toggle: Button = screen._log_toggle
	if screen._log.visible:
		ok = _fail("the event log is on the first screen the board opens")
	elif screen._log_shown:
		ok = _fail("the log reads as shown while its Label is hidden; the two have drifted")
	elif is_instance_valid(screen._log_heading) and screen._log_heading.visible:
		ok = _fail("the log is hidden under a visible 'last tick' heading: a labelled empty gap")
	elif not toggle.visible or toggle.get_parent() == null:
		ok = _fail("there is no visible control to show the log with")
	elif not toggle.text.to_lower().contains("log"):
		ok = _fail("the control does not name what it does, it reads '%s'" % toggle.text)
	elif not toggle.text.contains("L"):
		ok = _fail("the control does not name its key, so the key cannot be discovered: '%s'"
				% toggle.text)
	screen.queue_free()
	return ok


## HIDDEN MEANS HIDDEN, NOT REMOVED -- Marlow's note on the item, and the one risk the whole change
## carries.
##
## **THE ORDER IS THE TEST, AND MY FIRST VERSION HAD IT WRONG.** I planted the lines while the log
## was already hidden, so the hide path never ran over them -- and a `_show_log` that cleared the
## text on hide PASSED, which I only found by mutating it. The lines have to go in while the log is
## SHOWN and the hide has to happen over text that is already there, which is the order a player's
## lines actually arrive in. A test whose steps run in an order the real thing never does is a test
## that agrees with the bug.
##
## So: show, plant, hide **through the control**, and read the node back while it is hidden -- still
## in the column, still carrying its text, with `_events` untrimmed. Then reveal, and the same text
## must be there with nothing re-fetched: showing the log may not be what loads it.
##
## WHAT THIS CANNOT CATCH, said rather than implied: a deferred `queue_free` on hide. The suite works
## inside `SceneTree._initialize` and there is no frame for the free to happen in, so the node would
## still be valid here. The lever that does catch it is
## `test_the_screen_builds_a_hud_column_beside_the_map`, which fails with "the last tick section was
## never added to the screen" -- measured, not assumed.
##
## The lines are planted rather than played because this file has no relay and no world; the real
## stream is covered by `test_buttons.gd`, which drives a refusal through a real sim.
func test_a_hidden_log_still_carries_its_lines() -> bool:
	var screen := _screen()
	var ok := true
	var planted := PackedStringArray(["41 · you mined 2 ore", "42 · you started walking"])
	screen._log_toggle.pressed.emit()
	screen._events = planted
	screen._log.text = "\n".join(planted)
	screen._log_toggle.pressed.emit()
	if screen._log.visible:
		ok = _fail("the control would not hide the log again")
	elif not is_instance_valid(screen._log) or screen._log.get_parent() == null:
		ok = _fail("the log was taken out of the column rather than hidden, so the lines it was "
				+ "carrying are gone and the probes' surface with them")
	elif not screen._log.text.contains("you mined 2 ore"):
		ok = _fail("a hidden log dropped the lines it was given: '%s'" % screen._log.text)
	elif screen._events.size() != planted.size():
		ok = _fail("the remembered lines were trimmed while hidden: %d of %d"
				% [screen._events.size(), planted.size()])
	else:
		# The reveal shows what was already there. Nothing is refetched, and that is the point: a
		# node freed on hide cannot come back, and text cleared on hide comes back empty.
		screen._log_toggle.pressed.emit()
		if not screen._log.visible:
			ok = _fail("pressing the control did not show the log")
		elif not screen._log_shown:
			ok = _fail("the log is visible but reads as hidden; the two have drifted")
		elif not screen._log.text.contains("you started walking"):
			ok = _fail("the revealed log had lost the lines it carried: '%s'" % screen._log.text)
		elif is_instance_valid(screen._log_heading) and not screen._log_heading.visible:
			ok = _fail("the log came back without its heading")
		elif not screen._log_toggle.text.to_lower().contains("hide"):
			ok = _fail("the control still offers to show an already-shown log: '%s'"
					% screen._log_toggle.text)
	screen.queue_free()
	return ok


## THE KEY DOES WHAT THE BUTTON DOES, and it is `_unhandled_key_input` so that a focused `LineEdit`
## eats the keystroke first: typing "localhost" into the host field must not fold the panel on the
## `l`. That half cannot be tested here -- it is the engine's own input routing, and this suite runs
## before there is a focus owner -- so what is checked is that the handler is the unhandled one.
func test_the_l_key_toggles_the_log_and_cannot_eat_a_typed_l() -> bool:
	var screen := _screen()
	var ok := true
	var key := InputEventKey.new()
	key.keycode = KEY_L
	key.pressed = true
	if not screen.has_method("_unhandled_key_input"):
		ok = _fail("the key is handled in _input, so typing an 'l' in the host field toggles the "
				+ "panel")
	elif screen._log.visible:
		ok = _fail("the log was not hidden to begin with, so this proves nothing")
	else:
		screen._unhandled_key_input(key)
		if not screen._log.visible:
			ok = _fail("L did not show the log")
		else:
			screen._unhandled_key_input(key)
			if screen._log.visible:
				ok = _fail("L showed the log and will not hide it again")
		# An echo is a held key, and a held L must not strobe the panel.
		var echo := InputEventKey.new()
		echo.keycode = KEY_L
		echo.pressed = true
		echo.echo = true
		var before: bool = screen._log.visible
		screen._unhandled_key_input(echo)
		if ok and screen._log.visible != before:
			ok = _fail("a key repeat toggled the log, so holding L strobes it")
	screen.queue_free()
	return ok


## NO ROW ASKS FOR MORE WIDTH THAN THE PANEL THAT CLIPS IT (ASSA-98).
##
## The HUD column lives in a `ScrollContainer` exactly `PANEL` wide whose horizontal scrolling is
## DISABLED, so a row wider than that is not a row you scroll to -- it is a row whose right-hand end
## does not exist. Every pack row used to ask for 358: the verb flow claimed the whole panel and the
## 32px icon beside it pushed the total past the box. `art/pack_icon_layout.gd` measured it on real
## frames; this measures the CAUSE, which is the minimum the row asks for.
##
## **`get_combined_minimum_size` AND NOT `size`, DELIBERATELY.** This suite runs inside
## `SceneTree._initialize`, where no layout pass has happened and every `size` is still whatever it
## was constructed with -- a `size` assertion here would read zeros and pass against anything. The
## combined minimum is computed from the children on demand, which is the one width that means
## something before a frame, and it is also the exact quantity that was wrong.
##
## BOTH SHAPES, because only one of them ever was wrong: a stack row has an icon beside its body and
## a bench row is the full panel with nothing beside it. A fix that just subtracted 38 everywhere
## would have broken the bench and passed a test that only looked at the pack.
func test_no_row_asks_for_more_width_than_the_panel_that_clips_it() -> bool:
	var screen := _screen()
	var ok := true
	# The richest pack the demo loop actually produces, which is the one with seven verbs on a row.
	screen._rebuild_pack([
		{"kind": "refined", "species": 4, "grade": "B", "count": 6, "name": "Minyte refined (B)"},
		{"kind": "ore", "species": 4, "grade": "B", "count": 22, "name": "Minyte ore (B)"},
		{"kind": "head", "species": 4, "grade": "B", "count": 2, "name": "Minyte head (B)"},
	])
	var checked := 0
	for section in [screen._carrying, screen._bench, screen._species, screen._actions]:
		for child in section.get_children():
			if not (child is Control):
				continue
			var row: Control = child
			var want: float = row.get_combined_minimum_size().x
			checked += 1
			if want > AssayHud.PANEL:
				ok = _fail(("a row asks for %f px inside a %f px panel that clips and does not "
						+ "scroll sideways, so its right-hand end cannot be reached: '%s'")
						% [want, AssayHud.PANEL, _text_in(row)])
				break
		if not ok:
			break
	if ok and checked == 0:
		ok = _fail("no rows were measured, so this proves nothing")
	screen.queue_free()
	return ok


## Whatever text a row carries, for a failure message that names the row rather than its index.
func _text_in(node: Node) -> String:
	if node is Label:
		return (node as Label).text
	if node is Button:
		return (node as Button).text
	var parts := PackedStringArray()
	for child in node.get_children():
		var found := _text_in(child)
		if found != "":
			parts.append(found)
	return " | ".join(parts)


## ASSA-88: THE CRAFTING MENU IS A SECTION BESIDE THE MAP, OPEN ON FIRST JOIN, AND ITS CONTROL NAMES
## ITS KEY.
##
## Open, unlike the event log, and that is the opposite call for the opposite reason: the board asked
## for a crafting menu, so a menu nobody finds is the clunk restated. The default is asserted here
## because `_make_shown` is initialised to the WRONG answer on purpose -- this can only pass if
## `_build_ui` actually called `_show_make(true)`.
func test_the_crafting_menu_is_open_on_first_join_and_its_control_names_the_key() -> bool:
	var screen := _screen()
	var ok := true
	var beside := AssayHud.VIEW.x - AssayHud.PANEL - AssayHud.MARGIN.x
	if screen._make.get_parent() == null:
		ok = _fail("the crafting menu was never added to the screen")
	elif _left_edge_of(screen._make) < beside:
		ok = _fail("the crafting menu starts at x %f, which is over the map"
				% _left_edge_of(screen._make))
	elif not screen._make.visible:
		ok = _fail("the crafting menu is folded away on first open; the board asked for a menu")
	elif not screen._make_toggle.text.contains("(M)"):
		ok = _fail("the menu's control does not name its key: `%s`" % screen._make_toggle.text)
	elif screen._make_toggle.text != AssayHud.make_toggle_text(true):
		ok = _fail("the control says `%s` while the rows are showing" % screen._make_toggle.text)
	screen.queue_free()
	return ok


## THE MENU FOLDS AND THE RUNNING CRAFT DOES NOT FOLD WITH IT (Maren's clause on ASSA-89, applied to
## ASSA-88): a craft is a CONDITION, not a moment.
##
## STRUCTURAL, AND THAT IS THE POINT. `test_buttons.gd` proves it with a real craft running; this
## proves the countdown is not a CHILD of the thing the toggle hides, so the property holds whatever
## a later edit does to the rows. Both, because the structural half is what makes the behavioural
## half impossible to break by accident.
func test_folding_the_crafting_menu_cannot_hide_the_running_craft() -> bool:
	var screen := _screen()
	var ok := true
	var walk: Node = screen._crafting
	while walk != null:
		if walk == screen._make:
			ok = _fail("the running craft lives inside the container the toggle hides")
			break
		walk = walk.get_parent()
	# AND IT SURVIVES A REBUILD OF THE ROWS. `_rebuild_make` CLEARS the container it owns, so a
	# countdown that had been added to the rows would be freed and the walk above would find a node
	# with no parent at all -- which is how a mutation that moved this line into the rows passed
	# every test I had. The parent is therefore asserted, not just "not the menu".
	if ok:
		screen._make_showing = "not a shape any pack has"
		screen._refresh_make()
		if not is_instance_valid(screen._crafting):
			ok = _fail("rebuilding the rows freed the running-craft line")
		elif screen._crafting.get_parent() == null:
			ok = _fail("rebuilding the rows took the running-craft line off the panel")
	if ok:
		screen._show_make(false)
		if screen._make.visible:
			ok = _fail("_show_make(false) left the rows visible")
		elif not screen._crafting.visible and screen._crafting.text != "":
			ok = _fail("folding the rows away hid a running craft")
		elif screen._make_toggle.text != AssayHud.make_toggle_text(false):
			ok = _fail("the control still says `%s` with the rows hidden"
					% screen._make_toggle.text)
	screen.queue_free()
	return ok


## AN EMPTY MENU SAYS WHICH KIND OF EMPTY IT IS, and names the cause: hands work on what you carry,
## so an empty menu means an empty pack. A heading over nothing reads as a bug -- the same rule the
## empty pack and empty bench already follow.
func test_the_crafting_menu_says_why_it_is_empty_before_a_world_exists() -> bool:
	var screen := _screen()
	var ok := true
	var said := ""
	for child in screen._make.get_children():
		if child is Label:
			said = (child as Label).text
	if said != AssayHud.nothing_to_make_line():
		ok = _fail("the empty menu says `%s`" % said)
	screen.queue_free()
	return ok


## ASSA-107 / Maren's ASSA-88 RULING: THE CHOSEN PARTS LIVE IN THE CRAFTING MENU, UNDER THE RUNNING
## CRAFT — not in the `do` section two sections away from the rows they were chosen on.
##
## ASSERTED AS ORDER IN A SHARED PARENT, not as pixel positions: the three parts of the menu have to
## read top to bottom as one activity (what is running · what you are assembling · what you can
## make), and that is a property of the column's child order which survives any restyling.
func test_the_chosen_parts_sit_under_the_running_craft_inside_the_menu() -> bool:
	var screen := _screen()
	var ok := true
	var column: Node = screen._crafting.get_parent()
	if screen._assembling.get_parent() != column:
		ok = _fail("the chosen parts are not in the same container as the running craft")
	elif screen._make.get_parent() != column:
		ok = _fail("the menu's rows are not in that container either, so order proves nothing")
	else:
		var craft := column.get_children().find(screen._crafting)
		var mid := column.get_children().find(screen._assembling)
		var rows := column.get_children().find(screen._make)
		if not (craft < mid and mid < rows):
			ok = _fail(("the menu does not read running craft (%d), assembling (%d), rows (%d)")
					% [craft, mid, rows])
	# AND NOT IN THE `do` SECTION ANY MORE. Checked by walking `_actions` for the button, because
	# that is what a player would still find there if the move were half done.
	if ok and _button_under(screen._actions, "Assemble") != null:
		ok = _fail("`Assemble` is still in the do section")
	screen.queue_free()
	return ok


## FOLDING THE ROWS AWAY DOES NOT PUT DOWN THE PARTS IN YOUR HANDS.
##
## MY READING OF MAREN'S CLAUSE, NOT HER WORDS: she ruled a running craft is a CONDITION and must
## survive the collapse, and left the bench's placement to me. A half-chosen assembly is the same
## kind of thing — fold the rows with three parts in hand and a container inside them would take
## `Assemble` with it, so the chosen parts are a sibling of the rows rather than a child. Structural,
## so it holds whatever a later edit does to the rows.
func test_folding_the_menu_cannot_put_down_the_parts_you_are_holding() -> bool:
	var screen := _screen()
	var ok := true
	var walk: Node = screen._assembling
	while walk != null:
		if walk == screen._make:
			ok = _fail("the chosen parts live inside the container the toggle hides")
			break
		walk = walk.get_parent()
	# AND IT SURVIVES A REBUILD OF THE ROWS -- THE SAME GUARD `_crafting`'s test needed, which I
	# failed to carry over and a mutation caught. `_rebuild_make` CLEARS the container it owns, so a
	# block moved inside the rows is FREED: the walk above then finds a node with no parent at all
	# and passes about nothing. Second time in one night for this exact shape.
	if ok:
		screen._make_showing = "not a shape any pack has"
		screen._refresh_make()
		if not is_instance_valid(screen._assembling):
			ok = _fail("rebuilding the rows freed the chosen-parts block")
		elif screen._assembling.get_parent() == null:
			ok = _fail("rebuilding the rows took the chosen-parts block off the panel")
	if ok:
		screen._show_make(false)
		if not screen._assembling.visible:
			ok = _fail("folding the rows away hid the parts you are holding")
		elif screen._make.visible:
			ok = _fail("_show_make(false) left the rows visible, so this proves nothing")
	screen.queue_free()
	return ok


func _button_under(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == label:
			return child
		var found := _button_under(child, label)
		if found != null:
			return found
	return null
