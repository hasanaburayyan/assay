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
## Every bundle's arrival instant and the sim tick it carried, for the host's own pacing.
var _bundle_at: Array[float] = []
var _bundle_tick: Array[int] = []
## Frames where the renderer had published no drawn position for us. A sampler that reads the wrong
## field is silent in exactly the way a body that never moved is; this counts the difference.
var _blind := 0
## **THE RECTANGLE THE RENDERER BLITTED, in world pixels (`dest.position + origin`), and the foot
## mark's beside it.** This is the column Maren's ASSA-200 says box 1 and box 3 have to be read off:
## `_at` below is the lerp's OUTPUT, which `AssayScene._place` used to floor away before anything
## reached the screen, so every number on this item before 2026-10-04 was measured on the input to
## the broken step. World pixels and not map pixels because a centring camera holds the body still
## in the WINDOW while the ground slides -- the quantity a player perceives is the body against the
## world, and adding `origin` back recovers it exactly as the renderer computed it.
var _drawn: Array[Vector2] = []
var _foot: Array[Vector2] = []
## When the SCREEN last advanced its playout clock, per sample. See `_sample`.
var _screen_at: Array[float] = []
## Frames the renderer drew with no single body on the scene (see `WorldLayer.drawn_body`).
var _unlit := 0
## The clock's own state at each sample, so a frozen frame can be told from a starved one.
var _play: Array[float] = []
var _starved: Array[bool] = []
var _held: Array[int] = []
var _sim_tick: Array[int] = []
## **THE QUANTITY THE CLOCK IS CONTROLLING, AND WHAT IT HAS LEARNT ABOUT ITS OWN MEASUREMENT**
## (ASSA-197). `_held` is how many positions the queue holds, which is not the same thing: the depth
## is fractional and is what decides whether the next late bundle is absorbed or felt. A trim away
## from 1.0 says the measured tick length is biased by that much and the loop has corrected it --
## which on a machine none of us owns is the only way to see that happening at all.
var _depth: Array[float] = []
var _trim: Array[float] = []
## How many times the screen had advanced its playout clock by this sample. See
## `main.gd::_play_advances`: more than one between two samples means `_played_at` stepped without a
## new rectangle being drawn, and the verdict column's denominator is then short.
var _advances: Array[int] = []
## One entry per moving frame that failed the bar, with the parts of its own verdict.
var _outliers: Array[Dictionary] = []


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
	_screen._client.tick_bundle.connect(func(t: int, _i: Array, _r: String) -> void:
		var now := _now()
		if _last_bundle > 0.0:
			_bundle_gaps.append(now - _last_bundle)
		_last_bundle = now
		# **THE TICK NUMBER AS WELL AS THE INSTANT, so the HOST's own rate can be stated** (ASSA-197).
		# A raw gap is bimodal and says nothing about pacing -- the client drains its socket once a
		# frame, so bundles land in pairs 0.17 ms apart and the gap series reads 0.17, 0.17, 221, 258.
		# Collapsed per frame and divided by the tick span it covers, the same arrivals give the
		# length of a tick as the host actually produced it, which is the reference the bar's constant
		# 10.00 tiles/s stands in for.
		_bundle_at.append(now)
		_bundle_tick.append(t))


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
	# THE DRAWN RECT IS TAKEN FIRST AND IT CAN VETO THE SAMPLE. An empty `drawn_body` means the layer
	# refused to say which body was yours, and a row with a lerp but no rectangle would quietly
	# compare the two columns across different frames.
	var body: Rect2 = _screen._world.drawn_body
	var foot: Rect2 = _screen._world.drawn_foot
	if body.size == Vector2.ZERO:
		_unlit += 1
		return
	var origin: Vector2 = (_screen._world.view as Dictionary).get("origin", Vector2.ZERO)
	_drawn.append(body.position + origin)
	_foot.append(foot.position + origin)
	# **THE SCREEN'S OWN FRAME CLOCK, which is a different number from this probe's `delta` and the
	# difference is the instrument.** `_played_at` is the `Time.get_ticks_msec()` reading the screen
	# took when it last advanced the playout clock, so it is the instant the rectangle above was
	# computed for. This probe's `_process` runs at a different point in the frame, so `delta` and
	# the position I read are a frame boundary out of phase, and dividing one by the other reports
	# speed errors in BOTH directions that nothing in the game did. Not an estimate (Wren's rule on
	# this probe): it is wall clock, read where the drawing happened.
	_screen_at.append(float(_screen._played_at))
	_at.append(mine)
	_origin.append(view.get("origin", Vector2.ZERO) as Vector2)
	_dt.append(delta)
	_clock.append(now)
	_play.append(float(_screen._play_tick))
	_starved.append(bool(_screen._starved))
	_held.append((_screen._pending as Array).size())
	_sim_tick.append(int(_screen._sim.tick()))
	_depth.append(float(_screen._play_depth))
	_trim.append(float(_screen._play_trim))
	_advances.append(int(_screen._play_advances))


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
	var drawn: Array[float] = []
	var apart: Array[float] = []
	var wall: Array[float] = []
	var camera: Array[float] = []
	var frames: Array[float] = []
	var probe: Array[float] = []
	var dry: Array[float] = []
	var within := 0
	var within_drawn := 0
	var within_wall := 0
	var tile_px: float = AssayScene.TILE_PX
	var offset: Vector2 = _drawn[from] - _foot[from]
	for i in range(from + 1, to + 1):
		var dt: float = _dt[i]
		if dt <= 0.0:
			continue
		# **A DRY FRAME IS COUNTED AND EXCLUDED, on Maren's wording (ASSA-197).** The mechanism
		# permits a hold -- when the buffer runs out the only honest thing to draw is the newest
		# position the sim produced -- and box 1 forbids a 0-speed frame. Both stand: a held frame is
		# not a speed the renderer chose, so it does not belong in a speed distribution, and the bar
		# on it is ZERO of them, reported with its duration.
		if _starved[i]:
			dry.append(dt * 1000.0)
			continue
		# **THE RECTANGLE THAT WAS BLITTED, OVER THE SCREEN'S OWN FRAME TIME.** This is the verdict
		# column. `probe dt` below is the same distance over this script's `delta`, kept so the
		# phase error between the two samplers stays visible rather than being tidied away.
		var moved := (_drawn[i] - _drawn[i - 1]).length() / tile_px
		var screen_dt: float = _screen_at[i] - _screen_at[i - 1]
		if screen_dt > 0.0:
			drawn.append(moved / screen_dt)
			if absf(drawn[drawn.size() - 1] - TRUE_SPEED) <= TRUE_SPEED * TOLERANCE:
				within_drawn += 1
			else:
				# **EVERY FRAME OUTSIDE THE BAR IS NAMED WITH WHAT ITS DENOMINATOR WAS MADE OF**, which
				# is the difference between a finding and a plea. `advances` is how many times the
				# clock stepped between these two samples: two means a bundle landed mid-frame and
				# moved `_played_at` without publishing a rectangle, so this frame's movement is being
				# divided by part of its own interval.
				_outliers.append({"frame": i, "speed": moved / screen_dt, "moved": moved,
						"screen_dt": screen_dt, "probe_dt": dt, "over_probe": moved / dt,
						"advances": _advances[i] - _advances[i - 1], "depth": _depth[i]})
		probe.append(moved / dt)
		# **BOX 3, MEASURED RATHER THAN BUILT.** The camera is on the drawn position (`main.gd`) and
		# the foot mark is drawn from it, so the body and its own mark must keep a fixed offset. Any
		# deviation is the body and the camera disagreeing about where you are -- Maren measured 34.2
		# px of it, more than a whole tile, with the floor in place.
		apart.append(((_drawn[i] - _foot[i]) - offset).length())
		var speed := (_at[i] - _at[i - 1]).length() / dt
		body.append(speed)
		# **THE SAME DISTANCE OVER THE WALL CLOCK BETWEEN THE TWO SAMPLES**, which is not the same
		# number as the engine's frame delta and the difference is the INSTRUMENT, not the game. This
		# probe's `_process` and the screen's run at different points in a frame, so the position I
		# read at sample i was drawn some microseconds before or after the delta I divide by. If the
		# wall-clock column is tight and the delta column is not, the body IS being drawn at a
		# constant speed and my sampler is the jitter.
		var wall_dt: float = _clock[i] - _clock[i - 1]
		if wall_dt > 0.0:
			var wall_speed := (_at[i] - _at[i - 1]).length() / wall_dt
			wall.append(wall_speed)
			if absf(wall_speed - TRUE_SPEED) <= TRUE_SPEED * TOLERANCE:
				within_wall += 1
		camera.append((_origin[i] - _origin[i - 1]).length() / tile_px / dt)
		frames.append(dt * 1000.0)
		if absf(speed - TRUE_SPEED) <= TRUE_SPEED * TOLERANCE:
			within += 1
	print("  true speed %.2f tiles/s (one tile per %.0f ms tick), bar is +/-%d%%"
			% [TRUE_SPEED, TICK_SECONDS * 1000.0, int(TOLERANCE * 100.0)])
	_say("DRAWN tiles/s", _percentiles(drawn))
	_say("drawn/probe dt", _percentiles(probe))
	_say("body-vs-mark px", _percentiles(apart))
	_say("lerp tiles/s", _percentiles(body))
	_say("lerp (wall)", _percentiles(wall))
	_say("camera tiles/s", _percentiles(camera))
	_say("frame ms", _percentiles(frames))
	_say("bundle gap ms", _percentiles(_scaled(_bundle_gaps, 1000.0)))
	# **WHAT THE HOST ACTUALLY DID, which is the other half of every verdict here.** The bar is
	# +/-25% of a CONSTANT 10.00 tiles/s, and that constant is the relay's nominal rate rather than a
	# measurement: a clock that follows a host perfectly is drawn outside the bar whenever the host
	# itself wanders more than 25%, and on this Mac under six agents the relay is a child process
	# competing for the same cores. So the host's own tick length is stated beside the body's speed,
	# and a stall is counted rather than left inside a percentage.
	_say("host tick ms", _percentiles(_scaled(_host_ticks(), 1000.0)))
	var stalls := 0
	var worst_tick := 0.0
	for seconds in _host_ticks():
		if seconds > TICK_SECONDS * 1.5:
			stalls += 1
			worst_tick = maxf(worst_tick, seconds)
	if stalls > 0:
		print(("  the HOST stalled %d times (a tick it took over %.0f ms to produce, longest %.0f "
				+ "ms): production the clock can only answer by slowing down or running dry")
				% [stalls, TICK_SECONDS * 1500.0, worst_tick * 1000.0])
	# **WHAT A FROZEN FRAME ACTUALLY WAS.** A drawn speed of zero has three different causes and they
	# need different fixes: the clock ran out of produced positions (starved), the sim produced the
	# same position twice (the body is not walking every tick), or the clock advanced but the segment
	# it is on has zero length. Counting them apart is the difference between fixing the renderer and
	# fixing the wrong thing.
	var frozen := 0
	var frozen_starved := 0
	var frozen_same := 0
	for i in range(from + 1, to + 1):
		if not _at[i].is_equal_approx(_at[i - 1]):
			continue
		frozen += 1
		if _starved[i]:
			frozen_starved += 1
		elif is_equal_approx(_play[i], _play[i - 1]):
			frozen_same += 1
	print(("  frozen frames %d of %d: %d starved, %d clock did not move, %d clock moved on a "
			+ "zero-length segment") % [frozen, to - from, frozen_starved, frozen_same,
			frozen - frozen_starved - frozen_same])
	if not _sim_tick.is_empty():
		var ticks := _sim_tick[to] - _sim_tick[from]
		var tiles := (_at[to] - _at[from]).length()
		print("  the SIM moved %.1f tiles in %d ticks = %.3f tiles/tick (true speed assumes 1.000)"
				% [tiles, ticks, tiles / maxf(1.0, float(ticks))])
	print("  buffer held: %s" % [_percentiles(_as_floats(_held))])
	# **THE DEPTH AND THE TRIM: THE LOOP'S OWN TWO NUMBERS** (ASSA-197). Depth is what the PI loop
	# controls -- `PLAYOUT_DELAY` is the target, and a depth sitting near zero is a clock about to
	# hold the body still. The trim is what it has learnt about `playout_step`'s bias: 1.000 means
	# the measurement is being taken at face value, and a trim parked on `PLAYOUT_TRIM_MAX` means the
	# integral has run out of authority and the next thing to look at is the measurement itself.
	print("  buffer depth (ticks, target %.1f): %s"
			% [AssayScene.PLAYOUT_DELAY, _percentiles(_slice(_depth, from, to))])
	print("  clock trim (1.000 = the measured tick taken as-is, clamp %.2f): %s"
			% [AssayScene.PLAYOUT_TRIM_MAX, _percentiles(_slice(_trim, from, to))])
	# **WHAT THE CLIENT THINKS A TICK IS, AGAINST WHAT IT ACTUALLY IS.** The clock divides by the
	# first number; the second is the sim's own tick count over the wall clock across the same span.
	# Any gap between them IS a speed error, multiplied straight into every drawn frame.
	var span_seconds: float = _clock[to] - _clock[from]
	var span_ticks: int = _sim_tick[to] - _sim_tick[from]
	if span_seconds > 0.0 and span_ticks > 0:
		var measured: float = span_seconds / float(span_ticks)
		print(("  tick length: the client is using %.1f ms, the host actually sent one every "
				+ "%.1f ms -> the clock runs %.0f%% of true speed")
				% [float(_screen._tick_gap) * 1000.0, measured * 1000.0,
				measured / maxf(float(_screen._tick_gap), 1e-6) * 100.0])
	if OS.get_environment("TRACE") != "":
		print("  frame  dt_ms   x        speed  play_tick  newest  held starved")
		for i in range(from + 1, mini(from + 46, to + 1)):
			print("  %5d %6.1f %8.3f %7.2f %10.3f %7d %5d %s"
					% [i, _dt[i] * 1000.0, _at[i].x, (_at[i] - _at[i - 1]).length() / maxf(_dt[i], 1e-6),
					_play[i], _sim_tick[i], _held[i], _starved[i]])
	# **EVERY DISTRIBUTION CARRIES ITS FRAME RATE (Wren, ASSA-197 ruling 1).** "A speed number
	# without its frame rate is half a number", and on this Mac the frame time swings by 4x between
	# runs minutes apart depending on how many of us are awake. The label is the run's own, so
	# whoever reads this knows what the box was doing.
	var ms := _percentiles(frames)
	var rate := "frame ms median %.1f / p95 %.1f (%.0f fps median), load: %s" % [
			float(ms.get("median", 0.0)), float(ms.get("p95", 0.0)),
			1000.0 / maxf(float(ms.get("median", 0.0)), 1e-6), _label]
	var share := 0.0 if drawn.is_empty() else float(within_drawn) / float(drawn.size())
	if not _outliers.is_empty():
		print("  THE FRAMES OUTSIDE THE BAR, one line each (see `_outliers`):")
		for entry: Dictionary in _outliers:
			print(("    frame %4d  %6.2f tiles/s  moved %.4f tiles  screen_dt %5.1f ms  "
					+ "probe_dt %5.1f ms  = %6.2f tiles/s over probe_dt  clock advances %d  depth %.2f")
					% [int(entry["frame"]), float(entry["speed"]), float(entry["moved"]),
					float(entry["screen_dt"]) * 1000.0, float(entry["probe_dt"]) * 1000.0,
					float(entry["over_probe"]), int(entry["advances"]), float(entry["depth"])])
	print("  WITHIN THE BAR, ON THE DRAWN RECT: %d of %d moving frames (%.1f%%), %s"
			% [within_drawn, drawn.size(), share * 100.0, rate])
	var share_lerp := 0.0 if body.is_empty() else float(within) / float(body.size())
	print("  ... the same frames on the LERP's output, which is what every number before 2026-10-04"
			+ " was read off: %d of %d (%.1f%%)" % [within, body.size(), share_lerp * 100.0])
	var share_wall := 0.0 if wall.is_empty() else float(within_wall) / float(wall.size())
	print("  ... the lerp against the wall clock between samples: %d of %d (%.1f%%)"
			% [within_wall, wall.size(), share_wall * 100.0])
	# DRY FRAMES, EACH WITH ITS DURATION (Maren's wording). The bar is zero of them.
	if dry.is_empty():
		print("  DRY FRAMES: 0 -- the buffer never ran out across %d moving frames" % drawn.size())
	else:
		var longest := 0.0
		var total := 0.0
		for d in dry:
			longest = maxf(longest, d)
			total += d
		print(("  DRY FRAMES: %d, holding %.0f ms in total, longest %.1f ms. The bar on this item "
				+ "is ZERO. Durations: %s") % [dry.size(), total, longest, dry])
	if _unlit > 0:
		print(("  %d frames drew no single body, so no rectangle could be attributed; see "
				+ "`WorldLayer.drawn_body`") % _unlit)
	if _walk_at > 0.0 and span.has("raw_from"):
		print("  input latency on your own body: %.0f ms (press -> first drawn movement)"
				% ((_clock[int(span["raw_from"]) + 1] - _walk_at) * 1000.0))
	# **BOTH HALVES, OR IT IS NOT A PASS.** Box 1 is every moving frame inside the bar AND no dry
	# frame; a run that holds for 200 ms and then draws beautifully is the thing the board felt.
	print("  VERDICT: %s" % ("WITHIN BAR" if share >= 1.0 and dry.is_empty() else "OUTSIDE BAR"))


func _as_floats(values: Array[int]) -> Array[float]:
	var out: Array[float] = []
	for v in values:
		out.append(float(v))
	return out


## **HOW LONG THE HOST TOOK OVER EACH TICK IT SENT**, in seconds, one entry per tick.
##
## ARRIVALS COLLAPSED PER SOCKET DRAIN FIRST, exactly as `AssayScene.playout_step` does and for the
## same reason: two bundles that come out of one `poll` are 0.17 ms apart, so a series of raw gaps is
## a measurement of this client's frame rate wearing the host's name. The span between two drains
## divided by the sim ticks between them is seconds per TICK whatever the delivery did.
func _host_ticks() -> Array[float]:
	var out: Array[float] = []
	var last_at := -1.0
	var last_tick := -1
	for i in _bundle_at.size():
		if last_at >= 0.0 and _bundle_at[i] - last_at <= AssayScene.SAME_FRAME:
			continue
		if last_at >= 0.0 and _bundle_tick[i] > last_tick:
			out.append((_bundle_at[i] - last_at) / float(_bundle_tick[i] - last_tick))
		last_at = _bundle_at[i]
		last_tick = _bundle_tick[i]
	return out


## THE MOVING STRETCH OF A PER-FRAME SERIES, both ends inclusive, so a distribution over it is about
## the walk and not about how long the probe watched a standing body.
func _slice(values: Array[float], from: int, to: int) -> Array[float]:
	var out: Array[float] = []
	for i in range(maxi(from, 0), mini(to + 1, values.size())):
		out.append(values[i])
	return out


func _scaled(values: Array[float], by: float) -> Array[float]:
	var out: Array[float] = []
	for v in values:
		out.append(v * by)
	return out
