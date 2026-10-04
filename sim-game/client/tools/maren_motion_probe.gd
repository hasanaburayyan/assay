extends SceneTree
## MAREN'S PROBE, not a shipped tool: does the body actually TWEEN in the window, or does it jump a
## tile at a time? The board said the movement is choppy. Nerite checked and said correctly that a
## still cannot answer it, and asked who owns the check. This is the check.
##
##   godot --headless --path client --script res://tools/maren_motion_probe.gd -- <seed> [seconds] [whole|solo]
##
## `solo` IS THE ONE THAT ANSWERS THE BOARD. It presses the screen's own `Play solo`, which starts a
## REAL `sim-relay` process and joins it over a REAL socket -- the player's actual path, with the
## relay owning the clock. The offline modes above feed ticks from this script, so they can say the
## tween arithmetic works and nothing about whether ticks ARRIVE evenly. This mode also records the
## wall-clock gap between arriving ticks, which is the jitter I said I could not measure.
##
## WHAT IT READS, AND WHY NOT MY OWN ARITHMETIC. `main.gd::_refresh_world` publishes each player's
## DRAWN position into `_world.view["players"][i]["at"]` -- `Vector2(_was).lerp(Vector2(_seen),
## part)`. This samples that dictionary, which is the renderer's own output. Re-deriving the lerp
## here would measure my copy of the rule and tell us nothing about the client.
##
## THE TRAP THIS PROBE HAD TO AVOID, and it would have faked the exact defect it is looking for.
## `part = (now - _tick_at) / _tick_gap`, and `_tick_gap` is MEASURED from the wall clock between
## ticks. Every other probe here feeds ticks as fast as its loop runs, which drives `_tick_gap`
## toward its 0.01 floor, pins `part` at 1.0, and leaves the body on integer tiles every frame --
## choppy, manufactured entirely by the harness. So this one feeds a tick every TICK_SECONDS of
## real wall clock, which is what a relay at the default 10 tps does.
##
## AND THE HYPOTHESIS WORTH NAMING BEFORE MEASURING: `_process` only calls `_refresh_world()` when
## `_close_up` is true -- the schematic is painted when a tick lands, by its own documented design.
## So the whole-world view (V) is a tile-jump on purpose, and a player who pressed V would see
## exactly what "choppy" describes with nothing broken.

const TICK_SECONDS := 0.1
## Walk this far east, far enough to cross many tiles without leaving a 96x64 world.
const WALK := 25

var _screen: Node
var _asked: Array = []
var _seed := "14247"
var _seconds := 4.0
## `whole` runs the same walk in the SCHEMATIC view, which is the hypothesis above under test.
var _whole := false
var _solo := false
var _joined := false
## Wall-clock gaps between ticks as they ARRIVED, not as anyone intended them.
var _gaps: Array[float] = []
var _last_tick_at := 0.0
var _started := false
var _done := false
var _started_at := 0.0
var _next_tick := 0.0
var _samples: Array[Vector2] = []
var _parts: Array[float] = []
var _frames := 0


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	_seed = String(argv[0]) if argv.size() > 0 else "14247"
	_seconds = float(argv[1]) if argv.size() > 1 else 4.0
	_whole = argv.size() > 2 and String(argv[2]) == "whole"
	_solo = argv.size() > 2 and String(argv[2]) == "solo"
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _process(_delta: float) -> bool:
	if _done:
		return true
	if not _started:
		var welcome := AssaySimHost.fresh_welcome_json(_seed, "maren")
		if welcome == "":
			print("PROBE DEAD: no world on seed %s" % _seed)
			_done = true
			return true
		if _solo:
			# The button, not the handler: a probe that called `_on_play_solo` directly would skip
			# whatever the screen does on a press, and the press is the thing a player performs.
			var button := _find_button(_screen, "Play solo")
			if button == null:
				print("PROBE DEAD: no Play solo button")
				_done = true
				return true
			button.pressed.emit()
			_started = true
			_started_at = _now()
			print("view=close-up, pressed Play solo; waiting for the relay to listen and welcome us")
			return false
		_screen._client.play_offline()
		_screen._client.feed_offline(welcome)
		_started = true
		if _whole:
			_screen._show_close_up(false)
		_started_at = _now()
		_next_tick = _started_at
		print("view=%s close_up=%s running=%s" % ["whole world" if _whole else "close-up",
				_screen._close_up, _screen._sim.running()])
		var me := _screen._sim.spawn_tile() as Vector2i
		_screen._client.submit(AssayActions.move_to(me + Vector2i(WALK, 0)))
		print("walking from %s to %s" % [me, me + Vector2i(WALK, 0)])
	var now := _now()
	if _solo:
		if not _joined:
			if not _screen._sim.running() or _screen._client.player_id < 0:
				if now - _started_at > 30.0:
					print("PROBE DEAD: no world after 30s of waiting")
					_done = true
					return true
				return false
			_joined = true
			_started_at = now
			var here := _me_tile()
			var to := _walk_target(here)
			_screen._client.submit(AssayActions.move_to(to))
			print("joined as player %d at %s; walking to %s"
					% [_screen._client.player_id, here, to])
			return false
		if _screen._tick_at != _last_tick_at:
			if _last_tick_at > 0.0:
				_gaps.append(_screen._tick_at - _last_tick_at)
			_last_tick_at = _screen._tick_at
		if now - _started_at > _seconds:
			_screen.stop_solo_relay()
			_report()
			return true
		_sample()
		return false
	if now - _started_at > _seconds:
		_report()
		return true
	# A TICK ON THE WALL CLOCK, not on the loop. See the note at the top.
	if now >= _next_tick:
		_next_tick += TICK_SECONDS
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
		_asked.clear()
		var at: int = _screen._sim.tick()
		_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
	_sample()
	return false


func _find_button(node: Node, label: String) -> Button:
	if node is Button and (node as Button).text == label:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, label)
		if found != null:
			return found
	return null


## WHERE TO WALK, CLAMPED INTO THE WORLD. The solo relay keeps its save, so a second run joins a
## world where the player is wherever the FIRST run left them -- and `here + 25` east then lands off
## a 96x64 map, the sim refuses it, and the probe reports a body that never moved. It did that to me
## twice before I read the first/last line: a bug in the instrument that looks exactly like a
## finding about the subject.
func _walk_target(here: Vector2i) -> Vector2i:
	var size: Vector2i = _screen._sim.size_tiles()
	if here.x + WALK < size.x - 1:
		return here + Vector2i(WALK, 0)
	return here - Vector2i(WALK, 0)


func _me_tile() -> Vector2i:
	for entry in _screen._sim.players():
		var p: Dictionary = entry
		if int(p.get("id", -1)) == _screen._client.player_id:
			return p["pos"] as Vector2i
	return _screen._sim.spawn_tile() as Vector2i


func _sample() -> void:
	_frames += 1
	var view: Dictionary = _screen._world.view
	var players: Variant = view.get("players")
	if players == null:
		return
	for entry in (players as Array):
		var p: Dictionary = entry
		_samples.append(p["at"] as Vector2)
		break
	_parts.append(_screen._tick_gap)


func _report() -> void:
	_done = true
	if _samples.is_empty():
		print("NO SAMPLES: the scene never published a drawn position")
		print("PROBE OK")
		return
	var distinct := {}
	var on_tile := 0
	var biggest := 0.0
	for i in range(_samples.size()):
		var at := _samples[i]
		distinct[at] = true
		if is_equal_approx(at.x, roundf(at.x)) and is_equal_approx(at.y, roundf(at.y)):
			on_tile += 1
		if i > 0:
			biggest = maxf(biggest, (at - _samples[i - 1]).length())
	print("frames %d, samples %d over %.1fs; measured tick gap %.3fs"
			% [_frames, _samples.size(), _seconds, _parts[-1]])
	print("distinct drawn positions: %d" % distinct.size())
	print("samples landing exactly on a tile: %d of %d (%.1f%%)"
			% [on_tile, _samples.size(), 100.0 * on_tile / _samples.size()])
	print("biggest step between consecutive frames: %.3f tiles (1.000 = a whole-tile jump)" % biggest)
	if not _gaps.is_empty():
		var lo := _gaps[0]
		var hi := _gaps[0]
		var total := 0.0
		for g in _gaps:
			lo = minf(lo, g)
			hi = maxf(hi, g)
			total += g
		print("TICKS AS THEY ARRIVED: %d gaps, mean %.3fs, min %.3fs, max %.3fs, spread %.3fs"
				% [_gaps.size(), total / _gaps.size(), lo, hi, hi - lo])
	print("first %s last %s" % [_samples[0], _samples[-1]])
	print("PROBE OK")
