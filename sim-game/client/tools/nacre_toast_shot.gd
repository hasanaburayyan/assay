extends SceneTree
## A PICTURE OF THE STATUS TOAST, IN BOTH OF ITS STATES (ASSA-239).
##
##   godot --path . --script res://tools/nacre_toast_shot.gd -- <out_dir> [seed]
##
## NOT `--headless`: a dummy rendering driver reads back a blank frame and reports success, which is
## the most expensive kind of green there is. Same rule as `window_shot.gd`.
##
## **WHY `window_shot.gd` CANNOT TAKE THIS ONE.** Maren's Gap 2 ruling gives the 96px header strip to
## the world and puts nothing in its place, so what the client is saying became a toast over the
## world's bottom-left that is drawn ONLY while it has something to say. An accepted command DOES say
## something -- `Mine · submitted`, her ASSA-237 ruling: *"the acceptance is a fact a player uses; the
## tick is not"* -- but it is a `Say.JOINED` line, so it ages out after `SAYING_DWELL_TICKS` of the
## world's clock. So a world left alone for a couple of seconds has no toast at all, and a shot set
## that only ever catches that state proves nothing about the panel.
##
## **THE DROP IS REACHED BY KILLING THE RELAY, NOT BY CALLING THE HANDLER.** `_on_refused` and
## `_say` are one function call away and would photograph my own model of a dead link. Stopping the
## real process kills a real socket, so `AssayNetClient` finds it the way a player's client does:
## stage DEAD, `link_failed` with the operating system's own reason, and `_refresh_join_band` putting
## the reconnect controls back. That is the one in-world state this panel exists for, and it is the
## state the picture has to be of.
##
## Writes two frames and prints `TOAST SHOT OK` LAST and only on success, because Godot exits 0 even
## on a compile error.
##  - `01-healthy.png`  a played world with nothing to say: the toast is ABSENT, not empty.
##  - `02-dropped.png`  the same world after the host died: the sentence and the way back in, in one
##                      panel over the world's bottom-left.

const DEFAULT_SEED := "14247"
const LISTEN_DEADLINE := 10.0
const JOIN_DEADLINE := 12.0
const DROP_DEADLINE := 30.0
## How long the screen may take to go quiet after a join before this calls it permanent (ASSA-239).
const QUIET_DEADLINE := 20.0
const SETTLE_FRAMES := 4
const RUN_CEILING := 180.0

var _screen: Node = null
var _binary := ""
var _out := ""
var _seed := DEFAULT_SEED
var _address := ""
var _relay_pid := -1
var _relay_stdio: FileAccess = null
var _relay_said := PackedStringArray()

var _step := 0
var _until := 0.0
var _settle := 0
var _done := false
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING
var _said := PackedStringArray()
var _healthy_toast := true
var _dropped_toast := false
var _dropped_rect := Rect2()


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		print("FAIL  need an output directory")
		quit(1)
		return
	_out = String(argv[0])
	if argv.size() > 1:
		_seed = String(argv[1])
	DirAccess.make_dir_recursive_absolute(_out)
	_binary = AssaySoloRelay.find_binary()
	if _binary == "":
		print("FAIL  no sim-relay binary")
		quit(1)
		return
	var saves := OS.get_user_data_dir().path_join("nacre-toast-shot-saves")
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
			_wait_for_quiet()
		4:
			# THE HEALTHY FRAME. Read the toast BEFORE shooting, so the report states what the picture
			# contains rather than what I expect it to.
			_healthy_toast = _screen._says_toast.visible
			_shoot("01-healthy.png")
			_step = 5
		5:
			_kill_the_host()
		6:
			_wait_for_the_drop()
		7:
			_settle_then(8)
		8:
			_dropped_toast = _screen._says_toast.visible
			_dropped_rect = Rect2(_screen._says_toast.position, _screen._says_toast.size)
			_shoot("02-dropped.png")
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


## **WAIT FOR THE SCREEN TO GO QUIET, AND FAIL IF IT NEVER DOES** (ASSA-239).
##
## A join says `joined as player 0`, which is a `Say.JOINED` sentence and therefore ages out after
## `SAYING_DWELL_TICKS` of the world's own clock -- about two seconds at the relay's default rate.
## Shooting four frames after the world arrives photographs that sentence mid-life, which is a true
## picture of the wrong moment: the claim under test is that the resting state of a played screen has
## no toast in it, and "resting" is exactly what the dwell has to have expired for.
##
## **THE DEADLINE IS WHAT MAKES THIS A TEST RATHER THAN A PAUSE.** If the line never clears, this does
## not quietly shoot a toast anyway -- it runs out and `_report` fails on `healthy: toast visible`,
## which is how the permanent `joined as player 0` was caught in the first place.
func _wait_for_quiet() -> void:
	if not _screen._says_toast.visible:
		_settle_then(4)
		return
	_settle = 0
	if _now() >= _until + QUIET_DEADLINE:
		# Fall through to the shot: `_report` is what judges it, and a picture of the failure is worth
		# more than a bail with no frame beside it.
		print("  the toast never went quiet within %ds; shooting it anyway" % int(QUIET_DEADLINE))
		_step = 4


## **THE HOST DIES FOR REAL.** Killing the process is what makes the client discover this rather than
## be told it: the socket goes away under a reader thread that is not expecting it.
func _kill_the_host() -> void:
	if _relay_pid > 0 and OS.get_process_exit_code(_relay_pid) == -1:
		OS.kill(_relay_pid)
		print("  killed the relay (pid %d)" % _relay_pid)
	_relay_pid = -1
	_step = 6
	_until = _now() + DROP_DEADLINE


func _wait_for_the_drop() -> void:
	if _screen._client.stage == AssayNetClient.Stage.DEAD:
		_step = 7
		return
	if _now() >= _until:
		_bail("the client never noticed the host had gone (stage %d after %ds)"
				% [_screen._client.stage, int(DROP_DEADLINE)])


## MORE THAN ONE FRAME. The screen is built from deferred layout, so the first frame after a change
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


## **THE RUN FAILS IF EITHER FRAME MISSED ITS SUBJECT**, which is `window_shot.gd`'s own rule: a shot
## advertised as a picture of a thing, that does not contain the thing, reads as coverage.
func _report() -> void:
	var world := AssayHud.world_rect()
	print("")
	print("TOAST SHOT: seed %s, world rect %s" % [_seed, world])
	print("  healthy: toast visible = %s (want false -- a settled world has nothing to say)"
			% _healthy_toast)
	print("  dropped: toast visible = %s at %s" % [_dropped_toast, _dropped_rect])
	print("  said: %s" % " | ".join(_said))
	if _healthy_toast:
		_bail("the toast is drawn on a healthy world, which is the header strip at a smaller size")
		return
	if not _dropped_toast:
		_bail("the host died and the toast never appeared, so a dropped player is told nothing")
		return
	if not world.encloses(_dropped_rect):
		_bail("the toast at %s is outside the world %s" % [_dropped_rect, world])
		return
	print("TOAST SHOT OK")
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
