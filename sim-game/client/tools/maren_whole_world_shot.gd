extends SceneTree
## CI: local -- a shot: --headless writes a blank frame and reports success
## THE WHOLE-WORLD SCHEMATIC, PHOTOGRAPHED FOR THE FIRST TIME (Maren).
##
##   godot --path client --script res://tools/maren_whole_world_shot.gd -- <out_dir> [seed] [row]
##   (A GUI RUN. Never --headless: a headless viewport photographs nothing.)
##
## **`window_shot.gd` SHOOTS FIVE SCREENS AND NOT ONE OF THEM IS THIS ONE.** 01-join, 02-play,
## 03-log, 04-pack, 05-rocks. The game has TWO ways of looking at the world -- the close-up at
## 32px/tile and the `whole world (V)` schematic -- and only one has ever been in front of anyone's
## eyes. `button_play.gd` toggles it to test a control and `maren_motion_probe.gd` drives it to
## measure motion; neither saves a frame.
##
## So this presses V and shoots both views of the same world, one after the other, so they can be
## judged side by side at 1x.

const DEFAULT_SEED := "777042"
const DEFAULT_ROW := 3
const LISTEN_DEADLINE := 10.0
const JOIN_DEADLINE := 12.0
const WALK_DEADLINE := 90.0
const SETTLE_FRAMES := 4
const RUN_CEILING := 180.0

var _screen: Node = null
var _binary := ""
var _out := ""
var _seed := DEFAULT_SEED
var _row := DEFAULT_ROW
var _address := ""
var _relay_pid := -1
var _relay_stdio: FileAccess = null
var _relay_said := PackedStringArray()

var _step := 0
var _until := 0.0
var _settle := 0
var _done := false
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING
var _target := Vector2i.ZERO
var _said := PackedStringArray()


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		print("FAIL  need an output directory")
		quit(1)
		return
	_out = String(argv[0])
	if argv.size() > 1:
		_seed = String(argv[1])
	if argv.size() > 2:
		_row = int(argv[2])
	DirAccess.make_dir_recursive_absolute(_out)
	_binary = AssaySoloRelay.find_binary()
	if _binary == "":
		print("FAIL  no sim-relay binary")
		quit(1)
		return
	var saves := OS.get_user_data_dir().path_join("maren-north-shot-saves")
	DirAccess.make_dir_recursive_absolute(saves)
	OS.set_environment("R2TS_SAVES_DIR", saves)
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	_screen._client.note.connect(func(l): _said.append("note: %s" % l))
	_screen._client.link_failed.connect(func(l): _said.append("failed: %s" % l))
	print("window %s, viewport %s" % [DisplayServer.window_get_size(), root.size])
	if not _spawn_relay():
		return
	_step = 1
	_until = _now() + LISTEN_DEADLINE


func _process(_delta: float) -> bool:
	if _done:
		return true
	if _now() >= _ceiling:
		_bail("ran past its ceiling at step %d" % _step)
		return true
	match _step:
		1:
			_wait_then_join()
		2:
			_wait_for_the_world()
		3:
			_walk_north()
		4:
			_wait_for_arrival()
		5:
			_settle_then(6)
		6:
			_shoot("01-close-up.png")
			_screen._show_make(false)
			_step = 7
		7:
			_settle_then(8)
		8:
			# THE PRESS ITSELF, not `_show_close_up` -- what a person's click does.
			_screen._view_toggle.emit_signal("pressed")
			_step = 9
		9:
			_settle_then(10)
		10:
			_shoot("02-whole-world.png")
			_report()
	return _done


func _wait_then_join() -> void:
	_drain_relay()
	if _address == "":
		if _now() >= _until:
			_bail("relay never said LISTENING: %s" % " / ".join(_relay_said))
		return
	_screen._host.text = _address
	_screen._on_join()
	_step = 2
	_until = _now() + JOIN_DEADLINE


func _wait_for_the_world() -> void:
	if _screen._client.stage == AssayNetClient.Stage.JOINED and _screen._sim.running() \
			and _screen._client.bundles_seen > 0:
		_step = 3
		return
	if _now() >= _until:
		_bail("no world within %ds (stage %d)" % [int(JOIN_DEADLINE), _screen._client.stage])


## THE SAME COMMAND A LEFT CLICK SENDS. `main.gd::_on_map_click` submits `AssayActions.move_to`;
## anything else here would be testing my model of the client rather than the client.
##
## **IT WALKS IN HOPS, AND THAT IS NOT A DETAIL -- IT IS WHAT MAKES THE SHOT THE RIGHT SHOT.** My
## first run went straight there and photographed a TWO-LINE log: the panel is sized by its content
## and only capped at the ceiling, so a fresh session's panel is 80px and the player cleared it by
## two pixels. A picture of an empty log is not a picture of this defect. Each hop prints `started
## walking` and `arrived`, so the hops fill the panel to the cap the arithmetic is about.
const HOPS := 5

var _hops_left := HOPS


func _walk_north() -> void:
	var me := _me()
	if me.is_empty():
		if _now() >= _ceiling:
			_bail("the sim never reported my own player")
		return
	# THE LAST HOP IS THE ONE THAT ARRIVES. The others zig-zag along the row above the target so
	# every one of them is a real walk with a real pair of events.
	if _hops_left > 1:
		var dx := 3 if (_hops_left % 2) == 0 else -3
		_target = Vector2i(int(me["at"].x) + dx, maxi(_row + 1, 1))
	else:
		_target = Vector2i(int(me["at"].x), _row)
	if not _screen._client.submit(AssayActions.move_to(_target)):
		_bail("the client refused a MoveTo to %s" % _target)
		return
	print("  hop %d: %s -> %s" % [HOPS - _hops_left + 1, me["at"], _target])
	_step = 4
	_until = _now() + WALK_DEADLINE


func _wait_for_arrival() -> void:
	var me := _me()
	if me.is_empty():
		return
	if Vector2i(int(me["at"].x), int(me["at"].y)) == _target:
		_hops_left -= 1
		if _hops_left <= 0:
			print("  arrived at %s (row %d)" % [me["at"], int(me["at"].y)])
			_step = 5
		else:
			_step = 3
		return
	if _now() >= _until:
		_bail("never reached %s in %ds; stuck at %s" % [_target, int(WALK_DEADLINE), me["at"]])


## MY OWN PLAYER, as the screen already finds it.
func _me() -> Dictionary:
	for entry in _screen._sim.players():
		var p: Dictionary = entry
		if int(p.get("id", -1)) == int(_screen._client.player_id):
			return {"at": Vector2(p.get("pos", Vector2i.ZERO))}
	return {}


## MORE THAN ONE FRAME. The screen is built from deferred layout, so the first frame after a toggle
## photographs the state before it.
func _settle_then(next: int) -> void:
	_settle += 1
	if _settle >= SETTLE_FRAMES:
		_settle = 0
		_step = next


func _shoot(name: String) -> void:
	var image := root.get_texture().get_image()
	var path := _out.path_join(name)
	if image.save_png(path) != OK:
		_bail("could not write %s" % path)
		return
	print("  wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])


func _report() -> void:
	var me := _me()
	print("")
	print("WHOLE-WORLD SHOT: seed %s, player at %s, toggle reads: %s, close_up=%s"
			% [_seed, me.get("at", "?"), _screen._view_toggle.text, _screen._close_up])
	print("  said: %s" % " | ".join(_said))
	print("WINDOW SHOT OK")
	_finish(0)


func _spawn_relay() -> bool:
	var pipe := OS.execute_with_pipe(_binary, PackedStringArray([_seed, "--bind", "127.0.0.1",
			"--port", "0"]))
	if pipe.is_empty() or int(pipe.get("pid", -1)) <= 0:
		_bail("could not start %s" % _binary)
		return false
	_relay_pid = int(pipe["pid"])
	_relay_stdio = pipe["stdio"]
	return true


func _drain_relay() -> void:
	while _relay_stdio != null and _relay_stdio.get_length() > _relay_stdio.get_position():
		var line := _relay_stdio.get_line()
		if line.begins_with(AssaySoloRelay.LISTENING):
			_address = line.substr(AssaySoloRelay.LISTENING.length()).strip_edges()
			continue
		if line.strip_edges() != "":
			_relay_said.append(line.strip_edges())


func _bail(why: String) -> void:
	print("FAIL  %s" % why)
	_finish(1)


func _finish(code: int) -> void:
	if _relay_pid > 0 and OS.get_process_exit_code(_relay_pid) == -1:
		OS.kill(_relay_pid)
	_relay_stdio = null
	_done = true
	quit(code)


func _now() -> float:
	return Time.get_unix_time_from_system()
