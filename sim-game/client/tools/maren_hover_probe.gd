extends SceneTree
## MAREN'S PROBE, not a shipped tool: what does the cursor section say when the mouse is over a
## building? Two claims rest on that line and NEITHER had been run.
##
##   1. ASSA-136 box 5 — "the cursor readout names a standing building". Nerite would only accept
##      it on the code path (`building_address` in sim-godot) and offered to narrow the box. A
##      narrowed box is the right answer only if the picture is genuinely out of reach; it is not.
##   2. ASSA-138 box 3 — I ruled that the map carries the ordinal and the HOVER LINE carries the
##      exact hopper count. I read that off `machine_status` and `hud.gd:557` and asserted it.
##      Reading code is not running it, and that is my own standing rule.
##
## `window_shot` cannot hover: it never moves the mouse. This feeds an InputEventMouseMotion at the
## tile's own centre, exactly as `button_play._click` feeds a button event, and then reads the
## cursor section's lines back out of the HUD.
##
##   godot --headless --path client --script res://tools/maren_hover_probe.gd -- <seed> [ticks]

const TICKS_PER_FRAME := 40

var _screen: Node
var _play: Object
var _asked: Array = []
var _seed := "777042"
var _left := 600
var _started := false
var _done := false


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	_seed = String(argv[0]) if argv.size() > 0 else "777042"
	_left = int(argv[1]) if argv.size() > 1 else 600
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	_play = AssayButtonPlay.new(_screen, 0)


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
	for _i in range(TICKS_PER_FRAME):
		if _left <= 0:
			_report()
			return true
		_left -= 1
		_play.advance()
		if _play.finished:
			_report()
			return true
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
		_asked.clear()
		var at: int = _screen._sim.tick()
		_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
	return false


## Hover a tile the way a hand does: a motion event at the tile's own centre, through the screen's
## own `_unhandled_input`. `point_of_tile` is the screen's answer to where that is, never mine --
## there are two views of the world and they put a tile in different places.
func _hover(tile: Vector2i) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _screen.point_of_tile(tile)
	_screen._unhandled_input(event)


func _report() -> void:
	_done = true
	var buildings: Array = _screen._sim.buildings()
	print("tick %d, %d building(s)" % [_screen._sim.tick(), buildings.size()])
	for b in buildings:
		var pos: Vector2i = b["pos"]
		print("\n=== HOVER %s at %s ===" % [String(b.get("kind", "?")), pos])
		print("  snapshot name   : %s" % String(b.get("name", "")))
		print("  snapshot status : %s" % String(b.get("status", "")))
		_hover(pos)
		print("  --- what the player reads in the cursor section ---")
		for line in _screen._cursor.text.split("\n"):
			print("  cursor > %s" % line)
	print("PROBE OK")
