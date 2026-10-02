extends SceneTree
## IS THIS CLIENT A REAL LOCKSTEP PEER? Headless, against a real relay, one line of verdict.
##
##   godot --headless --path . --script res://tools/lockstep_probe.gd \
##       -- localhost:7777 limpet [ticks] [walk|session]
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
## It also prints one `HASH tick=N <hex>` line per hash it puts on the wire. The relay already
## checks those; the lines exist so SEVERAL PEERS CAN BE COMPARED WITH EACH OTHER afterwards,
## tick by tick, without taking the relay's word for it.
##
## WHAT WOULD MAKE IT FAIL, all of them real failures and not flakes:
##  - the sim binding is missing or will not load (no world to step)
##  - a bundle is refused, which means our tick and the relay's have parted company
##  - no hash was ever due, so the silence proves nothing (HASH_EVERY is 20 ticks)
##  - the relay sends `Desync`: our world drifted from the host's
##  - in `session` mode, the sim refuses one of our commands, or an action never takes effect
##
## THE THIRD ARGUMENT PICKS HOW MUCH IS PROVED:
##  - nothing: we apply bundles and report hashes. A spectator that keeps up.
##  - `walk`: one `MoveTo`, and OUR OWN PLAYER MUST HAVE MOVED IN THE STEPPED WORLD. The whole round
##    trip -- command out, relay orders it onto a tick, bundle back, sim walks us.
##  - `session`: a scripted demo session. Walk ONTO a deposit, `Mine` it until ore arrives, `Assay`
##    it until the sheet is exact, then keep stepping. This is the mode ASSA-7's "three or more
##    clients and the relay keep matching hashes through a full demo session" asks for: hashes
##    matching while the world is EMPTY proves much less than hashes matching while three peers are
##    changing it. Which deposit is `AssaySessionPlan`'s call, and it is unit-tested.
##
## Nothing is predicted in any mode. Every position, count and sheet checked is read back out of the
## stepped world, so a check can only pass if the real rules produced the state it is reading.
##
## Reconnect is deliberately absent (Decision 3), so there is no retry here either.

const DEFAULT_TICKS := 45
const JOIN_TIMEOUT := 10.0
## A relay at 10 ticks/s plus slack. Not a pacing choice -- the relay owns the clock.
const SECONDS_PER_TICK := 0.5
## `sim::tuning`, repeated here ONLY to size a budget and a deadline. No rule is decided with them:
## whether ore arrived and whether a sheet is exact are both read back out of the sim.
const HAND_MINE_TICKS := 4
const ASSAY_TICKS := 30

## What the scripted session is doing. `CRUISING` is after the script is done: still stepping, still
## reporting hashes, which is most of a long run.
enum Step { WALKING, MINING, ASSAYING, CRUISING }

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
## `session` mode: the script, and the tick each part of it actually completed on. -1 means "has not
## happened", and every one of them is set by reading the stepped world, never by sending a command.
var _session := false
var _step: Step = Step.WALKING
var _target_species := -1
var _target_center := Vector2i.ZERO
var _ore_before := 0
var _mine_sent_at := -1
var _mined_at := -1
var _assay_sent_at := -1
var _assayed_at := -1
var _ore_mined := 0
## HASHES WE ACTUALLY PUT ON THE WIRE, counted here and not in the host. The host counts the ones it
## produced, and the difference is the whole point: a report that was never sent is a report the relay
## never checked, and a probe that counted those would pass without ever being contradicted.
var _hashes_sent := 0


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.size() < 2:
		print("FAIL  usage: -- host[:port] name [ticks] [walk|session]")
		quit(1)
		return
	_want_ticks = int(argv[2]) if argv.size() > 2 else DEFAULT_TICKS
	var mode := String(argv[3]) if argv.size() > 3 else ""
	_walking = mode == "walk"
	_session = mode == "session"
	if mode != "" and not _walking and not _session:
		print("FAIL  unknown mode '%s'; expected walk or session" % mode)
		quit(1)
		return

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
		# The relay checks this one itself. The line is for comparing PEERS afterwards.
		print("  HASH tick=%d %s" % [_sim.tick(), _sim.hash_hex()])
	if _refusal_of_ours() != "":
		_finish(false, "the sim refused a command of ours: %s" % _refusal_of_ours())
		return
	_maybe_walk()
	_advance_session()


## OUR OWN command refusals, in the sim's own words. Anybody else's refusal is their business; ours
## means the script asked for something the rules do not allow, and a run that walked past it would
## report "no desync" about a session that never happened.
func _refusal_of_ours() -> String:
	for line in _sim.event_lines(_client.player_id):
		if String(line).begins_with("you: refused"):
			return String(line)
	return ""


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


## THE SCRIPTED SESSION, one bundle at a time.
##
## Each part of it moves on only when the STEPPED WORLD shows the previous part happened: we are on
## the tile, the ore is in the inventory, the sheet is exact. Timing is never assumed -- the relay
## owns the clock and another peer's inputs share our ticks, so "it has been 4 ticks, we must have
## mined" is exactly the kind of local guess this client is not allowed to make.
func _advance_session() -> void:
	if not _session or _done:
		return
	var me := _my_player()
	if me.is_empty():
		_finish(false, "player %d is not in the stepped world" % _client.player_id)
		return
	var at := me.get("pos", Vector2i.ZERO) as Vector2i
	match _step:
		Step.WALKING:
			if _target_species < 0:
				_choose_target(at)
				return
			if at == _target_center:
				_begin_mining()
		Step.MINING:
			var held := AssaySessionPlan.ore_held(_sim.inventory_of(_client.player_id),
					_target_species)
			if held > _ore_before:
				_ore_mined = held - _ore_before
				_mined_at = _sim.tick()
				print("  mined: %d ore of %s arrived by tick %d" % [_ore_mined, _species_name(),
						_mined_at])
				_begin_assaying()
		Step.ASSAYING:
			if AssaySessionPlan.is_assayed(_sim.species_sheets(), _target_species):
				_assayed_at = _sim.tick()
				print("  assayed: %s reads exact at tick %d" % [_species_name(), _assayed_at])
				_step = Step.CRUISING
		Step.CRUISING:
			pass


## Pick a deposit and start walking. Done once, two bundles in, for the same reason `walk` waits:
## until the sim has stepped us at least once, the only position we have is one we were told.
func _choose_target(at: Vector2i) -> void:
	if _sim.applied < 2:
		return
	# RANK IS OUR PLAYER ID so three peers take three different species -- see `session_plan.gd`.
	var deposit := AssaySessionPlan.choose_deposit(_sim.deposits(), _sim.species_sheets(), at,
			_client.player_id)
	if deposit.is_empty():
		_finish(false, ("no deposit in this world is hand-minable, unassayed and still holding ore, "
				+ "so there is no session to play. Host a fresh world."))
		return
	_target_species = int(deposit.get("species", -1))
	_target_center = deposit.get("center", Vector2i.ZERO) as Vector2i
	var needed := AssaySessionPlan.ticks_needed(at, _target_center, HAND_MINE_TICKS, ASSAY_TICKS)
	if _want_ticks < needed:
		_finish(false, ("%d ticks cannot cover this session: %d tiles to walk, %d to mine, %d to "
				+ "assay. Ask for at least %d.") % [_want_ticks,
				AssaySessionPlan.walk_ticks(at, _target_center), HAND_MINE_TICKS, ASSAY_TICKS,
				needed])
		return
	if not _client.submit({"MoveTo": {"target": {"x": _target_center.x, "y": _target_center.y}}}):
		_finish(false, "the MoveTo command was not submitted")
		return
	print("  session: walking from %s to the %s deposit at %s (%d tiles)" % [at, _species_name(),
			_target_center, AssaySessionPlan.walk_ticks(at, _target_center)])


func _begin_mining() -> void:
	_ore_before = AssaySessionPlan.ore_held(_sim.inventory_of(_client.player_id), _target_species)
	if not _client.submit("Mine"):
		_finish(false, "the Mine command was not submitted")
		return
	_mine_sent_at = _sim.tick()
	_step = Step.MINING
	print("  session: standing on %s at %s, mining from tick %d" % [_species_name(), _target_center,
			_mine_sent_at])


## Assay on top of mining, not instead of it: `mining` and `assaying` are separate fields on a
## player and both systems run every tick, so the rest of the session has ore still arriving while
## the sheet sharpens. More inputs per tick is the point of this mode.
func _begin_assaying() -> void:
	if not _client.submit("Assay"):
		_finish(false, "the Assay command was not submitted")
		return
	_assay_sent_at = _sim.tick()
	_step = Step.ASSAYING
	print("  session: assaying %s from tick %d (%d ticks of standing still)" % [_species_name(),
			_assay_sent_at, ASSAY_TICKS])


func _species_name() -> String:
	var named := AssaySessionPlan.species_name(_sim.species_sheets(), _target_species)
	return named if named != "" else "species %d" % _target_species


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
	if _session and not _check_session():
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


## DID THE SESSION ACTUALLY HAPPEN? Every answer is read back out of the stepped world at the end of
## the run, not remembered from when we sent the command. A probe that passed on "I submitted Mine"
## would pass against a relay that threw our inputs away.
func _check_session() -> bool:
	if _target_species < 0:
		_finish(false, "session mode asked for but no deposit was ever chosen")
		return false
	var me := _my_player()
	var at := me.get("pos", Vector2i.ZERO) as Vector2i
	if at != _target_center:
		_finish(false, ("the sim has us at %s, not on the %s deposit at %s: the walk never "
				+ "finished, so %d ticks was too few") % [at, _species_name(), _target_center,
				_sim.applied])
		return false
	var held := AssaySessionPlan.ore_held(_sim.inventory_of(_client.player_id), _target_species)
	if held <= _ore_before:
		_finish(false, ("stood on the %s deposit and submitted Mine at tick %d, and the sim still "
				+ "has %d of its ore in our inventory") % [_species_name(), _mine_sent_at, held])
		return false
	if not AssaySessionPlan.is_assayed(_sim.species_sheets(), _target_species):
		_finish(false, ("submitted Assay at tick %d and the sim still reads %s as rough, so the "
				+ "assay never finished") % [_assay_sent_at, _species_name()])
		return false
	# The HUD is what a person would be looking at while this ran, and it is pure functions of these
	# same dictionaries -- so the words on the panel are checkable here, against the world that
	# produced them, without a screen.
	var lines := AssayHud.inventory_lines(_sim.inventory_of(_client.player_id))
	var ore := String(_species_name())
	var found := false
	for line in lines:
		if String(line).contains(ore):
			found = true
	if not found:
		_finish(false, ("the sim has %d %s ore in our inventory and the HUD's own inventory lines "
				+ "do not mention it: %s") % [held, ore, lines])
		return false
	print(("  session: %s mined from tick %d (first ore at %d, %d held now) and assayed from tick "
			+ "%d (exact at %d). The HUD's own lines say so.") % [ore, _mine_sent_at, _mined_at,
			held - _ore_before, _assay_sent_at, _assayed_at])
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
