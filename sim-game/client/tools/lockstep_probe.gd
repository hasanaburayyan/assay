extends SceneTree
## IS THIS CLIENT A REAL LOCKSTEP PEER? Headless, against a real relay, one line of verdict.
##
##   godot --headless --path . --script res://tools/lockstep_probe.gd \
##       -- localhost:7777 limpet [ticks] [walk|session|demo]
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
##  - in `session` mode, the sim refuses one of our commands, or a stage of the loop never takes
##    effect in the stepped world inside the tick budget
##
## THE THIRD ARGUMENT PICKS HOW MUCH IS PROVED:
##  - nothing: we apply bundles and report hashes. A spectator that keeps up.
##  - `walk`: one `MoveTo`, and OUR OWN PLAYER MUST HAVE MOVED IN THE STEPPED WORLD. The whole round
##    trip -- command out, relay orders it onto a tick, bundle back, sim walks us.
##  - `demo`: every stage `session` plays, ending in a world SOMEONE CAN JOIN LATER -- the player is
##    stopped and the drill is left unplaced, so the bench still has rows on it an hour afterwards.
##    Its product is a standing world, not a verdict about lockstep. See `_check_demo`.
##  - `session`: THE WHOLE DEMO LOOP, start to finish. Walk onto a deposit of the material this world
##    guarantees, mine it, assay it, craft a smelter, mine fuel, place the smelter, load it, smelt,
##    take the refined, make a handle, two heads and a frame, assemble a pick, equip it, assemble a
##    drill and plant it. This is what ASSA-7 asks for: hashes matching while the world is EMPTY
##    proves much less than hashes matching while three peers mine, build and plant in it.
##
## WHY THE PLANTING MATTERS MOST. `PlaceAssembly` is the only action in the loop that draws from the
## world's `Rng`: an overweight design calls `break_apart`, which rolls which parts come back. A
## client whose Rng had drifted by one draw would agree with everybody up to that moment and disagree
## for the rest of the world's life. It is the single most desync-prone thing in the game, so the
## session ends by planting something.
##
## AND THE VERDICT IS TREATED AS A PROMISE. `designs_of` gives the sim's own word on a design before
## it is placed: SAFE must then be placed, WILL BREAK must then break. UNCERTAIN promises nothing --
## it is a band overlapping the budget -- so the probe only records which happened. The verdict is
## never recomputed here; comparing mass against budget in GDScript is exactly the second opinion
## lockstep cannot absorb.
##
## Nothing is predicted in any mode. Every position, count, sheet and design checked is read back out
## of the stepped world, so a check can only pass if the real rules produced the state it is reading.
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

## WHAT THE SCRIPTED SESSION IS DOING, in the order it does it. `CRUISING` is after the loop is
## done: still stepping, still reporting hashes, which is most of a long run.
enum Step {
	WALKING,
	MINING,
	CRAFTING,
	TO_FUEL,
	FUEL_MINING,
	PLACING,
	LOADING,
	SMELTING,
	MAKING,
	PICK,
	DRILL,
	PLANTING,
	CRUISING,
}

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
## `session` mode. Every `_*_at` is the tick the STEPPED WORLD showed a stage finished on, never the
## tick we sent its command; -1 means it has not happened.
var _session := false
var _step: Step = Step.WALKING
var _material := -1
var _fuel := -1
var _target_center := Vector2i.ZERO
var _stand_at := Vector2i.ZERO
var _fuel_center := Vector2i.ZERO
var _fuel_stand := Vector2i.ZERO
var _ore_before := 0
var _ore_wanted := 0
var _mined_at := -1
var _assay_sent := false
var _assay_skipped := false
var _assayed_at := -1
var _crafted_at := -1
var _smelter_at := Vector2i(-1, -1)
var _building := -1
var _placed_at := -1
var _loaded_at := -1
var _taken_at := -1
var _refined_held := 0
var _parts_at := -1
var _pick_at := -1
var _equipped_at := -1
## `demo` mode: the same loop, but it leaves the world fit to be joined later. See `_check_demo`.
var _demo := false
var _drill_at := -1
var _drill_spot := Vector2i(-1, -1)
var _drill_verdict := ""
var _planted_at := -1
var _broke_at := -1
var _break_line := ""
## One-shot submissions, keyed by stage name, so no stage can send its command twice while waiting for
## the world to show it happened.
var _sent := {}
## HASHES WE ACTUALLY PUT ON THE WIRE, counted here and not in the host. The host counts the ones it
## produced, and the difference is the whole point: a report that was never sent is a report the relay
## never checked, and a probe that counted those would pass without ever being contradicted.
var _hashes_sent := 0


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.size() < 2:
		print("FAIL  usage: -- host[:port] name [ticks] [walk|session|demo]")
		quit(1)
		return
	_want_ticks = int(argv[2]) if argv.size() > 2 else DEFAULT_TICKS
	var mode := String(argv[3]) if argv.size() > 3 else ""
	_walking = mode == "walk"
	# `demo` plays every stage `session` does, so it IS a session; it only ends differently.
	_demo = mode == "demo"
	_session = mode == "session" or _demo
	if mode != "" and not _walking and not _session:
		print("FAIL  unknown mode '%s'; expected walk, session or demo" % mode)
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
	if not _client.submit(AssayActions.move_to(_walk_to)):
		_finish(false, "the MoveTo command was not submitted")
		return
	_walk_sent = true
	print("  submitted MoveTo from %s to %s at tick %d" % [_walk_from, _walk_to, _sim.tick()])


## THE SCRIPTED SESSION, one bundle at a time.
##
## Each stage moves on only when the STEPPED WORLD shows the previous one happened: we are on the
## tile, the ore is in the inventory, the sheet is exact, the smelter is on the map, the part is in
## our hands. Timing is never assumed -- the relay owns the clock and other peers' inputs share our
## ticks, so "it has been 4 ticks, we must have mined" is exactly the kind of local guess this client
## is not allowed to make.
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
			if _material < 0:
				_begin_session(at)
				return
			if at == _stand_at:
				_begin_mining()
		Step.MINING:
			_mining(at)
		Step.CRAFTING:
			if _held("smelter", _material) > 0:
				_crafted_at = _sim.tick()
				print("  session: a smelter is in the pack at tick %d" % _crafted_at)
				_leave_for_fuel(at)
		Step.TO_FUEL:
			if at == _fuel_stand:
				_once("mine fuel", AssayActions.mine())
				_step = Step.FUEL_MINING
		Step.FUEL_MINING:
			if _held("ore", _fuel) >= AssayDemoPlan.FUEL_ORE:
				print("  session: %d fuel ore held at tick %d" % [_held("ore", _fuel), _sim.tick()])
				_step = Step.PLACING
		Step.PLACING:
			_placing(at)
		Step.LOADING:
			_loading()
		Step.SMELTING:
			_smelting()
		Step.MAKING:
			_making()
		Step.PICK:
			_pick()
		Step.DRILL:
			_drill(at)
		Step.PLANTING:
			_planting()
		Step.CRUISING:
			pass


## SEND A COMMAND ONCE, however many bundles we then wait through. Returns true the first time.
func _once(key: String, command: Variant) -> bool:
	if _sent.has(key):
		return false
	_sent[key] = true
	if not _client.submit(command):
		_finish(false, "the %s command was not submitted" % key)
	return true


func _held(kind: String, species: int) -> int:
	return AssayDemoPlan.held(_sim.inventory_of(_client.player_id), kind, species)


func _stack(kind: String, species: int) -> Dictionary:
	return AssayDemoPlan.best_stack(_sim.inventory_of(_client.player_id), kind, species)


## PICK THE MATERIAL, THE FUEL AND THE DEPOSIT, AND START WALKING. Done once, two bundles in, for the
## same reason `walk` waits: until the sim has stepped us at least once, the only position we have is
## one we were told about rather than one we hold.
func _begin_session(at: Vector2i) -> void:
	if _sim.applied < 2:
		return
	# THE SIM CHOOSES THE PAIR. "Does this fuel melt that ore" is a rule, and before an assay a
	# client holds a 25-wide band to guess with -- see `starter_pair` in the binding.
	var pair := _sim.starter_pair()
	if pair.size() != 2:
		_finish(false, "this world has no starter pair, so there is no loop to play")
		return
	_material = pair[0]
	_fuel = pair[1]
	_ore_wanted = AssayDemoPlan.material_ore_needed()
	if _fuel == _material:
		# ONE SPECIES CAN BE BOTH, and a scripted session that assumed otherwise would fail on a
		# perfectly good world. Then there is no second deposit to walk to: mine the fuel here.
		_ore_wanted += AssayDemoPlan.FUEL_ORE

	var deposit := AssaySessionPlan.nearest_of_species(_sim.deposits(), _material, at,
			_client.player_id)
	if deposit.is_empty():
		_finish(false, ("no deposit of the starter material (species %d) still holds ore, so there "
				+ "is no loop to play. Host a fresh world.") % _material)
		return
	_target_center = deposit.get("center", Vector2i.ZERO) as Vector2i
	if int(deposit.get("amount", 0)) < _ore_wanted:
		_finish(false, ("the %s deposit at %s holds %d ore and this loop needs %d. Host a world "
				+ "with more in its starter chunks.") % [_species_name(_material), _target_center,
				int(deposit.get("amount", 0)), _ore_wanted])
		return
	_stand_at = AssayDemoPlan.stand_tile(_target_center, _client.player_id,
			_deposit_cover(_target_center))

	if _fuel != _material:
		var fuel_deposit := AssaySessionPlan.nearest_of_species(_sim.deposits(), _fuel,
				_target_center, _client.player_id)
		if fuel_deposit.is_empty():
			_finish(false, "no deposit of the starter fuel (species %d) holds ore" % _fuel)
			return
		_fuel_center = fuel_deposit.get("center", Vector2i.ZERO) as Vector2i

	var needed := AssayDemoPlan.ticks_needed(AssaySessionPlan.walk_ticks(at, _stand_at),
			AssaySessionPlan.walk_ticks(_stand_at, _fuel_center) if _fuel != _material else 0,
			1, HAND_MINE_TICKS, ASSAY_TICKS)
	if _want_ticks < needed:
		_finish(false, ("%d ticks cannot cover the whole loop: it needs about %d (%d ore to mine at "
				+ "%d ticks a cycle, %d to smelt, plus the walking). Ask for at least %d.")
				% [_want_ticks, needed, _ore_wanted, HAND_MINE_TICKS,
				AssayDemoPlan.refined_needed() * AssayDemoPlan.SMELT_TICKS_PER_ORE, needed])
		return
	if not _client.submit(AssayActions.move_to(_stand_at)):
		_finish(false, "the MoveTo command was not submitted")
		return
	print(("  session: material %s, fuel %s (the sim's pair). Walking from %s to %s on the deposit "
			+ "at %s; want %d ore, %d of it for the fire.") % [_species_name(_material),
			_species_name(_fuel), at, _stand_at, _target_center, _ore_wanted,
			AssayDemoPlan.refined_needed()])


## WHICH OF THE CANDIDATE TILES THE SIM SAYS THE DEPOSIT COVERS. Asked rather than worked out: a
## deposit's radius is a circle and `tile_at` is the only thing entitled to an opinion about it.
func _deposit_cover(center: Vector2i) -> Dictionary:
	var cover := {}
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var tile := center + Vector2i(dx, dy)
			cover[tile] = _sim.tile_at(tile).get("deposit") != null
	return cover


func _begin_mining() -> void:
	_ore_before = _held("ore", _material)
	_once("mine", AssayActions.mine())
	_step = Step.MINING
	print("  session: standing on %s at %s, mining from tick %d"
			% [_species_name(_material), _stand_at, _sim.tick()])


## MINE AND ASSAY TOGETHER. `mining` and `assaying` are separate fields on a player and both systems
## run every tick, so the ore keeps arriving while the sheet sharpens. More inputs per tick is the
## point of this mode.
##
## THE ASSAY IS SKIPPED IF ANOTHER PEER GOT THERE FIRST. Assaying is per world, so the second peer to
## submit it would be refused with `AlreadyAssayed` -- and reading the world before acting is what a
## player does, where retrying around a refusal is what a script does. Either way the species is
## exact before any part is made of it, which is what makes the design's verdict a number and not a
## band.
func _mining(_at: Vector2i) -> void:
	var exact := AssaySessionPlan.is_assayed(_sim.species_sheets(), _material)
	if not exact and not _assay_sent:
		_assay_sent = true
		_once("assay", AssayActions.assay())
		print("  session: assaying %s from tick %d (%d ticks of standing still)"
				% [_species_name(_material), _sim.tick(), ASSAY_TICKS])
	elif exact and not _assay_sent:
		_assay_skipped = true
		_assay_sent = true
		print("  session: %s was already exact at tick %d -- another peer assayed it"
				% [_species_name(_material), _sim.tick()])
	if exact and _assayed_at < 0:
		_assayed_at = _sim.tick()
	var held := _held("ore", _material)
	if held > _ore_before and _mined_at < 0:
		_mined_at = _sim.tick()
		print("  session: first %s ore arrived at tick %d" % [_species_name(_material), _mined_at])
	if held < _ore_wanted or not exact:
		return
	print("  session: %d %s ore held and the sheet is exact at tick %d"
			% [held, _species_name(_material), _sim.tick()])
	# THE ITEM IS THE ONE THE SIM NAMED. Its kind, species and grade come straight back out of
	# `inventory_of`; nothing here works out what we are carrying.
	var ore := _stack("ore", _material)
	if ore.is_empty():
		_finish(false, "the sim says we hold %d ore and the inventory has no stack of it" % held)
		return
	_once("craft smelter", AssayActions.craft(AssaySimHost.recipe_tag("smelter"),
			AssayActions.item_of_stack(ore), 1))
	_step = Step.CRAFTING


func _leave_for_fuel(at: Vector2i) -> void:
	if _fuel == _material:
		# We mined the fuel at the same deposit; place the smelter where we stand.
		_step = Step.PLACING
		return
	_fuel_stand = AssayDemoPlan.stand_tile(_fuel_center, _client.player_id,
			_deposit_cover(_fuel_center))
	if not _client.submit(AssayActions.move_to(_fuel_stand)):
		_finish(false, "the MoveTo to the fuel deposit was not submitted")
		return
	_step = Step.TO_FUEL
	print("  session: walking from %s to the %s fuel at %s (%d tiles)"
			% [at, _species_name(_fuel), _fuel_stand, AssaySessionPlan.walk_ticks(at, _fuel_stand)])


## PUT THE SMELTER DOWN BESIDE US, on a 2x2 the sim says is free. Three peers craft at once, so the
## spot is chosen against the buildings the world actually holds rather than a guess -- otherwise the
## second peer is refused `TileOccupied` and the run dies on a collision, not a bug.
func _placing(at: Vector2i) -> void:
	if _building >= 0:
		return
	if _smelter_at.x < 0:
		_smelter_at = AssayDemoPlan.smelter_spot(at, _sim.size_tiles(), _buildings_near(at))
		if _smelter_at.x < 0:
			_finish(false, "no free 2x2 within reach of %s to put a smelter on" % at)
			return
		var smelter := _stack("smelter", _material)
		if smelter.is_empty():
			_finish(false, "the craft finished and no smelter is in the pack")
			return
		_once("place smelter", AssayActions.place(AssayActions.item_of_stack(smelter),
				_smelter_at))
		return
	# Waiting for the building to exist in the stepped world.
	var building: Variant = _sim.tile_at(_smelter_at).get("building")
	if building == null:
		return
	_building = int((building as Dictionary).get("id", -1))
	_placed_at = _sim.tick()
	print("  session: smelter %d is on the map at %s, tick %d"
			% [_building, _smelter_at, _placed_at])
	_step = Step.LOADING


## The tiles near us the SIM says already hold a building. Only the tiles a smelter could go on, so
## this is a handful of `tile_at` calls and not a scan of the world.
func _buildings_near(at: Vector2i) -> Array:
	var taken := []
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var tile := at + Vector2i(dx, dy)
			if _sim.tile_at(tile).get("building") != null:
				taken.append(tile)
	return taken


## FUEL FIRST, THEN ORE, both in one tick. The smelter holds one input stack at a time and burns fuel
## to reach the ore's heat tolerance; loading the ore first would just stall the fire until the fuel
## arrived, which is a slower way to the same place.
func _loading() -> void:
	if not _sent.has("insert fuel"):
		var fuel := _stack("ore", _fuel)
		var ore := _stack("ore", _material)
		if fuel.is_empty() or ore.is_empty():
			_finish(false, "the smelter is placed and we hold fuel=%s ore=%s" % [fuel, ore])
			return
		_once("insert fuel", AssayActions.insert(_building, AssayActions.SLOT_FUEL,
				AssayActions.item_of_stack(fuel), AssayDemoPlan.FUEL_ORE))
		_sent["insert ore"] = true
		if not _client.submit(AssayActions.insert(_building, AssayActions.SLOT_INPUT,
				AssayActions.item_of_stack(ore), AssayDemoPlan.refined_needed())):
			_finish(false, "the Insert of ore was not submitted")
		return
	# THE SMELTER'S OWN SENTENCE SAYS WHEN THE ORE LANDED: `sim::debug::building_status` calls an
	# empty input slot "idle: nothing to refine", so the moment it stops saying that, there is ore in
	# the fire. `_smelting` then waits for the same sentence to come BACK, which is the fire going out
	# because everything we put in has been refined. One source for both edges.
	var status := _smelter_status()
	if status == "" or status.contains("idle: nothing to refine"):
		return
	_loaded_at = _sim.tick()
	print("  session: smelter %d loaded at tick %d -- %s" % [_building, _loaded_at, status])
	_step = Step.SMELTING


func _smelter_status() -> String:
	var building: Variant = _sim.tile_at(_smelter_at).get("building")
	if building == null:
		return ""
	return String((building as Dictionary).get("status", ""))


## WAIT FOR THE FIRE TO FINISH, THEN TAKE. "idle: nothing to refine" is the SIM'S OWN sentence for an
## empty input slot (`sim::debug::building_status`), so this is reading its words rather than counting
## ticks of our own -- and if that wording ever changes, this stage times out with the status printed
## beside the failure instead of taking an empty slot and being refused.
func _smelting() -> void:
	var status := _smelter_status()
	if not status.contains("idle: nothing to refine"):
		return
	if _once("take", AssayActions.take(_building)):
		print("  session: the fire is out at tick %d -- %s" % [_sim.tick(), status])
		return
	_refined_held = _held("refined", _material)
	if _refined_held < AssayDemoPlan.refined_needed():
		return
	_taken_at = _sim.tick()
	print("  session: took %d refined %s at tick %d"
			% [_refined_held, _species_name(_material), _taken_at])
	_step = Step.MAKING


## A HANDLE, TWO HEADS AND A FRAME, all in one tick. `MakePart` takes effect the moment it is applied,
## so three commands on one tick is three parts on one tick -- and three commands from one player on
## one tick is itself worth putting through a relay.
func _making() -> void:
	if not _sent.has("make parts"):
		var refined := _stack("refined", _material)
		if refined.is_empty():
			_finish(false, "took the refined material and the inventory has no stack of it")
			return
		var material := AssayActions.item_of_stack(refined)
		_sent["make parts"] = true
		for order in [["handle", 1], ["head", 2], ["frame", 1]]:
			if not _client.submit(AssayActions.make_part(AssaySimHost.part_tag(String(order[0])),
					material, int(order[1]))):
				_finish(false, "the MakePart of a %s was not submitted" % order[0])
				return
		return
	if _held("handle", _material) < 1 or _held("head", _material) < 2 \
			or _held("frame", _material) < 1:
		return
	_parts_at = _sim.tick()
	print("  session: a handle, two heads and a frame at tick %d" % _parts_at)
	_step = Step.PICK


## A PICK: a handle with a head on it, then put it in our hands. `Assemble` takes the part items out
## of the pack and appends to the built list, so the pick is the last index; `Equip` moves it to the
## hand and leaves the list empty again, which is why the drill is index 0 too.
func _pick() -> void:
	if not _sent.has("assemble pick"):
		_once("assemble pick", AssayActions.assemble(
				AssayActions.item_of_stack(_stack("handle", _material)),
				[AssayActions.item_of_stack(_stack("head", _material))]))
		return
	var designs := _sim.designs_of(_client.player_id)
	if _pick_at < 0:
		if designs.is_empty():
			return
		_pick_at = _sim.tick()
		print("  session: a pick is built at tick %d -- %s" % [_pick_at,
				String((designs[0] as Dictionary).get("verdict", "?"))])
		_once("equip", AssayActions.equip(0))
		return
	for entry in designs:
		if bool((entry as Dictionary).get("in_hand", false)):
			_equipped_at = _sim.tick()
			print("  session: the pick is in hand at tick %d" % _equipped_at)
			_step = Step.DRILL
			return


## DID THE WORLD END UP FIT TO BE LOOKED AT? `demo` mode's product is not a verdict about lockstep --
## `session` proves that -- it is A WORLD SOMEONE CAN JOIN AN HOUR LATER AND STILL SEE SOMETHING IN.
##
## THE BUG THIS MODE EXISTS FOR, and I shipped it before I caught it: I set a demo world up with
## `session`, left the relay standing, and rejoined 5,600 ticks later to an EMPTY bench. The relay owns
## the clock and never stops, `Mine` repeats until something stops it, so the player kept swinging for
## ten minutes; `PICK_WEAR_PER_SWING` (`sim/src/step.rs:810`) wore the pick to nothing and the only
## design they owned was gone. The inventory had 856 ore in it. A demo world that decays is worse than
## no demo world, because it looks ready at the moment you build it.
##
## So this mode leaves the world INERT on purpose:
##  - `Stop`, so nothing is mining. Wear only happens on a swing, so a stopped player's tool keeps its
##    durability for as long as the relay runs.
##  - THE DRILL IS NEVER PLANTED. An unplaced design sits in `assemblies` and nothing in the sim
##    consumes it, so it is still on the bench whenever they arrive. Planting would spend it.
## What is left is two rows that do not rot: a tool IN HAND with durability, and an unplaced PLANTED
## design -- both mounts, and two different verdicts, which is what Decision #38 asks to be judged.
func _check_demo() -> bool:
	if not _sent.has("stop"):
		_finish(false, "demo mode never sent Stop, so the player is still mining and the tool wears")
		return false
	var me := _my_player()
	if me.get("target") != null:
		_finish(false, "demo mode: the player is still walking to %s" % [me.get("target")])
		return false
	var in_hand := 0
	var spare := 0
	for entry in _sim.designs_of(_client.player_id):
		if bool((entry as Dictionary).get("in_hand", false)):
			in_hand += 1
		else:
			spare += 1
	if in_hand < 1 or spare < 1:
		_finish(false, ("demo mode wants a bench that survives the clock: %d design(s) in hand and "
				+ "%d unplaced, wanted at least one of each. Designs: %s")
				% [in_hand, spare, _sim.designs_of(_client.player_id)])
		return false
	print("  demo: the bench is %d in hand and %d unplaced, the player is stopped at %s."
			% [in_hand, spare, me.get("pos", Vector2i.ZERO)])
	for entry in _sim.designs_of(_client.player_id):
		var design: Dictionary = entry
		print("    [%s]%s" % [String(design.get("verdict", "?")),
				" in hand" if bool(design.get("in_hand", false)) else " on the bench"])
		for line in AssayHud.design_lines(design):
			print("      %s" % line)
	return true


## A DRILL: a planted frame with a head on it. Its verdict is read BEFORE it is planted, because that
## verdict is a promise the placement has to keep.
func _drill(at: Vector2i) -> void:
	if not _sent.has("assemble drill"):
		_once("assemble drill", AssayActions.assemble(
				AssayActions.item_of_stack(_stack("frame", _material)),
				[AssayActions.item_of_stack(_stack("head", _material))]))
		return
	for entry in _sim.designs_of(_client.player_id):
		var design: Dictionary = entry
		if bool(design.get("in_hand", false)) or String(design.get("mount", "")) != "planted":
			continue
		_drill_at = _sim.tick()
		_drill_verdict = String(design.get("verdict", "?"))
		_drill_spot = AssayDemoPlan.smelter_spot(at, _sim.size_tiles(), _buildings_near(at))
		if _drill_spot.x < 0 and not _demo:
			_finish(false, "no free 2x2 within reach of %s to plant a drill on" % at)
			return
		print(("  session: a drill is built at tick %d, index %d, the sim calls it %s (mass %d-%d "
				+ "of %d-%d budget).%s") % [_drill_at,
				int(design.get("index", -1)), _drill_verdict, int(design.get("mass_low", 0)),
				int(design.get("mass_high", 0)), int(design.get("budget_low", 0)),
				int(design.get("budget_high", 0)),
				" LEAVING IT ON THE BENCH (demo)." if _demo else " Planting it at %s." % _drill_spot])
		# `demo` leaves the design unplaced and stops the player: see `_check_demo`. Planting is what
		# `session` is for, and it SPENDS the design -- which is the whole reason a demo world built
		# with `session` is empty by the time anyone opens it.
		if _demo:
			# A BARE STRING, like `Mine`. `Stop` is a unit variant, and externally-tagged JSON spells
			# those as the name alone -- `{"Stop": {}}` is refused, which would have left the player
			# mining and the bench rotting exactly as before, with the probe reporting success.
			_once("stop", AssayActions.stop())
			_step = Step.CRUISING
			return
		_once("plant", AssayActions.place_assembly(int(design.get("index", 0)), _drill_spot))
		_step = Step.PLANTING
		return


## DID IT SURVIVE? Either a machine is on the map at that spot, or the design is gone from the built
## list and the sim told us it came apart. Both are read out of the stepped world; neither is guessed
## from the numbers.
func _planting() -> void:
	if _sim.tile_at(_drill_spot).get("building") != null:
		_planted_at = _sim.tick()
		print("  session: the drill is planted at %s, tick %d" % [_drill_spot, _planted_at])
		_step = Step.CRUISING
		return
	var planted := false
	for entry in _sim.designs_of(_client.player_id):
		if String((entry as Dictionary).get("mount", "")) == "planted":
			planted = true
	if planted:
		return
	# The design left the built list and nothing stands where it went: it broke, and `break_apart`
	# rolled which parts came back FROM THE WORLD'S RNG. That roll is the most desync-prone draw in
	# the game, which is why this session ends here.
	for line in _sim.event_lines(_client.player_id):
		if String(line).contains("MachineBroke") or String(line).to_lower().contains("broke"):
			_break_line = String(line)
	_broke_at = _sim.tick()
	print("  session: the drill came apart at tick %d. %s"
			% [_broke_at, _break_line if _break_line != "" else "(no worded event for it yet)"])
	_step = Step.CRUISING


func _species_name(species: int) -> String:
	var named := AssaySessionPlan.species_name(_sim.species_sheets(), species)
	return named if named != "" else "species %d" % species


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


## DID THE WHOLE LOOP ACTUALLY HAPPEN? Every answer is read back out of the stepped world at the end
## of the run, not remembered from when the command was sent. A probe that passed on "I submitted
## Mine" would pass against a relay that threw our inputs away.
##
## The stage that got furthest is named in every failure, because "the loop did not finish" is not a
## report -- which stage it died in, and what the sim's state was there, is.
## A session failure, worded and recorded, returning false so `_check_session` can `return
## _fail_session(...)` in one line where it is checking several things in a row.
func _fail_session(why: String) -> bool:
	_finish(false, why)
	return false


func _check_session() -> bool:
	if _material < 0:
		_finish(false, "session mode asked for but no material was ever chosen")
		return false
	if _mined_at < 0:
		_finish(false, ("never mined: the sim has us at %s, the %s deposit is at %s (stand tile %s)"
				% [(_my_player().get("pos", Vector2i.ZERO) as Vector2i),
				_species_name(_material), _target_center, _stand_at]))
		return false
	if not AssaySessionPlan.is_assayed(_sim.species_sheets(), _material):
		_finish(false, "the sim still reads %s as rough, so the assay never finished"
				% _species_name(_material))
		return false
	if _crafted_at < 0:
		_finish(false, ("never crafted a smelter: %d %s ore held, wanted %d"
				% [_held("ore", _material), _species_name(_material), _ore_wanted]))
		return false
	if _placed_at < 0:
		_finish(false, "never placed the smelter (spot %s, step %d)" % [_smelter_at, _step])
		return false
	if _taken_at < 0:
		_finish(false, ("never took refined material out of smelter %d. Its status: %s"
				% [_building, _smelter_status()]))
		return false
	if _parts_at < 0:
		_finish(false, ("never made the parts: %d handles, %d heads, %d frames, %d refined held"
				% [_held("handle", _material), _held("head", _material),
				_held("frame", _material), _held("refined", _material)]))
		return false
	if _equipped_at < 0:
		_finish(false, "never got a pick into our hands (designs: %s)"
				% [_sim.designs_of(_client.player_id)])
		return false
	if _demo:
		return _check_demo()
	if _planted_at < 0 and _broke_at < 0:
		_finish(false, ("never planted the drill: verdict %s, spot %s, designs %s"
				% [_drill_verdict, _drill_spot, _sim.designs_of(_client.player_id)]))
		return false

	# THE VERDICT WAS A PROMISE. SAFE means the mass band sits wholly under the budget band, so it
	# cannot be overweight; WILL BREAK means it sits wholly over. UNCERTAIN promises nothing, and the
	# probe says which happened rather than pretending it was told.
	if _drill_verdict.to_upper().contains("SAFE") and _planted_at < 0:
		_finish(false, ("the sim called the drill %s and it came apart anyway: a SAFE design has its "
				+ "whole mass band under its budget band, so this is the sim disagreeing with itself")
				% _drill_verdict)
		return false
	if _drill_verdict.to_upper().contains("BREAK") and _broke_at < 0:
		_finish(false, ("the sim called the drill %s and it planted fine: a WILL BREAK design has "
				+ "its whole mass band over its budget band") % _drill_verdict)
		return false

	# A tool in hand, read out of the sim, with the sim's own verdict on it.
	var tool := {}
	for entry in _sim.designs_of(_client.player_id):
		if bool((entry as Dictionary).get("in_hand", false)):
			tool = entry
	if tool.is_empty():
		_finish(false, "the loop finished and the sim says nothing is in our hands")
		return false
	# The HUD is what a person would have been looking at while this ran, and it is pure functions of
	# these same dictionaries -- so the words on the panel are checkable here, against the world that
	# produced them, without a screen.
	var verdict := String(tool.get("verdict", ""))
	var panel := "\n".join(AssayHud.design_lines(tool))
	# THE VERDICT IS NOT IN THESE LINES, AND I HAD THIS WRONG FIRST: `main.gd` draws it as a word in
	# its own colour ABOVE the lines, because a verdict that reads as body text is a verdict nobody
	# reads. So what the lines must carry is the numbers under it, and what the HUD must have for the
	# verdict is a colour it actually recognises -- an unknown verdict falls to a neutral grey, and a
	# grey "WILL BREAK" is the failure worth catching.
	for number in ["mass %d" % int(tool.get("mass_low", -1)),
			"%d budget" % int(tool.get("budget_low", -1))]:
		if not panel.contains(number):
			return _fail_session("the part menu does not show '%s' for the tool in hand: %s"
					% [number, panel])
	if AssayHud.verdict_color(verdict) == AssayHud.verdict_color("something else entirely"):
		_finish(false, ("the HUD has no colour of its own for the verdict '%s', so it would draw it "
				+ "in the neutral grey it uses for a word it does not know") % verdict)
		return false
	print(("  session: mined at %d, exact at %d%s, smelter crafted %d and placed %d, loaded %d, "
			+ "refined taken %d (%d units), parts %d, pick built %d and equipped %d, drill built %d "
			+ "(%s) and %s at %d.") % [_mined_at, _assayed_at,
			" (another peer's assay)" if _assay_skipped else "", _crafted_at, _placed_at,
			_loaded_at, _taken_at, _refined_held, _parts_at, _pick_at, _equipped_at, _drill_at,
			_drill_verdict, "planted" if _planted_at >= 0 else "came apart",
			_planted_at if _planted_at >= 0 else _broke_at])
	print("  session: the part menu for the tool in hand reads --")
	for line in AssayHud.design_lines(tool):
		print("    %s" % line)
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
