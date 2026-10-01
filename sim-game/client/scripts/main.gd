extends Node2D
## THE WHOLE CLIENT A PLAYER SEES, for now: a host address, a name, and the world you joined.
##
## Decision 1's test is "a friend with no terminal can download a build, enter a host address and
## play", so the address field is not a debug convenience -- it is the front door, and it is here on
## the first screen rather than behind a menu.
##
## WHAT IS DRAWN IS THE SNAPSHOT THE RELAY WELCOMED US WITH, and the status line says so plainly.
## A tick bundle carries inputs, not state; turning inputs into a newer world is `sim::step` in Rust,
## which this client does not yet hold (see `AssayNetClient`). Drawing a guessed position would be a
## second rules engine with a nicer name. So: the join tick is shown, the bundle count proves the
## link is live, and nothing moves until the sim is bound in.

const TILE := 10.0
const MARGIN := Vector2(24.0, 96.0)

var _client: AssayNetClient
var _host := LineEdit.new()
var _name := LineEdit.new()
var _status := Label.new()
var _detail := Label.new()


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
	_client.tick_bundle.connect(func(_tick, _inputs): _refresh())
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


func _on_welcomed(player: int, _world: Dictionary) -> void:
	_say("joined as player %d" % player)
	_refresh()
	queue_redraw()


func _say(line: String) -> void:
	_status.text = line
	print(line)


func _refresh() -> void:
	var world: Dictionary = _client.joined_world
	if world.is_empty():
		return
	_detail.text = ("world seed %s, %sx%s chunks, %d species, %d players · joined at tick %d · "
			+ "%d bundles since (last tick %d). The map is the JOIN snapshot: applying bundles "
			+ "needs the Rust sim, which this client does not run yet.") % [
			world.get("seed", "?"), world.get("width_chunks", "?"), world.get("height_chunks", "?"),
			(world.get("species", []) as Array).size(), (world.get("players", []) as Array).size(),
			int(world.get("tick", -1)), _client.bundles_seen, _client.last_tick]


## The joined snapshot, read straight off the dictionary: world bounds, every deposit, every player,
## and spawn. No sprite yet on purpose -- `assets/sprites` is drawn for the old named ores and the
## species here are generated, so shape-and-colour from the snapshot's own numbers is the honest
## picture until the art pipeline catches up.
func _draw() -> void:
	# A self-check run returns out of `_ready` before there is a client, and the engine still calls
	# `_draw` once. In the editor that is a caught script error; in an EXPORTED RELEASE BUILD it
	# segfaulted on exit (measured: exit 139 after the marker was already written). Nothing to draw
	# without a client is also just true.
	if _client == null:
		return
	var world: Dictionary = _client.joined_world
	if world.is_empty():
		return
	var wide := int(world.get("width_chunks", 0)) * 16
	var high := int(world.get("height_chunks", 0)) * 16
	if wide <= 0 or high <= 0:
		return
	var scale := minf((1280.0 - MARGIN.x * 2.0) / float(wide), (720.0 - MARGIN.y - 24.0) / float(high))
	var cell := maxf(2.0, floorf(scale))
	draw_rect(Rect2(MARGIN, Vector2(wide, high) * cell), Color(0.10, 0.11, 0.13), true)

	var spawn: Dictionary = world.get("spawn", {})
	if not spawn.is_empty():
		var at := MARGIN + Vector2(float(int(spawn.get("x", 0)) * 16 + 8),
				float(int(spawn.get("y", 0)) * 16 + 8)) * cell
		draw_rect(Rect2(at - Vector2(cell, cell) * 2.0, Vector2(cell, cell) * 4.0),
				Color(0.35, 0.33, 0.20), true)

	# Purity is 1-100 and it is the number the whole game is named after, so it is what the deposit's
	# brightness means here. Grade bands (C < 40, B 40-69, A >= 70) are the sim's, not invented.
	for entry in world.get("deposits", []) as Array:
		var d: Dictionary = entry
		if int(d.get("amount", 0)) <= 0:
			continue
		var centre: Dictionary = d.get("center", {})
		var purity := clampf(float(int(d.get("purity", 1))) / 100.0, 0.05, 1.0)
		var at := MARGIN + Vector2(float(centre.get("x", 0)), float(centre.get("y", 0))) * cell
		draw_circle(at, maxf(cell, float(int(d.get("radius", 1))) * cell),
				Color(0.30 + 0.45 * purity, 0.45 + 0.35 * purity, 0.55, 0.85))

	for entry in world.get("players", []) as Array:
		var p: Dictionary = entry
		var pos: Dictionary = p.get("pos", {})
		var at := MARGIN + Vector2(float(pos.get("x", 0)), float(pos.get("y", 0))) * cell
		var mine := int(p.get("id", -1)) == _client.player_id
		draw_rect(Rect2(at - Vector2(cell, cell), Vector2(cell, cell) * 2.0),
				Color(0.95, 0.85, 0.45) if mine else Color(0.75, 0.78, 0.85), true)
