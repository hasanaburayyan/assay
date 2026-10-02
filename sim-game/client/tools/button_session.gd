extends SceneTree
## CAN A PERSON AT THE WINDOW PLAY THE DEMO LOOP? Headless, one line of verdict.
##
##   godot --headless --path . --script res://tools/button_session.gd -- offline [seed] [rank]
##   godot --headless --path . --script res://tools/button_session.gd -- localhost:7777 name [rank]
##
## `lockstep_probe.gd --session` plays the same loop by calling `submit`, which proves the sim, the
## wire and lockstep. It cannot prove ASSA-37's claim, which is about REACHABILITY: every command can
## be perfectly correct and still have no click target, which is what this client was until today.
## So this presses the screen's own buttons and clicks its own map, and `AssayButtonPlay` holds the
## loop. If a button is missing, mislabelled, built over the map or wired to the wrong command, this
## stops on that step and says which.
##
## TWO MODES, ONE STATE MACHINE.
##  - `offline`: no socket and no relay. This script is the clock: it takes the commands the buttons
##    asked for, writes the `TickBundle` a relay would have written, and feeds it back through the
##    real frame reader. Fast enough to run in a test, which is where ASSA-37's fifth box lives.
##  - a host address: the screen JOINS BY ITS OWN JOIN BUTTON and the relay owns the clock. Run three
##    of these at once and the relay's own hash check covers the sixth box; each prints its final
##    hash so the three can also be compared without taking the relay's word for it.
##
## Prints `BUTTON SESSION OK` LAST and only on success. A positive marker printed last is the only
## thing a grep can trust, because Godot exits 0 even when a script fails to compile.

## Offline ticks to allow. The chain is about 550 ticks on a fresh world (mine 22 ore, smelt 17 at 20
## ticks each, walk twice); this is generous because an underestimate turns a real failure into "ask
## for more ticks", which is the confusing way round.
const OFFLINE_TICKS := 4000
## Relay ticks to allow, at ten a second. The same chain over a real clock is about a minute.
const RELAY_TICKS := 1400
const JOIN_TIMEOUT := 10.0
const SECONDS_PER_TICK := 0.1

var _screen: Node
var _play: AssayButtonPlay
var _asked: Array = []
var _offline := false
var _done := false
var _join_deadline := 0.0
var _run_deadline := 0.0
var _desynced_at := -1
var _hashes: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		print("FAIL  usage: -- offline [seed] [rank] | host[:port] name [rank]")
		quit(1)
		return
	_offline = String(argv[0]) == "offline"
	var seed_text := String(argv[1]) if argv.size() > 1 else "777042"
	var rank := int(argv[2]) if argv.size() > 2 else 0

	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND, for the same reason `tests/test_main_screen.gd` does it: a script run with
	# `--script` works inside `SceneTree._initialize`, before the root window is in the tree, so the
	# engine's own call comes too late to be useful. The screen is built once however often it runs.
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	_screen._client.desynced.connect(func(tick: int) -> void: _desynced_at = tick)
	_screen._client.refused.connect(func(reason: String) -> void:
		_finish(false, "the relay refused us: %s" % reason))
	_screen._client.link_failed.connect(func(reason: String) -> void: _finish(false, reason))
	_play = AssayButtonPlay.new(_screen, rank)

	if _offline:
		_run_offline(seed_text)
		return
	# THE JOIN BUTTON, not `join()`. The front door is a button too, and a session that reached past
	# it would leave the one control every player uses first untested.
	_screen._host.text = String(argv[0])
	_screen._name.text = seed_text
	if not _press("Join"):
		_finish(false, "no Join button on the screen")
		return
	var now := Time.get_unix_time_from_system()
	_join_deadline = now + JOIN_TIMEOUT
	_run_deadline = now + JOIN_TIMEOUT + float(RELAY_TICKS) * SECONDS_PER_TICK
	_screen._client.tick_bundle.connect(_after_bundle)


## OFFLINE: THIS SCRIPT IS THE RELAY. Welcome ourselves into a fresh world, then for every tick take
## whatever the buttons asked for and hand it back as the bundle a relay would have sent.
##
## A BUNDLE IS NUMBERED WITH THE TICK WE ARE AT, not the one it produces -- the relay builds
## `TickBundle { tick: world.tick }` and only then steps. I had that backwards once and every bundle
## a real relay sent was refused.
func _run_offline(seed_text: String) -> void:
	var welcome := AssaySimHost.fresh_welcome_json(seed_text, "limpet")
	if welcome == "":
		_finish(false, "could not make a world on seed %s" % seed_text)
		return
	_screen._client.play_offline()
	_screen._client.feed_offline(welcome)
	if not _screen._sim.running():
		_finish(false, "offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
		return
	print("  offline on seed %s, world %dx%d, player %d at tick %d"
			% [seed_text, _screen._sim.size_tiles().x, _screen._sim.size_tiles().y,
			_screen._client.player_id, _screen._sim.tick()])
	for _i in range(OFFLINE_TICKS):
		_play.advance()
		if _play.finished:
			break
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
		_asked.clear()
		var at: int = _screen._sim.tick()
		var before: int = _screen._sim.applied
		_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
		if _screen._sim.applied == before:
			_finish(false, "the sim refused the bundle for tick %d" % at)
			return
	_report()


## RELAY: the relay owns the clock, so one step of the loop happens per bundle. Connected AFTER the
## screen's own handler, so by the time this runs the world has already been stepped -- which is the
## only state the loop may read.
func _after_bundle(_tick: int, _inputs: Array, _raw: String) -> void:
	if _done:
		return
	if _screen._sim.tick() % 20 == 0:
		_hashes.append("HASH tick=%d %s" % [_screen._sim.tick(), _screen._sim.hash_hex()])
	_play.advance()


func _process(_delta: float) -> bool:
	if _done or _offline:
		return _done
	var now := Time.get_unix_time_from_system()
	if _screen._client.stage != AssayNetClient.Stage.JOINED:
		if now >= _join_deadline:
			_finish(false, "no welcome within %ds (stage %d)"
					% [JOIN_TIMEOUT, _screen._client.stage])
		return _done
	if _desynced_at >= 0:
		_finish(false, "the relay called us desynced at tick %d" % _desynced_at)
		return _done
	if _play.finished:
		_report()
		return _done
	if now >= _run_deadline:
		_finish(false, "the loop was still on %s at the deadline"
				% AssayButtonPlay.Step.keys()[_play.step])
		return _done
	return false


func _press(label: String) -> bool:
	var button := _find(_screen, label)
	if button == null:
		return false
	button.pressed.emit()
	return true


func _find(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == label:
			return child
		var found := _find(child, label)
		if found != null:
			return found
	return null


## THE REPORT, and what it is allowed to claim. Every line is read out of the stepped world or out of
## the list of buttons actually pressed; the only verdict about a design is the sim's own word.
func _report() -> void:
	if _play.failed != "":
		_finish(false, _play.failed)
		return
	if _play.outcome == "":
		_finish(false, "the loop finished with nothing to say about the design it planted")
		return
	print("  pressed %d buttons and clicked the map %d times"
			% [_play.pressed.size(), _play.clicks.size()])
	for line in _play.pressed:
		print("    press %s" % line)
	for line in _play.clicks:
		print("    click %s" % line)
	for line in _hashes:
		print("  %s" % line)
	print("  the sim's verdict on the design before planting: %s" % _play.planted_verdict)
	print("  %s" % _play.outcome)
	print("  final: tick %d, hash %s, %d bundles applied"
			% [_screen._sim.tick(), _screen._sim.hash_hex(), _screen._sim.applied])
	print("BUTTON SESSION OK")
	_done = true
	quit(0)


func _finish(ok: bool, why: String) -> void:
	if _done:
		return
	_done = true
	if ok:
		print("BUTTON SESSION OK")
		quit(0)
		return
	print("FAIL  %s" % why)
	if _play != null:
		print("  stopped on %s after %d presses and %d clicks"
				% [AssayButtonPlay.Step.keys()[_play.step], _play.pressed.size(),
				_play.clicks.size()])
		for line in _play.pressed:
			print("    press %s" % line)
		for line in _play.clicks:
			print("    click %s" % line)
	if _screen != null and _screen._sim.running():
		print("  world at tick %d, hash %s; pack %s"
				% [_screen._sim.tick(), _screen._sim.hash_hex(),
				_screen._sim.inventory_of(_screen._client.player_id)])
	quit(1)
