extends RefCounted

#: THE SUITE'S ONE THEME-POKE SITE (ASSA-312). A project-themed control resolves the PLAIN
#: type's entries until it gets `NOTIFICATION_THEME_CHANGED`, which frames do not deliver, so
#: every headless theme read in here goes through this.
const Poke := preload("res://tests/theme_poke.gd")
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


## A relay the screen is ALREADY playing through: mid-session, address long since known. Counts both
## calls separately, because ASSA-219 is exactly the difference between them -- a `pump()` that must
## happen on every one of these frames and a `poll()` that must not happen on any of them.
class _RelayMidSession extends AssaySoloRelay:
	var polls := 0
	var pumps := 0

	func poll() -> bool:
		polls += 1
		return address != ""

	func pump() -> void:
		pumps += 1


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
	# COUNTED BEFORE THE SECOND `_ready`, which is the whole of the comparison below.
	var before: int = screen.find_children("*", "ScrollContainer", true, false).size()
	screen._ready()
	var ok := true
	if screen._carrying.get_parent() != column:
		ok = _fail("a second _ready reparented the HUD into a new column")
	# **THE CHECK IS THAT THE COUNT DID NOT CHANGE, NOT THAT IT IS ONE** (ASSA-328).
	#
	# **IT ASSERTED `== 1` AND THAT NUMBER WAS NEVER THE PROPERTY.** The defect is a second `_ready`
	# building a second copy of a panel; `1` was true only because the HUD column was the sole scroll
	# box in the client, so this counted "every ScrollContainer anywhere" and called the answer "HUD
	# columns". The build screen has four of its own (ASSA-328) and the test went red for a screen that
	# is built exactly once -- a check satisfied by something other than the thing it is about.
	#
	# **AND COUNTING BEFORE AND AFTER IS STRICTLY STRONGER than counting after**: it now catches a
	# SECOND copy of any panel in this client rather than of the one that happened to scroll, and it
	# cannot be made to pass by a surface arriving or leaving. The non-zero clause is what stops a
	# client that builds nothing at all from passing it twice over.
	var after: int = screen.find_children("*", "ScrollContainer", true, false).size()
	if ok and before == 0:
		ok = _fail("the screen has no scroll boxes at all, so a duplicate could not be seen")
	elif ok and after != before:
		ok = _fail("a second _ready took the screen from %d scroll boxes to %d" % [before, after])
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
	var colour: Color = _drawn_color(screen._status)
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
	var idle: Color = _drawn_color(screen._status)
	var instruction: String = screen._status.text
	screen._client.link_failed.emit("could not reach 127.0.0.1:1")
	var failed: Color = _drawn_color(screen._status)
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
	# **THE READING IS OF THE FRONT DOOR NOW, AND IT IS STILL A READING ORDER** (ASSA-231). Before a
	# world the composition is a `VBoxContainer` over the map and the axis is top-to-bottom; the
	# depth-first flatten below is the order a stranger's eye takes either way, because a
	# `BoxContainer` of either kind lays its children out in tree order. Asked of the door the
	# controls are actually in rather than of `_join_band`'s parent, which is the empty in-world row.
	# CONTROLS, NOT TEXT: the door's first two lines are the game's name and the sentence that names
	# both doors, which is composition and not something a stranger can press. What the ruling is
	# about is the first thing they CAN press or type into.
	var reading := []
	for control in _row_reading(screen._front_door):
		if control is Button or control is LineEdit:
			reading.append(control)
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


## A desync is a failure and not narration -- the session really did end.
##
## **AND IT CARRIES ITS EVIDENCE NOW** (ASSA-190, protocol 10): the tick and BOTH hashes. The
## host's hash did not exist on this client until the message grew it, so a desync could only ever
## say "we diverged", which is indistinguishable from a bad connection. A determinism bug that reads
## as a network problem is the one class of bug this game cannot afford to mistake, so the two
## numbers are asserted on the screen rather than trusted to the signal.
##
## **IT MUST NOT READ AS A DROPPED CABLE EITHER.** `_on_link_failed`'s sentences are about a socket;
## this one is about two worlds disagreeing, and the suite is where that distinction is kept.
func test_a_desync_is_reported_as_a_failure_with_both_hashes() -> bool:
	var screen := _screen()
	screen._client.desynced.emit(140, "ourhash", "hosthash")
	var said: String = screen._status.text
	var colour: Color = _drawn_color(screen._status)
	screen.queue_free()
	if not said.contains("140"):
		return _fail("a desync at tick 140 was reported as %s" % said)
	if not said.contains("ourhash") or not said.contains("hosthash"):
		return _fail("a desync must name both hashes, ours and the host's: %s" % said)
	if said.to_lower().contains("connection") or said.to_lower().contains("closed the"):
		return _fail("a desync must not read as a connection failure: %s" % said)
	if colour != AssayHud.status_color(AssayHud.Say.FAILED):
		return _fail("a desync is coloured %s, not the failed colour" % colour)
	return true


## **THE DEFECT ASSA-190 IS ABOUT: A DESYNC USED TO LEAVE THE ONE STATE THIS WINDOW CANNOT LEAVE.**
##
## `_join_address` returns on its first line at JOINED, so a peer told its world had drifted sat in
## that world with the Join button refusing and no exit but restarting the application. The cure is a
## fresh `Welcome`, which a rejoin already delivers into the same slot (ASSA-177, measured) -- so the
## client hangs up on a desync and DEAD becomes honest, because we ended the link ourselves.
##
## **ASSERTED ON THE STAGE AND ON THE BAND, not on the socket.** The stage is what `_join_address`
## reads and the band is what a player sees, and ASSA-231 is the reminder that those two can
## disagree. The count is here too: a client that quietly re-welcomed itself on every desync would
## hide a determinism bug, so the number has to exist for anything to report it.
func test_a_desync_leaves_a_stage_the_join_button_will_serve() -> bool:
	var joined := _joined_screen()
	var before: int = joined._client.desyncs_seen
	joined._client.feed_offline(
			'{"Desync":{"tick":88,"reported":"ourhash","expected":"hosthash"}}')
	var ok := true
	if joined._client.stage != AssayNetClient.Stage.DEAD:
		ok = _fail(("a desync left the stage at %d: `_join_address` returns on its first line "
				+ "unless the stage is IDLE or DEAD, so that is a world with no way out of it")
				% joined._client.stage)
	elif joined._client.desyncs_seen != before + 1:
		ok = _fail("the desync was not counted (%d), so nothing can report a repeat"
				% joined._client.desyncs_seen)
	else:
		# THE STAGE IS WHAT `_join_address` READS AND THE BAND IS WHAT A PLAYER SEES, and ASSA-231 is
		# the reminder that those two can disagree. Both, or this proves half of it.
		joined._process(0.016)
		if not _on_screen(joined._join_button):
			ok = _fail("the Join button is not on screen after a desync, so the way back exists "
					+ "only in the stage machine")
	joined.queue_free()
	return ok


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
	# No `tick N ·` prefix since ASSA-222 — `_remember_events` no longer writes one, and a fixture
	# that still carried it would be planting a line this client cannot produce.
	var planted := PackedStringArray(["you mined 2 ore", "you started walking"])
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
##
## **AND THE CRAFTING MENU, WHICH WAS NOT IN THIS LIST UNTIL ASSA-116 BOX 3 MADE ME READ IT.** The
## box is *"pack AND CRAFTING rows ... no clipping in the 320px panel"*, and the four sections swept
## here were pack, bench, species and `do`. A make row is the newest surface to get the icon column
## (ASSA-240) and the one whose own comment names a budget — `main.gd` measures its sentence "against
## a budget of about 313" with "the row's floor is the icon box's 48 px" — so it is the shape where
## 48 px beside a flowing body is most likely to push the total past the box. That is ASSA-98's
## defect exactly, and the one section it was never asked about.
##
## `_rebuild_make` is driven with the real builder and the sim's own offer shape, one row with art and
## one without, because the icon column and the reserved gap are different children and both have to
## fit.
func test_no_row_asks_for_more_width_than_the_panel_that_clips_it() -> bool:
	var screen := _screen()
	var ok := true
	# The richest pack the demo loop actually produces, which is the one with seven verbs on a row.
	screen._rebuild_pack([
		{"kind": "refined", "species": 4, "grade": "B", "count": 6, "name": "Minyte refined (B)"},
		{"kind": "ore", "species": 4, "grade": "B", "count": 22, "name": "Minyte ore (B)"},
		{"kind": "head", "species": 4, "grade": "B", "count": 2, "name": "Minyte head (B)"},
	])
	# A LONG SENTENCE ON PURPOSE: the widest make line the sim can be asked to draw, shaped like
	# `make_offers`' own (a named species, a grade, a count and what one batch spends). A short
	# `line` would fit whatever the icon column did and the arm would prove nothing.
	screen._rebuild_make([
		{"makes": {"kind": "ore", "species": 4, "grade": "B", "count": 1, "name": "Minyte ore (B)"},
			"line": "sort 3 Minyte ore (B) into 1 Minyte ore (A) · you have 22 · spends 3",
			"verb": "craft", "tag": 0},
		{"makes": {"kind": "gear", "species": 4, "grade": "B", "count": 1, "name": "Minyte gear (B)"},
			"line": "make 1 Minyte gear (B) from 2 Minyte refined (B) · you have 6 · spends 2",
			"verb": "make", "tag": 0},
	])
	var checked := 0
	for section in [screen._carrying, screen._bench, screen._species, screen._actions, screen._make]:
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


## **NO VERB THAT ACTS ON A TILE IS DISABLED** (ASSA-37's rule, held for ASSA-96 box 3).
##
## ASSA-96 asked whether Fuel, Smelt and Place read clearly when the tile they land on is named two
## sections up the column. The Game Director closed it as no change needed on 2026-10-08 — the
## close-up now marks the acted-on tile — and its last box is this standing property, which nothing
## held.
##
## **TWO OF ITS THREE VERBS NO LONGER EXIST ON A PACK ROW** (ASSA-331, Maren's ruling): `Fuel` and
## `Smelt` are deleted, because her ASSA-316 ruling 8 made the cursor they aimed at unreachable on a
## machine. `Place` is the only verb left on the pack that acts on a tile at a distance, so it is the
## only one this can be built on -- and the premise below is what makes that visible rather than quietly
## reducing the test to nothing.
##
## **IT IS SCOPED TO THE PACK ON PURPOSE AND THAT IS NOT A LOOPHOLE.** There are exactly two
## `.disabled` writes in the whole client: a crafting row you cannot afford — Maren's own LATER
## ASSA-247 ruling, held by `test_buttons.gd::test_a_row_you_cannot_afford_is_not_pressable_...` —
## and a placeholder tab in `tab_strip.gd`. So the blanket form of "nothing is disabled" is no longer
## the design, and a test asserting it would redden her ruling. What ASSA-37 is about is the verbs
## that act at a DISTANCE: pressing one submits and lets the sim answer, instead of the client
## deciding in advance that a press it never made would be refused.
##
## THE PREMISE IS ASSERTED: one of these verbs has to be on screen, or a pack that offered none would
## pass this silently — the shape that made `test_every_make_row_starts_its_sentence_at_the_same_x`
## read as coverage until its author checked.
func test_no_verb_that_acts_on_a_tile_is_disabled() -> bool:
	var screen := _screen()
	# THE ORE ROW IS STILL HERE THOUGH IT CARRIES NO VERB NOW: the pack is what you HAVE, so a row with
	# nothing to press is the shape to walk over, and walking over it is part of what is checked.
	screen._rebuild_pack([
		{"kind": "ore", "species": 4, "grade": "B", "count": 22, "name": "Minyte ore (B)"},
		{"kind": "smelter", "species": 4, "grade": "B", "count": 1, "name": "Minyte smelter (B)"},
	])
	var ok := true
	var acting := 0
	var seen := PackedStringArray()
	for found in screen._carrying.find_children("*", "Button", true, false):
		var button := found as Button
		seen.append(button.text)
		if button.text == "Place":
			acting += 1
		if button.disabled:
			ok = _fail(("the pack offers `%s` as a DISABLED button, so the client decided the sim "
					+ "would refuse a press nobody made (ASSA-37)") % button.text)
	if ok and acting == 0:
		ok = _fail(("no Place button is on this pack, so nothing here acts on a tile at a distance "
				+ "and this proves nothing. What the rows offered: %s") % ", ".join(seen))
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
## it is checked by the two tests below instead.
##
## **AND SINCE ASSA-247 THE ORDER IS NOT A COLUMN OF SIX HEADINGS AT ALL**, so this test is rewritten
## rather than retired. The board's shape (Rainy, via Wren's ruling) is ONE tabbed panel: `do` always
## on, then `make` / `inventory` / `bench` / `mineralogy` as tabs, one visible at a time. Maren's ASSA-133
## ruling 2 -- a section may not sit above the section it is derived from -- is not weakened by that;
## it is retired, because `make` and the pack are no longer in one box where either can push the
## other. **What this test holds now is the thing a later edit could quietly undo: that the pack and
## the make list are NOT siblings in one scrolling column again.**
func test_the_panel_is_do_always_on_then_four_tabs() -> bool:
	var screen := _screen()
	var ok := true
	# **`mineralogy`, NOT `rocks`** (Maren, ASSA-241): the fourth tab is this column's `rocks` section
	# wearing Rainy's word for it, not a fifth tab beside it. The variable it renders is still
	# `_species`, which is why only the NAME moved here.
	var want := ["make", "inventory", "bench", "mineralogy"]
	var seen := Array(screen._tabs.tab_names())
	if seen != want:
		ok = _fail(("the tab strip reads %s; the board's structure and Wren's ruling are %s")
				% [seen, want])
	elif screen._actions.get_parent() != screen._tabs.get_parent():
		ok = _fail("`do` is not a sibling of the tab strip, so what you can do HERE is behind a tab: "
				+ "Wren ruled it the one always-on section")
	elif _scroll_enclosing(screen._actions) != null:
		ok = _fail("`do` is inside the scroll box, so the one always-on section can be scrolled away")
	elif screen._carrying.get_parent() == screen._make.get_parent():
		ok = _fail("the pack and the make list are siblings in one box again, which is ASSA-133 "
				+ "ruling 2: a list derived from your pack grows faster than it and pushes it off")
	elif screen._tabs.get_parent().get_children().has(screen._log):
		ok = _fail("the event log is back in the HUD column, which is ASSA-147: it is unbounded and "
				+ "every other section is not, so in one scroll box it wins against the controls")
	screen.queue_free()
	return ok


## **EVERY TAB'S NAME IS ON SCREEN EVEN WHEN ITS BODY IS NOT** (ASSA-247), which is the whole reason
## the board's structure is a strip and not a set of keyboard summons -- Maren's reason, kept where
## the mechanism is: a tab strip is a VISIBLE affordance and a key is an invisible one, and a
## five-minute player cannot summon what they do not know exists.
##
## So: exactly one body visible, and all four names present and pressable.
func test_one_system_is_visible_and_all_four_names_are() -> bool:
	var screen := _screen()
	var ok := true
	var shown := PackedStringArray()
	for named in screen._tabs.tab_names():
		if (screen._tabs.body_of(named) as Control).visible:
			shown.append(named)
	var names := PackedStringArray()
	for child in screen._tabs.names_box().get_children():
		if child is Button:
			names.append((child as Button).text)
	if shown.size() != 1:
		ok = _fail("%d tab bodies are visible at once; the ruling is one system at a time" % shown.size())
	elif Array(names) != Array(screen._tabs.tab_names()):
		ok = _fail("the strip draws %s for tabs %s: a tab a player cannot press is not a tab"
				% [names, screen._tabs.tab_names()])
	elif _scroll_enclosing(screen._tabs.names_box()) != null:
		ok = _fail("the tab names are inside the scroll box, so scrolling a long list can carry away "
				+ "the way back to the other systems")
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
	elif _scroll_enclosing(screen._carrying) == null:
		# THE OTHER HALF, OR THIS PASSES FOR THE WRONG REASON. "The log is not in the scroll box" is
		# also true of a screen with no scroll box at all, and of one where the content left instead.
		#
		# **THE WITNESS IS THE PACK AND NO LONGER `do`** (ASSA-247). `do` is pinned always-on now, so
		# asking whether IT scrolls would fail on the current design while saying nothing about the
		# log. The pack is a tab body inside the strip's own scroll box, which is the box this test is
		# about: the one the log must not be in.
		ok = _fail("the pack is not in a scroll box any more, so this test is green about a column "
				+ "that no longer exists rather than about the log leaving it")
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
## the box is `IGNORE`, because 912x672 of empty space answering the mouse is how
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


## THE SAME READING, WITH THE HUD COLUMN FORCED ON SCREEN FOR THE LENGTH OF IT (ASSA-231).
##
## **A STRANGER CANNOT SEE ANY OF THIS ANY MORE AND THE WORDING STILL HAS TO BE RIGHT.** Maren's Gap
## 5 took the column off the join screen entirely ("the empty column not shown at all before a world
## exists"), so `_on_screen` is false for every label in it there -- and the two ASSA-186 tests that
## read those sentences would fail on their own premise, which is the instrument refusing rather than
## passing, and the right behaviour. What they are about is the WORDS, and the words outlive the
## state: the column has had a no-world state twice (ASSA-134, ASSA-186) and will have one again the
## day a section is read before a join. So they are read in the state they were written for, by hand,
## and the state itself is asserted absent by
## `test_the_hud_column_is_not_on_the_join_screen_and_comes_back_with_a_world`.
##
## RESTORED AFTERWARDS, because a test that leaves the screen in a state it invented is the next
## test's wrong premise.
## **AND SINCE ASSA-247 IT OPENS THE SECTION'S TAB TOO, for the same reason and with the same
## restore.** One system is on screen at a time now, so `_on_screen` is false for three of the four
## tab bodies at any moment -- and these tests are about the WORDS a section says when it is empty,
## which it says whether or not its tab is the open one. Without this they fail on their own premise,
## which is honest of them and useless.
##
## **WHAT IT DOES NOT PAPER OVER:** that a tab's body is hidden until pressed is asserted as a
## property of its own by `test_one_system_is_visible_and_all_four_names_are`, and that selecting a
## tab is what brings its section back is asserted in a world by
## `test_the_hud_column_is_not_on_the_join_screen_and_comes_back_with_a_world`. This helper is the
## instrument for the wording tests; it is not where the structure is checked.
func _lone_note_in_the_column(screen: Node, section: Node) -> String:
	var column: Panel = screen._column
	var was: bool = column != null and column.visible
	if column != null:
		column.visible = true
	var open_was: String = screen._tabs.selected() if screen._tabs != null else ""
	for named in (screen._tabs.tab_names() if screen._tabs != null else PackedStringArray()):
		var body: Control = screen._tabs.body_of(named)
		if body != null and (body == section or body.is_ancestor_of(section)):
			screen._tabs.select(named)
			break
	var said := _lone_note(section)
	if screen._tabs != null and open_was != "":
		screen._tabs.select(open_was)
	if column != null:
		column.visible = was
	return said


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
	# READ WITH THE COLUMN FORCED ON SCREEN (ASSA-231): Gap 5 took the column off the join screen, so
	# these three sentences are the wording of a state a player can no longer reach. The wording is
	# still under test here; that the state is gone is asserted in its own test.
	var sentences := {"the bench": _lone_note_in_the_column(screen, screen._bench),
			"the crafting menu": _lone_note_in_the_column(screen, screen._make),
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
	# WITH THE COLUMN FORCED ON SCREEN FOR THIS ONE READING (ASSA-231): the no-world wording is what
	# the in-world wording has to differ from, and the column itself is off screen before a world now.
	var before := _lone_note_in_the_column(screen, screen._bench)
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
	ok = _reads_in_world(screen, screen._bench, "bench",
			"nothing built yet — mine, smelt and make parts first") and ok
	ok = _reads_in_world(screen, screen._make, "crafting menu",
			"nothing you are carrying can be worked by hand — mine some rock first") and ok
	ok = _reads_in_world(screen, screen._log, "event log", "nothing has happened yet") and ok
	screen.queue_free()
	return ok


## **THE SCHEMATIC HAS THE FACT ITS DISCS ARE DRAWN FROM, ON THE REAL SCREEN** (ASSA-187).
##
## This is the wiring half, and it is the half that cannot be checked in `test_hud.gd`:
## `AssayHud.deposit_disc` being right buys nothing until the list `main.gd::_draw` iterates actually
## carries `reach_note`, and it reads that key WITHOUT A DEFAULT on purpose. So a binding that
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
## `tools/maren_whole_world_shot.gd` (a GUI run) measured by `shared/assay/assa187_measure.py` against
## the geometry `tools/schematic_disc_table.gd` prints. Since ASSA-199 the number is Cove's:
## share of the interior at `MAP_BG` ink, 22.2-27.1% hatched against 0.0% on a clean disc.
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
		# **`reach_note` IS THE KEY NOW, NOT `hand_minable`** (ASSA-199): a rock can be dug and not
		# smelted, so the two are not opposites and the mark follows the note. Both are checked
		# for presence, because the tile readout still reads the other one.
		var missing := []
		for key: String in ["hand_minable", "reach_note"]:
			if not deposit.has(key):
				missing.append(key)
		if not missing.is_empty():
			ok = _fail(("the screen is about to draw a deposit with no %s on it: %s. "
					+ "`deposit_disc` reads `reach_note` with no default, so this is a blank schematic.")
					% [missing, deposit.keys()])
			break
		var disc := AssayHud.deposit_disc(deposit, 18.0)
		if not bool(disc["filled"]):
			ok = _fail(("the screen is about to draw an UNFILLED disc at %s. ASSA-199 box 4: the "
					+ "hollow of #259 is gone, not left underneath the hatch.")
					% [deposit.get("center", Vector2i.ZERO)])
			break
		states[bool(disc["hatch"])] = true
	if ok and (drawn < 2 or states.size() != 2):
		ok = _fail(("premise: %d discs and %d distinct HATCH states on seed 777042. The Game "
				+ "Director counted 8 of 13 dead ends there; one state means this world cannot "
				+ "show the distinction and the assertions above are vacuous")
				% [drawn, states.size()])
	screen.queue_free()
	return ok


## ONE SECTION'S IN-WORLD SENTENCE, named in the failure so three sections do not report as one.
## **THROUGH `_lone_note_in_the_column` SINCE ASSA-247, so the reading opens the section's own tab.**
## The bench is a tab body now and `make` is the tab that happens to be open on entering a world, so
## reading these three with the bare `_lone_note` would compare the bench's sentence against the
## empty string and call it a wording change. What is under test is the words; which tab is open is
## asserted where it belongs.
func _reads_in_world(screen: Node, section: Node, named: String, want: String) -> bool:
	var said := _lone_note_in_the_column(screen, section)
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
##
## **AND IT POKES THE LABEL FIRST, WHICH IS THE WHOLE OF ASSA-246 FOR THE FOUR SWEEPS THAT USE THIS.**
## Our theme is a PROJECT theme (`project.godot` `gui/theme/custom`), and a control themed that way
## keeps resolving the PLAIN type's entries -- `Label` -- ignoring its own `theme_type_variation`
## until it receives `NOTIFICATION_THEME_CHANGED`. Running `_process` frames does not deliver it. So
## headless, a `Heading` label reported `Label`'s colour and a `Quiet` button reported `INK` where
## the window draws `INK_MUTED`; a test of mine on ASSA-233 asserted the opposite of what ships and
## passed.
##
## **THE SWEEPS WERE RIGHT BY COINCIDENCE, NOT BY CONSTRUCTION, AND THAT IS WHY THIS IS A ONE-LINE
## FIX TO A HELPER RATHER THAN A SWEEP OF 27 CALL SITES.** All 7 `Heading` labels and the 1 `Display`
## go through here, and they came back correct only because `_style_label` sets plain `Label`'s
## `font_color` to `INK` as well. Retune `Heading`'s ink away from `Label`'s -- which Maren has
## already done once, `INK_MUTED` -> `INK` on ASSA-224 -- and ASSA-117's 4.5:1 floor would have gone
## blind to every heading in the window while staying green. One poke here fixes every caller at
## once, and no caller has to remember.
func _drawn_color(label: Label) -> Color:
	return Poke.drawn_color(label)


## **THE POKE ITSELF MOVED OUT OF THIS FILE (ASSA-312), AND THESE THREE ARE NOW NAMES FOR IT.**
##
## ASSA-246 shipped the poke inside `_drawn_color` and disclosed that nothing could catch its
## removal: every `Label` variation's ink coincides with plain `Label`'s, so a colour assertion is
## blind to it, and the one test that reads a property where the two types DO differ -- `font_size`,
## `Heading` 15 against `Label` 13 -- poked its own probe by hand. So it proved that poking works,
## not that the helper does it. ASSA-252 fixed that by routing the size read through the helper.
##
## **WHAT MOVED IT OUT WAS A SECOND FILE NEEDING IT.** ASSA-267 removed the override that was the
## only thing propping up `test_tab_strip.gd`'s theme read, and 12 assertions went red against a
## theme that was already correct. Two sites is where "a shared helper rather than call sites each
## remembering" -- ASSA-246's own words -- stops being theoretical.
##
## These three wrappers stay because ~30 call sites in this file use them and renaming those would
## be a diff nobody could review for the thing it is actually about. The poke lives in
## `tests/theme_poke.gd`, `check_one_theme_poke.py` fails if it reappears anywhere else in
## `tests/`, and deleting it from the helper still reddens by name on the `font_size` lever.
func _poke_theme(control: Control) -> Control:
	return Poke.poke(control)


## The font size a label DRAWS, which is not what a headless read reports until it is poked. Same
## helper as `_drawn_color`, so the two cannot drift apart, and this is the read that gives the poke
## a lever: `Heading` declares 15 and plain `Label` 13, so an un-poked `Heading` is off by 2px.
func _drawn_font_size(label: Label) -> int:
	return Poke.drawn_font_size(label)


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
	# **AND `Join` GOES WITH THEM NOW** (ASSA-237, Maren's Gap 2: *"a `Join` button sits in the
	# top-left corner of a world you are already in"*). This assertion was its own opposite until
	# today -- it read *"hiding the band took `Join` with it, which is the one control that can still
	# act"*. That reason is true at IDLE, CONNECTING and DEAD and false here: `_join_address` returns
	# on its first line unless the stage is IDLE or DEAD, so the only thing this press can reach at
	# JOINED is a refusal. The DEAD half below is what keeps the half of ASSA-175 that was real.
	if _on_screen(joined._join_button):
		ok = _fail("`Join` is still on screen in a world you are already in, where the only thing "
				+ "pressing it can produce is a refusal")
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
		# NO `tick N ·` PREFIX, because `_remember_events` stopped writing one (ASSA-222, Maren's
		# ruling). A fixture that still carried it would be measuring a line the client cannot
		# produce -- and these tests are about WIDTH and dimming, so a stale prefix would quietly
		# measure the wrong string length.
		lines.append("event number %d" % i)
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
## re-word or count them. The total on the heading is the sim's own sentence and not this block's
## arithmetic over the rows -- see the test below, which is what holds that apart.
##
## **WHAT IS PINNED IS NOW THE CONDITION AND NOT THE LIST** (ASSA-247, Maren's ruling 17:22 UTC
## 2026-10-06, amending her own ASSA-89/94). `_halt` was the one UNBOUNDED thing in the pinned
## chrome -- one line per stalled machine, growing with the factory, and 161 px of the worst-case
## clip. Her words: *"a stall is a condition, not a moment was about never losing the fact -- it
## never said every stalled machine must sit above the fold forever."* So the count stays pinned and
## the machines go to the `bench` tab, where machines live.
##
## **BOTH HALVES ARE ASSERTED HERE, because either alone is the ruling half-built**: a pinned block
## that still holds the list did not return the pixels, and a list in the bench tab with nothing
## pinned loses the fact that something has stopped.
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
		var bench: Control = screen._tabs.body_of("bench")
		if not screen._halt_box.visible:
			ok = _fail("two buildings have stopped and the block is still hidden")
		elif not bench.is_ancestor_of(screen._halt_lines):
			ok = _fail("the stalled machines are not in the `bench` tab, so the one unbounded list in "
					+ "the pinned chrome still grows with the factory: Maren's 17:22 ruling")
		elif not screen._halt.find_children("*", "Label", true, false).size() == 1:
			ok = _fail(("the pinned block holds %d labels; it is the condition and its size, one line, "
					+ "and the machines are a press away in `bench`")
					% screen._halt.find_children("*", "Label", true, false).size())
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


## **THE STOPPED HEADING CARRIES A TOTAL THIS BLOCK COULD NOT HAVE WORKED OUT** (ASSA-94).
##
## The Game Director ruled the count the floor of this surface: *"a player who reads '3 machines
## stopped' and can see one reason knows there are two more to find; a player who sees one reason and
## no count does not know anything is missing."* The block declined one in a comment, on the correct
## objection that a count would be a second claim about the world -- and the answer was never for the
## client to count, it was to read the sentence the sim was already composing (`halt_summary`).
##
## **THE ASSERTION IS THAT THE HEADING HOLDS A NUMBER THE ROWS DO NOT CONTAIN, and that is the whole
## design of this test.** Asserting `heading.text == summary` alone is nearly vacuous -- `summary` is
## the argument that was just passed in. So the fixture is deliberately **2 stopped out of 7**: a
## block counting its own rows can produce the 2 and can NEVER produce the 7, because how many
## buildings exist is not in `halt_lines` at all. That is also the fact that made the old comment
## wrong on the merits rather than on taste.
func test_the_stopped_headings_total_is_one_this_block_could_not_have_counted() -> bool:
	var screen := _screen()
	var ok := true
	var planted := PackedStringArray([
		"smelter 3 at (12, 7) · walls stone · stalled: the fuel will not light",
		"machine 1 at (4, 9) · nothing here to mine",
	])
	# Two stopped, SEVEN built. `planted.size()` is 2 and no arithmetic over these rows reaches 7.
	var summary := "2 of 7 buildings stopped"
	screen._rebuild_halt(planted, summary)
	var heading: Label = null
	for child in screen._halt.get_children():
		if child is Label and (child as Label).theme_type_variation == &"Heading":
			heading = child
			break
	if heading == null:
		ok = _fail("the stopped block has no heading, so there is nowhere for the total to survive "
				+ "when the reasons are dropped")
	elif heading.text != summary:
		ok = _fail(("the stopped heading reads '%s' and the sim's sentence is '%s': the count is the "
				+ "sim's wording or it is a second claim about the world") % [heading.text, summary])
	elif not heading.text.contains("7"):
		ok = _fail(("the stopped heading reads '%s', which carries no total beyond the %d rows it was "
				+ "handed -- a block counting its own rows would read exactly like this, and the "
				+ "ruling is that the player is told how many there ARE") % [heading.text,
				planted.size()])
	# AND THE ROWS ARE UNTOUCHED BY IT: the heading is not one of them, so a short column drops
	# reasons and never the number.
	if ok:
		var rows: Array = screen._halt_lines.find_children("*", "Label", true, false)
		if rows.size() != planted.size():
			ok = _fail("%d lines went in and %d came out once the heading carried a count"
					% [planted.size(), rows.size()])
	# **AND THE TOTAL IS PART OF WHAT "THE BLOCK IS ALREADY SHOWING THIS" MEANS.** `_refresh_halt`
	# rebuilds only when the shape changes, and M moves when a WORKING building is placed -- which
	# changes no line. So "1 of 2" and "1 of 3" carry identical lines, and a shape built from the
	# lines alone would compare equal and leave the old total on screen: the number that must always
	# be stated, quietly wrong. The suite cannot reach a world with a stalled building in it, so this
	# is asserted on the shape itself rather than left to a comment.
	if ok:
		var same := PackedStringArray(["machine 1 at (4, 9) · nothing here to mine"])
		if screen._halt_shape("1 of 2 buildings stopped", same) \
				== screen._halt_shape("1 of 3 buildings stopped", same):
			ok = _fail("placing a working building moves the total and no line, and this block "
					+ "cannot tell those two states apart, so it would keep showing the old count")
	# AND WITH NO SENTENCE FROM THE SIM IT FALLS BACK TO THE SECTION'S NAME rather than inventing a
	# number -- the state every other test here drives it in.
	if ok:
		screen._rebuild_halt(planted)
		for child in screen._halt.get_children():
			if child is Label and (child as Label).theme_type_variation == &"Heading":
				if (child as Label).text != "stopped":
					ok = _fail(("with no summary the heading reads '%s'; it must fall back to the "
							+ "section's own name") % [(child as Label).text])
				break
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
	for _i in 12:
		lines.append(long)
	# THE NEWEST ENTRY IS ALSO A LONG ONE, or "the newest shows whole" would be a claim about a
	# sentence that fits anyway and the exemption could be deleted with nothing going red.
	#
	# NO `tick N ·` PREFIX SINCE ASSA-222: `_remember_events` no longer writes one, and this test
	# measures WRAPPING, so a fixture carrying a prefix the client cannot produce would be wrapping
	# a string five characters longer than any real line.
	lines.append(long)
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
	# **A STATE A PLAYER CANNOT REACH ANY MORE, AND A WORDING THAT STILL HAS TO BE RIGHT** (ASSA-231).
	# Maren's Gap 5 took the whole column off the join screen, and this sweep reads each section's OWN
	# visible flag rather than its ancestors -- so it would have stayed green while being about a
	# column nobody can see, which is the worst of both. Shown by hand for the length of the sweep,
	# with the absence asserted in
	# `test_the_hud_column_is_not_on_the_join_screen_and_comes_back_with_a_world`.
	screen._column.visible = true
	var ok := _sweep_headings(screen, "the join screen")
	screen._column.visible = false
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
	var door: VBoxContainer = screen._front_door
	# **THE SURFACE THIS IS MEASURED AGAINST IS THE WINDOW, NOT THE MAP** (ASSA-231). It was
	# `world_rect` while the door was the map's note. Before a world exists there is no map to be on
	# and no column beside it, so the composition owns the screen -- see `join_rect`.
	var world := AssayHud.join_rect()
	if note == null:
		ok = _fail("the join screen's map has no note at all")
	elif not _on_screen(note):
		ok = _fail("the map's note exists but is hidden on the first screen a stranger sees")
	elif note.text != AssayHud.empty_map_line() or note.text.strip_edges() == "":
		ok = _fail("the map's note is not the shipped sentence: '%s'" % note.text)
	# **THE SPAN IS THE DOOR'S NOW, AND IT IS THE SAME PROPERTY** (ASSA-231). The sentence is one line
	# inside `_front_door`; what has to cover the map is the composition the sentence belongs to, and
	# a one-line label is no longer the thing to measure. The note being INSIDE the door is what ties
	# the two halves together, so neither can be satisfied by a label parked in a corner.
	elif note.get_parent() != door:
		ok = _fail("the map's note is not part of the front door, so its span is nobody's property")
	elif not world.encloses(Rect2(door.position, door.size)):
		ok = _fail(("the front door is not on the surface it explains: door %s, surface %s")
				% [Rect2(door.position, door.size), world])
	# **CENTRED ON THE WINDOW A PLAYER IS LOOKING AT, AND THIS IS THE LEVER** (ASSA-231). The first
	# version of this screen centred the door on `world_rect`, which subtracts the 320 px the HUD
	# column stands in -- and the column is not drawn here. The shot showed the whole composition
	# sitting 80 px left of centre beside a band of bare window. Reading the door's own centre is
	# what fails on that build: it answered 480 where the window's middle is 640.
	elif not is_equal_approx(door.position.x + door.size.x * 0.5, AssayHud.VIEW.x * 0.5):
		ok = _fail(("the join composition is centred at x=%.0f, and the window's middle is %.0f -- "
				+ "it is centred on the map's rectangle, which is not drawn here")
				% [door.position.x + door.size.x * 0.5, AssayHud.VIEW.x * 0.5])
	elif door.size.x * door.size.y < world.size.x * world.size.y * 0.5:
		ok = _fail(("the front door covers %d px of a %d px rectangle, so centring it says nothing "
				+ "about where the words land") % [door.size.x * door.size.y,
				world.size.x * world.size.y])
	# AND THE SURFACE UNDER IT IS PAINTED. A centred composition on bare window is the same defect
	# wearing the other half of the fix: the door is a transparent container and `_world` paints
	# `MAP_BG` over the map's rectangle only.
	elif not screen._door_backdrop.visible \
			or not Rect2(screen._door_backdrop.position, screen._door_backdrop.size).encloses(world):
		ok = _fail("the join screen's dark surface does not cover the window the door is centred on")
	elif note.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER \
			or door.alignment != BoxContainer.ALIGNMENT_CENTER:
		ok = _fail("Maren's ruling is a CENTRED line; the note aligns %d and the door %d"
				% [note.horizontal_alignment, door.alignment])
	elif note.mouse_filter != Control.MOUSE_FILTER_IGNORE \
			or door.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		ok = _fail("a map-sized control that answers the mouse swallows every click on the map, and "
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
	# call cannot look like a pass. **THE FRONT DOOR IS WHAT CARRIES THE VISIBILITY NOW** (ASSA-231):
	# the sentence is one line inside it, and the column is the same fact the other way up.
	screen._front_door.visible = false
	screen._column.visible = true
	screen._refresh_world()
	if not screen._front_door.visible:
		ok = _fail("with no world, _refresh_world left the map silent")
	elif screen._column.visible:
		ok = _fail("with no world, the HUD column is still on screen (Maren's Gap 5)")
	screen.queue_free()

	var joined := _joined_screen()
	if ok and joined._sim.running():
		joined._front_door.visible = true
		joined._column.visible = false
		joined._refresh_world()
		if joined._world.view.is_empty():
			ok = _fail("the welcomed screen drew no world, so this half proves nothing")
		elif joined._front_door.visible:
			ok = _fail("the map has a world on it and still says there is no world yet")
		elif not joined._column.visible:
			ok = _fail("there is a world and the HUD column did not come back with it")
	elif ok:
		ok = _fail("could not build an offline world, so the in-world half proves nothing: %s"
				% joined._sim.fail_reason)
	joined.queue_free()
	return ok


## **THE EMPTY COLUMN IS NOT SHOWN AT ALL BEFORE A WORLD EXISTS** (ASSA-231, Maren's Gap 5 in doc
## `assay-ui-direction`, verbatim).
##
## Six of its seven sections said which kind of empty they were, which is ASSA-134 and ASSA-186
## working as ruled, and her own doc calls the composition that produces "a column of six apologies".
##
## **ASKED OF EVERY SECTION AND OF THE ANCESTOR CHAIN**, not of the one node this fix happens to hide:
## `_on_screen` walks the parents, so a later refactor that moves the hide somewhere else still has to
## pass, and hiding a section's parent cannot read as "the section is fine".
##
## **AND BOTH HALVES, BECAUSE THE FIRST HALF ALONE PASSES ON A CLIENT WITH NO COLUMN AT ALL.** The
## in-world half is what makes this a measurement: the same nodes, on screen, the frame a world
## arrives. Driven through a real `Welcome` and one `_refresh()`, which is the call `_process` makes.
func test_the_hud_column_is_not_on_the_join_screen_and_comes_back_with_a_world() -> bool:
	var screen := _screen()
	var ok := true
	# **SPLIT IN TWO SINCE ASSA-247, AND THE JOIN-SCREEN HALF IS UNCHANGED BY THE SPLIT**: nothing in
	# this column is on screen before a world, tabbed or not. What the tabs change is the OTHER half
	# -- "comes back with a world" cannot mean "all four systems are visible at once", because one
	# system at a time is the ruling. So a tab's body comes back when its own name is pressed, which
	# is a stronger statement than the old sweep made: it says the strip actually reveals the section.
	var always_on := {"do": screen._actions, "the log's toggle": screen._log_toggle,
			"the painted surface": screen._column, "the tab strip": screen._tabs.names_box(),
			"the cursor readout": screen._cursor}
	var tabbed := {"make": screen._make, "inventory": screen._carrying,
			"bench": screen._bench, "mineralogy": screen._species}
	for named: String in always_on:
		if _on_screen(always_on[named]):
			ok = _fail(("%s is on the join screen, where it has nothing to say: Gap 5 is that the "
					+ "empty column is not shown at all before a world exists") % named)
	for named: String in tabbed:
		if _on_screen(tabbed[named]):
			ok = _fail(("the %s tab's body is on the join screen, where it has nothing to say: Gap 5 "
					+ "is that the empty column is not shown at all before a world exists") % named)
	# THE HEADINGS TOO, which are Labels in the column rather than fields on the screen, so they are
	# found the way the sweeps find them: by the variation that MAKES a heading a heading here.
	# SEARCHED THROUGH THE WHOLE COLUMN rather than one parent's children, because a heading is inside
	# a tab body now and a sweep over one level would find only `do` and report six as one.
	var headings := 0
	for child in screen._column.find_children("*", "Label", true, false):
		var label := child as Label
		if label != null and label.theme_type_variation == &"Heading":
			headings += 1
			if _on_screen(label):
				ok = _fail("the `%s` heading is on the join screen with no world under it"
						% label.text)
	if headings < 1:
		ok = _fail("found no headings in the column, so this sweep could not fail")
	var welcome := AssaySimHost.fresh_welcome_json("14247", "limpet")
	screen._client.play_offline()
	screen._client.feed_offline(welcome)
	screen._refresh()
	if not screen._sim.running():
		ok = _fail("premise: nothing is being simulated, so the in-world half asks nothing")
	else:
		for named: String in always_on:
			if not _on_screen(always_on[named]):
				ok = _fail("%s did not come back when the world did" % named)
		for named: String in tabbed:
			if not screen._tabs.select(named):
				ok = _fail("the %s tab cannot be selected in a world" % named)
			elif not _on_screen(tabbed[named]):
				ok = _fail("%s did not come back when its own tab was opened in a world" % named)
	screen.queue_free()
	return ok


## **ONE SCREEN, ONE PRIMARY ACTION** (ASSA-231, Maren's Gap 5: *"the one thing a stranger should
## press, Play solo, is a small outlined button in the top-left corner, visually subordinate to the
## host field, the name field and Join"*).
##
## ASSA-224 answered the colour half -- `Play solo` is the only `Primary` in the client. This is the
## layout half: the primary has a line to itself above the host path, so it is not sharing its line
## with two text boxes and a second button, and the whole composition is in the middle of the map
## rather than in the corner of it.
##
## **AND THE CONTROLS GO BACK TO THE ROW IN A WORLD, WHICH IS THE HALF THAT COULD BREAK A DROP.**
## `_join_address` permits a join attempt at stage DEAD and that band is the client's only reconnect
## affordance (ASSA-175/ASSA-177), so a composition that kept them on a door hidden by the world
## would take the way back in away from a dropped player. The same nodes, two homes, asserted both
## ways: `_place_join_controls` is the only thing that moves them.
func test_the_primary_has_its_own_line_before_a_world_and_the_row_has_it_after() -> bool:
	var screen := _screen()
	var ok := true
	if screen._solo_button.get_parent() != screen._solo_cell \
			or screen._solo_cell.get_parent() != screen._door_primary:
		ok = _fail("Play solo is not in the front door's primary line: %s"
				% screen._solo_button.get_parent())
	# THE PRIMARY'S LINE HOLDS NOTHING ELSE. One `Button` and no field: that is the whole of "its own
	# line", and it is asserted by counting rather than by reading an index.
	var on_that_line := 0
	for control in _row_reading(screen._door_primary):
		if control is Button or control is LineEdit:
			on_that_line += 1
	if on_that_line != 1:
		ok = _fail("%d controls share the primary's line, so it is not alone on it" % on_that_line)
	# AND THE HOST PATH IS THE LINE UNDER IT, in the door's order and after the primary.
	var order: Array = screen._front_door.get_children()
	if order.find(screen._door_primary) > order.find(screen._door_secondary):
		ok = _fail("the host path is above the primary, so the composition reads host-first")
	for named: String in ["the host box", "the name box", "Join"]:
		var control: Control = {"the host box": screen._host, "the name box": screen._name,
				"Join": screen._join_button}[named]
		if not _on_screen(control):
			ok = _fail("%s is not on the join screen, so the other way in is gone" % named)
		elif not screen._door_secondary.is_ancestor_of(control):
			ok = _fail("%s is not on the door's second line: %s" % [named, control.get_parent()])
	# IN A WORLD: back in the top-left row, with `Join` in the row itself rather than in the band.
	var welcome := AssaySimHost.fresh_welcome_json("14247", "limpet")
	screen._client.play_offline()
	screen._client.feed_offline(welcome)
	screen._refresh()
	if not screen._sim.running():
		ok = _fail("premise: nothing is being simulated, so the in-world half asks nothing")
	else:
		if _on_screen(screen._front_door):
			ok = _fail("the front door is still over the world a player is standing in")
		if screen._solo_cell.get_parent() != screen._join_band \
				or screen._cred_cell.get_parent() != screen._join_band:
			ok = _fail("the join controls did not go back into the band: %s / %s"
					% [screen._solo_cell.get_parent(), screen._cred_cell.get_parent()])
		if screen._join_button.get_parent() != screen._row:
			ok = _fail("Join did not go back into the row: %s" % screen._join_button.get_parent())
		# **THE TWO LABELS THE CLIENT SPEAKS THROUGH GO INTO THE TOAST NOW** (ASSA-239). They came
		# home to the screen itself at (24, 54) and (24, 74) until today -- two hand-written
		# coordinates inside the 96px header strip that Maren's Gap 2 ruling deleted. There is no
		# strip, so there is no coordinate: they move between two containers and nothing positions
		# them.
		for named: String in ["the status line", "the detail line"]:
			var label: Label = {"the status line": screen._status,
					"the detail line": screen._detail}[named]
			if label.get_parent() != screen._says_toast_box:
				ok = _fail("%s is under %s, not in the toast over the world"
						% [named, label.get_parent()])
	screen.queue_free()
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
## So it drives the real screen at the real 912x672 rect, puts the body in row 0, and reads the
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
		# **THE BODY IS PLACED THROUGH THE PLAYOUT BUFFER, NOT BY SETTING `_was`/`_seen`** (ASSA-197).
		# Those two are now DERIVED every frame from the positions the clock is between, so a test
		# that assigned them was overwritten before `_refresh_world` drew anything -- it reported a
		# body at spawn and a camera aimed somewhere else, which is how this test caught the change.
		# One held position with the clock parked on it is a standing body: `from == to`, part 1.
		# TYPED, because `_pending` is an `Array[Dictionary]` and assigning a bare array literal to
		# one aborts the test mid-function -- which the runner reports as "returned false and said
		# nothing", a failure with no message and no line.
		var held: Array[Dictionary] = [{"at": 0.0, "tick": 1, "where": {id: Vector2i(48, row)}}]
		screen._pending = held
		screen._play_tick = 1.0
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
		for _i in 14:
			# No `tick N ·` prefix since ASSA-222 (ASSA-116 box 2).
			lines.append("you mined 20 of Tonore ore (A) at (74, 36)")
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
			# No `tick N ·` prefix since ASSA-222; `i` is unused now, hence `_i`.
			lines.append("you mined 20 of Tonore ore (A) at (74, 36)")
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


## **THE WARNING COVERS THE STATUS LINE AND GIVES BACK WHAT IT COVERED** (ASSA-191, Maren's 2s
## threshold: say something, change nothing, and go the moment a bundle lands).
##
## WHAT IS DRIVEN HERE AND WHY IT IS THE SIGNAL. The RULE -- when a gap is worth a word and what the
## number is -- is `tests/test_link_silence.gd`, and that a real silent host reaches this signal at
## all is `tools/reconnect_probe.gd` case F against a real relay. What is left, and what this file
## exists for, is that the signal is wired to anything: a label nobody connected would pass both of
## those and show a player nothing.
##
## THE ASSERTION IS THE ROUND TRIP, not the warning. A client that blanked the line on the way back
## would satisfy "the sentence disappears" and leave the player with less than they started with.
func test_a_quiet_host_covers_the_status_line_and_gives_back_what_it_covered() -> bool:
	var screen := _joined_screen()
	if screen._client.stage != AssayNetClient.Stage.JOINED:
		screen.queue_free()
		return _fail("the fixture never joined (stage %d), so there is no status line to cover"
				% screen._client.stage)
	var joined_said: String = screen._status.text
	var joined_colour: Color = _drawn_color(screen._status)
	var ok := true
	if joined_said.strip_edges() == "":
		ok = _fail("the joined screen says nothing, so this test cannot tell a cover from a blank")
	screen._client.link_quiet.emit(3)
	var warned: String = screen._status.text
	if ok and warned != AssayHud.quiet_host_line(3):
		ok = _fail(("a host quiet for 3s left the status line saying \"%s\". The window looks exactly "
				+ "like a running game, which is the whole defect.") % warned)
	elif ok and _drawn_color(screen._status) != AssayHud.status_color(AssayHud.Say.CONNECTING):
		ok = _fail("the warning is coloured %s, not the colour this line uses for a transient state"
				% _drawn_color(screen._status))
	# THE NUMBER GOING UP IS THE PART A PLAYER READS. A line that froze at the first count would say
	# the same thing at 3s and at 9s, which is "something happened once" rather than "it is ongoing".
	screen._client.link_quiet.emit(7)
	if ok and screen._status.text != AssayHud.quiet_host_line(7):
		ok = _fail("the count did not go up: the line still reads \"%s\"" % screen._status.text)
	# A REAL SENTENCE ARRIVES WHILE THE HOST IS QUIET -- through the path that composes them, not by
	# assignment. It must not show (the warning outranks it, `main.gd::_render_status`) and it must be
	# what comes back, which is what proves the line is derived rather than saved and restored.
	#
	# **THE VEHICLE IS A REFUSAL NOW AND IT USED TO BE A NOTE** (ASSA-245). `note.emit` no longer
	# reaches the status line once the stage is JOINED -- the only note that can still fire there is
	# `offline, so no hash report was sent`, a sentence about this client's hash reporting that Maren's
	# Gap 2 ruling named and sent off the player's screen. So a note at JOINED is printed and not
	# drawn, and a test using one as its "real sentence" was testing a path that no longer exists.
	# `refused` is the same shape and still composes through a real handler (`_on_refused` -> `_say`),
	# and it is a `FAILED` line, which also means the dwell cannot age it out underneath this
	# assertion.
	screen._client.refused.emit("the relay said no")
	if ok and screen._status.text != AssayHud.quiet_host_line(7):
		ok = _fail(("a note displaced the quiet warning: \"%s\". The world is not moving; the newest "
				+ "sentence is not the most useful one.") % screen._status.text)
	screen._client.link_quiet.emit(0)
	var back: String = screen._status.text
	if ok and back == AssayHud.quiet_host_line(7):
		ok = _fail("a bundle landed and the warning is still on screen: \"%s\"" % back)
	elif ok and back.strip_edges() == "":
		ok = _fail(("the warning took the status line down with it. It covered \"%s\"; a player who "
				+ "waited out a hiccup now has less than they started with.") % joined_said)
	elif ok and not back.contains("the relay said no"):
		ok = _fail(("the line came back as \"%s\" and not as the sentence that arrived under the "
				+ "warning. The label is being restored from a copy rather than derived.") % back)
	elif ok and _drawn_color(screen._status) == AssayHud.status_color(AssayHud.Say.CONNECTING) \
			and joined_colour != AssayHud.status_color(AssayHud.Say.CONNECTING):
		ok = _fail("the warning's colour outlived its sentence: %s" % _drawn_color(screen._status))
	screen.queue_free()
	return ok


## **THE SCHEMATIC IS HANDED EVERY BUILDING THE SIM REPORTS** (ASSA-189, Maren's P1).
##
## This is the wiring half and it is the half that IS the defect. `AssayHud.building_mark` being
## right buys nothing: for a month `_sim.buildings()` occurred exactly ONCE in `main.gd`, inside the
## close-up's `view` dictionary, so the whole-world view could not draw a factory because it was
## never handed one. Nothing in `test_hud.gd` can see that, and the picture could not either -- an
## empty map looks the same whether the painter is wrong or the list never arrived.
##
## **THE LIST IS AN ARGUMENT, BECAUSE A FRESH `Welcome` HAS NO BUILDINGS IN IT.** Planting two, the
## way `test_what_has_stopped_is_pinned_outside_the_scroll` plants the sim's halt lines, is what stops
## this passing for the ABSENCE of the data it is about -- the hole Marlow found in my durability test
## and the one I keep re-finding. The screen is real, driven into the real schematic through
## `_show_close_up(false)`, and the geometry comes out at the screen's own `_cell` and `MARGIN`.
##
## **AND THE SOURCE IS SCANNED, which is the leg that would have caught the bug.** The two together:
## the marks prove the geometry survives the real screen, the scan proves `_draw` asks for the list at
## all. A `_building_marks` that exists, is correct and is called by nobody is exactly the state this
## item describes, and it leaves every assertion above green.
##
## WHAT IT CANNOT SEE: whether `draw_colored_polygon` put any pixels down. Nothing headless can read a
## canvas back. That is `tools/window_shot.gd`'s whole-world shot, measured by
## `shared/assay/assa187_measure.py`.
func test_the_schematic_is_handed_every_building_the_sim_reports() -> bool:
	var screen := _joined_screen()
	screen._show_close_up(false)
	screen._refresh()
	if screen._close_up or not screen._sim.running() or screen._cell <= 0.0:
		screen.queue_free()
		return _fail(("premise: close_up %s, running %s, cell %f -- `_draw` returns before a "
				+ "building on any of those and this test would be about nothing")
				% [screen._close_up, screen._sim.running(), screen._cell])
	var ok := true
	# A 2x2 smelter and a 1x1 machine: the two footprints `BuildingKind::footprint` actually gives.
	var planted := [{"pos": Vector2i(12, 7), "footprint": Vector2i(2, 2), "kind": "smelter"},
			{"pos": Vector2i(40, 30), "footprint": Vector2i(1, 1), "kind": "machine"}]
	var marks: Array = screen._building_marks(planted)
	var map := Rect2(screen.MARGIN, Vector2(screen._sim.size_tiles()) * screen._cell)
	if marks.size() != planted.size():
		ok = _fail("%d buildings went in and %d marks came out" % [planted.size(), marks.size()])
	else:
		for i in marks.size():
			var mark: Dictionary = marks[i]
			var building: Dictionary = planted[i]
			var at: Vector2 = mark["at"]
			var want: Vector2 = screen.MARGIN + (Vector2(building["pos"] as Vector2i)
					+ Vector2(building["footprint"] as Vector2i) * 0.5) * screen._cell
			if at.distance_to(want) > 1e-4:
				ok = _fail(("the %s at tile %s is marked at %s and its footprint's centre on this "
						+ "screen is %s") % [building["kind"], building["pos"], at, want])
				break
			if not map.has_point(at):
				ok = _fail(("the %s at tile %s is marked at %s, outside the map rect %s: a factory "
						+ "drawn off the world is the same news as one not drawn")
						% [building["kind"], building["pos"], at, map])
				break
			# **NOT THE PLAYER'S SHAPE, ON THE REAL CELL** (Maren's box 4, re-asked as ASSA-236).
			# The claim it holds is reversed and still the same claim: the two must differ in SHAPE,
			# which is the half that survives a greyscale copy. A machine's mark fills the corner of
			# its own box -- it is the footprint -- and is empty at its CENTRE, where a person
			# standing on it is solid. Asserting both is what stops the swap being a rename.
			var span: Vector2 = mark["span"]
			var corner := at + span * 0.5 - (span.normalized() * 0.5)
			var points := mark["points"] as PackedVector2Array
			if not Geometry2D.is_point_in_polygon(corner, points):
				ok = _fail(("the %s's mark misses its own corner %s at %.1fpx a tile, so it is a "
						+ "point shape and not the footprint it stands on")
						% [building["kind"], corner, screen._cell])
				break
			if Geometry2D.is_point_in_polygon(at, mark["hole_points"] as PackedVector2Array) == false:
				ok = _fail(("the %s's mark is solid at %s, its own centre: a person standing on this "
						+ "machine is painted out by it (ASSA-203 measured 0.0%% surviving)")
						% [building["kind"], at])
				break
			if not Geometry2D.is_point_in_polygon(at,
					AssayHud.player_mark(at, false)["points"] as PackedVector2Array):
				ok = _fail("a partner's own mark is hollow at its centre too, so the two no longer "
						+ "differ in the way this test says they do")
				break
	# **THE TWO KEYS IT READS WITHOUT A DEFAULT ARE DECLARED AT THE BOUNDARY.** `building_mark` reads
	# `pos` and `footprint` with `[]`, so a binding that stopped sending either empties the frame
	# instead of drawing every factory on the corner (ASSA-196's bill). `AssayScene.SIM_FACTS` is the
	# list `test_sim_binding.gd` asks the RUNNING binding about, and the Rust side holds it too
	# (`every_building_is_listed_with_the_footprint_the_sim_gave_it`).
	if ok:
		for key: String in ["pos", "footprint"]:
			if not (AssayScene.SIM_FACTS["building"] as Array).has(key):
				ok = _fail(("the schematic reads `%s` off a building with no default and "
						+ "AssayScene.SIM_FACTS['building'] does not declare it, so nothing asks "
						+ "the binding whether it is still sent") % key)
				break
	# **AND `_draw` ACTUALLY ASKS FOR THE LIST.** This is the one assertion that fails on the code
	# this item was filed against: before today `_sim.buildings()` appeared once in this file and it
	# was inside the close-up's view dictionary. Blunt on purpose, like
	# `test_sim_binding.gd::test_every_player_fact_main_reads_is_declared`.
	if ok:
		var source := FileAccess.get_file_as_string("res://scripts/main.gd")
		if source == "":
			ok = _fail("could not read res://scripts/main.gd, so nothing was scanned")
		elif not source.contains("_building_marks(_sim.buildings())"):
			ok = _fail("`_building_marks` is never handed `_sim.buildings()` in main.gd, which is "
					+ "ASSA-189 exactly: the mark is right and the schematic still draws no factory")
		elif source.find("_building_marks(_sim.buildings())") \
				< source.rfind("for entry in _sim.players():"):
			# **AND IT IS PAINTED AFTER THE PLAYERS, WHICH IS THE ONE CLAUSE OF THE APPROVED DESIGN MAIN
			# DOES NOT FOLLOW, AND IT IS OPEN ON ASSA-203.** Cove's hand-off and Maren's 17:40 ruling
			# both say deposits -> buildings -> players, so that a person is never hidden by a thing.
			# The measurement is that on this world it costs the other half: the play loop plants on
			# the tile you are STANDING on, so a mark and your body land at the same point TO THE
			# PIXEL, and at the approved `BUILDING_MARK_PX` 16 the diamond is exactly inscribed in a
			# 16px filled square. Gone, not merely dimmed; the keyline's four points clear the body by
			# 2.8px and are MAP_BG on a MAP_BG background. On the demo's own shot at 12px the sim held
			# 2 buildings and the schematic showed 1.
			#
			# **THIS ASSERTION IS THEREFORE A PIN, NOT A RULING.** It holds main at the measured order
			# so a flip is never silent, and it carries the reason either way. If Maren rules for her
			# clause, this test and one line of `_draw` move together -- and the right fix then is a
			# player mark that is not a solid block, which is a change to a read she owns.
			#
			# A SOURCE ORDER AND NOT A CLAIM ABOUT THE ENGINE: `_draw`'s calls happen in the order they
			# are written, which is the one frame-ordering fact in here I do not have to ask about.
			ok = _fail("main.gd paints the building marks BEFORE the players, so a machine on the tile "
					+ "you stand on is covered whole by your own 16px mark -- see ASSA-203, where both "
					+ "orders are photographed at 1x and the ruling is Maren's")
	screen.queue_free()
	return ok


## **EVERY PLAYER THE SCREEN READS GOES THROUGH ONE BOUNDARY** (ASSA-196 boxes 3 and 5).
##
## Five places in `main.gd` read a player's `id` and `pos` with a silent default, so a binding that
## stopped sending `pos` would draw every player on tile (0,0) CONFIDENTLY and put the camera there
## too. The fix is one reader, `_players()`, which refuses the frame rather than the player.
##
## **THIS SCAN IS THE LEG THAT WOULD HAVE CAUGHT THE DEFECT, and the one my own plan would have left
## open.** I had written that the boundary would be `_refresh_world` and the other reads would keep
## their defaults, unreachable behind it -- with the worry that `_my_tile` runs from input handlers,
## so the ordering needed measuring. The ordering was the wrong question: `_my_tile` does not read
## `_refresh_world`'s view, it re-reads `_sim.players()` itself, and so do `_remember_positions` and
## the schematic's own loop. Three readers would have gone on defaulting in any frame order. So what
## is asserted is DATA FLOW: `_sim.players()` may appear in this file only inside `_players()`, and a
## sixth reader added next month reddens this instead of quietly defaulting.
##
## The `.size()` count in the world line is allowed by name: it reads no fact off a player, only how
## many there are, and a count cannot be placed on the wrong tile.
func test_every_player_read_goes_through_the_one_boundary() -> bool:
	var source := FileAccess.get_file_as_string("res://scripts/main.gd")
	if source == "":
		return _fail("could not read res://scripts/main.gd, so nothing was scanned")
	var strays := PackedStringArray()
	for line in source.split("\n"):
		var text := String(line)
		if not text.contains("_sim.players()"):
			continue
		if text.strip_edges().begins_with("#") or text.strip_edges().begins_with("##"):
			continue
		if text.contains("var players: Array = _sim.players()"):
			continue   # the boundary itself
		if text.contains("_sim.players().size()"):
			continue   # a count, not a fact
		strays.append(text.strip_edges())
	if not strays.is_empty():
		return _fail(("%d place(s) in main.gd read `_sim.players()` outside the `_players()` "
				+ "boundary, so they default `pos` to (0,0) on their own and the camera goes to the "
				+ "world's corner: %s") % [strays.size(), String(" | ").join(strays)])
	# AND THE BOUNDARY IS ACTUALLY THE ONE THE READERS CALL, not a function nobody uses -- the
	# ASSA-189 failure, where a correct `_building_marks` was called by nobody for a month.
	if not source.contains("for entry in _players():"):
		return _fail("nothing in main.gd iterates `_players()`, so the boundary is dead code and "
				+ "every player read is somewhere else")
	# AND A REFUSAL BLANKS THE VIEW RATHER THAN DROPPING A BODY (box 5). Asserted as the branch
	# existing in `_refresh_world`, because making the real binding stop sending `pos` is a Rust edit
	# and lives in the lever on the item, not in the suite.
	if not source.contains("if not _player_facts_missing.is_empty():"):
		return _fail("`_refresh_world` does not check for a refusal, so a binding that stopped "
				+ "describing players would draw a world with nobody in it instead of saying so")
	return true


## **THE FACT CHECKER NAMES THE KEY WELL ENOUGH TO ACT ON** (ASSA-196 box 2), in the same words
## `AssayScene.missing_sim_facts` uses, so one vocabulary covers both boundaries.
##
## SWEPT OVER EVERY DECLARED FACT, not just `pos`: the defect was two keys with one shape, and `id`
## is the worse of them -- every player becomes -1, `id == _client.player_id` is false for everyone,
## and the camera follows nobody while the bodies are all still drawn.
func test_a_player_dict_missing_a_fact_is_named_not_defaulted() -> bool:
	var whole := {}
	for key in AssaySimHost.PLAYER_FACTS:
		whole[key] = 0
	if not AssaySimHost.missing_player_facts([whole, whole]).is_empty():
		return _fail("two complete player dicts reported missing facts: %s"
				% [AssaySimHost.missing_player_facts([whole, whole])])
	if not AssaySimHost.missing_player_facts([]).is_empty():
		return _fail("an empty list reported missing facts; a world nobody has joined is not a "
				+ "binding that stopped describing people")
	for key in AssaySimHost.PLAYER_FACTS:
		var broken := whole.duplicate()
		broken.erase(key)
		var said := AssaySimHost.missing_player_facts([whole, broken])
		if said.size() != 1:
			return _fail("erasing `%s` from the second of two players reported %d complaints: %s"
					% [key, said.size(), said])
		var want := "player[1 of 2].%s" % String(key)
		if String(said[0]) != want:
			return _fail(("erasing `%s` is reported as `%s`; it should be `%s` -- the index, the "
					+ "count and the key, which is what `missing_sim_facts` says and what a reader "
					+ "needs to act") % [key, said[0], want])
	return true


## A HOST THAT HANDS THE SCREEN EXACTLY THE PLAYER DICTS IT IS GIVEN.
##
## Subclassed rather than faked, this file's `_RelayThatIsListening` idiom: only `players()` is
## replaced, so the boundary below still runs the real `AssaySimHost.missing_player_facts` over the
## real `PLAYER_FACTS`, and a fact added to that list is covered here without an edit.
class _SimSaying extends AssaySimHost:
	var said: Array

	func _init(players_to_say: Array) -> void:
		said = players_to_say

	func players() -> Array:
		return said


## **THE REFUSAL ITSELF, PRESSED** (ASSA-196, Nerite's mutation at 20:39 EDT).
##
## Changing `_players()`'s `return []` on the refusal path to `return players` reddened NOTHING in a
## 286-test suite. Both legs above are reads: one scans source for who calls the boundary, the other
## asks `missing_player_facts` about dicts without going near `main.gd`. So the suite proved that
## every reader goes through the boundary and never once that the boundary REFUSES -- which is the
## whole claim the `player.get("pos", Vector2i.ZERO)` defaults downstream rest on for being
## unreachable. A boundary that lets a bad dict past is the original defect with one more function in
## front of it.
##
## **THE CONTROL IS IN THE SAME TEST**, because a `_players()` that returned `[]` for every world
## would pass the first half: a complete dict must come back whole and must leave no complaint behind.
func test_a_player_dict_without_pos_makes_the_boundary_refuse_the_frame() -> bool:
	var screen := _screen()
	var ok := true
	var whole := {}
	for key in AssaySimHost.PLAYER_FACTS:
		whole[key] = 0
	# THE CONTROL FIRST, so a refusal below cannot be the only behaviour this function has, and so
	# the complaint counted further down belongs to the broken dict rather than to a dirty screen.
	screen._sim = _SimSaying.new([whole])
	var described: Array = screen._players()
	if described.size() != 1:
		ok = _fail("a complete player dict was refused: `_players()` returned %s" % [described])
	elif not screen._player_facts_missing.is_empty():
		ok = _fail("a complete player dict left a complaint behind: %s"
				% [screen._player_facts_missing])
	var broken: Dictionary = whole.duplicate()
	broken.erase("pos")
	screen._sim = _SimSaying.new([broken])
	if ok and not screen._players().is_empty():
		ok = _fail("a player dict with no `pos` came back out of `_players()`, so every reader "
				+ "downstream defaults it to tile (0,0) and the camera follows it to the corner")
	if ok and screen._player_facts_missing.is_empty():
		ok = _fail("the refusal recorded no `_player_facts_missing`, so `_refresh_world` has nothing "
				+ "to blank the frame on and the screen says a world with nobody in it is normal")
	# **AND THE SCREEN SAYS SO, NAMING THE KEY.** This leg is the one that found the defect: the
	# refusal called `_note`, which BUILDS a Label and returns it for a caller to add, and this caller
	# dropped it -- so the sentence existed in the source and nowhere a player could see it. It goes
	# to the status line now.
	if ok and not screen._status.text.contains("player[0 of 1].pos"):
		ok = _fail("the refusal did not name the key on screen; the status line says '%s'"
				% screen._status.text)
	# **SAID ONCE PER CAUSE, NOT LATCHED ONCE.** Counting repetitions is not available to a test: the
	# sentence goes to a status line that holds one sentence, so a second identical frame leaves no
	# trace either way. What IS observable is the half that can actually rot -- the guard comparing
	# WHAT IS MISSING rather than whether it has ever complained. A latch would leave the screen
	# reporting the first cause while a second, different one went unsaid.
	screen._players()
	var worse: Dictionary = whole.duplicate()
	worse.erase("id")
	screen._sim = _SimSaying.new([worse])
	if ok and not screen._players().is_empty():
		ok = _fail("a player dict with no `id` came back out of `_players()`; every player becomes "
				+ "-1, so `id == _client.player_id` is false and the camera follows nobody")
	if ok and not screen._status.text.contains("player[0 of 1].id"):
		ok = _fail(("a second, different missing fact was not said: the status line still reads "
				+ "'%s'. The guard is latching instead of comparing what is missing")
				% screen._status.text)
	# AND IT RECOVERS. A boundary that refuses for ever after one bad frame would blank a healthy
	# world, which is the same screen the defect produced for the opposite reason.
	screen._sim = _SimSaying.new([whole])
	if ok and screen._players().size() != 1:
		ok = _fail("a whole dict after a refused one was still refused, so one bad frame blanks the "
				+ "screen for good")
	if ok and not screen._player_facts_missing.is_empty():
		ok = _fail("the complaint outlived the problem: %s" % [screen._player_facts_missing])
	screen.queue_free()
	return ok


## **THE HATCH GOES ON BEFORE THE LETTER, WHICH IS THE ONLY THING KEEPING THE LETTER** (ASSA-199
## box 6; Cove's constraint is that the hatch repaints only pixels already inside the disc).
##
## The hatch is `MAP_BG` strokes across the disc's interior and the species letter sits in the middle
## of that interior. Nothing clips the strokes away from the glyph -- `hatch_segments` knows about a
## circle and not about typography -- so what protects the letter is that `_draw` paints it AFTER.
## Swap those two statements and the letter is cut by two dark bars on every dead end, which is 55.1%
## of rocks.
##
## **A SOURCE ORDER, AND IT IS WHY THIS IS NOT A PIXEL TEST.** `_draw`'s statements run in written
## order, which is the one frame-ordering fact in here I do not have to ask the engine about. I also
## tried to measure it on the real shot and could not: glyph-ink pixels inside a hatched disc come
## out within a few per cent of a clean one at the same radius, but the discs carry DIFFERENT LETTERS
## (M, H, N, D, P), and a letter's own pixel count swamps the effect. A control would need the same
## glyph at the same radius with and without the mark. The picture is Maren's box 1.
func test_the_hatch_is_painted_before_the_species_letter() -> bool:
	var source := FileAccess.get_file_as_string("res://scripts/main.gd")
	if source == "":
		return _fail("could not read res://scripts/main.gd, so nothing was scanned")
	# **THE INK NOW COMES OUT OF `AssayHud.MAP_MARKS` AND THE CALL TEXT SAYS SO** (ASSA-206): every
	# colour `_draw` paints with is looked up by the mark's name, which is what lets the map's key be
	# generated from the painter's own table. So the scan looks for the named lookup, and the fact the
	# old literal carried -- that a hatch is in the map's own ground ink -- is asserted on the table
	# itself two lines down rather than inferred from a word in a call.
	if AssayHud.mark_ink(&"dead_end") != AssayHud.MAP_BG:
		return _fail("the dead-end hatch is no longer drawn in the map's own ink: %s"
				% AssayHud.mark_ink(&"dead_end"))
	var hatch_at := source.find(
			"draw_line(strokes[i], strokes[i + 1], AssayHud.mark_ink_of(&\"dead_end\", ink), thick)")
	if hatch_at < 0:
		return _fail("main.gd does not paint `AssayHud.hatch_segments` as lines, so a dead-end rock "
				+ "is drawn exactly like one that pays (ASSA-199 box 2)")
	# **THE LETTER IS NO LONGER IN THE DEPOSIT LOOP AT ALL** (ASSA-213): it is the last mark on the
	# view, after the factories, because a building standing on a deposit was erasing it. That makes
	# this assertion weaker than it was -- the hatch is now four passes rather than six lines ahead of
	# the glyph -- and it stays because the hatch is still the mark that would cut the letter if the
	# two ever swapped, and because this scan is what notices the call going away. The ink now comes
	# out of `_glyph_marks`, which is the function a test can ask what the letter will be painted in.
	var glyph_at := source.find(
			"AssayHud.mark_ink_of(&\"species_glyph\", glyph[\"ink\"]))")
	if glyph_at < 0:
		return _fail("main.gd no longer draws the species letter with `_glyph_marks`' own ink, so "
				+ "this scan cannot say whether the hatch goes under it")
	if hatch_at > glyph_at:
		return _fail("main.gd paints the hatch AFTER the species letter, so every dead end's letter "
				+ "is cut by two bars of MAP_BG -- 55.1% of rocks over Maren's 30 seeds")
	# AND THE FILL IS UNDER BOTH: a hatch painted before the disc it marks is simply invisible.
	var fill_at := source.find("draw_circle(at, radius, AssayHud.mark_ink_of(&\"deposit\", colour))")
	if fill_at < 0 or fill_at > hatch_at:
		return _fail(("main.gd paints the deposit's fill at %d and the hatch at %d: a hatch under "
				+ "its own disc marks nothing") % [fill_at, hatch_at])
	return true


## **A PARTNER ON A LIGHT SPECIES LETTER FUSES WITH IT INTO ONE BLOB** (Maren's second ruling on
## ASSA-189, 17:40; Cove's finding, `assa-193-player-vs-mark-on-a-letter-3x.png` panel 3).
##
## `THEIRS` is a pale near-white (0.75,0.78,0.85) and a player's body carried no rim, so a partner
## standing on a deposit whose letter is drawn in a light ink stopped being a person and became part
## of the glyph. Cove hit the identical failure with a keyline-0 diamond and fixed it with 2px of
## `MAP_BG`; the ruling is that both player marks get the same two lines. **It is a defect that was
## shipping, not polish** -- the one view co-op exists for, failing at telling a person from a rock.
##
## **THE GEOMETRY HALF IS THAT THE RIM GROWS OUTWARDS.** `PLAYER_MARK_PX` is 16 because Maren measured
## the consequence of the old tile-derived size (ASSA-119 box 6), so a rim paid for out of the body
## would quietly re-tune her number. 16 in, 20 out, and your own 1.6x hollow ring is clear of it.
##
## **AND THE WIRING HALF IS A SOURCE SCAN, because nothing headless can read a canvas back.** The
## order matters as much as the call: the rim drawn AFTER the body is a 2px dark frame ON the person,
## which is a different mark and not the ruling. `_draw`'s statements run in written order, so the
## scan is about this file and not about the engine. The picture is `tools/window_shot.gd`'s
## whole-world shot; this is what notices if the call goes away.
func test_both_player_marks_carry_the_maps_own_keyline() -> bool:
	# **BOTH BODIES, AND THEY ARE TWO SHAPES SINCE ASSA-236**, so the rim is measured on each rather
	# than on one rect that used to serve both. The claim is the same one: every point of the body is
	# inside its own rim, and the rim is `MARK_KEYLINE_PX` thick PERPENDICULAR -- which on the
	# diamond means a diagonal grown by `2t*sqrt(2)` and on the cross means every edge moved by `t`.
	var at := Vector2(100.0, 200.0)
	for mine: bool in [true, false]:
		var person: Dictionary = AssayHud.player_mark(at, mine)
		var points: PackedVector2Array = person["points"]
		var rim: PackedVector2Array = person["keyline_points"]
		if rim.size() != points.size():
			return _fail("a %s body is a %d-gon and its rim a %d-gon, so the rim is not its shape"
					% ["player" if mine else "partner", points.size(), rim.size()])
		for point: Vector2 in points:
			if not Geometry2D.is_point_in_polygon(point, rim):
				return _fail(("a %s body reaches %s, outside its own keyline: the rim is being paid "
						+ "for out of a size Maren set from a measurement")
						% ["player" if mine else "partner", point])
		# **THE THICKNESS, OFF THE POLYGON AND NOT OFF THE CONSTANT -- AND THE TWO SHAPES CONVERT
		# DIFFERENTLY, WHICH IS THE WHOLE POINT OF MEASURING IT.** The gap at the top vertex is the
		# diagonal's growth on a diamond, so the PERPENDICULAR rim is that over sqrt(2); on the
		# cross every edge is axis-aligned and the gap is the rim. Writing the diamond's number as
		# if it were the rim is the `span + 4` mistake ASSA-193 caught, one shape along.
		# (The gap is read on the Y axis, not as a distance between the two first vertices: on the
		# cross that vertex is a CORNER of the top arm and moves diagonally, so a distance there
		# reports 2.83 for a 2px rim. The edge it sits on moves by exactly the rim.)
		var vertex_gap := absf(points[0].y - rim[0].y)
		var gap := vertex_gap / sqrt(2.0) if mine else vertex_gap
		if absf(gap - AssayHud.MARK_KEYLINE_PX) > 0.01:
			return _fail(("a %s body's rim is %.2fpx thick where it should be %.2f")
					% ["player" if mine else "partner", gap, AssayHud.MARK_KEYLINE_PX])
	# CLEAR OF YOUR OWN RING, which is 1.6x the body drawn hollow at 2px. Both are diamonds now, so
	# the distance that matters is to the EDGE and not to the point: the ring's edge sits at
	# 12.8/sqrt(2) = 9.05px from the centre and the rim's at 7.66. Two marks that met would read as
	# one thick frame, and on the old square ring this margin was 1.8px rather than 1.4.
	var ring_inner := AssayHud.PLAYER_MARK_PX * 0.8 / sqrt(2.0) - 1.0
	var rim_edge := (AssayHud.PLAYER_MARK_PX * 0.5 + AssayHud.MARK_KEYLINE_PX * sqrt(2.0)) / sqrt(2.0)
	if rim_edge >= ring_inner:
		return _fail(("the keyline reaches %.1fpx from a player's centre and your own ring's inner "
				+ "edge is at %.1fpx: they would meet and read as one frame") % [rim_edge, ring_inner])
	var source := FileAccess.get_file_as_string("res://scripts/main.gd")
	if source == "":
		return _fail("could not read res://scripts/main.gd, so nothing was scanned")
	# THE RIM'S INK IS LOOKED UP BY THE MARK'S NAME NOW (ASSA-206), so the scan names the lookup and
	# the ink is checked against the table -- which is the stronger half: the old scan would have been
	# satisfied by the word `MAP_BG` in a call that drew something else.
	if AssayHud.mark_ink(&"player_keyline") != AssayHud.MAP_BG:
		return _fail("a player's keyline is no longer the map's own ink: %s"
				% AssayHud.mark_ink(&"player_keyline"))
	if AssayHud.mark_ink(&"partner_keyline") != AssayHud.MAP_BG:
		return _fail("a partner's keyline is no longer the map's own ink: %s"
				% AssayHud.mark_ink(&"partner_keyline"))
	var call_at := source.find(
			"AssayHud.mark_ink(&\"player_keyline\" if mine else &\"partner_keyline\"))")
	if call_at < 0:
		return _fail("no player mark in main.gd draws `player_mark`'s keyline polygon in MAP_BG, so a "
				+ "partner on a light species letter still fuses with it (Maren's ASSA-189 ruling 2)")
	# **UNDER THE BODY AND NOT OVER IT.** Both bodies: one `draw_colored_polygon` serves MINE and
	# THEIRS, so the rim is on the partner by construction rather than by a second call.
	var body_at := source.find(
			"AssayHud.mark_ink_of(&\"player_mine\" if mine else &\"player_theirs\", colour))")
	if body_at < 0:
		return _fail("main.gd no longer paints a player body as one polygon of the mark's own ink, so "
				+ "this scan cannot say whether the keyline is under it")
	if call_at > body_at:
		return _fail("main.gd draws the player keyline AFTER the body, which is a dark frame ON the "
				+ "person rather than a rim behind them")
	return true


## **A BUILDING MARK MAY NOT ERASE THE SPECIES LETTER IT STANDS ON** (ASSA-213, Maren's P1 and her
## ruling; the pictures are hers, at 1x on two seeds, `shared/assay/maren-assa206-coop/`).
##
## WHY THIS IS THE NORMAL CASE AND NOT AN UNLUCKY TILE: `sim/src/step.rs` lets a building stand on a
## deposit -- Place checks bounds, occupancy and reach and nothing else -- and a drill is on the rock
## it mines by definition. The letter is how this view names ore (ASSA-73), so the mark was taking a
## read away to add one.
##
## **THE PREMISE IS MEASURED FIRST, because a test about a mark covering a letter on a world where it
## does not is green for the wrong reason.** The diamond and the letter's box come out of the real
## `_building_marks` and `_glyph_marks` at the real screen's `_cell`, and the overlap is sampled on a
## 1px grid. If the two do not overlap, this fails as a broken instrument.
##
## WHAT IT CANNOT SEE: ink. Nothing headless rasterises a glyph, so "the letter is still legible" is
## the 1x window shot in the item. The two legs here are the ORDER (a source scan, because `_draw`'s
## statements run in written order) and the BED (the colour the ink was picked against travels with
## the letter, so the order is safe over a mark as well as over a rock).
##
## **ASSA-314 NARROWED WHAT THIS GUARDS AND I SAY SO HERE RATHER THAN LEAVE IT LOOKING UNTOUCHED.**
## Maren ruled on 2026-10-08 that a tile carrying a building mark gets **no species letter at all**:
## her census says a drill's 16x16 hole is 56.2% letter and 0 of 26 capitals fit it, so ASSA-213's
## remedy — paint the letter LAST, over the machine — was saving a letter into a hole it could never
## fit. On the shipped frame the case this test plants **cannot occur**: `_glyph_marks` is handed the
## sim's buildings and suppresses that letter.
##
## So the COVERAGE leg below now measures a collision the player never sees, and it is kept on
## purpose, as the arithmetic behind the newer ruling: if a mark and a letter ever stop landing on
## each other, 314's suppression is deleting a letter for nothing and this is what notices. The
## ORDER and BED legs are undiminished — they hold every letter that IS drawn, which is every letter
## on a tile nobody built on. `test_a_letter_is_not_drawn_on_a_tile_a_machine_stands_on` holds 314.
func test_a_building_on_a_deposits_centre_cannot_erase_the_species_letter() -> bool:
	var screen := _joined_screen()
	screen._show_close_up(false)
	screen._refresh()
	var ok := true
	if screen._close_up or not screen._sim.running() or screen._cell <= 0.0:
		screen.queue_free()
		return _fail(("premise: close_up %s, running %s, cell %f -- `_draw` returns before any mark "
				+ "on any of those") % [screen._close_up, screen._sim.running(), screen._cell])
	var font := ThemeDB.fallback_font
	var marks: Array = screen._glyph_marks(screen._sim.deposits(), font)
	if marks.is_empty():
		screen.queue_free()
		return _fail("the schematic paints no species letter on this world, so there is nothing for "
				+ "a building to erase and this test is about nothing")
	# The deposit the mark belongs to, and a 1x1 machine planted on its CENTRE tile -- the tile the
	# play loop plants on, and the one Maren's shots caught.
	var glyph: Dictionary = marks[0]
	# **THE TILE THE MARK NAMES, NOT A TILE RECOVERED FROM ITS PIXEL** (ASSA-220 box 3). This read
	# `round((at - MARGIN) / _cell)`, which was exact for exactly as long as `at` was the tile's CORNER.
	# Now that it is the middle, `(at - MARGIN) / _cell` is `tile + 0.5` and `round()` takes it UP: this
	# test would have planted its machine one tile down and right of the letter and then failed on the
	# coverage assertion, reporting the case as absent rather than reporting the move. `tile` exists on
	# the mark for this (ASSA-213 box 2).
	var tile: Vector2i = glyph["tile"]
	var planted := [{"pos": tile, "footprint": Vector2i(1, 1), "kind": "machine"}]
	var mark: Dictionary = (screen._building_marks(planted)[0] as Dictionary)
	var outline: PackedVector2Array = mark["points"]
	var hole: PackedVector2Array = mark["hole_points"]
	var box: Rect2 = glyph["box"]
	# SAMPLED ON A 1px GRID, NOT REASONED, AND THE FRACTION IS THE MARK'S AND NOT THE BOX'S. The
	# box is the font's whole line box -- ascent, descent and advance -- so the share of IT a 16px
	# mark covers is small however completely the letter is destroyed. What the defect is about is
	# where the mark lands: all of it, on the middle of the letter.
	#
	# **THE SAMPLE IS THE FRAME AND NOT ITS BOX SINCE ASSA-236.** The mark is hollow, so counting its
	# bounding box would report ink that is not painted -- and the hole is most of it.
	var mark_px := 0
	var on_letter := 0
	var bounds := Rect2(outline[0], Vector2.ZERO)
	for point in outline:
		bounds = bounds.expand(point)
	var y := bounds.position.y
	while y <= bounds.end.y:
		var x := bounds.position.x
		while x <= bounds.end.x:
			var point := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(point, outline) \
					and not Geometry2D.is_point_in_polygon(point, hole):
				mark_px += 1
				if box.has_point(point):
					on_letter += 1
			x += 1.0
		y += 1.0
	var covered := float(on_letter) / float(maxi(mark_px, 1))
	# **THIS FLOOR WAS 0.8 AND ASSA-293 MOVED THE GEOMETRY UNDER IT, so the number is amended rather
	# than the premise quietly dropped.** Holding the letter at the size that fits the smallest patch
	# takes this deposit's letter from 32 px to 25, and its line box from 25x35 to 23x27 -- so a 20 px
	# frame on the same tile now lands 72.4% inside the box instead of clearing 80%. The collision is
	# not smaller in kind (the mark is still on the middle of the letter, which is what the paint
	# order below is about); the BOX shrank around it, and most of a hollow frame's ink is on its
	# perimeter, which is exactly where a smaller box cuts. The floor goes to 0.65: still high enough
	# that a letter and a mark drifting apart fails here, and not pinned to 72.4, because the box's
	# height is a font metric (`get_ascent`) and a font change would move it without moving anything
	# this test is about.
	if covered < 0.65:
		ok = _fail(("a machine on the deposit's own centre tile %s puts %.1f%% of its frame (%d of "
				+ "%d sampled px) inside the letter's box %s: the case this item is about is not in "
				+ "this test") % [tile, covered * 100.0, on_letter, mark_px, box])
	# **THE ORDER.** The one assertion that fails on the code this item was filed against: the letter
	# was painted in the deposit loop, four passes before the factories.
	if ok:
		var source := FileAccess.get_file_as_string("res://scripts/main.gd")
		var glyph_at := source.find("AssayHud.mark_ink_of(&\"species_glyph\", glyph[\"ink\"]))")
		var building_at := source.find("AssayHud.mark_ink_of(&\"building\", shape[\"colour\"])")
		if source == "" or glyph_at < 0 or building_at < 0:
			ok = _fail(("main.gd does not paint both the species letter (%d) and a building mark "
					+ "(%d) through the map's table, so this scan says nothing")
					% [glyph_at, building_at])
		elif glyph_at < building_at:
			ok = _fail(("main.gd paints the species letter BEFORE the building marks, so the %.1f%% "
					+ "of a machine diamond that lands on the letter is painted over it -- and a drill is on a "
					+ "deposit by definition") % [covered * 100.0])
		# **AND THE BUILDING MARKS GO IN WITH THEM** (ASSA-218 box 9). This read
		# `_glyph_marks(deposits, font)` and my box-9 change broke it, correctly: the call grew a
		# third argument. Pinning the new form is strictly stronger, because `bedded` is decided from
		# those marks — handed `[]`, a LAPPED letter reports `bedded: false` and the expensive bed is
		# silently never drawn on the one letter it exists for. (It said "every letter" until box 9
		# was amended to `lapped OR hatched`: a hatched letter is bedded with no buildings at all,
		# which is the half of the ruling that does not depend on this argument.) `shapes` and not
		# `_building_marks(...)` inline, so the same list reaches both passes in one frame.
		elif not source.contains("_glyph_marks(deposits, font, shapes, _sim.buildings())"):
			ok = _fail("`_glyph_marks` is not handed the deposits, the building marks `_draw` read "
					+ "AND the sim's buildings, which is ASSA-189's shape: a correct mark that "
					+ "nothing paints, since box 9 a correct mark nothing beds, and since ASSA-314 "
					+ "a letter drawn in a machine's hole because the painter was never told a "
					+ "machine stands there")
	# **THE BED, which is what makes painting last safe.** `glyph_color` picks the ink by contrast
	# against the DISC; over a pale `HOVER` diamond a `GLYPH_LIGHT` letter chosen for a dark rock is
	# the same letter gone. So the ink must be the one picked for the bed it carries.
	if ok:
		for entry in marks:
			var each: Dictionary = entry
			if AssayHud.glyph_color(each["bed"] as Color) != each["ink"]:
				ok = _fail(("a letter is painted in %s on a bed of %s, and the ink picked for that "
						+ "bed is %s: the bed is not the surface the contrast was measured on")
						% [each["ink"], each["bed"], AssayHud.glyph_color(each["bed"] as Color)])
				break
			if float(each["bed_px"]) < 1.0:
				ok = _fail("a letter carries a bed %.1fpx wide, which is no bed at all"
						% [each["bed_px"] as float])
				break
	# **AND THE BED IS A COLOUR OFF THE DISC TABLE, NOT ONE THE PAINTER CHOSE.** This is what makes
	# `hud.gd`'s "on an unoccupied disc the bed is invisible by construction" true, and it is the
	# sentence a bed of any other colour would break: a bed that is merely DARK would pass the ink
	# check above on every light-ink letter and paint a rim on all thirteen.
	#
	# WHY THIS IS NOT THE CHECK ABOVE IN A SECOND COSTUME, and it took three levers to show it. I
	# expected `"bed": Color.BLACK` to slip past the suite; it reddened the INK check, because seed
	# 777042 carries dark-ink letters whose verdict a black bed flips. So did `lightened(0.25)`. The
	# lever that separates the two is the realistic regression -- the bed nudged **3% darker, alpha
	# held at 1**, which preserves every ink verdict on this world and so is invisible above:
	# 336 passed, 1 failed, and the one failure is this assertion by name. The check above is strong
	# here by accident of the seed holding both ink kinds; this one is not.
	if ok:
		var table := {}
		for raw in screen._sim.deposits():
			var deposit: Dictionary = raw
			table[AssayHud.deposit_color(int(deposit["species"]), int(deposit["purity"]))] = true
		if table.is_empty():
			ok = _fail("premise: this world has no deposits, so there is no disc table to check the "
					+ "bed colours against and this assertion measures nothing")
		else:
			for entry in marks:
				var each: Dictionary = entry
				if not table.has(each["bed"] as Color):
					ok = _fail(("a letter's bed is %s, which is no deposit's fill on this world: the "
							+ "bed is the disc's own colour or it is a new mark on every disc that "
							+ "has no building on it") % [each["bed"]])
					break
	# AND THE REASON THIS DEPOSIT IS A CASE AT ALL, as a number rather than as a sentence: the ink
	# this world actually picked, read against the diamond it now sits on.
	#
	# **`on_bed` IS THE NOMINAL BED, NOT THE BED AS DRAWN, AND THE DIFFERENCE IS LARGE** (ASSA-218).
	# `glyph["bed"]` is a colour out of the table; every bed copy is an antialiased `draw_string`, so
	# the pixels beside the ink are a blend. On seed 777042's light-ink case the nominal figure here
	# is 9.20:1 and the drawn bed measures **4.35:1** -- below the 4.5 floor. So this is a PREMISE
	# CHECK ("a bed could help this letter"), not a measurement of what a reader gets, and it must
	# never be quoted as one. The drawn figure comes from a real window:
	# `shared/assay/marlow-assa218-bedclaim/` (three arms, the bed levered out).
	if ok:
		var on_mark := AssayHud.contrast_ratio(glyph["ink"] as Color, AssayHud.HOVER)
		var on_bed := AssayHud.contrast_ratio(glyph["ink"] as Color, glyph["bed"] as Color)
		if on_bed <= on_mark:
			ok = _fail(("this deposit's letter reads %.2f:1 on its NOMINAL bed and %.2f:1 on the "
					+ "building mark, so even in the colour table the bed buys nothing here and the "
					+ "case needs a different deposit") % [on_bed, on_mark])
	screen.queue_free()
	return ok


## **A LETTER CARRIES THE EIGHT-STAMP BED WHEN A MARK LAPS IT OR A HATCH CROSSES IT** (ASSA-218 box
## 9 as Maren AMENDED it at 13:00 EDT, having measured my priced alternative rather than ruling on
## it). Box 9 first shipped as *lapped only*, and her measurement is that this kept the bed on the
## one letter never at risk and stripped it from the eight that are: the stamps are worth **1.16 to
## 2.43 ratio points** on every hatched disc of seed 777042 and **+1.55** on the lapped one.
##
## **IT IS A REWRITE AND NOT A NEW TEST BECAUSE NERITE DELETED THE WHOLE DECISION AND NOTHING WENT
## RED.** Their 12:34 arm turned `if bool(glyph["bedded"]):` into `if false:` and the suite stayed
## 342/0. The bed's other tests read the ink mask and the fixture -- box 3 calls it a FIXTURE in
## those words -- and none of them reads this fact, so `bedded` could be set any way at all, or not
## used, with the suite green both times. Maren asked that the widening and its guard ship together,
## for the honest reason that a rule nothing asserts is a comment.
##
## **THE THREE CASES THE RULING NAMES, ALL PRESENT IN THIS FRAME** (seed 777042, the fixture's own
## seed and the seed every number on ASSA-218 was measured on -- 13 letters, 8 hatched, read out of
## `tools/schematic_disc_table.gd` before this was written, not assumed):
##
## ```
## unlapped + hatched    8 letters   bedded      <- the case box 9 as built stripped
## lapped   + unhatched  1 letter    bedded      <- disc 9, the only one it kept
## unlapped + unhatched  4 letters   NOT bedded  <- Maren's zero-footprint control
## ```
##
## **THE MACHINE IS PLANTED ON AN UNHATCHED LETTER ON PURPOSE.** It is the case the two halves of the
## rule disagree about; planted on a hatched one, "lapped" would change nothing observable and the
## lapped half of the rule would be unguarded while looking covered.
##
## **HATCHEDNESS COMES FROM THE SIM, NOT FROM `deposit_disc`.** The painter asks `deposit_disc`; this
## asks the deposit's own `reach_note` ("nothing can get this ore out"). Asking the same helper would
## make the comparison `x == x` -- the vacuity I have shipped twice this week.
##
## WHAT IT GUARDS, by mutation: `bedded` back to lapped-only fails on the eight hatched letters;
## `bedded = true` everywhere fails on the four controls; dropping the `letter_occlusions` loop fails
## on the planted letter; handing `_glyph_marks` no buildings fails the same way, which is what a
## caller forgetting the third argument does -- `window_shot.gd` being the caller that would
## otherwise photograph a map nobody drew.
##
## **WHAT IT STILL CANNOT SEE, AND NOTHING HEADLESS CAN:** whether `_draw` paints the stamps it is
## told to. Nothing counts draw calls, which is exactly why the decision was published as a fact on
## the mark. Nerite's `if false:` arm lives in that gap. The only cover for it is a 1x picture, so
## `window_shot.gd`'s marks table now reports `bedded` per letter -- the painter's own answer, beside
## the frame, for Maren's `disc02/05/12` arms to be checked against.
func test_a_letter_is_bedded_when_a_mark_laps_it_or_a_hatch_crosses_it() -> bool:
	var screen := _joined_screen()
	screen._show_close_up(false)
	screen._refresh()
	if screen._close_up or not screen._sim.running() or screen._cell <= 0.0:
		screen.queue_free()
		return _fail(("premise: close_up %s, running %s, cell %f -- `_draw` returns before any mark")
				% [screen._close_up, screen._sim.running(), screen._cell])
	var font := ThemeDB.fallback_font
	var deposits: Array = screen._sim.deposits()
	# **THE SIM'S OWN ANSWER FOR WHICH ROCKS ARE DEAD ENDS**, keyed by the tile a letter names, so the
	# expectation below is derived from the world and not from the helper the painter reads.
	var dead_end := {}
	for raw in deposits:
		var deposit: Dictionary = raw
		dead_end[deposit["center"]] = not String(deposit["reach_note"]).is_empty()
	var bare: Array = screen._glyph_marks(deposits, font)
	if bare.size() < 2:
		screen.queue_free()
		return _fail(("premise: this world paints %d species letter(s); two are needed so that the "
				+ "rule has something to separate") % bare.size())
	# THE FIRST UNHATCHED LETTER, for the reason in the docstring: a machine on a hatched letter
	# would be bedded either way and the lapped half of the rule would go untested.
	var target := {}
	for raw in bare:
		var glyph: Dictionary = raw
		if not bool(dead_end.get(glyph["tile"], false)):
			target = glyph
			break
	if target.is_empty():
		screen.queue_free()
		return _fail(("premise: all %d letters in this world are hatched, so every one of them is "
				+ "bedded by the hatch alone and planting a machine proves nothing") % bare.size())
	var planted := [{"pos": target["tile"], "footprint": Vector2i(1, 1), "kind": "machine"}]
	var shapes: Array = screen._building_marks(planted)
	var marks: Array = screen._glyph_marks(deposits, font, shapes)
	if marks.size() != bare.size():
		screen.queue_free()
		return _fail(("passing buildings changed the letter COUNT, %d -> %d: `bedded` must change "
				+ "which letters are expensive, never which letters exist")
				% [bare.size(), marks.size()])
	# WHO IS LAPPED IS `letter_occlusions`' ANSWER, NOT MINE. Asserting "the target and no other"
	# would bake in the assumption that one machine laps exactly one letter, which two deposits
	# sharing a tile would break -- so the expectation is read from the function the painter reads.
	var lapped := {}
	for raw in AssayHud.letter_occlusions(shapes, marks):
		lapped[int((raw as Dictionary)["letter"])] = true
	# THE THREE CLASSES, COUNTED BEFORE ANYTHING IS ASSERTED. A frame missing one of them makes the
	# corresponding half of the rule vacuous, and this test's whole purpose is that the rule is
	# asserted rather than described.
	var hatched_unlapped := 0
	var lapped_any := 0
	var plain := 0
	for j in marks.size():
		var glyph: Dictionary = marks[j]
		var hatched := bool(dead_end.get(glyph["tile"], false))
		if lapped.has(j):
			lapped_any += 1
		elif hatched:
			hatched_unlapped += 1
		else:
			plain += 1
	if lapped_any == 0 or hatched_unlapped == 0 or plain == 0:
		screen.queue_free()
		return _fail(("premise: this frame holds %d lapped, %d unlapped-hatched and %d plain "
				+ "letters, and the ruling names all three. A zero makes that case vacuous.")
				% [lapped_any, hatched_unlapped, plain])
	var ok := true
	for j in marks.size():
		var glyph: Dictionary = marks[j]
		var bedded := bool(glyph["bedded"])
		var hatched := bool(dead_end.get(glyph["tile"], false))
		var want := lapped.has(j) or hatched
		if bedded != want:
			ok = _fail(("letter %d (`%s`, tile %s) reports bedded=%s; it is lapped=%s and "
					+ "hatched=%s, so the rule says %s. A hatch and a white letter can be the same "
					+ "white -- 1.00:1, no edge at all -- and the stamps are what hold them apart; "
					+ "a plain letter sits on the disc its ink was picked against and needs none.")
					% [j, glyph["symbol"], glyph["tile"], bedded, lapped.has(j), hatched, want])
			break
	# AND THE SAVING STILL EXISTS, AS A NUMBER RATHER THAN AS A CLAIM: eight stamps per bedded
	# letter. The widening spends more than lapped-only did and must still spend less than all.
	if ok:
		var paid := (lapped_any + hatched_unlapped) * AssayHud.GLYPH_BED_STAMPS.size()
		var everything := marks.size() * AssayHud.GLYPH_BED_STAMPS.size()
		if paid >= everything:
			ok = _fail("the bed costs %d draw calls and stamping every letter costs %d: no saving"
					% [paid, everything])
	# AND WITH NO BUILDINGS PASSED, THE HATCHED LETTERS ARE STILL BEDDED AND NOTHING ELSE IS -- the
	# default-argument path every other caller takes. Before the amendment this case was "no stamps
	# at all", which is the half of the ruling Maren measured as wrong.
	if ok:
		for entry in bare:
			var glyph: Dictionary = entry
			var hatched := bool(dead_end.get(glyph["tile"], false))
			if bool(glyph["bedded"]) != hatched:
				ok = _fail(("with no buildings, letter `%s` (tile %s) reports bedded=%s and the sim "
						+ "says hatched=%s. The hatch is a property of the rock, so it decides the "
						+ "bed whether or not anything is standing on the map.")
						% [glyph["symbol"], glyph["tile"], glyph["bedded"], hatched])
				break
	screen.queue_free()
	return ok


## **A SPECIES LETTER IS NOT DRAWN AT ALL ON A TILE A MACHINE STANDS ON** (ASSA-314, Maren ruled
## option 1 at 16:38 EDT: *no species letter on a tile carrying a building mark*).
##
## **BOTH HALVES, AND THE SECOND IS THE ONE THAT MATTERS.** Her ruling names a SIM fact —
## `machines_on_letters`, a footprint holding the tile a letter is drawn on. The obvious wrong helper
## is `letter_occlusions`, a PIXEL lap, which at the shipped numbers (a 20 px mark, a 23x27 cap box,
## a 9 px cell) reaches **two tiles away**. A build on that one would delete the letters of deposits
## nothing is standing on, and *a patch whose centre is free keeps its letter* is the whole clause.
##
## So the control is not "some other letter survives": it is a letter that **`letter_occlusions`
## says IS lapped** and `machines_on_letters` says is not. That letter must still be drawn. If the
## two helpers ever stop disagreeing at this distance the test says so as a stale premise rather
## than passing on a control that controls nothing.
func test_a_letter_is_not_drawn_on_a_tile_a_machine_stands_on() -> bool:
	var screen := _joined_screen()
	screen._show_close_up(false)
	screen._refresh()
	if screen._close_up or not screen._sim.running() or screen._cell <= 0.0:
		screen.queue_free()
		return _fail(("premise: close_up %s, running %s, cell %f -- `_draw` returns before any mark")
				% [screen._close_up, screen._sim.running(), screen._cell])
	var font := ThemeDB.fallback_font
	var deposits: Array = screen._sim.deposits()
	var bare: Array = screen._glyph_marks(deposits, font)
	if bare.is_empty():
		screen.queue_free()
		return _fail("premise: this world paints no species letter, so none can be suppressed")
	var home: Vector2i = (bare[0] as Dictionary)["tile"]
	var symbol := String((bare[0] as Dictionary)["symbol"])

	# HALF ONE: a machine standing on that very tile. The letter must be gone.
	var on_it := [{"pos": home, "footprint": Vector2i(1, 1), "kind": "machine"}]
	var shapes: Array = screen._building_marks(on_it)
	var after: Array = screen._glyph_marks(deposits, font, shapes, on_it)
	if after.size() != bare.size() - 1:
		screen.queue_free()
		return _fail(("a machine on tile %s left %d letters and the bare frame had %d: exactly one "
				+ "letter (`%s`) stands on an occupied tile, so exactly one must go. Her census: a "
				+ "drill's 16x16 hole is 56.2%% species letter, and 0 of 26 capitals fit it.")
				% [home, after.size(), bare.size(), symbol])
	for glyph_entry in after:
		if (glyph_entry as Dictionary)["tile"] == home:
			screen.queue_free()
			return _fail(("letter `%s` is still drawn on tile %s with a machine standing on it. The "
					+ "mark is hollow so the ROCK shows through it (ASSA-236); a letter in the hole "
					+ "is the thing the hollowness was bought for, gone.") % [symbol, home])

	# HALF TWO: THE CONTROL. Two tiles away, where the two helpers disagree.
	var near := home + Vector2i(2, 0)
	var beside := [{"pos": near, "footprint": Vector2i(1, 1), "kind": "machine"}]
	var near_shapes: Array = screen._building_marks(beside)
	# **THE LAP IS MEASURED ON `bare`, THE FRAME WITH NO SUPPRESSION IN IT.** Measuring it on the
	# suppressed frame makes this premise circular: a build on `letter_occlusions` deletes that very
	# letter, so the lap "disappears" and the premise reports a geometry change that never happened.
	# It cost me one lever run to notice, which is what levers are for.
	var laps := false
	for raw in AssayHud.letter_occlusions(near_shapes, bare):
		if int((raw as Dictionary)["letter"]) == 0:
			laps = true
	if not laps:
		screen.queue_free()
		return _fail(("premise: a machine two tiles from letter `%s` no longer LAPS it, so this "
				+ "control cannot catch a build on `letter_occlusions`. Re-measure the reach: it "
				+ "was two tiles at a 20 px mark and a 23x27 cap box on a 9 px cell.") % [symbol])
	var kept: Array = screen._glyph_marks(deposits, font, near_shapes, beside)
	screen.queue_free()
	if kept.size() != bare.size():
		return _fail(("a machine two tiles away at %s deleted a letter: %d letters, not %d. "
				+ "`letter_occlusions` laps that letter and `machines_on_letters` does not, and the "
				+ "ruling is the second one -- a patch whose centre is free keeps its letter.")
				% [near, kept.size(), bare.size()])
	return true


## **THE BED YIELDS TO THE BAND IT LAPS, AND THE LETTER'S OWN INK DOES NOT** (ASSA-273 box 3, Maren's
## ruling 2026-10-08 13:29: *"take the band-only arm"*, under the §11.39 she wrote the same night —
## **where two marks overlap, the keyline yields and the ink does not**).
##
## **WHY THE BED AND NOT THE LETTER.** On real co-op frames a drill standing on its own deposit centre
## keeps **13.2%** of its band's own ink on seed 777042 and 62.5% on 63, and two of the four sides hold
## no pixel of the mark at all — a band is a shape, so the statistic is its longest unbroken run. What
## took it is not mostly the letter: **65.3% of that band is the letter's BED**, a halo in the disc's
## colour stamped eight ways under the strokes (ASSA-218 box 9). A bed is a separator; a machine's
## band has been its whole identity since ASSA-236, so the separator is what gives way.
##
## **AND MAREN REFUSED MY `GLYPH_DARK` CONDITION WITH A SWEEP, WHICH IS WHY NOTHING HERE BRANCHES ON
## INK.** Over all 600 disc states `glyph_color` picks `GLYPH_LIGHT` **342 times (57.0%)**, which is
## **1.12:1** on a 242 band, and in **222/600 (37.0%) no single ink clears 3:1 against both its disc
## and the band**. So the fusion I measured on 777042 is the common case, not that seed, and a letter
## cannot be whole on an occupied tile whatever the bed does. She ruled the design call — the machine
## wins the overlap — and the leftover letter is ASSA-314, hers.
##
## **TWO LEGS, BECAUSE NOTHING HEADLESS RASTERISES A GLYPH.**
##
## 1. **THE DATA.** `lapped_by` must name exactly the buildings `letter_occlusions` says lap that
##    letter, and be a valid index into the shapes the painter was handed — the painter indexes
##    `shapes[...]` with it, so a stale index is a crash in `_draw` and not a wrong picture. `bedded`
##    is one bit and the bed's price is PER BUILDING, which is the whole reason this field exists.
## 2. **THE ORDER**, by a source scan, because `_draw` cannot be asked what it painted: the bed's
##    stamps, then the band restored over them, then the letter's strokes. Move the re-stroke after
##    the letter and the machine wins a band the letter no longer crosses; move it before the bed and
##    the bed paints over it again, which is the defect.
func test_a_letters_bed_yields_to_the_band_it_laps_and_its_ink_does_not() -> bool:
	var screen := _joined_screen()
	screen._show_close_up(false)
	screen._refresh()
	if screen._close_up or not screen._sim.running() or screen._cell <= 0.0:
		screen.queue_free()
		return _fail(("premise: close_up %s, running %s, cell %f -- `_draw` returns before any mark")
				% [screen._close_up, screen._sim.running(), screen._cell])
	var font := ThemeDB.fallback_font
	var deposits: Array = screen._sim.deposits()
	var bare: Array = screen._glyph_marks(deposits, font)
	if bare.is_empty():
		screen.queue_free()
		return _fail("premise: this world paints no species letter, so nothing can lap one")
	# A machine on the first letter's own tile: the case the item is about, and the one the ruling
	# is about. Which letters it ends up lapping is `letter_occlusions`' answer, never mine.
	var planted := [{"pos": (bare[0] as Dictionary)["tile"], "footprint": Vector2i(1, 1),
			"kind": "machine"}]
	var shapes: Array = screen._building_marks(planted)
	var marks: Array = screen._glyph_marks(deposits, font, shapes)
	var want := {}
	for raw in AssayHud.letter_occlusions(shapes, marks):
		var lap: Dictionary = raw
		var j := int(lap["letter"])
		if not want.has(j):
			want[j] = []
		(want[j] as Array).append(int(lap["building"]))
	if want.is_empty():
		screen.queue_free()
		return _fail(("premise: a machine planted on letter 0's own tile %s laps no letter at all, "
				+ "so this frame holds none of the case the ruling is about")
				% [(bare[0] as Dictionary)["tile"]])
	var ok := true
	var unlapped := 0
	for j in marks.size():
		var glyph: Dictionary = marks[j]
		if not glyph.has("lapped_by"):
			ok = _fail(("letter %d (`%s`) carries no `lapped_by`, so the painter cannot know WHICH "
					+ "frame to give its band back. `bedded` is one bit and the bed's price is per "
					+ "building: 65.3%% of a drill's band is bed on seed 777042.")
					% [j, glyph["symbol"]])
			break
		var got: Array = glyph["lapped_by"]
		var expected: Array = want.get(j, [])
		if got != expected:
			ok = _fail(("letter %d (`%s`, tile %s) reports lapped_by=%s and `letter_occlusions` says "
					+ "%s. The painter re-strokes exactly these frames' bands over the bed, so a "
					+ "wrong list restores a band that was never covered or leaves a covered one "
					+ "buried.") % [j, glyph["symbol"], glyph["tile"], got, expected])
			break
		if got.is_empty():
			unlapped += 1
		for raw_index in got:
			var index := int(raw_index)
			if index < 0 or index >= shapes.size():
				ok = _fail(("letter %d names building %d and the painter was handed %d shapes. "
						+ "`_draw` indexes `shapes[...]` with this, so a stale index is a crashed "
						+ "frame, not a wrong one.") % [j, index, shapes.size()])
				break
	# **THE CONTROL, and without it "every letter is lapped" would pass this.** A letter nothing
	# stands on must keep an EMPTY list: the bed is ASSA-218's and it only yields where a band is
	# underneath it.
	if ok and unlapped == 0:
		ok = _fail(("premise: every one of the %d letters in this frame is lapped, so an empty "
				+ "`lapped_by` is never exercised and the bed could be yielding everywhere")
				% marks.size())
	# **LEG 2: THE ORDER, WHICH IS THE WHOLE RULING AND WHICH NO DICTIONARY CAN CARRY.**
	if ok:
		var source := FileAccess.get_file_as_string("res://scripts/main.gd")
		var bed_at := source.find("AssayHud.mark_ink_of(&\"species_bed\", glyph[\"bed\"])")
		var band_at := source.find("AssayHud.mark_ink_of(&\"building\", lapped[\"colour\"])")
		var ink_at := source.find("AssayHud.mark_ink_of(&\"species_glyph\", glyph[\"ink\"])")
		if source == "" or bed_at < 0 or band_at < 0 or ink_at < 0:
			ok = _fail(("main.gd's glyph pass does not paint all three of the bed (%d), the lapped "
					+ "band (%d) and the letter's ink (%d) through the map's table, so this scan "
					+ "says nothing") % [bed_at, band_at, ink_at])
		elif not (bed_at < band_at and band_at < ink_at):
			ok = _fail(("the glyph pass paints bed@%d, lapped band@%d, letter@%d and the ruling is "
					+ "bed, then band, then letter. Band before the bed and the halo buries it "
					+ "again; band after the letter and the machine wins a band the letter no "
					+ "longer crosses -- ASSA-213 says the strokes stay last.")
					% [bed_at, band_at, ink_at])
	screen.queue_free()
	return ok


## **EVERY DEPOSIT MARK SITS ON THE MIDDLE OF THE TILE IT NAMES** (ASSA-220).
##
## **WHY THE INVARIANT THAT ALREADY EXISTS CANNOT SEE THIS**, which is most of why a half-tile shipped
## for as long as it did. `tests/test_scene_view.gd` holds `_tile_under(point_of_tile(t)) == t` in both
## views, and that passes on the defect: the tile's top-left CORNER is inside the tile too, so
## `_tile_under` answers `t` for the corner exactly as it does for the middle. A round trip through a
## floor cannot tell two points in one cell apart. Only a claim about WHERE IN the cell can.
##
## **AND THE WANTED POINT IS DERIVED, NOT COPIED.** Re-spelling `MARGIN + (tile + 0.5) * _cell` here
## would assert the implementation against itself -- the vacuous shape that has cost me two merged
## tests. So the claim is the one in the item: a deposit covers tiles `centre +/- radius`, which on
## screen spans `(c - r) * cell` to `(c + r + 1) * cell`, and a circle drawn concentric with the rock it
## describes sits at the MIDPOINT of that span. `r` cancels out of that midpoint, which is the point --
## the answer is the tile's middle as a CONCLUSION about the rock, not as a premise about the formula.
##
## **TWO CELL SIZES, because the error is half a CELL and not a number of pixels.** At one cell size a
## constant 4.5 px offset satisfies this assertion; at two it cannot.
func test_a_deposit_and_its_letter_are_drawn_on_the_middle_of_the_tile_they_name() -> bool:
	var screen := _joined_screen()
	screen._show_close_up(false)
	screen._refresh()
	if screen._close_up or not screen._sim.running():
		screen.queue_free()
		return _fail(("premise: close_up %s, running %s -- `_draw` returns before any deposit on "
				+ "either") % [screen._close_up, screen._sim.running()])
	var font := ThemeDB.fallback_font
	var deposits: Array = screen._sim.deposits()
	if deposits.is_empty():
		screen.queue_free()
		return _fail("premise: this world has no deposits, so there is no mark to place and this test "
				+ "is about nothing")
	var ok := true
	var checked := 0
	for cell: float in [9.0, 23.0]:
		if not ok:
			break
		screen._cell = cell
		var by_tile := {}
		for entry in screen._glyph_marks(deposits, font):
			var mark: Dictionary = entry
			by_tile[mark["tile"] as Vector2i] = mark
		if by_tile.is_empty():
			ok = _fail(("premise: no species letter is placed at %.0fpx a tile, so there is nothing "
					+ "to measure at this cell size") % [cell])
			break
		for raw in deposits:
			var deposit: Dictionary = raw
			var tile: Vector2i = deposit["center"]
			if int(deposit["amount"]) <= 0 or not by_tile.has(tile):
				continue
			var mark: Dictionary = by_tile[tile]
			# The rock's own pixel span, straight off the tiles it covers.
			var radius := int(deposit["radius"])
			var low: Vector2 = screen.MARGIN + Vector2(tile - Vector2i(radius, radius)) * cell
			var high: Vector2 = screen.MARGIN + Vector2(tile + Vector2i(radius + 1, radius + 1)) * cell
			var want: Vector2 = (low + high) * 0.5
			var at: Vector2 = mark["at"]
			if at.distance_to(want) > 1e-4:
				var off := (at - want) / cell
				ok = _fail(("the %s deposit at tile %s spans %s..%s at %.0fpx a tile, so a mark "
						+ "concentric with it belongs at %s -- and it is drawn at %s, off by (%.2f, "
						+ "%.2f) of a tile. A mark may lie about its size or its colour and never "
						+ "about its position.") % [mark["symbol"], tile, low, high, cell, want, at,
						off.x, off.y])
				break
			checked += 1
	if ok and checked < 2:
		ok = _fail(("only %d deposit marks were measured across both cell sizes, which is too few for "
				+ "the two-cell argument to mean anything") % [checked])
	# **AND THE DISC ITSELF, WHICH NOTHING HEADLESS CAN READ.** The letter's position comes out of
	# `_glyph_marks` and is measured above; the disc's is computed inside `_draw`, where nothing can be
	# asked what it painted (the same gap the comment on `_building_marks` names). The two were
	# INDEPENDENT copies of the corner formula, which is exactly how one defect came to sit in two
	# places, so a scan for the shared helper is what keeps them from drifting apart again.
	if ok:
		var source := FileAccess.get_file_as_string("res://scripts/main.gd")
		if source == "":
			ok = _fail("main.gd could not be read, so this scan says nothing")
		elif not source.contains("point_of_tile(deposit.get(\"center\""):
			ok = _fail("the deposit pass in `_draw` no longer takes its centre from `point_of_tile`, "
					+ "so the disc and the letter it carries can disagree about which tile they are on")
		# **THESE TWO MUST KEEP THE CORNER, and that is the whole reason they are asserted** (Maren's
		# second point on ASSA-220). A rect that COVERS a cell is not a mark that NAMES one: both start
		# at the tile's top-left and span `_cell`. Their arithmetic is identical to the bug this test is
		# about, so the next person to grep for `MARGIN + Vector2(` and "finish the job" moves the two
		# marks that were right -- and would see nothing red without this.
		elif not source.contains("MARGIN + Vector2(_target) * _cell"):
			ok = _fail("the target brackets no longer start at the tile's corner: a rect that covers a "
					+ "cell is not a mark that names it, and ASSA-220 moved the marks, not the rects")
		# **THE HOVER OUTLINE'S CORNER IS NOW ASSERTED ON GEOMETRY INSTEAD OF ON A STRING** (ASSA-284).
		# This read `source.contains("MARGIN + Vector2(_hover) * _cell")` and went red when the rect
		# moved into `AssayHud.hover_mark` so that the outline could be given a rim -- correctly, since
		# that string was the only thing holding the corner. The property it was standing in for is
		# held directly by `test_hud.gd::test_the_hovered_tiles_outline_carries_its_own_opaque_rim`,
		# which checks the rect IS tile (12, 7)'s own cell at three cell sizes. The scan stays, because
		# ASSA-220's actual finding was two independent copies of the corner formula drifting apart:
		# what it pins now is that `_draw` takes the rect from the shared helper rather than keeping a
		# fourth copy of the arithmetic.
		elif not source.contains("AssayHud.hover_mark(_hover, _cell, MARGIN)"):
			ok = _fail("`_draw` no longer takes the hovered tile's rect from `AssayHud.hover_mark`, "
					+ "so the corner formula has a copy in the paint loop again -- which is the shape "
					+ "of ASSA-220's defect, and nothing headless can read a `draw_rect` back")
	# **AND THE INSTRUMENT, BECAUSE IT CARRIED THE SAME BUG.** `window_shot.gd` recorded each disc's
	# centre with its own third copy of `MARGIN + tile * _cell`, so it AGREED WITH THE DEFECT: every
	# centre measured off `08-whole-world-marks.json` was the corner, and `main.gd` fixed alone would
	# have left the shot reporting a point the screen does not draw, with nothing red anywhere.
	if ok:
		var shot := FileAccess.get_file_as_string("res://tools/window_shot.gd")
		if shot == "":
			ok = _fail("window_shot.gd could not be read, so this scan says nothing")
		elif not shot.contains("_screen.point_of_tile(tile)"):
			ok = _fail("the shot's disc table no longer takes its centre from the screen, so a "
					+ "measurement off its JSON can be half a tile from what was painted")
	screen.queue_free()
	return ok


## **EVERY SPECIES LETTER IN A FRAME IS THE SAME SIZE, AND IT IS THE SIZE THAT FITS THE SMALLEST
## PATCH THE SIM CAN ROLL** (ASSA-293, Maren's ruling 11.35: *"the letter's size means nothing and is
## held constant"*).
##
## **WHY A TEST AND NOT A CONSTANT:** the defect was not a wrong number, it was a letter COPYING the
## disc's channel. `glyph_size(radius x cell)` clamps at 32, so at cell 9 a radius-3 and a radius-4
## patch drew the identical letter while a radius-2 one drew 25 -- three facts, two states, 63.6% of
## deposits over ten seeds wearing a size that distinguished nothing (`tools/letter_size_spread.gd`).
## Two cold readers decoded the surviving difference in two different wrong directions (Nacre:
## quantity; Limpet: hover). So what has to hold is a property over a WHOLE FRAME, which a unit test
## on `glyph_size` cannot state: no two letters on one map differ.
##
## **TWO SEEDS AND TWO CELL SIZES.** One seed could happen to roll a single radius; `test_hud.gd::
## test_the_held_letter_fits_the_smallest_patch_the_sim_rolls` is what holds the radii spread itself.
## Two cells, because "one size" must not mean "a constant 25" -- the held size is a function of the
## cell, and a hard-coded 25 would pass this at cell 9 and lie at every other zoom.
##
## WHAT IT CANNOT SEE: whether 25 px is legible, or whether a letter that no longer grows with its
## patch still reads as belonging to it. Both are 1x window questions and live on ASSA-273's figures.
func test_every_species_letter_on_one_map_is_drawn_at_one_size() -> bool:
	var font := ThemeDB.fallback_font
	var ok := true
	var checked := 0
	for seed_text: String in ["777042", "63"]:
		if not ok:
			break
		var screen := _joined_screen(seed_text)
		screen._show_close_up(false)
		screen._refresh()
		if screen._close_up or not screen._sim.running():
			screen.queue_free()
			return _fail(("premise: close_up %s, running %s on seed %s -- `_draw` returns before any "
					+ "letter on either") % [screen._close_up, screen._sim.running(), seed_text])
		var deposits: Array = screen._sim.deposits()
		for cell: float in [9.0, 23.0]:
			screen._cell = cell
			var want := AssayHud.glyph_size_held(cell)
			var sizes := {}
			var radii := {}
			for entry in screen._glyph_marks(deposits, font):
				var mark: Dictionary = entry
				sizes[int(mark["size"])] = true
				checked += 1
			for raw in deposits:
				var deposit: Dictionary = raw
				if int(deposit.get("amount", 0)) > 0:
					radii[int(deposit.get("radius", 1))] = true
			if sizes.is_empty():
				ok = _fail(("premise: seed %s paints no species letter at %.0fpx a tile, so there is "
						+ "nothing to measure") % [seed_text, cell])
				break
			if sizes.size() > 1:
				var found := sizes.keys()
				found.sort()
				ok = _fail(("seed %s paints %d different letter sizes on one map at %.0fpx a tile "
						+ "(%s). A letter's size means nothing (ASSA-293), so two letters that differ "
						+ "are a channel a player will try to decode -- and the two cold readers on "
						+ "file decoded it as quantity and as hover, both wrong.")
						% [seed_text, sizes.size(), cell, found])
				break
			if int(sizes.keys()[0]) != want:
				ok = _fail(("seed %s draws its letters at %d px and the size that fits the smallest "
						+ "patch the sim can roll is %d px at %.0fpx a tile. Sized for anything bigger, "
						+ "a letter overflows the narrowest patch and reads as a label for the tile "
						+ "next door, which is `glyph_size`' own rule.")
						% [seed_text, int(sizes.keys()[0]), want, cell])
				break
			# **THE PREMISE THAT MAKES THE ASSERTION ABOVE WORTH ANYTHING**, and it is the half a
			# "sizes.size() == 1" check silently drops: if every deposit in frame happens to share one
			# radius, one size proves nothing at all.
			if radii.size() < 2:
				ok = _fail(("premise: seed %s rolls only %d distinct deposit radius at %.0fpx a tile, "
						+ "so one letter size could be an accident of the world rather than the rule")
						% [seed_text, radii.size(), cell])
				break
		screen.queue_free()
	if ok and checked < 8:
		ok = _fail(("only %d letters were measured over two seeds and two cell sizes, too few for a "
				+ "claim about a whole frame") % [checked])
	return ok


## **THE OTHER HALF OF ASSA-219, AND THE HALF THAT MADE IT A FREEZE A PLAYER MET.**
##
## `solo_relay.gd`'s `poll()` had an early return that stopped it reading the pipe once an address
## was known. Fixing that alone would have changed nothing, because THIS function had a matching
## guard -- `if _solo == null or _solo.address != "" ... : return` -- so from the frame the relay said
## where it was listening, the screen never called it again. The relay prints a line per submitted
## command into that pipe; about two thousand lines later it blocks inside its own tick loop and the
## world stops for good.
##
## So what is pinned here is the CALL, on a frame that is deep in a session, which is the one state
## the old code is guaranteed to skip. The drain itself is measured against a real flooding process
## in `test_solo_relay.gd::test_the_relays_log_is_drained_for_a_whole_session_and_never_blocks_its_host`;
## a counter here would be happy with a `pump()` that did nothing, so neither test is worth much
## without the other.
##
## **AND `poll()` MUST NOT BE CALLED ON THESE FRAMES**, which is not a style point: `_join_address`
## opens a socket, and the guard this fix moves is also what stops it re-joining every frame. A fix
## that drained the pipe by dropping the guard outright would have traded a freeze for a reconnect
## storm, so the two counters are asserted together.
func test_the_solo_frame_keeps_reading_the_relay_for_the_whole_session() -> bool:
	var screen := _screen()
	var solo := _RelayMidSession.new()
	# MID-SESSION: the address arrived frames ago and the join already happened.
	solo.address = "127.0.0.1:54321"
	screen._solo = solo
	screen._process(0.016)
	screen._process(0.016)
	screen._process(0.016)
	screen._solo = null
	var ok := true
	if solo.pumps != 3:
		ok = _fail(("three frames of a joined solo session read the relay %d times, not 3 -- its "
				+ "stdout fills and the host stops ticking (ASSA-219)") % solo.pumps)
	elif solo.polls != 0:
		ok = _fail(("a joined solo session asked poll() %d times; that is the re-join the moved guard "
				+ "exists to prevent") % solo.polls)
	screen.queue_free()
	return ok

## **EXACTLY ONE GREEN THING TO PRESS PER SCREEN** (ASSA-233, Maren's ruling 2; the hole Nerite
## measured on ASSA-224).
##
## **THIS EXISTS BECAUSE NERITE PROVED NOTHING GUARDED IT.** They replaced
## `_solo_button.theme_type_variation = &"Primary"` with `pass` and the suite answered 340 passed,
## 0 failed: no test in `tests/` read the word `Primary` or `Quiet`, so the one-accent rule and the
## quiet furniture were held up by a screenshot and a reviewer removing the accent would have merged
## green. A rank nothing can fail is a preference, not a rule.
##
## **IT COUNTS ON THE REAL TREE AND NOT AT THE CALL SITES.** A grep of `main.gd` would pass over a
## `Primary` applied by a loop, a scene file, or a third screen written next month; what the rule is
## about is how many accented controls a player can see at once, so that is what is counted --
## every visible `Button` under the screen, in both states the client has.
##
## THE JOIN SCREEN'S ONE IS `Play solo`, AND IT IS NAMED. "Exactly one" with no name would stay green
## if the accent moved to `Join`, which is the quieter path and the opposite of the ruling.
func test_exactly_one_control_per_screen_wears_the_accent() -> bool:
	var screen := _screen()
	var ok := true
	var before := _accented(screen)
	if before.size() != 1:
		ok = _fail(("the join screen shows %d accented controls, not 1: %s (ASSA-233: one screen, "
				+ "one primary action)") % [before.size(), ", ".join(before)])
	elif before[0] != "Play solo":
		ok = _fail("the join screen's one accented control is `%s`, not `Play solo`" % before[0])
	screen.queue_free()
	if not ok:
		return false

	# AND THE PLAYED SCREEN, which is the one the ruling was filed about: nine buttons at identical
	# weight. `_joined_screen` plays a real world through the binding, so what is counted here is the
	# column a player actually gets rather than a hand-built row.
	#
	# **TWO WORLDS, OPPOSITE EXPECTATIONS, AND THE SIM SAYS WHICH IS WHICH.** This half used to run
	# one world and accept any count of 0 or 1, under a comment of mine calling that "the honest
	# half": `Mine` is Primary only where a hand can break the rock under you, so on a world where
	# the body stands on grass ZERO really is the right answer, and demanding one would demand an
	# accent on a button that refuses. The reasoning was right and the conclusion was wrong -- a
	# test that accepts both answers asserts neither. Nerite measured what it cost: BOTH one-line
	# mutations of the played-screen accent merged green (345/0).
	#
	#     `if minable:` -> `if true:`     the gate Maren asked for, held by nothing
	#     Mine's `Primary` deleted        the rank this test is named after, held by nothing
	#
	# So the expectation is DERIVED, not picked: ask `_can_hand_mine_here()` -- the same call
	# `_refresh_actions` gates the accent on, so the test cannot drift from the client by consulting
	# a different authority -- and then assert the exact count that follows from its answer.
	var arms := {}
	for seed_text in ["14247", "777042"]:
		var joined := _joined_screen(seed_text)
		# **ONE FRAME, BECAUSE A WELCOME ALONE IS A STATE PRODUCTION NEVER SITS IN.**
		# `_joined_screen` feeds a welcome and stops; `_refresh_join_band` and `_refresh_front_door`
		# run in `_process`, so without this the join controls still wear the visibility they were
		# BUILT with and the first run of this test reported `Play solo` accented inside a played
		# world. That was my harness, not the client -- the same trap
		# `test_play_solo_neither_reads_nor_wipes_a_typed_host` already carries a note about.
		joined._process(0.016)
		var minable: bool = joined._can_hand_mine_here()
		var during := _accented(joined)
		arms[minable] = seed_text
		if minable and during.size() != 1:
			ok = _fail(("seed %s spawns on a rock a hand can break, so the played screen must show "
					+ "exactly 1 accented control and shows %d: %s. `Mine` is this screen's one "
					+ "primary (ASSA-233 ruling 2)") % [seed_text, during.size(), ", ".join(during)])
		elif minable and during[0] != "Mine":
			ok = _fail(("seed %s: the played screen's one accented control is `%s`, not `Mine`")
					% [seed_text, during[0]])
		elif not minable and during.size() != 0:
			ok = _fail(("seed %s spawns where no hand can mine, so the played screen must show 0 "
					+ "accented controls and shows %d: %s. A green button that refuses is worse "
					+ "than a grey one that refuses (Maren, ASSA-233)")
					% [seed_text, during.size(), ", ".join(during)])
		joined.queue_free()

	# **AND BOTH ARMS HAVE TO HAVE HAPPENED, OR THIS TEST IS VACUOUS.** Which seed spawns on a
	# minable deposit is the sim's doing and not a property of this file: a worldgen change, or
	# someone editing the seed list, could leave every arm on the same side and the loop above would
	# go green over exactly the two mutations it exists to catch. This is the control inside the
	# test -- it fails on the absence of a case rather than on a number I chose.
	if not arms.has(true) or not arms.has(false):
		ok = _fail(("the played-screen arms are vacuous: the seeds covered %s. One world must spawn "
				+ "on a hand-minable deposit and one must not, or deleting Mine's accent passes "
				+ "this test") % str(arms))
	return ok


## **THE QUIET WEIGHT IS THE QUIETEST OF THREE, AND IT IS A CONTROL** (ASSA-233, Maren's Q1 fix at
## 17:00Z, which reverses her own 14:25Z one).
##
## **NOTHING HAS EVER TESTED THIS AND THAT IS WHY IT WENT ROUND TWICE.** Nerite's note on ASSA-224:
## "no test in `tests/` read the word `Primary` or `Quiet`, so the one-accent rule and the Quiet
## furniture on the log and mode toggles are guarded only by a picture". The accent half got its test;
## this half did not, so I shipped an edge at rest for her first ruling and had nothing to fail when
## the second ruling took it away again.
##
## **THE CLAUSE WENT ROUND THREE TIMES AND THIS TEST IS WRITTEN AGAINST THE MEASUREMENT, NOT THE
## ARGUMENT.** Maren ruled the edge at rest keep (14:25Z) -> delete (17:00Z) -> keep (18:40Z), and I
## built the middle one. The 17:00Z position was reasoning -- *"a border makes quiet into default and
## spends the rank"* -- and the 18:40Z one measured the same frame and disproved it: **what a player
## reads as the default weight is its FILL**, `RAISED` (53,57,67), while a quiet toggle stays flush
## with the panel (37,40,48) and a field sinks to its own darker well (28,30,36).
##
## **SO THE FILL IS WHAT IS GUARDED, AND NOTHING GUARDED IT WHILE THREE RULINGS ARGUED ABOUT THE
## EDGE.** Asserted: quiet HAS an edge at rest; quiet's fill is the panel's own; `default`'s fill is
## NOT; and quiet's edge is the dimmer of the two, so hover has a step left to make. The third of
## those is the control -- a theme flattening `Button`'s fill onto the panel would leave every other
## assertion here true while the rank they exist to protect was gone.
##
## READ OFF THE REAL CONTROLS, NOT THE GENERATOR (ASSA-152's lesson). `build_theme.gd` refusing to
## WRITE something is not the window refusing to DRAW it: the resolved stylebox on the button in the
## tree is what a player sees, so that is what is asked.
##
## **AND IT HAS TO BE POKED FIRST, WHICH IS A FACT ABOUT THIS HARNESS AND NOT ABOUT THE CLIENT.**
## `theme_type_variation` here resolves against the PROJECT theme (`project.godot`
## `gui/theme/custom`), and a control that gets its theme that way keeps reading the plain `Button`
## entries until it receives `NOTIFICATION_THEME_CHANGED`. Running `_process` frames does not do it;
## a freshly built in-tree `Button` wearing `Quiet` reports `font_color` = `INK` (the default
## weight's). So without the poke below this test would assert the OPPOSITE of what ships.
##
## **MEASURED, BECAUSE I WOULD OTHERWISE BE TRUSTING A METHOD NAME.** Real window, 1280x720, seed
## 14247, `tools/window_shot.gd` `02-play.png`, inside the log toggle's own rect: the fill is
## (37,40,48) = `SURFACE`, and the brightest glyph pixel is (167,176,190) = `INK_MUTED` exactly,
## with `INK` on 0 pixels of it. The window draws this weight; only the headless read needed telling.
##
## **AND THE INK BAR THIS ONCE CARRIED IS GONE BECAUSE I DISPROVED IT.** Her clause (b) wanted these
## toggles' ink at or above the brightest body row (5.44). Measured, both toggles and every body row
## are that same `INK_MUTED` at 6.74:1 on the same surface -- they are not below the brightest body
## row, they ARE it -- and her 4.22-against-5.44 was `SMALL` (11px) against `BODY` (13px) on a
## mean-over-glyph-box reading. She withdrew the number. What survives is her intent, asserted below:
## a control may never be inked dimmer than the prose beside it.
func test_the_quiet_toggles_are_the_quietest_weight_and_still_read_as_controls() -> bool:
	var screen := _screen()
	var ok := true
	# **BY THE CLIENT'S OWN NAMES FOR THEM, not by label text.** Both toggles re-text themselves with
	# their state ("show"/"hide"), so a literal here passes or fails on which way the menu happens to
	# open rather than on the ruling -- which is how the first run of this test failed looking for
	# `show what I can make (M)` on a screen whose menu starts open.
	for named in [["_log_toggle", screen._log_toggle], ["_make_toggle", screen._make_toggle]]:
		var label: String = named[0]
		var toggle := named[1] as Button
		if toggle == null:
			ok = _fail("no `%s` on the screen: the quiet toggles are the two controls Maren's Q1 "
					% label + "ruling is about")
			continue
		_poke_theme(toggle)
		if toggle.theme_type_variation != &"Quiet":
			ok = _fail(("`%s` wears `%s`, not `Quiet`. It is furniture beside the section headings "
					+ "it sits between (ASSA-224)") % [label, toggle.theme_type_variation])
		# **THE CUE THAT IS LEFT.** Centred, these were the only rows in a column whose every other
		# row sits at the body x=11, so they read as a caption for the heading above them --
		# "centred + boxless + above the block it controls is a caption by construction".
		if toggle.alignment != HORIZONTAL_ALIGNMENT_LEFT:
			ok = _fail(("`%s` is not left-aligned. Every other control in that column sits at the "
					+ "body x=11, and these two were the only centred rows in it (Maren, ASSA-233)")
					% label)
		var rest := toggle.get_theme_stylebox(&"normal") as StyleBoxFlat
		if rest == null:
			ok = _fail("`%s` resolves no StyleBoxFlat at rest, so its weight cannot be read" % label)
			continue
		# AN EDGE IS A BORDER WIDTH **AND** A COLOUR YOU CAN SEE AGAINST THE FILL. Either one at zero
		# is no edge, which is the state Maren read as a panel TITLE rather than as a control.
		var edge := rest.border_width_left > 0 and rest.border_color.a > 0.0 \
				and not rest.border_color.is_equal_approx(rest.bg_color)
		if not edge:
			ok = _fail(("`%s` draws no edge at rest (border %s on fill %s). A dim line with no box, "
					+ "across the top of a panel, is where a TITLE sits -- which is what this read as "
					+ "when the edge was gone (Maren, ASSA-233 18:40Z)")
					% [label, rest.border_color, rest.bg_color])
		# **AND THE FILL IS THE PANEL'S OWN, WHICH IS THE PROPERTY THE RULING ACTUALLY TURNS ON.**
		# Maren ruled this clause three times in a day -- keep the edge, delete it, keep it -- and
		# only the last carried a measurement: what a player reads as the DEFAULT weight is its FILL,
		# `RAISED` (53,57,67), while a quiet toggle stays flush with the panel (37,40,48) and a field
		# sinks to its own darker well. The charge against the hairline was that it "makes quiet into
		# default"; it cannot, so long as this stays true. **The fill is the thing to guard, not the
		# edge**, and nothing guarded it while three rulings argued about the edge.
		if not rest.bg_color.is_equal_approx(_panel_surface()):
			ok = _fail(("`%s` fills %s, which is not the panel's own %s. A quiet button acquiring a "
					+ "fill is what would really spend the rank -- the default weight is read off "
					+ "exactly that (Maren, ASSA-233 18:40Z)")
					% [label, rest.bg_color, _panel_surface()])
		# **MAREN'S CLAUSE (b), IN THE ONE FORM THAT IS ACTUALLY A PROPERTY OF THE CLIENT.** She asked
		# for "ink at or above the brightest body row (5.44), not below it", off rendered glyph boxes
		# where these toggles read 4.22 and 4.79. The colour is already equal: `_note()` paints every
		# body row `INK_MUTED` out of this theme and so does `Quiet` -- 6.74:1, the same 24-bit value
		# on the same surface, confirmed on the real window. Her gap is `SMALL` (11px) against `BODY`
		# (13px): a smaller glyph spends proportionally more of itself on partly-covered edge pixels,
		# so one colour measures two numbers.
		#
		# So what is guarded here is her INTENT -- a type scale exists to lift what you can act on
		# above what you merely read, and these two must never end up dimmer than the prose beside
		# them. It is asked of luminance rather than of a colour name, so moving either token still
		# has to keep the order.
		var body_ink := _drawn_color(screen._note("a body row"))
		var toggle_ink := toggle.get_theme_color(&"font_color", &"Quiet")
		if AssayHud.relative_luminance(toggle_ink) \
				< AssayHud.relative_luminance(body_ink) - 0.001:
			ok = _fail(("`%s` is inked %s, dimmer than the body rows beside it at %s. The two things "
					+ "you can click in that column must not be its dimmest text (Maren, ASSA-233)")
					% [label, toggle_ink, body_ink])
	# **AND THE TWO FILLS MUST STAY APART, or "quieter than default" is a claim about nothing.** This
	# is the control inside the test. A theme that flattened `Button`'s fill down onto the panel
	# would make every assertion above still pass while the rank it exists to protect was gone --
	# quiet and default would be the same box with the same inside, differing only in a hairline's
	# alpha. That is the one change this test must not be able to sleep through.
	var plain := Button.new()
	screen.add_child(plain)
	_poke_theme(plain)
	var plain_rest := plain.get_theme_stylebox(&"normal") as StyleBoxFlat
	if plain_rest == null:
		ok = _fail("a `default` Button resolves no StyleBoxFlat at rest, so rank cannot be read")
	elif plain_rest.bg_color.is_equal_approx(_panel_surface()):
		ok = _fail(("a `default` Button fills the panel's own %s, so it is as flush as `Quiet` is: "
				+ "the weights now differ by a hairline alone and the fill no longer ranks them "
				+ "(Maren's measured reason, ASSA-233)") % _panel_surface())
	# AND QUIET'S EDGE IS THE QUIETER OF THE TWO, which is the other half of "without competing with
	# the default button beside it": same token, lower alpha, so hover brightens an existing edge
	# rather than conjuring one.
	var quiet_rest := (screen._log_toggle as Button).get_theme_stylebox(&"normal") as StyleBoxFlat
	if plain_rest != null and quiet_rest != null \
			and quiet_rest.border_color.a >= plain_rest.border_color.a:
		ok = _fail(("`Quiet`'s edge at rest is alpha %.2f against `default`'s %.2f: it is not the "
				+ "quieter of the two, so there is no step left for hover to make")
				% [quiet_rest.border_color.a, plain_rest.border_color.a])
	screen.queue_free()
	return ok


## Every VISIBLE button under a node wearing the accent weight, by its label.
func _accented(node: Node) -> PackedStringArray:
	var found := PackedStringArray()
	for child in node.get_children():
		if child is Button and (child as Button).theme_type_variation == &"Primary" \
				and _on_screen(child):
			found.append((child as Button).text)
		found.append_array(_accented(child))
	return found


## **THE DEBUG READOUT IS NOT IN THE PLAYER'S VIEW, AND EVERY WORD OF IT IS STILL THERE** (ASSA-237,
## Maren's Gap 2: *"none of it in the player's view. Keep every word of it behind a developer toggle
## (it is genuinely useful to us)"*).
##
## **THE SECOND HALF IS THE HALF WORTH TESTING.** "Hidden" is one line of production code and one
## assertion; the way this fix fails in six weeks is that somebody also stops WRITING the line,
## because nothing on screen was reading it -- and then F3 answers with a stale tick, or with nothing,
## at the exact moment someone is using it to debug a desync. So this drives a real played world and
## reads the hidden label's own text back.
##
## IT ASKS FOR THE SEED AND THE HASH BY NAME rather than for a non-empty string: those two are the
## reason the readout exists (a `u64` neither GDScript nor a person can reconstruct), and a readout
## that had quietly become "tick 12" alone would pass any length check.
func test_the_debug_readout_is_hidden_but_still_written() -> bool:
	var ok := true
	var screen := _screen()
	if _on_screen(screen._detail):
		ok = _fail("the debug readout is drawn on the first screen a stranger sees")
	screen.queue_free()
	if not ok:
		return ok

	var joined := _joined_screen()
	joined._process(0.016)
	joined._refresh()
	if _on_screen(joined._detail):
		ok = _fail("the debug readout is drawn in a played world, which is the screen we send "
				+ "the board")
	var written: String = joined._detail.text
	for word in ["world seed", "hash", "tick", "bundle"]:
		if not written.contains(word):
			ok = _fail("the hidden readout has stopped saying `%s`: `%s`" % [word, written])
	joined.queue_free()
	return ok


## **F3 GIVES IT BACK, WITH THE WORLD'S STATE AS IT IS NOW AND NOT AS IT WAS WHEN IT WENT AWAY**
## (ASSA-237). The toggle only gates the drawing, never the write, which is what makes the first press
## honest; a version that stopped refreshing while hidden would pass a "becomes visible" test and show
## a tick from whenever the window opened.
##
## DRIVEN THROUGH `_unhandled_key_input` WITH A REAL `InputEventKey`, not through `_show_dev_readout`.
## Calling the setter would pass with nothing in production ever reaching it -- the same lever-that-
## cannot-fail that `test_the_join_band_is_on_screen_in_every_stage_except_joined` carries a note
## about.
func test_f3_shows_the_debug_readout_and_shows_it_current() -> bool:
	var ok := true
	var joined := _joined_screen()
	joined._process(0.016)
	joined._refresh()
	var before: String = joined._detail.text

	var press := InputEventKey.new()
	press.keycode = KEY_F3
	press.pressed = true
	joined._unhandled_key_input(press)
	if not _on_screen(joined._detail):
		ok = _fail("F3 did not bring the debug readout back")

	# AND IT IS STILL BEING REWRITTEN NOW THAT IT IS VISIBLE. `_refresh` is the only writer; a fix
	# that had moved the write inside the toggle would leave this blank, and one that cached it would
	# leave F3 answering with the tick the window opened on.
	joined._detail.text = ""
	joined._refresh()
	if joined._detail.text == "":
		ok = _fail("nothing rewrote the readout while it was visible, so F3 shows whatever was "
				+ "last written rather than the world's state now")
	elif not joined._detail.text.contains("world seed"):
		ok = _fail("the visible readout is not the readout: `%s`" % joined._detail.text)

	# AND F3 AGAIN TAKES IT AWAY, because a developer toggle a player can trip into is a developer
	# toggle a player cannot get out of.
	var again := InputEventKey.new()
	again.keycode = KEY_F3
	again.pressed = true
	joined._unhandled_key_input(again)
	if _on_screen(joined._detail):
		ok = _fail("F3 is a one-way door: it showed the readout and will not hide it again")
	if before == "":
		ok = _fail("the fixture never wrote a readout, so this test asked nothing")
	joined.queue_free()
	return ok


## **HIDING THE READOUT MUST NOT HIDE THE ONE SENTENCE IN IT THAT WAS NEVER DEBUG** (ASSA-237).
##
## `_refresh` wrote *"joined at tick N, but no world is being simulated: ..."* into `_detail`. That is
## a client that joined and can draw nothing -- the state where saying something matters most -- and
## the moment `_detail` stopped being drawn it would have become the one state this client says
## nothing about. "No refusal is silent" lost to a layout change is the quietest way this slice could
## have gone wrong, so it is the one with a test.
##
## THE STATE IS BUILT THE WAY THE BRANCH DEFINES IT -- a joined client whose sim is not running --
## rather than by calling the branch. A fresh `AssaySimHost` has never been started, which is exactly
## `running() == false`, and `_client.joined_world` is left as the real welcome put it.
func test_a_joined_client_with_no_world_says_so_on_the_status_line() -> bool:
	var ok := true
	var joined := _joined_screen()
	if joined._client.joined_world.is_empty():
		joined.queue_free()
		return _fail("the fixture never joined, so there is no `joined but not simulating` state")
	joined._sim = AssaySimHost.new()
	if joined._sim.running():
		joined.queue_free()
		return _fail("a never-started host reports running, so this test asked nothing")
	joined._refresh()
	if not joined._status.text.contains("no world is being simulated"):
		ok = _fail("a joined client that cannot simulate says `%s` on its status line"
				% joined._status.text)
	if _on_screen(joined._detail):
		ok = _fail("the sentence is on the status line AND the debug readout is visible, so this "
				+ "test could pass with the fix reverted")
	joined.queue_free()
	return ok


## **NO PIXEL OF THIS WINDOW IS A COLOUR NOBODY CHOSE** (ASSA-237).
##
## 16.0% of a real-window shot of `02-play` was `(77, 77, 77)` -- Godot's default clear colour, which
## appears in no palette in this repo. It is the frame around the map and the band above it, and it is
## the surface the STATUS LINE is drawn on, at **3.86:1** against a 4.5 floor once ASSA-233 moved that
## line to `INK_MUTED`. This is ASSA-152's finding one layer out: that item painted the HUD column
## because "nothing is a colour"; the window itself was still nothing.
##
## **THE ASSERTION IS `== AssayHud.MAP_BG`, NOT `!= GREY`.** "Not the default" would pass for any
## colour anybody ever typed here, which is the defect rather than the fix -- the rule is that this
## surface is a NAMED one, so the test names it. It also fails if `MAP_BG` is retuned without the
## window following, which is the pair this exists to keep together.
func test_the_window_background_is_a_colour_this_game_names() -> bool:
	var screen := _screen()
	var painted := RenderingServer.get_default_clear_color()
	screen.queue_free()
	if not painted.is_equal_approx(AssayHud.MAP_BG):
		return _fail(("the window clears to %s, which is not `AssayHud.MAP_BG` (%s). Every other "
				+ "surface in this client comes from a named palette; this one is whatever the "
				+ "engine shipped") % [painted, AssayHud.MAP_BG])
	# AND IT CLEARS THE FLOOR THE THEME REFUSES TO WRITE ITSELF UNDER, for the one line drawn on it.
	var muted := Color(0.655, 0.690, 0.745)
	var ratio := AssayHud.contrast_ratio(muted, painted)
	if ratio < 4.5:
		return _fail("the status line reads %.2f:1 on the window's own background, under the 4.5 "
				% ratio + "floor `build_theme.gd` refuses to write a theme under")
	return true


## **NOTHING IS DRAWN ABOVE THE WORLD ANY MORE** (ASSA-239, Maren's Gap 2 ruling 2: *"the strip gets
## nothing in its place. A thinner status line is a thinner version of this defect."*).
##
## **THE ASSERTION IS A SWEEP, NOT A CONSTANT.** Checking `AssayHud.MARGIN.y == 24` would read the fix
## back to itself and would pass on a screen that had quietly parked a label at y=10. This walks every
## visible `Control` on a played screen and fails on any whose rect begins above the world's own top
## edge -- so it fails for a strip that comes back under any name, including one nobody called a
## strip.
##
## THE COLUMN IS NOT AN EXCEPTION AND DOES NOT NEED TO BE: `COLUMN_TOP` is `MARGIN.y` now, so the two
## regions share a top edge rather than the column climbing 16px above the view beside it.
func test_no_control_is_drawn_above_the_world_in_a_played_screen() -> bool:
	var ok := true
	var joined := _joined_screen()
	joined._process(0.016)
	joined._refresh()
	if not joined._sim.running():
		joined.queue_free()
		return _fail("the fixture never simulated, so this test asked nothing")
	var top: float = AssayHud.world_rect().position.y
	var above := PackedStringArray()
	var walk: Array[Node] = [joined]
	while not walk.is_empty():
		var node: Node = walk.pop_back()
		for child in node.get_children():
			walk.append(child)
		var control := node as Control
		if control == null or control == joined or not _on_screen(control):
			continue
		if _top_edge_of(control) < top - 0.01:
			above.append("%s at y=%.0f" % [control.name, _top_edge_of(control)])
	if not above.is_empty():
		ok = _fail("%d control(s) are drawn above the world's top edge (y=%.0f), which is the header "
				% [above.size(), top] + "strip coming back: %s" % ", ".join(above))
	# AND THE WORLD ACTUALLY TOOK THE ROOM, read off the node rather than off the constant.
	#
	# **THE ABSOLUTE 600 THAT USED TO BE HERE IS GONE AND IS NOT REPLACED BY A SECOND OPINION**
	# (ASSA-287). It could not fail: `720 - 24 - 96` is exactly 600, so the strip could come all the
	# way back and this clause would sit on its boundary. The height floor is now a share of the
	# window, ratcheted, and it is `test_the_world_may_never_shrink_as_a_share_of_the_window`'s only
	# job -- this test is about controls drawn above the world, and a second unrelated assertion
	# inside it is how a test ends up with a name that no longer describes it.
	if joined._world.position.y > top + 0.01:
		ok = _fail("the world layer is %s at %s, so the room the strip gave up went nowhere"
				% [joined._world.size, joined._world.position])
	joined.queue_free()
	return ok


## **NO PIXEL OF THE TITLE SCREEN IS BARE WINDOW** (ASSA-292, Maren's rectangle ruling of
## 2026-10-08). The reasoning and her measurement are in `AssayHud.world_layer_rect`'s docstring; what
## this owns is that the client actually asks it, in both states and in the right order.
##
## **IT IS THE WIRING AND NOT THE ARITHMETIC, AND THAT DISTINCTION IS THIS WEEK'S LESSON** (ASSA-292
## box 3): three tests of `AssayScene.title_drift` passed for a whole night while nothing on the
## screen called it. So the first clause reads the LAYER, the second reads the view the door actually
## composed -- which is the half a rect assertion cannot see, since `_door_view` reads `_world.size`
## while it works out the camera -- and the third blanks both and demands one `_refresh_world` put
## them back.
##
## THE TWO STATES ARE ONE TEST because they are one claim with a sign: the door takes the whole
## window, a world gives the column back. Split in two, a `world_layer_rect` that returned the same
## rectangle either way would redden exactly one of them and read like a local failure.
func test_the_door_world_fills_the_window_and_a_world_gives_the_column_back() -> bool:
	var ok := true
	var door := _screen()
	var want := AssayHud.join_rect()
	if not _same_rect(door._world.get_rect(), want):
		ok = _fail(("the door's world layer is %s and the door is %s: %.0f px of bare window beside "
				+ "a lit world is Maren's 26.9%% column (ASSA-292)")
				% [door._world.get_rect(), want, want.size.x - door._world.get_rect().size.x])
	# **THE CAMERA AGREES WITH THE RECTANGLE IT IS DRAWN IN.** `_door_view` reads `_world.size` twice,
	# so a layer resized AFTER the view was composed draws a 912-wide camera stretched over a
	# 1280-wide door -- a picture, not a crash, and nothing else here could see it.
	var view: Dictionary = door._world.view
	if view.is_empty():
		ok = _fail("the door drew no world at all, so this test asked nothing (stale client-lib?)")
	elif (view.get("size", Vector2.ZERO) as Vector2) != door._world.size:
		ok = _fail(("the door camera was composed for a %s layer and the layer is %s: the resize "
				+ "happens after the view") % [view.get("size"), door._world.size])
	# **THE CALL, NOT THE STATE.** Both of the above are also true of a screen that was placed once in
	# `_build_ui` and never again -- which is the state a session ENDING leaves. Blank them and demand
	# one refresh rebuild both.
	door._world.size = AssayHud.world_rect().size
	door._world.view = {}
	door._refresh_world()
	if not _same_rect(door._world.get_rect(), want):
		ok = _fail(("one refresh at the door left the layer at %s instead of %s: the rectangle is "
				+ "set at build time and never restored") % [door._world.get_rect(), want])
	if (door._world.view.get("size", Vector2.ZERO) as Vector2) != want.size:
		ok = _fail(("one refresh at the door composed a camera for %s instead of %s")
				% [door._world.view.get("size"), want.size])
	door.queue_free()
	# AND THE OTHER SIGN: in a world the column is standing there and the map must not be under it.
	var joined := _joined_screen()
	joined._process(0.016)
	joined._refresh()
	if not joined._sim.running():
		joined.queue_free()
		return _fail("the fixture never simulated, so the in-world half asked nothing")
	if not _same_rect(joined._world.get_rect(), AssayHud.world_rect()):
		ok = _fail(("in a world the layer is %s and `world_rect()` is %s: the door's full-window "
				+ "rectangle is being drawn under the HUD column")
				% [joined._world.get_rect(), AssayHud.world_rect()])
	joined.queue_free()
	return ok


## **THE DOOR CAMERA IS ON ITS NAMED LOOK-AT, AND THE ORE WAS GATHERED THERE TOO** (ASSA-311, Maren).
##
## ASSA-292 pointed this camera at `spawn_tile()`, and ADR 0001 guarantees ore beside spawn in every
## seed, so the title card sat on a deposit by construction. `DOOR_LOOK_AT` moves it; what this owns
## is that BOTH places that need the look-at use it.
##
## **AND THE SECOND HALF IS THE ONE THAT WOULD HAVE SHIPPED BROKEN.** `_door_ore_under` gathers the
## ore ONCE, over a window around its own `home`, and nothing afterwards asks the sim about a tile
## outside it. Move the camera and leave that line on spawn and the title screen is a lit world with
## **no ore in it at all** -- a picture, not a crash, and every other test on this screen still green.
## That is this week's lesson twice over (ASSA-292 box 3, ASSA-292's `_process` guard): a constant
## used in two places needs a test that the two agree, not two tests that each read it.
##
## **THE PHASES COME FROM `AssayScene`'s OWN PUBLISHED SAMPLE COUNT**, not from a list typed here, so
## a retune of the loop cannot leave a stale phase table behind. A deposit the camera sees at ANY
## phase must have been gathered, because the ore window is built once and the camera keeps moving.
##
## **ITS BOUND:** if the look-at ever coincides with spawn this test cannot tell one from the other,
## and if no deposit is in frame at any phase it asserts nothing about ore. Both fail loudly instead.
func test_the_door_gathers_its_ore_where_its_camera_is_pointing() -> bool:
	var ok := true
	var door := _screen()
	var view: Dictionary = door._world.view
	if view.is_empty():
		door.queue_free()
		return _fail("the door drew no world at all, so this test asked nothing (stale client-lib?)")
	var world_tiles: Vector2i = view.get("world_tiles", Vector2i.ZERO)
	var layer: Vector2 = view.get("size", Vector2.ZERO)
	var seconds := float(view.get("seconds", 0.0))
	var drift := AssayScene.title_drift(seconds)
	var want := AssayScene.camera_origin(door.DOOR_LOOK_AT + drift, world_tiles, layer, 0.0)
	var spawn_at := AssayScene.camera_origin(
			Vector2(door._door_sim.spawn_tile()) + drift, world_tiles, layer, 0.0)
	if want.distance_to(spawn_at) < 1.0:
		ok = _fail(("DOOR_LOOK_AT %s and spawn %s put the camera in the same place, so this test "
				+ "cannot tell the framing ASSA-311 asked for from the one it replaced")
				% [door.DOOR_LOOK_AT, door._door_sim.spawn_tile()])
	elif (view.get("origin", Vector2.ZERO) as Vector2).distance_to(want) > 0.01:
		ok = _fail(("the door camera is at %s where DOOR_LOOK_AT puts it at %s (spawn would be %s): "
				+ "the title card is framed on whatever the camera found")
				% [view.get("origin"), want, spawn_at])
	var ore: Dictionary = view.get("ore", {})
	var in_frame := 0
	var missed: Array[Vector2i] = []
	for entry in door._door_sim.deposits():
		var patch: Dictionary = entry
		var at: Vector2i = patch.get("center", Vector2i.ZERO)
		var radius := int(patch.get("radius", 0))
		var box := Rect2i(at - Vector2i(radius, radius), Vector2i(radius * 2 + 1, radius * 2 + 1))
		var seen := false
		for i in range(AssayScene.TITLE_DRIFT_SAMPLES):
			var at_second := i * AssayScene.TITLE_DRIFT_PERIOD / float(AssayScene.TITLE_DRIFT_SAMPLES)
			var origin := AssayScene.camera_origin(
					door.DOOR_LOOK_AT + AssayScene.title_drift(at_second), world_tiles, layer, 0.0)
			if AssayScene.visible_tiles(origin, layer, world_tiles).intersects(box):
				seen = true
				break
		if not seen:
			continue
		in_frame += 1
		var gathered := false
		for y in range(box.position.y, box.end.y):
			for x in range(box.position.x, box.end.x):
				if ore.has(Vector2i(x, y)):
					gathered = true
		if not gathered:
			missed.append(at)
	if ok and in_frame == 0:
		ok = _fail(("no deposit of the %d in the door world is in frame at any phase of the loop, so "
				+ "this test said nothing about the ore") % door._door_sim.deposits().size())
	elif ok and not missed.is_empty():
		ok = _fail(("%d of the %d deposits the door camera sees have no ore gathered for them, the "
				+ "first at %s: the ore window is built somewhere the camera is not pointing")
				% [missed.size(), in_frame, missed[0]])
	door.queue_free()
	return ok


## Rect2 equality with one pixel-hundredth of slack, so a test about a 344 px column cannot fail on a
## float.
func _same_rect(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_to(b.position) < 0.01 and a.size.distance_to(b.size) < 0.01


## **THE WORLD MAY NEVER SHRINK** (ASSA-287, Maren's ruling on ASSA-239: *"ratchet it, do not raise
## it"*). The constant and the whole reasoning are `AssayHud.WORLD_HEIGHT_FLOOR_SHARE`'s docstring.
##
## **THIS IS THE TEST THE 72 PIXELS GOT PAST.** `MARGIN.y` 24 -> 96 restores the strip-era 912x600
## and the suite was 392/0, unchanged: the only floor was an absolute 600 sitting exactly on that
## mutation's own result. A share of the window cannot sit on a coincidence of one window size.
##
## **THE FLOOR IS TODAY'S VALUE WITH NO SLACK, which is Maren overruling my 0.92** (2026-10-08): a
## floor below today's value says "this much of the world may be spent without anyone being told".
## So the failure has to earn its keep in one read -- it names the share AND the floor, says how many
## pixels went, and says what to do if the shrink was meant. Her condition: *"a ratchet whose failure
## reads `assertion failed` costs more than the pixels it protects."*
##
## IT READS `world_rect()` AND NOT THE NODE, deliberately and the opposite way round from the sweep
## above: that one asks whether the layout HONOURED the rule, which has to come off the screen; this
## asks whether the rule itself has been weakened, which is a fact about the arithmetic and is true
## before anything is drawn. A regression here is a constant someone edited, not a layout that
## drifted.
func test_the_world_may_never_shrink_as_a_share_of_the_window() -> bool:
	var world := AssayHud.world_rect()
	var share := world.size.y / AssayHud.VIEW.y
	if share < AssayHud.WORLD_HEIGHT_FLOOR_SHARE:
		return _fail(("the world is %.0f of a %.0f px window = %.4f, floor %.4f. Chrome has taken "
				+ "%.0f px of the gameplay view back. IF THIS SHRINK IS DELIBERATE, change "
				+ "AssayHud.WORLD_HEIGHT_FLOOR_SHARE to %.4f in the same commit and say why in the "
				+ "message; if it is not, the chrome you just added is the bug. Raising this floor "
				+ "as the screen improves is free; lowering it to match a regression is the thing "
				+ "it exists to catch") % [world.size.y, AssayHud.VIEW.y, share,
				AssayHud.WORLD_HEIGHT_FLOOR_SHARE,
				AssayHud.VIEW.y * AssayHud.WORLD_HEIGHT_FLOOR_SHARE - world.size.y,
				floorf(share * 10000.0) / 10000.0])
	return true


## Summed up the ancestor chain, for the same reason `_left_edge_of` is: the suite runs before any
## layout pass, so `get_global_position` is about a node that is not anywhere yet.
func _top_edge_of(node: Node) -> float:
	var y := 0.0
	var walk: Node = node
	while walk != null and not (walk is Node2D):
		if walk is Control:
			y += (walk as Control).position.y
		walk = walk.get_parent()
	return y


## **THE TOAST IS DRAWN ONLY WHILE THE CLIENT HAS SOMETHING TO SAY** (ASSA-239).
##
## The status line stopped being furniture when the strip died: it is a transient, empty for most of a
## session, and a panel that sat there empty would be the strip again at a quarter of the height --
## which is the version of this fix Maren ruled against in advance.
##
## **AND WHERE IT LANDS IS CHECKED AGAINST THE WORLD, NOT AGAINST A PAIR OF NUMBERS.** The rule is
## "inside the world's bottom-left corner"; the arithmetic that places it is `status_toast_rect`'s, so
## a test repeating those numbers would only prove I can add. This asks whether the panel is inside
## the world rect and in its lower-left quadrant, which is the thing a player sees.
func test_the_status_toast_appears_only_with_something_to_say() -> bool:
	var ok := true
	var joined := _joined_screen()
	joined._process(0.016)
	joined._refresh()

	joined._say("", AssayHud.Say.IDLE)
	if joined._says_toast.visible and not joined._dev_shown:
		ok = _fail("the toast is drawn with nothing to say, which is the header strip again at a "
				+ "quarter of the height")

	joined._say("mined 1 x ore", AssayHud.Say.IDLE)
	if not joined._says_toast.visible:
		ok = _fail("the client said something and the toast did not appear")
	else:
		var world := AssayHud.world_rect()
		var at := Rect2(joined._says_toast.position, joined._says_toast.size)
		if not world.encloses(at):
			ok = _fail("the toast at %s is not inside the world %s" % [at, world])
		elif at.position.x > world.position.x + world.size.x * 0.5 \
				or at.position.y < world.position.y + world.size.y * 0.5:
			ok = _fail("the toast at %s is not in the world's bottom-left corner: the log owns the "
					% at + "top and the view/key toggles own the bottom-right")
	joined.queue_free()
	return ok


## **THE TOAST KEEPS OFF THE SHAPE KEY, AND BOTH OF THEM USED TO BE IN THAT CORNER** (ASSA-281).
##
## `status_toast_rect`'s own docstring said the world's bottom-left was "the only free corner". It was
## not free: `_build_map_key_over_the_map` had pinned the key there first, on the one view where the
## toast has the most to say. **Measured on five real-window shots by four people**: the key's last
## row, *"the tile the readout is describing"*, held 476 px of sample swatch before this toast existed
## and 172 px in every shot since -- and because the toast's fill IS the key panel's `SURFACE`, it did
## not read as an overlay at all, it read as a twelfth row.
##
## **WHY THE ASSERTION IS `intersects` AND NOT A PAIR OF COORDINATES.** Where the toast goes instead
## is a layout decision that may be revisited -- above, beside, inset further. What must never be true
## again is the two overlapping, so that is the sentence the test holds. A test naming x = 340 would
## have to be rewritten by anyone who improved the placement, which is how a test starts being edited
## to agree with the code.
##
## **AND IT PINS THE UNBLOCKED CASE TOO**, because a fix that moved the toast when nothing was in the
## way would be a regression for every player who never opens the key: with the key down the rect must
## be byte-identical to the one `status_toast_rect` has always returned.
##
## WHAT IT CANNOT SEE: the picture. Headless has no window, so this asserts geometry and the shot is
## `tools/window_shot.gd`'s key leg measured by `probe/nacre_keyrows.py` -- the same instrument that
## found the defect, which is on the item.
func test_the_status_toast_keeps_off_the_shape_key() -> bool:
	var ok := true
	var joined := _joined_screen()
	joined._process(0.016)
	joined._refresh()
	joined._say("mined 1 x ore", AssayHud.Say.IDLE)

	# WITH THE KEY DOWN, NOTHING MOVES. The close-up is where a player spends most of a session and
	# the key cannot be drawn there at all.
	var corner := AssayHud.status_toast_rect(joined._says_toast.get_combined_minimum_size())
	joined._place_says_toast()
	var down := Rect2(joined._says_toast.position, joined._says_toast.size)
	if down != corner:
		ok = _fail("with no key up the toast moved: %s, where it has always been %s" % [down, corner])

	# NOW THE SCHEMATIC AND THE KEY, THROUGH THE SAME TWO SETTERS THE (V) AND (K) BUTTONS CALL.
	joined._show_close_up(false)
	joined._show_map_key(true)
	if not joined._map_key_box.visible:
		joined.queue_free()
		return _fail("premise: the key is not visible after V then K, so this test is about nothing")

	var key := AssayHud.map_key_rect(joined._map_key_box.get_combined_minimum_size())
	var at := Rect2(joined._says_toast.position, joined._says_toast.size)
	if at.intersects(key):
		ok = _fail(("the toast at %s is on top of the shape key at %s: it hides the row a player "
				+ "opened the key to read") % [at, key])
	# STILL ON THE MAP. **NOT "and still on the same baseline", which is what this asserted first and
	# is a promise the function cannot always keep:** a sentence wider than the room beside the key has
	# nowhere to go but above it, and the headless font makes that the case in this very test. The
	# baseline is preserved whenever there IS room -- which is every frame of the shipped window -- and
	# the real-window shot on the item is what says so. Asserting it here would pin the test to a font.
	if not AssayHud.world_rect().encloses(at):
		ok = _fail("the toast at %s left the world %s getting out of the key's way"
				% [at, AssayHud.world_rect()])

	# AND IT GOES BACK when the key does, so the corner is not lost for the rest of the session.
	joined._show_map_key(false)
	var back := Rect2(joined._says_toast.position, joined._says_toast.size)
	if back != corner:
		ok = _fail("the toast did not return to the corner after the key went down: %s, want %s"
				% [back, corner])
	joined.queue_free()
	return ok


## **AN ACCEPTED COMMAND SAYS IT WAS ACCEPTED, AND NEVER SAYS WHEN** (ASSA-245, Maren's full ruling
## on ASSA-237: *"The acceptance is a fact a player uses; the tick is not. Press-to-motion on this
## relay is 204-362 ms, so 'the game took your command' is real feedback and must not simply be
## deleted. **Keep the acceptance, drop `at tick 514`, and move it out of the band.**"*).
##
## **THIS TEST ASSERTED THE OPPOSITE ONE COMMIT AGO AND I WAS WRONG.** ASSA-239 shipped `_act` saying
## nothing at all on success, because I read "the line is empty when healthy" and stopped there. For a
## fifth to a third of a second after a press, a silent screen and a dead button are the same picture,
## and this client never predicts -- so deleting the acceptance deleted the only answer to *did it
## hear me*. The log answers what HAPPENED, a tick later; it cannot answer this.
##
## **TWO CLAUSES, AND THE SECOND IS THE ONE THAT ROTS QUIETLY.** The sentence must carry the
## acceptance, and it must carry no tick -- a tick number is what Gap 2 sent off this screen, and
## re-admitting it on another line is the debug readout returning one clause at a time. A fix that
## only checked for the word `submitted` would pass on a line that had grown its tick back.
func test_an_accepted_command_says_so_without_a_tick() -> bool:
	var ok := true
	var joined := _joined_screen()
	joined._process(0.016)
	joined._refresh()
	if not joined._sim.running():
		joined.queue_free()
		return _fail("the fixture never simulated, so no command could be accepted")

	joined._act("Mine", AssayActions.mine())
	var said: String = joined._status.text
	if not said.contains("submitted"):
		ok = _fail("an accepted command said `%s`: for up to a third of a second that is the only "
				% said + "thing telling a player the game heard them")
	# NO TICK, ASKED OF THE SENTENCE RATHER THAN OF MY MEMORY OF IT: any run of digits long enough to
	# be a tick count is the readout coming back. The world is well past tick 9 by here.
	if said.contains("tick") or said.to_lower().contains("at tick"):
		ok = _fail("the acceptance line names a tick again: `%s`" % said)
	for digits in [str(joined._sim.tick()), str(joined._sim.tick() - 1)]:
		if said.contains(digits):
			ok = _fail("the acceptance line carries the world's tick (%s) in `%s`" % [digits, said])
	# AND IT IS A TRANSIENT, not furniture: `Say.JOINED` is the level that ages out.
	if joined._base_level != AssayHud.Say.JOINED:
		ok = _fail("the acceptance is level %d, so it never ages out of the toast"
				% joined._base_level)
	joined.queue_free()
	return ok


## **AND IT AGES OUT, WHICH IS WHAT KEEPS THE TOAST A TRANSIENT** (ASSA-245/ASSA-239).
##
## If an accepted command's sentence stayed, the toast would be on screen for the whole of a played
## session and the 96 px Maren reclaimed would have come back wearing a smaller frame. The dwell is
## counted in the WORLD's ticks, so this drives the sim rather than a clock.
func test_the_acceptance_ages_out_of_the_toast() -> bool:
	var ok := true
	var joined := _joined_screen()
	joined._process(0.016)
	joined._refresh()
	joined._act("Mine", AssayActions.mine())
	if joined._status.text == "":
		joined.queue_free()
		return _fail("premise: nothing was said, so there is nothing to age out")

	# **THE WORLD REALLY STEPS, rather than the stamp being back-dated.** My first version set
	# `_said_at_tick = tick - DWELL`, and on a fresh welcome that is a NEGATIVE number -- which
	# `_age_the_saying` reads as "said before there was a world" and correctly refuses to age. The
	# test failed, and it was the test that was wrong: faking the arithmetic walked straight into a
	# sentinel the production code is right to have.
	_step_the_world(joined, joined.SAYING_DWELL_TICKS + 1)
	if joined._status.text != "":
		ok = _fail("the acceptance is still on screen %d ticks later: `%s`"
				% [joined.SAYING_DWELL_TICKS + 1, joined._status.text])

	# A REFUSAL IN THE SAME PLACE MUST NOT AGE. No refusal is silent, and this is the half that a
	# "clear the line after a while" fix would quietly lose.
	joined._say("refused: nothing there", AssayHud.Say.FAILED)
	_step_the_world(joined, joined.SAYING_DWELL_TICKS * 3)
	if joined._status.text == "":
		ok = _fail("a refusal aged out of the toast, so a player can miss the one sentence the log "
				+ "cannot tell them")
	joined.queue_free()
	return ok


## Step an offline screen's world by feeding it the `Tick` frames a relay would have sent, the same
## way `test_buttons.gd` does. Empty input lists: this is about the clock, not about commands.
func _step_the_world(screen: Node, count: int) -> void:
	for _i in range(count):
		var at: int = screen._sim.tick()
		screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": []}}))


## **A REFUSAL IS STILL LOUD, which is the half that must NOT follow the ruling above** (ASSA-239).
##
## "No refusal is silent" is a standing rule here, and this is the branch it protects: a press that
## never reached the wire produces no sim event, so the status line is the only place a player can
## ever learn it happened. A fix that quietened `_act` all the way would pass the test above and lose
## this, which is why they are two tests and not one.
func test_a_command_that_never_reached_the_wire_still_says_so() -> bool:
	var ok := true
	var screen := _screen()
	# NOT JOINED: `AssayNetClient.submit` refuses, which is the real path rather than a stubbed one.
	screen._act("Mine", AssayActions.mine())
	if not screen._status.text.contains("not submitted"):
		ok = _fail("a command that never reached the wire said `%s`" % screen._status.text)
	if screen._base_level != AssayHud.Say.FAILED:
		ok = _fail("the refusal is not painted as a failure, so it reads as an instruction")
	screen.queue_free()
	return ok


## A HOST IN WHICH EXACTLY ONE BUILDING IS STOPPED, and nothing else is replaced.
##
## This file's `_SimSaying` idiom: one method overridden, so `_age_the_saying` runs the real decision
## over an answer this test chooses. **Stubbed for one reason only** — the headless suite cannot reach
## a world with a stalled building in it (the same limit `_rebuild_halt`'s tests are under), and both
## directions of this decision have to be covered or the test could not tell "ages when the condition
## clears" from "ages always". The real stall and the real recovery are measured end to end by
## `tools/toast_stall_probe.gd`, against a real sim, which is ASSA-300's box 4.
class _SimWhereOneBuildingIsStopped extends AssaySimHost:
	var stopped := -1

	func is_halted(building: int) -> bool:
		return building == stopped


## **A STALL SENTENCE COMES DOWN WHEN THE STALL DOES, AND A REFUSAL NEVER DOES** (ASSA-300, the Game
## Director's §300 ruling).
##
## The bug this closes: nothing in this client could clear a `Say.FAILED` line at all, so fuelling a
## smelter left `the Tonore smelter (A) stopped: no fuel` over the world while the pinned count beside
## it had already dropped to zero — the screen contradicting itself, with the reason on the false
## half.
##
## **FOUR MOMENTS, AND THE LAST IS THE ONE A CARELESS FIX LOSES.** A condition that holds must stay; a
## condition that clears must go, on the first ask and with no dwell; an act must never go; and an act
## said OVER a condition must survive that condition clearing. The fourth is only true because the
## building is an argument to `_say` rather than a field something else sets — which is the difference
## between a rule and two assignments that have to agree.
func test_a_stall_sentence_comes_down_when_the_stall_does_and_a_refusal_never_does() -> bool:
	var ok := true
	var screen := _screen()
	var sim := _SimWhereOneBuildingIsStopped.new()
	sim.stopped = 3
	screen._sim = sim
	var notice := "the Tonore smelter (A) stopped: no fuel"

	# 1. WHILE IT IS TRUE IT STAYS, asked many times. A sentence that went on the second look would
	#    be a dwell wearing a condition's clothes.
	screen._say(notice, AssayHud.Say.FAILED, 3)
	for _i in range(5):
		screen._age_the_saying()
	if screen._status.text != notice:
		ok = _fail(("a stall notice came down while the sim still called that building stopped: `%s`. "
				+ "The one surface carrying the reason would go blank with the machine still cold.")
				% screen._status.text)

	# 2. THE TICK IT IS FIXED, IT GOES -- no dwell, because this is not about having been read. A
	#    false sentence is worse the longer it is legible.
	sim.stopped = -1
	screen._age_the_saying()
	if screen._status.text != "":
		ok = _fail(("the smelter is working and the toast still reads `%s`. This is the whole of "
				+ "ASSA-300: the pinned count has already dropped to zero.") % screen._status.text)

	# 3. AN ACT IN THE SAME HEALTHY WORLD DOES NOT MOVE (ASSA-239: a failure that faded out would be
	#    the one class of sentence a player cannot recover).
	screen._say("refused: nothing there", AssayHud.Say.FAILED)
	for _i in range(5):
		screen._age_the_saying()
	if screen._status.text == "":
		ok = _fail("a refusal aged out of the toast because no building was stopped, so every "
				+ "sentence in the client just became a condition")

	# 4. AND AN ACT SAID OVER A CONDITION KEEPS ITS OWN KIND. Stall, then a refusal wins the line
	#    (newest wins, `_remember_events`), then the stall clears: the refusal must still be there.
	#    This is the leak a `_said_about_building` set anywhere but `_say` would have.
	sim.stopped = 3
	screen._say(notice, AssayHud.Say.FAILED, 3)
	screen._say("refused: out of reach", AssayHud.Say.FAILED)
	sim.stopped = -1
	screen._age_the_saying()
	if screen._status.text != "refused: out of reach":
		ok = _fail(("a refusal said over a stall notice read `%s` after the stall cleared: the "
				+ "sentence on screen was taken down by something that happened to a different "
				+ "sentence") % screen._status.text)
	screen.queue_free()
	return ok


## **AND THE JOINED DWELL IS UNTOUCHED BY ALL OF THAT.** `_age_the_saying` now has two clauses, and
## the cheap mistake is to let the new one swallow the old: a `JOINED` line carries no building, so it
## must still age on the dwell and not instantly.
##
## The control is in the same test: a `JOINED` line asked BEFORE the dwell is up must still be there.
## Without it, "ages on the dwell" and "ages on the first ask" are the same green.
func test_a_joined_line_still_ages_on_the_dwell_and_not_on_the_first_ask() -> bool:
	var ok := true
	var joined := _joined_screen()
	joined._say("walking to 57, 59", AssayHud.Say.JOINED)
	joined._age_the_saying()
	if joined._status.text == "":
		ok = _fail("a healthy sentence went on the first ask, so the dwell is gone and nothing on "
				+ "this screen can be read before it disappears")
	_step_the_world(joined, joined.SAYING_DWELL_TICKS + 1)
	if joined._status.text != "":
		ok = _fail("a healthy sentence outlived its dwell by the condition clause taking it over: `%s`"
				% joined._status.text)
	joined.queue_free()
	return ok


## **THE POKE IN `_drawn_color` IS LOAD-BEARING, AND TODAY NO COLOUR CAN PROVE IT** (ASSA-246).
##
## Our theme is a PROJECT theme, and a control themed that way ignores its own
## `theme_type_variation` until it receives `NOTIFICATION_THEME_CHANGED` -- `_process` frames do not
## deliver it. Four contrast sweeps read every label in the window through `_drawn_color`, including
## all 7 `Heading`s and the 1 `Display`.
##
## **THEY CAME BACK CORRECT BY COINCIDENCE.** `_style_label` sets plain `Label`'s `font_color` to
## `INK`, and `Heading` and `Display` are `INK` too, so reading the base type returned the
## variation's answer by luck. **No COLOUR assertion on this build can catch the poke being removed**
## -- there is no Label variation whose ink differs from `Label`'s for a test to catch it with.
## Saying so is the point of this test rather than a reason to skip it.
##
## **BUT A SIZE ASSERTION CAN, AND SINCE ASSA-252 THIS ONE DOES.** When ASSA-246 shipped, part 1
## below poked its own probe by hand, so it proved that POKING works and said nothing about whether
## `_drawn_color` does it: deleting the poke with nothing retuned stayed green, and I filed that as
## prophylactic. The poke now lives in `_poke_theme`, this reads through `_drawn_font_size`, and
## removing it reddens here by name with no retune and no new colour.
##
## **SO IT ASSERTS THE TWO THINGS THAT ARE ACTUALLY CHECKABLE.**
##
## 1. **THE MECHANISM IS LIVE AND THE HELPER IS WHAT APPLIES IT**, shown on `font_size`, where
##    `Heading` (15) and `Label` (13) do differ: a raw read reports the base type's size and a read
##    through the helper reports the variation's. If that ever stops differing, Godot has changed
##    this behaviour and the poke can be deleted -- the failure message says so, so a future reader
##    gets an instruction and not a puzzle.
## 2. **THE COINCIDENCE IS DECLARED, AND THE GUARD GROWS TEETH THE DAY IT ENDS.** For every Label
##    variation, either its ink equals `Label`'s -- recorded here as a known coincidence -- or
##    `_drawn_color` must demonstrably return the variation's ink and not the base type's. The second
##    branch is dead code today and becomes the real assertion the moment anybody retunes a heading,
##    which Maren has already done once (`INK_MUTED` -> `INK`, ASSA-224). Nacre's tab strip will add
##    variations whose colours do NOT coincide, and they will land straight in branch two.
## **EVERY COLOUR THE ENGINE WOULD OTHERWISE PICK FOR A `LineEdit` IS NAMED BY US** (ASSA-315).
##
## **THE LIST IS ASKED FOR, NOT TYPED, AND THAT IS THE WHOLE POINT.** A hand-written list of the
## three colours ASSA-315 happened to notice would only ever check the three somebody remembered —
## the same defect as the bug it guards, one level up (ASSA-304's lesson, and my own). So the
## expected set comes from `ThemeDB.get_default_theme()`: whatever Godot declares for `LineEdit` is
## exactly the set of colours it will draw for us if we stay quiet, today and after an engine
## upgrade that invents a fourth.
##
## It asserts only that each is DECLARED, never what it equals: the values are the Game Director's
## and live in `build_theme.gd` beside her reasons. A test that pinned them here would be a second
## place to change her mind.
func test_the_theme_names_every_line_edit_colour_the_engine_would_otherwise_pick() -> bool:
	var theme: Theme = load("res://theme/assay.tres")
	if theme == null:
		return _fail("no theme/assay.tres to read declared values from")
	var fallback := ThemeDB.get_default_theme()
	if fallback == null:
		return _fail("no default theme to ask, so this test cannot know what the engine would pick")
	var engine_picks := fallback.get_color_list("LineEdit")
	if engine_picks.is_empty():
		return _fail(("the engine declares NO LineEdit colours, so this test would pass against a "
				+ "theme that declares none either: the premise is gone, not the defect"))
	# **THE THREE THE GAME DIRECTOR HAS NOT RULED YET, NAMED OUT LOUD RATHER THAN QUIETLY PASSED.**
	# Asking the engine found more than ASSA-315 set out to fix: Godot declares NINE LineEdit
	# colours and her ruling covers three. These are the remainder. They are not a tolerance — the
	# test still fails for any colour outside this list, so an engine upgrade that invents a tenth
	# lands here, and it ALSO fails once one of these is declared, so the list cannot rot into a
	# permanent excuse. It shrinks to empty the day she rules them.
	const UNRULED := ["font_outline_color", "clear_button_color", "clear_button_color_pressed"]
	var undeclared := PackedStringArray()
	for name in engine_picks:
		if not theme.has_color(name, "LineEdit") and not UNRULED.has(name):
			undeclared.append(name)
	var stale := PackedStringArray()
	for name in UNRULED:
		if theme.has_color(name, "LineEdit"):
			stale.append(name)
	if not stale.is_empty():
		return _fail(("%s is declared now but still listed as unruled, so this test is excusing a "
				+ "colour somebody already chose. Delete it from UNRULED.") % ", ".join(stale))
	if undeclared.is_empty():
		return true
	return _fail(("the theme leaves %d of the engine's %d LineEdit colours undeclared and unruled, "
			+ "so Godot chooses them and nobody here did: %s. Declare them in "
			+ "`build_theme.gd::_style_line_edit` and rebuild the theme.")
			% [undeclared.size(), engine_picks.size(), ", ".join(undeclared)])


func test_the_theme_poke_is_load_bearing_and_the_sweeps_coincidence_is_declared() -> bool:
	var screen := _screen()
	var ok := true
	var theme: Theme = load("res://theme/assay.tres")
	if theme == null:
		screen.queue_free()
		return _fail("no theme/assay.tres to read declared values from")

	# 1. THE MECHANISM, ON A PROPERTY WHERE THE TWO TYPES DISAGREE.
	var probe := Label.new()
	probe.theme_type_variation = &"Heading"
	screen.add_child(probe)
	# The un-poked read is deliberately RAW -- it models a caller who does not use the helper. The
	# poked one goes through `_drawn_font_size`, and therefore through `_poke_theme`, so this
	# assertion fails if the poke ever leaves the helper. It used to poke `probe` itself, which
	# proved that poking works and left the helper's own line uncovered (ASSA-252).
	var unpoked := probe.get_theme_font_size(&"font_size")
	var poked := _drawn_font_size(probe)
	var declared_heading := theme.get_font_size(&"font_size", &"Heading")
	var declared_label := theme.get_font_size(&"font_size", &"Label")
	if poked != declared_heading:
		ok = _fail(("a poked `Heading` label reports font_size %d, not the theme's declared %d: the "
				+ "poke does not resolve the variation and `_drawn_color` cannot be trusted")
				% [poked, declared_heading])
	elif unpoked == poked:
		ok = _fail(("an UN-poked `Heading` label already reports %d, the variation's own size. The "
				+ "project-theme behaviour ASSA-246 is about has changed -- GOOD NEWS: delete the "
				+ "`notification()` line in `_drawn_color` and this assertion with it.") % unpoked)
	elif unpoked != declared_label:
		ok = _fail(("an un-poked `Heading` label reports %d, which is neither the variation's %d nor "
				+ "the base type's %d. The fallback is not what ASSA-246 measured, so re-measure "
				+ "before trusting any headless theme read") % [unpoked, declared_heading,
				declared_label])

	# 2. EVERY LABEL VARIATION: EITHER A DECLARED COINCIDENCE, OR THE POKE IS PROVED ON IT.
	var coincident := PackedStringArray()
	for v in [&"Heading", &"Display"]:
		var base := theme.get_color(&"font_color", &"Label")
		var mine := theme.get_color(&"font_color", v)
		var tell := Label.new()
		tell.theme_type_variation = v
		screen.add_child(tell)
		var drawn := _drawn_color(tell)
		if mine.is_equal_approx(base):
			# KNOWN COINCIDENCE. Recorded, not asserted away: a sweep reading this label cannot tell
			# a working poke from a broken one, and the poke is what makes it safe to retune.
			coincident.append(String(v))
		elif not drawn.is_equal_approx(mine):
			ok = _fail(("`%s`'s ink %s differs from `Label`'s %s, and `_drawn_color` returned %s -- "
					+ "the base type's. The contrast sweeps are now measuring the wrong colour for "
					+ "every `%s` in the window (ASSA-246)") % [v, mine, base, drawn, v])
		tell.queue_free()
	print("    ASSA-246: Label variations whose ink coincides with `Label`'s, so the sweeps cannot "
			+ "prove the poke: %s" % [", ".join(coincident) if coincident.size() > 0 else "none"])
	screen.queue_free()
	return ok


## **THE MINERALOGY TAB IS THE SIM'S ANSWER WITH THE ROCKS LIST AS ITS EVIDENCE** (ASSA-241's ruling,
## wiring Limpet's ASSA-254 body into ASSA-247's strip).
##
## `test_mineralogy.gd` owns the body in isolation and cannot see this: every one of its tests builds
## `AssayMineralogy.new()` directly, so a `main.gd` that never put the body in the strip, or that left
## `_species` hanging beside it as a fifth section, passes all six of them. What this asks is the
## COMPOSITION -- that the one object in the tab is his body and the list is INSIDE his evidence box.
##
## **AND THE CONTROL ORDER, WHICH IS MAREN'S RULING AND WREN'S FOLD RULE IN ONE ASSERTION**: `go here`
## is the tab's only control and the evidence list is unbounded (my own measurement: ~651 px of rows
## against a 313 px worst-case budget), so a control UNDER it is below the fold by construction. Asked
## as child order and not as a `position`, because this suite has no layout pass and every rect in it
## reads 0.0 -- the geometry belongs to `tools/nacre_tab_budget_probe.gd`.
func test_the_mineralogy_tab_is_the_answer_with_the_rocks_list_as_its_evidence() -> bool:
	var screen := _screen()
	var ok := true
	var body: Control = screen._tabs.body_of("mineralogy")
	if body == null:
		screen.queue_free()
		return _fail("there is no `mineralogy` tab, so Rainy's index has nowhere to open")
	# THE BODY HOLDS HIS OBJECT, found by type rather than by index: the strip wraps every entry in a
	# `VBoxContainer`, so this walks down to the thing that matters instead of guessing the depth.
	var found: Array = body.find_children("*", "AssayMineralogy", true, false)
	if found.size() != 1:
		ok = _fail(("the mineralogy tab holds %d `AssayMineralogy` bodies, want exactly 1: ASSA-254's "
				+ "body is the tab, not a decoration beside it") % found.size())
	elif found[0] != screen._mineralogy:
		ok = _fail("the tab holds a DIFFERENT AssayMineralogy than the screen refreshes, so the one on "
				+ "screen would never be updated")
	elif not screen._mineralogy.evidence.is_ancestor_of(screen._species):
		ok = _fail(("the rocks list is not inside the answer's evidence box (its parent is `%s`): "
				+ "Mineralogy IS this column's `rocks` with the headline on top, not a tab beside it")
				% screen._species.get_parent())
	else:
		# CONTROLS ABOVE THE LIST. Both are children of his body, so this is one index comparison.
		var kids: Array = screen._mineralogy.get_children()
		if kids.find(screen._mineralogy.go_here) > kids.find(screen._mineralogy.evidence):
			ok = _fail("`go here` sits below the evidence list, which is unbounded: Wren's rule is that "
					+ "no control is ever below the fold, and a list may scroll only because it has none")
		if kids.find(screen._mineralogy.headline) != 0:
			ok = _fail("the headline is not the first thing in the tab: child 0 is `%s`"
					% kids[0].name)
	screen.queue_free()
	return ok


## **THE HEADLINE IS REWRITTEN ON EVERY REFRESH, NOT CACHED BEHIND THE SPECIES SHEETS** (ASSA-254
## wired into ASSA-247), and this is the test for the mistake I was one line away from making.
##
## `_refresh_species` returns early unless the species SHEETS changed, which is right for the rows: a
## sheet moves about twice a session. The headline is not like the rows -- it carries a distance and a
## heading from where the player is STANDING, so calling `show_answer` inside that guard would freeze
## the sentence the moment the player started walking toward the rock it named, and every test that
## only reads it once after a join would still pass.
##
## **SO THE SHEETS ARE HELD STILL AND THE LABEL IS POISONED.** A refresh that routes through the
## species cache cannot repair it; one that asks the binding every time can. That is the mutation this
## catches, asserted without needing the player to walk a tile.
##
## It also pins the half `test_mineralogy.gd` cannot reach: that the text on the REAL screen is the
## binding's own `headline`, with `main.gd` adding nothing to it.
func test_the_mineralogy_headline_is_rewritten_on_every_refresh_not_behind_the_species_cache() -> bool:
	var screen := _joined_screen("14247")
	screen._refresh()
	var ok := true
	var id: int = screen._client.player_id
	if not screen._sim.running() or id < 0:
		screen.queue_free()
		return _fail("premise: nothing is being simulated, so there is no answer to render")
	var answers: Array = screen._sim.proximity_answers(id)
	if answers.is_empty():
		screen.queue_free()
		return _fail("premise: the binding answered nothing for a player who is in the world")
	var expected := String((answers[0] as Dictionary).get("headline", ""))
	if expected == "":
		screen.queue_free()
		return _fail("premise: the binding sent an empty headline, which the sim never produces")
	if screen._mineralogy.headline.text != expected:
		ok = _fail("the tab reads `%s` and the binding says `%s`"
				% [screen._mineralogy.headline.text, expected])
	# NOW HOLD THE SHEETS STILL AND BREAK THE LABEL. `_species_showing` is the species cache's own
	# signature; leaving it untouched is what makes this a test of the OTHER path.
	var cached_before: String = screen._species_showing
	screen._mineralogy.headline.text = "a sentence no sim ever produced"
	screen._refresh()
	if screen._species_showing != cached_before:
		ok = _fail("the species cache changed during the refresh, so this test did not hold the sheets "
				+ "still and proves nothing about the headline's own path")
	elif screen._mineralogy.headline.text != expected:
		ok = _fail(("a refresh left the headline reading `%s`: the answer is cached behind the species "
				+ "sheets, so it would freeze as soon as the player walked") % screen._mineralogy.headline.text)
	screen.queue_free()
	return ok


## **THE STATUS PALETTE IS REACHABLE BY A TEST AT ALL, WHICH IT WAS NOT** (ASSA-251 box 4, Maren).
##
## `AssayHud.status_color` returns four raw `Color` literals in `hud.gd`, OUTSIDE the theme's named
## set. `tools/build_theme.gd` refuses to WRITE a theme whose own inks miss 4.5:1 — and these never
## went through it, so a 3.983:1 sentence shipped past a repo that has a guard for exactly this.
## Maren's words on why no sweep caught it: *"a contrast test could only ever check one of them."*
##
## THIS IS THE DECLARED HALF, asked of every state rather than the one that was broken. Measured
## against the toast's own panel. Three of the four were always above the floor, which is the reason
## the defect survived: it bit only `FAILED`, the one state whose job is to say the game stopped.
func test_every_status_colour_clears_the_floor_on_the_panel_it_is_drawn_on() -> bool:
	var ok := true
	var panel := _panel_surface()
	var worst := 99.0
	var worst_named := ""
	# EVERY VALUE OF THE ENUM, from the enum, so a fifth state added without a colour fails here.
	for entry in AssayHud.Say.values():
		var level: int = entry
		var ink: Color = AssayHud.status_color(level)
		var ratio := AssayHud.contrast_ratio(ink, panel)
		if ratio < worst:
			worst = ratio
			worst_named = "level %d %s" % [level, ink]
		if ratio < 4.5:
			ok = _fail(("status_color(%d) is %s, which is %.3f:1 on the panel it is drawn on and "
					+ "under the 4.5 floor build_theme.gd enforces on every other ink")
					% [level, ink, ratio])
	print("    ASSA-251: the dimmest declared status colour is %s at %.3f:1" % [worst_named, worst])
	return ok


## **A SWEEP FINALLY VISITS THE DROPPED SCREEN, AND READS WHAT IS DRAWN** (ASSA-251 boxes 2, 3, 7).
##
## **NO SWEEP HAS EVER BEEN TO THIS STATE**, which is the actual hole — the colour was the symptom.
## The dropped screen is the one screen whose entire job is to tell you the game stopped, and it was
## neither shot nor swept until Nacre photographed it for ASSA-245 and Maren measured the picture.
##
## **IT READS THE DRAWN COLOUR, NOT THE CONSTANT BEHIND IT.** `_drawn_color` multiplies `font_color`
## by `modulate`, which is the whole point: the defect was `modulate = status_color(...)` multiplying
## the theme's `INK`, so a test that read `status_color` alone — or `font_color` alone — would have
## passed over it. Maren's control is why the cause was never in doubt: on the same shot headings
## reached `INK` and body rows `INK_MUTED` with shortfall 0.000, so glyph rendering was not it.
##
## AND THE SURFACE IS THE ONE REALLY BEHIND THE LABEL (`_surface_behind`, ASSA-152's lesson), not the
## theme's declaration of a panel: the toast is a `PanelContainer` over the world, so a reading taken
## against the wrong backdrop would be a number about nothing.
func test_the_dropped_screens_failure_sentence_is_drawn_above_the_floor() -> bool:
	var joined := _joined_screen()
	joined._process(0.016)
	# THE DROP, THROUGH THE REAL LINK: a `Refused` frame is what kills it, the same route
	# `test_the_join_band...` uses rather than a stage poked by hand.
	joined._client.feed_offline('{"Refused":{"reason":"the relay went away"}}')
	if joined._client.stage != AssayNetClient.Stage.DEAD:
		joined.queue_free()
		return _fail("the Refused frame did not kill the link, so the dropped screen was never built")
	joined._process(0.016)
	var ok := true
	if joined._status.text == "":
		ok = _fail("the dropped screen says nothing, so there is no sentence to measure")
	var drawn := _drawn_color(joined._status)
	var behind: Variant = _surface_behind(joined._status)
	if behind == null:
		ok = _fail("nothing behind the status label resolves a panel, so the reading has no backdrop")
	else:
		var ratio := AssayHud.contrast_ratio(drawn, behind as Color)
		if ratio < 4.5:
			ok = _fail(("the dropped screen's sentence is DRAWN at %s, %.3f:1 on %s. Maren measured "
					+ "3.983:1 here, below even the 4.091 the board called hard on the eyes "
					+ "(ASSA-251)") % [drawn, ratio, behind])
		else:
			print("    ASSA-251: dropped sentence drawn %s at %.3f:1 on %s" % [drawn, ratio, behind])
	# AND THE MULTIPLIER IS GONE, not merely overridden. A `modulate` left behind would scale whatever
	# the override states, which is the same defect wearing a different line.
	if not joined._status.modulate.is_equal_approx(Color.WHITE):
		ok = _fail(("the status label still carries modulate %s: it multiplies the colour this line "
				+ "states, so the colour on screen is nobody's decision") % joined._status.modulate)
	joined.queue_free()
	return ok


## **WITH NO SESSION THE ONE GREEN THING IS THE WAY BACK IN** (ASSA-251 box 5, Maren).
##
## Nacre's shot had `Mine` green AND `Play solo` green at the same moment. `minable` is the sim's bit
## about the ROCK and knows nothing about whether a relay is listening, so with the link dead
## pressing `Mine` reaches `_act` -> `submit` fails -> *"not submitted; join a world first"*. That is
## the clause ASSA-233 turns on: **a green button that refuses is worse than a grey one that
## refuses** — and here the live-looking green was the dead one.
##
## ASSERTED ON THE REAL TREE AND BY NAME, not as a count: "exactly one" with no name would stay green
## if the accent moved to the wrong control, and the whole ruling is about WHICH one it is.
func test_a_dropped_screen_has_one_primary_and_it_is_the_way_back_in() -> bool:
	var joined := _joined_screen("14247")
	joined._process(0.016)
	var ok := true
	# THE CONTROL FIRST: on 14247 the body spawns on a minable deposit, so `Mine` IS accented while
	# the session is live. Without this the test below could pass on a world where it never was.
	var live := _accented(joined)
	if not live.has("Mine"):
		joined.queue_free()
		return _fail(("seed 14247 does not accent `Mine` while joined (%s), so the dropped arm "
				+ "cannot show that the drop is what removed it") % [", ".join(live)])
	joined._client.feed_offline('{"Refused":{"reason":"the relay went away"}}')
	if joined._client.stage != AssayNetClient.Stage.DEAD:
		joined.queue_free()
		return _fail("the Refused frame did not kill the link")
	joined._process(0.016)
	var after := _accented(joined)
	if after.size() != 1:
		ok = _fail(("a dropped screen shows %d accented controls: %s. One green thing to press, and "
				+ "with no session it is the way back in") % [after.size(), ", ".join(after)])
	elif after[0] != "Play solo":
		ok = _fail(("the dropped screen's one accented control is `%s`, not the way back in")
				% after[0])
	if after.has("Mine"):
		ok = _fail("`Mine` is still green with the link dead, where pressing it can only refuse")
	joined.queue_free()
	return ok


## **NOTHING ANYWHERE IN THE COLUMN MAY ASK FOR MORE WIDTH THAN THE COLUMN HAS** (ASSA-247), which
## is the test that would have caught the defect a 1x shot caught instead.
##
## **WHAT HAPPENED, because the shape of the hole is the point.** The cursor readout is a `Label` and
## it was added through `AssayTabStrip.add_footer`, which is not `add_tab`, so it missed the autowrap
## every tab body gets in `_build_ui`. An unwrapped Label's minimum width is its longest line --
## **434 px against a 320 px panel**. A container sizes its child to `max(available, minimum)` and a
## `ScrollContainer` with horizontal scrolling DISABLED folds its content's minimum into its own, so
## that one Label pushed the scroll box to 438 px and dragged every ancestor out with it. On the shot
## the column's ink ran to the window's last pixel on **77 rows**, and `_log_toggle` -- which is in the
## chrome and not in any tab -- was pulled out too.
##
## **THE EXISTING WIDTH TEST COULD NOT SEE IT AND STILL CANNOT**, which is why this is a second one
## rather than an edit: `test_no_row_asks_for_more_width_than_the_panel_that_clips_it` walks the direct
## children of four named sections. The offender was a child of the strip's bodies box, in no section
## at all, and the containers that carried the damage are not rows. So this sweeps EVERY `Control`
## under the painted surface, containers included, and names the deepest one -- an ancestor is only
## reporting what a child demanded.
##
## Minimum width is content-derived and needs no layout pass, which is the one geometry question this
## headless suite may honestly ask (every `position` and `size` here reads 0.0).
func test_nothing_in_the_column_asks_for_more_width_than_the_panel() -> bool:
	var screen := _joined_screen("14247")
	screen._refresh()
	var ok := true
	if not screen._sim.running():
		screen.queue_free()
		return _fail("premise: no world, so the tab bodies hold empty notes and cannot ask for width")
	# WITH A PACK IN IT, because an empty section cannot overflow and the demo's richest row is the
	# one that historically did (ASSA-98's 358 px pack row).
	screen._rebuild_pack([
		{"kind": "refined", "species": 4, "grade": "B", "count": 6, "name": "Minyte refined (B)"},
		{"kind": "ore", "species": 4, "grade": "B", "count": 22, "name": "Minyte ore (B)"},
	])
	var worst: Control = null
	var worst_w := 0.0
	var worst_path := ""
	var checked := 0
	var stack: Array = [[screen._column, "", 0]]
	var deepest := -1
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node = entry[0]
		var path: String = entry[1]
		var depth: int = entry[2]
		var control := node as Control
		if control != null:
			checked += 1
			var want := control.get_combined_minimum_size().x
			# THE DEEPEST OFFENDER WINS, not the widest: the widest is usually the outermost container
			# passing the demand upward, and fixing that one would only hide the child that made it.
			if want > AssayHud.PANEL and depth > deepest:
				deepest = depth
				worst = control
				worst_w = want
				worst_path = path
		for child in node.get_children():
			stack.append([child, "%s/%s" % [path, child.name], depth + 1])
	if checked < 10:
		ok = _fail("only %d controls were measured under the column, so this sweep proves nothing"
				% checked)
	elif worst != null:
		ok = _fail(("`%s` (%s) asks for %.0f px inside a %.0f px panel that clips and does not scroll "
				+ "sideways, so its right-hand end is off the window: %s")
				% [worst_path, worst.get_class(), worst_w, AssayHud.PANEL,
				(worst as Label).text if worst is Label else "not a Label"])
	screen.queue_free()
	return ok


## **THE DOOR KEEPS REFRESHING ITSELF WITH NO SESSION** (ASSA-292), which is a claim about a CALL and
## not about arithmetic.
##
## THIS TEST EXISTS BECAUSE THREE GREEN TESTS DID NOT CATCH A DEAD SCREEN. `AssayScene.title_drift` is
## asserted three ways -- periodic, bounded, continuous -- and every one of them passed while the
## title camera never moved a pixel, because `_process` refreshed the world only
## `if _close_up and _sim.running()` and there is no session at the door. The arithmetic was right and
## nothing called it; a unit test on a pure function cannot tell those apart. The same guard also hid
## the door plate, which is sized from laid-out children and so can only be computed after a layout
## pass -- it ran once inside `_ready()`, found every child 0x0, and hid itself for good.
##
## So this asserts the only thing that would have gone red: that a frame at the door rebuilds the
## view. It blanks `_world.view` by hand and demands `_process` put it back.
func test_the_door_keeps_refreshing_itself_with_no_session() -> bool:
	var screen: Node = load("res://scenes/main.tscn").instantiate()
	runner.root_node.add_child(screen)
	screen._ready()
	if screen._sim.running():
		screen.queue_free()
		return _fail("this test is about the doorless case and the scene came up with a session")
	screen._world.view = {}
	screen._process(0.016)
	var after: Dictionary = screen._world.view
	screen.queue_free()
	if after.is_empty():
		return _fail("a frame at the door left the view empty: nothing is driving the title world, "
				+ "so the camera cannot drift and the plate can never be sized. The guard in "
				+ "_process is asking for a session that the door does not have")
	return true


## **THE FIRST SCREEN SAYS WHAT THE GAME IS CALLED** (ASSA-116 box 4; Maren's finding 2 on that item,
## 2026-10-03: a developer telemetry line had the best seat on the screen "including the game's name,
## which appears nowhere at all. A build that opens without saying what it is reads as a tool").
##
## **THE TITLE IS THE PROJECT'S OWN NAME AND NOT A TYPED COPY OF IT**, and the second half of that
## is asserted by renaming the project under a second screen -- because `text == the project name` is
## satisfied by a literal "Assay" for exactly as long as the game is called Assay. A literal here
## would survive the game being renamed and the first screen would then be the one place still using
## the old name. `project.godot` is also what names the exported `Assay.app`, so this ties the
## window's title to its bundle.
##
## Nothing here pins the SENTENCE under it. `test_the_empty_map_names_which_kind_of_empty_it_is`
## asserts the note is `AssayHud.empty_map_line()`, and the wording inside that function is the Game
## Director's to re-rule -- a test that froze her words would turn her next ruling into a red suite,
## which is the same reason `sim/tests/proximity.rs` refuses to pin a headline.
func test_the_join_screen_names_the_game() -> bool:
	var screen := _screen()
	var ok := true
	var title: Label = screen._door_title
	var want := String(ProjectSettings.get_setting("application/config/name", ""))
	if want.strip_edges() == "":
		ok = _fail("premise: project.godot declares no application/config/name, so there is no name "
				+ "for the first screen to carry")
	elif title == null:
		ok = _fail("the join screen has no title at all")
	elif not _on_screen(title):
		ok = _fail("the join screen has a title that is not on it")
	elif title.text != want:
		ok = _fail("the title says '%s' and the project is called '%s'" % [title.text, want])
	elif screen._front_door == null or not screen._front_door.is_ancestor_of(title):
		ok = _fail("the title is not part of the front door, so the composition it heads is not its")
	else:
		# AND IT HEADS THE DOOR: above the sentence that names the two ways in, by the door's own
		# order rather than by a y coordinate, which a layout change may legitimately move.
		var order: Array = screen._front_door.get_children()
		if order.find(title) > order.find(screen._map_note):
			ok = _fail("the title is below the sentence, so the screen explains itself before it "
					+ "says what it is")
		# **AND IT FOLLOWS THE NAME RATHER THAN COPYING IT, which everything above fails to hold.**
		# `title.text == want` is satisfied by a literal "Assay" for exactly as long as the game is
		# called Assay, so without this the docstring above would claim a property the test does not
		# have -- which is the defect shape this suite keeps finding in other people's checks. So the
		# project is renamed, a second screen is stood up, and the name is put back BEFORE anything is
		# asserted, so a failure here cannot leave the setting broken for the tests after it.
		ProjectSettings.set_setting("application/config/name", "Nominal")
		var renamed := _screen()
		var carried := String((renamed._door_title as Label).text)
		ProjectSettings.set_setting("application/config/name", want)
		renamed.queue_free()
		if carried != "Nominal":
			ok = _fail(("the title reads '%s' on a project renamed to 'Nominal', so it is a typed "
					+ "copy of the name and would outlive the game being renamed") % carried)
	screen.queue_free()
	return ok


## **THE COMMIT BAR IS ONE RECT HOLDING TWO THINGS, THE SENTENCE LEFT AND `Build` RIGHT** (ASSA-332;
## Maren's §5.4 ruling 3, which moved this rect after slice 1 had shipped it as a 56 px strip).
##
## **THE PIXELS ARE NOT CHECKABLE HERE AND THE STRUCTURE IS.** Nothing in this suite has a size
## (`_place_build_screen`'s docstring: a node's rect is `(0,0,0,0)` until a window lays it out), so
## `tools/limpet_build_screen_shot.gd` is what measures y 529..641 and Build's 160 px ceiling on a
## real window. What this holds is the half that would silently come apart in a refactor: `Build`
## back in the screen's own column, or the sentence drawn under the button instead of beside it.
func test_the_commit_bar_holds_the_sentence_left_and_build_right() -> bool:
	var screen := _screen()
	var ok := true
	var bar: Control = screen._build_bar
	if bar == null:
		ok = _fail("the screen has no commit bar at all")
	elif screen._build_said.get_parent() != bar or screen._build_act.get_parent() != bar:
		ok = _fail("the sentence and `Build` are not both in the bar, so they are not one rect")
	elif bar.get_child(0) != screen._build_said or bar.get_child(1) != screen._build_act:
		ok = _fail("the bar holds %s; §5.4 puts the sentence left and `Build` right"
				% [bar.get_children()])
	elif screen._build_act.size_flags_horizontal != Control.SIZE_SHRINK_END:
		ok = _fail("`Build` is not pinned to the bar's right end (flags %d), so the sentence's floor "
				% screen._build_act.size_flags_horizontal + "is not the width it was measured at")
	elif not is_equal_approx(bar.custom_minimum_size.y, AssayHud.BUILD_COMMIT_BAR):
		ok = _fail("the bar asks for %.0f px of height and her rect is %.0f"
				% [bar.custom_minimum_size.y, AssayHud.BUILD_COMMIT_BAR])
	elif bar.get_parent() != screen._build_title.get_parent().get_parent():
		ok = _fail("the bar is not a block of the screen beside the title row; it is under %s"
				% bar.get_parent())
	if ok:
		# **AND THE SENTENCE'S FLOOR IS DERIVED FROM THE REAL SCREEN AND THE REAL GUTTER** (box 5): the
		# 687 Maren measured the wrap at is written down nowhere in the client, so it is asserted here
		# out of `build_screen_rect`'s own width and `BUILD_GUTTER` itself. Moving either moves this.
		var world := AssayHud.world_rect()
		var band := world.end.y - AssayHud.WORLD_CONTROLS_BAND
		var wide: float = AssayHud.build_screen_rect(world, band).size.x
		var owed: float = AssayHud.commit_sentence_width(wide, float(screen.BUILD_GUTTER))
		if owed < 687.0:
			ok = _fail(("the screen is %.0f px wide with a %d px gutter, so the sentence's floor is "
					+ "%.0f px, under the 687 Maren measured the wrap at") % [wide, screen.BUILD_GUTTER, owed])
	screen.queue_free()
	return ok
## **THE BUILD SCREEN IS PLACED AGAIN WHEN ITS OWN MINIMUM MOVES, AND A REAL WINDOW IS WHY** (ASSA-332).
##
## **WHAT WAS MEASURED, because nothing in this suite can see it.** A `Control`'s `size` is clamped up
## to its combined minimum at the instant it is assigned, and right after a rebuild that minimum is
## briefly the whole content -- the rows are in the tree before the `ScrollContainer`s have been told
## they can absorb them. `tools/limpet_build_screen_shot.gd` in a 1280x720 window: the box was asked
## for **864 x 592 and came out 864 x 1042**, hanging 450 px past the world's own control band and
## **covering the status toast by 113 x 32 px** -- the one thing Maren's §1 forbids. One frame later
## the same box reports a minimum of 276, so neither the rect nor the content was ever wrong.
##
## **THIS SUITE LAYS NOTHING OUT**, so every rect here is `(0,0,0,0)` and the pixels are the shot
## tool's job (it now faults on box-bigger-than-asked, and prints the chain of minimums that pays for
## the height). What a headless test CAN hold is the connection itself, because the way this defect
## comes back is somebody deleting a line whose comment they do not believe.
##
## **AND IT IS `minimum_size_changed` RATHER THAN `call_deferred`, WHICH I MEASURED AS NO FIX**: the
## minimum's own recalculation is deferred too, so a deferred placement can run before it and be
## clamped by the same stale number.
func test_the_build_screen_is_replaced_when_its_own_minimum_moves() -> bool:
	var screen := _screen()
	var ok := true
	var box: Control = screen._build_box
	if box == null:
		ok = _fail("the screen has no build box at all")
	elif not box.minimum_size_changed.is_connected(screen._place_build_screen):
		ok = _fail("nothing re-places the build screen when its minimum drops, so the size assigned "
				+ "while the minimum was stale is the size it keeps -- measured at 864x1042 against a "
				+ "rect of 864x592, over the status toast")
	screen.queue_free()
	return ok
