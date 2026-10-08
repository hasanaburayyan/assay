extends SceneTree
## CI: local -- needs a real relay; a gate could run it as hud_in_a_gate.sh does and none does yet
## DID A GODOT CLIENT REALLY JOIN A REAL RELAY? Headless, no window, one line of verdict.
##
##   godot --headless --path . --script res://tools/join_probe.gd -- localhost:7777 limpet [seconds]
##
## Joins, waits for the `Welcome`, then listens for tick bundles for a moment so the verdict covers
## the live link and not just the handshake. Prints `JOIN PROBE OK` LAST, and only on success: a
## positive marker printed last is the only thing a CI grep can trust, because Godot exits 0 even
## when a script fails to compile.
##
## It reports what it READ off the world rather than what it hoped for -- tick, player slot, how
## many species and players the snapshot carries -- because "connected" is not evidence that the
## snapshot is a world.

const DEFAULT_SECONDS := 3.0

var _client: AssayNetClient
var _done := false
var _ok := false
var _why := ""
var _deadline := 0.0
var _listen_until := 0.0
var _welcome_tick := -1


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
	if argv.size() < 2:
		print("FAIL  usage: -- host[:port] name [seconds]")
		quit(1)
		return
	var seconds: float = float(argv[2]) if argv.size() > 2 else DEFAULT_SECONDS

	_client = AssayNetClient.new()
	_client.welcomed.connect(_on_welcomed)
	_client.refused.connect(func(reason): _finish(false, "refused: %s" % reason))
	_client.link_failed.connect(func(reason): _finish(false, reason))
	_client.desynced.connect(func(tick): print("  desync reported at tick %d" % tick))
	_client.note.connect(func(line): print("  %s" % line))
	root.add_child(_client)

	_deadline = Time.get_unix_time_from_system() + 10.0
	_listen_until = Time.get_unix_time_from_system() + seconds
	_client.join(String(argv[0]), String(argv[1]))


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		print("FAIL  join_probe.gd ran past its %ds ceiling: nothing finished it" % int(RUN_CEILING))
		quit(1)
		return true
	var now := Time.get_unix_time_from_system()
	if _client.stage == AssayNetClient.Stage.JOINED:
		if now >= _listen_until:
			_report()
			return true
		return false
	if now >= _deadline:
		_finish(false, "no welcome within 10s (stage %d)" % _client.stage)
		return true
	return false


## `_raw` is the message's own text, which is what the sim is fed; this probe only reads the
## snapshot, so it does not need it. `tools/lockstep_probe.gd` is the one that steps.
func _on_welcomed(player: int, world: Dictionary, _raw: String) -> void:
	_welcome_tick = int(world.get("tick", -1))
	print("  welcomed as player %d into a world at tick %d" % [player, _welcome_tick])


func _report() -> void:
	var world: Dictionary = _client.joined_world
	var species: Array = world.get("species", [])
	var players: Array = world.get("players", [])
	var deposits: Array = world.get("deposits", [])
	# `World` has no chunk list: the map is width_chunks x height_chunks of 16x16 tiles, generated
	# from the seed. Reported as the size it claims so a wrong-shaped snapshot is visible here.
	var wide := int(world.get("width_chunks", 0))
	var high := int(world.get("height_chunks", 0))
	if species.is_empty() or players.is_empty():
		_finish(false, ("the snapshot has %d species and %d players: a welcome arrived but it did "
				+ "not carry a world") % [species.size(), players.size()])
		return
	if _client.bundles_seen <= 0:
		_finish(false, ("joined at tick %d but no tick bundle arrived: the relay's clock is not "
				+ "reaching this client") % _welcome_tick)
		return
	if wide <= 0 or high <= 0:
		_finish(false, "the snapshot claims a %dx%d chunk world" % [wide, high])
		return
	# `int()` on the seed because Godot's JSON hands back a FLOAT for every number -- it printed
	# "777001.0" before this line said otherwise. See AssayProtocol's note: past 2^53 a double cannot
	# hold a u64 exactly, which is a trap for seeds and a wall for hashes.
	print(("  world: seed %d, %dx%d chunks, %d species, %d players, %d deposits; %d bundles, last "
			+ "tick %d (joined at %d)") % [int(world.get("seed", 0)), wide, high, species.size(),
			players.size(), deposits.size(), _client.bundles_seen, _client.last_tick, _welcome_tick])
	_finish(true, "")


func _finish(ok: bool, why: String) -> void:
	if _done:
		return
	_done = true
	_ok = ok
	_why = why
	if ok:
		print("JOIN PROBE OK: joined as player %d, protocol %d, %d bundles to tick %d" % [
				_client.player_id, AssayProtocol.protocol_version(), _client.bundles_seen,
				_client.last_tick])
	else:
		print("FAIL  %s" % why)
	quit(0 if ok else 1)
