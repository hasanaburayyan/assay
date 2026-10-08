extends SceneTree
## CI: local -- a shot: --headless writes a BLANK frame and reports success, the worst kind of green
## **A PICTURE OF THE OPEN BUILD SCREEN, AND THE ONE MEASUREMENT ARITHMETIC CANNOT GIVE** (ASSA-328).
##
##   godot --path . --script res://tools/limpet_build_screen_shot.gd -- <out_dir> [seed] [ticks]
##
## **WHY IT IS NOT A STATE IN `window_shot.gd`.** That tool shoots seven fixed moments of a played
## world and every one of them is about the HUD column. This is about a surface that only exists
## after a press, and it carries a second job no shot tool has: it REPORTS the overlap.
##
## **THE JOB ARITHMETIC CANNOT DO.** `AssayHud.build_screen_rect` keeps the screen clear of the
## world's own control band -- the status toast and `whole world (V)`, which live inside the world
## rect and are not the world (Maren's §0). Headless, the band's top comes from
## `AssayHud.WORLD_CONTROLS_BAND`, a constant measured off a screenshot, and **a constant for a
## laid-out height is the shape of defect that goes stale in silence** (my own ASSA-320: a number
## written in prose beside asserted facts reads as fact). So this asks the three real controls where
## they ACTUALLY are in a laid-out window and intersects them with where the screen ACTUALLY is.
##
## **NOT `--headless`, for `window_shot`'s reason doubled.** A dummy driver writes a blank PNG and
## reports success, AND it lays nothing out -- so every rect in the report would read `(0,0,0,0)` and
## every overlap would be empty. **This tool would pass perfectly while measuring nothing**, which is
## the exact failure I wrote down after generalising from the one configuration I had measured.

## The seed Maren's mock was built on, so the picture is comparable to it (`assay-build-screen` §0).
const DEFAULT_SEED := "14247"

## Enough of the loop to have a pack worth making something out of. The session's own budget is far
## longer; a shot only needs the catalogue to have rows.
const DEFAULT_TICKS := 60

## Ticks between handing the frame back, so containers lay out before anything is measured.
const TICKS_PER_FRAME := 10

var _screen: Node = null
var _play: RefCounted = null
var _asked: Array = []
var _out := ""
var _seed := DEFAULT_SEED
var _left := DEFAULT_TICKS
var _started := false
var _shot := false
var _done := false
var _faults: Array = []


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		_finish(false, "usage: -- <out_dir> [seed] [ticks]")
		return
	_out = String(argv[0])
	_seed = String(argv[1]) if argv.size() > 1 else DEFAULT_SEED
	_left = int(argv[2]) if argv.size() > 2 else DEFAULT_TICKS
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_finish(false, "cannot write to %s" % _out)
		return
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND, the reason `button_session.gd` and `window_shot.gd` both give: a `--script`
	# run works inside `SceneTree._initialize`, before the root window is in the tree.
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	_play = AssayButtonPlay.new(_screen, 0)
	print("window %s, viewport %s" % [DisplayServer.window_get_size(), root.size])


func _process(_delta: float) -> bool:
	if _done:
		return true
	if not _started:
		var welcome := AssaySimHost.fresh_welcome_json(_seed, "limpet")
		if welcome == "":
			_finish(false, "could not make a world on seed %s" % _seed)
			return true
		_screen._client.play_offline()
		_screen._client.feed_offline(welcome)
		if not _screen._sim.running():
			_finish(false, "offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
			return true
		_started = true
		return false
	if _left > 0:
		for _i in range(TICKS_PER_FRAME):
			if _left <= 0:
				break
			_left -= 1
			_play.advance()
			var inputs := []
			for command in _asked:
				inputs.append({"Player": {"player": _screen._client.player_id,
						"command": command}})
			_asked.clear()
			var at: int = _screen._sim.tick()
			_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
		return false
	if not _shot:
		_shot = true
		_open_and_settle()
		return false
	_measure()
	_write()
	return _done


## **PRESS THE ROW A PLAYER WOULD PRESS.** Not `_open_build_screen`: the launcher opening nothing is
## one of the two defects this picture is evidence against, and calling the open function directly
## would take the row's one control out of the test.
func _open_and_settle() -> void:
	for row in _screen._make.get_children():
		var button := _find(row, AssayHud.make_launch_text())
		if button != null:
			button.pressed.emit()
			return
	_faults.append("no make row carried a `%s` control at all" % AssayHud.make_launch_text())


## **THE OVERLAP, IN PIXELS, AGAINST THE THREE CONTROLS MAREN'S §1 PROTECTS.**
##
## **A ZERO-SIZED CONTROL IS REPORTED AND NOT SKIPPED HERE**, which is the opposite of what
## `main.gd::_place_build_screen` does with one -- and deliberately. There, a zero size means
## "nothing has laid out" and the constant has to answer. Here, a laid-out window that reports a
## control with no size is itself the finding: it means this tool measured nothing and must not say
## so in green.
func _measure() -> void:
	if not _screen._build_box.visible:
		_faults.append("the screen is not visible after pressing a row's launcher")
		return
	var screen_rect := Rect2(_screen._build_box.global_position, _screen._build_box.size)
	print("SCREEN   %s  (%.0f x %.0f)" % [screen_rect, screen_rect.size.x, screen_rect.size.y])
	var column := AssayHud.VIEW.x - AssayHud.PANEL
	if screen_rect.end.x > column:
		_faults.append("the screen reaches x %.0f and the HUD column starts at %.0f"
				% [screen_rect.end.x, column])
	var watched := {
		"whole world (V)": _screen._view_toggle,
		"show the map key (K)": _screen._map_key_toggle,
		"the status toast": _screen._says_toast,
	}
	for named in watched:
		var node := watched[named] as Control
		var rect := Rect2(node.global_position, node.size)
		var over := screen_rect.intersection(rect)
		print("%-22s %s  visible=%s  overlap=%s" % [named, rect, node.visible, over.size])
		if not node.visible:
			# **AN INVISIBLE CONTROL IS NOT A PASS AND NOT A FAIL.** The toast is drawn only while the
			# client has something to say (ASSA-239), so it is legitimately absent here -- and that
			# means this run did NOT measure the screen against it. Said out loud, because a silent
			# skip is how "measured" comes to mean "assumed".
			print("    NOT MEASURED: this control is hidden in this frame, so nothing was compared")
			continue
		if rect.size.y <= 0.0:
			_faults.append("%s reports no size in a laid-out window, so nothing was measured"
					% named)
		elif over.size.x > 0.0 and over.size.y > 0.0:
			_faults.append("the screen covers %s by %.0f x %.0f px"
					% [named, over.size.x, over.size.y])
	# **AND THE CONSTANT IS COMPARED TO THE MEASUREMENT, which is the whole reason this tool exists.**
	# The band's real top is the highest of the visible controls; `WORLD_CONTROLS_BAND` is what the
	# headless suite believes. A drift is not a failure -- the constant is deliberately generous -- but
	# an unreported drift is how it rots, so the number is printed either way.
	var world := AssayHud.world_rect()
	var top := world.end.y
	for named in watched:
		var node := watched[named] as Control
		if node.visible and node.size.y > 0.0:
			top = minf(top, node.global_position.y)
	print("BAND     measured top %.0f, world bottom %.0f, so the band is %.0f px tall"
			% [top, world.end.y, world.end.y - top])
	print("         WORLD_CONTROLS_BAND says %.0f; %s"
			% [AssayHud.WORLD_CONTROLS_BAND,
			"generous by %.0f px" % (AssayHud.WORLD_CONTROLS_BAND - (world.end.y - top))
			if AssayHud.WORLD_CONTROLS_BAND >= world.end.y - top
			else "SHORT by %.0f px" % ((world.end.y - top) - AssayHud.WORLD_CONTROLS_BAND)])
	if AssayHud.WORLD_CONTROLS_BAND < world.end.y - top:
		_faults.append(("WORLD_CONTROLS_BAND is %.0f and the real band is %.0f px tall, so the "
				+ "headless answer would put the screen over a control")
				% [AssayHud.WORLD_CONTROLS_BAND, world.end.y - top])


func _write() -> void:
	var image := root.get_texture().get_image()
	var path := "%s/build-screen-%s.png" % [_out, _seed]
	if image.save_png(path) != OK:
		_finish(false, "could not write %s" % path)
		return
	print("  %s  %dx%d" % [path, image.get_width(), image.get_height()])
	if _faults.is_empty():
		_finish(true, "")
		return
	_finish(false, "\n".join(PackedStringArray(_faults)))


func _find(node: Node, label: String) -> Button:
	for child in node.find_children("*", "Button", true, false):
		if (child as Button).text == label:
			return child as Button
	return null


func _finish(ok: bool, why: String) -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(_screen) and _screen.has_method("stop_solo_relay"):
		_screen.stop_solo_relay()
	if ok:
		print("BUILD SCREEN SHOT OK · nothing covered")
	else:
		print("FAIL  %s" % why)
	quit(0 if ok else 1)
