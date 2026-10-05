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
## Ticks counted on the client's OWN `tick_bundle` signal, which fires once per bundle. Sampling
## `_tick_at` once a frame cannot tell one late tick from two that arrived in the same frame, and
## the difference decides whether delivery is bursty or my sampling was blind.
var _bundles := 0
var _bundle_gaps: Array[float] = []
var _last_bundle := 0.0
var _started := false
var _done := false
var _started_at := 0.0
var _next_tick := 0.0
var _samples: Array[Vector2] = []
## A FRAME SHORTER THAN THIS CANNOT HONESTLY DRAW A WHOLE TILE. The sim steps a walking player one
## tile per tick (`sim/src/step.rs`) and the relay's default clock is 10 ticks/s, so the body's true
## speed is one tile per ~100 ms. In a longer frame a whole-tile step is REQUIRED of any renderer
## that does not predict (banned, ASSA-119); in a shorter one it is the renderer outrunning elapsed
## time, which is the ASSA-148 defect. 95 ms leaves a little room under the nominal 100.
const SHORT_FRAME := 0.095

## THE SIM'S OWN TILE AT EACH SAMPLE (ASSA-201). The snap bar below is written in TILES against a
## reference of ONE tile per tick, and that reference is only true on an AXIS-ALIGNED walk: the sim
## moves Chebyshev (`sim/src/step.rs` adds signum to BOTH axes), so a diagonal tick covers sqrt(2)
## tiles. A correctly tweened diagonal body therefore steps 1.414 and trips a 0.9-tile "snap" with
## nothing wrong. This probe was safe only because `_walk_target` hardcoded east.
var _tiles: Array[Vector2i] = []
## Walk diagonally instead of east, which is what makes the guard above reachable at all.
var _diag := false

var _parts: Array[float] = []
var _frames := 0
## WHEN EACH SAMPLE WAS TAKEN, which is the premise nobody had checked before building a fix.
##
## The drawn step per frame cannot be smaller than the distance a correctly tweened body covers in
## ONE FRAME. On a walk of one tile per tick at 10 tps, a 250 ms frame moves the body 2.5 tiles no
## matter what the interpolation does -- so if the client's frames are that long, "biggest step well
## under a tile" is unreachable by any renderer change and the defect is elsewhere. Marlow, ASSA-148.
var _sampled_at: Array[float] = []
## HOW MANY PRODUCED POSITIONS WERE WAITING TO BE DRAWN, per frame (ASSA-148's playout queue).
##
## THIS IS THE PRICE OF THE FIX, STATED IN THE UNIT IT IS PAID IN. A queue of depth d means the body
## is drawn d steps behind the newest tick -- about d x 100 ms of latency on your own movement. It
## also says whether the queue's cap is being hit, which is the one case the fix degrades: over the
## cap the oldest unplayed position is dropped and the next segment spans two tiles at double speed.
var _depths: Array[int] = []


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	_seed = String(argv[0]) if argv.size() > 0 else "14247"
	_seconds = float(argv[1]) if argv.size() > 1 else 4.0
	_whole = argv.size() > 2 and String(argv[2]) == "whole"
	_solo = argv.size() > 2 and String(argv[2]) == "solo"
	_diag = argv.size() > 3 and String(argv[3]) == "diag"
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	_screen._client.tick_bundle.connect(func(_t: int, _i: Array, _r: String) -> void:
		var at := _now()
		if _joined:
			_bundles += 1
			if _last_bundle > 0.0:
				_bundle_gaps.append(at - _last_bundle)
			_last_bundle = at)


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
		# THROUGH `_walk_target` SO THIS PATH IS CLAMPED TOO. It used to add WALK to x inline, which
		# is in-bounds from any spawn; a DIAGONAL offset is not, and `goto` off the map is refused
		# and the probe then measures a body that never moved.
		var to := _walk_target(me)
		_screen._client.submit(AssayActions.move_to(to))
		print("walking from %s to %s (%s)" % [me, to, "DIAGONAL" if _diag else "east"])
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
	if _diag:
		# ASSA-201'S OWN GOTO, not a symmetric one: from the demo spawn (56, 40) this is `goto 76 48`,
		# which is 8 ticks on BOTH axes and then 12 on x alone. A pure 45-degree walk would have no
		# straight phase at all, so it could not show the thing the item is about -- the speed
		# CHANGING mid-walk.
		var d := Vector2i(20, 8)
		if here.x + d.x < size.x - 1 and here.y + d.y < size.y - 1:
			return here + d
		return here - d
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
	_sampled_at.append(_now())
	_tiles.append(_me_tile())
	_depths.append((_screen._pending as Array).size())


## THE MOVING STRETCH, which is the only stretch this item is about (Maren's box 2, 07:47 UTC).
##
## A 25-tile walk takes about four seconds and the probe may watch for twelve, so most samples can be
## a body standing still -- and a standing body is exactly on a tile in every frame. Any statistic
## over ALL samples therefore measures HOW LONG WE WATCHED. These two indices bound the frames in
## which the drawn position actually changed: `from` is the frame before the first change, `to` is the
## frame of the last one. Returns an empty dictionary when nothing ever moved, which is a finding and
## not an error -- it is what a refused `move_to` looks like, and it fooled this probe twice.
func _moving_span() -> Dictionary:
	var first := -1
	var last := -1
	for i in range(1, _samples.size()):
		if not _samples[i].is_equal_approx(_samples[i - 1]):
			if first < 0:
				first = i - 1
			last = i
	if first < 0:
		return {}
	return {"from": first, "to": last}


## Biggest step, distinct positions, whole-tile snaps and parked share over one span of samples.
##
## A SNAP IS COUNTED AT 0.9 TILES AND NOT AT 1.0, because the mechanism produces a step of one tile
## plus or minus however far the tween had already travelled -- Maren measured 1.000 and 1.320 on the
## same walk. A bar written at exactly 1.0 would miss a 0.98 and read as a pass.
func _span_stats(from: int, to: int) -> Dictionary:
	var distinct := {}
	var biggest := 0.0
	var snaps := 0
	var on_tile := 0
	var biggest_at := from
	var snaps_in_short_frames := 0
	for i in range(from, to + 1):
		var at := _samples[i]
		distinct[at] = true
		if is_equal_approx(at.x, roundf(at.x)) and is_equal_approx(at.y, roundf(at.y)):
			on_tile += 1
		if i > from:
			var step := (at - _samples[i - 1]).length()
			if step > biggest:
				biggest = step
				biggest_at = i
			if step >= 0.9:
				snaps += 1
				# THE BAR (ASSA-148, corrected): a whole tile inside a frame SHORTER than a tick
				# gap is the renderer outrunning elapsed time. In a frame longer than a tick gap
				# the sim's own one-tile-per-tick motion requires it, so it is a dropped frame
				# (ASSA-167) and not a snap. `SHORT_FRAME` is the sim's rate, not a taste.
				if _sampled_at[i] - _sampled_at[i - 1] < SHORT_FRAME:
					snaps_in_short_frames += 1
	return {
		"frames": to - from + 1,
		"distinct": distinct.size(),
		"biggest": biggest,
		"biggest_at": biggest_at,
		"snaps": snaps,
		"snaps_short": snaps_in_short_frames,
		"on_tile": on_tile,
	}


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
	# THE FRAME CLOCK FIRST, because it bounds what any tween can do. See `_sampled_at`.
	if _sampled_at.size() > 2:
		var flo := _sampled_at[1] - _sampled_at[0]
		var fhi := flo
		var ftotal := 0.0
		for i in range(1, _sampled_at.size()):
			var dt := _sampled_at[i] - _sampled_at[i - 1]
			flo = minf(flo, dt)
			fhi = maxf(fhi, dt)
			ftotal += dt
		print("FRAMES AS THEY RAN: %d gaps, mean %.4fs (%.0f fps), min %.4fs, max %.4fs"
				% [_sampled_at.size() - 1, ftotal / float(_sampled_at.size() - 1),
				float(_sampled_at.size() - 1) / maxf(ftotal, 0.0001), flo, fhi])
	# THE MOVING STRETCH, which is Maren's box 2: every statistic above is over the whole window and
	# a window that outlasts the walk measures standing still.
	var span := _moving_span()
	if span.is_empty():
		print("MOVING STRETCH: none -- the drawn position never changed. The walk was refused or the"
				+ " body never got a tick; this is a finding about the run, not about the tween.")
	else:
		var from := int(span["from"])
		var to := int(span["to"])
		var s := _span_stats(from, to)
		print("MOVING STRETCH: frames %d..%d of %d (%.2fs of %.1fs), walked %.2f tiles"
				% [from, to, _samples.size(), _sampled_at[to] - _sampled_at[from], _seconds,
				(_samples[to] - _samples[from]).length()])
		if _depths.size() > to:
			var dhi := 0
			var dtotal := 0
			var at_cap := 0
			for i in range(from, to + 1):
				dhi = maxi(dhi, _depths[i])
				dtotal += _depths[i]
				if _depths[i] >= 3:
					at_cap += 1
			print("  PLAYOUT QUEUE over the walk: mean %.2f, max %d, at or over the cap in %d of %d"
					% [float(dtotal) / float(to - from + 1), dhi, at_cap, to - from + 1]
					+ " frames (a depth of d is ~d x %.0f ms of latency on your own body)"
					% [1000.0 * _parts[-1]])
		# IS THE BIGGEST STEP THE TWEEN'S FAULT OR THE FRAME'S? A body crossing one tile per
		# `_tick_gap` covers `dt / gap` tiles in a frame of `dt`, and no renderer can beat that. The
		# sim moves one tile per tick (`sim/src/step.rs`), so a frame longer than a tick gap MUST
		# draw a whole tile and a step measured in TILES reports the frame, not the tween (ASSA-148).
		#
		# IT IS COMPARED AT THE FRAME THE BIGGEST STEP LANDED IN, and that is the fix of ASSA-171.
		# This used to pair the worst step with the LONGEST frame's share, which is the most
		# forgiving denominator in the run and usually a different frame -- so a step could sit a
		# couple of percent over and still read as a pass. One step, one frame, one comparison.
		#
		# NOT a max over per-frame ratios, which is what I proposed first and withdrew: at 7 ms a
		# frame the 1 ms clock and the two reads being one node apart carry about 14%, so a max over
		# every frame's ratio is a max over noise and prints false reds. That caveat has not gone
		# away -- it is why `dt` is printed beside the ratio. Read a 7 ms frame's ratio as soft and a
		# 100 ms one as solid. For scale: a whole-tile snap in a 7 ms frame is fourteen times its
		# frame's share.
		var longest := 0.0
		for i in range(from + 1, to + 1):
			longest = maxf(longest, _sampled_at[i] - _sampled_at[i - 1])
		var hit := int(s["biggest_at"])
		var hit_dt := _sampled_at[hit] - _sampled_at[maxi(hit - 1, 0)] if hit > from else 0.0
		var hit_part: float = _parts[hit] if hit < _parts.size() else _parts[-1]
		var hit_share := hit_dt / maxf(hit_part, 0.01)
		print("  FRAME-PACED? biggest step %.3f tiles in frame %d, whose own share is %.3f"
				% [s["biggest"], hit, hit_share]
				+ " tiles (%.1f ms at %.0f ms a tile) -> ratio %.2f"
				% [1000.0 * hit_dt, 1000.0 * hit_part, s["biggest"] / maxf(hit_share, 0.0001)])
		print("    (old pairing, for comparison with logs before ASSA-171: against the LONGEST"
				+ " frame's share %.3f tiles, %.1f ms at %.0f ms a tile)"
				% [longest / maxf(_parts[-1], 0.01), 1000.0 * longest, 1000.0 * _parts[-1]])
		# THE BAR ITSELF, and it needs no estimated tick gap: a whole tile inside a frame shorter
		# than one.
		#
		# WHY THE RATIO LINES ABOVE ARE NOT THE BAR, measured rather than assumed. Their
		# denominator is an EMA of arrival gaps (`_tick_gap`), not the instantaneous playout rate,
		# and catch-up on a deep queue legitimately beats it: two clean headless runs on
		# `18d3dd6`+this, zero whole-tile steps in both, printed ratios of 1.47 and 4.13. So the
		# ratio cannot carry a pass/fail at the few-percent level -- I ruled a 5% tolerance on it
		# at 08:20 and withdrew it an hour later on these two runs. Do not put a bar on a number
		# whose denominator is an estimate.
		#
		# IT IS STILL INFORMATIVE AS AN ORDER OF MAGNITUDE, and 4.13 is not EMA error: a 67 ms
		# estimate against a true ~100 ms is a factor of 1.5, not 4. That run moved 0.741 tiles in
		# a 12 ms frame -- about 61 tiles/s against a true 10 -- which is sub-tile and so invisible
		# to the bar. Whether a 24 px hop is felt is a design question and mine; see ASSA-167.
		# THE BAR IS ONLY READABLE ON AN AXIS-ALIGNED WALK (ASSA-201), and that was true of every
		# run this probe had ever done only because `_walk_target` hardcoded east. It is stated
		# rather than assumed now: a diagonal tick is sqrt(2) tiles of REAL sim motion, so a
		# correctly tweened body steps 1.414 and every tick trips a 0.9-tile "snap". Refusing to
		# print a number is the honest outcome; printing one would be a 41% error wearing a bar.
		var diag_ticks := _diagonal_ticks()
		if diag_ticks > 0:
			print("  WHOLE-TILE STEPS: NO VERDICT -- %d of this walk's ticks moved BOTH axes."
					% diag_ticks)
			print("     The sim is Chebyshev, so a diagonal tick is sqrt(2) = 1.414 tiles and a")
			print("     correct tween trips the 0.9-tile snap test. This bar reads 1 tile/tick and")
			print("     cannot be believed here. Re-run without `diag` for the bar (ASSA-201 box 3).")
		else:
			print("  WHOLE-TILE STEPS IN A FRAME UNDER %.0f ms: %d  <-- THE BAR, must be 0"
					% [1000.0 * SHORT_FRAME, int(s["snaps_short"])]
					+ " (of %d whole-tile steps in all; the rest are dropped frames, ASSA-167)"
					% [int(s["snaps"])])
		_report_regimes()
		# WHY A MAX IS NOT ENOUGH, AND WHY THIS IS NOT A SECOND BAR (ASSA-167). The bar above counts
		# WHOLE-tile steps and reads 0. What is left is the SUB-tile hop -- 0.6-0.7 tiles in a 12 ms
		# frame -- and a max cannot answer the only question that matters about it, which is whether
		# a player feels it: one 20 px twitch in a 25-tile walk is not the same defect as thirty.
		#
		# So print the spread. Across six runs the hop tracks the FRAME RATE, not the tween: at
		# 93-100 fps the worst step is 9-11 px with 0-1 steps over 3x the mean, and at 73-79 fps it
		# is 20-23 px with 5% of steps over 2x. That is the ASSA-167 verdict (the hitch is the
		# machine, Marlow) showing up in the body as well as in the frame clock.
		#
		# NOTHING HERE IS A PASS/FAIL. It is context for a design call, like the ratio line.
		var steps: Array[float] = []
		for i in range(from + 1, to + 1):
			steps.append((_samples[i] - _samples[i - 1]).length())
		steps.sort()
		var tot := 0.0
		for v in steps:
			tot += v
		var mean_step := tot / maxf(float(steps.size()), 1.0)
		var over2 := 0
		var over3 := 0
		for v in steps:
			if v > 2.0 * mean_step:
				over2 += 1
			if v > 3.0 * mean_step:
				over3 += 1
		print("  STEP SPREAD: mean %.3f tiles (%.1f px), median %.3f, p90 %.3f, p99 %.3f,"
				% [mean_step, 32.0 * mean_step, steps[steps.size() / 2],
				steps[int(0.90 * steps.size())], steps[int(0.99 * steps.size())]]
				+ " max %.3f tiles (%.1f px)" % [steps[-1], 32.0 * steps[-1]])
		print("  HOPS over the walk: >2x mean %d · >3x mean %d · of %d steps (%.1f%% / %.1f%%)"
				% [over2, over3, steps.size(), 100.0 * over2 / steps.size(),
				100.0 * over3 / steps.size()]
				+ "  -- context for ASSA-167, NOT a bar")
		print("  biggest step %.3f tiles · WHOLE-TILE SNAPS (>=0.9) %d of %d steps · distinct"
				% [s["biggest"], s["snaps"], int(s["frames"]) - 1]
				+ " positions %d · on an exact tile %d of %d (%.1f%%)"
				% [s["distinct"], s["on_tile"], s["frames"],
				100.0 * float(s["on_tile"]) / float(s["frames"])])
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
	if _bundles > 0:
		var blo := _bundle_gaps[0] if not _bundle_gaps.is_empty() else 0.0
		var bhi := blo
		var btotal := 0.0
		for g in _bundle_gaps:
			blo = minf(blo, g)
			bhi = maxf(bhi, g)
			btotal += g
		print("BUNDLES ON THE SIGNAL: %d in %.1fs = %.2f/s; gap mean %.3fs min %.3fs max %.3fs"
				% [_bundles, _seconds, _bundles / _seconds,
				btotal / maxf(float(_bundle_gaps.size()), 1.0), blo, bhi])
	print("first %s last %s" % [_samples[0], _samples[-1]])
	print("PROBE OK")


## HOW MANY OF THIS WALK'S SIM TICKS MOVED BOTH AXES, from the sim's own tile sequence rather than
## from the target we asked for: a goto that runs out of one axis is diagonal for part of the walk
## and straight for the rest, so the walk as a whole is neither.
func _diagonal_ticks() -> int:
	var n := 0
	var prev := Vector2i(-9999, -9999)
	for t in _tiles:
		if prev.x != -9999 and t != prev:
			if absi(t.x - prev.x) > 0 and absi(t.y - prev.y) > 0:
				n += 1
		if t != prev:
			prev = t
	return n


## THE TWO SPEED REGIMES OF ONE GOTO (ASSA-201), measured on the DRAWN body rather than on the sim.
## A Chebyshev diagonal covers sqrt(2) tiles a tick and a straight step covers 1, so a goto that is
## not axis-aligned decelerates by 29.3% mid-walk with a perfect renderer and a perfect clock.
##
## SUSTAINED SPEED, NOT THE SPEED AT THE TICK BOUNDARY, and the difference is the whole measurement.
## My first version sampled only the frames where the sim's tile CHANGED and divided that frame's
## drawn distance by that frame's duration. That is the catch-up frame: it reported 25.8 and 15.8
## tiles/s against true values of 14.14 and 10.00, because a ~16 ms frame carrying a tick's worth of
## tween is an instantaneous rate and not a speed. Every frame of a phase counts here, so the
## denominator is the time the phase actually took.
func _report_regimes() -> void:
	if _tiles.size() != _samples.size() or _tiles.size() < 3:
		return
	var diag_dist := 0.0
	var diag_time := 0.0
	var straight_dist := 0.0
	var straight_time := 0.0
	var diag_frames := 0
	var straight_frames := 0
	# The phase a frame belongs to is set by the most recent tile transition at or before it.
	var phase_diag := false
	var seen_move := false
	var prev_tile := _tiles[0]
	# THE WALK ENDS AND THE BODY STANDS STILL FOREVER AFTER. Counting those frames puts zero
	# distance over real seconds into whichever phase happened to be last, which is how a straight
	# phase measured 3.27 tiles/s against a true 10.00 on my first run. Same trap as the "parked
	# 86% of frames" statistic I had to withdraw on ASSA-200: a window that outlives the motion.
	var last_move := 0
	for i in range(1, _tiles.size()):
		if _tiles[i] != _tiles[i - 1]:
			last_move = i
	if last_move < 2:
		return
	for i in range(1, last_move + 1):
		var t := _tiles[i]
		if t != prev_tile:
			phase_diag = absi(t.x - prev_tile.x) > 0 and absi(t.y - prev_tile.y) > 0
			seen_move = true
			prev_tile = t
		if not seen_move:
			continue
		var d := (_samples[i] - _samples[i - 1]).length()
		var dt := _sampled_at[i] - _sampled_at[i - 1]
		if dt <= 0.0:
			continue
		if phase_diag:
			diag_dist += d
			diag_time += dt
			diag_frames += 1
		else:
			straight_dist += d
			straight_time += dt
			straight_frames += 1
	if diag_time <= 0.0 or straight_time <= 0.0:
		return
	var dm := diag_dist / diag_time
	var sm := straight_dist / straight_time
	print("  THE TWO REGIMES OF THIS GOTO (ASSA-201), SUSTAINED drawn tiles per second:")
	print("     diagonal phase  %3d frames, %.2f tiles in %.2fs = %.2f tiles/s  (true 14.14)"
			% [diag_frames, diag_dist, diag_time, dm])
	print("     straight phase  %3d frames, %.2f tiles in %.2fs = %.2f tiles/s  (true 10.00)"
			% [straight_frames, straight_dist, straight_time, sm])
	print("     change mid-walk %+.1f%%   (the sim's own figure is -29.3%%)"
			% [100.0 * (sm - dm) / dm])
