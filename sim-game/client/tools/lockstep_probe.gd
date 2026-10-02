extends SceneTree
## IS THIS CLIENT A REAL LOCKSTEP PEER? Headless, against a real relay, one line of verdict.
##
##   godot --headless --path . --script res://tools/lockstep_probe.gd \
##       -- localhost:7777 limpet [ticks] [walk]
##
## `join_probe.gd` proves the handshake and that bundles arrive. This proves the harder half: that
## every bundle is APPLIED through the real Rust sim, that our world stays on the relay's tick, and
## that the relay never calls us desynced. The relay compares our reported hash against its own and
## sends `Desync` when they differ, so A SILENT RUN IS THE PASS and the verdict is the relay's
## opinion of us rather than ours of ourselves.
##
## Prints `LOCKSTEP PROBE OK` LAST and only on success: a positive marker printed last is the only
## thing a grep can trust, because Godot exits 0 even when a script fails to compile.
##
## WHAT WOULD MAKE IT FAIL, all of them real failures and not flakes:
##  - the sim binding is missing or will not load (no world to step)
##  - a bundle is refused, which means our tick and the relay's have parted company
##  - no hash was ever due, so the silence proves nothing (HASH_EVERY is 20 ticks)
##  - the relay sends `Desync`: our world drifted from the host's
##
## WITH A FOURTH ARGUMENT `walk`, it also submits one `MoveTo` and checks that OUR OWN PLAYER MOVED IN
## THE STEPPED WORLD. That is the whole round trip -- command out, relay orders it onto a tick, bundle
## back, sim walks us -- and it is the only way to tell "this client submits commands" apart from
## "this client sends bytes". Nothing is predicted: the position checked is the sim's.
##
## Reconnect is deliberately absent (Decision 3), so there is no retry here either.

const DEFAULT_TICKS := 45
const JOIN_TIMEOUT := 10.0
## A relay at 10 ticks/s plus slack. Not a pacing choice -- the relay owns the clock.
const SECONDS_PER_TICK := 0.5

var _client: AssayNetClient
var _sim := AssaySimHost.new()
var _done := false
var _want_ticks := DEFAULT_TICKS
var _join_deadline := 0.0
var _run_deadline := 0.0
var _welcome_tick := -1
var _desynced_at := -1
var _refused_bundles := 0
## `walk` mode: where we asked to go, where we started, and whether the sim took us there.
var _walking := false
var _walk_from := Vector2i.ZERO
var _walk_to := Vector2i.ZERO
var _walk_sent := false
## HASHES WE ACTUALLY PUT ON THE WIRE, counted here and not in the host. The host counts the ones it
## produced, and the difference is the whole point: a report that was never sent is a report the relay
## never checked, and a probe that counted those would pass without ever being contradicted.
var _hashes_sent := 0


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.size() < 2:
		print("FAIL  usage: -- host[:port] name [ticks]")
		quit(1)
		return
	_want_ticks = int(argv[2]) if argv.size() > 2 else DEFAULT_TICKS
	_walking = argv.size() > 3 and String(argv[3]) == "walk"

	_client = AssayNetClient.new()
	_client.welcomed.connect(_on_welcomed)
	_client.tick_bundle.connect(_on_tick_bundle)
	_client.refused.connect(func(reason): _finish(false, "refused: %s" % reason))
	_client.link_failed.connect(func(reason): _finish(false, reason))
	# THE VERDICT THE RELAY GIVES US. Recorded rather than acted on: the run continues so the report
	# can say which tick drifted, and the exit code is still a failure.
	_client.desynced.connect(func(tick): _desynced_at = tick)
	_client.note.connect(func(line): print("  %s" % line))
	root.add_child(_client)

	var now := Time.get_unix_time_from_system()
	_join_deadline = now + JOIN_TIMEOUT
	_run_deadline = now + JOIN_TIMEOUT + float(_want_ticks) * SECONDS_PER_TICK
	_client.join(String(argv[0]), String(argv[1]))


func _process(_delta: float) -> bool:
	if _done:
		return true
	var now := Time.get_unix_time_from_system()
	if _client.stage != AssayNetClient.Stage.JOINED:
		if now >= _join_deadline:
			_finish(false, "no welcome within %ds (stage %d)" % [JOIN_TIMEOUT, _client.stage])
			return true
		return false
	if _desynced_at >= 0:
		_finish(false, ("the relay called us desynced at tick %d: our world drifted from the host's"
				% _desynced_at))
		return true
	if _sim.applied >= _want_ticks:
		_report()
		return true
	if now >= _run_deadline:
		_finish(false, ("only %d of %d bundles applied before the deadline (%d refused, relay at "
				+ "tick %d)") % [_sim.applied, _want_ticks, _refused_bundles, _client.last_tick])
		return true
	return false


func _on_welcomed(player: int, world: Dictionary, raw: String) -> void:
	_welcome_tick = int(world.get("tick", -1))
	if not _sim.start(raw):
		_finish(false, _sim.fail_reason)
		return
	print("  welcomed as player %d into a world at tick %d; sim at tick %d, hash %s"
			% [player, _welcome_tick, _sim.tick(), _sim.hash_hex()])


## Step, then report a hash if one is owed. The same order and the same rule as `sim-cli`, which is
## the reference client: both ask the sim whether a hash is due AFTER stepping.
func _on_tick_bundle(tick: int, _inputs: Array, raw: String) -> void:
	var before := _sim.applied
	var report := _sim.apply(raw)
	if _sim.applied == before:
		# A refused bundle is not noise. It means the relay's tick and ours have parted company, and
		# the hash check would catch it twenty ticks later at best.
		_refused_bundles += 1
		print("  REFUSED a bundle for tick %d while the sim is at tick %d" % [tick, _sim.tick()])
		return
	if report != "" and _client.send_text(report):
		_hashes_sent += 1
	_maybe_walk()


## Ask to walk, once, a few tiles from wherever the sim has us. Not on the first bundle: `MoveTo` is
## validated inside `step` against the world the relay will be on, and asking before we know where we
## are would be asking about a position we read rather than one we hold.
func _maybe_walk() -> void:
	if not _walking or _walk_sent or _sim.applied < 2:
		return
	var me := _my_player()
	if me.is_empty():
		_finish(false, "player %d is not in the stepped world" % _client.player_id)
		return
	_walk_from = me.get("pos", Vector2i.ZERO) as Vector2i
	# Four tiles along, and inside the map. The movement system walks one tile per tick, diagonals
	# included, so four ticks is the cost and the probe's tick budget has to cover it.
	var size := _sim.size_tiles()
	_walk_to = Vector2i(clampi(_walk_from.x + 4, 0, size.x - 1), _walk_from.y)
	if _walk_to == _walk_from:
		_finish(false, "nowhere to walk from %s in a %s world" % [_walk_from, size])
		return
	if not _client.submit({"MoveTo": {"target": {"x": _walk_to.x, "y": _walk_to.y}}}):
		_finish(false, "the MoveTo command was not submitted")
		return
	_walk_sent = true
	print("  submitted MoveTo from %s to %s at tick %d" % [_walk_from, _walk_to, _sim.tick()])


## Our own player, out of the stepped world. Found by id, because `players` is indexed by `PlayerId`
## and a slot is not a position in a list once anyone leaves.
func _my_player() -> Dictionary:
	for entry in _sim.players():
		var player: Dictionary = entry
		if int(player.get("id", -1)) == _client.player_id:
			return player
	return {}


func _report() -> void:
	if _refused_bundles > 0:
		_finish(false, "%d bundles were refused: this client is not in step" % _refused_bundles)
		return
	# A run with no hash in it proves nothing: the relay only contradicts us when we report one.
	if _hashes_sent <= 0:
		_finish(false, ("applied %d bundles but sent no hash, so the relay never checked us. "
				+ "HASH_EVERY is 20 ticks; ask for more than that.") % _sim.applied)
		return
	if _sim.tick() != _welcome_tick + _sim.applied:
		_finish(false, "sim at tick %d after %d bundles from tick %d"
				% [_sim.tick(), _sim.applied, _welcome_tick])
		return
	if _walking and not _check_walked():
		return
	print("  world: seed %s, %d x %d tiles, %d species, %d players, %d deposits"
			% [_sim.seed_text(), _sim.size_tiles().x, _sim.size_tiles().y,
			_sim.species_names().size(), _sim.players().size(), _sim.deposits().size()])
	_finish(true, "")


## DID THE SIM ACTUALLY WALK US? The position is read out of the stepped world, so this fails if the
## command never reached the relay, if the relay never put it on a tick, or if this client is drawing
## a world the rules did not produce.
func _check_walked() -> bool:
	if not _walk_sent:
		_finish(false, "walk mode asked for but no MoveTo was ever sent")
		return false
	var me := _my_player()
	var at := me.get("pos", Vector2i.ZERO) as Vector2i
	if at == _walk_from:
		_finish(false, "asked to walk from %s to %s and the sim has us still at %s"
				% [_walk_from, _walk_to, at])
		return false
	if at != _walk_to:
		_finish(false, ("asked to walk to %s, the sim has us at %s -- %d ticks may not have been "
				+ "enough to cover %d tiles") % [_walk_to, at, _sim.applied,
				absi(_walk_to.x - _walk_from.x)])
		return false
	print("  walked: the sim moved us from %s to %s" % [_walk_from, at])
	return true


func _finish(ok: bool, why: String) -> void:
	if _done:
		return
	_done = true
	if ok:
		print(("LOCKSTEP PROBE OK: joined at tick %d, applied %d bundles to tick %d, reported %d "
				+ "hashes, no desync. Our hash now %s") % [_welcome_tick, _sim.applied, _sim.tick(),
				_hashes_sent, _sim.hash_hex()])
	else:
		print("FAIL  %s" % why)
	quit(0 if ok else 1)
