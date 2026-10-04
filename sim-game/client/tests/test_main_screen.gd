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


## WHETHER A CONTROL WOULD BE DRAWN, asked of the control AND of every ancestor it hangs from.
##
## `is_visible_in_tree()` is the engine's answer to this question and cannot be used here: the suite
## runs inside `SceneTree._initialize`, where a node added under the runner reports
## `is_inside_tree() == false`, so the engine's answer is about a node that is not yet anywhere.
##
## Walking the chain also keeps the test about the CONTROL rather than about the container today's fix
## happens to hide. A later refactor that moves the hide to a different ancestor still has to pass,
## and one that hides a control's parent cannot read as "the control is fine".
func _on_screen(node: Node) -> bool:
	var walk: Node = node
	while walk != null:
		if walk is CanvasItem and not (walk as CanvasItem).visible:
			return false
		walk = walk.get_parent()
	return true


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
## **IT ASKS THE WHOLE ROW IN TREE ORDER, AND IT USED TO ASK ONE INDEX** -- which my own ASSA-175
## refactor would have left green while meaning less. Putting the three dead controls in a band kept
## `get_index() == 0` true of the band's first child, so the old assertion would have passed with the
## band moved to the END of the row, i.e. with Play solo last on screen. A `BoxContainer` lays its
## children out in tree order, so the flattened reading below is the left-to-right one the item is
## about, however many containers it is nested in.
##
## WHAT THIS CANNOT DO IS WATCH THE FOCUS LAND. Measured: inside `SceneTree._initialize`, where this
## suite runs, a node added under the root reports `is_inside_tree() == false`, `get_viewport()` is
## null, and `grab_focus()` errors out leaving `has_focus()` false. One frame later it works, so the
## real focus owner is read back off the viewport by `tools/focus_probe.gd` instead, headless.
func test_play_solo_is_the_first_door_in_the_row() -> bool:
	var screen := _screen()
	var button: Button = screen._solo_button
	var reading := _row_reading(screen._join_band.get_parent())
	var names := PackedStringArray()
	for control in reading:
		names.append(control.get_class() + ":" + String(control.get("text")))
	var ok := true
	if not is_instance_valid(button):
		ok = _fail("the Play solo button does not exist")
	elif button.get_parent() == null:
		ok = _fail("the Play solo button is not in the screen at all")
	elif button.text != "Play solo":
		ok = _fail("the first door reads `%s`" % button.text)
	elif reading.is_empty() or reading[0] != button:
		ok = _fail("the row reads %s, so Play solo is not the first door" % ", ".join(names))
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
		# THE NO-WORLD HALF, because this screen never joins one (ASSA-186). What the sentence may
		# not be is the in-world route -- that is the rule, and it is swept over the whole screen in
		# `test_no_section_on_the_join_screen_asks_for_a_world_it_has_not_got`.
		var line: Label = bench.get_child(0) as Label
		if line == null or line.text != AssayHud.no_designs_line(false):
			ok = _fail("an empty bench must say which kind of empty, shows '%s'"
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
	if said != AssayHud.nothing_to_make_line(false):
		ok = _fail("the empty menu says `%s`" % said)
	screen.queue_free()
	return ok


## THE ONE SENTENCE A SECTION IS SHOWING, or "" if it is not showing exactly one.
##
## Shared by the two ASSA-186 tests so they cannot drift into reading this column differently, and it
## COUNTS rather than taking the first child: a section holding two notes is a different screen from
## the one under test and must not read as the first of them. Visibility is asked of the ancestor
## chain (`_on_screen`), because the log lives in a box its toggle raises and lowers.
func _lone_note(section: Node) -> String:
	var said := ""
	var notes := 0
	for child in section.find_children("*", "Label", true, false):
		var label := child as Label
		if _on_screen(label) and label.text.strip_edges() != "":
			notes += 1
			said = label.text
	return said if notes == 1 else ""


## **NOTHING ON THE JOIN SCREEN MAY ASK FOR A WORLD IT HAS NOT GOT** (ASSA-186, Maren's ruling).
## Three of the six sections did: the bench said "mine, smelt and make parts first", the crafting menu
## "mine some rock first", and the event log answered as a world that had not spoken yet. Two of them
## with no key pressed, on the first screen a stranger ever sees.
##
## **A SWEEP OVER THE WHOLE SCREEN RATHER THAN THREE NAMED ASSERTIONS**, for the reason the heading
## sweeps give: three assertions are a test about the three sections Maren happened to read, and the
## defect is a CLASS -- a sentence written for a world, drawn where there is none. A seventh section
## shipping "mine some rock first" fails this with nobody remembering this item.
##
## **THE FORBIDDEN PHRASES ARE THE RULING'S OWN, NOT `AssayHud`'s.** A sweep that asked the wording
## functions what to expect would agree with any wording they returned, which is the self-agreeing
## test I have shipped twice this week. These are the three the acceptance box names, bare `smelt`
## included -- on this screen there is no smelting to mention at all.
##
## **TWO ASSERTIONS, BECAUSE THE PHRASE SWEEP ALONE HAS A HOLE I MEASURED.** Reverting the log's
## no-world wording leaves "nothing has happened yet" on the join screen, which contains none of the
## three phrases and is still the wrong kind of empty -- so each of the three sections must also NAME
## THE DOOR. And the premise is checked before either: pressing (L) before this item revealed a
## visible heading over an empty section, which is a worse defect than a wrong sentence and would
## have passed a sweep that only read what was there.
##
## WHAT IT CANNOT SEE, and `test_the_empty_sections_say_the_in_world_kind_once_a_world_arrives` owns:
## deleting the in-world sentences, or never re-saying them when a world arrives, leaves this green.
func test_no_section_on_the_join_screen_asks_for_a_world_it_has_not_got() -> bool:
	var screen := _screen()
	# PRESSED, because the log is folded at build and its sentence is one press away on a live
	# control. Through the button's own signal rather than `_show_log`, so this is what a click does.
	screen._log_toggle.emit_signal("pressed")
	var ok := true
	# THE PREMISE FIRST: the three sections each show exactly one sentence before a join. Without
	# this a sweep over an empty column passes by having nothing to read -- and an empty section
	# under a visible heading is its own defect (ASSA-134), not a pass.
	var sentences := {"the bench": _lone_note(screen._bench),
			"the crafting menu": _lone_note(screen._make),
			"the event log": _lone_note(screen._log)}
	for named: String in sentences:
		if String(sentences[named]) == "":
			ok = _fail(("premise: %s is not showing exactly one sentence before a join, so the "
					+ "sweep below has nothing to read there") % named)
	if not ok:
		screen.queue_free()
		return false
	# **AND EACH OF THE THREE POINTS AT THE DOOR**, which is the half a forbidden-phrase sweep cannot
	# see: "nothing has happened yet" instructs nobody and is still an answer about a world that does
	# not exist. `do` and `rocks` were already right this way, and Maren's wordings mirror them. The
	# word rather than the sentence, so a rewording that still names the door passes.
	for named: String in sentences:
		if not String(sentences[named]).contains("join"):
			ok = _fail(("before a join %s says '%s', which names neither the door nor what is "
					+ "missing") % [named, String(sentences[named])])
	# AND NOW THE WHOLE SCREEN, not only those three. Every label a stranger can see.
	for child in screen.find_children("*", "Label", true, false):
		var label := child as Label
		if not _on_screen(label):
			continue
		for instruction: String in ["mine some rock first", "smelt", "make parts first"]:
			if label.text.contains(instruction):
				ok = _fail(("the join screen says `%s`, which needs a world: '%s'. Every empty "
						+ "section must say WHICH kind of empty it is (hud.gd), and with no world "
						+ "the kind is a missing world") % [instruction, label.text])
	screen.queue_free()
	return ok


## **AND THE FRAME A WORLD ARRIVES, ALL THREE SAY THE OTHER KIND OF EMPTY** (ASSA-186 box 3).
##
## This is the half the join-screen sweep cannot see, and it is not a wording question. Every section
## in this column caches what it drew by SHAPE, and **an empty section has the same shape either side
## of a join**: no designs is "" before and after, so is an empty menu, so is an empty log. A fix that
## only changed the wordings would leave "join a world and the machines you build appear here" on the
## bench of a world you are standing in, for as long as the bench stays empty -- which on a fresh
## world is the first minutes of play, and the whole of the demo's first stretch.
##
## It drives the real transition: a screen built with no world, a real `Welcome` fed through the real
## client, then ONE `_refresh()` -- the call `_process` makes every frame and the only place either
## side of the early return can notice. The expected sentences are LITERALS of what shipped before
## this item, because box 3 is exactly that they do not change in a world.
##
## SEPARATION FROM THE SWEEP, which is what makes two tests honest rather than one duplicated:
## dropping `_resay_the_empty_sections` reddens THIS alone (the sweep never reaches a world); keeping
## it and wording the no-world half as an instruction reddens the SWEEP alone (this test reads only
## in-world sentences). Neither covers the other.
func test_the_empty_sections_say_the_in_world_kind_once_a_world_arrives() -> bool:
	var screen := _screen()
	screen._log_toggle.emit_signal("pressed")
	var welcome := AssaySimHost.fresh_welcome_json("777042", "marlow")
	var before := _lone_note(screen._bench)
	if welcome == "" or before != AssayHud.no_designs_line(false):
		screen.queue_free()
		return _fail(("premise: with no world the bench reads '%s' and the welcome is %d bytes, so "
				+ "this test is not starting where it thinks") % [before, welcome.length()])
	screen._client.play_offline()
	screen._client.feed_offline(welcome)
	screen._refresh()
	var id: int = screen._client.player_id
	if not screen._sim.running() or id < 0:
		screen.queue_free()
		return _fail("premise: nothing is being simulated, so this is the join screen a second time")
	# AND THE SECTIONS MUST STILL BE EMPTY IN THAT WORLD, or they would be showing rows and this
	# test would be reading a row rather than the sentence under test.
	if not screen._sim.designs_of(id).is_empty() or not screen._sim.make_offers(id).is_empty() \
			or not screen._events.is_empty():
		screen.queue_free()
		return _fail(("premise: a fresh world arrives with %d designs, %d offers and %d events, so "
				+ "these sections are not empty") % [screen._sim.designs_of(id).size(),
				screen._sim.make_offers(id).size(), screen._events.size()])
	var ok := true
	ok = _reads_in_world(screen._bench, "bench",
			"nothing built yet — mine, smelt and make parts first") and ok
	ok = _reads_in_world(screen._make, "crafting menu",
			"nothing you are carrying can be worked by hand — mine some rock first") and ok
	ok = _reads_in_world(screen._log, "event log", "nothing has happened yet") and ok
	screen.queue_free()
	return ok


## **THE SCHEMATIC HAS THE FACT ITS DISCS ARE DRAWN FROM, ON THE REAL SCREEN** (ASSA-187).
##
## This is the wiring half, and it is the half that cannot be checked in `test_hud.gd`:
## `AssayHud.deposit_disc` being right buys nothing until the list `main.gd::_draw` iterates actually
## carries `hand_minable`, and it reads that key WITHOUT A DEFAULT on purpose. So a binding that
## stopped sending it does not draw a wrong map, it draws NO map -- the frame aborts on the first
## disc, and the one surface for crossing a 96x64 world goes blank. That is a failure mode worth a
## test of its own, because the pure test above and the shot below would both survive it: the shot
## would be of an empty rectangle and nobody would know which of fifty things did it.
##
## It drives the real screen into the real schematic through `_show_close_up(false)` -- the same
## setter the (V) toggle calls -- rather than assigning `_close_up`, so the state under test is one a
## player can reach.
##
## **WHAT IT CANNOT SEE, SAID PLAINLY: whether `_draw` branches on any of it.** Nothing in a headless
## suite can read a `draw_circle`, and `--headless` has no frame to photograph. The picture is
## `client/tools/schematic_minability_shot.gd` plus `shared/assay/assa187_measure.py`, run with a real
## window and measured in greyscale, and that is the evidence for Maren's boxes 1 to 3.
func test_the_schematic_has_the_minability_of_every_disc_it_draws() -> bool:
	var screen := _joined_screen()
	screen._show_close_up(false)
	if screen._close_up or not screen._sim.running():
		screen.queue_free()
		return _fail(("premise: close_up %s and running %s, so `_draw` would return before a disc "
				+ "and this test is about nothing") % [screen._close_up, screen._sim.running()])
	var ok := true
	var states := {}
	var drawn := 0
	for entry in screen._sim.deposits():
		var deposit: Dictionary = entry
		if int(deposit.get("amount", 0)) <= 0:
			continue
		drawn += 1
		if not deposit.has("hand_minable"):
			ok = _fail(("the screen is about to draw a deposit with no `hand_minable` on it: %s. "
					+ "`deposit_disc` reads that key with no default, so this is a blank schematic.")
					% [deposit.keys()])
			break
		var disc := AssayHud.deposit_disc(deposit, 18.0)
		states[bool(disc["filled"])] = true
	if ok and (drawn < 2 or states.size() != 2):
		ok = _fail(("premise: %d discs and %d distinct fill states on seed 777042. The Game "
				+ "Director counted 6 of 13 unminable there; one state means this world cannot "
				+ "show the distinction and the assertions above are vacuous")
				% [drawn, states.size()])
	screen.queue_free()
	return ok


## ONE SECTION'S IN-WORLD SENTENCE, named in the failure so three sections do not report as one.
func _reads_in_world(section: Node, named: String, want: String) -> bool:
	var said := _lone_note(section)
	if said == want:
		return true
	return _fail(("in a world the %s reads '%s'. Before ASSA-186 it read '%s', and that sentence is "
			+ "right here -- either it changed or the no-world one was never re-said")
			% [named, said, want])


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


## THE SURFACE ACTUALLY BEHIND A LABEL, ASKED OF THE BUILT TREE (ASSA-152, Maren's amended box 3).
##
## **THE OLD READING WAS OF THE GENERATOR AND THAT IS THE WHOLE DEFECT CLASS.** `_panel_surface()`
## returns what the theme DECLARES its panel to be. Maren's ASSA-117 ruling: *"the theme refusing to
## WRITE below 4.5 while the window could still RENDER below it is the defect class, not the
## symptom. A check that guards the generator and not the output is a check I have never seen fire."*
## It did not fire. `build_theme.gd::_style_panel` styles `Panel` and `PanelContainer`, the HUD
## column was a VBox inside a ScrollContainer inside a VBox, and SURFACE was painted on **zero
## pixels** -- so every line in the column rendered on Godot's default clear colour (77,77,77) and
## INK_MUTED came out at 3.86:1 where the guard had verified 6.74:1.
##
## So this climbs the REAL ancestors and asks each whether IT resolves a panel stylebox. A `Label`
## answers no (the theme has no `panel` entry for `Label`), a `VBoxContainer` answers no, a `Panel`
## or `PanelContainer` answers yes. The first yes going up is what is painted behind the label.
## `null` means nothing in its whole chain paints anything, which is not a gap in this check -- it
## is the bug, and the sweep below fails on it by name.
##
## THE RECT IS NEVER CONSULTED, deliberately: the test runner builds the screen in
## `SceneTree._initialize`, so containers have not laid out and every child rect is zero. A
## geometric "which panel is under this label" would be reading zeros and calling it a surface.
## Ancestry is the one relationship that is true before layout.
func _surface_behind(label: Label) -> Variant:
	var node: Node = label.get_parent()
	while node != null:
		var control := node as Control
		if control != null and control.has_theme_stylebox(&"panel"):
			var box := control.get_theme_stylebox(&"panel") as StyleBoxFlat
			if box != null:
				return box.bg_color
		node = node.get_parent()
	return null


## EVERY READOUT IN THE COLUMN CLEARS WCAG AA ON THE SURFACE THE TREE ACTUALLY PUTS BEHIND IT
## (ASSA-152). The sweep below is the ASSA-117 one re-aimed: same labels, same `modulate` arithmetic,
## but the second colour now comes from `_surface_behind` instead of from the theme file.
##
## **THE BOARD COMPLAINED AT 4.091:1 AND THIS SCREEN HAS BEEN AT 3.86:1 EVER SINCE.** INK_MUTED is
## every section heading, every crafting row and the `acting on ...` line -- the surface where a
## player decides what to build.
func test_every_readout_clears_aa_on_the_surface_behind_it() -> bool:
	var screen := _screen()
	var ok := true
	var checked := 0
	var unpainted := PackedStringArray()
	var worst := 99.0
	var worst_said := ""
	for section in [screen._make, screen._carrying, screen._actions, screen._bench,
			screen._species, screen._cursor, screen._log, screen._halt]:
		for node in section.find_children("*", "Label", true, false):
			var label := node as Label
			# The glyph letter: centred inside a Panel of its own, which is the tint disc, not the
			# column. `art/check_glyph_contrast.py` fails CI at 4.52 for the worst species and
			# purity, so excluding it here is honest -- something else can fail for it.
			if label.get_parent() is Panel:
				continue
			checked += 1
			var behind: Variant = _surface_behind(label)
			if behind == null:
				# NOT SKIPPED. A label with nothing painted behind it is the defect, and a sweep
				# that passed over it is how this shipped: it sits on the engine's clear colour,
				# which no theme guard can reach.
				unpainted.append("'%s'" % label.text.substr(0, 30))
				continue
			var ratio := AssayHud.contrast_ratio(_drawn_color(label), behind as Color)
			if ratio < worst:
				worst = ratio
				worst_said = "'%s' at %s on %s" % [label.text.substr(0, 40), _drawn_color(label),
						behind]
	if checked == 0:
		ok = _fail("the sweep found no labels at all, so it would pass over anything")
	elif not unpainted.is_empty():
		ok = _fail(("%d of %d readouts have NO painted surface in their whole ancestor chain, so "
				+ "they render on the engine's clear colour: %s")
				% [unpainted.size(), checked, " ".join(unpainted)])
	elif worst < 4.5:
		ok = _fail(("a readout is drawn at %.3f:1 against the surface actually behind it, under "
				+ "the 4.5 floor: %s") % [worst, worst_said])
	screen.queue_free()
	return ok


## THE PAINTED SURFACE MOVES NOTHING (ASSA-152). Maren ruled a SIBLING `Panel` to avoid reflow and I
## built a PARENT instead, because her own amended box 3 climbs ancestors and a sibling is never one.
## A parent is only safe if `Panel` really does lay out no children -- so that is asserted here
## rather than believed, against the arrangement she ruled.
##
## `chrome` must end up at the SAME GLOBAL RECT it had as a sibling: position `(VIEW.x - PANEL -
## MARGIN.x, COLUMN_TOP)`, size `(PANEL, VIEW.y - COLUMN_TOP - 24)`. If a `Panel` ever started
## imposing margins the way a `PanelContainer` does, that global rect is where it would show.
func test_the_painted_surface_moves_no_control() -> bool:
	var screen := _screen()
	var ok := true
	var surface := screen.get_node_or_null(NodePath(screen.COLUMN_SURFACE)) as Panel
	if surface == null:
		screen.queue_free()
		return _fail("no %s in the screen, so the column has no painted surface at all"
				% screen.COLUMN_SURFACE)
	if surface.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		ok = _fail("the column's surface would swallow clicks on empty column: filter %d"
				% surface.mouse_filter)
	var want_pos := Vector2(AssayHud.VIEW.x - AssayHud.PANEL - AssayHud.MARGIN.x,
			AssayHud.COLUMN_TOP)
	var want_size := Vector2(AssayHud.PANEL, AssayHud.VIEW.y - AssayHud.COLUMN_TOP - 24.0)
	if surface.position != want_pos or surface.size != want_size:
		ok = _fail("the surface is not the column's rect: %s %s, wanted %s %s"
				% [surface.position, surface.size, want_pos, want_size])
	# THE PAD IS THE SURFACE'S WHOLE RECT, so the painted area and the padded area are one thing.
	#
	# **THIS USED TO ASSERT `chrome`'s RECT AND NO LONGER CAN, which is a real loss and is named
	# rather than quietly dropped** (ASSA-142). `chrome` is inside a `MarginContainer` now, so its
	# rect is decided on the first layout pass -- and the test runner builds in
	# `SceneTree._initialize`, where layout never happens. Any number asserted for it here would be
	# the pre-layout zero, which is a reading about nothing. What this file CAN still hold is that
	# the painted rect is the column's rect; what moved to the window shot is whether the glyphs
	# landed inside it (ASSA-142 box 2, which is a pixel claim and says so).
	var pad := surface.get_node_or_null(NodePath(screen.COLUMN_PAD)) as MarginContainer
	if pad == null:
		ok = _fail("no %s inside the surface, so the column's content has no inset"
				% screen.COLUMN_PAD)
	elif pad.position != Vector2.ZERO or pad.size != want_size:
		ok = _fail("the pad is not the surface's whole rect: %s %s, wanted (0, 0) %s"
				% [pad.position, pad.size, want_size])
	screen.queue_free()
	return ok


## THE COLUMN'S GUTTER IS THE THEME'S OWN NUMBER, NOT ONE TYPED IN `main.gd` (ASSA-142 box 1).
##
## **MAREN'S PROPERTY, VERBATIM: "the number comes from the container, not from this item."** She
## expected roughly 24 and said in advance that if it turned out to be another number in the
## container's own terms, that was the right answer. It is `content_margin_left` on the panel
## stylebox `build_theme.gd::_box` writes -- the same inset `_running_box` and `_halt_box` already
## get, because a `PanelContainer` IS a Container and applies it. The HUD column is the one panel in
## the window that does not, since a plain `Panel` draws a stylebox and lays out nothing.
##
## So the padding was never missing from the design. It was declared and unapplied, and this test is
## about the LINK rather than about the value: it reads the stylebox at run time and compares. Typing
## `10` here would pass on a theme that had moved to 14 and the column would be wrong and green.
func test_the_columns_gutter_is_the_panel_styleboxs_own_margin() -> bool:
	var screen := _screen()
	var ok := true
	var surface := screen.get_node_or_null(NodePath(screen.COLUMN_SURFACE)) as Panel
	var pad := null if surface == null else surface.get_node_or_null(NodePath(screen.COLUMN_PAD))
	var margins := pad as MarginContainer
	if margins == null:
		screen.queue_free()
		return _fail("no %s/%s, so the column has no inset to check its source"
				% [screen.COLUMN_SURFACE, screen.COLUMN_PAD])
	var box := surface.get_theme_stylebox(&"panel")
	if box == null:
		ok = _fail("the column's surface resolves no panel stylebox, so there is no number to take")
	else:
		# NOT ZERO, FIRST. A theme that declared no content margin would make every comparison below
		# trivially true and the column would have no gutter at all -- the shipped defect, passing.
		if box.content_margin_left <= 0.0:
			ok = _fail(("the panel stylebox declares no left content margin, so this test would "
					+ "pass over a column with no gutter at all"))
		for side in [["margin_left", box.content_margin_left],
				["margin_right", box.content_margin_right]]:
			var applied := margins.get_theme_constant(StringName(side[0]))
			if ok and applied != int(side[1]):
				ok = _fail(("the column's %s is %d and the panel stylebox declares %d: the gutter "
						+ "stopped coming from the theme") % [side[0], applied, int(side[1])])
	screen.queue_free()
	return ok


## A CONTROL THAT CANNOT DO ANYTHING IS NOT ON THE SCREEN (ASSA-142 box 3, ASSA-161, Maren).
##
## `whole world (V)` was the only button inside the map's rectangle before a join, offering a view of
## a world that does not exist, while the five sections beside it each say "no world yet" in words.
##
## **ASSA-161 ASKS FOR THIS AS A TEST AND NOT A SCREENSHOT DIFF**, which is the right ask: a shot
## proves the join screen, and only a test can show the button comes BACK. Both directions are here,
## driven by `_sim.running()` because that is what the code keys on.
func test_the_view_toggle_is_absent_until_there_is_a_world() -> bool:
	var screen := _screen()
	var ok := true
	if screen._view_toggle.visible:
		ok = _fail("`whole world (V)` is on the join screen, offering a view of no world")
	# A REFRESH WITH NO WORLD MUST NOT BRING IT BACK, which is the case the early return in
	# `_refresh` makes easy to get wrong: everything below that return runs only with a world, so a
	# line placed one below it would leave the button hidden for ever.
	if ok:
		screen._refresh()
		if screen._view_toggle.visible:
			ok = _fail("the toggle reappeared on a refresh with no world running")
	# AND THE SHORTCUT IS AS DEAD AS THE BUTTON. Hiding the control and leaving V live would keep
	# the promise this item removes: a player who read the key off the button could still toggle to
	# a view of nothing, with the control that would explain it now gone.
	if ok:
		var before: bool = screen._close_up
		var press := InputEventKey.new()
		press.keycode = KEY_V
		press.pressed = true
		screen._unhandled_key_input(press)
		if screen._close_up != before:
			ok = _fail("V toggled the view with no world, so the hidden button's key is still live")
	screen.queue_free()
	if not ok:
		return ok

	# AND IT COMES BACK IN A WORLD (ASSA-161 box 2: "the fix is not 'remove the button'"). Without
	# this half, `_view_toggle.visible = false` and a deleted button are the same green.
	var joined := _joined_screen()
	if not joined._sim.running():
		joined.queue_free()
		return _fail("the fixture world did not start, so the half that matters was never asked")
	joined._refresh()
	if not joined._view_toggle.visible:
		ok = _fail("`whole world (V)` never came back once a world existed")
	# AND THE V KEY AGREES WITH THE BUTTON, in the world where it is supposed to work.
	elif true:
		var was: bool = joined._close_up
		var event := InputEventKey.new()
		event.keycode = KEY_V
		event.pressed = true
		joined._unhandled_key_input(event)
		if joined._close_up == was:
			ok = _fail("V did nothing in a world, so hiding the button took its shortcut with it")
	joined.queue_free()
	return ok


## **THE BAND LEAVES THE SCREEN IN A WORLD AND IS BACK IN EVERY OTHER STAGE** (ASSA-175).
##
## `host` and `name` had exactly one reader each and `_join_address` returns before either unless the
## stage is IDLE or DEAD, so all three controls sat there for the whole session reading as available.
##
## **DRIVEN THROUGH `_process`, NOT THROUGH `_refresh_join_band`.** Calling the function the fix added
## would pass with nothing in production ever calling it -- a lever that cannot fail -- and the call
## sits above an early return in `_process` that skips most frames of a session, which is exactly the
## placement a green test should have to earn.
##
## **THE DEAD HALF IS THE ONE WORTH HAVING** (Maren's second ruling). `_join_address` permits a join
## attempt at stage DEAD, so this band is the client's only reconnect affordance; a predicate like
## `_sim.running()`, or a latch on the welcome, would hide it at the moment a dropped player reaches
## for it and would pass a test that only checked the join screen and the world. DEAD is reached here
## by feeding a real `Refused` frame through the reader, not by assigning the field: `_handle` is what
## sets DEAD in production.
##
## THE TWO LABELS ARE FOUND BY SCANNING THE SCREEN, not by reading them out of the band the fix
## built. A scan of the band could only ever find what the fix put there; this fails for a third
## label added elsewhere, and the IDLE count below is what stops "found nothing" reading as "found
## nothing on screen".
func test_the_join_band_is_on_screen_in_every_stage_except_joined() -> bool:
	var ok := true
	var screen := _screen()
	screen._process(0.016)
	for named in [["Play solo", screen._solo_button], ["the host box", screen._host],
			["the name box", screen._name], ["Join", screen._join_button]]:
		if not _on_screen(named[1]):
			ok = _fail("%s is not on the join screen at all" % named[0])
	var idle_labels := _labels_naming_the_band(screen)
	if idle_labels.size() < 2:
		ok = _fail("found %d of the `host`/`name` labels on the join screen, so the scan below"
				% idle_labels.size() + " could not fail")
	for label in idle_labels:
		if not _on_screen(label):
			ok = _fail("the `%s` label is hidden before a join" % (label as Label).text)
	screen.queue_free()
	if not ok:
		return ok

	# IN A WORLD: the three dead controls and both their labels are gone, and `Join` has stayed.
	var joined := _joined_screen()
	if joined._client.stage != AssayNetClient.Stage.JOINED:
		joined.queue_free()
		return _fail("the fixture never reached JOINED, so this test asked nothing")
	joined._process(0.016)
	for named in [["Play solo", joined._solo_button], ["the host box", joined._host],
			["the name box", joined._name]]:
		if _on_screen(named[1]):
			ok = _fail("%s is still on screen in a world, where nothing reads it" % named[0])
	for label in _labels_naming_the_band(joined):
		if _on_screen(label):
			ok = _fail("the `%s` label is still standing over a hidden field"
					% (label as Label).text)
	if not _on_screen(joined._join_button):
		ok = _fail("hiding the band took `Join` with it, which is the one control that can still act")
	if not ok:
		joined.queue_free()
		return ok

	# AND A DROPPED PLAYER GETS IT BACK.
	joined._client.feed_offline('{"Refused":{"reason":"the relay went away"}}')
	if joined._client.stage != AssayNetClient.Stage.DEAD:
		joined.queue_free()
		return _fail("the Refused frame did not kill the link, so the DEAD half was never asked")
	joined._process(0.016)
	for named in [["Play solo", joined._solo_button], ["the host box", joined._host],
			["the name box", joined._name], ["Join", joined._join_button]]:
		if not _on_screen(named[1]):
			ok = _fail("%s is gone after the link died, and that is the only way back in" % named[0])
	joined.queue_free()
	return ok


## EVERY CONTROL IN A ROW, FLATTENED INTO THE ORDER IT IS DRAWN IN. Containers are the nesting and
## not the reading, so they are walked through rather than listed; a `BoxContainer` lays its children
## out in tree order, which is what makes depth-first order the left-to-right one.
func _row_reading(row: Node) -> Array:
	var out := []
	for child in row.get_children():
		if child is Container:
			out.append_array(_row_reading(child))
		elif child is Control:
			out.append(child)
	return out


## The `host` and `name` labels, wherever on the screen they are. Text and not identity, because the
## fix holds neither as a field and a test that reached into the band would be reading the fix back
## to itself.
func _labels_naming_the_band(screen: Node) -> Array:
	var out := []
	for node in screen.find_children("*", "Label", true, false):
		if (node as Label).text == "host" or (node as Label).text == "name":
			out.append(node)
	return out


## **A REFUSED JOIN NAMES THE STAGE THE PLAYER IS ACTUALLY IN** (ASSA-176).
##
## Both sites gated on "not IDLE and not DEAD" and said *already joining* for all four remaining
## stages, so a player ten minutes into a world was told they were joining. After ASSA-175 that is
## the sentence the only remaining control in the row says.
##
## BOTH STAGES ARE REACHED THE REAL WAY. CONNECTING comes from a real `_on_join` at a port nothing
## listens on -- `connect_to_host` returns OK there, so the stage is CONNECTING with no answer yet --
## and JOINED from the offline welcome fixture. Neither is an assignment to `stage`, so the test
## cannot pass by agreeing with a predicate I typed twice.
##
## IT ASSERTS BOTH DIRECTIONS, which is what makes a SWAP of the two clauses fail rather than half of
## it: the joined sentence must not say "joining" and the connecting one must.
func test_a_refused_join_names_the_stage_the_player_is_in() -> bool:
	var screen := _screen()
	# Nothing listens on port 1; the point is the stage, not the answer.
	screen._host.text = "127.0.0.1:1"
	screen._on_join()
	if screen._client.stage != AssayNetClient.Stage.CONNECTING:
		screen.queue_free()
		return _fail("the fixture did not reach CONNECTING, so the true sentence was never asked")
	var ok := true
	screen._on_join()
	if not screen._status.text.begins_with("already joining"):
		ok = _fail("a player mid-handshake is not told they are joining: %s" % screen._status.text)
	screen._on_play_solo()
	if not screen._status.text.begins_with("already joining"):
		ok = _fail("the solo refusal mid-handshake reads `%s`" % screen._status.text)
	screen.queue_free()
	if not ok:
		return ok

	var joined := _joined_screen()
	if joined._client.stage != AssayNetClient.Stage.JOINED:
		joined.queue_free()
		return _fail("the fixture never reached JOINED, so this test asked nothing")
	joined._on_join()
	var said: String = joined._status.text
	if said.contains("joining"):
		ok = _fail("a player who is IN a world is told they are joining: %s" % said)
	elif not said.begins_with("already in a world"):
		ok = _fail("the joined refusal does not name the state the player is in: %s" % said)
	# THE WAY OUT SURVIVED. A refusal that names the state and drops the remedy is this item's defect
	# with the halves swapped: no refusal is silent, and none of them is only half a sentence.
	elif not said.contains("restart the client to change host"):
		ok = _fail("the joined refusal lost its remedy: %s" % said)
	if ok:
		joined._on_play_solo()
		var solo_said: String = joined._status.text
		if solo_said.contains("joining"):
			ok = _fail("the solo refusal in a world still says joining: %s" % solo_said)
		elif not solo_said.contains("start a world of your own"):
			ok = _fail("the solo refusal lost its own remedy: %s" % solo_said)
	joined.queue_free()
	return ok


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
	# **FOURTEEN GO IN AND THE ROOM DECIDES HOW MANY COME OUT (ASSA-156).** The panel is capped to
	# the room above the player's own body, so this is no longer `lines.size()`; what it still is, is
	# a CONTIGUOUS block starting at the newest, and the two `contains` below are what say so. The
	# bug they catch is real and I shipped it into this branch for an hour: indexing the block off
	# the drawn count instead of off `_events.size()` walks AWAY from the newest line and draws the
	# eighth-oldest at the top, in correct newest-first order, looking entirely plausible.
	var holds := mini(lines.size(), screen._log_lines_that_fit())
	if drawn.size() != holds:
		ok = _fail("%d lines went in, the room holds %d and %d Labels came out"
				% [lines.size(), holds, drawn.size()])
		screen.queue_free()
		return ok
	# THE NEWEST EVENT IS AT THE TOP.
	if not (drawn[0] as Label).text.contains("event number 13"):
		ok = _fail(("the first line in the log is '%s'; the newest event is the one a player who "
				+ "can see two rows of this section must get") % (drawn[0] as Label).text)
	elif not (drawn[drawn.size() - 1] as Label).text.contains(
			"event number %d" % (lines.size() - drawn.size())):
		ok = _fail(("the last line is '%s', which is not the oldest of the %d the room holds: the "
				+ "lines on screen are not one run ending at the newest")
				% [(drawn[drawn.size() - 1] as Label).text, drawn.size()])
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
	elif said != AssayHud.quiet_log_line(false):
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
	# THE ROOM DECIDES THE COUNT SINCE ASSA-156, and with a newest line this long it decides one
	# fewer: the newest keeps its wrapping, so it is two rows and the panel pays for both.
	var holds := mini(lines.size(), screen._log_lines_that_fit())
	if drawn.size() != holds:
		ok = _fail("%d lines went in, the room holds %d and %d Labels came out"
				% [lines.size(), holds, drawn.size()])
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


## **AND THE CAMERA KEEPS YOU BELOW IT IN THE ROWS WHERE THE PANEL IS (ASSA-184).**
##
## `test_scene_view.gd::test_the_north_edge_rows_draw_a_whole_body_below_the_panel` owns the
## geometry, on the real `placements` at four positions in every one of the north rows. **This test
## owns the WIRING, which is the half that cannot be checked there**: `AssayScene.north_headroom`
## existing and being right buys nothing until `main.gd` hands it to `camera_origin`, and "I added
## the function and forgot to pass it" is a defect that leaves every scene-view assertion green.
##
## So it drives the real screen at the real 912x600 rect, puts the body in row 0, and reads the
## camera out of the view the screen actually built.
##
## **WHAT IT CANNOT SEE, MEASURED NOT GUESSED.** Its expectation is `-north_headroom(...)`, so it
## agrees with that function about the VALUE and can only catch a camera that ignores it. Mutating
## the headroom's own arithmetic (dropping the sprite's overhang, 252 -> 220) leaves this test green
## and reddens `test_the_north_edge_rows_draw_a_whole_body_below_the_panel`, which measures the body
## instead. Mutating `main.gd` to pass 0.0 reddens THIS one and only this one. Two tests, two
## different holes, and neither covers the other. It also pins Maren's rule on ASSA-156, now
## hers: **the panel's room must not move as you walk.** A camera bound that fixed this by shortening
## the log would pass every assertion above and fail that one.
func test_the_camera_keeps_you_below_the_panel_in_the_north_rows() -> bool:
	var screen := _joined_screen()
	var map := AssayHud.world_rect()
	var room := AssayScene.north_headroom(AssaySprites.manifest(), map.size)
	var id: int = screen._client.player_id
	if room <= 0.0 or id < 0 or screen._sim.players().is_empty():
		screen.queue_free()
		return _fail(("headroom %f, player id %d, %d players: the fixture has nothing to measure "
				+ "and every assertion below would pass on an empty world")
				% [room, id, screen._sim.players().size()])
	if absf(screen._north_room - room) > 0.01:
		screen.queue_free()
		return _fail(("the screen built its camera bound as %f and the scene says %f: main.gd is "
				+ "not reading the same manifest or the same rect the log panel was sized from")
				% [screen._north_room, room])
	var ok := true
	var rooms := {}
	for row: int in [0, 3, 7, 40]:
		screen._seen = {id: Vector2i(48, row)}
		screen._was = screen._seen.duplicate()
		screen._refresh_world()
		var view: Dictionary = screen._world.view
		var players: Array = view.get("players", [])
		if players.is_empty() or absf(float((players[0] as Dictionary)["at"].y) - float(row)) > 0.01:
			ok = _fail(("the fixture did not put a body in row %d (view says %s), so this test is "
					+ "measuring a camera aimed somewhere else")
					% [row, players if players.is_empty() else players[0]["at"]])
			break
		var origin: Vector2 = view["origin"]
		var want := -room if row <= 1 else (float(row) + 0.5) * AssayScene.TILE_PX - map.size.y * 0.5
		if absf(origin.y - want) > 0.01:
			ok = _fail(("standing in row %d the screen's camera is at y %f and ASSA-184 wants %f: "
					+ "at the old bound of 0 the body is drawn from y %f, behind a panel owning the "
					+ "top %f of the map") % [row, origin.y, want,
					float(row) * AssayScene.TILE_PX - AssayScene.TILE_PX,
					AssayScene.player_ceiling(AssaySprites.manifest(), map.size)])
			break
		# THE PANEL, MEASURED A SECOND WAY AT EVERY ROW. Not `_log_room` against itself -- that is a
		# constant compared to a constant, which is the self-agreeing test I have shipped twice. The
		# quantity here is how many lines the panel actually BUILT, which is downstream of the room
		# through a division I am not allowed to ask.
		var lines := PackedStringArray()
		for i in 14:
			lines.append("%d · you mined 20 of Tonore ore (A) at (74, 36)" % (400 + i))
		screen._events = lines
		screen._rebuild_log()
		rooms[row] = [screen._log_room,
				screen._log.find_children("*", "Label", true, false).size()]
	if ok:
		var first: Array = rooms.values()[0]
		for row: int in rooms:
			if rooms[row] != first:
				ok = _fail(("the log changed shape as the body walked: row %d gave %s and the first "
						+ "row gave %s. Maren's rule on ASSA-156 is that the panel must not move or "
						+ "resize under your feet, so the CAMERA is the only thing allowed to "
						+ "answer this") % [row, rooms[row], first])
				break
		# WHAT THIS CANNOT SEE, SAID OUT LOUD: both numbers are position-independent BY SIGNATURE --
		# `player_ceiling` and `north_headroom` take a manifest and a rect and no player at all -- so
		# this loop cannot fail today and is here to redden the day somebody passes the camera into
		# either of them. That is a regression guard, not evidence, and box 3 is ticked on the
		# signature plus the window shot, not on this.
	screen.queue_free()
	return ok


## **THE PANEL STOPS ABOVE THE BODY THE CAMERA CENTRES (ASSA-156, box 6).**
##
## Maren's measurement: seed 777042 with the log open had ZERO player pixels anywhere in the map
## rect, against 199 with it closed, and the panel was INSIDE the map the whole time -- the bound it
## already had was the wrong bound. An unclamped camera puts your body in the map's centre and the
## panel owns the map's top, so the panel's height is the only free variable.
##
## **WHAT THIS TEST CANNOT SEE, SAID OUT LOUD, because a green tick here is not the fix.** The suite
## runs inside `SceneTree._initialize`: nothing is laid out, and `Control.update_minimum_size` is
## deferred, so `_log_box` honestly reports 12px for a 342px panel (measured in
## `tools/log_room_probe.gd`). There is no real rectangle to ask. So this sums the height the engine
## WILL give the panel out of the nodes it will lay out -- the stylebox's margins, the heading at its
## own type's font size, the separations, and every Label actually added -- and compares that to the
## ceiling. It is a different computation from the division in `AssayHud.log_lines_that_fit`, which
## is what lets it catch an off-by-one there; it is NOT independent of the terms, so a wrong chrome
## term would pass here. The laid-out rect is checked in `tools/window_shot.gd::_reveal_report`, on
## a real window, which is the only place it can be.
func test_the_log_panel_stops_above_the_body_the_camera_centres() -> bool:
	var screen := _screen()
	var ok := true
	var map := AssayHud.world_rect()
	var ceiling := AssayScene.player_ceiling(AssaySprites.manifest(), map.size)
	if ceiling <= 0.0:
		screen.queue_free()
		return _fail(("the scene cannot say where a body is drawn (ceiling %.1f), so the log's "
				+ "panel has no bound at all and ASSA-156 is unfixed rather than fixed") % ceiling)
	# TWO FIXTURES, AND THE SECOND IS THE ONE THAT PAYS FOR THIS TEST. A newest line long enough to
	# wrap is measured through the TextServer here, NOT off the Label's own minimum height, because
	# that minimum says 18px for a 36px line until a layout has happened -- so a panel sized as if
	# every line were one row is a panel a row taller than it measured, over the head of the player
	# this item is about. Asking `_log_lines_that_fit` for the expected count instead would be this
	# test agreeing with the arithmetic it is checking, which is how I shipped exactly that hole
	# twice (ASSA-135, and the first version of this file an hour ago).
	var long := ("your design broke: mass 1078 of 705 budget · holds 210 · speed 78 (bare hands 25)"
			+ " · frame(Tonore A 385) + head(Tonore A 120) + hopper(Souktulore B 140) x4")
	for newest in ["you mined 20 of Tonore ore (A) at (74, 36)", long]:
		var lines := PackedStringArray()
		for i in 13:
			lines.append("%d · you mined 20 of Tonore ore (A) at (74, 36)" % (400 + i))
		lines.append("413 · %s" % newest)
		screen._events = lines
		screen._rebuild_log()
		var drawn: Array = screen._log.find_children("*", "Label", true, false)
		var style: StyleBox = screen._log_box.get_theme_stylebox(&"panel")
		var inside: Control = screen._log_box.get_child(0)
		var head: Font = screen._log_heading.get_theme_font(&"font", &"Heading")
		var body: Font = screen._log.get_theme_font(&"font", &"Label")
		var body_size: int = screen._log.get_theme_font_size(&"font_size", &"Label")
		var tall: float = style.get_margin(SIDE_TOP) + style.get_margin(SIDE_BOTTOM)
		tall += head.get_height(screen._log_heading.get_theme_font_size(&"font_size", &"Heading"))
		tall += float(inside.get_theme_constant(&"separation"))
		var sep := float(screen._log.get_theme_constant(&"separation"))
		for i in drawn.size():
			if i == 0:
				# THE WIDTH THE PANEL WILL GIVE IT: the map, less the stylebox's own left and right.
				tall += body.get_multiline_string_size((drawn[0] as Label).text,
						HORIZONTAL_ALIGNMENT_LEFT, map.size.x - style.get_margin(SIDE_LEFT)
						- style.get_margin(SIDE_RIGHT), body_size).y
			else:
				tall += (drawn[i] as Control).get_combined_minimum_size().y + sep
		if drawn.size() >= lines.size():
			ok = _fail(("fourteen events drew %d lines in a panel with %.0fpx of room above the "
					+ "player: the cap is not in force, so the panel still owns the map's centre")
					% [drawn.size(), ceiling])
		elif tall > ceiling:
			ok = _fail(("with a %d-character newest line the log's panel will be %.0fpx tall and "
					+ "your own body is drawn from y %.0f of the map: %.0fpx of it is over your "
					+ "head, which is what Maren's 777042 shot measured as zero player pixels")
					% [newest.length(), tall, ceiling, tall - ceiling])
		if not ok:
			break
	screen.queue_free()
	return ok
