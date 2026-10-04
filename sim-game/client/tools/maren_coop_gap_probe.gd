extends SceneTree
## ASSA-179 PART 2, THE HOLE I NAMED IN MY OWN MEASUREMENT. (Maren.)
##
##   godot --headless --path client --script res://tools/maren_coop_gap_probe.gd -- [seed] [secs]
##
## `maren_bundle_gap_probe.gd` measured the worst bundle gap a healthy session produces -- 263ms over
## 599 bundles -- and I wrote under it, in the ruling that set `SILENCE_MS`, the two things that run
## did NOT contain: **a second player joining** (the relay answers a join with a full `Welcome`
## snapshot, a big blocking write on the thread that owns the clock) and any real network. Assay's
## first milestone is a TWO-PLAYER co-op demo, so the first of those is not an exotic case; it is the
## demo. A threshold measured only on a one-player session is measured on a world the game does not
## ship.
##
## SO THIS RUN IS THE SAME INSTRUMENT WITH THE DISTURBANCE PUT BACK IN. One Godot client stays joined
## and times every `tick_bundle` ARRIVAL, exactly as before. Meanwhile a real `sim-cli` peer joins,
## plays for a few seconds and is killed, over and over, so the relay serves a `Welcome` and loses a
## peer repeatedly inside the watch window.
##
## WHY A KILLED PEER AND NOT A STACK OF THEM: the demo's shape is two players, not eight, and a
## second peer that joins, leaves and rejoins is both the realistic disturbance and the repeated one.
## A stack of six would measure a crowd nobody is going to play in.
##
## **THE NUMBER THIS RUN EXISTS TO PRODUCE is not the max. It is the max NEAR A JOIN** -- every gap is
## tagged with whether it falls inside `BLAME_MS` of a join being requested, so the run reports the
## quiet distribution and the disturbed one separately and you can see whether the join is the cause
## rather than assuming it. A max with no attribution would only tell me this machine is loaded,
## which I already knew.
##
## Frame deltas are recorded in the same run for the same reason as before: if `_process` does not
## run, nothing reads the socket, and a bundle that arrived on time is observed late. A worst gap that
## coincides with a worst frame is this machine's, not the relay's.

const DEFAULT_SEED := "777042"
const DEFAULT_SECONDS := 60.0
const LISTEN_DEADLINE := 10.0
const JOIN_DEADLINE := 12.0
const RUN_CEILING := 240.0

## The peer's rhythm: join, stay this long, die, stay away this long, repeat.
const PEER_ALIVE := 4.0
const PEER_AWAY := 3.0
## How long after a join request a gap is still credited to that join. The relay ticks every 100ms
## and a Welcome is one write, so 1.5s is generous on purpose: an over-wide window can only make the
## disturbed set look MORE like the quiet one, which is the conservative direction for a threshold.
const BLAME_MS := 1500.0
## The peer's account name prefix. The relay's join line is matched on it, so our own welcome can
## never be counted as a peer's.
const PEER_PREFIX := "probe-peer-"

var _screen: Node = null
var _relay_binary := ""
var _cli_binary := ""
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

## Gaps split by whether a join was in flight, and the raw pairs so the report can name the worst.
var _quiet: Array[float] = []
var _disturbed: Array[float] = []
var _frames: Array[float] = []
## THE SAME GAPS MINUS THE FRAME THEY WERE OBSERVED IN -- see `_on_bundle`. This is the list a
## threshold actually has to clear, because it is the only one that is about the HOST.
var _host_only: Array[float] = []
var _last_bundle_ms := -1.0
var _frame_ms := 0.0
var _frame_at_worst := 0.0
var _worst_overall := 0.0

## The peer. -1 pid means away; `_peer_switch_at` is when its state next changes.
var _peer_pid := -1
var _peer_stdio: FileAccess = null
var _peer_switch_at := 0.0
var _peer_joins := 0
var _peer_kills := 0
var _peer_welcomed := 0
var _peer_said := PackedStringArray()
var _last_join_ms := -1.0
var _join_log: Array[String] = []


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.size() > 0:
		_seed = String(argv[0])
	if argv.size() > 1:
		_seconds = float(argv[1])
	_relay_binary = AssaySoloRelay.find_binary()
	if _relay_binary == "":
		print("FAIL  no sim-relay binary")
		quit(1)
		return
	# THE PEER IS THE REFERENCE CLIENT, found beside the relay rather than guessed: whatever built
	# one built the other, and a probe that silently measured a one-player session because it could
	# not find `sim-cli` would be the worst possible failure here -- it would look like a clean run.
	_cli_binary = _relay_binary.get_base_dir().path_join("sim-cli")
	if not FileAccess.file_exists(_cli_binary):
		print("FAIL  no sim-cli beside the relay at %s" % _cli_binary)
		quit(1)
		return
	# **A FRESH SAVES DIRECTORY EVERY RUN, and the second run of this probe is why.** The relay loads
	# whatever save it finds, so run two resumed run one's world at tick 600 with ten player slots in
	# it. That is not wrong to measure, but it is a DIFFERENT world from run one's, and two runs that
	# are not the same world cannot be compared -- which is the whole use of this probe. The grown
	# world is a separate axis and nothing here has measured it.
	var saves := OS.get_user_data_dir().path_join("maren-coop-probe-saves")
	DirAccess.make_dir_recursive_absolute(saves)
	var dir := DirAccess.open(saves)
	if dir != null:
		for stale in dir.get_files():
			dir.remove(stale)
	OS.set_environment("R2TS_SAVES_DIR", saves)
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	_screen._client.tick_bundle.connect(_on_bundle)
	if not _spawn_relay("0"):
		return
	_step = 1
	_until = _now() + LISTEN_DEADLINE


## THE ARRIVAL, not a poll. Emitted from `_process` the moment a whole frame is read off the socket.
func _on_bundle(_tick: int, _inputs: Array, _raw: String) -> void:
	var now := float(Time.get_ticks_msec())
	if _last_bundle_ms >= 0.0 and _step == 3:
		var gap := now - _last_bundle_ms
		# BLAMED ON THE REQUEST, NOT ON THE ARRIVAL. A gap that STRADDLES a join must count as
		# disturbed, so the test is whether the join happened within the window ending at this
		# arrival -- using the gap's start would miss exactly the gap the join caused.
		if _last_join_ms >= 0.0 and now - _last_join_ms <= BLAME_MS:
			_disturbed.append(gap)
		else:
			_quiet.append(gap)
		# **THE FRAME THIS GAP WAS SEEN IN, NOT THE WORST FRAME SO FAR -- and the first version of
		# this probe had the second, which is a running max and so can only ever exaggerate.** The
		# socket is read inside `_process`, so a bundle that arrived on time during a long frame is
		# observed up to that whole frame late. `gap - frame` is therefore a LOWER BOUND on the part
		# of the gap the relay could be responsible for, and the lower bound is the honest number for
		# a threshold: it is the one that cannot be inflated by this machine's own stalls.
		_host_only.append(maxf(gap - _frame_ms, 0.0))
		if gap > _worst_overall:
			_worst_overall = gap
			_frame_at_worst = _frame_ms
	_last_bundle_ms = now


func _process(delta: float) -> bool:
	if _done:
		return true
	var ms := delta * 1000.0
	_frame_ms = ms
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
		print("  joined, watching for %.0fs with a peer joining every %.0fs"
				% [_seconds, PEER_ALIVE + PEER_AWAY])
		_step = 3
		_until = _now() + _seconds
		# EVERY COUNTER RESET AT THE START OF THE WATCH, as in the one-player probe: our own join
		# delivers a Welcome and then a burst, and the gap across our handshake is not a gap in a
		# running session. The peer's joins are the subject; ours is setup.
		_quiet.clear()
		_disturbed.clear()
		_frames.clear()
		_host_only.clear()
		_last_bundle_ms = -1.0
		_worst_overall = 0.0
		_peer_switch_at = _now() + 1.0
		return
	if _now() >= _until:
		_bail("no world within %ds (stage %d)" % [int(JOIN_DEADLINE), _screen._client.stage])


func _watch() -> void:
	_drain_relay()
	_drive_peer()
	if _now() < _until:
		return
	_report()


## Join, live, die, repeat. One peer at a time; the state machine is two lines because the whole
## point is that the disturbance is real (a separate process doing a real handshake) rather than a
## simulated one.
func _drive_peer() -> void:
	if _now() < _peer_switch_at:
		return
	if _peer_pid < 0:
		_peer_joins += 1
		var name := "%s%d" % [PEER_PREFIX, _peer_joins]
		var pipe := OS.execute_with_pipe(_cli_binary, PackedStringArray(["--connect", _address,
				"--name", name, "--plain"]))
		if pipe.is_empty() or int(pipe.get("pid", -1)) <= 0:
			_bail("could not start the peer %s" % _cli_binary)
			return
		_peer_pid = int(pipe["pid"])
		_peer_stdio = pipe["stdio"]
		_last_join_ms = float(Time.get_ticks_msec())
		_join_log.append("join #%d as %s (pid %d) at +%.1fs"
				% [_peer_joins, name, _peer_pid, _seconds - (_until - _now())])
		_peer_switch_at = _now() + PEER_ALIVE
		return
	_kill_peer()
	_peer_kills += 1
	_peer_switch_at = _now() + PEER_AWAY


func _kill_peer() -> void:
	if _peer_pid > 0 and OS.get_process_exit_code(_peer_pid) == -1:
		OS.kill(_peer_pid)
	_peer_pid = -1
	_peer_stdio = null


func _report() -> void:
	_kill_peer()
	if _quiet.is_empty() and _disturbed.is_empty():
		_bail("no bundles arrived at all in the watch window")
		return
	if _peer_joins == 0:
		_bail("the peer never joined, so this run measured the one-player case again")
		return
	# SPAWNING A PEER IS NOT JOINING ONE. Without this the probe would happily report a clean
	# distribution measured on a session nothing ever disturbed.
	if _peer_welcomed < _peer_joins:
		_bail("%d peers spawned but the relay welcomed %d: the disturbance is not what it claims"
				% [_peer_joins, _peer_welcomed])
		return
	# A RUN WITH NO DISTURBED GAPS PROVED NOTHING and must not read as a clean result. It means the
	# blame window never caught an arrival, which is a broken probe, not a quiet relay.
	if _disturbed.is_empty():
		_bail("%d joins and not one gap inside the %.0fms blame window: the probe is wrong"
				% [_peer_joins, BLAME_MS])
		return
	_quiet.sort()
	_disturbed.sort()
	_frames.sort()
	print("")
	print("BUNDLE ARRIVAL GAPS over %.0fs with a SECOND PEER joining, seed %s, real sim-relay"
			% [_seconds, _seed])
	print("  peer joins %d, welcomed by the relay %d, kills %d   bundles %d   frames %d"
			% [_peer_joins, _peer_welcomed, _peer_kills,
			_quiet.size() + _disturbed.size() + 1, _frames.size()])
	for line in _join_log:
		print("    %s" % line)
	for line in _peer_said:
		print("    relay: %s" % line)
	_host_only.sort()
	_line("QUIET    (no join within %.0fms)" % BLAME_MS, _quiet)
	_line("DISTURBED(a join within %.0fms)" % BLAME_MS, _disturbed)
	_line("HOST-ONLY(gap minus its own frame) ", _host_only)
	print("  frame ms min %.1f  p50 %.1f  p90 %.1f  p99 %.1f  MAX %.1f"
			% [_frames[0], _pct(_frames, 50), _pct(_frames, 90), _pct(_frames, 99), _frames[-1]])
	print("  the frame the worst gap was OBSERVED in: %.1f ms" % _frame_at_worst)
	# ROOM AS A MULTIPLE, because the thing a threshold must clear is a tail, not a mean. Quoted
	# against the HOST-ONLY worst, since the client's own stalls are handled by WHERE the check runs
	# (after the drain, ASSA-179) and not by the size of the number.
	for secs in [1.0, 2.0, 3.0, 5.0, 10.0]:
		print("  a %.0fs threshold is %.1fx the worst HOST-ONLY gap (%.1fx the raw worst)"
				% [secs, secs * 1000.0 / maxf(_host_only[-1], 1.0),
				secs * 1000.0 / maxf(_worst_overall, 1.0)])
	print("")
	print("COOP GAP PROBE VERDICT: worst raw gap %.1f ms (quiet %.1f, disturbed %.1f), "
			% [_worst_overall, _quiet[-1], _disturbed[-1]]
			+ "worst HOST-ONLY %.1f ms, over %d bundles, %d real peer joins, six-agent Mac"
			% [_host_only[-1], _quiet.size() + _disturbed.size() + 1, _peer_joins])
	_finish(0)


func _line(label: String, values: Array[float]) -> void:
	if values.is_empty():
		print("  %s  none" % label)
		return
	print("  %s  n %d  min %.1f  p50 %.1f  p90 %.1f  p99 %.1f  MAX %.1f"
			% [label, values.size(), values[0], _pct(values, 50), _pct(values, 90),
			_pct(values, 99), values[-1]])


func _pct(sorted_values: Array[float], p: float) -> float:
	var i := int(floor(float(sorted_values.size() - 1) * p / 100.0))
	return sorted_values[clampi(i, 0, sorted_values.size() - 1)]


func _spawn_relay(port: String) -> bool:
	var pipe := OS.execute_with_pipe(_relay_binary, PackedStringArray([_seed, "--bind", "127.0.0.1",
			"--port", port]))
	if pipe.is_empty() or int(pipe.get("pid", -1)) <= 0:
		_bail("could not start %s" % _relay_binary)
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
		# **THE HOST'S OWN RECEIPT THAT IT SERVED A WELCOME, counted from the relay and not from the
		# peer.** A disturbance that did not happen cannot disturb anything, and the worst failure
		# this probe could have is a peer that only completed a TCP connect and was refused: the run
		# would read as a clean one-player result while claiming to be a co-op one. The relay logs
		# `[tick N] <name> (<account>) joined as player N from <addr>` after the Welcome is written.
		# MATCHED ON THE PEER'S NAME, not on the step. My first version gated this on being in the
		# watch, and the run printed "9 joins, 10 welcomed": the drain is lazy, so OUR OWN welcome
		# line was still unread when the step flipped and it counted as a peer's. A guard that can
		# be satisfied by the thing it is guarding against is not a guard.
		if line.contains("joined as player") and line.contains(PEER_PREFIX):
			_peer_welcomed += 1
			_peer_said.append(line.strip_edges())
			continue
		# WHICH WORLD, AND AT WHAT TICK, printed rather than swallowed: it is the receipt that the
		# saves wipe above worked, and the one line that tells a later reader whether two runs of
		# this probe measured the same thing.
		if line.begins_with("Hosting world"):
			print("  relay: %s" % line.strip_edges())
			continue
		if line.strip_edges() != "":
			_relay_said.append(line.strip_edges())


func _bail(why: String) -> void:
	print("FAIL  %s" % why)
	_finish(1)


func _now() -> float:
	return Time.get_unix_time_from_system()


func _finish(code: int) -> void:
	_kill_peer()
	if _relay_pid > 0 and OS.get_process_exit_code(_relay_pid) == -1:
		OS.kill(_relay_pid)
	_relay_stdio = null
	_done = true
	quit(code)
