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

## WHERE THINGS GO lives in `AssayHud` with the rest of the view's rules, so the one that matters can
## be tested: the HUD column sits BESIDE the map (Maren's ruling, ASSA-7), its width coming out of the
## map's own width term rather than covering it. The part menu lands in that same column once there is
## an assemble command to drive it.
const MARGIN := AssayHud.MARGIN
const VIEW := AssayHud.VIEW
const PANEL := AssayHud.PANEL
## Event lines kept on screen. A tick can produce several and they arrive ten times a second, so this
## is the last few seconds of the world, not a history.
const LOG_LINES := 14

var _client: AssayNetClient
var _sim := AssaySimHost.new()
var _host := LineEdit.new()
var _name := LineEdit.new()
var _status := Label.new()
var _detail := Label.new()
var _carrying := Label.new()
var _cursor := Label.new()
var _log := Label.new()
## THE PART MENU'S HOME: one headline label plus one body label per design, rebuilt only when the
## list changes. Not a Label like the others, because the verdict is a WORD IN ITS OWN COLOUR above
## numbers in another (Maren's ruling) and one Label can only be one colour.
var _bench := VBoxContainer.new()
## What the bench was last built from, so ten refreshes a second do not rebuild nodes that have not
## changed. The designs themselves are the signature: if they are identical, so is the panel.
var _bench_showing := ""
## Tile size last drawn at, so a click can be turned back into a tile. Set by `_draw`, which is the
## only place that decides it; 0 means nothing has been drawn yet and a click means nothing.
var _cell := 0.0
## Hash reports actually put on the wire. See `_on_tick_bundle`.
var _hashes_sent := 0
## The tile under the mouse, and whether the mouse has ever been over the map. Not a Vector2i alone,
## because tile (0, 0) is a real tile and "no hover" is not it.
var _hover := Vector2i.ZERO
var _hovering := false
## The newest event lines, oldest first. View state: the sim keeps only the last tick's events, so
## anything older than that is remembered here or nowhere.
var _events := PackedStringArray()


func _ready() -> void:
	# CI, not a player: prove the build it just exported works, then leave. Before any UI, because
	# a self-check that needed the window would not run on a build server.
	var selfcheck := AssaySelfCheck.requested_path()
	if selfcheck != "":
		get_tree().quit(AssaySelfCheck.run(selfcheck))
		return
	_client = AssayNetClient.new()
	_client.welcomed.connect(_on_welcomed)
	_client.refused.connect(func(reason): _say("refused: %s" % reason, AssayHud.Say.FAILED))
	_client.link_failed.connect(func(reason): _say(reason, AssayHud.Say.FAILED))
	_client.tick_bundle.connect(_on_tick_bundle)
	_client.desynced.connect(func(tick): _say(
			"desync at tick %d. Restart the client to rejoin (Decision 3: no reconnect)." % tick,
			AssayHud.Say.FAILED))
	# A note is narration, so its state is whatever the link's state already is.
	_client.note.connect(func(line): _say(line, AssayHud.Say.JOINED
			if _client.stage == AssayNetClient.Stage.JOINED else AssayHud.Say.CONNECTING))
	add_child(_client)
	_build_ui()
	_say("enter a host address and join", AssayHud.Say.IDLE)


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

	# THE HUD COLUMN, beside the map. Three sections, each the plainest thing that answers one
	# question: what am I carrying, what is under the cursor, what just happened.
	var column := VBoxContainer.new()
	column.position = Vector2(VIEW.x - PANEL - MARGIN.x, MARGIN.y)
	column.custom_minimum_size = Vector2(PANEL, 0.0)
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	for part in [["you", _carrying], ["bench", _bench], ["cursor", _cursor], ["last tick", _log]]:
		var heading := Label.new()
		heading.text = String(part[0])
		heading.modulate = Color(0.60, 0.64, 0.70)
		column.add_child(heading)
		var body: Control = part[1]
		body.custom_minimum_size = Vector2(PANEL, 0.0)
		if body is Label:
			(body as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(body)
	_refresh_bench()


func _on_join() -> void:
	if _client.stage != AssayNetClient.Stage.IDLE and _client.stage != AssayNetClient.Stage.DEAD:
		_say("already joining; restart the client to change host (no reconnect in the demo)",
				AssayHud.Say.FAILED)
		return
	# SAID BEFORE THE CALL, not after it: `join` does reach a socket, and a button that shows nothing
	# until the answer comes back reads as a dead button. Maren's ruling, and she had the premise
	# slightly wrong -- `join` already emits a "connecting to ..." note of its own -- but only on the
	# path where `connect_to_host` succeeds, so this is the line that is true either way.
	_say("connecting to %s…" % _host.text, AssayHud.Say.CONNECTING)
	_client.join(_host.text, _name.text if _name.text != "" else "player")


## THE RAW TEXT GOES TO THE SIM, the dictionary does not. By the time a `Welcome` is a Godot
## Dictionary its numbers have been through a double, so the world is built from the bytes.
func _on_welcomed(player: int, _world: Dictionary, raw: String) -> void:
	if not _sim.start(raw):
		_say("joined as player %d, but cannot simulate: %s" % [player, _sim.fail_reason],
				AssayHud.Say.FAILED)
		_refresh()
		return
	_say("joined as player %d" % player, AssayHud.Say.JOINED)
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
	_remember_events()
	_refresh()
	queue_redraw()


## What the tick we just applied did, kept where it can be read. The sim holds only the newest tick's
## events, so a line not copied out here is gone a tenth of a second later.
func _remember_events() -> void:
	var tick := _sim.tick()
	for line in _sim.event_lines(_client.player_id):
		_events.append("%d · %s" % [tick, line])
	_events = AssayHud.trimmed_log(_events, LOG_LINES)


func _say(line: String, level: int) -> void:
	_status.text = line
	_status.modulate = AssayHud.status_color(level)
	print(line)


func _refresh() -> void:
	if not _sim.running():
		var joined: Dictionary = _client.joined_world
		if joined.is_empty():
			return
		_detail.text = ("joined at tick %d, but no world is being simulated: %s"
				% [int(joined.get("tick", -1)), _sim.fail_reason])
		return
	_carrying.text = "\n".join(AssayHud.inventory_lines(_sim.inventory_of(_client.player_id)))
	# The tile under the mouse, or your own tile until the mouse has been over the map. Which one it
	# is has to be on screen: a readout that silently changed subject would be unreadable.
	var at := _hover
	var source := "under the mouse"
	if not _hovering:
		at = _my_tile()
		source = "where you stand"
	_cursor.text = "%s\n%s" % [source, "\n".join(AssayHud.tile_lines(_sim.tile_at(at)))]
	_log.text = "\n".join(_events)
	_refresh_bench()


## THE PART MENU: every design you hold, verdict first.
##
## Maren's ruling, and the reason this is nodes rather than one Label: THE VERDICT IS THE HEADLINE
## AND THE NUMBERS ARE THE SMALL PRINT. A player predicting a break should read one word, not
## compare two integers -- so the word is its own label, in the verdict's own colour and larger,
## with the spans under it in grey.
##
## NOTHING HERE DECIDES ANYTHING. The verdict, the spans, the durability wording and the list of
## species still reading rough all arrive from `sim` through the binding. The one thing this client
## adds is the arrangement.
##
## NO PLACE BUTTON YET, and that is deliberate rather than an oversight: the ruling is that place is
## never disabled, and a button that cannot work is a disabled one with extra steps. Placement lands
## with the command path that can be driven end to end.
func _refresh_bench() -> void:
	var designs := _sim.designs_of(_client.player_id) if _client != null else []
	var signature := str(designs)
	if signature == _bench_showing:
		return
	_bench_showing = signature
	for child in _bench.get_children():
		child.queue_free()
		_bench.remove_child(child)
	if designs.is_empty():
		var empty := Label.new()
		empty.text = AssayHud.no_designs_line()
		empty.modulate = Color(0.55, 0.58, 0.64)
		empty.custom_minimum_size = Vector2(PANEL, 0.0)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bench.add_child(empty)
		return
	for entry in designs:
		var design: Dictionary = entry
		var verdict := Label.new()
		verdict.text = String(design.get("verdict", "?"))
		verdict.modulate = AssayHud.verdict_color(verdict.text)
		verdict.add_theme_font_size_override("font_size", 19)
		_bench.add_child(verdict)
		var body := Label.new()
		body.text = "\n".join(AssayHud.design_lines(design))
		body.modulate = Color(0.78, 0.80, 0.85)
		body.add_theme_font_size_override("font_size", 13)
		body.custom_minimum_size = Vector2(PANEL, 0.0)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bench.add_child(body)


## The tile my own player is on, as the sim has them. Spawn before there is a player of mine to find:
## it is the one tile every world has and it is where I am about to be.
func _my_tile() -> Vector2i:
	for entry in _sim.players():
		var player: Dictionary = entry
		if int(player.get("id", -1)) == _client.player_id:
			return player.get("pos", Vector2i.ZERO) as Vector2i
	return _sim.spawn_tile()
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
	if event is InputEventMouseMotion:
		_track_hover(event.position)
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == 1):
		return
	var target: Variant = _tile_under(event.position)
	if target == null:
		return
	var tile: Vector2i = target
	if _client.submit({"MoveTo": {"target": {"x": tile.x, "y": tile.y}}}):
		_say("walking to %d, %d" % [tile.x, tile.y], AssayHud.Say.JOINED)


## Which tile a screen position is on, or null for anywhere that is not a tile. ONE PLACE DOES THIS,
## because a hover readout that disagreed with where a click goes would be worse than no readout.
func _tile_under(at: Vector2) -> Variant:
	if not _sim.running() or _cell <= 0.0:
		return null
	var tile := ((at - MARGIN) / _cell).floor()
	var size := _sim.size_tiles()
	if tile.x < 0.0 or tile.y < 0.0 or tile.x >= float(size.x) or tile.y >= float(size.y):
		return null
	return Vector2i(int(tile.x), int(tile.y))


func _track_hover(at: Vector2) -> void:
	var tile: Variant = _tile_under(at)
	var now_on: bool = tile != null
	# Off the map, the readout goes back to your own tile rather than freezing on the last tile the
	# mouse crossed, which would be a stale answer that looks live.
	if not now_on:
		if _hovering:
			_hovering = false
			_refresh()
			queue_redraw()
		return
	var found: Vector2i = tile
	if _hovering and found == _hover:
		return
	_hover = found
	_hovering = true
	_refresh()
	queue_redraw()


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
	_cell = AssayHud.map_cell(size)
	if _cell <= 0.0:
		return
	draw_rect(Rect2(MARGIN, Vector2(size) * _cell), Color(0.10, 0.11, 0.13), true)

	var spawn := _sim.spawn_tile()
	draw_rect(Rect2(MARGIN + Vector2(spawn) * _cell - Vector2(_cell, _cell) * 2.0,
			Vector2(_cell, _cell) * 4.0), Color(0.35, 0.33, 0.20), true)

	# SPECIES IS HUE, PURITY IS BRIGHTNESS, and the rule plus why my first version was wrong is in
	# `AssayHud.deposit_color`. Grade bands (C < 40, B 40-69, A >= 70) are the sim's, not invented.
	var species_count := _sim.species_names().size()
	for entry in _sim.deposits():
		var deposit: Dictionary = entry
		if int(deposit.get("amount", 0)) <= 0:
			continue
		var at := MARGIN + Vector2(deposit.get("center", Vector2i.ZERO) as Vector2i) * _cell
		draw_circle(at, maxf(_cell, float(int(deposit.get("radius", 1))) * _cell),
				AssayHud.deposit_color(int(deposit.get("species", 0)), species_count,
						int(deposit.get("purity", 1))))

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

	# The tile the readout is talking about, outlined. Drawn last so it is never buried, and only
	# while the mouse is actually over the map -- an outline left behind would point at an answer the
	# panel is no longer giving.
	if _hovering:
		draw_rect(Rect2(MARGIN + Vector2(_hover) * _cell, Vector2(_cell, _cell)),
				Color(0.95, 0.95, 0.95, 0.55), false, 1.0)
