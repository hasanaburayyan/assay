extends SceneTree
## PRESS PLAY SOLO, HEADLESS, AGAINST THE REAL RELAY (ASSA-106).
##
##   godot --headless --path . --script res://tools/solo_probe.gd
##
## The suite drives every REFUSAL with a stand-in process, because the real relay will not produce
## them on demand. This drives the one case the stand-ins cannot: the relay that actually ships,
## started by the real button, joined by the real client, stepping the real sim.
##
## **IT IS A TOOL AND NOT A SUITE TEST, deliberately.** It starts a process, binds a socket and waits
## on wall-clock time, and the suite is the thing CI runs on every push: one flaky socket test there
## would teach everybody to re-run it until it passes, which is worse than not having it. This is run
## by hand and quoted as evidence, the same shape as `button_session.gd` and `join_probe.gd`.
##
## PRINTS `SOLO PROBE OK` LAST, or `SOLO PROBE FAILED: <why>`. Godot exits 0 on almost anything, so a
## marker line printed last is the only honest verdict.

const PATIENCE_MS := 15000

var _screen: Node = null
var _ticks := 0
var _first_tick := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_screen = scene.instantiate()
	root.add_child(_screen)
	_screen._ready()

	# THE RELAY THE BUTTON WOULD FIND, named before anything is pressed, because "it worked" against
	# a binary nobody can point at is not evidence.
	var binary := AssaySoloRelay.find_binary()
	if binary == "":
		_done(false, "no sim-relay found; looked in %s"
				% ", ".join(AssaySoloRelay.candidate_paths()))
		return
	print("relay:  %s" % binary)
	print("saves:  %s" % AssaySoloRelay.saves_dir())

	# PRESSED, NOT CALLED. `_on_play_solo` is reached through the Button's own signal so that a
	# button wired to nothing fails here rather than passing.
	var button := _find_button(_screen, "Play solo")
	if button == null:
		_done(false, "no `Play solo` button on the join screen")
		return
	button.pressed.emit()
	if _screen._solo == null:
		_done(false, "the press started nothing: %s" % _screen._status.text)
		return

	var started := Time.get_ticks_msec()
	var joined_at := 0
	while Time.get_ticks_msec() - started < PATIENCE_MS:
		# THE FRAME LOOP BY HAND, because a `SceneTree` script has none. BOTH `_process`es: the
		# screen's polls the relay for its address, and the net client's is what reads the socket --
		# without the second the handshake completes and then nothing ever ticks, which is exactly
		# what this probe reported the first time I ran it.
		_screen._process(0.016)
		if _screen._client != null:
			_screen._client._process(0.016)
		if _screen._solo != null and _screen._solo.failure != "":
			_done(false, "the relay refused: %s" % _screen._solo.failure)
			return
		if _screen._client != null and _screen._client.stage == AssayNetClient.Stage.JOINED:
			if joined_at == 0:
				joined_at = Time.get_ticks_msec()
				print("address: %s" % _screen._solo.address)
				print("joined:  player %d after %d ms"
						% [_screen._client.player_id, joined_at - started])
			# AND THE WORLD HAS TO MOVE. Joining proves a handshake; a tick proves the relay is
			# running the sim and this client is applying its bundles.
			if _screen._sim.tick() > _ticks:
				if _first_tick == 0:
					# THE FIRST TICK THIS CLIENT SAW IS THE RESUME EVIDENCE (ruling 4): a fresh
					# world starts at 1, so anything higher means the relay loaded the save it
					# wrote last time. Printed rather than inferred from the final tick, which is
					# what I did first and had to reason about afterwards.
					_first_tick = _screen._sim.tick()
					print("resumed: first tick seen %d (a fresh world starts at 1)" % _first_tick)
				_ticks = _screen._sim.tick()
				if _ticks >= _first_tick + 20:
					break
		OS.delay_msec(16)

	if _ticks < _first_tick + 20:
		_done(false, "joined but the world only reached tick %d in %d ms"
				% [_ticks, Time.get_ticks_msec() - started])
		return
	print("ticks:   %d, hash %s" % [_screen._sim.tick(), _screen._sim.hash_hex()])

	# LOOPBACK ONLY (ruling 2), asked of the address the relay actually reported rather than of the
	# flag we passed it. A relay that ignored `--bind` would print its LAN address here.
	if not _screen._solo.address.begins_with("127.0.0.1:"):
		_done(false, "the solo relay is listening on %s, which is not loopback only"
				% _screen._solo.address)
		return
	var port := int(_screen._solo.address.split(":")[1])
	if port == 7777 or port == 7803 or port == 0:
		_done(false, "the solo relay took port %d, which is not a free one" % port)
		return
	print("port:    %d (not 7777, not 7803)" % port)

	# AND IT DIES WITH US (ruling 4). The pid is kept because `stop_solo_relay` clears the field --
	# asking the object afterwards would be asking about nothing.
	var pid: int = _screen._solo.pid
	_screen.stop_solo_relay()
	OS.delay_msec(300)
	# THE EXIT CODE AND NOT `is_process_running`: this process holds the child's pipe, so a killed
	# child stays a zombie and `is_process_running` answers true for it until something reaps it.
	if OS.get_process_exit_code(pid) == -1:
		_done(false, "the relay (pid %d) is still running after the client stopped it" % pid)
		return
	print("stopped: pid %d is gone" % pid)
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
	# THE RELAY IS STOPPED ON EVERY PATH, including the failures. A probe that leaves a relay holding
	# a port behind makes the next run fail for a reason that has nothing to do with the code.
	if _screen != null:
		_screen.stop_solo_relay()
	print("SOLO PROBE OK" if ok else "SOLO PROBE FAILED: %s" % why)
	quit(0 if ok else 1)
