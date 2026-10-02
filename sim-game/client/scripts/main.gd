extends Node2D
## THE WHOLE CLIENT A PLAYER SEES, for now: a host address, a name, and the world you are in.
##
## Decision 1's test is "a friend with no terminal can download a build, enter a host address and
## play", so the address field is not a debug convenience -- it is the front door, and it is here on
## the first screen rather than behind a menu.
##
## WHAT IS DRAWN IS THE WORLD THE SIM STEPPED, not a guess at it. A tick bundle carries inputs, not
## state; turning inputs into a newer world is `sim::step`, which this client now runs through
## `AssaySimHost`. Nothing here predicts, interpolates or recomputes: a position on screen is a
## position the sim is actually on, and if the sim has not reached a tick yet then neither has the
## picture. Until the first `Welcome` there is nothing to draw at all.

const MARGIN := Vector2(24.0, 96.0)
const VIEW := Vector2(1280.0, 720.0)

var _client: AssayNetClient
var _sim := AssaySimHost.new()
var _host := LineEdit.new()
var _name := LineEdit.new()
var _status := Label.new()
var _detail := Label.new()
## Tile size last drawn at, so a click can be turned back into a tile. Set by `_draw`, which is the
## only place that decides it; 0 means nothing has been drawn yet and a click means nothing.
var _cell := 0.0
## Hash reports actually put on the wire. See `_on_tick_bundle`.
var _hashes_sent := 0


func _ready() -> void:
	# CI, not a player: prove the build it just exported works, then leave. Before any UI, because
	# a self-check that needed the window would not run on a build server.
	var selfcheck := AssaySelfCheck.requested_path()
	if selfcheck != "":
		get_tree().quit(AssaySelfCheck.run(selfcheck))
		return
	_client = AssayNetClient.new()
	_client.welcomed.connect(_on_welcomed)
	_client.refused.connect(func(reason): _say("refused: %s" % reason))
	_client.link_failed.connect(func(reason): _say(reason))
	_client.tick_bundle.connect(_on_tick_bundle)
	_client.desynced.connect(func(tick): _say(
			"desync at tick %d. Restart the client to rejoin (Decision 3: no reconnect)." % tick))
	_client.note.connect(_say)
	add_child(_client)
	_build_ui()
	_say("enter a host address and join")


func _build_ui() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(24.0, 20.0)
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var host_label := Label.new()
	host_label.text = "host"
	row.add_child(host_label)
	_host.text = "localhost:%d" % AssayProtocol.DEFAULT_PORT
	_host.custom_minimum_size = Vector2(240.0, 0.0)
	_host.tooltip_text = "host, host:port, or [v6]:port. A bare address uses 7777."
	row.add_child(_host)

	var name_label := Label.new()
	name_label.text = "name"
	row.add_child(name_label)
	_name.text = OS.get_environment("USER")
	_name.custom_minimum_size = Vector2(140.0, 0.0)
	row.add_child(_name)

	var join := Button.new()
	join.text = "Join"
	join.pressed.connect(_on_join)
	row.add_child(join)

	_status.position = Vector2(24.0, 54.0)
	add_child(_status)
	_detail.position = Vector2(24.0, 74.0)
	add_child(_detail)


func _on_join() -> void:
	if _client.stage != AssayNetClient.Stage.IDLE and _client.stage != AssayNetClient.Stage.DEAD:
		_say("already joining; restart the client to change host (no reconnect in the demo)")
		return
	_client.join(_host.text, _name.text if _name.text != "" else "player")


## THE RAW TEXT GOES TO THE SIM, the dictionary does not. By the time a `Welcome` is a Godot
## Dictionary its numbers have been through a double, so the world is built from the bytes.
func _on_welcomed(player: int, _world: Dictionary, raw: String) -> void:
	if not _sim.start(raw):
		_say("joined as player %d, but cannot simulate: %s" % [player, _sim.fail_reason])
		_refresh()
		return
	_say("joined as player %d" % player)
	_refresh()
	queue_redraw()


## One tick: step the world, then report a hash if one is owed.
##
## The hash is the whole point of being a lockstep peer -- it is how the relay tells us our world has
## drifted instead of letting us play a different game quietly. The message is written in Rust
## because its `hash` is a `u64`; see `protocol.gd`.
func _on_tick_bundle(_tick: int, _inputs: Array, raw: String) -> void:
	var report := _sim.apply(raw)
	# Counted on the SEND, not on the produce: a report that never left is a report the relay never
	# checked, and the status line would be claiming a check that did not happen.
	if report != "" and _client.send_text(report):
		_hashes_sent += 1
	_refresh()
	queue_redraw()


func _say(line: String) -> void:
	_status.text = line
	print(line)


func _refresh() -> void:
	if not _sim.running():
		var joined: Dictionary = _client.joined_world
		if joined.is_empty():
			return
		_detail.text = ("joined at tick %d, but no world is being simulated: %s"
				% [int(joined.get("tick", -1)), _sim.fail_reason])
		return
	# Everything on this line comes out of the sim. The seed and the hash are TEXT, because a u64
	# cannot survive a GDScript number -- that is not caution, it is measured.
	var size := _sim.size_tiles()
	_detail.text = ("world seed %s, %d x %d tiles, %d species, %d players · tick %d, hash %s · "
			+ "%d bundles applied, %d hashes reported") % [
			_sim.seed_text(), size.x, size.y, _sim.species_names().size(), _sim.players().size(),
			_sim.tick(), _sim.hash_hex(), _sim.applied, _hashes_sent]


## Click a tile to walk there. The command is the same `PlayerCommand::MoveTo` `sim-cli` sends; the
## sim decides whether it is legal and the movement system walks us one tile per tick. NOTHING MOVES
## HERE -- the player on screen moves when a bundle carrying this command comes back around.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == 1):
		return
	if not _sim.running() or _cell <= 0.0:
		return
	var tile := ((event.position - MARGIN) / _cell).floor()
	var size := _sim.size_tiles()
	if tile.x < 0.0 or tile.y < 0.0 or tile.x >= float(size.x) or tile.y >= float(size.y):
		return
	var target := Vector2i(int(tile.x), int(tile.y))
	if _client.submit({"MoveTo": {"target": {"x": target.x, "y": target.y}}}):
		_say("walking to %d, %d" % [target.x, target.y])


## The world as the sim has it: bounds, every deposit, every player, and spawn. No sprite yet on
## purpose -- `assets/sprites` is drawn for the old named ores and the species here are generated, so
## shape-and-colour from the sim's own numbers is the honest picture until the art pipeline catches up.
func _draw() -> void:
	# A self-check run returns out of `_ready` before there is a client, and the engine still calls
	# `_draw` once. In the editor that is a caught script error; in an EXPORTED RELEASE BUILD it
	# segfaulted on exit (measured: exit 139 after the marker was already written). Nothing to draw
	# without a client is also just true.
	if _client == null or not _sim.running():
		return
	var size := _sim.size_tiles()
	if size.x <= 0 or size.y <= 0:
		return
	var fit := minf((VIEW.x - MARGIN.x * 2.0) / float(size.x),
			(VIEW.y - MARGIN.y - 24.0) / float(size.y))
	_cell = maxf(2.0, floorf(fit))
	draw_rect(Rect2(MARGIN, Vector2(size) * _cell), Color(0.10, 0.11, 0.13), true)

	var spawn := _sim.spawn_tile()
	draw_rect(Rect2(MARGIN + Vector2(spawn) * _cell - Vector2(_cell, _cell) * 2.0,
			Vector2(_cell, _cell) * 4.0), Color(0.35, 0.33, 0.20), true)

	# Purity is 1-100 and it is the number the whole game is named after, so it is what the deposit's
	# brightness means here. Grade bands (C < 40, B 40-69, A >= 70) are the sim's, not invented.
	for entry in _sim.deposits():
		var deposit: Dictionary = entry
		if int(deposit.get("amount", 0)) <= 0:
			continue
		var purity := clampf(float(int(deposit.get("purity", 1))) / 100.0, 0.05, 1.0)
		var at := MARGIN + Vector2(deposit.get("center", Vector2i.ZERO) as Vector2i) * _cell
		draw_circle(at, maxf(_cell, float(int(deposit.get("radius", 1))) * _cell),
				Color(0.30 + 0.45 * purity, 0.45 + 0.35 * purity, 0.55, 0.85))

	for entry in _sim.players():
		var player: Dictionary = entry
		var at := MARGIN + Vector2(player.get("pos", Vector2i.ZERO) as Vector2i) * _cell
		var mine := int(player.get("id", -1)) == _client.player_id
		# Where the sim is walking them, drawn as a line to there. Not a tween: the sim owns the
		# position and this is its intention, not a frame of motion we invented.
		var target: Variant = player.get("target")
		if target != null:
			draw_line(at, MARGIN + Vector2(target as Vector2i) * _cell,
					Color(0.95, 0.85, 0.45, 0.35) if mine else Color(0.75, 0.78, 0.85, 0.25), 1.0)
		draw_rect(Rect2(at - Vector2(_cell, _cell), Vector2(_cell, _cell) * 2.0),
				Color(0.95, 0.85, 0.45) if mine else Color(0.75, 0.78, 0.85), true)
