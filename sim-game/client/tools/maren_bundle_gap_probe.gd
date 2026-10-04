extends SceneTree
## ASSA-179: HOW LONG DOES A *HEALTHY* SESSION EVER GO WITHOUT A BUNDLE? (Maren.)
##
##   godot --headless --path client --script res://tools/maren_bundle_gap_probe.gd -- [seed] [secs]
##
## Limpet asked me for the threshold at which a silent host is called dead, and said a number they
## picked alone would be tuned to their harness. A number I pick alone would be tuned to my taste,
## which is worse. So: measure the thing the threshold has to clear.
##
## THE FALSE-POSITIVE CASE IS THE ONE THAT NEEDS A NUMBER. A timeout that is too long leaves a player
## staring at a frozen world; a timeout that is too SHORT drops someone out of a session that was
## fine. The second cost is bounded now (ASSA-177: one press of Join, same slot, nothing lost), but
## it is not zero, and the only honest way to set it is to find the worst gap a LIVE relay and a LIVE
## client produce between them and leave room above it.
##
## WHAT IT MEASURES, and the distinction matters: the gap between consecutive arrivals of
## `tick_bundle` -- the signal `net_client.gd::_process` emits when it has actually read a bundle off
## the socket. Not `bundles_seen` polled per frame, which would quantise every gap to a frame.
##
## FRAME DELTAS ARE RECORDED IN THE SAME RUN, because the client's own stalls are a source of gaps
## that have nothing to do with the host: if `_process` does not run, nothing reads the socket, and a
## bundle that arrived on time is observed late. If the worst gap and the worst frame coincide, the
## gap is this machine's, not the relay's.
##
## THIS MACHINE IS THE WORST CASE WE HAVE and that is the right direction for a floor: it runs six
## agents. A player's quiet machine produces smaller gaps, so a threshold clearing THIS distribution
## clears theirs. Load is shown sufficient here, never necessary.

const DEFAULT_SEED := "777042"
const DEFAULT_SECONDS := 60.0
const LISTEN_DEADLINE := 10.0
const JOIN_DEADLINE := 12.0
const RUN_CEILING := 180.0

var _screen: Node = null
var _binary := ""
var _seed := DEFAULT_SEED
var _seconds := DEFAULT_SECONDS
var _address := ""
var _relay_pid := -1
var _relay_stdio: FileAccess = null
var _relay_said := PackedStringArray()

var _step := 0
var _until := 0.0
var _done := false
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING

var _gaps: Array[float] = []
var _frames: Array[float] = []
var _last_bundle_ms := -1.0
var _worst_gap := 0.0
var _worst_gap_frame := 0.0
var _frame_at_worst := 0.0


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.size() > 0:
		_seed = String(argv[0])
	if argv.size() > 1:
		_seconds = float(argv[1])
	_binary = AssaySoloRelay.find_binary()
	if _binary == "":
		print("FAIL  no sim-relay binary")
		quit(1)
		return
	var saves := OS.get_user_data_dir().path_join("maren-gap-probe-saves")
	DirAccess.make_dir_recursive_absolute(saves)
	OS.set_environment("R2TS_SAVES_DIR", saves)
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	_screen._client.tick_bundle.connect(_on_bundle)
	if not _spawn_relay("0"):
		return
	_step = 1
	_until = _now() + LISTEN_DEADLINE


## THE ARRIVAL, not a poll. Emitted from `_process` the moment a whole frame is read.
func _on_bundle(_tick: int, _inputs: Array, _raw: String) -> void:
	var now := float(Time.get_ticks_msec())
	if _last_bundle_ms >= 0.0:
		var gap := now - _last_bundle_ms
		_gaps.append(gap)
		if gap > _worst_gap:
			_worst_gap = gap
			_frame_at_worst = _worst_gap_frame
	_last_bundle_ms = now


func _process(delta: float) -> bool:
	if _done:
		return true
	var ms := delta * 1000.0
	_worst_gap_frame = maxf(_worst_gap_frame, ms)
	if _step >= 3:
		_frames.append(ms)
	if _now() >= _ceiling:
		_bail("ran past its %ds ceiling at step %d" % [int(RUN_CEILING), _step])
		return true
	match _step:
		1:
			_wait_then_join()
		2:
			_wait_for_the_world()
		3:
			_watch()
	return _done


func _wait_then_join() -> void:
	_drain_relay()
	if _address == "":
		if _now() >= _until:
			_bail("relay never said LISTENING: %s" % " / ".join(_relay_said))
		return
	_screen._host.text = _address
	_screen._on_join()
	_step = 2
	_until = _now() + JOIN_DEADLINE


func _wait_for_the_world() -> void:
	if _screen._client.stage == AssayNetClient.Stage.JOINED and _screen._sim.running() \
			and _screen._client.bundles_seen > 0:
		print("  joined, watching for %.0fs" % _seconds)
		_step = 3
		_until = _now() + _seconds
		# EVERY COUNTER RESET AT THE START OF THE WATCH. The join itself delivers a Welcome and then
		# a burst, and the gap across the handshake is not a gap in a running session.
		_gaps.clear()
		_frames.clear()
		_last_bundle_ms = -1.0
		_worst_gap = 0.0
		_worst_gap_frame = 0.0
		return
	if _now() >= _until:
		_bail("no world within %ds (stage %d)" % [int(JOIN_DEADLINE), _screen._client.stage])


func _watch() -> void:
	_drain_relay()
	if _now() < _until:
		return
	_report()


func _report() -> void:
	if _gaps.is_empty():
		_bail("no bundles arrived at all in the watch window")
		return
	_gaps.sort()
	_frames.sort()
	print("")
	print("BUNDLE ARRIVAL GAPS over %.0fs, seed %s, a real sim-relay on loopback" % [_seconds, _seed])
	print("  bundles %d   frames %d" % [_gaps.size() + 1, _frames.size()])
	print("  gap ms   min %.1f  p50 %.1f  p90 %.1f  p99 %.1f  MAX %.1f"
			% [_gaps[0], _pct(_gaps, 50), _pct(_gaps, 90), _pct(_gaps, 99), _gaps[-1]])
	print("  frame ms min %.1f  p50 %.1f  p90 %.1f  p99 %.1f  MAX %.1f"
			% [_frames[0], _pct(_frames, 50), _pct(_frames, 90), _pct(_frames, 99), _frames[-1]])
	print("  worst frame seen before the worst gap: %.1f ms" % _frame_at_worst)
	# HOW MUCH ROOM A THRESHOLD WOULD HAVE, said as a multiple rather than a margin, because the
	# thing it must clear is a tail and not a mean.
	for secs in [2.0, 3.0, 5.0, 10.0]:
		print("  a %.0fs threshold is %.1fx the worst gap in this run" % [secs, secs * 1000.0 / _gaps[-1]])
	print("")
	print("GAP PROBE VERDICT: worst healthy gap %.1f ms over %d bundles on a six-agent Mac"
			% [_gaps[-1], _gaps.size() + 1])
	_finish(0)


func _pct(sorted_values: Array[float], p: float) -> float:
	var i := int(floor(float(sorted_values.size() - 1) * p / 100.0))
	return sorted_values[clampi(i, 0, sorted_values.size() - 1)]


func _spawn_relay(port: String) -> bool:
	var pipe := OS.execute_with_pipe(_binary, PackedStringArray([_seed, "--bind", "127.0.0.1",
			"--port", port]))
	if pipe.is_empty() or int(pipe.get("pid", -1)) <= 0:
		_bail("could not start %s" % _binary)
		return false
	_relay_pid = int(pipe["pid"])
	_relay_stdio = pipe["stdio"]
	print("  relay pid %d" % _relay_pid)
	return true


func _drain_relay() -> void:
	while _relay_stdio != null and _relay_stdio.get_length() > _relay_stdio.get_position():
		var line := _relay_stdio.get_line()
		if line.begins_with(AssaySoloRelay.LISTENING):
			_address = line.substr(AssaySoloRelay.LISTENING.length()).strip_edges()
			continue
		if line.strip_edges() != "":
			_relay_said.append(line.strip_edges())


func _bail(why: String) -> void:
	print("FAIL  %s" % why)
	_finish(1)


func _finish(code: int) -> void:
	if _relay_pid > 0 and OS.get_process_exit_code(_relay_pid) == -1:
		OS.kill(_relay_pid)
	_relay_stdio = null
	_done = true
	quit(code)


func _now() -> float:
	return Time.get_unix_time_from_system()
