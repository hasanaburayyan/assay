extends SceneTree
## ASSA-167: WHAT DOES THE LONG FRAME SPEND ITS TIME ON? The unit on this probe is MILLISECONDS and
## nothing here measures the body.
##
## Nerite's window run 2 of `maren_motion_probe.gd` had a **108 ms** frame, and a frame longer than
## one tick gap draws a whole tile however good the tween (ASSA-148's ruling: the sim steps one tile
## per tick at 10/s, and a renderer may not predict). So the jump that is left is a dropped frame,
## and the question is whose.
##
## **THE INSTRUMENT IS THE FIRST SUSPECT, which is the whole reason this file exists rather than a
## patch to Maren's probe.** Both known hitches were measured under a probe. One correction to how
## ASSA-167 words that, though, because it matters for what there is to turn off: `maren_motion_probe`
## does NOT print per frame -- every `print` in it is in the report at the end. What it does per frame
## is `_sample()`: four array appends and a read of `_screen._world.view`. So this probe runs the same
## walk with three different per-frame workloads and nothing else different between them:
##
##   quiet         one `Time.get_ticks_usec()` into a `PackedInt64Array`. As close to nothing as a
##                 probe can do and still know how long a frame was.
##   sampled       exactly what `maren_motion_probe._sample()` does, copied rather than called so the
##                 two files cannot drift into measuring different things.
##   instrumented  quiet, plus what the ENGINE says about each frame: the draw calls it issued, the
##                 node count, static memory, and whether the ore cache rebuilt.
##
## **WHAT THIS PROBE CANNOT DO IS NAME WHAT A LONG FRAME SPENT ITS TIME ON** -- ASSA-167 box 3, which
## was rewritten to say so. It used to print a `_process` / `outside` split from
## `Performance.TIME_PROCESS`, and that column was wrong rather than imprecise: the monitor is a
## ~1 Hz aggregate, so 703 of 715 consecutive frames report an IDENTICAL value, and the value
## attached to one frame EXCEEDED that frame's own measured length in 698 of 715. `outside` therefore
## printed a NEGATIVE millisecond count on 98% of frames. Deleted on Maren's ruling, ASSA-167.
## **Do not bring back a column that cannot say which frame it belongs to.**
##
## **WHAT IS LEFT DOES ELIMINATION, NOT ATTRIBUTION, and that is worth having.** The rest are true
## per-frame counters, each read at the end of its own frame: if the slowest frame issues the same
## draw calls over the same node count with no allocation and no ore-cache rebuild, nothing asked
## that frame to do more and the time went somewhere that is not our work. The node count separates a
## HUD rebuild (this client builds Labels by the dozen when a section's signature moves) from a
## draw-side stall, and static memory separates a big allocation from both. A median of 42 draw calls
## with the ASSA-214 scatter layer and 42 without is how this column killed a published explanation
## of that layer's cost.
##
## Run it in a REAL WINDOW. `--headless` has never hitched (137 fps mean, worst 23 ms over 1642
## frames) and a dummy driver measures nothing about presenting a frame.
##
##   godot --path . --script res://tools/frame_hitch_probe.gd -- <seed> <secs> <mode>

## The walk, in tiles. Long enough to be the ">=20-tile walk" box 1 asks for.
const WALK := 25

var _screen: Node
var _seed := "14247"
var _seconds := 12.0
var _mode := "quiet"
var _started := false
var _joined := false
var _done := false
var _started_at := 0.0
var _asked: Array = []

## WHEN EACH FRAME ENDED, in microseconds. A `PackedInt64Array` and not an `Array[int]`: a packed
## array does not box its elements, so the one thing this probe does per frame stays one store.
var _at := PackedInt64Array()
## THE ENGINE'S OWN ACCOUNT OF THE SAME FRAME, `instrumented` only. Per-frame counters only; see the
## header for why `Performance.TIME_PROCESS` is not among them and must not come back.
var _nodes := PackedInt64Array()
var _static_kb := PackedFloat64Array()
var _draws := PackedInt64Array()
var _ore := PackedStringArray()
## `sampled` ONLY: the four arrays `maren_motion_probe` fills, so that arm pays the same price.
var _samples: Array[Vector2] = []
var _parts: Array[float] = []
var _sampled_at: Array[float] = []
var _depths: Array[int] = []


## **A WALL-CLOCK CEILING, AND IT IS A MEMBER INITIALIZER** (ASSA-182). A `SceneTree` whose
## `_initialize` dies still gets `_process` every frame -- Godot exits 0 on a parse error and does not
## exit AT ALL on a runtime error in `_initialize` -- so a probe waiting for state that `_initialize`
## never set waits for ever. Measured on this machine: one typo held a headless Godot for 45 minutes,
## and an orphan that holds a port or an account makes somebody else's run fail for a reason they will
## never find. **Set at the end of `_initialize` it would be absent in exactly the case it is for**,
## which is the mistake the first version of this made (#242).
##
## 300 s is above every honest run these tools have: their own budgets are a 10 s join timeout plus a
## few hundred frames. The five with a budget of their own raise the ceiling from it -- two from the
## duration argument, three from the `_run_deadline` they already compute -- so this floor can
## never shorten a run somebody asked for.
const RUN_CEILING := 300.0
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	_seed = String(argv[0]) if argv.size() > 0 else "14247"
	_seconds = float(argv[1]) if argv.size() > 1 else 12.0
	_mode = String(argv[2]) if argv.size() > 2 else "quiet"
	# A LONGER RUN MAY BE ASKED FOR, and the floor above still covers the case where
	# `_initialize` dies before this line runs at all.
	_ceiling = maxf(_ceiling, Time.get_unix_time_from_system() + _seconds * 3.0 + 60.0)
	if not ["quiet", "sampled", "instrumented"].has(_mode):
		print("PROBE DEAD: mode must be quiet, sampled or instrumented, not %s" % _mode)
		_done = true
		quit(2)
		return
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		print("FAIL  frame_hitch_probe.gd ran past its %ds ceiling (started=%s): nothing finished it"
				% [int(RUN_CEILING), _started])
		quit(1)
		return true
	if not _started:
		if AssaySimHost.fresh_welcome_json(_seed, "marlow") == "":
			print("PROBE DEAD: no world on seed %s" % _seed)
			_done = true
			return true
		# THE BUTTON, NOT THE HANDLER, same as `maren_motion_probe`: a probe that called
		# `_on_play_solo` would skip whatever the screen does on a press, and the press is the thing
		# a player performs.
		var button := _find_button(_screen, "Play solo")
		if button == null:
			print("PROBE DEAD: no Play solo button")
			_done = true
			return true
		button.pressed.emit()
		_started = true
		_started_at = _now()
		print("mode=%s seed=%s window=%s; pressed Play solo"
				% [_mode, _seed, "REAL" if DisplayServer.get_name() != "headless" else "HEADLESS"])
		return false
	var now := _now()
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
		print("joined as player %d at %s; walking to %s" % [_screen._client.player_id, here, to])
		return false
	if now - _started_at > _seconds:
		_screen.stop_solo_relay()
		_report()
		return true
	_record()
	return false


## THE ONE THING THIS PROBE DOES PER FRAME, and the only line that differs between the three arms.
func _record() -> void:
	_at.append(Time.get_ticks_usec())
	if _mode == "sampled":
		# COPIED FROM `maren_motion_probe._sample()` RATHER THAN CALLED. Calling it would mean this
		# arm and that probe could only ever agree; copying means they can be compared.
		var view: Dictionary = _screen._world.view
		var players: Variant = view.get("players")
		if players != null:
			for entry in (players as Array):
				var p: Dictionary = entry
				_samples.append(p["at"] as Vector2)
				break
		_parts.append(_screen._tick_gap)
		_sampled_at.append(_now())
		_depths.append((_screen._pending as Array).size())
	elif _mode == "instrumented":
		_nodes.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		_static_kb.append(Performance.get_monitor(Performance.MEMORY_STATIC) / 1024.0)
		# **HOW MUCH WORK THE FRAME WAS, so a long one can be told from a busy one.** If the slowest
		# frame issues the same draw calls over the same object count as the median, then nothing
		# asked this frame to do more and the time went somewhere that is not work -- which on a
		# machine running six agents is the scheduler, not the client.
		_draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		# AND WHETHER THE ORE CACHE REBUILT, the one per-frame job in this client that is not
		# constant: `_refresh_world` re-reads every deposit in view when the window moves off its
		# cached rectangle, which during a 25-tile walk is exactly what keeps happening.
		_ore.append(str(_screen._ore_at) + _screen._ore_stamp)


func _report() -> void:
	if _at.size() < 3:
		print("NO FRAMES: %d" % _at.size())
		print("PROBE OK")
		return
	var gaps := PackedFloat64Array()
	for i in range(1, _at.size()):
		gaps.append(float(_at[i] - _at[i - 1]) / 1000.0)
	var total := 0.0
	var longest := 0.0
	for g in gaps:
		total += g
		longest = maxf(longest, g)
	print("mode %s: %d frames over %.1fs, mean %.2f ms (%.0f fps), LONGEST %.1f ms"
			% [_mode, _at.size(), total / 1000.0, total / float(gaps.size()),
			1000.0 * float(gaps.size()) / total, longest])
	# OVER THE TICK GAP IS THE BAR (ASSA-167 box 1): 95 ms, one tick at 10/s. Below it a frame cannot
	# force a whole-tile step; above it, one is required of any renderer that does not predict.
	var over := 0
	for g in gaps:
		if g >= 95.0:
			over += 1
	print("  frames at or over one tick gap (95 ms): %d of %d" % [over, gaps.size()])
	var order: Array[int] = []
	for i in gaps.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return gaps[a] > gaps[b])
	print("  the five longest frames:")
	for rank in mini(5, order.size()):
		var i: int = order[rank]
		var line := "    frame %5d  %6.1f ms" % [i + 1, gaps[i]]
		if _mode == "instrumented" and i + 1 < _draws.size():
			# WHAT THE FRAME WAS ASKED TO DO, not where its time went. Every number here is a counter
			# read at the end of this frame against the end of the one before, so it belongs to this
			# frame and to nothing else -- which is exactly what the deleted `_process` column could
			# not say about itself. The node delta is a HUD rebuild; the memory delta is an
			# allocation; the draw calls against their own median say whether this frame was busier.
			line += "   nodes %+d   static %+.0f KB   draws %d (median %d)   ore cache %s" % [
					_nodes[i + 1] - _nodes[i], _static_kb[i + 1] - _static_kb[i],
					_draws[i + 1], _median(_draws),
					"REBUILT" if _ore[i + 1] != _ore[i] else "unchanged"]
		print(line)
	if _mode == "instrumented":
		var ore_moves := 0
		for i in range(1, _ore.size()):
			if _ore[i] != _ore[i - 1]:
				ore_moves += 1
		print("  ore cache rebuilt in %d of %d frames, against a %.2f ms median frame."
				% [ore_moves, _ore.size(), _median_f(gaps)])
		print("  the machine while this ran: %s" % _load())
	if _mode == "sampled":
		print("  (the sampled arm also filled %d positions, %d parts, %d depths)"
				% [_samples.size(), _parts.size(), _depths.size()])
	print("PROBE OK")


## WHAT ELSE WAS ON THIS MACHINE. Six agents work here and a Godot window gets whatever is left: a
## frame time is a measurement of the computer as much as of the client, and a report that does not
## say so is a report somebody will read as a verdict on the renderer.
func _load() -> String:
	var out: Array = []
	OS.execute("/usr/bin/uptime", [], out)
	var line := String(out[0]).strip_edges() if not out.is_empty() else "unknown"
	var cut := line.find("load averages:")
	return "%s (%d cores)" % [line.substr(cut) if cut >= 0 else line,
			OS.get_processor_count()]


func _median(values: PackedInt64Array) -> int:
	if values.is_empty():
		return 0
	var copy := values.duplicate()
	copy.sort()
	return copy[copy.size() / 2]


func _median_f(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var copy := values.duplicate()
	copy.sort()
	return copy[copy.size() / 2]


func _find_button(node: Node, label: String) -> Button:
	if node is Button and (node as Button).text == label:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, label)
		if found != null:
			return found
	return null


## WHERE TO WALK, CLAMPED INTO THE WORLD -- the solo relay keeps its save, so a second run starts
## where the first one stopped and `here + 25` would walk off the map. `maren_motion_probe`'s own
## comment says this cost it two runs that looked like findings.
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
