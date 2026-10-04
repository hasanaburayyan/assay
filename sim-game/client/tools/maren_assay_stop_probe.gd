extends SceneTree
## MAREN'S PROBE, not a shipped tool: does an assay STOPPED BY WALKING OFF reach the player?
##
## ASSA-95's last box, and Marlow said plainly that it is not driven by anyone — it may well hold
## through the event path, but nothing runs it. The sim half is visible in `debug.rs:836`:
## `AssayStopped` is an attention event when its reason is not `Stopped`. This drives the whole
## path instead: press the screen's own `Assay`, walk away, and read what reaches
## `attention_lines` — the list the HUD shows WITH THE LOG HIDDEN, which is the state every player
## is in until they press L.
##
##   godot --headless --path client --script res://tools/maren_assay_stop_probe.gd -- <seed>
##
## Prints the running block and the attention lines around the walk-off, then a verdict line.

const TICKS_PER_FRAME := 10
## How far to walk. Deposits are radius 2-4, so eight tiles leaves any of them.
const WALK := 8

var _screen: Node
var _asked: Array = []
var _seed := "14247"
var _started := false
var _done := false
var _left := 200
var _phase := "assaying"
var _home := Vector2i.ZERO
var _rows: Array[String] = []
var _stop_line := ""
var _stop_tick := -1
var _assay_seen := false


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	_seed = String(argv[0]) if argv.size() > 0 else "14247"
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))


func _find_button(node: Node, label: String) -> Button:
	if node is Button and (node as Button).text == label:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, label)
		if found != null:
			return found
	return null


func _me() -> int:
	return _screen._client.player_id


func _pos() -> Vector2i:
	# `players()` hands over `pos`, not loose x/y. Reading `x` off it returned (0,0) for every tick
	# of the first run of this probe -- a readout that was confidently wrong rather than missing,
	# which is the shape ASSA-141 is about. Not a default: if the player is gone, say so loudly.
	for p in _screen._sim.players():
		if int(p.get("id", -1)) == _me():
			return p["pos"] as Vector2i
	push_error("no player %d in the snapshot" % _me())
	return Vector2i(-1, -1)


func _process(_delta: float) -> bool:
	if _done:
		return true
	if not _started:
		var welcome := AssaySimHost.fresh_welcome_json(_seed, "maren")
		if welcome == "":
			print("PROBE DEAD: no world on seed %s" % _seed)
			_done = true
			return true
		_screen._client.play_offline()
		_screen._client.feed_offline(welcome)
		_started = true
		_home = _pos()
		var assay := _find_button(_screen, "Assay")
		if assay == null:
			print("PROBE DEAD: no Assay button on the screen")
			_done = true
			return true
		assay.pressed.emit()
		print("pressed Assay at %s, tick %d" % [_home, _screen._sim.tick()])
	for _i in range(TICKS_PER_FRAME):
		if _left <= 0:
			_report()
			return true
		_left -= 1
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": _me(), "command": command}})
		_asked.clear()
		var at: int = _screen._sim.tick()
		_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
		_sample(at)
		# Let the assay get properly under way, then walk off it. The walk is a MoveTo, the same
		# command the map's left click submits -- the player's own gesture, not a teleport.
		if _phase == "assaying" and at >= 10:
			var away := _home + Vector2i(WALK, 0)
			_screen._client.submit(AssayActions.move_to(away))
			print("walking from %s to %s at tick %d" % [_home, away, at])
			_phase = "walking"
	return false


func _sample(at: int) -> void:
	var running: PackedStringArray = _screen._sim.activity_lines(_me())
	for line in running:
		if line.to_lower().contains("assay"):
			_assay_seen = true
	var attention: PackedStringArray = _screen._sim.attention_lines(_me())
	for line in attention:
		if line.to_lower().contains("assay") and _stop_tick < 0 and _phase == "walking":
			_stop_tick = at
			_stop_line = line
	_rows.append("%d\t%s\tat %s\trunning[%s]\tattention[%s]"
			% [at, _phase, _pos(), " | ".join(running), " | ".join(attention)])


func _report() -> void:
	_done = true
	var last := "\u0000"
	for row in _rows:
		var parts := row.split("\t", true, 1)
		if parts[1] != last:
			print(row)
			last = parts[1]
	print("---")
	print("an assay was running at some point: %s" % _assay_seen)
	if _stop_tick >= 0:
		print("STOP REACHED THE PLAYER at tick %d: %s" % [_stop_tick, _stop_line])
	else:
		print("NO assay line ever reached attention_lines after the walk")
	print("PROBE OK")
