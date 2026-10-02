extends SceneTree
## DOES THE HUD READ A REAL WORLD? Headless, against a real relay, one line of verdict.
##
##   godot --headless --path . --script res://tools/hud_probe.gd -- localhost:7777 limpet [ticks]
##
## `lockstep_probe.gd` proves this client is a peer: bundles applied, hashes accepted, no desync. This
## proves the other half -- that what the HUD would PUT ON SCREEN comes out of that world and is true
## of it. The panel's text is built here by the same `AssayHud` functions `main.gd` uses, from the same
## `AssaySimHost` reads, and then checked against the world it came from.
##
## Prints `HUD PROBE OK` LAST and only on success, because Godot exits 0 even on a compile error.
##
## WHAT WOULD MAKE IT FAIL:
##  - a reading of an unassayed species is a single number: the client narrowed a 25-wide band itself
##  - a deposit tile's readout does not name its species in words (colour-blind players read the words)
##  - the tile under our own feet reads as off the map
##  - no event line ever mentions "you" after we walk, so the log is not about this player
const DEFAULT_TICKS := 25
const JOIN_TIMEOUT := 10.0
const SECONDS_PER_TICK := 0.5

var _client: AssayNetClient
var _sim := AssaySimHost.new()
var _done := false
var _want_ticks := DEFAULT_TICKS
var _join_deadline := 0.0
var _run_deadline := 0.0
var _walk_sent := false
## Every event line the run produced, as the HUD would have shown them.
var _events := PackedStringArray()


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.size() < 2:
		print("FAIL  usage: -- host[:port] name [ticks]")
		quit(1)
		return
	_want_ticks = int(argv[2]) if argv.size() > 2 else DEFAULT_TICKS

	_client = AssayNetClient.new()
	_client.welcomed.connect(_on_welcomed)
	_client.tick_bundle.connect(_on_tick_bundle)
	_client.refused.connect(func(reason): _finish(false, "refused: %s" % reason))
	_client.link_failed.connect(func(reason): _finish(false, reason))
	_client.desynced.connect(func(tick): _finish(false, "desynced at tick %d" % tick))
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
	if _sim.applied >= _want_ticks:
		_report()
		return true
	if now >= _run_deadline:
		_finish(false, "only %d of %d bundles applied before the deadline"
				% [_sim.applied, _want_ticks])
		return true
	return false


func _on_welcomed(_player: int, _world: Dictionary, raw: String) -> void:
	if not _sim.start(raw):
		_finish(false, _sim.fail_reason)


func _on_tick_bundle(_tick: int, _inputs: Array, raw: String) -> void:
	var before := _sim.applied
	var report := _sim.apply(raw)
	if _sim.applied == before:
		_finish(false, "a bundle for tick %d was refused at sim tick %d" % [_tick, _sim.tick()])
		return
	if report != "":
		_client.send_text(report)
	for line in _sim.event_lines(_client.player_id):
		_events.append("%d · %s" % [_sim.tick(), line])
	# Walk, so the log has something of ours in it. The sim decides whether it is legal and the
	# movement system does the walking; nothing here predicts a position.
	# AND IT WALKS WHICHEVER WAY HAS ROOM, because this probe is run REPEATEDLY against one standing
	# world. The old version always went 3 tiles east and clamped to the edge, so each run shoved the
	# player further east until a run found itself already at x = size - 1; the MoveTo then asked for
	# the tile it was standing on, nothing moved, no event mentioned us, and the probe reported FAIL on
	# a world that was perfectly healthy. I hit it on the third run against the board's demo world --
	# the bench check passed and the walk check failed, which is the worst shape for a false alarm,
	# because the next person to see it is whoever is verifying my claim about the bench.
	if not _walk_sent and _sim.applied >= 2:
		var me := _my_tile()
		var size := _sim.size_tiles()
		var step := 3 if me.x + 3 <= size.x - 1 else -3
		var to := Vector2i(clampi(me.x + step, 0, size.x - 1), me.y)
		if to == me:
			_finish(false, ("nowhere to walk from %s in a %d-wide world, so the log check cannot mean "
					+ "anything") % [me, size.x])
			return
		_walk_sent = _client.submit({"MoveTo": {"target": {"x": to.x, "y": to.y}}})


func _my_tile() -> Vector2i:
	for entry in _sim.players():
		var player: Dictionary = entry
		if int(player.get("id", -1)) == _client.player_id:
			return player.get("pos", Vector2i.ZERO) as Vector2i
	return _sim.spawn_tile()


func _report() -> void:
	# 1. YOUR OWN TILE, which must at least be on the map we are standing on.
	var mine := _sim.tile_at(_my_tile())
	if not bool(mine.get("in_bounds", false)):
		_finish(false, "the tile under our own player reads as off the map: %s" % [mine])
		return
	print("  where you stand:")
	for line in AssayHud.tile_lines(mine):
		print("    %s" % line)

	# 2. A DEPOSIT TILE, found in the world rather than invented, and its readout must name the
	# species in words -- hue alone cannot carry species for a colour-blind player.
	var deposit := _a_deposit()
	if deposit.is_empty():
		_finish(false, "no deposit with ore left in a world of %d" % _sim.deposits().size())
		return
	var at := deposit.get("center", Vector2i.ZERO) as Vector2i
	var tile := _sim.tile_at(at)
	var found: Variant = tile.get("deposit")
	if found == null:
		_finish(false, "deposit %s is centred on (%d, %d) and that tile reports no deposit"
				% [deposit.get("id"), at.x, at.y])
		return
	var text := "\n".join(AssayHud.tile_lines(tile))
	var species_name := String((found as Dictionary).get("species_name", ""))
	if species_name == "" or not text.contains(species_name):
		_finish(false, "the readout does not name the species (%s): %s" % [species_name, text])
		return
	if not text.contains("grade %s" % String((found as Dictionary).get("grade", "?"))):
		_finish(false, "the readout does not carry the sim's grade: %s" % text)
		return
	print("  under the cursor, at a real deposit:")
	for line in AssayHud.tile_lines(tile):
		print("    %s" % line)

	# 2b. THE BENCH, AS THE PANEL WOULD SHOW IT. Built by the same `AssayHud` calls `main.gd`'s
	# `_refresh_bench` uses, on the designs the sim says THIS player owns, so what prints here is the
	# text that would be on screen -- which is the thing Decision #38 asks the board to judge.
	#
	# It is a READOUT, not a check, with one exception below: how many designs a player has is a fact
	# about the world, not a rule, so "no designs" is the honest answer on a fresh world and must not
	# be a failure. `BENCH_MUST_HAVE_ROWS=1` turns it into one, which is how the demo setup proves the
	# board will not open an empty panel -- the claim "the bench is already full" then has to survive
	# a join under their own account instead of being something I watched happen once.
	var designs := _sim.designs_of(_client.player_id)
	print("  the bench, as the panel builds it (%d design(s) for player %d):"
			% [designs.size(), _client.player_id])
	if designs.is_empty():
		print("    %s" % AssayHud.no_designs_line())
	for entry in designs:
		var design: Dictionary = entry
		print("    [%s]" % String(design.get("verdict", "?")))
		for line in AssayHud.design_lines(design):
			print("      %s" % line)
	if OS.get_environment("BENCH_MUST_HAVE_ROWS") != "" and designs.is_empty():
		_finish(false, ("the bench is empty for player %d, and this run required rows. The board "
				+ "would open the panel on '%s'. Either the session probe did not play under this "
				+ "account, or it is still holding it open and we landed on a fresh player.")
				% [_client.player_id, AssayHud.no_designs_line()])
		return

	# 3. EVERY UNASSAYED READING IS A BAND. The sim decides; this fails if a single number ever
	# arrives for a species nobody has assayed.
	for entry in _sim.species_sheets():
		var species: Dictionary = entry
		if bool(species.get("assayed", false)):
			continue
		var readings: Dictionary = species.get("readings", {})
		if readings.is_empty():
			_finish(false, "species %s reported no readings at all" % species.get("name"))
			return
		for property in readings:
			var reading := String(readings[property])
			if not reading.contains("-"):
				_finish(false, ("%s's %s reads as %s while unassayed. A rough sheet is a 25-wide "
						+ "band; one number is certainty the player has not paid for.")
						% [species.get("name"), property, reading])
				return
	print("  species, as the players know them:")
	for entry in _sim.species_sheets():
		var species: Dictionary = entry
		print("    %s%s: %s" % [species.get("name"), "" if bool(species.get("assayed", false))
				else " (rough)", species.get("readings")])

	# 4. WHAT YOU ARE CARRYING, and 5. the log, which must have something of ours in it.
	print("  carrying: %s" % ", ".join(AssayHud.inventory_lines(
			_sim.inventory_of(_client.player_id))))
	var ours := 0
	for line in _events:
		if line.contains("you"):
			ours += 1
	if ours == 0:
		_finish(false, ("%d event lines and not one about us, after submitting a MoveTo. The log is "
				+ "not this player's.") % _events.size())
		return
	print("  last of %d event lines:" % _events.size())
	for line in AssayHud.trimmed_log(_events, 6):
		print("    %s" % line)
	_finish(true, "")


func _a_deposit() -> Dictionary:
	for entry in _sim.deposits():
		var deposit: Dictionary = entry
		if int(deposit.get("amount", 0)) > 0:
			return deposit
	return {}


func _finish(ok: bool, why: String) -> void:
	if _done:
		return
	_done = true
	if ok:
		print(("HUD PROBE OK: %d bundles applied to tick %d, the readout matches the world, every "
				+ "unassayed sheet is a band, %d event lines") % [_sim.applied, _sim.tick(),
				_events.size()])
	else:
		print("FAIL  %s" % why)
	quit(0 if ok else 1)
