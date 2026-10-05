extends SceneTree
## **DOES A REAL SOLO WORLD SURVIVE A REAL SESSION'S WORTH OF COMMANDS** (ASSA-219, found by Nerite).
##
##   godot --headless --path . --script res://tools/solo_flood_probe.gd -- [drained|undrained]
##
## The suite proves the DRAIN against a stand-in that floods a pipe
## (`test_solo_relay.gd::test_the_relays_log_is_drained_for_a_whole_session_and_never_blocks_its_host`).
## This proves the THING THE BOARD MET: the relay that ships, started by the real button, joined by
## the real client, sent thousands of real commands, each of which makes `sim-relay` print a line.
## A stand-in cannot do that -- it floods a pipe on my instruction, where the relay floods it as a
## consequence of being played, which is the sentence on the item.
##
## **TWO ARMS, AND THE SECOND IS WHY THE FIRST MEANS ANYTHING.** `drained` steps the screen's
## `_process`, which is what a running client does and what now calls `pump()`. `undrained` steps
## ONLY the net client, so nobody ever reads the relay's stdout -- the shipped behaviour before this
## fix, reproduced on the fixed build rather than by reverting it. If both arms keep ticking then the
## flood fitted in the pipe and this probe proved nothing, and it says so rather than printing OK.
##
## **IT IS A TOOL AND NOT A SUITE TEST, for `solo_probe.gd`'s reason**: it starts a process, binds a
## socket and leans on wall-clock time, and one flaky socket test in the thing CI runs on every push
## teaches everybody to re-run until it passes.
##
## PRINTS `SOLO FLOOD PROBE OK` LAST, or `SOLO FLOOD PROBE FAILED: <why>`. Godot exits 0 on almost
## anything, so a marker line printed last is the only honest verdict.

## A CEILING OF ITS OWN (ASSA-182). A tool that can wait on a socket can wait for ever, and a
## headless Godot nobody is watching does exactly that -- mine ran 45 minutes on a typo once.
const RUN_CEILING_MS := 180000

## ENOUGH COMMANDS TO BEAT THE PIPE TWICE OVER. The relay logs about 40 bytes per command; macOS and
## Linux pipes hold 64 KB, Windows anonymous pipes can hold 4 KB. 4000 is ~160 KB.
const COMMANDS := 4000

## HOW LONG THE WORLD IS WATCHED AFTER THE FLOOD. The question is not whether a tick arrived during
## the flood but whether the host is still alive at the end of it, which is the state a player is
## left in: frozen for good, no error, nothing to press.
const WATCH_MS := 2000

var _screen: Node = null
var _began := 0
var _quitting := false


func _process(_delta: float) -> bool:
	if not _quitting:
		print("FAIL  solo_flood_probe.gd: _initialize ended without asking to quit -- see above")
		quit(1)
	return true


func _initialize() -> void:
	_began = Time.get_ticks_msec()
	var arm := "drained"
	for a in OS.get_cmdline_user_args():
		arm = a
	if arm != "drained" and arm != "undrained":
		_done(false, "arm must be `drained` or `undrained`, not `%s`" % arm)
		return
	print("arm:     %s" % arm)

	var scene: PackedScene = load("res://scenes/main.tscn")
	_screen = scene.instantiate()
	root.add_child(_screen)
	_screen._ready()

	var binary := AssaySoloRelay.find_binary()
	if binary == "":
		_done(false, "no sim-relay found; looked in %s"
				% ", ".join(AssaySoloRelay.candidate_paths()))
		return
	print("relay:   %s" % binary)

	# PRESSED, NOT CALLED, for `solo_probe.gd`'s reason: a button wired to nothing fails here.
	var button := _find_button(_screen, "Play solo")
	if button == null:
		_done(false, "no `Play solo` button on the join screen")
		return
	button.pressed.emit()
	if _screen._solo == null:
		_done(false, "the press started nothing: %s" % _screen._status.text)
		return

	# JOIN FIRST, AND WITH THE SCREEN'S OWN `_process` IN BOTH ARMS. Reading the pipe until the
	# contract line is not the behaviour under test -- the bug is what happens AFTERWARDS -- and an
	# arm that never joined would fail for the wrong reason.
	var joined := false
	while Time.get_ticks_msec() - _began < 20000:
		_screen._process(0.016)
		if _screen._client != null:
			_screen._client._process(0.016)
		if _screen._solo != null and _screen._solo.failure != "":
			_done(false, "the relay refused: %s" % _screen._solo.failure)
			return
		if _screen._client != null and _screen._client.stage == AssayNetClient.Stage.JOINED:
			joined = true
			break
		OS.delay_msec(16)
	if not joined:
		_done(false, "never joined its own relay in 20 s: %s" % _screen._status.text)
		return
	print("joined:  %s as player %d" % [_screen._solo.address, _screen._client.player_id])

	# **THE FLOOD, AND IT IS MADE OF REAL COMMANDS.** Every accepted `MoveTo` makes `main.rs` call
	# `log()` -- a `println!` -- at line 396, so this is a line of relay stdout per command, which is
	# the shape of the defect rather than an imitation of it. Two tiles alternating so the walk
	# always has somewhere to go.
	var sent := 0
	var refused := 0
	for i in COMMANDS:
		var tile := Vector2i(56, 40) if i % 2 == 0 else Vector2i(57, 40)
		if _screen._client.submit(AssayActions.move_to(tile)):
			sent += 1
		else:
			refused += 1
		# THE FRAME LOOP, EACH ARM BEING ITSELF. The screen's `_process` is the one that drains.
		if arm == "drained":
			_screen._process(0.016)
		_screen._client._process(0.016)
		if Time.get_ticks_msec() - _began > RUN_CEILING_MS:
			_done(false, "ran past its %d s ceiling during the flood" % int(RUN_CEILING_MS / 1000))
			return
	print("sent:    %d commands (%d refused by the client)" % [sent, refused])
	if sent < COMMANDS / 2:
		_done(false, ("only %d of %d commands were sent, so the relay was never flooded and nothing "
				+ "below is a measurement") % [sent, COMMANDS])
		return

	# **IS THE HOST STILL TICKING.** Asked of the tick the sim reached, before and after, because a
	# relay blocked inside `run_tick` sends no more bundles and this client's tick stops dead.
	var before: int = _screen._sim.tick()
	var watch := Time.get_ticks_msec()
	while Time.get_ticks_msec() - watch < WATCH_MS:
		if arm == "drained":
			_screen._process(0.016)
		_screen._client._process(0.016)
		OS.delay_msec(16)
	var after: int = _screen._sim.tick()
	var alive: bool = _screen._solo != null and not _screen._solo.has_exited()
	print("ticks:   %d -> %d over %d ms (relay process alive: %s)" % [
			before, after, WATCH_MS, alive])

	# THE VERDICT, AND EACH ARM HAS THE OPPOSITE ONE. `undrained` is the control: it must FREEZE, or
	# the flood was not big enough and the drained arm's health says nothing about draining.
	if arm == "drained":
		if after <= before:
			_done(false, ("the world stopped at tick %d after %d commands -- the host is frozen, "
					+ "which is ASSA-219 still alive") % [after, sent])
			return
		print("verdict: the world is still ticking after %d real commands" % sent)
	else:
		if after > before:
			_done(false, ("THIS PROBE IS MEASURING NOTHING: with nobody reading its stdout the host "
					+ "still ticked %d -> %d, so %d commands did not fill the pipe. Raise COMMANDS.")
					% [before, after, sent])
			return
		print("verdict: unread, the host froze at tick %d and stayed there (the defect)" % after)
	_done(true, "")


func _find_button(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == label:
			return child
		var found := _find_button(child, label)
		if found != null:
			return found
	return null


func _done(ok: bool, why: String) -> void:
	# THE RELAY IS STOPPED ON EVERY PATH, failures included: a probe that leaves one holding a port
	# makes the next run fail for a reason that has nothing to do with the code.
	if _screen != null:
		_screen.stop_solo_relay()
	print("SOLO FLOOD PROBE OK" if ok else "SOLO FLOOD PROBE FAILED: %s" % why)
	_quitting = true
	quit(0 if ok else 1)
