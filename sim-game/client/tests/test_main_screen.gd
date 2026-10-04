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
## EVERY EVENT LINE ON SCREEN, oldest-to-newest order not assumed. One Label per line since
## ASSA-117, so the log's "text" is a question about a container rather than about a control.
func _log_text(screen: Node) -> String:
	var out := PackedStringArray()
	for line in screen._log.find_children("*", "Label", true, false):
		out.append((line as Label).text)
	return " · ".join(out)


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
	# AT ANY DEPTH, since ASSA-117 put the scroll box inside the panel's chrome column. Counting one
	# level found zero and reported "0 HUD columns", which happens to be the failure this test
	# exists to catch -- a check that cannot tell "built twice" from "moved" is not a check.
	for child in screen.find_children("*", "ScrollContainer", true, false):
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
##
## THE EVENT LOG IS NO LONGER IN THIS LIST AND THAT IS ASSA-147, not an exemption I helped myself to.
## Maren ruled the log out of the column and left the placement to me; it is now a panel over the map,
## which this test would fail it for. The rule's own reason is what makes the exception safe -- the
## log holds no control, so a click on it cannot mean two things -- and
## `test_the_log_over_the_map_holds_no_control_and_eats_the_clicks_it_covers` is that sentence as a
## lever rather than as this paragraph.
func test_the_screen_builds_a_hud_column_beside_the_map() -> bool:
	var screen := _screen()
	var ok := true
	var beside := AssayHud.VIEW.x - AssayHud.PANEL - AssayHud.MARGIN.x
	for part in [["you", screen._carrying], ["do", screen._actions], ["bench", screen._bench],
			["cursor", screen._cursor],
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
	# FOUND BY WALKING UP FROM A SECTION, NOT BY SCANNING THE SCREEN'S DIRECT CHILDREN. This used to
	# look for a `ScrollContainer` among `screen.get_children()`, which stopped finding it the moment
	# ASSA-117 put the scroll box inside the panel's chrome column -- and the old form could never
	# have proved what the test is about anyway: that the SECTION is inside something that scrolls.
	# Walking up from `_carrying` asserts exactly that.
	var scroll := _scroll_enclosing(screen._carrying)
	var ok := true
	if scroll == null:
		ok = _fail("the HUD column is not inside a ScrollContainer, so a tall pack hides buttons")
	elif scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		ok = _fail("the column scrolls sideways, which would hide a button rather than reveal it")
	elif scroll.size_flags_vertical != Control.SIZE_EXPAND_FILL:
		# THE HEIGHT IS NO LONGER A NUMBER TO CHECK, so what is checked is the derivation that
		# replaced it: the scroll box takes whatever the pinned toggle and the stopped block leave.
		# The old assertion read `custom_minimum_size.y`, which is a floor this box must not have --
		# the stopped block appears and disappears with the world, and a floor would outlive it.
		ok = _fail("the scroll box does not expand to fill the panel, so its height is a number "
				+ "somebody has to keep in step with the controls pinned above it")
	screen.queue_free()
	return ok


## THE NEAREST `ScrollContainer` ABOVE A NODE, or null. See the test above for why this is a walk up
## rather than a scan of one level.
func _scroll_enclosing(node: Node) -> ScrollContainer:
	var walk: Node = node.get_parent()
	while walk != null:
		if walk is ScrollContainer:
			return walk
		walk = walk.get_parent()
	return null


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
##
## **THE RULE DID NOT MOVE; THE SURFACE DID** (Maren's ruling 1, ASSA-127). The sentence is the same
## words, now centred on the map rather than in the status line above it, so this reads it off the
## label that actually carries it. What it asserts is unchanged: both doors, solo first.
##
## The idle-COLOUR clause went with the sentence rather than being dropped: an empty status line has
## no meaningful `status_color`, and the legibility of these words is now asserted where they are
## drawn, against `MAP_BG`, by `test_the_empty_map_names_which_kind_of_empty_it_is`.
func test_the_opening_line_offers_the_door_that_needs_nothing_typed() -> bool:
	var screen := _screen()
	var said: String = screen._map_note.text if screen._map_note != null else ""
	screen.queue_free()
	if not said.contains("Play solo"):
		return _fail("the opening line does not mention Play solo at all: %s" % said)
	if not said.contains("host address"):
		return _fail("the opening line dropped the host door: %s" % said)
	# SOLO FIRST, because the row reads left to right and so does the sentence over it.
	if said.find("Play solo") > said.find("host address"):
		return _fail("the opening line puts the host door first: %s" % said)
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
## still be valid here. An IMMEDIATE removal is caught, by the parent check below.
##
## **THAT PARAGRAPH USED TO NAME `test_the_screen_builds_a_hud_column_beside_the_map` as the lever,
## and since ASSA-147 it is not one**: the log left the HUD column for a panel over the map, so it is
## not in that test's list any more. A comment pointing at a check that no longer looks is worse than
## no comment -- everyone who reads it stops looking -- and this is the second one of mine this week.
##
## The lines are planted rather than played because this file has no relay and no world; the real
## stream is covered by `test_buttons.gd`, which drives a refusal through a real sim.
func test_a_hidden_log_still_carries_its_lines() -> bool:
	var screen := _screen()
	var ok := true
	var planted := PackedStringArray(["41 · you mined 2 ore", "42 · you started walking"])
	screen._log_toggle.pressed.emit()
	# PLANTED INTO THE MODEL AND DRAWN BY THE REAL REBUILD (ASSA-117). It used to set `_log.text`,
	# which was a single Label's text and no longer exists -- the log is one Label per line now, so
	# "the newest line is the brightest" is something a control can be. Driving `_rebuild_log` rather
	# than writing the controls by hand is also the stronger version of the old test: the thing the
	# hide path has to survive is now what the real code built, not what the test typed.
	screen._events = planted
	screen._rebuild_log()
	screen._log_toggle.pressed.emit()
	if screen._log.visible:
		ok = _fail("the control would not hide the log again")
	elif not is_instance_valid(screen._log) or screen._log.get_parent() == null:
		ok = _fail("the log was taken out of the column rather than hidden, so the lines it was "
				+ "carrying are gone and the probes' surface with them")
	elif not _log_text(screen).contains("you mined 2 ore"):
		ok = _fail("a hidden log dropped the lines it was given: '%s'" % _log_text(screen))
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
		elif not _log_text(screen).contains("you started walking"):
			ok = _fail("the revealed log had lost the lines it carried: '%s'" % _log_text(screen))
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


## THE RUNNING BLOCK IS OUTSIDE THE SCROLL BOX, WHICH IS THE WHOLE OF MAREN'S RULING 1 (ASSA-133).
##
## WHAT THIS REPLACES. It used to walk `_crafting`'s ancestors to prove the countdown was not a CHILD
## of the container `_show_make` hides -- true, and arranged. The countdown is now in the chrome, so
## the stronger property is available and is the one asserted: no ancestor of the running block is
## the scroll box, so NOTHING in the column -- not the menu folding, not a section growing, not a
## later edit -- can carry it off the bottom. "Announcing does not scroll" as a structural fact.
##
## `_halt_box` is held to the same bar in the same walk, because the two blocks are one ruling and a
## test that watched only the new one would let the precedent rot.
func test_what_is_running_and_what_has_stopped_are_both_outside_the_scroll_box() -> bool:
	var screen := _screen()
	var ok := true
	for named in [["running", screen._running_box], ["stopped", screen._halt_box]]:
		var label := String(named[0])
		var box: Node = named[1]
		if not is_instance_valid(box):
			ok = _fail("the %s block does not exist" % label)
			break
		var walk: Node = box
		var depth := 0
		while walk != null:
			if walk == screen._scroll:
				ok = _fail(("the %s block is inside the scroll box, so a long enough column can "
						+ "push it off the window") % label)
				break
			walk = walk.get_parent()
			depth += 1
		if not ok:
			break
		# AND IT IS ON THE PANEL AT ALL. A block with no parent passes the walk above for the wrong
		# reason -- the loop ends immediately -- which is the shape of hole that let a countdown live
		# in a freed container once already.
		if depth < 2:
			ok = _fail("the %s block is only %d deep, so the walk above proved nothing" % [label, depth])
			break
	screen.queue_free()
	return ok


## EMPTY IS EMPTY, FOR BOTH CHROME BLOCKS (ASSA-133 box 2). A window with nothing running and nothing
## stopped must look exactly as it did before this item: no heading, no "nothing running", no pixels.
## A fresh screen has never joined a world, so both are the empty case by construction.
func test_the_chrome_blocks_take_no_space_when_they_have_nothing_to_say() -> bool:
	var screen := _screen()
	var ok := true
	for named in [["running", screen._running_box], ["stopped", screen._halt_box]]:
		var box: Control = named[1]
		if box.visible:
			ok = _fail(("nothing is %s and its block is visible. Empty is empty: a reassuring line "
					+ "is the cry-wolf failure one step removed. If this reddens with the block "
					+ "never rebuilt, the `_refresh_%s` call in `_build_ui` is what is missing -- a "
					+ "PanelContainer is visible by default and the refresh only redraws on change.")
					% [String(named[0]), String(named[0])])
			break
	screen.queue_free()
	return ok


## **A SECTION MAY NOT SIT ABOVE THE SECTION IT IS DERIVED FROM** (ASSA-133 ruling 2, box 4). The
## crafting menu is generated from the pack and grows faster than it, so `make` goes below `you`.
##
## ASSERTED AS THE ORDER OF HEADINGS IN THE SHARED PARENT, not as pixel positions: the ruling is
## about which section pushes which off the bottom, and that is child order. Reading the headings
## rather than the bodies is deliberate -- a body can be hidden, and a hidden section still occupies
## its place in the order a later edit would have to respect.
##
## THE LIST IS ONE SHORTER SINCE ASSA-147: `event log` was last and is now a panel over the map, so
## it is checked by the two tests below instead. The rest of Maren's order is untouched, and this
## test now also says the log is not back in the column -- "the log left the column" is the fix, and
## a fix that only lives in a docstring is one somebody re-adds a section to.
func test_the_column_reads_you_do_make_bench_rocks_cursor() -> bool:
	var screen := _screen()
	var ok := true
	var want := ["you", "do", "make", "bench", "rocks", "cursor"]
	var column: Node = screen._carrying.get_parent()
	var seen := PackedStringArray()
	for child in column.get_children():
		if child is Label and (child as Label).theme_type_variation == &"Heading":
			seen.append((child as Label).text)
	if Array(seen) != want:
		ok = _fail(("the column reads %s; Maren ruled %s. A list derived from your pack may not sit "
				+ "above it.") % [seen, want])
	elif column.get_children().has(screen._log):
		ok = _fail("the event log is back in the HUD column, which is ASSA-147: it is unbounded and "
				+ "every other section is not, so in one scroll box it wins against the controls")
	screen.queue_free()
	return ok


## **OPENING THE LOG MAY NOT MOVE A CONTROL** (ASSA-147, Maren's ruling: the event log leaves the HUD
## column). The defect was measured on a real window at seed 14247 tick 519: with the log open, `do`
## -- Mine, Stop and Assay -- sat at y -852..-802, off the top of the clip, because the log was the
## last section of a 2023px column and revealing it scrolled 1120px to the bottom.
##
## **WHAT THIS TEST CAN AND CANNOT HOLD, SAID PLAINLY, BECAUSE THE DIFFERENCE IS WHERE I GET THIS
## WRONG.** This suite works inside `SceneTree._initialize`: `_ready` never fires, no frame is drawn,
## no container ever lays out, so every rect here is zero and a position assertion would be a test of
## nothing. So this holds the STRUCTURE that makes the eviction impossible -- the log is not inside
## the box that scrolls -- and the real-window verdict (every control's rect identical before and
## after the toggle, which fails loudly on the shipped code) lives in `tools/window_shot.gd`, where
## there is a window to measure.
func test_the_event_log_is_outside_the_box_that_scrolls_the_controls() -> bool:
	var screen := _screen()
	var ok := true
	var scroll := _scroll_enclosing(screen._log)
	if scroll != null:
		ok = _fail("the event log is inside the ScrollContainer the controls are in, so revealing "
				+ "it scrolls them off the top: ASSA-147 exactly")
	elif _scroll_enclosing(screen._actions) == null:
		# THE OTHER HALF, OR THIS PASSES FOR THE WRONG REASON. "The log is not in the scroll box" is
		# also true of a screen with no scroll box at all, and of one where the controls left instead.
		ok = _fail("the `do` controls are not in a scroll box any more, so this test is green about "
				+ "a column that no longer exists rather than about the log leaving it")
	elif _scroll_enclosing(screen._log_box) != null:
		ok = _fail("the log's panel is inside a scroll box, so its own surface can be scrolled away")
	screen.queue_free()
	return ok


## THE ONE SURFACE ALLOWED OVER THE MAP CARRIES NO CONTROL, AND STOPS THE MOUSE.
##
## `test_the_screen_builds_a_hud_column_beside_the_map` is the rule this is the exception to, and the
## rule's reason is the exception's constraint: a BUTTON over the map would be a click that means two
## things. The log has no buttons -- its toggle stays in the column, where it is always reachable --
## so the panel is allowed over the world, and this test is what keeps that true.
##
## AND IT STOPS THE MOUSE ON PURPOSE. The map is clicked through `_unhandled_input`, so an `IGNORE`
## panel would let a click pass through the log onto the tile under it: a machine placed on a tile you
## cannot see. `STOP` means the covered tiles are not clickable while the log is up. The region around
## the box is `IGNORE`, because 912x600 of empty space answering the mouse is how
## `_map_note`'s own comment says this goes wrong ("Play solo does nothing", nowhere near that line).
func test_the_log_over_the_map_holds_no_control_and_eats_the_clicks_it_covers() -> bool:
	var screen := _screen()
	var ok := true
	var map := AssayHud.world_rect()
	var region: Control = screen._log_region
	var box: Control = screen._log_box
	var controls: Array = box.find_children("*", "Button", true, false)
	if region == null or box == null:
		ok = _fail("there is no log surface over the map, so ASSA-147's fix is not on the screen")
	elif not controls.is_empty():
		ok = _fail(("the log's panel over the map holds %d Button(s) (%s). A control over the map is "
				+ "a click that means two things; the log's own toggle lives in the column.")
				% [controls.size(), (controls[0] as Button).text])
	elif region.position != map.position or region.size != map.size:
		ok = _fail("the log's region is %s %s, not the map's %s %s: it either covers the HUD column "
				% [region.position, region.size, map.position, map.size]
				+ "or stops short of the surface it is drawn over")
	elif box.size_flags_vertical != Control.SIZE_SHRINK_BEGIN:
		ok = _fail("the log's panel does not shrink to its content, so it is a fixed rectangle over "
				+ "the world: dead space when the log is short, a cut newest line when it is long")
	elif box.mouse_filter != Control.MOUSE_FILTER_STOP:
		ok = _fail("the log's panel passes the mouse through, so a click on a log line lands on the "
				+ "tile underneath it -- placing a machine on a tile the player cannot see")
	elif region.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		ok = _fail("the log's region answers the mouse over the whole map, so every click on the "
				+ "world is swallowed by empty space around the panel")
	screen.queue_free()
	return ok


## THE SURFACE AND THE LINES IN IT ARE ONE STATE (ASSA-147). `_show_log` writes three flags -- the
## panel, the lines and the heading -- because the panel is what a player sees and `_log.visible` is
## what every test, probe and tool in this repo asks. Three flags one function sets can still drift
## the day somebody sets one of them somewhere else, and a log reading `visible` inside a hidden panel
## is exactly the lie ASSA-117 was (a node answering honestly about a state the screen does not have).
##
## DRIVEN THROUGH ALL THREE DOORS, because that is where a fourth writer would appear: the button, the
## L key, and the call `_build_ui` and `window_shot.gd` make directly.
func test_the_log_panel_and_its_lines_can_never_disagree() -> bool:
	var screen := _screen()
	var ok := true
	var key := InputEventKey.new()
	key.keycode = KEY_L
	key.pressed = true
	var doors := {
		"the first screen": func() -> void: pass,
		"the button": func() -> void: screen._log_toggle.pressed.emit(),
		"the L key": func() -> void: screen._unhandled_key_input(key),
		"_show_log(true)": func() -> void: screen._show_log(true),
		"_show_log(false)": func() -> void: screen._show_log(false),
	}
	for named in doors:
		(doors[named] as Callable).call()
		var surface: bool = screen._log_box.visible
		if screen._log.visible != surface or screen._log_heading.visible != surface:
			ok = _fail(("after %s the panel is %s, the lines are %s and the heading is %s. One of "
					+ "them is lying about what is on screen.") % [named, surface,
					screen._log.visible, screen._log_heading.visible])
			break
		elif screen._log_shown != surface:
			ok = _fail("after %s `_log_shown` is %s and the panel is %s"
					% [named, screen._log_shown, surface])
			break
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


## ASSA-107 / Maren's ASSA-88 RULING: THE CHOSEN PARTS LIVE IN THE CRAFTING MENU — not in the `do`
## section two sections away from the rows they were chosen on.
##
## THE RUNNING CRAFT USED TO BE THE FIRST OF THREE and this test read all three in order. It left the
## column on ASSA-133, so what remains of the ruling is the part that was always about the menu: the
## parts you have chosen sit at the menu's head, above the control and the rows it offers.
##
## ASSERTED AS ORDER IN A SHARED PARENT, not as pixel positions: the menu has to read top to bottom
## as one activity (what you are assembling · the control · what you can make), and that is a
## property of the column's child order which survives any restyling.
func test_the_chosen_parts_sit_at_the_head_of_the_crafting_menu() -> bool:
	var screen := _screen()
	var ok := true
	var column: Node = screen._make.get_parent()
	if screen._assembling.get_parent() != column:
		ok = _fail("the chosen parts are not in the same container as the menu's rows")
	elif screen._make_toggle.get_parent() != column:
		ok = _fail("the menu's control is not in that container either, so order proves nothing")
	else:
		var mid := column.get_children().find(screen._assembling)
		var toggle := column.get_children().find(screen._make_toggle)
		var rows := column.get_children().find(screen._make)
		if not (mid < toggle and toggle < rows):
			ok = _fail(("the menu does not read assembling (%d), control (%d), rows (%d)")
					% [mid, toggle, rows])
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
		# **WITH SOMETHING ACTUALLY IN HAND, which this test used to skip** (ASSA-134). It asserted
		# `_assembling.visible` on a screen holding NO parts, so it was reading the default flag of an
		# empty box rather than the fate of a half-chosen assembly -- and it went red the moment that
		# box started hiding itself when it has nothing to show. The claim is about parts you are
		# holding; the fixture has to hold some.
		screen._choose_part(_a_part_stack())
		if screen._building.is_empty():
			ok = _fail("the sim refused the part this test chooses, so the fold proves nothing")
		elif not screen._assembling.visible:
			ok = _fail("choosing a part left the chosen-parts block hidden, before any fold")
		else:
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


## THE SHIPPED THEME'S PANEL COLOUR, which is the surface every readout in the column is drawn on.
##
## READ OUT OF `theme/assay.tres` AND NEVER WRITTEN DOWN HERE. `tools/build_theme.gd` owns the
## palette and refuses to write a theme whose own inks miss WCAG AA on it; a copy of the number in
## this file would stop agreeing with that the first time Marlow moves it, and the test would then be
## checking my memory of a colour against the engine's.
func _panel_surface() -> Color:
	var theme: Theme = load("res://theme/assay.tres")
	if theme == null:
		return Color.BLACK
	var box := theme.get_stylebox("panel", "Panel") as StyleBoxFlat
	return Color.BLACK if box == null else box.bg_color


## THE COLOUR A LABEL IS ACTUALLY DRAWN IN, which is not the colour anybody set.
##
## `modulate` MULTIPLIES the font colour, and that is the whole reason this helper exists rather than
## a direct read of one property. The 4.091:1 defect ASSA-117 fixed was a `modulate` going around the
## outside of the theme's own contrast guard -- so a test that read `font_color` alone would have
## passed over it, and so would one that read `modulate` alone.
func _drawn_color(label: Label) -> Color:
	var c := label.get_theme_color(&"font_color")
	var m := label.modulate
	return Color(c.r * m.r, c.g * m.g, c.b * m.b, c.a * m.a)


## EVERY READOUT IN THE COLUMN CLEARS WCAG AA ON THE PANEL IT SITS ON (ASSA-117).
##
## **THIS IS THE BOARD'S OWN COMPLAINT AS A NUMBER.** "logs are hard on the eyes" (10-02) was a true
## report: `_note` set `modulate = Color(0.55, 0.58, 0.64)`, which multiplied the theme's ink down to
## **4.091:1** against the panel -- under the 4.5 floor `tools/build_theme.gd` REFUSES to write a
## theme at. Every pack sentence, every crafting row, the running-craft line and every log line went
## through that one function. Maren found the same hole on the status line (ASSA-116) and called it
## "a colour doing semantic work outside the only check that can fail it"; this was the same hole on
## roughly every other line in the window.
##
## A SWEEP RATHER THAN A CHECK OF `_note`, because the defect is not in `_note` -- it is in any call
## site that reaches for `modulate`, and there were four more. A sweep fails for the next one too.
##
## THE ONE EXCLUSION, NAMED WITH ITS OWN GUARD: the species glyph letter is drawn on a tint disc and
## not on the panel, so the panel is the wrong surface to judge it against. `AssayHud.glyph_color`
## picks its colour by comparing both candidates' contrast against that disc, and
## `art/check_glyph_contrast.py` fails CI at 4.52 for the worst species and purity. Excluding a
## control from a sweep is only honest when something else can fail for it.
func test_no_readout_in_the_column_is_below_wcag_aa_on_its_panel() -> bool:
	var screen := _screen()
	var surface := _panel_surface()
	var ok := true
	if AssayHud.contrast_ratio(Color.WHITE, surface) < 4.5:
		ok = _fail("the theme's panel colour did not load, so this sweep proves nothing: %s"
				% surface)
		screen.queue_free()
		return ok
	var checked := 0
	var worst := 99.0
	var worst_said := ""
	for section in [screen._make, screen._carrying, screen._actions, screen._bench,
			screen._species, screen._cursor, screen._log, screen._halt]:
		for node in section.find_children("*", "Label", true, false):
			var label := node as Label
			# The glyph letter, by the property that makes it the exception: it is CENTRED INSIDE a
			# Panel of its own, which is the disc. Nothing else in the column is.
			if label.get_parent() is Panel:
				continue
			checked += 1
			var ratio := AssayHud.contrast_ratio(_drawn_color(label), surface)
			if ratio < worst:
				worst = ratio
				worst_said = "'%s' at %s" % [label.text.substr(0, 40), _drawn_color(label)]
	if ok and checked == 0:
		ok = _fail("the sweep found no labels at all, so it would pass over anything")
	elif ok and worst < 4.5:
		ok = _fail(("a readout is drawn at %.3f:1 against the panel, under the 4.5 floor "
				+ "build_theme.gd refuses to write a theme at: %s") % [worst, worst_said])
	screen.queue_free()
	return ok


## THE NEWEST LINE IS THE MOST LEGIBLE AND IT IS THE FIRST ONE YOU REACH (ASSA-117, box 1).
##
## Three claims, and they are separate on purpose: the order, the ramp, and the floor.
##
## **ORDER.** Newest first, which ASSA-117 box 3 grants as presentation ("dimming and ordering are
## presentation"). The argument is the fold: this is the LAST section of a column Marlow measured at
## 2023px in a 720px window, so its bottom edge is the first thing cut off, and oldest-first spends
## the surviving rows on the lines that matter least.
##
## **RAMP.** Strictly dimmer with age, read back off the ENGINE (`get_theme_color`) rather than off
## `AssayHud.log_line_color`'s arithmetic -- otherwise this would be the same expression twice and
## would pass whether or not `_rebuild_log` applied it to anything.
##
## **FLOOR.** Every step still clears AA on the panel. The sweep above covers the log too, but only
## for the lines a freshly built screen has; this drives fourteen.
func test_the_newest_log_line_is_the_brightest_and_the_oldest_is_still_readable() -> bool:
	var screen := _screen()
	var surface := _panel_surface()
	var lines := PackedStringArray()
	for i in 14:
		lines.append("%d · event number %d" % [100 + i, i])
	screen._events = lines
	screen._rebuild_log()
	var drawn: Array = screen._log.find_children("*", "Label", true, false)
	var ok := true
	if drawn.size() != lines.size():
		ok = _fail("%d lines went in and %d Labels came out" % [lines.size(), drawn.size()])
		screen.queue_free()
		return ok
	# THE NEWEST EVENT IS AT THE TOP.
	if not (drawn[0] as Label).text.contains("event number 13"):
		ok = _fail(("the first line in the log is '%s'; the newest event is the one a player who "
				+ "can see two rows of this section must get") % (drawn[0] as Label).text)
	elif not (drawn[drawn.size() - 1] as Label).text.contains("event number 0"):
		ok = _fail("the last line is '%s', not the oldest event"
				% (drawn[drawn.size() - 1] as Label).text)
	if ok:
		var previous := 999.0
		for i in drawn.size():
			var ratio := AssayHud.contrast_ratio(_drawn_color(drawn[i] as Label), surface)
			if ratio >= previous:
				ok = _fail(("line %d is drawn at %.3f:1 and the line above it at %.3f:1, so age "
						+ "does not recede; a ramp that does not move is a ramp nobody chose")
						% [i, ratio, previous])
				break
			if ratio < 4.5:
				ok = _fail(("line %d of %d is drawn at %.3f:1, under the 4.5 floor. The oldest "
						+ "line is dimmer, not unreadable.") % [i, drawn.size(), ratio])
				break
			previous = ratio
	screen.queue_free()
	return ok


## AN EMPTY LOG SAYS WHICH KIND OF EMPTY IT IS. A blank section under a heading reads as a game with
## nothing to say, which is not the same news as a world that has not spoken yet -- the distinction
## `sim::debug::halted_table` already makes for the terminal, and the reason the pack and the bench
## name their own emptiness.
func test_an_empty_log_says_nothing_has_happened_rather_than_nothing() -> bool:
	var screen := _screen()
	screen._events = PackedStringArray()
	screen._rebuild_log()
	var ok := true
	var said := _log_text(screen)
	if said.strip_edges() == "":
		ok = _fail("the event log is a blank space under a heading")
	elif said != AssayHud.quiet_log_line():
		ok = _fail("the empty log reads '%s', which is not the words `quiet_log_line` owns" % said)
	screen.queue_free()
	return ok


## **WHAT HAS STOPPED CANNOT BE SCROLLED AWAY, AND THAT IS STRUCTURAL** (ASSA-117 box 2, Maren's
## ASSA-89/94 ruling: a refusal is a MOMENT, a stall is a CONDITION).
##
## The old answer to "this line must not scroll away" was placement -- put the section near the top,
## where the scroll box is *least likely* to have carried it off. That is an argument about odds. The
## block is OUTSIDE the scroll box, so no amount of content below it and no scroll position can move
## it, and this test is the one that holds that true: it asserts there is no `ScrollContainer`
## anywhere between the block and the screen.
##
## AND THE LINES ARE THE SIM'S, IN THE SIM'S ORDER. `sim::debug::halt_lines` is "every building that
## has stopped, one line each, worst-placed first in placement order"; this block may not sort,
## re-word or count them.
func test_what_has_stopped_is_pinned_outside_the_scroll_and_reads_verbatim() -> bool:
	var screen := _screen()
	var ok := true
	if _scroll_enclosing(screen._halt) != null:
		ok = _fail("the stopped block is inside the scroll box, so fourteen log lines can push the "
				+ "one sentence that explains an eight-second silence off the bottom of it")
	elif screen._halt_box == null or screen._halt_box.visible:
		ok = _fail("the stopped block is on screen with nothing stopped, which is a panel that "
				+ "permanently says nothing is wrong")
	else:
		# The sim's own sentences, with their punctuation and their order.
		var planted := PackedStringArray([
			"smelter 3 at (12, 7) · walls stone · stalled: the fuel will not light",
			"machine 1 at (4, 9) · nothing here to mine",
		])
		screen._rebuild_halt(planted)
		var rows: Array = screen._halt_lines.find_children("*", "Label", true, false)
		if not screen._halt_box.visible:
			ok = _fail("two buildings have stopped and the block is still hidden")
		elif rows.size() != planted.size():
			ok = _fail("%d lines went in and %d came out" % [planted.size(), rows.size()])
		else:
			for i in rows.size():
				if (rows[i] as Label).text != planted[i]:
					ok = _fail(("line %d reads '%s' and the sim said '%s'. The order is placement "
							+ "order and the words are `halt_lines`'") % [i, (rows[i] as Label).text,
							planted[i]])
					break
		if ok:
			# AND IT GOES AWAY AGAIN when the condition clears, which is the other half of
			# "a condition, not a moment": a stall that outlived its own fix would be worse.
			screen._rebuild_halt(PackedStringArray())
			if screen._halt_box.visible:
				ok = _fail("the smelter was fixed and the panel still says it is stopped")
			elif screen._halt_lines != null:
				ok = _fail("the lines are still in the block, one `visible` away from coming back")
	screen.queue_free()
	return ok


## A BENCH ROW IS WRITTEN BY NAME, SO A ROW THAT GROWS A CHILD STILL GETS ITS WORDS (ASSA-117).
##
## **THIS TEST EXISTS BECAUSE A MUTATION SURVIVED.** I changed `_write_design` from `get_child(0)`
## and `get_child(1)` to a lookup by name, ran the mutation back, and the whole suite stayed green --
## because the verdict IS child 0 today, so the index is right by luck and nothing could tell the
## two apart. A hardening with no lever is a comment.
##
## The failure it is about has already happened once, on the other surface: adding a sprite to a pack
## row made child 0 a `TextureRect`, and the fast path that re-texts the count silently stopped
## finding its label. Maren's icon ruling reaches bench rows next, so this row WILL grow a child.
## Here that is simulated by putting one in front, which is the cheapest honest version of it.
func test_a_bench_row_that_grows_a_child_is_still_written_correctly() -> bool:
	var screen := _screen()
	var design := {"index": 0, "verdict": "WILL BREAK", "in_hand": false, "mount": "planted"}
	screen._rebuild_bench([design])
	var ok := true
	var row: Node = screen._bench.get_child(0)
	if row == null:
		ok = _fail("the bench built no row to write into")
		screen.queue_free()
		return ok
	# The icon that is coming. Added at the front, which is where `_icon_box` puts one.
	var icon := TextureRect.new()
	row.add_child(icon)
	row.move_child(icon, 0)
	screen._write_design(row, {"index": 0, "verdict": "SAFE", "in_hand": false, "mount": "planted"})
	var verdict := row.find_child(screen.BENCH_VERDICT, true, false) as Label
	if verdict == null:
		ok = _fail("the bench row has no named verdict label at all")
	elif verdict.text != "SAFE":
		ok = _fail(("the row grew a child and the verdict now reads '%s'; it was written into "
				+ "whatever happened to be child 0") % verdict.text)
	elif row.get_child(0) is Label:
		ok = _fail("the planted child did not land in front, so this test proves nothing")
	screen.queue_free()
	return ok


## AN OLD LOG LINE IS ONE ROW; THE NEWEST ONE IS WHOLE (Maren's ruling, ASSA-117 box 8).
##
## **THE RULING EXISTS BECAUSE THE LOG WAS A STACK OF PANELS.** She measured entries 1, 4, 4, 5 and 6
## rows tall at seed 14247: the tall ones are a design verdict whose numbers already live in `bench`,
## and `sim/src/debug.rs:1785` says in writing that the sentence was ordered to survive being CUT by
## a narrow panel. This client wrapped it instead, so 682px of log went into a 566px box.
##
## **WHAT THIS TEST CAN AND CANNOT SEE.** The height of a drawn row is layout, and `run_tests.gd`
## works in `SceneTree._initialize`: no frame is drawn and nothing is laid out, so "the section got
## shorter" is NOT assertable here and is not asserted. It is the window shot's job
## (`tools/window_shot.gd`, both pinned seeds). What IS visible headless is the two properties the
## engine decides the cut from, and one consequence that matters more than they do.
##
## **THE CONSEQUENCE IS THE LEVER, because the obvious wrong fix passes the properties.** Turning
## wrapping off ALONE gives a Label a minimum width of its whole sentence -- 1012px, asked of the
## engine with the real line at the real font -- and a row 692px wider than the 320px panel is
## ASSA-98's clipping defect restored, which would be a worse bug than the one being fixed and
## invisible to any assertion about wrap modes. So every cut line is required to fit the panel.
##
## The newest line is required to still WRAP rather than merely to be exempt: "shows whole" is a
## promise about a sentence that is wider than the column, and only wrapping keeps it.
func test_an_old_log_line_is_one_row_and_the_newest_is_whole() -> bool:
	var screen := _screen()
	# A FIXTURE SHAPED LIKE THE LINE MAREN MEASURED -- long enough that one row cannot hold it at any
	# plausible font. The wording is this test's, not the sim's: nothing here asserts a sentence.
	var long := ("your design broke: mass 1078 of 705 budget · holds 210 · speed 78 (bare hands 25)"
			+ " · frame(Tonore A 385) + head(Tonore A 120) + hopper(Souktulore B 140) x4")
	var lines := PackedStringArray()
	for i in 12:
		lines.append("%d · %s" % [500 + i, long])
	# THE NEWEST ENTRY IS ALSO A LONG ONE, or "the newest shows whole" would be a claim about a
	# sentence that fits anyway and the exemption could be deleted with nothing going red.
	lines.append("%d · %s" % [512, long])
	screen._events = lines
	screen._rebuild_log()
	var drawn: Array = screen._log.find_children("*", "Label", true, false)
	var ok := true
	if drawn.size() != lines.size():
		ok = _fail("%d lines went in and %d Labels came out" % [lines.size(), drawn.size()])
	else:
		# NEWEST FIRST, so index 0 is the exempt one.
		var newest := drawn[0] as Label
		if newest.autowrap_mode == TextServer.AUTOWRAP_OFF:
			ok = _fail("the newest line does not wrap, so a sentence wider than the column is cut "
					+ "and `the newest shows whole` is false")
		for i in range(1, drawn.size()):
			var line := drawn[i] as Label
			if line.autowrap_mode != TextServer.AUTOWRAP_OFF:
				ok = _fail(("log line %d of %d still wraps, so one event is still as many rows as "
						+ "its sentence wants") % [i, drawn.size()])
				break
			if line.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
				ok = _fail(("log line %d does not wrap and does not trim either, which is a "
						+ "sentence that runs out of its panel in silence") % i)
				break
			var width := line.get_combined_minimum_size().x
			if width > AssayHud.PANEL:
				ok = _fail(("log line %d asks for %.0fpx inside a %.0fpx panel: ASSA-98's clipping, "
						+ "restored by turning wrapping off without a trim") % [i, width,
						AssayHud.PANEL])
				break
	screen.queue_free()
	return ok


## NO HEADING ON THE JOIN SCREEN STANDS OVER NOTHING (Maren's ruling, ASSA-134).
##
## `_note`'s own docstring is the rule: *"a heading with nothing under it reads as a bug, so every
## empty section says which kind of empty it is."* Maren checked it against the shipped picture and
## found **five sections honouring it and two not** -- `cursor`, a bare Label that `_refresh` writes
## only after a join and so never reaches on the first screen, at 93px the largest labelled void in
## the column; and the 53px between the `make` heading and its own toggle.
##
## **ASSERTED OVER EVERY SECTION, NOT OVER `cursor`.** A test that named the cursor would be a test
## about the bug Maren happened to find; this one is about the rule, so the next section added to this
## column cannot ship blank. The sweep is why the `make` void shows up here at all -- nobody,
## including Maren, had noticed that one until a number was taken.
##
## A HIDDEN SECTION IS NOT A VOID and is skipped: the event log starts hidden with its heading, which
## is ASSA-89 working as ruled. What is required is that a heading a stranger can SEE has something
## under it they can READ -- any visible control carrying text, because the `make` section's first
## reachable thing is legitimately its toggle and not a sentence.
func test_no_visible_heading_on_the_join_screen_stands_over_nothing() -> bool:
	var screen := _screen()
	var ok := _sweep_headings(screen, "the join screen")
	screen.queue_free()
	return ok


## **AND THE SAME RULE ONCE THERE IS A WORLD, WITH NOTHING UNDER THE MOUSE** (ASSA-127 box 3).
##
## THE BOX HAS TWO HALVES AND ONLY ONE OF THEM WAS EVER CHECKED. `quiet_cursor_line` covers the
## pre-join half, and the sweep above holds it; the in-world half -- "after joining with nothing
## hovered, say that kind of empty instead" -- had no test at all, and Nerite left the box open on
## exactly that gap because neither shot in a window set shows it.
##
## **THE MOUSE HAS NOT BEEN OVER THE MAP**, which is the state this is about and the state a window
## shot is always in: `_refresh` falls back to the tile you STAND on and says `where you stand`, so
## the section is never empty in a world. If that fallback were dropped, the join-screen sweep would
## stay green -- it never reaches a world -- and the cursor would be a heading over nothing for every
## player who had not yet moved a mouse.
##
## STILL THE SWEEP AND NOT A TEST NAMED FOR THE CURSOR, for the reason the join-screen one gives: a
## test about `cursor` is a test about the bug Maren happened to find. This one is about the rule, so
## the next section added to this column cannot ship blank in a world either.
func test_no_visible_heading_in_a_joined_world_stands_over_nothing() -> bool:
	var screen := _joined_screen()
	if not screen._sim.running():
		screen.queue_free()
		return _fail("premise: no world was joined, so this sweep is about the join screen again")
	if screen._hovering:
		screen.queue_free()
		return _fail("premise: the mouse is already over the map, which is not the state under test")
	var ok := _sweep_headings(screen, "a joined world (nothing hovered)")
	screen.queue_free()
	return ok


## THE SWEEP ITSELF, over whatever state the caller put the screen in.
##
## Shared so the two states cannot drift into asking different questions -- the whole value of this
## being a sweep is that it is ONE rule, and two copies of it would be two rules the day somebody
## edited one.
func _sweep_headings(screen: Node, where: String) -> bool:
	var column: Node = screen._make.get_parent()
	var ok := true
	var heading := ""
	var said := false
	# THE COLUMN IN ORDER: every heading opens a section and everything after it belongs to that
	# section until the next heading. Read off `theme_type_variation`, which is what MAKES a heading a
	# heading here, rather than off a list of names this test would have to keep in step.
	for child in column.get_children():
		var control := child as Control
		if control == null:
			continue
		var is_heading: bool = control is Label and control.theme_type_variation == &"Heading"
		if is_heading:
			if heading != "" and not said:
				ok = _fail(("the `%s` heading is visible on %s with nothing readable under it: "
						+ "a stranger reads that as a game with nothing to say") % [heading, where])
				break
			heading = (control as Label).text if control.visible else ""
			said = false
			continue
		if heading == "" or not control.visible:
			continue
		if _carries_text(control):
			said = true
	if ok and heading != "" and not said:
		ok = _fail("on %s the last section, `%s`, is a visible heading over nothing"
				% [where, heading])
	return ok


## Does this control, or anything visible inside it, actually put words on screen?
func _carries_text(control: Control) -> bool:
	if control is Label and (control as Label).text.strip_edges() != "":
		return true
	if control is Button and (control as Button).text.strip_edges() != "":
		return true
	# DESCENDING ONLY THROUGH VISIBLE CHILDREN, AND NOT VIA `is_visible_in_tree` -- asked of the
	# engine after it reported every section blank: a screen built under the test runner has no
	# visible ancestor chain, so `is_visible_in_tree` is false for every node in it and the sweep
	# would have passed or failed on a property of the harness rather than of the panel.
	for child in control.get_children():
		var inner := child as Control
		if inner != null and inner.visible and _carries_text(inner):
			return true
	return false


## **THE MAP NAMES WHICH KIND OF EMPTY IT IS, AND IT IS 59% OF THE WINDOW** (Maren's ruling 1,
## ASSA-127).
##
## Six surfaces in the HUD column say which kind of empty they are -- the sweep above is that rule.
## The seventh is the map, measured twice at **543,180 px of one colour = 58.9% of the window**, and
## it said nothing; the sentence that explains it sat in the status line at ~1.5% of the window,
## above the thing being explained.
##
## **THE CONTRAST IS ASSERTED HERE AND NOT BY THE COLUMN SWEEP, which is the trap this control walks
## into.** `test_no_readout_in_the_column_is_below_wcag_aa_on_its_panel` iterates the column's
## sections; this note is not in the column, and it sits on `MAP_BG` (0.10/0.11/0.13) rather than on
## the panel's surface. A new readout on a new background escapes every guard we already had, and
## `_drawn_color` is used rather than `font_color` because `modulate` multiplies what the theme chose
## and is how 4.091:1 shipped once already.
##
## THE SPAN IS A PROPERTY, NOT A COORDINATE: enclosed by the map's rectangle and covering most of it,
## with the text centred both ways. A one-line label parked in a corner would satisfy "the map has a
## note" and would not be the thing Maren ruled for.
func test_the_empty_map_names_which_kind_of_empty_it_is() -> bool:
	var screen := _screen()
	var ok := true
	var note: Label = screen._map_note
	var world := AssayHud.world_rect()
	if note == null:
		ok = _fail("the join screen's map has no note at all")
	elif not note.visible:
		ok = _fail("the map's note exists but is hidden on the first screen a stranger sees")
	elif note.text != AssayHud.empty_map_line() or note.text.strip_edges() == "":
		ok = _fail("the map's note is not the shipped sentence: '%s'" % note.text)
	elif not world.encloses(Rect2(note.position, note.size)):
		ok = _fail(("the map's note is not on the map it explains: note %s, map %s")
				% [Rect2(note.position, note.size), world])
	elif note.size.x * note.size.y < world.size.x * world.size.y * 0.5:
		ok = _fail(("the map's note covers %d px of a %d px rectangle, so centring it says nothing "
				+ "about where the words land") % [note.size.x * note.size.y,
				world.size.x * world.size.y])
	elif note.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER \
			or note.vertical_alignment != VERTICAL_ALIGNMENT_CENTER:
		ok = _fail("Maren's ruling is a CENTRED line; this one is aligned %d/%d"
				% [note.horizontal_alignment, note.vertical_alignment])
	elif note.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		ok = _fail("a 912x600 label that answers the mouse swallows every click on the map, and "
				+ "the bug would read as `Play solo does nothing`")
	else:
		var ratio := AssayHud.contrast_ratio(_drawn_color(note), AssayHud.MAP_BG)
		if ratio < 4.5:
			ok = _fail(("the map's note is drawn at %.3f:1 against MAP_BG, under the 4.5 floor "
					+ "build_theme.gd refuses to write a theme at: %s")
					% [ratio, _drawn_color(note)])
		else:
			print("    map note: %.3f:1 on MAP_BG" % ratio)
	# ONE SENTENCE IN ONE PLACE, which is half of what the ruling asked for. Leaving it in the status
	# line too would pass every assertion above and still be the thing she filed.
	if ok and screen._status.text.strip_edges() == AssayHud.empty_map_line().strip_edges():
		ok = _fail("the invitation is still in the status line as well as on the map")
	screen.queue_free()
	return ok


## **THE NOTE IS SHOWN EXACTLY WHEN THE MAP HAS NOTHING ON IT**, asserted through `_refresh_world`
## rather than by poking the flag (ASSA-127).
##
## The derivation lives in `_refresh_map_note`, which reads `_world.view.is_empty()` -- the same fact
## `world_layer.gd` uses to decide whether to paint anything. **Both branches of `_refresh_world` are
## driven here on purpose**: a test that only called the helper would pass with the helper wired to
## nothing, which is exactly the shape of bug that has got past me before.
func test_the_maps_note_is_shown_exactly_when_the_map_is_empty() -> bool:
	var screen := _screen()
	var ok := true
	# Pre-join: no sim, so `_refresh_world` takes its early return. Seeded wrong first, so a missing
	# call cannot look like a pass.
	screen._map_note.visible = false
	screen._refresh_world()
	if not screen._map_note.visible:
		ok = _fail("with no world, _refresh_world left the map silent")
	screen.queue_free()

	var joined := _joined_screen()
	if ok and joined._sim.running():
		joined._map_note.visible = true
		joined._refresh_world()
		if joined._world.view.is_empty():
			ok = _fail("the welcomed screen drew no world, so this half proves nothing")
		elif joined._map_note.visible:
			ok = _fail("the map has a world on it and still says there is no world yet")
	elif ok:
		ok = _fail("could not build an offline world, so the in-world half proves nothing: %s"
				% joined._sim.fail_reason)
	joined.queue_free()
	return ok


## **"1 players" WAS THE FIRST LINE OF EVERY SCREENSHOT OF ASSAY THAT EXISTS** (ASSA-145).
##
## Solo is `Play solo`, which is how every window shot was taken and how a stranger opens the game,
## so the second line of the window has read `6 species, 1 players` in every picture the board has
## looked at. The Game Director filed it as the same defect as `5 of your 3 Tonore ore`: a sentence
## that only reads in the good case is a defect.
##
## DRIVEN AT EXACTLY 1, ON A REAL SCREEN, AGAINST THE LABEL'S OWN TEXT. A fresh offline world has
## one player and no bundles applied yet, which is why this is the only state worth driving: all
## three counts were already right at 0 and at 2 and had been printing wrongly for weeks.
func test_the_headline_counts_agree_with_their_nouns() -> bool:
	var screen := _joined_screen()
	screen._refresh()
	var line: String = screen._detail.text
	if not line.contains("1 player ·"):
		return _fail("a solo world does not say `1 player`: %s" % line)
	for wrong in ["1 players", "1 bundles", "1 hashes"]:
		if line.contains(wrong):
			return _fail("the headline says `%s`: %s" % [wrong, line])
	# THE PREMISE: if the counts were missing from the line altogether, every assertion above would
	# pass on a sentence with no numbers in it.
	for noun in ["player", "applied", "reported", "species", "tiles"]:
		if not line.contains(noun):
			return _fail("the headline has no `%s` at all: %s" % [noun, line])
	# AND THE PLURAL STILL WORKS, which is the half a singular-only fix breaks: 6 species and 96
	# tiles are on this same line and must not have been turned singular.
	if not line.contains("6 species") or not line.contains("96 x 64 tiles"):
		return _fail("a plural on this line stopped reading as one: %s" % line)
	return true


## A live screen welcomed into a fresh offline world, the way `test_buttons.gd::_joined` does it:
## `_ready` by hand because the suite works inside `SceneTree._initialize`.
func _joined_screen(seed_text := "777042") -> Node:
	var screen: Node = load("res://scenes/main.tscn").instantiate()
	runner.root_node.add_child(screen)
	screen._ready()
	var welcome := AssaySimHost.fresh_welcome_json(seed_text, "limpet")
	if welcome != "":
		screen._client.play_offline()
		screen._client.feed_offline(welcome)
	return screen


## A STACK SHAPED LIKE A FRAME PART, out of the sim's own catalogue of kinds. The first part of an
## assembly must be a frame (`part_press_refusal`), so this is what a press that is NOT refused looks
## like -- the fold test needs something in hand or it is reading an empty box's default flag.
func _a_part_stack() -> Dictionary:
	for entry in AssaySimHost.part_kinds():
		var part: Dictionary = entry
		if bool(part.get("is_frame", false)):
			var kind := String(part.get("name", ""))
			return {"kind": kind, "species": 0, "species_name": "Testore", "grade": "C",
					"count": 1, "name": kind}
	return {}
