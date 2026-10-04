extends SceneTree
## **DOES PRESSING JOIN AFTER A DROP ACTUALLY RECONNECT YOU?** (ASSA-177, Maren's question.)
##
##   godot --headless --path . --script res://tools/reconnect_probe.gd -- [seed] [seconds]
##
## THE CONTRADICTION THIS EXISTS TO SETTLE. `main.gd::_join_address` lets a join through when the
## stage is IDLE **or DEAD**, and `net_client.gd::_process` treats DEAD as "not connected" rather
## than "finished" -- so the Join button is live after a drop and reaches a socket. Meanwhile the root
## `CLAUDE.md` says "a dropped client must restart to rejoin", `net_client.gd`'s own header says
## reconnect is "deliberately absent (Decision 3)", and the refusal sentence says "no reconnect in the
## demo". Three claims, no test. Maren: *"either answer is worth having."*
##
## **IT DRIVES THE REAL SCREEN, NOT `AssayNetClient` ALONE.** The question is about what happens when a
## player presses the button, so the probe presses `_on_join` on a live `scenes/main.tscn`: the real
## guard, the real `_on_welcomed` (which calls `AssaySimHost.start` a second time), the real status
## line, and the real join band. An `AssayNetClient` on its own would answer a narrower question than
## the one that was asked.
##
## **THE DROP IS A REAL DEAD SOCKET, NOT AN ASSIGNMENT TO `stage`.** The relay is killed, and DEAD is
## reached the way production reaches it: `_process` sees the socket's status change and calls
## `_fail`. A probe that wrote `stage = DEAD` would be testing my model of the client.
##
## **AND THE SAME PORT, WHICH COSTS THE TEN LINES BELOW.** `AssaySoloRelay` always appends `--port 0`,
## and `sim-relay`'s parser takes the LAST `--port`, so the production class cannot be asked for a
## fixed port. The relay is spawned here instead: relay 1 on `--port 0` to get a free one race-free,
## relay 2 on that same number, so the address in the host box never changes and "press Join again" is
## literally the same press.
##
## FOUR PRESSES, REPORTED SEPARATELY, because they are four different things a player does:
##   A. the first join, to have a world and a slot to compare against
##   B/C. Join at the old address with NOTHING listening -- what the control does when the host is gone
##   D. Join once a relay is back on that port -- the reconnect after a HOST RESTART
##   E. Join after only the SOCKET died, with the host still up and still holding the world -- which is
##      the drop a player actually gets (a blip, a sleep, a wifi change) and the one where nothing
##      about the world should have moved backwards
##
## Prints `RECONNECT PROBE VERDICT: ...` LAST, with YES or NO in it, and exits 0 on either: a
## no-reconnect answer is a result, not a probe failure. Only a probe that could not ASK exits 1.

const DEFAULT_SEED := "777042"
## Long enough to pass the relay's 20-tick autosave at 10 ticks/s, so relay 2 RESUMES the world
## rather than generating one: a reconnect into a freshly generated world would look identical on a
## pinned seed and would not be the thing being asked about.
const PLAY_SECONDS := 3.0
const JOIN_DEADLINE := 12.0
const DEAD_DEADLINE := 8.0
const LISTEN_DEADLINE := 10.0

var _screen: Node = null
var _binary := ""
var _seed := DEFAULT_SEED
var _address := ""
var _port := ""

var _relay_pid := -1
var _relay_stdio: FileAccess = null
var _relay_stderr: FileAccess = null
var _relay_said := PackedStringArray()

var _step := 0
var _until := 0.0
var _done := false
var _lines := PackedStringArray()

## What the first session had, to compare the later ones against.
var _first := {}
var _second := {}
var _before_drop := {}
var _before_blip := {}
var _after_blip := {}
var _host_restart_ok := false
var _blip_ok := false
## The join band at the drop, read twice on purpose. See `_wait_for_the_drop`.
var _band_at_the_drop := false
var _band_after := false
## Every sentence the screen said, in order, so a refusal that scrolled past is still evidence.
var _said := PackedStringArray()
var _dropped_said := ""
var _no_listener_said := ""


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.size() > 0:
		_seed = String(argv[0])
	_binary = AssaySoloRelay.find_binary()
	if _binary == "":
		print("FAIL  no sim-relay binary; looked in: %s"
				% ", ".join(AssaySoloRelay.candidate_paths()))
		quit(1)
		return
	# A SCRATCH SAVES DIR, inherited by both relays. Never the founders' world-42 and never the
	# solo dir a player's own world lives in.
	var saves := OS.get_user_data_dir().path_join("reconnect-probe-saves")
	DirAccess.make_dir_recursive_absolute(saves)
	OS.set_environment("R2TS_SAVES_DIR", saves)
	print("  saves dir %s, seed %s, relay %s" % [saves, _seed, _binary])

	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND, as the suite does: inside `SceneTree._initialize` a node added to the root is
	# not in the tree yet, so the engine's own `_ready` has not happened and `_client` is still null.
	# It is idempotent -- `main.gd::_ready` guards on `_built` precisely because this happens.
	_screen._ready()
	# EVERY SENTENCE, not the last one. `_status.text` is one line and the interesting ones replace
	# each other inside a frame or two.
	_screen._client.note.connect(func(line): _said.append("note: %s" % line))
	_screen._client.link_failed.connect(func(line): _said.append("link_failed: %s" % line))
	_screen._client.refused.connect(func(line): _said.append("refused: %s" % line))

	if not _spawn_relay("0"):
		return
	_step = 1
	_until = _now() + LISTEN_DEADLINE


func _process(_delta: float) -> bool:
	if _done:
		return true
	match _step:
		1:
			_wait_for_listening_then_join()
		2:
			_wait_for_the_first_world()
		3:
			_play_then_kill_the_relay()
		4:
			_wait_for_the_drop()
		5:
			_press_join_with_nothing_listening()
		6:
			_wait_for_the_second_drop()
		7:
			_wait_for_listening_then_join()
		8:
			_wait_for_the_reconnect()
		9:
			_watch_the_reconnected_world()
		10:
			_report_the_band_once_a_frame_has_passed()
		11:
			_kill_only_the_socket()
		12:
			_wait_for_the_blip_to_be_noticed()
		13:
			_wait_for_the_reconnect_after_the_blip()
		14:
			_watch_the_world_after_the_blip()
	return _done


# ---------------------------------------------------------------- the three presses


## STEP 1 / 7: the relay says where it is, and then Join is pressed ONCE.
func _wait_for_listening_then_join() -> void:
	_drain_relay()
	if _address == "":
		if _now() >= _until:
			_bail("relay never said LISTENING within %ds; it said: %s"
					% [int(LISTEN_DEADLINE), " / ".join(_relay_said)])
		return
	_screen._host.text = _address
	_screen._on_join()
	_said.append("press: Join %s (stage was %d)" % [_address, _screen._client.stage])
	if _step == 1:
		_step = 2
		_until = _now() + JOIN_DEADLINE
	else:
		_step = 8
		_until = _now() + JOIN_DEADLINE


## STEP 2: the first session, which is the baseline everything after is compared to.
func _wait_for_the_first_world() -> void:
	if _screen._client.stage == AssayNetClient.Stage.JOINED and _screen._sim.running() \
			and _screen._client.bundles_seen > 0:
		_first = _snapshot()
		_lines.append("A. FIRST JOIN: %s" % _describe(_first))
		_step = 3
		_until = _now() + PLAY_SECONDS
		return
	if _now() >= _until:
		_bail("no world within %ds on the FIRST join (stage %d): the probe never got as far as the "
				% [int(JOIN_DEADLINE), _screen._client.stage] + "question it exists to ask")


## STEP 3: let it run past an autosave, then kill the host under it.
func _play_then_kill_the_relay() -> void:
	if _now() < _until:
		return
	_before_drop = _snapshot()
	_lines.append("   played on to %s" % _describe(_before_drop))
	_kill_relay()
	_step = 4
	_until = _now() + DEAD_DEADLINE


## STEP 4: the drop itself, reached through the socket rather than through an assignment.
func _wait_for_the_drop() -> void:
	if _screen._client.stage == AssayNetClient.Stage.DEAD:
		_dropped_said = String(_screen._status.text)
		# **THE BAND IS READ TWICE, AND THE FIRST READING IS THE WRONG ONE.** It reported `false` on
		# the first run of this probe and I nearly wrote that down as an ASSA-175 bug. A parent's
		# `_process` runs before its children's, and `_client` is a child of the screen: on the frame
		# the socket dies, `main._process` has ALREADY asked the stage (still JOINED) by the time
		# `_client._process` sets DEAD. So the hidden band in this sample is one frame old, which is a
		# fact about when I looked and not about what the client does. `_band_after` is the honest one.
		_band_at_the_drop = _screen._join_band.visible
		_lines.append(("B. THE DROP: stage DEAD, screen says \"%s\". sim still running: %s at tick "
				+ "%d. Reader holds %d pending bytes, error \"%s\"")
				% [_dropped_said, _screen._sim.running(),
				_screen._sim.tick(), _screen._client._reader.pending_bytes(),
				_screen._client._reader.error])
		_step = 10
		_until = _now() + 0.3
		return
	if _now() >= _until:
		_bail("the client never noticed the relay was gone (stage %d after %ds)"
				% [_screen._client.stage, int(DEAD_DEADLINE)])


## STEP 10: the band, a few frames after the drop rather than in the frame that noticed it.
func _report_the_band_once_a_frame_has_passed() -> void:
	if _now() < _until:
		return
	_band_after = _screen._join_band.visible
	_lines.append(("   join band on screen (ASSA-175): %s in the frame that noticed the drop, %s "
			+ "0.3s later. The first is a stale read, see the note in the source.")
			% [_band_at_the_drop, _band_after])
	_step = 5


## STEP 5: **THE CRUEL CASE.** The host is gone and the player presses the only live control. What
## the screen says here is the whole of Maren's "failing silently" worry, measured.
func _press_join_with_nothing_listening() -> void:
	_screen._on_join()
	_no_listener_said = String(_screen._status.text)
	_lines.append("C. JOIN WITH NOTHING LISTENING: stage %d, screen says \"%s\""
			% [_screen._client.stage, _no_listener_said])
	_step = 6
	_until = _now() + DEAD_DEADLINE


## STEP 6: and how that press ends, which is the part a player waits through.
func _wait_for_the_second_drop() -> void:
	if _screen._client.stage == AssayNetClient.Stage.DEAD:
		_lines.append("   that press ended with: \"%s\"" % _screen._status.text)
		if not _spawn_relay(_port):
			return
		_step = 7
		_until = _now() + LISTEN_DEADLINE
		return
	if _now() >= _until:
		_lines.append("   that press was still at stage %d after %ds -- it never resolved"
				% [_screen._client.stage, int(DEAD_DEADLINE)])
		if not _spawn_relay(_port):
			return
		_step = 7
		_until = _now() + LISTEN_DEADLINE


## STEP 8: the reconnect. Either answer ends the probe; neither is an error.
func _wait_for_the_reconnect() -> void:
	if _screen._client.stage == AssayNetClient.Stage.JOINED:
		_second = _snapshot()
		_lines.append("D. RECONNECT: welcomed again. %s" % _describe(_second))
		_step = 9
		_until = _now() + 2.0
		return
	if _screen._client.stage == AssayNetClient.Stage.DEAD:
		_lines.append("D. RECONNECT REFUSED: stage DEAD, screen says \"%s\"" % _screen._status.text)
		_report()
		return
	if _now() >= _until:
		_lines.append(("D. RECONNECT NEVER RESOLVED: stage %d after %ds, screen says \"%s\". Reader "
				+ "holds %d pending bytes, error \"%s\"") % [_screen._client.stage,
				int(JOIN_DEADLINE), _screen._status.text,
				_screen._client._reader.pending_bytes(), _screen._client._reader.error])
		_report()


## STEP 9: A WELCOME IS NOT A PLAYABLE WORLD. The question is whether the world MOVES afterwards, so
## the verdict waits for ticks to be applied on the new link.
func _watch_the_reconnected_world() -> void:
	if _now() < _until:
		return
	var after := _snapshot()
	_lines.append("   two seconds on: %s" % _describe(after))
	_host_restart_ok = _is_playing(after, _second, _before_drop)
	_lines.append("   verdict terms after a HOST RESTART: %s" % _terms(after, _second, _before_drop))
	if not _host_restart_ok:
		_report()
		return
	_step = 11


# ---------------------------------------------------------------- the drop a player actually gets


## STEP 11: **ONLY THE SOCKET DIES, AND THE HOST KEEPS THE WORLD.** This is the drop in the wild -- a
## blip, a lid closed, a wifi change -- and it is the one case where the world should not move
## backwards at all, because nothing reloaded a save. Case D's rollback is the relay's autosave
## interval; this case has no reason to lose a tick.
##
## `disconnect_from_host` ON THE CLIENT'S OWN SOCKET is the closest thing to a blip I can cause from
## inside the client: the stream is gone, nothing told the relay, and the stage is still JOINED until
## `_process` reads the status. The client then reaches DEAD the same way it does for a dead host.
func _kill_only_the_socket() -> void:
	_before_blip = _snapshot()
	_lines.append("E. THE BLIP: host still up, killing only the client's socket at %s"
			% _describe(_before_blip))
	_screen._client._socket.disconnect_from_host()
	_step = 12
	_until = _now() + DEAD_DEADLINE


## STEP 12: the client has to NOTICE. A socket that is gone with no word from the host is the case a
## lockstep peer can sit in for ever, so the deadline here is part of the answer.
func _wait_for_the_blip_to_be_noticed() -> void:
	if _screen._client.stage == AssayNetClient.Stage.DEAD:
		_lines.append("   noticed: \"%s\"" % _screen._status.text)
		_screen._on_join()
		_said.append("press: Join %s after the blip (stage was %d)"
				% [_address, _screen._client.stage])
		_step = 13
		_until = _now() + JOIN_DEADLINE
		return
	if _now() >= _until:
		_lines.append(("   NOT NOTICED: %ds after the socket went, the stage is still %d and the "
				+ "screen says \"%s\" -- a client sitting in a dead session believing it is live")
				% [int(DEAD_DEADLINE), _screen._client.stage, _screen._status.text])
		_report()


func _wait_for_the_reconnect_after_the_blip() -> void:
	if _screen._client.stage == AssayNetClient.Stage.JOINED:
		_after_blip = _snapshot()
		_lines.append("   welcomed again: %s" % _describe(_after_blip))
		_step = 14
		_until = _now() + 2.0
		return
	if _screen._client.stage == AssayNetClient.Stage.DEAD:
		_lines.append("   REFUSED after the blip: \"%s\"" % _screen._status.text)
		_report()
		return
	if _now() >= _until:
		_lines.append("   NEVER RESOLVED after the blip: stage %d, \"%s\""
				% [_screen._client.stage, _screen._status.text])
		_report()


func _watch_the_world_after_the_blip() -> void:
	if _now() < _until:
		return
	var after := _snapshot()
	_lines.append("   two seconds on: %s" % _describe(after))
	_blip_ok = _is_playing(after, _after_blip, _before_blip)
	_lines.append("   verdict terms after a BLIP: %s" % _terms(after, _after_blip, _before_blip))
	# THE WORLD MUST NOT HAVE GONE BACKWARDS. Nothing reloaded a save here, so a lower tick after the
	# rejoin than before the blip would be a real defect rather than the autosave interval.
	var lost := int(_before_blip.get("relay_tick", -1)) - int(_after_blip.get("relay_tick", -1))
	_lines.append("   ticks lost to the blip: %d (relay tick %d before, %d on the welcome)"
			% [lost, _before_blip.get("relay_tick", -1), _after_blip.get("relay_tick", -1)])
	_report()


# ---------------------------------------------------------------- the relay, by hand


## Spawn `sim-relay` on loopback at `port` ("0" means any). Not `AssaySoloRelay.start`, which always
## appends `--port 0`; everything else here is that class's own idiom.
func _spawn_relay(port: String) -> bool:
	_address = ""
	_relay_said = PackedStringArray()
	var args := PackedStringArray([_seed, "--bind", "127.0.0.1", "--port", port])
	var pipe := OS.execute_with_pipe(_binary, args)
	if pipe.is_empty() or int(pipe.get("pid", -1)) <= 0:
		_bail("could not start %s on port %s" % [_binary, port])
		return false
	_relay_pid = int(pipe["pid"])
	_relay_stdio = pipe["stdio"]
	_relay_stderr = pipe.get("stderr")
	print("  relay pid %d on port %s" % [_relay_pid, port])
	return true


## READ ONLY WHAT IS ALREADY WAITING. `FileAccess.get_line` on a pipe blocks (measured at 3044ms in
## `AssaySoloRelay`), and a blocked probe is a probe that cannot time anything out.
func _drain_relay() -> void:
	while _relay_stdio != null and _relay_stdio.get_length() > _relay_stdio.get_position():
		var line := _relay_stdio.get_line()
		if line.begins_with(AssaySoloRelay.LISTENING):
			_address = line.substr(AssaySoloRelay.LISTENING.length()).strip_edges()
			# THE PORT IS KEPT so relay 2 can take the same one. `rsplit` because an IPv6 address
			# has colons of its own.
			var bits := _address.rsplit(":", true, 1)
			_port = bits[1] if bits.size() > 1 else ""
			continue
		if line.strip_edges() != "":
			_relay_said.append(line.strip_edges())


func _kill_relay() -> void:
	if _relay_pid > 0 and OS.get_process_exit_code(_relay_pid) == -1:
		OS.kill(_relay_pid)
	_relay_stdio = null
	_relay_stderr = null
	_relay_pid = -1


# ---------------------------------------------------------------- reporting


func _now() -> float:
	return Time.get_unix_time_from_system()


## WHAT A SESSION IS, as numbers a second session can be compared against. `player` is the one that
## decides whether a reconnect resumed a slot or spawned a new player beside the old one.
func _snapshot() -> Dictionary:
	return {
		"player": _screen._client.player_id,
		"relay_tick": _screen._client.last_tick,
		"bundles": _screen._client.bundles_seen,
		"sim_tick": _screen._sim.tick(),
		"applied": _screen._sim.applied,
		"running": _screen._sim.running(),
		"fail_reason": _screen._sim.fail_reason,
		"players_in_world": (_screen._sim.players() as Array).size() if _screen._sim.running() else -1,
	}


func _describe(snap: Dictionary) -> String:
	return ("player %d, relay tick %d, %d bundles, sim tick %d (%d applied), running %s, "
			+ "%d players in the world%s") % [snap.get("player", -1), snap.get("relay_tick", -1),
			snap.get("bundles", -1), snap.get("sim_tick", -1), snap.get("applied", -1),
			snap.get("running", false), snap.get("players_in_world", -1),
			"" if String(snap.get("fail_reason", "")) == "" else
					", sim fail \"%s\"" % snap.get("fail_reason", "")]


## The probe could not ASK its question. Exit 1, because this is the one outcome that says nothing
## about the client.
func _bail(why: String) -> void:
	if _done:
		return
	_done = true
	_kill_relay()
	_print_lines()
	print("FAIL  %s" % why)
	_free_screen()
	quit(1)


## IS THIS A PLAYABLE SESSION, asked of three snapshots rather than of a welcome. A `Welcome` is a
## message; a world that steps is the thing a player got back.
##
## **THE `rebuilt` TERM IS HERE BECAUSE A LEVER CAUGHT ME WITHOUT IT** (and it is the only reason I
## am not reporting a YES that was partly luck). I broke `_on_welcomed` so the second Welcome did NOT
## restart the sim -- the client keeping its dead session's world -- and the host-restart leg still
## reported "rejoined and playing". It could: relay 2 resumes from an autosave BEHIND where the old
## session got to, so it replays ticks the stale sim refuses, catches up, and then every bundle
## applies. Ticks advance, nothing was rebuilt, and the terms could not tell the difference.
##
## `AssaySimHost.start` zeroes `applied`, so a count LOWER than the one at the drop is the fact that a
## world was built from the new Welcome rather than carried over. The blip leg never needed it (there
## the host is ahead, so a stale sim never aligns again) -- which is exactly why one leg of a probe
## agreeing is not two.
func _is_playing(after: Dictionary, at_join: Dictionary, before: Dictionary) -> bool:
	return bool(after.get("running", false)) \
			and int(after.get("applied", 0)) > int(at_join.get("applied", 0)) \
			and int(after.get("sim_tick", -1)) > int(at_join.get("sim_tick", -1)) \
			and int(at_join.get("applied", 0)) < int(before.get("applied", 0))


func _terms(after: Dictionary, at_join: Dictionary, before: Dictionary) -> String:
	return ("sim running %s · applied more bundles %s · tick advanced %s · world rebuilt from the "
			+ "new Welcome %s (%d bundles applied at the welcome, %d before the drop)") % [
			after.get("running", false),
			int(after.get("applied", 0)) > int(at_join.get("applied", 0)),
			int(after.get("sim_tick", -1)) > int(at_join.get("sim_tick", -1)),
			int(at_join.get("applied", 0)) < int(before.get("applied", 0)),
			at_join.get("applied", -1), before.get("applied", -1)]


## The answer, either way. **EXIT 0 ON A NO**: "the button does not reconnect" is the result this was
## filed to get, and an exit code that called it a failure would make a CI grep hide it.
func _report() -> void:
	if _done:
		return
	_done = true
	_kill_relay()
	_print_lines()
	print("")
	print("  the same slot every time: first join player %d, after a host restart %d, after a blip %d"
			% [_first.get("player", -1), _second.get("player", -1), _after_blip.get("player", -1)])
	print("  the screen's sentences, in order:")
	for line in _said:
		print("    %s" % line)
	var verdict := "NO"
	if _host_restart_ok and _blip_ok:
		verdict = "YES"
	elif _host_restart_ok or _blip_ok:
		verdict = "PARTLY"
	print("RECONNECT PROBE VERDICT: %s -- host restarted: %s · socket dropped with the host up: %s"
			% [verdict, "rejoined and playing" if _host_restart_ok else "did NOT get back in",
			"rejoined and playing" if _blip_ok else "did NOT get back in"])
	_free_screen()
	quit(0)


func _print_lines() -> void:
	print("")
	for line in _lines:
		print(line)


## The screen holds the relay it may have started and a socket; freeing it runs `_notification`.
func _free_screen() -> void:
	if _screen != null:
		_screen.stop_solo_relay()
		_screen.queue_free()
		_screen = null
