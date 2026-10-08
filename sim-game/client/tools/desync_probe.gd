extends SceneTree
## **DOES A DESYNCED CLIENT GET BACK IN?** (ASSA-190 box 3.)
##
##   godot --headless --path . --script res://tools/desync_probe.gd -- [seed]
##
## ASSA-190 shipped the hang-up: a `Desync` now leaves `AssayNetClient` at DEAD with the socket
## closed BY US, so the join band comes back and Join is live. Five of its six boxes are met by the
## suite and by a `Desync` frame pushed through the real decode path. The sixth is this file, and it
## is the one a test cannot answer: **after a REAL desync against a REAL relay, does pressing Join
## rebuild the world from a fresh `Welcome`, in the same slot, and does the HOST then accept the
## rebuilt world?** The fix is worthless if the answer is no -- the player would be handed a button
## that drops them straight back into a world the host still disagrees with.
##
## **THE DESYNC IS REAL, AND NOT ONE LINE OF IT IS FAKED.** The honest way to cause a desync is to
## make this client's WORLD genuinely wrong, because that is what a determinism bug does; so the
## probe hands the live client ONE tick bundle the relay never sent, carrying one extra `MoveTo` for
## our own player. From that frame on the client is a peer that applied an input the host did not,
## which is a divergence in the only place divergences live. Everything after the injection is
## production code: the hash is computed by `sim`, the `ClientMsg::Hash` is written by Rust
## (`AssaySim.hash_message_json`), it goes down the real socket, the real `sim-relay` compares it
## against its own history (`sim-relay/src/main.rs`'s `ClientMsg::Hash` arm) and decides to send
## `Desync` -- and the two hashes in the band are the relay's own strings.
##
## **WHAT A WEAKER PROBE WOULD HAVE DONE, and why I did not.** `send_text` will put any text on the
## wire, so a probe could report a hash it had corrupted and get a `Desync` out of the relay in three
## lines. That measures the detection and lies about the recovery: the client's world would still be
## RIGHT, so "the world was rebuilt" could not be told from "the world was never wrong". A divergence
## this probe caused for real is the only version where the rejoin has something to repair.
##
## **THE INJECTION GOES INTO THE FRAME READER, NOT INTO THE SIM.** `feed_offline` refuses a client
## that is not offline (by design -- see `net_client.gd`), so the frame is fed to `_reader` directly
## on a live client, with `pending_bytes() == 0` asserted first so it can never land inside a
## half-read message from the socket. That way `main.gd::_on_tick_bundle` applies it and reports the
## hash through the real path, rather than the probe stepping the sim behind the screen's back.
## The relay's own bundle for that tick then arrives and the binding refuses it with a warning on
## stderr: EXPECTED, it is `sim-godot`'s "ignoring a bundle for tick N while at tick N+1", and it is
## the shape of the one bundle's inputs this client has lost.
##
## **IT DRIVES THE REAL SCREEN**, like `tools/reconnect_probe.gd` (ASSA-177), which is this file's
## sibling and worth reading first: same relay-spawning, same snapshots, same `_is_playing` terms.
## The question is about a person pressing a button, so the press is `_on_join()` on a live
## `scenes/main.tscn` -- the real guard (`_join_address` returns on its first line unless the stage
## is IDLE or DEAD, which is the whole reason a desync had to reach DEAD), the real `_on_welcomed`,
## the real band, the real status line. The two files are deliberately not merged: a drop and a
## divergence are different causes, `reconnect_probe` already runs eight cases under one ceiling, and
## this one needs a sim-level mutation none of those do.
##
## **THE CONTROL IS A CLEAN CHECKPOINT BEFORE THE INJECTION.** The client must report at least one
## hash that the host ACCEPTS (no `Desync`) before anything is injected. Without it a desync
## afterwards would only mean "this probe was in the room": a client that desynced on its own, or a
## relay that quarrels with every peer, would read exactly the same.
##
## Prints `DESYNC PROBE VERDICT: ...` and, only when every leg that ran passed, `DESYNC PROBE OK`
## LAST. Exit 0 on a NO: "a desynced client cannot get back in" is a result, and an exit code that
## called it a crash would make a CI grep hide it. Exit 1 only when the probe could not ASK.

## Not the founders' 42, and not a seed any other probe pins: this one generates its own world in a
## scratch saves dir and throws it away.
const DEFAULT_SEED := "777190"

const LISTEN_DEADLINE := 15.0
const JOIN_DEADLINE := 20.0
## **TWO HASH CHECKPOINTS' WORTH OF SLACK, AND THEN SOME.** `sim-net::HASH_EVERY` is 20 ticks and the
## relay's clock is 10/s, so a checkpoint is ~2s apart; the injected bundle may also consume the tick
## a report was due on, which pushes the first diverged report one whole interval out. 30s is ~15
## intervals. Generous on purpose: this is a COUNT measurement, and the studio Mac's load makes wall
## clocks slip (every timing number is held until the board says that box is fixed), so a tight
## deadline here would report a false NO about a client that works.
const DESYNC_DEADLINE := 30.0
## How long to wait for each hash report after the rejoin, same reasoning.
const CHECKPOINT_DEADLINE := 30.0
## **HOW MANY CHECKPOINTS THE REBUILT WORLD MUST SURVIVE, and why it is not one.** One is "the relay
## had nothing to compare"; two is the host validating the rebuilt world twice, which is the only
## evidence available on this side that the rejoin actually REPAIRED the divergence rather than
## hiding it until the next check.
const REJOIN_CHECKPOINTS := 2
## Let the relay notice our hang-up before Join is pressed. Not a measurement, a courtesy: the relay
## polls at its own clock and an account it still thinks is online is REFUSED, which is a real
## outcome this probe reports rather than papers over (see `_press_join_after_the_desync`).
const SETTLE := 0.8
## Presses allowed if the relay is still holding the account. Reported, never hidden.
const PRESSES := 4
## **SET WHERE `_initialize` CANNOT FAIL BEFORE IT.** A `SceneTree` whose `_initialize` dies still
## gets `_process` every frame, so a probe waiting for state that was never set waits for ever; a
## member initializer runs when the object is built. `reconnect_probe.gd` learned this the hard way
## (#242) and so did `join_probe.gd`.
const RUN_CEILING := 240.0

var _screen: Node = null
var _binary := ""
var _seed := DEFAULT_SEED
var _address := ""

var _relay_pid := -1
var _relay_stdio: FileAccess = null
var _relay_stderr: FileAccess = null
var _relay_said := PackedStringArray()

var _step := 0
var _until := 0.0
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING
var _done := false
var _lines := PackedStringArray()
## Every sentence the screen said, in order, so a refusal that scrolled past is still evidence.
var _said := PackedStringArray()

## **EVERY (tick, hash) PAIR THIS CLIENT ACTUALLY PUT ON THE WIRE.** Recorded in a `tick_bundle`
## handler connected AFTER `main.gd`'s, so it runs in the same frame but after the apply: at that
## moment `_sim.tick()` and `_sim.hash_hex()` ARE the pair the message carried, because `hash_due()`
## is asked of the world the step produced. This is what lets the verdict say the relay compared OUR
## hash rather than taking its word for it.
var _reported: Array[Dictionary] = []
## The `Desync` as it arrived, straight off the signal.
var _desync := {}

var _first := {}
var _control := {}
var _at_injection := {}
var _at_desync := {}
var _second := {}
var _after := {}

var _hash_before_injection := ""
var _hash_after_injection := ""
var _target := Vector2i(-1, -1)
var _target_seen := Vector2i(-1, -1)
var _reports_before_injection := 0
var _reports_at_rejoin := 0
var _presses := 0
var _band_after_desync := false
var _socket_status_after_desync := -1
var _desync_said := ""

## The legs, each a fact somebody could regress on its own.
var _control_ok := false
var _world_diverged := false
var _host_noticed := false
var _window_has_a_way_out := false
var _same_slot := false
var _rebuilt := false
var _host_accepts_the_rebuild := false


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
	# A SCRATCH SAVES DIR. Never the founders' world-42, never a player's solo dir.
	var saves := OS.get_user_data_dir().path_join("desync-probe-saves")
	DirAccess.make_dir_recursive_absolute(saves)
	OS.set_environment("R2TS_SAVES_DIR", saves)
	print("  saves dir %s, seed %s, relay %s" % [saves, _seed, _binary])

	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND, as the suite does: inside `SceneTree._initialize` a node added to the root is
	# not in the tree yet, so the engine's own `_ready` has not run and `_client` is still null. It is
	# idempotent -- `main.gd::_ready` guards on `_built` precisely because this happens.
	_screen._ready()
	_screen._client.note.connect(func(line): _said.append("note: %s" % line))
	_screen._client.link_failed.connect(func(line): _said.append("link_failed: %s" % line))
	_screen._client.refused.connect(func(line): _said.append("refused: %s" % line))
	_screen._client.desynced.connect(_on_desync)
	# AFTER the screen's own handler, on purpose. See `_reported`.
	_screen._client.tick_bundle.connect(_after_a_bundle)

	if not _spawn_relay("0"):
		return
	_step = 1
	_until = _now() + LISTEN_DEADLINE


func _process(_delta: float) -> bool:
	if _done:
		return true
	# THE CEILING FIRST: `_step == 0` means `_initialize` never finished, which is the case that runs
	# for ever, so it is checked before the step table rather than inside it.
	if _now() >= _ceiling:
		_bail("the probe ran past its %ds ceiling at step %d: nothing advanced it"
				% [int(RUN_CEILING), _step])
		return true
	match _step:
		1:
			_wait_for_listening_then_join()
		2:
			_wait_for_the_first_world()
		3:
			_wait_for_a_clean_checkpoint()
		4:
			_inject_one_bundle_the_host_never_sent()
		5:
			_confirm_this_client_really_diverged()
		6:
			_wait_for_the_desync()
		7:
			_read_the_window_a_few_frames_later()
		8:
			_press_join_after_the_desync()
		9:
			_wait_for_the_rejoin()
		10:
			_watch_the_host_accept_the_rebuilt_world()
	return _done


# ---------------------------------------------------------------- the session


## STEP 1: the relay says where it is, and Join is pressed once.
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
	_step = 2
	_until = _now() + JOIN_DEADLINE


## STEP 2: the baseline session. Every later number is compared against this one.
func _wait_for_the_first_world() -> void:
	if _screen._client.stage == AssayNetClient.Stage.JOINED and _screen._sim.running() \
			and _screen._client.bundles_seen > 0:
		_first = _snapshot()
		_lines.append("A. JOINED: %s" % _describe(_first))
		_step = 3
		_until = _now() + CHECKPOINT_DEADLINE
		return
	if _now() >= _until:
		_bail(("no world within %ds on the first join (stage %d): the probe never got as far as the "
				+ "question it exists to ask") % [int(JOIN_DEADLINE), _screen._client.stage])


## STEP 3: **THE CONTROL.** One hash reported and ACCEPTED -- the host had our number, compared it,
## and said nothing. Until that has happened, a `Desync` later would not be evidence about the
## injection: it could be a client that desyncs on its own or a relay that quarrels with everyone.
func _wait_for_a_clean_checkpoint() -> void:
	if _screen._client.desyncs_seen > 0:
		_bail(("this client desynced BEFORE anything was injected (%d, at tick %s): the control "
				+ "failed, so nothing this probe does next would mean anything")
				% [_screen._client.desyncs_seen, _desync.get("tick", -1)])
		return
	if _reported.size() >= 1:
		_control_ok = true
		_control = _snapshot()
		_lines.append(("B. CONTROL: reported hash %s for tick %d and the host accepted it (0 "
				+ "desyncs). %s") % [_reported[0].get("hash", ""), _reported[0].get("tick", -1),
				_describe(_control)])
		_step = 4
		_until = _now() + 5.0
		return
	if _now() >= _until:
		_bail(("no hash reached the relay within %ds (%d bundles applied, %d hashes sent): with no "
				+ "accepted checkpoint there is no control to compare a desync against")
				% [int(CHECKPOINT_DEADLINE), _screen._sim.applied, _screen._hashes_sent])


## STEP 4: **ONE BUNDLE THE HOST NEVER SENT.** The whole mutation, and the only dishonest byte in the
## run: from here the client's world really is wrong, by exactly one `MoveTo` for our own player.
##
## `pending_bytes() == 0` is waited for rather than assumed, because a frame fed into the middle of a
## half-read message from the socket would corrupt the stream and this probe would be measuring its
## own framing bug.
func _inject_one_bundle_the_host_never_sent() -> void:
	if _screen._client._reader.pending_bytes() != 0:
		if _now() >= _until:
			_bail("the frame reader never emptied (%d bytes pending): refusing to inject into the "
					% _screen._client._reader.pending_bytes()
					+ "middle of a message from the socket")
		return
	_at_injection = _snapshot()
	_hash_before_injection = _screen._sim.hash_hex()
	_reports_before_injection = _reported.size()
	# A TILE INSIDE THE WORLD, AWAY FROM SPAWN. Far enough that the walk is still going when the
	# desync lands, so the divergence is a moving target rather than one the host could coincide with.
	# TYPED, NOT INFERRED: `_screen` is a `Node` to this file, so every call through it hands back a
	# Variant and `:=` cannot infer. (A mismatched typed assignment aborts the function, which is why
	# these are the right types rather than `Variant`.)
	var size: Vector2i = _screen._sim.size_tiles()
	var spawn: Vector2i = _screen._sim.spawn_tile()
	_target = Vector2i(clampi(spawn.x + 12, 0, size.x - 1), clampi(spawn.y + 8, 0, size.y - 1))
	var at: int = _screen._sim.tick()
	var text := JSON.stringify({"Tick": {"tick": at, "inputs": [
		{"Player": {"player": _screen._client.player_id,
				"command": {"MoveTo": {"target": {"x": _target.x, "y": _target.y}}}}},
	]}})
	_screen._client._reader.feed(AssayProtocol.encode_text(text))
	_lines.append(("C. INJECTED a bundle for tick %d carrying one MoveTo to (%d, %d) for player %d, "
			+ "which the host never ordered. Our hash before: %s")
			% [at, _target.x, _target.y, _screen._client.player_id, _hash_before_injection])
	_step = 5
	_until = _now() + 5.0


## STEP 5: **THE PREMISE, ASSERTED RATHER THAN HOPED FOR.** A probe whose mutation silently failed to
## land would go on to report a NO about a client that works. Three things must be true: the bundle
## was applied, our player is walking where no host ordered it to, and the state hash MOVED. The
## third is the one the relay will act on; the second is what makes it a divergence and not a tick.
func _confirm_this_client_really_diverged() -> void:
	if _screen._sim.applied <= int(_at_injection.get("applied", 0)):
		if _now() >= _until:
			_bail("the injected bundle was never applied (%d applied, %d at the injection): the "
					% [_screen._sim.applied, _at_injection.get("applied", -1)]
					+ "mutation did not land, so this run says nothing about a desync")
		return
	_hash_after_injection = _screen._sim.hash_hex()
	_target_seen = _player_target()
	if _hash_after_injection == _hash_before_injection:
		_bail(("our state hash did not move across the injection (%s): the extra input changed "
				+ "nothing, so there is no divergence for the host to find")
				% _hash_after_injection)
		return
	if _target_seen != _target:
		_bail(("player %d is walking to %s, not to the injected (%d, %d): the extra input did not "
				+ "reach our world the way this probe claims")
				% [_screen._client.player_id, _target_seen, _target.x, _target.y])
		return
	_world_diverged = true
	_lines.append(("   our world moved: hash %s -> %s, player %d now walking to (%d, %d). THIS "
			+ "CLIENT IS NOW WRONG ABOUT THE WORLD.") % [_hash_before_injection,
			_hash_after_injection, _screen._client.player_id, _target_seen.x, _target_seen.y])
	_step = 6
	_until = _now() + DESYNC_DEADLINE


## STEP 6: the host's verdict, on its own schedule. Nothing is nudged here: the next hash this client
## owes goes out through `main.gd::_on_tick_bundle` and the relay decides.
func _wait_for_the_desync() -> void:
	if not _desync.is_empty():
		_host_noticed = true
		_at_desync = _snapshot()
		_desync_said = String(_screen._status.text)
		_socket_status_after_desync = _screen._client._socket.get_status()
		var ours := _reported_for(int(_desync.get("tick", -1)))
		_lines.append(("D. THE HOST NOTICED: Desync at tick %d -- it says we reported %s and it has "
				+ "%s. Stage %d, %d desyncs, socket status %d. Screen: \"%s\"")
				% [_desync.get("tick", -1), _desync.get("reported", ""),
				_desync.get("expected", ""), _screen._client.stage,
				_screen._client.desyncs_seen, _socket_status_after_desync, _desync_said])
		# **THE RELAY COMPARED OUR HASH, NOT A HASH.** Our own record of what went on the wire for
		# that tick must be the string the relay quotes back. Without this the band could be naming
		# two hashes neither of which this client ever computed, and nobody would know.
		if String(ours.get("hash", "")) != String(_desync.get("reported", "")):
			_lines.append(("   MISMATCH IN THE EVIDENCE: we recorded %s as the hash we sent for tick "
					+ "%d, the relay quotes %s back. One of the two is wrong and the band is the "
					+ "thing a player reads.") % [ours.get("hash", "(none recorded)"),
					_desync.get("tick", -1), _desync.get("reported", "")])
			_host_noticed = false
		if String(_desync.get("reported", "")) == String(_desync.get("expected", "")):
			_lines.append("   THE TWO HASHES IN THE MESSAGE ARE EQUAL, which cannot be a desync")
			_host_noticed = false
		_step = 7
		_until = _now() + 0.3
		return
	if _now() >= _until:
		_lines.append(("D. THE HOST NEVER NOTICED within %ds: %d hashes sent since the injection, "
				+ "stage %d, %s. A divergence this client cannot be told about is the determinism "
				+ "bug that passes as a bad connection.")
				% [int(DESYNC_DEADLINE), _reported.size() - _reports_before_injection,
				_screen._client.stage, _describe(_snapshot())])
		_report()


## STEP 7: **THE WAY OUT OF THE WINDOW, READ A FEW FRAMES AFTER THE EVENT AND NOT IN IT.** A parent's
## `_process` runs before its children's, so a band read in the frame the stage changed is one frame
## old -- `reconnect_probe.gd` nearly filed that stale reading as an ASSA-175 bug.
func _read_the_window_a_few_frames_later() -> void:
	if _now() < _until:
		return
	_band_after_desync = _screen._join_band.visible
	var dead: bool = _screen._client.stage == AssayNetClient.Stage.DEAD
	var hung_up: bool = _socket_status_after_desync != StreamPeerTCP.STATUS_CONNECTED
	var reads_as_a_cable := _desync_said.to_lower().contains("connection failed") \
			or _desync_said.to_lower().contains("could not reach")
	_window_has_a_way_out = dead and hung_up and _band_after_desync and not reads_as_a_cable
	_lines.append(("   stage DEAD: %s · we hung up (socket not CONNECTED): %s · join band on "
			+ "screen: %s · the sentence reads as a cable: %s")
			% [dead, hung_up, _band_after_desync, reads_as_a_cable])
	if not _window_has_a_way_out:
		# No press is possible or meaningful from here: this IS the failure ASSA-190 exists to fix.
		_report()
		return
	_step = 8
	_until = _now() + SETTLE


## STEP 8: **THE PRESS.** The same control a player has, at the stage a desync now leaves them in.
##
## The relay may still be holding the account from the session we just hung up on -- it polls at its
## own clock -- and then this press is REFUSED. That is a real thing a player would hit, so it is
## reported with the count rather than slept away: how many presses it took is the number that says
## whether the button works or whether it works eventually.
func _press_join_after_the_desync() -> void:
	if _now() < _until:
		return
	_presses += 1
	_screen._on_join()
	_said.append("press: Join %s (stage was %d, press %d)"
			% [_address, _screen._client.stage, _presses])
	_step = 9
	_until = _now() + JOIN_DEADLINE


## STEP 9: a `Welcome`, a refusal, or nothing.
func _wait_for_the_rejoin() -> void:
	if _screen._client.stage == AssayNetClient.Stage.JOINED and _screen._sim.running():
		_second = _snapshot()
		_reports_at_rejoin = _reported.size()
		_same_slot = int(_second.get("player", -2)) == int(_first.get("player", -1))
		# `AssaySimHost.start` zeroes `applied`, so a count BELOW the one at the desync is the fact
		# that this world was built from the new `Welcome` rather than carried over. The lever that
		# taught `reconnect_probe.gd` this: a second Welcome that did NOT restart the sim still
		# reported "rejoined and playing", because the stale world caught up and then applied
		# everything. Ticks advancing is not a rebuild.
		_rebuilt = int(_second.get("applied", -1)) < int(_at_desync.get("applied", 0))
		_lines.append(("E. REJOINED after %d press%s: %s. Same slot as the first join: %s · world "
				+ "rebuilt from the new Welcome: %s (%d bundles applied now, %d before the desync)")
				% [_presses, "" if _presses == 1 else "es", _describe(_second), _same_slot, _rebuilt,
				_second.get("applied", -1), _at_desync.get("applied", -1)])
		_step = 10
		_until = _now() + CHECKPOINT_DEADLINE
		return
	if _screen._client.stage == AssayNetClient.Stage.DEAD:
		_lines.append("   press %d REFUSED: screen says \"%s\"" % [_presses, _screen._status.text])
		if _presses < PRESSES:
			_step = 8
			_until = _now() + 1.0
			return
		_lines.append(("E. NEVER REJOINED in %d presses: the stage is DEAD and the screen says "
				+ "\"%s\"") % [_presses, _screen._status.text])
		_report()
		return
	if _now() >= _until:
		_lines.append(("E. THE REJOIN NEVER RESOLVED: stage %d after %ds, screen says \"%s\". "
				+ "Reader holds %d pending bytes, error \"%s\"")
				% [_screen._client.stage, int(JOIN_DEADLINE), _screen._status.text,
				_screen._client._reader.pending_bytes(), _screen._client._reader.error])
		_report()


## STEP 10: **THE LEG THE REST OF THIS PROBE EXISTS FOR.** A `Welcome` is a message; a repaired world
## is one the HOST goes on accepting. So the rebuilt world has to survive `REJOIN_CHECKPOINTS` hash
## comparisons with no second `Desync` -- the host checking our arithmetic twice against its own.
## Anything less and "rejoining cures a desync" would rest on the absence of evidence.
func _watch_the_host_accept_the_rebuilt_world() -> void:
	var fresh := _reported.size() - _reports_at_rejoin
	var desynced_again: bool = _screen._client.desyncs_seen > 1
	if desynced_again:
		_after = _snapshot()
		_lines.append(("F. DESYNCED AGAIN after the rejoin (%d total): the fresh Welcome did not "
				+ "cure it. %s") % [_screen._client.desyncs_seen, _describe(_after)])
		_report()
		return
	if fresh >= REJOIN_CHECKPOINTS:
		_after = _snapshot()
		_host_accepts_the_rebuild = _is_playing(_after, _second, _at_desync)
		_lines.append(("F. THE HOST ACCEPTS THE REBUILT WORLD: %d hashes reported since the rejoin, "
				+ "0 further desyncs. %s") % [fresh, _describe(_after)])
		_lines.append("   stepping: %s" % _terms(_after, _second, _at_desync))
		_report()
		return
	if _now() >= _until:
		_after = _snapshot()
		_lines.append(("F. ONLY %d of %d hashes reached the relay within %ds after the rejoin, so "
				+ "nothing here says the rebuilt world is accepted. %s")
				% [fresh, REJOIN_CHECKPOINTS, int(CHECKPOINT_DEADLINE), _describe(_after)])
		_report()


# ---------------------------------------------------------------- the client's own words


func _on_desync(tick: int, reported: String, expected: String) -> void:
	if _desync.is_empty():
		_desync = {"tick": tick, "reported": reported, "expected": expected}
	_said.append("desynced: tick %d, we hashed %s, the host has %s" % [tick, reported, expected])


## Connected AFTER `main.gd`'s handler, so the apply and the send have already happened: a hash that
## went out in this frame is the hash of the world the sim is on right now. See `_reported`.
func _after_a_bundle(_tick: int, _inputs: Array, _raw: String) -> void:
	if _screen == null or not _screen._sim.running():
		return
	while _screen._hashes_sent > _reported.size():
		_reported.append({"tick": _screen._sim.tick(), "hash": _screen._sim.hash_hex()})


func _reported_for(tick: int) -> Dictionary:
	for pair in _reported:
		if int(pair.get("tick", -1)) == tick:
			return pair
	return {}


func _player_target() -> Vector2i:
	for player in _screen._sim.players():
		if int((player as Dictionary).get("id", -1)) == _screen._client.player_id:
			var target: Variant = (player as Dictionary).get("target")
			return target if target is Vector2i else Vector2i(-1, -1)
	return Vector2i(-1, -1)


# ---------------------------------------------------------------- the relay


func _spawn_relay(port: String) -> bool:
	_address = ""
	_relay_said = PackedStringArray()
	# `--fresh` because this probe runs over and over: a resumed save would start each run at
	# whatever tick the last one reached, and the account map from a session that ended in a desync is
	# not state any later run should inherit. The scratch saves dir keeps the file out of everyone's
	# way; `--fresh` keeps the world out of this run's way.
	var args := PackedStringArray([_seed, "--bind", "127.0.0.1", "--port", port, "--fresh"])
	var pipe := OS.execute_with_pipe(_binary, args)
	if pipe.is_empty() or int(pipe.get("pid", -1)) <= 0:
		_bail("could not start %s on port %s" % [_binary, port])
		return false
	_relay_pid = int(pipe["pid"])
	_relay_stdio = pipe["stdio"]
	_relay_stderr = pipe.get("stderr")
	print("  relay pid %d on port %s" % [_relay_pid, port])
	return true


## READ ONLY WHAT IS ALREADY WAITING. `FileAccess.get_line` on a pipe BLOCKS (measured at 3044ms in
## `AssaySoloRelay`), and a blocked probe cannot time anything out.
func _drain_relay() -> void:
	while _relay_stdio != null and _relay_stdio.get_length() > _relay_stdio.get_position():
		var line := _relay_stdio.get_line()
		if line.begins_with(AssaySoloRelay.LISTENING):
			_address = line.substr(AssaySoloRelay.LISTENING.length()).strip_edges()
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


func _snapshot() -> Dictionary:
	return {
		"player": _screen._client.player_id,
		"relay_tick": _screen._client.last_tick,
		"bundles": _screen._client.bundles_seen,
		"sim_tick": _screen._sim.tick(),
		"applied": _screen._sim.applied,
		"running": _screen._sim.running(),
		"hash": _screen._sim.hash_hex() if _screen._sim.running() else "",
		"hashes_sent": _screen._hashes_sent,
		"desyncs": _screen._client.desyncs_seen,
		"fail_reason": _screen._sim.fail_reason,
	}


func _describe(snap: Dictionary) -> String:
	return ("player %d, relay tick %d, %d bundles, sim tick %d (%d applied), running %s, hash %s, "
			+ "%d hashes sent, %d desyncs%s") % [snap.get("player", -1), snap.get("relay_tick", -1),
			snap.get("bundles", -1), snap.get("sim_tick", -1), snap.get("applied", -1),
			snap.get("running", false), snap.get("hash", ""), snap.get("hashes_sent", -1),
			snap.get("desyncs", -1),
			"" if String(snap.get("fail_reason", "")) == "" else
					", sim fail \"%s\"" % snap.get("fail_reason", "")]


## IS THIS A PLAYABLE SESSION? Asked of three snapshots, because a `Welcome` is a message and a world
## that steps is the thing a player got back. The `rebuilt` term is the one a lever caught
## `reconnect_probe.gd` without; it is spelled out there.
func _is_playing(after: Dictionary, at_join: Dictionary, before: Dictionary) -> bool:
	return bool(after.get("running", false)) \
			and int(after.get("applied", 0)) > int(at_join.get("applied", 0)) \
			and int(after.get("sim_tick", -1)) > int(at_join.get("sim_tick", -1)) \
			and int(at_join.get("applied", 0)) < int(before.get("applied", 0))


func _terms(after: Dictionary, at_join: Dictionary, before: Dictionary) -> String:
	return ("sim running %s · applied more bundles %s · tick advanced %s · world rebuilt from the "
			+ "new Welcome %s (%d bundles applied at the welcome, %d before the desync)") % [
			after.get("running", false),
			int(after.get("applied", 0)) > int(at_join.get("applied", 0)),
			int(after.get("sim_tick", -1)) > int(at_join.get("sim_tick", -1)),
			int(at_join.get("applied", 0)) < int(before.get("applied", 0)),
			at_join.get("applied", -1), before.get("applied", -1)]


## The probe could not ASK its question. Exit 1: this is the one outcome that says nothing about the
## client.
func _bail(why: String) -> void:
	if _done:
		return
	_done = true
	if _screen != null and _screen._client != null:
		_screen._client.set_process(false)
	_kill_relay()
	_print_lines()
	print("FAIL  %s" % why)
	_free_screen()
	quit(1)


## The answer, either way. **EXIT 0 ON A NO.**
func _report() -> void:
	if _done:
		return
	_done = true
	# THE CLIENT STOPS POLLING BEFORE THE RELAY DIES. This file promises the verdict is the LAST line
	# and a CI grep reads it that way; killing the relay under a live client makes `main._say` print
	# "closed the connection" after it.
	if _screen != null and _screen._client != null:
		_screen._client.set_process(false)
	_kill_relay()
	_print_lines()
	print("")
	print("  the slot: first join player %d, after the desync %d"
			% [_first.get("player", -1), _second.get("player", -2)])
	print("  every hash this client put on the wire:")
	for pair in _reported:
		print("    tick %d: %s" % [pair.get("tick", -1), pair.get("hash", "")])
	print("  the screen's sentences, in order:")
	for line in _said:
		print("    %s" % line)
	# EVERY LEG IN THE VERDICT LINE, with `ran` separate from `ok`: a leg that could not happen must
	# not read as one that failed.
	var legs := [
		["a checkpoint the host accepted first", _control_ok, true],
		["our world really diverged", _world_diverged, _control_ok],
		["the host noticed and named both hashes", _host_noticed, _world_diverged],
		["the window has a way out", _window_has_a_way_out, _host_noticed],
		["Join put us back in the same slot", _same_slot, _window_has_a_way_out],
		["the world was rebuilt from the new Welcome", _rebuilt, not _second.is_empty()],
		["the host accepts the rebuilt world, stepping", _host_accepts_the_rebuild,
				not _second.is_empty()],
	]
	var ran := 0
	var passed := 0
	var terms := PackedStringArray()
	for leg in legs:
		var ok: bool = leg[1]
		var leg_ran: bool = leg[2]
		if leg_ran:
			ran += 1
			if ok:
				passed += 1
		terms.append("%s: %s" % [leg[0], ("yes" if ok else "NO") if leg_ran else "not run"])
	var verdict := "PARTLY"
	if ran > 0 and passed == ran:
		verdict = "YES"
	elif passed == 0:
		verdict = "NO"
	print("DESYNC PROBE VERDICT: %s -- %s" % [verdict, " · ".join(terms)])
	# A POSITIVE MARKER LAST, AND ONLY WHEN EVERY LEG THAT RAN PASSED. Godot exits 0 even when a
	# script fails to compile, so a grep for this line is the only thing CI can trust.
	if verdict == "YES" and ran == legs.size():
		print("DESYNC PROBE OK: a desynced client rejoined in %d press%s, same slot, %d hashes "
				% [_presses, "" if _presses == 1 else "es", _reported.size() - _reports_at_rejoin]
				+ "accepted after the rebuild")
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
