extends SceneTree
## **HOW FAST THE BODY IS DRAWN, FRAME BY FRAME, IN A REAL WINDOW** (ASSA-197, Wren's bar).
##
##   godot --path client --script res://tools/motion_speed_probe.gd -- <seed> [seconds] [label]
##   **NEVER `--headless`.** A headless run has no vsync and no compositor: frames come as fast as
##   the loop can spin, so `dt` is a tenth of a real frame's and the distribution below is of a
##   machine nobody plays on. The board plays a window. This measures a window.
##
## **THE BAR IT MEASURES, WHICH IS NOT THE ONE ASSA-148 PASSED.** That item asked whether the body
## ever teleports (a whole tile inside a frame shorter than a tick). It does not. This asks whether
## the body moves at a CONSTANT SPEED, which is what "jumpy" means and what the board said twice:
##
##   drawn speed this frame = |drawn position now - drawn position last frame| / this frame's own dt
##   true speed             = one tile per tick gap = 1 / TICK_SECONDS tiles per second
##   the bar                = every moving frame within +/-25% of true, first/last 150 ms excluded
##
## **NO ESTIMATE IN THE DENOMINATOR** (Wren). `dt` is the frame's own delta, handed to `_process` by
## the engine; the tick rate is the relay's documented default, printed here so a reader can check
## it against the measured bundle gaps rather than trusting the constant.
##
## **IT READS THE RENDERER'S OWN OUTPUT, NEVER ITS ARITHMETIC** — `_world.view.players[].at`, which
## is what `main.gd::_refresh_world` publishes and what the scene draws. Re-deriving the lerp here
## would measure my copy of the rule (Maren's rule on her own probe, kept).
##
## **AND THE CAMERA, AT THE SAME INSTANT.** A perfectly tweened body against a camera that moves in
## steps judders exactly like a bad tween, and from a chair you cannot tell which moved. So the
## camera's own speed is measured from `view.origin` in the same frames, in the same unit, and
## reported beside the body's. The walk is aimed to stay away from the map's edges, because a
## clamped camera legitimately stops while the body keeps going.
##
## Run ceiling is a MEMBER INITIALIZER (Limpet, ASSA-182): a runtime error inside `_initialize`
## must not leave this holding a relay and a window for ever.

## The relay's default clock (`sim-relay`, 10 ticks/s) and the sim's one-tile-per-tick walk.
const TICK_SECONDS := 0.1
const TRUE_SPEED := 1.0 / TICK_SECONDS
## Wren's bar.
const TOLERANCE := 0.25
## Both ends of the walk are excluded: starting and stopping are not the steady state under test.
const EDGE_TRIM := 0.15
const WALK := 22
## Keep the camera off its clamp: the view is 912px wide at 32px a tile, so about 14 tiles each side.
const EDGE_KEEPOUT := 16
const JOIN_DEADLINE := 30.0
const RUN_CEILING := 180.0

var _screen: Node
var _seed := "14247"
var _seconds := 8.0
var _label := "run"
var _joined := false
var _started := false
var _done := false
var _started_at := 0.0
var _walk_at := -1.0
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING

## One row per frame, from the frame the walk was ordered.
var _at: Array[Vector2] = []
var _origin: Array[Vector2] = []
var _dt: Array[float] = []
var _clock: Array[float] = []
## Bundle arrivals, as a cross-check on TICK_SECONDS and to show how bursty delivery was.
var _bundle_gaps: Array[float] = []
var _last_bundle := 0.0
## Frames where the renderer had published no drawn position for us. A sampler that reads the wrong
## field is silent in exactly the way a body that never moved is; this counts the difference.
var _blind := 0


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	_seed = String(argv[0]) if argv.size() > 0 else "14247"
	_seconds = float(argv[1]) if argv.size() > 1 else 8.0
	_label = String(argv[2]) if argv.size() > 2 else "run"
	if DisplayServer.get_name() == "headless":
		print("FAIL  headless: this probe measures frame pacing and there is none here")
		quit(2)
		return
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	_screen._client.tick_bundle.connect(func(_t: int, _i: Array, _r: String) -> void:
		var now := _now()
		if _last_bundle > 0.0:
			_bundle_gaps.append(now - _last_bundle)
		_last_bundle = now)


func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


func _process(delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		print("FAIL  the probe ran past its %ds ceiling: joined=%s, %d frames"
				% [int(RUN_CEILING), _joined, _at.size()])
		_stop()
		return true
	if not _started:
		# THE BUTTON, NOT THE HANDLER (Maren's rule on her probe): this starts a real `sim-relay`
		# process and joins it over a real socket, which is the player's actual path and the only
		# one where arrivals are the relay's rather than this script's.
		var button := _find_button(_screen, "Play solo")
		if button == null:
			print("FAIL  no Play solo button")
			_stop()
			return true
		button.pressed.emit()
		_started = true
		_started_at = _now()
		return false
	var now := _now()
	if not _joined:
		if not _screen._sim.running() or _screen._client.player_id < 0:
			if now - _started_at > JOIN_DEADLINE:
				print("FAIL  no world after %ds" % int(JOIN_DEADLINE))
				_stop()
				return true
			return false
		_joined = true
		_started_at = now
		var here := _me_tile()
		var to := _walk_target(here)
		_screen._client.submit(AssayActions.move_to(to))
		_walk_at = now
		print("joined as player %d at %s, walking to %s on seed %s (%s)"
				% [_screen._client.player_id, here, to, _seed, _label])
		return false
	_sample(delta, now)
	if now - _started_at > _seconds:
		_report()
		_stop()
		return true
	return false


func _stop() -> void:
	_done = true
	if _screen != null and _screen.has_method("stop_solo_relay"):
		_screen.stop_solo_relay()
	quit(0)


func _find_button(node: Node, label: String) -> Button:
	if node is Button and (node as Button).text == label:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, label)
		if found != null:
			return found
	return null


func _me_tile() -> Vector2i:
	for entry in _screen._sim.players():
		var player: Dictionary = entry
		if int(player.get("id", -1)) == _screen._client.player_id:
			return player["pos"] as Vector2i
	return _screen._sim.spawn_tile() as Vector2i


## A STRAIGHT WALK THAT STAYS OFF THE CAMERA'S CLAMP AND INSIDE THE WORLD. The solo relay keeps its
## save, so a second run starts wherever the first one left the body (Maren found that the hard way);
## the keepout also stops the camera legitimately stopping at an edge while the body walks on, which
## would read as a camera defect in the numbers below.
func _walk_target(here: Vector2i) -> Vector2i:
	var size: Vector2i = _screen._sim.size_tiles()
	if here.x + WALK <= size.x - EDGE_KEEPOUT:
		return Vector2i(here.x + WALK, here.y)
	if here.x - WALK >= EDGE_KEEPOUT:
		return Vector2i(here.x - WALK, here.y)
	return Vector2i(clampi(size.x / 2, EDGE_KEEPOUT, size.x - EDGE_KEEPOUT), here.y)


func _sample(delta: float, now: float) -> void:
	var view: Dictionary = _screen._world.view
	# **`_world.me`, NOT `view.players[i]` AND NOT `view.me`, AND BOTH WRONG TURNS ARE FINDINGS.**
	# The view's player entries carry `at`, `facing` and `moving` and **no `id`**, so your own body
	# cannot be picked out of that array at all; and `me` is a property of the layer beside `view`,
	# not a key inside it. My first two runs matched nothing and printed "the body never moved",
	# which is exactly what a refused walk looks like -- an instrument failure wearing a finding's
	# clothes. `_blind` below exists so the two can never be confused again.
	var mine_at: Variant = _screen._world.me
	if mine_at == null:
		_blind += 1
		return
	var mine := mine_at as Vector2
	_at.append(mine)
	_origin.append(view.get("origin", Vector2.ZERO) as Vector2)
	_dt.append(delta)
	_clock.append(now)


## THE MOVING STRETCH ONLY, both ends trimmed. A standing body is on its tile in every frame, so any
## statistic over the whole watch measures how long we watched; and the first and last 150 ms are a
## body starting and stopping, which is not the steady state the bar is about.
func _moving_span() -> Dictionary:
	var first := -1
	var last := -1
	for i in range(1, _at.size()):
		if not _at[i].is_equal_approx(_at[i - 1]):
			if first < 0:
				first = i - 1
			last = i
	if first < 0:
		return {}
	var from := first
	var to := last
	while from < to and _clock[from] - _clock[first] < EDGE_TRIM:
		from += 1
	while to > from and _clock[last] - _clock[to] < EDGE_TRIM:
		to -= 1
	return {"from": from, "to": to, "raw_from": first, "raw_to": last}


func _percentiles(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	var pick := func(p: float) -> float:
		return sorted[clampi(int(round(p * (sorted.size() - 1))), 0, sorted.size() - 1)]
	var total := 0.0
	for v in sorted:
		total += v
	return {"min": sorted[0], "p5": pick.call(0.05), "median": pick.call(0.5),
			"p95": pick.call(0.95), "max": sorted[sorted.size() - 1],
			"mean": total / float(sorted.size()), "n": sorted.size()}


func _say(name: String, stats: Dictionary) -> void:
	if stats.is_empty():
		print("  %-14s no samples" % name)
		return
	print("  %-14s n=%3d  min %6.2f  p5 %6.2f  median %6.2f  p95 %6.2f  max %6.2f"
			% [name, int(stats["n"]), stats["min"], stats["p5"], stats["median"],
			stats["p95"], stats["max"]])


func _report() -> void:
	print("")
	print("MOTION SPEED, real window, seed %s, %s" % [_seed, _label])
	print("  display %s, vsync %d, %d frames watched"
			% [DisplayServer.get_name(), DisplayServer.window_get_vsync_mode(), _at.size()])
	var span := _moving_span()
	if span.is_empty():
		if _at.is_empty():
			print(("  NOTHING WAS SAMPLED (%d blind frames): the renderer published no drawn "
					+ "position for us. This is an INSTRUMENT failure, not a finding about motion.")
					% _blind)
		else:
			print("  THE BODY NEVER MOVED over %d sampled frames. That is what a refused walk looks"
					+ " like; check the target is inside the world." % _at.size())
		return
	var from: int = span["from"]
	var to: int = span["to"]
	var body: Array[float] = []
	var camera: Array[float] = []
	var frames: Array[float] = []
	var within := 0
	var tile_px: float = AssayScene.TILE_PX
	for i in range(from + 1, to + 1):
		var dt: float = _dt[i]
		if dt <= 0.0:
			continue
		var speed := (_at[i] - _at[i - 1]).length() / dt
		body.append(speed)
		camera.append((_origin[i] - _origin[i - 1]).length() / tile_px / dt)
		frames.append(dt * 1000.0)
		if absf(speed - TRUE_SPEED) <= TRUE_SPEED * TOLERANCE:
			within += 1
	print("  true speed %.2f tiles/s (one tile per %.0f ms tick), bar is +/-%d%%"
			% [TRUE_SPEED, TICK_SECONDS * 1000.0, int(TOLERANCE * 100.0)])
	_say("body tiles/s", _percentiles(body))
	_say("camera tiles/s", _percentiles(camera))
	_say("frame ms", _percentiles(frames))
	_say("bundle gap ms", _percentiles(_scaled(_bundle_gaps, 1000.0)))
	var share := 0.0 if body.is_empty() else float(within) / float(body.size())
	print("  WITHIN THE BAR: %d of %d moving frames (%.1f%%)" % [within, body.size(), share * 100.0])
	if _walk_at > 0.0 and span.has("raw_from"):
		print("  input latency on your own body: %.0f ms (press -> first drawn movement)"
				% ((_clock[int(span["raw_from"]) + 1] - _walk_at) * 1000.0))
	print("  VERDICT: %s" % ("WITHIN BAR" if share >= 1.0 else "OUTSIDE BAR"))


func _scaled(values: Array[float], by: float) -> Array[float]:
	var out: Array[float] = []
	for v in values:
		out.append(v * by)
	return out
